// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RestoreEngine",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RestoreEngine", targets: ["RestoreEngine"]),
    ],
    targets: [
        .target(name: "RestoreEngine"),
        .testTarget(
            name: "RestoreEngineTests",
            dependencies: ["RestoreEngine"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
