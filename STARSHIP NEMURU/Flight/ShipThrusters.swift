import RealityKit
import UIKit

@MainActor
final class ShipThrusters {
    private var engines: [ModelEntity] = []
    private var previous: Float = -1

    func attach(to ship: Entity) {
        engines = ["thruster.left", "thruster.right"].compactMap { ship.findEntity(named: $0) as? ModelEntity }
        previous = -1
        apply(0)
    }

    func apply(_ brightness: Float) {
        let level = min(1, max(0, brightness))
        guard abs(level - previous) > 0.005 || (level == 0 && previous != 0) else { return }
        previous = level
        // Unlit emission-like color remains readable in both dark space and the resting landscape.
        let material = UnlitMaterial(color: UIColor(red: CGFloat(0.012 + 0.47 * level),
            green: CGFloat(0.022 + 0.92 * level), blue: CGFloat(0.025 + 0.85 * level), alpha: 1))
        for engine in engines {
            guard var model = engine.model else { continue }
            model.materials = [material]
            engine.model = model
        }
    }
}
