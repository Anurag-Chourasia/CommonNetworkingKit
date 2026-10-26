// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CommonNetworkingKit",
    platforms: [.iOS(.v16), .macOS(.v14)],
    products: [
        .library(name: "CommonNetworkingKit", targets: ["CommonNetworkingKit"]),
        .library(name: "CommonNetworking", targets: ["CommonNetworking"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "CommonNetworkingKit",
            dependencies: [],
            path: "Sources/CommonNetworkingKit"
        ),
        .target(
            name: "CommonNetworking",
            dependencies: ["CommonNetworkingKit"],
            path: "Sources/CommonNetworking"
        ),
        .testTarget(
            name: "CommonNetworkingKitTests",
            dependencies: ["CommonNetworkingKit"],
            path: "Tests/CommonNetworkingKitTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
