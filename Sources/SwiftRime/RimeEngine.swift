import CLibrime

public final actor RimeEngine {
    nonisolated public static let shared = RimeEngine()

    let rimeApi: RimeApi_stdbool
    var opaque: Box?

    private init() {
        rimeApi = rime_get_api_stdbool().pointee
    }

    public init(raw pointer: UnsafeRawPointer) {
        rimeApi = pointer.load(as: RimeApi_stdbool.self)
    }

    public init(opaque pointer: OpaquePointer) {
        self.init(raw: UnsafeRawPointer(pointer))
    }

    public func initialize(with traits: borrowing RimeTraits) {
        var traits = traits.toCStructure()
        rimeApi.initialize(&traits)
    }

    public func finalize() {
        rimeApi.finalize()
    }
}

extension RimeEngine {
    public func startMaintenance(fullCheck: Bool) -> Bool {
        rimeApi.start_maintenance(fullCheck)
    }

    public var isMaintenanceMode: Bool {
        rimeApi.is_maintenance_mode()
    }

    public func joinMaintenanceThread() {
        rimeApi.join_maintenance_thread()
    }
}

extension RimeEngine {
    func option(named option: String, for sessionID: RimeSessionID) -> Bool {
        rimeApi.get_option(sessionID.rawValue, option)
    }

    func setOption(_ option: String, value: Bool, for sessionID: RimeSessionID) {
        rimeApi.set_option(sessionID.rawValue, option, value)
    }

    func property(named property: String, for sessionID: RimeSessionID) -> String? {
        let bufferSize = 1024
        let buffer: [CChar] = Array(repeating: 0, count: bufferSize)
        return buffer.withUnsafeBufferPointer { pointer in
            guard
                rimeApi.get_property(
                    sessionID.rawValue,
                    property,
                    UnsafeMutablePointer(mutating: pointer.baseAddress),
                    bufferSize
                )
            else {
                return nil
            }
            return pointer.baseAddress.map { String(cString: $0) }
        }
    }

    func setProperty(_ property: String, value: String, for sessionID: RimeSessionID) {
        rimeApi.set_property(sessionID.rawValue, property, value)
    }
}

extension RimeSession {
    public func option(named option: String) async -> Bool {
        await engine.option(named: option, for: sessionID)
    }

    public func setOption(_ option: String, value: Bool) async {
        await engine.setOption(option, value: value, for: sessionID)
    }

    public func property(named property: String) async -> String? {
        await engine.property(named: property, for: sessionID)
    }

    public func setProperty(_ property: String, value: String) async {
        await engine.setProperty(property, value: value, for: sessionID)
    }
}
