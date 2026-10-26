import RealityKit
import simd

extension SceneryGeometry {
    /// Broad, translucent polygon veils. Rings share exact edges and fade outwards.
    static func nebula(seed: UInt64) throws -> Entity {
        let root = Entity()
        root.name = "nebula-veil"
        var random = SeededRandom(seed: seed)
        let colors: [SIMD3<Float>] = [[0.20,0.35,0.36], [0.32,0.23,0.40], [0.39,0.24,0.30]]
        let color = colors[Int(seed % 3)]
        var centers: [SIMD3<Float>] = []
        for _ in 0..<5 { centers.append([random.range(-80,80), random.range(-35,35), random.range(-60,60)]) }
        for layer in 0..<8 {
            var triangles: [[SIMD3<Float>]] = []
            let inner = Float(layer) / 8, outer = Float(layer + 1) / 8
            for (index, center) in centers.enumerated() {
                let orientation = simd_quatf(angle: Float(index) * 0.6 - 1.2, axis: [0,1,0])
                func point(_ segment: Int, _ radius: Float) -> SIMD3<Float> {
                    let angle = Float(segment) / 40 * 2 * .pi
                    let wave = 1 + sin(angle * 3 + Float(index)) * 0.1
                    return center + orientation.act([cos(angle) * radius * 125 * wave,
                                                     sin(angle) * radius * 65 * wave, 0])
                }
                for segment in 0..<40 {
                    let a = point(segment, inner), b = point(segment + 1, inner)
                    let c = point(segment, outer), d = point(segment + 1, outer)
                    if layer == 0 { triangles += [[a,d,c], [c,d,a]] }
                    else { triangles += [[a,b,c], [c,b,d], [c,b,a], [d,b,c]] }
                }
            }
            let alpha = pow(1 - (inner + outer) / 2, 2) * 0.085
            var material = PolygonFactory.material(PolygonFactory.uiColor(color))
            material.blending = .transparent(opacity: .init(floatLiteral: alpha))
            root.addChild(ModelEntity(mesh: try PolygonFactory.mesh(triangles), materials: [material]))
        }
        return root
    }

    /// Sparse pass-through crystals; no collision or interaction is attached.
    static func ice(seed: UInt64) throws -> Entity {
        let root = Entity()
        root.name = "ice-garden"
        var random = SeededRandom(seed: seed)
        let corners: [SIMD3<Float>] = [[0,1.8,0], [0,-1.4,0], [-0.7,0,0], [0,0,0.7], [0.7,0,0], [0,0,-0.7]]
        let faces = [[0,2,3], [0,3,4], [0,4,5], [0,5,2], [1,3,2], [1,4,3], [1,5,4], [1,2,5]]
        let colors: [SIMD3<Float>] = [[0.30,0.47,0.49], [0.45,0.57,0.61], [0.25,0.31,0.44]]
        for index in 0..<12 {
            let crystal = Entity()
            crystal.position = [random.range(-75,75), random.range(-42,42), random.range(-90,90)]
            let size = random.range(0.7,2.1)
            for group in 0..<3 {
                let triangles = faces.enumerated().filter { $0.offset % 3 == group }.map { _, face in
                    face.map { corners[$0] * size }
                }
                var material = PolygonFactory.material(PolygonFactory.uiColor(colors[(group + index) % 3]))
                material.blending = .transparent(opacity: .init(floatLiteral: 0.48))
                crystal.addChild(ModelEntity(mesh: try PolygonFactory.mesh(triangles), materials: [material]))
            }
            root.addChild(crystal)
        }
        return root
    }

    static func ripple(seed: UInt64) throws -> Entity {
        let root = Entity()
        root.name = "distant-ripple"
        for _ in 0..<2 {
            let wave = Entity()
            for band in 0..<5 {
                var triangles: [[SIMD3<Float>]] = []
                let inner = 48 + Float(band) * 0.6
                let outer = inner + 0.6
                func point(_ step: Int, _ radius: Float) -> SIMD3<Float> {
                    let angle = Float(step) / 96 * 2 * .pi
                    return [cos(angle) * radius, sin(angle) * radius * 0.6, 0]
                }
                for step in 0..<96 {
                    let a = point(step, inner), b = point(step + 1, inner)
                    let c = point(step, outer), d = point(step + 1, outer)
                    triangles += [[a,b,c], [c,b,d], [c,b,a], [d,b,c]]
                }
                wave.addChild(ModelEntity(mesh: try PolygonFactory.mesh(triangles),
                    materials: [PolygonFactory.material(PolygonFactory.uiColor([0.29,0.45,0.47]))]))
            }
            root.addChild(wave)
        }
        animateRipple(root, seed: seed, time: 0, updateMaterials: true)
        return root
    }

    static func animateRipple(_ root: Entity, seed: UInt64, time: Double, updateMaterials: Bool) {
        for (index, wave) in root.children.enumerated() {
            let progress = Float((time / 96 + Double(seed % 96) / 96 + Double(index) * 0.5)
                .truncatingRemainder(dividingBy: 1))
            wave.scale = SIMD3(repeating: 0.65 + progress * 1.25)
            wave.orientation = simd_quatf(angle: Float(seed % 40) / 100 - 0.2, axis: [0,0,1])
            guard updateMaterials else { continue }
            let envelope = pow(sin(progress * .pi), 2)
            for (band, child) in wave.children.enumerated() {
                guard let model = child as? ModelEntity else { continue }
                let edge = sin((Float(band) + 0.5) / 5 * .pi)
                var material = PolygonFactory.material(PolygonFactory.uiColor([0.29,0.45,0.47]))
                material.blending = .transparent(opacity: .init(floatLiteral: envelope * edge * 0.18))
                model.model?.materials = [material]
            }
        }
    }
}
