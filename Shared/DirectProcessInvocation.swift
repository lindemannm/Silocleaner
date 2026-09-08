import Foundation

/// A process launched through Foundation with explicit executable, arguments, and
/// environment. This deliberately has no shell-command representation.
struct DirectProcessInvocation: Equatable {
    let executableURL: URL
    let arguments: [String]
    let environment: [String: String]

    init(
        executablePath: String,
        arguments: [String],
        userEnvironment: [String: String],
        prependExecutableDirectoryToPath: Bool = false
    ) {
        executableURL = URL(fileURLWithPath: executablePath)
        self.arguments = arguments

        var environment = userEnvironment
        if prependExecutableDirectoryToPath {
            let executableDirectory = executableURL.deletingLastPathComponent().path
            let inheritedPath = environment["PATH"]
            environment["PATH"] = inheritedPath.map { "\(executableDirectory):\($0)" } ?? executableDirectory
        }
        self.environment = environment
    }

    func makeProcess() -> Process {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        return process
    }
}
