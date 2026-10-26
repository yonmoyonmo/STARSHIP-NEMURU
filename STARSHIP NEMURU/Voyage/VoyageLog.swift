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
        // Old journals already contain sector IDs; reconstruct their unchanged generated centers.
        for id in Array(worlds.keys) where worlds[id]?.position == nil {
            worlds[id]?.position = Universe.generate(id).planet?.position
        }
        distance = snapshot.distance
    }
    func record(_ id: SectorID) -> WorldRecord? { worlds[id] }
    var favorites: [WorldRecord] { entries.filter { $0.favorite == true } }
    func rename(_ id: SectorID, to name: String) {
        let clean = String(name.filter { !$0.isNewline && !($0.isASCII && $0.asciiValue! < 32) }
            .trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard worlds[id] != nil else { return }
        worlds[id]?.nickname = clean.isEmpty ? nil : clean
        revision &+= 1
    }
    func remember(_ id: SectorID, favorite: Bool) {
        guard worlds[id] != nil else { return }
        worlds[id]?.favorite = favorite
        revision &+= 1
    }
    func findConstellation(on world: PlanetDefinition, at date: Date) {
        discover(world, at: date)
        worlds[world.sector]?.constellationFoundAt = date
        revision &+= 1
    }
    func findActivity(_ activity: QuietActivity, at date: Date) {
        discover(activity.world, at: date)
        guard var record = worlds[activity.world.sector] else { return }
        if activity.kind == .signal { record.signalFoundAt = record.signalFoundAt ?? date }
        else { record.patternFoundAt = record.patternFoundAt ?? date }
        worlds[activity.world.sector] = record
        revision &+= 1
    }
    func discover(_ world: PlanetDefinition, at date: Date) {
        guard worlds[world.sector] == nil else { return }
        worlds[world.sector] = WorldRecord(id: world.sector, name: world.name, foundAt: date, position: world.position)
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
    func restingTime(on world: PlanetDefinition) -> TimeInterval { worlds[world.sector]?.stay ?? 0 }
}
