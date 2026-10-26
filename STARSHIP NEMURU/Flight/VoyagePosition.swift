import Foundation

/// Cartesian chart coordinates in light years, with C–18 as the fictional chart origin.
nonisolated struct VoyagePosition {
    let x: Double
    let y: Double
    let z: Double
    var distanceLightYears: Double { hypot(hypot(x, y), z) }

    init(_ position: UniversePosition) {
        let home = PlanetDefinition.home
        x = (Double(position.sector.x - home.sector.x) * UniversePosition.sectorSize
            + position.offset.x - Double(home.offset.x)) / 1_000
        y = (Double(position.sector.y - home.sector.y) * UniversePosition.sectorSize
            + position.offset.y - Double(home.offset.y)) / 1_000
        z = (Double(position.sector.z - home.sector.z) * UniversePosition.sectorSize
            + position.offset.z - Double(home.offset.z)) / 1_000
    }

    static func format(_ value: Double) -> String {
        let rounded = (value * 1_000).rounded() / 1_000
        return (rounded > 0 ? "+" : "")
            + (rounded == 0 ? 0 : rounded).formatted(.number.precision(.fractionLength(3))) + " ly"
    }
}
