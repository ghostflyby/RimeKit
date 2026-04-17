// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "RimeKit",
  platforms: [
    .macOS(.v13),
    .iOS(.v15),
  ],
  products: [
    // Products define the executables and libraries a package produces, making them visible to other packages.
    .library(
      name: "RimeKit",
      targets: ["RimeKit"])
  ],
  dependencies: [
    .package(
      url: "https://github.com/ghostflyby/librime-xcframework", from: "1.16.1-pack.8",
      // traits: [.trait(name: "dynamic")]
    )
  ],
  targets: [
    .target(
      name: "RimeKit",
      dependencies: [
        .product(
          name: "RimeDynamic", package: "librime-xcframework")
      ]),
    .testTarget(
      name: "RimeKitTests",
      dependencies: ["RimeKit"]
    ),
  ]
)
