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

extension UnsafeMutablePointer<UnsafePointer<CChar>?> {
  func toStringArray() -> [String] {
    var result: [String] = []
    var index = 0
    while let cString = self[index] {
      result.append(String(cString: cString))
      index += 1
    }
    return result
  }

  func deallocateCStringArray() {
    var index = 0
    while let cString = self[index] {
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
    while let cString = self[index] {
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
