import Foundation
import RimeDynamic

/// `ObjectHandle` 的幽灵标记类型:仅用于在类型层面区分配置迭代器句柄,不存在实例。
/// 保持 Copyable:线缆序列化(XPCMarshal)要求句柄类型可复制传递。
public enum RimeConfigIterator: Sendable {}

public struct ObjectHandle<T: ~Copyable>: Sendable, Codable, Hashable {
  private let rawValue: UUID
  internal init() {
    rawValue = UUID()
  }

  internal init(id: UUID) {
    rawValue = id
  }

  internal var id: UUID { rawValue }
}

final public class RimeConfig: Sendable {

  internal let handle: ObjectHandle<RimeConfig>
  internal let engine: RimeEngine
  fileprivate init(handle: ObjectHandle<RimeConfig>, engine: RimeEngine) {
    self.handle = handle
    self.engine = engine
  }
  deinit {
    try? engine.close(config: handle)
  }
}

extension RimeEngine {
  public func openSchema(_ schemaID: String) throws(RimeError) -> ObjectHandle<RimeConfig>? {
    var config: rime_config_t = rime_config_t()
    if rimeApi.schema_open(schemaID, &config) {
      let handle = ObjectHandle<RimeConfig>()
      configs[handle] = config
      return handle
    } else {
      return nil
    }
  }

  public func openConfig(_ configID: String) throws(RimeError) -> ObjectHandle<RimeConfig>? {
    var config: rime_config_t = rime_config_t()
    if rimeApi.config_open(configID, &config) {
      let handle = ObjectHandle<RimeConfig>()
      configs[handle] = config
      return handle
    } else {
      return nil
    }
  }

  public func openUserConfig(configId: String) throws(RimeError) -> ObjectHandle<RimeConfig>? {
    var config: rime_config_t = rime_config_t()
    if rimeApi.user_config_open(configId, &config) {
      let handle = ObjectHandle<RimeConfig>()
      configs[handle] = config
      return handle
    } else {
      return nil
    }
  }
}

extension RimeConfig {
  public func string(forKey: String) throws(RimeError) -> String? {
    try engine.string(forKey: forKey, in: self.handle)
  }
  public func set(_ value: String, forKey: String) throws(RimeError) -> Bool {
    try engine.set(value, forKey: forKey, in: self.handle)
  }
  public func int(forKey: String) throws(RimeError) -> Int32? {
    try engine.int(forKey: forKey, in: self.handle)
  }
  public func set(_ value: Int32, forKey: String) throws(RimeError) -> Bool {
    try engine.set(value, forKey: forKey, in: self.handle)
  }
  public func bool(forKey: String) throws(RimeError) -> Bool? {
    try engine.bool(forKey: forKey, in: self.handle)
  }
  public func set(_ value: Bool, forKey: String) throws(RimeError) -> Bool {
    try engine.set(value, forKey: forKey, in: self.handle)
  }
  public func double(forKey: String) throws(RimeError) -> Double? {
    try engine.double(forKey: forKey, in: self.handle)
  }
  public func set(_ value: Double, forKey: String) throws(RimeError) -> Bool {
    try engine.set(value, forKey: forKey, in: self.handle)
  }
  public func item(forKey: String) throws(RimeError) -> RimeConfig? {
    if let handle = try engine.item(forKey: forKey, in: self.handle) {
      RimeConfig(handle: handle, engine: engine)
    } else {
      nil
    }
  }
  public func set(_ value: borrowing RimeConfig, forKey: String) throws(RimeError) -> Bool {
    try engine.set(value.handle, forKey: forKey, in: self.handle)
  }

  public func removeValue(forKey key: String) throws(RimeError) -> Bool {
    try engine.removeValue(forKey: key, in: self.handle)
  }
}

extension RimeEngine {

  public func close(config: ObjectHandle<RimeConfig>) throws(RimeError) -> Bool {
    guard var config = configs[config] else {
      throw RimeError.invalidHandle(kind: .config, id: config.id)
    }
    return rimeApi.config_close(&config)
  }

  public func string(forKey key: String, in config: ObjectHandle<RimeConfig>) throws(RimeError)
    -> String?
  {
    guard var config = configs[config] else {
      throw RimeError.invalidHandle(kind: .config, id: config.id)
    }

    let cStr = rimeApi.config_get_cstring(&config, key)
    defer { cStr?.deallocate() }
    return if let cStr = cStr {
      String(cString: cStr)
    } else {
      nil
    }
  }

  public func set(_ value: String, forKey key: String, in config: ObjectHandle<RimeConfig>)
    throws(RimeError) -> Bool
  {
    guard var config = configs[config] else {
      throw RimeError.invalidHandle(kind: .config, id: config.id)
    }
    return rimeApi.config_set_string(&config, key, value)
  }

  public func int(forKey key: String, in config: ObjectHandle<RimeConfig>) throws(RimeError)
    -> Int32?
  {
    guard var config = configs[config] else {
      throw RimeError.invalidHandle(kind: .config, id: config.id)
    }
    var value: Int32 = 0
    return if rimeApi.config_get_int(&config, key, &value) {
      value
    } else {
      nil
    }
  }
  public func set(_ value: Int32, forKey key: String, in config: ObjectHandle<RimeConfig>)
    throws(RimeError) -> Bool
  {
    guard var config = configs[config] else {
      throw RimeError.invalidHandle(kind: .config, id: config.id)
    }
    return rimeApi.config_set_int(&config, key, value)
  }
  public func bool(forKey key: String, in config: ObjectHandle<RimeConfig>) throws(RimeError)
    -> Bool?
  {
    guard var config = configs[config] else {
      throw RimeError.invalidHandle(kind: .config, id: config.id)
    }
    var value: Bool = false
    return if rimeApi.config_get_bool(&config, key, &value) {
      value
    } else {
      nil
    }
  }
  public func set(_ value: Bool, forKey key: String, in config: ObjectHandle<RimeConfig>)
    throws(RimeError) -> Bool
  {
    guard var config = configs[config] else {
      throw RimeError.invalidHandle(kind: .config, id: config.id)
    }
    return rimeApi.config_set_bool(&config, key, value)
  }
  public func double(forKey key: String, in config: ObjectHandle<RimeConfig>) throws(RimeError)
    -> Double?
  {
    guard var config = configs[config] else {
      throw RimeError.invalidHandle(kind: .config, id: config.id)
    }
    var value: Double = 0
    return if rimeApi.config_get_double(&config, key, &value) {
      value
    } else {
      nil
    }
  }
  public func set(_ value: Double, forKey key: String, in config: ObjectHandle<RimeConfig>)
    throws(RimeError) -> Bool
  {
    guard var config = configs[config] else {
      throw RimeError.invalidHandle(kind: .config, id: config.id)
    }
    return rimeApi.config_set_double(&config, key, value)
  }
  public func item(forKey key: String, in config: ObjectHandle<RimeConfig>) throws(RimeError)
    -> ObjectHandle<RimeConfig>?
  {
    guard var config = configs[config] else {
      throw RimeError.invalidHandle(kind: .config, id: config.id)
    }
    var subConfig: rime_config_t = rime_config_t()
    if rimeApi.config_get_item(&config, key, &subConfig) {
      let handle = ObjectHandle<RimeConfig>()
      configs[handle] = subConfig
      return handle
    } else {
      return nil
    }
  }
  public func set(
    _ value: ObjectHandle<RimeConfig>, forKey key: String, in config: ObjectHandle<RimeConfig>
  ) throws(RimeError) -> Bool {
    guard var config = configs[config] else {
      throw RimeError.invalidHandle(kind: .config, id: config.id)
    }
    guard var valueConfig = configs[value] else {
      throw RimeError.invalidHandle(kind: .config, id: value.id)
    }
    return rimeApi.config_set_item(&config, key, &valueConfig)
  }
  public func removeValue(forKey key: String, in config: ObjectHandle<RimeConfig>) throws(RimeError)
    -> Bool
  {
    guard var config = configs[config] else {
      throw RimeError.invalidHandle(kind: .config, id: config.id)
    }
    return rimeApi.config_clear(&config, key)
  }

  public func update(signature: String, for config: ObjectHandle<RimeConfig>) throws(RimeError)
    -> Bool
  {
    guard var config = configs[config] else {
      throw RimeError.invalidHandle(kind: .config, id: config.id)
    }
    return rimeApi.config_update_signature(&config, signature)
  }

  public func load(yaml: String, into config: ObjectHandle<RimeConfig>) throws(RimeError) -> Bool {
    guard var config = configs[config] else {
      throw RimeError.invalidHandle(kind: .config, id: config.id)
    }
    return rimeApi.config_load_string(&config, yaml)
  }

  public func createList(forKey key: String, in config: ObjectHandle<RimeConfig>) throws(RimeError)
    -> Bool
  {
    guard var config = configs[config] else {
      throw RimeError.invalidHandle(kind: .config, id: config.id)
    }
    return rimeApi.config_create_list(&config, key)
  }

  public func createMap(forKey key: String, in config: ObjectHandle<RimeConfig>) throws(RimeError)
    -> Bool
  {
    guard var config = configs[config] else {
      throw RimeError.invalidHandle(kind: .config, id: config.id)
    }
    return rimeApi.config_create_map(&config, key)
  }

  public func listSize(forKey key: String, in config: ObjectHandle<RimeConfig>) throws(RimeError)
    -> Int
  {
    guard var config = configs[config] else {
      throw RimeError.invalidHandle(kind: .config, id: config.id)
    }
    return rimeApi.config_list_size(&config, key)
  }

  public func makeConfig() throws(RimeError) -> ObjectHandle<RimeConfig> {
    let handle = ObjectHandle<RimeConfig>()
    var config = rime_config_t()
    _ = rimeApi.config_init(&config)
    configs[handle] = config
    return handle
  }

}

extension RimeEngine {

  public func beginMap(forKey key: String, in config: ObjectHandle<RimeConfig>) throws(RimeError)
    -> ObjectHandle<RimeConfigIterator>
  {
    let handle = ObjectHandle<RimeConfigIterator>()
    var iterator = rime_config_iterator_t()
    guard var config = configs[config] else {
      throw RimeError.invalidHandle(kind: .config, id: config.id)
    }
    _ = rimeApi.config_begin_map(&iterator, &config, key)
    configIterators[handle] = iterator
    return handle
  }

  public func beginList(forKey key: String, in config: ObjectHandle<RimeConfig>) throws(RimeError)
    -> ObjectHandle<RimeConfigIterator>
  {
    let handle = ObjectHandle<RimeConfigIterator>()
    var iterator = rime_config_iterator_t()
    guard var config = configs[config] else {
      throw RimeError.invalidHandle(kind: .config, id: config.id)
    }
    _ = rimeApi.config_begin_list(&iterator, &config, key)
    configIterators[handle] = iterator
    return handle
  }

  public func advanceConfigIterator(_ iterator: ObjectHandle<RimeConfigIterator>) throws(RimeError)
    -> RimeConfigLocation?
  {
    guard var rime_iterator = configIterators[iterator] else {
      throw RimeError.invalidHandle(kind: .configIterator, id: iterator.id)
    }
    if rimeApi.config_next(&rime_iterator) {
      configIterators[iterator] = rime_iterator
      return RimeConfigLocation(
        index: rime_iterator.index,
        key: rime_iterator.key.map { String(cString: $0) },
        path: rime_iterator.path.map { String(cString: $0) }
      )
    }
    return nil
  }

  public func endConfigIterator(_ iterator: ObjectHandle<RimeConfigIterator>) throws(
    RimeError
  ) {
    guard var rime_iterator = configIterators[iterator] else {
      return
    }
    _ = rimeApi.config_end(&rime_iterator)
    configIterators.removeValue(forKey: iterator)
  }
}
