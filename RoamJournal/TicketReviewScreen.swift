import SwiftUI
import UniformTypeIdentifiers

struct TicketReviewScreen: View {
    @EnvironmentObject private var store: NotebookStore
    @Environment(\.scenePhase) private var phase
    @Environment(\.dismiss) private var dismiss
    let tripID: UUID
    var recognizer: any TicketRecognizing = OnDeviceTicketRecognizer()
    @State private var importing = false
    @State private var busy = false
    @State private var text = ""
    @State private var candidates: TicketCandidates?
    @State private var number = ""
    @State private var bookingReference = ""
    @State private var from = ""
    @State private var to = ""
    @State private var departing = ""
    @State private var arriving = ""
    @State private var returning = false
    @State private var error: String?
    @State private var confirm = false
    @State private var airlines: AirlineCatalog?
    @State private var airports: AirportCatalog?
    @State private var task: Task<Void, Never>?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Choose ticket PDF or image", systemImage: "doc.text.viewfinder") { importing = true }
                    if busy { ProgressView("Reading on this device…") }
                } footer: { Text("No ticket is uploaded. Reads up to 10 PDF pages. Review every value; ambiguous dates and times require manual entry. Importing here does not attach the original document.") }
                if let candidates {
                    Section("Review extracted details") {
                        Toggle("Use for return flight", isOn: $returning)
                        TextField("Flight number", text: $number).textInputAutocapitalization(.characters)
                        TextField("Booking reference (optional)", text: $bookingReference)
                        ForEach(candidates.flightNumbers, id: \.self) { value in Button(value) { number = value } }
                        Picker("From airport", selection: $from) { Text("Leave unchanged").tag(""); ForEach(candidates.airportCodes, id: \.self) { Text($0).tag($0) } }
                        Picker("To airport", selection: $to) { Text("Leave unchanged").tag(""); ForEach(candidates.airportCodes, id: \.self) { Text($0).tag($0) } }
                        Picker("Departure (airport local time)", selection: $departing) { Text("Leave unchanged").tag(""); ForEach(candidates.dateTimes) { Text($0.raw).tag($0.raw) } }
                        Picker("Arrival (airport local time)", selection: $arriving) { Text("Leave unchanged").tag(""); ForEach(candidates.dateTimes) { Text($0.raw).tag($0.raw) } }
                        Button("Review and apply to flight") { confirm = true }.disabled(FlightNumber(number) == nil)
                    }
                    Section("Recognized text") { Text(text).textSelection(.enabled).font(.footnote) }
                }
            }.disabled(busy || store.isSaving).navigationTitle("Scan ticket").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { dismiss() } }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image]) { result in
                    switch result { case .success(let url): read(url); case .failure(let error): self.error = error.localizedDescription }
                }
                .confirmationDialog("Replace the selected flight fields?", isPresented: $confirm, titleVisibility: .visible) { Button("Apply reviewed details") { apply() } } message: { Text("Applies to the first outbound or return flight. Connections and unselected fields are kept. Check the ticket before confirming.") }
                .alert("Ticket needs attention", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
                .onDisappear { task?.cancel() }
                .onChange(of: phase) { _, value in
                    if value == .background { task?.cancel(); text = ""; candidates = nil; number = ""; bookingReference = ""; confirm = false }
                }
        }
    }
    private func read(_ url: URL) {
        busy = true
        task = Task { @MainActor in
            defer { busy = false }
            do {
                let document = try await TravelDocumentImporter().read(url)
                let result = try await recognizer.text(in: document)
                let airlines = try await BundledAirlineCatalog.shared.load(); let airports = try await BundledAirportCatalog.shared.load()
                try Task.checkCancellation()
                self.airlines = airlines; self.airports = airports; text = result
                let parsed = TicketParser.parse(result, airlines: airlines, airports: airports)
                candidates = parsed; number = parsed.flightNumbers.first ?? ""; bookingReference = parsed.bookingReference ?? ""; from = ""; to = ""; departing = ""; arriving = ""
                if result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { error = "No readable text found. Try a sharper image or enter flight details manually." }
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
    private func apply() {
        guard let trip = store.notebook.trips.first(where: { $0.id == tripID }), let airlines, let airports else { return }
        let original = (trip.essentials ?? TripEssentials()).flights; var updated = original
        var flight = returning ? original.returning : original.outbound
        flight.number = number; flight.refreshAirline(using: airlines)
        if let airport = airports.search(from).first(where: { $0.airport.iata == from }) { flight.selectAirport(airport, at: .departure) }
        if let airport = airports.search(to).first(where: { $0.airport.iata == to }) { flight.selectAirport(airport, at: .arrival) }
        if let value = candidates?.dateTimes.first(where: { $0.raw == departing }) { guard let zone = flight.departureTimeZoneID.flatMap(TimeZone.init(identifier:)), let date = value.date(in: zone) else { error = "Choose a departure airport with a time zone and verify its local date/time."; return }; flight.departure = date }
        if let value = candidates?.dateTimes.first(where: { $0.raw == arriving }) { guard let zone = flight.arrivalTimeZoneID.flatMap(TimeZone.init(identifier:)), let date = value.date(in: zone) else { error = "Choose an arrival airport with a time zone and verify its local date/time."; return }; flight.arrival = date }
        if !bookingReference.isEmpty { flight.bookingReference = bookingReference }
        if returning { updated.returning = flight } else { updated.outbound = flight }
        guard updated.isValid else { error = updated.validationMessage; return }
        Task { do { try await store.updateEssentials(.flights(updated, expected: original), tripID: tripID); dismiss() } catch { self.error = error.localizedDescription } }
    }
}
