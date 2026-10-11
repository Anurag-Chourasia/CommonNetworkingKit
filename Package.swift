// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CommonNetworking",
    platforms: [.iOS("16.6")],
    products: [
        .library(name: "CommonNetworking", targets: ["CommonNetworking"])
    ],
    dependencies: [],
    targets: [
        .target(name: "CommonNetworking", dependencies: []),
        .testTarget(name: "CommonNetworkingTests", dependencies: ["CommonNetworking"])
    ],
    swiftLanguageVersions: [.v5]
)
