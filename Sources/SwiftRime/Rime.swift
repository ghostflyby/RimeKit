import CLibrime
import Foundation

public protocol Rime {
    func setup(with traits: RimeTraits) async

    func setNotificationHandler(_ handler: @escaping RimeNotificationHandler) async

    func initialize(with traits: RimeTraits) async
    func finalize() async

    func startMaintenance(fullCheck: Bool) async -> Bool
    var isMaintenanceMode: Bool { get }
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

    func processKey(_ keyCode: CInt, modifierMask: CInt) async -> Bool
    func commitComposition() async -> Bool
    func clearComposition() async

    func commit(for sessionID: RimeSessionID) async -> RimeCommit?
    func status(for sessionID: RimeSessionID) async -> RimeStatus?
    func context(for sessionID: RimeSessionID) async -> RimeContext?

    func option(named option: String, for sessionID: RimeSessionID) async -> Bool
    func setOption(_ option: String, value: Bool, for sessionID: RimeSessionID) async
    func property(named property: String, for sessionID: RimeSessionID) async -> String?
    func setProperty(_ property: String, value: String, for sessionID: RimeSessionID) async

    var schemaList: RimeSchemaList { get }
    func currentSchema(for sessionID: RimeSessionID) async -> String?
    func selectSchema(_ schemaID: String, for sessionID: RimeSessionID) async -> Bool

    func openSchema(_ schemaID: String) async -> RimeConfig?
    func openConfig(_ configID: String) async -> RimeConfig?

    func close(config: borrowing RimeConfig) async -> Bool

    func string(forKey key: String, in config: borrowing RimeConfig) async -> String?
    func int(forKey key: String, in config: borrowing RimeConfig) async -> Int32?
    func bool(forKey key: String, in config: borrowing RimeConfig) async -> Bool?
    func double(forKey key: String, in config: borrowing RimeConfig) async -> Double?
    func item(forKey key: String, in config: borrowing RimeConfig) async -> RimeConfig?
    func set(_ value: String, forKey key: String, in config: borrowing RimeConfig) async -> Bool
    func set(_ value: Int32, forKey key: String, in config: borrowing RimeConfig) async -> Bool
    func set(_ value: Bool, forKey key: String, in config: borrowing RimeConfig) async -> Bool
    func set(_ value: Double, forKey key: String, in config: borrowing RimeConfig) async -> Bool
    func set(
        _ value: borrowing RimeConfig, forKey key: String, in config: borrowing RimeConfig
    ) async -> Bool

    func removeValue(forKey key: String, in config: borrowing RimeConfig) async -> Bool

    func update(signature: String, for config: borrowing RimeConfig) async -> Bool
    func beginMap(forKey key: String, in config: borrowing RimeConfig) async -> RimeConfigIterator
    func beginList(forKey key: String, in config: borrowing RimeConfig) async -> RimeConfigIterator
    func advanceConfigIterator(_ iterator: inout RimeConfigIterator) async
    func endConfigIterator(_ iterator: inout RimeConfigIterator) async

    func makeConfig() async -> RimeConfig
    func load(yaml: String, into config: borrowing RimeConfig) async -> Bool
    func createList(forKey key: String, in config: borrowing RimeConfig) async -> Bool

    func createMap(forKey key: String, in config: borrowing RimeConfig) async -> Bool

    func listSize(forKey key: String, in config: borrowing RimeConfig) async -> Int

    var userID: String { get }
    var userDataSyncDirectory: String { get }

    var input: String { get set }
    var caretPosition: Int { get set }
    var version: String { get }

    func selectCandidate(at index: Int, for session: RimeSessionID) async -> Bool
    func selectCandidateOnCurrentPage(at index: Int, for session: RimeSessionID) async -> Bool

    func beginCandidates(for session: RimeSessionID) async -> RimeCandidateIterator
    func advanceCandidateIterator(_ iterator: inout RimeCandidateIterator) async
    func endCandidateIterator(_ iterator: inout RimeCandidateIterator) async

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

    var sharedDataDirectory: String { get }
    var userDataDirectory: String { get }
    var prebuiltDataDirectory: String { get }
    var stagingDirectory: String { get }
    var syncDirectory: String { get }
}

public enum RimeState {
    case on
    case off
}

public enum RimePageDirection {
    case forward
    case backward
}
