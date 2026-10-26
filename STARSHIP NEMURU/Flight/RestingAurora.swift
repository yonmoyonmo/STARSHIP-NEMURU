import RealityKit
import simd

/// Continuous seeded curtains, built once per landing; only whole-curtain transforms animate.
@MainActor
final class RestingAurora {
    let root = Entity()
    private var curtains: [Entity] = []
    private var time: Float = 0
    private let phase: Float
    let available: Bool

    init(seed: UInt64) throws {
        phase = Float(seed % 628) / 100
        var random = SeededRandom(seed: seed ^ 0x4155524F5241)
        available = seed == PlanetDefinition.home.seed || random.value() < 0.42
        root.name = "resting-aurora"
        guard available else { return }
        let violet = random.value() < 0.4
        for ribbon in 0..<2 {
            let curtain = Entity()
            let shift = phase + Float(ribbon) * 1.7
            // Adjacent sections share exact edge positions, so motion cannot open rectangular gaps.
            func point(_ section: Int, _ level: Int) -> SIMD3<Float> {
                let x = Float(section) * 9 - 144
                let bottom = 22 + sin(x * 0.026 + shift) * 6
                let height = 17 + sin(x * 0.017 + shift) * 5
                return [x, bottom + Float(level) / 10 * height,
                        -130 - cos(x * 0.014 + shift) * 15 - Float(ribbon) * 18]
            }
            for layer in 0..<10 {
                var faces: [[SIMD3<Float>]] = []
                for section in 0..<32 {
                    let a = point(section, layer), b = point(section + 1, layer)
                    let c = point(section, layer + 1), d = point(section + 1, layer + 1)
                    faces += [[a,b,c], [c,b,d], [c,b,a], [d,b,c]]
                }
                let tint: SIMD3<Float> = violet ? [0.32,0.23,0.44] : [0.16,0.39,0.30]
                let envelope = pow(sin((Float(layer) + 0.5) / 10 * .pi), 2)
                var material = PolygonFactory.material(PolygonFactory.uiColor(tint))
                material.blending = .transparent(opacity: .init(floatLiteral: envelope * 0.38))
                curtain.addChild(ModelEntity(mesh: try PolygonFactory.mesh(faces), materials: [material]))
            }
            curtains.append(curtain)
            root.addChild(curtain)
        }
        update(dt: 0, reduceMotion: false)
    }

    func update(dt: Float, reduceMotion: Bool) {
        if !reduceMotion { time = (time + max(0, dt)).truncatingRemainder(dividingBy: 2 * .pi / 0.12) }
        for (index, curtain) in curtains.enumerated() {
            let wave = Float(index) * 1.7 + phase + time * 0.12
            curtain.scale.y = 0.94 + sin(wave) * 0.06
            curtain.position.y = sin(wave) * 1.5
            curtain.orientation = simd_quatf(angle: sin(wave) * 0.018, axis: [0,1,0])
        }
    }
}
