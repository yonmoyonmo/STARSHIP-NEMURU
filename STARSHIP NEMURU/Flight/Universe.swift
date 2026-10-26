import Foundation
import simd

nonisolated struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func value() -> Float {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Float(state >> 40) / Float(1 << 24)
    }
    mutating func range(_ a: Float, _ b: Float) -> Float { a + value() * (b - a) }
}

nonisolated struct SectorID: Hashable, Comparable, Codable, Sendable {
    var x: Int64
    var y: Int64
    var z: Int64
    static let zero = SectorID(x: 0, y: 0, z: 0)
    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.x != rhs.x { return lhs.x < rhs.x }
        if lhs.y != rhs.y { return lhs.y < rhs.y }
        return lhs.z < rhs.z
    }
}

/// Large integral sectors + a bounded Double offset; large coordinates never reach RealityKit.
nonisolated struct UniversePosition: Equatable, Codable, Sendable {
    static let sectorSize: Double = 640
    var sector: SectorID = .zero
    private(set) var offset = SIMD3<Double>.zero

    mutating func advance(_ displacement: SIMD3<Float>) {
        offset += SIMD3(Double(displacement.x), Double(displacement.y), Double(displacement.z))
        for axis in 0..<3 {
            let carry = Int64(floor((offset[axis] + Self.sectorSize / 2) / Self.sectorSize))
            offset[axis] -= Double(carry) * Self.sectorSize
            switch axis {
            case 0: sector.x += carry
            case 1: sector.y += carry
            default: sector.z += carry
            }
        }
    }

    func relative(sector other: SectorID, offset local: SIMD3<Float>) -> SIMD3<Float> {
        let delta = SIMD3(Double(other.x - sector.x), Double(other.y - sector.y), Double(other.z - sector.z))
        let position = delta * Self.sectorSize + SIMD3(Double(local.x), Double(local.y), Double(local.z)) - offset
        return SIMD3(Float(position.x), Float(position.y), Float(position.z))
    }
}

nonisolated struct PlanetColors: Equatable {
    let low: SIMD3<Float>
    let high: SIMD3<Float>
}

nonisolated enum PlanetPalette: Int, CaseIterable {
    case tide, dusk, clay, frost, ochre, moss, rose, indigo, pearl, ember
    var low: SIMD3<Float> {
        switch self {
        case .tide: return [0.12, 0.21, 0.24]
        case .dusk: return [0.20, 0.16, 0.26]
        case .clay: return [0.26, 0.19, 0.16]
        case .frost: return [0.19, 0.25, 0.29]
        case .ochre: return [0.30, 0.25, 0.12]
        case .moss: return [0.13, 0.25, 0.17]
        case .rose: return [0.30, 0.17, 0.22]
        case .indigo: return [0.14, 0.17, 0.31]
        case .pearl: return [0.26, 0.28, 0.28]
        case .ember: return [0.32, 0.13, 0.14]
        }
    }
    var high: SIMD3<Float> {
        switch self {
        case .tide: return [0.31, 0.46, 0.47]
        case .dusk: return [0.39, 0.32, 0.45]
        case .clay: return [0.47, 0.36, 0.26]
        case .frost: return [0.43, 0.52, 0.56]
        case .ochre: return [0.64, 0.55, 0.29]
        case .moss: return [0.35, 0.53, 0.32]
        case .rose: return [0.61, 0.37, 0.44]
        case .indigo: return [0.34, 0.39, 0.62]
        case .pearl: return [0.58, 0.62, 0.56]
        case .ember: return [0.60, 0.28, 0.30]
        }
    }

    func colors(seed: UInt64) -> PlanetColors {
        // A separate stream keeps cosmetic variation from changing terrain or celestial placement.
        var random = SeededRandom(seed: seed ^ 0x434F4C4F5253)
        let tint = SIMD3(random.range(0.88, 1.12), random.range(0.88, 1.12), random.range(0.88, 1.12))
        let brightness = random.range(0.92, 1.08)
        return PlanetColors(low: simd_clamp(low * tint * brightness, .zero, SIMD3(repeating: 0.72)),
                            high: simd_clamp(high * tint * brightness, .zero, SIMD3(repeating: 0.72)))
    }
}

nonisolated struct PlanetDefinition: Equatable {
    let sector: SectorID
    let offset: SIMD3<Float>
    let seed: UInt64
    let radius: Float
    let roughness: Float
    let palette: PlanetPalette
    let name: String
    var colors: PlanetColors { palette.colors(seed: seed) }
    var position: UniversePosition {
        var position = UniversePosition(sector: sector)
        position.advance(offset)
        return position
    }
    var collisionRadius: Float { radius * (1 + roughness) }
    static let home = PlanetDefinition(sector: .zero, offset: [0, 8, -240], seed: 18,
                                      radius: 36, roughness: 0, palette: .tide, name: "C–18")
}

nonisolated struct ClusterDefinition: Equatable {
    let sector: SectorID
    let offset: SIMD3<Float>
    let seed: UInt64
}

nonisolated struct SectorContents: Equatable {
    let planet: PlanetDefinition?
    let cluster: ClusterDefinition?
}

@MainActor
final class Universe {
    static let radius: Int64 = 2
    static let maximumSectorCount = 125
    private(set) var position = UniversePosition()
    private(set) var sectors: [SectorID: SectorContents] = [:]
    private(set) var planets: [PlanetDefinition] = []
    private(set) var clusters: [ClusterDefinition] = []
    private(set) var revision: UInt64 = 0
    private var loadedCenter: SectorID?

    init(position: UniversePosition? = nil) {
        self.position = position ?? UniversePosition()
        stream()
    }

    /// SplitMix64 mixing is stable across launches; Swift's randomized Hasher is never used for generation.
    nonisolated static func seed(for id: SectorID) -> UInt64 {
        func mix(_ input: UInt64) -> UInt64 {
            var value = input &+ 0x9E3779B97F4A7C15
            value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
            value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
            return value ^ (value >> 31)
        }
        return mix(UInt64(bitPattern: id.x)) ^ mix(UInt64(bitPattern: id.y) &+ 0x4E454D555255)
            ^ mix(UInt64(bitPattern: id.z) &+ 0x5354415253)
    }

    nonisolated static func generate(_ id: SectorID) -> SectorContents {
        if id == .zero {
            return SectorContents(planet: .home,
                cluster: ClusterDefinition(sector: id, offset: [150, 80, -410], seed: 7718))
        }
        let seed = seed(for: id)
        var random = SeededRandom(seed: seed)
        var planet: PlanetDefinition?
        if random.value() < 0.56 {
            let offset = SIMD3(random.range(-130, 130), random.range(-130, 130), random.range(-130, 130))
            let radius = random.range(24, 52)
            let palette = PlanetPalette(rawValue: Int(random.value() * Float(PlanetPalette.allCases.count))) ?? .tide
            let prefixes = ["C", "M", "L", "N", "S", "V"]
            let name = "\(prefixes[Int(seed % 6)])–\(100 + (seed >> 8) % 900)"
            planet = PlanetDefinition(sector: id, offset: offset, seed: seed, radius: radius,
                roughness: random.range(0.015, 0.075), palette: palette, name: name)
        }
        var cluster: ClusterDefinition?
        if random.value() < 0.22 {
            cluster = ClusterDefinition(sector: id,
                offset: [random.range(-220, 220), random.range(-220, 220), random.range(-220, 220)],
                seed: seed ^ 0x434C5553544552)
        }
        return SectorContents(planet: planet, cluster: cluster)
    }

    func relative(_ planet: PlanetDefinition) -> SIMD3<Float> {
        position.relative(sector: planet.sector, offset: planet.offset)
    }
    func relative(_ cluster: ClusterDefinition) -> SIMD3<Float> {
        position.relative(sector: cluster.sector, offset: cluster.offset)
    }

    /// Applies a swept segment check to every nearby body, not only the selected landing target.
    func safeDisplacement(_ requested: SIMD3<Float>) -> SIMD3<Float> {
        var movement = requested
        for planet in planets {
            let center = relative(planet)
            let clearance = planet.collisionRadius + 19.02
            let centerSquared = simd_length_squared(center)
            if centerSquared < clearance * clearance {
                let direction = centerSquared > 0.0001 ? simd_normalize(center) : SIMD3<Float>(0, 0, -1)
                movement = center - direction * clearance
                continue
            }
            let a = simd_length_squared(movement)
            guard a > 0.000001 else { continue }
            let projection = simd_dot(center, movement)
            let discriminant = projection * projection - a * (centerSquared - clearance * clearance)
            if projection > 0, discriminant >= 0 {
                let entry = (projection - sqrt(discriminant)) / a
                if entry >= 0 && entry < 1 {
                    movement *= max(0, entry - 0.001 / sqrt(a))
                }
            }
        }
        return movement
    }

    func advance(_ displacement: SIMD3<Float>) {
        position.advance(displacement)
        stream()
    }

    private func stream() {
        let center = position.sector
        guard center != loadedCenter else { return }
        var needed = Set<SectorID>()
        for x in -Self.radius...Self.radius {
            for y in -Self.radius...Self.radius {
                for z in -Self.radius...Self.radius {
                    let id = SectorID(x: center.x + x, y: center.y + y, z: center.z + z)
                    needed.insert(id)
                    if sectors[id] == nil { sectors[id] = Self.generate(id) }
                }
            }
        }
        sectors = sectors.filter { needed.contains($0.key) }
        let ordered = sectors.keys.sorted()
        planets = ordered.compactMap { sectors[$0]?.planet }
        clusters = ordered.compactMap { sectors[$0]?.cluster }
        loadedCenter = center
        revision &+= 1
    }
}
