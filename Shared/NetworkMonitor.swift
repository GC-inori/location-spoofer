import Network
import Foundation
import SystemConfiguration.CaptiveNetwork

@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isSatisfied = true
    @Published private(set) var isWiFiEnabled = true
    @Published private(set) var currentSSID: String?

    /// WiFi 重连或 SSID 变化时触发（仅虚拟定位激活时使用）
    var onWiFiChanged: (() -> Void)?

    private let monitor = NWPathMonitor()
    private var ssidTimer: Timer?
    private var wasSatisfied = true

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            let wifi = path.usesInterfaceType(.wifi)
            Task { @MainActor in
                guard let self else { return }
                // 网络恢复连接 → 触发检测
                let reconnected = satisfied && !self.wasSatisfied && wifi
                self.wasSatisfied = satisfied
                self.isSatisfied = satisfied
                self.isWiFiEnabled = wifi
                if reconnected {
                    self.onWiFiChanged?()
                }
            }
        }
        monitor.start(queue: .main)
        startSSIDPolling()
    }

    var isAirplaneMode: Bool { !isSatisfied }

    private func startSSIDPolling() {
        ssidTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let ssid = Self.fetchSSID()
                if ssid != self.currentSSID, ssid != nil {
                    self.currentSSID = ssid
                    self.onWiFiChanged?()
                }
            }
        }
    }

    static func fetchSSID() -> String? {
        guard let interfaces = CNCopySupportedInterfaces() as? [String] else { return nil }
        for iface in interfaces {
            if let info = CNCopyCurrentNetworkInfo(iface as CFString) as? [String: Any],
               let ssid = info[kCNNetworkInfoKeySSID as String] as? String {
                return ssid
            }
        }
        return nil
    }
}
