// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RestoreEngine",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "RestoreEngine", targets: ["RestoreEngine"]),
    ],
    targets: [
        .target(name: "RestoreEngine"),
        .executableTarget(name: "prepare-models", dependencies: ["RestoreEngine"]),
        .testTarget(
            name: "RestoreEngineTests",
            dependencies: ["RestoreEngine"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
