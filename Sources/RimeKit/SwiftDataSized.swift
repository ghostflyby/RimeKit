// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import RimeC

/// 零初始化的 C 结构体统一入口:首字段 `data_size` 之前的区域为元数据,
/// 置零后才是可用载荷;keypath 测量前缀尺寸后整块清零。
protocol CDataSized {
  var dataSize: Int32 { get set }
  init()
}

// 转发属性:C 字段真名是 data_size(不可改),协议面用驼峰。
extension rime_context_t: CDataSized {
  var dataSize: Int32 {
    get { data_size }
    set { data_size = newValue }
  }
}

extension rime_traits_t: CDataSized {
  var dataSize: Int32 {
    get { data_size }
    set { data_size = newValue }
  }
}

extension rime_commit_t: CDataSized {
  var dataSize: Int32 {
    get { data_size }
    set { data_size = newValue }
  }
}

extension rime_status_t: CDataSized {
  var dataSize: Int32 {
    get { data_size }
    set { data_size = newValue }
  }
}

extension rime_module_t: CDataSized {
  var dataSize: Int32 {
    get { data_size }
    set { data_size = newValue }
  }
}

extension CDataSized {

  static func rimeStructInit() -> Self {
    var value = Self()

    withUnsafeMutableBytes(of: &value) { raw in
      raw.bindMemory(to: UInt8.self).update(repeating: 0)
    }

    let prefixSize = MemoryLayout.size(ofValue: value.dataSize)
    value.dataSize = Int32(MemoryLayout<Self>.size - prefixSize)
    return value
  }
}
