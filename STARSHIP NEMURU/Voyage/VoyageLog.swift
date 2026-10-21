import Foundation
import Combine

@MainActor
final class VoyageLog: ObservableObject {
    @Published private(set) var revision: UInt64 = 0
    private var worlds: [SectorID: WorldRecord] = [:]
    private(set) var distance: Double = 0
    // A game-space scale, not a physical conversion of RealityKit meters to astronomical distance.
    var distanceLightYears: Double { distance / 1_000 }
    var found: Int { worlds.count }
    var visited: Int { worlds.values.filter { $0.landings > 0 }.count }
    var longest: WorldRecord? { worlds.values.filter { $0.stay > 0 }.max { $0.stay < $1.stay } }
    var entries: [WorldRecord] { worlds.values.sorted { $0.foundAt > $1.foundAt } }
    var snapshot: JournalSnapshot { JournalSnapshot(worlds: worlds.values.sorted { $0.id < $1.id }, distance: distance) }

    init(_ snapshot: JournalSnapshot = JournalSnapshot()) {
        worlds = Dictionary(uniqueKeysWithValues: snapshot.worlds.map { ($0.id, $0) })
        distance = snapshot.distance
    }
    func discover(_ world: PlanetDefinition, at date: Date) {
        guard worlds[world.sector] == nil else { return }
        worlds[world.sector] = WorldRecord(id: world.sector, name: world.name, foundAt: date)
        revision &+= 1
    }
    func land(on world: PlanetDefinition, at date: Date) {
        discover(world, at: date)
        guard var record = worlds[world.sector] else { return }
        record.firstLandedAt = record.firstLandedAt ?? date
        record.lastLandedAt = date
        record.landings += 1
        worlds[world.sector] = record
        revision &+= 1
    }
    func travel(_ distance: Double) { self.distance += distance }
    func rest(on world: PlanetDefinition, seconds: TimeInterval) {
        guard seconds > 0, worlds[world.sector]?.landings ?? 0 > 0 else { return }
        worlds[world.sector]?.stay += seconds
    }
    func refresh() { revision &+= 1 }
}
