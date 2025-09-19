import CLibrime
import Foundation

public protocol Rime {
    func setup(with traits: RimeTraits) async

    func setNotificationHandler(_ handler: @escaping RimeNotificationHandler)

    func initialize(with traits: RimeTraits)
    func finalize()

    func startMaintenance(fullCheck: Bool) -> Bool
    var isMaintenanceMode: Bool { get }
    func joinMaintenanceThread()

    func initializeDeployer(with traits: RimeTraits)
    func prebuild() -> Bool
    func deploy() -> Bool
    func deploySchema(withID schemaID: String) -> Bool
    func deployConfig(filename: String, versionKey: String) -> Bool
    func syncUserData() -> Bool

    func createSession() -> RimeSessionID
    func findSession(with sessionID: RimeSessionID) -> Bool
    func destroySession(with sessionID: RimeSessionID) -> Bool
    func cleanupStaleSessions()
    func cleanupAllSessions()

    func processKey(_ keyCode: CInt, modifierMask: CInt) async -> Bool
    func commitComposition() async -> Bool
    func clearComposition() async

    func commit(for sessionID: RimeSessionID) -> RimeCommit?
    func status(for sessionID: RimeSessionID) async -> RimeStatus?
    func context(for sessionID: RimeSessionID) -> RimeContext?

    func option(named option: String, for sessionID: RimeSessionID) -> Bool
    func setOption(_ option: String, value: Bool, for sessionID: RimeSessionID)
    func property(named property: String, for sessionID: RimeSessionID) -> String?
    func setProperty(_ property: String, value: String, for sessionID: RimeSessionID)

    var schemaList: RimeSchemaList { get }
    func currentSchema(for sessionID: RimeSessionID) -> String?
    func selectSchema(_ schemaID: String, for sessionID: RimeSessionID) -> Bool

    func openSchema(_ schemaID: String) -> RimeConfig?
    func openConfig(_ configID: String) -> RimeConfig?

    func close(config: borrowing RimeConfig) -> Bool

    func string(forKey key: String, in config: borrowing RimeConfig) -> String?
    func int(forKey key: String, in config: borrowing RimeConfig) -> Int32?
    func bool(forKey key: String, in config: borrowing RimeConfig) -> Bool?
    func double(forKey key: String, in config: borrowing RimeConfig) -> Double?
    func item(forKey key: String, in config: borrowing RimeConfig) -> RimeConfig?
    func set(_ value: String, forKey key: String, in config: borrowing RimeConfig) -> Bool
    func set(_ value: Int32, forKey key: String, in config: borrowing RimeConfig) -> Bool
    func set(_ value: Bool, forKey key: String, in config: borrowing RimeConfig) -> Bool
    func set(_ value: Double, forKey key: String, in config: borrowing RimeConfig) -> Bool
    func set(
        _ value: borrowing RimeConfig, forKey key: String, in config: borrowing RimeConfig
    ) -> Bool

    func removeValue(forKey key: String, in config: borrowing RimeConfig) -> Bool

    func update(signature: String, for config: borrowing RimeConfig) -> Bool
    func beginMap(forKey key: String, in config: borrowing RimeConfig) -> RimeConfigIterator
    func beginList(forKey key: String, in config: borrowing RimeConfig) -> RimeConfigIterator
    func advanceConfigIterator(_ iterator: inout RimeConfigIterator)
    func endConfigIterator(_ iterator: inout RimeConfigIterator)

    func makeConfig() -> RimeConfig
    func load(yaml: String, into config: borrowing RimeConfig) -> Bool
    func createList(forKey key: String, in config: borrowing RimeConfig) -> Bool

    func createMap(forKey key: String, in config: borrowing RimeConfig) -> Bool

    func listSize(forKey key: String, in config: borrowing RimeConfig) -> Int

    var userID: String { get }
    var userDataSyncDirectory: String { get }

    var input: String { get set }
    var caretPosition: Int { get set }
    var version: String { get }

    func selectCandidate(at index: Int, for session: RimeSessionID) -> Bool
    func selectCandidateOnCurrentPage(at index: Int, for session: RimeSessionID) -> Bool

    func beginCandidates(for session: RimeSessionID) -> RimeCandidateIterator
    func advanceCandidateIterator(_ iterator: inout RimeCandidateIterator)
    func endCandidateIterator(_ iterator: inout RimeCandidateIterator)

    func stateLabel(for key: String, state: RimeState, in session: RimeSessionID) -> String?
    func stateLabel(
        for key: String,
        state: RimeState,
        abbreviated: Bool,
        in session: RimeSessionID
    ) -> String?

    func removeCandidate(at index: Int, for session: RimeSessionID) -> Bool
    func removeCandidateOnCurrentPage(at index: Int, for session: RimeSessionID) -> Bool

    func highlightCandidate(at index: Int, for session: RimeSessionID) -> Bool
    func highlightCandidateOnCurrentPage(at index: Int, for session: RimeSessionID) -> Bool
    func page(_ direction: RimePageDirection, for session: RimeSessionID) -> Bool

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
