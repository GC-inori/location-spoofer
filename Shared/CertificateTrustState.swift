import Foundation

enum CertificateTrustState: Equatable {
    case checking
    case trusted
    case unavailable

    var canModify: Bool { self == .trusted }

    var message: String {
        switch self {
        case .checking: return "checking..."
        case .trusted: return "trusted"
        case .unavailable: return "not configured"
        }
    }
}

enum LocationActionState: Equatable {
    case idle
    case applyingLocation
    case failed(String)

    var isBusy: Bool {
        if case .applyingLocation = self { return true }
        return false
    }

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }

    var statusTitle: String {
        switch self {
        case .idle: return ""
        case .applyingLocation: return "applying..."
        case .failed: return "failed"
        }
    }
}
