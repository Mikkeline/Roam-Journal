import XCTest
import CryptoKit
@testable import LegacyRouteLab

final class RouteVaultTests: XCTestCase {
    let vault = RouteVault()
    func testEveryFixtureDecryptsToExpectedRoute() throws {
        let paths = ["/demo/v1/trails", "/demo/v1/conditions", "/demo/v1/saved"]
        for (route, path) in zip(DemoRoute.allCases, paths) {
            XCTAssertEqual(try vault.resolve(route), path)
            XCTAssertEqual(try vault.makeURL(origin: "https://trails.example", route: route).absoluteString, "https://trails.example" + path)
        }
    }
    func testEveryTamperedFixtureIsRejected() {
        for route in DemoRoute.allCases {
            XCTAssertThrowsError(try vault.resolve(route, tampered: true)) {
                XCTAssertEqual($0 as? VaultError, .authenticationFailed)
            }
        }
    }
    func testUntrustedAndMalformedOriginsAreRejected() {
        for origin in ["http://trails.example", "https://evil.example", "https://trails.example.evil.example", "https://user:pass@trails.example", "https://trails.example:443", "https://trails.example/x", "https://trails.example?x=1", "https://trails.example#x", "https://%74rails.example", "", "//trails.example"] {
            XCTAssertThrowsError(try vault.makeURL(origin: origin, route: .trails), origin)
        }
    }
    func testTrailingSlashOriginIsAccepted() throws {
        XCTAssertEqual(try vault.makeURL(origin: "https://trails.example/", route: .trails).path, "/demo/v1/trails")
    }
    func testWrongKeyAndTruncatedPayloadAreRejected() throws {
        let key = SymmetricKey(size: .bits256)
        let sealed = try AES.GCM.seal(Data("/demo/v1/trails".utf8), using: key).combined!
        XCTAssertThrowsError(try RouteVault.decrypt(sealed, using: SymmetricKey(size: .bits256)))
        XCTAssertThrowsError(try RouteVault.decrypt(Data(sealed.prefix(8)), using: key))
    }
    func testAuthenticatedButInvalidPathsAreRejected() throws {
        let key = SymmetricKey(size: .bits256)
        for path in ["//evil.example", "/demo/v1/../admin", "/demo/v1/trails?token=x", "/demo/v1/%2e%2e", "/demo/v1/", "/demo/v1/a//b", "/other/trails"] {
            let sealed = try AES.GCM.seal(Data(path.utf8), using: key).combined!
            XCTAssertThrowsError(try RouteVault.decrypt(sealed, using: key)) {
                XCTAssertEqual($0 as? VaultError, .invalidRoute)
            }
        }
    }
    func testMockSuccessAndEmptyState() async throws {
        let service = MockTrailService()
        let response = try await service.load(route: .saved, origin: "https://trails.example", tampered: false, simulateFailure: false)
        XCTAssertEqual(response.heading, "No adventures saved")
    }
    func testMockFailureIsRecoverable() async throws {
        let service = MockTrailService()
        do {
            _ = try await service.load(route: .trails, origin: "https://trails.example", tampered: false, simulateFailure: true)
            XCTFail("Expected simulated network failure")
        } catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
        let retry = try await service.load(route: .trails, origin: "https://trails.example", tampered: false, simulateFailure: false)
        XCTAssertEqual(retry.heading, "Pine Loop · 3.2 km")
    }
}
