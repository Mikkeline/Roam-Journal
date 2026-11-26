import SwiftUI

/// Navigation hub only; each feature owns its view and editing lifecycle.
struct TripEssentialsEditor: View {
    @EnvironmentObject private var store: NotebookStore
    @Environment(\.dismiss) private var dismiss
    let trip: TravelTrip
    private var current: TravelTrip? { store.notebook.trips.first { $0.id == trip.id } }
    private var canRemainOpen: Bool { store.tripAccess.allows(trip.id) || store.protectedTripID == trip.id }
    var body: some View {
        NavigationStack {
            List {
                if let current {
                    Section {
                        NavigationLink { FlightsScreen(tripID: trip.id) } label: { Label("Flights", systemImage: "airplane") }
                        NavigationLink { PackingScreen(tripID: trip.id) } label: {
                            HStack { Label("Packing checklist", systemImage: "checklist"); Spacer(); Text("\(current.essentials?.packing.filter(\.packed).count ?? 0)/\(current.essentials?.packing.count ?? 0)").foregroundStyle(.secondary) }
                        }
                        NavigationLink { TravelDocumentsScreen(tripID: trip.id) } label: {
                            HStack { Label("Travel documents", systemImage: "doc.text"); Spacer(); Text("\(current.essentials?.documents.count ?? 0)").foregroundStyle(.secondary) }
                        }
                    } footer: { Text("Flights and document edits use Save. Packing changes save immediately. Everything stays inside your locked trip.") }
                } else { ContentUnavailableView("Trip unavailable", systemImage: "suitcase") }
            }.navigationTitle("Travel essentials").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(JournalPalette.accent)
            .onChange(of: canRemainOpen) { _, allowed in if !allowed { dismiss() } }
    }
}
