import RealityKit
import simd

/// A restrained horizon glow, separate from terrain and independent of gameplay time.
@MainActor
final class RestingDawn {
    let root = Entity()
    let available: Bool
    private let phase: Float
    private var time: Double = 0
    private var clock: Float = 0

    init(seed: UInt64) throws {
        var random = SeededRandom(seed: seed ^ 0x4441574E)
        available = seed == PlanetDefinition.home.seed || random.value() < 0.32
        phase = Float(seed % 628) / 100
        root.name = "resting-dawn"
        guard available else { return }
        for ring in 0..<10 {
            let inner = Float(ring) / 10, outer = Float(ring + 1) / 10
            var triangles: [[SIMD3<Float>]] = []
            func point(_ step: Int, _ radius: Float) -> SIMD3<Float> {
                let angle = Float(step) / 64 * 2 * .pi
                return [cos(angle) * radius * 165, 1 + sin(angle) * radius * 37, -190]
            }
            for step in 0..<64 {
                let a = point(step, inner), b = point(step + 1, inner)
                let c = point(step, outer), d = point(step + 1, outer)
                if ring == 0 { triangles += [[a,d,c], [c,d,a]] }
                else { triangles += [[a,b,c], [c,b,d], [c,b,a], [d,b,c]] }
            }
            let model = ModelEntity(mesh: try PolygonFactory.mesh(triangles),
                materials: [PolygonFactory.material(PolygonFactory.uiColor([0.45,0.30,0.27]))])
            root.addChild(model)
        }
        update(dt: 0, reduceMotion: false, force: true)
    }

    func update(dt: Float, reduceMotion: Bool, force: Bool = false) {
        if !reduceMotion { time += Double(max(0, dt)) }
        clock += dt
        guard force || (!reduceMotion && clock >= 0.5) else { return }
        clock = 0
        let breath = 0.75 + sin(Float((time * 0.025).truncatingRemainder(dividingBy: 2 * .pi)) + phase) * 0.25
        for (index, child) in root.children.enumerated() {
            guard let model = child as? ModelEntity else { continue }
            let falloff = pow(1 - (Float(index) + 0.5) / 10, 2)
            var material = PolygonFactory.material(PolygonFactory.uiColor([0.45,0.30,0.27]))
            material.blending = .transparent(opacity: .init(floatLiteral: falloff * breath * 0.22))
            model.model?.materials = [material]
        }
    }
}
