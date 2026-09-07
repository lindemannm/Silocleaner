// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SilocleanerHelperSecurity",
    platforms: [.macOS(.v13)],
    products: [.library(name: "SilocleanerHelperSecurity", targets: ["SilocleanerHelperSecurity"])],
    targets: [
        .target(
            name: "SilocleanerCore",
            path: "Shared",
            exclude: ["AppGroupDefaults.swift"],
            sources: ["ReleaseSafety.swift"]
        ),
        .target(
            name: "SilocleanerHelperSecurity",
            path: "SilocleanerHelper",
            exclude: ["main.swift", "com.lindemannm.Silocleaner.SilocleanerHelper.plist"]
        ),
        .testTarget(
            name: "SilocleanerHelperSecurityTests",
            dependencies: ["SilocleanerHelperSecurity"],
            path: "HelperSecurityTests"
        ),
        .testTarget(
            name: "SilocleanerCoreTests",
            dependencies: ["SilocleanerCore"],
            path: "CoreTests"
        )
    ]
)
