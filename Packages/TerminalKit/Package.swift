// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TerminalKit",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [
        .library(name: "TerminalKit", targets: ["TerminalKit"]),
    ],
    dependencies: [
        // Exact pin per spec §6.4.3 (ADR-0002). Upgrades require a full
        // terminal regression run (spec §3.2).
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.20.0"),
        .package(path: "../CoreSSH"),
    ],
    targets: [
        .target(
            name: "TerminalKit",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                "CoreSSH",
            ],
            path: "Sources/TerminalKit"
        ),
        .testTarget(
            name: "TerminalKitTests",
            dependencies: ["TerminalKit"],
            path: "Tests/TerminalKitTests"
        ),
    ]
)
