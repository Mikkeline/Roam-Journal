import XCTest
@testable import TrailCore

final class AirlineDetectionTests: XCTestCase {
    private func catalog() throws -> AirlineCatalog {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("RoamJournal/Resources/AirlineCatalog.json"))
        return AirlineCatalog(airlines: try JSONDecoder().decode([Airline].self, from: data))
    }
    func testCommonFlightNumbersAndICAOCodes() throws {
        let catalog = try catalog()
        for (number, expected) in [("MU8642", "China Eastern Airlines"), ("mh 123", "Malaysia Airlines"), ("AK-123", "AirAsia"), ("D7505", "AirAsia X"), ("OD123", "Batik Air Malaysia"), ("FY1234", "Firefly"), ("CES8642", "China Eastern Airlines"), ("6E123", "IndiGo"), ("3U8888", "Sichuan Airlines")] {
            XCTAssertEqual(catalog.detect(number)?.airline, expected, number)
        }
    }
    func testInvalidAndUnknownNumbersDoNotGuess() throws {
        let catalog = try catalog()
        for number in ["", "MU", "12345", "M123", "MU12345", "MU123/AK456", "MU123<script>", "ZZ999"] { XCTAssertNil(catalog.detect(number), number) }
        XCTAssertEqual(FlightNumber(" mu-8642a ")?.normalised, "MU8642A")
    }
    func testDuplicateAirlineCodesAreNotGuessed() throws {
        let data = Data(#"[{"iata":"MU","icao":"CES","airline":"One","country":"CN"},{"iata":"MU","icao":"OTH","airline":"Two","country":"CN"}]"#.utf8)
        let catalog = AirlineCatalog(airlines: try JSONDecoder().decode([Airline].self, from: data))
        XCTAssertNil(catalog.detect("MU123"))
    }
    func testAutomaticAirlineUpdatesWithNumberAndClearsWhenUnknown() throws {
        let catalog = try catalog(); var flight = FlightDetails()
        flight.number = "MU8642"; flight.refreshAirline(using: catalog)
        XCTAssertEqual(flight.airline, "China Eastern Airlines")
        flight.number = "MH123"; flight.refreshAirline(using: catalog)
        XCTAssertEqual(flight.airline, "Malaysia Airlines")
        flight.number = "ZZ123"; flight.refreshAirline(using: catalog)
        XCTAssertEqual(flight.airline, ""); XCTAssertNil(flight.automaticallyDetectedAirline)
    }
    func testManualOverrideSurvivesNumberChange() throws {
        let catalog = try catalog(); var flight = FlightDetails()
        flight.number = "MU8642"; flight.refreshAirline(using: catalog)
        flight.setAirlineManually("Operating carrier from ticket")
        flight.number = "MH123"; flight.refreshAirline(using: catalog)
        XCTAssertEqual(flight.airline, "Operating carrier from ticket")
        XCTAssertNil(flight.automaticallyDetectedAirline)
    }
    func testExistingManualAirlineIsNeverOverwritten() throws {
        let catalog = try catalog(); var flight = FlightDetails(); flight.airline = "China Eastern Airlines"; flight.number = "MH123"
        flight.refreshAirline(using: catalog)
        XCTAssertEqual(flight.airline, "China Eastern Airlines")
    }
    func testDetectionProvenanceSurvivesSaveAndOlderRecordsDecode() throws {
        var flight = FlightDetails(); flight.number = "MU8642"; try flight.refreshAirline(using: catalog())
        let restored = try JSONDecoder().decode(FlightDetails.self, from: JSONEncoder().encode(flight))
        XCTAssertEqual(restored, flight)
        let legacy = Data(#"{"number":"MU8642","airline":"Manual","from":"KUL","to":"PVG","bookingReference":""}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(FlightDetails.self, from: legacy).automaticallyDetectedAirline)
    }
}
