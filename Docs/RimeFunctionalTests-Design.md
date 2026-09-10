# RimeKit 功能测试设计(swift test × Swift Testing)

- 状态:交付稿(测试基建 + 七个功能套件全绿;iOS destination 构建守护回绿)
- 日期:2026-09-10
- 依赖基线:librime-xcframework 1.16.1-pack.8;Swift 6.3.3 工具链内置 Swift Testing;
  SwiftXPC ≥ 0.3.2(自 v0.3.2 起为正式远程依赖,含 §7 两处线缆修复 + base 前缀元数据回退;
  此前为本地 path 依赖 + `wire-fixes-for-rimekit-e2e` 分支)
- 运行:`swift test`(macOS);iOS 守护:`swift build --destination <ios.json>`(v2 schema 见文末附录)

## 0. 参考来源(调研结论)

| 来源 | 现状 | 对本设计的输入 |
|---|---|---|
| **rime/squirrel**(鼠须管,master) | **零自动化测试**(2024 Swift 重写后仅有 SwiftLint/periphery/构建冒烟,无 test target) | 只能参考其**驱动流程**:setup(traits+通知回调)→ initialize → start_maintenance;通知四类消息(deploy/option/schema/property);X11 keysym + modifier 掩码(`MacOSKeyCodes.swift`);每控制器一会话、`find_session` 校验;退出时 `cleanup_all_sessions` |
| **rime/librime** | 完整 gtest 套件(`test/*.cc` + `data/test/` 自造小夹具;不依赖 rime-data/luna_pinyin,仅 OpenCC 外部依赖) | **夹具范式**:自造最小 yaml/词典随测试落盘(`rime_test_main.cc` 以 Environment 一次性 setup+initialize,工作目录即数据目录);组件级语义(config/dictionary/key_table)作为 C API 层测试的断言依据 |

即:Squirrel 侧**没有可抄的测试**,可抄的是"输入法前端怎么用 librime";librime 侧提供了"自造数据、进程内单次部署"的测试范式——本设计是两者的合成。

## 1. 架构

```
Tests/RimeKitTests/
├── Support/
│   ├── RimeBackend.swift            # 注入接缝:后端 → 根 actor
│   ├── RimeTestEnvironment.swift    # 进程级单次部署环境 + 通知收集器(C 钩子)
│   ├── MinimalRimeData.swift        # 自造最小方案数据(确定性夹具)
│   ├── RimeKeys.swift               # X11 keysym/modifier 常量(key_table.h 同源)
│   └── RimeSession+TestHelpers.swift# 键入/候选迭代小步进
├── EngineLifecycleTests.swift       # 生命周期/目录/运维面
├── SessionLifecycleTests.swift      # 会话表语义
├── TypingTests.swift                # 键入主路径(按键→组词→候选→提交)
├── CandidateTests.swift             # 页式菜单/翻页/高亮/句柄式迭代
├── SchemaTests.swift                # 方案表/切换/状态标签
├── ConfigTests.swift                # 配置读写/遍历/句柄纪律
├── NotificationTests.swift          # deploy/option/schema 通知
└── (RimeKitTests.swift / XPCWireTests.swift 为既有单测,未动)
```

### 1.1 注入接缝与双后端参数化(进程内 / 进程内 XPC)

测试体只面向 `RimeTestEnvironment.bootstrapped(backend:)` 给出的环境(根引用 +
数据目录 + 通知日志)。**每个功能测试函数以 `@Test(arguments: RimeBackend.allCases)`
参数化**,同一份断言在两种引用形态下各跑一遍:

| 后端 | 根引用形态 | 调用路径 |
|---|---|---|
| `.inProcess` | 服务端根 actor 的**本地引用** | 编译器直连,不过线缆 |
| `.inProcessXPC` | 经进程内 XPC 连接对 `resolve(id: .root)` 的**线缆代理** | 每次调用走完整 XPC 线缆(marshal/unmarshal、typed-throws 错误还原、每通道 FIFO) |

**单根不变式(§3.7)**:两个后端指向**同一个**根 actor 实例——它诞生在进程内
连接对的服务端(`RimeXPCWirePair.make()`,`reserveRootID` + `bind`)。若两后端
各持一个根实例,并行套件即绕过唯一串行执行域,对 librime 形成数据竞争(§2.6)。
单根双引用让 `swift test` 单进程内安全地并行跑满两种形态;这也是 §3.4"四种形态
调用点同构"的首次端到端实证(80 方法全量过线缆)。

- 连接对写法复制自 SwiftXPC `DistributedXPCIntegrationTests.makeConnectionPair`
  (匿名 listener → accept 回调内建服务端 system → endpoint marshal → client
  resolve);`reserveRootID`/`bind` 为 internal,经 `@testable import DistributedXPC`
  访问(SwiftPM debug 构建对依赖开启 testability,已实证)。
- Swift Testing 工具链无 `@Suite(arguments:)`(探针实证),参数化落在**测试函数级**
  `@Test(arguments:)`;`RimeTestRuntime`(部署 + 连接对)进程内单次,环境按后端缓存。
- 既有单元/线缆往返测试(RimeKitTests / XPCWireTests)不参数化,保持原样。

### 1.2 进程级 bootstrap(每测试进程至多部署一次)

`RimeTestEnvironment.deploy` 按 Squirrel 初始化序列执行:落盘夹具 → 通知回调注册 →
`setup(with:)` → `initialize(with:)` → `startMaintenance(fullCheck: true)` →
`joinMaintenanceThread()` → 探活(createSession ≠ 0 且 currentSchema == 主方案)。
并发套件经 `RimeBootstrap`(actor + 备忘 Task)共享同一次部署;失败可重试。

要点:
- **通知收集必须直挂 C API**(`RimeNotificationLog.installCollector`,Squirrel
  setupRime 同型):根 actor 的 `engineSetNotificationHandler` 是非 distributed 成员,
  不可经(可能是远程代理的)根引用调用。librime 通知本就是进程级单回调(§1.3),
  测试基建在 C 层注册最忠实;且必须先于 initialize,否则首部署事件丢失。
- bootstrap 内的 `joinMaintenanceThread` 阻塞执行域秒级——§3.8 I4 只约束服务路径,
  测试进程可接受。

### 1.3 确定性夹具(MinimalRimeData)

`default.yaml` + 两个 schema + 一个小词典(table 直查),全落临时目录(同时充当
shared/user data dir)。确定性设计:

- `enable_sentence/enable_user_dict/enable_completion` 全关 → 候选序 = 词典权重降序,
  与运行历史无关,跨测试无污染(代价:`delete_candidate` 的用户词典语义无法覆盖,
  见 §4);
- 引擎件仅 `ascii_composer/speller/selector/navigator/express_editor`,不引入带内建
  默认值的标点/识别部件;
- 两个方案共用词典,alt 方案为 schema 切换/通知测试服务;
- `mmmm` 码 12 条候选 × page_size 5 → 5/5/2 三页,翻页/末页断言全部确定。

## 2. 书写纪律(测试代码三条铁律)

1. **`~Copyable` 不进断言宏**:`RimeSession` 不可被 `#expect`/`#require` 的
   autoclosure 捕获(捕获即要求 Copyable,编译失败)。所有观察值先取局部值再进宏。
2. **非 distributed 成员不可经根引用调用**:根是"潜在远程"的 distributed actor,
   其扩展方法/internal 普通方法在调用点一律被拒;测试 helper 一律自由函数,
   经 distributed 方法组合实现(`collectAllCandidates` 即范例)。
3. **部署侧操作禁入测试体**:`deploy/prebuild/deploySchema(已知方案)` 会触发部署
   任务乃至维护窗口;维护期会话调用静默 false(§3.7 规则 d),并行套件随即雪崩
   (实证见 §3.5)。它们只允许出现在 bootstrap。

## 3. 实证语义摘录(librime 1.16.1,断言依据与陷阱)

这些结论已沉淀为测试断言或注释,是未来 remote/蓝绿实现的直接输入:

1. `select_schema` 只要会话存在即返回 true,**不校验方案存在**(rime_api_impl.h,
   DEPRECATED 路径);Bool 不是有效性信号。
2. `change_page` C API 不移动页(实测恒 false);翻页以 Page_Down/Page_Up 键驱动
   (navigator 消费 X11 keysym)——Squirrel 同型。
3. 配置键的列表索引语法为 `@n`(如 `schema_list/@0/schema`,同 custom patch 约定);
   `/0` 不命中。
4. `config_clear`(removeValue)缺键也返回 true;未知 config/schema `open` "成功"
   且得到空配置(可写形态),非 nil/错误。
5. 无用户词典(夹具配置)时 `delete_candidate` 返回 true 但不重排候选表。
6. `commit_composition` 在无候选(如退格到非完整码)时回退为提交原文。
7. `Context::set_input/set_caret_pos` 经 update 通知触发重算(context.cc):
   光标复位到快照位置后组合与现场键入等价——**蓝绿迁移假设 §4.4 成立**;
   但光标停在码内会改变分段,迁移必须连快照光标一并恢复。
8. 数字选择键在 `menu.select_keys` 报告空串时仍生效(selector 内建缺省
   1234567890)。
9. 通知契约(rime_api.h):deploy 进度 session_id=0、值域 start/success/failure;
   option 通知 `ascii_mode`/`!ascii_mode`;schema 通知 `id/name`。
10. traits.modules **空数组必须写 NULL**(librime 约定 NULL = 加载全部内建模块;
    非 NULL 零项数组 → 零模块 → 引擎无组件,全部 "error creating X")。

## 4. 已知缺口与后续

| 项 | 状态 | 去向 |
|---|---|---|
| `cleanupAllSessions`/`cleanupStaleSessions` | `.disabled` | 进程级破坏性操作,会连带销毁并行套件的活跃会话;remote 后端(每后端独立服务进程)下经参数化启用 |
| `removeCandidateReflowsList` | `.disabled` | 依赖用户词典语义(§3.5);夹具为确定性关闭了 user_dict |
| `finalize()` 往返 | 未测 | 进程级单例上 finalize 会毒化共享引擎;属 remote 阶段隔离环境测试 |
| property 通知(`_` 保留属性) | 未覆盖 | Squirrel 有消费场景,待后续按需补 |
| `prebuild()`/`deploy()`/`syncUserData`/`deployConfig` 成败语义 | 未测 | 同部署侧纪律(§2 纪律 3),留给 remote 阶段 |
| 夹具目录/日志 | 留在系统临时目录 | 便于失败取证(librime 日志在 `<tmp>/log`),由系统清理;另:glog 在主机名含非 ASCII 时报 "Could not create logging file",仅噪音,日志回落 stderr |

## 5. 测试驱动出的产品修复(随本设计落地)

RimeKit(Sources):

| # | 缺陷 | 修复 |
|---|---|---|
| P1 | `engineString` 对 `config_get_cstring` 返回的**借用** `const char*` 调用 `deallocate()` → malloc abort(整测试进程崩,ConfigTests 首次实证) | 去除释放,只拷贝(`RimeConfig.swift`) |
| P1 | 空组合读 `context` 即崩:`RimeMenu/RimeContext/RimeSchemaList` 对 nil 候选数组/标签数组/`select_keys`/`preedit`/`commit_text_preview` 强解包(IUO fatal) | 全部 nil 安全化,空值按空集合/空串处理(`RimeContext.swift`、`RimeSchemaList.swift`) |
| P2 | `RimeTraits` 空模块表写成非 NULL 零项数组 → 引擎零模块零组件(默认 traits 下引擎必瘫) | 空数组写 NULL,回归 librime "缺省加载全部内建模块"语义(`RimeTraits.swift`) |
| P2 | `engineClose` 不从句柄表移除已关配置 → 句柄表泄漏 + 复用句柄悬垂读取已释放 `rime_config_t` | `removeValue` 后关闭,复用抛 `invalidHandle`(与 D4 纪律一致) |
| P2 | 候选迭代器 `advance` 强解包句柄表 → 外来/陈旧句柄崩溃(§1.4 D4 残留) | 改抛 `invalidHandle(.candidateIterator)`(`RimeContext.swift`);`end` 保持幂等容忍 |

SwiftXPC(上游 `/Users/ghostflyby/repos/tests/SwiftXPC`,分支 `wire-fixes-for-rimekit-e2e`):

| # | 缺陷 | 修复 |
|---|---|---|
| P1 | `parseMethodSuffix` 不处理匿名首参的 `_` 分隔符:`selectSchema(_:for:)` 等解析成 `method()`,与 `@XPCService` 元数据键不匹配 → 白表未命中 → 每次调用 `unknownTarget` | base 名后跳过 `_`;附真实 mangling 回归测试 |
| P1 | `XPCReplyEnvelope.payload: XPCObject?` 宏解码把 "present-but-null" 折叠成 nil:`Optional.none` 返回值(如 `advance` 迭代穷尽、无 commit)客户端报 `missingPayload(.returnValue)` | 手写 envelope 编解码 + `hasPayload` 标记区分无载荷/空载荷;附往返回归测试 |
| P2 | 标识符解析无法解码 Swift 词替换压缩(`…3for0E011abbreviated2in…` 中 `0E0`="state")→ `stateLabel` 双重载键不匹配 | `lookupMetadata` 增加 base 名前缀回退(歧义重载族退化为无元数据,与宏的合并规则一致);附单元测试 |

## 6. remote 参数化路线(阶段 3 接入清单)

1. `RimeBackend.remote` 补实现:launchd 服务(borrow SwiftXPC demo bundle 模式);
   `makeRoot` 返回 `RimeServiceRoot.resolve(...)` 代理。RimeBackend 为
   `CaseIterable` 枚举,追加 case 即纳入全部 `@Test(arguments:)` 自动双跑/三跑。
2. `RimeTestEnvironment` 持有连接生命周期,补 `shutdown()`(进程内 no-op);bootstrap
   的健康探活改走 `serviceVersion()`/`healthCheck()`。
3. 解锁项:`cleanup*`/`finalize`/部署侧语义测试随隔离环境启用(§4)——它们正是
   `.disabled` 登记时预留的启用点。

## 7. 实证语义摘录(续):XPC 线缆层

双后端参数化跑通前,线缆层发现并修复/确认的事实(对阶段 3 蓝绿直接有用):

1. **`@XPCService` 元数据键 vs mangled 标识符**:匿名首参在 mangling 中拼作
   `_` 分隔符(`12selectSchema_3for`),词复用触发压缩(`0E0`="state")——
   从标识符解析方法键本质上是 demangling 问题,启发式解析必漏。已以上游
   修复 + base 前缀回退兜底;新增分布式方法后跑双后端测试即可暴露新形状。
2. **nil Optional 返回值**需要 envelope 携带 `hasPayload` 标记才能与
   `.returnVoid` 区分(上游已修)。
3. 单条 XPC 连接上的多路并发调用(libxpc 逐消息应答关联)+ 服务端根 actor
   串行,在 48 测试 × 2 形态并行压测下无串扰——SwiftXPC FIFO 语义成立。
4. RimeError typed-throws 错误跨线缆还原端到端成立(`invalidHandle` 家族
   在 `.inProcessXPC` 下断言原值通过)。
5. 80 方法全量线缆调用 + 并行套件共享单根,是 V7 编译器缺陷家族的现成
   探针:本轮调用点签名漂移(`thrown expression type 'any Error' cannot
   be converted to error type 'RimeError'`,随文件字母序布局非确定性移动)
   再次复现,规避写法为调用点套 `do throws(any Error)`。

## 附录:iOS destination 构建守护

Swift 6.3.3 的 destination JSON 为 v2 全字段 schema,以下经实测可用(`ios.json`):

```json
{
  "version": 2,
  "sdkRootDir": "<iphonesimulator SDK 路径>",
  "binDir": "<xcrun --find swift 所在目录>",
  "toolchainBinDir": "<同上>",
  "hostTriples": ["arm64-apple-macosx"],
  "targetTriples": ["arm64-apple-ios16.0-simulator"],
  "extraCCFlags": [], "extraSwiftCFlags": [], "extraCPPFlags": [],
  "extraCXXFlags": [], "extraLinkerFlags": []
}
```

`swift build --destination ios.json` → 整包(含 RimeKitRimeService)构建回绿。
