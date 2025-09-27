import CLibrime
import Distributed

public final actor RimeEngine: Rime {
    nonisolated public static let shared = RimeEngine()

    internal let rimeApi: RimeApi_stdbool
    internal var opaque: Box?
    internal static let cStringBufferSize = 1024
    internal let cStringBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: cStringBufferSize)

    internal var configs: [ObjectHandle<RimeConfig>: rime_config_t] = [:]
    internal var configIterators: [ObjectHandle<RimeConfigIterator>: rime_config_iterator_t] = [:]
    internal var candidateIterators:
        [ObjectHandle<RimeCandidateIterator>: rime_candidate_list_iterator_t] = [:]

    private init() {
        rimeApi = rime_get_api_stdbool().pointee
    }

    public init(raw pointer: UnsafeRawPointer) {
        rimeApi = pointer.load(as: RimeApi_stdbool.self)
    }

    public init(opaque pointer: OpaquePointer) {
        self.init(raw: UnsafeRawPointer(pointer))
    }

    public func setup(with traits: RimeTraits) async {
        var t = rime_traits_t.rimeStructInit()
        _ = traits.toCStructure(&t)
        rimeApi.setup(&t)
    }

    public func initialize(with traits: borrowing RimeTraits) async {
        var t = rime_traits_t.rimeStructInit()
        _ = traits.toCStructure(&t)
        rimeApi.initialize(&t)
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
    public func option(named option: String, for sessionID: RimeSessionID) -> Bool {
        rimeApi.get_option(sessionID.rawValue, option)
    }

    public func setOption(_ option: String, value: Bool, for sessionID: RimeSessionID) {
        rimeApi.set_option(sessionID.rawValue, option, value)
    }

    public func property(named property: String, for sessionID: RimeSessionID) -> String? {
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

    public func setProperty(_ property: String, value: String, for sessionID: RimeSessionID) {
        rimeApi.set_property(sessionID.rawValue, property, value)
    }
}

extension RimeEngine {
    public var userID: String {
        String(cString: rimeApi.get_user_id()!)
    }

    public var version: String {
        String(cString: rimeApi.get_version()!)
    }

    public var userDataSyncDirectory: String {
        rimeApi.get_user_data_sync_dir(cStringBuffer, RimeEngine.cStringBufferSize)
        return String(cString: cStringBuffer)
    }

    public var sharedDataDirectory: String {
        rimeApi.get_shared_data_dir_s(cStringBuffer, RimeEngine.cStringBufferSize)
        return String(cString: cStringBuffer)
    }

    public var userDataDirectory: String {
        rimeApi.get_user_data_dir_s(cStringBuffer, RimeEngine.cStringBufferSize)
        return String(cString: cStringBuffer)
    }

    public var prebuiltDataDirectory: String {
        rimeApi.get_prebuilt_data_dir_s(cStringBuffer, RimeEngine.cStringBufferSize)
        return String(cString: cStringBuffer)
    }

    public var stagingDirectory: String {
        rimeApi.get_staging_dir_s(cStringBuffer, RimeEngine.cStringBufferSize)
        return String(cString: cStringBuffer)
    }

    public var syncDirectory: String {
        rimeApi.get_sync_dir_s(cStringBuffer, RimeEngine.cStringBufferSize)
        return String(cString: cStringBuffer)
    }

}

extension RimeEngine {
    public func initializeDeployer(with traits: RimeTraits) async {
        var t = rime_traits_t.rimeStructInit()
        _ = traits.toCStructure(&t)
        rimeApi.deployer_initialize(&t)
    }

    public func prebuild() async -> Bool {
        rimeApi.prebuild()
    }

    public func deploy() async -> Bool {
        rimeApi.deploy()
    }

    public func deploySchema(withID schemaID: String) async -> Bool {
        rimeApi.deploy_schema(schemaID)
    }

    public func deployConfig(filename: String, versionKey: String) async -> Bool {
        rimeApi.deploy_config_file(filename, versionKey)
    }

    public func syncUserData() async -> Bool {
        rimeApi.sync_user_data()
    }
}
