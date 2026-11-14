import Foundation

 
 
 
 
enum ClashWidgetMailboxClient {
    static var store: ClashWidgetMailboxStore {
        ClashWidgetMailboxStore(
            root: ClashAppIdentifiers.appGroupContainer ?? FileManager.default.temporaryDirectory
        )
    }

     
     
    static func requestAndWait(_ command: ClashWidgetRequest.Command, group: String?, kind: String = "") async -> ClashWidgetSnapshot? {
        let store = store
        let request = ClashWidgetRequest(command: command, group: group)
        let began = Date()
        do {
            try store.writeRequest(request)
        } catch {
            ClashLogStore.shared.append(
                "widget client: request not written  \(error.localizedDescription)",
                stream: .app, level: .warning
            )
            return store.readSnapshot()
        }
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(ClashWidgetMailbox.requestNotification as CFString),
            nil, nil, true
        )
        let deadline = began.addingTimeInterval(ClashWidgetMailbox.waitForSnapshot)
        var latest = store.readSnapshot()
        var answered = latest.map { $0.at.timeIntervalSince(request.at) >= 0 } ?? false
        while !answered, Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if let snapshot = store.readSnapshot() {
                latest = snapshot
                answered = snapshot.at.timeIntervalSince(request.at) >= 0
            }
        }
        let milliseconds = Int(Date().timeIntervalSince(began) * 1_000)
        let phase = latest.map { $0.phase.rawValue } ?? "none"
        ClashLogStore.shared.append(
            "widget client: \(kind) \(word(command)) answered=\(answered) in \(milliseconds) ms phase=\(phase) proxy=\(latest?.proxy != nil) conns=\(latest?.connections != nil)",
            stream: .app, level: .info
        )
        return latest
    }

     
     
     
    static func markDisconnected() {
        let store = store
        if let file = store.readSnapshot(), file.phase == .connected {
            try? store.writeSnapshot(file.asDisconnected())
        }
    }

    private static func word(_ command: ClashWidgetRequest.Command) -> String {
        switch command {
        case .refresh: return "refresh"
        case .setMode(let mode): return "setMode \(mode.rawValue)"
        case .select: return "select"
        }
    }
}
