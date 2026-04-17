import Foundation
import RimeDynamic

public protocol Rime: Sendable {
  func setup(with traits: RimeTraits) async

  func setNotificationHandler(_ handler: @escaping RimeNotificationHandler) async

  func initialize(with traits: RimeTraits) async
  func finalize() async

  func startMaintenance(fullCheck: Bool) async -> Bool
  var isMaintenanceMode: Bool { get async }
  func joinMaintenanceThread() async

  func initializeDeployer(with traits: RimeTraits) async
  func prebuild() async -> Bool
  func deploy() async -> Bool
  func deploySchema(withID schemaID: String) async -> Bool
  func deployConfig(filename: String, versionKey: String) async -> Bool
  func syncUserData() async -> Bool

  func createSession() async -> RimeSessionID
  func findSession(with sessionID: RimeSessionID) async -> Bool
  func destroySession(with sessionID: RimeSessionID) async -> Bool
  func cleanupStaleSessions() async
  func cleanupAllSessions() async

  func processKey(keyCode: CInt, modifierMask: CInt, for sessionID: RimeSessionID) async -> Bool
  func commitComposition(for sessionID: RimeSessionID) async -> Bool
  func clearComposition(for sessionID: RimeSessionID) async

  func commit(for sessionID: RimeSessionID) async -> RimeCommit?
  func status(for sessionID: RimeSessionID) async -> RimeStatus?
  func context(for sessionID: RimeSessionID) async -> RimeContext?

  func option(named option: String, for sessionID: RimeSessionID) async -> Bool
  func setOption(_ option: String, value: Bool, for sessionID: RimeSessionID) async
  func property(named property: String, for sessionID: RimeSessionID) async -> String?
  func setProperty(_ property: String, value: String, for sessionID: RimeSessionID) async

  var schemaList: RimeSchemaList { get async }
  func currentSchema(for sessionID: RimeSessionID) async -> String?
  func selectSchema(_ schemaID: String, for sessionID: RimeSessionID) async -> Bool

  func openSchema(_ schemaID: String) async -> ObjectHandle<RimeConfig>?
  func openConfig(_ configID: String) async -> ObjectHandle<RimeConfig>?

  func close(config: borrowing ObjectHandle<RimeConfig>) async -> Bool

  func string(forKey key: String, in config: borrowing ObjectHandle<RimeConfig>) async -> String?
  func int(forKey key: String, in config: borrowing ObjectHandle<RimeConfig>) async -> Int32?
  func bool(forKey key: String, in config: borrowing ObjectHandle<RimeConfig>) async -> Bool?
  func double(forKey key: String, in config: borrowing ObjectHandle<RimeConfig>) async -> Double?
  func item(forKey key: String, in config: borrowing ObjectHandle<RimeConfig>) async
    -> ObjectHandle<
      RimeConfig
    >?
  func set(_ value: String, forKey key: String, in config: borrowing ObjectHandle<RimeConfig>)
    async
    -> Bool
  func set(_ value: Int32, forKey key: String, in config: borrowing ObjectHandle<RimeConfig>)
    async
    -> Bool
  func set(_ value: Bool, forKey key: String, in config: borrowing ObjectHandle<RimeConfig>) async
    -> Bool
  func set(_ value: Double, forKey key: String, in config: borrowing ObjectHandle<RimeConfig>)
    async
    -> Bool
  func set(
    _ value: borrowing ObjectHandle<RimeConfig>, forKey key: String,
    in config: borrowing ObjectHandle<RimeConfig>
  ) async -> Bool

  func removeValue(forKey key: String, in config: borrowing ObjectHandle<RimeConfig>) async
    -> Bool

  func update(signature: String, for config: borrowing ObjectHandle<RimeConfig>) async -> Bool
  func beginMap(forKey key: String, in config: borrowing ObjectHandle<RimeConfig>) async
    -> ObjectHandle<RimeConfigIterator>
  func beginList(forKey key: String, in config: borrowing ObjectHandle<RimeConfig>) async
    -> ObjectHandle<RimeConfigIterator>
  func advanceConfigIterator(_ iterator: ObjectHandle<RimeConfigIterator>) async
    -> RimeConfigLocation?
  func endConfigIterator(_ iterator: ObjectHandle<RimeConfigIterator>) async

  func makeConfig() async -> ObjectHandle<RimeConfig>
  func load(yaml: String, into config: borrowing ObjectHandle<RimeConfig>) async -> Bool
  func createList(forKey key: String, in config: borrowing ObjectHandle<RimeConfig>) async -> Bool

  func createMap(forKey key: String, in config: borrowing ObjectHandle<RimeConfig>) async -> Bool

  func listSize(forKey key: String, in config: borrowing ObjectHandle<RimeConfig>) async -> Int

  var userID: String { get async }
  var userDataSyncDirectory: String { get async }

  func input(for sessionID: RimeSessionID) async -> String?
  func set(input: String, for sessionID: RimeSessionID) async -> Bool
  func caretPosition(for sessionID: RimeSessionID) async -> Int
  func set(caretPosition: Int, for sessionID: RimeSessionID) async
  var version: String { get async }

  func selectCandidate(at index: Int, for session: RimeSessionID) async -> Bool
  func selectCandidateOnCurrentPage(at index: Int, for session: RimeSessionID) async -> Bool

  func beginCandidates(for session: RimeSessionID) async -> ObjectHandle<RimeCandidate>
  func advanceCandidateIterator(_ iterator: ObjectHandle<RimeCandidate>) async
    -> RimeCandidate?
  func endCandidateIterator(_ iterator: ObjectHandle<RimeCandidate>) async

  //   Bool (*user_config_open)(const char* config_id, RimeConfig* config);

  //   Bool (*candidate_list_from_index)(RimeSessionId session_id,
  //                                     RimeCandidateListIterator* iterator,
  //                                     int index);

  func openUserConfig(configId: String) async -> ObjectHandle<RimeConfig>?

  func candidateList(
    fromIndex: Int32, for sessionID: RimeSessionID
  ) async -> ObjectHandle<RimeCandidate>?

  func stateLabel(for key: String, state: RimeState, in session: RimeSessionID) async -> String?
  func stateLabel(
    for key: String,
    state: RimeState,
    abbreviated: Bool,
    in session: RimeSessionID
  ) async -> String?

  func removeCandidate(at index: Int, for session: RimeSessionID) async -> Bool
  func removeCandidateOnCurrentPage(at index: Int, for session: RimeSessionID) async -> Bool

  func highlightCandidate(at index: Int, for session: RimeSessionID) async -> Bool
  func highlightCandidateOnCurrentPage(at index: Int, for session: RimeSessionID) async -> Bool
  func page(_ direction: RimePageDirection, for session: RimeSessionID) async -> Bool

  var sharedDataDirectory: String { get async }
  var userDataDirectory: String { get async }
  var prebuiltDataDirectory: String { get async }
  var stagingDirectory: String { get async }
  var syncDirectory: String { get async }
}

public enum RimeState: Sendable {
  case on
  case off
}

public enum RimePageDirection: Sendable {
  case forward
  case backward
}
