// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftRime",
    platforms: [
        .macOS(.v11),
        .iOS(.v15),
        .watchOS(.v8),
        .tvOS(.v15),
        .macCatalyst(.v15),
        .visionOS(.v2),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "SwiftRime",
            targets: ["SwiftRime"])
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .systemLibrary(
            name: "CLibrime",
            path: "Sources/CLibrime",
            pkgConfig: "rime",
            providers: [
                .brew(["librime"]),
                .apt(["librime"]),
            ],
        ),
        .target(
            name: "SwiftRime",
            dependencies: ["CLibrime"]),
        .testTarget(
            name: "SwiftRimeTests",
            dependencies: ["SwiftRime"]
        ),
    ]
)
