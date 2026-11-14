import Foundation

 
 
 
 
 
 
 
 
public enum ClashWidgetMailbox {
    public static let directory = "widgets"
     
    public static let requestFile = "widgets/request.json"
     
    public static let snapshotFile = "widgets/snapshot.json"
     
    public static let appFile = "widgets/app.json"
     
     
    public static let modeFile = "widgets/mode.json"
     
     
     
    public static let noticeFile = "widgets/notice.json"
    public static let requestNotification = "org.example.clash.widget.request"
     
    public static let updatedNotification = "org.example.clash.widget.updated"
     
     
    public static let waitForSnapshot: TimeInterval = 1.5
     
     
     
     
    public static let groupMemberLimit = 16

     
     
     
     
     
     
     
    public enum Kind {
        public static let main = "org.example.clash.widget.main"
        public static let all = [main]
    }
}

public struct ClashWidgetRequest: Codable, Equatable, Sendable {
    public enum Command: Codable, Equatable, Sendable {
        case refresh
        case setMode(ClashWidgetMode)
        case select(group: String, name: String)
    }

    public let id: String
    public let command: Command
     
     
    public let group: String?
    public let at: Date

    public init(command: Command, group: String?, at: Date = Date()) {
        id = UUID().uuidString
        self.command = command
        self.group = group
        self.at = at
    }
}

 
 
 
 
 
 
public struct ClashWidgetModeChoice: Codable, Equatable, Sendable {
    public let mode: ClashWidgetMode
    public let at: Date

    public init(mode: ClashWidgetMode, at: Date) {
        self.mode = mode
        self.at = at
    }
}

 
 
 
 
 
 
public struct ClashWidgetNotice: Codable, Equatable, Sendable {
     
     
    public let exit: String?
    public let at: Date

     
    public static let lifetime: TimeInterval = 60

    public init(exit: String?, at: Date) {
        self.exit = exit
        self.at = at
    }

     
    public var text: String {
        ClashTunnelOutboundMode.notTurnedOnKey(exit.map { ClashTunnelOutboundMode.GlobalExit(rawValue: $0) ?? .other })
    }

     
    public func text(at now: Date) -> String? {
        let age = now.timeIntervalSince(at)
        return age >= -5 && age <= Self.lifetime ? text : nil
    }
}

 
 
 
public struct ClashWidgetAppFacts: Codable, Equatable, Sendable {
    public let profile: String?
    public let firstGroup: String?
    public let groups: [String]
     
     
    public let members: [String: [String]]
     
    public let selections: [String: String]
     
     
     
     
     
    public let mode: ClashWidgetMode?
     
     
     
     
     
    public let countsWired: Bool?
     
     
     
     
    public let globalVerdict: ClashTunnelOutboundMode.StoredGlobalVerdict?
    public let writtenAt: Date

    public init(
        profile: String?, firstGroup: String?, groups: [String],
        members: [String: [String]] = [:], selections: [String: String] = [:],
        mode: ClashWidgetMode? = nil, countsWired: Bool? = nil,
        globalVerdict: ClashTunnelOutboundMode.StoredGlobalVerdict? = nil,
        writtenAt: Date
    ) {
        self.globalVerdict = globalVerdict
        self.profile = profile
        self.firstGroup = firstGroup
        self.groups = groups
        self.members = members
        self.selections = selections
        self.mode = mode
        self.countsWired = countsWired
        self.writtenAt = writtenAt
    }

     
     
     
     
     
     
    public func group(for pick: String?) -> String? {
        guard let pick else { return nil }
        return groups.contains(pick) ? pick : firstGroup
    }
}

 
 
 
 
 
 
public enum ClashWidgetStoredMode {
     
     
    public static let key = "config.runtime.flclash.v1"

    public static func read(from defaults: UserDefaults) -> ClashWidgetMode? {
        guard let data = defaults.data(forKey: key),
              let record = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let patchJSON = record["patchJSON"] as? String,
              let patch = (try? JSONSerialization.jsonObject(with: Data(patchJSON.utf8))) as? [String: Any],
              let mode = patch["mode"] as? String else { return nil }
        return ClashWidgetMode(rawValue: mode.lowercased())
    }
}

 
 
 
 
public struct ClashWidgetMailboxStore {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func readSnapshot() -> ClashWidgetSnapshot? {
        read(ClashWidgetMailbox.snapshotFile)
    }

    public func writeSnapshot(_ snapshot: ClashWidgetSnapshot) throws {
        try write(snapshot, to: ClashWidgetMailbox.snapshotFile)
    }

    public func readAppFacts() -> ClashWidgetAppFacts? {
        read(ClashWidgetMailbox.appFile)
    }

    public func writeAppFacts(_ facts: ClashWidgetAppFacts) throws {
        try write(facts, to: ClashWidgetMailbox.appFile)
    }

    public func readModeChoice() -> ClashWidgetModeChoice? {
        read(ClashWidgetMailbox.modeFile)
    }

    public func writeModeChoice(_ choice: ClashWidgetModeChoice) throws {
        try write(choice, to: ClashWidgetMailbox.modeFile)
    }

    public func clearModeChoice() {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(ClashWidgetMailbox.modeFile))
    }

    public func readNotice() -> ClashWidgetNotice? {
        read(ClashWidgetMailbox.noticeFile)
    }

    public func writeNotice(_ notice: ClashWidgetNotice) throws {
        try write(notice, to: ClashWidgetMailbox.noticeFile)
    }

    public func clearNotice() {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(ClashWidgetMailbox.noticeFile))
    }

     
     
    public func restingMode(stored: ClashWidgetMode?) -> ClashWidgetMode? {
        readModeChoice()?.mode ?? stored
    }

    public func writeRequest(_ request: ClashWidgetRequest) throws {
        try write(request, to: ClashWidgetMailbox.requestFile)
    }

     
    public func takeRequest() -> ClashWidgetRequest? {
        guard let request: ClashWidgetRequest = read(ClashWidgetMailbox.requestFile) else { return nil }
        try? FileManager.default.removeItem(at: root.appendingPathComponent(ClashWidgetMailbox.requestFile))
        return request
    }

    private func read<T: Decodable>(_ relative: String) -> T? {
        guard let data = try? Data(contentsOf: root.appendingPathComponent(relative)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(T.self, from: data)
    }

    private func write<T: Encodable>(_ value: T, to relative: String) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
