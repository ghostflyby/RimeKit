// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Distributed
import Foundation
import RimeDynamic

#if os(macOS)
  import DistributedXPC
#endif

/// librime 的 XPC 服务根 actor(§4.2)。
///
/// - 客户端经 `Rime.resolve(id:using:)` 取得远程代理,或在本进程内
///   `init(actorSystem:)` 构造本地实例——四种形态(本地/远程/蓝/绿)调用点同构。
/// - 签名与重塑后的 `Rime` 协议要求 1:1 镜像(协议属性在此展开为 getter 方法);
///   **不 conform `Rime`**(§3.4 F3:typed throws 见证触发编译器 IRGen 崩溃)。
/// - 全部方法**显式标注 `async`**:语义上与隐式等价(分布式方法天然异步),
///   但绕开 Swift 6.3.3 类型检查器在方法数 >~10 时丢失隐式 async 的缺陷(V7)。
/// - 实现体全部一行直调本 actor 的 internal `engine*` 成员:librime 调用的唯一串行执行域(§3.7)。
@available(macOS 15, iOS 16, *)
#if os(macOS)
  @XPCService
#endif
public distributed actor Rime {

  #if os(macOS)
    public typealias ActorSystem = XPCDistributedActorSystem
  #else
    public typealias ActorSystem = RimeLocalSystem
  #endif

  private var notificationSink: RimeNotificationSink?

  /// 串行化不变式(§3.7):每进程恰有一个本地共享实例;
  /// XPC 服务进程由 shouldAccept 单 peer 策略保证。
  #if os(macOS)
    internal static let localShared = Rime(
      actorSystem: XPCDistributedActorSystem(connection: XPCConnection(name: nil)))
  #else
    internal static let localShared = Rime(actorSystem: RimeLocalSystem())
  #endif

  internal let rimeApi: RimeApi_stdbool
  internal var opaque: Box?
  internal static let cStringBufferSize = 1024
  internal let cStringBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: cStringBufferSize)
  internal var configs: [ObjectHandle<RimeConfig>: rime_config_t] = [:]
  internal var configIterators: [ObjectHandle<RimeConfigIterator>: rime_config_iterator_t] = [:]
  internal var candidateIterators: [ObjectHandle<RimeCandidate>: rime_candidate_list_iterator_t] =
    [:]

  public init(actorSystem: ActorSystem) {
    self.actorSystem = actorSystem
    self.rimeApi = rime_get_api_stdbool().pointee
  }

  // MARK: 运维面(不进 `Rime` 协议)

  public distributed func serviceVersion() async throws(RimeError) -> String {
    "rimekit/" + (try await version())
  }

  public distributed func healthCheck() async throws(RimeError) -> Bool {
    true
  }

  /// 订阅通知(内部实现,经 `setNotificationHandler` 间接使用)。
  /// **声明不得包 `#if`**:否则 `@XPCService` 宏枚举不到,元数据白表缺失,
  /// 线缆调用即 unknownTarget(实证)。
  distributed func setNotificationSink(_ sink: RimeNotificationSink?) async throws(RimeError) {
    notificationSink = sink
    if let sink {
      engineSetNotificationHandler { session, type, value in
        Task { try? await sink.emit(session, type, value) }
      }
    } else {
      engineNotificationHandler = nil
    }
  }

  // MARK: 蓝绿生命周期(宿主切换协议)

  /// 注意:与全部线缆方法一样,声明必须位于主定义文件内且不得包 `#if`——
  /// `@XPCService` 宏在编译期枚举成员生成元数据白表,声明在别的文件扩展里
  /// 或包进条件编译都会从白表缺失,线缆调用即 unknownTarget(实证)。

  /// 返回服务进程 pid。宿主蓝绿切换协议:shutdown 前记下 pid,shutdown 后
  /// 轮询其消失,以确认 userdb 锁已释放。
  public distributed func servicePid() async throws(RimeError) -> pid_t {
    pid_t(getpid())
  }

  /// 请求服务进程干净退出(蓝绿切换协议:宿主应先 syncUserData 落盘)。
  ///
  /// RPC 应答可能随进程终止而失败,调用方应容忍错误并以 servicePid 消失
  /// 为完成标志。exit(0) 不运行 librime 级清理,但 leveldb WAL 保证重开
  /// 一致性。
  public distributed func shutdown() async throws(RimeError) {
    // SwiftXPC 0.6 协作式关闭:拆除全部 peer → serviceWillShutdown 钩子 →
    // 宿主 xpcMain 预置的 shutdownCompletion(exit(0))完成进程退役。客户端
    // 应答随连接拆除而中断,以 pid 消失为完成标志。
    // iOS 本地系统无服务进程语义,关闭为空操作;声明保持裸露(白表按成员枚举)。
    #if os(macOS)
      actorSystem.requestServiceShutdown()
    #endif
  }

  // MARK: 生命周期

  public distributed func setup(with traits: RimeTraits) async throws(RimeError) {
    var t = rime_traits_t.rimeStructInit()
    let handle = traits.toCStructure(&t)
    rimeApi.setup(&t)
    withExtendedLifetime(handle) {}
  }

  public distributed func initialize(with traits: RimeTraits) async throws(RimeError) {
    var t = rime_traits_t.rimeStructInit()
    let handle = traits.toCStructure(&t)
    rimeApi.initialize(&t)
    withExtendedLifetime(handle) {}
  }

  public distributed func finalize() async throws(RimeError) {
    rimeApi.finalize()
  }

  // MARK: 维护

  public distributed func startMaintenance(fullCheck: Bool) async throws(RimeError) -> Bool {
    rimeApi.start_maintenance(fullCheck)
  }

  public distributed func isMaintenanceMode() async throws(RimeError) -> Bool {
    rimeApi.is_maintenance_mode()
  }

  public distributed func joinMaintenanceThread() async throws(RimeError) {
    rimeApi.join_maintenance_thread()
  }

  // MARK: Deployer

  public distributed func initializeDeployer(with traits: RimeTraits) async throws(RimeError) {
    var t = rime_traits_t.rimeStructInit()
    let handle = traits.toCStructure(&t)
    rimeApi.deployer_initialize(&t)
    withExtendedLifetime(handle) {}
  }

  public distributed func prebuild() async throws(RimeError) -> Bool {
    rimeApi.prebuild()
  }

  public distributed func deploy() async throws(RimeError) -> Bool {
    rimeApi.deploy()
  }

  public distributed func deploySchema(withID schemaID: String) async throws(RimeError) -> Bool {
    rimeApi.deploy_schema(schemaID)
  }

  public distributed func deployConfig(filename: String, versionKey: String) async throws(RimeError)
    -> Bool
  {
    rimeApi.deploy_config_file(filename, versionKey)
  }

  public distributed func syncUserData() async throws(RimeError) -> Bool {
    rimeApi.sync_user_data()
  }

  // MARK: 会话

  public distributed func createSession() async throws(RimeError) -> RimeSessionID {
    try engineCreateSession()
  }

  public distributed func findSession(with sessionID: RimeSessionID) async throws(RimeError) -> Bool
  {
    try engineFindSession(with: sessionID)
  }

  public distributed func destroySession(with sessionID: RimeSessionID) async throws(RimeError)
    -> Bool
  {
    try engineDestroySession(with: sessionID)
  }

  public distributed func cleanupStaleSessions() async throws(RimeError) {
    try engineCleanupStaleSessions()
  }

  public distributed func cleanupAllSessions() async throws(RimeError) {
    try engineCleanupAllSessions()
  }

  // MARK: 按键

  public distributed func processKey(
    keyCode: Int32, modifierMask: Int32, for sessionID: RimeSessionID
  ) async throws(RimeError) -> Bool {
    try engineProcessKey(keyCode: keyCode, modifierMask: modifierMask, for: sessionID)
  }

  public distributed func commitComposition(for sessionID: RimeSessionID) async throws(RimeError)
    -> Bool
  {
    try engineCommitComposition(for: sessionID)
  }

  public distributed func clearComposition(for sessionID: RimeSessionID) async throws(RimeError) {
    try engineClearComposition(for: sessionID)
  }

  // MARK: 输出

  public distributed func commit(for sessionID: RimeSessionID) async throws(RimeError)
    -> RimeCommit?
  {
    try engineCommit(for: sessionID)
  }

  public distributed func status(for sessionID: RimeSessionID) async throws(RimeError)
    -> RimeStatus?
  {
    try engineStatus(for: sessionID)
  }

  public distributed func context(for sessionID: RimeSessionID) async throws(RimeError)
    -> RimeContext?
  {
    try engineContext(for: sessionID)
  }

  // MARK: 选项 / 属性

  public distributed func option(named option: String, for sessionID: RimeSessionID)
    async throws(RimeError) -> Bool
  {
    rimeApi.get_option(sessionID.rawValue, option)
  }

  public distributed func setOption(_ option: String, value: Bool, for sessionID: RimeSessionID)
    async throws(RimeError)
  {
    rimeApi.set_option(sessionID.rawValue, option, value)
  }

  public distributed func property(named property: String, for sessionID: RimeSessionID)
    async throws(RimeError) -> String?
  {
    let bufferSize = 1024
    let buffer: [CChar] = Array(repeating: 0, count: bufferSize)
    return buffer.withUnsafeBufferPointer { pointer in
      guard
        rimeApi.get_property(
          sessionID.rawValue,
          property,
          UnsafeMutablePointer(mutating: pointer.baseAddress),
          bufferSize
        )
      else {
        return nil
      }
      return pointer.baseAddress.map { String(cString: $0) }
    }
  }

  public distributed func setProperty(
    _ property: String, value: String, for sessionID: RimeSessionID
  ) async throws(RimeError) {
    rimeApi.set_property(sessionID.rawValue, property, value)
  }

  // MARK: Schema

  public distributed func schemaList() async throws(RimeError) -> RimeSchemaList {
    try engineSchemaList
  }

  public distributed func currentSchema(for sessionID: RimeSessionID) async throws(RimeError)
    -> String?
  {
    try engineCurrentSchema(for: sessionID)
  }

  public distributed func selectSchema(_ schemaID: String, for sessionID: RimeSessionID)
    async throws(RimeError) -> Bool
  {
    try engineSelectSchema(schemaID, for: sessionID)
  }

  // MARK: 配置打开

  public distributed func openSchema(_ schemaID: String) async throws(RimeError) -> ObjectHandle<
    RimeConfig
  >? {
    try engineOpenSchema(schemaID: schemaID)
  }

  public distributed func openConfig(_ configID: String) async throws(RimeError) -> ObjectHandle<
    RimeConfig
  >? {
    try engineOpenConfig(configID: configID)
  }

  public distributed func close(config: ObjectHandle<RimeConfig>) async throws(RimeError) -> Bool {
    try engineClose(config: config)
  }

  // MARK: 配置读写

  public distributed func string(forKey key: String, in config: ObjectHandle<RimeConfig>)
    async throws(RimeError) -> String?
  {
    try engineString(forKey: key, in: config)
  }

  public distributed func int(forKey key: String, in config: ObjectHandle<RimeConfig>)
    async throws(RimeError) -> Int32?
  {
    try engineInt(forKey: key, in: config)
  }

  public distributed func bool(forKey key: String, in config: ObjectHandle<RimeConfig>)
    async throws(RimeError) -> Bool?
  {
    try engineBool(forKey: key, in: config)
  }

  public distributed func double(forKey key: String, in config: ObjectHandle<RimeConfig>)
    async throws(RimeError) -> Double?
  {
    try engineDouble(forKey: key, in: config)
  }

  public distributed func item(forKey key: String, in config: ObjectHandle<RimeConfig>)
    async throws(RimeError) -> ObjectHandle<RimeConfig>?
  {
    try engineItem(forKey: key, in: config)
  }

  public distributed func set(
    _ value: String, forKey key: String, in config: ObjectHandle<RimeConfig>
  ) async throws(RimeError) -> Bool {
    try engineSet(value: value, forKey: key, in: config)
  }

  public distributed func set(
    _ value: Int32, forKey key: String, in config: ObjectHandle<RimeConfig>
  ) async throws(RimeError) -> Bool {
    try engineSet(value: value, forKey: key, in: config)
  }

  public distributed func set(
    _ value: Bool, forKey key: String, in config: ObjectHandle<RimeConfig>
  ) async throws(RimeError) -> Bool {
    try engineSet(value: value, forKey: key, in: config)
  }

  public distributed func set(
    _ value: Double, forKey key: String, in config: ObjectHandle<RimeConfig>
  ) async throws(RimeError) -> Bool {
    try engineSet(value: value, forKey: key, in: config)
  }

  public distributed func set(
    _ value: ObjectHandle<RimeConfig>, forKey key: String, in config: ObjectHandle<RimeConfig>
  ) async throws(RimeError) -> Bool {
    try engineSet(value: value, forKey: key, in: config)
  }

  public distributed func removeValue(forKey key: String, in config: ObjectHandle<RimeConfig>)
    async throws(RimeError) -> Bool
  {
    try engineRemoveValue(forKey: key, in: config)
  }

  public distributed func update(signature: String, for config: ObjectHandle<RimeConfig>)
    async throws(RimeError) -> Bool
  {
    try engineUpdate(signature: signature, for: config)
  }

  public distributed func beginMap(forKey key: String, in config: ObjectHandle<RimeConfig>)
    async throws(RimeError) -> ObjectHandle<RimeConfigIterator>
  {
    try engineBeginMap(forKey: key, in: config)
  }

  public distributed func beginList(forKey key: String, in config: ObjectHandle<RimeConfig>)
    async throws(RimeError) -> ObjectHandle<RimeConfigIterator>
  {
    try engineBeginList(forKey: key, in: config)
  }

  public distributed func advanceConfigIterator(_ iterator: ObjectHandle<RimeConfigIterator>)
    async throws(RimeError) -> RimeConfigLocation?
  {
    try engineAdvanceConfigIterator(iterator)
  }

  public distributed func endConfigIterator(_ iterator: ObjectHandle<RimeConfigIterator>)
    async throws(RimeError)
  {
    try engineEndConfigIterator(iterator)
  }

  public distributed func makeConfig() async throws(RimeError) -> ObjectHandle<RimeConfig> {
    try engineMakeConfig()
  }

  public distributed func load(yaml: String, into config: ObjectHandle<RimeConfig>)
    async throws(RimeError) -> Bool
  {
    try engineLoad(yaml: yaml, into: config)
  }

  public distributed func createList(forKey key: String, in config: ObjectHandle<RimeConfig>)
    async throws(RimeError) -> Bool
  {
    try engineCreateList(forKey: key, in: config)
  }

  public distributed func createMap(forKey key: String, in config: ObjectHandle<RimeConfig>)
    async throws(RimeError) -> Bool
  {
    try engineCreateMap(forKey: key, in: config)
  }

  public distributed func listSize(forKey key: String, in config: ObjectHandle<RimeConfig>)
    async throws(RimeError) -> Int
  {
    try engineListSize(forKey: key, in: config)
  }

  // MARK: 身份 / 目录

  public distributed func userID() async throws(RimeError) -> String {
    guard let userID = rimeApi.get_user_id() else {
      throw RimeError.engineNotInitialized
    }
    return String(cString: userID)
  }

  public distributed func userDataSyncDirectory() async throws(RimeError) -> String {
    rimeApi.get_user_data_sync_dir(cStringBuffer, Self.cStringBufferSize)
    return String(cString: cStringBuffer)
  }

  // MARK: 输入 / 光标

  public distributed func input(for sessionID: RimeSessionID) async throws(RimeError) -> String? {
    try engineInput(for: sessionID)
  }

  public distributed func set(input: String, for sessionID: RimeSessionID) async throws(RimeError)
    -> Bool
  {
    try engineSet(input: input, for: sessionID)
  }

  public distributed func caretPosition(for sessionID: RimeSessionID) async throws(RimeError) -> Int
  {
    try engineCaretPosition(for: sessionID)
  }

  public distributed func set(caretPosition: Int, for sessionID: RimeSessionID)
    async throws(RimeError)
  {
    try engineSet(caretPosition: caretPosition, for: sessionID)
  }

  // MARK: 版本

  public distributed func version() async throws(RimeError) -> String {
    guard let version = rimeApi.get_version() else {
      throw RimeError.apiUnavailable("get_version")
    }
    return String(cString: version)
  }

  // MARK: 候选(页式)

  public distributed func selectCandidate(at index: Int, for session: RimeSessionID)
    async throws(RimeError) -> Bool
  {
    try engineSelectCandidate(at: index, for: session)
  }

  public distributed func selectCandidateOnCurrentPage(at index: Int, for session: RimeSessionID)
    async throws(RimeError) -> Bool
  {
    try engineSelectCandidateOnCurrentPage(at: index, for: session)
  }

  // MARK: 候选(句柄式)

  public distributed func beginCandidates(for session: RimeSessionID) async throws(RimeError)
    -> ObjectHandle<RimeCandidate>
  {
    try engineBeginCandidates(for: session)
  }

  public distributed func advanceCandidateIterator(_ iterator: ObjectHandle<RimeCandidate>)
    async throws(RimeError) -> RimeCandidate?
  {
    try engineAdvanceCandidateIterator(iterator)
  }

  public distributed func endCandidateIterator(_ iterator: ObjectHandle<RimeCandidate>)
    async throws(RimeError)
  {
    try engineEndCandidateIterator(iterator)
  }

  public distributed func openUserConfig(configId: String) async throws(RimeError) -> ObjectHandle<
    RimeConfig
  >? {
    try engineOpenUserConfig(configId: configId)
  }

  public distributed func candidateList(fromIndex: Int32, for sessionID: RimeSessionID)
    async throws(RimeError) -> ObjectHandle<RimeCandidate>?
  {
    try engineCandidateList(fromIndex: fromIndex, for: sessionID)
  }

  // MARK: 状态标签

  public distributed func stateLabel(for key: String, state: RimeState, in session: RimeSessionID)
    async throws(RimeError) -> String?
  {
    try engineStateLabel(for: key, state: state, in: session)
  }

  public distributed func stateLabel(
    for key: String, state: RimeState, abbreviated: Bool, in session: RimeSessionID
  ) async throws(RimeError) -> String? {
    try engineStateLabel(for: key, state: state, abbreviated: abbreviated, in: session)
  }

  // MARK: 候选编辑 / 翻页

  public distributed func removeCandidate(at index: Int, for session: RimeSessionID)
    async throws(RimeError) -> Bool
  {
    try engineRemoveCandidate(at: index, for: session)
  }

  public distributed func removeCandidateOnCurrentPage(at index: Int, for session: RimeSessionID)
    async throws(RimeError) -> Bool
  {
    try engineRemoveCandidateOnCurrentPage(at: index, for: session)
  }

  public distributed func highlightCandidate(at index: Int, for session: RimeSessionID)
    async throws(RimeError) -> Bool
  {
    try engineHighlightCandidate(at: index, for: session)
  }

  public distributed func highlightCandidateOnCurrentPage(at index: Int, for session: RimeSessionID)
    async throws(RimeError) -> Bool
  {
    try engineHighlightCandidateOnCurrentPage(at: index, for: session)
  }

  public distributed func page(_ direction: RimePageDirection, for session: RimeSessionID)
    async throws(RimeError) -> Bool
  {
    try enginePage(direction, for: session)
  }

  // MARK: 目录

  public distributed func sharedDataDirectory() async throws(RimeError) -> String {
    rimeApi.get_shared_data_dir_s(cStringBuffer, Self.cStringBufferSize)
    return String(cString: cStringBuffer)
  }

  public distributed func userDataDirectory() async throws(RimeError) -> String {
    rimeApi.get_user_data_dir_s(cStringBuffer, Self.cStringBufferSize)
    return String(cString: cStringBuffer)
  }

  public distributed func prebuiltDataDirectory() async throws(RimeError) -> String {
    rimeApi.get_prebuilt_data_dir_s(cStringBuffer, Self.cStringBufferSize)
    return String(cString: cStringBuffer)
  }

  public distributed func stagingDirectory() async throws(RimeError) -> String {
    rimeApi.get_staging_dir_s(cStringBuffer, Self.cStringBufferSize)
    return String(cString: cStringBuffer)
  }

  public distributed func syncDirectory() async throws(RimeError) -> String {
    rimeApi.get_sync_dir_s(cStringBuffer, Self.cStringBufferSize)
    return String(cString: cStringBuffer)
  }
}

#if os(macOS)
  /// 进程级单例根:`.serviceHost` 宿主系统在首个连接前预留 `.root` 身份,
  /// 与 `shared` 首次物化的时机无关。文件作用域常量模式见 XPCRootActor 文档
  /// (actor 自身不能以 `static let` 调 `init(actorSystem:)`)。
  private let sharedRime = Rime(actorSystem: .serviceHost)

  extension Rime: XPCRootActor {
    public static var shared: Rime { sharedRime }
  }
#endif
