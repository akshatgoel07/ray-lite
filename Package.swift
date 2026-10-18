// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "RayLite",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "RayLite",
            path: "Sources/RayLite",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "RayLiteTests",
            dependencies: ["RayLite"],
            path: "Tests/RayLiteTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
