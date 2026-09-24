// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Darwin
import Foundation
import RimeC

public struct RimeSessionID: Sendable, Codable, Hashable, RawRepresentable {
  public let rawValue: UInt

  public init(rawValue: UInt) {
    self.rawValue = rawValue
  }
}

/// Rime 会话:绑定 (root, sessionID) 的**同步门面**,输入法宿主的直接对接面。
///
/// 所有权归注册表(强持有,镜像 librime 会话表):消费方可自由持引用,
/// 销毁只经 `invalidate()` 协调发生(蓝绿切换/重连/显式销毁);失效后
/// 一切事务抛 `RimeSessionError.invalidated`,消费方按当前活跃根重建。
/// 事务经内部 FIFO 门串行:多调用分组(如按键事务)对其他事务不可见。
///
/// 同步方法为阻塞包装,阻塞落在调用方线程(输入法回调线程,其同步契约
/// 本就要求等待);协作线程池仅挂起不占线程。超时默认 10s,超时抛
/// `timedOut` 而内部操作继续。跨进程的只有根 actor;本类型保持本地。
public final class RimeSession: RimeSessionProtocol {
  internal let id: RimeSessionID
  internal let root: Rime
  let gate = RimeSessionGate()  // internal:@testable 供超时测试占门
  private let state = InvalidatedFlag()

  /// 进程内公开工厂:绑定共享引擎(iOS/进程内路径的公开入口)。
  public convenience init() async throws {
    try await self.init(root: .localShared)
  }

  /// 绑定任意根引用(本地实例或 XPC 代理):输入法宿主的公开入口。
  /// 新建会话并注册进同一性规范表。
  public init(root: Rime) async throws {
    let id = try await root.createSession()
    self.id = id
    self.root = root
    RimeSessionRegistry.register(root: root, session: self)
  }

  /// 内部:绑定已通过 findSession 校验的既有会话并注册。
  private init(claiming root: Rime, sessionID: RimeSessionID) {
    self.id = sessionID
    self.root = root
    RimeSessionRegistry.register(root: root, session: self)
  }

  /// 同步工厂:新建会话并注册(阻塞一次 createSession 往返)。
  /// 输入法回调等同步上下文按当前活跃根建会话的入口。
  public static func create(root: Rime, timeout: Duration = .seconds(10)) throws -> RimeSession {
    try RimeSync.perform(timeout: timeout) { try await RimeSession(root: root) }
  }

  /// 重绑既有会话:同键存活句柄存在时**直接返回规范实例**;否则经
  /// findSession 校验后新建(校验失败返回 nil,调用方可重建会话)。
  public static func rebind(
    root: Rime, sessionID: RimeSessionID
  ) async throws -> RimeSession? {
    if let existing = RimeSessionRegistry.lookup(root: root, sessionID: sessionID) {
      return existing
    }
    guard try await root.findSession(with: sessionID) else { return nil }
    return RimeSession(claiming: root, sessionID: sessionID)
  }

  /// 会话 ID(供重连/迁移场景重建句柄)。
  public var sessionID: RimeSessionID { id }

  /// 同步失效:注册表移除 + 后台排队销毁(不等待完成)。
  /// 供同步门面的调用方在任意上下文丢弃句柄时使用。
  public func abort() {
    state.markInvalidated()
    _ = RimeSessionRegistry.retire(root: root, sessionID: id)
    let root = root
    let id = id
    Task { try? await root.destroySession(with: id) }
  }

  /// 协调失效:从注册表移除并**同步销毁**底层会话(返回后 findSession
  /// 必为假,rebind 不可能再获得本会话)。幂等。
  public func invalidate() async {
    state.markInvalidated()
    _ = RimeSessionRegistry.retire(root: root, sessionID: id)
    _ = try? await root.destroySession(with: id)
  }

  /// 显式销毁(invalidate 加即时 destroy,保留直白命名)。
  public func destroy() async {
    await invalidate()
  }

  // MARK: - 同步门面(RimeSessionProtocol)

  public func keyTransaction(keyCode: Int32, modifierMask: Int32) throws
    -> RimeKeyTransactionResult
  {
    try keyTransaction(keyCode: keyCode, modifierMask: modifierMask, timeout: .seconds(10))
  }

  public func keyTransaction(
    keyCode: Int32, modifierMask: Int32, timeout: Duration
  ) throws -> RimeKeyTransactionResult {
    try RimeSync.perform(timeout: timeout) {
      try await self._keyTransaction(keyCode: keyCode, modifierMask: modifierMask)
    }
  }

  public func blurTransaction() throws -> RimeCommit? {
    try RimeSync.perform(timeout: .seconds(10)) {
      try await self._blurTransaction()
    }
  }

  public func selectCandidateTransaction(onCurrentPage index: Int) throws
    -> RimeKeyTransactionResult
  {
    try RimeSync.perform(timeout: .seconds(10)) {
      try await self._selectCandidateTransaction(onCurrentPage: index)
    }
  }

  public func pageTransaction(_ direction: RimePageDirection) throws
    -> RimeKeyTransactionResult
  {
    try RimeSync.perform(timeout: .seconds(10)) {
      try await self._pageTransaction(direction)
    }
  }

  public func candidatesTransaction() throws -> RimeElasticCandidates {
    try RimeSync.perform(timeout: .seconds(10)) {
      try await self._candidatesTransaction()
    }
  }

  /// 会话失效自愈核验(阻塞):底层会话是否仍存在于引擎会话表。
  public func sessionExists() throws -> Bool {
    let root = self.root
    let id = self.id
    return try RimeSync.perform(timeout: .seconds(10)) {
      try await root.findSession(with: id)
    }
  }

  public func selectCandidateGlobalTransaction(at index: Int) throws
    -> RimeKeyTransactionResult
  {
    try RimeSync.perform(timeout: .seconds(10)) {
      try await self._selectCandidateGlobalTransaction(at: index)
    }
  }

  public func setOption(_ option: String, value: Bool) throws {
    let root = self.root
    let id = self.id
    try RimeSync.perform(timeout: .seconds(10)) {
      try await root.setOption(option, value: value, for: id)
    }
  }

  // MARK: - 门控事务核(async;同步包装的唯一实现路径)

  func _keyTransaction(keyCode: Int32, modifierMask: Int32) async throws
    -> RimeKeyTransactionResult
  {
    try await beginTransaction()
    defer { gate.release() }
    // 服务端组装事务:单次往返返回业务结果(原四次 RPC 组装已上移引擎)。
    return try await root.keyTransaction(
      keyCode: keyCode, modifierMask: modifierMask, for: id)
  }

  func _blurTransaction() async throws -> RimeCommit? {
    try await beginTransaction()
    defer { gate.release() }
    let composing = try await root.status(for: id)?.isComposing ?? false
    guard composing else { return nil }  // 非组字态无副作用
    _ = try await root.commitComposition(for: id)
    return try await root.commit(for: id)
  }

  func _selectCandidateTransaction(onCurrentPage index: Int) async throws
    -> RimeKeyTransactionResult
  {
    try await beginTransaction()
    defer { gate.release() }
    return try await root.selectCandidateTransaction(onCurrentPage: index, for: id)
  }

  func _candidatesTransaction() async throws -> RimeElasticCandidates {
    try await beginTransaction()
    defer { gate.release() }
    return try await root.candidatesTransaction(for: id)
  }

  func _selectCandidateGlobalTransaction(at index: Int) async throws
    -> RimeKeyTransactionResult
  {
    try await beginTransaction()
    defer { gate.release() }
    return try await root.selectCandidateGlobalTransaction(at: index, for: id)
  }

  func _pageTransaction(_ direction: RimePageDirection) async throws
    -> RimeKeyTransactionResult
  {
    try await beginTransaction()
    defer { gate.release() }
    return try await root.pageTransaction(direction, for: id)
  }

  /// 入门 + 失效检查(检查在门内进行,与 invalidate 串行)。
  private func beginTransaction() async throws {
    await gate.acquire()
    guard !state.isInvalidated else {
      gate.release()
      throw RimeSessionError.invalidated
    }
  }
}

/// 失效标记(NSLock 而非 Mutex:与包内其他同步原语的地板对齐)。
final class InvalidatedFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var value = false

  func markInvalidated() {
    lock.lock()
    value = true
    lock.unlock()
  }

  var isInvalidated: Bool {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
}

extension RimeSession {
  public func option(named option: String) async throws -> Bool {
    try await root.option(named: option, for: sessionID)
  }

  public func setOption(_ option: String, value: Bool) async throws {
    try await root.setOption(option, value: value, for: sessionID)
  }

  public func property(named property: String) async throws -> String? {
    try await root.property(named: property, for: sessionID)
  }

  public func setProperty(_ property: String, value: String) async throws {
    try await root.setProperty(property, value: value, for: sessionID)
  }
}

extension RimeSession {
  public func processKey(_ keyCode: Int32, modifierMask: Int32) async throws -> Bool {
    try await root.processKey(keyCode: keyCode, modifierMask: modifierMask, for: sessionID)
  }

  public func commitComposition() async throws -> Bool {
    try await root.commitComposition(for: sessionID)
  }

  public func clearComposition() async throws {
    try await root.clearComposition(for: sessionID)
  }
}

extension Rime {
  func engineCreateSession() throws(RimeError) -> RimeSessionID {
    RimeSessionID(rawValue: UInt(rimeApi.create_session()))
  }

  func engineFindSession(with sessionID: RimeSessionID) throws(RimeError) -> Bool {
    rimeApi.find_session(sessionID.rawValue)
  }

  func engineDestroySession(with sessionID: RimeSessionID) throws(RimeError) -> Bool {
    rimeApi.destroy_session(sessionID.rawValue)
  }

  func engineCleanupStaleSessions() throws(RimeError) {
    rimeApi.cleanup_stale_sessions()
  }

  func engineCleanupAllSessions() throws(RimeError) {
    rimeApi.cleanup_all_sessions()
  }
}

extension Rime {
  func engineProcessKey(keyCode: Int32, modifierMask: Int32, for sessionID: RimeSessionID)
    throws(RimeError) -> Bool
  {
    rimeApi.process_key(sessionID.rawValue, keyCode, modifierMask)
  }

  func engineCommitComposition(for sessionID: RimeSessionID) throws(RimeError) -> Bool {
    rimeApi.commit_composition(sessionID.rawValue)
  }

  func engineClearComposition(for sessionID: RimeSessionID) throws(RimeError) {
    rimeApi.clear_composition(sessionID.rawValue)
  }
}

extension Rime {
  func engineInput(for sessionID: RimeSessionID) throws(RimeError) -> String? {
    guard let c = rimeApi.get_input(sessionID.rawValue) else {
      return nil
    }
    return String(cString: c)
  }
  func engineSet(input: String, for sessionID: RimeSessionID) throws(RimeError) -> Bool {
    return rimeApi.set_input(sessionID.rawValue, input)
  }

  func engineCaretPosition(for sessionID: RimeSessionID) throws(RimeError) -> Int {
    return Int(rimeApi.get_caret_pos(sessionID.rawValue))
  }
  func engineSet(caretPosition: Int, for sessionID: RimeSessionID) throws(RimeError) {
    rimeApi.set_caret_pos(sessionID.rawValue, caretPosition)
  }
}

extension RimeSession {

  public var input: String? {
    get async throws { try await root.input(for: sessionID) }
  }
  public func set(input: String) async throws -> Bool {
    try await root.set(input: input, for: sessionID)
  }

  public var caretPosition: Int {
    get async throws { try await root.caretPosition(for: sessionID) }
  }
  public func set(caretPosition: Int) async throws {
    try await root.set(caretPosition: caretPosition, for: sessionID)
  }
}

extension RimeSession {
  /// 提交当前候选(全局下标;跨页自动定位)。
  public func commit() async throws -> RimeCommit? {
    try await root.commit(for: sessionID)
  }

  /// 组字/候选快照(当前引擎页)。
  public func context() async throws -> RimeContext? {
    try await root.context(for: sessionID)
  }

  /// 会话状态(isComposing 等)。
  public func status() async throws -> RimeStatus? {
    try await root.status(for: sessionID)
  }
}

/// 会话句柄同一性规范表:**注册表强持有**(镜像 librime 会话表——
/// 所有权归表,销毁只经协调路径 `invalidate`/`retire` 发生),同一
/// `(root, id)` 至多一个存活句柄实例,别名在结构上不可能。键含根身份:
/// 双代(blue/green)各自独立进程/代理,id 空间互不可见。
enum RimeSessionRegistry {
  /// NSLock 而非 Mutex:可用性地板与包地板对齐(见 RimeGlobalNotificationHook)。
  private final class State: @unchecked Sendable {
    let lock = NSLock()
    var table: [ObjectIdentifier: [RimeSessionID: RimeSession]] = [:]

    func lookup(root: Rime, sessionID: RimeSessionID) -> RimeSession? {
      lock.lock()
      defer { lock.unlock() }
      return table[ObjectIdentifier(root)]?[sessionID]
    }

    func register(root: Rime, session: RimeSession) {
      lock.lock()
      defer { lock.unlock() }
      table[ObjectIdentifier(root), default: [:]][session.id] = session
    }

    func retire(root: Rime, sessionID: RimeSessionID) -> RimeSession? {
      lock.lock()
      defer { lock.unlock() }
      let key = ObjectIdentifier(root)
      guard var sessions = table[key], let removed = sessions.removeValue(forKey: sessionID)
      else { return nil }
      if sessions.isEmpty {
        table[key] = nil
      } else {
        table[key] = sessions
      }
      return removed
    }
  }

  private static let state = State()

  static func lookup(root: Rime, sessionID: RimeSessionID) -> RimeSession? {
    state.lookup(root: root, sessionID: sessionID)
  }

  static func register(root: Rime, session: RimeSession) {
    state.register(root: root, session: session)
  }

  static func retire(root: Rime, sessionID: RimeSessionID) -> RimeSession? {
    state.retire(root: root, sessionID: sessionID)
  }
}
