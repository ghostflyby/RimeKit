// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0

import Foundation

/// 同步包装的阻塞执行器:在调用方线程等待 async 操作完成。
///
/// 阻塞落在调用方线程(输入法回调线程,其同步契约本就要求等待),
/// 协作线程池仅挂起不占线程;超时返回后**内部操作继续**(在途引擎调用
/// 不可中断),调用方以 `timedOut` 决定放行/丢弃。
enum RimeSync {
  static func perform<T: Sendable>(
    timeout: Duration,
    operation: @escaping @Sendable () async throws -> T
  ) throws -> T {
    let box = ResultBox<T>()
    let task = Task.detached(priority: .userInitiated) {
      await box.complete(with: Result { try await operation() })
    }
    defer { task.cancel() }
    let seconds =
      Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
    guard box.semaphore.wait(timeout: .now() + seconds) == .success else {
      throw RimeSessionError.timedOut
    }
    return try box.value.get()
  }

  private final class ResultBox<T: Sendable>: @unchecked Sendable {
    let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var stored: Result<T, Error>?

    func complete(with result: Result<T, Error>) {
      lock.lock()
      stored = result
      lock.unlock()
      semaphore.signal()  // stored 先于 signal 写入,唤醒方必读到值
    }

    var value: Result<T, Error> {
      lock.lock()
      defer { lock.unlock() }
      guard let stored else { fatalError("结果未就绪却被唤醒") }
      return stored
    }
  }
}
