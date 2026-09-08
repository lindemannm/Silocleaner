import Foundation

enum SilocleanerDeepLink {
    static let scheme = FinderInvocationPolicy.scheme

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

    static func route(_ url: URL, homeDirectory: URL) -> SilocleanerDeepLinkRoute {
        guard isAppURL(url) else { return .externalFile(url) }

        let applicationDirectories = FinderInvocationPolicy.applicationDirectories(homeDirectory: homeDirectory)
        if url.host == FinderInvocationPolicy.finderHost {
            guard let applicationURL = FinderInvocationPolicy.applicationURL(
                fromFinderDeepLink: url,
                applicationDirectories: applicationDirectories
            ) else { return .rejected }
            return .finderApplication(applicationURL)
        }

        guard let host = url.host, isKnownAction(host) else { return .rejected }
        if host == "uninstallApp" {
            guard let applicationURL = applicationURL(fromServiceDeepLink: url) else {
                return .rejected
            }
            return .serviceApplication(applicationURL)
        }
        return .action(host)
    }

    static func serviceDeepLink(for applicationURL: URL) -> URL? {
        guard applicationURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
            return nil
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = "uninstallApp"
        components.queryItems = [URLQueryItem(name: "path", value: applicationURL.standardizedFileURL.path)]
        return components.url
    }

    private static func applicationURL(fromServiceDeepLink url: URL) -> URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              queryItems.count == 1,
              queryItems[0].name == "path",
              let path = queryItems[0].value,
              !path.isEmpty else { return nil }
        let applicationURL = URL(fileURLWithPath: path).standardizedFileURL
        return applicationURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame
            ? applicationURL
            : nil
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
