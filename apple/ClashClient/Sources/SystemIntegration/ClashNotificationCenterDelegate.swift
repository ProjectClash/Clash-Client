import Foundation
import UserNotifications

 
 
 
 
 
 
 
 
 
final class ClashNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = ClashNotificationCenterDelegate()

     
    static let kindKey = #"clash.notification.kind"#

     
     
     
     
    static let presentationOptions: UNNotificationPresentationOptions = [.banner, .list, .sound]

     
     
    static let heldTapsLimit = 8

     
    private var handlers: [String: @MainActor (ClashNotificationTap) -> Void] = [:]
    private var held: [ClashNotificationTap] = []

     
    static func install(on center: UNUserNotificationCenter = .current()) {
        center.delegate = shared
    }

     
    static func mark(_ content: UNMutableNotificationContent, kind: String) {
        content.userInfo[kindKey] = kind
    }

     
    @MainActor
    func register(kind: String, handler: @escaping @MainActor (ClashNotificationTap) -> Void) {
        handlers[kind] = handler
        let waiting = held.filter { $0.kind == kind }
        held.removeAll { $0.kind == kind }
        waiting.forEach(handler)
    }

    @MainActor
    func deliver(_ tap: ClashNotificationTap) {
        guard let kind = tap.kind else { return }
        if let handler = handlers[kind] { return handler(tap) }
        held.append(tap)
        if held.count > Self.heldTapsLimit { held.removeFirst(held.count - Self.heldTapsLimit) }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(Self.presentationOptions)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let content = response.notification.request.content
        let tap = ClashNotificationTap(
            identifier: response.notification.request.identifier,
            action: response.actionIdentifier,
            userInfo: content.userInfo,
            title: content.title, subtitle: content.subtitle, body: content.body
        )
        DispatchQueue.main.async {
             
             
             
             
            completionHandler()
            MainActor.assumeIsolated { self.deliver(tap) }
        }
    }
}

 
struct ClashNotificationTap: Equatable, Sendable {
     
    var kind: String?
    var identifier: String
     
    var action: String
     
    var info: [String: String]
     
     
     
    var title: String
    var subtitle: String
    var body: String

    init(kind: String?, identifier: String, action: String, info: [String: String],
         title: String = #""#, subtitle: String = #""#, body: String = #""#) {
        self.kind = kind
        self.identifier = identifier
        self.action = action
        self.info = info
        self.title = title
        self.subtitle = subtitle
        self.body = body
    }

    init(identifier: String, action: String, userInfo: [AnyHashable: Any],
         title: String = #""#, subtitle: String = #""#, body: String = #""#) {
        var info: [String: String] = [:]
        for case let (key as String, value as String) in userInfo where key != ClashNotificationCenterDelegate.kindKey {
            info[key] = value
        }
        self.init(
            kind: userInfo[ClashNotificationCenterDelegate.kindKey] as? String,
            identifier: identifier, action: action, info: info,
            title: title, subtitle: subtitle, body: body
        )
    }
}
