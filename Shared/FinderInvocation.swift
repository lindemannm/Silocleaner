import Foundation

enum SilocleanerDeepLinkRoute: Equatable {
    case externalFile(URL)
    case finderApplication(URL)
    case serviceApplication(URL)
    case action(String)
    case rejected
}

/// The Finder extension and main app share this policy so that a context-menu
/// item, its URL, and its receiving route all agree on the allowed scope.
enum FinderInvocationPolicy {
    static let scheme = "silocleaner"
    static let finderHost = "com.lindemannm.Silocleaner"

    static func applicationDirectories(homeDirectory: URL) -> [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        ].map(\.standardizedFileURL)
    }

    static func selectedApplicationURL(
        from selections: [URL],
        applicationDirectories: [URL]
    ) -> URL? {
        guard selections.count == 1, let selection = selections.first else { return nil }
        return isAllowedApplication(selection, applicationDirectories: applicationDirectories)
            ? selection.standardizedFileURL
            : nil
    }

    static func finderDeepLink(
        for selections: [URL],
        applicationDirectories: [URL]
    ) -> URL? {
        guard let applicationURL = selectedApplicationURL(
            from: selections,
            applicationDirectories: applicationDirectories
        ) else { return nil }

        var components = URLComponents()
        components.scheme = scheme
        components.host = finderHost
        components.queryItems = [URLQueryItem(name: "path", value: applicationURL.path)]
        return components.url
    }

    static func applicationURL(
        fromFinderDeepLink url: URL,
        applicationDirectories: [URL]
    ) -> URL? {
        guard url.scheme?.lowercased() == scheme,
              url.host == finderHost,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              queryItems.count == 1,
              queryItems[0].name == "path",
              let path = queryItems[0].value,
              !path.isEmpty else { return nil }

        let applicationURL = URL(fileURLWithPath: path).standardizedFileURL
        return isAllowedApplication(applicationURL, applicationDirectories: applicationDirectories)
            ? applicationURL
            : nil
    }

    private static func isAllowedApplication(
        _ url: URL,
        applicationDirectories: [URL]
    ) -> Bool {
        let applicationURL = url.standardizedFileURL
        guard applicationURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
            return false
        }

        return applicationDirectories.contains { directory in
            let directoryPath = directory.standardizedFileURL.path
            let applicationPath = applicationURL.path
            return applicationPath.hasPrefix(directoryPath + "/")
        }
    }
}
