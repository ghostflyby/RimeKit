// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if os(macOS)
  import Foundation
  import SwiftXPC

  // MARK: - 手写 XPCMarshal 一致性(§3.6)
  //
  // DTO 声明在平台中立的核心区,attached 宏无法跨声明处使用,故手写。
  // 编码一律采用位置式 XPCArray:**字段顺序即线缆布局**,演进遵守 §4.6 additive-only 纪律。

  /// 位置式装箱:按给定顺序把各字段 marshal 进一个 XPCArray。
  private func pack(_ values: any XPCMarshal...) throws(XPCMarshalError) -> XPCObject {
    var items: [XPCObject] = []
    for value in values {
      items.append(try value.marshal())
    }
    return try items.marshal()
  }

  /// 取位置式字段数组并做数量下限校验。
  private func fields(_ object: XPCObject, minimum count: Int) throws(XPCMarshalError)
    -> [XPCObject]
  {
    let array = try Array<XPCObject>.unmarshal(from: object)
    guard array.count >= count else {
      throw XPCMarshalError.outOfBounds(index: array.count, count: count)
    }
    return array
  }

  // MARK: 会话 ID

  extension RimeSessionID: XPCMarshal {
    public func marshal() throws(XPCMarshalError) -> XPCObject {
      try rawValue.marshal()
    }

    public static func unmarshal(from object: XPCObject) throws(XPCMarshalError) -> RimeSessionID {
      RimeSessionID(rawValue: try UInt.unmarshal(from: object))
    }
  }

  // MARK: 句柄(泛型单份一致性,payload 仅 UUID)

  extension ObjectHandle: XPCMarshal {
    public func marshal() throws(XPCMarshalError) -> XPCObject {
      try id.marshal()
    }

    public static func unmarshal(from object: XPCObject) throws(XPCMarshalError) -> ObjectHandle {
      ObjectHandle(id: try UUID.unmarshal(from: object))
    }
  }

  // MARK: 提交 / 状态 / 上下文

  extension RimeCommit: XPCMarshal {
    public func marshal() throws(XPCMarshalError) -> XPCObject {
      try pack(text)
    }

    public static func unmarshal(from object: XPCObject) throws(XPCMarshalError) -> RimeCommit {
      let f = try fields(object, minimum: 1)
      return RimeCommit(text: try String.unmarshal(from: f[0]))
    }
  }

  extension RimeStatus: XPCMarshal {
    public func marshal() throws(XPCMarshalError) -> XPCObject {
      try pack(
        schemaID, schemaName, isDisabled, isComposing, isASCIIMode,
        isFullShape, isSimplified, isTraditional, isASCIIPunctuation)
    }

    public static func unmarshal(from object: XPCObject) throws(XPCMarshalError) -> RimeStatus {
      let f = try fields(object, minimum: 9)
      return RimeStatus(
        schemaID: try String.unmarshal(from: f[0]),
        schemaName: try String.unmarshal(from: f[1]),
        isDisabled: try Bool.unmarshal(from: f[2]),
        isComposing: try Bool.unmarshal(from: f[3]),
        isASCIIMode: try Bool.unmarshal(from: f[4]),
        isFullShape: try Bool.unmarshal(from: f[5]),
        isSimplified: try Bool.unmarshal(from: f[6]),
        isTraditional: try Bool.unmarshal(from: f[7]),
        isASCIIPunctuation: try Bool.unmarshal(from: f[8]))
    }
  }

  extension RimeComposition: XPCMarshal {
    public func marshal() throws(XPCMarshalError) -> XPCObject {
      try pack(length, cursorPosition, selectionStart, selectionEnd, preedit)
    }

    public static func unmarshal(from object: XPCObject) throws(XPCMarshalError) -> RimeComposition
    {
      let f = try fields(object, minimum: 5)
      return RimeComposition(
        length: try Int32.unmarshal(from: f[0]),
        cursorPosition: try Int32.unmarshal(from: f[1]),
        selectionStart: try Int32.unmarshal(from: f[2]),
        selectionEnd: try Int32.unmarshal(from: f[3]),
        preedit: try String.unmarshal(from: f[4]))
    }
  }

  extension RimeCandidate: XPCMarshal {
    public func marshal() throws(XPCMarshalError) -> XPCObject {
      try pack(text, comment)
    }

    public static func unmarshal(from object: XPCObject) throws(XPCMarshalError) -> RimeCandidate {
      let f = try fields(object, minimum: 2)
      return RimeCandidate(
        text: try String.unmarshal(from: f[0]),
        comment: try String.unmarshal(from: f[1]))
    }
  }

  extension RimeMenu: XPCMarshal {
    public func marshal() throws(XPCMarshalError) -> XPCObject {
      try pack(pageSize, pageNumber, isLastPage, highlightedCandidateIndex, candidates, selectKeys)
    }

    public static func unmarshal(from object: XPCObject) throws(XPCMarshalError) -> RimeMenu {
      let f = try fields(object, minimum: 6)
      return RimeMenu(
        pageSize: try Int32.unmarshal(from: f[0]),
        pageNumber: try Int32.unmarshal(from: f[1]),
        isLastPage: try Bool.unmarshal(from: f[2]),
        highlightedCandidateIndex: try Int32.unmarshal(from: f[3]),
        candidates: try [RimeCandidate].unmarshal(from: f[4]),
        selectKeys: try String.unmarshal(from: f[5]))
    }
  }

  extension RimeContext: XPCMarshal {
    public func marshal() throws(XPCMarshalError) -> XPCObject {
      try pack(composition, menu, commitTextPreview, selectLabels)
    }

    public static func unmarshal(from object: XPCObject) throws(XPCMarshalError) -> RimeContext {
      let f = try fields(object, minimum: 4)
      return RimeContext(
        composition: try RimeComposition.unmarshal(from: f[0]),
        menu: try RimeMenu.unmarshal(from: f[1]),
        commitTextPreview: try String.unmarshal(from: f[2]),
        selectLabels: try [String].unmarshal(from: f[3]))
    }
  }

  // MARK: Schema / 配置位置

  extension RimeSchemaListItem: XPCMarshal {
    public func marshal() throws(XPCMarshalError) -> XPCObject {
      try pack(schemaID, name)
    }

    public static func unmarshal(from object: XPCObject) throws(XPCMarshalError)
      -> RimeSchemaListItem
    {
      let f = try fields(object, minimum: 2)
      return RimeSchemaListItem(
        schemaID: try String.unmarshal(from: f[0]),
        name: try String.unmarshal(from: f[1]))
    }
  }

  extension RimeSchemaList: XPCMarshal {
    public func marshal() throws(XPCMarshalError) -> XPCObject {
      try pack(items)
    }

    public static func unmarshal(from object: XPCObject) throws(XPCMarshalError) -> RimeSchemaList {
      let f = try fields(object, minimum: 1)
      return RimeSchemaList(items: try [RimeSchemaListItem].unmarshal(from: f[0]))
    }
  }

  extension RimeConfigLocation: XPCMarshal {
    public func marshal() throws(XPCMarshalError) -> XPCObject {
      try pack(index, key, path)
    }

    public static func unmarshal(from object: XPCObject) throws(XPCMarshalError)
      -> RimeConfigLocation
    {
      let f = try fields(object, minimum: 3)
      return RimeConfigLocation(
        index: try Int32.unmarshal(from: f[0]),
        key: try String?.unmarshal(from: f[1]),
        path: try String?.unmarshal(from: f[2]))
    }
  }

  // MARK: Traits / 日志级别

  extension RimeLogLevel: XPCMarshal {
    public func marshal() throws(XPCMarshalError) -> XPCObject {
      try rawValue.marshal()
    }

    public static func unmarshal(from object: XPCObject) throws(XPCMarshalError) -> RimeLogLevel {
      let raw = try Int32.unmarshal(from: object)
      guard let level = RimeLogLevel(rawValue: raw) else {
        throw XPCMarshalError.unknownEnumCase(String(raw), enumName: "RimeLogLevel")
      }
      return level
    }
  }

  extension RimeTraits: XPCMarshal {
    public func marshal() throws(XPCMarshalError) -> XPCObject {
      try pack(
        sharedDataDir, userDataDir, distributionName, distributionCodeName,
        distributionVersion, appName, modules, minLogLevel,
        logDir, prebuiltDataDir, stagingDir)
    }

    public static func unmarshal(from object: XPCObject) throws(XPCMarshalError) -> RimeTraits {
      let f = try fields(object, minimum: 11)
      return RimeTraits(
        sharedDataDir: try String.unmarshal(from: f[0]),
        userDataDir: try String.unmarshal(from: f[1]),
        distributionName: try String.unmarshal(from: f[2]),
        distributionCodeName: try String.unmarshal(from: f[3]),
        distributionVersion: try String.unmarshal(from: f[4]),
        appName: try String.unmarshal(from: f[5]),
        modules: try [String].unmarshal(from: f[6]),
        minLogLevel: try RimeLogLevel.unmarshal(from: f[7]),
        logDir: try String?.unmarshal(from: f[8]),
        prebuiltDataDir: try String?.unmarshal(from: f[9]),
        stagingDir: try String?.unmarshal(from: f[10]))
    }
  }

  // MARK: 错误(线缆布局:[caseTag, payload...];additive-only)

  extension RimeError: XPCMarshal {
    public func marshal() throws(XPCMarshalError) -> XPCObject {
      switch self {
      case .invalidHandle(let kind, let id):
        let kindTag =
          switch kind {
          case .config: 0
          case .configIterator: 1
          case .candidateIterator: 2
          }
        return try pack(0, kindTag, id.uuidString)
      case .sessionNotFound(let sessionID):
        return try pack(1, sessionID)
      case .engineNotInitialized:
        return try pack(2)
      case .maintenanceMode:
        return try pack(3)
      case .deployFailed(let operation):
        return try pack(4, operation)
      case .invalidArgument(let message):
        return try pack(5, message)
      case .apiUnavailable(let api):
        return try pack(6, api)
      }
    }

    public static func unmarshal(from object: XPCObject) throws(XPCMarshalError) -> RimeError {
      let f = try fields(object, minimum: 1)
      let tag = try Int.unmarshal(from: f[0])
      func payload(_ index: Int) throws(XPCMarshalError) -> XPCObject {
        guard f.count > index else {
          throw XPCMarshalError.outOfBounds(index: f.count, count: index + 1)
        }
        return f[index]
      }
      switch tag {
      case 0:
        let kindTag = try Int.unmarshal(from: payload(1))
        let kind =
          switch kindTag {
          case 0: HandleKind.config
          case 1: HandleKind.configIterator
          case 2: HandleKind.candidateIterator
          default: throw XPCMarshalError.unknownEnumCase(String(kindTag), enumName: "HandleKind")
          }
        guard let id = UUID(uuidString: try String.unmarshal(from: payload(2))) else {
          throw XPCMarshalError.typeMismatch(
            expected: "UUID string", actual: try String.unmarshal(from: payload(2)))
        }
        return .invalidHandle(kind: kind, id: id)
      case 1:
        return .sessionNotFound(try RimeSessionID.unmarshal(from: payload(1)))
      case 2:
        return .engineNotInitialized
      case 3:
        return .maintenanceMode
      case 4:
        return .deployFailed(operation: try String.unmarshal(from: payload(1)))
      case 5:
        return .invalidArgument(try String.unmarshal(from: payload(1)))
      case 6:
        return .apiUnavailable(try String.unmarshal(from: payload(1)))
      default:
        throw XPCMarshalError.unknownEnumCase(String(tag), enumName: "RimeError")
      }
    }
  }

  // MARK: 会话状态 / 翻页方向

  extension RimeState: XPCMarshal {
    public func marshal() throws(XPCMarshalError) -> XPCObject {
      try pack(self == .on ? 0 : 1)
    }

    public static func unmarshal(from object: XPCObject) throws(XPCMarshalError) -> RimeState {
      let f = try fields(object, minimum: 1)
      guard f.count == 1 else { throw XPCMarshalError.outOfBounds(index: f.count, count: 1) }
      switch try Int.unmarshal(from: f[0]) {
      case 0: return .on
      case 1: return .off
      default:
        throw XPCMarshalError.unknownEnumCase(String(f.count), enumName: "RimeState")
      }
    }
  }

  extension RimePageDirection: XPCMarshal {
    public func marshal() throws(XPCMarshalError) -> XPCObject {
      try pack(self == .forward ? 0 : 1)
    }

    public static func unmarshal(from object: XPCObject) throws(XPCMarshalError)
      -> RimePageDirection
    {
      let f = try fields(object, minimum: 1)
      guard f.count == 1 else { throw XPCMarshalError.outOfBounds(index: f.count, count: 1) }
      switch try Int.unmarshal(from: f[0]) {
      case 0: return .forward
      case 1: return .backward
      default:
        throw XPCMarshalError.unknownEnumCase(String(f.count), enumName: "RimePageDirection")
      }
    }
  }

  // MARK: 通知类型

  extension RimeNotificationType: XPCMarshal {
    public func marshal() throws(XPCMarshalError) -> XPCObject {
      switch self {
      case .schema: return try pack(0)
      case .option: return try pack(1)
      case .deploy: return try pack(2)
      case .unknown(let raw): return try pack(3, raw)
      }
    }

    public static func unmarshal(from object: XPCObject) throws(XPCMarshalError)
      -> RimeNotificationType
    {
      let f = try fields(object, minimum: 1)
      switch try Int.unmarshal(from: f[0]) {
      case 0: return .schema
      case 1: return .option
      case 2: return .deploy
      case 3: return .unknown(try String.unmarshal(from: f[1]))
      default:
        throw XPCMarshalError.unknownEnumCase(
          "RimeNotificationType tag", enumName: "RimeNotificationType")
      }
    }
  }

#endif
