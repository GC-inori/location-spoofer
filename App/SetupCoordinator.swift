import Foundation
import SwiftUI

@MainActor
final class SetupCoordinator: ObservableObject {
    @Published private(set) var trustState: CertificateTrustState = .checking
    @Published var message = ""
    @Published var isBrowsingWithoutTrust = false
    @Published var testLog = ""
    // 启动检测失败才弹引导页；检测通过则保持 false
    @Published var needsSetup = false

    let certificateStore = CertificateAuthorityStore()
    let proxy = ProxyManager.shared
    private var isVerificationRunning = false

    init() { RuntimeLogger.info("APP", "Setup", "初始化") }

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    var canModify: Bool { proxy.isRunning && trustState == .trusted }

    func refreshTrust() async {
        trustState = .checking
        message = "正在检测…"
        testLog = ""
        do {
            _ = try certificateStore.ensure()
            if !proxy.isRunning { try await proxy.start() }
            // 强制走代理 POST 到 Apple 定位接口：TLS 成功 = CA 信任
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 5
            config.timeoutIntervalForResource = 8
            config.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: true,
                kCFNetworkProxiesHTTPProxy as String: "127.0.0.1",
                kCFNetworkProxiesHTTPPort as String: 8888,
            ]
            // 用当前保存的虚拟定位坐标做测试；没有则用默认坐标
            let saved = WlocSettingsStore.load()
            let testLat = saved?.latitude ?? 22.543099
            let testLon = saved?.longitude ?? 113.934576
            let testAccuracy = saved?.accuracy ?? 25
            let req = makeWlocRequest()
            let (_, resp) = try await URLSession(configuration: config).data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            // 400 = Apple 拒绝了测试请求体，但 TLS 握手成功 = 证书已信任
            if status == 0 {
                trustState = .unavailable
                message = "代理链路异常，未收到响应"
                return
            }
            trustState = .trusted
            message = "✓ 定位环境正常（返回 \(status)）"
        } catch {
            trustState = .unavailable
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain && ns.code == -1202 {
                message = "CA 证书未信任，请去「设置→通用→关于→证书信任设置」开启或重新安装"
            } else if ns.domain == NSURLErrorDomain && ns.code == -1001 {
                message = "检测超时，请检查代理是否正常"
            } else if ns.domain == NSURLErrorDomain && ns.code == -1200 {
                message = "代理未启动或无法连接"
            } else {
                message = "检测失败 [\(ns.domain) \(ns.code)]: \(ns.localizedDescription)"
            }
        }
        needsSetup = !canModify
    }

    func sceneDidBecomeActive() {}
    func browseMapWithoutSetup() { isBrowsingWithoutTrust = true; needsSetup = false }
    func completeSetup() { needsSetup = false }
    func requestSetup() { needsSetup = true }

    // MARK: - Step-by-step verification test

    private func makeWlocRequest() -> URLRequest {
        var req = URLRequest(url: URL(string: "https://gs-loc.apple.com/clls/wloc")!)
        req.httpMethod = "POST"
        req.httpBody = CoreBridge.testWlocRequestData()
        req.setValue("application/x-protobuf", forHTTPHeaderField: "Content-Type")
        req.setValue("wloc/1.0", forHTTPHeaderField: "User-Agent")
        req.setValue("application/x-protobuf", forHTTPHeaderField: "Accept")
        return req
    }

    func runVerificationTest(testLat: Double = 22.543099, testLon: Double = 113.934576) async -> VerificationResult {
        guard !isVerificationRunning else { return .verificationInProgress }
        isVerificationRunning = true
        defer { isVerificationRunning = false }

        testLog = ""
        let log = { (msg: String) in self.testLog += msg + "\n" }

        log("======== 代理验证测试 ========")
        log("App 版本: \(appVersion)")
        log("系统版本: iOS \(UIDevice.current.systemVersion)")
        log("")

        // Step A: Proxy running
        log("[步骤 A] 检查代理是否运行…")
        log("  端口: 127.0.0.1:8888")
        let stepAStart = Date()
        if !proxy.isRunning {
            log("  ⚠ 代理未运行，尝试启动…")
            do { try await proxy.start() } catch {
                log("  ✗ 启动失败: \(error.localizedDescription)")
                return .proxyNotRunning
            }
            log("  ✓ 代理启动成功")
        } else {
            log("  ✓ 代理已在运行中")
        }
        collectProxyLogs(since: stepAStart, to: log)

        // Step B: Combined CA + WiFi proxy check (single request)
        log("")
        log("[步骤 B] 检测证书与 WiFi 代理…")
        log("  方式: 请求 baidu.com/paopao-verify-<token>")
        log("  结果判定: TLS 错误=证书问题 / 响应不匹配=代理未配置 / 匹配=通过")
        let stepBStart = Date()
        let verifyToken = CoreBridge.refreshVerifyToken()
        guard !verifyToken.isEmpty else {
            log("  ✗ 无法生成验证 token")
            return .certNotTrusted
        }
        do {
            let url = URL(string: "https://www.baidu.com/paopao-verify-\(verifyToken)")!
            var req = URLRequest(url: url)
            req.timeoutInterval = 8
            req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            let config = URLSessionConfiguration.ephemeral
            let (data, resp) = try await URLSession(configuration: config).data(for: req)
            let statusCode = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            if body == verifyToken {
                log("  ✓ 证书已信任，WiFi 代理已配置")
            } else {
                log("  ✗ 响应不匹配 (HTTP \(statusCode))，WiFi 代理未配置")
                log("  收到: \(body.prefix(100))")
                return .wifiProxyNotConfigured
            }
        } catch {
            let ns = error as NSError
            let msg = error.localizedDescription
            log("  ✗ 请求失败 [\(ns.domain) code=\(ns.code)]: \(msg)")
            if ns.domain == NSURLErrorDomain && ns.code == -1202 {
                log("  TLS 握手被拒，CA 证书未信任")
                return .certNotTrusted
            }
            if msg.contains("TLS") {
                log("  包含 TLS → 证书问题")
                return .certNotTrusted
            }
            return .wifiProxyNotConfigured
        }
        collectProxyLogs(since: stepBStart, to: log)

        log("")
        log("======== 环境检测通过 ✓ ========")
        return .success
    }

    /// 拉取 Go 代理的详细日志（CONNECT/请求/上游响应/改写结果）到 testLog
    private func collectProxyLogs(since date: Date, to log: (String) -> Void) {
        CoreBridge.flushLogs(category: "Proxy")
        let entries = RuntimeLogStore.loadAll(limit: 200)
        let proxyEntries = entries.filter {
            $0.source == "CORE" && $0.category == "Proxy" && $0.timestamp >= date
        }
        guard !proxyEntries.isEmpty else { return }
        log("  --- 代理日志 ---")
        for e in proxyEntries {
            log("  " + e.message)
        }
    }
}
