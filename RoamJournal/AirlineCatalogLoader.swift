import Foundation

protocol AirlineCatalogLoading: Sendable { func load() async throws -> AirlineCatalog }
actor BundledAirlineCatalog: AirlineCatalogLoading {
    static let shared = BundledAirlineCatalog()
    func load() async throws -> AirlineCatalog { AirlineCatalog(airlines: try await ReferenceDataService.shared.snapshot().airlines) }
}
