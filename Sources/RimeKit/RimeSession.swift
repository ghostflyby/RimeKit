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

/// Rime 会话句柄:绑定 (root, sessionID) 的可长期持有外观。
///
/// class 语义:可存入 actor 属性、协议存在类型与 `@Sendable` 闭包,供输入法
/// 宿主**长期持有**(每输入会话一个句柄,随宿主生命周期)。引用计数归零时
/// 排队销毁底层会话;`destroy()` 供提前显式销毁——两者同一通道且幂等
/// (librime 对已销毁会话返回 false)。短命用法(单次调用即弃)同样成立。
///
/// **同一性规范**(弱引用注册表):同一 `(root, id)` 至多存在一个存活
/// 句柄实例,全部构造路径经 `RimeSessionRegistry` 收敛——别名(两个
/// 句柄包同一会话,一方丢弃连带销毁另一方)在结构上不可能。
public final class RimeSession: Sendable {
  internal let id: RimeSessionID
  internal let root: Rime

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

  deinit {
    let root = root
    let id = id
    Task { try? await root.destroySession(with: id) }
  }

  /// 会话 ID(供重连/迁移场景重建句柄)。
  public var sessionID: RimeSessionID { id }

  /// 显式销毁底层会话(与析构销毁同通道,幂等)。
  public func destroy() async {
    _ = try? await root.destroySession(with: id)
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

/// 会话句柄同一性规范表:同一 `(root, id)` 至多一个存活句柄实例,
/// 全部构造路径经此收敛——别名(两个句柄包同一会话,一方丢弃连带
/// 销毁另一方)在结构上不可能。表持**弱引用**,持有者全部消亡时条目
/// 自动蒸发(销毁由句柄 deinit 常规触发);键含根身份:双代(blue/green)
/// 各自独立进程/代理,id 空间互不可见。
enum RimeSessionRegistry {
  private final class Weak {
    weak var value: RimeSession?
    init(_ value: RimeSession) { self.value = value }
  }

  /// NSLock 而非 Mutex:可用性地板与包地板对齐(见 RimeGlobalNotificationHook)。
  private final class State: @unchecked Sendable {
    let lock = NSLock()
    var table: [ObjectIdentifier: [RimeSessionID: Weak]] = [:]

    func lookup(root: Rime, sessionID: RimeSessionID) -> RimeSession? {
      lock.lock()
      defer { lock.unlock() }
      let key = ObjectIdentifier(root)
      guard var sessions = table[key], let weak = sessions[sessionID] else { return nil }
      if let value = weak.value { return value }
      sessions[sessionID] = nil
      if sessions.isEmpty {
        table[key] = nil
      } else {
        table[key] = sessions
      }
      return nil
    }

    func register(root: Rime, session: RimeSession) {
      lock.lock()
      defer { lock.unlock() }
      table[ObjectIdentifier(root), default: [:]][session.id] = Weak(session)
    }
  }

  private static let state = State()

  static func lookup(root: Rime, sessionID: RimeSessionID) -> RimeSession? {
    state.lookup(root: root, sessionID: sessionID)
  }

  static func register(root: Rime, session: RimeSession) {
    state.register(root: root, session: session)
  }
}
