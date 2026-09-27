// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0

import Testing

@testable import RimeKit

/// varpage 端到端:推表 → 首翻页 → 卷轴位与高亮落点。
/// 首翻页(前向)答原位:引擎 offset carry 落点 = 原高亮(真正的不翻页,
/// 仅展开);二次翻页(open 后)照常答目标行,落点 = 目标行首 + 原偏移。
@Suite struct VarPageTurnTests {
  @Test(arguments: RimeBackend.allCases)
  func firstTurnOpensAndKeepsHighlight(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let session = try await env.makeSession()
    try await session.setOption("_linear", value: true)
    _ = try await session.typeKeys("mmmm")

    let before = try await session.context?.commitTextPreview
    // 页界表:4 行 × 3 格,瓦片覆盖全部 12 候选。
    try await session.updateVarPageTiles(starts: [0, 3, 6, 9], total: 12)

    let handled = try await session.processKey(Key.pageDown, modifierMask: 0)
    let open = try await session.varPageIsOpen()
    let preview = try await session.context?.commitTextPreview

    #expect(handled == true)
    // 首翻页只展开、候选不动:原位答 → 落点 = 原高亮。
    #expect(open == true)
    #expect(preview == before)
  }

  @Test(arguments: RimeBackend.allCases)
  func secondTurnMovesToNextRow(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let session = try await env.makeSession()
    try await session.setOption("_linear", value: true)
    _ = try await session.typeKeys("mmmm")
    try await session.updateVarPageTiles(starts: [0, 3, 6, 9], total: 12)
    _ = try await session.processKey(Key.pageDown, modifierMask: 0)

    // 展开态二次翻页:答目标行,落点 = 第二行首(offset 0)。
    let handled = try await session.processKey(Key.pageDown, modifierMask: 0)
    let preview = try await session.context?.commitTextPreview
    #expect(handled == true)
    #expect(preview == MinimalRimeData.mmmmCandidates[3])
  }

  @Test(arguments: RimeBackend.allCases)
  func turnWithoutTilesFallsBack(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let session = try await env.makeSession()
    try await session.setOption("_linear", value: true)
    _ = try await session.typeKeys("mmmm")

    let handled = try await session.processKey(Key.pageDown, modifierMask: 0)
    let open = try await session.varPageIsOpen()

    // 无表:resolver 恒答未知,内置算术接管,卷轴位不置。
    #expect(handled == true)
    #expect(open == false)
  }

  @Test(arguments: RimeBackend.allCases)
  func candidatesPageBatchAssembly(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let session = try await env.makeSession()
    _ = try await session.typeKeys("mmmm")

    // 一次往返取一批:满批/短批/越界。
    let root = env.root
    let full = try await root.candidatesPage(
      fromIndex: 0, count: 5, for: session.sessionID)
    #expect(full.map(\.text) == Array(MinimalRimeData.mmmmCandidates.prefix(5)))
    let short = try await root.candidatesPage(
      fromIndex: 9, count: 5, for: session.sessionID)
    #expect(short.map(\.text) == Array(MinimalRimeData.mmmmCandidates.suffix(3)))
    let beyond = try await root.candidatesPage(
      fromIndex: 12, count: 5, for: session.sessionID)
    #expect(beyond.isEmpty)
  }
}

/// 页答案断言(optional 命名元组无提升 ==,经 helper 展开比较)。
private func expectPage(
  _ actual: (start: Int, length: Int)?, _ start: Int, _ length: Int,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  #expect(actual?.start == start && actual?.length == length, sourceLocation: sourceLocation)
}

/// 状态机单元序列(@testable):翻页识别、原位答、残留清除。
@Suite struct VarPageTileBoxTests {
  @Test func firstForwardTurnAnswersOriginAndOpens() {
    let box = VarPageTileBox(sessionID: RimeSessionID(rawValue: 1))
    box.update(starts: [0, 3, 6, 9], total: 12)
    // 第一段(选中页)。
    expectPage(box.page(of: 0), 0, 3)
    // 第二段(边界 probe):首翻页前向答原位,置卷轴位。
    expectPage(box.page(of: 3), 0, 3)
    #expect(box.isOpen() == true)
    // open 后照常答目标行。
    expectPage(box.page(of: 0), 0, 3)
    expectPage(box.page(of: 3), 3, 3)
  }

  @Test func firstBackwardTurnAnswersTargetRowAndOpens() {
    let box = VarPageTileBox(sessionID: RimeSessionID(rawValue: 1))
    box.update(starts: [0, 3, 6, 9], total: 12)
    expectPage(box.page(of: 6), 6, 3)
    // 后向首翻页:答目标行(不原位),置卷轴位。
    expectPage(box.page(of: 2), 0, 3)
    #expect(box.isOpen() == true)
  }

  @Test func beginTurnDetectionClearsStaleResidue() {
    let box = VarPageTileBox(sessionID: RimeSessionID(rawValue: 1))
    box.update(starts: [0, 3, 6, 9], total: 12)
    // 跨事务残留:单次查询(如选键)留下的行首。
    _ = box.page(of: 6)
    box.beginTurnDetection()
    // 残留清除后,新事务的单次查询不得误判为翻页第二段。
    expectPage(box.page(of: 0), 0, 3)
    #expect(box.isOpen() == false)
    // 同事务内的二段查询仍正确识别。
    expectPage(box.page(of: 3), 0, 3)
    #expect(box.isOpen() == true)
  }

  @Test func settleClassifiesTurnActions() {
    let box = VarPageTileBox(sessionID: RimeSessionID(rawValue: 1))
    box.update(starts: [0, 3, 6, 9], total: 12)
    // 前向二段 → forwardTurn。
    box.beginTurnDetection()
    _ = box.page(of: 0)
    _ = box.page(of: 3)
    box.settleTurn()
    #expect(box.lastTurnAction() == VarPageTurnAction.forwardTurn.rawValue)
    // 后向二段 → backwardTurn。
    box.beginTurnDetection()
    _ = box.page(of: 6)
    _ = box.page(of: 2)
    box.settleTurn()
    #expect(box.lastTurnAction() == VarPageTurnAction.backwardTurn.rawValue)
    // 单段查询落首行 → singleQueryAtFirstRow(行首后向翻页/行首选键)。
    box.beginTurnDetection()
    _ = box.page(of: 0)
    box.settleTurn()
    #expect(box.lastTurnAction() == VarPageTurnAction.singleQueryAtFirstRow.rawValue)
    // 单段查询落他行 → singleQueryElsewhere。
    box.beginTurnDetection()
    _ = box.page(of: 7)
    box.settleTurn()
    #expect(box.lastTurnAction() == VarPageTurnAction.singleQueryElsewhere.rawValue)
    // 无页查询 → none。
    box.beginTurnDetection()
    box.settleTurn()
    #expect(box.lastTurnAction() == VarPageTurnAction.none.rawValue)
  }

  @Test func outOfTableIndexAnswersUnknown() {
    let box = VarPageTileBox(sessionID: RimeSessionID(rawValue: 1))
    box.update(starts: [0, 3], total: 6)
    #expect(box.page(of: 6) == nil)
    #expect(box.isOpen() == false)
  }
}
