// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LeanGitHub",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "LeanGitHub", path: "Sources/LeanGitHub"),
        .testTarget(name: "LeanGitHubTests", dependencies: ["LeanGitHub"], path: "Tests/LeanGitHubTests"),
    ]
)
