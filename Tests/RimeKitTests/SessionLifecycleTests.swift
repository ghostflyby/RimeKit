import Testing

@testable import RimeKit

/// 会话表语义(参考:librime `flavored_api_test.cc` 的 create/find 会话级断言;
/// Squirrel 每个 InputController 一会话、`find_session` 校验、退出时 `cleanup_all_sessions`)。
///
/// 书写纪律:`RimeSession` 是 `~Copyable` 门面,不可被 `#expect`/`#require` 的
/// autoclosure 捕获——所有观察值先取出为局部值,再进入断言宏。
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
    #expect(schemaID == MinimalRimeData.primarySchemaID)
    #expect(input?.isEmpty != false)
  }

  @Test(arguments: RimeBackend.allCases)
  func facadeRejectsUnknownSessionID(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let ghost = RimeSessionID(rawValue: 0xDEAD_BEEF)
    let restored = try await RimeSession(root: env.root, sessionID: ghost)
    if restored != nil {
      Issue.record("未知会话不应可绑定门面")
    }
  }

  @Test(.disabled("cleanup 是进程级破坏性操作,会连带销毁并行套件的活跃会话;待 remote 后端(每后端独立服务进程)经参数化启用"), arguments: RimeBackend.allCases)
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
