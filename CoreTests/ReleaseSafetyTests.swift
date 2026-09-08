import Foundation
import XCTest
@testable import SilocleanerCore

final class ReleaseSafetyTests: XCTestCase {
    func testSilocleanerDeepLinkAcceptsOnlyTheFinalSchemeAndKnownActions() {
        XCTAssertTrue(SilocleanerDeepLink.isAppURL(URL(string: "silocleaner://openSettings")!))
        XCTAssertFalse(SilocleanerDeepLink.isAppURL(URL(string: "pear://openSettings")!))
        XCTAssertTrue(SilocleanerDeepLink.isKnownAction("openSettings"))
        XCTAssertFalse(SilocleanerDeepLink.isKnownAction("runShellCommand"))
    }

    func testRestrictedApplicationPolicyUsesPathBoundaries() {
        XCTAssertTrue(SilocleanerPathPolicy.isRestrictedApplication(URL(fileURLWithPath: "/Applications/Safari.app"), protectedBundleURL: nil))
        XCTAssertTrue(SilocleanerPathPolicy.isRestrictedApplication(URL(fileURLWithPath: "/Applications/Utilities/Terminal.app"), protectedBundleURL: nil))
        XCTAssertFalse(SilocleanerPathPolicy.isRestrictedApplication(URL(fileURLWithPath: "/Applications/Safari.app.backup"), protectedBundleURL: nil))
        XCTAssertTrue(SilocleanerPathPolicy.isRestrictedApplication(URL(fileURLWithPath: "/Applications/Silocleaner.app/Contents/MacOS/Silocleaner"), protectedBundleURL: URL(fileURLWithPath: "/Applications/Silocleaner.app")))
    }

    func testDestructivePreviewIsSortedAndRequiresExplicitConfirmation() {
        let message = DestructiveOperationPreview.message(for: [
            URL(fileURLWithPath: "/tmp/zeta"), URL(fileURLWithPath: "/tmp/alpha")
        ])
        XCTAssertEqual(message, "Preview — the following 2 item(s) would be moved to the Trash:\n/tmp/alpha\n/tmp/zeta\nRe-run this command with --yes to confirm.")
    }

    func testPrivateTemporaryDirectoryIsPrivateAndRemoved() throws {
        let directory = try PrivateTemporaryDirectory.create()
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        try PrivateTemporaryDirectory.remove(directory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testDirectProcessInvocationPreservesMetacharactersAsArguments() {
        let packageName = "example; touch /tmp/should-not-run $(whoami) 'quoted'"
        let invocation = DirectProcessInvocation(
            executablePath: "/Applications/Python 3/bin/python3",
            arguments: ["-m", "pip", "uninstall", "-y", packageName],
            userEnvironment: ["PATH": "/usr/local/bin:/usr/bin", "HOME": "/Users/tester"],
            prependExecutableDirectoryToPath: true
        )

        XCTAssertEqual(invocation.executableURL.path, "/Applications/Python 3/bin/python3")
        XCTAssertEqual(invocation.arguments, ["-m", "pip", "uninstall", "-y", packageName])
        XCTAssertEqual(invocation.environment["PATH"], "/Applications/Python 3/bin:/usr/local/bin:/usr/bin")
        XCTAssertEqual(invocation.environment["HOME"], "/Users/tester")
    }

    func testDirectProcessInvocationDoesNotNeedAUserShellPath() {
        let optionLikeValue = "--config=$(id); echo unexpected"
        let invocation = DirectProcessInvocation(
            executablePath: "/opt/custom python/bin/python3",
            arguments: ["-m", "pip", "show", optionLikeValue],
            userEnvironment: [:],
            prependExecutableDirectoryToPath: true
        )

        XCTAssertEqual(invocation.arguments.last, optionLikeValue)
        XCTAssertEqual(invocation.environment["PATH"], "/opt/custom python/bin")

        let process = invocation.makeProcess()
        XCTAssertEqual(process.executableURL, invocation.executableURL)
        XCTAssertEqual(process.arguments, invocation.arguments)
        XCTAssertEqual(process.environment, invocation.environment)
    }
}
