// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AquaristKit",
    platforms: [
        .iOS("26.0"),
        .macOS(.v15),
    ],
    products: [
        .library(name: "AquaristKit", targets: ["AquaristKit"]),
    ],
    targets: [
        .target(name: "AquaristKit"),
        .testTarget(name: "AquaristKitTests", dependencies: ["AquaristKit"]),
    ]
)
