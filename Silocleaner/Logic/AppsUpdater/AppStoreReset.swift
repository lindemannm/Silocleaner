//
//  AppStoreReset.swift
//  Silocleaner
//
//  Resetting App Store processes and caches required private frameworks and is
//  intentionally unavailable in distributable Silocleaner builds.
//

import Foundation

enum AppStoreReset {
    static func reset() async -> Result<Void, Error> {
        .failure(ResetError.unavailable)
    }

    enum ResetError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "App Store reset is unavailable because it relies on unsupported macOS internals."
        }
    }
}
