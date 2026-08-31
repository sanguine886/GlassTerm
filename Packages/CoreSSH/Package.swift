// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "CoreSSH",
    platforms: [.iOS("26.0"), .macOS(.v14)],
    products: [
        .library(name: "CoreSSH", targets: ["CoreSSH"]),
    ],
    dependencies: [
        // Exact pins per spec §6.4.3 (ADR-0002). The NIOSSH fork and NIO version
        // ranges match what Citadel 0.12.1 itself requires.
        .package(url: "https://github.com/orlandos-nl/Citadel.git", exact: "0.12.1"),
        .package(url: "https://github.com/Wellz26/swift-nio-ssh.git", exact: "0.3.4"),
        .package(url: "https://github.com/apple/swift-nio.git", exact: "2.81.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "3.12.3"),
    ],
    targets: [
        .target(
            name: "CoreSSH",
            dependencies: [
                .product(name: "Citadel", package: "Citadel"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            path: "Sources/CoreSSH"
        ),
        .testTarget(
            name: "CoreSSHTests",
            dependencies: [
                "CoreSSH",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
            ],
            path: "Tests/CoreSSHTests"
        ),
    ]
)
