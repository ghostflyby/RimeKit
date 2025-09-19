import CLibrime

public struct RimeStatus:Sendable ,Codable{
    let schemaId : String
    let schemaName : String
    let isDisabled : Bool
    let isComposing : Bool
    let isAsciiMode : Bool
    let isFullShape : Bool
    let isSimplified : Bool
    let isTraditional : Bool
    let isAsciiPunct : Bool

    fileprivate init(raw: rime_status_t_stdbool, engine: RimeEngine) {
        schemaId = String(cString: raw.schema_id)
        schemaName = String(cString: raw.schema_name)
        isDisabled = raw.is_disabled
        isComposing = raw.is_composing
        isAsciiMode = raw.is_ascii_mode
        isFullShape = raw.is_full_shape
        isSimplified = raw.is_simplified
        isTraditional = raw.is_traditional
        isAsciiPunct = raw.is_ascii_punct
    }
    
}

public extension RimeSession {
    var status: RimeStatus? {
        get async{
            await engine.status(session: self.id)
        }
    }
}

fileprivate extension RimeEngine {
    func status(session: RimeSessionId) -> RimeStatus? {
        var status = rime_status_t_stdbool.rimeStructInit()
        defer { _ = rimeApi.free_status(&status) }
        return if rimeApi.get_status(session.id, &status){
            RimeStatus(raw: status, engine: self)
        }else {
            nil
        }
    }
    
}
    
