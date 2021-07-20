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
      .package(url: "https://github.com/groue/GRDB.swift.git", .upToNextMajor(from: "5.8.0")),
      .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "KeyValueCRDT",
            dependencies: [
              .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "KeyValueCRDTTests",
            dependencies: ["KeyValueCRDT"]
        ),
    ]
)
