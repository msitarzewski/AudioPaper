// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AudioPaperKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "AudioPaperKit", targets: ["AudioPaperKit"]),
        .executable(name: "apctl", targets: ["apctl"]),
    ],
    targets: [
        .target(name: "AudioPaperKit"),
        .executableTarget(name: "apctl", dependencies: ["AudioPaperKit"]),
        .testTarget(
            name: "AudioPaperKitTests",
            dependencies: ["AudioPaperKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
