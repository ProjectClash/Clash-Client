#if os(iOS) || os(macOS)
import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
struct ModuleScriptNotificationRecord: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var id: String
    var at: Date
    var scriptName: String
    var title: String
    var subtitle: String
    var body: String
     
    var openURL: String?
     
     
    var clipboardText: String?
    var sound: Bool
     
     
    var mediaURL: String?
     
    var delaySeconds: Double?

    init(
        scriptName: String, title: String, subtitle: String, body: String,
        openURL: String? = nil, clipboardText: String? = nil, sound: Bool = false,
        mediaURL: String? = nil, delaySeconds: Double? = nil,
        id: String = UUID().uuidString, at: Date = Date()
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.at = at
        self.scriptName = scriptName
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.openURL = openURL
        self.clipboardText = clipboardText
        self.sound = sound
        self.mediaURL = mediaURL
        self.delaySeconds = delaySeconds
    }
}

struct ModuleScriptNotificationMailbox: Sendable {
     
     
    static let directoryName = "module-scripts/notifications"
     
     
    static let darwinNotification = "clash.module.notification"
     
    static let pendingLimit = 32

    let container: URL
    let directory: URL
    let notificationName: String

    init(container: URL, notificationName: String = ModuleScriptNotificationMailbox.darwinNotification) {
        self.container = container
        directory = container.appendingPathComponent(Self.directoryName, isDirectory: true)
        self.notificationName = notificationName
    }

     
    static var production: ModuleScriptNotificationMailbox? {
        ClashAppIdentifiers.appGroupContainer.map { ModuleScriptNotificationMailbox(container: $0) }
    }

     
     
    @discardableResult
    func post(_ record: ModuleScriptNotificationRecord) throws -> Int {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let pending = pendingFiles()
        var dropped = 0
        if pending.count >= Self.pendingLimit {
            for stale in pending.prefix(pending.count - Self.pendingLimit + 1) {
                try? manager.removeItem(at: stale)
                dropped += 1
            }
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(record).write(
            to: directory.appendingPathComponent(Self.fileName(for: record)),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(notificationName as CFString), nil, nil, true)
        return dropped
    }

     
     
    func takeAll() -> (records: [ModuleScriptNotificationRecord], unreadable: Int) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        var records: [ModuleScriptNotificationRecord] = []
        var unreadable = 0
        for url in pendingFiles() {
            defer { try? FileManager.default.removeItem(at: url) }
            guard let data = try? Data(contentsOf: url),
                  let record = try? decoder.decode(ModuleScriptNotificationRecord.self, from: data) else {
                unreadable += 1
                continue
            }
            records.append(record)
        }
        return (records, unreadable)
    }

     
    static func fileName(for record: ModuleScriptNotificationRecord) -> String {
        String(format: "%015lld", Int64(record.at.timeIntervalSince1970 * 1000)) + "-" + record.id + ".json"
    }

    private func pendingFiles() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }.sorted().map { directory.appendingPathComponent($0) }
    }
}

 
struct ModuleScriptNotificationWords: Codable, Equatable, Sendable {
    var title: String
    var subtitle: String
    var body: String
    var clipboardText: String?
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ModuleScriptNotificationWordsStore: Sendable {
     
    static let directoryName = "module-scripts/notification-words"
     
    static let keptLimit = 32
     
     
     
    static let keptFor: TimeInterval = 7 * 24 * 60 * 60
     
     
    static let textLimitBytes = 64 * 1024

    let directory: URL

    init(container: URL) {
        directory = container.appendingPathComponent(Self.directoryName, isDirectory: true)
    }

     
    static var production: ModuleScriptNotificationWordsStore? {
        ClashAppIdentifiers.appGroupContainer.map { ModuleScriptNotificationWordsStore(container: $0) }
    }

     
     
     
    @discardableResult
    func keep(_ record: ModuleScriptNotificationRecord, now: Date = Date()) -> Bool {
        guard Self.isFileSafe(record.id) else { return false }
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            var kept = sweep(now: now).filter { Self.id(ofFile: $0.lastPathComponent) != record.id }
            while kept.count >= Self.keptLimit {
                try? manager.removeItem(at: kept.removeFirst())
            }
            let words = ModuleScriptNotificationWords(
                title: Self.bounded(record.title), subtitle: Self.bounded(record.subtitle), body: Self.bounded(record.body),
                clipboardText: record.clipboardText.map(Self.bounded))
            let name = String(format: "%015lld", Int64(now.timeIntervalSince1970 * 1000)) + "-" + record.id + ".json"
            try JSONEncoder().encode(words).write(to: directory.appendingPathComponent(name),
                                                  options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            return false
        }
    }

     
     
    func take(id: String, now: Date = Date()) -> ModuleScriptNotificationWords? {
        guard Self.isFileSafe(id) else { return nil }
        guard let url = sweep(now: now).first(where: { Self.id(ofFile: $0.lastPathComponent) == id }) else { return nil }
        defer { try? FileManager.default.removeItem(at: url) }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ModuleScriptNotificationWords.self, from: data)
    }

     
    private func sweep(now: Date) -> [URL] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasSuffix(".json") }.sorted()
        let oldest = Int64((now.timeIntervalSince1970 - Self.keptFor) * 1000)
        var kept: [URL] = []
        for name in names {
            let url = directory.appendingPathComponent(name)
            if let at = Int64(name.prefix(15)), at >= oldest {
                kept.append(url)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }
        return kept
    }

     
    private static func id(ofFile name: String) -> String? {
        guard name.hasSuffix(".json"), name.count > 21, name.prefix(15).allSatisfy({ $0.isASCII && $0.isNumber }),
              name.dropFirst(15).first == "-" else { return nil }
        return String(name.dropFirst(16).dropLast(5))
    }

     
    private static func isFileSafe(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 128
            && id.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_") }
    }

     
    static func bounded(_ text: String) -> String {
        guard text.utf8.count > textLimitBytes else { return text }
        var bytes = 0
        var end = text.startIndex
        for index in text.indices {
            let next = text.index(after: index)
            let size = text.utf8.distance(from: index, to: next)
            guard bytes + size <= textLimitBytes else { break }
            bytes += size
            end = next
        }
        return String(text[..<end])
    }
}
#endif
