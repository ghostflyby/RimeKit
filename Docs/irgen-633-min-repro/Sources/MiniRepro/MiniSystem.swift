import Distributed

/// 进程内占位 actor system:远程路径全部 fatalError,只为满足协议。
public protocol Wire {}

public struct MiniSystem: DistributedActorSystem {
  public typealias ActorID = MiniID
  public typealias RemoteObject = Never
  public typealias SerializationRequirement = Wire
  public typealias InvocationDecoder = MiniDecoder
  public typealias InvocationEncoder = MiniEncoder
  public typealias ResultHandler = MiniResultHandler

  public init() {}

  public func resolve<Act>(id: ActorID, as actorType: Act.Type) throws -> Act?
  where Act: DistributedActor, Act.ID == ActorID { nil }

  public func assignID<Act>(_ actorType: Act.Type) -> ActorID
  where Act: DistributedActor, Act.ID == ActorID { MiniID(raw: 0) }

  public func actorReady<Act>(_ actor: Act) where Act: DistributedActor, Act.ID == ActorID {}

  public func resignID(_ id: ActorID) {}

  public func makeInvocationEncoder() -> InvocationEncoder { MiniEncoder() }

  public func remoteCall<Act, Err, Res>(
    on actor: Act, target: RemoteCallTarget, invocation: inout InvocationEncoder,
    throwing errorType: Err.Type, returning returnType: Res.Type
  ) async throws -> Res
  where Act: DistributedActor, Act.ID == ActorID, Err: Error, Res: SerializationRequirement {
    fatalError("remote path unsupported")
  }

  public func remoteCallVoid<Act, Err>(
    on actor: Act, target: RemoteCallTarget, invocation: inout InvocationEncoder,
    throwing errorType: Err.Type
  ) async throws
  where Act: DistributedActor, Act.ID == ActorID, Err: Error {
    fatalError("remote path unsupported")
  }
}

public struct MiniID: Hashable, Sendable {
  public var raw: UInt
  public init(raw: UInt) { self.raw = raw }
}

public struct MiniDecoder: DistributedTargetInvocationDecoder {
  public typealias SerializationRequirement = Wire
  public init() {}
  public mutating func decodeNextArgument<Argument: SerializationRequirement>() throws -> Argument {
    fatalError("remote path unsupported")
  }
  public func decodeGenericSubstitutions() throws -> [any Any.Type] { [] }
  public func decodeReturnType() throws -> (any Any.Type)? { nil }
  public func decodeErrorType() throws -> Any.Type? { nil }
}

public struct MiniEncoder: DistributedTargetInvocationEncoder {
  public typealias SerializationRequirement = Wire
  public init() {}
  public mutating func recordArgument<Value: SerializationRequirement>(
    _ argument: RemoteCallArgument<Value>) throws {}
  public mutating func recordReturnType<Res: SerializationRequirement>(_ resultType: Res.Type)
    throws {}
  public mutating func recordErrorType<E: Error>(_ type: E.Type) throws {}
  public mutating func recordGenericSubstitution<T>(_ type: T.Type) throws {}
  public func doneRecording() throws {}
}

public struct MiniResultHandler: DistributedTargetInvocationResultHandler {
  public typealias SerializationRequirement = Wire
  public init() {}
  public func onReturn<Success: SerializationRequirement>(value: Success) async throws {
    fatalError("remote path unsupported")
  }
  public func onReturnVoid() async throws {}
  public func onThrow<Err>(error: Err) async throws where Err: Error {
    fatalError("remote path unsupported")
  }
}

extension Int: Wire {}
extension Optional: Wire where Wrapped: Wire {}
