import SwiftUI

struct VoyageLogView: View {
    let flight: FlightSession
    @ObservedObject var log: VoyageLog
    @Environment(\.dismiss) private var dismiss
    @State private var records: [WorldRecord]
    init(flight: FlightSession) { self.flight = flight; log = flight.log; _records = State(initialValue: flight.log.entries) }

    var body: some View {
        NavigationStack {
            List {
                Section("Traces of your voyage") {
                    LabeledContent("Worlds found", value: "\(log.found)")
                    LabeledContent("Worlds visited", value: "\(log.visited)")
                    LabeledContent("Distance", value: log.distanceLightYears.formatted(.number.precision(.fractionLength(3))) + " ly")
                    LabeledContent("Longest stay", value: log.longest.map { "\($0.displayName) · \(restDuration($0.stay))" } ?? "—")
                }
                if records.contains(where: { $0.favorite == true }) {
                    Section("Places to return to") {
                        ForEach(records.filter { $0.favorite == true }.prefix(5)) { record in placeLink(record) }
                    }
                }
                Section {
                    if records.isEmpty { Text("Your voyage will leave a few quiet traces here.").foregroundStyle(.secondary) }
                    ForEach(records.prefix(3)) { record in placeLink(record) }
                    if !records.isEmpty {
                        NavigationLink("View all worlds") { WorldHistoryView(flight: flight) }
                    }
                } header: { Text("Worlds along the way") }
                footer: { Text("Keep a place, give it a name, or set a quiet course back.") }
                if let message = flight.storageMessage { Section { Text(message).font(.footnote).foregroundStyle(.secondary) } }
            }
            .navigationTitle("Nemuru log")
            .onChange(of: log.revision) { _, _ in records = log.entries }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
        }
    }
    private func placeLink(_ record: WorldRecord) -> some View {
        NavigationLink { WorldPlaceView(flight: flight, id: record.id) } label: { WorldRecordRow(record: record) }
    }
}

private struct WorldHistoryView: View {
    let flight: FlightSession
    @ObservedObject var log: VoyageLog
    @State private var records: [WorldRecord]
    @State private var query = ""
    @State private var filter = 0
    @State private var limit = 40
    init(flight: FlightSession) { self.flight = flight; log = flight.log; _records = State(initialValue: flight.log.entries) }
    private var matches: [WorldRecord] {
        let name = query.filter { $0.isLetter || $0.isNumber }
        return records.map { log.record($0.id) ?? $0 }.filter {
            (filter != 1 || $0.landings > 0) && (filter != 2 || $0.favorite == true)
                && (name.isEmpty || ($0.name + " " + ($0.nickname ?? "")).filter { $0.isLetter || $0.isNumber }.localizedStandardContains(name))
        }
    }
    var body: some View {
        let filtered = matches
        List {
            Section {
                Picker("Worlds", selection: $filter) {
                    Text("All").tag(0); Text("Visited").tag(1); Text("Kept").tag(2)
                }.pickerStyle(.segmented)
            }
            Section {
                if filtered.isEmpty { Text("No worlds match this view.").foregroundStyle(.secondary) }
                ForEach(filtered.prefix(limit)) { record in
                    NavigationLink { WorldPlaceView(flight: flight, id: record.id) } label: { WorldRecordRow(record: record) }
                }
                if limit < filtered.count { Button("Show more worlds") { limit += 40 }.frame(minHeight: 44) }
            } header: { Text("Latest discoveries first") }
            footer: { Text("Showing \(min(limit, filtered.count)) of \(filtered.count) worlds") }
        }
        .navigationTitle("Worlds").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search names and chart names")
        .onChange(of: query) { _, _ in limit = 40 }
        .onChange(of: filter) { _, _ in limit = 40 }
    }
}

struct WorldPlaceView: View {
    @ObservedObject var flight: FlightSession
    @ObservedObject var log: VoyageLog
    let id: SectorID
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    init(flight: FlightSession, id: SectorID) { self.flight = flight; log = flight.log; self.id = id }
    var body: some View {
        Form {
            if let record = log.record(id) {
                Section {
                    Text(record.displayName).font(.system(.title2, design: .monospaced))
                    if record.nickname != nil { Text(record.name).foregroundStyle(.secondary) }
                    if let world = Universe.generate(id).planet { Text(WorldAtmosphere.forWorld(world).name).foregroundStyle(.secondary) }
                    Text("Found " + record.foundAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    if let last = record.lastLandedAt { Text("Last visit " + last.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                    if record.constellationFoundAt != nil { Label("Found through a leaf of light", systemImage: "leaf") }
                    if record.signalFoundAt != nil { Label("Found through a quiet signal", systemImage: "waveform") }
                    if record.patternFoundAt != nil { Label("Found through a rhythm of light", systemImage: "circle.grid.3x1") }
                    Text(record.landings > 0 ? "\(record.landings) visits · \(restDuration(record.stay)) resting" : "A place waiting for a visit.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section {
                    TextField("A name for this place", text: $name).submitLabel(.done)
                        .onChange(of: name) { _, value in if value.count > 40 { name = String(value.prefix(40)) } }
                        .onSubmit { flight.nameWorld(id, name: name) }
                    Button("Save name") { flight.nameWorld(id, name: name) }
                    Toggle("Keep this place", isOn: Binding(get: { log.record(id)?.favorite == true },
                        set: { flight.rememberWorld(id, favorite: $0) }))
                } header: { Text("Your own name") }
                footer: { Text("Up to 40 characters. Leave it empty to use the chart name.") }
                Section {
                    Button(flight.destination == id ? "Following this course" : "Set course to this place") { flight.setCourse(to: id); dismiss() }
                    if flight.destination == id { Button("Let the course go") { flight.setCourse(to: nil); dismiss() } }
                    Text("A direction and a distance. You decide how to get there.").font(.footnote).foregroundStyle(.secondary)
                }
                if let point = record.position {
                    Section("Galactic coordinates") {
                        GalacticCoordinateReadings(position: point)
                        Text("Origin · C–18").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("A place in your voyage").navigationBarTitleDisplayMode(.inline)
        .onAppear { name = log.record(id)?.nickname ?? "" }
    }
}

private struct WorldRecordRow: View {
    let record: WorldRecord
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(record.displayName).font(.system(.headline, design: .monospaced))
                if record.favorite == true { Image(systemName: "bookmark.fill").font(.caption) }
                if record.constellationFoundAt != nil { Image(systemName: "leaf").font(.caption) }
                if record.signalFoundAt != nil { Image(systemName: "waveform").font(.caption) }
                if record.patternFoundAt != nil { Image(systemName: "circle.grid.3x1").font(.caption) }
            }
            if record.nickname != nil { Text(record.name).font(.caption).foregroundStyle(.secondary) }
            Text(record.landings > 0 ? "Visited · \(restDuration(record.stay)) resting" : "Seen in passing")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 5)
    }
}

private func restDuration(_ seconds: TimeInterval) -> String {
    let minutes = Int(seconds) / 60
    if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
    if minutes > 0 { return "\(minutes)m" }
    return "\(Int(seconds))s"
}
