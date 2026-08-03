import XCTest
@testable import PaopaoLocationSpoofer

final class CertificateAuthorityStoreTests: XCTestCase {
    func testEnsureCreatesOnceAndThenReusesExistingPair() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var generations = 0
        let store = CertificateAuthorityStore(directory: directory) {
            generations += 1
            return CertificateAuthority(certPEM: "cert", keyPEM: "key")
        }
        XCTAssertEqual(try store.ensure(), CertificateAuthority(certPEM: "cert", keyPEM: "key"))
        XCTAssertEqual(try store.ensure(), CertificateAuthority(certPEM: "cert", keyPEM: "key"))
        XCTAssertEqual(generations, 1)
    }
}
