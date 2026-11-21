// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RepoSelect",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "RepoSelect", path: "Sources/RepoSelect"),
        .testTarget(name: "RepoSelectTests", dependencies: ["RepoSelect"], path: "Tests/RepoSelectTests"),
    ]
)
