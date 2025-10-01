import CLibrime
import Darwin
import Foundation

public struct RimeSessionID: Sendable, Codable, RawRepresentable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }
}

public struct RimeSession: ~Copyable {
    internal let sessionID: RimeSessionID
    internal let engine: Rime

    public init(engine: Rime) async {
        self.sessionID = await engine.createSession()
        self.engine = engine
    }

    public init?(engine: Rime, sessionID: RimeSessionID) async {
        guard await engine.findSession(with: sessionID) else { return nil }
        self.sessionID = sessionID
        self.engine = engine
    }

    deinit {
        let engine = engine
        let sessionID = sessionID
        Task {
            await engine.destroySession(with: sessionID)
        }
    }
}

extension RimeSession {
    public func option(named option: String) async -> Bool {
        await engine.option(named: option, for: sessionID)
    }

    public func setOption(_ option: String, value: Bool) async {
        await engine.setOption(option, value: value, for: sessionID)
    }

    public func property(named property: String) async -> String? {
        await engine.property(named: property, for: sessionID)
    }

    public func setProperty(_ property: String, value: String) async {
        await engine.setProperty(property, value: value, for: sessionID)
    }
}

extension RimeSession {
    public func processKey(_ keyCode: CInt, modifierMask: CInt) async -> Bool {
        await engine.processKey(keyCode: keyCode, modifierMask: modifierMask, for: sessionID)
    }

    public func commitComposition() async -> Bool {
        await engine.commitComposition(for: sessionID)
    }

    public func clearComposition() async {
        await engine.clearComposition(for: sessionID)
    }
}

extension RimeEngine {
    public func createSession() -> RimeSessionID {
        RimeSessionID(rawValue: UInt(rimeApi.create_session()))
    }

    public func findSession(with sessionID: RimeSessionID) -> Bool {
        rimeApi.find_session(sessionID.rawValue)
    }

    public func destroySession(with sessionID: RimeSessionID) -> Bool {
        rimeApi.destroy_session(sessionID.rawValue)
    }

    public func cleanupStaleSessions() {
        rimeApi.cleanup_stale_sessions()
    }

    public func cleanupAllSessions() {
        rimeApi.cleanup_all_sessions()
    }
}

extension RimeEngine {
    public func processKey(keyCode: CInt, modifierMask: CInt, for sessionID: RimeSessionID)
        -> Bool
    {
        rimeApi.process_key(sessionID.rawValue, keyCode, modifierMask)
    }

    public func commitComposition(for sessionID: RimeSessionID) -> Bool {
        rimeApi.commit_composition(sessionID.rawValue)
    }

    public func clearComposition(for sessionID: RimeSessionID) {
        rimeApi.clear_composition(sessionID.rawValue)
    }
}

extension RimeEngine {
    public func input(for sessionID: RimeSessionID) async -> String? {
        guard let c = rimeApi.get_input(sessionID.rawValue) else {
            return nil
        }
        return String(cString: c)
    }
    public func set(input: String, for sessionID: RimeSessionID) async -> Bool {
        return rimeApi.set_input(sessionID.rawValue, input)
    }

    public func caretPosition(for sessionID: RimeSessionID) async -> Int {
        return Int(rimeApi.get_caret_pos(sessionID.rawValue))
    }
    public func set(caretPosition: Int, for sessionID: RimeSessionID) async {
        rimeApi.set_caret_pos(sessionID.rawValue, caretPosition)
    }

}
