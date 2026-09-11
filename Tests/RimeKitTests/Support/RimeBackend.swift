// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

@testable import RimeKit

/// 测试后端:被测根 actor 引用的来源,全部功能测试的参数化维度。
///
/// 两个后端指向**同一个**根 actor 实例(进程内 XPC 连接对的服务端根,
/// 见 `RimeTestRuntime`),区别仅在引用形态:
///
/// - `.inProcess`:本地引用——编译器直连调用,不过线缆;
/// - `.inProcessXPC`:线缆代理——经进程内连接对(匿名 listener + endpoint)的
///   `resolve(id: .root)` 代理,每次调用走完整 XPC 线缆(marshal/unmarshal、
///   typed-throws 错误还原、每通道 FIFO)。写法复制自 SwiftXPC 的
///   `DistributedXPCIntegrationTests.makeConnectionPair`(需 `@testable` 访问
///   `reserveRootID`/`bind`,SwiftPM debug 构建对依赖开启 testability,已实证)。
///
/// 单根不变式(§3.7):librime 是进程级单例,两个后端的调用必须收敛到同一
/// 执行域——否则并行套件经不同根实例并发触达 librime 即 §2.6 数据竞争。
/// "每服务进程一引擎"的多实例语义仍由阶段 3 的 remote 后端承载。
enum RimeBackend: String, CaseIterable, Sendable, CustomStringConvertible {
  case inProcess
  #if os(macOS)
    case inProcessXPC
  #endif

  var description: String { rawValue }
}

/// 测试基建自身的失败(bootstrap 未达可测状态等),detail 携带 librime 侧诊断。
struct RimeTestFailure: Error, CustomStringConvertible {
  let stage: String
  let detail: String

  var description: String { "RimeTestFailure[\(stage)]: \(detail)" }
}
