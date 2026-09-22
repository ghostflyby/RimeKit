// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing

@testable import RimeKit

/// 会话表语义(参考:librime `flavored_api_test.cc` 的 create/find 会话级断言;
/// Squirrel 每个 InputController 一会话、`find_session` 校验、退出时 `cleanup_all_sessions`)。
///
/// 句柄现为 final class(Sendable),含同一性规范表:同键 rebind 返回同一实例。
@Suite(.serialized)
struct SessionLifecycleTests {
  @Test(arguments: RimeBackend.allCases)
  func createSessionYieldsValidID(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let sessionID = try await env.root.createSession()
    #expect(sessionID.rawValue != 0)
    let found = try await env.root.findSession(with: sessionID)
    #expect(found == true)
    _ = try await env.root.destroySession(with: sessionID)
  }

  @Test(arguments: RimeBackend.allCases)
  func unknownSessionIsNotFindable(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let ghost = RimeSessionID(rawValue: 0xDEAD_BEEF)
    let found = try await env.root.findSession(with: ghost)
    #expect(found == false)
  }

  @Test(arguments: RimeBackend.allCases)
  func destroySessionRemovesItFromTable(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let sessionID = try await env.root.createSession()
    let destroyed = try await env.root.destroySession(with: sessionID)
    #expect(destroyed == true)
    let found = try await env.root.findSession(with: sessionID)
    #expect(found == false)
    // 重复销毁:会话已不在表中,成败型 Bool 返回 false 而非错误。
    let destroyedAgain = try await env.root.destroySession(with: sessionID)
    #expect(destroyedAgain == false)
  }

  @Test(arguments: RimeBackend.allCases)
  func sessionsAreIndependent(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let first = try await env.makeSession()
    let second = try await env.makeSession()
    let firstID = first.sessionID
    let secondID = second.sessionID
    #expect(firstID != secondID)

    // 输入状态互不串扰(会话表隔离)。
    _ = try await first.typeKeys("nihao")
    let firstInput = try await first.input
    let secondInput = try await second.input
    let firstComposing = try await first.status?.isComposing
    let secondComposing = try await second.status?.isComposing
    #expect(firstInput == "nihao")
    #expect(secondInput?.isEmpty != false)
    #expect(firstComposing == true)
    #expect(secondComposing == false)
  }

  @Test(arguments: RimeBackend.allCases)
  func facadeBindsExistingSession(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let session = try await env.makeSession()
    let schemaID = try await session.status?.schemaID
    let input = try await session.input
    // 新会话默认方案随进程级最后选择漂移(见 SchemaTests 同名说明),不断言具体值。
    #expect(schemaID?.isEmpty == false)
    #expect(input?.isEmpty != false)
  }

  @Test(arguments: RimeBackend.allCases)
  func rebindReturnsNilForUnknownSessionID(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let ghost = RimeSessionID(rawValue: 0xDEAD_BEEF)
    let restored = try await RimeSession.rebind(root: env.root, sessionID: ghost)
    #expect(restored == nil)
  }

  @Test(arguments: RimeBackend.allCases)
  func rebindReturnsCanonicalInstanceForLiveSession(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let session = try await env.makeSession()
    let rebound = try await RimeSession.rebind(root: env.root, sessionID: session.sessionID)
    // 同键存活句柄:返回同一规范实例,而非新建包装(别名在结构上不可能)。
    #expect(rebound != nil)
    #expect(rebound === session)
  }

  @Test(arguments: RimeBackend.allCases)
  func handleReleaseDoesNotDestroySession(backend: RimeBackend) async throws {
    // 所有权在注册表(强持有):释放消费方引用不影响会话;
    // 销毁只经 invalidate()/destroy() 协调发生。
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let sessionID = try await env.root.createSession()
    var handle: RimeSession? = try await RimeSession.rebind(
      root: env.root, sessionID: sessionID)
    #expect(handle != nil)
    handle = nil
    let found = try await env.root.findSession(with: sessionID)
    #expect(found == true)
    let rebound = try await RimeSession.rebind(root: env.root, sessionID: sessionID)
    #expect(rebound != nil)  // 注册表规范实例仍可取出
  }

  @Test(
    .disabled("cleanup 是进程级破坏性操作,会连带销毁并行套件的活跃会话;待 remote 后端(每后端独立服务进程)经参数化启用"),
    arguments: RimeBackend.allCases)
  func cleanupAllSessionsEmptiesTable(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let sessionID = try await env.root.createSession()
    try await env.root.cleanupAllSessions()
    let found = try await env.root.findSession(with: sessionID)
    #expect(found == false)
  }

  @Test(.disabled("同上:stale 清理对 C API 创建的会话同样是进程级全量删除"), arguments: RimeBackend.allCases)
  func cleanupStaleSessionsDropsUnreferencedSessions(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let sessionID = try await env.root.createSession()
    try await env.root.cleanupStaleSessions()
    let found = try await env.root.findSession(with: sessionID)
    #expect(found == false)
  }
}
