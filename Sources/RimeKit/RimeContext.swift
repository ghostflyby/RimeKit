import Foundation
import RimeDynamic

typealias RimeContextRaw = RimeDynamic.rime_context_t_stdbool

public struct RimeContext: Sendable, Codable {
  let composition: RimeComposition
  let menu: RimeMenu
  let commitTextPreview: String
  let selectLabels: [String]
}

extension RimeContext {
  fileprivate init(rawValue: RimeContextRaw) {
    composition = RimeComposition(rawValue.composition)
    menu = RimeMenu(rawValue.menu)
    commitTextPreview = String(cString: rawValue.commit_text_preview)
    selectLabels = rawValue.select_labels.toStringArray()
  }
}

extension RimeSession {
  public var context: RimeContext? {
    get async throws {
      try await root.context(for: sessionID)
    }
  }
}

extension RimeServiceRoot {
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
  let length: Int32
  let cursorPosition: Int32
  let selectionStart: Int32
  let selectionEnd: Int32
  let preedit: String
}

extension RimeComposition {
  fileprivate init(_ cStruct: RimeDynamic.RimeComposition) {
    length = cStruct.length
    cursorPosition = cStruct.cursor_pos
    selectionStart = cStruct.sel_start
    selectionEnd = cStruct.sel_end
    preedit = String(cString: cStruct.preedit)
  }
}

public struct RimeCandidate: Sendable, Codable {
  let text: String
  let comment: String
}

extension RimeCandidate {
  fileprivate init(_ cStruct: RimeDynamic.RimeCandidate) {
    text = String(cString: cStruct.text)
    comment = String(cString: cStruct.comment)
  }
}

public struct RimeMenu: Sendable, Codable {
  let pageSize: Int32
  let pageNumber: Int32
  let isLastPage: Bool
  let highlightedCandidateIndex: Int32
  let candidates: [RimeCandidate]
  let selectKeys: String
}

extension RimeMenu {
  fileprivate init(_ cStruct: RimeDynamic.RimeMenu_stdbool) {
    pageSize = cStruct.page_size
    pageNumber = cStruct.page_no
    isLastPage = cStruct.is_last_page
    highlightedCandidateIndex = cStruct.highlighted_candidate_index
    selectKeys = String(cString: cStruct.select_keys)
    let numCandidates = Int(cStruct.num_candidates)
    let buffer = UnsafeBufferPointer(start: cStruct.candidates, count: numCandidates)
    candidates = buffer.map { RimeCandidate($0) }
  }
}

extension RimeServiceRoot {
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
    var iter = candidateIterators[iterator]!
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

  func engineCandidateList(fromIndex: Int32, for sessionID: RimeSessionID) throws(RimeError) -> ObjectHandle<
    RimeCandidate
  >? {
    let handle = ObjectHandle<RimeCandidate>()
    var iterator = rime_candidate_list_iterator_t()
    _ = rimeApi.candidate_list_from_index(sessionID.rawValue, &iterator, fromIndex)
    candidateIterators[handle] = iterator
    return handle
  }

  func engineStateLabel(for key: String, state: RimeState, in session: RimeSessionID) throws(RimeError)
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

  func engineHighlightCandidate(at index: Int, for session: RimeSessionID) throws(RimeError) -> Bool {
    return rimeApi.highlight_candidate(session.rawValue, index)
  }

  func engineHighlightCandidateOnCurrentPage(at index: Int, for session: RimeSessionID)
    throws(RimeError) -> Bool
  {
    return rimeApi.highlight_candidate_on_current_page(session.rawValue, index)
  }

  func enginePage(_ direction: RimePageDirection, for session: RimeSessionID) throws(RimeError) -> Bool {
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

  public func stateLabel(for key: String, state: RimeState, abbreviated: Bool) async throws -> String? {
    try await root.stateLabel(for: key, state: state, abbreviated: abbreviated, in: sessionID)
  }
}
