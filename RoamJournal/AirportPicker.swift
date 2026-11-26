import SwiftUI

protocol AirportCatalogLoading: Sendable { func load() async throws -> AirportCatalog }
actor BundledAirportCatalog: AirportCatalogLoading {
    static let shared = BundledAirportCatalog()
    func load() async throws -> AirportCatalog { AirportCatalog(airports: try await ReferenceDataService.shared.snapshot().airports) }

}
struct AirportPicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var catalog: AirportCatalog?
    @State private var error = false
    let provider: any AirportCatalogLoading
    let onSelect: (AirportSelection) -> Void
    init(provider: any AirportCatalogLoading = BundledAirportCatalog.shared, onSelect: @escaping (AirportSelection) -> Void) { self.provider = provider; self.onSelect = onSelect }
    var body: some View {
        NavigationStack {
            Group {
                if let catalog {
                    let matches = catalog.search(query)
                    List {
                        Section {
                            ForEach(matches) { selection in
                                Button { onSelect(selection); dismiss() } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(selection.label).foregroundStyle(.primary)
                                        Text("\(selection.airport.city), \(selection.airport.country) · \(selection.airport.icao)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        } header: { Text(query.isEmpty ? "Popular airports" : "Matches") }
                        footer: { Text("Search \(catalog.count) airports offline by name, city, IATA or ICAO code. KLIA T1 and KLIA T2 both use KUL; verify the terminal on your ticket. Showing up to 100 matches.") }
                        if matches.isEmpty { ContentUnavailableView.search(text: query) }
                        NavigationLink("Airport data & credits") { AirportDataCredits() }
                    }
                } else if error { ContentUnavailableView("Airport list unavailable", systemImage: "airplane", description: Text("You can still enter the airport manually in the flight form.")) }
                else { ProgressView("Loading airports…") }
            }
            .searchable(text: $query, prompt: "KUL, KLIA T2, Singapore, WMKK…")
            .navigationTitle("Choose airport").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { do { catalog = try await provider.load() } catch { self.error = true } }
        }
    }
}

private struct AirportDataCredits: View {
    private var license: String {
        guard let url = Bundle.main.url(forResource: "AirportData-LICENSE", withExtension: "txt") else { return "Airport reference data: mwgg/Airports, MIT License." }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? "mwgg/Airports, MIT License"
    }
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            Text("Airport reference data works offline. Names and time zones can change; confirm details and terminals against your ticket.")
            Link("mwgg/Airports source", destination: URL(string: "https://github.com/mwgg/Airports")!)
            Text(license).font(.footnote).textSelection(.enabled)
        }.padding() }.navigationTitle("Airport data")
    }
}
