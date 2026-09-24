// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Distributed
import Foundation

/// 进程内专用分布式 actor 系统(§4.1 iOS/进程内路径)。
///
/// 仅支持本地引用调用:本地引用的方法由编译器直连执行,**不会经过本系统**;
/// 远程机制成员全部为致命占位——它们的存在只为满足协议,一旦触达即为编程错误。
/// 线缆序列化需求由 `RimeLocalWire` 承担(与 macOS 的 XPCMarshal 解耦)。
public struct RimeLocalSystem: DistributedActorSystem {
  public typealias ActorID = RimeLocalID
  public typealias RemoteObject = Never
  public typealias SerializationRequirement = RimeLocalWire
  public typealias InvocationDecoder = RimeLocalDecoder
  public typealias InvocationEncoder = RimeLocalEncoder
  public typealias ResultHandler = RimeLocalResultHandler

  public init() {}

  public func resolve<Act>(id: ActorID, as actorType: Act.Type) throws -> Act?
  where Act: DistributedActor, Act.ID == ActorID {
    nil
  }

  public func assignID<Act>(_ actorType: Act.Type) -> ActorID
  where Act: DistributedActor, Act.ID == ActorID {
    RimeLocalID(raw: 0)
  }

  public func actorReady<Act>(_ actor: Act) where Act: DistributedActor, Act.ID == ActorID {}

  public func resignID(_ id: ActorID) {}

  public func makeInvocationEncoder() -> InvocationEncoder {
    RimeLocalEncoder()
  }

  public func remoteCall<Act, Err, Res>(
    on actor: Act,
    target: RemoteCallTarget,
    invocation: inout InvocationEncoder,
    throwing errorType: Err.Type,
    returning returnType: Res.Type
  ) async throws -> Res
  where Act: DistributedActor, Act.ID == ActorID, Err: Error, Res: SerializationRequirement {
    fatalError("RimeLocalSystem 仅支持本地引用调用,远程路径不应触达")
  }

  public func remoteCallVoid<Act, Err>(
    on actor: Act,
    target: RemoteCallTarget,
    invocation: inout InvocationEncoder,
    throwing errorType: Err.Type
  ) async throws
  where Act: DistributedActor, Act.ID == ActorID, Err: Error {
    fatalError("RimeLocalSystem 仅支持本地引用调用,远程路径不应触达")
  }
}

/// 核心区线缆序列化需求:本地系统的分布式方法出入参必须满足(平台中立)。
public protocol RimeLocalWire {}

/// 本地调用解码器(永不触达)。
public struct RimeLocalDecoder: DistributedTargetInvocationDecoder {
  public typealias SerializationRequirement = RimeLocalWire
  public init() {}

  public mutating func decodeNextArgument<Argument: SerializationRequirement>() throws -> Argument {
    fatalError("RimeLocalSystem 仅支持本地引用调用")
  }

  public func decodeGenericSubstitutions() throws -> [any Any.Type] { [] }

  public func decodeReturnType() throws -> (any Any.Type)? { nil }

  public func decodeErrorType() throws -> Any.Type? { nil }
}

/// 本地调用编码器(永不触达)。
public struct RimeLocalEncoder: DistributedTargetInvocationEncoder {
  public typealias SerializationRequirement = RimeLocalWire
  public init() {}

  public mutating func recordArgument<Value: SerializationRequirement>(
    _ argument: RemoteCallArgument<Value>
  ) throws {}

  public mutating func recordReturnType<Res: SerializationRequirement>(_ resultType: Res.Type)
    throws
  {}

  public mutating func recordErrorType<E: Error>(_ type: E.Type) throws {}

  public mutating func recordGenericSubstitution<T>(_ type: T.Type) throws {}

  public func doneRecording() throws {}
}

/// 本地结果处理器(永不触达)。
public struct RimeLocalResultHandler: DistributedTargetInvocationResultHandler {
  public typealias SerializationRequirement = RimeLocalWire
  public init() {}

  public func onReturn<Success: SerializationRequirement>(value: Success) async throws {
    fatalError("RimeLocalSystem 仅支持本地引用调用")
  }

  public func onReturnVoid() async throws {}

  public func onThrow<Err>(error: Err) async throws where Err: Error {
    fatalError("RimeLocalSystem 仅支持本地引用调用")
  }
}

public struct RimeLocalID: Hashable, Sendable {
  public var raw: UInt
  public init(raw: UInt) { self.raw = raw }
}

// MARK: - 边界类型 RimeLocalWire 一致性(iOS 类型检查;声明式,无运行时行为)

extension Int32: RimeLocalWire {}
extension Double: RimeLocalWire {}
extension Int: RimeLocalWire {}
extension UInt: RimeLocalWire {}
extension Bool: RimeLocalWire {}
extension String: RimeLocalWire {}
extension UUID: RimeLocalWire {}
extension Array: RimeLocalWire where Element: RimeLocalWire {}
extension Optional: RimeLocalWire where Wrapped: RimeLocalWire {}
extension RimeSessionID: RimeLocalWire {}
extension RimeError: RimeLocalWire {}
extension RimeState: RimeLocalWire {}
extension RimePageDirection: RimeLocalWire {}
extension RimeNotificationType: RimeLocalWire {}
extension ObjectHandle: RimeLocalWire {}
extension RimeCommit: RimeLocalWire {}
extension RimeStatus: RimeLocalWire {}
extension RimeComposition: RimeLocalWire {}
extension RimeMenu: RimeLocalWire {}
extension RimeCandidate: RimeLocalWire {}
extension RimeContext: RimeLocalWire {}
extension RimeSchemaListItem: RimeLocalWire {}
extension RimeSchemaList: RimeLocalWire {}
extension RimeConfigLocation: RimeLocalWire {}
extension RimeTraits: RimeLocalWire {}
extension RimeNotificationSink: RimeLocalWire {}
extension RimeKeyTransactionResult: RimeLocalWire {}
extension RimeElasticCandidates: RimeLocalWire {}
