// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AIAgent",
    platforms: [.iOS("26.0")],
    products: [
        .library(name: "AIAgent", targets: ["AIAgent"]),
    ],
    targets: [
        .target(name: "AIAgent", path: "Sources/AIAgent"),
    ]
)
