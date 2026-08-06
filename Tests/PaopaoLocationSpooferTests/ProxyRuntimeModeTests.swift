import XCTest
@testable import PaopaoLocationSpoofer

@MainActor
final class ProxyRuntimeModeTests: XCTestCase {
    func testDefaultsToLocalWiFiAndPersistsThirdPartyMode() {
        let suiteName = "ProxyRuntimeModeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let initial = ProxyRuntimeModeStore(defaults: defaults)
        XCTAssertEqual(initial.mode, .localWiFi)
        XCTAssertFalse(initial.hasSelectedMode)

        initial.setMode(.thirdParty)
        let restored = ProxyRuntimeModeStore(defaults: defaults)
        XCTAssertEqual(restored.mode, .thirdParty)
        XCTAssertTrue(restored.hasSelectedMode)
    }
}
