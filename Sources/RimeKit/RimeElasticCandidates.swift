// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0

import Foundation

/// 弹性模式的取数事务结果:**全量候选**(脱离引擎分页,迭代器枚举)
/// 与引擎高亮的全省下标。
///
/// `globalHighlight = pageNumber × pageSize + highlightedCandidateIndex`,
/// 供消费方以自身窗口(定宽、任意容量)定位引擎高亮;非组字态时 items
/// 为空、globalHighlight 无意义。
public struct RimeElasticCandidates: Sendable {
  public let items: [RimeCandidate]
  public let composing: Bool
  public let globalHighlight: Int
  public let pageSize: Int

  init(items: [RimeCandidate], composing: Bool, globalHighlight: Int, pageSize: Int) {
    self.items = items
    self.composing = composing
    self.globalHighlight = globalHighlight
    self.pageSize = pageSize
  }
}
