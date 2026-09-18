// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if os(macOS)
  import Distributed
  import DistributedXPC
  import Foundation

  @available(macOS 15, *)
  extension Rime {
    /// (SwiftXPC 0.6 起)服务托管入口不再由 RimeKit 提供——按典型实践,由宿主输入法自建 `XPCApp`/`XPCServiceDelegate` 入口并 `@main`,托管
    /// `Rime.shared`。客户端侧连接仍走 `connect`。

    /// 连接 launchd on-demand 的 Rime XPC 服务并解析根 actor(消费侧入口)。
    ///
    /// 客户端入口(与宿主自建的 `XPCApp` 入口对称):无需直接 import DistributedXPC。连接具备
    /// 重连语义(named mach service):服务重启后,对返回根 actor 的调用
    /// 透明恢复。
    ///
    /// - Parameters:
    ///   - serviceName: launchd mach service 名,须与服务端一致(由宿主
    ///     自行约定,如 bundle id 派生)。
    ///   - peerCodeSigningRequirement: **内核强制**的代码签名要求,于连接
    ///     激活前安装;服务不满足即被 XPC 丢弃,要求无法安装时抛错
    ///     (fail-closed),从不静默降级为无校验。
    public static func connect(
      toService serviceName: String,
      peerCodeSigningRequirement: String? = nil
    ) throws -> Rime {
      try Self.connectViaXPCRoot(
        toService: serviceName, peerCodeSigningRequirement: peerCodeSigningRequirement)
    }

    /// 泛型形参语境下成员查找只可见协议扩展成员,不会递归命中本体。
    private static func connectViaXPCRoot<A: XPCRootActor>(
      toService serviceName: String,
      peerCodeSigningRequirement: String?
    ) throws -> A {
      try A.connect(
        toService: serviceName,
        peerCodeSigningRequirement: peerCodeSigningRequirement)
    }

  }
#endif
