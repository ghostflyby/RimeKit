import Distributed

#if (os(macOS))
  import DistributedXPC
#endif

/// librime 的 XPC 服务根 actor(§4.2)。
///
/// - 客户端经 `RimeServiceRoot.resolve(id:using:)` 取得远程代理,或在本进程内
///   `init(actorSystem:)` 构造本地实例——四种形态(本地/远程/蓝/绿)调用点同构。
/// - 签名与重塑后的 `Rime` 协议要求 1:1 镜像(协议属性在此展开为 getter 方法);
///   **不 conform `Rime`**(§3.4 F3:typed throws 见证触发编译器 IRGen 崩溃)。
/// - 全部方法**显式标注 `async`**:语义上与隐式等价(分布式方法天然异步),
///   但绕开 Swift 6.3.3 类型检查器在方法数 >~10 时丢失隐式 async 的缺陷(V7)。
/// - 实现体全部一行委托 `RimeEngine.shared`:librime 调用的唯一串行执行域(§3.7)。
public distributed actor RimeServiceRoot: XPCRootActor {
  public typealias ActorSystem = XPCDistributedActorSystem

  private var notificationSink: RimeNotificationSink?

  /// 委托目标:经协议的 async 要求调用(分布式方法体的同步隔离上下文
  /// 不能直接调用另一 actor 的同步成员,经 `any Rime` 走见证 thunk)。
  private let engine = RimeEngine.shared

  public init(actorSystem: ActorSystem) {
    self.actorSystem = actorSystem
  }

  // MARK: 运维面(不进 `Rime` 协议)

  public distributed func serviceVersion() async throws(RimeError) -> String {
    "rimekit/" + (try engine.version)
  }

  public distributed func healthCheck() async throws(RimeError) -> Bool {
    true
  }

  public distributed func setNotificationSink(_ sink: RimeNotificationSink?) async throws(RimeError)
  {
    notificationSink = sink
    if let sink {
      engine.setNotificationHandler { session, type, value in
        Task { try? await sink.emit(session, type, value) }
      }
    } else {
      engine.notificationHandler = nil
    }
  }

  // MARK: 生命周期

  public distributed func setup(with traits: RimeTraits) async throws(RimeError) {
    try engine.setup(with: traits)
  }

  public distributed func initialize(with traits: RimeTraits) async throws(RimeError) {
    try engine.initialize(with: traits)
  }

  public distributed func finalize() async throws(RimeError) {
    try engine.finalize()
  }

  // MARK: 维护

  public distributed func startMaintenance(fullCheck: Bool) async throws(RimeError) -> Bool {
    try engine.startMaintenance(fullCheck: fullCheck)
  }

  public distributed func isMaintenanceMode() async throws(RimeError) -> Bool {
    try engine.isMaintenanceMode
  }

  public distributed func joinMaintenanceThread() async throws(RimeError) {
    try engine.joinMaintenanceThread()
  }

  // MARK: Deployer

  public distributed func initializeDeployer(with traits: RimeTraits) async throws(RimeError) {
    try engine.initializeDeployer(with: traits)
  }

  public distributed func prebuild() async throws(RimeError) -> Bool {
    try engine.prebuild()
  }

  public distributed func deploy() async throws(RimeError) -> Bool {
    try engine.deploy()
  }

  public distributed func deploySchema(withID schemaID: String) async throws(RimeError) -> Bool {
    try engine.deploySchema(withID: schemaID)
  }

  public distributed func deployConfig(filename: String, versionKey: String) async throws(RimeError)
    -> Bool
  {
    try engine.deployConfig(filename: filename, versionKey: versionKey)
  }

  public distributed func syncUserData() async throws(RimeError) -> Bool {
    try engine.syncUserData()
  }

  // MARK: 会话

  public distributed func createSession() async throws(RimeError) -> RimeSessionID {
    try engine.createSession()
  }

  public distributed func findSession(with sessionID: RimeSessionID) async throws(RimeError) -> Bool
  {
    try engine.findSession(with: sessionID)
  }

  public distributed func destroySession(with sessionID: RimeSessionID) async throws(RimeError)
    -> Bool
  {
    try engine.destroySession(with: sessionID)
  }

  public distributed func cleanupStaleSessions() async throws(RimeError) {
    try engine.cleanupStaleSessions()
  }

  public distributed func cleanupAllSessions() async throws(RimeError) {
    try engine.cleanupAllSessions()
  }

  // MARK: 按键

  public distributed func processKey(
    keyCode: Int32, modifierMask: Int32, for sessionID: RimeSessionID
  ) async throws -> Bool {
    try engine.processKey(keyCode: keyCode, modifierMask: modifierMask, for: sessionID)
  }

  public distributed func commitComposition(for sessionID: RimeSessionID) async throws(RimeError)
    -> Bool
  {
    try engine.commitComposition(for: sessionID)
  }

  public distributed func clearComposition(for sessionID: RimeSessionID) async throws(RimeError) {
    try engine.clearComposition(for: sessionID)
  }

  // MARK: 输出

  public distributed func commit(for sessionID: RimeSessionID) async throws(RimeError)
    -> RimeCommit?
  {
    try engine.commit(for: sessionID)
  }

  public distributed func status(for sessionID: RimeSessionID) async throws(RimeError)
    -> RimeStatus?
  {
    try engine.status(for: sessionID)
  }

  public distributed func context(for sessionID: RimeSessionID) async throws(RimeError)
    -> RimeContext?
  {
    try engine.context(for: sessionID)
  }

  // MARK: 选项 / 属性

  public distributed func option(named option: String, for sessionID: RimeSessionID)
    async throws(RimeError) -> Bool
  {
    try engine.option(named: option, for: sessionID)
  }

  public distributed func setOption(_ option: String, value: Bool, for sessionID: RimeSessionID)
    async throws(RimeError)
  {
    try engine.setOption(option, value: value, for: sessionID)
  }

  public distributed func property(named property: String, for sessionID: RimeSessionID)
    async throws(RimeError) -> String?
  {
    try engine.property(named: property, for: sessionID)
  }

  public distributed func setProperty(
    _ property: String, value: String, for sessionID: RimeSessionID
  ) async throws(RimeError) {
    try engine.setProperty(property, value: value, for: sessionID)
  }

  // MARK: Schema

  public distributed func schemaList() async throws(RimeError) -> RimeSchemaList {
    try engine.schemaList
  }

  public distributed func currentSchema(for sessionID: RimeSessionID) async throws(RimeError)
    -> String?
  {
    try engine.currentSchema(for: sessionID)
  }

  public distributed func selectSchema(_ schemaID: String, for sessionID: RimeSessionID)
    async throws(RimeError) -> Bool
  {
    try engine.selectSchema(schemaID, for: sessionID)
  }

  // MARK: 配置打开

  public distributed func openSchema(_ schemaID: String) async throws(RimeError) -> ObjectHandle<
    RimeConfig
  >? {
    try engine.openSchema(schemaID)
  }

  public distributed func openConfig(_ configID: String) async throws(RimeError) -> ObjectHandle<
    RimeConfig
  >? {
    try engine.openConfig(configID)
  }

  public distributed func close(config: ObjectHandle<RimeConfig>) async throws(RimeError) -> Bool {
    try engine.close(config: config)
  }

  // MARK: 配置读写

  public distributed func string(forKey key: String, in config: ObjectHandle<RimeConfig>)
    async throws(RimeError) -> String?
  {
    try engine.string(forKey: key, in: config)
  }

  public distributed func int(forKey key: String, in config: ObjectHandle<RimeConfig>)
    async throws(RimeError) -> Int32?
  {
    try engine.int(forKey: key, in: config)
  }

  public distributed func bool(forKey key: String, in config: ObjectHandle<RimeConfig>)
    async throws(RimeError) -> Bool?
  {
    try engine.bool(forKey: key, in: config)
  }

  public distributed func double(forKey key: String, in config: ObjectHandle<RimeConfig>)
    async throws(RimeError) -> Double?
  {
    try engine.double(forKey: key, in: config)
  }

  public distributed func item(forKey key: String, in config: ObjectHandle<RimeConfig>)
    async throws(RimeError) -> ObjectHandle<RimeConfig>?
  {
    try engine.item(forKey: key, in: config)
  }

  public distributed func set(
    _ value: String, forKey key: String, in config: ObjectHandle<RimeConfig>
  ) async throws(RimeError) -> Bool {
    try engine.set(value, forKey: key, in: config)
  }

  public distributed func set(
    _ value: Int32, forKey key: String, in config: ObjectHandle<RimeConfig>
  ) async throws(RimeError) -> Bool {
    try engine.set(value, forKey: key, in: config)
  }

  public distributed func set(
    _ value: Bool, forKey key: String, in config: ObjectHandle<RimeConfig>
  ) async throws(RimeError) -> Bool {
    try engine.set(value, forKey: key, in: config)
  }

  public distributed func set(
    _ value: Double, forKey key: String, in config: ObjectHandle<RimeConfig>
  ) async throws(RimeError) -> Bool {
    try engine.set(value, forKey: key, in: config)
  }

  public distributed func set(
    _ value: ObjectHandle<RimeConfig>, forKey key: String, in config: ObjectHandle<RimeConfig>
  ) async throws(RimeError) -> Bool {
    try engine.set(value, forKey: key, in: config)
  }

  public distributed func removeValue(forKey key: String, in config: ObjectHandle<RimeConfig>)
    async throws(RimeError) -> Bool
  {
    try engine.removeValue(forKey: key, in: config)
  }

  public distributed func update(signature: String, for config: ObjectHandle<RimeConfig>)
    async throws(RimeError) -> Bool
  {
    try engine.update(signature: signature, for: config)
  }

  public distributed func beginMap(forKey key: String, in config: ObjectHandle<RimeConfig>)
    async throws(RimeError) -> ObjectHandle<RimeConfigIterator>
  {
    try engine.beginMap(forKey: key, in: config)
  }

  public distributed func beginList(forKey key: String, in config: ObjectHandle<RimeConfig>)
    async throws(RimeError) -> ObjectHandle<RimeConfigIterator>
  {
    try engine.beginList(forKey: key, in: config)
  }

  public distributed func advanceConfigIterator(_ iterator: ObjectHandle<RimeConfigIterator>)
    async throws(RimeError) -> RimeConfigLocation?
  {
    try engine.advanceConfigIterator(iterator)
  }

  public distributed func endConfigIterator(_ iterator: ObjectHandle<RimeConfigIterator>)
    async throws(RimeError)
  {
    try engine.endConfigIterator(iterator)
  }

  public distributed func makeConfig() async throws(RimeError) -> ObjectHandle<RimeConfig> {
    try engine.makeConfig()
  }

  public distributed func load(yaml: String, into config: ObjectHandle<RimeConfig>)
    async throws(RimeError) -> Bool
  {
    try engine.load(yaml: yaml, into: config)
  }

  public distributed func createList(forKey key: String, in config: ObjectHandle<RimeConfig>)
    async throws(RimeError) -> Bool
  {
    try engine.createList(forKey: key, in: config)
  }

  public distributed func createMap(forKey key: String, in config: ObjectHandle<RimeConfig>)
    async throws(RimeError) -> Bool
  {
    try engine.createMap(forKey: key, in: config)
  }

  public distributed func listSize(forKey key: String, in config: ObjectHandle<RimeConfig>)
    async throws(RimeError) -> Int
  {
    try engine.listSize(forKey: key, in: config)
  }

  // MARK: 身份 / 目录

  public distributed func userID() async throws(RimeError) -> String {
    try engine.userID
  }

  public distributed func userDataSyncDirectory() async throws(RimeError) -> String {
    try engine.userDataSyncDirectory
  }

  // MARK: 输入 / 光标

  public distributed func input(for sessionID: RimeSessionID) async throws(RimeError) -> String? {
    try engine.input(for: sessionID)
  }

  public distributed func set(input: String, for sessionID: RimeSessionID) async throws(RimeError)
    -> Bool
  {
    try engine.set(input: input, for: sessionID)
  }

  public distributed func caretPosition(for sessionID: RimeSessionID) async throws(RimeError) -> Int
  {
    try engine.caretPosition(for: sessionID)
  }

  public distributed func set(caretPosition: Int, for sessionID: RimeSessionID)
    async throws(RimeError)
  {
    try engine.set(caretPosition: caretPosition, for: sessionID)
  }

  // MARK: 版本

  public distributed func version() async throws(RimeError) -> String {
    try engine.version
  }

  // MARK: 候选(页式)

  public distributed func selectCandidate(at index: Int, for session: RimeSessionID)
    async throws(RimeError) -> Bool
  {
    try engine.selectCandidate(at: index, for: session)
  }

  public distributed func selectCandidateOnCurrentPage(at index: Int, for session: RimeSessionID)
    async throws(RimeError) -> Bool
  {
    try engine.selectCandidateOnCurrentPage(at: index, for: session)
  }

  // MARK: 候选(句柄式)

  public distributed func beginCandidates(for session: RimeSessionID) async throws(RimeError)
    -> ObjectHandle<RimeCandidate>
  {
    try engine.beginCandidates(for: session)
  }

  public distributed func advanceCandidateIterator(_ iterator: ObjectHandle<RimeCandidate>)
    async throws(RimeError) -> RimeCandidate?
  {
    try engine.advanceCandidateIterator(iterator)
  }

  public distributed func endCandidateIterator(_ iterator: ObjectHandle<RimeCandidate>)
    async throws(RimeError)
  {
    try engine.endCandidateIterator(iterator)
  }

  public distributed func openUserConfig(configId: String) async throws(RimeError) -> ObjectHandle<
    RimeConfig
  >? {
    try engine.openUserConfig(configId: configId)
  }

  public distributed func candidateList(fromIndex: Int32, for sessionID: RimeSessionID)
    async throws(RimeError) -> ObjectHandle<RimeCandidate>?
  {
    try engine.candidateList(fromIndex: fromIndex, for: sessionID)
  }

  // MARK: 状态标签

  public distributed func stateLabel(for key: String, state: RimeState, in session: RimeSessionID)
    async throws(RimeError) -> String?
  {
    try engine.stateLabel(for: key, state: state, in: session)
  }

  public distributed func stateLabel(
    for key: String, state: RimeState, abbreviated: Bool, in session: RimeSessionID
  ) async throws(RimeError) -> String? {
    try engine.stateLabel(for: key, state: state, abbreviated: abbreviated, in: session)
  }

  // MARK: 候选编辑 / 翻页

  public distributed func removeCandidate(at index: Int, for session: RimeSessionID)
    async throws(RimeError) -> Bool
  {
    try engine.removeCandidate(at: index, for: session)
  }

  public distributed func removeCandidateOnCurrentPage(at index: Int, for session: RimeSessionID)
    async throws(RimeError) -> Bool
  {
    try engine.removeCandidateOnCurrentPage(at: index, for: session)
  }

  public distributed func highlightCandidate(at index: Int, for session: RimeSessionID)
    async throws(RimeError) -> Bool
  {
    try engine.highlightCandidate(at: index, for: session)
  }

  public distributed func highlightCandidateOnCurrentPage(at index: Int, for session: RimeSessionID)
    async throws(RimeError) -> Bool
  {
    try engine.highlightCandidateOnCurrentPage(at: index, for: session)
  }

  public distributed func page(_ direction: RimePageDirection, for session: RimeSessionID)
    async throws(RimeError) -> Bool
  {
    try engine.page(direction, for: session)
  }

  // MARK: 目录

  public distributed func sharedDataDirectory() async throws(RimeError) -> String {
    try engine.sharedDataDirectory
  }

  public distributed func userDataDirectory() async throws(RimeError) -> String {
    try engine.userDataDirectory
  }

  public distributed func prebuiltDataDirectory() async throws(RimeError) -> String {
    try engine.prebuiltDataDirectory
  }

  public distributed func stagingDirectory() async throws(RimeError) -> String {
    try engine.stagingDirectory
  }

  public distributed func syncDirectory() async throws(RimeError) -> String {
    try engine.syncDirectory
  }
}
