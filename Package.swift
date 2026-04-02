// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QuitProtect",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "QuitProtect",
            path: "Sources",
            linkerSettings: [
                .unsafeFlags(["-framework", "AppKit"]),
                .unsafeFlags(["-framework", "ApplicationServices"]),
                .unsafeFlags(["-framework", "Carbon"]),
                .unsafeFlags(["-framework", "ServiceManagement"]),
            ]
        )
    ]
)
