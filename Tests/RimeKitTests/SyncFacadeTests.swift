// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0

import Testing

@testable import RimeKit

/// 同步门面:事务组装、门串行、超时、协调失效。
@Suite(.serialized)
struct SyncFacadeTests {
  @Test(arguments: RimeBackend.allCases)
  func keyTransactionAssemblesOutcome(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let session = try await env.makeSession()

    let first = try session.keyTransaction(keyCode: Key.ascii("n"), modifierMask: 0)
    #expect(first.handled)
    #expect(first.composing)
    #expect(first.context?.composition.preedit == "n")

    let second = try session.keyTransaction(keyCode: Key.ascii("i"), modifierMask: 0)
    #expect(second.handled)
    #expect(second.context?.composition.preedit == "ni")
    #expect(second.commit == nil)  // 组字中无提交
  }

  @Test(arguments: RimeBackend.allCases)
  func blurTransactionCommitsComposition(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let session = try await env.makeSession()
    for char in "nihao" {
      _ = try session.keyTransaction(keyCode: Key.ascii(char), modifierMask: 0)
    }
    let commit = try session.blurTransaction()
    #expect(commit?.text.isEmpty == false)
    // 失焦后离开组字态
    let after = try await session.context()
    #expect(after?.composition.preedit.isEmpty == true)
  }

  @Test(arguments: RimeBackend.allCases)
  func gateSerializesConcurrentTransactions(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let session = try await env.makeSession()
    // 双线程并发按键:门保证两事务不交错,两键完整落进组字缓冲(次序不定)。
    let t1 = Task.detached { try session.keyTransaction(keyCode: Key.ascii("a"), modifierMask: 0) }
    let t2 = Task.detached { try session.keyTransaction(keyCode: Key.ascii("b"), modifierMask: 0) }
    let r1 = try await t1.value
    let r2 = try await t2.value
    #expect(r1.handled && r2.handled)
    let input = try await session.input
    #expect(input?.count == 2)
    #expect(input == "ab" || input == "ba")
  }

  @Test(arguments: RimeBackend.allCases)
  func timedOutThrowsAndPoisonsGate(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let session = try await env.makeSession()
    // 手动占门制造卡死:短时限事务应抛 timedOut。
    await session.gate.acquire()
    #expect(throws: RimeSessionError.self) {
      try session.keyTransaction(keyCode: Key.ascii("a"), modifierMask: 0, timeout: .milliseconds(80))
    }
    session.gate.release()
    // 释放后事务恢复可用(被弃操作完成后门已可复用;此处直接验证可达)。
    let retry = try session.keyTransaction(keyCode: Key.ascii("n"), modifierMask: 0)
    #expect(retry.handled)
  }

  @Test(arguments: RimeBackend.allCases)
  func invalidatePoisonsSubsequentTransactions(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let session = try await env.makeSession()
    await session.invalidate()
    do {
      _ = try session.keyTransaction(keyCode: Key.ascii("a"), modifierMask: 0)
      Issue.record("失效后事务应抛 invalidated")
    } catch let error as RimeSessionError {
      #expect(error == .invalidated)
    }
    // 协调失效后 rebind 不可再获得该会话(引擎内已销毁)。
    let rebound = try await RimeSession.rebind(root: env.root, sessionID: session.sessionID)
    #expect(rebound == nil)
  }
}
