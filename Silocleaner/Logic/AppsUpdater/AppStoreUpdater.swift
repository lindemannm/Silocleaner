//
//  AppStoreUpdater.swift
//  Silocleaner
//
//  The App Store owns installation. Silocleaner can discover updates using
//  Apple's public lookup API, then hands the user to the App Store.
//

import AppKit
import Foundation

final class AppStoreUpdater {
    enum Error: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "Unable to open this app in the App Store."
        }
    }

    static let shared = AppStoreUpdater()

    func updateApp(adamID: UInt64, appPath: URL, isIOSApp: Bool, progress: @escaping (Double, String) -> Void) async throws {
        progress(0, "Opening App Store")
        guard let url = URL(string: "macappstore://itunes.apple.com/app/id\(adamID)") else {
            throw Error.unavailable
        }
        guard NSWorkspace.shared.open(url) else { throw Error.unavailable }
        progress(1, "Open in App Store")
    }
}
