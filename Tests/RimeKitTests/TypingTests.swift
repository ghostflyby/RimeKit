// SPDX-License-Identifier: MPL-2.0
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing

@testable import RimeKit

/// 键入主路径:按键 → 组词 → 候选 → 提交(Squirrel 输入主链路 `process_key`
/// → `get_context`/`get_commit` 的镜像;数据语义由自造最小方案保证确定性)。
/// `RimeSession` 为 `~Copyable`:观察值一律先取出局部值再进断言宏。
@Suite struct TypingTests {
  @Test(arguments: RimeBackend.allCases)
  func typedKeysComposeAndPreview(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let session = try await env.makeSession()

    // 每个字母都被引擎消费(未进入 passthrough)。
    let handled = try await session.typeKeys("nihao")
    #expect(handled == [true, true, true, true, true])

    let input = try await session.input
    let caret = try await session.caretPosition
    let composing = try await session.status?.isComposing
    #expect(input == "nihao")
    #expect(caret == 5)
    #expect(composing == true)

    let context = try await session.context
    #expect(context?.composition.preedit == "nihao")
    #expect(context?.composition.length == 5)
    #expect(context?.composition.cursorPosition == 5)
    #expect(context?.menu.candidates.map(\.text) == MinimalRimeData.nihaoCandidates)
    #expect(context?.menu.highlightedCandidateIndex == 0)
    #expect(context?.commitTextPreview == MinimalRimeData.nihaoCandidates[0])
  }

  @Test(arguments: RimeBackend.allCases)
  func digitSelectKeyCommitsHighlightedCandidate(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let session = try await env.makeSession()
    _ = try await session.typeKeys("nihao")

    let handled = try await session.processKey(Key.ascii("1"), modifierMask: 0)
    #expect(handled == true)

    let commitText = try await session.commitText
    let input = try await session.input
    let composing = try await session.status?.isComposing
    #expect(commitText == MinimalRimeData.nihaoCandidates[0])
    #expect(input?.isEmpty != false)
    #expect(composing == false)
  }

  @Test(arguments: RimeBackend.allCases)
  func selectCandidateByGlobalIndex(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let session = try await env.makeSession()
    _ = try await session.typeKeys("nihao")
    let handled = try await session.selectCandidate(at: 1)
    let commitText = try await session.commitText
    #expect(handled == true)
    #expect(commitText == MinimalRimeData.nihaoCandidates[1])
  }

  @Test(arguments: RimeBackend.allCases)
  func selectCandidateOnCurrentPage(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let session = try await env.makeSession()
    _ = try await session.typeKeys("mmmm")
    let handled = try await session.selectCandidateOnCurrentPage(at: 2)
    let commitText = try await session.commitText
    #expect(handled == true)
    #expect(commitText == MinimalRimeData.mmmmCandidates[2])
  }

  @Test(arguments: RimeBackend.allCases)
  func commitCompositionCommitsHighlighted(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let session = try await env.makeSession()
    _ = try await session.typeKeys("ceshi")
    let handled = try await session.commitComposition()
    let commitText = try await session.commitText
    #expect(handled == true)
    #expect(commitText == MinimalRimeData.ceshiCandidates[0])
  }

  @Test(arguments: RimeBackend.allCases)
  func commitCompositionWithoutCompositionIsRefused(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let session = try await env.makeSession()
    let handled = try await session.commitComposition()
    let commit = try await session.commit
    #expect(handled == false)
    #expect(commit == nil)
  }

  @Test(arguments: RimeBackend.allCases)
  func backspaceShrinksComposition(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let session = try await env.makeSession()
    _ = try await session.typeKeys("nihao")

    let handled = try await session.processKey(Key.backspace, modifierMask: 0)
    #expect(handled == true)

    let input = try await session.input
    let caret = try await session.caretPosition
    #expect(input == "niha")
    #expect(caret == 4)

    // 回缩到无精确词条的码(enable_completion 关闭 → 无候选)时,
    // commit_composition 回退为提交原文。
    let committed = try await session.commitComposition()
    let commitText = try await session.commitText
    #expect(committed == true)
    #expect(commitText == "niha")
  }

  @Test(arguments: RimeBackend.allCases)
  func escapeClearsComposition(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let session = try await env.makeSession()
    _ = try await session.typeKeys("nihao")

    let handled = try await session.processKey(Key.escape, modifierMask: 0)
    #expect(handled == true)

    let input = try await session.input
    let composing = try await session.status?.isComposing
    // 空输入的读值形态:librime 可能返回 "" 或 NULL,两者皆视作"无输入"。
    #expect(input?.isEmpty != false)
    #expect(composing == false)
  }

  @Test(arguments: RimeBackend.allCases)
  func clearCompositionAPI(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let session = try await env.makeSession()
    _ = try await session.typeKeys("ceshi")
    try await session.clearComposition()
    let input = try await session.input
    let context = try await session.context
    #expect(input?.isEmpty != false)
    // get_context 对空组合仍返回空上下文(非 nil):候选为空即"无组合"。
    #expect(context?.menu.candidates.isEmpty != false)
    #expect(context?.composition.preedit.isEmpty != false)
  }

  @Test(arguments: RimeBackend.allCases)
  func asciiModePassesKeysThrough(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let session = try await env.makeSession()
    try await session.setOption("ascii_mode", value: true)

    let option = try await session.option(named: "ascii_mode")
    let asciiMode = try await session.status?.isASCIIMode
    #expect(option == true)
    #expect(asciiMode == true)

    // 西文模式:字母键不被消费(透传给宿主),不产生组合。
    let passthrough = try await session.processKey(Key.ascii("a"), modifierMask: 0)
    let inputInASCII = try await session.input
    #expect(passthrough == false)
    #expect(inputInASCII?.isEmpty != false)

    try await session.setOption("ascii_mode", value: false)
    let handled = try await session.processKey(Key.ascii("a"), modifierMask: 0)
    let input = try await session.input
    #expect(handled == true)
    #expect(input == "a")
    try await session.clearComposition()
  }

  /// 蓝绿会话迁移原语(§4.4):input/caret 快照-恢复。
  /// `Context::set_input/set_caret_pos` 经 update 通知触发重算:光标复位到
  /// 快照位置后,恢复的组合与现场键入等价,可继续选取提交。
  /// 注意:光标停在码内(如 5 字输入的光标 3)会改变分段,选取语义随之变化——
  /// 迁移实现必须把快照光标一并恢复,不能只恢复输入串。
  @Test(arguments: RimeBackend.allCases)
  func inputAndCaretSnapshotRoundTrip(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let session = try await env.makeSession()
    let restored = try await session.set(input: "nihao")
    #expect(restored == true)
    let input = try await session.input
    let caret = try await session.caretPosition
    #expect(input == "nihao")
    #expect(caret == 5)

    // 光标本身可独立读写。
    try await session.set(caretPosition: 3)
    let caretAfterMove = try await session.caretPosition
    #expect(caretAfterMove == 3)

    // 复位到快照位置:组合恢复为可选取状态。
    try await session.set(caretPosition: 5)
    let handled = try await session.selectCandidate(at: 0)
    #expect(handled == true)
    let commitText = try await session.commitText
    #expect(commitText == MinimalRimeData.nihaoCandidates[0])
  }

  @Test(arguments: RimeBackend.allCases)
  func unhandledKeyReturnsFalse(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let session = try await env.makeSession()
    // F12(0xFFC6)无任何部件绑定:未消费即透传。
    let handled = try await session.processKey(0xFFC6, modifierMask: 0)
    let input = try await session.input
    #expect(handled == false)
    #expect(input?.isEmpty != false)
  }
}
