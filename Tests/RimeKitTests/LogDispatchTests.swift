// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0

import Foundation
import Testing
import os

@testable import RimeKit

@Suite(.serialized) struct LogDispatchTests {
  @Test func replacementAndRemovalApplyToSubsequentRecords() {
    let received = OSAllocatedUnfairLock<[String]>(initialState: [])
    defer { RimeLog.set(handler: nil) }
    RimeLog.set { record in received.withLock { $0.append("first:" + record.message) } }
    RimeLog.emit(.info, "a")
    RimeLog.set { record in received.withLock { $0.append("second:" + record.message) } }
    RimeLog.emit(.warning, "b")
    RimeLog.set(handler: nil)
    RimeLog.emit(.error, "ignored")
    #expect(received.withLock { $0 } == ["first:a", "second:b"])
  }

  #if os(macOS)
    @Test func repeatedDispatchKeepsABoundedNativeThreadStack() async {
      await #expect(processExitsWith: .success) {
        exerciseNativeLogThread()
      }
    }
  #endif
}

#if os(macOS)
  private func exerciseNativeLogThread() {
    let received = OSAllocatedUnfairLock<Int>(initialState: 0)
    let done = DispatchSemaphore(value: 0)
    RimeLog.set { _ in received.withLock { $0 += 1 } }
    defer { RimeLog.set(handler: nil) }
    let thread = Thread {
      for _ in 0..<100_000 { RimeLog.emit(.info, "native thread log") }
      done.signal()
    }
    thread.stackSize = 512 * 1024
    thread.start()
    #expect(done.wait(timeout: .now() + 10) == .success)
    #expect(received.withLock { $0 } == 100_000)
  }
#endif
