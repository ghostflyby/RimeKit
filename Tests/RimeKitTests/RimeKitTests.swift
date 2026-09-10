import Foundation
import RimeDynamic
import Testing

@testable import RimeKit

struct HandleAndIDTests {
  @Test func objectHandleCodableRoundTrip() throws {
    let handle = ObjectHandle<RimeKit.RimeConfig>()
    let data = try JSONEncoder().encode(handle)
    let decoded = try JSONDecoder().decode(ObjectHandle<RimeKit.RimeConfig>.self, from: data)
    #expect(decoded == handle)
    #expect(decoded.id == handle.id)
  }

  @Test func rimeSessionIDCodableRoundTrip() throws {
    let id = RimeSessionID(rawValue: 0x1234_5678)
    let data = try JSONEncoder().encode(id)
    let decoded = try JSONDecoder().decode(RimeSessionID.self, from: data)
    #expect(decoded == id)
    #expect(decoded.rawValue == 0x1234_5678)
  }
}

struct RimeErrorTests {
  @Test func equalityAndHashability() {
    let zero = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    let a = RimeError.invalidHandle(kind: .config, id: zero)
    let b = RimeError.invalidHandle(kind: .config, id: zero)
    let c = RimeError.invalidHandle(kind: .configIterator, id: zero)
    #expect(a == b)
    #expect(a != c)
    #expect(Set([a, b, c]).count == 2)
  }
}

struct RimeTraitsTests {
  @Test func publicInitAndCStructure() {
    var traits = RimeTraits(
      sharedDataDir: "/tmp/rime-shared",
      userDataDir: "/tmp/rime-user",
      distributionName: "RimeKit",
      distributionCodeName: "dev.rimekit",
      distributionVersion: "0.1",
      appName: "RimeKitTests",
      minLogLevel: .warning
    )
    traits.modules = ["default"]

    var c = rime_traits_t.rimeStructInit()
    let handle = traits.toCStructure(&c)
    #expect(String(cString: c.shared_data_dir) == "/tmp/rime-shared")
    #expect(String(cString: c.user_data_dir) == "/tmp/rime-user")
    #expect(String(cString: c.distribution_name) == "RimeKit")
    #expect(String(cString: c.distribution_code_name) == "dev.rimekit")
    #expect(String(cString: c.distribution_version) == "0.1")
    #expect(String(cString: c.app_name) == "RimeKitTests")
    #expect(c.min_log_level == RimeLogLevel.warning.rawValue)
    if let modules = c.modules {
      let first = modules.pointee
      #expect(first != nil && String(cString: first!) == "default")
    } else {
      Issue.record("modules array missing")
    }
    _ = handle  // 保持句柄存活至断言结束
  }
}

@Suite(.serialized)
struct RimeEngineSmokeTests {
  @Test func invalidHandleThrowsInsteadOfCrashing() async {
    let root = RimeServiceRoot.localShared
    let foreign = ObjectHandle<RimeKit.RimeConfig>()
    await #expect(throws: RimeError.invalidHandle(kind: .config, id: foreign.id)) {
      _ = try engine.string(forKey: "x", in: foreign)
    }
  }

  @Test func versionSmoke() async throws {
    // 未初始化引擎上 get_version 允许为空(抛 apiUnavailable)或不为空,只要不崩溃。
    _ = try? await RimeServiceRoot.localShared.version()
  }

  @Test func sessionFacadeInvalidHandlePassthrough() async {
    // 门面将引擎的 typed error 原样透传,不吞不换。
    let root = RimeServiceRoot.localShared
    let foreign = ObjectHandle<RimeKit.RimeConfig>()
    do {
      _ = try engine.string(forKey: "x", in: foreign)
      Issue.record("expected throw")
    } catch {
      #expect((error as? RimeError) == .invalidHandle(kind: .config, id: foreign.id))
    }
  }
}
