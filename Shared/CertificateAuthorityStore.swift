import Foundation

final class CertificateAuthorityStore {
    private let directory: URL
    private let generator: () throws -> CertificateAuthority
    private let certificateURL: URL
    private let keyURL: URL

    init(directory: URL = AppGroup.containerURL.appendingPathComponent("CertificateAuthority", isDirectory: true), generator: @escaping () throws -> CertificateAuthority = CoreBridge.generateCertificateAuthority) {
        self.directory = directory
        self.generator = generator
        self.certificateURL = directory.appendingPathComponent("ca-cert.pem")
        self.keyURL = directory.appendingPathComponent("ca-key.pem")
    }

    func ensure() throws -> CertificateAuthority {
        if let current = try load() {
            RuntimeLogger.debug("SHARED", "Certificate.store", "读取已有 CA 文件", details: ["directory": directory.path])
            return current
        }
        RuntimeLogger.info("SHARED", "Certificate.store", "未找到 CA 文件，开始生成", details: ["directory": directory.path])
        let authority = try generator()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let certificateData = authority.certPEM.data(using: .utf8),
              let keyData = authority.keyPEM.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        try certificateData.write(to: certificateURL, options: .atomic)
        try keyData.write(to: keyURL, options: .atomic)
        applyCompleteProtection(to: certificateURL)
        applyCompleteProtection(to: keyURL)
        RuntimeLogger.info("SHARED", "Certificate.store", "CA 文件写入完成", details: ["directory": directory.path])
        return authority
    }

    func load() throws -> CertificateAuthority? {
        guard FileManager.default.fileExists(atPath: certificateURL.path), FileManager.default.fileExists(atPath: keyURL.path) else { return nil }
        return CertificateAuthority(certPEM: try String(contentsOf: certificateURL, encoding: .utf8), keyPEM: try String(contentsOf: keyURL, encoding: .utf8))
    }

    private func applyCompleteProtection(to url: URL) {
        #if os(iOS)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        #endif
    }
}
