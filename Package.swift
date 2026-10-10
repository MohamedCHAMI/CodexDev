// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexDev",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "CodexDev",
            path: "Sources/CodexDev"
        )
    ]
)
