import CLibrime

public final actor RimeEngine {
	nonisolated public static let shared = RimeEngine()
	let rimeApi: RimeApi_stdbool
    var opaque: Box? = nil

	private init() {
		self.rimeApi = rime_get_api_stdbool().pointee
	}
    
    public init(raw:UnsafeRawPointer){
        self.rimeApi = raw.load(as: RimeApi_stdbool.self)
    }
    
    public init(opaque:OpaquePointer){
        let pointer = UnsafeRawPointer(opaque)
        self.init(raw: pointer)
    }

	public func initialize(traits: borrowing RimeTraits) {
		var traits = traits.toCStructure()
		rimeApi.initialize(&traits)
	}

	public func finalize() {
		rimeApi.finalize()
	}


}



public extension RimeEngine {
    
    func startMaintenance(fullCheck : Bool)->Bool {
       rimeApi.start_maintenance(fullCheck)
    }
    
    var isMaintenanceMode:Bool {
        rimeApi.is_maintenance_mode()
    }
    
    func joinMaintenanceThread() {
        rimeApi.join_maintenance_thread()
    }
}
//void (*set_option)(RimeSessionId session_id, const char* option, Bool value);
//Bool (*get_option)(RimeSessionId session_id, const char* option);
//
//void (*set_property)(RimeSessionId session_id,
//                     const char* prop,
//                     const char* value);
//Bool (*get_property)(RimeSessionId session_id,
//                     const char* prop,
//                     char* value,
//                     size_t buffer_size);

extension RimeEngine {
    func getOption(session:RimeSessionId, option:String) -> Bool {
        rimeApi.get_option(session.id, option)
    }
    
    func setOption(session:RimeSessionId, option:String, value:Bool) {
        rimeApi.set_option(session.id, option, value)
    }
    
    func getProperty(session:RimeSessionId, prop:String) -> String? {
        let bufferSize = 1024
        let buffer :[CChar] = Array(repeating: 0, count: bufferSize)
        return buffer.withUnsafeBufferPointer{ ptr in
            return if rimeApi.get_property(session.id, prop, UnsafeMutablePointer(mutating: ptr.baseAddress), bufferSize)
            {String(cString: ptr.baseAddress!)}
            else {nil}
        }
    }
    
    func setProperty(session:RimeSessionId, prop:String, value:String) {
        rimeApi.set_property(session.id, prop, value)
    }
    
}

public extension RimeSession {
    func get(option:String) async -> Bool {
        await engine.getOption(session: self.id, option: option)
    }
    func set(option:String, value:Bool) async {
        await engine.setOption(session: self.id, option: option, value: value)
    }
    func get(prop:String) async -> String? {
        await engine.getProperty(session: self.id, prop: prop)
    }
    func set(prop:String, value:String) async {
        await engine.setProperty(session: self.id, prop: prop, value: value)
    }
}
    

