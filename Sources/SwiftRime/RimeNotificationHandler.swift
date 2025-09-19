import CLibrime
import Foundation

public typealias RimeNotificationHandler = (RimeSessionId, RimeNotificationType, String) -> Void

final class Box {
	let body: RimeNotificationHandler
	init(_ body: @escaping RimeNotificationHandler) { self.body = body }
}

private func thunk(
    ctx: UnsafeMutableRawPointer?, session: CLibrime.RimeSessionId, type: UnsafePointer<CChar>?,
	value: UnsafePointer<CChar>?
) {
	guard let ctx, let type, let value else { return }
	let box = Unmanaged<Box>.fromOpaque(ctx).takeUnretainedValue()
    box.body(RimeSessionId(id:session), RimeNotificationType(from: String(cString: type)), String(cString: value))
}

public enum RimeNotificationType :Codable{
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

public extension RimeEngine {
    
    var notificationHandler: RimeNotificationHandler?
    {
        get {
            opaque?.body
        }
        set {
            if let newValue {
                setNotificationHandler(newValue)
            } else {
                cancel()
            }
        }
    }

    private func setNotificationHandler(
        _ closure:
            @escaping RimeNotificationHandler
    ) {
        let box = Box(closure)

        let ctx = Unmanaged.passUnretained(box).toOpaque()

        rimeApi.set_notification_handler(thunk, ctx)
        opaque = box
    }

    private func cancel() {
        guard opaque != nil else { return }
        rimeApi.set_notification_handler(nil, nil)
        opaque = nil
    }
    

}
