import Testing

@testable import RimeKit

/// 候选面:页式菜单/翻页/高亮/删除与句柄式迭代(D2 修复的守护面;
/// 12 条候选 × page_size 5 → 5/5/2 三页,断言全部确定性)。
/// `RimeSession` 为 `~Copyable`:观察值一律先取出局部值再进断言宏。
@Suite struct CandidateTests {
  let env: RimeTestEnvironment
  init() async throws { env = try await RimeTestEnvironment.bootstrapped() }

  /// 键入 `mmmm` 并返回会话(12 候选场景的公共前奏)。
  /// 元组不可携带 `~Copyable`,故只返回会话,上下文由调用方自取。
  private func sessionTypingPagingCode() async throws -> RimeSession {
    let session = try await env.makeSession()
    _ = try await session.typeKeys("mmmm")
    return session
  }

  @Test func firstPageLayoutAndOrder() async throws {
    let session = try await sessionTypingPagingCode()
    let context = try await session.context
    let menu = try await #require(context?.menu)
    #expect(menu.pageSize == MinimalRimeData.pageSize)
    #expect(menu.pageNumber == 0)
    #expect(menu.isLastPage == false)
    #expect(menu.highlightedCandidateIndex == 0)
    #expect(menu.candidates.map(\.text) == Array(MinimalRimeData.mmmmCandidates.prefix(5)))
    // 注:menu.select_keys 在 table 方案下报告空串,但数字选择键仍然生效
    // (selector 用内建缺省 1234567890),故不对此字段强断言。
  }

  @Test func pagingViaPageKeys() async throws {
    // 1.16.1 的 change_page C API 不移动页(实测恒 false);真实前端(Squirrel)以
    // Page_Down/Page_Up 键翻页(navigator 消费 X11 keysym),测试同型驱动。
    let session = try await sessionTypingPagingCode()

    let firstStep = try await session.processKey(Key.pageDown, modifierMask: 0)
    #expect(firstStep == true)
    var context = try await session.context
    var menu = try await #require(context?.menu)
    #expect(menu.pageNumber == 1)
    #expect(menu.candidates.map(\.text) == Array(MinimalRimeData.mmmmCandidates[5..<10]))
    #expect(menu.isLastPage == false)

    let secondStep = try await session.processKey(Key.pageDown, modifierMask: 0)
    #expect(secondStep == true)
    context = try await session.context
    menu = try await #require(context?.menu)
    #expect(menu.pageNumber == 2)
    #expect(menu.isLastPage == true)
    #expect(menu.candidates.map(\.text) == Array(MinimalRimeData.mmmmCandidates.suffix(2)))

    // 末页再前进:停留末页。
    let overshoot = try await session.processKey(Key.pageDown, modifierMask: 0)
    #expect(overshoot == true)
    context = try await session.context
    menu = try await #require(context?.menu)
    #expect(menu.pageNumber == 2)

    let backward = try await session.processKey(Key.pageUp, modifierMask: 0)
    #expect(backward == true)
    context = try await session.context
    menu = try await #require(context?.menu)
    #expect(menu.pageNumber == 1)
  }

  @Test func highlightAPI() async throws {
    let session = try await sessionTypingPagingCode()

    let highlighted = try await session.highlightCandidate(at: 3)
    var context = try await session.context
    var menu = try await #require(context?.menu)
    #expect(highlighted == true)
    #expect(menu.highlightedCandidateIndex == 3)

    let highlightedOnPage = try await session.highlightCandidateOnCurrentPage(at: 1)
    context = try await session.context
    menu = try await #require(context?.menu)
    #expect(highlightedOnPage == true)
    #expect(menu.highlightedCandidateIndex == 1)
  }

  @Test func globalSelectAcrossPages() async throws {
    let session = try await sessionTypingPagingCode()
    // 全局第 12 候选(末页最后一个),不经翻页直接全局选取。
    let handled = try await session.selectCandidate(at: 11)
    let commitText = try await session.commitText
    #expect(handled == true)
    #expect(commitText == MinimalRimeData.mmmmCandidates[11])
  }

  @Test(.disabled("delete_candidate 在无用户词典的夹具下返回 true 但不重排候选表(语义依赖 user_dict);待 remote 阶段带用户词典环境再验证"))
  func removeCandidateReflowsList() async throws {
    let session = try await env.makeSession()
    _ = try await session.typeKeys("nihao")

    let removed = try await session.removeCandidate(at: 0)
    #expect(removed == true)
    let texts = try await session.candidateTexts
    #expect(texts == Array(MinimalRimeData.nihaoCandidates.dropFirst()))

    // 删后列表仍可选取提交。
    let handled = try await session.selectCandidate(at: 0)
    let commitText = try await session.commitText
    #expect(handled == true)
    #expect(commitText == MinimalRimeData.nihaoCandidates[1])
  }

  @Test func handleIteratorWalksAllCandidates() async throws {
    let session = try await sessionTypingPagingCode()
    let texts = try await collectAllCandidates(from: env.root, session: session.sessionID)
    #expect(texts == MinimalRimeData.mmmmCandidates)
  }

  @Test func candidateListFromIndex() async throws {
    let session = try await sessionTypingPagingCode()
    let iterator = try await env.root.candidateList(fromIndex: 10, for: session.sessionID)
    let unwrapped = try await #require(iterator)
    var texts: [String] = []
    while let candidate = try await env.root.advanceCandidateIterator(unwrapped) {
      texts.append(candidate.text)
    }
    try await env.root.endCandidateIterator(unwrapped)
    #expect(texts == Array(MinimalRimeData.mmmmCandidates.suffix(2)))
  }

  @Test func advanceForeignCandidateIteratorThrows() async throws {
    // D4 纪律:外来/陈旧句柄抛 invalidHandle,而非强解包崩溃。
    let foreign = ObjectHandle<RimeCandidate>()
    await #expect(
      throws: RimeError.invalidHandle(kind: .candidateIterator, id: foreign.id)
    ) { try await env.root.advanceCandidateIterator(foreign) }
  }
}
