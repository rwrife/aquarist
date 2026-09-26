// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AquaristStore",
    platforms: [
        .iOS("26.0"),
        .macOS(.v15),
    ],
    products: [
        .library(name: "AquaristStore", targets: ["AquaristStore"]),
        .library(name: "AquaristStoreTestSupport", targets: ["AquaristStoreTestSupport"]),
    ],
    dependencies: [
        .package(path: "../AquaristKit"),
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
    ],
    targets: [
        .target(
            name: "AquaristStore",
            dependencies: [
                .product(name: "AquaristKit", package: "AquaristKit"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .target(
            name: "AquaristStoreTestSupport",
            dependencies: [
                "AquaristStore",
                .product(name: "AquaristKit", package: "AquaristKit"),
            ]
        ),
        .executableTarget(
            name: "fixture-seed",
            dependencies: [
                "AquaristStore",
                .product(name: "AquaristKit", package: "AquaristKit"),
            ],
            path: "Tools/fixture-seed"
        ),
        .testTarget(
            name: "AquaristStoreTests",
            dependencies: [
                "AquaristStore",
                "AquaristStoreTestSupport",
                .product(name: "AquaristKit", package: "AquaristKit"),
            ],
            exclude: ["Fixtures"]
        ),
    ]
)
