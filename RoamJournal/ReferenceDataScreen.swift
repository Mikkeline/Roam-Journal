import SwiftUI
struct ReferenceDataScreen: View {
    @State private var snapshot: ReferenceDataService.Snapshot?
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        Form {
            if let snapshot {
                LabeledContent("Reference date", value: snapshot.date.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("Airports", value: "\(snapshot.airports.count)")
                LabeledContent("Airlines", value: "\(snapshot.airlines.count)")
            }
            Button("Check for reference-data updates", systemImage: "arrow.triangle.2.circlepath") {
                busy = true
                Task { defer { busy = false }; do { _ = try await ReferenceDataService.shared.update(); snapshot = try await ReferenceDataService.shared.snapshot() } catch { self.error = "The update couldn’t be verified or downloaded. Your current airport and airline lists have been kept." } }
            }.disabled(busy)
            if busy { ProgressView("Downloading reference lists…") }
            Text("Downloads public airport/airline lists from their GitHub sources. No trip details are sent. New pickers use the updated list; existing saved flights stay unchanged. This does not update flight schedules or confirm terminals.").font(.footnote).foregroundStyle(.secondary)
        }.navigationTitle("Airport & airline data")
            .task { snapshot = try? await ReferenceDataService.shared.snapshot() }
            .alert("Update unavailable", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
}
