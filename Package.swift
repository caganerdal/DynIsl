// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DynIsl",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "DynIsl", path: "Sources/DynIsl")
    ]
)
