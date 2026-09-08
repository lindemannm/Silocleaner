//
//  HelperToolManager.swift
//  Silocleaner
//
//  Created by Alin Lupascu on 3/14/25.
//

import ServiceManagement
import AlinFoundation

extension Notification.Name {
    static let helperRequired = Notification.Name("helperRequired")
}

@objc(HelperToolProtocol)
public protocol HelperToolProtocol {
    func thinApplicationBundle(_ request: HelperBundleThinningRequest, withReply reply: @escaping (HelperBundleThinningResult) -> Void)
}

@objc(SilocleanerBundleThinningRequest)
public final class HelperBundleThinningRequest: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }
    let bundlePath: String
    init(bundlePath: String) { self.bundlePath = bundlePath }
    public required init?(coder: NSCoder) {
        guard let path = coder.decodeObject(of: NSString.self, forKey: "bundlePath") as String? else { return nil }
        bundlePath = path
    }
    public func encode(with coder: NSCoder) { coder.encode(bundlePath as NSString, forKey: "bundlePath") }
}

@objc(SilocleanerBundleThinningResult)
public final class HelperBundleThinningResult: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }
    let succeeded: Bool
    let preSize: UInt64
    let postSize: UInt64
    public required init?(coder: NSCoder) {
        succeeded = coder.decodeBool(forKey: "succeeded")
        preSize = UInt64(coder.decodeInt64(forKey: "preSize"))
        postSize = UInt64(coder.decodeInt64(forKey: "postSize"))
    }
    public func encode(with coder: NSCoder) {
        coder.encode(succeeded, forKey: "succeeded")
        coder.encode(Int64(clamping: preSize), forKey: "preSize")
        coder.encode(Int64(clamping: postSize), forKey: "postSize")
    }
}

enum HelperToolAction: Equatable {
    case none      // Only check status
    case install   // Install the helper tool
    case uninstall // Uninstall the helper tool
    case reinstall // Uninstall then reinstall (fixes desync)
}

class HelperToolManager: ObservableObject {
    static let shared = HelperToolManager()
    private var helperConnection: NSXPCConnection?
    let helperToolIdentifier = "com.lindemannm.Silocleaner.SilocleanerHelper"
    @Published var isHelperToolInstalled: Bool = false
    @Published var message: String = String(localized: "Checking...")
    @Published var isInitialCheckComplete: Bool = false
    @Published private(set) var lifecycleState: HelperLifecycleState = .checking

    var status: String {
        lifecycleState.title
    }

    var shouldShowHelperBadge: Bool {
        isInitialCheckComplete && lifecycleState.shouldShowAttention
    }

    // Trigger overlay when operation fails due to missing helper
    func triggerHelperRequiredAlert() {
        NotificationCenter.default.post(name: .helperRequired, object: nil)
    }

    init() {
        Task {
            await manageHelperTool()
        }
    }

    private func setLifecycleState(_ state: HelperLifecycleState) {
        updateOnMain {
            self.lifecycleState = state
            self.message = String(localized: String.LocalizationValue(state.message))
            self.isHelperToolInstalled = state.isEnabled
            self.isInitialCheckComplete = state != .checking
        }
    }

    // Function to manage the helper tool installation/uninstallation
    func manageHelperTool(action: HelperToolAction = .none) async {
        let plistName = "\(helperToolIdentifier).plist"
        let service = SMAppService.daemon(plistName: plistName)
        var occurredError: NSError?

        if action == .install || action == .reinstall {
            setLifecycleState(.installing)
        }

        // Perform install/uninstall actions if specified
        switch action {
        case .install:
            // Pre-check before registering
            switch service.status {
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
            case .enabled:
                break
            default:
                do {
                    try service.register()
                    if service.status == .requiresApproval {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                } catch let nsError as NSError {
                    occurredError = nsError
                    if HelperServiceError.from(nsError) == .denied {
                        SMAppService.openSystemSettingsLoginItems()
                    } else {
                        printOS("Failed to register helper: \(nsError.localizedDescription)")
                    }

                }
            }

        case .uninstall:
            do {
                try await service.unregister()
                // Close any existing connection
                helperConnection?.invalidate()
                helperConnection = nil
            } catch let nsError as NSError {
                occurredError = nsError
                printOS("Failed to unregister helper: \(nsError.localizedDescription)")
            }

        case .reinstall:
            // Uninstall first
            do {
                try await service.unregister()
                helperConnection?.invalidate()
                helperConnection = nil
            } catch let nsError as NSError {
                printOS("Reinstall: Failed to unregister: \(nsError.localizedDescription)")
            }

            // Small delay to ensure launchd processes the unregister
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            // Then install
            do {
                try service.register()
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            } catch let nsError as NSError {
                occurredError = nsError
                printOS("Reinstall: Failed to register: \(nsError.localizedDescription)")
            }

        case .none:
            break
        }

        setLifecycleState(
            HelperLifecycleState.resolve(
                status: HelperServiceStatus.from(service.status),
                error: occurredError.map(HelperServiceError.from)
            )
        )
    }

    // Function to open Settings > Login Items
    func openSMSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // The sole privileged mutation is a validated, root-owned /Applications bundle.
    func runBundleThinning(bundlePath path: String) async -> (Bool, String, [String: UInt64]) {
        guard let connection = getConnection() else {
            return (false, "XPC: No helper connection", [:])
        }

        return await withCheckedContinuation { continuation in
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                continuation.resume(returning: (false, "XPC: Error: \(error.localizedDescription)", [:]))
            }) as? HelperToolProtocol else {
                continuation.resume(returning: (false, "XPC: Proxy failure", [:]))
                return
            }

            proxy.thinApplicationBundle(HelperBundleThinningRequest(bundlePath: path)) { result in
                let sizes = result.succeeded ? ["pre": result.preSize, "post": result.postSize] : [:]
                continuation.resume(returning: (result.succeeded, result.succeeded ? "Bundle thinning completed successfully" : "Bundle thinning failed", sizes))
            }
        }
    }


    // Create/reuse XPC connection
    private func getConnection() -> NSXPCConnection? {
        if let connection = helperConnection {
            return connection
        }
        let connection = NSXPCConnection(machServiceName: helperToolIdentifier, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: HelperToolProtocol.self)
        connection.remoteObjectInterface?.setClasses(xpcClasses(HelperBundleThinningRequest.self), for: #selector(HelperToolProtocol.thinApplicationBundle(_:withReply:)), argumentIndex: 0, ofReply: false)
        connection.remoteObjectInterface?.setClasses(xpcClasses(HelperBundleThinningResult.self), for: #selector(HelperToolProtocol.thinApplicationBundle(_:withReply:)), argumentIndex: 0, ofReply: true)
        connection.invalidationHandler = { [weak self] in
            self?.helperConnection = nil
        }
        connection.resume()
        helperConnection = connection
        return connection
    }



    // MARK: - Nuclear Reset

    /// Nuclear reset: Reset BTM (Background Task Management) database to clear desynced helper registrations
    /// This is a last-resort fix for when SMAppService becomes desynced during development
    /// PREREQUISITE: User must manually disable helper in System Settings > Login Items first in certain cases
    /// Uses the fixed-operation privileged runner, which prompts through sudo.
    func nuclearResetHelper() async -> Bool {
        printOS("Starting nuclear reset of helper tool...")

        setLifecycleState(.maintenance("Resetting Background Task Management database…"))

        // Execute sfltool resetbtm to clear Background Task Management database
        // NOTE: This only works if user has disabled the service in System Settings first
        let result = try? await runPrivilegedTool("/usr/bin/sfltool", arguments: ["resetbtm"])
        let success = result?.success == true
        let output = result?.output ?? "Unable to start sfltool"

        if success {
            printOS("BTM reset succeeded")

            // Invalidate XPC connection
            helperConnection?.invalidate()
            helperConnection = nil

            setLifecycleState(.installable)

            return true
        } else {
            printOS("BTM reset failed: \(output)")
            setLifecycleState(.failed("Background Task Management reset failed: \(output)"))
            return false
        }
    }
}

private extension HelperServiceStatus {
    static func from(_ status: SMAppService.Status) -> Self {
        switch status {
        case .notFound:
            return .unavailable
        case .notRegistered:
            return .installable
        case .requiresApproval:
            return .approvalRequired
        case .enabled:
            return .enabled
        @unknown default:
            return .unknown
        }
    }
}

private extension HelperServiceError {
    static func from(_ error: NSError) -> Self {
        switch error.code {
        case kSMErrorAlreadyRegistered:
            return .alreadyRegistered
        case kSMErrorLaunchDeniedByUser:
            return .denied
        case kSMErrorInvalidSignature:
            return .invalidSignature
        case 1:
            return .authorizationRequired
        default:
            return .other(error.localizedDescription)
        }
    }
}

private func xpcClasses(_ type: AnyClass) -> Set<AnyHashable> {
    NSSet(object: type) as! Set<AnyHashable>
}
