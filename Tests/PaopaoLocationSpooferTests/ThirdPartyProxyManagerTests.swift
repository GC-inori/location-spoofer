import XCTest
@testable import PaopaoLocationSpoofer

@MainActor
final class ThirdPartyProxyManagerTests: XCTestCase {
    func testQueryDistinguishesConnectedWithoutCoordinate() async throws {
        let requester = FakeThirdPartyRequester(body: #"{"success":false,"error":"无已保存的坐标"}"#)
        let manager = ThirdPartyProxyManager(requester: requester)

        let response = try await manager.query()

        XCTAssertFalse(response.success)
        XCTAssertEqual(manager.connectionState, .connected(active: false))
        XCTAssertEqual(requester.lastURL?.query, "action=query")
    }

    func testSaveUsesFavoriteWGS84AndAcceptsMatchingResponse() async throws {
        let favorite = FavoriteLocation(
            name: "深圳湾",
            latitude: 22.494,
            longitude: 113.951,
            accuracy: 20,
            mapCoordinateSystem: .gcj02
        )
        let wgs84 = favorite.coordinatePair.wgs84
        let body = String(format: #"{"success":true,"longitude":%.8f,"latitude":%.8f,"accuracy":20}"#,
                          locale: Locale(identifier: "en_US_POSIX"), wgs84.longitude, wgs84.latitude)
        let requester = FakeThirdPartyRequester(body: body)
        let manager = ThirdPartyProxyManager(requester: requester)

        _ = try await manager.save(favorite)

        let components = URLComponents(url: try XCTUnwrap(requester.lastURL), resolvingAgainstBaseURL: false)
        let values = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        let latitude = try XCTUnwrap(Double(values["lat"] ?? ""))
        let longitude = try XCTUnwrap(Double(values["lon"] ?? ""))
        XCTAssertEqual(latitude, wgs84.latitude, accuracy: 0.000_000_01)
        XCTAssertEqual(longitude, wgs84.longitude, accuracy: 0.000_000_01)
        XCTAssertEqual(values["acc"], "20")
        XCTAssertEqual(manager.connectionState, .connected(active: true))
    }

    func testSaveRejectsCoordinateMismatchWithoutMarkingActive() async {
        let requester = FakeThirdPartyRequester(body: #"{"success":true,"longitude":1,"latitude":2,"accuracy":25}"#)
        let manager = ThirdPartyProxyManager(requester: requester)
        let favorite = FavoriteLocation(name: "深圳湾", latitude: 22.494, longitude: 113.951, accuracy: 25)

        do {
            _ = try await manager.save(favorite)
            XCTFail("expected coordinate mismatch")
        } catch {
            XCTAssertEqual(error as? ThirdPartyProxyError, .coordinateMismatch)
        }
        XCTAssertEqual(manager.connectionState, .unknown)
        XCTAssertNil(manager.activeSettings)
    }

    func testMalformedResponseIsNotTreatedAsSuccess() async {
        let manager = ThirdPartyProxyManager(requester: FakeThirdPartyRequester(body: "not-json"))
        do {
            _ = try await manager.query()
            XCTFail("expected interception failure")
        } catch {
            XCTAssertEqual(error as? ThirdPartyProxyError, .moduleNotIntercepted)
        }
    }

    func testClientLinksUseOfficialUpstreamModulesAndVerificationLabels() {
        XCTAssertEqual(ThirdPartyProxyClient.shadowrocket.verificationText, "当前可测试")
        XCTAssertTrue(ThirdPartyProxyClient.surge.verificationText.contains("尚未验证"))
        XCTAssertEqual(ThirdPartyProxyClient.egern.subscriptionURL, ThirdPartyProxyClient.surge.subscriptionURL)
        XCTAssertTrue(ThirdPartyProxyClient.stash.subscriptionURL.absoluteString.hasSuffix("/modules/wloc.stoverride"))
        XCTAssertTrue(ThirdPartyProxyClient.shadowrocket.subscriptionURL.absoluteString.hasSuffix("/modules/wloc.module"))
        XCTAssertEqual(ThirdPartyProxyClient.shadowrocket.launchURL?.scheme, "shadowrocket")
        XCTAssertEqual(ThirdPartyProxyClient.surge.launchURL?.scheme, "surge")
        XCTAssertEqual(ThirdPartyProxyClient.quantumultX.launchURL?.scheme, "quantumult-x")
        XCTAssertEqual(ThirdPartyProxyClient.loon.launchURL?.scheme, "loon")
        XCTAssertEqual(ThirdPartyProxyClient.stash.launchURL?.scheme, "stash")
        XCTAssertEqual(ThirdPartyProxyClient.egern.launchURL?.scheme, "egern")
    }

    func testSelectedClientPersists() {
        let suiteName = "ThirdPartyProxyClientStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ThirdPartyProxyClientStore(defaults: defaults)
        XCTAssertEqual(store.selectedClient, .shadowrocket)

        store.select(.stash)
        XCTAssertEqual(ThirdPartyProxyClientStore(defaults: defaults).selectedClient, .stash)
    }
}

private final class FakeThirdPartyRequester: ThirdPartyProxyRequesting {
    private let data: Data
    private(set) var lastURL: URL?

    init(body: String) {
        data = Data(body.utf8)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastURL = request.url
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (data, response)
    }
}
