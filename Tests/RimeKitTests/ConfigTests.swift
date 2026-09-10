import Testing

@testable import RimeKit

/// 配置面(参考:librime `config_test.cc` 的读写/遍历语义,经 C API 层展开;
/// 句柄纪律:外来/陈旧句柄抛 `invalidHandle` 而非崩溃)。
@Suite struct ConfigTests {
  @Test(arguments: RimeBackend.allCases)
  func openSchemaReadsCompiledConfig(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let config = try await #require(env.root.openSchema(MinimalRimeData.primarySchemaID))
    #expect(try await env.root.string(forKey: "schema/name", in: config) == MinimalRimeData.primarySchemaName)
    #expect(try await env.root.string(forKey: "schema/schema_id", in: config) == MinimalRimeData.primarySchemaID)
    #expect(try await env.root.int(forKey: "menu/page_size", in: config) == Int32(MinimalRimeData.pageSize))
    #expect(try await env.root.item(forKey: "engine", in: config) != nil)
    // 缺键返回 nil(非错误)。
    #expect(try await env.root.string(forKey: "no/such/key", in: config) == nil)
    #expect(try await env.root.close(config: config) == true)
  }

  @Test(arguments: RimeBackend.allCases)
  func openUnknownSchemaYieldsEmptyConfig(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    // librime 语义:未知方案/配置打开"成功"但得到空配置(可写形态),读任何键得 nil。
    let config = try await #require(env.root.openSchema("rimekit_nonexistent"))
    let schemaID = try await env.root.string(forKey: "schema/schema_id", in: config)
    #expect(schemaID == nil)
    #expect(try await env.root.close(config: config) == true)
  }

  @Test(arguments: RimeBackend.allCases)
  func openDefaultConfigListsSchemas(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let config = try await #require(env.root.openConfig("default"))
    #expect(try await env.root.listSize(forKey: "schema_list", in: config) == 2)
    // librime 配置键语法:列表索引用 `@n`(同 custom patch 约定)。
    #expect(try await env.root.string(forKey: "schema_list/@0/schema", in: config) == MinimalRimeData.primarySchemaID)
    #expect(try await env.root.string(forKey: "schema_list/@1/schema", in: config) == MinimalRimeData.altSchemaID)
    #expect(try await env.root.close(config: config) == true)
  }

  @Test(arguments: RimeBackend.allCases)
  func openUnknownConfigYieldsEmptyConfig(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    // 同上:未知 config 打开为空配置(可写形态)。
    let config = try await #require(env.root.openConfig("nonexistent_config"))
    let any = try await env.root.string(forKey: "any", in: config)
    #expect(any == nil)
    #expect(try await env.root.close(config: config) == true)
  }

  /// makeConfig + 内联 YAML:全类型读/写/删/嵌套/遍历(librime config_test 的 C API 等价物)。
  @Test(arguments: RimeBackend.allCases)
  func inMemoryConfigRoundTrip(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let config = try await env.root.makeConfig()
    #expect(
      try await env.root.load(
        yaml: """
          greeting: 你好
          count: 42
          enabled: true
          ratio: 3.25
          nested:
            inner: 7
          list: [ x, y ]
          """,
        into: config) == true)

    #expect(try await env.root.string(forKey: "greeting", in: config) == "你好")
    #expect(try await env.root.int(forKey: "count", in: config) == 42)
    #expect(try await env.root.bool(forKey: "enabled", in: config) == true)
    #expect(try await env.root.double(forKey: "ratio", in: config) == 3.25)

    let nested = try await #require(env.root.item(forKey: "nested", in: config))
    #expect(try await env.root.int(forKey: "inner", in: nested) == 7)
    #expect(try await env.root.close(config: nested) == true)

    #expect(try await env.root.listSize(forKey: "list", in: config) == 2)
    #expect(try await env.root.string(forKey: "list/@0", in: config) == "x")
    #expect(try await env.root.string(forKey: "list/@1", in: config) == "y")

    // 写回全类型并读回。
    #expect(try await env.root.set("世界", forKey: "greeting", in: config) == true)
    #expect(try await env.root.string(forKey: "greeting", in: config) == "世界")
    #expect(try await env.root.set(Int32(7), forKey: "count", in: config) == true)
    #expect(try await env.root.int(forKey: "count", in: config) == 7)
    #expect(try await env.root.set(false, forKey: "enabled", in: config) == true)
    #expect(try await env.root.bool(forKey: "enabled", in: config) == false)
    #expect(try await env.root.set(1.5, forKey: "ratio", in: config) == true)
    #expect(try await env.root.double(forKey: "ratio", in: config) == 1.5)

    // 动态建表/建列。
    #expect(try await env.root.createMap(forKey: "added/map", in: config) == true)
    #expect(try await env.root.set("v", forKey: "added/map/k", in: config) == true)
    #expect(try await env.root.string(forKey: "added/map/k", in: config) == "v")
    #expect(try await env.root.createList(forKey: "added/list", in: config) == true)
    #expect(try await env.root.set("a", forKey: "added/list/@0", in: config) == true)
    #expect(try await env.root.listSize(forKey: "added/list", in: config) == 1)

    // 子配置整体挂载。
    let value = try await env.root.makeConfig()
    #expect(try await env.root.load(yaml: "p: 1", into: value) == true)
    #expect(try await env.root.set(value, forKey: "added/node", in: config) == true)
    let mounted = try await #require(env.root.item(forKey: "added/node", in: config))
    #expect(try await env.root.int(forKey: "p", in: mounted) == 1)
    #expect(try await env.root.close(config: value) == true)
    #expect(try await env.root.close(config: mounted) == true)

    // 删除(config_clear):读回为 nil;缺键也返回 true(1.16.1 实测语义)。
    #expect(try await env.root.removeValue(forKey: "greeting", in: config) == true)
    #expect(try await env.root.string(forKey: "greeting", in: config) == nil)
    #expect(try await env.root.removeValue(forKey: "no/such/key", in: config) == true)

    // 签名(部署器自定义状态键)。
    #expect(try await env.root.update(signature: "rimekit-test", for: config) == true)

    #expect(try await env.root.close(config: config) == true)
  }

  @Test(arguments: RimeBackend.allCases)
  func mapAndListIterators(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let config = try await env.root.makeConfig()
    #expect(
      try await env.root.load(
        yaml: "map: { a: 1, b: 2 }\nlist: [ p, q, r ]", into: config) == true)

    let mapIterator = try await env.root.beginMap(forKey: "map", in: config)
    var mapKeys: [String] = []
    while let location = try await env.root.advanceConfigIterator(mapIterator) {
      mapKeys.append(try #require(location.key))
    }
    try await env.root.endConfigIterator(mapIterator)
    #expect(mapKeys == ["a", "b"])

    let listIterator = try await env.root.beginList(forKey: "list", in: config)
    var indices: [Int32] = []
    while let location = try await env.root.advanceConfigIterator(listIterator) {
      indices.append(location.index)
    }
    try await env.root.endConfigIterator(listIterator)
    #expect(indices == [0, 1, 2])

    #expect(try await env.root.close(config: config) == true)
  }

  @Test(arguments: RimeBackend.allCases)
  func foreignConfigHandleThrowsInsteadOfCrashing(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let foreign = ObjectHandle<RimeConfig>()
    await #expect(throws: RimeError.invalidHandle(kind: .config, id: foreign.id)) {
      try await env.root.string(forKey: "k", in: foreign)
    }
    await #expect(throws: RimeError.invalidHandle(kind: .config, id: foreign.id)) {
      try await env.root.close(config: foreign)
    }
  }

  @Test(arguments: RimeBackend.allCases)
  func foreignConfigIteratorHandleThrows(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let foreign = ObjectHandle<RimeConfigIterator>()
    await #expect(throws: RimeError.invalidHandle(kind: .configIterator, id: foreign.id)) {
      try await env.root.advanceConfigIterator(foreign)
    }
    // end 幂等容忍(与 config 侧语义一致)。
    try await env.root.endConfigIterator(foreign)
  }

  @Test(arguments: RimeBackend.allCases)
  func closedConfigHandleThrowsOnReuse(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let config = try await #require(env.root.openConfig("default"))
    #expect(try await env.root.close(config: config) == true)
    // 关闭即失效:同一句柄再读抛 invalidHandle(而非悬垂读取)。
    await #expect(throws: RimeError.invalidHandle(kind: .config, id: config.id)) {
      try await env.root.string(forKey: "schema_list", in: config)
    }
  }
}
