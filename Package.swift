// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Today",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Today",
            path: "Sources/Today"
        )
    ]
)
