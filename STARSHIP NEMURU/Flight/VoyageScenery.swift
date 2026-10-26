import RealityKit
import simd

/// Cosmetic streams never consume the world's planet/cluster random sequence.
nonisolated struct SceneryDefinition: Equatable {
    enum Kind: CaseIterable {
        case dust, comet, nebula, ice, ripple
        var salt: UInt64 {
            switch self {
            case .dust: return 0x4455535452495645
            case .comet: return 0x434F4D455453
            case .nebula: return 0x4E4542554C41
            case .ice: return 0x4943454741524445
            case .ripple: return 0x524950504C45
            }
        }
        var probability: Float {
            switch self {
            case .dust: return 0.32
            case .comet: return 0.12
            case .nebula: return 0.15
            case .ice: return 0.18
            case .ripple: return 0.055
            }
        }
        var limit: Int {
            switch self {
            case .dust: return 6
            case .comet: return 3
            case .nebula, .ice: return 2
            case .ripple: return 1
            }
        }
        var homeOffset: SIMD3<Float> {
            switch self {
            case .dust: return [0, 0, -130]
            case .comet: return [55, 80, -340]
            case .nebula: return [-160, 80, -470]
            case .ice: return [-65, -8, -160]
            case .ripple: return [210, 110, -650]
            }
        }
    }
    let sector: SectorID
    let seed: UInt64
    let kind: Kind
    let offset: SIMD3<Float>

    static func generate(_ sector: SectorID, kind: Kind) -> Self? {
        let seed = Universe.seed(for: sector) ^ kind.salt
        var random = SeededRandom(seed: seed)
        guard random.value() < kind.probability || sector == .zero else { return nil }
        let offset: SIMD3<Float> = sector == .zero
            ? kind.homeOffset
            : [random.range(-220, 220), random.range(-180, 180), random.range(-220, 220)]
        return Self(sector: sector, seed: seed, kind: kind, offset: offset)
    }
}

/// Independent, bounded cosmetic cache; nothing here affects collision, journal or saves.
@MainActor
final class VoyageScenery {
    let root = Entity()
    static let maximumDust = 6
    static let maximumComets = 3
    static let maximumObjects = SceneryDefinition.Kind.allCases.reduce(0) { $0 + $1.limit }
    private struct Entry { let definition: SceneryDefinition; let entity: Entity }
    private var entries: [Entry] = []
    private var pending: [SceneryDefinition] = []
    private var revision: UInt64?
    private var refreshClock: Float = 1
    private var time: Double = 0
    private var materialClock: Float = 0
    private(set) var buildFailure: String?
    var renderedCount: Int { entries.count }

    func update(_ universe: Universe, dt: Float, reduceMotion: Bool, cameraPosition: SIMD3<Float> = .zero) {
        if !reduceMotion { time += Double(max(0, dt)) }
        materialClock += dt
        let updateMaterials = materialClock >= 0.1
        if updateMaterials { materialClock = 0 }
        refreshClock += dt
        if revision != universe.revision || refreshClock >= 0.5 {
            revision = universe.revision
            refreshClock = 0
            var desired: [SceneryDefinition] = []
            for kind in SceneryDefinition.Kind.allCases {
                let candidates = universe.sectors.keys.compactMap { SceneryDefinition.generate($0, kind: kind) }
                    .filter { simd_length(universe.position.relative(sector: $0.sector, offset: $0.offset)) < 1050 }
                    .sorted {
                        let a = simd_length(universe.position.relative(sector: $0.sector, offset: $0.offset))
                        let b = simd_length(universe.position.relative(sector: $1.sector, offset: $1.offset))
                        return a == b ? $0.sector < $1.sector : a < b
                    }
                desired += candidates.prefix(kind.limit)
            }
            entries.removeAll { entry in
                guard !desired.contains(entry.definition) else { return false }
                entry.entity.removeFromParent()
                return true
            }
            pending = desired.filter { definition in !entries.contains { $0.definition == definition } }
        }
        if !pending.isEmpty {
            let definition = pending.removeFirst()
            do {
                let node = try SceneryGeometry.make(definition)
                entries.append(Entry(definition: definition, entity: node))
                root.addChild(node)
            } catch { buildFailure = String(describing: error); assertionFailure("Scenery mesh: \(error)") }
        }
        for entry in entries {
            var position = universe.position.relative(sector: entry.definition.sector, offset: entry.definition.offset)
            if entry.definition.kind == .comet {
                let phase = Float(entry.definition.seed % 628) / 100
                let angle = Float((time * 0.006).truncatingRemainder(dividingBy: 2 * .pi)) + phase
                position += [sin(angle) * 55, cos(angle) * 18, 0]
            }
            entry.entity.position = position
            let t = min(1, max(0, (simd_length(position) - 760) / 260))
            var visibility = 1 - t * t * (3 - 2 * t)
            if entry.definition.kind == .ripple {
                let near = min(1, max(0, (simd_distance(position, cameraPosition) - 180) / 140))
                visibility *= near * near * (3 - 2 * near)
            }
            entry.entity.isEnabled = visibility > 0.001 && !(reduceMotion && entry.definition.kind == .dust)
            entry.entity.scale = SIMD3(repeating: max(0.001, visibility))
            if entry.definition.kind == .ice {
                let phase = Float(entry.definition.seed % 628) / 100
                for (index, crystal) in entry.entity.children.enumerated() {
                    let angle = Float((time * (0.018 + Double(index % 3) * 0.004)).truncatingRemainder(dividingBy: 2 * .pi))
                    crystal.orientation = simd_quatf(angle: angle + phase + Float(index), axis: simd_normalize(SIMD3<Float>(0.4, 1, 0.2)))
                    let distance = simd_distance(position + crystal.position * visibility, cameraPosition)
                    let near = min(1, max(0, (distance - 12) / 20))
                    crystal.scale = SIMD3(repeating: near * near * (3 - 2 * near))
                }
            }
            if entry.definition.kind == .ripple {
                SceneryGeometry.animateRipple(entry.entity, seed: entry.definition.seed, time: time,
                                               updateMaterials: updateMaterials)
            }
        }
    }
}
