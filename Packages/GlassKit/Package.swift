// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "GlassKit",
    platforms: [.iOS("26.0")],
    products: [
        .library(name: "GlassKit", targets: ["GlassKit"]),
    ],
    targets: [
        .target(name: "GlassKit", path: "Sources/GlassKit"),
    ]
)
