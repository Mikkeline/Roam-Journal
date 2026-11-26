import XCTest
@testable import TrailCore

final class EssentialsWorkflowTests: XCTestCase {
    private func airports() throws -> [Airport] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try JSONDecoder().decode([Airport].self, from: Data(contentsOf: root.appendingPathComponent("RoamJournal/Resources/AirportCatalog.json")))
    }
    private func fixture() -> TravelTrip {
        var trip = TravelTrip(destination: "Holiday", entries: [TravelEntry(title: "Keep me")]); trip.essentials = TripEssentials()
        trip.essentials?.packing = [PackingItem(title: "Passport")]
        trip.essentials?.documents = [TripDocument(name: "booking.txt", type: "text", data: Data("booking".utf8))]
        return trip
    }
    func testCatalogIncludesGlobalCodesAndValidTimeZones() throws {
        let records = try airports()
        XCTAssertGreaterThan(records.count, 7000)
        XCTAssertEqual(Set(records.map(\.icao)).count, records.count)
        XCTAssertTrue(records.allSatisfy { TimeZone(identifier: $0.timeZoneID) != nil })
        for code in ["KUL", "PEN", "SIN", "PVG", "KMG", "LHR", "JFK"] {
            let airport = try XCTUnwrap(records.first { $0.iata == code })
            XCTAssertNotNil(TimeZone(identifier: airport.timeZoneID), code)
        }
    }
    func testKLIAAliasesResolveAirportAndTerminal() throws {
        let catalog = AirportCatalog(airports: try airports())
        for (query, terminal) in [("KLIA T1", "1"), ("klia1", "1"), ("KLIA T2", "2"), ("KLIA2", "2"), ("KUL T2", "2"), ("K.L.I.A. T 2", "2")] {
            let result = try XCTUnwrap(catalog.search(query).first, query)
            XCTAssertEqual(result.airport.iata, "KUL", query); XCTAssertEqual(result.terminal, terminal, query)
        }
        XCTAssertEqual(catalog.search("WMKK").first?.airport.iata, "KUL")
        XCTAssertTrue(catalog.search("PVG Shanghai").contains { $0.airport.iata == "PVG" })
        XCTAssertTrue(catalog.search("Singapore").contains { $0.airport.iata == "SIN" })
        XCTAssertTrue(catalog.search("not-a-real-airport-xyz").isEmpty)
    }
    func testAirportSelectionFillsTimeZoneAndClearsOldTerminal() throws {
        let catalog = AirportCatalog(airports: try airports())
        var flight = FlightDetails(); let instant = Date(timeIntervalSince1970: 1_800_000_000); flight.departure = instant
        flight.selectAirport(try XCTUnwrap(catalog.search("KLIA2").first), at: .departure)
        XCTAssertTrue(flight.from.contains("KUL")); XCTAssertEqual(flight.departureTerminal, "2")
        XCTAssertEqual(flight.departureTimeZoneID, "Asia/Kuala_Lumpur"); XCTAssertEqual(flight.departure, instant)
        flight.selectAirport(try XCTUnwrap(catalog.search("LHR").first), at: .departure)
        XCTAssertNil(flight.departureTerminal); XCTAssertEqual(flight.departureTimeZoneID, "Europe/London")
        flight.selectAirport(try XCTUnwrap(catalog.search("KLIA T1").first), at: .arrival)
        XCTAssertEqual(flight.arrivalTerminal, "1"); XCTAssertEqual(flight.arrivalTimeZoneID, "Asia/Kuala_Lumpur")
    }
    func testOlderFlightAndEssentialsDecodeWithoutNewFields() throws {
        let json = Data(#"{"number":"MU8642","airline":"China Eastern","from":"KL","to":"Shanghai","bookingReference":"ABC"}"#.utf8)
        let flight = try JSONDecoder().decode(FlightDetails.self, from: json)
        XCTAssertNil(flight.arrival); XCTAssertNil(flight.departureTimeZoneID)
        let source = try JSONEncoder().encode(TripEssentials())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: source) as? [String: Any])
        object.removeValue(forKey: "outboundConnections"); object.removeValue(forKey: "returnConnections")
        let restored = try JSONDecoder().decode(TripEssentials.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(restored.flights.isValid); XCTAssertTrue(restored.flights.outboundConnections.isEmpty)
    }
    func testArrivalValidationUsesAbsoluteTimeAcrossDateLine() throws {
        var value = TripEssentials()
        let iso = ISO8601DateFormatter()
        value.outbound.departure = iso.date(from: "2026-11-26T23:00:00+09:00")
        value.outbound.arrival = iso.date(from: "2026-11-26T17:00:00-08:00")
        value.outbound.departureTimeZoneID = "Asia/Tokyo"; value.outbound.arrivalTimeZoneID = "America/Los_Angeles"
        XCTAssertTrue(value.isValid)
        value.outbound.arrival = iso.date(from: "2026-11-26T10:00:00Z")
        XCTAssertFalse(value.isValid)
        value.outbound.arrival = nil; value.outbound.arrivalTimeZoneID = "Invalid/Zone"
        XCTAssertFalse(value.isValid)
    }
    func testConnectionsValidateSequenceAndRoundTrip() throws {
        var trip = fixture(); let date = Date(timeIntervalSince1970: 1_800_000_000)
        trip.essentials?.outbound.departure = date; trip.essentials?.outbound.arrival = date.addingTimeInterval(3600)
        var connection = FlightDetails(); connection.number = "MH456"; connection.departure = date.addingTimeInterval(7200); connection.arrival = date.addingTimeInterval(10800)
        trip.essentials?.outboundConnections = [FlightLeg(details: connection)]
        let book = TravelNotebook(trips: [trip]); _ = try book.validated()
        XCTAssertEqual(try JSONDecoder().decode(TravelNotebook.self, from: JSONEncoder().encode(book)), book)
        trip.essentials?.outboundConnections?[0].details.departure = date
        XCTAssertThrowsError(try TravelNotebook(trips: [trip]).validated())
    }
    func testFlightSavePreservesIndependentPackingAndDocuments() throws {
        let trip = fixture(); let original = try XCTUnwrap(trip.essentials?.flights)
        let packedID = try XCTUnwrap(trip.essentials?.packing.first?.id)
        let current = try TravelNotebook(trips: [trip]).changingEssentials(.setPacked(packedID, true), tripID: trip.id)
        var edited = original; edited.outbound.number = "MH123"
        let saved = try current.changingEssentials(.flights(edited, expected: original), tripID: trip.id)
        XCTAssertTrue(saved.trips[0].essentials?.packing[0].packed == true)
        XCTAssertEqual(saved.trips[0].essentials?.documents, trip.essentials?.documents)
        XCTAssertEqual(saved.trips[0].entries, trip.entries)
        XCTAssertThrowsError(try saved.changingEssentials(.flights(original, expected: original), tripID: trip.id))
    }
    func testDocumentsSavePreservesFlightEditsAndRejectsStaleDocuments() throws {
        let trip = fixture(); let old = try XCTUnwrap(trip.essentials)
        var flights = old.flights; flights.returning.number = "MU1234"
        let current = try TravelNotebook(trips: [trip]).changingEssentials(.flights(flights, expected: old.flights), tripID: trip.id)
        let saved = try current.changingEssentials(.documents([], expected: old.documents), tripID: trip.id)
        XCTAssertEqual(saved.trips[0].essentials?.returning.number, "MU1234")
        XCTAssertThrowsError(try saved.changingEssentials(.documents(old.documents, expected: old.documents), tripID: trip.id))
    }
    func testPackingCommandsPreserveTicksDeduplicateAndDoNotResurrect() throws {
        let trip = fixture(); let id = try XCTUnwrap(trip.essentials?.packing[0].id)
        var book = try TravelNotebook(trips: [trip]).changingEssentials(.setPacked(id, true), tripID: trip.id)
        book = try book.changingEssentials(.addPacking([" passport ", "Charger", "", "CHARGER"]), tripID: trip.id)
        XCTAssertEqual(book.trips[0].essentials?.packing.count, 2)
        XCTAssertTrue(book.trips[0].essentials?.packing[0].packed == true)
        XCTAssertFalse(book.trips[0].essentials?.packing[1].packed ?? true)
        book = try book.changingEssentials(.renamePacking(id, "ID", expected: "Passport"), tripID: trip.id)
        XCTAssertThrowsError(try book.changingEssentials(.renamePacking(id, "Old draft", expected: "Passport"), tripID: trip.id))
        book = try book.changingEssentials(.removePacking(id), tripID: trip.id)
        XCTAssertThrowsError(try book.changingEssentials(.setPacked(id, false), tripID: trip.id))
    }
    func testPackingTemplatesIncludedInEncryptedBackup() throws {
        var book = TravelNotebook(trips: [fixture()]); book.packingTemplates = [PackingTemplate(name: "Hiking", items: ["Shoes", "Water"])]
        let code = NotebookBackup.recoveryCode()
        let restored = try NotebookBackup.open(NotebookBackup.seal(book, code: code), code: code)
        XCTAssertEqual(restored.packingTemplates, book.packingTemplates)
        book.packingTemplates = [PackingTemplate(name: "", items: ["Item"])]
        XCTAssertThrowsError(try book.validated())
    }
}
