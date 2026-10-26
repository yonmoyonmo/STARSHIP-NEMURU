import CoreHaptics
import Foundation
import OSLog

/// One continuous, soft vibration; frame updates change its strength without retriggering taps.
@MainActor
final class BrakingHaptics {
    private let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private let logger = Logger(subsystem: "yowenomo.studio.STARSHIP-NEMURU", category: "BrakingHaptics")
    private var engine: CHHapticEngine?
    private var player: (any CHHapticAdvancedPatternPlayer)?
    private var strength: Float = 0
    private var lastSent: Float = -1
    private var retryAfter = Date.distantPast

    func update(holding: Bool, speed: Float, elapsed: Float) {
        guard supported else { return }
        // Strongest while shedding cruising speed, settling to a faint texture at low speed.
        let braking = min(1, max(0, (speed - FlightTuning.slowSpeed) / (FlightTuning.cruiseSpeed - FlightTuning.slowSpeed)))
        let target: Float = holding ? 0.5 + 0.35 * braking : 0
        guard holding || player != nil else { return }
        if player == nil {
            guard Date() >= retryAfter else { return }
            do { try preparePlayer() }
            catch {
                logger.error("Could not start braking haptics: \(error.localizedDescription, privacy: .public)")
                stop()
                retryAfter = Date().addingTimeInterval(2)
                return
            }
        }
        strength += (target - strength) * (1 - exp(-max(0, elapsed) / 0.12))
        if !holding && strength < 0.008 {
            stopPlayer()
            return
        }
        guard abs(strength - lastSent) > 0.002 else { return }
        do {
            try player?.sendParameters([
                CHHapticDynamicParameter(parameterID: .hapticIntensityControl,
                                         value: strength, relativeTime: 0)
            ], atTime: CHHapticTimeImmediate)
            lastSent = strength
        } catch {
            logger.error("Could not update braking haptics: \(error.localizedDescription, privacy: .public)")
            stop()
            retryAfter = Date().addingTimeInterval(2)
        }
    }

    private func preparePlayer() throws {
        if engine == nil {
            let newEngine = try CHHapticEngine()
            // This engine must never reconfigure or emit the voyage's audio.
            newEngine.playsHapticsOnly = true
            newEngine.isAutoShutdownEnabled = true
            newEngine.stoppedHandler = { [weak self, weak newEngine] reason in
                Task { @MainActor [weak self, weak newEngine] in
                    guard let self, let newEngine, self.engine === newEngine else { return }
                    self.logger.notice("Haptic engine stopped: \(reason.rawValue)")
                    self.player = nil
                    self.strength = 0
                    self.lastSent = -1
                }
            }
            newEngine.resetHandler = { [weak self, weak newEngine] in
                Task { @MainActor [weak self, weak newEngine] in
                    guard let self, let newEngine, self.engine === newEngine else { return }
                    self.player = nil
                    self.strength = 0
                    self.lastSent = -1
                }
            }
            engine = newEngine
        }
        guard let engine else { return }
        try engine.start()
        let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.15)
        ], relativeTime: 0, duration: 1)
        let pattern = try CHHapticPattern(events: [event], parameters: [])
        let newPlayer = try engine.makeAdvancedPlayer(with: pattern)
        newPlayer.loopEnabled = true
        // Start at a quiet, nonzero level. Send live controls only after playback starts;
        // do not depend on a parameter sent before start being retained by the player.
        try newPlayer.start(atTime: CHHapticTimeImmediate)
        try newPlayer.sendParameters([
            CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: 0.1, relativeTime: 0)
        ], atTime: CHHapticTimeImmediate)
        player = newPlayer
        strength = 0.1
        lastSent = 0.1
        logger.notice("Continuous braking haptics started")
    }

    private func stopPlayer() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
        strength = 0
        lastSent = -1
    }

    func stop() {
        stopPlayer()
        let previous = engine
        engine = nil
        previous?.stop(completionHandler: nil)
    }
}
