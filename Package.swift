// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StayWake",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "StayWake", path: "Sources/StayWake")
    ]
)
