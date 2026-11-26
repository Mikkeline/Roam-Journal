import Foundation
import CryptoKit
#if canImport(NativeCatalog)
import NativeCatalog
#endif

public enum DemoRoute: Int32, CaseIterable, Sendable {
    case trails, conditions, saved
    public var title: String {
        switch self {
        case .trails: "Discover trails"
        case .conditions: "Trail conditions"
        case .saved: "Saved adventures"
        }
    }
}

public enum VaultError: Error, LocalizedError, Equatable {
    case missingPayload, authenticationFailed, invalidRoute, invalidOrigin
    public var errorDescription: String? {
        switch self {
        case .missingPayload: "The demo route is unavailable."
        case .authenticationFailed: "Integrity check failed. The modified route was blocked."
        case .invalidRoute: "The route format was rejected."
        case .invalidOrigin: "Use https://trails.example with no path, credentials, query, or port."
        }
    }
}

public struct RouteVault: Sendable {
    public init() {}

    public func resolve(_ route: DemoRoute, tampered: Bool = false) throws -> String {
        var count = 0
        guard let pointer = trail_catalog_payload(route.rawValue, &count), count > 0 else {
            throw VaultError.missingPayload
        }
        var sealed = Data(bytes: pointer, count: count)
        if tampered { sealed[sealed.count - 1] ^= 0x01 }
        var keyCount = 0
        guard let keyPointer = trail_catalog_key(&keyCount), keyCount == 32 else {
            throw VaultError.missingPayload
        }
        let key = SymmetricKey(data: Data(bytes: keyPointer, count: keyCount))
        return try Self.decrypt(sealed, using: key)
    }

    // Internal seam used to test authentication failures without exporting real data.
    static func decrypt(_ sealed: Data, using key: SymmetricKey) throws -> String {
        let plaintext: Data
        do {
            plaintext = try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key)
        } catch { throw VaultError.authenticationFailed }
        guard let path = String(data: plaintext, encoding: .utf8),
              path.hasPrefix("/demo/v1/"),
              path.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 47 || $0 == 45 }),
              !path.contains("//"), !path.hasSuffix("/") else {
            throw VaultError.invalidRoute
        }
        return path
    }

    public func makeURL(origin: String, route: DemoRoute, tampered: Bool = false) throws -> URL {
        guard var parts = URLComponents(string: origin),
              parts.scheme == "https", parts.host == "trails.example",
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.query == nil, parts.fragment == nil, parts.percentEncodedHost == "trails.example",
              parts.path.isEmpty || parts.path == "/" else { throw VaultError.invalidOrigin }
        parts.path = try resolve(route, tampered: tampered)
        guard let url = parts.url else { throw VaultError.invalidOrigin }
        return url
    }
}

public struct DemoResponse: Sendable {
    public let heading: String
    public let detail: String
    public let url: URL
}

// No URLSession or networking code. The reserved .example host is display-only.
public struct MockTrailService: Sendable {
    public init() {}
    public func load(route: DemoRoute, origin: String, tampered: Bool, simulateFailure: Bool) async throws -> DemoResponse {
        let url = try RouteVault().makeURL(origin: origin, route: route, tampered: tampered)
        try await Task.sleep(for: .milliseconds(450))
        if simulateFailure { throw URLError(.notConnectedToInternet) }
        switch route {
        case .trails:
            return DemoResponse(heading: "Pine Loop · 3.2 km", detail: "A fictional easy woodland route. Estimated walking time: 55 minutes.", url: url)
        case .conditions:
            return DemoResponse(heading: "Clear skies · 22°C", detail: "Fictional conditions for demonstration. Never use this data for outdoor decisions.", url: url)
        case .saved:
            return DemoResponse(heading: "No adventures saved", detail: "This is the sample empty state. Discover trails to plan your next walk.", url: url)
        }
    }
}
