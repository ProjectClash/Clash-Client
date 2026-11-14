#if os(iOS) || os(macOS)
import Foundation
import UserNotifications

 
 
 
enum ModuleScriptNotificationPoster {
     
     
     
     
    static let kind = "module.script"
     
     
     
    static let kindKey = #"clash.notification.kind"#

     
     
     
    static func request(for record: ModuleScriptNotificationRecord, now: Date = Date()) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = record.title
        content.subtitle = record.subtitle
        content.body = record.body
        content.threadIdentifier = kind
        if record.sound { content.sound = .default }
        var info: [String: String] = [kindKey: kind, "scriptName": record.scriptName, "id": record.id]
        if let url = record.openURL { info["openURL"] = url }
        if let text = record.clipboardText { info["clipboardText"] = text }
        if let media = record.mediaURL { info["mediaURL"] = media }
        content.userInfo = info
        let left = record.delaySeconds.map { $0 - now.timeIntervalSince(record.at) }
        let trigger = left.flatMap { $0 > 0 ? UNTimeIntervalNotificationTrigger(timeInterval: $0, repeats: false) : nil }
        return UNNotificationRequest(identifier: kind + "." + record.id, content: content, trigger: trigger)
    }

     
     
     
     
    nonisolated(unsafe) static var askFirst: (@Sendable (@escaping @Sendable (Bool) -> Void) -> Void)?

     
     
     
     
    static func post(_ record: ModuleScriptNotificationRecord,
                     words: ModuleScriptNotificationWordsStore? = ModuleScriptNotificationWordsStore.production,
                     log: @escaping @Sendable (String) -> Void) {
        let center = UNUserNotificationCenter.current()
        @Sendable func notShown(_ status: UNAuthorizationStatus) {
            log(#"module script notification \#(record.id) from \#(record.scriptName) not shown: "#
                + #"notifications are off for Clash (status \#(status.rawValue))"#)
        }
        @Sendable func show() {
            if words?.keep(record) == false {
                log(#"module script notification \#(record.id): its words were not kept whole; a tap shows what the system keeps"#)
            }
            let request = Self.request(for: record)
             
            DispatchQueue.main.async {
                center.add(request) { error in
                    guard let error else { return }
                    log(#"module script notification \#(record.id) not shown: \#(error.localizedDescription)"#)
                }
            }
        }
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .denied:
                notShown(.denied)
            case .notDetermined:
                guard let ask = askFirst else { return notShown(.notDetermined) }
                ask { mayShow in mayShow ? show() : notShown(.notDetermined) }
            default:
                show()
            }
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ModuleScriptTunnelNotifier: Sendable {
    typealias Add = @Sendable (UNNotificationRequest, @escaping @Sendable (Error?) -> Void) -> Void

     
    static let systemAdd: Add = { request, completion in
        UNUserNotificationCenter.current().add(request) { completion($0) }
    }

    let mailbox: ModuleScriptNotificationMailbox
    let postsItself: Bool
    let queue: DispatchQueue
    let add: Add
    let log: @Sendable (String) -> Void
     
    var words: ModuleScriptNotificationWordsStore { ModuleScriptNotificationWordsStore(container: mailbox.container) }

    init(mailbox: ModuleScriptNotificationMailbox, postsItself: Bool = true,
         queue: DispatchQueue = DispatchQueue(label: "modules.scripts.notifications", qos: .utility),
         add: @escaping Add = ModuleScriptTunnelNotifier.systemAdd, log: @escaping @Sendable (String) -> Void) {
        self.mailbox = mailbox
        self.postsItself = postsItself
        self.queue = queue
        self.add = add
        self.log = log
    }

    func post(_ record: ModuleScriptNotificationRecord) {
        let mailbox = self.mailbox
        let log = self.log
        let add = self.add
        let postsItself = self.postsItself
        let words = self.words
        queue.async {
             
            guard postsItself else { return Self.leave(record, in: mailbox, log: log) }
            if !words.keep(record) {
                log(#"[script] the words of a notification from \#(record.scriptName) were not kept whole; a tap shows what the system keeps"#)
            }
            add(ModuleScriptNotificationPoster.request(for: record)) { error in
                guard let error else { return }
                let refusal = error as NSError
                log(#"[script] the tunnel could not show a notification from \#(record.scriptName) "#
                    + #"(\#(refusal.domain) \#(refusal.code): \#(refusal.localizedDescription)); it waits for the App"#)
                Self.leave(record, in: mailbox, log: log)
            }
        }
    }

     
    private static func leave(_ record: ModuleScriptNotificationRecord, in mailbox: ModuleScriptNotificationMailbox,
                              log: @Sendable (String) -> Void) {
        do {
            let dropped = try mailbox.post(record)
            if dropped > 0 {
                log(#"[script] the App had not taken \#(dropped) older notifications; they were dropped"#)
            }
        } catch {
            log(#"[script] a notification from \#(record.scriptName) did not reach the App: \#(error.localizedDescription)"#)
        }
    }
}
#endif
