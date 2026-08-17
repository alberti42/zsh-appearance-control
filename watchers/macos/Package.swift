// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "zac-watch-macos",
    platforms: [.macOS(.v11)],
    targets: [
        .executableTarget(
            name: "zac-watch-macos",
            path: "Sources/zac-watch-macos",
            swiftSettings: [.unsafeFlags(["-Osize"], .when(configuration: .release))]
        )
    ]
)
