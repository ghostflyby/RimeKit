import CLibrime

public struct RimeCommit :Sendable,Codable{
    public let text : String
}

public extension RimeSession {
    var commit: RimeCommit? {
        get async{
            await engine.commit(session: self.id)
        }
    }
    
    var commitText: String? {
        get async{
            await engine.commit(session: self.id)?.text
        }
    }
}

fileprivate extension RimeCommit {
     init(raw: rime_commit_t, engine: RimeEngine) {
        text = String(cString: raw.text)
    }
}

fileprivate extension RimeEngine {
    func commit(session: RimeSessionId) -> RimeCommit? {
        var commit = rime_commit_t.rimeStructInit()
        defer { _ = rimeApi.free_commit(&commit) }
        return if rimeApi.get_commit(session.id, &commit){
            RimeCommit(raw: commit, engine: self)
        }else {
            nil
        }
    }
}
    
