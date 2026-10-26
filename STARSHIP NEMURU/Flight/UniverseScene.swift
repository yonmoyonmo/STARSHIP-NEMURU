import RealityKit
import simd

/// Nearby gameplay definitions and a separate, bounded planetary horizon share stable sector seeds.
@MainActor
final class UniverseScene {
    let root = Entity()
    static let maximumNearPlanets = 12
    static let maximumFarPlanets = 12
    static let maximumPlanets = maximumNearPlanets + maximumFarPlanets
    static let maximumClusters = 16
    static let planetFadeStart: Float = 3200
    static let planetFadeEnd: Float = 4000
    private var planets: [SectorID: Entity] = [:]
    private var clusters: [SectorID: Entity] = [:]
    private var selectedPlanets: [PlanetDefinition] = []
    private var horizon: [PlanetDefinition] = []
    private var horizonRevision: UInt64?
    private var appearances: [SectorID: Float] = [:]
    private var pending: [Request] = []
    private var revision: UInt64?
    private var refreshClock: Float = 1
    private(set) var buildFailure: String?
    var renderedCount: Int { planets.count + clusters.count }

    private enum Request {
        case planet(PlanetDefinition)
        case cluster(ClusterDefinition)
        func distance(in universe: Universe) -> Float {
            switch self {
            case .planet(let body): return simd_length(universe.relative(body))
            case .cluster(let group): return simd_length(universe.relative(group))
            }
        }
    }

    func update(_ universe: Universe, dt: Float) {
        refreshClock += dt
        if revision != universe.revision || refreshClock >= 0.5 {
            refreshClock = 0
            revision = universe.revision
            refresh(universe)
        }
        // At most one procedural mesh group is constructed per rendered frame.
        if !pending.isEmpty {
            let request = pending.removeFirst()
            do {
                switch request {
                case .planet(let definition):
                    let node = try PolygonFactory.planet(definition)
                    node.name = definition.name
                    planets[definition.sector] = node
                    appearances[definition.sector] = 0
                    root.addChild(node)
                case .cluster(let definition):
                    let node = try PolygonFactory.cluster(definition)
                    clusters[definition.sector] = node
                    root.addChild(node)
                }
            } catch {
                buildFailure = String(describing: error)
                assertionFailure("Could not construct universe geometry: \(error)")
            }
        }
        for definition in selectedPlanets {
            if let node = planets[definition.sector] {
                let appearance = min(1, (appearances[definition.sector] ?? 0) + max(0, dt) / 1.5)
                appearances[definition.sector] = appearance
                place(node, at: universe.relative(definition), fadeStart: Self.planetFadeStart,
                      fadeEnd: Self.planetFadeEnd, appearance: appearance)
            }
        }
        for definition in universe.clusters {
            if let node = clusters[definition.sector] {
                place(node, at: universe.relative(definition), fadeStart: 900, fadeEnd: 1100)
            }
        }
    }

    private func refresh(_ universe: Universe) {
        if horizonRevision != universe.revision {
            horizonRevision = universe.revision
            horizon.removeAll(keepingCapacity: true)
            let center = universe.position.sector
            // ±7 covers the 4,000-unit horizon even at a sector edge. These definitions
            // never enter gameplay streaming, discovery, collision, or the voyage archive.
            for x: Int64 in -7...7 {
                for y: Int64 in -7...7 {
                    for z: Int64 in -7...7 {
                        let sector = SectorID(x: center.x + x, y: center.y + y, z: center.z + z)
                        guard simd_length(universe.position.relative(sector: sector, offset: .zero)) < 4300 else { continue }
                        if let body = Universe.generate(sector).planet { horizon.append(body) }
                    }
                }
            }
        }
        let near = universe.planets.filter { simd_length(universe.relative($0)) < 1400 }
            .sorted { closer($0, $1, in: universe) }.prefix(Self.maximumNearPlanets)
        let nearIDs = Set(near.map(\.sector))
        // Retain the existing distant selection while approaching it: no reselection every half second.
        var far = selectedPlanets.filter {
            let distance = simd_length(universe.relative($0))
            return !nearIDs.contains($0.sector) && distance >= 1200 && distance < 4050
        }.prefix(Self.maximumFarPlanets).map { $0 }
        let candidates = horizon.filter {
            let distance = simd_length(universe.relative($0))
            return distance >= 1600 && distance < Self.planetFadeEnd
                && !nearIDs.contains($0.sector) && !far.contains($0)
        }.sorted {
            let a = abs(simd_length(universe.relative($0)) - 2800)
            let b = abs(simd_length(universe.relative($1)) - 2800)
            return a == b ? $0.sector < $1.sector : a < b
        }
        for body in candidates where far.count < Self.maximumFarPlanets {
            let direction = simd_normalize(universe.relative(body))
            // Spread the horizon across the sky rather than spending the budget on a single patch.
            guard far.allSatisfy({ simd_dot(direction, simd_normalize(universe.relative($0))) < 0.88 }) else { continue }
            far.append(body)
        }
        selectedPlanets = Array(near) + far
        let nearbyClusters = universe.clusters.filter {
            simd_length(universe.relative($0)) < (clusters[$0.sector] == nil ? 1200 : 1250)
        }.sorted { simd_length(universe.relative($0)) < simd_length(universe.relative($1)) }
            .prefix(Self.maximumClusters)
        let planetIDs = Set(selectedPlanets.map(\.sector))
        let clusterIDs = Set(nearbyClusters.map(\.sector))
        for id in Array(planets.keys) where !planetIDs.contains(id) {
            planets.removeValue(forKey: id)?.removeFromParent()
            appearances.removeValue(forKey: id)
        }
        for id in Array(clusters.keys) where !clusterIDs.contains(id) {
            clusters.removeValue(forKey: id)?.removeFromParent()
        }
        pending = selectedPlanets.filter { planets[$0.sector] == nil }.map { .planet($0) }
            + nearbyClusters.filter { clusters[$0.sector] == nil }.map { .cluster($0) }
        pending.sort { $0.distance(in: universe) < $1.distance(in: universe) }
    }

    private func closer(_ a: PlanetDefinition, _ b: PlanetDefinition, in universe: Universe) -> Bool {
        let first = simd_length(universe.relative(a)), second = simd_length(universe.relative(b))
        return first == second ? a.sector < b.sector : first < second
    }

    private func place(_ entity: Entity, at position: SIMD3<Float>, fadeStart: Float,
                       fadeEnd: Float, appearance: Float = 1) {
        entity.position = position
        let t = min(1, max(0, (simd_length(position) - fadeStart) / (fadeEnd - fadeStart)))
        let visibility = (1 - t * t * (3 - 2 * t)) * appearance
        entity.isEnabled = visibility > 0.001
        entity.scale = SIMD3(repeating: max(0.001, visibility))
    }
}
