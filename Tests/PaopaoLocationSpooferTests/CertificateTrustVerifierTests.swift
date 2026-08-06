import XCTest
@testable import PaopaoLocationSpoofer

final class CertificateTrustVerifierTests: XCTestCase {
    func testVerifierRejectsMalformedPEM() {
        XCTAssertFalse(CertificateTrustVerifier.isCACertificateTrusted(certPEM: "not a certificate"))
    }
}
