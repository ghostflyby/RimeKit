import RimeDynamic

// RimeEngine 内联实现(生命周期/维护/选项/Deployer/目录/身份):根 actor 的内部成员。
// 原类型已删除,状态与方法由 RimeServiceRoot 独占(§3.7 单一执行域)。
extension RimeServiceRoot {






  public func engineSetup(with traits: RimeTraits) throws(RimeError) {
    var t = rime_traits_t.rimeStructInit()
    let handle = traits.toCStructure(&t)
    rimeApi.setup(&t)
    withExtendedLifetime(handle) {}
  }

  public func engineInitialize(with traits: borrowing RimeTraits) throws(RimeError) {
    var t = rime_traits_t.rimeStructInit()
    let handle = traits.toCStructure(&t)
    rimeApi.initialize(&t)
    withExtendedLifetime(handle) {}
  }

  public func engineFinalize() throws(RimeError) {
    rimeApi.finalize()
  }

  public func engineStartMaintenance(fullCheck: Bool) throws(RimeError) -> Bool {
    rimeApi.start_maintenance(fullCheck)
  }

  public var engineIsMaintenanceMode: Bool {
    get throws(RimeError) {
      rimeApi.is_maintenance_mode()
    }
  }

  public func engineJoinMaintenanceThread() throws(RimeError) {
    rimeApi.join_maintenance_thread()
  }

  public func engineOption(named option: String, for sessionID: RimeSessionID) throws(RimeError) -> Bool {
    rimeApi.get_option(sessionID.rawValue, option)
  }

  public func engineSetOption(_ option: String, value: Bool, for sessionID: RimeSessionID) throws(RimeError) {
    rimeApi.set_option(sessionID.rawValue, option, value)
  }

  public func engineProperty(named property: String, for sessionID: RimeSessionID) throws(RimeError) -> String? {
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

  public func engineSetProperty(_ property: String, value: String, for sessionID: RimeSessionID) throws(RimeError) {
    rimeApi.set_property(sessionID.rawValue, property, value)
  }

  public var engineUserID: String {
    get throws(RimeError) {
      guard let userID = rimeApi.get_user_id() else {
        throw RimeError.engineNotInitialized
      }
      return String(cString: userID)
    }
  }

  public var engineVersion: String {
    get throws(RimeError) {
      guard let version = rimeApi.get_version() else {
        throw RimeError.apiUnavailable("get_version")
      }
      return String(cString: version)
    }
  }

  public var engineUserDataSyncDirectory: String {
    get throws(RimeError) {
      rimeApi.get_user_data_sync_dir(cStringBuffer, Self.cStringBufferSize)
      return String(cString: cStringBuffer)
    }
  }

  public var engineSharedDataDirectory: String {
    get throws(RimeError) {
      rimeApi.get_shared_data_dir_s(cStringBuffer, Self.cStringBufferSize)
      return String(cString: cStringBuffer)
    }
  }

  public var engineUserDataDirectory: String {
    get throws(RimeError) {
      rimeApi.get_user_data_dir_s(cStringBuffer, Self.cStringBufferSize)
      return String(cString: cStringBuffer)
    }
  }

  public var enginePrebuiltDataDirectory: String {
    get throws(RimeError) {
      rimeApi.get_prebuilt_data_dir_s(cStringBuffer, Self.cStringBufferSize)
      return String(cString: cStringBuffer)
    }
  }

  public var engineStagingDirectory: String {
    get throws(RimeError) {
      rimeApi.get_staging_dir_s(cStringBuffer, Self.cStringBufferSize)
      return String(cString: cStringBuffer)
    }
  }

  public var engineSyncDirectory: String {
    get throws(RimeError) {
      rimeApi.get_sync_dir_s(cStringBuffer, Self.cStringBufferSize)
      return String(cString: cStringBuffer)
    }
  }

  public func engineInitializeDeployer(with traits: RimeTraits) throws(RimeError) {
    var t = rime_traits_t.rimeStructInit()
    let handle = traits.toCStructure(&t)
    rimeApi.deployer_initialize(&t)
    withExtendedLifetime(handle) {}
  }

  public func enginePrebuild() throws(RimeError) -> Bool {
    rimeApi.prebuild()
  }

  public func engineDeploy() throws(RimeError) -> Bool {
    rimeApi.deploy()
  }

  public func engineDeploySchema(withID schemaID: String) throws(RimeError) -> Bool {
    rimeApi.deploy_schema(schemaID)
  }

  public func engineDeployConfig(filename: String, versionKey: String) throws(RimeError) -> Bool {
    rimeApi.deploy_config_file(filename, versionKey)
  }

  public func engineSyncUserData() throws(RimeError) -> Bool {
    rimeApi.sync_user_data()
  }

}
