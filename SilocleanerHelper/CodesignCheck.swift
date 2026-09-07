// Validates that an XPC client is the signed main application which owns this
// helper. Sharing a signing certificate does not authorise a process.

import Foundation
import Security

enum CodesignCheckError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(message): message
        }
    }
}

struct CodesignCheck {
    /// Checks the connecting process against the main app's designated
    /// requirement. It is tied to both the exact bundle ID and the Developer
    /// ID team that signed this helper.
    static func isAuthorizedClient(pid: pid_t) throws -> Bool {
        let helperSigningInfo = try signingInformation(for: try staticCodeForSelf())
        guard
            let helperIdentifier = helperSigningInfo[kSecCodeInfoIdentifier as String] as? String,
            let teamIdentifier = helperSigningInfo[kSecCodeInfoTeamIdentifier as String] as? String,
            let mainAppIdentifier = mainAppIdentifier(forHelperIdentifier: helperIdentifier)
        else {
            throw CodesignCheckError.message("Helper is not signed with a configured application identity")
        }

        let requirement = try clientRequirement(bundleIdentifier: mainAppIdentifier, teamIdentifier: teamIdentifier)
        let status = SecCodeCheckValidity(try codeForProcess(pid), SecCSFlags(rawValue: kSecCSStrictValidate), requirement)
        return status == errSecSuccess
    }

    // Internal so a future helper test target can exercise requirement
    // construction without needing a signed process.
    static func clientRequirement(bundleIdentifier: String, teamIdentifier: String) throws -> SecRequirement {
        guard isValidRequirementComponent(bundleIdentifier), isValidRequirementComponent(teamIdentifier) else {
            throw CodesignCheckError.message("Invalid helper client identity")
        }

        let source = "anchor apple generic and identifier \"\(bundleIdentifier)\" and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
        var requirement: SecRequirement?
        try checkStatus(SecRequirementCreateWithString(source as CFString, [], &requirement))
        guard let requirement else {
            throw CodesignCheckError.message("Security framework returned an empty requirement")
        }
        return requirement
    }

    private static func mainAppIdentifier(forHelperIdentifier helperIdentifier: String) -> String? {
        guard let finalSeparator = helperIdentifier.lastIndex(of: ".") else { return nil }
        let mainAppIdentifier = String(helperIdentifier[..<finalSeparator])
        return isValidRequirementComponent(mainAppIdentifier) ? mainAppIdentifier : nil
    }

    private static func isValidRequirementComponent(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "-"
        }
    }

    private static func staticCodeForSelf() throws -> SecStaticCode {
        var selfCode: SecCode?
        try checkStatus(SecCodeCopySelf([], &selfCode))
        guard let selfCode else {
            throw CodesignCheckError.message("Security framework returned an empty self code reference")
        }

        var staticCode: SecStaticCode?
        try checkStatus(SecCodeCopyStaticCode(selfCode, [], &staticCode))
        guard let staticCode else {
            throw CodesignCheckError.message("Security framework returned an empty static code reference")
        }
        return staticCode
    }

    private static func codeForProcess(_ pid: pid_t) throws -> SecCode {
        var clientCode: SecCode?
        try checkStatus(SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid: pid] as CFDictionary, [], &clientCode))
        guard let clientCode else {
            throw CodesignCheckError.message("Security framework returned an empty client code reference")
        }
        return clientCode
    }

    private static func signingInformation(for staticCode: SecStaticCode) throws -> [String: Any] {
        var signingInfo: CFDictionary?
        try checkStatus(SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &signingInfo))
        guard let signingInfo = signingInfo as? [String: Any] else {
            throw CodesignCheckError.message("Security framework returned empty signing information")
        }
        return signingInfo
    }

    private static func checkStatus(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            throw CodesignCheckError.message(message)
        }
    }
}
