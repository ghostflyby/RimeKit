import CLibrime

public struct RimeStatus: Sendable, Codable {
    let schemaID: String
    let schemaName: String
    let isDisabled: Bool
    let isComposing: Bool
    let isASCIIMode: Bool
    let isFullShape: Bool
    let isSimplified: Bool
    let isTraditional: Bool
    let isASCIIPunctuation: Bool

    fileprivate init(rawValue: rime_status_t_stdbool, engine _: RimeEngine) {
        schemaID = String(cString: rawValue.schema_id)
        schemaName = String(cString: rawValue.schema_name)
        isDisabled = rawValue.is_disabled
        isComposing = rawValue.is_composing
        isASCIIMode = rawValue.is_ascii_mode
        isFullShape = rawValue.is_full_shape
        isSimplified = rawValue.is_simplified
        isTraditional = rawValue.is_traditional
        isASCIIPunctuation = rawValue.is_ascii_punct
    }
}

extension RimeSession {
    public var status: RimeStatus? {
        get async {
            await engine.status(for: sessionID)
        }
    }
}

extension RimeEngine {
    fileprivate func status(for sessionID: RimeSessionID) -> RimeStatus? {
        var status = rime_status_t_stdbool.rimeStructInit()
        defer { _ = rimeApi.free_status(&status) }
        guard rimeApi.get_status(sessionID.rawValue, &status) else {
            return nil
        }
        return RimeStatus(rawValue: status, engine: self)
    }
}
