import Foundation

/// A fixture-safe representation of a direct filesystem operation. The app
/// converts these to `Process` calls only after the plan has been approved.
struct FileOperation: Equatable {
    let executable: String
    let arguments: [String]
}

/// The result of the non-mutating preflight performed before a destructive CLI
/// operation. Keeping the decision separate from presentation makes it
/// testable without launching the app or touching the user's Trash.
enum DestructiveOperationAuthorization: Equatable {
    case confirmationRequired(preview: String)
    case privilegedAuthorizationRequired(protectedPaths: [String])
    case authorized

    static func evaluate(
        paths: [URL],
        acknowledged: Bool,
        hasPrivilegedAuthorization: Bool,
        isWritable: (URL) -> Bool
    ) -> Self {
        guard acknowledged else {
            return .confirmationRequired(preview: DestructiveOperationPreview.message(for: paths))
        }

        let protectedPaths = paths
            .filter { !isWritable($0) }
            .map(\.path)
            .sorted()
        guard protectedPaths.isEmpty || hasPrivilegedAuthorization else {
            return .privilegedAuthorizationRequired(protectedPaths: protectedPaths)
        }

        return .authorized
    }
}

/// Plans deletion and inverse restore operations without performing either.
/// It is deliberately ignorant of the real filesystem except for the injected
/// collision check, so tests can exercise the exact production planning rules
/// using isolated fixture URLs.
struct TrashMovePlan: Equatable {
    struct FilePair: Equatable {
        let trashURL: URL
        let originalURL: URL
    }

    let bundleFolderURL: URL
    let filePairs: [FilePair]
    let deleteOperations: [FileOperation]

    static func make(
        files: [URL],
        trashDirectoryURL: URL,
        bundleFolderName: String,
        destinationExists: (URL) -> Bool
    ) -> TrashMovePlan {
        let bundleFolderURL = trashDirectoryURL.appendingPathComponent(bundleFolderName, isDirectory: true)
        var seenFileNames: [String: Int] = [:]
        var filePairs: [FilePair] = []

        for file in files {
            let baseName = file.lastPathComponent
            var count = seenFileNames[baseName] ?? 0
            var finalName = baseName
            repeat {
                if count > 0 {
                    finalName = "\(baseName)-\(count)"
                }
                count += 1
            } while destinationExists(bundleFolderURL.appendingPathComponent(finalName))
            seenFileNames[baseName] = count

            filePairs.append(
                FilePair(
                    trashURL: bundleFolderURL.appendingPathComponent(finalName),
                    originalURL: file
                )
            )
        }

        let operations = [FileOperation(executable: "/bin/mkdir", arguments: ["-p", bundleFolderURL.path])]
            + filePairs.map { FileOperation(executable: "/bin/mv", arguments: [$0.originalURL.path, $0.trashURL.path]) }
        return TrashMovePlan(
            bundleFolderURL: bundleFolderURL,
            filePairs: filePairs,
            deleteOperations: operations
        )
    }

    static func restoreOperations(for filePairs: [FilePair]) -> [FileOperation] {
        var operations = filePairs.map {
            FileOperation(executable: "/bin/mv", arguments: [$0.trashURL.path, $0.originalURL.path])
        }
        guard let bundleFolderURL = filePairs.first?.trashURL.deletingLastPathComponent(),
              bundleFolderURL.lastPathComponent.contains("_") else {
            return operations
        }
        operations.append(FileOperation(executable: "/bin/rmdir", arguments: [bundleFolderURL.path]))
        return operations
    }
}
