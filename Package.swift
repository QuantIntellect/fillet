// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Fillet",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Fillet", path: "Sources/Fillet")
    ]
)
