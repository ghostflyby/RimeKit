import Foundation
import Synchronization

#if os(macOS)
import DistributedXPC
#endif

/// 通知订阅:闭包输入,按平台自动选择回流路径(§8)。
///
/// - **macOS(XPC 形态)**:`attach(to:)` 在宿主侧自建匿名 actor system 承载
///   内部 sink(实现细节,不公开),经 `setNotificationSink` 过线订阅;通知由
///   sink actor 序列化回流,顺序保持。system 与 sink 的生命周期由本订阅持有。
/// - **iOS/进程内**:直接 C 注册,librime 回调线程上**同步**执行闭包——
///   实现方严禁在闭包内重入引擎(§3.7 规则 b)。
///
/// librime 为进程全局单 handler(§1.3):同进程内多次 `attach` 即替换订阅;
/// remote 形态下每个服务进程各自持一份订阅。订阅可复用:`detach` 后再次
/// `attach` 即重新订阅。
public final class RimeNotificationSubscription: Sendable {
  private let handler: RimeNotificationHandler
  #if os(macOS)
  private let transport = Mutex<SinkTransport?>(nil)
  #endif

  public init(_ handler: @escaping RimeNotificationHandler) {
    self.handler = handler
  }

  /// 订阅 `root` 所在引擎的通知(幂等替换语义)。
  /// 注:untyped throws 为门面风格(与 `RimeSession` 一致);运行时抛出的仍是
  /// `RimeError`——此处不经 typed throws 系 V7 签名漂移的规避写法。
  public func attach(to root: RimeServiceRoot) async throws {
    #if os(macOS)
    let sink = transport.withLock { state in
      if let state { return state.sink }
      let created = SinkTransport(handler: handler)
      state = created
      return created.sink
    }
    try await root.setNotificationSink(sink)
    #else
    RimeGlobalNotificationHook.install(handler)
    #endif
  }

  /// 退订(幂等)。不影响订阅对象的复用。
  public func detach(from root: RimeServiceRoot) async throws {
    #if os(macOS)
    try await root.setNotificationSink(nil)
    #else
    RimeGlobalNotificationHook.clear()
    #endif
  }

  #if os(macOS)
  /// 内部 sink 与其宿主 system(匿名监听,服务端据此回流)的生命周期容器。
  private final class SinkTransport: Sendable {
    let system: XPCDistributedActorSystem
    let sink: RimeNotificationSink

    init(handler: @escaping RimeNotificationHandler) {
      let system = XPCDistributedActorSystem(connection: XPCConnection(name: nil))
      self.system = system
      self.sink = RimeNotificationSink(actorSystem: system, handler: handler)
    }
  }
  #endif
}
