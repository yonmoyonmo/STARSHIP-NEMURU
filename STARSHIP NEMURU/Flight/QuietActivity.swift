import Foundation
import simd

nonisolated struct QuietActivity {
    enum Kind { case signal, pattern }
    let world: PlanetDefinition
    let kind: Kind
    private(set) var focus: Float = 0

    static func kind(for world: PlanetDefinition) -> Kind? {
        guard world.sector != .zero else { return nil }
        switch world.seed % 5 { case 1: return .signal; case 2: return .pattern; default: return nil }
    }
    var centerOffset: SIMD3<Float> {
        let side: Float = kind == .signal ? 1.8 : -1.5
        return world.offset + SIMD3(world.radius * side, world.radius * 0.7, world.radius * 1.8)
    }
    func relative(to position: UniversePosition) -> SIMD3<Float> {
        position.relative(sector: world.sector, offset: centerOffset)
    }
    func alignment(position: UniversePosition, forward: SIMD3<Float>) -> Float {
        let delta = relative(to: position)
        guard simd_length(delta) > 1 else { return 0 }
        let angle = acos(min(1, max(-1, simd_dot(simd_normalize(delta), forward))))
        return min(1, max(0, 1 - angle / 0.4))
    }
    func clarity(position: UniversePosition, forward: SIMD3<Float>) -> Float {
        let distance = simd_length(relative(to: position))
        let proximity = min(1, max(0, 1 - (distance - 100) / 700))
        return alignment(position: position, forward: forward) * proximity
    }
    mutating func listen(dt: Float, position: UniversePosition, forward: SIMD3<Float>, allowed: Bool) -> Bool {
        guard kind == .signal, allowed, clarity(position: position, forward: forward) > 0.6 else { return false }
        focus = min(4, focus + max(0, min(dt, 0.1)))
        return focus >= 4
    }
    var unit: [Int] {
        let shift = Int((world.seed >> 8) % 3)
        let base: [Int]
        switch (world.seed >> 12) % 3 {
        case 0: base = [0,1]
        case 1: base = [0,1,2]
        default: base = [0,0,1]
        }
        return base.map { ($0 + shift) % 3 }
    }
    var shown: [Int] { (0..<5).map { unit[$0 % unit.count] } }
    var answer: Int { unit[5 % unit.count] }
    static let symbols = ["○", "△", "◇"]
    var sequence: String { shown.map { Self.symbols[$0] }.joined(separator: "  ") + "  ?" }
    func accepts(_ choice: Int) -> Bool { kind == .pattern && choice == answer }
}
