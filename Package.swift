// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BoosteroidPresence",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "BoosteroidPresence", targets: ["BoosteroidPresence"])
    ],
    targets: [
        .executableTarget(
            name: "BoosteroidPresence",
            resources: [.process("Resources")],
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-strict-concurrency=minimal"])
            ]
        ),
        .testTarget(
            name: "BoosteroidPresenceTests",
            dependencies: ["BoosteroidPresence"]
        )
    ]
)
