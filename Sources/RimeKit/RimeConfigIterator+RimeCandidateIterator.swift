public struct RimeConfigLocation: Codable, Sendable {
  let index: Int32
  let key: String?
  let path: String?
}

public class RimeConfigIterator: AsyncIteratorProtocol {
  internal let handle: ObjectHandle<RimeConfigIterator>
  internal let engine: any Rime

  internal init(handle: ObjectHandle<RimeConfigIterator>, engine: any Rime) {
    self.handle = handle
    self.engine = engine
  }

  public func next() async throws -> RimeConfigLocation? {
    await engine.advanceConfigIterator(handle)
  }

  public func next(isolation actor: isolated (any Actor)?) async
    -> RimeConfigLocation?
  {
    await engine.advanceConfigIterator(handle)
  }

  deinit {
    let ptr = handle
    let engine = engine
    Task {
      await engine.endConfigIterator(ptr)
    }
  }

}

public class RimeCandidateIterator: AsyncIteratorProtocol {
  internal init(
    handle: ObjectHandle<RimeCandidateIterator>, engine: any Rime
  ) {
    self.handle = handle
    self.engine = engine
  }

  internal let handle: ObjectHandle<RimeCandidateIterator>
  internal let engine: any Rime

  public func next() async throws -> RimeCandidate? {
    await engine.advanceCandidateIterator(handle)
  }

  public func next(isolation actor: isolated (any Actor)?) async
    -> RimeCandidate?
  {
    await engine.advanceCandidateIterator(handle)
  }

  deinit {
    let ptr = handle
    let engine = engine
    Task {
      await engine.endCandidateIterator(ptr)
    }
  }

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
        guard let iter = await engine.candidateList(fromIndex: index, for: sessionID) else {
          continuation.finish()
          return
        }
        continuation.onTermination = { @Sendable _ in
          Task { await engine.endCandidateIterator(iter) }
        }
        while let candidate = await engine.advanceCandidateIterator(iter) {
          continuation.yield(candidate)
        }
        await engine.endCandidateIterator(iter)
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
    return AsyncStream {
      continuation in
      Task {
        let iter =
          if mode == .list {
            await engine.beginList(forKey: key, in: handle)
          } else {
            await engine.beginMap(forKey: key, in: handle)
          }
        continuation.onTermination = { @Sendable _ in
          Task { await engine.endConfigIterator(iter) }
        }
        while let loc = await engine.advanceConfigIterator(iter) {
          continuation.yield(loc)
        }
        await engine.endConfigIterator(iter)
        continuation.finish()
      }
    }
  }

  private enum Mode {
    case list
    case map
  }
}
