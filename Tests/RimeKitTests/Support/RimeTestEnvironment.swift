import Foundation
import Synchronization
import RimeDynamic

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

  /// 直挂 librime C API 的全局通知回调并返回收集器。
  ///
  /// 根 actor 的 `engineSetNotificationHandler` 非 distributed 成员,不可经
  /// (可能是远程代理的)根引用触达;通知收集本就是进程级关注点(librime 全局
  /// 单回调,§1.3),故由测试基建在 C API 层完成——Squirrel `setupRime` 同型,
  /// 且必须先于 `initialize` 调用。C thunk 在 librime 自己的线程上同步执行,
  /// 严禁同步重入引擎(§3.7 规则 b),此处只做无锁追加。
  static func installCollector() -> RimeNotificationLog {
    final class Box {
      let log: RimeNotificationLog
      init(_ log: RimeNotificationLog) { self.log = log }
    }

    let log = RimeNotificationLog()
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
    return log
  }
}

// MARK: - 已部署测试环境

/// 进程级共享的已部署环境:根 actor 引用 + 夹具数据目录 + 通知日志。
///
/// librime 是进程级单例,setup/initialize/deploy 每测试进程至多执行一次
/// (对应 librime gtest 的 `rime_test_main.cc` Environment;Squirrel 的
/// `setupRime` + `startRime` 流程)。各套件经 `bootstrapped()` 共享同一环境,
/// 并发套件的全部引擎调用天然串行于唯一根 actor(§3.7)。
///
/// 各测试套件的接法(未来 remote 化时保持不变):
///
///     @Suite struct TypingTests {
///       let env: RimeTestEnvironment
///       init() async throws { env = try await RimeTestEnvironment.bootstrapped() }
///       @Test func …() async throws { let s = try await env.makeSession() … }
///     }
final class RimeTestEnvironment: Sendable {
  /// 选择的后端名(诊断用)。
  let backendName: String
  /// 夹具数据目录(同时是 traits 的 shared/user data dir;生命周期测试断言目录回读)。
  let userDirectory: URL
  /// 引擎根引用:进程内即 `localShared`,remote 化后为连接的根代理。
  let root: RimeServiceRoot
  /// 自 bootstrap 注册起的全局通知流水(部署/选项/方案切换断言的数据源)。
  let notifications: RimeNotificationLog

  private init(
    backendName: String, userDirectory: URL, root: RimeServiceRoot,
    notifications: RimeNotificationLog
  ) {
    self.backendName = backendName
    self.userDirectory = userDirectory
    self.root = root
    self.notifications = notifications
  }

  /// 新建输入会话(门面;deinit 异步销毁,不参与时序敏感断言,§1.4 D5)。
  func makeSession() async throws -> RimeSession {
    try await RimeSession(root: root)
  }

  // MARK: bootstrap(进程内单次)

  private static let bootstrap = RimeBootstrap()

  static func bootstrapped() async throws -> RimeTestEnvironment {
    try await bootstrap.environment(backend: .current)
  }

  /// 部署一次:Squirrel 形态的初始化序列(setup → 通知回调 → initialize →
  /// start_maintenance(fullCheck) → join),随后探活方案就绪。
  /// `joinMaintenanceThread` 阻塞执行域秒级——§3.8 I4 只约束服务路径,测试进程可接受。
  fileprivate static func deploy(backend: RimeBackend) async throws -> RimeTestEnvironment {
    let baseDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("rimekit-tests-\(UUID().uuidString)", isDirectory: true)
    let userDirectory = baseDirectory.appendingPathComponent("user", isDirectory: true)
    let logDirectory = baseDirectory.appendingPathComponent("log", isDirectory: true)
    try FileManager.default.createDirectory(at: userDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    try MinimalRimeData.write(into: userDirectory)
    // 夹具目录留在系统临时目录便于失败取证(librime 日志在 log/ 下),由系统清理。

    let root = try await backend.makeRoot()
    let notifications = RimeNotificationLog.installCollector()
    let environment = RimeTestEnvironment(
      backendName: backend.name, userDirectory: userDirectory, root: root,
      notifications: notifications)

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

    return environment
  }
}

/// bootstrap 备忘:并发套件共享同一次部署;失败后允许下次调用重试。
private actor RimeBootstrap {
  private var task: Task<RimeTestEnvironment, any Error>?

  func environment(backend: RimeBackend) async throws -> RimeTestEnvironment {
    if let task { return try await task.value }
    let deployed = Task { try await RimeTestEnvironment.deploy(backend: backend) }
    task = deployed
    do {
      return try await deployed.value
    } catch {
      task = nil
      throw error
    }
  }
}
