// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

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
    let root = self.root
    let sessionID = self.sessionID
    return AsyncStream {
      continuation in
      Task {
        guard let iter = try? await root.candidateList(fromIndex: index, for: sessionID) else {
          continuation.finish()
          return
        }
        continuation.onTermination = { @Sendable _ in
          Task { try? await root.endCandidateIterator(iter) }
        }
        while let candidate = try? await root.advanceCandidateIterator(iter) {
          continuation.yield(candidate)
        }
        try? await root.endCandidateIterator(iter)
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
    let root = self.root
    let handle = self.handle
    return AsyncStream {
      continuation in
      Task {
        let iter: ObjectHandle<RimeConfigIterator>?
        do {
          iter = if mode == .list {
            try await root.beginList(forKey: key, in: handle)
          } else {
            try await root.beginMap(forKey: key, in: handle)
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
          Task { try? await root.endConfigIterator(iter) }
        }
        while let loc = try? await root.advanceConfigIterator(iter) {
          continuation.yield(loc)
        }
        try? await root.endConfigIterator(iter)
        continuation.finish()
      }
    }
  }

  private enum Mode {
    case list
    case map
  }
}
