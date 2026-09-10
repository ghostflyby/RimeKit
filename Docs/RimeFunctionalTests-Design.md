# RimeKit 功能测试设计(swift test × Swift Testing)

- 状态:交付稿(测试基建 + 七个功能套件全绿;iOS destination 构建守护回绿)
- 日期:2026-09-10
- 依赖基线:librime-xcframework 1.16.1-pack.8;Swift 6.3.3 工具链内置 Swift Testing
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

### 1.1 注入接缝(多实例预留)

测试体只面向 `RimeTestEnvironment.bootstrapped()` 给出的环境(根引用 + 数据目录 +
通知日志),对"根是进程内实例还是远程代理"零感知——对应蓝绿方案"四种形态调用点同构"。

- `RimeBackend.inProcess`:直通 `RimeServiceRoot.localShared`。librime 是进程级单例
  (§0),进程内**不**按套件多实例化根——并行套件若各持根实例,即绕过唯一串行执行域
  (§3.7),对 librime 形成数据竞争(§2.6)。"多实例"语义由 remote 后端承载:每环境
  一条连接,每个服务进程内恰一个引擎(§1.3 同构)。
- `RimeBackend.remote`(阶段 3 预留,注释内含接线草图):XPC resolve 根代理。
- 后端选择:`RIMEKIT_TEST_BACKEND` 环境变量(缺省 `inProcess`)。工具链 Swift Testing
  尚无 `@Suite(arguments:)`(6.3.3 探针实证),remote 参数化以 CI 矩阵逐后端跑同一批
  套件实现;待上游支持参数化套件后可平移为 `@Suite(arguments:)`。
- 会话等高层门面经 `env.makeSession()`(internal `RimeSession(root:)`)注入根,不用
  绑死 `localShared` 的公开 `init()`。

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

| # | 缺陷 | 修复 |
|---|---|---|
| P1 | `engineString` 对 `config_get_cstring` 返回的**借用** `const char*` 调用 `deallocate()` → malloc abort(整测试进程崩,ConfigTests 首次实证) | 去除释放,只拷贝(`RimeConfig.swift`) |
| P1 | 空组合读 `context` 即崩:`RimeMenu/RimeContext/RimeSchemaList` 对 nil 候选数组/标签数组/`select_keys`/`preedit`/`commit_text_preview` 强解包(IUO fatal) | 全部 nil 安全化,空值按空集合/空串处理(`RimeContext.swift`、`RimeSchemaList.swift`) |
| P2 | `RimeTraits` 空模块表写成非 NULL 零项数组 → 引擎零模块零组件(默认 traits 下引擎必瘫) | 空数组写 NULL,回归 librime "缺省加载全部内建模块"语义(`RimeTraits.swift`) |
| P2 | `engineClose` 不从句柄表移除已关配置 → 句柄表泄漏 + 复用句柄悬垂读取已释放 `rime_config_t` | `removeValue` 后关闭,复用抛 `invalidHandle`(与 D4 纪律一致) |
| P2 | 候选迭代器 `advance` 强解包句柄表 → 外来/陈旧句柄崩溃(§1.4 D4 残留) | 改抛 `invalidHandle(.candidateIterator)`(`RimeContext.swift`);`end` 保持幂等容忍 |

## 6. remote 参数化路线(阶段 3 接入清单)

1. `RimeBackend.remote` 补实现:launchd 服务(borrow SwiftXPC demo bundle 模式)或
   进程内 connection pair;`makeRoot` 返回 `RimeServiceRoot.resolve(...)` 代理。
2. `RimeTestEnvironment` 持有连接生命周期,补 `shutdown()`(进程内 no-op);bootstrap
   的健康探活改走 `serviceVersion()`/`healthCheck()`。
3. CI 矩阵:同一批套件在 `RIMEKIT_TEST_BACKEND=inProcess|remote` 下各跑一遍;
   工具链支持 `@Suite(arguments:)` 后可改为进程内参数化。
4. 解锁项:`cleanup*`/`finalize`/部署侧语义测试随隔离环境启用(§4)。

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
