//
//  UndoManager.swift
//  Silocleaner
//
//  Created by Alin Lupascu on 2/24/25.
//

import Foundation
import SwiftUI
import AlinFoundation

class FileManagerUndo {
    // MARK: - Singleton Instance
    static let shared = FileManagerUndo()

    // Private initializer to enforce singleton pattern
    private init() {}

    // NSUndoManager instance to handle undo/redo actions
    let undoManager = UndoManager()

    // MARK: - Path Validation
    /// Validates that a path is safe to delete (not a critical system path or app folder)
    private func validatePath(_ path: String) -> Bool {
        // Normalize path
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path

        // Block empty paths
        guard !normalizedPath.trimmingCharacters(in: .whitespaces).isEmpty else {
            printOS("⚠️ Blocked deletion: Empty path")
            return false
        }

        // Combine critical system paths + user app folder paths into single set
        let criticalSystemPaths = [
            "/",
            "/Applications",
            "/Library",
            "/System",
            "/usr",
            "/bin",
            "/sbin",
            "/etc",
            "/var",
            "/private",
            "/opt",
            NSHomeDirectory()
        ]

        let userAppPaths = FolderSettingsManager.shared.folderPaths
        let blockedPaths = Set(criticalSystemPaths + userAppPaths)

        // Block if path exactly matches any blocked path
        if blockedPaths.contains(normalizedPath) {
            printOS("⚠️ Blocked deletion: Protected path '\(normalizedPath)'")
            return false
        }

        return true
    }

    func deleteFiles(at urls: [URL], isCLI: Bool = false, bundleName: String? = nil) -> Bool {
        // Filter out invalid/dangerous paths before deletion
        let validURLs = urls.filter { validatePath($0.path) }

        // If no valid paths remain, return early
        guard !validURLs.isEmpty else {
            printOS("⚠️ All paths were blocked - no files deleted")
            return false
        }

        // Log if any paths were filtered out
        if validURLs.count < urls.count {
            printOS("⚠️ Filtered out \(urls.count - validURLs.count) dangerous path(s)")
        }
        let trashPath = (NSHomeDirectory() as NSString).appendingPathComponent(".Trash")
        let dispatchSemaphore = DispatchSemaphore(value: 0)  // Semaphore to make it synchronous
        var finalStatus = false  // Store the final success/failure status

        let hasProtectedFiles = validURLs.contains { $0.isProtected }

        // Create bundle folder name with app name and timestamp
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())

        let folderName: String
        if let customBundleName = bundleName {
            folderName = customBundleName
        } else if !AppState.shared.appInfo.appName.isEmpty {
            folderName = AppState.shared.appInfo.appName
        } else {
            // Fallback for plugins: use the first file's name or "Mixed Files"
            if let firstFile = validURLs.first {
                folderName = firstFile.deletingPathExtension().lastPathComponent
            } else {
                folderName = "Mixed Files"
            }
        }

        let bundleFolderName = "\(folderName)_\(timestamp)"
        let plan = TrashMovePlan.make(
            files: validURLs,
            trashDirectoryURL: URL(fileURLWithPath: trashPath, isDirectory: true),
            bundleFolderName: bundleFolderName,
            destinationExists: { FileManager.default.fileExists(atPath: $0.path) }
        )
        let bundleFolderPath = plan.bundleFolderURL.path
        let operations = plan.deleteOperations.map { ($0.executable, $0.arguments) }
        let filePairs = plan.filePairs.map { (trashURL: $0.trashURL, originalURL: $0.originalURL) }

        if executeFileOperations(operations, isCLI: isCLI, hasProtectedFiles: hasProtectedFiles) {
            undoManager.registerUndo(withTarget: self) { target in
                let result = target.restoreFiles(filePairs: filePairs)
                if !result {
                    printOS("Trash Error: Could not restore files.")
                }
            }
            undoManager.setActionName("Delete File")

            // Record in persistent history
            Task { @MainActor in
                UndoHistoryManager.shared.addRecord(
                    appName: folderName,
                    bundleFolderPath: bundleFolderPath,
                    filePairs: filePairs.map { ($0.originalURL.path, $0.trashURL.path) }
                )
            }

            // Play trash sound after successful deletion
            if !isCLI {
                playTrashSound()
            }

            finalStatus = true
        } else {
            //            printOS("Trash Error: \(isCLI ? "Could not run commands directly with sudo." : "Could not perform privileged commands.")")
            updateOnMain {
                AppState.shared.trashError = true
            }
            finalStatus = false
        }

        dispatchSemaphore.signal()

        dispatchSemaphore.wait()
        return finalStatus
    }

    func restoreFiles(filePairs: [(trashURL: URL, originalURL: URL)], isCLI: Bool = false) -> Bool {
        let dispatchSemaphore = DispatchSemaphore(value: 0)
        var finalStatus = true

        let hasProtectedFiles = filePairs.contains {
            $0.originalURL.deletingLastPathComponent().isProtected
        }

        let plannedPairs = filePairs.map { TrashMovePlan.FilePair(trashURL: $0.trashURL, originalURL: $0.originalURL) }
        let operations = TrashMovePlan.restoreOperations(for: plannedPairs).map { ($0.executable, $0.arguments) }
        let bundleFolderToRemove = plannedPairs.first?.trashURL.deletingLastPathComponent().lastPathComponent.contains("_") == true
            ? plannedPairs.first?.trashURL.deletingLastPathComponent().path
            : nil

        if executeFileOperations(operations, isCLI: isCLI, hasProtectedFiles: hasProtectedFiles, isRestore: true) {
            // Remove from persistent history after successful restore
            if let bundleFolder = bundleFolderToRemove {
                Task { @MainActor in
                    UndoHistoryManager.shared.removeRecord(bundleFolderPath: bundleFolder)
                }
            }

            finalStatus = true
        } else {
            //            printOS("Trash Error: \(isCLI ? "Failed to run restore CLI commands" : "Failed to run restore privileged commands")")
            updateOnMain {
                AppState.shared.trashError = true
            }
            finalStatus = false
        }

        dispatchSemaphore.signal()
        dispatchSemaphore.wait()
        return finalStatus
    }

    // Executes file operations without creating shell source from file paths.
    private func executeFileOperations(_ operations: [(String, [String])], isCLI: Bool, hasProtectedFiles: Bool, isRestore: Bool = false) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var status = false

        Task {
            for (tool, arguments) in operations {
                let result = try! await runPrivilegedTool(
                    tool, arguments: arguments,
                    errorContext: isRestore ? "Undo restore operation failed" : "Undo delete operation failed",
                    throwOnFailure: false
                )
                status = result.0
                if !status { break }
            }

            if !status {
                printOS(isRestore ? "Restore operation failed" : "Trash operation failed")
                updateOnMain {
                    AppState.shared.trashError = true
                }

                // Fallback to direct shell if appropriate
                if isCLI || !hasProtectedFiles {
                    status = operations.allSatisfy { runDirectTool($0.0, arguments: $0.1) }
                    if !status {
                        printOS(isRestore ? "Restore operation failed" : "Trash operation failed")
                        updateOnMain {
                            AppState.shared.trashError = true
                        }
                    }
                }
            }

            semaphore.signal()
        }
        semaphore.wait()

        return status
    }

    private func runDirectTool(_ executable: String, arguments: [String]) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        do {
            try task.run()
        } catch {
            return false
        }
        task.waitUntilExit()
        return task.terminationStatus == 0
    }

}

extension URL {
    var isProtected: Bool {
        !FileManager.default.isWritableFile(atPath: self.path)
    }
}
