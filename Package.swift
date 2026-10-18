// swift-tools-version:6.2
import Foundation
import PackageDescription

let package = Package(
    name: "ray-lite",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "ray-lite", targets: ["RayLite"])
    ],
    targets: [
        .executableTarget(
            name: "RayLite",
            path: "Sources/RayLite",
            exclude: ["App/Info.plist"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.unsafeFlags([
                "-Xlinker", "-sectcreate",
                "-Xlinker", "__TEXT",
                "-Xlinker", "__info_plist",
                "-Xlinker", URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                    .appendingPathComponent("Sources/RayLite/App/Info.plist").path
            ])]
        ),
        .testTarget(
            name: "RayLiteTests",
            dependencies: ["RayLite"],
            path: "Tests/RayLiteTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
