// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if canImport(Darwin)
  import Darwin
#endif
#if canImport(Glibc)
  import Glibc
#endif

extension String {
  func toCString() -> UnsafePointer<CChar> {
    UnsafePointer(strdup(self))
  }
}

/// C 字符串表遍历的防御上界:契约上这些表以 NULL 结尾,但实测个别引擎状态
/// (组字标签表)在宿主并发环境下内容被破坏、终止符缺失,无界遍历即 SIGSEGV
/// (String(cString:) 读野指针,预览进程五份崩溃报告同栈)。上界远超
/// page_size 与标签表的实际规模,正常数据不受影响。
private let cStringArrayWalkLimit = 64

extension UnsafeMutablePointer<UnsafePointer<CChar>?> {
  func toStringArray() -> [String] {
    var result: [String] = []
    var index = 0
    while index < cStringArrayWalkLimit, let cString = self[index] {
      result.append(String(cString: cString))
      index += 1
    }
    return result
  }

  func deallocateCStringArray() {
    var index = 0
    while index < cStringArrayWalkLimit, let cString = self[index] {
      cString.deallocate()
      index += 1
    }
    self.deallocate()
  }
}

extension UnsafeMutablePointer<UnsafeMutablePointer<CChar>?> {
  func toStringArray() -> [String] {
    var result: [String] = []
    var index = 0
    while index < cStringArrayWalkLimit, let cString = self[index] {
      result.append(String(cString: cString))
      index += 1
    }
    return result
  }

}

extension [String] {
  func toNullTerminatedCStringArray() -> UnsafeMutablePointer<UnsafePointer<CChar>?> {
    let array = Array(self)
    let count = array.count
    let pointer = UnsafeMutablePointer<UnsafePointer<CChar>?>.allocate(capacity: count + 1)
    for (i, str) in array.enumerated() {
      pointer[i] = UnsafePointer(strdup(str))
    }
    pointer[count] = nil
    return pointer
  }
}
