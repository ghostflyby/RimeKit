import Darwin
import Foundation
import RimeDynamic

public struct RimeSessionID: Sendable, Codable, Hashable, RawRepresentable {
  public let rawValue: UInt

  public init(rawValue: UInt) {
    self.rawValue = rawValue
  }
}

public struct RimeSession: ~Copyable {
  internal let sessionID: RimeSessionID
  internal let engine: RimeEngine

  /// 进程内公开工厂:绑定共享引擎(iOS/进程内路径的公开入口)。
  public init() throws(RimeError) {
    try self.init(engine: .shared)
  }

  init(engine: RimeEngine) throws(RimeError) {
    self.sessionID = try engine.createSession()
    self.engine = engine
  }

  init?(engine: RimeEngine, sessionID: RimeSessionID) throws(RimeError) {
    guard try engine.findSession(with: sessionID) else { return nil }
    self.sessionID = sessionID
    self.engine = engine
  }

  deinit {
    try? engine.destroySession(with: sessionID)
  }
}

extension RimeSession {
  public func option(named option: String) throws(RimeError) -> Bool {
    try engine.option(named: option, for: sessionID)
  }

  public func setOption(_ option: String, value: Bool) throws(RimeError) {
    try engine.setOption(option, value: value, for: sessionID)
  }

  public func property(named property: String) throws(RimeError) -> String? {
    try engine.property(named: property, for: sessionID)
  }

  public func setProperty(_ property: String, value: String) throws(RimeError) {
    try engine.setProperty(property, value: value, for: sessionID)
  }
}

extension RimeSession {
  public func processKey(_ keyCode: Int32, modifierMask: Int32) throws(RimeError) -> Bool {
    try engine.processKey(keyCode: keyCode, modifierMask: modifierMask, for: sessionID)
  }

  public func commitComposition() throws(RimeError) -> Bool {
    try engine.commitComposition(for: sessionID)
  }

  public func clearComposition() throws(RimeError) {
    try engine.clearComposition(for: sessionID)
  }
}

extension RimeEngine {
  public func createSession() throws(RimeError) -> RimeSessionID {
    RimeSessionID(rawValue: UInt(rimeApi.create_session()))
  }

  public func findSession(with sessionID: RimeSessionID) throws(RimeError) -> Bool {
    rimeApi.find_session(sessionID.rawValue)
  }

  public func destroySession(with sessionID: RimeSessionID) throws(RimeError) -> Bool {
    rimeApi.destroy_session(sessionID.rawValue)
  }

  public func cleanupStaleSessions() throws(RimeError) {
    rimeApi.cleanup_stale_sessions()
  }

  public func cleanupAllSessions() throws(RimeError) {
    rimeApi.cleanup_all_sessions()
  }
}

extension RimeEngine {
  public func processKey(keyCode: Int32, modifierMask: Int32, for sessionID: RimeSessionID) throws(RimeError) -> Bool
  {
    rimeApi.process_key(sessionID.rawValue, keyCode, modifierMask)
  }

  public func commitComposition(for sessionID: RimeSessionID) throws(RimeError) -> Bool {
    rimeApi.commit_composition(sessionID.rawValue)
  }

  public func clearComposition(for sessionID: RimeSessionID) throws(RimeError) {
    rimeApi.clear_composition(sessionID.rawValue)
  }
}

extension RimeEngine {
  public func input(for sessionID: RimeSessionID) throws(RimeError) -> String? {
    guard let c = rimeApi.get_input(sessionID.rawValue) else {
      return nil
    }
    return String(cString: c)
  }
  public func set(input: String, for sessionID: RimeSessionID) throws(RimeError) -> Bool {
    return rimeApi.set_input(sessionID.rawValue, input)
  }

  public func caretPosition(for sessionID: RimeSessionID) throws(RimeError) -> Int {
    return Int(rimeApi.get_caret_pos(sessionID.rawValue))
  }
  public func set(caretPosition: Int, for sessionID: RimeSessionID) throws(RimeError) {
    rimeApi.set_caret_pos(sessionID.rawValue, caretPosition)
  }
}

extension RimeSession {

  public var input: String? {
    get throws(RimeError) { try engine.input(for: sessionID) }
  }
  public func set(input: String) throws(RimeError) -> Bool {
    try engine.set(input: input, for: sessionID)
  }

  public var caretPosition: Int {
    get throws(RimeError) { try engine.caretPosition(for: sessionID) }
  }
  public func set(caretPosition: Int) throws(RimeError) {
    try engine.set(caretPosition: caretPosition, for: sessionID)
  }
}
