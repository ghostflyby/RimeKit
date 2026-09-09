# RimeKit × SwiftXPC:XPC 蓝绿发布热切换改造方案

- 状态:阶段一交付稿(分析与规格,未改任何代码)
- 日期:2026-09-09
- 依赖基线:SwiftXPC v0.2.0(`/Users/ghostflyby/repos/tests/SwiftXPC`,HEAD `e8a41ee`);librime-xcframework 1.16.1-pack.8
- 已确认决策:
  1. 阶段一只产出本方案文档,不动代码;
  2. 架构走 **统一 Rime 协议** 路线(wire-compatible 重塑,进程内引擎与远程实现共用同一协议);
  3. **现在引入 typed throws**(阶段 2a 落地 `RimeError`,替换强解包)。
  4. **iOS 保持一级支持**(2026-09-09 补充):iOS 不支持 XPC;XPC 相关内容以 macOS 平台可用性声明(`@available(macOS 15, *)`)圈定 API 表面,并经**平台条件化目标依赖 + 包内条件编译**落地(§2.5)。
  5. **客户端采用具体类型契约**(2026-09-09 补充):不把远程引用装入 `any Rime` 存在型;远程代理与本地实例同型,客户端直接持有 XPC 模块声明的具体根 actor 类型。基于此,核心不再声明分布式 actor(语言墙实证见 §3.4),`RemoteRimeEngine` 适配器方案废除。
  6. **XPC 支持回归 RimeKit 主包**(2026-09-09 补充,复勘修正):不建独立包、**不变更上游**;SwiftXPC 以**平台条件化目标依赖**引入——`.product(name: "DistributedXPC", package: "SwiftXPC", condition: .when(platforms: [.macOS]))`,iOS 构建图自动排除 SwiftXPC(`TargetDependencyCondition.when(platforms:)` 自 _PackageDescription 5.7 即存在,初版调研漏检,双平台构建实验已实证,见 §2.5)。XPC 目标源文件全部 `#if os(macOS)` 守卫 + 公开 API `@available(macOS 15, *)`。
  7. **并发模型定案**(2026-09-09 补充):确立**方案 1**——根 actor 为低级别 API 全量暴露函数,作为 librime 调用的唯一串行执行域;语义化 API 为非 actor 二次封装层。**否决方案 2**(语义类型各自持 actor 队列):librime 1.16.1 内部无任何全局/会话/配置锁,多执行流并发调用即数据竞争,源码考察见 §2.6。
  8. **同步桥与死锁不变式**(2026-09-09 补充):IMK 全同步编程模型与 actor 集成的阻塞等待点清点与不变式 I1–I6 见 §3.8,列为 2b/宿主集成审查项;IMK 适配壳不进本包(宿主侧关注点)。

---

## 0. 背景与目标

librime 是**进程级单例**:`setup/initialize/finalize` 全局唯一、全局通知回调、全局会话表、维护线程、deployer、目录状态全部绑定在一个进程上。这意味着:

- 无法在同一进程内运行两代 librime/方案数据;
- 部署(deploy/fullCheck)与升级只能"停机换血";
- 服务崩溃即全部会话丢失。

目标形态:把 librime(RimeKit)装进 **XPC 服务进程**,客户端(宿主 App)经 SwiftXPC 调用;以 **蓝绿双实例**(`…rime.blue.xpc` / `…rime.green.xpc`)实现:

> 绿机预热(initialize + deploy + 建会话 + 迁移状态)→ 客户端原子换绑 → 蓝机 drain(在途调用排空)→ 回收蓝机。

绿机预热同时把 librime 最昂贵的 deploy 成本移出了服务路径——这是蓝绿对单实例架构最大的语义增益。

---

## 1. RimeKit 现状评估

### 1.1 包形态与依赖

| 项 | 现状 |
|---|---|
| tools | 6.1(`Package.swift:1`),Swift 6 严格并发默认语言模式 |
| 平台 | macOS 13 / iOS 15(`Package.swift:8–11`) |
| 产品 | 单 library `RimeKit` |
| 依赖 | 仅 `librime-xcframework`(取 `RimeDynamic` 产品),无 SwiftXPC |

**重要事实澄清**:`RimeDynamic` 不是 dlopen 层,而是 **librime 本体预编译为动态框架**(binaryTarget xcframework,bundle id `org.rime.RimeDynamic`,install name `@rpath/RimeDynamic.framework/RimeDynamic`)。全仓无任何 dlopen/dlsym/NSBundle 代码;框架由 dyld 在进程启动时加载。符号取用方式:`RimeEngine` 私有 init 里 `rime_get_api_stdbool().pointee` 把**版本化函数指针表**按值拷贝进 `internal let rimeApi`(`RimeEngine.swift:17–19`),后续全部经该表调用。另存在公开的 `RimeEngine(UnsafeRawPointer)` / `(OpaquePointer)` init(`RimeEngine.swift:21–27`),是现成的"替代 API 提供者"接缝。

### 1.2 架构现状:协议接缝

- **`protocol Rime: Sendable`**(`Rime.swift:4`):全量 **81 个要求**(71 个 async 方法 + 10 个 async 属性),覆盖生命周期/维护/deployer/会话/按键/输出/选项/Schema/Config/迭代器/候选/目录。
- **`actor RimeEngine: Rime`**(`RimeEngine.swift:4`):唯一实现,`nonisolated public static let shared` 单例。actor 隔离的共享状态:通知回调 `Box?`、复用的 1KB C 缓冲 `cStringBuffer`、三张句柄表 `configs` / `configIterators` / `candidateIterators`(句柄 `ObjectHandle<T>` = UUID 包装,`Sendable+Codable+Hashable`,实际 C 结构体存在 actor 字典里)。
- **高层门面全部面向 `any Rime` 编程**:`RimeSession`(`~Copyable`,持有 `sessionID + any Rime`)、`RimeConfig`(`final class: Sendable`,持有句柄+引擎)、候选/配置迭代器辅助。这是最关键的既有资产:**任何新的 `Rime` 实现都能让整套高层 API 免费工作**。
- 值类型 DTO(`RimeSessionID`(UInt)、`RimeTraits`、`RimeCommit/Status/Context/Candidate/SchemaList*`、`RimeConfigLocation`、`RimeNotificationType`)全部 `Sendable (+Codable)`。
- 并发模型:Swift 6 模式,无 DispatchQueue/NSLock;`RimeSession.deinit` 与 `RimeConfig.deinit` 派生 fire-and-forget Task 做清理(与 `finalize()` 无顺序保证)。

### 1.3 librime 进程级单例面清单(即 XPC 服务进程应独占的部分)

1. 全局生命周期:`setup` → `initialize(traits)`(目录等烙进 traits)→ `finalize`;
2. 全局唯一通知回调:`set_notification_handler(thunk, context)`(C thunk 在 librime 自己的线程上同步调用 Swift 闭包,`RimeNotificationHandler.swift:15–28`);
3. 全局会话表:`RimeSessionID`(uintptr_t)仅在本进程内有意义;
4. 维护线程(`start_maintenance` / `join_maintenance_thread`)与 deployer;
5. 目录状态(shared/user/prebuilt/staging/sync)。

**结论**:librime 的单例性与"一个 XPC 服务进程一个 librime"完全同构——服务进程内 `RimeServiceRoot` 委托 `RimeEngine.shared` 即可,不需要任何新的并发原语。

### 1.4 缺陷与阻塞项清单(阶段 2a 前置修复)

| # | 问题 | 位置 | 影响 |
|---|---|---|---|
| D1 | 测试目录 `Tests/SwiftRimeTests/` 与目标名 `RimeKitTests` 错配,且测试文件 `@testable import SwiftRime`(模块已改名) | `Tests/SwiftRimeTests/SwiftRimeTests.swift:3` | `swift test` 必挂,测试地基为零 |
| D2 | `beginCandidates` / `candidateList(fromIndex:)` 创建句柄但**从不写入** `candidateIterators`,而 `advanceCandidateIterator` 强解包 `candidateIterators[iterator]!` → 调用必崩 | `RimeContext.swift:101–135`(崩溃点 113) | 候选迭代路径不可用 |
| D3 | `RimeTraits` 字段全 internal、无公开构造器 | `RimeTraits.swift:4–16` | 模块外(含未来 XPC 客户端)无法构造 traits,类型不可用 |
| D4 | `configs[handle]!` 等成片强解包:陈旧/外来句柄直接崩溃 | `RimeConifg.swift:107,112,126,140,…`、`RimeContext.swift:113` | 崩溃面;typed throws 改造的对象 |
| D5 | deinit 派生无序清理 Task(会话销毁/配置释放与 `finalize()`/drain 无顺序保证) | `RimeSession.swift:28–34`、`RimeConifg.swift:22` | 跨进程后销毁时序不可依赖 |
| D6 | 未使用的 `import Distributed`(全模块无 distributed 代码) | `RimeEngine.swift:1` | 死代码 |
| D7 | README 仅 4 行且仍标题 "SwiftRime";文件名 `RimeConifg.swift` 拼写错误 | 根目录 / Sources | 仓库卫生 |
| D8 | 协议内含注释掉的 API 备忘(`user_config_open`、`candidate_list_from_index` 残留) | `Rime.swift:112–116` | 文档卫生 |

---

## 2. 语义契合度分析

### 2.1 天然契合(改造红利)

| RimeKit 既有形态 | SwiftXPC/蓝绿语义 | 结论 |
|---|---|---|
| `protocol Rime` 接缝,全部高层 API 面向 `any Rime` | 客户端对"本地引擎 / 远程引擎 / 蓝机 / 绿机"零感知 | 换绑即切换,高层 API 不动 |
| `ObjectHandle<T>`(UUID)句柄 + actor 端字典存真实对象 | 标准远程对象引用模式(句柄过线、状态驻留服务端) | 配置/迭代器**天生远程友好**,零改造 |
| `RimeSessionID`(UInt)值类型 | 进程内会话句柄,天然 marshalable | 直接过线 |
| `actor RimeEngine` 串行化一切 | SwiftXPC 每通道 FIFO(`runIncomingHandler` 信号量门控)+ 服务端 actor 隔离 | 无锁正确性天然成立 |
| librime 进程单例 | 一个服务进程一个 librime | 蓝绿的前提条件,恰好成立 |
| `RimeSession.input` / `caretPosition` get+set(提交 `ed6baef`) | 会话状态快照/恢复原语 | 蓝绿状态迁移的正中需求 |
| 绿机预热 | deploy/fullCheck 在绿机空闲时完成 | 把最贵操作移出服务路径 |

### 2.2 需要改造的点

1. **序列化**:RimeKit DTO 是 `Codable`,SwiftXPC 的 `SerializationRequirement = XPCMarshal`(宏生成,**字段顺序即线缆布局**,非 Codable 桥)。→ 统一协议重塑后,为 DTO 在包内 XPC 条件编译区补 `XPCMarshal` 一致性(见 §3.6)。
2. **`borrowing` 参数**:`Rime` 协议中 19 个方法、20 处 `borrowing ObjectHandle<RimeConfig>`(`Rime.swift:49–93`)。`ObjectHandle` 是 UUID 小值类型,borrowing 纯属拷贝优化,降为普通参数无任何损失。
3. **错误语义**:现协议不 throw、实现层强解包崩溃。SwiftXPC 线缆协议原生支持 **typed-throws**(`XPCDistributedTargetMetadata.thrownErrorType` + `XPCReplyEnvelope.throwError` 解码)→ 引入 `RimeError`(§3.3)。
4. **`AsyncStream` 候选流**:`RimeSession.candidates: AsyncStream<RimeCandidate>` 不能过线;但其底层本就是"迭代器句柄驻留服务端 + 逐个 advance"的拉取模式 → `AsyncStream` 降为协议扩展(由 `beginCandidates/advance/end` 句柄要求实现),线缆只传句柄与单个 `RimeCandidate`。
5. **通知回调**:协议内 `setNotificationHandler(_ handler: @escaping RimeNotificationHandler)`(`Rime.swift:7`)是逃逸闭包,不可过线;且 librime 侧是**进程全局单回调**。→ 改用分布式 actor 引用:`RimeNotificationSink`(§3.5)。
6. **`RimeSession.deinit` 清理**:跨进程后 `destroySession` 变成一次远程调用,drain/`close()` 期间存在竞态 → drain 前先显式 quiesce 会话(§4.5)。
7. **SwiftXPC 已知限制**(v0.2.0,TODO.md 在案):无超时/无取消(一次卡死调用永久占用其通道);`parseTargetIdentifier` 对**大写开头参数 label** 会截断(label 约定小写开头);endpoint 一次性;`XPCDictionary[k]=nil` 语义陷阱(避免使用)。

### 2.3 硬约束与平台地板

- **iOS 保持一级支持,XPC 内容 macOS-only**:核心协议重塑保持平台中立(不 import SwiftXPC,iOS 15 声明不变);XPC 代码置于主包内条件编译区(目标/文件级 `#if os(macOS)`),公开 API 以 `@available(macOS 15, *)` 圈定(同包化前置与实测依据见 §2.5)。
- **`XPCRootConnection` 全系 `@available(macOS 15, *)`**(含 `XPCRetryPolicy`、事件流;已核实 `XPCRootConnection.swift:11,54,75`)→ 可用性声明即以此为地板;客户端若需支持 <15,可用简化路径 `XPCRootActor.connect(toService:)` 自建重试(非本方案范围,注明即可)。
- SwiftXPC 声明 swift-tools **6.2** → RimeKit 需 6.1→6.2 升级。
- **每通道 FIFO 串行**:同一命名连接上的所有调用严格串行,且最终仍会在服务端 `RimeEngine` actor 上二次串行。**运维通道分离**(维护/deploy 走独立连接,见 §4.2 注)可避免传输层队头阻塞,但引擎级串行仍在——蓝绿预热才是真正把 deploy 移出服务路径的手段。

### 2.4 SwiftXPC 能力核对:分布式 actor 远程引用作为参数/返回值

**支持**,这是 `XPCActorReference`(`XPCActorReference.swift:11–15`,线缆 `{version, actorID, endpoint}`)与 `XPCExportableActor` 提供的能力,亦是 `SerializationRequirement = XPCMarshal` 的直接推论:

- **本地 actor → 过线**:marshal 缺省实现 = `actorSystem.export(self)`,为本进程 actor 铸一个**匿名 endpoint 监听**(`mintExportSession`,`XPCConnection(name: nil)`,支持多 peer),对端 `unmarshal` 拨号得到代理。Demo 中 `DemoRoot.makeGreeter() -> DemoGreeter` 即"返回 actor 引用"的实证。
- **已导入代理 → 转发**:再次 marshal 时重发存储的 endpoint(直拨,不中继)。
- **约束**(全部要写进契约纪律):
  1. 仅**具体** distributed actor 类型可作参数/返回;`any` 存在型被编译器拒绝(4 种形状已探测),泛型 distributed 方法语言级不支持;
  2. **根代理导出被拒绝**(根只走命名通道);
  3. 每次 export 铸一个新匿名监听 = 一个 mach port,高频导出有资源代价;
  4. **子代理不可重连**:服务进程死亡后子代理永久失效,必须经根重取(根代理经命名通道在 launchd 重拉后自愈,已探针实证);
  5. 客户端要**本地创建**可导出 actor(如 sink),需要一个客户端自有的 `XPCDistributedActorSystem` 实例 —— `unmarshal` 路径各自持有自有 system,但 `XPCRootConnection` 是否暴露其内部 system 供客户端建本地 actor **待验证**(§5.3)。

**本方案对 actor 引用的使用决策**:

| 场景 | 采用 | 理由 |
|---|---|---|
| 通知回调(服务→客户端) | ✅ `RimeNotificationSink` actor 引用 | 唯一需要**反向调用**的场景,actor 引用是正解 |
| 会话/配置/迭代器 | ❌ 继续用 `RimeSessionID` / `ObjectHandle` 句柄 | 句柄零 mach-port 成本、wire 上无类型歧义、崩溃后与根通道一起消亡的语义更简单;会话 actor 化(每会话一条子通道)只省传输层队头,省不掉引擎级串行,还引入端口开销与不可重连子代理 |
| 返回子 actor(仿 `makeGreeter`) | ❌ 不采用 | 同上;统一协议重塑后句柄方案与现有 `ObjectHandle` 资产完全对齐 |

### 2.5 iOS 支持策略与同包化实测(2026-09-09 复勘修正)

**结论:XPC 支持放回 RimeKit 主包可行且为既定方案(决策 6);机制 = 平台条件化目标依赖 + 包内条件编译 + 可用性声明,零上游变更。**

> 勘误说明:初版调研误判"SwiftPM 无按平台条件依赖机制,依赖一经声明即被无条件纳入所有平台构建"。该结论**错误**——`TargetDependencyCondition.when(platforms:)` 自 _PackageDescription 5.7 起即为既有 API(工具链 ManifestAPI 接口文件核验)。初版实验声明的是**无条件**依赖,SwiftXPC 因此被纳入 iOS 构建图并以其自身的 iOS 编译失败拖垮整个构建;失败归因于实验设计,而非 SwiftPM 缺失能力。

**复勘实验**(同实验对象:声明 `[.macOS(.v13), .iOS(.v15)]` 的包,path 依赖 SwiftXPC v0.2.0,destination JSON 正规交叉编译至 iOS 模拟器,Swift 6.3.3):

```swift
// Package.swift
.target(name: "Demo", dependencies: [
  .product(name: "DistributedXPC", package: "SwiftXPC",
           condition: .when(platforms: [.macOS]))
])
// Demo.swift:全部内容 #if os(macOS) 守卫
```

- macOS 构建:通过(SwiftXPC 正常编译链接);
- **iOS 模拟器 destination 构建:通过(1.97s,SwiftXPC 完全不在构建计划内)**;
- 对照组(无条件依赖,初版实验):iOS 构建在 SwiftXPC 源内失败——`xpc_connection_create_mach_service`/`xpc_main`/`xpc_transaction_*`/`xpc_connection_get_pid` 为 Apple 标注 unavailable in iOS,对端鉴权族需 iOS 17.4/18+,其余地板杂音因依赖未声明 iOS 平台按默认低地板编译——这些事实界定了"哪些内容必须留在条件区内"。

**落地形态**(全部既有 SwiftPM/语言机制,零上游变更):

1. `Package.swift`:主包新增 `RimeKitXPC` 目标,其依赖唯一写法为 `condition: .when(platforms: [.macOS])`;开发期 SwiftXPC 走本地 path,发布切 tag;
2. `RimeKitXPC` 目标**每个源文件**整体 `#if os(macOS)` 守卫(iOS 侧编译为空模块;守卫纪律进 CI——iOS destination 构建即守护,任何漏守卫立即暴露);
3. 公开 API 逐个 `@available(macOS 15, *)`(地板来自 `XPCRootConnection` 系,§2.3);
4. 核心目标不依赖 SwiftXPC,协议重塑保持平台中立,iOS 15 声明不变。

**语义边界不变**:launchd 命名服务模型在 iOS 运行时不存在,蓝绿/XPC 服务仅 macOS 可用;可用性声明如实表达。iOS 上若未来出现 IPC 需求(App↔扩展匿名 endpoint/NSXPCConnection 通道),属另一传输层设计。

### 2.6 并发模型考察:librime 1.16.1 内部同步结构(2026-09-09 源码级核实)

核实对象:`rime_api.h`/`rime_levers_api.h`(本地 1.16.1-pack.8 头文件)与 librime 源码(`service.h/cc`、`rime_api_impl.h`、`deployer.cc`,1.16.1 标签与 master 双重确认)。

| 操作类别 | 实际串行化手段 | 出处 |
|---|---|---|
| 会话按键/提交/上下文读取 | **无锁**——C API 直接取 `an<Session>` 裸调,包装层 0 处 lock_guard | `src/rime_api_impl.h` |
| 会话表创建/查找/销毁 | **无锁**——`sessions_` 普通 map 裸操作 | `src/rime/service.cc` |
| Session 对象内部 | **无锁**(1.16.1 起无独立 session.h,Session 定义于 service.h,成员无 mutex) | `src/rime/service.h` |
| config 读写(含与 session 之间) | **无锁**,独立路径,零互斥 | `src/rime_api_impl.h` |
| 通知回调 | **唯一带锁点**:`Service::Notify` 持 `mutex_` 串行化回调本身;**回调可能来自部署维护线程** | `src/rime/service.cc`、`rime_api.h` L227–229 |
| 部署/维护 | `Deployer::mutex_` 仅护任务队列;维护跑 `std::async` 独立线程;**维护期 `Service::disabled()` → 全部会话调用立即返回 false(不阻塞不排队)**;`join_maintenance_thread` 阻塞至完成 | `src/rime/deployer.cc`、`service.h` |
| 生命周期 setup/initialize/finalize | 无锁,纯顺序约定 | `rime_api.h` L262–263 |

- **官方表述**:头文件/README/源码注释零线程安全承诺;生态佐证 [rime/weasel#1487](https://github.com/rime/weasel/issues/1487)(并发调用崩溃);官方前端(Squirrel/Weasel/iBus)均把全部调用收敛到单线程。
- **三问答案**:不同 session 并发=不安全(会话表裸操作+共享组件状态);session↔config 并发=不安全(独立无锁路径);部署期间服务调用=立即 false(非阻塞)。
- **结论**:librime 既不提供真实并行、也不提供内部全局锁——"多个 Swift actor 各持队列并发调用"不是退化为一把锁,而是未定义行为。正确架构是**单一执行域独占全部 librime 调用**(§3.7)。
- **IMK 补充**:macOS InputMethodKit 编程模型全同步(`inputText:keyChar:modifiers:client:` 等回调要求同步返回),与 actor 集成必然存在同步桥——阻塞等待点清点与不变式见 §3.8。

## 3. 统一 Rime 协议改造规格

### 3.1 wire-compatible 签名规则(六条)

统一后的 `Rime` 协议(阶段 2a 落地于核心模块)须满足:

1. **无所有权修饰**:`borrowing`/`consuming` 参数一律降为普通参数(仅涉及 `ObjectHandle`,无损失);
2. **参数与返回全部 XPCMarshal 兼容值类型**:已满足(DTO/句柄/`RimeSessionID`/基本类型);禁止 `Any`、不透明返回、`AsyncStream` 等流类型作为协议要求;
3. **typed throws**:全部要求改为 `async throws(RimeError)`;
4. **无逃逸闭包要求**:`setNotificationHandler` 移出协议(保留为 `RimeEngine` 专属 API,进程内用户不受影响;XPC 侧经 sink actor);
5. **label 小写开头**(SwiftXPC `parseTargetIdentifier` 限制):现有 81 个要求的 label 全部已合规,作为命名纪律写死;
6. **无泛型方法、无 `any` 存在型参数/返回**:现有要求天然合规,作为演进纪律写死。

> 布尔返回语义决策:librime 大量 `Bool` 返回分两类——"应答型"(`processKey` 返回是否处理)保持不变;"成败型"(`deploy/prebuild/deploySchema/…`)**也保持 Bool 签名**(marshalable、改动最小、蓝绿预热探活足够;细化错误诊断靠日志与 `RimeError` 的其它 case)。typed throws 专收**结构性与状态性**失败(§3.3)。

### 3.2 全量审计表(81 个要求 → 改造后形态)

改造为**机械性、无语义损失**,按簇列示(同簇方法变换相同):

| 簇 | 成员(方法/属性) | 改造 |
|---|---|---|
| 生命周期 | `setup(with:)`、`initialize(with:)`、`finalize()` | `throws(RimeError)`;traits 类型不变(公开构造器,见 D3) |
| 通知 | `setNotificationHandler(_:)` | **移出协议** → `RimeEngine` 专属 API;协议侧删除 |
| 维护 | `startMaintenance(fullCheck:)`、`isMaintenanceMode`、`joinMaintenanceThread()` | throws;Bool/Bool 属性签名不变 |
| Deployer | `initializeDeployer(with:)`、`prebuild()`、`deploy()`、`deploySchema(withID:)`、`deployConfig(filename:versionKey:)`、`syncUserData()` | throws(Bool 保留,成败型决策见上) |
| 会话 | `createSession()`、`findSession(with:)`、`destroySession(with:)`、`cleanupStaleSessions()`、`cleanupAllSessions()` | throws;`findSession` 现返回 `Bool`,保持 |
| 按键 | `processKey(keyCode:modifierMask:for:)`、`commitComposition(for:)`、`clearComposition(for:)` | throws(应答型 Bool 保留);`CInt` → 定宽 `Int32`(marshal 明确性) |
| 输出 | `commit(for:)`、`status(for:)`、`context(for:)` | throws;Optional DTO 保留(缺省=无数据,非错误) |
| 选项/属性 | `option(named:for:)`、`setOption(_:value:for:)`、`property(named:for:)`、`setProperty(_:value:for:)` | throws |
| Schema | `schemaList`、`currentSchema(for:)`、`selectSchema(_:for:)` | throws |
| Config 打开 | `openSchema(_:)`、`openConfig(_:)`、`openUserConfig(configId:)` | throws;返回 `ObjectHandle<RimeConfig>?` 保留 |
| Config 读写 | `close(config:)`、`string/int/bool/double(forKey:in:)`、`item(forKey:in:)`、`set(_:forKey:in:)` ×5、`removeValue(forKey:in:)`、`update(signature:for:)`、`beginMap/beginList(forKey:in:)`、`advanceConfigIterator(_:)`、`endConfigIterator(_:)`、`makeConfig()`、`load(yaml:into:)`、`createList/createMap(forKey:in:)`、`listSize(forKey:in:)` | 19 个方法、20 处 `borrowing` 全部去除 + throws;**句柄不存在时由强解包崩溃改为 `throw .invalidHandle`**(D4 收口) |
| 输入/光标 | `input(for:)`、`set(input:for:)`、`caretPosition(for:)`、`set(caretPosition:for:)` | throws(蓝绿迁移原语,见 §4.4) |
| 身份/目录 | `userID`、`userDataSyncDirectory`、`version`、`sharedDataDirectory`、`userDataDirectory`、`prebuiltDataDirectory`、`stagingDirectory`、`syncDirectory` | throws;签名不变 |
| 候选(句柄式) | `beginCandidates(for:)`、`advanceCandidateIterator(_:)`、`endCandidateIterator(_:)`、`candidateList(fromIndex:for:)` | throws;**先修 D2**(服务端补句柄存储);`candidates: AsyncStream` 降为协议扩展 |
| 候选(页式) | `selectCandidate(at:for:)`、`selectCandidateOnCurrentPage(at:for:)`、`removeCandidate(at:for:)`、`removeCandidateOnCurrentPage(at:for:)`、`highlightCandidate(at:for:)`、`highlightCandidateOnCurrentPage(at:for:)`、`page(_:for:)` | throws;应答 Bool 保留 |
| 状态标签 | `stateLabel(for:state:in:)`、`stateLabel(for:state:abbreviated:in:)` | throws |

### 3.3 `RimeError` typed throws 设计

```swift
/// 核心模块声明(平台中立,不依赖 SwiftXPC)
public enum RimeError: Error, Sendable, Hashable {
  case invalidHandle(kind: HandleKind, id: UUID)   // 收口 D4 全部强解包
  case sessionNotFound(RimeSessionID)
  case engineNotInitialized                        // initialize 前/ finalize 后调用
  case maintenanceMode                             // 维护期拒绝服务性调用
  case deployFailed(operation: String)             // deploy 族失败的细节补充通道
  case invalidArgument(String)
  case apiUnavailable(String)                      // 函数指针表缺项(旧 librime)
}
public enum HandleKind: Sendable, Hashable { case config, configIterator, candidateIterator }
```

- 服务端:替换全部强解包点(D4);`deinit` 派生清理 Task 改为可容忍 `engineNotInitialized`(静默)。
- 线缆:`XPCReplyEnvelope.throwError` 经 `xpcDistributedTargetMetadata` 的 `thrownErrorType` 解码回 `RimeError`(SwiftXPC typed-throws 闭环,需在包内 XPC 条件编译区为 `RimeError` 手写 `XPCMarshal` 一致性——枚举 case 名标记法,与 `#XPCMarshal` 生成物同形)。
- 客户端:`RemoteRimeEngine` 原样重抛 → `any Rime` 调用方拿到的是**同一类型化错误**,蓝绿管理器据 `engineNotInitialized`/`deployFailed` 做预热失败判定。

### 3.4 见证与客户端策略(2026-09-09 语言探针实证修订)

**探针实证的语言事实**(Swift 6.3.3,编译/运行实测 + SwiftXPC 源码核对):

| # | 事实 | 证据 |
|---|---|---|
| F1 | 协议内**不得**声明 `distributed func`——"分布式协议"从未落地;契约协议只能是普通形态 | 编译器实测:`'distributed' method can only be declared within 'distributed actor'` |
| F2 | `distributed func` **可以**见证普通协议的 `async throws` 要求 | 探针编译通过(`RemoteEngine: Rime`,typed throws 见证) |
| F3 | 但 **distributed actor 见证 typed throws 协议 = Swift 6.3.3 IRGen 崩溃**(signal 11);untyped throws 可编译 | 探针二分实测 |
| F4 | `@XPCService` **只能贴 actor 声明本体**,且只枚举声明体内成员;贴扩展=诊断错误,跨模块不可见 | 源码 `XPCServiceMacro.swift:17`(guard `ActorDeclSyntax`)、`:22–26`(memberBlock 枚举) |
| F5 | 跨模块为核心类型手写 `XPCMarshal` 一致性扩展**可行**(同包直接扩展;独立包加 `@retroactive`) | 探针编译通过(Point/RimeErr) |
| F6 | **"核心改分布式 actor"纯形式被三堵墙挡死**:① 单 actor 单系统类型——`XPCExportableActor where ActorSystem == XPCDistributedActorSystem`(`XPCActorReference.swift:22–23`),同一类型无法既绑本地系统又绑 XPC 系统;② 核心若泛型化/存在型化系统,则无法命名 `XPCMarshal` 作为 SerializationRequirement 约束(协议≠协议同型约束不存在);③ 泛型 distributed 方法语言级禁止 | 源码核对 + 类型系统推演 |
| F7 | `import Distributed` 在 iOS 可用(标准库模块) | iOS 模拟器 SDK typecheck 通过 |

**修订后的架构**(决策 5:具体类型契约):

```swift
// 核心(RimeKit,平台中立,iOS 15 不变):
//   Rime 普通协议保持为【进程内接缝】——重塑仅限:去 borrowing、typed throws(RimeError)、
//   setNotificationHandler 移出;RimeEngine 保持普通 actor(现状);核心不声明任何分布式 actor。
//   RimeSession 泛型化:`public struct RimeSession<Engine: Rime>: ~Copyable`
//   (进程内用法 RimeSession<RimeEngine>;测试/替换经协议,无远程引用进存在型)。

// XPC 条件编译区(主包内 RimeKitXPC 目标,#if os(macOS) 守卫,公开 API 均 @available(macOS 15, *)):
@XPCService
public distributed actor RimeServiceRoot: XPCRootActor {
  public typealias ActorSystem = XPCDistributedActorSystem
  // 81 个 distributed func,签名与重塑后 Rime 要求 1:1 镜像(属性→getter 方法),
  // typed throws(RimeError)(宏据此生成 thrownErrorType 元数据,上游 IntegrationError 同型实证),
  // 实现体一行委托 RimeEngine.shared —— 这是仅存的服务端委托面。
  // 注意:不 conform Rime(F3 编译器崩溃;具体类型契约下亦无必要)。
}

// 客户端(RimeKitXPC):
//   直接持有具体类型引用 —— resolve 返回的远程代理与本地实例同为 RimeServiceRoot:
//   let rime = try RimeServiceRoot.resolve(id: .root, using: clientSystem)
//   try await rime.processKey(...)   // 直接调用,编译器生成 thunk 走线缆
//   蓝绿 = 同一具体类型的两个引用(蓝/绿各一条 XPCRootConnection),换绑即引用交换。
```

- `RemoteRimeEngine` 81 行客户端适配器**废除**(原 §3.4 方案);`any Rime` 不再承载远程引用(决策 5)。
- `@XPCService` 在 XPC 模块自己的 actor 声明上合法(F4),81 方法元数据(含 typed throws 错误类型)由宏全量生成——手写元数据表仅作后备(F5 证明扩展一致性可行,但此处无需)。
- 通知 sink(`RimeNotificationSink`,§3.5)同样声明在 XPC 模块,宏路径一致;客户端本地实例化 sink 所需的系统即客户端自己的 `XPCDistributedActorSystem` 实例(探针中已按此构造连接对)。
- 兼容门面(可选,2b 视需求):为让既有 `any Rime` 面向进程内的调用方平滑迁移,XPC 模块可提供一个薄门面 actor(普通 actor,持有 root 连接,untyped throws 转发)——注意其错误语义退化为 `XPCRemoteCallError`,默认不提供,登记为选项。

### 3.5 通知回调的 XPC 化:`RimeNotificationSink`

利用 §2.4 的 actor 引用能力(本方案唯一需要反向调用的场景):

```swift
// RimeKitXPC 目标(服务端声明,客户端本地实例化)
@XPCService distributed actor RimeNotificationSink {
  // 客户端本地 init 捕获既有 RimeNotificationHandler 闭包,保持进程内 API 兼容
  public init(actorSystem: XPCDistributedActorSystem,
              handler: @escaping RimeNotificationHandler)
  distributed func emit(_ session: RimeSessionID,
                        _ type: RimeNotificationType, _ value: String) // → 调 handler
}

// RimeServiceRoot 增补(不进 Rime 协议):
distributed func setNotificationSink(_ sink: RimeNotificationSink?)  // nil = 取消注册
```

- 服务端实现:收到 sink 后调用引擎的 `setNotificationHandler { session, type, value in Task { await sink.emit(...) } }`(C thunk 在 librime 线程上同步回调,须立即脱线程,只在引擎 actor 内捕获 sink 并转 Task)。
- 客户端:`RemoteRimeEngine` 提供 `setNotificationHandler(_:)` 兼容门面,内部建本地 sink actor 实例并注册(**前置依赖 §5.3-V1**:客户端自有 system 的获取方式)。
- 蓝绿纪律:换绑后必须**在新活动端重注册 sink**;drain 期蓝机仍可能推送迟到通知,sink 需容忍"来自已退位实例"的通知(管理器在 drain 完成后静默丢弃)。

### 3.6 序列化一致性落点:核心零依赖(宏不可用),一致性手写于 XPC 条件编译区

- `#XPCMarshal` 是 attached 宏,只能贴在**类型声明处**;DTO 声明必须双平台存在(核心引擎在 iOS 也要用),无法整体放进 `#if os(macOS)` 守卫,而贴宏又要求该文件导入 SwiftXPC——iOS 侧即断。故宏对 DTO 不可用,一致性手写。
- **决策**:核心只重塑签名与新增 `RimeError`(平台中立);`XPCMarshal` 一致性在包内 XPC 条件编译区**手写**(约 20 个 DTO + `RimeError` + 泛型 `ObjectHandle`——后者 payload 仅 UUID,单份一致性即可覆盖全部 T)。
- 防漂移:XPC 条件编译区内为每个一致性写**往返(round-trip)测试**;线缆演进遵守 §4.7。备选(若手写量不可接受):DTO 迁入包内独立契约目标以使用宏——登记为后备(宏只能贴声明处,DTO 声明须随迁;XPC 目标可贴宏但 DTO 声明在核心区)。

---

### 3.7 执行域与队列规则(并发架构定案,决策 7)

**方案 1(确立)**:根 actor(RimeServiceRoot)为低级别 API、全量暴露函数,作为 librime 调用的**唯一串行执行域**——进程内即 `RimeEngine` actor;服务进程内逐 peer 根 actor 一行委托 `RimeEngine.shared`,多连接天然汇流到同一执行器。语义化 API(DTO、`RimeSession<Engine>` 门面、候选流、§3.8 后的语义封装)为**非 actor 二次封装层**:只做工效学增值(组合调用、流、值类型化),不持有队列、不触碰 librime。

**方案 2(否决,证据链)**:会话 actor/配置 actor/维护 actor 各持队列 ⇒ 多执行流并发触达 librime ⇒ 按 §2.6 是数据竞争而非"退化为内部全局锁"。librime 不提供内部并行,自有队列换不来吞吐;真实代价反而是:跨 actor 的调用重排序(按键序列失去全序)、actor 间 await 的死锁面、以及每个语义 actor 到拥有者的额外 hop。可并行的真实空间只有三处,均已由既有设计覆盖:绿机预热部署(独立进程,§4.3)、通知 sink 的 Swift 侧扇出(§3.5)、取数后的纯 Swift 值处理(语义层,无锁自由处理)。

**安全规则**(与 §3.8 不变式配合):
- (a) 全部 `rimeApi` 调用只发生在拥有者 actor 上,禁止脱离执行域的裸调用或 `Task.detached` 直调;
- (b) 通知 thunk 严禁同步重入 librime——立即脱线程转发(进程内转闭包 Task,XPC 转 sink actor);
- (c) `join_maintenance_thread` 阻塞拥有者执行器:服务侧仅限关停/维护窗口调用,禁止进入按键服务路径;
- (d) 维护期会话调用**静默返回 false**(非报错):蓝绿预热健康探针必须用 `isMaintenanceMode` 区分"维护中"与"部署失败";
- (e) 有序性:XPC 每通道 FIFO + 拥有者 actor 执行器 ⇒ 单会话按键序列全序;方案 2 不提供更强保证,反而破坏之。

### 3.8 同步桥与死锁不变式(IMK 集成,决策 8)

macOS IMK 编程模型全同步:回调要求同步返回按键处理结果。actor 引擎与同步宿主之间必然存在**同步桥**。全部阻塞等待点清点:

| # | 阻塞等待点 | 性质 |
|---|---|---|
| W1 | IMK 回调线程阻塞于引擎 actor 结果 | 设计内的同步桥 |
| W2 | 引擎 actor 内 `join_maintenance_thread` | 阻塞整个执行器,秒~分钟级 |
| W3 | XPC 客户端阻塞等服务响应 | 无超时(风险 R1) |
| W4 | 通知 sink 走独立匿名 endpoint 通道 | 不与请求/应答通道共用,无队头阻塞 |
| W5 | 通知 thunk → sink 转发 | 脱线程 fire-and-forget,引擎不等待 |
| W6 | `initialize`/`deploy` 在拥有者 actor 上执行 | 阻塞执行器(秒级) |
| W7 | 潜在 ABBA:actor 内同步询问客户端/主线程的未来功能 | 当前 API 无此需求,列为禁用模式 |

**不变式 I1–I6**(编码进 2b 代码审查与宿主集成文档):

- **I1 单一执行域**:全部 rimeApi 调用只在拥有者 actor(= §3.7 规则 (a))。
- **I2 同步桥只阻塞 IMK 自己的回调线程**(IMK 本就期望同步方法);**严禁阻塞 Swift 协作线程池**。标准模式:

  ```swift
  // IMK 回调(IMK 自己的线程,允许阻塞)
  func inputText(_ string: String!, client: Any!) -> Bool {
    let gate = DispatchSemaphore(value: 0)
    var result = false
    Task.detached {               // Task 内正确挂起,协作池只挂起不阻塞
      result = await controller.handle(string, client: client)
      gate.signal()
    }
    gate.wait()                   // 仅阻塞 IMK 线程
    return result
  }
  ```

- **I3 无回环**:拥有者 actor 不得 await 任何直接/间接回调自身的执行体;通知一律脱线程 fire-and-forget(`try? await sink.emit` 之外的 `await sink` 进临界区即违规)。
- **I4 服务路径禁阻塞操作**:`deploy/prebuild/syncUserData/joinMaintenanceThread` 不得出现在按键服务路径;in-process 模式仅限启动早期或显式维护窗口;XPC 模式由绿机预热/运维通道吸收(§4.2)。
- **I5 维护期语义**:维护期会话调用静默 false——IMK 适配层须定义丢键行为(丢弃/缓冲策略由宿主定);蓝绿模式由绿机预热规避。
- **I6 引擎 actor 上禁止一切长任务**:IMK 回调默认落输入法进程主线程(实现期探针确认),主线程经 W1 阻塞于引擎 ⇒ 引擎上的长任务等于整个输入法进程卡顿;这是 W3"无超时"风险的进程内对应形态。

**结论**:W1–W7 中不存在环形依赖——引擎从不同步等待任何会回到引擎的路径(I3),通知独立通道(W4),阻塞操作全部隔离于服务路径(I4);配合 I2/I6 即**无死锁**。残余风险为"挂起"而非"死锁":服务挂死(W3)由蓝绿兜底,进程内长任务(W6)由 I4 规避。

## 4. 蓝绿热切换方案

### 4.1 进程拓扑与部署形态

```
Host.app/Contents/XPCServices/
  ├── RimeService.blue.xpc    ┐ 同一二进制,两个 bundle id
  └── RimeService.green.xpc   ┘ CFBundleIdentifier == mach service name
```

- launchd on-demand(`ServiceType = Application`),打包方式复用 SwiftXPC Demo 的 `build-demo-bundle.sh` 模式。
- 同一服务二进制只部署一份逻辑代码;蓝/绿只是**两个可独立替换升级的实例槽位**。升级 = 替换非活动槽位的 bundle → 预热 → 换绑 → drain → 下一轮角色互换。**"当前活动色"由客户端管理器持久化**(App Support 下一个小状态文件),App 重启后能认出谁是蓝谁是绿。

### 4.2 服务端:`RimeServiceRoot`

- `distributedXPCMain(RimeServiceRoot.self)`;`XPCRootActorServer` 对**每个 peer 连接**新建一个 root actor 实例,全部委托 `RimeEngine.shared`(进程内仍单例)。
- 在 `Rime` 全量方法之外增补运维面(不进协议):`serviceVersion() -> String`(构建号/契约版本)、`healthCheck() -> Bool`、`setNotificationSink(_:)`(§3.5)。
- **运维通道分离**:预热期对绿机发起的 `deploy/fullCheck/syncUserData` 走**专用第二条连接**(第二个 peer → 第二个 root actor 实例 → 同一引擎),避免长调用在传输层队头阻塞同通道的会话操作;引擎级串行仍存在,但真正的重活发生在"尚无客户端会话"的绿机上,实际影响为零(阻塞规则 I4:服务路径禁 deploy/join,§3.8)。
- 生命周期:服务进程随最后一个连接断开被 launchd 回收前,`xpcTransactionBegin/End` 在预热窗口保活;librime 冷启动成本(initialize+deploy,秒级)只在预热路径发生。

### 4.3 客户端:`RimeBlueGreenManager` 状态机

```swift
@available(macOS 15, *)
public final class RimeBlueGreenManager: Sendable {
  // 双通道句柄;活动侧由 Mutex<Side> 保护 —— 原子换绑就是一次引用交换(同一具体类型)
  private let sides: (blue: SideHandle, green: SideHandle)
  private let active: Mutex<Side>

  public var activeRoot: RimeServiceRoot { ... }  // active 侧连接的根代理(具体类型,非存在型)

  public func preheat(_ side: Side, traits: RimeTraits) async throws(RimeError)
  public func switchOver() async            // 原子换绑 + 会话迁移 + sink 重注册
  public func drain(_ side: Side) async     // 在途计数归零后 close()
  public func rollback(to side: Side) async
}
```

流程(绿升级示例):

1. **预热**:`connect(toService: …green.xpc)` → `retrying { initialize(traits) }` → (可选)`deploy`/`prebuild`(运维通道)→ `serviceVersion()` 断言版本匹配 → 健康探活(探活须以 `isMaintenanceMode` 区分"维护中"与"部署失败",§3.7 规则 (d))。任一步 `throws(RimeError)` → **回滚**(保持蓝,关闭绿连接,上报)。
2. **迁移**:见 §4.4。
3. **换绑**:`active.swap(.green)`(Mutex,单条指令级原子)。此刻起新调用全部走绿;蓝上**在途调用**照常完成(两个通道互不干扰,子通道无共享状态)。
4. **drain**:蓝侧在途计数(管理器包一层计数器)归零 → 显式销毁蓝侧剩余会话(避免 deinit 派生 Task 的竞态窗口,D5)→ `handle.close()`。launchd 随即回收蓝进程。
5. **记录**:持久化 `active = green`,供下次升级互换。

**超时缺口**(SwiftXPC v0.2.0 无超时/取消):预热阶段管理器**自行包超时**(对 `retrying` 外再套 `Task` 竞速 + 失败即放弃该侧连接),因为预热的对端是刚被 launchd 拉起的新进程,卡死概率最高且此时还没有用户流量,放弃成本最低。服务中调用仍无超时——这是 SwiftXPC Phase 6 的上游欠账,登记风险 R1。

### 4.4 会话状态迁移

蓝绿切换时,librime 会话表不可跨进程,按会话快照迁移(原语全部现成,即 `ed6baef` 的 input/caretPosition setter):

```
对蓝侧每个活跃会话 s:
  快照 = (input: s.input, caret: s.caretPosition,
          schema: s.currentSchema, options: [命名选项集 → Bool])
  绿侧 createSession() → set(input:) → set(caretPosition:) → selectSchema → setOption×n
  新 sessionID 记入映射表,客户端门面重建 RimeSession(engine: greenEngine, sessionID: 新ID)
```

- 选项集迁移范围:显式声明的已知集(`ascii_mode`、`full_shape`、`ascii_punct`、`simplification` 等)而非全量枚举——librime 无"枚举全部选项"API,未知选项经 `option(named:)` 按白名单拉取。
- 迁移在换绑**之前**完成(绿侧会话就绪后才 swap),换绑瞬间无窗口期;输入中的组合串经 `input/caret` 快照完整保留。

### 4.5 Drain、回滚与崩溃恢复

- **drain 语义**:纯客户端构造(SwiftXPC 无服务端 drain 原语)。在途计数 + 显式会话销毁 + `close()`;不追求"服务端拒绝新调用"的精确闸门,因为"新调用路由"本来就在客户端手里(换绑即闸门)。
- **回滚**:预热/迁移/探活任一步失败 → 保持蓝机活动,关闭绿连接(launchd 回收),上报 `RimeError` + 阶段标记。蓝机全程未受扰动,回滚零成本——这是蓝绿相对"就地重启"的核心价值。
- **崩溃恢复与蓝绿的互补**:SwiftXPC 中**根通道可自愈**(命名连接,launchd 重拉后同一根代理下次调用即恢复,探针实证),**子状态不可自愈**(会话表在进程内,崩溃即失)。蓝绿不改变这一点,但把两类事件正交化:
  - 崩溃(非升级):`events` 收到 `.disconnected` → 根代理重试自愈 → **无绿机可切**(绿不是常驻的),走"重初始化 + 会话重建"路径(可复用迁移代码,只是源为空);
  - 升级:受控换绑,无崩溃。
  - 后续可选演进:崩溃时拉起对侧槽位当临时绿机走完整蓝绿流(把崩溃恢复统一进蓝绿路径),登记为路线图可选项。

### 4.6 线缆契约演进纪律

drain 期客户端**同时**与蓝(旧构建)、绿(新构建)两代服务通信 → 相邻构建间契约必须互通:

- `XPCInvocationMessage/XPCReplyEnvelope` 已带 `version`(现 `currentVersion = 1`),不匹配报 `unsupportedProtocolVersion` —— 预热探活时即暴露;
- **additive-only**:DTO 只能**尾部加字段**(`#XPCMarshal` 按字段序编码,插入/重排即破线缆);改字段顺序/类型 = bump 线缆版本并放弃跨代 drain(退化为"蓝直接关、绿全量重建会话");
- `RimeError` 新增 case 同理 additive-only(旧客户端遇未知 case 报 `unknownEnumCase`,可接受);
- 服务与宿主同 bundle 分发时版本天然锁定,此纪律只在"服务热升级"场景生效,作为约束写进 CI(一致性往返测试即护栏)。

---

## 5. 路线图与风险

### 5.1 阶段划分

| 阶段 | 内容 | 退出标准 |
|---|---|---|
| **2a 地基**(纯核心,不引 SwiftXPC) | 修 D1(测试目录/import 重命名 + 首批真实测试);修 D2(候选迭代器补存储);D3(`RimeTraits` 公开 memberwise init);typed throws `RimeError` 落地协议与实现、替换全部强解包(D4);去 `borrowing`;`setNotificationHandler` 移出协议;`RimeSession` 泛型化 `RimeSession<Engine: Rime>`;D6/D7/D8 卫生;tools 6.1→6.2 | `swift test` 绿;81 要求全 `throws(RimeError)`;核心仍 macOS 13/iOS 15 |
| **2b XPC 目标** | 主包内新增 RimeKitXPC 目标(依赖 RimeKit 核心区 + DistributedXPC 0.2.0,开发期本地 path 依赖;**依赖声明带 `condition: .when(platforms: [.macOS])`,§2.5**):源文件全部 `#if os(macOS)` 守卫;全部公开 API 标注 `@available(macOS 15, *)`;新增库产品;DTO/`RimeError`/`ObjectHandle` 手写 `XPCMarshal` + 往返测试;`@XPCService RimeServiceRoot`(81 个 distributed func,typed throws,委托 `RimeEngine.shared`,**不 conform Rime**,§3.4 F3);客户端直接持具体类型引用(无适配器);`RimeNotificationSink`;运维面方法 | 端到端:双进程(demo bundle)内以具体类型全流程跑通,含按键/候选/配置/通知回传;**RimeKit 包 iOS 模拟器 destination 构建保持绿**(§2.5 守护) |
| **3 蓝绿管理器** | `RimeBlueGreenManager`(预热/迁移/换绑/drain/回滚/持久化);运维通道分离;集成测试(参照 SwiftXPC `XPCRootReconnectionTests` 的真实 connection pair 模式 + 双实例 kill/relaunch 探针) | 真机双 .xpc 换绑切换,drain 期无丢失调用;预热失败自动回滚 |
| **4 交付** | 打包脚本(双槽位 bundle)、签名要求(peer code-signing requirement 接入 `shouldAccept`)、运维文档(升级/回滚手册、`serviceVersion` 语义) | 文档 + 打包脚本入库 |

### 5.2 风险登记表

| # | 风险 | 等级 | 缓解 |
|---|---|---|---|
| R1 | SwiftXPC 无超时/无取消:服务端一次卡死(librime hook 死锁、畸形 schema)永久占用通道 | 高 | 预热路径自带超时竞速(§4.3);服务路径短期接受,推动上游 Phase 6;蓝绿本身是兜底(整进程可弃) |
| R2 | launchd 空闲回收:低峰期杀服务 → 下次按键冷启动(秒级) | 高 | 预热窗口 `xpcTransactionBegin/End` 保活;评估 plist 禁 idle exit;冷启动路径复用迁移代码快速重建 |
| R3 | 宏字段序脆弱:DTO 重排即破跨代 drain | 中 | §4.6 additive-only 纪律 + 往返测试入 CI |
| R4 | `RimeServiceRoot` 81 处服务端委托为手写面,易漂移 | 中 | `@XPCService` 元数据编译期生成,漏方法在调用时报 `unknownTarget` 即时暴露;codegen 脚本可选。另登记(F3):未来若让根 actor 回接 `Rime` 一致性,typed throws 见证在 Swift 6.3.3 触发 IRGen 崩溃,需等编译器修复后重评 |
| R5 | 通知 sink 依赖客户端自有 `XPCDistributedActorSystem`(§5.3-V1 未验证) | 中 | 2b 首个验证项;若 `XPCRootConnection` 不暴露,可独立构造 system(export 只需匿名监听,不依赖根连接)或推动上游暴露 |
| R6 | iOS 边界:XPC 能力在 iOS 不可用(命名服务模型被 Apple 标注 unavailable,§2.5) | 低 | 平台条件化依赖(`.when(platforms: [.macOS])`)使 iOS 构建图不含 SwiftXPC + 目标内 `#if os(macOS)` 守卫 + `@available(macOS 15, *)` 门控;CI 加 iOS destination 构建守护(漏守卫/误依赖即红) |
| R7 | 每 peer 一个 root actor 实例的语义:两条连接看到两个实例,但共享同一引擎/会话表 | 低 | 文档明示"多连接=同引擎多视图";管理器用键避免跨连接句柄混用 |

### 5.3 语言探针实证结论(2026-09-09)与余留验证项

**已实证**(探针包三目标:核心零依赖 / XPC 绑定 / 可执行,详见 §3.4 事实表 F1–F7):

- ✅ 协议内禁止 `distributed func`(F1);`distributed func` 可见证普通协议 async- throws 要求(F2);typed throws 见证触发 Swift 6.3.3 IRGen 崩溃(F3)。
- ✅ `@XPCService` 仅限 actor 声明本体(F4);跨模块手写 `XPCMarshal` 扩展可行(F5);`import Distributed` iOS 可用(F7)。
- ✅ typed throws 跨进程错误还原:SwiftXPC 上游 `DistributedXPCReplyTests` + `IntegrationGreeter`(typed `IntegrationError`)同型实证——本方案 `RimeError` 走同一机制。
- ✅ 进程内连接对(`XPCConnection(name: nil)` + endpoint marshal/unmarshal + `reserveRootID`/`bind`/`resolve`)可在客户端代码中构造——通知 sink 的本地实例化路径可行(V1 关闭:客户端自建 `XPCDistributedActorSystem` 即可,无需 `XPCRootConnection` 暴露内部系统)。
- ➖ 存在型 `any Rime` 装载远程引用的运行时路由:按决策 5 整体不采用,不再验证。

**余留验证项(阶段 2b 首批)**:

- **V3** `Int32`/`UInt`(`RimeSessionID`)在 XPCMarshal 手写一致性下的定宽编码往返。
- **V4** 泛型 `extension ObjectHandle: XPCMarshal` 单份一致性覆盖全部 `T` 的编译形状(`static func unmarshal(from:) -> Self` 在泛型上下文的解析)。
- **V5** launchd 下双槽位 .xpc 并存、按名独立拉起/回收(demo bundle 脚本扩展)。
- **V6** 上游核对:大写 label 限制在 `parseTargetIdentifier` 修复后可解除(不影响本方案,现有命名已合规)。
- **V7(升级为阻塞项)**:Swift 6.3.3 分布式 actor 缺陷族(F3 家族)实测扩大——除 F3 的 IRGen 崩溃外,同一类型内声明约 10 个以上 `distributed func` 后,后续方法**失去隐式 async**("add 'async' to function ..."/"function that does not support concurrency"),边界随文件布局/拆分**非确定性移动**,与 typed/untyped throws 无关,扩展与多文件拆分均无法绕过(2026-09-09 在 RimeServiceRoot 80 方法上实测,错误输出在案)。已获源码级可行的替代路径:**根 actor 以 untyped `throws` 声明 + 手写 `xpcDistributedTargetMetadata` 表携带 `thrownErrorType: RimeError.self`**——服务端 `onThrow` 按运行时值 cast 编码(XPCInvocationResultHandler.swift:33–38),客户端解码按元数据回退(XPCDistributedActorSystem.swift:216–226),类型化错误语义端到端保留;但服务端编码路径依赖的"运行时值 cast"仍需进程内连接对测试实证后启用。补充实证(同日):为根 actor 全部方法**显式标注 `async`** 后,类型检查阶段的隐式 async 丢失完全消失(显式标注不经过出错的细化路径,零语义代价);但编译在 IRGen 阶段崩溃(signal 5,F3 同族)——即缺陷横跨类型检查与 IRGen 两个阶段,Swift 6.3.3 上 80 方法 typed-throws 分布式 actor 无法落地。`RimeServiceRoot` 以 `RimeServiceRoot.swift.disabled.explicit-async` 保留(显式 async 版,最接近可用),`RimeKitRimeService` 可执行目标同步暂缓;解除条件:升级/修复工具链后重试该文件,或上报 swiftlang 待修复。
