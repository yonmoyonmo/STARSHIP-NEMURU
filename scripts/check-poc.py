#!/usr/bin/env python3
"""Run actual flight dynamics and sample synthesis on macOS, without device/audio I/O."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
universe = (root / 'STARSHIP NEMURU/Flight/Universe.swift').read_text()
tuning = (root / 'STARSHIP NEMURU/Flight/FlightTuning.swift').read_text()
voyage_position = (root / 'STARSHIP NEMURU/Flight/VoyagePosition.swift').read_text()
sky_motion = (root / 'STARSHIP NEMURU/Flight/RestingSkyMotion.swift').read_text()
star_colors = (root / 'STARSHIP NEMURU/Flight/StarColors.swift').read_text()
thruster_response = (root / 'STARSHIP NEMURU/Flight/ThrusterResponse.swift').read_text()
store = (root / 'STARSHIP NEMURU/Voyage/VoyageStore.swift').read_text()
log = (root / 'STARSHIP NEMURU/Voyage/VoyageLog.swift').read_text()
flight = (root / 'STARSHIP NEMURU/Flight/FlightSession.swift').read_text()
voice = (root / 'STARSHIP NEMURU/Audio/VoyageAudio.swift').read_text().split('@MainActor\nfinal class VoyageAudio')[0].replace('import MediaPlayer', '')
checks = r'''
@MainActor final class VoyageAudio {
    var onStateChange: ((Bool, String?) -> Void)?
    var isPlaying = false
    var needsUserResume = false
    func start() throws { isPlaying = true; needsUserResume = false; onStateChange?(true, nil) }
    func stop() { isPlaying = false; onStateChange?(false, nil) }
    func pauseByUser() { stop(); needsUserResume = true }
    private(set) var touchdownCount = 0
    func playTouchdown(volume: Float) { touchdownCount += 1 }
    func setLevels(engine: Float, signal: Float, ambience: Float, speed: Float, rest: Float, approach: Float, elapsed: Float = 0.15) {}
}

@main struct PoCChecks {
    @MainActor static func advance(_ session: FlightSession, _ seconds: Float, fps: Int = 60) {
        for _ in 0..<Int(seconds * Float(fps)) { _ = session.update(1 / Float(fps)) }
    }
    @MainActor static func clearFlight() -> FlightSession {
        for index: Int64 in 100...300 {
            let world = Universe(position: UniversePosition(sector: SectorID(x: index, y: 0, z: 0)))
            let clear = world.planets.allSatisfy { body in
                let center = world.relative(body)
                let along = min(800, max(0, -center.z))
                return simd_length(center - SIMD3<Float>(0, 0, -along)) > body.collisionRadius + 125
            }
            if clear { return FlightSession(universe: world) }
        }
        preconditionFailure("No clear test corridor")
    }
    @MainActor static func main() {
        var origin = UniversePosition()
        origin.advance(PlanetDefinition.home.offset)
        let homeAddress = VoyagePosition(origin)
        precondition(homeAddress.x == 0 && homeAddress.y == 0 && homeAddress.z == 0)
        let offsets: [SIMD3<Float>] = [[0,0,-1_000], [1_000,0,0], [0,0,1_000], [-1_000,0,0], [0,-1_000,0], [1_000,1_000,-1_000]]
        for offset in offsets {
            var point = origin
            point.advance(offset)
            let chart = VoyagePosition(point)
            precondition(abs(chart.x - Double(offset.x) / 1_000) < 0.000001)
            precondition(abs(chart.y - Double(offset.y) / 1_000) < 0.000001)
            precondition(abs(chart.z - Double(offset.z) / 1_000) < 0.000001)
        }
        let farAddress = VoyagePosition(UniversePosition(sector: SectorID(x: 1_000_000_000_000, y: 0, z: 0)))
        precondition(farAddress.distanceLightYears.isFinite && farAddress.x.isFinite)
        var sky = RestingSkyMotion(seed: 18)
        let initialSky = sky.angle
        var visibleSky = sky
        visibleSky.advance(5, reduceMotion: false)
        let probe = SIMD3<Float>(0, 0, -350)
        let initialProbe = sky.orientation.act(probe)
        let movedProbe = visibleSky.orientation.act(probe)
        precondition(simd_distance(initialProbe, movedProbe) > 5,
                     "Five seconds must produce a perceptible change in a star away from the pole")
        sky.advance(60, reduceMotion: true)
        precondition(sky.angle == initialSky, "System Reduce Motion must freeze the resting sky")
        sky.advance(60, reduceMotion: false)
        precondition(abs(sky.angle - initialSky - 60 * RestingSkyMotion.radiansPerSecond) < 0.000001)
        let restoredSky = RestingSkyMotion(seed: 18, elapsed: 60)
        precondition(abs(restoredSky.angle - sky.angle) < 0.000001)
        print("PASS galactic XYZ across sectors and far coordinates, quiet sky rotation/reduce-motion/restore")
        for palette in PlanetPalette.allCases {
            let first = palette.colors(seed: 18)
            precondition(first == palette.colors(seed: 18), "World color must regenerate identically")
            precondition(first != palette.colors(seed: 19), "The same family must permit per-world variation")
            for axis in 0..<3 {
                precondition(first.low[axis].isFinite && first.high[axis].isFinite)
                precondition(first.low[axis] >= 0 && first.high[axis] <= 0.721 && first.low[axis] < first.high[axis])
            }
        }
        var starCounts = Array(repeating: 0, count: StarColors.tints.count)
        for value in 0..<1000 { starCounts[StarColors.index(sample: Float(value) / 1000)] += 1 }
        precondition(starCounts.allSatisfy { $0 > 0 } && starCounts[2] > 300,
                     "All six star colors must occur, with soft white the largest share")
        for color in StarColors.tints { for axis in 0..<3 { precondition(color[axis] >= 0 && color[axis] <= 0.73) } }
        precondition(StarColors.cluster(seed: 18) == StarColors.cluster(seed: 18))
        precondition(StarColors.cluster(seed: 18) != StarColors.cluster(seed: 19))
        print("PASS ten muted planet families, seeded color variation, six weighted star tints and cluster families")
        var drive = ThrusterResponse()
        for _ in 0..<120 { drive.update(speed: 24, acceleration: 0, braking: false, liftingOff: false, resting: false, dt: 1 / 60) }
        let cruisingGlow = drive.brightness
        precondition(cruisingGlow > 0.7 && cruisingGlow < 0.8)
        for _ in 0..<120 { drive.update(speed: 24, acceleration: 8, braking: false, liftingOff: false, resting: false, dt: 1 / 60) }
        precondition(drive.brightness > cruisingGlow && drive.brightness > 0.95)
        for _ in 0..<60 { drive.update(speed: 24, acceleration: -8, braking: true, liftingOff: false, resting: false, dt: 1 / 60) }
        precondition(drive.brightness < 0.13, "Braking must dim the drives before the ship has stopped")
        for _ in 0..<120 { drive.update(speed: 0, acceleration: 0, braking: false, liftingOff: false, resting: true, dt: 1 / 60) }
        precondition(drive.brightness == 0, "Stopped/resting drives must settle to dark")
        for _ in 0..<120 { drive.update(speed: 0, acceleration: 0, braking: false, liftingOff: true, resting: false, dt: 1 / 60) }
        precondition(drive.brightness > 0.8, "Launch must ignite before the ship leaves the ground")
        var thirtyGlow = ThrusterResponse(), sixtyGlow = ThrusterResponse()
        for _ in 0..<30 { thirtyGlow.update(speed: 12, acceleration: 4, braking: false, liftingOff: false, resting: false, dt: 1 / 30) }
        for _ in 0..<60 { sixtyGlow.update(speed: 12, acceleration: 4, braking: false, liftingOff: false, resting: false, dt: 1 / 60) }
        precondition(abs(thirtyGlow.brightness - sixtyGlow.brightness) < 0.00001)
        print("PASS thruster acceleration/cruise/braking/stop/launch and frame-rate-independent smoothing")
        let flight = clearFlight()
        flight.touch(at: .zero, size: CGSize(width: 400, height: 800))
        advance(flight, 8)
        precondition(abs(flight.velocity - 2) < 0.001, "Hold must decelerate to a positive minimum")
        flight.release()
        advance(flight, 24)
        precondition(abs(flight.velocity - 24) < 0.01, "Release must accelerate back to cruise")
        let fastArchive = flight.makeArchive()
        try! fastArchive.validate()
        let fastRoundTrip = try! JSONDecoder().decode(VoyageArchive.self, from: JSONEncoder().encode(fastArchive))
        precondition(fastRoundTrip.velocity > 23.9, "Doubled cruise speed must survive serialization")
        var tooFast = fastArchive
        tooFast.velocity = 25
        do { try tooFast.validate(); preconditionFailure("Out-of-range speeds must still be rejected") } catch {}

        let microTurn = FlightSession()
        microTurn.touch(at: .zero, size: CGSize(width: 400, height: 800))
        microTurn.touch(at: CGPoint(x: 5, y: 0), size: CGSize(width: 400, height: 800))
        advance(microTurn, 1)
        let smallAngle = atan2(microTurn.forward.x, -microTurn.forward.z)
        precondition(smallAngle > 0.005 && smallAngle < 0.03, "A five-point drag must permit a small precise turn")
        let releasedTurn = FlightSession()
        releasedTurn.touch(at: .zero, size: CGSize(width: 400, height: 800))
        releasedTurn.touch(at: CGPoint(x: 5, y: 0), size: CGSize(width: 400, height: 800))
        releasedTurn.release()
        advance(releasedTurn, 1)
        let settledForward = releasedTurn.forward
        advance(releasedTurn, 1)
        let residual = acos(min(1, max(-1, simd_dot(settledForward, releasedTurn.forward))))
        precondition(residual < 0.002, "Residual steering must settle promptly after release")
        print("PASS 24-unit cruise/save, precise small drags and short release settling")

        let turn = FlightSession()
        turn.touch(at: .zero, size: CGSize(width: 400, height: 800))
        turn.touch(at: CGPoint(x: 50, y: -50), size: CGSize(width: 400, height: 800))
        advance(turn, 1)
        precondition(turn.forward.x > 0 && turn.forward.y > 0, "Right/up drag must steer right/up")
        turn.release()
        advance(turn, 6)
        precondition(simd_length(turn.steering) < 0.0001, "Rotation must settle after release")

        let thirty = FlightSession(), sixty = FlightSession()
        for session in [thirty, sixty] { session.touch(at: .zero, size: .zero) }
        advance(thirty, 4, fps: 30)
        advance(sixty, 4)
        precondition(abs(thirty.velocity - sixty.velocity) < 0.001, "Damping must be frame-rate independent")

        let fifteen = FlightSession()
        fifteen.touch(at: .zero, size: .zero)
        advance(fifteen, 4, fps: 15)
        precondition(abs(fifteen.velocity - sixty.velocity) < 0.001, "Low-power damping must preserve elapsed time")

        let voyage = FlightSession()
        var nearest: Float = 10000
        for _ in 0..<(60 * 60 * 2) {
            _ = voyage.update(1 / 60)
            for body in voyage.universe.planets {
                let clearance = simd_length(voyage.universe.relative(body)) - body.collisionRadius
                nearest = min(nearest, clearance)
            }
            precondition(voyage.planet.x.isFinite && voyage.heading.real.isFinite)
        }
        precondition(nearest >= 19 - 0.001, "Unattended flight must not enter the planet")
        precondition(voyage.isProximityStopped && voyage.velocity == 0)
        precondition(voyage.heading == simd_quatf(angle: 0, axis: [0,1,0]), "Approach must not turn the pilot automatically")
        let heldPosition = voyage.universe.position
        advance(voyage, 120)
        precondition(voyage.universe.position == heldPosition, "A nearby planet must hold position without creeping")
        for _ in 0..<300 {
            voyage.accessibleTurn([1,0])
            _ = voyage.update(1 / 60)
        }
        precondition(!voyage.isProximityStopped && voyage.velocity > 0, "Turning away must resume cruising")
        print("PASS near-planet stop, no automatic turn, stable hold and pilot-controlled departure")

        let landing = FlightSession()
        advance(landing, 6)
        precondition(landing.canLand, "The initial planet must be reachable")
        precondition(landing.approachAmount > 0, "Approaching a visible planet must affect its atmosphere")
        landing.landOrLaunch()
        precondition(landing.phase == .landing)
        landing.landOrLaunch()
        precondition(landing.transitionProgress == 0, "Repeated transition taps must be ignored")
        let entrySpeed = landing.velocity
        advance(landing, 1)
        precondition(landing.velocity < entrySpeed && landing.velocity > 0, "Landing must ease down from flight")
        let pausedProgress = landing.transitionProgress
        landing.setActive(false)
        advance(landing, 2)
        precondition(landing.transitionProgress == pausedProgress, "Backgrounding must pause a landing transition")
        landing.setActive(true)
        advance(landing, 2.2)
        precondition(landing.groundVisible && landing.fade > 0.99, "Scene swap must be fully hidden")
        precondition(landing.velocity < 0.001, "Space movement must stop at the scene swap")
        advance(landing, 4)
        precondition(landing.phase == .landed && landing.groundVisible && landing.fade == 0)
        precondition(landing.position == landing.targetPlanet.position, "The landed chart must agree with the visited world's location")
        precondition(landing.velocity == 0 && landing.groundShipHeight == -0.5)
        precondition(landing.restAmount == 1 && landing.audio.touchdownCount == 1)
        let visitedPlanet = landing.targetPlanet
        let resting = landing.planet
        let restingHeading = landing.heading
        landing.touch(at: .zero, size: CGSize(width: 400, height: 800))
        landing.touch(at: CGPoint(x: 200, y: 200), size: CGSize(width: 400, height: 800))
        advance(landing, 40)
        precondition(landing.audio.touchdownCount == 1, "Resting must not retrigger contact audio")
        precondition(landing.heading == restingHeading && !landing.touching, "Resting touch must not steer")
        precondition(landing.controlsVisible, "Resting controls must remain available after inactivity")
        landing.touch(at: .zero, size: .zero)
        advance(landing, 1)
        precondition(landing.controlsVisible && landing.phase == .landed, "Resting touch must leave controls available without changing phase")
        precondition(landing.planet == resting, "Landing must be stationary")
        landing.landOrLaunch()
        advance(landing, 3)
        precondition(!landing.groundVisible && landing.fade > 0.99, "Departure scene must switch under the fade")
        precondition(simd_dot(landing.forward, simd_normalize(landing.universe.relative(visitedPlanet))) < 0, "Reorientation must finish before fade-in")
        advance(landing, 3)
        precondition(landing.phase == .flying && !landing.groundVisible)
        precondition(simd_dot(landing.forward, simd_normalize(landing.universe.relative(visitedPlanet))) < 0, "Launch must face away from planet")

        precondition(!landing.canLand, "Departure must not offer a planet behind the ship")
        let noLanding = FlightSession()
        noLanding.landOrLaunch()
        precondition(noLanding.phase == .flying, "Distant planets must not allow landing")

        landing.setActive(false)
        let paused = landing.planet
        advance(landing, 10)
        precondition(landing.planet == paused, "Background flight must pause")
        precondition(!landing.touching)

        // Content must regenerate exactly after eviction and across negative/far coordinates.
        let original = Universe.generate(.zero)
        let streamed = Universe()
        for _ in 0..<1000 {
            streamed.advance([640, 0, 0])
            precondition(streamed.sectors.count == Universe.maximumSectorCount)
        }
        precondition(streamed.sectors[.zero] == nil, "Distant definitions must be evicted")
        for _ in 0..<1000 { streamed.advance([-640, 0, 0]) }
        precondition(streamed.sectors[.zero] == original, "Returning must restore the same content")
        precondition(streamed.position == UniversePosition())
        var paletteSet = Set<Int>()
        var radiusSet = Set<Int>()
        var clusterCount = 0
        for x in -8...8 {
            for z in -8...8 {
                let id = SectorID(x: Int64(x), y: -3, z: Int64(z))
                let first = Universe.generate(id)
                precondition(first == Universe.generate(id))
                if let planet = first.planet {
                    paletteSet.insert(planet.palette.rawValue)
                    radiusSet.insert(Int(planet.radius))
                    precondition(planet.radius >= 24 && planet.radius <= 52)
                }
                if first.cluster != nil { clusterCount += 1 }
            }
        }
        precondition(paletteSet.count == PlanetPalette.allCases.count && radiusSet.count > 10 && clusterCount > 0)
        var boundary = UniversePosition()
        boundary.advance([-320.25, 320.25, -640.5])
        precondition(boundary.sector == SectorID(x: -1, y: 1, z: -1))
        for axis in 0..<3 { precondition(abs(boundary.offset[axis]) <= 320) }
        let farID = SectorID(x: 1_000_000_000_000, y: -1_000_000_000_000, z: 10)
        var farPosition = UniversePosition(sector: farID)
        farPosition.advance([0.125, -0.25, 0.5])
        let local = farPosition.relative(sector: farID, offset: [1, 2, 3])
        precondition(local == SIMD3<Float>(0.875, 2.25, 2.5), "Sub-meter precision must survive huge sector coordinates")
        precondition(Universe.generate(farID) == Universe.generate(farID))
        let sweep = Universe()
        let movement = sweep.safeDisplacement([0, 0, -500])
        precondition(movement.z > -240 && movement.z < -150, "Swept safety must stop before entering a planet")
        sweep.advance(movement)
        precondition(simd_length(sweep.relative(.home)) >= PlanetDefinition.home.collisionRadius + 19)
        // One hour of simulated flight, with a fixed active-sector budget and all-body safety checks.
        let longVoyage = FlightSession()
        var sectorChanges = 0
        var previousSector = longVoyage.universe.position.sector
        for _ in 0..<72_000 {
            if longVoyage.isProximityStopped { longVoyage.accessibleTurn([1, 0]) }
            _ = longVoyage.update(0.05)
            let world = longVoyage.universe
            precondition(world.sectors.count == Universe.maximumSectorCount)
            if world.position.sector != previousSector { sectorChanges += 1; previousSector = world.position.sector }
            for axis in 0..<3 { precondition(abs(world.position.offset[axis]) <= 320) }
            for body in world.planets {
                precondition(simd_length(world.relative(body)) >= body.collisionRadius + 18.99)
            }
        }
        precondition(sectorChanges > 20, "Flight must actually traverse many sectors")
        // Land on a generated world, preserving its identity throughout the round trip.
        let otherWorld = Universe()
        let otherBody = otherWorld.planets.first { $0.sector != .zero && $0.palette != .tide }!
        otherWorld.advance(otherWorld.relative(otherBody) + SIMD3<Float>(0, 0, 110))
        let otherLanding = FlightSession(universe: otherWorld)
        precondition(otherLanding.targetPlanet == otherBody && otherLanding.canLand)
        otherLanding.landOrLaunch()
        advance(otherLanding, 7)
        precondition(otherLanding.phase == .landed && otherLanding.targetPlanet == otherBody)
        precondition(otherLanding.planetName == otherBody.name)
        otherLanding.landOrLaunch()
        advance(otherLanding, 6)
        precondition(otherLanding.phase == .flying)
        precondition(simd_dot(otherLanding.forward, simd_normalize(otherWorld.relative(otherBody))) < 0)
        print("PASS deterministic regeneration, 1,000-sector eviction/return, palettes, far-coordinate precision, swept safety")
        print("PASS one-hour simulated voyage across \(sectorChanges) sector boundaries, generated-world landing/departure")

        let savedDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("nemuru-save-check-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: savedDirectory) }
        let voyageStore = VoyageStore(directory: savedDirectory)
        let persisted = FlightSession(store: voyageStore)
        advance(persisted, 10)
        precondition(persisted.log.found > 0, "Visible planets must enter the journal")
        let foundBefore = persisted.log.found
        persisted.landOrLaunch()
        advance(persisted, 7)
        advance(persisted, 20)
        precondition(persisted.log.visited == 1 && persisted.log.found == foundBefore)
        precondition((persisted.log.longest?.stay ?? 0) > 19)
        persisted.engineVolume = 0.23
        persisted.signalVolume = 0.17
        persisted.backgroundSound = false
        persisted.save()
        voyageStore.flush()
        let savedPosition = persisted.universe.position
        let savedJournal = persisted.log.snapshot
        precondition(savedJournal.worlds.first { $0.id == persisted.targetPlanet.sector }?.position == persisted.targetPlanet.position)
        var oldArchive = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(persisted.makeArchive())) as! [String: Any]
        var oldSettings = oldArchive["settings"] as! [String: Any]
        oldSettings["gentleMotion"] = true
        oldArchive["settings"] = oldSettings
        var oldJournal = oldArchive["journal"] as! [String: Any]
        oldJournal["worlds"] = (oldJournal["worlds"] as! [[String: Any]]).map { entry in
            var legacy = entry
            legacy.removeValue(forKey: "position")
            return legacy
        }
        oldArchive["journal"] = oldJournal
        let legacyArchive = try! JSONDecoder().decode(VoyageArchive.self, from: JSONSerialization.data(withJSONObject: oldArchive))
        try! legacyArchive.validate()
        let migratedLog = VoyageLog(legacyArchive.journal)
        precondition(migratedLog.snapshot.worlds.allSatisfy { $0.position == Universe.generate($0.id).planet?.position })
        precondition(migratedLog.visited == persisted.log.visited && migratedLog.distance == persisted.log.distance)
        let holdRestoreDirectory = savedDirectory.appendingPathComponent("holding")
        let holdStore = VoyageStore(directory: holdRestoreDirectory)
        let holding = FlightSession(store: holdStore)
        advance(holding, 60)
        precondition(holding.isProximityStopped)
        holding.save()
        holdStore.flush()
        let heldArchive = holding.universe.position
        let holdRestored = FlightSession(store: VoyageStore(directory: holdRestoreDirectory))
        advance(holdRestored, 30)
        precondition(holdRestored.isProximityStopped && holdRestored.universe.position == heldArchive)
        print("PASS planet center persistence, legacy journal location backfill, stopped-voyage restoration")
        let restored = FlightSession(store: VoyageStore(directory: savedDirectory))
        precondition(restored.phase == .landed && restored.groundVisible)
        precondition(restored.targetPlanet == persisted.targetPlanet)
        precondition(restored.universe.position == savedPosition)
        precondition(restored.log.snapshot == savedJournal, "Closed-app time must not fabricate a longer stay")
        precondition(restored.engineVolume == 0.23 && restored.signalVolume == 0.17)
        precondition(!restored.backgroundSound)
        advance(restored, 2)
        precondition(restored.log.visited == 1, "Resuming a stay must not count a second landing")
        restored.landOrLaunch()
        advance(restored, 6)
        precondition(restored.phase == .flying)
        restored.setActive(true)
        restored.backgroundSound = true
        restored.setActive(false, background: true)
        let beforeBackground = restored.log.distance
        for _ in 0..<20 { _ = restored.update(1, background: true) }
        precondition(restored.log.distance > beforeBackground, "Audible locked-screen voyages must continue")
        restored.pauseAudio()
        let pausedDistance = restored.log.distance
        _ = restored.update(1, background: true)
        precondition(restored.log.distance == pausedDistance, "Paused audio must not keep a background simulation alive")
        restored.setActive(true)
        precondition(!restored.soundPlaying, "User-paused sound must not restart on foregrounding")
        restored.startAudio(userInitiated: true)
        precondition(restored.soundPlaying)
        restored.backgroundSound = false
        restored.setActive(false, background: true)
        let stopped = restored.universe.position
        _ = restored.update(1, background: true)
        precondition(restored.universe.position == stopped && !restored.soundPlaying)
        restored.shutdown()
        restored.store?.flush()
        let muted = FlightSession()
        muted.setActive(true)
        muted.engineVolume = 0
        muted.signalVolume = 0
        muted.ambienceVolume = 0
        muted.setActive(false, background: true)
        let mutedPosition = muted.universe.position
        _ = muted.update(1, background: true)
        precondition(muted.universe.position == mutedPosition && !muted.soundPlaying)
        muted.shutdown()
        let middleDirectory = savedDirectory.appendingPathComponent("mid-transition")
        let middleStore = VoyageStore(directory: middleDirectory)
        let middle = FlightSession(store: middleStore)
        advance(middle, 10)
        middle.landOrLaunch()
        advance(middle, 3.3)
        middle.save()
        middleStore.flush()
        let middleRestored = FlightSession(store: VoyageStore(directory: middleDirectory))
        precondition(middleRestored.phase == .landing && middleRestored.groundVisible)
        advance(middleRestored, 4)
        precondition(middleRestored.phase == .landed && middleRestored.log.visited == 1)
        precondition(middleRestored.audio.touchdownCount == 1)
        middleRestored.shutdown()
        middleStore.flush()
        let recoveryDirectory = savedDirectory.appendingPathComponent("recovery")
        let recoveryStore = VoyageStore(directory: recoveryDirectory)
        var firstArchive = persisted.makeArchive()
        firstArchive.settings.engine = 0.3
        recoveryStore.save(firstArchive)
        var secondArchive = firstArchive
        secondArchive.settings.engine = 0.7
        recoveryStore.save(secondArchive)
        recoveryStore.flush()
        let primary = recoveryDirectory.appendingPathComponent("voyage.json")
        try! Data("broken".utf8).write(to: primary)
        let recovered = recoveryStore.load()
        precondition(recovered.archive?.settings.engine == 0.3 && recovered.message != nil)
        recoveryStore.save(secondArchive)
        recoveryStore.flush()
        precondition(recoveryStore.load().archive?.settings.engine == 0.7)
        var futureArchive = secondArchive
        futureArchive.version = 99
        let futureData = try! JSONEncoder().encode(futureArchive)
        try! futureData.write(to: primary)
        precondition(recoveryStore.load().archive == nil, "Future versions must not silently fall back and overwrite newer data")
        recoveryStore.save(firstArchive)
        recoveryStore.flush()
        precondition(try! Data(contentsOf: primary) == futureData)
        var invalidArchive = firstArchive
        invalidArchive.heading = [0, 0, 0, 0]
        do { try invalidArchive.validate(); preconditionFailure("Invalid orientations must be rejected") }
        catch {}
        persisted.shutdown()
        middle.shutdown()
        voyageStore.flush()
        middleStore.flush()
        print("PASS journal counts/stay/distance, settings and landed restore, transition restore, backup recovery, future-file protection")
        print("PASS background voyage, audio pause/resume, background opt-out, no fabricated offline stay")

        let rate = 48000.0
        var contactPeak: Float = 0
        for frame in 0...Int(rate * LandingSound.duration) {
            let sample = LandingSound.sample(at: Double(frame) / rate)
            precondition(sample.isFinite && abs(sample) < 0.13)
            contactPeak = max(contactPeak, abs(sample))
        }
        precondition(contactPeak > 0.01 && LandingSound.sample(at: 0) == 0)
        precondition(LandingSound.sample(at: LandingSound.duration) == 0)
        print("PASS soft contact waveform and single touchdown event")
        let count: AVAudioFrameCount = 512
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        for kind in [SynthVoice.Kind.engine, .signal, .atmosphere] {
            let voice = SynthVoice(kind, rate: rate)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
            buffer.frameLength = count
            var peak: Float = 0
            var power: Double = 0
            // Includes several signal events and all startup envelopes.
            for _ in 0..<5000 {
                precondition(voice.render(count, buffer.mutableAudioBufferList) == noErr)
                for channel in 0..<2 {
                    for i in 0..<Int(count) {
                        let sample = buffer.floatChannelData![channel][i]
                        precondition(sample.isFinite && abs(sample) < 0.5, "Synthesis must stay finite and below clipping")
                        peak = max(peak, abs(sample))
                        power += Double(sample * sample)
                    }
                }
            }
            precondition(peak > 0.01 && power > 1, "Each voice must generate audible samples")
            print("PASS synthesized voice \(kind): peak \(peak)")
        }
        print("PASS hold/release, drag direction, damping, 2-minute collision safety, landing, launch, background pause")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='nemuru-check-') as temporary:
    path = Path(temporary)
    source = path / 'Checks.swift'
    source.write_text(tuning + '\n' + universe + '\n' + voyage_position + '\n' + sky_motion + '\n' + star_colors + '\n' + thruster_response + '\n' + store + '\n' + log + '\n' + flight + '\n' + voice + '\n' + checks)
    executable = path / 'checks'
    subprocess.run(['xcrun', '--sdk', 'macosx', 'swiftc', '-O', '-parse-as-library',
                    '-default-isolation', 'MainActor', '-module-cache-path', str(path / 'modules'), str(source), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
