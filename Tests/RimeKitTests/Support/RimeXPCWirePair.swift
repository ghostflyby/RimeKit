// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if os(macOS)
  import DistributedXPC
  import Foundation

  @testable import RimeKit

  /// 进程内 XPC 连接对:生产 `XPCActorService` 跑在匿名 listener 上,客户端用
  /// 生产 `XPCRootConnection` 拨号接线(TN3113:endpoint 直连,不落 launchd):
  ///
  /// 1. `XPCActorService(Rime.self)` 装配服务端:预留 `.root` 身份并构造根
  ///    (进程唯一 librime 执行域);
  /// 2. `listen()` 开匿名 listener,把接受的 peer 绑到该根;
  /// 3. endpoint 交客户端通道(`XPCChannelTransport.cConnection.channel(dialing:)`),
  ///    `XPCRootConnection.connect(using:)` 激活并解析出线缆代理。
  ///
  /// 全程公开 API,与 launchd 具名服务的差别仅在拨号目标(本 listener endpoint);
  /// 这把进程内连接对正是阶段 3 蓝绿服务与客户端同进程联调的最小复现。
  struct RimeXPCWirePair: Sendable {
    /// 服务端装配:持有根 actor 与宿主。
    let service: XPCActorService<Rime>
    /// 匿名 listener(服务端接入点)。
    let acceptor: XPCChannelAcceptor
    /// 客户端句柄:root 为线缆代理,events/close 与真实服务同型。
    let client: XPCRootConnection<Rime>

    /// 连接对服务端创建的根:进程唯一 librime 执行域。
    var servedRoot: Rime { service.root }

    static func make() throws -> RimeXPCWirePair {
      let service = XPCActorService(Rime.self)
      let acceptor = try service.listen()
      let clientChannel = try XPCChannelTransport.cConnection.channel(
        dialing: acceptor.wireEndpoint)
      let client = try XPCRootConnection<Rime>.connect(using: clientChannel)
      return RimeXPCWirePair(service: service, acceptor: acceptor, client: client)
    }

    /// 客户端侧根代理:与 `servedRoot` 同一 actor,但每次调用走完整线缆。
    func resolveProxy() -> Rime { client.root }
  }
#endif
