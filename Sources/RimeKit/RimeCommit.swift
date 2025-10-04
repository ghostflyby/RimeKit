import CLibrime

public struct RimeCommit: Sendable, Codable {
  public let text: String
}

extension RimeSession {
  public var commit: RimeCommit? {
    get async {
      await engine.commit(for: sessionID)
    }
  }

  public var commitText: String? {
    get async {
      await engine.commit(for: sessionID)?.text
    }
  }
}

extension RimeCommit {
  fileprivate init(rawValue: rime_commit_t) {
    text = String(cString: rawValue.text)
  }
}

extension RimeEngine {
  public func commit(for sessionID: RimeSessionID) -> RimeCommit? {
    var commit = rime_commit_t.rimeStructInit()
    defer { _ = rimeApi.free_commit(&commit) }
    guard rimeApi.get_commit(sessionID.rawValue, &commit) else {
      return nil
    }
    return RimeCommit(rawValue: commit)
  }
}
