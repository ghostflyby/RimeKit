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

/// C 字符串表遍历的防御上界:对"按个数交付"或终止符意外缺失的表,无界
/// 的 NULL 结尾遍历会冲出数组读野指针(String(cString:) 读越界地址即
/// SIGSEGV)。上界远超各表的实际规模,正常数据不受影响;计数已知的表
/// (如 select_labels)应优先按个数读取而非依赖本兜底。
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
