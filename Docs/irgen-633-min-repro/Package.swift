// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "mini-repro",
    platforms: [.macOS(.v13), .iOS(.v16)],
    targets: [.target(name: "MiniRepro")]
)
