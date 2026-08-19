// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QuitProtect",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "QuitProtectCore", path: "Sources/Core"),
        .executableTarget(
            name: "QuitProtect",
            dependencies: ["QuitProtectCore"],
            path: "Sources",
            exclude: ["Core"],
            linkerSettings: [
                .unsafeFlags(["-framework", "AppKit"]),
                .unsafeFlags(["-framework", "ApplicationServices"]),
                .unsafeFlags(["-framework", "Carbon"]),
                .unsafeFlags(["-framework", "ServiceManagement"]),
            ]
        ),
        .testTarget(
            name: "QuitProtectTests",
            dependencies: ["QuitProtectCore"],
            path: "Tests"
        )
    ]
)
