// swift-tools-version: 6.2
import PackageDescription

// System-mode stand-in for the bundled RimeDynamic product: same package
// product/target/module names, but nothing is bundled. Headers and the link
// come from pkg-config (brew librime, or a custom prefix via PKG_CONFIG_PATH).
// Switch RimeKit to this by replacing the librime-xcframework dependency with
// a path dependency on this directory (see Package.swift switch block).
let package = Package(
    name: "Librime",
    products: [
        .library(name: "RimeDynamic", targets: ["RimeDynamic"])
    ],
    targets: [
        .systemLibrary(
            name: "RimeDynamic",
            path: "Sources/RimeDynamic")
    ])
