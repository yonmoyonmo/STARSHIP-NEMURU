import SwiftUI

struct VoyageLogView: View {
    @ObservedObject var log: VoyageLog
    @Environment(\.dismiss) private var dismiss
    var storageMessage: String?
    @State private var records: [WorldRecord] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    metric("Worlds found", value: "\(log.found)")
                    metric("Worlds visited", value: "\(log.visited)")
                    metric("Distance", value: lightYears + " ly")
                        .accessibilityLabel("Distance")
                        .accessibilityValue(lightYears + " light years")
                    metric("Longest stay", value: log.longest.map { "\($0.name) · \(restDuration($0.stay))" } ?? "—")
                } header: { Text("Traces of your voyage") }
                Section {
                    if records.isEmpty {
                        Text("Your voyage will leave a few quiet traces here.").foregroundStyle(.secondary)
                    }
                    ForEach(records.prefix(3)) { record in
                        WorldRecordRow(record: record, compact: true)
                    }
                    if !records.isEmpty {
                        NavigationLink {
                            WorldHistoryView(records: log.entries)
                        } label: {
                            HStack {
                                Text("View all worlds")
                                Spacer()
                                Text(records.count.formatted()).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                } header: { Text("Worlds along the way") }
                footer: { if !records.isEmpty { Text("Your latest discoveries. The full journal is always here.") } }
                if let storageMessage {
                    Section { Text(storageMessage).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Nemuru log")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
            .onAppear { records = log.entries }
            .onChange(of: log.found) { _, _ in records = log.entries }
        }
    }

    private func metric(_ title: String, value: String) -> some View {
        LabeledContent {
            Text(value).monospacedDigit().foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        } label: { Text(title) }
            .accessibilityElement(children: .combine)
    }
    private var lightYears: String {
        log.distanceLightYears.formatted(.number.precision(.fractionLength(3)))
    }
}

private struct WorldHistoryView: View {
    // Keep a stable snapshot while browsing; arrival of a new world must not shift the list.
    @State private var records: [WorldRecord]
    @State private var query = ""
    @State private var visitedOnly = false
    @State private var limit = 40

    init(records: [WorldRecord]) {
        _records = State(initialValue: records)
    }

    private var matches: [WorldRecord] {
        // Let a typed "C18" or "C-18" find the displayed "C–18" as well.
        let name = query.filter { $0.isLetter || $0.isNumber }
        return records.filter {
            (!visitedOnly || $0.landings > 0)
                && (name.isEmpty || $0.name.filter { $0.isLetter || $0.isNumber }.localizedStandardContains(name))
        }
    }

    var body: some View {
        let filtered = matches
        List {
            Section {
                Picker("Worlds", selection: $visitedOnly) {
                    Text("All").tag(false)
                    Text("Visited").tag(true)
                }.pickerStyle(.segmented)
            }
            Section {
                if filtered.isEmpty {
                    Text(query.isEmpty ? "No visited worlds yet." : "No worlds match your search.")
                        .foregroundStyle(.secondary)
                }
                ForEach(filtered.prefix(limit)) { record in
                    WorldRecordRow(record: record)
                }
                if limit < filtered.count {
                    Button("Show more worlds") { limit = min(filtered.count, limit + 40) }
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            } header: { Text("Latest discoveries first") }
            footer: {
                Text("Showing \(min(limit, filtered.count).formatted()) of \(filtered.count.formatted()) worlds")
            }
        }
        .navigationTitle("Worlds")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search world names")
        .onChange(of: query) { _, _ in limit = 40 }
        .onChange(of: visitedOnly) { _, _ in limit = 40 }
    }
}

private struct WorldRecordRow: View {
    let record: WorldRecord
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(record.name).font(.system(.headline, design: .monospaced))
            Text("Found \(record.foundAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(.secondary)
            if compact {
                Text(record.landings > 0 ? "Visited" : "Seen in passing")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let landed = record.lastLandedAt {
                Text("Last visit \(landed.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Visits \(record.landings) · \(restDuration(record.stay)) resting")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 5).accessibilityElement(children: .combine)
    }
}

private func restDuration(_ seconds: TimeInterval) -> String {
    let minutes = Int(seconds) / 60
    if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
    if minutes > 0 { return "\(minutes)m" }
    return "\(Int(seconds))s"
}
