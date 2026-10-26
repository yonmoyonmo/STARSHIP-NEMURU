import Foundation

/// A smooth visual throttle; slowing down cuts the main drives even before speed reaches zero.
nonisolated struct ThrusterResponse {
    private(set) var brightness: Float = 0

    mutating func update(speed: Float, acceleration: Float, braking: Bool,
                         liftingOff: Bool, resting: Bool, dt: Float) {
        let target: Float
        if resting {
            target = 0
        } else if liftingOff {
            target = 0.85
        } else if speed < 0.05 {
            target = 0
        } else {
            let cruise = min(1, max(0, speed / FlightTuning.cruiseSpeed))
            let thrust = min(1, max(0, acceleration / 8))
            target = min(1, (0.12 + cruise * 0.66 + thrust * 0.22) * (braking ? 0.15 : 1))
        }
        let duration: Float = target < brightness ? 0.18 : 0.35
        brightness += (target - brightness) * (1 - exp(-max(0, dt) / duration))
        if target == 0 && brightness < 0.002 { brightness = 0 }
    }
}
