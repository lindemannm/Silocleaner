import Foundation

/// Environment policy for user-owned subprocesses. It deliberately does not
/// inherit `SHELL`, `BASH_ENV`, `ENV`, or a shell-derived `PATH`: no shell is
/// launched to construct this dictionary.
enum UserProcessEnvironment {
    static let executableSearchPath = [
        "/opt/homebrew/bin", "/opt/homebrew/sbin",
        "/usr/local/bin", "/usr/local/sbin",
        "/usr/bin", "/bin", "/usr/sbin", "/sbin"
    ].joined(separator: ":")

    static func make(
        homeDirectory: URL,
        temporaryDirectory: URL,
        inheritedEnvironment _: [String: String] = [:]
    ) -> [String: String] {
        [
            "HOME": homeDirectory.standardizedFileURL.path,
            "TMPDIR": temporaryDirectory.standardizedFileURL.path,
            "PATH": executableSearchPath
        ]
    }
}
