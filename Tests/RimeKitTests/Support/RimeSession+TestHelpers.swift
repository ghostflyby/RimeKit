import Foundation

@testable import RimeKit

/// 测试用会话小步进(逐字符按键),各套件复用。
extension RimeSession {
  /// 逐字符键入可打印 ASCII 文本,返回每次 `processKey` 的 handled 结果。
  func typeKeys(_ text: String) async throws -> [Bool] {
    var handled: [Bool] = []
    handled.reserveCapacity(text.utf8.count)
    for character in text {
      handled.append(try await processKey(Key.ascii(character), modifierMask: 0))
    }
    return handled
  }

  /// 当前候选文本快照(经页式菜单)。
  var candidateTexts: [String] {
    get async throws {
      try await context?.menu.candidates.map(\.text) ?? []
    }
  }
}

/// 句柄式候选迭代:从 `beginCandidates` 走到穷尽,收尾 `endCandidateIterator`。
///
/// 自由函数而非 `RimeServiceRoot` 扩展:根是"潜在远程"的 distributed actor,
/// 非 distributed 成员不可经其引用调用(分布式隔离规则)。
func collectAllCandidates(
  from root: RimeServiceRoot, session: RimeSessionID
) async throws -> [String] {
  let iterator = try await root.beginCandidates(for: session)
  var texts: [String] = []
  while let candidate = try await root.advanceCandidateIterator(iterator) {
    texts.append(candidate.text)
  }
  try await root.endCandidateIterator(iterator)
  return texts
}
