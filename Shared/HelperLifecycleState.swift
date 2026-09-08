import Foundation

/// ServiceManagement facts, represented without linking the testable core to
/// ServiceManagement itself.
enum HelperServiceStatus: Equatable {
    case unavailable
    case installable
    case approvalRequired
    case enabled
    case unknown
}

enum HelperServiceError: Equatable {
    case alreadyRegistered
    case denied
    case invalidSignature
    case authorizationRequired
    case other(String)
}

/// The user-facing state of the privileged helper. Only `.enabled` permits a
/// helper-backed operation; every other state fails closed.
enum HelperLifecycleState: Equatable {
    case checking
    case unavailable
    case installable
    case installing
    case approvalRequired
    case enabled
    case denied
    case invalidSignature
    case failed(String)
    case maintenance(String)

    static func resolve(status: HelperServiceStatus, error: HelperServiceError? = nil) -> Self {
        if let error {
            switch error {
            case .alreadyRegistered:
                return .enabled
            case .denied, .authorizationRequired:
                return .denied
            case .invalidSignature:
                return .invalidSignature
            case .other(let description):
                return .failed(description)
            }
        }

        switch status {
        case .unavailable:
            return .unavailable
        case .installable:
            return .installable
        case .approvalRequired:
            return .approvalRequired
        case .enabled:
            return .enabled
        case .unknown:
            return .failed("macOS returned an unknown helper service status.")
        }
    }

    var isEnabled: Bool {
        self == .enabled
    }

    var isBusy: Bool {
        if case .installing = self { return true }
        return false
    }

    var needsSystemSettings: Bool {
        switch self {
        case .approvalRequired, .denied:
            return true
        default:
            return false
        }
    }

    var shouldShowAttention: Bool {
        !isEnabled && !isBusy && self != .checking
    }

    var title: String {
        switch self {
        case .checking: return "Checking"
        case .unavailable: return "Unavailable"
        case .installable: return "Ready to Install"
        case .installing: return "Installing"
        case .approvalRequired: return "Approval Required"
        case .enabled: return "Enabled"
        case .denied: return "Permission Denied"
        case .invalidSignature: return "Invalid Signature"
        case .failed: return "Unavailable"
        case .maintenance: return "Maintenance"
        }
    }

    var message: String {
        switch self {
        case .checking:
            return "Checking helper status…"
        case .unavailable:
            return "The helper service is not available in this installation."
        case .installable:
            return "The helper is not registered. You may install it now."
        case .installing:
            return "Installing helper…"
        case .approvalRequired:
            return "The helper is registered but needs approval in System Settings > Login Items."
        case .enabled:
            return "The helper is enabled and ready for its approved operations."
        case .denied:
            return "Permission was denied. Approve the helper in System Settings > Login Items."
        case .invalidSignature:
            return "The helper signature is invalid. Reinstall a correctly signed Silocleaner build."
        case .failed(let description), .maintenance(let description):
            return description
        }
    }
}
