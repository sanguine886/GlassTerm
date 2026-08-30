// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "CoreSSH",
    platforms: [.iOS("26.0")],
    products: [
        .library(name: "CoreSSH", targets: ["CoreSSH"])
    ],
    targets: [
        .target(name: "CoreSSH", path: "Sources/CoreSSH")
    ]
)
