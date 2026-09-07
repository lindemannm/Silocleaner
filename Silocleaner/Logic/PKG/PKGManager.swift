//
//  PKGManager.swift
//  Silocleaner
//
//  Package receipt access through the public pkgutil interface.
//

import Foundation

enum PKGManager {
    static func getAllPackages() -> [PackageInfo] {
        runPkgutil(["--pkgs"]).compactMap(packageInfo)
    }

    static func getPackageFiles(packageID: String, installLocation: String) -> [String] {
        runPkgutil(["--files", packageID]).map { path in
            path.hasPrefix("/") ? path : URL(fileURLWithPath: installLocation).appendingPathComponent(path).path
        }.filter { !$0.contains("._") }
    }

    private static func packageInfo(packageID: String) -> PackageInfo? {
        let fields = Dictionary(uniqueKeysWithValues: runPkgutil(["--pkg-info", packageID]).compactMap { line -> (String, String)? in
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return (parts[0].trimmingCharacters(in: .whitespaces), parts[1].trimmingCharacters(in: .whitespaces))
        })
        guard !fields.isEmpty else { return nil }

        let receiptRoot = "/var/db/receipts/\(packageID)"
        let receiptPaths = ["\(receiptRoot).plist", "\(receiptRoot).bom"].filter(FileManager.default.fileExists)
        return PackageInfo(
            packageId: packageID, packageName: "", packageFileName: "",
            version: fields["version"] ?? "", installDate: fields["install-time"] ?? "",
            installProcessName: fields["installer"] ?? "", bomFiles: [],
            receiptPath: receiptPaths.first ?? "\(receiptRoot).plist",
            installLocation: fields["volume"] ?? "/", packageGroups: [], additionalInfo: "",
            isSecure: false, receiptStoragePaths: receiptPaths, totalSizeFromBOM: 0, totalFilesInBOM: 0
        )
    }

    private static func runPkgutil(_ arguments: [String]) -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/pkgutil")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do { try process.run() } catch { return [] }
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline).map(String.init)
    }
}
