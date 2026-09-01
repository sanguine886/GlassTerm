// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AIAgent",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [
        .library(name: "AIAgent", targets: ["AIAgent"]),
    ],
    dependencies: [
        // Local dependency on the SSH engine; AIAgent's direction is one-way
        // toward CoreSSH (spec §3.3) so it can reuse transport abstractions.
        .package(path: "../CoreSSH"),
    ],
    targets: [
        .target(
            name: "AIAgent",
            dependencies: [
                .product(name: "CoreSSH", package: "CoreSSH"),
            ],
            path: "Sources/AIAgent"
        ),
        .testTarget(
            name: "AIAgentTests",
            dependencies: [
                "AIAgent",
                .product(name: "CoreSSH", package: "CoreSSH"),
            ],
            path: "Tests/AIAgentTests"
        ),
    ]
)
