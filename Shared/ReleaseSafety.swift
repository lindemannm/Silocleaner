import Foundation

enum SilocleanerDeepLink {
    static let scheme = "silocleaner"

    static let actions: Set<String> = [
        "openSilocleaner", "openSettings", "openPermissions", "uninstallApp",
        "checkOrphanedFiles", "checkDevEnv", "appLipo", "checkUpdates",
        "appsPaths", "orphanedPaths", "refreshAppsList", "resetSettings"
    ]

    static func isAppURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme
    }

    static func isKnownAction(_ action: String?) -> Bool {
        guard let action else { return false }
        return actions.contains(action)
    }
}

enum SilocleanerPathPolicy {
    static func isRestrictedApplication(_ url: URL, protectedBundleURL: URL?) -> Bool {
        let path = url.standardizedFileURL.path
        let safari = "/Applications/Safari.app"
        let utilities = "/Applications/Utilities"

        if path == safari || path.hasPrefix(safari + "/") ||
            path == utilities || path.hasPrefix(utilities + "/") {
            return true
        }

        guard let protectedBundleURL else { return false }
        let protectedPath = protectedBundleURL.standardizedFileURL.path
        return path == protectedPath || path.hasPrefix(protectedPath + "/")
    }
}

enum DestructiveOperationPreview {
    static func message(for paths: [URL]) -> String {
        let sortedPaths = paths.map(\.path).sorted()
        let heading = "Preview — the following \(sortedPaths.count) item(s) would be moved to the Trash:"
        return ([heading] + sortedPaths + ["Re-run this command with --yes to confirm."]).joined(separator: "\n")
    }
}

enum PrivateTemporaryDirectory {
    static func create(fileManager: FileManager = .default) throws -> URL {
        let directory = fileManager.temporaryDirectory.appendingPathComponent(
            "silocleaner-install-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        return directory
    }

    static func remove(_ directory: URL, fileManager: FileManager = .default) throws {
        try fileManager.removeItem(at: directory)
    }
}
