import RealityKit
import simd

/// A bounded rendering cache. Definitions outlive meshes through their deterministic sector seeds.
@MainActor
final class UniverseScene {
    let root = Entity()
    static let maximumPlanets = 32
    static let maximumClusters = 16
    private var planets: [SectorID: Entity] = [:]
    private var clusters: [SectorID: Entity] = [:]
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
        for definition in universe.planets {
            if let node = planets[definition.sector] { place(node, at: universe.relative(definition)) }
        }
        for definition in universe.clusters {
            if let node = clusters[definition.sector] { place(node, at: universe.relative(definition)) }
        }
    }

    private func refresh(_ universe: Universe) {
        let nearbyPlanets = universe.planets.filter {
            simd_length(universe.relative($0)) < (planets[$0.sector] == nil ? 1200 : 1250)
        }.sorted { simd_length(universe.relative($0)) < simd_length(universe.relative($1)) }
            .prefix(Self.maximumPlanets)
        let nearbyClusters = universe.clusters.filter {
            simd_length(universe.relative($0)) < (clusters[$0.sector] == nil ? 1200 : 1250)
        }.sorted { simd_length(universe.relative($0)) < simd_length(universe.relative($1)) }
            .prefix(Self.maximumClusters)
        let planetIDs = Set(nearbyPlanets.map(\.sector))
        let clusterIDs = Set(nearbyClusters.map(\.sector))
        for id in Array(planets.keys) where !planetIDs.contains(id) {
            planets.removeValue(forKey: id)?.removeFromParent()
        }
        for id in Array(clusters.keys) where !clusterIDs.contains(id) {
            clusters.removeValue(forKey: id)?.removeFromParent()
        }
        pending = nearbyPlanets.filter { planets[$0.sector] == nil }.map { .planet($0) }
            + nearbyClusters.filter { clusters[$0.sector] == nil }.map { .cluster($0) }
        pending.sort { $0.distance(in: universe) < $1.distance(in: universe) }
    }

    private func place(_ entity: Entity, at position: SIMD3<Float>) {
        entity.position = position
        let t = min(1, max(0, (simd_length(position) - 900) / 200))
        let visibility = 1 - t * t * (3 - 2 * t)
        entity.isEnabled = visibility > 0.001
        entity.scale = SIMD3(repeating: max(0.001, visibility))
    }
}
