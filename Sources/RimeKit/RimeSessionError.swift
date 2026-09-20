// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0

/// 同步门面的失败形态。
///
/// - `timedOut`:阻塞包装超过时限返回;**内部操作仍在继续**(无法中断
///   在途的引擎调用),会话门在操作完成后释放,期间后续调用继续排队。
/// - `invalidated`:句柄已经 `invalidate()`(蓝绿切换/重连/显式销毁),
///   消费方应丢弃引用并按当前活跃根重建会话。
public enum RimeSessionError: Error, Equatable {
  case timedOut
  case invalidated
}
