// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Vinegar303",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "Vinegar303Kit", targets: ["Vinegar303Kit"]),
    ],
    targets: [
        .target(
            name: "Vinegar303Kit",
            path: "Shared"
        ),
        .testTarget(
            name: "Vinegar303KitTests",
            dependencies: ["Vinegar303Kit"],
            path: "Tests/Vinegar303KitTests"
        ),
    ]
)
