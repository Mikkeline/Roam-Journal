import Foundation

actor ReferenceDataService {
    static let shared = ReferenceDataService()
    struct Snapshot: Codable, Sendable { var airports: [Airport]; var airlines: [Airline]; var date: Date }
    private var cache: Snapshot?
    private var updating = false
    private var savedURL: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ReferenceData.json") }
    func snapshot() throws -> Snapshot {
        if let cache { return cache }
        if let bytes = try? Data(contentsOf: savedURL), let saved = try? JSONDecoder().decode(Snapshot.self, from: bytes), valid(saved) { cache = saved; return saved }
        guard let a = Bundle.main.url(forResource: "AirportCatalog", withExtension: "json"), let b = Bundle.main.url(forResource: "AirlineCatalog", withExtension: "json") else { throw NotebookError.invalidContent }
        let value = Snapshot(airports: try JSONDecoder().decode([Airport].self, from: Data(contentsOf: a)), airlines: try JSONDecoder().decode([Airline].self, from: Data(contentsOf: b)), date: ISO8601DateFormatter().date(from: "2026-11-26T00:00:00Z")!)
        cache = value; return value
    }
    private func valid(_ value: Snapshot) -> Bool {
        value.airports.count >= 1000 && value.airports.count <= 50_000 && value.airlines.count >= 50 && value.airlines.count <= 10_000
        && Set(value.airports.map(\.icao)).count == value.airports.count
        && value.airports.allSatisfy { !$0.iata.isEmpty && TimeZone(identifier: $0.timeZoneID) != nil }
        && value.airlines.allSatisfy { !$0.airline.isEmpty && ($0.iata.count == 2 || $0.icao.count == 3) }
    }
    func update() async throws -> Date {
        guard !updating else { throw NotebookEditError.changed }; updating = true; defer { updating = false }
        let old = try snapshot()
        func download(_ path: String) async throws -> Data {
            let url = URL(string: "https://raw.githubusercontent.com/" + path)!
            var request = URLRequest(url: url); request.timeoutInterval = 30
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200, response.url?.host == "raw.githubusercontent.com", data.count <= 20_000_000 else { throw NotebookError.invalidContent }; return data
        }
        async let airportBytes = download("mwgg/Airports/master/airports.json")
        async let airlineBytes = download("AviationShop/airline-codes/main/airline-codes.json")
        struct RawAirport: Decodable { var icao: String; var iata: String; var name: String; var city: String; var country: String; var tz: String }
        let raw = try JSONDecoder().decode([String: RawAirport].self, from: await airportBytes)
        let airports = raw.values.filter { !$0.iata.isEmpty && TimeZone(identifier: $0.tz) != nil }.map { Airport(icao: $0.icao, iata: $0.iata, name: $0.name, city: $0.city, country: $0.country, timeZoneID: $0.tz) }
        var airlines = try JSONDecoder().decode([Airline].self, from: await airlineBytes)
        for local in old.airlines where ["D7", "OD", "FY", "3U"].contains(local.iata) && !airlines.contains(where: { $0.iata == local.iata }) { airlines.append(local) }
        let value = Snapshot(airports: airports, airlines: airlines, date: .now)
        guard valid(value) else { throw NotebookError.invalidContent }
        try FileManager.default.createDirectory(at: savedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: savedURL, options: .atomic); cache = value; return value.date
    }
}
