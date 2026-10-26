import Foundation
import simd

nonisolated enum WorldAtmosphere: Int, CaseIterable {
    case blue, amber, haze, airless
    static func forWorld(_ world: PlanetDefinition) -> Self {
        var random = SeededRandom(seed: world.seed ^ 0x534B59434F4C4F52)
        return Self(rawValue: min(3, Int(random.value() * 4))) ?? .airless
    }
    var name: String {
        switch self {
        case .blue: return "Blue atmosphere"
        case .amber: return "Amber atmosphere"
        case .haze: return "Pale haze"
        case .airless: return "Airless sky"
        }
    }
    var color: SIMD3<Float> {
        switch self {
        case .blue: return [0.055, 0.16, 0.29]
        case .amber: return [0.19, 0.135, 0.06]
        case .haze: return [0.21, 0.235, 0.25]
        case .airless: return [0.012, 0.022, 0.037]
        }
    }
    var starVisibility: Float {
        switch self {
        case .blue: return 0.24
        case .amber: return 0.38
        case .haze: return 0.14
        case .airless: return 1
        }
    }
}

/// A forgiving observation: focus accumulates only while facing it, with no failure or countdown.
nonisolated struct QuietConstellation {
    let world: PlanetDefinition
    private(set) var focusSeconds: Float = 0
    var centerOffset: SIMD3<Float> {
        world.offset + SIMD3(-world.radius * 1.1, world.radius * 0.5, world.radius * 1.8)
    }
    func relative(to position: UniversePosition) -> SIMD3<Float> {
        position.relative(sector: world.sector, offset: centerOffset)
    }
    func alignment(position: UniversePosition, forward: SIMD3<Float>) -> Float {
        let delta = relative(to: position)
        guard simd_length(delta) > 1 else { return 0 }
        let angle = acos(min(1, max(-1, simd_dot(simd_normalize(delta), forward))))
        return max(0, min(1, 1 - angle / 0.24))
    }
    mutating func observe(dt: Float, position: UniversePosition, forward: SIMD3<Float>, allowed: Bool) -> Bool {
        guard allowed, alignment(position: position, forward: forward) > 0.6 else { return false }
        focusSeconds = min(3, focusSeconds + max(0, min(dt, 0.1)))
        return focusSeconds >= 3
    }
    // A pointed leaf: six edge lights and a central stem. Unaligned, the same lights scatter.
    static let leaf: [SIMD2<Float>] = [[0,10], [-6,4], [-7,-2], [0,-10], [7,-2], [6,4], [0,0]]
}
