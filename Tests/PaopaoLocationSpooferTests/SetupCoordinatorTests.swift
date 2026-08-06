import XCTest
@testable import PaopaoLocationSpoofer

@MainActor
final class SetupCoordinatorTests: XCTestCase {
    func testSuccessfulVerificationDismissesSetup() {
        let coordinator = SetupCoordinator()
        coordinator.requestSetup()

        coordinator.applyVerificationResult(.success)

        XCTAssertEqual(coordinator.trustState, .trusted)
        XCTAssertFalse(coordinator.needsSetup)
    }

    func testCertificateFailureRoutesDirectlyToCertificateStep() {
        let coordinator = SetupCoordinator()

        coordinator.applyVerificationResult(.certNotTrusted)

        XCTAssertEqual(coordinator.trustState, .unavailable)
        XCTAssertTrue(coordinator.needsSetup)
        XCTAssertEqual(coordinator.setupStep, .cert)
    }

    func testProxyFailureRoutesBackToProxyStep() {
        let coordinator = SetupCoordinator()
        coordinator.applyVerificationResult(.certNotTrusted)

        coordinator.applyVerificationResult(.wifiProxyNotConfigured)

        XCTAssertTrue(coordinator.needsSetup)
        XCTAssertEqual(coordinator.setupStep, .proxy)
    }

    func testWiFiChangeMapsLocalProxyStartFailureToProxyReminder() {
        XCTAssertEqual(VerificationResult.proxyNotRunning.wifiChangeReminderTipKind, .proxySetup)
    }

    func testWiFiChangeDoesNotPresentFailureForConcurrentVerification() {
        XCTAssertNil(VerificationResult.verificationInProgress.wifiChangeReminderTipKind)
    }

    func testWiFiChangeCertificateFailureDoesNotUseGenericReminder() {
        XCTAssertNil(VerificationResult.certNotTrusted.wifiChangeReminderTipKind)
        XCTAssertNil(VerificationResult.certNotTrusted.tipKind)
    }
}
