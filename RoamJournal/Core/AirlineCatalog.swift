import Foundation

public struct Airline: Codable, Equatable, Sendable {
    public let iata: String
    public let icao: String
    public let airline: String
    public let country: String
}
public struct FlightNumber: Equatable, Sendable {
    public let airlineCode: String
    public let normalised: String
    public init?(_ text: String) {
        let value = text.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard let regex = try? NSRegularExpression(pattern: "^([A-Z0-9]{2}|[A-Z]{3})([0-9]{1,4})([A-Z]?)$"),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value) else { return nil }
        let code = String(value[range])
        guard code.contains(where: \.isLetter) else { return nil }
        airlineCode = code; normalised = value
    }
}
public struct AirlineCatalog: Sendable {
    private let airlines: [Airline]
    public init(airlines: [Airline]) { self.airlines = airlines }
    public func detect(_ number: String) -> Airline? {
        guard let parsed = FlightNumber(number) else { return nil }
        let matches = airlines.filter { parsed.airlineCode == $0.iata || parsed.airlineCode == $0.icao }
        // Reassigned or duplicate codes must not silently select one airline.
        guard matches.count == 1 else { return nil }
        return matches[0]
    }
}
extension FlightDetails {
    public mutating func refreshAirline(using catalog: AirlineCatalog) {
        let canFill = airline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (automaticallyDetectedAirline != nil && airline == automaticallyDetectedAirline)
        guard canFill else { return }
        let detected = catalog.detect(number)?.airline
        airline = detected ?? ""; automaticallyDetectedAirline = detected
    }
    public mutating func setAirlineManually(_ name: String) { airline = name; automaticallyDetectedAirline = nil }
}
