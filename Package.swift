// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "blox",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "bloxKit"),
        .executableTarget(
            name: "blox",
            dependencies: ["bloxKit"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "blox-selftest",
            dependencies: ["bloxKit"]
        )
    ]
)
