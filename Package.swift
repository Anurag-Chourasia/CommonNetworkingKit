// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CommonNetworkingKit",
    platforms: [.iOS(.v16), .macOS(.v14)],
    products: [
        .library(name: "CommonNetworkingKit", targets: ["CommonNetworkingKit"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "CommonNetworkingKit",
            dependencies: [],
            path: "Sources/CommonNetworkingKit"
        ),
        .testTarget(
            name: "CommonNetworkingKitTests",
            dependencies: ["CommonNetworkingKit"],
            path: "Tests/CommonNetworkingKitTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
