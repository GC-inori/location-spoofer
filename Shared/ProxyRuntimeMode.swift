import Foundation

enum ProxyRuntimeMode: String, CaseIterable, Codable, Identifiable {
    case localWiFi
    case thirdParty

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .localWiFi: return "APP模式"
        case .thirdParty: return "第三方代理模式"
        }
    }
}

@MainActor
final class ProxyRuntimeModeStore: ObservableObject {
    static let shared = ProxyRuntimeModeStore()

    private enum Key {
        static let runtimeMode = "proxyRuntimeMode"
        static let hasSelectedRuntimeMode = "hasSelectedProxyRuntimeMode"
    }

    @Published private(set) var mode: ProxyRuntimeMode
    @Published private(set) var hasSelectedMode: Bool
    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        self.mode = defaults.string(forKey: Key.runtimeMode)
            .flatMap(ProxyRuntimeMode.init(rawValue:)) ?? .localWiFi
        self.hasSelectedMode = defaults.bool(forKey: Key.hasSelectedRuntimeMode)
    }

    func setMode(_ mode: ProxyRuntimeMode) {
        let changed = self.mode != mode
        self.mode = mode
        hasSelectedMode = true
        defaults.set(mode.rawValue, forKey: Key.runtimeMode)
        defaults.set(true, forKey: Key.hasSelectedRuntimeMode)
        if changed {
            RuntimeLogger.info("APP", "Mode", "代理运行模式已切换", details: [
                "模式": mode.displayName
            ])
        }
    }
}
