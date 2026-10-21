import SwiftUI
import RealityKit
import UIKit
import simd

struct SpaceView: UIViewRepresentable {
    @ObservedObject var session: FlightSession

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(UIColor(red: 0.012, green: 0.022, blue: 0.037, alpha: 1))
        view.renderOptions = [.disableMotionBlur, .disableDepthOfField, .disableCameraGrain, .disableGroundingShadows]
        context.coordinator.install(in: view)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) { context.coordinator.setActive(session.active) }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator: NSObject {
        let session: FlightSession
        private let anchor = AnchorEntity(world: .zero)
        private let camera = PerspectiveCamera()
        private let space = Entity()
        private let ground = Entity()
        private let shipPivot = Entity()
        private var ship = Entity()
        private let scenery = UniverseScene()
        private let brakingHaptics = BrakingHaptics()
        private var groundPlanet: PlanetDefinition?
        private struct Star {
            let entity: Entity
            let halfExtent: Float
            let size: Float
            let foreground: Bool
        }
        private var stars: [Star] = []
        private var displayLink: CADisplayLink?
        private var previousTime: CFTimeInterval = 0
        private var elapsed: Float = 0
        private var showingGround = false
        private var ready = false
        private var wasActive = true
        private var preferredFPS: Float = 60

        init(session: FlightSession) { self.session = session }

        func install(in view: ARView) {
            view.scene.addAnchor(anchor)
            anchor.addChild(space)
            anchor.addChild(ground)
            anchor.addChild(camera)
            camera.camera.fieldOfViewInDegrees = 58
            camera.camera.near = 0.1
            camera.camera.far = 2000
            camera.position = [0, 5.5, 22]
            camera.orientation = simd_quatf(angle: -0.14, axis: [1, 0, 0])
            do {
                ship = try PolygonFactory.ship()
                shipPivot.addChild(ship)
                anchor.addChild(shipPivot)
                space.addChild(scenery.root)
                try prepareGround()
                createStars()
                scenery.update(session.universe, dt: 0)
                applySceneMode()
                ready = true
            } catch {
                // Mesh construction is deterministic; surface errors in development instead of silently hiding them.
                assertionFailure("Could not build procedural scene: \(error)")
            }
            let link = CADisplayLink(target: self, selector: #selector(frame(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        private func prepareGround() throws {
            let definition = session.targetPlanet
            let terrain = try PolygonFactory.terrain(definition)
            let moon = try PolygonFactory.planet(definition)
            moon.scale = SIMD3(repeating: 22 / definition.radius)
            moon.position = [-65, 45, -170]
            for child in Array(ground.children) { child.removeFromParent() }
            ground.addChild(terrain)
            ground.addChild(moon)
            groundPlanet = definition
        }

        private func createStars() {
            var random = SeededRandom(seed: 0x4E454D555255)
            let mesh = MeshResource.generateBox(size: 1)
            let colors: [UIColor] = [UIColor(red: 0.42, green: 0.53, blue: 0.57, alpha: 1),
                                     UIColor(red: 0.65, green: 0.67, blue: 0.58, alpha: 1),
                                     UIColor(red: 0.28, green: 0.38, blue: 0.46, alpha: 1)]
            // A sparse near layer supplies parallax while distant stars retain the calm background.
            for i in 0..<1000 {
                let foreground = i >= 700
                let extent: Float = foreground ? 90 : 420
                let star = ModelEntity(mesh: mesh, materials: [PolygonFactory.material(colors[i % colors.count])])
                star.position = [random.range(-extent, extent), random.range(-extent, extent), random.range(-extent, extent)]
                let size = foreground ? random.range(0.045, 0.12) : random.range(0.3, 0.85)
                star.scale = SIMD3(repeating: size)
                anchor.addChild(star)
                stars.append(Star(entity: star, halfExtent: extent, size: size, foreground: foreground))
            }
        }

        @objc private func frame(_ link: CADisplayLink) {
            guard previousTime > 0 else { previousTime = link.timestamp; return }
            let dt = Float(min(0.1, max(0, link.timestamp - previousTime)))
            previousTime = link.timestamp
            guard session.active, ready else { return }
            let process = ProcessInfo.processInfo
            let fps: Float = process.thermalState == .serious || process.thermalState == .critical ? 20
                : session.groundVisible ? 15 : (session.isIdle || process.isLowPowerModeEnabled ? 30 : 60)
            if preferredFPS != fps {
                preferredFPS = fps
                link.preferredFrameRateRange = CAFrameRateRange(minimum: fps, maximum: fps, preferred: fps)
            }
            elapsed += dt
            let movement = session.update(dt)
            let canBrake = session.phase == .flying && !session.settingsPresented && !session.logPresented
            if canBrake {
                brakingHaptics.update(holding: session.touching, speed: session.velocity, elapsed: dt)
            } else {
                brakingHaptics.stop()
            }
            if session.phase == .landing && groundPlanet != session.targetPlanet {
                do { try prepareGround() }
                catch { assertionFailure("Could not construct landing site: \(error)") }
            }
            if showingGround != session.groundVisible {
                applySceneMode()
            }
            if showingGround {
                shipPivot.position = [0, session.groundShipHeight, 0]
                ship.orientation = simd_quatf(angle: 0, axis: [0, 0, 1])
            } else {
                shipPivot.position = [0, session.gentleMotion ? 0 : sin(elapsed * 0.7) * 0.045, 0]
                shipPivot.orientation = session.heading
                let bank = simd_quatf(angle: session.gentleMotion ? 0 : -session.steering.x * 0.35, axis: [0, 0, 1])
                ship.orientation = simd_slerp(ship.orientation, bank, 1 - exp(-dt * 4))
                scenery.update(session.universe, dt: dt)
                let follow = 1 - exp(-dt * 3)
                camera.position += (session.heading.act([0, 5.5, 22]) - camera.position) * follow
                camera.orientation = simd_slerp(camera.orientation,
                    session.heading * simd_quatf(angle: -0.14, axis: [1, 0, 0]), follow)
                for entry in stars {
                    let star = entry.entity
                    star.position -= movement
                    for axis in 0..<3 {
                        if star.position[axis] < -entry.halfExtent { star.position[axis] += entry.halfExtent * 2 }
                        if star.position[axis] > entry.halfExtent { star.position[axis] -= entry.halfExtent * 2 }
                    }
                    if entry.foreground {
                        star.isEnabled = !session.gentleMotion
                        // Shrink before recycling and near the camera: no sudden arrivals or oversized flashes.
                        let edge = simd_abs(star.position).max() / entry.halfExtent
                        let boundaryVisibility = 1 - smoothstep(0.72, 1, edge)
                        let cameraVisibility = smoothstep(8, 24, simd_distance(star.position, camera.position))
                        let size = entry.size * boundaryVisibility * cameraVisibility
                        let stretch = 1 + 0.6 * min(1, session.velocity / 12)
                        star.scale = [size, size, size * stretch]
                        star.orientation = session.heading
                    }
                }
            }
        }

        private func applySceneMode() {
            showingGround = session.groundVisible
            ground.isEnabled = showingGround
            space.isEnabled = !showingGround
            for entry in stars where entry.foreground {
                entry.entity.isEnabled = !showingGround && !session.gentleMotion
            }
            if showingGround {
                shipPivot.position = [0, session.groundShipHeight, 0]
                shipPivot.orientation = simd_quatf(angle: 0.4, axis: [0, 1, 0])
                ship.orientation = simd_quatf(angle: 0, axis: [0, 0, 1])
                camera.position = [8, 4.5, 13]
                camera.look(at: [0, 0.8, 0], from: camera.position, relativeTo: nil)
            } else {
                shipPivot.position = .zero
                shipPivot.orientation = session.heading
                camera.position = session.heading.act([0, 5.5, 22])
                camera.orientation = session.heading * simd_quatf(angle: -0.14, axis: [1, 0, 0])
            }
        }

        private func smoothstep(_ lower: Float, _ upper: Float, _ value: Float) -> Float {
            let t = min(1, max(0, (value - lower) / (upper - lower)))
            return t * t * (3 - 2 * t)
        }

        func setActive(_ active: Bool) {
            guard wasActive != active else { return }
            wasActive = active
            if !active { brakingHaptics.stop() }
            displayLink?.isPaused = !active
            previousTime = 0
            if active && !session.groundVisible {
                camera.position = session.heading.act([0, 5.5, 22])
                camera.orientation = session.heading * simd_quatf(angle: -0.14, axis: [1, 0, 0])
            }
        }

        func stop() {
            brakingHaptics.stop()
            displayLink?.invalidate()
            displayLink = nil
        }
    }
}
