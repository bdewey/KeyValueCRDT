// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "KeyValueCRDT",
    platforms: [
      .iOS(.v13),
      .macOS(.v10_15),
      .watchOS(.v6),
      .tvOS(.v13),
    ],
    products: [
        .library(
            name: "KeyValueCRDT",
            targets: ["KeyValueCRDT"]
        ),
    ],
    dependencies: [
      .package(url: "https://github.com/bdewey/GRDB.swift", branch: "xcode13"),
//      .package(url: "https://github.com/groue/GRDB.swift.git", .upToNextMajor(from: "5.8.0")),
      .package(url: "https://github.com/apple/swift-log", .upToNextMajor(from: "1.4.0")),
      .package(url: "https://github.com/apple/swift-argument-parser", from: "0.4.0"),
    ],
    targets: [
        .target(
            name: "KeyValueCRDT",
            dependencies: [
              .product(name: "GRDB", package: "GRDB.swift"),
              .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .executableTarget(
            name: "kvcrdt",
            dependencies: [
              .product(name: "ArgumentParser", package: "swift-argument-parser"),
              "KeyValueCRDT",
            ]
        ),
        .testTarget(
            name: "KeyValueCRDTTests",
            dependencies: ["KeyValueCRDT"]
        ),
    ]
)
