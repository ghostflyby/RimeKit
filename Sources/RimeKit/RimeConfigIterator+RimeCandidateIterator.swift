public struct RimeConfigLocation: Codable, Sendable {
  let index: Int32
  let key: String?
  let path: String?
}

extension RimeSession {
  public var candidates: AsyncStream<RimeCandidate> {
    candidates(startingAt: 0)
  }

  public func candidates(startingAt index: Int32) -> AsyncStream<RimeCandidate> {
    let engine = self.engine
    let sessionID = self.sessionID
    return AsyncStream {
      continuation in
      Task {
        guard let iter = try? engine.candidateList(fromIndex: index, for: sessionID) else {
          continuation.finish()
          return
        }
        continuation.onTermination = { @Sendable _ in
          Task { try? engine.endCandidateIterator(iter) }
        }
        while let candidate = try? engine.advanceCandidateIterator(iter) {
          continuation.yield(candidate)
        }
        try? engine.endCandidateIterator(iter)
        continuation.finish()
      }
    }
  }
}

extension RimeConfig {

  public func list(forKey key: String) -> AsyncStream<RimeConfigLocation> {
    beginIteration(forKey: key, mode: .list)
  }

  public func map(forKey key: String) -> AsyncStream<RimeConfigLocation> {
    beginIteration(forKey: key, mode: .map)
  }

  private func beginIteration(forKey key: String, mode: Mode) -> AsyncStream<RimeConfigLocation> {
    let engine = self.engine
    let handle = self.handle
    return AsyncStream {
      continuation in
      Task {
        let iter: ObjectHandle<RimeConfigIterator>?
        do {
          iter = if mode == .list {
            try engine.beginList(forKey: key, in: handle)
          } else {
            try engine.beginMap(forKey: key, in: handle)
          }
        } catch {
          continuation.finish()
          return
        }
        guard let iter else {
          continuation.finish()
          return
        }
        continuation.onTermination = { @Sendable _ in
          Task { try? engine.endConfigIterator(iter) }
        }
        while let loc = try? engine.advanceConfigIterator(iter) {
          continuation.yield(loc)
        }
        try? engine.endConfigIterator(iter)
        continuation.finish()
      }
    }
  }

  private enum Mode {
    case list
    case map
  }
}
