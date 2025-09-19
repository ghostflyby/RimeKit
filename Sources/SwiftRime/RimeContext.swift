import CLibrime

typealias rime_context_t = CLibrime.rime_context_t_stdbool

public struct RimeContext:Sendable ,Codable{
    let composition : RimeComposition
     let menu : RimeMenu
     let commitTextPreview : String
     let selectLabels : [String]
    
    fileprivate init(raw: rime_context_t, engine: RimeEngine) {
        composition = RimeComposition(raw.composition)
        menu = RimeMenu(raw.menu)
        commitTextPreview = String(cString: raw.commit_text_preview)
        selectLabels = CStringArray.convertCStringArrayNullTerminated(raw.select_labels)
    }
    
}

public extension RimeSession {
    var context: RimeContext? {
        get async{
            await engine.context(session: self.id)
        }
    }
}

fileprivate extension RimeEngine {
    func context(session: RimeSessionId) -> RimeContext? {
        var context = rime_context_t.rimeStructInit()
        defer { _ = rimeApi.free_context(&context) }
        return if rimeApi.get_context(session.id, &context){
            RimeContext(raw: context, engine: self)
        }else {
            nil
        }
    }
    
}

public struct RimeComposition :Sendable,Codable{
    let length : Int32
    let cursorPos : Int32
    let selectionStart : Int32
    let selectionEnd : Int32
    let preEdit : String
}

fileprivate extension RimeComposition{
    init(_ cStruct: CLibrime.RimeComposition){
        length = cStruct.length
        cursorPos = cStruct.cursor_pos
        selectionStart = cStruct.sel_start
        selectionEnd = cStruct.sel_end
        preEdit = String(cString: cStruct.preedit)
    }
}

public struct RimeCandidate :Sendable,Codable{
    let text : String
    let comment : String
}
fileprivate extension RimeCandidate{
    init(_ cStruct: CLibrime.RimeCandidate){
        text = String(cString: cStruct.text)
        comment = String(cString: cStruct.comment)
    }
}
    
public struct RimeMenu :Sendable,Codable{
    let pageSize : Int32
    let pageNo : Int32
    let isLastPage : Bool
    let highlightedCandidateIndex : Int32
    let candidates : [RimeCandidate]
    let selectKeys : String
}

fileprivate extension RimeMenu{
    init(_ cStruct: CLibrime.RimeMenu_stdbool){
        pageSize = cStruct.page_size
        pageNo = cStruct.page_no
        isLastPage = cStruct.is_last_page
        highlightedCandidateIndex = cStruct.highlighted_candidate_index
        selectKeys = String(cString: cStruct.select_keys)
        let numCandidates = Int(cStruct.num_candidates)
        let buffer = UnsafeBufferPointer(start: cStruct.candidates, count: numCandidates)
        candidates = buffer.map{ RimeCandidate($0) }
    }
}
