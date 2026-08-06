import Foundation

/// 环境验证结果，UI 层根据此值弹出对应的引导面板。
enum VerificationResult: Equatable, Identifiable {
    case success
    case proxyNotRunning
    case verificationInProgress
    case verificationSuperseded
    case certNotTrusted
    case wifiProxyNotConfigured
    case coordinateWriteFailed(String)
    case patchFailed(String)

    var id: String {
        switch self {
        case .success: return "成功"
        case .proxyNotRunning: return "代理未运行"
        case .verificationInProgress: return "已有验证正在进行"
        case .verificationSuperseded: return "验证已被新位置取代"
        case .certNotTrusted: return "证书未信任"
        case .wifiProxyNotConfigured: return "WiFi代理未配置"
        case .coordinateWriteFailed: return "坐标写入失败"
        case .patchFailed: return "改写验证失败"
        }
    }

    var isSuccess: Bool { self == .success }

    /// 对应的引导页类型
    var tipKind: TipKind? {
        switch self {
        case .success: return nil
        case .proxyNotRunning, .verificationInProgress, .verificationSuperseded: return nil
        case .certNotTrusted: return nil
        case .wifiProxyNotConfigured: return .proxySetup
        case .coordinateWriteFailed, .patchFailed: return .rewriteFailed
        }
    }

    /// Wi-Fi 变化后仍留在地图页显示的提醒。
    /// 证书失败必须进入完整证书安装引导，因此不在这里返回通用提示页。
    var wifiChangeReminderTipKind: TipKind? {
        switch self {
        case .proxyNotRunning:
            return .proxySetup
        case .certNotTrusted, .verificationInProgress, .verificationSuperseded:
            return nil
        default:
            return tipKind
        }
    }
}
