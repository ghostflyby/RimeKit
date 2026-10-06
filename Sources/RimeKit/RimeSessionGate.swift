// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0

import Foundation
import os

/// 会话事务门:保证**同一会话**上多调用组成的事务不被其他事务插队。
///
/// librime 根 actor 串行化的是单次调用,不是调用组;`processKey → commit →
/// status → context` 这样的组若无客户端侧门禁,可被并发事务在 await 处
/// 交错,导致结果错误归属。门以 FIFO 交接所有权:持门事务完成后唤醒
/// 最早排队者(占用不释放,属所有权转移)。
///
/// 阻塞发生在同步包装的调用方线程(见 `RimeSync`);本门内的 await 只
/// 挂起协作线程,不占线程。
final class RimeSessionGate: Sendable {
  private struct State: Sendable {
    var busy = false
    var waiters: [CheckedContinuation<Void, Never>] = []
  }

  private let state = OSAllocatedUnfairLock(initialState: State())

  func acquire() async {
    await withCheckedContinuation { continuation in
      state.withLock { state in
        if state.busy {
          state.waiters.append(continuation)
          return
        }
        state.busy = true
        // 置位与 resume 必须在同一临界区内:若把 resume 移到锁外,解锁到
        // resume 之间前持有者的 release 会看到空等待队列而置 busy=false,
        // 第三方可抢先获得,形成双持有(慢路径 resume 在锁外是安全的——
        // busy 保持 true 挡住新来者)。
        continuation.resume()
      }
    }
  }

  func release() {
    let next = state.withLock { state -> CheckedContinuation<Void, Never>? in
      if state.waiters.isEmpty {
        state.busy = false
        return nil
      }
      return state.waiters.removeFirst()  // busy 保持 true:所有权移交
    }
    next?.resume()
  }
}
