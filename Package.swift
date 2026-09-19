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
      targets: ["RimeKit"])
  ],
  dependencies: [
    // librime-xcframework 的 product 拆分:Rime = 纯头模块(唯一模块提供者,零二进制下载);
    // RimeDynamic/RimeStatic = 无模块二进制(动态框架/静态库,消费方按需选挂);
    // RimeSystem = pkg-config 系统库(模块同为 Rime,不可与本包同依赖图)。
    .package(
      url: "https://github.com/ghostflyby/librime-xcframework", from: "1.17.0-pack.4"),
    // 开发期曾为本地 path 依赖(../SwiftXPC);自 0.3.2 起切正式版本。
    // 依赖经 `.when(platforms: [.macOS])` 条件化:构建 iOS 时 SwiftXPC 不进入依赖图(§2.5)。
    .package(url: "https://github.com/ghostflyby/SwiftXPC.git", from: "0.6.0")
  ],
  targets: [
    // librime C API 的包内转出口:C 模块名 Rime 与 RimeKit 的分布式 actor Rime 同名,
    // RimeKit 内 `Rime.` 模块限定被本地类型遮蔽;此目标自身不含 Rime 类型,
    // 在此 @_exported 转出 C 模块,RimeKit 经 `RimeC.` 限定访问全部 C API。
    .target(
      name: "RimeC",
      dependencies: [
        .product(name: "Rime", package: "librime-xcframework"),
      ]),
    .target(
      name: "RimeKit",
      dependencies: [
        "RimeC",
        .product(
          name: "DistributedXPC", package: "SwiftXPC",
          condition: .when(platforms: [.macOS]))
      ]),
    .testTarget(
      name: "RimeKitTests",
      dependencies: [
        "RimeKit",
        "RimeC",
        // 测试基建直挂 librime C API 注册全局通知回调(Squirrel setupRime 同型;
        // 根 actor 的非 distributed 成员不可经远程引用触达,通知收集走进程级 C 钩子)。
        // RimeDynamic 为模块无关二进制产物:仅为测试运行器提供 librime 符号与链接。
        .product(name: "RimeDynamic", package: "librime-xcframework"),
        // 进程内 XPC 连接对(SwiftXPC IntegrationConnectionPair 范式);
        // 经 @testable 访问 reserveRootID/bind(SwiftPM debug 构建对依赖开 testability)。
        .product(
          name: "SwiftXPC", package: "SwiftXPC",
          condition: .when(platforms: [.macOS])),
        .product(
          name: "DistributedXPC", package: "SwiftXPC",
          condition: .when(platforms: [.macOS])),
      ])
  ]
)
