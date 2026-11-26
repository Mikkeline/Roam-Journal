import Foundation

/// A point selected by the user, stored with the encrypted entry. No device-location tracking.
public struct SavedPlace: Codable, Equatable, Sendable {
    public var name: String
    public var address: String
    public var latitude: Double
    public var longitude: Double
    public init(name: String, address: String, latitude: Double, longitude: Double) {
        self.name = name; self.address = address; self.latitude = latitude; self.longitude = longitude
    }
    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && latitude.isFinite && longitude.isFinite
            && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
    public var mapsURL: URL? {
        guard isValid else { return nil }
        var parts = URLComponents()
        parts.scheme = "https"; parts.host = "maps.apple.com"; parts.path = "/"
        parts.queryItems = [URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"), URLQueryItem(name: "q", value: name)]
        return parts.url
    }
}
