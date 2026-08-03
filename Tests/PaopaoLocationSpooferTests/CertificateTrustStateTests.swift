import XCTest
@testable import PaopaoLocationSpoofer

final class CertificateTrustStateTests: XCTestCase {
    func testActionStateBusyAndStatusText() {
        XCTAssertTrue(LocationActionState.applyingLocation.isBusy)
        XCTAssertEqual(LocationActionState.idle.statusTitle, "")
        XCTAssertEqual(LocationActionState.failed("permission denied").statusTitle, "failed")
        XCTAssertFalse(LocationActionState.idle.isBusy)
    }

    func testCertificateReadinessAllowsOnlyTrustedState() {
        XCTAssertTrue(CertificateTrustState.trusted.canModify)
        XCTAssertFalse(CertificateTrustState.unavailable.canModify)
        XCTAssertFalse(CertificateTrustState.checking.canModify)
    }
}
