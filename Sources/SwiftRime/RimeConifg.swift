import CLibrime

private struct rime_config_wrapper: @unchecked Sendable {
    let raw: rime_config_t
}

public class RimeConfig: @unchecked Sendable {
    init(engine: RimeEngine) async {
        self.engine = engine
        self.wrapper = await engine.configInit()
    }

    fileprivate let wrapper: rime_config_wrapper
    fileprivate let engine: RimeEngine
    fileprivate init(ptr: rime_config_t, engine: RimeEngine) {
        self.wrapper = rime_config_wrapper(raw: ptr)
        self.engine = engine
    }
    deinit {
        let ptr = wrapper
        let engine = engine
        Task.detached {
            await engine.close(config: ptr.raw)
        }
    }
}

extension RimeEngine {
    public func open(schemaId: String) -> RimeConfig? {
        var config: rime_config_t = rime_config_t()
        return if rimeApi.schema_open(schemaId, &config) {
            RimeConfig(ptr: config, engine: self)
        } else {
            nil
        }
    }
    public func open(configId: String) -> RimeConfig? {
        var config: rime_config_t = rime_config_t()
        return if rimeApi.config_open(configId, &config) {
            RimeConfig(ptr: config, engine: self)
        } else {
            nil
        }
    }
}

extension RimeConfig {
    public func string(forKey: String) async -> String? {
        await engine.string(forKey: forKey, in: self)
    }
    public func set(_ value: String, forKey: String) async -> Bool {
        await engine.set(value, forKey: forKey, in: self)
    }
    public func int(forKey: String) async -> Int32? {
        await engine.int(forKey: forKey, in: self)
    }
    public func set(_ value: Int32, forKey: String) async -> Bool {
        await engine.set(value, forKey: forKey, in: self)
    }
    public func bool(forKey: String) async -> Bool? {
        await engine.bool(forKey: forKey, in: self)
    }
    public func set(_ value: Bool, forKey: String) async -> Bool {
        await engine.set(value, forKey: forKey, in: self)
    }
    public func double(forKey: String) async -> Double? {
        await engine.double(forKey: forKey, in: self)
    }
    public func set(_ value: Double, forKey: String) async -> Bool {
        await engine.set(value, forKey: forKey, in: self)
    }
    public func item(forKey: String) async -> RimeConfig? {
        await engine.item(forKey: forKey, in: self)
    }
    public func set(_ value: borrowing RimeConfig, forKey: String) async -> Bool {
        await engine.set(value, forKey: forKey, in: self)
    }

    public func remove(forKey key: String) async -> Bool {
        await engine.remove(forKey: key, in: self)
    }
}

extension RimeEngine {
    public func close(config: rime_config_t) -> Bool {
        var config = config
        return rimeApi.config_close(&config)
    }

    public func string(forKey key: String, in config: borrowing RimeConfig) -> String? {
        var config = config.wrapper.raw

        let cStr = rimeApi.config_get_cstring(&config, key)
        defer { cStr?.deallocate() }
        return if let cStr = cStr {
            String(cString: cStr)
        } else {
            nil
        }
    }

    public func set(_ value: String, forKey key: String, in config: borrowing RimeConfig) -> Bool {
        var config = config.wrapper.raw
        return rimeApi.config_set_string(&config, key, value)
    }

    public func int(forKey key: String, in config: borrowing RimeConfig) -> Int32? {
        var config = config.wrapper.raw
        var value: Int32 = 0
        return if rimeApi.config_get_int(&config, key, &value) {
            value
        } else {
            nil
        }
    }
    public func set(_ value: Int32, forKey key: String, in config: borrowing RimeConfig) -> Bool {
        var config = config.wrapper.raw
        return rimeApi.config_set_int(&config, key, value)
    }
    public func bool(forKey key: String, in config: borrowing RimeConfig) -> Bool? {
        var config = config.wrapper.raw
        var value: Bool = false
        return if rimeApi.config_get_bool(&config, key, &value) {
            value
        } else {
            nil
        }
    }
    public func set(_ value: Bool, forKey key: String, in config: borrowing RimeConfig) -> Bool {
        var config = config.wrapper.raw
        return rimeApi.config_set_bool(&config, key, value)
    }
    public func double(forKey key: String, in config: borrowing RimeConfig) -> Double? {
        var config = config.wrapper.raw
        var value: Double = 0
        return if rimeApi.config_get_double(&config, key, &value) {
            value
        } else {
            nil
        }
    }
    public func set(_ value: Double, forKey key: String, in config: borrowing RimeConfig) -> Bool {
        var config = config.wrapper.raw
        return rimeApi.config_set_double(&config, key, value)
    }
    public func item(forKey key: String, in config: borrowing RimeConfig) -> RimeConfig? {
        var config = config.wrapper.raw
        var subConfig: rime_config_t = rime_config_t()
        return if rimeApi.config_get_item(&config, key, &subConfig) {
            RimeConfig(ptr: subConfig, engine: self)
        } else {
            nil
        }
    }
    public func set(
        _ value: borrowing RimeConfig, forKey key: String, in config: borrowing RimeConfig
    ) -> Bool {
        var config = config.wrapper.raw
        var value = value.wrapper.raw
        return rimeApi.config_set_item(&config, key, &value)
    }
    public func remove(forKey key: String, in config: borrowing RimeConfig) -> Bool {
        var config = config.wrapper.raw
        return rimeApi.config_clear(&config, key)
    }

    public func configCreateList(config: borrowing RimeConfig, key: String) -> Bool {
        var config = config.wrapper.raw
        return rimeApi.config_create_list(&config, key)
    }

    public func configCreateMap(config: borrowing RimeConfig, key: String) -> Bool {
        var config = config.wrapper.raw
        return rimeApi.config_create_map(&config, key)
    }

    public func configListSize(config: borrowing RimeConfig, key: String) -> Int {
        var config = config.wrapper.raw
        return rimeApi.config_list_size(&config, key)
    }

    fileprivate func configInit() -> rime_config_wrapper {
        var config = rime_config_t()
        _ = rimeApi.config_init(&config)
        return rime_config_wrapper(raw: config)
    }

}
