import CLibrime

typealias RimeContextRaw = CLibrime.rime_context_t_stdbool

public struct RimeContext: Sendable, Codable {
    let composition: RimeComposition
    let menu: RimeMenu
    let commitTextPreview: String
    let selectLabels: [String]

    fileprivate init(rawValue: RimeContextRaw, engine _: RimeEngine) {
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
    fileprivate func context(for sessionID: RimeSessionID) -> RimeContext? {
        var context = RimeContextRaw.rimeStructInit()
        defer { _ = rimeApi.free_context(&context) }
        guard rimeApi.get_context(sessionID.rawValue, &context) else {
            return nil
        }
        return RimeContext(rawValue: context, engine: self)
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
