import CLibrime
import Darwin

public struct RimeSessionId:Sendable ,Codable {
     let id : UInt
}

public struct RimeSession: ~Copyable {
	internal let id: RimeSessionId
    internal let engine : RimeEngine
    

    public init( engine: RimeEngine) async {
        self.id = await engine.createSession()
        self.engine = engine
	}

    public init?(engine: RimeEngine, id: RimeSessionId) async {
        if await engine.findSession(id: id) {
            self.id = id
            self.engine = engine
        }else {return nil}
    }

    deinit {
        let engine = engine
        let id = id
        Task.detached{
            await engine.destroySession(id: id)
        }
    }
}

public extension RimeSession{
    func processKey(keycode:CInt,  mask:CInt)async->Bool {
        await engine.processKey(session: self.id, keycode: keycode, mask: mask)
    }
    
    func commitComposition()async->Bool{
        await engine.commitComposition(session: self.id)
    }
    
    func clearComposition()async{
        await engine.clearComposition(session: self.id)
    }
}

fileprivate extension RimeEngine {

    func createSession() -> RimeSessionId {
        RimeSessionId(id: rimeApi.create_session())
	}

    func findSession(id: RimeSessionId) -> Bool {
        rimeApi.find_session(id.id)
	}

    func destroySession(id: RimeSessionId) -> Bool {
        rimeApi.destroy_session(id.id)
	}

    func cleanupStaleSessions() {
		rimeApi.cleanup_stale_sessions()
	}

    func cleanupAllSessions() {
		rimeApi.cleanup_all_sessions()
	}
}


fileprivate extension RimeEngine {
    func processKey(session: RimeSessionId, keycode:CInt,  mask:CInt)->Bool{
        rimeApi.process_key(session.id, keycode, mask)
    }
    
    func commitComposition(session: RimeSessionId)->Bool{
        rimeApi.commit_composition(session.id)
    }
    
    func clearComposition(session: RimeSessionId){
        rimeApi.clear_composition(session.id)
        
    }
}

