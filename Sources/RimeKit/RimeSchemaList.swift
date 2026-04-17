import RimeDynamic

public struct RimeSchemaListItem: Sendable, Codable {
  let schemaID: String
  let name: String
}

extension RimeSchemaListItem {
  fileprivate init(_ cStruct: RimeDynamic.RimeSchemaListItem) {
    schemaID = String(cString: cStruct.schema_id)
    name = String(cString: cStruct.name)
  }
}

public struct RimeSchemaList: Sendable, Codable {
  let items: [RimeSchemaListItem]
}

extension RimeSchemaList {
  fileprivate init(_ cStruct: RimeDynamic.RimeSchemaList) {
    let buffer = UnsafeBufferPointer(start: cStruct.list, count: Int(cStruct.size))
    items = buffer.map { RimeSchemaListItem($0) }
  }
}

extension RimeEngine {
  public var schemaList: RimeSchemaList {
    var schemaList = rime_schema_list_t()
    defer { rimeApi.free_schema_list(&schemaList) }
    guard rimeApi.get_schema_list(&schemaList) else {
      return RimeSchemaList(items: [])
    }
    return RimeSchemaList(schemaList)
  }

  public func currentSchema(for sessionID: RimeSessionID) -> String? {
    let bufferSize = 1024
    let buffer: [CChar] = Array(repeating: 0, count: bufferSize)
    return buffer.withUnsafeBufferPointer { pointer in
      guard
        rimeApi.get_current_schema(
          sessionID.rawValue,
          UnsafeMutablePointer(mutating: pointer.baseAddress),
          bufferSize
        )
      else {
        return nil
      }
      return pointer.baseAddress.map { String(cString: $0) }
    }
  }

  public func selectSchema(_ schemaID: String, for sessionID: RimeSessionID) -> Bool {
    rimeApi.select_schema(sessionID.rawValue, schemaID)
  }
}

extension RimeSession {
  public var schemaList: RimeSchemaList {
    get async {
      await engine.schemaList
    }
  }

  public var schemas: [RimeSchemaListItem] {
    get async {
      await engine.schemaList.items
    }
  }

  public func selectSchema(id schemaID: String) async -> Bool {
    await engine.selectSchema(schemaID, for: sessionID)
  }

  public func select(schema: RimeSchemaListItem) async -> Bool {
    await engine.selectSchema(schema.schemaID, for: sessionID)
  }
}
