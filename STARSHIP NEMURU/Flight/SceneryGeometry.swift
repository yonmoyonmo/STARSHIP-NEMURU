import RealityKit
import simd

@MainActor
enum SceneryGeometry {
    static func make(_ definition: SceneryDefinition) throws -> Entity {
        switch definition.kind {
        case .dust: return try dust(seed: definition.seed, home: definition.sector == .zero)
        case .comet: return try comet(seed: definition.seed)
        case .nebula: return try nebula(seed: definition.seed)
        case .ice: return try ice(seed: definition.seed)
        case .ripple: return try ripple(seed: definition.seed)
        }
    }

    static func dust(seed: UInt64, home: Bool) throws -> Entity {
        let root = Entity()
        root.name = "dust-river"
        var random = SeededRandom(seed: seed)
        var groups = Array(repeating: [[SIMD3<Float>]](), count: 3)
        // Small tetrahedra batched by shade, rather than hundreds of animated entities.
        let corners: [SIMD3<Float>] = [[-1,-0.5,0], [1,-0.5,0], [0,1,0], [0,0,1]]
        let faces = [[0,1,2], [0,3,1], [1,3,2], [2,3,0]]
        for index in 0..<540 {
            let along = random.range(-350, 350)
            let envelope = max(0, 1 - abs(along) / 360)
            let center = SIMD3<Float>(sin(along * 0.012) * 13 + random.range(-28, 28),
                                      cos(along * 0.009) * 5 + random.range(-14, 14), along)
            let size = random.range(0.08, 0.25) * envelope
            for face in faces { groups[index % 3].append(face.map { center + corners[$0] * size }) }
        }
        let shades: [SIMD3<Float>] = [[0.23,0.36,0.35], [0.32,0.39,0.43], [0.38,0.34,0.27]]
        for index in 0..<3 {
            root.addChild(ModelEntity(mesh: try PolygonFactory.mesh(groups[index]),
                materials: [PolygonFactory.material(PolygonFactory.uiColor(shades[index]))]))
        }
        if !home { root.orientation = simd_quatf(angle: random.range(-.pi, .pi), axis: simd_normalize(SIMD3<Float>(0.3, 1, 0.2))) }
        return root
    }

    static func comet(seed: UInt64) throws -> Entity {
        let root = Entity()
        root.name = "lonely-comet"
        let core = ModelEntity(mesh: .generateSphere(radius: 0.65),
            materials: [PolygonFactory.material(PolygonFactory.uiColor([0.65,0.72,0.68]))])
        root.addChild(core)
        // Two intersecting tapered sheets retain a tail from every viewing direction.
        for step in 0..<8 {
            let a = Float(step) / 8, b = Float(step + 1) / 8
            func center(_ t: Float) -> SIMD3<Float> { [t * 85, t * t * 12, t * 16] }
            var triangles: [[SIMD3<Float>]] = []
            for axis in [SIMD3<Float>(0,1,0), SIMD3<Float>(0,0,1)] {
                let u = axis * (0.35 + a * 3), v = axis * (0.35 + b * 3)
                let first = [center(a)-u, center(b)-v, center(a)+u]
                let second = [center(a)+u, center(b)-v, center(b)+v]
                triangles += [first, second, first.reversed().map { $0 }, second.reversed().map { $0 }]
            }
            let strength = (1 - b) * (1 - b) * 0.65
            var material = PolygonFactory.material(PolygonFactory.uiColor([0.45,0.65,0.61]))
            material.blending = .transparent(opacity: .init(floatLiteral: strength))
            root.addChild(ModelEntity(mesh: try PolygonFactory.mesh(triangles), materials: [material]))
        }
        root.orientation = simd_quatf(angle: Float(seed % 100) / 100 - 0.5, axis: [0,0,1])
        return root
    }
}
