// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import RimeC

typealias RimeContextRaw = RimeC.rime_context_t_stdbool

public struct RimeContext: Sendable, Codable {
  public let composition: RimeComposition
  public let menu: RimeMenu
  public let commitTextPreview: String
  public let selectLabels: [String]
}

extension RimeContext {
  fileprivate init(rawValue: RimeContextRaw) {
    composition = RimeComposition(rawValue.composition)
    menu = RimeMenu(rawValue.menu)
    // 空组合时下列 char* 字段为 NULL,统一按空串处理(不得强解包)。
    commitTextPreview = rawValue.commit_text_preview.map { String(cString: $0) } ?? ""
    // 空组合时 librime 不分配标签数组(nil),按空表处理。
    selectLabels = rawValue.select_labels?.toStringArray() ?? []
  }
}

extension RimeSession {
  public var context: RimeContext? {
    get async throws {
      try await root.context(for: sessionID)
    }
  }
}

extension Rime {
  func engineContext(for sessionID: RimeSessionID) throws(RimeError) -> RimeContext? {
    var context = RimeContextRaw.rimeStructInit()
    defer { _ = rimeApi.free_context(&context) }
    guard rimeApi.get_context(sessionID.rawValue, &context) else {
      return nil
    }
    return RimeContext(rawValue: context)
  }
}

public struct RimeComposition: Sendable, Codable {
  public let length: Int32
  public let cursorPosition: Int32
  public let selectionStart: Int32
  public let selectionEnd: Int32
  public let preedit: String
}

extension RimeComposition {
  fileprivate init(_ cStruct: RimeC.RimeComposition) {
    length = cStruct.length
    cursorPosition = cStruct.cursor_pos
    selectionStart = cStruct.sel_start
    selectionEnd = cStruct.sel_end
    preedit = cStruct.preedit.map { String(cString: $0) } ?? ""
  }
}

public struct RimeCandidate: Sendable, Codable {
  public let text: String
  public let comment: String
}

extension RimeCandidate {
  fileprivate init(_ cStruct: RimeC.RimeCandidate) {
    text = cStruct.text.map { String(cString: $0) } ?? ""
    comment = cStruct.comment.map { String(cString: $0) } ?? ""
  }
}

public struct RimeMenu: Sendable, Codable {
  public let pageSize: Int32
  public let pageNumber: Int32
  public let isLastPage: Bool
  public let highlightedCandidateIndex: Int32
  public let candidates: [RimeCandidate]
  public let selectKeys: String
}

extension RimeMenu {
  fileprivate init(_ cStruct: RimeC.RimeMenu) {
    pageSize = cStruct.page_size
    pageNumber = cStruct.page_no
    isLastPage = cStruct.is_last_page
    highlightedCandidateIndex = cStruct.highlighted_candidate_index
    selectKeys = cStruct.select_keys.map { String(cString: $0) } ?? ""
    let numCandidates = Int(cStruct.num_candidates)
    // 无候选时 librime 不分配候选数组(指针为 nil):按空表处理,不得强解包
    // ——空组合上读 context 即崩,已由功能测试实证。
    candidates =
      cStruct.candidates.map { pointer in
        UnsafeBufferPointer(start: pointer, count: numCandidates).map { RimeCandidate($0) }
      } ?? []
  }
}

extension Rime {
  func engineSelectCandidate(at index: Int, for session: RimeSessionID) throws(RimeError) -> Bool {
    return rimeApi.select_candidate(session.rawValue, index)
  }
  func engineSelectCandidateOnCurrentPage(at index: Int, for session: RimeSessionID)
    throws(RimeError) -> Bool
  {
    return rimeApi.select_candidate_on_current_page(session.rawValue, index)
  }

  func engineBeginCandidates(for session: RimeSessionID) throws(RimeError) -> ObjectHandle<
    RimeCandidate
  > {
    let handle = ObjectHandle<RimeCandidate>()
    var iterator = rime_candidate_list_iterator_t()
    _ = rimeApi.candidate_list_begin(session.rawValue, &iterator)
    candidateIterators[handle] = iterator
    return handle
  }

  func engineAdvanceCandidateIterator(_ iterator: ObjectHandle<RimeCandidate>) throws(RimeError)
    -> RimeCandidate?
  {
    guard var iter = candidateIterators[iterator] else {
      throw RimeError.invalidHandle(kind: .candidateIterator, id: iterator.id)
    }
    if rimeApi.candidate_list_next(&iter) {
      candidateIterators[iterator] = iter
      return RimeCandidate(iter.candidate)
    } else {
      return nil
    }
  }

  func engineEndCandidateIterator(_ iterator: ObjectHandle<RimeCandidate>) throws(RimeError) {
    if var iter = candidateIterators.removeValue(forKey: iterator) {
      rimeApi.candidate_list_end(&iter)
    }
  }

  func engineCandidateList(fromIndex: Int32, for sessionID: RimeSessionID) throws(RimeError)
    -> ObjectHandle<
      RimeCandidate
    >?
  {
    let handle = ObjectHandle<RimeCandidate>()
    var iterator = rime_candidate_list_iterator_t()
    _ = rimeApi.candidate_list_from_index(sessionID.rawValue, &iterator, fromIndex)
    candidateIterators[handle] = iterator
    return handle
  }

  func engineStateLabel(for key: String, state: RimeState, in session: RimeSessionID)
    throws(RimeError)
    -> String?
  {
    guard let cStr = rimeApi.get_state_label(session.rawValue, key, state == .on) else {
      return nil
    }
    return String(cString: cStr)
  }

  func engineStateLabel(
    for key: String, state: RimeState, abbreviated: Bool, in session: RimeSessionID
  ) throws(RimeError) -> String? {
    let slice = rimeApi.get_state_label_abbreviated(
      session.rawValue, key, state == .on, abbreviated)
    guard let bytes = slice.str else {
      return nil
    }
    let length = slice.length
    let data = Data(bytes: bytes, count: Int(length))
    return String(data: data, encoding: .utf8)
  }

  func engineRemoveCandidate(at index: Int, for session: RimeSessionID) throws(RimeError) -> Bool {
    return rimeApi.delete_candidate(session.rawValue, index)
  }

  func engineRemoveCandidateOnCurrentPage(at index: Int, for session: RimeSessionID)
    throws(RimeError) -> Bool
  {
    return rimeApi.delete_candidate_on_current_page(session.rawValue, index)
  }

  func engineHighlightCandidate(at index: Int, for session: RimeSessionID) throws(RimeError) -> Bool
  {
    return rimeApi.highlight_candidate(session.rawValue, index)
  }

  func engineHighlightCandidateOnCurrentPage(at index: Int, for session: RimeSessionID)
    throws(RimeError) -> Bool
  {
    return rimeApi.highlight_candidate_on_current_page(session.rawValue, index)
  }

  func enginePage(_ direction: RimePageDirection, for session: RimeSessionID) throws(RimeError)
    -> Bool
  {
    return rimeApi.change_page(session.rawValue, direction == .forward)
  }
}

extension RimeSession {
  public func selectCandidate(at index: Int) async throws -> Bool {
    try await root.selectCandidate(at: index, for: sessionID)
  }

  public func selectCandidateOnCurrentPage(at index: Int) async throws -> Bool {
    try await root.selectCandidateOnCurrentPage(at: index, for: sessionID)
  }

  public func removeCandidate(at index: Int) async throws -> Bool {
    try await root.removeCandidate(at: index, for: sessionID)
  }

  public func removeCandidateOnCurrentPage(at index: Int) async throws -> Bool {
    try await root.removeCandidateOnCurrentPage(at: index, for: sessionID)
  }

  public func highlightCandidate(at index: Int) async throws -> Bool {
    try await root.highlightCandidate(at: index, for: sessionID)
  }

  public func highlightCandidateOnCurrentPage(at index: Int) async throws -> Bool {
    try await root.highlightCandidateOnCurrentPage(at: index, for: sessionID)
  }

  public func page(_ direction: RimePageDirection) async throws -> Bool {
    try await root.page(direction, for: sessionID)
  }

  public func stateLabel(for key: String, state: RimeState) async throws -> String? {
    try await root.stateLabel(for: key, state: state, in: sessionID)
  }

  public func stateLabel(for key: String, state: RimeState, abbreviated: Bool) async throws
    -> String?
  {
    try await root.stateLabel(for: key, state: state, abbreviated: abbreviated, in: sessionID)
  }
}
