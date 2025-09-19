import CLibrime
import Darwin

public struct RimeSessionID: Sendable, Codable, RawRepresentable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }
}

public struct RimeSession: ~Copyable {
    internal let sessionID: RimeSessionID
    internal let engine: RimeEngine

    public init(engine: RimeEngine) async {
        self.sessionID = await engine.createSession()
        self.engine = engine
    }

    public init?(engine: RimeEngine, sessionID: RimeSessionID) async {
        guard await engine.findSession(with: sessionID) else { return nil }
        self.sessionID = sessionID
        self.engine = engine
    }

    deinit {
        let engine = engine
        let sessionID = sessionID
        Task.detached {
            await engine.destroySession(with: sessionID)
        }
    }
}

extension RimeSession {
    public func processKey(_ keyCode: CInt, modifierMask: CInt) async -> Bool {
        await engine.processKey(for: sessionID, keyCode: keyCode, modifierMask: modifierMask)
    }

    public func commitComposition() async -> Bool {
        await engine.commitComposition(for: sessionID)
    }

    public func clearComposition() async {
        await engine.clearComposition(for: sessionID)
    }
}

extension RimeEngine {
    fileprivate func createSession() -> RimeSessionID {
        RimeSessionID(rawValue: UInt(rimeApi.create_session()))
    }

    fileprivate func findSession(with sessionID: RimeSessionID) -> Bool {
        rimeApi.find_session(sessionID.rawValue)
    }

    fileprivate func destroySession(with sessionID: RimeSessionID) -> Bool {
        rimeApi.destroy_session(sessionID.rawValue)
    }

    fileprivate func cleanupStaleSessions() {
        rimeApi.cleanup_stale_sessions()
    }

    fileprivate func cleanupAllSessions() {
        rimeApi.cleanup_all_sessions()
    }
}

extension RimeEngine {
    fileprivate func processKey(for sessionID: RimeSessionID, keyCode: CInt, modifierMask: CInt)
        -> Bool
    {
        rimeApi.process_key(sessionID.rawValue, keyCode, modifierMask)
    }

    fileprivate func commitComposition(for sessionID: RimeSessionID) -> Bool {
        rimeApi.commit_composition(sessionID.rawValue)
    }

    fileprivate func clearComposition(for sessionID: RimeSessionID) {
        rimeApi.clear_composition(sessionID.rawValue)
    }
}
