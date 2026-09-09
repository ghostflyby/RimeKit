#if os(macOS)
import Distributed
import DistributedXPC
import Foundation
import Testing
import XPC

@testable import RimeKit

// MARK: - 单元级:手写 marshal 往返(§3.6 防漂移护栏)

struct XPCMarshalRoundTripTests {
  @Test func commitRoundTrip() throws {
    let original = RimeCommit(text: "hello")
    let restored = try RimeCommit.unmarshal(from: original.marshal())
    #expect(restored.text == original.text)
  }

  @Test func statusRoundTrip() throws {
    let original = RimeStatus(
      schemaID: "luna_pinyin", schemaName: "明月拼音", isDisabled: false, isComposing: true,
      isASCIIMode: false, isFullShape: false, isSimplified: true, isTraditional: false,
      isASCIIPunctuation: false)
    let restored = try RimeStatus.unmarshal(from: original.marshal())
    #expect(restored.schemaID == original.schemaID && restored.isSimplified == original.isSimplified)
  }

  @Test func contextRoundTrip() throws {
    let candidate = RimeCandidate(text: "你好", comment: "ni hao")
    let menu = RimeMenu(
      pageSize: 5, pageNumber: 0, isLastPage: false, highlightedCandidateIndex: 1,
      candidates: [candidate, candidate], selectKeys: "123456")
    let composition = RimeComposition(
      length: 4, cursorPosition: 2, selectionStart: 0, selectionEnd: 0, preedit: "nihao")
    let original = RimeContext(
      composition: composition, menu: menu, commitTextPreview: "你好",
      selectLabels: ["1", "2"])
    let restored = try RimeContext.unmarshal(from: original.marshal())
    #expect(restored.commitTextPreview == "你好")
    #expect(restored.menu.candidates.first?.text == "你好")
    #expect(restored.composition.preedit == "nihao")
  }

  @Test func traitsRoundTrip() throws {
    var original = RimeTraits(
      sharedDataDir: "/s", userDataDir: "/u", distributionName: "n",
      distributionCodeName: "c", distributionVersion: "1", appName: "a",
      minLogLevel: .warning)
    original.modules = ["default"]
    original.logDir = "/log"
    let restored = try RimeTraits.unmarshal(from: original.marshal())
    #expect(restored.sharedDataDir == "/s" && restored.modules == ["default"])
    #expect(restored.logDir == "/log" && restored.prebuiltDataDir == nil)
    #expect(restored.minLogLevel == .warning)
  }

  @Test func errorRoundTrip() throws {
    let id = UUID()
    for error in [
      RimeError.invalidHandle(kind: .config, id: id),
      RimeError.invalidHandle(kind: .candidateIterator, id: id),
      RimeError.sessionNotFound(RimeSessionID(rawValue: 7)),
      RimeError.engineNotInitialized, RimeError.maintenanceMode,
      RimeError.deployFailed(operation: "deploy"), RimeError.invalidArgument("bad"),
      RimeError.apiUnavailable("get_version"),
    ] {
      #expect(try RimeError.unmarshal(from: error.marshal()) == error)
    }
  }

  @Test func locationSchemaAndNotificationRoundTrip() throws {
    let location = RimeConfigLocation(index: 3, key: "k", path: nil)
    #expect(try RimeConfigLocation.unmarshal(from: location.marshal()).index == 3)

    let list = RimeSchemaList(items: [RimeSchemaListItem(schemaID: "a", name: "A")])
    #expect(try RimeSchemaList.unmarshal(from: list.marshal()).items.first?.schemaID == "a")

    if case .deploy = try RimeNotificationType.unmarshal(from: RimeNotificationType.deploy.marshal()) {
    } else { Issue.record("deploy 还原失败") }
    if case .unknown(let raw) = try RimeNotificationType.unmarshal(
      from: RimeNotificationType.unknown("x").marshal()) {
      #expect(raw == "x")
    } else { Issue.record("unknown 还原失败") }

    #expect(try RimeState.unmarshal(from: RimeState.on.marshal()) == .on)
    #expect(try RimePageDirection.unmarshal(from: RimePageDirection.backward.marshal()) == .backward)
  }
}
#endif
