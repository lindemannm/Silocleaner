import AlinFoundation
import ArgumentParser
import Foundation
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

// Main command structure
struct SilocleanerCLI: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "silocleaner",
        abstract: "Command-line interface for the Silocleaner app",
        subcommands: [
//            Run.self,
            List.self,
            ListOrphaned.self,
            Uninstall.self,
            UninstallAll.self,
            RemoveOrphaned.self,
            Helper.self,
            AskPassword.self,
        ]
    )

    // For dependency management
    static var locations: Locations!
    static var fsm: FolderSettingsManager!

    // Set up dependencies before running commands
    static func setupDependencies(
        locations: Locations, fsm: FolderSettingsManager
    ) {
        Self.locations = locations
        Self.fsm = fsm
    }

    /// CLI mutations require an explicit, non-interactive acknowledgement.
    /// Printing the resolved paths first makes `--yes` a confirmation of the
    /// actual operation rather than merely the command spelling.
    static func confirmDestructiveOperation(_ paths: [URL], acknowledged: Bool) -> Bool {
        guard !acknowledged else { return true }
        printOS(DestructiveOperationPreview.message(for: paths))
        return false
    }

    /// Reject protected paths before a CLI mutation when no approved elevated
    /// path is available. The decision itself lives in the fixture-tested core;
    /// this layer only supplies the CLI-specific remediation text.
    static func hasRequiredDeletionAuthorization(
        for paths: [URL],
        sudoCommand: String,
        helperInstalled: Bool = HelperToolManager.shared.isHelperToolInstalled
    ) -> Bool {
        switch DestructiveOperationAuthorization.evaluate(
            paths: paths,
            acknowledged: true,
            hasPrivilegedAuthorization: helperInstalled,
            isWritable: { FileManager.default.isWritableFile(atPath: $0.path) }
        ) {
        case .authorized:
            return true
        case .privilegedAuthorizationRequired(let protectedPaths):
            printOS("Protected files detected. Please run this command with sudo:\n")
            printOS("sudo \(sudoCommand)")
            printOS("\nProtected files:\n")
            protectedPaths.forEach { printOS($0) }
            return false
        case .confirmationRequired:
            assertionFailure("A confirmed deletion preflight must not require confirmation")
            return false
        }
    }

//    struct Run: ParsableCommand {
//        static var configuration = CommandConfiguration(
//            commandName: "run",
//            abstract: "Launch Silocleaner in Debug mode to see console logs"
//        )
//
//        func run() throws {
//            printOS("Silocleaner CLI | Launching App For Debugging:\n")
//        }
//    }

    struct List: ParsableCommand {
        static var configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List application files available for uninstall at the specified path"
        )

        @Argument(help: "Path to the application")
        var path: String

        func run() throws {
            // Convert the provided string path to a URL
            let url = URL(fileURLWithPath: path)

            // Fetch the app info and safely unwrap
            guard let appInfo = AppInfoFetcher.getAppInfo(atPath: url) else {
                printOS("Error: Invalid path or unable to fetch app info at path: \(path)\n")
                Foundation.exit(1)
            }

            // Use the AppPathFinder to find paths synchronously
            let appPathFinder = AppPathFinder(appInfo: appInfo, locations: SilocleanerCLI.locations)

            // Call findPaths to get the Set of URLs
            let foundPaths = appPathFinder.findPathsCLI()

            // Print each path in the Set to the console
            for path in foundPaths {
                printOS(path.path)
            }

            printOS("\nFound \(foundPaths.count) application files.\n")
            Foundation.exit(0)
        }
    }

    struct ListOrphaned: ParsableCommand {
        static var configuration = CommandConfiguration(
            commandName: "list-orphaned",
            abstract: "List orphaned files available for removal"
        )

        func run() throws {
            // Get installed apps for filtering
            DispatchQueue.global(qos: .userInitiated).async {
                let _ = getSortedApps(paths: SilocleanerCLI.fsm.folderPaths, useStreaming: false)
            }


            // Find orphaned files
            let foundPaths = ReversePathsSearcher(
                locations: SilocleanerCLI.locations,
                fsm: SilocleanerCLI.fsm,
                sortedApps: AppState.shared.sortedApps
            )
                .reversePathsSearchCLI()

            // Print each path in the array to the console
            for path in foundPaths {
                printOS(path.path)
            }
            printOS("\nFound \(foundPaths.count) orphaned files.\n")
            Foundation.exit(0)
        }
    }

    struct Uninstall: ParsableCommand {
        static var configuration = CommandConfiguration(
            commandName: "uninstall",
            abstract: "Uninstall only the application bundle at the specified path"
        )

        @Argument(help: "Path to the application")
        var path: String

        @Flag(name: .long, help: "Confirm moving the application bundle to the Trash")
        var yes = false

        func run() async throws {
            // Convert the provided string path to a URL
            let url = URL(fileURLWithPath: path)

            // Fetch the app info and safely unwrap
            guard let appInfo = AppInfoFetcher.getAppInfo(atPath: url) else {
                printOS("Error: Invalid path or unable to fetch app info at path: \(path)\n")
                Foundation.exit(1)
            }

            guard SilocleanerCLI.confirmDestructiveOperation([appInfo.path], acknowledged: yes) else {
                Foundation.exit(2)
            }

            // Kill app before deletion
            await killApp(appId: appInfo.bundleIdentifier)

            let success = moveFilesToTrashCLI(at: [appInfo.path])

            if success {
                printOS("Application deleted successfully.\n")
                Foundation.exit(0)
            } else {
                printOS("Failed to delete application.\n")
                Foundation.exit(1)
            }
        }
    }

    struct UninstallAll: ParsableCommand {
        static var configuration = CommandConfiguration(
            commandName: "uninstall-all",
            abstract: "Uninstall application bundle and ALL related files at the specified path"
        )

        @Argument(help: "Path to the application")
        var path: String

        @Flag(name: .long, help: "Confirm moving the application and related files to the Trash")
        var yes = false

        func run() async throws {
            // Convert the provided string path to a URL
            let url = URL(fileURLWithPath: path)

            // Fetch the app info and safely unwrap
            guard let appInfo = AppInfoFetcher.getAppInfo(atPath: url) else {
                printOS("Error: Invalid path or unable to fetch app info at path: \(path)")
                Foundation.exit(1)
            }

            // Use the AppPathFinder to find paths synchronously
            let appPathFinder = AppPathFinder(appInfo: appInfo, locations: SilocleanerCLI.locations)

            // Call findPaths to get the Set of URLs
            let foundPaths = appPathFinder.findPathsCLI()

            guard SilocleanerCLI.confirmDestructiveOperation(Array(foundPaths), acknowledged: yes) else {
                Foundation.exit(2)
            }

            if !SilocleanerCLI.hasRequiredDeletionAuthorization(
                for: Array(foundPaths),
                sudoCommand: "silocleaner uninstall-all \(path)"
            ) {
                Foundation.exit(1)
            }

            // Kill app before deletion
            await killApp(appId: appInfo.bundleIdentifier)

            let success = moveFilesToTrashCLI(at: Array(foundPaths))

            if success {
                printOS("The application and related files have been deleted successfully.\n")
                Foundation.exit(0)
            } else {
                printOS("Failed to delete some files, they might be protected or in use.\n")
                Foundation.exit(1)
            }
        }
    }

    struct RemoveOrphaned: ParsableCommand {
        static var configuration = CommandConfiguration(
            commandName: "remove-orphaned",
            abstract:
                "Remove ALL orphaned files (To ignore files, add them to the exception list within Silocleaner settings)"
        )

        @Flag(name: .long, help: "Confirm moving all listed orphaned files to the Trash")
        var yes = false

        func run() throws {

            // Get installed apps for filtering
            DispatchQueue.global(qos: .userInitiated).async {
                let _ = getSortedApps(paths: SilocleanerCLI.fsm.folderPaths, useStreaming: false)
            }

            // Find orphaned files
            let foundPaths = ReversePathsSearcher(
                locations: SilocleanerCLI.locations,
                fsm: SilocleanerCLI.fsm,
                sortedApps: AppState.shared.sortedApps
            )
                .reversePathsSearchCLI()

            guard SilocleanerCLI.confirmDestructiveOperation(foundPaths, acknowledged: yes) else {
                Foundation.exit(2)
            }

            if !SilocleanerCLI.hasRequiredDeletionAuthorization(
                for: foundPaths,
                sudoCommand: "silocleaner remove-orphaned"
            ) {
                Foundation.exit(1)
            }

            let success = moveFilesToTrashCLI(at: foundPaths)
            if success {
                printOS("Orphaned files have been deleted successfully.\n")
                Foundation.exit(0)
            } else {
                printOS("Failed to delete some orphaned files.\n")
                Foundation.exit(1)
            }
        }
    }

    struct Helper: ParsableCommand {
        static var configuration = CommandConfiguration(
            commandName: "helper",
            abstract: "Manage privileged helper tool status"
        )

        @Argument(help: "Action: 'enable' or 'disable'. Omit to check status.")
        var action: String?

        func run() throws {
            // If no action provided, return status
            guard let action = action else {
                let semaphore = DispatchSemaphore(value: 0)
                var isEnabled = false

                Task {
                    isEnabled = await isHelperEnabled()
                    semaphore.signal()
                }

                semaphore.wait()

                let status = isEnabled ? "Enabled" : "Disabled"
                printOS(status)
                Foundation.exit(0)
            }

            // Validate action
            guard ["enable", "disable"].contains(action.lowercased()) else {
                printOS("Error: Invalid action. Use 'enable', 'disable', or omit for status.\n")
                Foundation.exit(1)
            }

            // Check current status first
            let semaphore1 = DispatchSemaphore(value: 0)
            var currentlyEnabled = false

            Task {
                currentlyEnabled = await isHelperEnabled()
                semaphore1.signal()
            }

            semaphore1.wait()

            // Pre-check before attempting operation
            if action.lowercased() == "enable" {
                if currentlyEnabled {
                    printOS("Privileged helper is already enabled.\n")
                    Foundation.exit(0)
                }
            } else {
                if !currentlyEnabled {
                    printOS("Privileged helper is already disabled.\n")
                    Foundation.exit(0)
                }
            }

            // Proceed with enable/disable operation
            let semaphore2 = DispatchSemaphore(value: 0)
            var operationSuccess = false
            var errorMessage: String?

            Task {
                if action.lowercased() == "enable" {
                    await HelperToolManager.shared.manageHelperTool(action: .install)
                    operationSuccess = await isHelperEnabled()

                    if !operationSuccess {
                        errorMessage = "Failed to enable privileged helper"
                    }
                } else {
                    await HelperToolManager.shared.manageHelperTool(action: .uninstall)
                    operationSuccess = !(await isHelperEnabled())

                    if !operationSuccess {
                        errorMessage = "Failed to disable privileged helper"
                    }
                }
                semaphore2.signal()
            }

            // Wait for async operation to complete
            semaphore2.wait()

            if operationSuccess {
                if action.lowercased() == "enable" {
                    printOS("Privileged helper enabled successfully.\n")
                } else {
                    printOS("Privileged helper disabled successfully.\n")
                }
                Foundation.exit(0)
            } else {
                printOS("Error: \(errorMessage ?? "Unknown error occurred")\n")
                Foundation.exit(1)
            }
        }

        // Helper function to check if privileged helper is enabled
        private func isHelperEnabled() async -> Bool {
            await HelperToolManager.shared.manageHelperTool()
            return HelperToolManager.shared.isHelperToolInstalled
        }
    }

    struct AskPassword: ParsableCommand {
        static var configuration = CommandConfiguration(
            commandName: "ask-password",
            abstract: "Display password prompt for sudo operations",
            shouldDisplay: false
        )

        @Option(name: .long, help: .hidden)
        var message: String = "Homebrew is requesting your password to perform a privileged action"

        func run() throws {
            guard let password = obtainPassword() else {
                Darwin.exit(1)
            }

            // SUDO_ASKPASS consumes this value immediately. Never retain it.
            print(password)
            Darwin.exit(0)
        }

        // MARK: - Obtain Password
        private func obtainPassword() -> String? {
            // Check if Silocleaner main app is running
            let runningApps = NSWorkspace.shared.runningApplications
            let silocleanerRunning = runningApps.contains { app in
                app.bundleIdentifier == "com.lindemannm.Silocleaner" &&
                app.processIdentifier != ProcessInfo.processInfo.processIdentifier
            }

            if silocleanerRunning {
                return requestPasswordFromMainApp()
            } else {
                _ = NSApplication.shared
                return Self.showPasswordDialog(message: message)
            }
        }

        // MARK: - Request Password from Main App
        private func requestPasswordFromMainApp() -> String? {
            let center = DistributedNotificationCenter.default()
            let requestId = UUID().uuidString
            var receivedPassword: String?
            let semaphore = DispatchSemaphore(value: 0)

            let observerQueue = OperationQueue()
            let observer = center.addObserver(
                forName: NSNotification.Name("com.lindemannm.Silocleaner.passwordResponse"),
                object: nil,
                queue: observerQueue
            ) { notification in
                if let userInfo = notification.userInfo,
                   let responseId = userInfo["requestId"] as? String,
                   responseId == requestId {
                    receivedPassword = userInfo["password"] as? String
                    semaphore.signal()
                }
            }

            center.postNotificationName(
                NSNotification.Name("com.lindemannm.Silocleaner.passwordRequest"),
                object: nil,
                userInfo: [
                    "requestId": requestId,
                    "message": message
                ],
                deliverImmediately: true
            )

            let timeout = DispatchTime.now() + .seconds(60)
            if semaphore.wait(timeout: timeout) == .success {
                center.removeObserver(observer)
                return receivedPassword?.isEmpty == false ? receivedPassword : nil
            } else {
                center.removeObserver(observer)
                return nil
            }
        }

        // MARK: - Show Password Dialog
        private static func showPasswordDialog(message: String) -> String? {
            let alert = NSAlert()
            alert.messageText = "Silocleaner"
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")

            let secureTextField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
            secureTextField.placeholderString = "Password"
            alert.accessoryView = secureTextField
            alert.window.initialFirstResponder = secureTextField

            NSApp.activate(ignoringOtherApps: true)

            let response = alert.runModal()

            if response == .alertFirstButtonReturn {
                let password = secureTextField.stringValue
                return password.isEmpty ? nil : password
            }

            return nil
        }
    }
}
