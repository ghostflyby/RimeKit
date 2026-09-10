import Foundation
import RimeDynamic

public typealias RimeNotificationHandler =
  @Sendable (RimeSessionID, RimeNotificationType, String) -> Void

final class Box {
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

public enum RimeNotificationType: Codable, Sendable {
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

extension RimeServiceRoot {
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
