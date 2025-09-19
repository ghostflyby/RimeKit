import CLibrime

public struct RimeSchemaListItem: Sendable,Codable {
    let schemaId: String
    let name: String
}

fileprivate extension RimeSchemaListItem {
    init(_ cStruct: CLibrime.RimeSchemaListItem) {
        schemaId = String(cString: cStruct.schema_id)
        name = String(cString: cStruct.name)
    }
}

public struct RimeSchemaList: Sendable,Codable {
    let items: [RimeSchemaListItem]
}

extension RimeSchemaList {
    fileprivate init(_ cStruct: CLibrime.RimeSchemaList) {
        let buffer = UnsafeBufferPointer(
            start: cStruct.list,
            count: Int(cStruct.size)
        )
        items = buffer.map { RimeSchemaListItem($0) }
    }
}

extension RimeEngine {
    public var schemaList : RimeSchemaList {
        var schemaList = rime_schema_list_t()
        defer { rimeApi.free_schema_list(&schemaList) }
        return if rimeApi.get_schema_list(&schemaList) {
            RimeSchemaList(schemaList)
        } else {
            RimeSchemaList(items: [])
        }
    }

    fileprivate func currentSchema(session: RimeSessionId) -> String? {
        let bufferSize = 1024
        let buffer: [CChar] = Array(repeating: 0, count: bufferSize)
        return buffer.withUnsafeBufferPointer { ptr in
            return
                if rimeApi.get_current_schema(
                    session.id,
                    UnsafeMutablePointer(mutating: ptr.baseAddress),
                    bufferSize
                )
            {
                String(cString: ptr.baseAddress!)
            } else {
                nil
            }
        }
    }

   fileprivate func selectSchema(session: RimeSessionId, schemaId: String) -> Bool {
        rimeApi.select_schema(session.id, schemaId)
    }

}

public extension RimeSession {
    var schemaList: RimeSchemaList {
        get async {
            await engine.schemaList
        }
    }
    
    var schemas: [RimeSchemaListItem] {
        get async {
            await engine.schemaList.items
        }
    }
    
    func selectSchema(id: String) async -> Bool {
        await engine.selectSchema(session: self.id, schemaId: id)
    }
    
    func select(schema: RimeSchemaListItem) async -> Bool {
        await engine.selectSchema(session: self.id, schemaId: schema.schemaId)
    }
}
