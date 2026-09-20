// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0

import Foundation

/// 会话事务门:保证**同一会话**上多调用组成的事务不被其他事务插队。
///
/// librime 根 actor 串行化的是单次调用,不是调用组;`processKey → commit →
/// status → context` 这样的组若无客户端侧门禁,可被并发事务在 await 处
/// 交错,导致结果错误归属。门以 FIFO 交接所有权:持门事务完成后唤醒
/// 最早排队者(占用不释放,属所有权转移)。
///
/// 阻塞发生在同步包装的调用方线程(见 `RimeSync`);本门内的 await 只
/// 挂起协作线程,不占线程。
final class RimeSessionGate: @unchecked Sendable {
  private final class State: @unchecked Sendable {
    let lock = NSLock()
    var busy = false
    var waiters: [CheckedContinuation<Void, Never>] = []

    /// 快路径立即 resume(直接获得);慢路径入队等待 release 唤醒。
    func acquire(with continuation: CheckedContinuation<Void, Never>) {
      lock.lock()
      defer { lock.unlock() }
      if !busy {
        busy = true
        continuation.resume()
        return
      }
      waiters.append(continuation)
    }

    /// 返回需唤醒的下一等待者(nil = 释放所有权,门空闲)。
    func release() -> CheckedContinuation<Void, Never>? {
      lock.lock()
      defer { lock.unlock() }
      if waiters.isEmpty {
        busy = false
        return nil
      }
      return waiters.removeFirst()  // busy 保持 true:所有权移交
    }
  }

  private let state = State()

  func acquire() async {
    await withCheckedContinuation { state.acquire(with: $0) }
  }

  func release() {
    if let next = state.release() {
      next.resume()
    }
  }
}
