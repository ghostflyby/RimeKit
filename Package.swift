// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "RimeKit",
  platforms: [
    .macOS(.v15),
    .iOS(.v16),
  ],
  // 下游 librime 链接选型:显式 product 矩阵。互斥靠约定——同一最终链接镜像
  // 只挂一个变体,混挂会同时引入两份 librime 链接通道(traits 时代由包级
  // 解析机制保证,product 化后降为文档约定,见 README)。裸名 RimeKit 是
  // RimeKitStub 的别名:既有消费者零迁移,新消费者请用显式名。
  products: [
    // Stub(默认):经 RimeDynamicStub 桩以 -framework RimeDynamic 链接
    // (tbd,零二进制分发),真实框架的 embed 形态由下游决定(单副本嵌入 +
    // 子 bundle 经 runpath 解析)。
    .library(
      name: "RimeKit",
      targets: ["RimeKit", "RimeC", "RimeKitLinkageStub"]),
    .library(
      name: "RimeKitStub",
      targets: ["RimeKit", "RimeC", "RimeKitLinkageStub"]),
    // Dynamic:直挂真 RimeDynamic,SwiftPM 把框架嵌入每个链接它的 bundle
    // (含 XPC 的宿主会每 bundle 一份副本,勿用于 XPC 场景)。
    .library(
      name: "RimeKitDynamic",
      targets: ["RimeKit", "RimeC", "RimeKitLinkageDynamic"]),
    // Static:librime(含依赖)静态并入每个链接 RimeKit 的最终产物,
    // 无需 embed 任何框架、无运行期查找。
    .library(
      name: "RimeKitStatic",
      targets: ["RimeKit", "RimeC", "RimeKitLinkageStatic"]),
    // System:无锚——SwiftPM 不参与 librime 链接,头文件只供编译,符号解析
    // 完全由最终链接方决定(Xcode 工程自管链接与 embed;swift 命令行经
    // LIBRARY_PATH)。
    .library(
      name: "RimeKitSystem",
      targets: ["RimeKit", "RimeC"]),
    .plugin(
      name: "RimeDeployPlugin",
      targets: ["RimeDeployPlugin"]),
  ],
  dependencies: [
    // librime-xcframework 的 product 拆分:Rime = 纯头模块(唯一模块提供者,零
    // 二进制下载,全部形态共用的编译面);RimeDynamic/RimeStatic = 无模块二进制
    // (动态框架/静态库);RimeDynamicStub = tbd 框架桩(只链接不嵌)。二进制产物
    // 进链接的通道由上方 products 选型决定:每种形态一个"链接锚"target 把对应的
    // librime 二进制拖进链接闭包,System 形态无锚(链接外置)。
    .package(
      url: "https://github.com/ghostflyby/librime-xcframework", from: "1.17.0-pack.9.1.0"),
    // 开发期曾为本地 path 依赖(../SwiftXPC);自 0.3.2 起切正式版本。
    // 依赖经 `.when(platforms: [.macOS])` 条件化:构建 iOS 时 SwiftXPC 不进入依赖图(§2.5)。
    .package(url: "https://github.com/ghostflyby/SwiftXPC.git", from: "0.6.1")
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
    // 链接锚:除占位注释外不含任何代码,唯一职责是把对应形态的 librime 二进制
    // 拖进链接闭包(见 products 注释)。Static 锚一并传播 -lc++——静态 librime
    // 为 C++ 产物,不携带 C++ 运行时;动态形态经 RimeDynamic.framework 自带,
    // 无需此设置。
    .target(
      name: "RimeKitLinkageStub",
      dependencies: [
        .product(name: "RimeDynamicStub", package: "librime-xcframework")
      ]),
    .target(
      name: "RimeKitLinkageDynamic",
      dependencies: [
        .product(name: "RimeDynamic", package: "librime-xcframework")
      ]),
    .target(
      name: "RimeKitLinkageStatic",
      dependencies: [
        .product(name: "RimeStatic", package: "librime-xcframework")
      ],
      linkerSettings: [
        .linkedLibrary("c++")
      ]),
    // 构建期部署插件:驱动本包内的 RimeDeploy 可执行(源码随包构建)。
    // 工具自身经 RimeKitLinkageDynamic 锚直挂动态 librime,构建产物经构建
    // 系统 rpath 解析,对消费方自身的产品选型零传染(product 按边选型,
    // traits 时代的交叉污染不复存在;PreBuild 独立仓库与 artifactbundle
    // 分发随之退役)。
    .plugin(
      name: "RimeDeployPlugin",
      capability: .buildTool(),
      dependencies: ["RimeDeploy"],
      path: "Plugins/RimeDeployPlugin"),
    // 构建期部署工具(原 RimeKitPreBuild 独立仓库,product 矩阵落地后迁回):
    // 引擎驱动走进程内 RimeKit API(setup/initializeDeployer/prebuild/
    // deploy/finalize + logsink 错误收集),工具自身直挂 Dynamic 锚——动态
    // librime 框架随构建产物落盘、由构建系统 rpath 解析,工具进程不再需要
    // 静态自包含。
    .target(
      name: "RimeDeployCore",
      dependencies: [
        "RimeKit",
        "RimeKitLinkageDynamic",
      ]),
    // 命令行外壳:解析 argv、执行、报告。全部逻辑在库里以便测试直接调用。
    .executableTarget(
      name: "RimeDeploy",
      dependencies: [
        "RimeDeployCore",
      ]),
    // 插件附着到本包自己的数据目录(惯例名 + 非常规名并存),断言编译数据
    // 进 bundle、布局保留,并经 RimeKit 进程内加载验证。
    .testTarget(
      name: "RimeDeployPluginTests",
      dependencies: [
        "RimeKit",
        .product(name: "RimeDynamic", package: "librime-xcframework"),
      ],
      path: "Tests/RimeDeployPluginTests",
      exclude: ["RimeData", "MyRimeData", "WanxiangData"],
      plugins: [.plugin(name: "RimeDeployPlugin")]),
    .testTarget(
      name: "RimeDeployToolTests",
      // 只挂 Core:领域矩阵进程内调用;可执行 target 不可再作测试依赖——
      // 它同时是插件宿主工具(native 布局下两份 .o 并入同一测试包链接,
      // 符号成对重复)。真实工具执行的合约由 RimeDeployPluginTests 覆盖。
      dependencies: [
        "RimeDeployCore",
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
