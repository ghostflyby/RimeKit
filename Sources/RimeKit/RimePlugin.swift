// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0
//
// 插件模块 API 的二级命名空间。

/// librime 插件模块 API 的二级空间:经 find_module 获取、编译期可选存在
/// (logsink/varpage 等),与 rime_get_api() 直出的自有核心 API(Rime 线缆面)
/// 明确区分。无状态值,经 `Rime.plugin` 可达,各插件的获取方法以扩展挂入。
public struct RimePlugin {
  public init() {}
}

extension Rime {
  /// 插件二级空间。端点为进程级(librime 进程内插件,与实例无关),门面
  /// 不持状态、无隔离需求;serviceWillStart/makeRoot 后、setup 前即可用。
  public nonisolated var plugin: RimePlugin { RimePlugin() }
}
