// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SilocleanerHelperSecurity",
    platforms: [.macOS(.v13)],
    products: [.library(name: "SilocleanerHelperSecurity", targets: ["SilocleanerHelperSecurity"])],
    targets: [
        .target(
            name: "SilocleanerHelperSecurity",
            path: "SilocleanerHelper",
            exclude: ["main.swift", "com.lindemannm.Silocleaner.SilocleanerHelper.plist"]
        ),
        .testTarget(
            name: "SilocleanerHelperSecurityTests",
            dependencies: ["SilocleanerHelperSecurity"],
            path: "HelperSecurityTests"
        )
    ]
)
