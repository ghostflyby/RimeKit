// SPDX-License-Identifier: MPL-2.0
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Distributed
#if os(macOS)
import DistributedXPC
#endif

/// 通知回流的宿主侧接收端(§3.5)。**内部实现细节**:外部经
/// `Rime.setNotificationHandler` 以闭包订阅,不直接触碰本类型与
/// `setNotificationSink`。
///
/// 宿主在本地构造(捕获既有 `RimeNotificationHandler` 闭包),经
/// `Rime.setNotificationSink(_:)` 把 actor 引用交给服务端;
/// librime 的 C thunk 在维护线程上触发时,服务端立即脱线程转发到
/// `emit`(§3.8 I3:引擎不等待、不重入)。
///
/// 平台差异仅在 ActorSystem(macOS=XPC 可跨进程回流;iOS=进程内
/// `RimeLocalSystem`)。**声明体不得包 `#if`**:`@XPCService` 宏只扫描
/// 直接成员,`#if` 内的方法不进元数据白表(实证),平台分支只允许出现在
/// 属性与属性包装层。
#if os(macOS)
@XPCService
#endif
distributed actor RimeNotificationSink {
  #if os(macOS)
  public typealias ActorSystem = XPCDistributedActorSystem
  #else
  public typealias ActorSystem = RimeLocalSystem
  #endif

  private let handler: RimeNotificationHandler

  init(
    actorSystem: ActorSystem,
    handler: @escaping RimeNotificationHandler
  ) {
    self.handler = handler
    self.actorSystem = actorSystem
  }

  /// 服务端 → 宿主:转发一条 librime 通知。
  distributed func emit(
    _ session: RimeSessionID,
    _ type: RimeNotificationType,
    _ value: String
  ) {
    handler(session, type, value)
  }
}
