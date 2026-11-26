import Foundation

public struct Airport: Codable, Equatable, Sendable, Identifiable {
    public var icao: String
    public var iata: String
    public var name: String
    public var city: String
    public var country: String
    public var timeZoneID: String
    public var id: String { icao }
}
public struct AirportSelection: Identifiable, Equatable, Sendable {
    public let airport: Airport
    public let terminal: String?
    public var id: String { airport.icao + (terminal ?? "") }
    public var label: String { "\(airport.iata) · \(airport.name)" + (terminal.map { " · Terminal \($0)" } ?? "") }
}
public struct AirportCatalog: Sendable {
    private struct Indexed: Sendable { let choice: AirportSelection; let text: String; let aliases: [String] }
    private let indexed: [Indexed]
    public let count: Int
    public init(airports: [Airport]) {
        count = airports.count
        indexed = airports.flatMap { airport -> [Indexed] in
            let normal = Indexed(choice: AirportSelection(airport: airport, terminal: nil), text: Self.normalise("\(airport.iata) \(airport.icao) \(airport.name) \(airport.city) \(airport.country)"), aliases: airport.iata == "KUL" ? ["klia", "kualalumpur"] : [])
            guard airport.iata == "KUL" else { return [normal] }
            return [normal] + ["1", "2"].map { terminal in
                Indexed(choice: AirportSelection(airport: airport, terminal: terminal), text: normal.text + "terminal" + terminal, aliases: ["klia" + terminal, "kliat" + terminal, "kliaterminal" + terminal, "kult" + terminal, "kulterminal" + terminal, "kualalumpurinternationalairportterminal" + terminal, "kualalumpurterminal" + terminal])
            }
        }
    }
    public func search(_ query: String, limit: Int = 100) -> [AirportSelection] {
        let term = Self.normalise(query)
        let tokens = query.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { Self.normalise(String($0)) }
        let matches = indexed.filter { item in
            term.isEmpty || item.text.contains(term) || item.aliases.contains(where: { $0.contains(term) })
            || (!tokens.isEmpty && tokens.allSatisfy { token in item.text.contains(token) || item.aliases.contains(where: { $0.contains(token) }) })
        }
        let featured = ["KUL", "SZB", "PEN", "LGK", "JHB", "BKI", "KCH", "SIN", "BKK", "HKG", "PVG", "SHA", "KMG", "NRT", "ICN", "LHR"]
        return matches.sorted { a, b in
            func rank(_ item: Indexed) -> Int {
                if !term.isEmpty {
                    if item.aliases.contains(term) { return 0 }
                    if Self.normalise(item.choice.airport.iata) == term || Self.normalise(item.choice.airport.icao) == term { return 1 }
                    return 100
                }
                return featured.firstIndex(of: item.choice.airport.iata).map { $0 + 2 } ?? 100
            }
            let left = rank(a), right = rank(b)
            if left != right { return left < right }
            if a.choice.airport.name != b.choice.airport.name { return a.choice.airport.name < b.choice.airport.name }
            return a.choice.id < b.choice.id
        }.prefix(max(0, limit)).map(\.choice)
    }
    private static func normalise(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).filter(\.isLetterOrNumber)
    }
}
private extension Character { var isLetterOrNumber: Bool { isLetter || isNumber } }

public enum FlightEndpoint: String, Identifiable, Sendable { case departure, arrival; public var id: String { rawValue } }
extension FlightDetails {
    public mutating func selectAirport(_ selection: AirportSelection, at endpoint: FlightEndpoint) {
        let text = "\(selection.airport.iata) · \(selection.airport.name)"
        switch endpoint {
        case .departure: from = text; departureTerminal = selection.terminal; departureTimeZoneID = selection.airport.timeZoneID
        case .arrival: to = text; arrivalTerminal = selection.terminal; arrivalTimeZoneID = selection.airport.timeZoneID
        }
    }
}
