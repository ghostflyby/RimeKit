# Swift 6.3.3 IRGen 崩溃最小复现(distributed actor × `~Copyable` 泛型 × 旧部署目标)

独立 SwiftPM 包,不依赖 RimeKit / librime。核心复现面约 12 行
(`Sources/MiniRepro/Mini.swift`):1 个 distributed actor,1 个方法,
返回类型提及带 `~Copyable` 约束参数的泛型 `NCBox<Int>?`。

## 触发条件(必要且充分)

1. 工具链 **Swift 6.3.3**(Xcode 26.6 / swiftlang-6.3.3.1.3)下验证;
2. 任一 `distributed func` 的**签名**(参数位或返回位,Optional 与否均可)提及
   一个泛型标称类型,其**泛型参数带 `~Copyable` 约束**(类型本身可拷贝、可为空 struct);
3. 最低部署目标 **iOS < 18.0 或 macOS < 15.0**。

→ IRGen 阶段 signal 5(SIGTRAP)崩溃,`swift-frontend` 栈顶:
`IRGenModule::emitAccessibleFunction → getTypeRef → emitTypeMetadataRef →
createTypeMetadataAccessFunction → createDirectTypeMetadataAccessFunction`
(后者的回调帧出现自递归)。

## 本机实测矩阵(2026-09-10)

| 部署目标 | 结果 |
|---|---|
| iOS 16.0 / 17.1 / 17.4 simulator | **崩** |
| iOS 18.0 / 26.0 simulator | 通过 |
| macOS 13.0 / 14.0 | **崩** |
| macOS 15.0 / 16.0 / 26.0 | 通过 |
| `NCBox` 改 `T: Sendable`(其余不变,iOS 16) | 通过 |
| 方法从 1 个到 82 个 | 均崩(与数量无关) |
| typed throws / untyped throws | 均崩(与 throws 形态无关) |
| 方法拆到 extension / 另一文件 | 均崩(thunk 按类型/模块级发射,拆分无效) |

## 复现命令

```bash
cd Docs/irgen-633-min-repro
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
cat > /tmp/dest16.json <<EOD
{"version":1,"toolchain-bin-dir":"$(dirname $(xcrun -f swift))",
 "target":"arm64-apple-ios16.0-simulator","sdk":"$SDK",
 "swift-resources-path":"$SDK/usr/lib/swift",
 "extra-cc-flags":[],"extra-cxx-flags":[],"extra-cpp-flags":[],
 "extra-swiftc-flags":[],"extra-linker-flags":[]}
EOD
swift build --destination /tmp/dest16.json   # 预期:IRGen signal 5 崩溃

swift build                                   # macOS(floor 13)同样崩溃

# 对照:把 Mini.swift 的 `T: ~Copyable` 改成 `T: Sendable`,两条命令均通过。
```
