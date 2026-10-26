import Foundation

nonisolated struct VoyageSettings: Codable, Equatable, Sendable {
    var engine: Float = 0.5
    var signal: Float = 0.3
    var atmosphere: Float = 0.5
    var backgroundSound = true
}

nonisolated struct WorldRecord: Codable, Identifiable, Equatable, Sendable {
    let id: SectorID
    let name: String
    let foundAt: Date
    var firstLandedAt: Date?
    var lastLandedAt: Date?
    var landings = 0
    var stay: TimeInterval = 0
    var position: UniversePosition?
    var nickname: String?
    var favorite: Bool?
    var constellationFoundAt: Date?
    var signalFoundAt: Date?
    var patternFoundAt: Date?
    var displayName: String { nickname?.isEmpty == false ? nickname! : name }
}

nonisolated struct JournalSnapshot: Codable, Equatable, Sendable {
    var worlds: [WorldRecord] = []
    var distance: Double = 0
}

nonisolated struct VoyageArchive: Codable, Sendable {
    var version = 1
    var generatorVersion = 1
    var savedAt = Date()
    var position: UniversePosition
    var heading: [Float]
    var velocity: Float
    var phase: String
    var target: SectorID
    var transition: Float
    var approachSpeed: Float
    var touchdownPlayed: Bool
    var settings: VoyageSettings
    var journal: JournalSnapshot
    var destination: SectorID?

    func validate() throws {
        guard version == 1, generatorVersion == 1 else { throw ArchiveError.unsupported }
        func validSector(_ id: SectorID) -> Bool {
            [id.x, id.y, id.z].allSatisfy { $0 > -1_000_000_000_000_000 && $0 < 1_000_000_000_000_000 }
        }
        if let destination {
            guard validSector(destination), Universe.generate(destination).planet != nil else { throw ArchiveError.invalid }
        }
        let rotationLength = heading.reduce(Float.zero) { $0 + $1 * $1 }
        guard validSector(position.sector), validSector(target),
              (0..<3).allSatisfy({ position.offset[$0].isFinite && abs(position.offset[$0]) <= 320 }),
              heading.count == 4, heading.allSatisfy(\.isFinite), (0.9...1.1).contains(rotationLength),
              velocity.isFinite, (0...(FlightTuning.maximumArchivedSpeed + 0.01)).contains(velocity),
              ["flying", "landing", "landed", "launching"].contains(phase),
              transition.isFinite, (0...1).contains(transition),
              approachSpeed.isFinite, (0...(FlightTuning.maximumArchivedSpeed + 0.01)).contains(approachSpeed),
              [settings.engine, settings.signal, settings.atmosphere].allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              journal.distance.isFinite, journal.distance >= 0, journal.worlds.count <= 200_000,
              savedAt.timeIntervalSince1970.isFinite,
              Set(journal.worlds.map(\.id)).count == journal.worlds.count,
              journal.worlds.allSatisfy({ validSector($0.id) && !$0.name.isEmpty && $0.name.count <= 32
                  && $0.stay.isFinite && $0.stay >= 0 && $0.stay <= 10_000_000_000 && $0.landings >= 0
                  && ($0.nickname.map { !$0.isEmpty && $0.count <= 40 && !$0.contains(where: { $0.isNewline || $0.isASCII && $0.asciiValue! < 32 }) } ?? true)
                  && ($0.constellationFoundAt?.timeIntervalSince1970.isFinite ?? true)
                  && ($0.signalFoundAt?.timeIntervalSince1970.isFinite ?? true)
                  && ($0.patternFoundAt?.timeIntervalSince1970.isFinite ?? true)
                  && $0.foundAt.timeIntervalSince1970.isFinite
                  && ($0.position.map { point in validSector(point.sector)
                      && (0..<3).allSatisfy { point.offset[$0].isFinite && abs(point.offset[$0]) <= 320 } } ?? true)
                  && ($0.landings == 0 || $0.firstLandedAt != nil) }) else { throw ArchiveError.invalid }
        guard let body = Universe.generate(target).planet else { throw ArchiveError.invalid }
        if phase != "flying" {
            let center = position.relative(sector: body.sector, offset: body.offset)
            guard simdLength(center) < body.collisionRadius + 160 else { throw ArchiveError.invalid }
        }
    }

    private func simdLength(_ value: SIMD3<Float>) -> Float {
        sqrt(value.x * value.x + value.y * value.y + value.z * value.z)
    }
}

nonisolated enum ArchiveError: Error { case unsupported, invalid }

/// All filesystem state and writes are serialized. Audio rendering never touches this queue.
nonisolated final class VoyageStore: @unchecked Sendable {
    struct LoadReport {
        var archive: VoyageArchive?
        var message: String?
    }
    let directory: URL
    private let queue = DispatchQueue(label: "studio.nemuru.voyage-store", qos: .utility)
    private var blocked = false
    private var primary: URL { directory.appendingPathComponent("voyage.json") }
    private var backup: URL { directory.appendingPathComponent("voyage.previous.json") }

    init(directory: URL) { self.directory = directory }
    static func applicationStore() -> VoyageStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return VoyageStore(directory: base.appendingPathComponent("Nemuru", isDirectory: true))
    }
    private func decode(_ url: URL) throws -> VoyageArchive {
        let archive = try JSONDecoder().decode(VoyageArchive.self, from: Data(contentsOf: url))
        try archive.validate()
        return archive
    }
    func load() -> LoadReport {
        queue.sync {
            blocked = false
            let manager = FileManager.default
            guard manager.fileExists(atPath: primary.path) || manager.fileExists(atPath: backup.path) else {
                return LoadReport()
            }
            do { return LoadReport(archive: try decode(primary)) }
            catch ArchiveError.unsupported {
                blocked = true
                return LoadReport(message: "This voyage was saved by a different version. The original file is preserved.")
            } catch {
                if let recovered = try? decode(backup) {
                    return LoadReport(archive: recovered, message: "Recovered the previous saved voyage.")
                }
                blocked = true
                return LoadReport(message: "Your saved voyage could not be read. The original files are preserved; saving is paused.")
            }
        }
    }
    func save(_ archive: VoyageArchive, completion: (@Sendable (String?) -> Void)? = nil) {
        queue.async { [self] in
            do {
                guard !blocked else { completion?("Saving is paused to preserve the existing voyage."); return }
                try archive.validate()
                let manager = FileManager.default
                try manager.createDirectory(at: directory, withIntermediateDirectories: true)
                if (try? decode(primary)) != nil {
                    try Data(contentsOf: primary).write(to: backup, options: .atomic)
                }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                try encoder.encode(archive).write(to: primary, options: .atomic)
                #if os(iOS)
                for url in [directory, primary, backup] where manager.fileExists(atPath: url.path) {
                    try manager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
                }
                #endif
                completion?(nil)
            } catch {
                completion?("The voyage could not be saved. Your previous save is preserved.")
            }
        }
    }
    /// Tests and diagnostics only. UI saves are asynchronous.
    func flush() { queue.sync {} }
}
