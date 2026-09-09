import RimeDynamic

/// librime 的进程内引擎(内部实现细节)。
///
/// 串行化约定(§3.7 单一执行域):macOS 上由 `RimeServiceRoot` 分布式 actor
/// 的执行器独占调用;其他平台宿主需自行在单一队列/actor 上收敛调用。
/// 不作为公开 API——公开入口是 `RimeSession`(进程内)与 `RimeServiceRoot`(XPC)。
final class RimeEngine: @unchecked Sendable {
  public static let shared = RimeEngine()

  internal let rimeApi: RimeApi_stdbool
  internal var opaque: Box?
  internal static let cStringBufferSize = 1024
  internal let cStringBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: cStringBufferSize)

  internal var configs: [ObjectHandle<RimeConfig>: rime_config_t] = [:]
  internal var configIterators: [ObjectHandle<RimeConfigIterator>: rime_config_iterator_t] = [:]
  internal var candidateIterators: [ObjectHandle<RimeCandidate>: rime_candidate_list_iterator_t] =
    [:]

  private init() {
    rimeApi = rime_get_api_stdbool().pointee
  }

  public init(_ pointer: UnsafeRawPointer) {
    rimeApi = pointer.load(as: RimeApi_stdbool.self)
  }

  public convenience init(_ pointer: OpaquePointer) {
    self.init(UnsafeRawPointer(pointer))
  }

  public func setup(with traits: RimeTraits) throws(RimeError) {
    var t = rime_traits_t.rimeStructInit()
    let handle = traits.toCStructure(&t)
    rimeApi.setup(&t)
    withExtendedLifetime(handle) {}
  }

  public func initialize(with traits: borrowing RimeTraits) throws(RimeError) {
    var t = rime_traits_t.rimeStructInit()
    let handle = traits.toCStructure(&t)
    rimeApi.initialize(&t)
    withExtendedLifetime(handle) {}
  }

  public func finalize() throws(RimeError) {
    rimeApi.finalize()
  }
}

extension RimeEngine {
  public func startMaintenance(fullCheck: Bool) throws(RimeError) -> Bool {
    rimeApi.start_maintenance(fullCheck)
  }

  public var isMaintenanceMode: Bool {
    get throws(RimeError) {
      rimeApi.is_maintenance_mode()
    }
  }

  public func joinMaintenanceThread() throws(RimeError) {
    rimeApi.join_maintenance_thread()
  }
}

extension RimeEngine {
  public func option(named option: String, for sessionID: RimeSessionID) throws(RimeError) -> Bool {
    rimeApi.get_option(sessionID.rawValue, option)
  }

  public func setOption(_ option: String, value: Bool, for sessionID: RimeSessionID) throws(RimeError) {
    rimeApi.set_option(sessionID.rawValue, option, value)
  }

  public func property(named property: String, for sessionID: RimeSessionID) throws(RimeError) -> String? {
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

  public func setProperty(_ property: String, value: String, for sessionID: RimeSessionID) throws(RimeError) {
    rimeApi.set_property(sessionID.rawValue, property, value)
  }
}

extension RimeEngine {
  public var userID: String {
    get throws(RimeError) {
      guard let userID = rimeApi.get_user_id() else {
        throw RimeError.engineNotInitialized
      }
      return String(cString: userID)
    }
  }

  public var version: String {
    get throws(RimeError) {
      guard let version = rimeApi.get_version() else {
        throw RimeError.apiUnavailable("get_version")
      }
      return String(cString: version)
    }
  }

  public var userDataSyncDirectory: String {
    get throws(RimeError) {
      rimeApi.get_user_data_sync_dir(cStringBuffer, RimeEngine.cStringBufferSize)
      return String(cString: cStringBuffer)
    }
  }

  public var sharedDataDirectory: String {
    get throws(RimeError) {
      rimeApi.get_shared_data_dir_s(cStringBuffer, RimeEngine.cStringBufferSize)
      return String(cString: cStringBuffer)
    }
  }

  public var userDataDirectory: String {
    get throws(RimeError) {
      rimeApi.get_user_data_dir_s(cStringBuffer, RimeEngine.cStringBufferSize)
      return String(cString: cStringBuffer)
    }
  }

  public var prebuiltDataDirectory: String {
    get throws(RimeError) {
      rimeApi.get_prebuilt_data_dir_s(cStringBuffer, RimeEngine.cStringBufferSize)
      return String(cString: cStringBuffer)
    }
  }

  public var stagingDirectory: String {
    get throws(RimeError) {
      rimeApi.get_staging_dir_s(cStringBuffer, RimeEngine.cStringBufferSize)
      return String(cString: cStringBuffer)
    }
  }

  public var syncDirectory: String {
    get throws(RimeError) {
      rimeApi.get_sync_dir_s(cStringBuffer, RimeEngine.cStringBufferSize)
      return String(cString: cStringBuffer)
    }
  }
}

extension RimeEngine {
  public func initializeDeployer(with traits: RimeTraits) throws(RimeError) {
    var t = rime_traits_t.rimeStructInit()
    let handle = traits.toCStructure(&t)
    rimeApi.deployer_initialize(&t)
    withExtendedLifetime(handle) {}
  }

  public func prebuild() throws(RimeError) -> Bool {
    rimeApi.prebuild()
  }

  public func deploy() throws(RimeError) -> Bool {
    rimeApi.deploy()
  }

  public func deploySchema(withID schemaID: String) throws(RimeError) -> Bool {
    rimeApi.deploy_schema(schemaID)
  }

  public func deployConfig(filename: String, versionKey: String) throws(RimeError) -> Bool {
    rimeApi.deploy_config_file(filename, versionKey)
  }

  public func syncUserData() throws(RimeError) -> Bool {
    rimeApi.sync_user_data()
  }
}
