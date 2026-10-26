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
        private let thrusters = ShipThrusters()
        private var thrusterResponse = ThrusterResponse()
        private let scenery = UniverseScene()
        private let constellationScene = ConstellationScene()
        private var activityScene: ActivityScene?
        private weak var renderView: ARView?
        private var atmosphere = WorldAtmosphere.airless
        private let voyageScenery = VoyageScenery()
        private var aurora: RestingAurora?
        private var dawn: RestingDawn?
        private let brakingHaptics = BrakingHaptics()
        private var groundPlanet: PlanetDefinition?
        private var restingSky = Entity()
        private var restingSkyMotion = RestingSkyMotion(seed: 0)
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
        #if DEBUG
        private var aimedHorizonPreview = false
        private let traceRestingSky = ProcessInfo.processInfo.arguments.contains("--trace-resting-sky")
        private var skyTraceClock: Float = 0
        private var skyTraceFrames = 0
        #endif

        init(session: FlightSession) { self.session = session }

        func install(in view: ARView) {
            renderView = view
            view.scene.addAnchor(anchor)
            anchor.addChild(space)
            anchor.addChild(ground)
            anchor.addChild(camera)
            camera.camera.fieldOfViewInDegrees = 58
            camera.camera.near = 0.1
            camera.camera.far = 5000
            camera.position = [0, 5.5, 22]
            camera.orientation = simd_quatf(angle: -0.14, axis: [1, 0, 0])
            do {
                ship = try PolygonFactory.ship()
                thrusters.attach(to: ship)
                shipPivot.addChild(ship)
                anchor.addChild(shipPivot)
                space.addChild(scenery.root)
                space.addChild(constellationScene.root)
                space.addChild(constellationScene.navigationRoot)
                let activities = try ActivityScene()
                activityScene = activities
                space.addChild(activities.root)
                space.addChild(voyageScenery.root)
                try prepareGround()
                createStars()
                scenery.update(session.universe, dt: 0)
                voyageScenery.update(session.universe, dt: 0, reduceMotion: session.reduceMotion)
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
            terrain.name = "terrain"
            atmosphere = WorldAtmosphere.forWorld(definition)
            let sky = try PolygonFactory.restingSky(seed: definition.seed, starVisibility: atmosphere.starVisibility)
            let nextAurora = try RestingAurora(seed: definition.seed)
            let nextDawn = try RestingDawn(seed: definition.seed)
            sky.name = "resting-sky"
            restingSkyMotion = RestingSkyMotion(seed: definition.seed, elapsed: session.log.restingTime(on: definition))
            sky.orientation = restingSkyMotion.orientation
            for child in Array(ground.children) { child.removeFromParent() }
            ground.addChild(terrain)
            ground.addChild(sky)
            nextAurora.root.isEnabled = atmosphere != .airless
            ground.addChild(nextAurora.root)
            aurora = nextAurora
            nextDawn.root.isEnabled = atmosphere != .airless
            ground.addChild(nextDawn.root)
            dawn = nextDawn
            restingSky = sky
            groundPlanet = definition
        }

        private func createStars() {
            var random = SeededRandom(seed: 0x4E454D555255)
            let mesh = MeshResource.generateBox(size: 1)
            let starMaterials = StarColors.tints.map { PolygonFactory.material(PolygonFactory.uiColor($0)) }
            var colorRandom = SeededRandom(seed: 0x53544152434F4C)
            // A sparse near layer supplies parallax while distant stars retain the calm background.
            for i in 0..<1000 {
                let foreground = i >= 700
                let extent: Float = foreground ? 90 : 420
                let star = ModelEntity(mesh: mesh, materials: [starMaterials[StarColors.index(sample: colorRandom.value())]])
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
            let previousSpeed = session.velocity
            let movement = session.update(dt)
            let acceleration = (session.velocity - previousSpeed) / max(0.001, dt)
            thrusterResponse.update(speed: session.velocity, acceleration: acceleration,
                braking: session.touching || session.accessibleSlow || session.isProximityStopped || acceleration < -0.05,
                liftingOff: session.phase == .launching, resting: session.phase == .landed, dt: dt)
            thrusters.apply(thrusterResponse.brightness)
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
                restingSkyMotion.advance(dt, reduceMotion: session.reduceMotion)
                aurora?.update(dt: dt, reduceMotion: session.reduceMotion)
                dawn?.update(dt: dt, reduceMotion: session.reduceMotion)
                restingSky.orientation = restingSkyMotion.orientation
                #if DEBUG
                if traceRestingSky {
                    skyTraceClock += dt
                    skyTraceFrames += 1
                    if skyTraceClock >= 2 {
                        print("NEMURU_SKY frames=\(skyTraceFrames) seconds=\(skyTraceClock) angle=\(restingSkyMotion.angle) applied=\(restingSky.orientation.angle) reduceMotion=\(session.reduceMotion) systemReduceMotion=\(UIAccessibility.isReduceMotionEnabled)")
                        skyTraceClock = 0
                        skyTraceFrames = 0
                    }
                }
                #endif
                shipPivot.position = [0, session.groundShipHeight, 0]
                ship.orientation = simd_quatf(angle: 0, axis: [0, 0, 1])
            } else {
                shipPivot.position = [0, session.reduceMotion ? 0 : sin(elapsed * 0.7) * 0.045, 0]
                shipPivot.orientation = session.heading
                let bank = simd_quatf(angle: session.reduceMotion ? 0 : -session.steering.x * 0.35, axis: [0, 0, 1])
                ship.orientation = simd_slerp(ship.orientation, bank, 1 - exp(-dt * 4))
                scenery.update(session.universe, dt: dt)
                constellationScene.update(session.constellation, position: session.universe.position, forward: session.forward, dt: dt)
                constellationScene.guide(to: session.destinationWorld, position: session.universe.position)
                activityScene?.update(session.activity, position: session.universe.position, dt: dt, reduceMotion: session.reduceMotion)
                #if DEBUG
                if !aimedHorizonPreview, ProcessInfo.processInfo.arguments.contains("--preview-horizon"),
                   let distant = scenery.root.children.first(where: { simd_length($0.position) > 2400 }) {
                    session.previewDistantPlanet(at: distant.position)
                    aimedHorizonPreview = true
                }
                #endif
                voyageScenery.update(session.universe, dt: dt, reduceMotion: session.reduceMotion, cameraPosition: camera.position)
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
                        star.isEnabled = !session.reduceMotion
                        // Shrink before recycling and near the camera: no sudden arrivals or oversized flashes.
                        let edge = simd_abs(star.position).max() / entry.halfExtent
                        let boundaryVisibility = 1 - smoothstep(0.72, 1, edge)
                        let cameraVisibility = smoothstep(8, 24, simd_distance(star.position, camera.position))
                        let size = entry.size * boundaryVisibility * cameraVisibility
                        let stretch = 1 + 0.6 * min(1, session.velocity / FlightTuning.cruiseSpeed)
                        star.scale = [size, size, size * stretch]
                        star.orientation = session.heading
                    }
                }
            }
        }

        private func applySceneMode() {
            showingGround = session.groundVisible
            let background = showingGround ? atmosphere.color : WorldAtmosphere.airless.color
            renderView?.environment.background = .color(PolygonFactory.uiColor(background))
            ground.isEnabled = showingGround
            space.isEnabled = !showingGround
            for entry in stars {
                entry.entity.isEnabled = !showingGround && (!entry.foreground || !session.reduceMotion)
            }
            if showingGround {
                shipPivot.position = [0, session.groundShipHeight, 0]
                shipPivot.orientation = simd_quatf(angle: 0.4, axis: [0, 1, 0])
                ship.orientation = simd_quatf(angle: 0, axis: [0, 0, 1])
                camera.position = [8, 4.5, 13]
                camera.look(at: [0, 2.4, -2], from: camera.position, relativeTo: nil)
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
