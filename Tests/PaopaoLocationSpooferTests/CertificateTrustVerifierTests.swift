import XCTest
@testable import PaopaoLocationSpoofer

final class CertificateTrustVerifierTests: XCTestCase {
    func testVerifierMapsFailedProbeToUnavailable() async {
        let verifier = CertificateTrustVerifier(probe: { _, _ in false })
        XCTAssertEqual(await verifier.verify(url: URL(string: "https://127.0.0.1:1/health")!, leafHash: "x"), .unavailable)
    }
}
