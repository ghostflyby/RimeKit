// SPDX-License-Identifier: MPL-2.0
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import RimeDynamic

/// `ObjectHandle` 的幽灵标记类型:仅用于在类型层面区分配置迭代器句柄,不存在实例。
/// 保持 Copyable:线缆序列化(XPCMarshal)要求句柄类型可复制传递。
public enum RimeConfigIterator: Sendable {}

public struct ObjectHandle<T>: Sendable, Codable, Hashable {
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
  internal let root: Rime
  fileprivate init(handle: ObjectHandle<RimeConfig>, root: Rime) {
    self.handle = handle
    self.root = root
  }
  deinit {
    let root = root
    let handle = handle
    Task { try? await root.close(config: handle) }
  }
}

extension Rime {
  func engineOpenSchema(schemaID: String) throws(RimeError) -> ObjectHandle<RimeConfig>? {
    var config: rime_config_t = rime_config_t()
    if rimeApi.schema_open(schemaID, &config) {
      let handle = ObjectHandle<RimeConfig>()
      configs[handle] = config
      return handle
    } else {
      return nil
    }
  }

  func engineOpenConfig(configID: String) throws(RimeError) -> ObjectHandle<RimeConfig>? {
    var config: rime_config_t = rime_config_t()
    if rimeApi.config_open(configID, &config) {
      let handle = ObjectHandle<RimeConfig>()
      configs[handle] = config
      return handle
    } else {
      return nil
    }
  }

  func engineOpenUserConfig(configId: String) throws(RimeError) -> ObjectHandle<RimeConfig>? {
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
  public func string(forKey: String) async throws -> String? {
    try await root.string(forKey: forKey, in: self.handle)
  }
  public func set(_ value: String, forKey: String) async throws -> Bool {
    try await root.set(value, forKey: forKey, in: self.handle)
  }
  public func int(forKey: String) async throws -> Int32? {
    try await root.int(forKey: forKey, in: self.handle)
  }
  public func set(_ value: Int32, forKey: String) async throws -> Bool {
    try await root.set(value, forKey: forKey, in: self.handle)
  }
  public func bool(forKey: String) async throws -> Bool? {
    try await root.bool(forKey: forKey, in: self.handle)
  }
  public func set(_ value: Bool, forKey: String) async throws -> Bool {
    try await root.set(value, forKey: forKey, in: self.handle)
  }
  public func double(forKey: String) async throws -> Double? {
    try await root.double(forKey: forKey, in: self.handle)
  }
  public func set(_ value: Double, forKey: String) async throws -> Bool {
    try await root.set(value, forKey: forKey, in: self.handle)
  }
  public func item(forKey: String) async throws -> RimeConfig? {
    if let handle = try await root.item(forKey: forKey, in: self.handle) {
      RimeConfig(handle: handle, root: root)
    } else {
      nil
    }
  }
  public func set(_ value: borrowing RimeConfig, forKey: String) async throws -> Bool {
    try await root.set(value.handle, forKey: forKey, in: self.handle)
  }

  public func removeValue(forKey key: String) async throws -> Bool {
    try await root.removeValue(forKey: key, in: self.handle)
  }
}

extension Rime {

  func engineClose(config: ObjectHandle<RimeConfig>) throws(RimeError) -> Bool {
    // 关闭即从句柄表移除:句柄一次性,复用抛 invalidHandle 而非悬垂读取已释放的
    // rime_config_t(重复 close——如显式 close 与门面 deinit 竞合——由此自然幂等化)。
    guard var config = configs.removeValue(forKey: config) else {
      throw RimeError.invalidHandle(kind: .config, id: config.id)
    }
    return rimeApi.config_close(&config)
  }

  func engineString(forKey key: String, in config: ObjectHandle<RimeConfig>) throws(RimeError)
    -> String?
  {
    guard var config = configs[config] else {
      throw RimeError.invalidHandle(kind: .config, id: config.id)
    }

    // config_get_cstring 返回 const char*:借用指针,所有权在配置、生命周期与配置
    // 一致(头文件签名 const;API 无配套 free 入口)。只能拷贝,释放即堆损坏
    // ——malloc abort 已由 ConfigTests 实证。
    guard let cStr = rimeApi.config_get_cstring(&config, key) else {
      return nil
    }
    return String(cString: cStr)
  }

  func engineSet(value: String, forKey key: String, in config: ObjectHandle<RimeConfig>)
    throws(RimeError) -> Bool
  {
    guard var config = configs[config] else {
      throw RimeError.invalidHandle(kind: .config, id: config.id)
    }
    return rimeApi.config_set_string(&config, key, value)
  }

  func engineInt(forKey key: String, in config: ObjectHandle<RimeConfig>) throws(RimeError)
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
  func engineSet(value: Int32, forKey key: String, in config: ObjectHandle<RimeConfig>)
    throws(RimeError) -> Bool
  {
    guard var config = configs[config] else {
      throw RimeError.invalidHandle(kind: .config, id: config.id)
    }
    return rimeApi.config_set_int(&config, key, value)
  }
  func engineBool(forKey key: String, in config: ObjectHandle<RimeConfig>) throws(RimeError)
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
  func engineSet(value: Bool, forKey key: String, in config: ObjectHandle<RimeConfig>)
    throws(RimeError) -> Bool
  {
    guard var config = configs[config] else {
      throw RimeError.invalidHandle(kind: .config, id: config.id)
    }
    return rimeApi.config_set_bool(&config, key, value)
  }
  func engineDouble(forKey key: String, in config: ObjectHandle<RimeConfig>) throws(RimeError)
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
  func engineSet(value: Double, forKey key: String, in config: ObjectHandle<RimeConfig>)
    throws(RimeError) -> Bool
  {
    guard var config = configs[config] else {
      throw RimeError.invalidHandle(kind: .config, id: config.id)
    }
    return rimeApi.config_set_double(&config, key, value)
  }
  func engineItem(forKey key: String, in config: ObjectHandle<RimeConfig>) throws(RimeError)
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
  func engineSet(
    value: ObjectHandle<RimeConfig>, forKey key: String, in config: ObjectHandle<RimeConfig>
  ) throws(RimeError) -> Bool {
    guard var config = configs[config] else {
      throw RimeError.invalidHandle(kind: .config, id: config.id)
    }
    guard var valueConfig = configs[value] else {
      throw RimeError.invalidHandle(kind: .config, id: value.id)
    }
    return rimeApi.config_set_item(&config, key, &valueConfig)
  }
  func engineRemoveValue(forKey key: String, in config: ObjectHandle<RimeConfig>) throws(RimeError)
    -> Bool
  {
    guard var config = configs[config] else {
      throw RimeError.invalidHandle(kind: .config, id: config.id)
    }
    return rimeApi.config_clear(&config, key)
  }

  func engineUpdate(signature: String, for config: ObjectHandle<RimeConfig>) throws(RimeError)
    -> Bool
  {
    guard var config = configs[config] else {
      throw RimeError.invalidHandle(kind: .config, id: config.id)
    }
    return rimeApi.config_update_signature(&config, signature)
  }

  func engineLoad(yaml: String, into config: ObjectHandle<RimeConfig>) throws(RimeError) -> Bool {
    guard var config = configs[config] else {
      throw RimeError.invalidHandle(kind: .config, id: config.id)
    }
    return rimeApi.config_load_string(&config, yaml)
  }

  func engineCreateList(forKey key: String, in config: ObjectHandle<RimeConfig>) throws(RimeError)
    -> Bool
  {
    guard var config = configs[config] else {
      throw RimeError.invalidHandle(kind: .config, id: config.id)
    }
    return rimeApi.config_create_list(&config, key)
  }

  func engineCreateMap(forKey key: String, in config: ObjectHandle<RimeConfig>) throws(RimeError)
    -> Bool
  {
    guard var config = configs[config] else {
      throw RimeError.invalidHandle(kind: .config, id: config.id)
    }
    return rimeApi.config_create_map(&config, key)
  }

  func engineListSize(forKey key: String, in config: ObjectHandle<RimeConfig>) throws(RimeError)
    -> Int
  {
    guard var config = configs[config] else {
      throw RimeError.invalidHandle(kind: .config, id: config.id)
    }
    return rimeApi.config_list_size(&config, key)
  }

  func engineMakeConfig() throws(RimeError) -> ObjectHandle<RimeConfig> {
    let handle = ObjectHandle<RimeConfig>()
    var config = rime_config_t()
    _ = rimeApi.config_init(&config)
    configs[handle] = config
    return handle
  }

}

extension Rime {

  func engineBeginMap(forKey key: String, in config: ObjectHandle<RimeConfig>) throws(RimeError)
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

  func engineBeginList(forKey key: String, in config: ObjectHandle<RimeConfig>) throws(RimeError)
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

  func engineAdvanceConfigIterator(_ iterator: ObjectHandle<RimeConfigIterator>) throws(RimeError)
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

  func engineEndConfigIterator(_ iterator: ObjectHandle<RimeConfigIterator>) throws(
    RimeError
  ) {
    guard var rime_iterator = configIterators[iterator] else {
      return
    }
    _ = rimeApi.config_end(&rime_iterator)
    configIterators.removeValue(forKey: iterator)
  }
}
