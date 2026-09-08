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

    func testDestructivePreflightRequiresConfirmationBeforeAnyAuthorizationCheck() {
        let paths = [
            URL(fileURLWithPath: "/fixtures/Bravo"),
            URL(fileURLWithPath: "/fixtures/Alpha")
        ]

        let decision = DestructiveOperationAuthorization.evaluate(
            paths: paths,
            acknowledged: false,
            hasPrivilegedAuthorization: false,
            isWritable: { _ in false }
        )

        XCTAssertEqual(
            decision,
            .confirmationRequired(
                preview: "Preview — the following 2 item(s) would be moved to the Trash:\n/fixtures/Alpha\n/fixtures/Bravo\nRe-run this command with --yes to confirm."
            )
        )
    }

    func testDestructivePreflightFailsClosedForProtectedPathsWithoutAuthorization() {
        let writable = URL(fileURLWithPath: "/fixtures/writable")
        let protected = URL(fileURLWithPath: "/fixtures/protected")

        let decision = DestructiveOperationAuthorization.evaluate(
            paths: [writable, protected],
            acknowledged: true,
            hasPrivilegedAuthorization: false,
            isWritable: { $0 == writable }
        )

        XCTAssertEqual(decision, .privilegedAuthorizationRequired(protectedPaths: [protected.path]))
    }

    func testDestructivePreflightAuthorizesWritableFixturesWithoutPrivilege() {
        let paths = [URL(fileURLWithPath: "/fixtures/one"), URL(fileURLWithPath: "/fixtures/two")]
        XCTAssertEqual(
            DestructiveOperationAuthorization.evaluate(
                paths: paths,
                acknowledged: true,
                hasPrivilegedAuthorization: false,
                isWritable: { _ in true }
            ),
            .authorized
        )
    }

    func testTrashMovePlanBuildsLiteralMoveArgumentsAndInverseUndo() {
        let fixtureRoot = URL(fileURLWithPath: "/fixtures", isDirectory: true)
        let trash = fixtureRoot.appendingPathComponent("Trash", isDirectory: true)
        let first = fixtureRoot.appendingPathComponent("first/report; keep.txt")
        let second = fixtureRoot.appendingPathComponent("second/report; keep.txt")
        let plan = TrashMovePlan.make(
            files: [first, second],
            trashDirectoryURL: trash,
            bundleFolderName: "Silocleaner_2026-09-08_19-45-00",
            destinationExists: { _ in false }
        )

        XCTAssertEqual(plan.deleteOperations[0], FileOperation(executable: "/bin/mkdir", arguments: ["-p", plan.bundleFolderURL.path]))
        XCTAssertEqual(plan.filePairs.map(\.trashURL.path), [
            "/fixtures/Trash/Silocleaner_2026-09-08_19-45-00/report; keep.txt",
            "/fixtures/Trash/Silocleaner_2026-09-08_19-45-00/report; keep.txt-1"
        ])
        XCTAssertEqual(plan.deleteOperations[1].arguments, [first.path, plan.filePairs[0].trashURL.path])
        XCTAssertEqual(plan.deleteOperations[2].arguments, [second.path, plan.filePairs[1].trashURL.path])

        XCTAssertEqual(
            TrashMovePlan.restoreOperations(for: plan.filePairs),
            [
                FileOperation(executable: "/bin/mv", arguments: [plan.filePairs[0].trashURL.path, first.path]),
                FileOperation(executable: "/bin/mv", arguments: [plan.filePairs[1].trashURL.path, second.path]),
                FileOperation(executable: "/bin/rmdir", arguments: [plan.bundleFolderURL.path])
            ]
        )
    }
}
