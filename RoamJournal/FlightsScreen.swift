import SwiftUI

struct FlightsScreen: View {
    @EnvironmentObject private var store: NotebookStore
    let tripID: UUID
    @State private var editing = false
    @State private var scanning = false
    private var trip: TravelTrip? { store.notebook.trips.first { $0.id == tripID } }
    var body: some View {
        List {
            if let trip {
                let flights = (trip.essentials ?? TripEssentials()).flights
                Section("Outbound") {
                    FlightCard(flight: flights.outbound)
                    ForEach(flights.outboundConnections) { FlightCard(flight: $0.details) }
                }
                Section("Return") {
                    FlightCard(flight: flights.returning)
                    ForEach(flights.returnConnections) { FlightCard(flight: $0.details) }
                }
                Section {
                    Text("Times use each airport’s selected time zone. Confirm schedules and terminals against your ticket; these details are entered manually.").font(.footnote).foregroundStyle(.secondary)
                    NavigationLink("Airline reference data") { AirlineReferenceCredits() }
                }
            }
        }.navigationTitle("Flights")
            .toolbar { Button("Scan ticket", systemImage: "doc.text.viewfinder") { scanning = true }; Button("Edit") { editing = true }.disabled(trip == nil) }
            .sheet(isPresented: $editing) { if let trip { FlightsEditor(trip: trip) } }
            .sheet(isPresented: $scanning) { TicketReviewScreen(tripID: tripID) }
    }
}
private struct FlightCard: View {
    let flight: FlightDetails
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(flight.number.isEmpty ? "Flight details not added" : flight.number).font(.headline)
            if !flight.airline.isEmpty { Text(flight.airline).foregroundStyle(.secondary) }
            if !flight.from.isEmpty || !flight.to.isEmpty { Text("\(flight.from.isEmpty ? "From airport" : flight.from) → \(flight.to.isEmpty ? "To airport" : flight.to)").font(.subheadline) }
            if let date = flight.departure { Label(FlightTime.label(date, zoneID: flight.departureTimeZoneID), systemImage: "airplane.departure") }
            if let terminal = flight.departureTerminal, !terminal.isEmpty { Text("Departure terminal · \(terminal)").font(.caption) }
            if let date = flight.arrival { Label(FlightTime.label(date, zoneID: flight.arrivalTimeZoneID), systemImage: "airplane.arrival") }
            if let terminal = flight.arrivalTerminal, !terminal.isEmpty { Text("Arrival terminal · \(terminal)").font(.caption) }
            if !flight.bookingReference.isEmpty { Text("Booking · \(flight.bookingReference)").font(.caption).textSelection(.enabled) }
        }.padding(.vertical, 6)
    }
}
enum FlightTime {
    static func label(_ date: Date, zoneID: String?) -> String {
        let zone = zoneID.flatMap(TimeZone.init(identifier:)) ?? .current
        let format = DateFormatter(); format.dateStyle = .medium; format.timeStyle = .short; format.timeZone = zone
        return format.string(from: date) + " · " + (zoneID ?? "Device time zone") + " (" + (zone.abbreviation(for: date) ?? zone.identifier) + ")"
    }
}
private struct FlightsEditor: View {
    @EnvironmentObject private var store: NotebookStore
    @Environment(\.dismiss) private var dismiss
    let trip: TravelTrip
    private let original: FlightItinerary
    @State private var draft: FlightItinerary
    @State private var discard = false
    @State private var error: String?
    init(trip: TravelTrip) {
        self.trip = trip; let value = (trip.essentials ?? TripEssentials()).flights
        original = value; _draft = State(initialValue: value)
    }
    private var dirty: Bool { draft != original }
    var body: some View {
        NavigationStack {
            Form {
                Section("Outbound flight") { FlightFields(flight: $draft.outbound, defaultDate: trip.startDate) }
                ForEach($draft.outboundConnections) { $leg in
                    Section("Outbound connection") {
                        FlightFields(flight: $leg.details, defaultDate: trip.startDate)
                        Button("Remove connection", role: .destructive) { draft.outboundConnections.removeAll { $0.id == leg.id } }
                    }
                }
                Section { Button("Add outbound connection", systemImage: "plus") { draft.outboundConnections.append(connection(after: draft.outboundConnections.last?.details ?? draft.outbound)) }.disabled(draft.outboundConnections.count >= 8) }
                Section("Return flight") { FlightFields(flight: $draft.returning, defaultDate: trip.endDate) }
                ForEach($draft.returnConnections) { $leg in
                    Section("Return connection") {
                        FlightFields(flight: $leg.details, defaultDate: trip.endDate)
                        Button("Remove connection", role: .destructive) { draft.returnConnections.removeAll { $0.id == leg.id } }
                    }
                }
                Section { Button("Add return connection", systemImage: "plus") { draft.returnConnections.append(connection(after: draft.returnConnections.last?.details ?? draft.returning)) }.disabled(draft.returnConnections.count >= 8) }
                if let message = draft.validationMessage { Section { Text(message).foregroundStyle(.red) } }
                Section { Text("Select airports to fill their time zones, or enter an airport manually. Changing a time zone preserves the instant and changes its displayed local time; check your ticket before saving.").font(.footnote).foregroundStyle(.secondary) }
            }.disabled(store.isSaving).scrollDismissesKeyboard(.interactively)
                .navigationTitle("Edit flights").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if dirty { discard = true } else { dismiss() } }.disabled(store.isSaving) }
                    ToolbarItem(placement: .confirmationAction) { Button(store.isSaving ? "Saving…" : "Save") {
                        Task { do { try await store.updateEssentials(.flights(draft, expected: original), tripID: trip.id); dismiss() } catch { self.error = error.localizedDescription } }
                    }.disabled(store.isSaving || !draft.isValid) }
                }
                .interactiveDismissDisabled(dirty || store.isSaving)
                .confirmationDialog("Discard flight changes?", isPresented: $discard, titleVisibility: .visible) { Button("Discard changes", role: .destructive) { dismiss() } }
                .alert("Flights weren’t saved", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        }
    }
    private func connection(after previous: FlightDetails) -> FlightLeg {
        var details = FlightDetails(); details.from = previous.to
        details.departureTimeZoneID = previous.arrivalTimeZoneID
        return FlightLeg(details: details)
    }
}
private struct FlightFields: View {
    @Binding var flight: FlightDetails
    let defaultDate: Date
    @State private var airportSide: FlightEndpoint?
    @State private var airlines: AirlineCatalog?
    @State private var airlineLookupFailed = false
    private let airlineProvider: any AirlineCatalogLoading
    init(flight: Binding<FlightDetails>, defaultDate: Date, airlineProvider: any AirlineCatalogLoading = BundledAirlineCatalog.shared) {
        _flight = flight; self.defaultDate = defaultDate; self.airlineProvider = airlineProvider
    }
    var body: some View {
        Group {
            TextField("Flight number (e.g. MH123)", text: $flight.number).textInputAutocapitalization(.characters).autocorrectionDisabled()
                .sheet(item: $airportSide) { side in AirportPicker { selection in flight.selectAirport(selection, at: side) } }
                .onChange(of: flight.number) { _, _ in if let airlines { flight.refreshAirline(using: airlines) } }
                .task {
                    do { let catalog = try await airlineProvider.load(); try Task.checkCancellation(); airlines = catalog; flight.refreshAirline(using: catalog) }
                    catch { airlineLookupFailed = true }
                }
            TextField("Airline", text: Binding(get: { flight.airline }, set: { flight.setAirlineManually($0) }))
            if let detected = airlines?.detect(flight.number) {
                if flight.airline != detected.airline {
                    Button("Use detected airline: \(detected.airline)") {
                        flight.airline = detected.airline; flight.automaticallyDetectedAirline = detected.airline
                    }
                }
                Text("Airline suggested from the flight-number prefix. A codeshare may be operated by another airline.").font(.caption).foregroundStyle(.secondary)
            } else if airlineLookupFailed {
                Text("Airline suggestions are unavailable. Enter the airline manually.").font(.caption).foregroundStyle(.secondary)
            } else if FlightNumber(flight.number) != nil {
                Text("No unique match in the offline airline list. Enter the airline manually.").font(.caption).foregroundStyle(.secondary)
            }
            airportButton("From airport", value: flight.from, side: .departure)
            TextField("Departure terminal (optional)", text: optional($flight.departureTerminal))
            airportButton("To airport", value: flight.to, side: .arrival)
            DisclosureGroup("Enter airports manually") {
                TextField("From airport / city", text: $flight.from)
                TextField("To airport / city", text: $flight.to)
            }
            TextField("Arrival terminal (optional)", text: optional($flight.arrivalTerminal))
            TextField("Booking reference (optional)", text: $flight.bookingReference).textInputAutocapitalization(.characters).autocorrectionDisabled()
            FlightDateFields(title: "Departure", date: $flight.departure, zoneID: $flight.departureTimeZoneID, defaultDate: defaultDate)
            FlightDateFields(title: "Arrival", date: $flight.arrival, zoneID: $flight.arrivalTimeZoneID, defaultDate: flight.departure ?? defaultDate)
        }
    }
    private func airportButton(_ title: String, value: String, side: FlightEndpoint) -> some View {
        Button { airportSide = side } label: {
            HStack(alignment: .top) {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Text(value.isEmpty ? "Choose airport" : value).multilineTextAlignment(.trailing)
                Image(systemName: "chevron.right").font(.caption).padding(.top, 4)
            }
        }
    }
    private func optional(_ value: Binding<String?>) -> Binding<String> { Binding(get: { value.wrappedValue ?? "" }, set: { value.wrappedValue = $0.isEmpty ? nil : $0 }) }
}
private struct FlightDateFields: View {
    let title: String
    @Binding var date: Date?
    @Binding var zoneID: String?
    let defaultDate: Date
    private var zone: TimeZone { zoneID.flatMap(TimeZone.init(identifier:)) ?? .current }
    var body: some View {
        Toggle("Add \(title.lowercased()) time", isOn: Binding(get: { date != nil }, set: { enabled in
            date = enabled ? defaultDate : nil
            if enabled, zoneID == nil { zoneID = TimeZone.current.identifier }
        }))
        if date != nil {
            NavigationLink { TimeZonePicker(selection: $zoneID) } label: { LabeledContent("\(title) time zone", value: zoneID ?? "Device: \(TimeZone.current.identifier)") }
            DatePicker(title, selection: Binding(get: { date ?? defaultDate }, set: { date = $0 })).environment(\.timeZone, zone)
        }
    }
}
private struct TimeZonePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String?
    @State private var query = ""
    var body: some View {
        List(TimeZone.knownTimeZoneIdentifiers.filter { query.isEmpty || $0.localizedStandardContains(query.replacingOccurrences(of: " ", with: "_")) }, id: \.self) { id in
            Button { selection = id; dismiss() } label: { HStack { Text(id.replacingOccurrences(of: "_", with: " ")); Spacer(); if selection == id { Image(systemName: "checkmark") } } }
        }.searchable(text: $query, prompt: "City or region").navigationTitle("Time zone")
    }
}

private struct AirlineReferenceCredits: View {
    private var license: String {
        guard let url = Bundle.main.url(forResource: "AirlineData-LICENSE", withExtension: "txt") else { return "AviationShop/airline-codes, CC0 1.0." }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? "AviationShop/airline-codes, CC0 1.0."
    }
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            Text("Suggestions use the bundled or verified updated airline reference list. Codes can change or be shared; unknown or ambiguous prefixes leave manual entry available. A flight-number prefix identifies the marketing airline, and may differ from the operating carrier shown on your ticket.")
            Text(license).font(.footnote).textSelection(.enabled)
        }.padding() }.navigationTitle("Airline reference")
    }
}
