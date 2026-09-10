// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "RimeKit",
  platforms: [
    .macOS(.v15),
    .iOS(.v16),
  ],
  products: [
    .library(
      name: "RimeKit",
      targets: ["RimeKit"]),
    .executable(
      name: "RimeKitRimeService",
      targets: ["RimeKitRimeService"])
  ],
  dependencies: [
    .package(
      url: "https://github.com/ghostflyby/librime-xcframework", from: "1.16.1-pack.8",
      // traits: [.trait(name: "dynamic")]
    ),
    // 开发期本地 path 依赖;发布切 tag(from: "0.2.0")。
    // 依赖经 `.when(platforms: [.macOS])` 条件化:构建 iOS 时 SwiftXPC 不进入依赖图(§2.5)。
    .package(path: "../SwiftXPC")
  ],
  targets: [
    .target(
      name: "RimeKit",
      dependencies: [
        .product(
          name: "RimeDynamic", package: "librime-xcframework"),
        .product(
          name: "DistributedXPC", package: "SwiftXPC",
          condition: .when(platforms: [.macOS]))
      ]),
    .executableTarget(
      name: "RimeKitRimeService",
      dependencies: ["RimeKit"]),
    .testTarget(
      name: "RimeKitTests",
      dependencies: [
        "RimeKit",
        // 测试基建直挂 librime C API 注册全局通知回调(Squirrel setupRime 同型;
        // 根 actor 的非 distributed 成员不可经远程引用触达,通知收集走进程级 C 钩子)。
        .product(name: "RimeDynamic", package: "librime-xcframework"),
        .product(
          name: "DistributedXPC", package: "SwiftXPC",
          condition: .when(platforms: [.macOS])),
      ])
  ]
)
