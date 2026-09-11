// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import RimeDynamic

#if os(macOS)
  import DistributedXPC
  import Foundation
#endif

extension Rime {
  /// 设置进程/服务引擎的全局通知回调(`nil` = 退订,替换语义)。
  ///
  /// 按引用形态自动分派(§8):
  /// - **本地引用**(macOS 非 XPC / iOS):直接 C 注册——闭包在 librime 回调
  ///   线程上**同步**执行(Squirrel 同型),严禁在闭包内重入引擎(§3.7 规则 b);
  /// - **远程引用**(XPC 代理):自动转换为内部 sink actor 订阅(实现细节,
  ///   不公开),闭包经线缆回流,由 sink actor 序列化,顺序保持。
  ///
  /// librime 为进程全局单 handler(§1.3):重复设置即替换;本地/远程单槽各自独立
  /// (本地 = 进程 C 槽位,远程 = 所连服务进程的 sink 槽位)。
  public nonisolated func setNotificationHandler(
    _ handler: RimeNotificationHandler?
  ) async throws {
    // 本地性判定:语言层无 isRemote(提案评审移除),改用 system 注册表——
    // 服务端 system 能 resolve 到本 actor(本地),客户端代理不能(远程)。
    let isLocal: Bool
    #if os(macOS)
      isLocal = ((try? actorSystem.resolve(id: id, as: Self.self)) ?? nil) != nil
    #else
      isLocal = true  // RimeLocalSystem 无远程形态
    #endif

    if let handler {
      if isLocal {
        RimeGlobalNotificationHook.install(handler)
      } else {
        #if os(macOS)
          try await setNotificationSink(.create(handler))
        #endif
      }
    } else if isLocal {
      RimeGlobalNotificationHook.clear()
    } else {
      #if os(macOS)
        try await setNotificationSink(nil)
      #endif
    }
  }
}

#if os(macOS)
  extension RimeNotificationSink {
    /// 进程级共享宿主 system(匿名监听):sink 每次设置重建,system 常驻复用,
    /// 避免高频设置时的 mach port 开销(§2.4)。
    fileprivate static let sharedSystem = XPCDistributedActorSystem(
      connection: XPCConnection(name: nil))

    fileprivate static func create(
      _ handler: @escaping RimeNotificationHandler
    ) -> RimeNotificationSink {
      RimeNotificationSink(actorSystem: sharedSystem, handler: handler)
    }
  }
#endif
