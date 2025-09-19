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
    func deploySchema(schemaId: String) -> Bool
    func deployConfig(filename: String, versionKey: String) -> Bool
    func syncUserData() -> Bool

    func createSession() -> RimeSessionId
    func findSession(id: RimeSessionId) -> Bool
    func destroySession(id: RimeSessionId) -> Bool
    func cleanupStaleSessions()
    func cleanupAllSessions()

    func processKey(keycode: CInt, mask: CInt) async -> Bool
    func commitComposition() async -> Bool
    func clearComposition() async

    func commit(session: RimeSessionId) -> RimeCommit?
    func status(id: RimeSessionId) async -> RimeStatus?
    func context(session: RimeSessionId) -> RimeContext?

    func getOption(session: RimeSessionId, option: String) -> Bool
    func setOption(session: RimeSessionId, option: String, value: Bool)
    func getProperty(session: RimeSessionId, prop: String) -> String?
    func setProperty(session: RimeSessionId, prop: String, value: String)

    var schemaList: RimeSchemaList { get }
    func currentSchema(session: RimeSessionId) -> String?
    func selectSchema(session: RimeSessionId, schemaId: String) -> Bool

    func open(schemaId: String) -> RimeConfig?
    func open(configId: String) -> RimeConfig?

    func close(config: borrowing RimeConfig) -> Bool

    func string(forKey key: String, inConfig config: borrowing RimeConfig) -> String?
    func int(forKey key: String, inConfig config: borrowing RimeConfig) -> Int32?
    func bool(forKey key: String, inConfig config: borrowing RimeConfig) -> Bool?
    func double(forKey key: String, inConfig config: borrowing RimeConfig) -> Double?
    func item(forKey key: String, inConfig config: borrowing RimeConfig) -> RimeConfig?
    func set(_ value: String, forKey key: String, inConfig config: borrowing RimeConfig) -> Bool
    func set(_ value: Int32, forKey key: String, inConfig config: borrowing RimeConfig) -> Bool
    func set(_ value: Bool, forKey key: String, inConfig config: borrowing RimeConfig) -> Bool
    func set(_ value: Double, forKey key: String, inConfig config: borrowing RimeConfig) -> Bool
    func set(
        _ value: borrowing RimeConfig, forKey key: String, inConfig config: borrowing RimeConfig
    )
        -> Bool

    func remove(forKey key: String, inConfig config: borrowing RimeConfig) -> Bool

    func update(signature: String, forConfig config: borrowing RimeConfig) -> Bool
    func beginMap(forKey key: String, inConfig config: borrowing RimeConfig) -> RimeConfigIterator
    func beginList(forKey key: String, inConfig config: borrowing RimeConfig) -> RimeConfigIterator
    func next(configIterator: inout RimeConfigIterator)
    func end(configIterator: inout RimeConfigIterator)

    func initConfig() -> RimeConfig
    func load(yaml: String, into config: borrowing RimeConfig) -> Bool
    func createList(forKey key: String, inConfig config: borrowing RimeConfig) -> Bool

    func createMap(forKey key: String, inConfig config: borrowing RimeConfig) -> Bool

    func listSize(forKey key: String, inConfig config: borrowing RimeConfig) -> Int

    //   // testing

    //   Bool (*simulate_key_sequence)(RimeSessionId session_id,
    //                                 const char* key_sequence);

    //   // module

    //   Bool (*register_module)(RimeModule* module);
    //   RimeModule* (*find_module)(const char* module_name);

    //   Bool (*run_task)(const char* task_name);

    var userId: String { get }
    var userDataSyncDirectory: String { get }

    var input: String { get set }
    var caretPosition: Int { get set }
    var version: String { get }

    func selectCandidate(at: Int, for: RimeSessionId) -> Bool
    func selectCandidateOnCurrentPage(at: Int, for: RimeSessionId) -> Bool

    func beginCandidates(for session: RimeSessionId) -> RimeCandidateIterator
    func next(candidateIterator: inout RimeCandidateIterator)
    func end(candidateIterator: inout RimeCandidateIterator)

    func stateLabel(for key: String, state: RimeState, in session: RimeSessionId) -> String?
    func stateLabel(for key: String, state: RimeState, abbreviated: Bool, in session: RimeSessionId)
        -> String?

    func removeCandidate(at: Int, for session: RimeSessionId) -> Bool
    func removeCandidateOnCurrentPage(at: Int, for session: RimeSessionId) -> Bool

    func highlightCandidate(at: Int, for session: RimeSessionId) -> Bool
    func highlightCandidateOnCurrentPage(at: Int, for session: RimeSessionId) -> Bool
    func page(_ direction: RimePageDirection, for session: RimeSessionId) -> Bool

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
