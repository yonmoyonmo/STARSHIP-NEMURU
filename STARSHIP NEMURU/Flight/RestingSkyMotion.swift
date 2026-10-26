import Foundation
import simd

/// A slow sky rotation, advanced only while the landscape is being rendered.
nonisolated struct RestingSkyMotion {
    static let radiansPerSecond = 0.01
    // Keep the celestial pole inside the landscape's upper sky, making the arcs legible.
    static let axis = simd_normalize(SIMD3<Float>(-0.4, 0.22, -0.89))
    private(set) var angle: Double

    init(seed: UInt64, elapsed: TimeInterval = 0) {
        angle = (Double(seed % 628) / 100 + elapsed * Self.radiansPerSecond)
            .truncatingRemainder(dividingBy: 2 * .pi)
    }

    mutating func advance(_ dt: Float, reduceMotion: Bool) {
        guard !reduceMotion else { return }
        angle = (angle + Double(max(0, dt)) * Self.radiansPerSecond)
            .truncatingRemainder(dividingBy: 2 * .pi)
    }

    var orientation: simd_quatf {
        simd_quatf(angle: Float(angle), axis: Self.axis)
    }
}
