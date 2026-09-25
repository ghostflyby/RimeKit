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
    // 在消费方构建中调用 RimeDeploy(本包内 target,非产品)的 build tool
    // plugin:target 内的 Rime 数据在构建期编译,并以目录资源的形式进 bundle。
    .plugin(
      name: "RimeDeployPlugin",
      targets: ["RimeDeployPlugin"])
  ],
  traits: [
    // 下游 librime 链接选型(SE-0450):消费方在 .package(traits:) 显式列出即取代
    // 默认集(.default 不再传递),两个 trait 同开会链接期符号冲突,二选一。
    // 消费方缺省(不写 traits)时传递 .defaults 标记 → 启用 librimeDynamic:
    // RimeKit 的动态产品变体(Xcode 测试构建对宿主/测试共享的产品强制生成)
    // 经 RimeDynamicStub 桩以 -framework RimeDynamic 链接(tbd,零二进制分发),
    // 真实框架的 embed 形态由下游决定(单副本嵌入 + 子 bundle 经 runpath 解析)。
    .default(enabledTraits: ["librimeDynamic"]),
    .trait(name: "librimeDynamic"),
    // librimeStatic:librime 静态并入每个链接 RimeKit 的最终产物,
    // 下游无需另挂任何 librime 二进制。
    .trait(name: "librimeStatic"),
  ],
  dependencies: [
    // librime-xcframework 的 product 拆分:Rime = 纯头模块(唯一模块提供者,零二进制下载);
    // RimeDynamic/RimeStatic = 无模块二进制(动态框架/静态库);RimeDynamicStub =
    // tbd 框架桩(只链接不嵌);RimeSystem = pkg-config 系统库(模块同为 Rime,
    // 不可与本包同依赖图)。二进制产物进链接的通道由上方 traits 选型决定。
    // librime 引入形态二选一(product/target/模块名两侧一致,RimeKit 源码零改动):
    // bundled(默认)在下方;system(不 bundle,纯模块声明,链接与 embed 由 Xcode
    // 工程自管)切换为下一行,详见 README「librime 引入形态」。
    .package(
      url: "https://github.com/ghostflyby/librime-xcframework", from: "1.17.0-pack.9.0.1"),
    // .package(path: "Support/librime-system"),
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
        .product(
          name: "RimeDynamicStub", package: "librime-xcframework",
          condition: .when(traits: ["librimeDynamic"])),
        .product(
          name: "RimeStatic", package: "librime-xcframework",
          condition: .when(traits: ["librimeStatic"])),
      ],
      linkerSettings: [
        // 静态 librime 为 C++ 产物,不携带 C++ 运行时;仅在静态选型下随 RimeKit
        // 传播 -lc++(动态选型经 RimeDynamic.framework 自带,无需此设置)。
        .linkedLibrary("c++", .when(traits: ["librimeStatic"])),
      ]),
    .target(
      name: "RimeKit",
      dependencies: [
        "RimeC",
        .product(
          name: "DistributedXPC", package: "SwiftXPC",
          condition: .when(platforms: [.macOS]))
      ]),
    // 部署逻辑所在,引擎操作经 RimeKit 的进程内共享根;librime 的链接形态
    // 由下方可执行文件的 traits 选型(RimeC 的条件产品)决定。
    .target(
      name: "RimeDeployCore",
      dependencies: ["RimeKit"]),
    // 工具本体:参数解析外壳 + 引擎驱动。librime 链接跟随消费方 traits:
    // 动态档挂 RimeDynamic 产品(桩只是链接旗标,不会把 framework 工件带进
    // 构建图,须显式依赖才有可解析的框架);静态档由 RimeC 的条件产品与
    // -lc++ 传播承接。
    .executableTarget(
      name: "RimeDeploy",
      dependencies: [
        "RimeDeployCore",
        .product(
          name: "RimeDynamic", package: "librime-xcframework",
          condition: .when(traits: ["librimeDynamic"])),
      ]),
    .plugin(
      name: "RimeDeployPlugin",
      capability: .buildTool(),
      dependencies: ["RimeDeploy"],
      path: "Plugins/RimeDeployPlugin"),
    // RimeDeployCore 供进程内调用;RimeDeploy 保证冒烟用例 spawn 的可执行文件被构建。
    .testTarget(
      name: "RimeDeployToolTests",
      dependencies: ["RimeDeploy", "RimeDeployCore"],
      path: "Tests/RimeDeployToolTests"),
    // 把本包的插件应用到自己的数据目录上,从而断言"构建系统把什么带进了
    // bundle"(目录结构、目录名),这是只测工具测不到的层面。两个数据目录
    // (惯例名 RimeData + 非常规名 MyRimeData)并存,顺带断言多数据集一般性。
    .testTarget(
      name: "RimeDeployPluginTests",
      dependencies: [
        "RimeKit",
        .product(name: "RimeDynamic", package: "librime-xcframework"),
      ],
      path: "Tests/RimeDeployPluginTests",
      exclude: ["RimeData", "MyRimeData"],
      plugins: [.plugin(name: "RimeDeployPlugin")]),
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
