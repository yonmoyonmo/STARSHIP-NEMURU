import RealityKit
import simd

@MainActor
final class ConstellationScene {
    let root = Entity()
    let navigationRoot = Entity()
    private var brackets: [Entity] = []
    private var current: SectorID?
    private var points: [Entity] = []
    private var edges: [Entity] = []
    private var visibility: Float = 0

    init() {
        let box = MeshResource.generateBox(size: 1)
        for _ in 0..<8 {
            let marker = ModelEntity(mesh: box, materials: [PolygonFactory.material(PolygonFactory.uiColor([0.23,0.38,0.32]))])
            brackets.append(marker); navigationRoot.addChild(marker)
        }
        navigationRoot.isEnabled = false
        for _ in 0..<7 {
            let star = ModelEntity(mesh: box, materials: [PolygonFactory.material(PolygonFactory.uiColor([0.60,0.76,0.68]))])
            points.append(star); root.addChild(star)
        }
        for _ in 0..<6 {
            let edge = ModelEntity(mesh: box, materials: [PolygonFactory.material(PolygonFactory.uiColor([0.15,0.26,0.23]))])
            edges.append(edge); root.addChild(edge)
        }
    }

    func guide(to body: PlanetDefinition?, position: UniversePosition) {
        guard let body else { navigationRoot.isEnabled = false; return }
        let center = position.relative(sector: body.sector, offset: body.offset)
        let distance = simd_length(center)
        guard distance > body.radius && distance < 4200 else { navigationRoot.isEnabled = false; return }
        navigationRoot.isEnabled = true
        navigationRoot.position = center
        let direction = simd_normalize(center)
        let reference: SIMD3<Float> = abs(direction.y) > 0.95 ? [1,0,0] : [0,1,0]
        let right = simd_normalize(simd_cross(direction, reference))
        let up = simd_normalize(simd_cross(right, direction))
        let radius = body.collisionRadius * 1.2
        for corner in 0..<4 {
            let x: Float = corner % 2 == 0 ? -1 : 1
            let y: Float = corner / 2 == 0 ? -1 : 1
            let anchor = right * x * radius + up * y * radius
            for axis in 0..<2 {
                let line = brackets[corner * 2 + axis]
                let vector = axis == 0 ? right * -x : up * -y
                let length = radius * 0.24
                line.position = anchor + vector * length / 2
                line.orientation = simd_quatf(from: SIMD3<Float>(0,1,0), to: vector)
                line.scale = [0.16, length, 0.16]
            }
        }
    }

    func update(_ encounter: QuietConstellation?, position: UniversePosition, forward: SIMD3<Float>, dt: Float) {
        visibility += ((encounter == nil ? 0 : 1) - visibility) * (1 - exp(-max(0, dt) * 2))
        root.isEnabled = visibility > 0.001
        guard let encounter else { root.scale = SIMD3(repeating: max(0.001, visibility)); return }
        current = encounter.world.sector
        let center = encounter.relative(to: position)
        root.position = center
        root.scale = SIMD3(repeating: max(0.001, visibility))
        let direction = simd_normalize(center)
        let reference: SIMD3<Float> = abs(direction.y) > 0.95 ? [1,0,0] : [0,1,0]
        let right = simd_normalize(simd_cross(direction, reference))
        let up = simd_normalize(simd_cross(right, direction))
        let alignment = encounter.alignment(position: position, forward: forward)
        var random = SeededRandom(seed: encounter.world.seed ^ 0x4C454146)
        for (index, star) in points.enumerated() {
            let leaf = QuietConstellation.leaf[index] * 0.8
            let scatter = SIMD2(random.range(-11,11), random.range(-9,9)) * (1 - alignment)
            star.position = right * (leaf.x + scatter.x) + up * (leaf.y + scatter.y)
            star.scale = SIMD3(repeating: 0.45 + alignment * 0.15)
        }
        for (index, edge) in edges.enumerated() {
            let a = points[index].position, b = points[(index + 1) % 6].position
            edge.position = (a + b) / 2
            edge.orientation = simd_quatf(from: SIMD3<Float>(0,1,0), to: simd_normalize(b - a))
            let strength = max(0, (alignment - 0.35) / 0.65)
            edge.scale = [0.055 * strength, simd_length(b - a), 0.055 * strength]
        }
    }
}
