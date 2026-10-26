import Foundation

nonisolated enum FlightTuning {
    static let cruiseSpeed: Float = 16
    // Older version-1 saves may contain the former 24-unit cruise speed.
    static let maximumArchivedSpeed: Float = 24
    static let slowSpeed: Float = 0
    static let brakingAcceleration: Float = 4.8
}
