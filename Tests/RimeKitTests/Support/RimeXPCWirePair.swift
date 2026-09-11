// SPDX-License-Identifier: MPL-2.0
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if os(macOS)
import Dispatch
import DistributedXPC
import Foundation
import Synchronization
import SwiftXPC
import XPC

@testable import DistributedXPC
@testable import SwiftXPC
@testable import RimeKit

/// 进程内 XPC 连接对——写法复制自 SwiftXPC `DistributedXPCIntegrationTests` 的
/// `makeConnectionPair`(TN3113:`xpc_connection_create(NULL)` + endpoint):
///
/// 1. 匿名 listener(`XPCConnection(name: nil)`)在 accept 回调里为每个 peer 建
  ///    服务端 system,`reserveRootID()` 后创建根 `Rime` 并 `bind`;
/// 2. listener endpoint 经 marshal 交给 client 连接(`XPCConnection.unmarshal`);
/// 3. client `sendAndForget` 空消息触发 accept 握手(信号量等待);
/// 4. `resolve(id: .root, using: clientSystem)` 得到走线缆的根代理。
///
/// `reserveRootID`/`bind`/`xpc_object` 为 SwiftXPC internal/package 成员,经
/// `@testable` 访问(SwiftPM debug 构建对依赖开启 testability);这把进程内
/// 连接对正是阶段 3 蓝绿服务与客户端同进程联调的最小复现。
struct RimeXPCWirePair: Sendable {
  let listener: XPCConnection
  let server: XPCConnection
  let client: XPCConnection
  let serverSystem: XPCDistributedActorSystem
  let clientSystem: XPCDistributedActorSystem
  /// 连接对服务端创建的根:进程唯一 librime 执行域。
    let servedRoot: Rime

  private struct AcceptedPeer: Sendable {
    let server: XPCConnection
    let system: XPCDistributedActorSystem
      let root: Rime
  }

  static func make() throws -> RimeXPCWirePair {
    struct PeerAcceptTimedOut: Error {}

    let listener = XPCConnection(name: nil)
    let acceptedPeer = Mutex<AcceptedPeer?>(nil)
    let accepted = DispatchSemaphore(value: 0)

    listener.setEventHandler { object in
      guard xpc_get_type(object.xpc_object) == XPC_TYPE_CONNECTION else { return }
      let server = XPCConnection(xpc_object: object.xpc_object)
      let serverSystem = XPCDistributedActorSystem(connection: server)
      serverSystem.reserveRootID()
        let root = Rime(actorSystem: serverSystem)
      serverSystem.bind(server, to: root)
      acceptedPeer.withLock {
        $0 = AcceptedPeer(server: server, system: serverSystem, root: root)
      }
      server.activate()
      accepted.signal()
    }
    listener.activate()

    let endpoint = try listener.marshal()
    let client = try XPCConnection.unmarshal(from: endpoint)
    let clientSystem = XPCDistributedActorSystem(connection: client)
    client.activate()
    client.sendAndForget(message: XPCDictionary())

    guard accepted.wait(timeout: .now() + 5) == .success,
      let peer = acceptedPeer.withLock({ $0 })
    else {
      throw RimeTestFailure(stage: "xpc-pair", detail: "进程内连接对 accept 超时(5s)")
    }

    return RimeXPCWirePair(
      listener: listener,
      server: peer.server,
      client: client,
      serverSystem: peer.system,
      clientSystem: clientSystem,
      servedRoot: peer.root)
  }

  /// 客户端侧根代理:与 `servedRoot` 同一 actor,但每次调用走完整线缆。
    func resolveProxy() throws -> Rime {
      try Rime.resolve(id: .root, using: clientSystem)
  }
}
#endif
