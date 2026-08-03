import Foundation
import Security

final class CertificateTrustVerifier {
    /// Check whether a CA certificate (given as PEM data) is installed and fully trusted
    /// by the system. Uses SecTrust evaluation against system anchors only — no network needed.
    static func isCACertificateTrusted(certPEM: String) -> Bool {
        guard let certData = certPEM.data(using: .utf8),
              let cert = SecCertificateCreateWithData(nil, certData as CFData) else {
            RuntimeLogger.error("APP", "Trust", "无法解析 CA 证书 PEM")
            return false
        }

        // Create a basic trust with the CA cert, using system anchor certificates only
        var trust: SecTrust?
        let createStatus = SecTrustCreateWithCertificates(
            [cert] as CFArray,
            SecPolicyCreateBasicX509(),
            &trust
        )
        guard createStatus == errSecSuccess, let trust = trust else {
            RuntimeLogger.error("APP", "Trust", "无法创建 SecTrust")
            return false
        }

        // Use system anchors only — if our CA is installed & trusted, evaluation passes
        SecTrustSetAnchorCertificatesOnly(trust, false)

        var error: CFError?
        let result = SecTrustEvaluateWithError(trust, &error)
        if let error {
            RuntimeLogger.warning("APP", "Trust", "SecTrust 评估返回错误", details: [
                "error": (error as Error).localizedDescription
            ])
        }

        RuntimeLogger.info("APP", "Trust", result ? "CA 证书已被系统信任" : "CA 证书未被系统信任")
        return result
    }
}
