// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0

import Foundation

/// 一次按键事务的完整输出:`processKey` 之后服务侧会话状态的原子快照。
///
/// 由同步门面的分组事务在一次门持有内组装(组内调用对其他事务不可见);
/// `composing == false` 时 `context` 为 nil(无组字即无候选)。
public struct RimeKeyTransactionResult: Sendable {
  /// librime 是否消费了该键(未消费则宿主放行给应用)。
  public let handled: Bool
  /// 待提交文本(nil = 无提交)。
  public let commit: RimeCommit?
  /// 是否在组字态。
  public let composing: Bool
  /// 组字快照(仅组字态非 nil)。
  public let context: RimeContext?

}
