import Foundation

 
final class ProfileStore {
    private static let writeOptions: Data.WritingOptions =
        [.atomic, .completeFileProtectionUntilFirstUserAuthentication]

    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

     
     
     
     
     
     
    enum State: Equatable {
        case missing
        case unreadable
        case readable([Profile])
    }

    enum StoreError: LocalizedError, Equatable {
        case unreadableStore

        var errorDescription: String? {
            switch self {
            case .unreadableStore:
                return "The profile list could not be read, so it was left untouched. Restore from a backup, or remove the app's data to start over."
            }
        }
    }

    func state() -> State {
        guard fileManager.fileExists(atPath: fileURL.path) else { return .missing }
        guard let data = try? Data(contentsOf: fileURL) else { return .unreadable }
         
         
        guard !data.isEmpty,
              let profiles = try? JSONDecoder().decode([Profile].self, from: data)
        else { return .unreadable }
        return .readable(profiles)
    }

    func load() -> [Profile] {
        if case .readable(let profiles) = state() { return profiles }
        return []
    }

    func save(_ profiles: [Profile]) throws {
        try withWriteLock { try write(profiles) }
    }

    // Every write takes the in-process lock, then the cross-process lock file
    // the kernel and the tunnel extension use, so a concurrent CLI write cannot
    // land between our read and our save.
    func withWriteLock<T>(_ body: () throws -> T) throws -> T {
        try Self.withWriteLock {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            let lock = crossProcessLock()
            try lock.lock()
            defer { lock.unlock() }
            return try body()
        }
    }

    // Guarded by `writeLock`; one lock object per store directory so a nested
    // hold on the same thread re-enters instead of deadlocking on flock.
    nonisolated(unsafe) private static var crossProcessLocks: [String: ProfileStoreCrossProcessLock] = [:]

    private func crossProcessLock() -> ProfileStoreCrossProcessLock {
        let directory = fileURL.deletingLastPathComponent().standardizedFileURL.path
        if let lock = Self.crossProcessLocks[directory] { return lock }
        let lock = ProfileStoreCrossProcessLock(
            directory: URL(fileURLWithPath: directory, isDirectory: true))
        Self.crossProcessLocks[directory] = lock
        return lock
    }

     
     
     
     
     
    private static let writeLock = NSRecursiveLock()
     
     
    nonisolated(unsafe) private static var lockDepth = 0
    nonisolated(unsafe) private static var wroteUnderLock = false

     
    private func write(_ profiles: [Profile]) throws {
         
         
        if case .unreadable = state() { throw StoreError.unreadableStore }
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(profiles)
        try data.write(to: fileURL, options: Self.writeOptions)
        Self.wroteUnderLock = true
    }

     
     
     
     
     
     
     
    private static func announceWrite() {
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

     
     
     
     
     
    @discardableResult
    func updateIfPresent(id: String, when condition: (Profile) -> Bool = { _ in true },
                         _ change: (inout Profile) throws -> Void) throws -> Profile? {
        try withWriteLock {
            var profiles = load()
            guard let index = profiles.firstIndex(where: { $0.id == id }), condition(profiles[index]) else {
                return nil
            }
            try change(&profiles[index])
            try write(profiles)
            return profiles[index]
        }
    }



    // In-process only. Code that reads and then saves the whole list needs the
    // instance variant, which holds the cross-process lock for the whole
    // read-modify-write.
    static func withWriteLock<T>(_ body: () throws -> T) rethrows -> T {
        writeLock.lock()
        lockDepth += 1


        defer {
            lockDepth -= 1
            let announce = lockDepth == 0 && wroteUnderLock
            if lockDepth == 0 { wroteUnderLock = false }
            writeLock.unlock()
            if announce { announceWrite() }
        }
        return try body()
    }

     
     
    static let didChangeNotification = Notification.Name("ClashProfileStoreDidChange")

    func upsert(_ profile: Profile) throws {
        try withWriteLock {
            var profiles = load()
            if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
                profiles[idx] = profile
            } else {
                profiles.append(profile)
            }
            try write(profiles)
        }
    }

    func remove(id: String) throws {
        try withWriteLock { try write(load().filter { $0.id != id }) }
    }

     
     
     
     
     
    @discardableResult
    func updateAll(_ change: (inout [Profile]) throws -> Void) throws -> Bool {
        try withWriteLock {
            var profiles = load()
            let before = profiles
            try change(&profiles)
            guard profiles != before else { return false }
            try write(profiles)
            return true
        }
    }

     
     
    @discardableResult
    func insertIfAbsent(_ profile: Profile) throws -> Bool {
        try withWriteLock {
            var profiles = load()
            guard !profiles.contains(where: { $0.id == profile.id }) else { return false }
            profiles.append(profile)
            try write(profiles)
            return true
        }
    }
}

 
 
 
 
 
 
 
enum PersonalRulePlacementMigration {
    static let completedKey = "clash.migration.personal-rule-placement.v1"

    static func runIfNeeded(store: ProfileStore, defaults: UserDefaults) {
        guard !defaults.bool(forKey: completedKey) else { return }
         
         
        guard (try? store.updateAll({ profiles in
            for index in profiles.indices where !profiles[index].override.prependRules {
                profiles[index].override.prependRules = true
            }
        })) != nil else { return }
        defaults.set(true, forKey: completedKey)
    }
}
