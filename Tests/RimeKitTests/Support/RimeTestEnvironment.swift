import Foundation
import Synchronization
import RimeDynamic

#if os(macOS)
import DistributedXPC
#endif

@testable import RimeKit

// MARK: - 通知日志

/// librime 全局通知回调的进程内收集器(线程安全;回调可能来自部署维护线程,§2.6)。
final class RimeNotificationLog: Sendable {
  struct Entry: Sendable, CustomStringConvertible {
    let session: RimeSessionID
    let type: RimeNotificationType
    let value: String

    var description: String { "(\(session.rawValue), \(type), \(value))" }
  }

  private let entries = Mutex<[Entry]>([])

  func append(session: RimeSessionID, type: RimeNotificationType, value: String) {
    entries.withLock { $0.append(Entry(session: session, type: type, value: value)) }
  }

  var snapshot: [Entry] { entries.withLock { $0 } }

  /// deploy 族通知的 value 集合(bootstrap 断言用;部署通知 session_id=0)。
  var deployValues: [String] {
    entries.withLock { $0.filter { $0.session.rawValue == 0 } }
      .compactMap { if case .deploy = $0.type { return $0.value } else { return nil } }
  }

  /// 轮询等待匹配项出现(通知从维护线程异步到达,测试须让渡调度)。
  func waitFor(timeout: Duration = .seconds(3), _ match: @Sendable (Entry) -> Bool) async
    -> Bool
  {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
      if entries.withLock({ $0.contains(where: match) }) { return true }
      try? await Task.sleep(for: .milliseconds(25))
    }
    return entries.withLock({ $0.contains(where: match) })
  }

  /// 重新直挂 C API,把后续通知追加进本日志(供测试在钩子被清后恢复)。
  func reinstall() {
    RimeNotificationLog.install0(log: self)
  }

  /// 直挂 librime C API 的全局通知回调并返回收集器。
  ///
  /// 根 actor 的 `engineSetNotificationHandler` 非 distributed 成员,不可经
  /// (可能是远程代理的)根引用触达;通知收集本就是进程级关注点(librime 全局
  /// 单回调,§1.3),故由测试基建在 C API 层完成——Squirrel `setupRime` 同型,
  /// 且必须先于 `initialize` 调用。C thunk 在 librime 自己的线程上同步执行,
  /// 严禁同步重入引擎(§3.7 规则 b),此处只做无锁追加。
  static func installCollector() -> RimeNotificationLog {
    let log = RimeNotificationLog()
    install0(log: log)
    return log
  }

  fileprivate static func install0(log: RimeNotificationLog) {
    final class Box {
      let log: RimeNotificationLog
      init(_ log: RimeNotificationLog) { self.log = log }
    }

    let box = Box(log)
    // 进程生命周期内存活(与 librime 回调注册同寿),有意不释放。
    let context = Unmanaged.passRetained(box).toOpaque()
    rime_get_api_stdbool().pointee.set_notification_handler(
      { context, session, type, value in
        guard let context, let type, let value else { return }
        let box = Unmanaged<Box>.fromOpaque(context).takeUnretainedValue()
        box.log.append(
          session: RimeSessionID(rawValue: UInt(session)),
          type: RimeNotificationType(from: String(cString: type)),
          value: String(cString: value))
      }, context)
  }
}

// MARK: - 进程级运行时(唯一根 + 部署产物)

/// 进程级共享运行时:唯一的根 actor(进程内 XPC 连接对的服务端根)+ 已部署的
/// 夹具数据 + 通知流水。全部后端的调用都收敛到这一个执行域(§3.7)。
///
/// librime 是进程级单例,setup/initialize/deploy 每测试进程至多执行一次
/// (对应 librime gtest 的 `rime_test_main.cc` Environment;Squirrel 的
/// `setupRime` + `startRime` 流程)。
final class RimeTestRuntime: Sendable {
  /// 夹具数据目录(同时是 traits 的 shared/user data dir;生命周期测试断言目录回读)。
  let userDirectory: URL
  /// 自 bootstrap 注册起的全局通知流水(部署/选项/方案切换断言的数据源)。
  let notifications: RimeNotificationLog
  /// 唯一根 actor 实例:诞生于连接对服务端,`inProcess` 后端持其本地引用。
  let root: RimeServiceRoot
  #if os(macOS)
  /// 进程内连接对(`inProcessXPC` 后端的线缆通道);持有全部连接的生命周期。
  let wirePair: RimeXPCWirePair?
  #endif

  private init(
    userDirectory: URL, notifications: RimeNotificationLog, root: RimeServiceRoot
  ) {
    self.userDirectory = userDirectory
    self.notifications = notifications
    self.root = root
    #if os(macOS)
    self.wirePair = nil
    #endif
  }

  #if os(macOS)
  private init(
    userDirectory: URL, notifications: RimeNotificationLog, root: RimeServiceRoot,
    wirePair: RimeXPCWirePair
  ) {
    self.userDirectory = userDirectory
    self.notifications = notifications
    self.root = root
    self.wirePair = wirePair
  }
  #endif

  /// 部署一次:Squirrel 形态的初始化序列(setup → 通知回调 → initialize →
  /// start_maintenance(fullCheck) → join),随后探活方案就绪。
  /// `joinMaintenanceThread` 阻塞执行域秒级——§3.8 I4 只约束服务路径,测试进程可接受。
  fileprivate static func deploy() async throws -> RimeTestRuntime {
    let baseDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("rimekit-tests-\(UUID().uuidString)", isDirectory: true)
    let userDirectory = baseDirectory.appendingPathComponent("user", isDirectory: true)
    let logDirectory = baseDirectory.appendingPathComponent("log", isDirectory: true)
    try FileManager.default.createDirectory(at: userDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    try MinimalRimeData.write(into: userDirectory)
    // 夹具目录留在系统临时目录便于失败取证(librime 日志在 log/ 下),由系统清理。

    // 根 actor 诞生于进程内 XPC 连接对的服务端(单一执行域,双后端共享;
    // 写法复制自 SwiftXPC DistributedXPCIntegrationTests.makeConnectionPair)。
    #if os(macOS)
    let wirePair = try RimeXPCWirePair.make()
    let root = wirePair.servedRoot
    #else
    let root = RimeServiceRoot(actorSystem: RimeLocalSystem())
    #endif
    let notifications = RimeNotificationLog.installCollector()

    var traits = RimeTraits(
      sharedDataDir: userDirectory.path,
      userDataDir: userDirectory.path,
      distributionName: "RimeKit",
      distributionCodeName: "dev.rimekit",
      distributionVersion: "0.1",
      appName: "RimeKitTests",
      minLogLevel: .warning)
    traits.logDir = logDirectory.path

    try await root.setup(with: traits)
    try await root.initialize(with: traits)
    let maintenanceStarted = try await root.startMaintenance(fullCheck: true)
    try await root.joinMaintenanceThread()

    let schemaIDs = (try? await root.schemaList().items.map(\.schemaID)) ?? []
    func diagnose(_ stage: String) -> RimeTestFailure {
      RimeTestFailure(
        stage: stage,
        detail: """
          maintenanceStarted=\(maintenanceStarted); \
          deploy通知=\(notifications.deployValues); \
          全部通知=\(notifications.snapshot); \
          方案表=\(schemaIDs); \
          夹具目录=\(baseDirectory.path)
          """)
    }

    guard maintenanceStarted else { throw diagnose("startMaintenance") }
    guard notifications.deployValues.contains("success"),
      !notifications.deployValues.contains("failure")
    else { throw diagnose("deploy") }

    // 探活:会话可用且默认方案就位(部署失败的典型表现是 createSession==0 或方案缺失)。
    let probe = try await root.createSession()
    guard probe.rawValue != 0 else { throw diagnose("createSession") }
    let currentSchema = try await root.currentSchema(for: probe)
    guard currentSchema == MinimalRimeData.primarySchemaID else {
      _ = try? await root.destroySession(with: probe)
      throw RimeTestFailure(
        stage: "probe",
        detail: "当前方案 \(String(describing: currentSchema)) ≠ \(MinimalRimeData.primarySchemaID);"
          + diagnose("").detail)
    }
    _ = try await root.destroySession(with: probe)

    #if os(macOS)
    return RimeTestRuntime(
      userDirectory: userDirectory, notifications: notifications, root: root,
      wirePair: wirePair)
    #else
    return RimeTestRuntime(
      userDirectory: userDirectory, notifications: notifications, root: root)
    #endif
  }
}

// MARK: - 已部署测试环境(按后端取用)

/// 单个后端的测试环境:被测根引用(`runtime.root` 的本地引用,或经连接对
/// `resolve(id: .root)` 的线缆代理)+ 共享的部署产物。
///
/// 各测试套件的接法(函数级参数化;工具链 Swift Testing 暂无 `@Suite(arguments:)`):
///
///     @Suite struct TypingTests {
///       @Test(arguments: RimeBackend.allCases)
///       func typedKeys…(backend: RimeBackend) async throws {
///         let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
///         …
///       }
///     }
final class RimeTestEnvironment: Sendable {
  /// 本环境对应的引用形态。
  let backend: RimeBackend
  /// 被测根引用:`.inProcess` = 服务端根的本地引用;`.inProcessXPC` = 线缆代理。
  let root: RimeServiceRoot
  fileprivate let runtime: RimeTestRuntime

  var userDirectory: URL { runtime.userDirectory }
  var notifications: RimeNotificationLog { runtime.notifications }

  fileprivate init(backend: RimeBackend, runtime: RimeTestRuntime, root: RimeServiceRoot) {
    self.backend = backend
    self.runtime = runtime
    self.root = root
  }

  /// 新建输入会话(门面;deinit 异步销毁,不参与时序敏感断言,§1.4 D5)。
  func makeSession() async throws -> RimeSession {
    try await RimeSession(root: root)
  }

  /// 重新把全局 C 钩子指向本环境的通知日志。
  /// 订阅测试 `detach` 会清掉进程级 handler(macOS 路径 `setNotificationSink(nil)`),
  /// 并行套件的通知断言依赖本收集器,须即时恢复。
  func reinstallNotificationCollector() {
    notifications.reinstall()
  }

  // MARK: bootstrap(运行时单次部署 + 按后端缓存环境)

  private static let bootstrap = RimeBootstrap()

  static func bootstrapped(backend: RimeBackend) async throws -> RimeTestEnvironment {
    try await bootstrap.environment(backend: backend)
  }
}

/// bootstrap 备忘:运行时(部署 + 连接对)进程内单次;环境按后端缓存。
/// 失败后允许下次调用重试。
private actor RimeBootstrap {
  private var runtimeTask: Task<RimeTestRuntime, any Error>?
  private var environments: [RimeBackend: RimeTestEnvironment] = [:]

  func environment(backend: RimeBackend) async throws -> RimeTestEnvironment {
    if let cached = environments[backend] { return cached }

    let runtime: RimeTestRuntime
    if let runtimeTask {
      runtime = try await runtimeTask.value
    } else {
      let deployed = Task { try await RimeTestRuntime.deploy() }
      runtimeTask = deployed
      do {
        runtime = try await deployed.value
      } catch {
        runtimeTask = nil
        throw error
      }
    }

    let root: RimeServiceRoot
    switch backend {
    case .inProcess:
      root = runtime.root
    #if os(macOS)
    case .inProcessXPC:
      guard let pair = runtime.wirePair else {
        throw RimeTestFailure(stage: "backend", detail: "运行时缺少进程内 XPC 连接对")
      }
      root = try pair.resolveProxy()
    #endif
    }

    let environment = RimeTestEnvironment(backend: backend, runtime: runtime, root: root)
    environments[backend] = environment
    return environment
  }
}
