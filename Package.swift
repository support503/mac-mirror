// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MacMirror",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "MacMirrorCore",
            targets: ["MacMirrorCore"]
        ),
        .executable(
            name: "MacMirror",
            targets: ["MacMirrorApp"]
        ),
        .executable(
            name: "mac-mirror",
            targets: ["MacMirrorCLI"]
        ),
        .executable(
            name: "mac-mirror-login",
            targets: ["MacMirrorLogin"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.6.0"),
    ],
    targets: [
        .target(
            name: "MacMirrorCore"
        ),
        .executableTarget(
            name: "MacMirrorApp",
            dependencies: ["MacMirrorCore"]
        ),
        .executableTarget(
            name: "MacMirrorCLI",
            dependencies: ["MacMirrorCore"]
        ),
        .executableTarget(
            name: "MacMirrorLogin",
            dependencies: ["MacMirrorCore"]
        ),
        .testTarget(
            name: "MacMirrorCoreTests",
            dependencies: [
                "MacMirrorCore",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ]
)
