import Foundation

public struct TicketDateTime: Equatable, Sendable, Identifiable {
    public let raw: String
    public let components: DateComponents
    public var id: String { raw }
    public func date(in timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        guard let date = calendar.date(from: components) else { return nil }
        let check = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard check.year == components.year, check.month == components.month, check.day == components.day, check.hour == components.hour, check.minute == components.minute else { return nil }; return date
    }
}
public struct TicketCandidates: Sendable {
    public let flightNumbers: [String]
    public let airportCodes: [String]
    public let dateTimes: [TicketDateTime]
    public let bookingReference: String?
}
public enum TicketParser {
    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }
    public static func parse(_ text: String, airlines: AirlineCatalog, airports: AirportCatalog) -> TicketCandidates {
        let text = String(text.prefix(200_000)).uppercased()
        func unique(_ values: [String]) -> [String] { var seen = Set<String>(); return values.filter { seen.insert($0).inserted } }
        let flights = unique(matches("\\b[A-Z0-9]{2,3}[ -]?[0-9]{1,4}[A-Z]?\\b", in: text).compactMap { value in airlines.detect(value) == nil ? nil : FlightNumber(value)?.normalised })
        let codes = unique(matches("\\b[A-Z]{3}\\b", in: text).filter { code in airports.search(code).contains { $0.airport.iata == code } })
        let rawDates = unique(matches("\\b[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}\\b|\\b[0-9]{1,2} [A-Z]{3} [0-9]{4} [0-9]{2}:[0-9]{2}\\b", in: text))
        let dates = rawDates.compactMap { raw -> TicketDateTime? in
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.isLenient = false
            formatter.dateFormat = raw.contains("-") ? "yyyy-MM-dd HH:mm" : "d MMM yyyy HH:mm"
            guard let date = formatter.date(from: (raw.contains("-") ? raw.replacingOccurrences(of: "T", with: " ") : raw)) else { return nil }
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            return TicketDateTime(raw: raw, components: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date))
        }
        let pnr = matches("(?:PNR|BOOKING REFERENCE|RESERVATION CODE)[: #]+[A-Z0-9]{5,8}\\b", in: text).first?.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).last.map(String.init)
        return TicketCandidates(flightNumbers: flights, airportCodes: codes, dateTimes: dates, bookingReference: pnr)
    }
}
