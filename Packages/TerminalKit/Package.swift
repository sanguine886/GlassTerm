// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TerminalKit",
    platforms: [.iOS("26.0")],
    products: [
        .library(name: "TerminalKit", targets: ["TerminalKit"]),
    ],
    targets: [
        .target(name: "TerminalKit", path: "Sources/TerminalKit"),
    ]
)
