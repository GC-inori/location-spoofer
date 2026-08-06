import XCTest
@testable import PaopaoLocationSpoofer

final class VirtualLocationTipPreferencesTests: XCTestCase {
    private var suites: [String] = []

    override func tearDown() {
        for suite in suites {
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
        suites.removeAll()
        super.tearDown()
    }

    func testSuppressionAppearsOnlyAfterThirdSuccessfulOperation() {
        let defaults = makeDefaults()
        let legacyDefaults = makeDefaults()
        let preferences = VirtualLocationTipPreferences(
            defaults: defaults,
            legacyDefaults: legacyDefaults
        )

        XCTAssertEqual(preferences.recordSuccessfulOperation(.activation), 1)
        XCTAssertFalse(preferences.canSuppress(.activation))
        XCTAssertEqual(preferences.recordSuccessfulOperation(.activation), 2)
        XCTAssertFalse(preferences.canSuppress(.activation))
        XCTAssertEqual(preferences.recordSuccessfulOperation(.activation), 3)
        XCTAssertTrue(preferences.canSuppress(.activation))
    }

    func testActivationAndDeactivationCountersAndSuppressionAreIndependent() {
        let defaults = makeDefaults()
        let preferences = VirtualLocationTipPreferences(
            defaults: defaults,
            legacyDefaults: makeDefaults()
        )

        for _ in 0..<3 {
            preferences.recordSuccessfulOperation(.activation)
        }
        preferences.suppress(.activation)

        XCTAssertFalse(preferences.shouldPresentAutomaticTip(.activation))
        XCTAssertTrue(preferences.shouldPresentAutomaticTip(.deactivation))
        XCTAssertFalse(preferences.canSuppress(.deactivation))

        for _ in 0..<3 {
            preferences.recordSuccessfulOperation(.deactivation)
        }
        preferences.suppress(.deactivation)
        XCTAssertFalse(preferences.shouldPresentAutomaticTip(.deactivation))
    }

    func testSuppressionBeforeThirdOperationIsIgnored() {
        let preferences = VirtualLocationTipPreferences(
            defaults: makeDefaults(),
            legacyDefaults: makeDefaults()
        )

        preferences.recordSuccessfulOperation(.deactivation)
        preferences.suppress(.deactivation)

        XCTAssertTrue(preferences.shouldPresentAutomaticTip(.deactivation))
    }

    func testLegacyActivationSuppressionRemainsEffective() {
        let legacyDefaults = makeDefaults()
        legacyDefaults.set(true, forKey: "activationTipDisabled")
        let preferences = VirtualLocationTipPreferences(
            defaults: makeDefaults(),
            legacyDefaults: legacyDefaults
        )

        XCTAssertFalse(preferences.shouldPresentAutomaticTip(.activation))
        XCTAssertTrue(preferences.shouldPresentAutomaticTip(.deactivation))
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "VirtualLocationTipPreferencesTests.\(UUID().uuidString)"
        suites.append(suite)
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
