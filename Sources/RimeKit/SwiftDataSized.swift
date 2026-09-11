// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import RimeDynamic

protocol CDataSized {
  var data_size: Int32 { get set }
  init()
}

extension rime_context_t_stdbool: CDataSized {}
extension rime_traits_t: CDataSized {}
extension rime_commit_t: CDataSized {}
extension rime_status_t_stdbool: CDataSized {}
extension rime_module_t: CDataSized {}

extension CDataSized {

  static func rimeStructInit() -> Self {
    var value = Self()

    withUnsafeMutableBytes(of: &value) { raw in
      raw.bindMemory(to: UInt8.self).update(repeating: 0)
    }

    let prefixSize = MemoryLayout.size(ofValue: \Self.data_size)
    value.data_size = Int32(MemoryLayout<Self>.size - prefixSize)
    return value
  }
}
