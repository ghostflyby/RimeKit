import CLibrime
import Foundation

public struct ObjectHandle<T: ~Copyable>: Sendable, Codable, Hashable {
    private let rawValue: UUID
    internal init() {
        rawValue = UUID()
    }
}

final public class RimeConfig: Sendable {

    fileprivate let handle: ObjectHandle<RimeConfig>
    fileprivate let engine: any Rime
    fileprivate init(handle: ObjectHandle<RimeConfig>, engine: any Rime) {
        self.handle = handle
        self.engine = engine
    }
    deinit {
        let ptr = handle
        let engine = engine
        Task.detached {
            await engine.close(config: ptr)
        }
    }
}

extension RimeEngine {
    public func openSchema(_ schemaID: String) -> ObjectHandle<RimeConfig>? {
        var config: rime_config_t = rime_config_t()
        if rimeApi.schema_open(schemaID, &config) {
            let handle = ObjectHandle<RimeConfig>()
            configs[handle] = config
            return handle
        } else {
            return nil
        }
    }

    public func openConfig(_ configID: String) -> ObjectHandle<RimeConfig>? {
        var config: rime_config_t = rime_config_t()
        if rimeApi.config_open(configID, &config) {
            let handle = ObjectHandle<RimeConfig>()
            configs[handle] = config
            return handle
        } else {
            return nil
        }
    }
}

extension RimeConfig {
    public func string(forKey: String) async -> String? {
        await engine.string(forKey: forKey, in: self.handle)
    }
    public func set(_ value: String, forKey: String) async -> Bool {
        await engine.set(value, forKey: forKey, in: self.handle)
    }
    public func int(forKey: String) async -> Int32? {
        await engine.int(forKey: forKey, in: self.handle)
    }
    public func set(_ value: Int32, forKey: String) async -> Bool {
        await engine.set(value, forKey: forKey, in: self.handle)
    }
    public func bool(forKey: String) async -> Bool? {
        await engine.bool(forKey: forKey, in: self.handle)
    }
    public func set(_ value: Bool, forKey: String) async -> Bool {
        await engine.set(value, forKey: forKey, in: self.handle)
    }
    public func double(forKey: String) async -> Double? {
        await engine.double(forKey: forKey, in: self.handle)
    }
    public func set(_ value: Double, forKey: String) async -> Bool {
        await engine.set(value, forKey: forKey, in: self.handle)
    }
    public func item(forKey: String) async -> RimeConfig? {
        if let handle = await engine.item(forKey: forKey, in: self.handle) {
            RimeConfig(handle: handle, engine: engine)
        } else {
            nil
        }
    }
    public func set(_ value: borrowing RimeConfig, forKey: String) async -> Bool {
        await engine.set(value.handle, forKey: forKey, in: self.handle)
    }

    public func removeValue(forKey key: String) async -> Bool {
        await engine.removeValue(forKey: key, in: self.handle)
    }
}

extension RimeEngine {

    public func close(config: ObjectHandle<RimeConfig>) async -> Bool {
        var config = configs[config]!
        return rimeApi.config_close(&config)
    }

    public func string(forKey key: String, in config: ObjectHandle<RimeConfig>) -> String? {
        var config = configs[config]!

        let cStr = rimeApi.config_get_cstring(&config, key)
        defer { cStr?.deallocate() }
        return if let cStr = cStr {
            String(cString: cStr)
        } else {
            nil
        }
    }

    public func set(_ value: String, forKey key: String, in config: ObjectHandle<RimeConfig>)
        -> Bool
    {
        var config = configs[config]!
        return rimeApi.config_set_string(&config, key, value)
    }

    public func int(forKey key: String, in config: ObjectHandle<RimeConfig>) -> Int32? {
        var config = configs[config]!
        var value: Int32 = 0
        return if rimeApi.config_get_int(&config, key, &value) {
            value
        } else {
            nil
        }
    }
    public func set(_ value: Int32, forKey key: String, in config: ObjectHandle<RimeConfig>) -> Bool
    {
        var config = configs[config]!
        return rimeApi.config_set_int(&config, key, value)
    }
    public func bool(forKey key: String, in config: ObjectHandle<RimeConfig>) -> Bool? {
        var config = configs[config]!
        var value: Bool = false
        return if rimeApi.config_get_bool(&config, key, &value) {
            value
        } else {
            nil
        }
    }
    public func set(_ value: Bool, forKey key: String, in config: ObjectHandle<RimeConfig>) -> Bool
    {
        var config = configs[config]!
        return rimeApi.config_set_bool(&config, key, value)
    }
    public func double(forKey key: String, in config: ObjectHandle<RimeConfig>) -> Double? {
        var config = configs[config]!
        var value: Double = 0
        return if rimeApi.config_get_double(&config, key, &value) {
            value
        } else {
            nil
        }
    }
    public func set(_ value: Double, forKey key: String, in config: ObjectHandle<RimeConfig>)
        -> Bool
    {
        var config = configs[config]!
        return rimeApi.config_set_double(&config, key, value)
    }
    public func item(forKey key: String, in config: ObjectHandle<RimeConfig>) -> ObjectHandle<
        RimeConfig
    >? {
        var config = configs[config]!
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
    ) -> Bool {
        var config = configs[config]!
        var value = configs[value]!
        return rimeApi.config_set_item(&config, key, &value)
    }
    public func removeValue(forKey key: String, in config: ObjectHandle<RimeConfig>) -> Bool {
        var config = configs[config]!
        return rimeApi.config_clear(&config, key)
    }

    public func update(signature: String, for config: ObjectHandle<RimeConfig>) async -> Bool {
        var config = configs[config]!
        return rimeApi.config_update_signature(&config, signature)
    }

    public func load(yaml: String, into config: ObjectHandle<RimeConfig>) async -> Bool {
        var config = configs[config]!
        return rimeApi.config_load_string(&config, yaml)
    }

    public func createList(forKey key: String, in config: ObjectHandle<RimeConfig>) -> Bool {
        var config = configs[config]!
        return rimeApi.config_create_list(&config, key)
    }

    public func createMap(forKey key: String, in config: ObjectHandle<RimeConfig>) -> Bool {
        var config = configs[config]!
        return rimeApi.config_create_map(&config, key)
    }

    public func listSize(forKey key: String, in config: ObjectHandle<RimeConfig>) -> Int {
        var config = configs[config]!
        return rimeApi.config_list_size(&config, key)
    }

    public func makeConfig() async -> ObjectHandle<RimeConfig> {
        let handle = ObjectHandle<RimeConfig>()
        var config = rime_config_t()
        _ = rimeApi.config_init(&config)
        configs[handle] = config
        return handle
    }

}

extension RimeEngine {

    public func beginMap(forKey key: String, in config: ObjectHandle<RimeConfig>) async
        -> ObjectHandle<RimeConfigIterator>
    {
        let handle = ObjectHandle<RimeConfigIterator>()
        var iterator = rime_config_iterator_t()
        var config = configs[config]!
        _ = rimeApi.config_begin_map(&iterator, &config, key)
        configIterators[handle] = iterator
        return handle
    }

    public func beginList(forKey key: String, in config: ObjectHandle<RimeConfig>) async
        -> ObjectHandle<RimeConfigIterator>
    {
        let handle = ObjectHandle<RimeConfigIterator>()
        var iterator = rime_config_iterator_t()
        var config = configs[config]!
        _ = rimeApi.config_begin_list(&iterator, &config, key)
        configIterators[handle] = iterator
        return handle
    }

    public func advanceConfigIterator(_ iterator: ObjectHandle<RimeConfigIterator>)
        async// -> ObjectHandle<RimeConfig>?
    {
        var rime_iterator = configIterators[iterator]!
        _ = rimeApi.config_next(&rime_iterator)
        configIterators[iterator] = rime_iterator
    }

    public func endConfigIterator(_ iterator: ObjectHandle<RimeConfigIterator>) async {
        var rime_iterator = configIterators[iterator]!
        _ = rimeApi.config_end(&rime_iterator)
        configIterators.removeValue(forKey: iterator)
    }
}
