#if os(macOS)
import Distributed
import DistributedXPC

/// 通知回流的宿主侧接收端(§3.5)。
///
/// 宿主在本地构造(捕获既有 `RimeNotificationHandler` 闭包),经
/// `RimeServiceRoot.setNotificationSink(_:)` 把 actor 引用交给服务端;
/// librime 的 C thunk 在维护线程上触发时,服务端立即脱线程转发到
/// `emit`(§3.8 I3:引擎不等待、不重入)。
@available(macOS 15, *)
@XPCService
public distributed actor RimeNotificationSink {
  public typealias ActorSystem = XPCDistributedActorSystem

  private let handler: RimeNotificationHandler

  /// 宿主本地实例化入口(跨 actor 系统注入由调用方决定)。
  public init(
    actorSystem: ActorSystem,
    handler: @escaping RimeNotificationHandler
  ) {
    self.handler = handler
    self.actorSystem = actorSystem
  }

  /// 服务端 → 宿主:转发一条 librime 通知。
  public distributed func emit(
    _ session: RimeSessionID,
    _ type: RimeNotificationType,
    _ value: String
  ) {
    handler(session, type, value)
  }
}

#endif
