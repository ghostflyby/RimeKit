import Foundation
import RimeDynamic
import Synchronization

public typealias RimeNotificationHandler =
  @Sendable (RimeSessionID, RimeNotificationType, String) -> Void

final class Box: @unchecked Sendable {
  let body: RimeNotificationHandler

  init(_ body: @escaping RimeNotificationHandler) {
    self.body = body
  }
}

private func thunk(
  context: UnsafeMutableRawPointer?,
  session: RimeDynamic.RimeSessionId,
  type: UnsafePointer<CChar>?,
  value: UnsafePointer<CChar>?
) {
  guard let context, let type, let value else { return }
  let box = Unmanaged<Box>.fromOpaque(context).takeUnretainedValue()
  box.body(
    RimeSessionID(rawValue: UInt(session)),
    RimeNotificationType(from: String(cString: type)),
    String(cString: value)
  )
}

public enum RimeNotificationType: Codable, Sendable, Hashable {
  case schema
  case option
  case deploy
  case unknown(String)

  init(from string: String) {
    switch string {
    case "schema":
      self = .schema
    case "option":
      self = .option
    case "deploy":
      self = .deploy
    default:
      self = .unknown(string)
    }
  }
}

/// 进程级直接 C 注册(iOS/进程内路径):绕过 actor,librime 回调线程上
/// **同步**执行闭包——实现方严禁重入引擎(§3.7 规则 b)。
///
/// librime 为进程全局单 handler(§1.3),`install` 即替换;退役的 `Box`
/// 保留强引用至进程结束,避免在途回调悬垂(安装次数有界,开销可忽略)。
enum RimeGlobalNotificationHook {
  // NSLock 而非 Mutex:Mutex 的可用性地板(iOS 18)高于包地板(iOS 16)。
  private final class State: @unchecked Sendable {
    let lock = NSLock()
    private var current: Box?
    private var retired: [Box] = []

    func swap(in new: Box) {
      lock.lock()
      defer { lock.unlock() }
      current = new
      retired.append(new)
    }
  }

  private static let state = State()

  static func install(_ handler: @escaping RimeNotificationHandler) {
    let box = Box(handler)
    let context = Unmanaged.passUnretained(box).toOpaque()
    state.swap(in: box)
    rime_get_api_stdbool().pointee.set_notification_handler(thunk, context)
  }

  static func clear() {
    rime_get_api_stdbool().pointee.set_notification_handler(nil, nil)
  }
}

extension Rime {
  var engineNotificationHandler: RimeNotificationHandler? {
    get { opaque?.body }
    set {
      if let newValue {
        engineSetNotificationHandler(handler: newValue)
      } else {
        engineCancelNotificationHandler()
      }
    }
  }

  private func engineSetNotificationHandler(handler closure: @escaping RimeNotificationHandler) {
    let box = Box(closure)
    let context = Unmanaged.passUnretained(box).toOpaque()
    rimeApi.set_notification_handler(thunk, context)
    opaque = box
  }

  func engineSetNotificationHandler(_ handler: @escaping RimeNotificationHandler) {
    engineSetNotificationHandler(handler: handler)
  }

  private func engineCancelNotificationHandler() {
    guard opaque != nil else { return }
    rimeApi.set_notification_handler(nil, nil)
    opaque = nil
  }
}
