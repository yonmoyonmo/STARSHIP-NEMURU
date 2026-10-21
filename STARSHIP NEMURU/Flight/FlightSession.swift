import SwiftUI
import Combine
import simd

/// Owns the small PoC state machine. Space is expressed relative to the ship.
@MainActor
final class FlightSession: ObservableObject {
    enum Phase: String { case flying, landing, landed, launching }
    @Published private(set) var phase: Phase = .flying
    @Published private(set) var speed: Float = 12
    @Published private(set) var planetDistance: Float = 240
    @Published private(set) var hudOpacity: Double = 1
    @Published private(set) var fade: Double = 0
    @Published var settingsPresented = false
    @Published var engineVolume: Float = 0.5 { didSet { scheduleSave() } }
    @Published var signalVolume: Float = 0.3 { didSet { scheduleSave() } }
    @Published var ambienceVolume: Float = 0.5 { didSet { scheduleSave() } }
    @Published var backgroundSound = true { didSet { scheduleSave() } }
    @Published var gentlerMotion = false { didSet { scheduleSave() } }
    @Published var logPresented = false
    @Published private(set) var soundPlaying = false
    @Published private(set) var storageMessage: String?
    var reduceMotion = false
    var gentleMotion: Bool { reduceMotion || gentlerMotion }
    var accessibleSlow = false
    @Published private(set) var audioError: String?

    let store: VoyageStore?
    let log: VoyageLog
    private var saveTask: Task<Void, Never>?
    private var backgroundTimer: Timer?
    private var backgroundAllowed = false
    private var lastBackgroundTick = Date()
    private var logClock: Float = 0
    private var saveClock: Float = 0
    var isIdle: Bool { idle > 15 && !touching }

    let universe: Universe
    let audio = VoyageAudio()
    @Published private(set) var planetName = "C–18"
    private(set) var targetPlanet: PlanetDefinition = .home
    @Published private(set) var active = true
    private(set) var touching = false
    private(set) var steering = SIMD2<Float>.zero
    private(set) var heading = simd_quatf(angle: 0, axis: [0, 1, 0])
    private(set) var velocity: Float = 12
    var planet: SIMD3<Float> { universe.relative(targetPlanet) }
    private(set) var groundVisible = false
    private var lastTouch: CGPoint?
    private var idle: Float = 0
    private(set) var transitionProgress: Float = 0
    private var approachSpeed: Float = 0
    private var touchdownPlayed = false
    private var uiClock: Float = 0
    private var soundClock: Float = 0

    init(universe initialUniverse: Universe? = nil, store requestedStore: VoyageStore? = nil) {
        #if DEBUG
        let preview = ProcessInfo.processInfo.arguments.contains("--preview-landing")
            || ProcessInfo.processInfo.arguments.contains("--preview-universe")
            || ProcessInfo.processInfo.arguments.contains("--preview-log")
            || ProcessInfo.processInfo.arguments.contains("--preview-settings")
        store = preview ? nil : requestedStore
        #else
        store = requestedStore
        #endif
        let report = store?.load()
        let archive = initialUniverse == nil ? report?.archive : nil
        log = VoyageLog(archive?.journal ?? JournalSnapshot())
        universe = initialUniverse ?? Universe(position: archive?.position)
        if let archive {
            heading = simd_normalize(simd_quatf(vector: SIMD4(archive.heading[0], archive.heading[1], archive.heading[2], archive.heading[3])))
            velocity = archive.velocity
            phase = Phase(rawValue: archive.phase) ?? .flying
            targetPlanet = Universe.generate(archive.target).planet ?? .home
            transitionProgress = archive.transition
            approachSpeed = archive.approachSpeed
            touchdownPlayed = archive.touchdownPlayed
            groundVisible = phase == .landed || (phase == .landing && transitionProgress >= 0.5)
                || (phase == .launching && transitionProgress < 0.5)
            if phase == .landing || phase == .launching {
                fade = Double(smoothstep(0.25, 0.46, transitionProgress) * (1 - smoothstep(0.54, 0.82, transitionProgress)))
            }
            engineVolume = archive.settings.engine
            signalVolume = archive.settings.signal
            ambienceVolume = archive.settings.atmosphere
            backgroundSound = archive.settings.backgroundSound
            gentlerMotion = archive.settings.gentleMotion
        }
        storageMessage = report?.message
        if phase == .flying { selectTarget() }
        planetName = targetPlanet.name
        speed = velocity
        planetDistance = simd_length(planet)
        audio.onStateChange = { [weak self] playing, message in
            self?.soundPlaying = playing
            self?.audioError = message
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-universe"),
           let body = universe.planets.first(where: { $0.sector != .zero && $0.palette != .tide }) {
            universe.advance(universe.relative(body) + SIMD3<Float>(0, 0, 240))
            selectTarget()
            planetName = targetPlanet.name
        }
        // Repeatable visual/audio QA without racing the normal approach window.
        if ProcessInfo.processInfo.arguments.contains("--preview-landing") {
            universe.advance(planet - SIMD3<Float>(0, 8, -110))
            selectTarget()
            planetDistance = simd_length(planet)
            landOrLaunch()
        }
        if ProcessInfo.processInfo.arguments.contains("--preview-log") {
            let now = Date()
            var count = 0
            var sector: Int64 = 1
            while count < 120 {
                defer { sector += 1 }
                guard let world = Universe.generate(SectorID(x: sector, y: 0, z: 0)).planet else { continue }
                let date = now.addingTimeInterval(-Double(count + 1) * 43_200)
                log.discover(world, at: date)
                if count.isMultiple(of: 4) {
                    log.land(on: world, at: date.addingTimeInterval(300))
                    log.rest(on: world, seconds: Double(count + 1) * 120)
                }
                count += 1
            }
            log.discover(.home, at: Date())
            log.land(on: .home, at: Date())
            log.rest(on: .home, seconds: 120)
            log.travel(42_391)
            logPresented = true
        }
        if ProcessInfo.processInfo.arguments.contains("--preview-settings") { settingsPresented = true }
        #endif
    }

    var canLand: Bool {
        phase == .flying && simd_length(planet) < targetPlanet.collisionRadius + 94
            && simd_dot(forward, simd_normalize(planet)) > 0.25
    }
    var restAmount: Float {
        switch phase {
        case .flying: return 0
        case .landed: return 1
        case .landing: return smoothstep(0, 1, transitionProgress)
        case .launching: return 1 - smoothstep(0, 1, transitionProgress)
        }
    }
    var approachAmount: Float {
        guard phase == .flying else { return 0 }
        return smoothstep(targetPlanet.collisionRadius + 144, targetPlanet.collisionRadius + 44, simd_length(planet))
            * smoothstep(0.2, 0.85, simd_dot(forward, simd_normalize(planet)))
    }
    var groundShipHeight: Float {
        switch phase {
        case .landing: return -0.5 + 2.5 * (1 - smoothstep(0.5, 0.9, transitionProgress))
        case .launching: return -0.5 + 2.5 * smoothstep(0, 0.5, transitionProgress)
        default: return -0.5
        }
    }
    var controlsVisible: Bool { phase == .flying || phase == .landed }

    private func smoothstep(_ lower: Float, _ upper: Float, _ value: Float) -> Float {
        let t = min(1, max(0, (value - lower) / (upper - lower)))
        return t * t * (3 - 2 * t)
    }
    var forward: SIMD3<Float> { heading.act([0, 0, -1]) }

    func touch(at point: CGPoint, size: CGSize) {
        idle = 0
        guard phase == .flying, !settingsPresented, !logPresented else { return }
        if let previous = lastTouch {
            // Relative drag: keep the finger still to stop turning, without lifting to accelerate.
            let scale = Float(max(240, min(size.width, size.height)))
            steering += SIMD2(Float(point.x - previous.x), Float(point.y - previous.y)) / scale * 22
            steering = simd_clamp(steering, SIMD2(repeating: -1), SIMD2(repeating: 1))
        }
        lastTouch = point
        touching = true
        idle = 0
    }

    func release() {
        touching = false
        lastTouch = nil
    }

    func setActive(_ value: Bool, background: Bool = false) {
        active = value
        release()
        backgroundTimer?.invalidate()
        backgroundTimer = nil
        backgroundAllowed = !value && background && backgroundSound
            && [engineVolume, signalVolume, ambienceVolume].contains(where: { $0 > 0 })
        if value {
            startAudio()
        } else if backgroundAllowed {
            pushAudioLevels()
            lastBackgroundTick = Date()
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.backgroundTick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            backgroundTimer = timer
        } else {
            audio.stop()
        }
        save()
    }

    private func backgroundTick() {
        let now = Date()
        let elapsed = min(2, max(0, now.timeIntervalSince(lastBackgroundTick)))
        lastBackgroundTick = now
        guard !active, backgroundAllowed, audio.isPlaying else { return }
        _ = update(Float(elapsed), background: true)
    }

    func startAudio(userInitiated: Bool = false) {
        guard userInitiated || !audio.needsUserResume else { return }
        do {
            try audio.start()
            pushAudioLevels()
            soundPlaying = audio.isPlaying
            audioError = nil
        } catch {
            soundPlaying = false
            audioError = "Sound unavailable. You can keep drifting and retry in Sound settings."
        }
    }

    func pauseAudio() {
        audio.pauseByUser()
        soundPlaying = false
    }

    func shutdown() {
        backgroundTimer?.invalidate()
        backgroundTimer = nil
        backgroundAllowed = false
        active = false
        release()
        saveTask?.cancel()
        save()
        audio.stop()
    }

    func accessibleTurn(_ direction: SIMD2<Float>) {
        idle = 0
        guard phase == .flying else { return }
        steering = simd_clamp(steering + direction, SIMD2(repeating: -1), SIMD2(repeating: 1))
    }

    private func pushAudioLevels(elapsed: Float = 0.15) {
        audio.setLevels(engine: engineVolume, signal: signalVolume, ambience: ambienceVolume,
                        speed: velocity / 12, rest: restAmount, approach: approachAmount, elapsed: elapsed)
    }

    private func scheduleSave() {
        guard store != nil else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            self?.save()
        }
    }

    func makeArchive() -> VoyageArchive {
        let rotation = heading.vector
        return VoyageArchive(position: universe.position, heading: [rotation.x, rotation.y, rotation.z, rotation.w],
            velocity: velocity, phase: phase.rawValue, target: targetPlanet.sector,
            transition: transitionProgress, approachSpeed: approachSpeed, touchdownPlayed: touchdownPlayed,
            settings: VoyageSettings(engine: engineVolume, signal: signalVolume, atmosphere: ambienceVolume,
                backgroundSound: backgroundSound, gentleMotion: gentlerMotion), journal: log.snapshot)
    }

    func save() {
        guard let store else { return }
        saveClock = 0
        store.save(makeArchive()) { [weak self] message in
            Task { @MainActor [weak self] in self?.storageMessage = message }
        }
    }

    func landOrLaunch() {
        guard canLand || phase == .landed else { return }
        release()
        planetName = targetPlanet.name
        transitionProgress = 0
        approachSpeed = velocity
        touchdownPlayed = false
        steering = .zero
        phase = phase == .landed ? .launching : .landing
        idle = 0
        hudOpacity = 1
        save()
    }

    /// Called on the main thread by the display link; returns this frame's world displacement.
    func update(_ dt: Float, background: Bool = false) -> SIMD3<Float> {
        guard active || (background && backgroundAllowed && audio.isPlaying) else { return .zero }
        idle += dt
        if phase == .landed { log.rest(on: targetPlanet, seconds: Double(dt)) }
        var displacement = SIMD3<Float>.zero
        if phase == .flying {
            let target: Float = (touching || accessibleSlow) ? 2 : 12
            velocity += (target - velocity) * (1 - exp(-dt * (touching ? 1.7 : 0.38)))
            let yaw = simd_quatf(angle: -steering.x * dt * 0.8, axis: [0, 1, 0])
            let pitch = simd_quatf(angle: -steering.y * dt * 0.8, axis: [1, 0, 0])
            heading = simd_normalize(heading * yaw * pitch)
            steering *= exp(-dt * (touching ? 5 : 2.5))
            // Steering begins well outside the surface of any nearby body, including unselected ones.
            if let obstacle = universe.planets.min(by: {
                simd_length(universe.relative($0)) - $0.collisionRadius
                    < simd_length(universe.relative($1)) - $1.collisionRadius
            }) {
                let center = universe.relative(obstacle)
                if simd_length(center) < obstacle.collisionRadius + 49,
                   simd_dot(forward, simd_normalize(center)) > 0.2 {
                    let away = -simd_normalize(center)
                    var tangent = simd_cross(away, heading.act([0, 1, 0]))
                    if simd_length(tangent) < 0.01 { tangent = heading.act([1, 0, 0]) }
                    let safe = simd_normalize(away * 0.7 + simd_normalize(tangent))
                    let desired = simd_quatf(from: SIMD3<Float>(0, 0, -1), to: safe)
                    heading = simd_slerp(heading, desired, 1 - exp(-dt * 0.7))
                }
            }
            displacement = forward * velocity * dt
        } else if phase == .landing || phase == .launching {
            let landing = phase == .landing
            transitionProgress = min(1, transitionProgress + dt / (landing ? 6 : 5.5))
            let progress = transitionProgress
            // A fully black interval covers the scene and camera change at the midpoint.
            fade = Double(smoothstep(0.25, 0.46, progress) * (1 - smoothstep(0.54, 0.82, progress)))
            if landing {
                velocity = approachSpeed * (1 - smoothstep(0, 0.5, progress))
                if !groundVisible {
                    let towardPlanet = simd_quatf(from: SIMD3<Float>(0, 0, -1), to: simd_normalize(planet))
                    heading = simd_slerp(heading, towardPlanet, 1 - exp(-dt * 0.6))
                    displacement = forward * velocity * dt
                }
            }
            if progress >= 0.5 {
                if groundVisible != landing {
                    groundVisible = landing
                    if !landing {
                        heading = simd_quatf(from: SIMD3<Float>(0, 0, -1), to: -simd_normalize(planet))
                        velocity = 2
                    }
                }
                if !landing {
                    displacement = forward * velocity * dt
                }
            }
            if landing && progress >= 0.9 && !touchdownPlayed {
                touchdownPlayed = true
                audio.playTouchdown(volume: engineVolume)
            }
            if progress >= 1 {
                phase = groundVisible ? .landed : .flying
                velocity = groundVisible ? 0 : 2
                fade = 0
                if phase == .landed { log.land(on: targetPlanet, at: Date()) }
                save()
            }
        }

        displacement = universe.safeDisplacement(displacement)
        universe.advance(displacement)
        if phase == .flying { selectTarget() }
        log.travel(Double(simd_length(displacement)))
        logClock += dt
        saveClock += dt
        if logClock >= 1 {
            logClock = 0
            if !background && phase == .flying {
                for body in universe.planets {
                    let center = universe.relative(body)
                    if simd_length(center) < 650 && simd_dot(forward, simd_normalize(center)) > 0.92 {
                        log.discover(body, at: Date())
                    }
                }
            }
            if logPresented { log.refresh() }
        }
        if saveClock >= 30 { save() }
        soundClock += dt
        if soundClock > 0.15 {
            pushAudioLevels(elapsed: soundClock)
            soundClock = 0
        }
        uiClock += dt
        if uiClock > 0.1 {
            uiClock = 0
            speed = velocity
            planetDistance = simd_length(planet)
            planetName = targetPlanet.name
            hudOpacity = Double(0.22 + 0.78 * exp(-max(0, idle - 4) * 0.16))
        }
        return displacement
    }
    private func selectTarget() {
        var nearest: PlanetDefinition?
        var ahead: PlanetDefinition?
        var reachable: PlanetDefinition?
        var nearestDistance = Float.infinity
        var aheadDistance = Float.infinity
        var reachableDistance = Float.infinity
        for body in universe.planets {
            let center = universe.relative(body)
            let distance = simd_length(center) - body.collisionRadius
            if distance < nearestDistance { nearest = body; nearestDistance = distance }
            if simd_dot(forward, simd_normalize(center)) > 0.25 {
                if distance < aheadDistance { ahead = body; aheadDistance = distance }
                if distance < 94 && distance < reachableDistance { reachable = body; reachableDistance = distance }
            }
        }
        if let selected = reachable ?? ahead ?? nearest { targetPlanet = selected }
    }

}
