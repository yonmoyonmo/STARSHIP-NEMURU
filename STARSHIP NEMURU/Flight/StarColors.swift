import Foundation

/// Mostly soft whites, with fewer warm, icy and lavender lights. No color animation or flashing.
nonisolated enum StarColors {
    static let tints: [SIMD3<Float>] = [
        [0.70, 0.51, 0.32], // amber
        [0.67, 0.60, 0.42], // pale gold
        [0.65, 0.65, 0.59], // warm white
        [0.43, 0.62, 0.57], // mint white
        [0.39, 0.54, 0.72], // ice blue
        [0.57, 0.48, 0.70]  // lavender
    ]

    static func index(sample: Float) -> Int {
        switch sample {
        case ..<0.14: return 0
        case ..<0.28: return 1
        case ..<0.65: return 2
        case ..<0.77: return 3
        case ..<0.94: return 4
        default: return 5
        }
    }

    static func cluster(seed: UInt64) -> [SIMD3<Float>] {
        let families = [[0, 1, 2], [2, 4, 5], [2, 3, 4]]
        return families[Int(seed % UInt64(families.count))].map { tints[$0] }
    }
}
