import Distributed

/// 带 `~Copyable` 约束参数的泛型(可拷贝 struct 本身)。
/// 将 `T: ~Copyable` 改为普通约束(如无约束或 `T: Sendable`)即不再崩溃。
public struct NCBox<T: ~Copyable>: Sendable, Wire {}

@available(macOS 13, iOS 16, *)
public distributed actor Mini {
  public typealias ActorSystem = MiniSystem

  public init(actorSystem: ActorSystem) {
    self.actorSystem = actorSystem
  }

  /// 唯一方法:签名提及 `NCBox<Int>`(~Copyable 约束泛型)。
  public distributed func probe() async throws -> NCBox<Int>? {
    nil
  }
}
