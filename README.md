# RimeKit

Swift 封装的中州韵(rime)输入法引擎库:以 Swift actor 隔离 librime 的进程级全局状态,提供 async/typed-throws 的现代 Swift API。

- `protocol Rime`:引擎接缝(约 80 个异步要求,`throws(RimeError)` typed throws),`RimeSession` / `RimeConfig` 等高层门面全部面向该协议编程。
- `actor RimeEngine`:协议的进程内实现,串行化全部 librime 调用;`RimeEngine.shared` 单例。
- `RimeSession<Engine>`:按会话的门面(输入、候选、按键、上下文);librime 会话表为进程级,`RimeSessionID` 仅在本进程内有意义。
- 平台:macOS 13+ / iOS 15+;librime 以预编译动态框架(`RimeDynamic`,来自 [librime-xcframework](https://github.com/ghostflyby/librime-xcframework))构建期链接。

## 用法

```swift
import RimeKit

let engine = RimeEngine.shared
let traits = RimeTraits(
  sharedDataDir: ".../rime-shared", userDataDir: ".../rime-user",
  distributionName: "MyApp", distributionCodeName: "my.app",
  distributionVersion: "1.0", appName: "MyApp")
await engine.initialize(with: traits)
var session = await RimeSession(engine: engine)
_ = try await session.processKey(0x61, modifierMask: 0)  // "a"
let commit = try await session.commitText()
```

## 路线图

XPC 蓝绿发布热切换(基于 [SwiftXPC](https://github.com/ghostflyby/SwiftXPC))的设计与阶段规划见 [Docs/XPC-BlueGreen-Refactor-Plan.md](Docs/XPC-BlueGreen-Refactor-Plan.md)。
