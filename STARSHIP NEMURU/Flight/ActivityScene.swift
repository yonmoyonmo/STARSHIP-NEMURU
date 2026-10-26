import RealityKit
import simd

/// Fixed geometry with slow transforms. Only one curiosity is shown in the voyage at a time.
@MainActor
final class ActivityScene {
    let root = Entity()
    private let lights: [ModelEntity]
    private var time: Double = 0
    private var worldID: SectorID?

    init() throws {
        let color = PolygonFactory.material(PolygonFactory.uiColor([0.43,0.64,0.59]))
        let sphere = ModelEntity(mesh: .generateSphere(radius: 0.65), materials: [color])
        let triangle = ModelEntity(mesh: try PolygonFactory.mesh([
            [[0,0.9,0],[-0.8,-0.6,0],[0.8,-0.6,0]], [[0,0.9,0],[0.8,-0.6,0],[-0.8,-0.6,0]]]), materials: [color])
        let diamond = ModelEntity(mesh: try PolygonFactory.mesh([
            [[0,1,0],[-0.7,0,0],[0,-1,0]], [[0,1,0],[0,-1,0],[0.7,0,0]],
            [[0,-1,0],[-0.7,0,0],[0,1,0]], [[0.7,0,0],[0,-1,0],[0,1,0]]]), materials: [color])
        lights = [sphere, triangle, diamond]
        for light in lights { root.addChild(light) }
        root.isEnabled = false
    }
    func update(_ activity: QuietActivity?, position: UniversePosition, dt: Float, reduceMotion: Bool) {
        guard let activity else { root.isEnabled = false; return }
        root.isEnabled = true
        if worldID != activity.world.sector { worldID = activity.world.sector; time = 0 }
        if !reduceMotion { time += Double(max(0, dt)) }
        let center = activity.relative(to: position)
        root.position = center
        let direction = simd_normalize(center)
        let reference: SIMD3<Float> = abs(direction.y) > 0.95 ? [1,0,0] : [0,1,0]
        let right = simd_normalize(simd_cross(direction, reference))
        let up = simd_normalize(simd_cross(right, direction))
        root.orientation = simd_quatf(simd_float3x3(columns: (right, up, -direction)))
        for (index, light) in lights.enumerated() {
            if activity.kind == .signal {
                light.isEnabled = index == 0
                light.position = .zero
                light.scale = SIMD3(repeating: 1.1)
            } else {
                light.isEnabled = true
                light.position = [Float(index - 1) * 5, 0, 0]
                // No on/off flashing: a small, slow emphasis is redundant with the static sequence panel.
                let step = Int(time / 3) % activity.unit.count
                let phase = Float(time.truncatingRemainder(dividingBy: 3) / 3)
                let emphasis: Float = activity.unit[step] == index ? 0.12 * pow(sin(phase * .pi), 2) : 0
                light.scale = SIMD3(repeating: 0.9 + emphasis)
            }
        }
    }
}
