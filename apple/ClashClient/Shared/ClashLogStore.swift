import Foundation

 
 
 
 
 
 
 
 
public enum ClashLogStream: String, CaseIterable, Sendable {
     
    case core
     
    case app

     
     
     
     
    public var filePrefix: String { rawValue }

     
    public var bytesPerDay: Int {
        switch self {
        case .core: return 20 * 1024 * 1024
        case .app: return 1024 * 1024
        }
    }

     
     
     
     
    public var bytesPerFile: Int {
        switch self {
        case .core: return 20 * 1024 * 1024
        case .app: return 1024 * 1024
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
public enum ClashStartupSidecar: CaseIterable, Sendable {
    case breadcrumb
    case phases

     
    public var label: String {
        switch self {
        case .breadcrumb: return "startup-breadcrumb"
        case .phases: return "core-phases"
        }
    }

     
    public var relativePath: String {
        switch self {
        case .breadcrumb: return "working/startup-breadcrumb.json"
        case .phases: return "clash-core-phases.log"
        }
    }

     
     
     
    public var legacyRelativePath: String? {
        switch self {
        case .breadcrumb: return nil
        case .phases: return "clash-core-phases.log"
        }
    }
}

 
 
 
 
 
 
public enum ClashLogRetention: String, CaseIterable, Sendable {
    case oneDay
    case sevenDays
    case thirtyDays

    public var title: String {
        switch self {
        case .oneDay: return "1 day"
        case .sevenDays: return "7 days"
        case .thirtyDays: return "30 days"
        }
    }

    public var window: TimeInterval {
        switch self {
        case .oneDay: return 86_400
        case .sevenDays: return 7 * 86_400
        case .thirtyDays: return 30 * 86_400
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
public enum ClashLogSettings {
    public static let recordingKey = "logs.recording"

    #if os(tvOS)
    public static let defaultRecording = true
    #else
    public static let defaultRecording = false
    #endif

    public static func isRecording(from defaults: UserDefaults) -> Bool {
        defaults.object(forKey: recordingKey) as? Bool ?? defaultRecording
    }

    public static func setRecording(_ value: Bool, in defaults: UserDefaults) {
        let previous = isRecording(from: defaults)
        defaults.set(value, forKey: recordingKey)
         
         
         
        if previous != value {
            NotificationCenter.default.post(name: recordingDidChange, object: nil)
        }
    }

     
    public static let recordingDidChange = Notification.Name(
        "network.clash.logs.recordingDidChange"
    )

    public static let retentionKey = "logs.retention"

    public static func retention(from defaults: UserDefaults) -> ClashLogRetention {
        (defaults.string(forKey: retentionKey))
            .flatMap(ClashLogRetention.init(rawValue:)) ?? .sevenDays
    }

    public static func setRetention(
        _ value: ClashLogRetention,
        in defaults: UserDefaults
    ) {
        defaults.set(value.rawValue, forKey: retentionKey)
    }

     
     
     
    public static let severityFilterKey = "logs.levels"

     
     
     
     
     
    public static func severityFilter(from defaults: UserDefaults) -> [String] {
        (defaults.stringArray(forKey: severityFilterKey) ?? [])
            .filter { ClashLogLevel(rawValue: $0) != nil }
    }

    public static func setSeverityFilter(
        _ levels: [String],
        in defaults: UserDefaults
    ) {
        defaults.set(levels, forKey: severityFilterKey)
    }

     
     
     
    public static let levelDirectiveKey = "logs.levelDirective"

    public enum LevelDirective: Equatable, Sendable {
        case followProfile
        case forced(ClashLogLevel)

        public var rawValue: String? {
            switch self {
            case .followProfile: return nil
            case .forced(let level): return level.rawValue
            }
        }

        public init(rawValue: String?) {
            guard let rawValue, !rawValue.isEmpty, rawValue != "follow" else {
                self = .followProfile
                return
            }
            if let level = ClashLogLevel(rawValue: rawValue.lowercased()) {
                self = .forced(level)
            } else {
                self = .followProfile
            }
        }
    }

    public static func levelDirective(from defaults: UserDefaults) -> LevelDirective {
        LevelDirective(rawValue: defaults.string(forKey: levelDirectiveKey))
    }

    public static func setLevelDirective(
        _ directive: LevelDirective,
        in defaults: UserDefaults
    ) {
        let previous = defaults.string(forKey: levelDirectiveKey)
        if let raw = directive.rawValue {
            defaults.set(raw, forKey: levelDirectiveKey)
        } else {
            defaults.removeObject(forKey: levelDirectiveKey)
        }
         
         
         
         
         
         
        if previous != defaults.string(forKey: levelDirectiveKey) {
            NotificationCenter.default.post(name: levelDirectiveDidChange, object: nil)
        }
    }

     
    public static let levelDirectiveDidChange = Notification.Name(
        "network.clash.logs.levelDirectiveDidChange"
    )

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    public static func liveStreamLevel(
        directive: LevelDirective,
        profileLevel: String?
    ) -> String {
        switch directive {
        case .forced(let level):
            return level.rawValue
        case .followProfile:
            let declared = profileLevel?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return declared == ClashLogLevel.debug.rawValue ? "debug" : "info"
        }
    }

    public static func liveStreamLevel(from defaults: UserDefaults) -> String {
        liveStreamLevel(
            directive: levelDirective(from: defaults),
            profileLevel: activeProfileLogLevel(from: defaults)
        )
    }

     
    public static let activeProfileLogLevelKey = "logs.activeProfileLevel"

    public static func activeProfileLogLevel(from defaults: UserDefaults) -> String? {
        defaults.string(forKey: activeProfileLogLevelKey)
    }

    public static func setActiveProfileLogLevel(_ level: String?, in defaults: UserDefaults) {
        let previous = defaults.string(forKey: activeProfileLogLevelKey)
        if let level, !level.isEmpty {
            defaults.set(level, forKey: activeProfileLogLevelKey)
        } else {
            defaults.removeObject(forKey: activeProfileLogLevelKey)
        }
         
         
         
        if previous != defaults.string(forKey: activeProfileLogLevelKey) {
            NotificationCenter.default.post(name: activeProfileLogLevelDidChange, object: nil)
        }
    }

     
     
    public static let activeProfileLogLevelDidChange = Notification.Name(
        "network.clash.logs.activeProfileLevelDidChange"
    )
}

public enum ClashLogLevel: String, Sendable, CaseIterable {
    case silent
    case error
    case warning
    case info
    case debug
}

 
 
 
 
 
 
 
 
 
 
 
 
 
final class ClashLogBudget: @unchecked Sendable {
    private let lock = NSLock()
    let maximumBytes: Int
    let maximumCount: Int
    private var bytes = 0
    private var count = 0
    private var dropped = 0

    init(maximumBytes: Int, maximumCount: Int) {
        self.maximumBytes = maximumBytes
        self.maximumCount = maximumCount
    }

    func reserve(_ size: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard size >= 0, size <= maximumBytes - bytes, count < maximumCount else {
            dropped += 1
            return false
        }
        bytes += size; count += 1
        return true
    }

    @discardableResult func release(_ size: Int) -> Int {
        lock.lock(); defer { lock.unlock() }
        bytes -= size; count -= 1
        let lost = dropped
        dropped = 0
        return lost
    }

    var snapshot: (bytes: Int, count: Int, dropped: Int) {
        lock.lock(); defer { lock.unlock() }
        return (bytes, count, dropped)
    }
}

 
struct ClashLogBuffer {
    let maximumBytes: Int
    let maximumCount: Int
    private(set) var lines: [String] = []
    private(set) var bytes = 0
    private(set) var dropped = 0
    var isEmpty: Bool { lines.isEmpty }

    mutating func append(contentsOf incoming: [String]) {
        for line in incoming {
            let size = line.utf8.count
            guard size <= maximumBytes else { dropped += 1; continue }
            while !lines.isEmpty && (bytes + size > maximumBytes || lines.count >= maximumCount) {
                bytes -= lines.removeFirst().utf8.count
                dropped += 1
            }
            lines.append(line); bytes += size
        }
    }

    mutating func removeAll(keepingCapacity: Bool = false) {
        lines.removeAll(keepingCapacity: keepingCapacity)
        bytes = 0; dropped = 0
    }
}

public final class ClashLogStore: @unchecked Sendable {
    public static let shared = ClashLogStore()

    private let directory: URL?
    private let fileManager: FileManager
    private let queue: DispatchQueue
     
    private let coreBudget = ClashLogBudget(maximumBytes: 512 * 1024, maximumCount: 512)
    private let appBudget = ClashLogBudget(maximumBytes: 128 * 1024, maximumCount: 256)

    func pendingUsage(_ stream: ClashLogStream) -> (bytes: Int, count: Int, dropped: Int) {
        (stream == .core ? coreBudget : appBudget).snapshot
    }
    private let clock: () -> Date
    private let settings: UserDefaults?
     
     
     
     
    private var preparedDirectory = false
    private var lastPruneKey: [ClashLogStream: String] = [:]
#if os(macOS)
     
     
    private let queueKey = DispatchSpecificKey<Void>()
#endif

    public init(
        directory: URL? = ClashLogStore.defaultDirectory(),
        fileManager: FileManager = .default,
        clock: @escaping () -> Date = Date.init,
        settings: UserDefaults? = ClashLogStore.defaultSettings(),
        writeQueue: DispatchQueue? = nil
    ) {
        self.directory = directory
        self.fileManager = fileManager
        self.clock = clock
        self.settings = settings
        self.queue = writeQueue ?? DispatchQueue(label: "network.clash.logstore")
#if os(macOS)
        queue.setSpecific(key: queueKey, value: ())
#endif
    }

     
     
    private static func coreLogLevel(_ message: String) -> ClashLogLevel? {
        guard message.hasPrefix("time="), let range = message.range(of: " level=") else { return nil }
        let value = message[range.upperBound...].prefix { !$0.isWhitespace }
        switch value {
        case "fatal", "panic": return .error
        default: return ClashLogLevel(rawValue: String(value))
        }
    }

    public static func defaultSettings() -> UserDefaults? {
        UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite)
    }

    public static func defaultDirectory() -> URL? {
        ClashAppIdentifiers.appGroupContainer?.appendingPathComponent("logs", isDirectory: true)
    }

     
     
    public func append(
        _ message: String,
        stream: ClashLogStream = .app,
        level: ClashLogLevel = .info
    ) {
         
         
        if let settings, !ClashLogSettings.isRecording(from: settings) { return }
        appendLine(message, stream: stream, level: level)
    }

#if os(macOS)
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    public func appendDiagnostic(
        _ message: String,
        stream: ClashLogStream = .app,
        level: ClashLogLevel = .error
    ) {
        appendLine(message, stream: stream, level: level, budgeted: false, waitable: false)
        guard DispatchQueue.getSpecific(key: queueKey) == nil else { return }
        let written = DispatchSemaphore(value: 0)
        queue.async { written.signal() }
        _ = written.wait(timeout: .now() + .seconds(1))
    }
#endif

    private func appendLine(
        _ message: String,
        stream: ClashLogStream,
        level: ClashLogLevel,
        budgeted: Bool = true,
        waitable: Bool = true
    ) {
         
         
         
         
        guard !message.isEmpty else { return }
        let now = clock()
        let recordedLevel = stream == .core ? Self.coreLogLevel(message) ?? level : level
        let stamped = "\(Self.timestamp(now))  \(recordedLevel.rawValue.uppercased())  \(message)\n"
        let day = Self.day(now)
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        let budget = stream == .core ? coreBudget : appBudget
        let size = stamped.utf8.count
        if budgeted { guard budget.reserve(size) else { return } }
        let operation: @Sendable () -> Void = { [weak self] in
            self?.write(stamped, stream: stream, on: day)
            self?.pruneExpired(stream, now: now)
            guard budgeted else { return }
            let lost = budget.release(size)
            if lost > 0 {
                self?.write("\(Self.timestamp(now))  WARNING  Log queue full; dropped \(lost) lines.\n",
                            stream: stream, on: day)
            }
        }
        if waitable, isStartingUp() { queue.sync(execute: operation) }
        else { queue.async(execute: operation) }
    }

     
     
     
    private let startupLock = NSLock()
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private var startingUp = Bundle.main.bundlePath.hasSuffix(".appex")

    private func isStartingUp() -> Bool {
        startupLock.lock()
        defer { startupLock.unlock() }
        return startingUp
    }

    public func markTunnelEstablished() {
        startupLock.lock()
        startingUp = false
        startupLock.unlock()
    }

    public func markStartingUp() {
        startupLock.lock()
        startingUp = true
        startupLock.unlock()
    }

     
     
     
     
     
    public func flush() {
        queue.sync {}
    }

     
     
     
     
     
     
     
     
     
     
     
    public func clear() {
        guard let directory else { return }
        queue.sync {
            for stream in ClashLogStream.allCases {
                for url in files(for: stream) {
                    try? fileManager.removeItem(at: url)
                }
            }
            try? fileManager.removeItem(at: directory)
            preparedDirectory = false
            lastPruneKey.removeAll()
        }
    }

     
     
     
     
     
     
    public static let readBudgetPerStream = 8 * 1024 * 1024

     
     
     
    public func read(_ stream: ClashLogStream) -> String {
        queue.sync {
            var pieces: [String] = []
            var budget = Self.readBudgetPerStream
            var omitted = 0
             
             
            for url in files(for: stream).reversed() {
                if budget <= 0 {
                    omitted += ((try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? Int) ?? 0
                    continue
                }
                autoreleasepool {
                    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
                     
                    let cost = text.utf8.count
                    if cost <= budget {
                        budget -= cost
                        pieces.append(text)
                    } else {
                         
                         
                         
                         
                         
                         
                         
                        let bytes = Array(text.utf8.suffix(budget))
                        if let newline = bytes.firstIndex(of: 0x0A), newline + 1 < bytes.count {
                            let kept = String(decoding: bytes[(newline + 1)...], as: UTF8.self)
                            omitted += cost - kept.utf8.count
                            pieces.append(kept)
                        } else {
                            omitted += cost
                        }
                        budget = 0
                    }
                }
            }
            var body = pieces.reversed().joined()
            if omitted > 0 {
                body = "===== \(omitted / 1024) KiB of older lines omitted (read is bounded at \(Self.readBudgetPerStream / 1024 / 1024) MiB per stream) =====\n" + body
            }
            return body
        }
    }





     
     
     
     
     
     
     
     
    public static func isDayFileName(_ name: String) -> Bool {
        ClashLogStream.allCases.contains { stream in
            let prefix = stream.filePrefix + "-"
            guard name.hasPrefix(prefix), name.hasSuffix(".log") else { return false }
            let day = String(name.dropFirst(prefix.count).dropLast(".log".count))
            guard let parsed = dayFormatter.date(from: day) else { return false }
            return dayFormatter.string(from: parsed) == day
        }
    }



     
     
     
     
     
     
    private static let generationLock = NSLock()
    private static var mirrorGeneration = 0
    static var currentGeneration: Int {
        generationLock.lock(); defer { generationLock.unlock() }
        return mirrorGeneration
    }


     
     
     
     
     
     
     
     
     
     
    static func isOurMirrorCopy(at url: URL) -> Bool {
        guard isDayFileName(url.lastPathComponent),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
              values.isRegularFile == true,
              let handle = try? FileHandle(forReadingFrom: url) else { return false }
        let head = try? handle.read(upToCount: 512)
        try? handle.close()
        guard let data = head else { return false }

         
         
         
         
         
         
         
        let line = Array(data.prefix(while: { $0 != 0x0A }))
        let stampEnd = timestampWidth
        guard line.count > stampEnd + 2, line[0..<stampEnd].allSatisfy({ $0 < 0x80 }),
              line[stampEnd] == 0x20, line[stampEnd + 1] == 0x20 else { return false }
        let stamp = String(decoding: line[0..<stampEnd], as: UTF8.self)
        guard let parsed = formatter.date(from: stamp), formatter.string(from: parsed) == stamp else { return false }

        let levelStart = stampEnd + 2
        let levelBytes = Array(line[levelStart...].prefix(while: { $0 != 0x20 }))
        guard !levelBytes.isEmpty, levelBytes.allSatisfy({ $0 < 0x80 }),
              ClashLogLevel(rawValue: String(decoding: levelBytes, as: UTF8.self).lowercased()) != nil else { return false }
         
        let afterLevel = levelStart + levelBytes.count
        guard line.count > afterLevel + 1, line[afterLevel] == 0x20, line[afterLevel + 1] == 0x20 else { return false }
        return true
    }

     
     
    static let stagingPrefix = ".clash-mirror-"

     
     
     
     
     
     
     
     
    private static func removeStagingOrphans(in directory: URL) {


    }

     
     
     
     
     
     
     
     
     
    public static let mirrorDirectoryName = "ClashLogs"





     
     
     
     
     
     
     
     
     
    public func tail(_ stream: ClashLogStream, limit: Int = 400) -> [String] {
        queue.sync {
            var collected: [String] = []
            for url in files(for: stream).reversed() where collected.count < limit {
                collected = Self.lastLines(limit - collected.count, of: url)
                    + collected
            }
            return Array(collected.suffix(limit))
        }
    }

     
     
     
     
     
     
     
     
     
     
    private static func lastLines(_ count: Int, of url: URL) -> [String] {
        guard count > 0,
              let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd(), end > 0 else { return [] }

        let chunkSize: UInt64 = 128 * 1024
        var offset = end
        var buffer = Data()
        var newlines = 0
         
         
        while offset > 0, newlines <= count {
            let readSize = min(chunkSize, offset)
            offset -= readSize
             
            let joined: Bool = autoreleasepool {
                guard (try? handle.seek(toOffset: offset)) != nil,
                      let chunk = try? handle.read(upToCount: Int(readSize)),
                      !chunk.isEmpty else { return false }
                newlines += chunk.reduce(into: 0) { if $1 == 0x0A { $0 += 1 } }
                buffer = chunk + buffer
                return true
            }
            guard joined else { break }
        }
        if offset > 0 {
            guard let cut = buffer.firstIndex(of: 0x0A) else { return [] }
            buffer = buffer[buffer.index(after: cut)...]
        }
        guard let text = String(data: buffer, encoding: .utf8) else { return [] }
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .suffix(count)
            .map(String.init)
    }

     
     
     
     
     
     
    public func mergedTail(limit: Int = 400) -> [String] {
        let merged = ClashLogStream.allCases
            .flatMap { tail($0, limit: limit) }
            .sorted { lhs, rhs in
                 
                 
                lhs.prefix(Self.timestampWidth) < rhs.prefix(Self.timestampWidth)
            }
        return Array(merged.suffix(limit))
    }

    private static let timestampWidth = 24

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    @discardableResult
    public func writeExport(to destination: URL, device: String = "") -> Bool {
        let fileManager = self.fileManager
        guard fileManager.createFile(atPath: destination.path, contents: nil) else {
            return false
        }
        guard let handle = try? FileHandle(forWritingTo: destination) else { return false }
        defer { try? handle.close() }
        if !device.isEmpty {
            let body = device.hasSuffix("\n") ? device : "\(device)\n"
            try? handle.write(contentsOf: Data("===== device =====\n\(body)".utf8))
        }
        let urls = queue.sync { ClashLogStream.allCases.map { ($0, files(for: $0)) } }
        var sections: [(label: String, urls: [URL])] = urls.map { ($0.0.rawValue, $0.1) }
        if let container = directory?.deletingLastPathComponent() {
            for sidecar in ClashStartupSidecar.allCases {
                let candidates = [sidecar.relativePath] + (sidecar.legacyRelativePath.map { [$0] } ?? [])
                guard let url = candidates
                    .map({ container.appendingPathComponent($0) })
                    .first(where: { fileManager.fileExists(atPath: $0.path) }) else { continue }
                sections.append((sidecar.label, [url]))
            }
        }
        for (index, section) in sections.enumerated() {
            let gap = index == 0 && device.isEmpty ? "" : "\n"
            let header = "\(gap)===== \(section.label) =====\n"
            try? handle.write(contentsOf: Data(header.utf8))
            for url in section.urls {
                guard let reader = try? FileHandle(forReadingFrom: url) else { continue }
                defer { try? reader.close() }
                 
                 
                while autoreleasepool(invoking: { () -> Bool in
                    guard let chunk = try? reader.read(upToCount: 256 * 1024), !chunk.isEmpty else { return false }
                    try? handle.write(contentsOf: chunk)
                    return true
                }) {}
            }
        }
        return true
    }

    public func removeAll() {
        queue.sync {
            guard let directory else { return }
            try? fileManager.removeItem(at: directory)
             
            preparedDirectory = false
            lastPruneKey = [:]
        }
    }

     

    private func write(_ line: String, stream: ClashLogStream, on day: String) {
        guard let directory else { return }
        prepareDirectoryIfNeeded(at: directory)
        let url = url(for: stream, day: day)
        let data = Data(line.utf8)
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let existing = (attributes?[.size] as? Int) ?? 0
         
         
         
         
         
        if existing + data.count > stream.bytesPerDay {
            dropOldestHalf(of: url)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else {
            if !createFile(at: url, contents: data) {
                 
                 
                 
                 
                preparedDirectory = false
                prepareDirectoryIfNeeded(at: directory)
                _ = createFile(at: url, contents: data)
            }
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    private func prepareDirectoryIfNeeded(at directory: URL) {
        guard !preparedDirectory else { return }
        try? fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [
                 
                 
                 
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
            ]
        )
        excludeFromBackup(directory)
        preparedDirectory = true
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private func excludeFromBackup(_ directory: URL) {
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    @discardableResult
    private func createFile(at url: URL, contents data: Data) -> Bool {
        fileManager.createFile(
            atPath: url.path,
            contents: data,
            attributes: [
                .protectionKey:
                    FileProtectionType.completeUntilFirstUserAuthentication,
            ]
        )
    }

     
     
    private func dropOldestHalf(of url: URL) {
         
         
         
         
         
         
         
         
         
         
        let temporary = url.appendingPathExtension("rotating")
        guard let source = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? source.close() }
        guard let size = try? source.seekToEnd(), size > 0 else { return }

        try? fileManager.removeItem(at: temporary)
        guard fileManager.createFile(atPath: temporary.path, contents: nil),
              let sink = try? FileHandle(forWritingTo: temporary) else {
            try? fileManager.removeItem(at: temporary)
            return
        }
        defer { try? sink.close() }

         
         
        try? source.seek(toOffset: size / 2)
        var alignedToLine = false
         
         
        while autoreleasepool(invoking: { () -> Bool in
            guard let chunk = try? source.read(upToCount: Self.rotationChunkBytes),
                  !chunk.isEmpty else { return false }
            var payload = chunk
            if !alignedToLine {
                guard let newline = payload.firstIndex(of: 0x0A) else { return true }
                payload = payload[payload.index(after: newline)...]
                alignedToLine = true
            }
            try? sink.write(contentsOf: payload)
            return true
        }) {}
        try? sink.close()
        try? source.close()
        _ = try? fileManager.replaceItemAt(url, withItemAt: temporary)
        try? fileManager.removeItem(at: temporary)
    }

     
    private static let rotationChunkBytes = 256 * 1024

     
     
     
     
     
     
     
     
     
     
     
    public func composition(of stream: ClashLogStream = .core) -> String {
        queue.sync {
            let url = url(for: stream, day: Self.day(clock()))
            let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            guard let handle = try? FileHandle(forReadingFrom: url) else {
                return "core-log bytes=\(size) (unreadable)"
            }
            defer { try? handle.close() }
            var shapes = ShapeTally()
            var lines = 0
            var buffer = [UInt8](repeating: 0, count: Self.rotationChunkBytes)
            buffer.withUnsafeMutableBytes { raw in
                guard let base = raw.baseAddress else { return }
                 
                var kept = 0
                 
                var overlong = false
                while true {
                    let read = Darwin.read(handle.fileDescriptor, base + kept, raw.count - kept)
                    if read < 0, errno == EINTR { continue }
                    if read <= 0 { break }
                    let filled = kept + read
                    var start = 0
                    while start < filled, let newline = memchr(base + start, 0x0A, filled - start) {
                        let end = newline - UnsafeMutableRawPointer(base)
                        if !overlong {
                            shapes.add(UnsafeRawBufferPointer(start: base + start, count: end - start))
                        }
                        overlong = false
                        lines += 1
                        start = end + 1
                    }
                    if start == 0, filled == raw.count {
                         
                        if !overlong { shapes.add(UnsafeRawBufferPointer(start: base, count: filled)) }
                        overlong = true
                        kept = 0
                        continue
                    }
                    kept = filled - start
                    if kept > 0, start > 0 { memmove(base, base + start, kept) }
                }
            }
            return "core-log bytes=\(size) lines=\(lines) top=[\(shapes.top(3))]"
        }
    }

     
     
     
     
     
     
     
     
     
    private struct ShapeTally {
        private static let slots = 64
        private static let shapeBytes = 60
        private var hashes = [UInt64](repeating: 0, count: slots)
        private var counts = [Int](repeating: 0, count: slots)
        private var errors = [Int](repeating: 0, count: slots)
        private var lengths = [Int](repeating: 0, count: slots)
        private var names = [UInt8](repeating: 0, count: slots * shapeBytes)
        private var used = 0
        private var shape = [UInt8](repeating: 0, count: shapeBytes)

        mutating func add(_ line: UnsafeRawBufferPointer) {
            var length = 0
            var words = 0
            var inWord = false
            for byte in line {
                if byte == 0x20 {
                    inWord = false
                    continue
                }
                if !inWord {
                    inWord = true
                    words += 1
                    if words > 7 { break }
                    if words > 4, length < Self.shapeBytes {
                        shape[length] = 0x20
                        length += 1
                    }
                }
                if words > 3 {
                    if length == Self.shapeBytes { break }
                    shape[length] = byte
                    length += 1
                }
            }
            length = Self.characterBoundary(shape, length)
            var hash: UInt64 = 0xcbf2_9ce4_8422_2325
            for index in 0..<length {
                hash = (hash ^ UInt64(shape[index])) &* 0x0000_0100_0000_01b3
            }
            for slot in 0..<used where hashes[slot] == hash && lengths[slot] == length {
                counts[slot] += 1
                return
            }
            let slot: Int
            if used < Self.slots {
                slot = used
                used += 1
                counts[slot] = 1
                errors[slot] = 0
            } else {
                var least = 0
                for index in 1..<Self.slots where counts[index] < counts[least] { least = index }
                slot = least
                errors[slot] = counts[slot]
                counts[slot] += 1
            }
            hashes[slot] = hash
            lengths[slot] = length
            for index in 0..<length { names[slot * Self.shapeBytes + index] = shape[index] }
        }

         
         
        private static func characterBoundary(_ bytes: [UInt8], _ length: Int) -> Int {
            var lead = length
            while lead > 0, bytes[lead - 1] & 0xC0 == 0x80 { lead -= 1 }
            guard lead > 0, bytes[lead - 1] >= 0xC0 else { return length }
            let first = bytes[lead - 1]
            let needs = first >= 0xF0 ? 4 : first >= 0xE0 ? 3 : 2
            return length - (lead - 1) < needs ? lead - 1 : length
        }

        func top(_ count: Int) -> String {
            (0..<used).sorted { counts[$0] - errors[$0] > counts[$1] - errors[$1] }.prefix(count)
                .map { slot in
                    let start = slot * Self.shapeBytes
                    let name = String(decoding: names[start..<start + lengths[slot]], as: UTF8.self)
                    return "\(counts[slot] - errors[slot])× \(name)"
                }
                .joined(separator: " | ")
        }
    }

     
     
     
     
     
    private func pruneExpired(_ stream: ClashLogStream, now: Date) {
        guard let settings, directory != nil else { return }
        let window = ClashLogSettings.retention(from: settings).window
        let key = "\(Self.day(now))|\(window)"
        guard lastPruneKey[stream] != key else { return }
        lastPruneKey[stream] = key
        let cutoff = Self.day(now.addingTimeInterval(-window))
        for url in files(for: stream) {
            let name = url.deletingPathExtension().lastPathComponent
            let day = String(name.dropFirst(stream.filePrefix.count + 1))
            guard day < cutoff else { continue }
            try? fileManager.removeItem(at: url)
        }
    }

     
    private func files(for stream: ClashLogStream) -> [URL] {
        guard let directory else { return [] }
        let all = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return all
            .filter {
                $0.lastPathComponent.hasPrefix("\(stream.filePrefix)-")
                    && $0.pathExtension == "log"
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

     
     
     
     
     
    public static func mirrorableFileNames(
        now: Date = Date()
    ) -> [String] {
        [now, now.addingTimeInterval(-86_400)].flatMap { date in
            ClashLogStream.allCases.map {
                "\($0.filePrefix)-\(day(date)).log"
            }
        }
    }

    private func url(for stream: ClashLogStream, day: String) -> URL {
        (directory ?? URL(fileURLWithPath: "/dev/null"))
            .appendingPathComponent("\(stream.filePrefix)-\(day).log")
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func day(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return formatter
    }()

    private static func timestamp(_ date: Date) -> String {
        formatter.string(from: date)
    }
}
