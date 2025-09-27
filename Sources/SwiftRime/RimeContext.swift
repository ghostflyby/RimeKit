import CLibrime
import Foundation

typealias RimeContextRaw = CLibrime.rime_context_t_stdbool

public struct RimeContext: Sendable, Codable {
    let composition: RimeComposition
    let menu: RimeMenu
    let commitTextPreview: String
    let selectLabels: [String]

    fileprivate init(rawValue: RimeContextRaw) {
        composition = RimeComposition(rawValue.composition)
        menu = RimeMenu(rawValue.menu)
        commitTextPreview = String(cString: rawValue.commit_text_preview)
        selectLabels = rawValue.select_labels.toStringArray()
    }
}

extension RimeSession {
    public var context: RimeContext? {
        get async {
            await engine.context(for: sessionID)
        }
    }
}

extension RimeEngine {
    public func context(for sessionID: RimeSessionID) -> RimeContext? {
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
    fileprivate init(_ cStruct: CLibrime.RimeComposition) {
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
    fileprivate init(_ cStruct: CLibrime.RimeCandidate) {
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
    fileprivate init(_ cStruct: CLibrime.RimeMenu_stdbool) {
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

extension RimeEngine {
    public func selectCandidate(at index: Int, for session: RimeSessionID) async -> Bool {
        return rimeApi.select_candidate(session.rawValue, index)
    }
    public func selectCandidateOnCurrentPage(at index: Int, for session: RimeSessionID) async
        -> Bool
    {
        return rimeApi.select_candidate_on_current_page(session.rawValue, index)
    }

    public func beginCandidates(for session: RimeSessionID) async -> ObjectHandle<
        RimeCandidateIterator
    > {
        let handle = ObjectHandle<RimeCandidateIterator>()
        var iterator = rime_candidate_list_iterator_t()
        _ = rimeApi.candidate_list_begin(session.rawValue, &iterator)
        return handle
    }

    public func advanceCandidateIterator(_ iterator: ObjectHandle<RimeCandidateIterator>) async
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

    public func endCandidateIterator(_ iterator: ObjectHandle<RimeCandidateIterator>) async {
        if var iter = candidateIterators.removeValue(forKey: iterator) {
            rimeApi.candidate_list_end(&iter)
        }
    }

    public func candidateList(fromIndex: Int32, for sessionID: RimeSessionID) async -> ObjectHandle<
        RimeCandidateIterator
    >? {
        let handle = ObjectHandle<RimeCandidateIterator>()
        var iterator = rime_candidate_list_iterator_t()
        _ = rimeApi.candidate_list_from_index(sessionID.rawValue, &iterator, fromIndex)
        return handle
    }

    public func stateLabel(for key: String, state: RimeState, in session: RimeSessionID) async
        -> String?
    {
        guard let cStr = rimeApi.get_state_label(session.rawValue, key, state == .on) else {
            return nil
        }
        return String(cString: cStr)
    }

    public func stateLabel(
        for key: String, state: RimeState, abbreviated: Bool, in session: RimeSessionID
    ) async -> String? {
        let slice = rimeApi.get_state_label_abbreviated(
            session.rawValue, key, state == .on, abbreviated)
        guard let bytes = slice.str else {
            return nil
        }
        let length = slice.length
        let data = Data(bytes: bytes, count: Int(length))
        return String(data: data, encoding: .utf8)
    }

    public func removeCandidate(at index: Int, for session: RimeSessionID) async -> Bool {
        return rimeApi.delete_candidate(session.rawValue, index)
    }

    public func removeCandidateOnCurrentPage(at index: Int, for session: RimeSessionID) async
        -> Bool
    {
        return rimeApi.delete_candidate_on_current_page(session.rawValue, index)
    }

    public func highlightCandidate(at index: Int, for session: RimeSessionID) async -> Bool {
        return rimeApi.highlight_candidate(session.rawValue, index)
    }

    public func highlightCandidateOnCurrentPage(at index: Int, for session: RimeSessionID) async
        -> Bool
    {
        return rimeApi.highlight_candidate_on_current_page(session.rawValue, index)
    }

    public func page(_ direction: RimePageDirection, for session: RimeSessionID) async -> Bool {
        return rimeApi.change_page(session.rawValue, direction == .forward)
    }
}
