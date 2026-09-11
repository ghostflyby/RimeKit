# RimeKit

[librime](https://github.com/rime/librime)(中州韵输入法引擎)的 Swift 封装:以分布式 actor 隔离 librime 的进程级全局状态,提供 `async`/typed-throws 的现代 Swift API;同一调用点覆盖**进程内**与 **XPC 跨进程**两种形态,面向 macOS 输入法(IMK)与 iOS 键盘扩展的引擎层。

- **`Rime`(分布式 actor)**:librime 全量 C API 的唯一串行执行域(约 80 个方法,`throws(RimeError)` typed throws);进程内为本地引用,iOS 走 `RimeLocalSystem`,macOS 可经 XPC 远程引用——四种形态调用点同构。
- **`RimeSession`**:按会话门面(按键、预编辑、候选、提交、选项);`~Copyable`,以 `(root, sessionID)` 随时重建句柄,容忍服务重启与蓝绿切换。
- **通知订阅**:闭包输入的 `setNotificationHandler(_:)`——本地引用直接 C 注册,远程引用自动转内部 sink actor 订阅。
- **目录布局**:`RimeDirectoryLayout` 把配置(用户可编辑)与部署(编译产物)分离,部署目录按代次(blue/green)隔离。
- **XPC 服务**:`Rime.serveXPC()` 一行启动 launchd on-demand 服务;peer 审计与内核级代码签名校验(SwiftXPC 0.4.0)。
- librime 以预编译二进制分发([librime-xcframework](https://github.com/ghostflyby/librime-xcframework)),构建期链接,无需本地编译 C++。

## 系统要求

- macOS 15+(完整功能,含 XPC 蓝绿)/ iOS 16+(进程内引擎,XPC 为 macOS-only)
- Swift 6.2 工具链(swift-tools 6.2)

## 引入

```swift
dependencies: [
  .package(url: "https://github.com/ghostflyby/RimeKit.git", from: "0.1.0"),
  // librime 二进制分发(动态框架或静态库):
  .package(url: "https://github.com/ghostflyby/librime-xcframework.git", from: "1.16.1-pack.8"),
],
targets: [
  .target(
    name: "MyIME",
    dependencies: [
      .product(name: "RimeKit", package: "RimeKit"),
      .product(name: "RimeDynamic", package: "librime-xcframework"),
    ])
]
```

## 用法

### 进程内(iOS / macOS)

```swift
import RimeKit

let rime = Rime(actorSystem: RimeLocalSystem())   // 或 RimeSession() 直连共享引擎
var session = try await RimeSession(root: rime)

_ = try await session.processKey(0x6E, modifierMask: 0)      // n
_ = try await session.processKey(0x69, modifierMask: 0)      // i

if let preedit = try await session.context?.composition.preedit {
    // 预编辑:"ni" → 内联展示(setMarkedText)
}
_ = try await session.selectCandidate(at: 0)
if let committed = try await session.commitText {
    // 提交文本 → insertText 到客户端
}
```

### 通知订阅

```swift
// 本地引用:直接 C 注册;iOS 同一路径。
try await rime.setNotificationHandler { session, type, value in
    // type: .schema / .option / .deploy / .unknown
}
try await rime.setNotificationHandler(nil)   // 退订
```

### 目录布局(配置与部署分离 + 分代)

```swift
let layout = RimeDirectoryLayout(
    root: appSupport.appending(path: "rime"), generation: .blue)
try layout.prepare()
let traits = layout.makeTraits(
    sharedDataDir: bundledSchemas, distributionName: "MyIME",
    distributionCodeName: "my.ime", distributionVersion: "1.0", appName: "my.ime")
// config/  = userDataDir(用户可编辑,跨代共享)
// deploy/<gen>/ = stagingDir(编译产物,按代隔离)
```

### XPC 服务端(macOS)

```swift
// launchd on-demand 服务入口(@main 可执行目标的一行实现):
Rime.serveXPC(
    peerCodeSigningRequirement: "…",                       // 内核强制签名校验(可选)
    shouldAccept: { conn in conn.euid == getuid() })       // pid/euid 审计(可选)
```

### XPC 客户端(macOS)

```swift
// 同一调用点:代理上的 processKey/context/… 与本地引用完全一致。
let rime = try Rime.connect(
    toService: "com.example.MyIME.rimeservice.blue",
    peerCodeSigningRequirement: "…")                       // 核验服务身份(可选)
var session = try await RimeSession(root: rime)
```

## 范围与路线图

蓝绿部署的**编排层**(双服务连接与预热编排、健康探活、会话状态迁移、
原子换绑、排空与回滚)**不在本库**。本库提供的是它的文件与进程基元:
分代部署目录(`RimeDirectoryLayout`)、单槽服务入口(`serveXPC`)、
会话重绑定容忍(`RimeSession`);编排管理器规划于后续版本
(方案见 [Docs/XPC-BlueGreen-Refactor-Plan.md](Docs/XPC-BlueGreen-Refactor-Plan.md) §4.3–4.5)。

## 测试

进程内 / 进程内 XPC 连接对双后端参数化(69 项):引擎契约、会话表、键入主路径、
候选翻页与迭代、方案与状态标签、配置读写遍历、通知回流;iOS destination
构建守护保持。

```sh
swift test
```

设计与语义实证:`Docs/XPC-BlueGreen-Refactor-Plan.md`(蓝绿方案)、
`Docs/RimeFunctionalTests-Design.md`(测试设计)。

## 许可证

[Mozilla Public License 2.0](LICENSE)。librime 本身为 BSD-3-Clause,其二进制
打包的第三方归属见 [librime-xcframework 的 THIRD_PARTY_NOTICES](https://github.com/ghostflyby/librime-xcframework)。
