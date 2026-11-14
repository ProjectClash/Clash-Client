import CryptoKit
import Darwin
import Foundation

struct StoredConfiguration: Equatable {
    let profileID: String
    let revision: String
    let data: Data
    let recoveredFromLastKnownGood: Bool

    var text: String? { String(data: data, encoding: .utf8) }
}

struct InstalledConfiguration: Equatable {
    let profileID: String
    let revision: String
    let sha256: String
    let bytes: Int
    let reusedExistingRevision: Bool
    let activated: Bool
}

struct ActiveConfigurationPointer: Codable, Equatable {
    let profileID: String
    let revision: String
}

 
 
 
 
 
struct SuspensionShield {
    let begin: () -> Any?
    let end: (Any?) -> Void

    static let noop = SuspensionShield(begin: { nil }, end: { _ in })
}

 
 
 
struct ConfigurationCandidate: Equatable {
    let profileID: String
    let revision: String
    let stagingDirectory: URL
    let publishedDirectory: URL

    var stagingProvidersDirectory: URL {
        stagingDirectory.appendingPathComponent("providers", isDirectory: true)
    }

    var publishedProvidersDirectory: URL {
        publishedDirectory.appendingPathComponent("providers", isDirectory: true)
    }
}

enum ConfigResourceStoreError: LocalizedError {
    case invalidLimit
    case invalidProfileID
    case emptyConfiguration
    case configurationTooLarge(limit: Int)
    case configurationIsNotUTF8
    case configurationContainsNUL
    case unsafeFilesystemEntry(String)
    case lockTimedOut
    case noValidConfiguration
    case invalidRevision
    case corruptRevision
    case invalidActivation
    case activeConfigurationChanged
    case posix(operation: String, code: Int32)
    case simulatedCrash(ConfigResourceStoreFaultPoint)

    var errorDescription: String? {
        switch self {
        case .invalidLimit:
            return "Configuration store limits are invalid"
        case .invalidProfileID:
            return "Configuration profile ID is invalid"
        case .emptyConfiguration:
            return "Configuration is empty"
        case let .configurationTooLarge(limit):
            return "Configuration exceeds the \(limit)-byte limit"
         
         
         
        case .configurationIsNotUTF8, .configurationContainsNUL:
            return "That configuration is not a text file. Choose a different one."
        case let .unsafeFilesystemEntry(name):
            return "Configuration store entry is unsafe: \(name)"
        case .lockTimedOut:
            return "The configuration is in use. Try again in a moment."
        case .noValidConfiguration:
            return "No valid active or last-known-good configuration is available"
        case .invalidRevision:
            return "Configuration revision is invalid"
        case .corruptRevision:
            return "The saved configuration is damaged. Import it again."
        case .invalidActivation:
            return "The configuration could not be activated. Try again."
        case .activeConfigurationChanged:
            return "The active configuration changed while a replacement was being prepared"
        case let .posix(operation, code):
            return "Configuration store \(operation) failed (errno \(code))"
        case let .simulatedCrash(point):
            return "Simulated configuration store crash at \(point.rawValue)"
        }
    }
}

enum ConfigResourceStoreFaultPoint: String {
    case revisionDurable
    case revisionPublished
     
     
    case activating
    case currentCommitted
}

 
 
 
 
 
final class ConfigResourceStore {
     
     
     
     
     
     
     
     
    static let defaultMaximumConfigurationBytes = Int.max
     
     
     
    static let defaultMaximumRevisions = 5
    static let defaultProfileID = "00000000-0000-0000-0000-000000000000"
    static let abandonedCandidateAge: TimeInterval = 24 * 60 * 60
    static let maximumCandidateResources = 256
    static let maximumCandidateResourceBytes = 16 * 1024 * 1024

    private struct Manifest: Codable, Equatable {
        let schemaVersion: Int
        let profileID: String
        let revision: String
        let configurationBytes: Int
        let configurationSHA256: String
        let createdAtUnixMilliseconds: Int64
        let resources: [ResourceDigest]?
    }

    private struct ResourceDigest: Codable, Equatable {
        let path: String
        let bytes: Int
        let sha256: String
    }

    private struct Pointer: Codable, Equatable {
        let schemaVersion: Int
        let profileID: String
        let revision: String
    }

    private enum Name {
        static let working = "working"
        static let store = "store"
        static let profiles = "profiles"
        static let revisions = "revisions"
        static let activeDirectory = "active"
        static let lock = ".configuration-store.lock"
        static let activePointer = "active.json"
        static let lastKnownGoodPointer = "last-known-good.json"
         
         
         
         
        static let replacedActivePointer = "replaced-active.json"
        static let profileCurrent = "current"
        static let resolvedConfiguration = "config.resolved.yaml"
        static let compatibilityConfiguration = "config.yaml"
        static let manifest = "manifest.json"
        static let temporaryPrefix = ".tmp-"
         
         
         
        static let setAsidePrefix = #".removed-"#
        static let payloads = "payloads"
    }

     
    var payloadStore: ProviderPayloadStore { ProviderPayloadStore(workingDirectory: workingURL) }

    private let containerURL: URL
    private let workingURL: URL
    private let storeURL: URL
    private let profilesURL: URL
    private let activeDirectoryURL: URL
    private let lockURL: URL
    private let maximumConfigurationBytes: Int
    private let maximumRevisions: Int
    private let lockTimeout: TimeInterval
    private let faultInjector: ((ConfigResourceStoreFaultPoint) -> Bool)?
    private let fileManager: FileManager

    var activeConfigURL: URL {
        activeDirectoryURL.appendingPathComponent(Name.compatibilityConfiguration)
    }

    init(
        containerURL: URL,
        maximumConfigurationBytes: Int = ConfigResourceStore.defaultMaximumConfigurationBytes,
        maximumRevisions: Int = ConfigResourceStore.defaultMaximumRevisions,
        lockTimeout: TimeInterval = 2,
        fileManager: FileManager = .default,
        faultInjector: ((ConfigResourceStoreFaultPoint) -> Bool)? = nil
    ) throws {
        guard maximumConfigurationBytes > 0,
              maximumRevisions >= 2,
              lockTimeout > 0 else {
            throw ConfigResourceStoreError.invalidLimit
        }
        self.containerURL = containerURL.standardizedFileURL
        workingURL = self.containerURL.appendingPathComponent(Name.working, isDirectory: true)
        storeURL = workingURL.appendingPathComponent(Name.store, isDirectory: true)
        profilesURL = storeURL.appendingPathComponent(Name.profiles, isDirectory: true)
        activeDirectoryURL = workingURL.appendingPathComponent(
            Name.activeDirectory,
            isDirectory: true
        )
        lockURL = workingURL.appendingPathComponent(Name.lock)
        self.maximumConfigurationBytes = maximumConfigurationBytes
        self.maximumRevisions = maximumRevisions
        self.lockTimeout = lockTimeout
        self.fileManager = fileManager
        self.faultInjector = faultInjector
        try verifyContainerDirectory()
    }

     
     
    @discardableResult
    func install(
        _ data: Data,
        profileID: String = ConfigResourceStore.defaultProfileID,
        activate: Bool = true,
        markAsLastKnownGood: Bool = false
    ) throws -> InstalledConfiguration {
        try validateProfileID(profileID)
        try validateConfiguration(data)
        guard activate || !markAsLastKnownGood else {
            throw ConfigResourceStoreError.invalidActivation
        }
        return try withExclusiveLock {
            try prepareLayout()
            let profile = try prepareProfile(profileID)
            let digest = Self.sha256(data)
            let revision: String
            let reused: Bool

            if let currentRevision = try? readProfileCurrent(profile),
               let current = try? loadRevision(
                   Pointer(schemaVersion: 1, profileID: profileID, revision: currentRevision)
               ),
               Self.sha256(current.data) == digest {
                revision = currentRevision
                reused = true
            } else {
                revision = try publishRevision(
                    data,
                    digest: digest,
                    profileID: profileID,
                    profile: profile
                )
                reused = false
                try writeProfileCurrent(profile, revision: revision)
            }

            let pointer = Pointer(schemaVersion: 1, profileID: profileID, revision: revision)
            if activate {
                try commitActive(pointer, data: data)
                if markAsLastKnownGood {
                    try writePointer(Name.lastKnownGoodPointer, pointer: pointer)
                }
            }
            try pruneProfile(profileID)
            return InstalledConfiguration(
                profileID: profileID,
                revision: revision,
                sha256: digest,
                bytes: data.count,
                reusedExistingRevision: reused,
                activated: activate
            )
        }
    }

    @discardableResult
    func activate(
        profileID: String,
        revision: String,
        markAsLastKnownGood: Bool = false
    ) throws -> StoredConfiguration {
        try validateProfileID(profileID)
        guard Self.isValidRevision(revision) else {
            throw ConfigResourceStoreError.invalidRevision
        }
        return try withExclusiveLock {
            try prepareLayout()
            let pointer = Pointer(schemaVersion: 1, profileID: profileID, revision: revision)
            let loaded = try loadRevision(pointer)
            try commitActive(pointer, data: loaded.data)
            if markAsLastKnownGood {
                try writePointer(Name.lastKnownGoodPointer, pointer: pointer)
            }
            return loaded
        }
    }

     
     
     
    func beginCandidate(profileID: String) throws -> ConfigurationCandidate {
        try validateProfileID(profileID)
        return try withExclusiveLock {
            try prepareLayout()
            let profile = try prepareProfile(profileID)
            let revision = UUID().uuidString.lowercased()
            let staging = profile.revisions.appendingPathComponent(
                Name.temporaryPrefix + revision,
                isDirectory: true
            )
            let published = profile.revisions.appendingPathComponent(revision, isDirectory: true)
            try ensureNewDirectory(staging)
            let providers = staging.appendingPathComponent("providers", isDirectory: true)
            try ensureNewDirectory(providers)
            try syncDirectory(staging)
            return ConfigurationCandidate(
                profileID: profileID,
                revision: revision,
                stagingDirectory: staging,
                publishedDirectory: published
            )
        }
    }

     
     
     
    @discardableResult
    func publishAndActivate(
        _ candidate: ConfigurationCandidate,
        finalData: Data
    ) throws -> ActiveConfigurationPointer? {
        try publishAndActivate(
            candidate,
            finalData: finalData,
            expectation: .unconstrained
        )
    }

     
     
     
     
    func publishAndActivateIfCurrentMatches(
        _ candidate: ConfigurationCandidate,
        finalData: Data,
        expectedActive: ActiveConfigurationPointer?
    ) throws -> ActiveConfigurationPointer? {
        try publishAndActivate(
            candidate,
            finalData: finalData,
            expectation: .matches(expectedActive)
        )
    }

    enum ActiveExpectation {
        case unconstrained
        case matches(ActiveConfigurationPointer?)
         
         
         
         
         
         
        case matchesWithCatalog(ActiveConfigurationPointer, catalog: Data?)
    }

     
    func catalogData(of pointer: ActiveConfigurationPointer) -> Data? {
        try? Data(contentsOf: profilePaths(pointer.profileID).revisions
            .appendingPathComponent(pointer.revision, isDirectory: true)
            .appendingPathComponent(Self.appCatalogResource))
    }

     
    private func admits(_ expectation: ActiveExpectation, active: ActiveConfigurationPointer?) -> Bool {
        switch expectation {
        case .unconstrained: return true
        case .matches(let expected): return active == expected
        case .matchesWithCatalog(let expected, let catalog):
            return active == expected && catalogData(of: expected) == catalog
        }
    }

    private func publishAndActivate(
        _ candidate: ConfigurationCandidate,
        finalData: Data,
        expectation: ActiveExpectation
    ) throws -> ActiveConfigurationPointer? {
        try validateProfileID(candidate.profileID)
        guard Self.isValidRevision(candidate.revision) else {
            throw ConfigResourceStoreError.invalidRevision
        }
        try validateConfiguration(finalData)
        return try withExclusiveLock {
            try prepareLayout()
            let previousPointer = try? readPointer(Name.activePointer)
            let previous = previousPointer.flatMap { pointer -> ActiveConfigurationPointer? in
                guard (try? loadRevision(pointer)) != nil else { return nil }
                return ActiveConfigurationPointer(
                    profileID: pointer.profileID,
                    revision: pointer.revision
                )
            }
            if !admits(expectation, active: previous) {
                throw ConfigResourceStoreError.activeConfigurationChanged
            }
            try writeCandidateLocked(candidate, finalData: finalData)
            try publishCandidateLocked(candidate)

            let profile = profilePaths(candidate.profileID)
            try writeProfileCurrent(profile, revision: candidate.revision)
            let pointer = Pointer(
                schemaVersion: 1,
                profileID: candidate.profileID,
                revision: candidate.revision
            )
            try commitActive(pointer, data: finalData)
            try pruneProfile(candidate.profileID)
            return previous
        }
    }

     
     
     
     
    private func writeCandidateLocked(_ candidate: ConfigurationCandidate, finalData: Data) throws {
        let expected = candidateFor(profileID: candidate.profileID, revision: candidate.revision)
        guard candidate == expected,
              try entryType(at: candidate.stagingDirectory) == S_IFDIR,
              !fileManager.fileExists(atPath: candidate.publishedDirectory.path) else {
            throw ConfigResourceStoreError.invalidRevision
        }
        try writeDurableFile(
            finalData,
            to: candidate.stagingDirectory.appendingPathComponent(Name.resolvedConfiguration)
        )
        let manifest = Manifest(
            schemaVersion: 1,
            profileID: candidate.profileID,
            revision: candidate.revision,
            configurationBytes: finalData.count,
            configurationSHA256: Self.sha256(finalData),
            createdAtUnixMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000),
            resources: try validateSyncAndDigestCandidateResources(candidate)
        )
        try writeDurableFile(
            try encode(manifest),
            to: candidate.stagingDirectory.appendingPathComponent(Name.manifest)
        )
        try syncDirectory(candidate.stagingDirectory)
    }

     
     
    private func publishCandidateLocked(_ candidate: ConfigurationCandidate) throws {
        try renameItem(from: candidate.stagingDirectory, to: candidate.publishedDirectory)
        try syncDirectory(candidate.publishedDirectory.deletingLastPathComponent())
        noteWhole(profileID: candidate.profileID, revision: candidate.revision)
    }

     
     
    struct StagedRevision: Equatable {
        let pointer: ActiveConfigurationPointer
        fileprivate let finalData: Data
    }

     
     
     
     
     
     
    func stage(_ candidate: ConfigurationCandidate, finalData: Data) throws -> StagedRevision {
        try validateProfileID(candidate.profileID)
        guard Self.isValidRevision(candidate.revision) else {
            throw ConfigResourceStoreError.invalidRevision
        }
        try validateConfiguration(finalData)
        return try withExclusiveLock {
            try prepareLayout()
            try writeCandidateLocked(candidate, finalData: finalData)
            return StagedRevision(
                pointer: ActiveConfigurationPointer(profileID: candidate.profileID, revision: candidate.revision),
                finalData: finalData
            )
        }
    }

     
     
     
     
     
     
    func activateStaged(_ staged: StagedRevision, expectation: ActiveExpectation) throws -> ActiveConfigurationPointer? {
        try withExclusiveLock { try activateStagedLocked(staged, expectation: expectation) }
    }

    enum LockFreeActivation {
        case activated(previous: ActiveConfigurationPointer?)
         
        case busy
    }

     
     
     
    func activateStagedIfLockFree(_ staged: StagedRevision, expectation: ActiveExpectation) throws -> LockFreeActivation {
        guard let previous = try withExclusiveLockIfFree(operation: "activateStaged", {
            try activateStagedLocked(staged, expectation: expectation)
        }) else { return .busy }
        return .activated(previous: previous)
    }

     
    func waitUntilLockIsFree() throws {
        try withExclusiveLock(operation: "waitUntilLockIsFree") {}
    }

    private func activateStagedLocked(_ staged: StagedRevision, expectation: ActiveExpectation) throws -> ActiveConfigurationPointer? {
        try prepareLayout()
            let previous = validatedActiveLocked()
            if !admits(expectation, active: previous) {
                throw ConfigResourceStoreError.activeConfigurationChanged
            }
            let candidate = candidateFor(profileID: staged.pointer.profileID, revision: staged.pointer.revision)
             
            guard try entryType(at: candidate.stagingDirectory) == S_IFDIR,
                  !fileManager.fileExists(atPath: candidate.publishedDirectory.path) else {
                throw ConfigResourceStoreError.invalidRevision
            }
            try inject(.activating)
            try publishCandidateLocked(candidate)
            let pointer = Pointer(schemaVersion: 1, profileID: staged.pointer.profileID, revision: staged.pointer.revision)
            try writeProfileCurrent(profilePaths(pointer.profileID), revision: pointer.revision)
            try commitPointer(pointer)
            return previous
    }

     
     
     
     
    func activeIdentityWithoutLock() -> ActiveConfigurationPointer? {
        guard let pointer = try? readPointer(Name.activePointer) else { return nil }
        return ActiveConfigurationPointer(profileID: pointer.profileID, revision: pointer.revision)
    }

     
     
     
     
    func lastKnownGoodIdentityWithoutLock() -> ActiveConfigurationPointer? {
        guard let pointer = try? readPointer(Name.lastKnownGoodPointer) else { return nil }
        return ActiveConfigurationPointer(profileID: pointer.profileID, revision: pointer.revision)
    }

     
     
     
    func finishActivation(_ staged: StagedRevision) {
        try? withExclusiveLock {
            let pointer = Pointer(schemaVersion: 1, profileID: staged.pointer.profileID, revision: staged.pointer.revision)
            if (try? readPointer(Name.activePointer)) == pointer {
                writeMirrors(pointer, data: staged.finalData)
            }
            try pruneProfile(pointer.profileID)
        }
    }

     
     
    func discardStaged(_ staged: StagedRevision) {
        try? withExclusiveLock {
            let candidate = candidateFor(profileID: staged.pointer.profileID, revision: staged.pointer.revision)
            if fileManager.fileExists(atPath: candidate.stagingDirectory.path) {
                try fileManager.removeItem(at: candidate.stagingDirectory)
                try syncDirectory(candidate.stagingDirectory.deletingLastPathComponent())
                return
            }
            let pointer = Pointer(schemaVersion: 1, profileID: staged.pointer.profileID, revision: staged.pointer.revision)
            let profile = profilePaths(pointer.profileID)
            guard (try? readPointer(Name.activePointer)) != pointer,
                  (try? readPointer(Name.lastKnownGoodPointer)) != pointer,
                  (try? readPointer(Name.replacedActivePointer)) != pointer,
                  (try? readProfileCurrent(profile)) != pointer.revision else { return }
            let revision = profile.revisions.appendingPathComponent(pointer.revision, isDirectory: true)
            if fileManager.fileExists(atPath: revision.path) {
                try fileManager.removeItem(at: revision)
                try syncDirectory(profile.revisions)
            }
        }
    }

    func discard(_ candidate: ConfigurationCandidate) throws {
        try withExclusiveLock {
            let expected = candidateFor(profileID: candidate.profileID, revision: candidate.revision)
            guard candidate == expected else { throw ConfigResourceStoreError.invalidRevision }
            if fileManager.fileExists(atPath: candidate.stagingDirectory.path) {
                try fileManager.removeItem(at: candidate.stagingDirectory)
                try syncDirectory(candidate.stagingDirectory.deletingLastPathComponent())
            }
        }
    }

     
     
     
    static let appCatalogResource = "providers/providers.json"

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func adoptIfEquivalentToActive(
        _ candidate: ConfigurationCandidate,
        finalData: Data,
        expectation: ActiveExpectation
    ) -> ActiveConfigurationPointer? {
        guard candidate == candidateFor(profileID: candidate.profileID, revision: candidate.revision),
              let text = String(data: finalData, encoding: .utf8) else { return nil }
        return try? withExclusiveLock { () -> ActiveConfigurationPointer? in
            guard let pointer = try? readPointer(Name.activePointer),
                  pointer.profileID == candidate.profileID,
                  pointer.revision != candidate.revision else { return nil }
            let active = ActiveConfigurationPointer(profileID: pointer.profileID, revision: pointer.revision)
            if !admits(expectation, active: active) { return nil }
            let revisionURL = profilePaths(pointer.profileID).revisions
                .appendingPathComponent(pointer.revision, isDirectory: true)
            let manifestURL = revisionURL.appendingPathComponent(Name.manifest)
            guard let manifest = try? JSONDecoder().decode(
                Manifest.self, from: readBoundedFile(manifestURL, maximumBytes: 64 * 1024)
            ) else { return nil }
            let asInUse = Data(text.replacingOccurrences(of: candidate.revision, with: pointer.revision).utf8)
            guard asInUse.count == manifest.configurationBytes,
                  Self.sha256(asInUse) == manifest.configurationSHA256,
                  let resources = try? validateSyncAndDigestCandidateResources(candidate, sync: false) else { return nil }
            let inUse = manifest.resources ?? []
            let catalog = Self.appCatalogResource
            guard resources.filter({ $0.path != catalog }) == inUse.filter({ $0.path != catalog }) else { return nil }
             
            guard isKnownWhole(pointer) || (try? loadRevision(pointer)) != nil else { return nil }
            let catalogInUseURL = revisionURL.appendingPathComponent(catalog)
            let catalogURL = candidate.stagingDirectory.appendingPathComponent(catalog)
            if let catalogData = try? readBoundedFile(catalogURL, maximumBytes: Self.maximumCandidateResourceBytes),
               (try? readBoundedFile(catalogInUseURL, maximumBytes: Self.maximumCandidateResourceBytes)) != catalogData {
                 
                 
                 
                 
                 
                try writeAtomicFile(catalogData, to: catalogInUseURL)
            }
            return active
        }
    }

    func activePointer() throws -> ActiveConfigurationPointer? {
        try provedPointer(Name.activePointer)
    }

     
     
     
     
     
     
     
     
     
    private func provedPointer(_ name: String, operation: String = #function) throws -> ActiveConfigurationPointer? {
        func lockedRead() throws -> Pointer? {
            try withExclusiveLock(operation: operation) {
                try prepareLayout()
                return try? readPointer(name)
            }
        }
        var pointer = try lockedRead()
        for _ in 0..<3 {
            guard let candidate = pointer else { return nil }
            let proved = (try? loadRevision(candidate)) != nil
            let now = try lockedRead()
            guard now == candidate else {
                pointer = now
                continue
            }
            if proved { return ActiveConfigurationPointer(profileID: candidate.profileID, revision: candidate.revision) }
            break
        }
        return try withExclusiveLock(operation: operation) {
            try prepareLayout()
            guard let pointer = try? readPointer(name), (try? loadRevision(pointer)) != nil else { return nil }
            return ActiveConfigurationPointer(profileID: pointer.profileID, revision: pointer.revision)
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private static let knownWholeLock = NSLock()
    private static var knownWhole = Set<String>()

    private func knownWholeKey(profileID: String, revision: String) -> String {
        storeURL.path + "\u{0}" + profileID + "\u{0}" + revision
    }

    private func noteWhole(profileID: String, revision: String) {
        let key = knownWholeKey(profileID: profileID, revision: revision)
        Self.knownWholeLock.lock()
        Self.knownWhole.insert(key)
        Self.knownWholeLock.unlock()
    }

    private func isKnownWhole(_ pointer: Pointer) -> Bool {
        let key = knownWholeKey(profileID: pointer.profileID, revision: pointer.revision)
        Self.knownWholeLock.lock()
        let known = Self.knownWhole.contains(key)
        Self.knownWholeLock.unlock()
        guard known else { return false }
        let directory = profilePaths(pointer.profileID).revisions
            .appendingPathComponent(pointer.revision, isDirectory: true)
        return (try? entryType(at: directory)) == S_IFDIR
    }

     
     
     
    private func validatedActiveLocked() -> ActiveConfigurationPointer? {
        guard let pointer = try? readPointer(Name.activePointer),
              isKnownWhole(pointer) || (try? loadRevision(pointer)) != nil else { return nil }
        return ActiveConfigurationPointer(profileID: pointer.profileID, revision: pointer.revision)
    }

     
    func activeIdentityOrNil() -> ActiveConfigurationPointer? {
        (try? activeIdentity()) ?? nil
    }

    func activeIdentity() throws -> ActiveConfigurationPointer? {
        let url = storeURL.appendingPathComponent(Name.activePointer)
        let stamp = Self.pointerStamp(of: url)
        Self.activePointerCacheLock.lock()
        if let cached = Self.activePointerCache[url.path], cached.stamp == stamp {
            Self.activePointerCacheLock.unlock()
            return cached.pointer
        }
        Self.activePointerCacheLock.unlock()
         
         
         
         
        let (pointer, read): (ActiveConfigurationPointer?, PointerStamp?) = try withExclusiveLock {


            let stamp = Self.pointerStamp(of: url)
            guard let pointer = try? readPointer(Name.activePointer) else {
                return (nil, stamp)
            }
            return (ActiveConfigurationPointer(
                profileID: pointer.profileID,
                revision: pointer.revision
            ), stamp)
        }


        Self.activePointerCacheLock.lock()
        Self.activePointerCache[url.path] = (read, pointer)
        Self.activePointerCacheLock.unlock()
        return pointer
    }

     
     
     
     
     
     
     
     
     
     
    func publishedName() throws -> ActiveConfigurationPointer? {
        try withExclusiveLock {
            var unreadable: Error?
            for name in [Name.activePointer, Name.lastKnownGoodPointer]
            where fileManager.fileExists(atPath: storeURL.appendingPathComponent(name).path) {
                do {
                    let pointer = try readPointer(name)
                    return ActiveConfigurationPointer(profileID: pointer.profileID, revision: pointer.revision)
                } catch {
                    unreadable = error
                }
            }
            if let unreadable { throw unreadable }
            let versioned = [Name.activePointer, Name.lastKnownGoodPointer].contains {
                fileManager.fileExists(atPath: storeURL.appendingPathComponent($0).path)
            }
            if !versioned,
               fileManager.fileExists(atPath: containerURL.appendingPathComponent(Name.compatibilityConfiguration).path) {
                return ActiveConfigurationPointer(profileID: ConfigResourceStore.defaultProfileID, revision: "legacy-unversioned")
            }
            return nil
        }
    }

    private struct PointerStamp: Equatable {
        let size: Int
        let modified: Date
    }
    private static let activePointerCacheLock = NSLock()
    private static var activePointerCache: [String: (stamp: PointerStamp?, pointer: ActiveConfigurationPointer?)] = [:]
    private static func pointerStamp(of url: URL) -> PointerStamp? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.intValue,
              let modified = attributes[.modificationDate] as? Date else { return nil }
        return PointerStamp(size: size, modified: modified)
    }
    private static func forgetActivePointer(at url: URL) {
        activePointerCacheLock.lock()
        activePointerCache[url.path] = nil
        activePointerCacheLock.unlock()
    }



    func lastKnownGoodPointer() throws -> ActiveConfigurationPointer? {
        try provedPointer(Name.lastKnownGoodPointer)
    }

     
     
     
     
    @discardableResult
    func activateIfCurrentMatches(
        _ expected: ActiveConfigurationPointer?,
        replacement: ActiveConfigurationPointer,
        markAsLastKnownGood: Bool = false
    ) throws -> Bool {
        try validateProfileID(replacement.profileID)
        guard Self.isValidRevision(replacement.revision) else {
            throw ConfigResourceStoreError.invalidRevision
        }
        return try withExclusiveLock {
            try prepareLayout()
            let current: ActiveConfigurationPointer?
            if let pointer = try? readPointer(Name.activePointer),
               (try? loadRevision(pointer)) != nil {
                current = ActiveConfigurationPointer(
                    profileID: pointer.profileID,
                    revision: pointer.revision
                )
            } else {
                current = nil
            }
            guard current == expected else { return false }
            let pointer = Pointer(
                schemaVersion: 1,
                profileID: replacement.profileID,
                revision: replacement.revision
            )
            let loaded = try loadRevision(pointer)
            try commitActive(pointer, data: loaded.data)
            if markAsLastKnownGood {
                try writePointer(Name.lastKnownGoodPointer, pointer: pointer)
            }
            try pruneProfile(replacement.profileID)
            return true
        }
    }

    func rollback(to pointer: ActiveConfigurationPointer) throws {
        _ = try activate(profileID: pointer.profileID, revision: pointer.revision)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func activeProvidersDirectory() throws -> URL? {
        guard let pointer = try activeIdentity() else { return nil }
        return providersDirectory(profileID: pointer.profileID, revision: pointer.revision)
    }

     
     
     
     
     
     
     
     
    func newestProvidersDirectory(profileID: String) -> URL? {
        guard (try? validateProfileID(profileID)) != nil else { return nil }
        let revisions = profilePaths(profileID).revisions
        guard let entries = try? fileManager.contentsOfDirectory(
            at: revisions,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        return entries
            .filter { Self.isValidRevision($0.lastPathComponent) }
            .map { ($0.appendingPathComponent("providers", isDirectory: true),
                    (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate ?? .distantPast) }
            .filter { fileManager.fileExists(atPath: $0.0.path) }
            .sorted { $0.1 > $1.1 }
            .first?.0
    }

     
     
     
     
     
     
     
     
     
    func providersDirectory(profileID: String, revision: String) -> URL? {
        guard (try? validateProfileID(profileID)) != nil,
              Self.isValidRevision(revision) else { return nil }
        return profilePaths(profileID).revisions
            .appendingPathComponent(revision, isDirectory: true)
            .appendingPathComponent("providers", isDirectory: true)
    }

     
     
     
     
    func publishedConfigurationURL(profileID: String, revision: String) -> URL? {
        guard (try? validateProfileID(profileID)) != nil, Self.isValidRevision(revision) else { return nil }
        let url = profilePaths(profileID).revisions.appendingPathComponent(revision, isDirectory: true)
            .appendingPathComponent(Name.resolvedConfiguration)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

     
     
    func loadConfiguration(profileID: String, revision: String) throws -> StoredConfiguration {
        try validateProfileID(profileID)
        guard Self.isValidRevision(revision) else {
            throw ConfigResourceStoreError.invalidRevision
        }
        let pointer = Pointer(schemaVersion: 1, profileID: profileID, revision: revision)
         
         
         
         
        if let stored = try? loadRevision(pointer) { return stored }
        return try withExclusiveLock {
            try prepareLayout()
            return try loadRevision(pointer)
        }
    }

     
     
     
    func restoreActive(_ pointer: ActiveConfigurationPointer?) throws {
        if let pointer {
            try rollback(to: pointer)
            return
        }
        try withExclusiveLock {
            try prepareLayout()
            try removeActiveFiles()
        }
    }

     
     
     
    @discardableResult
    func deactivateIfCurrentMatches(_ expected: ActiveConfigurationPointer) throws -> Bool {
        try withExclusiveLock {
            try prepareLayout()
            guard let pointer = try? readPointer(Name.activePointer),
                  ActiveConfigurationPointer(profileID: pointer.profileID, revision: pointer.revision) == expected
            else { return false }
            try removeActiveFiles()
            return true
        }
    }

     
    private func removeActiveFiles() throws {
        for url in [
            storeURL.appendingPathComponent(Name.activePointer),
            activeDirectoryURL.appendingPathComponent(Name.compatibilityConfiguration),
            activeDirectoryURL.appendingPathComponent(Name.manifest),
            containerURL.appendingPathComponent(Name.compatibilityConfiguration),
        ] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
            try syncDirectory(url.deletingLastPathComponent())
        }
    }

     
     
     
     
     
     
     
     
     
    func loadCurrent() throws -> StoredConfiguration {
        let first = try withExclusiveLock { () throws -> (named: Pointer?, decided: StoredConfiguration?) in
            try prepareLayout()
            guard let pointer = try? readPointer(Name.activePointer) else { return (nil, try loadCurrentLocked()) }
            return (pointer, nil)
        }
        if let decided = first.decided { return decided }
        if let named = first.named, let loaded = try? loadRevision(named),
           try withExclusiveLock({ try? readPointer(Name.activePointer) }) == named {
            return loaded
        }
        return try withExclusiveLock {
            try prepareLayout()
            return try loadCurrentLocked()
        }
    }

     
    private func loadCurrentLocked() throws -> StoredConfiguration {
        let hasVersionedPointer = fileManager.fileExists(
            atPath: storeURL.appendingPathComponent(Name.activePointer).path
        ) || fileManager.fileExists(
            atPath: storeURL.appendingPathComponent(Name.lastKnownGoodPointer).path
        )
        if let active = try? readPointer(Name.activePointer),
           let loaded = try? loadRevision(active) {
            return loaded
        }
        if let lastKnownGood = try? readPointer(Name.lastKnownGoodPointer),
           let loaded = try? loadRevision(lastKnownGood) {
            return StoredConfiguration(
                profileID: loaded.profileID,
                revision: loaded.revision,
                data: loaded.data,
                recoveredFromLastKnownGood: true
            )
        }
        if !hasVersionedPointer,
           let legacy = try loadLegacyConfigurationIfPresent() {
            return legacy
        }
        throw ConfigResourceStoreError.noValidConfiguration
    }

     
     
    @discardableResult
    func recoverCurrentFromLastKnownGood() throws -> StoredConfiguration {
        try withExclusiveLock {
            try prepareLayout()
            if let active = try? readPointer(Name.activePointer),
               let loaded = try? loadRevision(active) {
                return loaded
            }
            let fallback = try readPointer(Name.lastKnownGoodPointer)
            let loaded = try loadRevision(fallback)
            try commitActive(fallback, data: loaded.data)
            return StoredConfiguration(
                profileID: loaded.profileID,
                revision: loaded.revision,
                data: loaded.data,
                recoveredFromLastKnownGood: true
            )
        }
    }

    func markLastKnownGood(profileID: String, revision: String) throws {
        try validateProfileID(profileID)
        guard Self.isValidRevision(revision) else {
            throw ConfigResourceStoreError.invalidRevision
        }
        try withExclusiveLock {
            try prepareLayout()
            let pointer = Pointer(schemaVersion: 1, profileID: profileID, revision: revision)
            _ = try loadRevision(pointer)
            try writePointer(Name.lastKnownGoodPointer, pointer: pointer)
            try pruneProfile(profileID)
        }
    }

    func currentRevision() throws -> String? {
        try withExclusiveLock {
            try prepareLayout()
            return try? readPointer(Name.activePointer).revision
        }
    }

    func currentProfileID() throws -> String? {
        try withExclusiveLock {
            try prepareLayout()
            return try? readPointer(Name.activePointer).profileID
        }
    }

    private struct ProfilePaths {
        let root: URL
        let revisions: URL
    }

    private func profilePaths(_ profileID: String) -> ProfilePaths {
        let root = profilesURL.appendingPathComponent(profileID, isDirectory: true)
        return ProfilePaths(
            root: root,
            revisions: root.appendingPathComponent(Name.revisions, isDirectory: true)
        )
    }

    private func candidateFor(profileID: String, revision: String) -> ConfigurationCandidate {
        let revisions = profilePaths(profileID).revisions
        return ConfigurationCandidate(
            profileID: profileID,
            revision: revision,
            stagingDirectory: revisions.appendingPathComponent(
                Name.temporaryPrefix + revision,
                isDirectory: true
            ),
            publishedDirectory: revisions.appendingPathComponent(revision, isDirectory: true)
        )
    }

    private func prepareLayout() throws {
        try ensureDirectory(workingURL)
         
         
         
         
        var protectedWorkingURL = workingURL
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try protectedWorkingURL.setResourceValues(resourceValues)
        try ensureDirectory(storeURL)
        try ensureDirectory(profilesURL)
        try ensureDirectory(activeDirectoryURL)
        try removeAbandonedTemporaryEntries(in: storeURL)
        try removeAbandonedTemporaryEntries(in: activeDirectoryURL)
    }

    private func prepareProfile(_ profileID: String) throws -> ProfilePaths {
        let profile = profilePaths(profileID)
        try ensureDirectory(profile.root)
        try ensureDirectory(profile.revisions)
        try removeAbandonedTemporaryEntries(
            in: profile.root,
            olderThan: Self.abandonedCandidateAge
        )
        try removeAbandonedTemporaryEntries(
            in: profile.revisions,
            olderThan: Self.abandonedCandidateAge
        )
        return profile
    }

    private func publishRevision(
        _ data: Data,
        digest: String,
        profileID: String,
        profile: ProfilePaths
    ) throws -> String {
        let revision = UUID().uuidString.lowercased()
        let temporary = profile.revisions.appendingPathComponent(
            Name.temporaryPrefix + revision,
            isDirectory: true
        )
        let published = profile.revisions.appendingPathComponent(revision, isDirectory: true)
        try ensureNewDirectory(temporary)
        var removeTemporary = true
        defer {
            if removeTemporary { try? fileManager.removeItem(at: temporary) }
        }
        try writeDurableFile(
            data,
            to: temporary.appendingPathComponent(Name.resolvedConfiguration)
        )
        let manifest = Manifest(
            schemaVersion: 1,
            profileID: profileID,
            revision: revision,
            configurationBytes: data.count,
            configurationSHA256: digest,
            createdAtUnixMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000),
            resources: nil
        )
        try writeDurableFile(
            try encode(manifest),
            to: temporary.appendingPathComponent(Name.manifest)
        )
        try syncDirectory(temporary)
        try inject(.revisionDurable)
        try renameItem(from: temporary, to: published)
        removeTemporary = false
        try syncDirectory(profile.revisions)
        try inject(.revisionPublished)
        return revision
    }

    private func commitActive(_ pointer: Pointer, data: Data) throws {
        try commitPointer(pointer)
        writeMirrors(pointer, data: data)
    }

     
     
    private func commitPointer(_ pointer: Pointer) throws {
         
         
         
        if let replaced = try? readPointer(Name.activePointer), replaced != pointer {
            try writePointer(Name.replacedActivePointer, pointer: replaced)
        }
        try writePointer(Name.activePointer, pointer: pointer)
        Self.forgetActivePointer(at: storeURL.appendingPathComponent(Name.activePointer))
        try inject(.currentCommitted)
    }

     
     
    private func writeMirrors(_ pointer: Pointer, data: Data) {
         
         
         
         
         
        try? writeAtomicFile(
            data,
            to: activeDirectoryURL.appendingPathComponent(Name.compatibilityConfiguration)
        )
        try? writeAtomicFile(
            try encode(pointer),
            to: activeDirectoryURL.appendingPathComponent(Name.manifest)
        )
        try? writeAtomicFile(
            data,
            to: containerURL.appendingPathComponent(Name.compatibilityConfiguration)
        )
    }

    private func loadRevision(_ pointer: Pointer) throws -> StoredConfiguration {
        guard pointer.schemaVersion == 1 else { throw ConfigResourceStoreError.invalidRevision }
        try validateProfileID(pointer.profileID)
        guard Self.isValidRevision(pointer.revision) else {
            throw ConfigResourceStoreError.invalidRevision
        }
        let revisionURL = profilePaths(pointer.profileID).revisions
            .appendingPathComponent(pointer.revision, isDirectory: true)
        guard try entryType(at: revisionURL) == S_IFDIR else {
            throw ConfigResourceStoreError.corruptRevision
        }
        let manifest = try JSONDecoder().decode(
            Manifest.self,
            from: readBoundedFile(
                revisionURL.appendingPathComponent(Name.manifest),
                maximumBytes: 64 * 1024
            )
        )
        guard manifest.schemaVersion == 1,
              manifest.profileID == pointer.profileID,
              manifest.revision == pointer.revision,
              manifest.configurationBytes > 0,
              manifest.configurationBytes <= maximumConfigurationBytes,
              manifest.configurationSHA256.count == 64 else {
            throw ConfigResourceStoreError.corruptRevision
        }


        let data = try readBoundedFile(
            revisionURL.appendingPathComponent(Name.resolvedConfiguration),
            maximumBytes: maximumConfigurationBytes
        )
        guard data.count == manifest.configurationBytes,
              Self.sha256(data) == manifest.configurationSHA256 else {
            throw ConfigResourceStoreError.corruptRevision
        }
        for resource in manifest.resources ?? [] {
             
             
             
             
             
             
             
             
            guard resource.bytes >= 0,
                  resource.bytes <= Self.maximumCandidateResourceBytes,
                  resource.sha256.count == 64,
                  isSafeResourcePath(resource.path) else {
                throw ConfigResourceStoreError.corruptRevision
            }
             
             
             
             
            if resource.path == Self.appCatalogResource { continue }
             
             
             
            let digest = try digestBoundedFile(
                revisionURL.appendingPathComponent(resource.path),
                maximumBytes: Self.maximumCandidateResourceBytes,
                expectedBytes: resource.bytes
            )
            guard digest.bytes == resource.bytes,
                  digest.sha256 == resource.sha256 else {
                throw ConfigResourceStoreError.corruptRevision
            }
        }
        try validateConfiguration(data)
        noteWhole(profileID: pointer.profileID, revision: pointer.revision)
        return StoredConfiguration(
            profileID: pointer.profileID,
            revision: pointer.revision,
            data: data,
            recoveredFromLastKnownGood: false
        )
    }

    private func loadLegacyConfigurationIfPresent() throws -> StoredConfiguration? {
        let url = containerURL.appendingPathComponent(Name.compatibilityConfiguration)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try readBoundedFile(url, maximumBytes: maximumConfigurationBytes)
        try validateConfiguration(data)
        return StoredConfiguration(
            profileID: ConfigResourceStore.defaultProfileID,
            revision: "legacy-unversioned",
            data: data,
            recoveredFromLastKnownGood: false
        )
    }

    private func writeProfileCurrent(_ profile: ProfilePaths, revision: String) throws {
        guard Self.isValidRevision(revision) else {
            throw ConfigResourceStoreError.invalidRevision
        }
        try writeAtomicFile(
            Data((revision + "\n").utf8),
            to: profile.root.appendingPathComponent(Name.profileCurrent)
        )
    }

    private func readProfileCurrent(_ profile: ProfilePaths) throws -> String {
        let data = try readBoundedFile(
            profile.root.appendingPathComponent(Name.profileCurrent),
            maximumBytes: 64
        )
        guard let revision = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            Self.isValidRevision(revision) else {
            throw ConfigResourceStoreError.invalidRevision
        }
        return revision
    }

    private func writePointer(_ name: String, pointer: Pointer) throws {
        try validateProfileID(pointer.profileID)
        guard pointer.schemaVersion == 1, Self.isValidRevision(pointer.revision) else {
            throw ConfigResourceStoreError.invalidRevision
        }
        try writeAtomicFile(try encode(pointer), to: storeURL.appendingPathComponent(name))
    }

    private func readPointer(_ name: String) throws -> Pointer {
        let pointer = try JSONDecoder().decode(
            Pointer.self,
            from: readBoundedFile(storeURL.appendingPathComponent(name), maximumBytes: 512)
        )
        try validateProfileID(pointer.profileID)
        guard pointer.schemaVersion == 1, Self.isValidRevision(pointer.revision) else {
            throw ConfigResourceStoreError.invalidRevision
        }
        return pointer
    }

     
     
     
     
     
     
     
    private func pruneProfile(_ profileID: String) throws {
        let profile = profilePaths(profileID)
        let profileCurrent = try? readProfileCurrent(profile)
        let active = try? readPointer(Name.activePointer)
        let lastKnownGood = try? readPointer(Name.lastKnownGoodPointer)
        var protected = Set([profileCurrent].compactMap { $0 })
        if active?.profileID == profileID { protected.insert(active!.revision) }
        if lastKnownGood?.profileID == profileID { protected.insert(lastKnownGood!.revision) }
        if let replaced = try? readPointer(Name.replacedActivePointer), replaced.profileID == profileID {
            protected.insert(replaced.revision)
        }
        let entries = try fileManager.contentsOfDirectory(
            at: profile.revisions,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        let revisions = entries.filter { Self.isValidRevision($0.lastPathComponent) }
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        }
        if let newest = revisions.max(by: { modified($0) < modified($1) }) {
            protected.insert(newest.lastPathComponent)
        }
        var removed = false
        for url in revisions where !protected.contains(url.lastPathComponent) {
            try fileManager.removeItem(at: url)
            removed = true
        }
        if removed { try syncDirectory(profile.revisions) }
    }

     
    private func validateSyncAndDigestCandidateResources(
        _ candidate: ConfigurationCandidate,
        sync: Bool = true
    ) throws -> [ResourceDigest] {
        let directory = candidate.stagingProvidersDirectory
        guard try entryType(at: directory) == S_IFDIR else {
            throw ConfigResourceStoreError.corruptRevision
        }
        let entries = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        guard entries.count <= Self.maximumCandidateResources else {
            throw ConfigResourceStoreError.configurationTooLarge(
                limit: Self.maximumCandidateResources
            )
        }
        var digests: [ResourceDigest] = []
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = entry.lastPathComponent
            guard isSafeResourcePath("providers/" + name),
                  try entryType(at: entry) == S_IFREG else {
                throw ConfigResourceStoreError.unsafeFilesystemEntry(name)
            }
            let digest = try digestBoundedFile(
                entry,
                maximumBytes: Self.maximumCandidateResourceBytes
            )
             
             
             
             
             
             
            if sync {
                let descriptor = open(entry.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
                guard descriptor >= 0 else { throw posixError("open candidate resource") }
                defer { close(descriptor) }
                guard fsync(descriptor) == 0 else { throw posixError("fsync candidate resource") }
            }
            digests.append(ResourceDigest(
                path: "providers/" + name,
                bytes: digest.bytes,
                sha256: digest.sha256
            ))
        }
        if sync { try syncDirectory(directory) }
        return digests
    }

    private func isSafeResourcePath(_ path: String) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return components.count == 2 &&
            components[0] == "providers" &&
            !components[1].isEmpty &&
            components[1] != "." &&
            components[1] != ".." &&
            !components[1].contains("\\")
    }

    private func validateProfileID(_ value: String) throws {
        guard value.count == 36,
              UUID(uuidString: value) != nil,
              value == value.lowercased() else {
            throw ConfigResourceStoreError.invalidProfileID
        }
    }

    private func validateConfiguration(_ data: Data) throws {
        guard !data.isEmpty else { throw ConfigResourceStoreError.emptyConfiguration }
        guard data.count <= maximumConfigurationBytes else {
            throw ConfigResourceStoreError.configurationTooLarge(limit: maximumConfigurationBytes)
        }
        guard String(data: data, encoding: .utf8) != nil else {
            throw ConfigResourceStoreError.configurationIsNotUTF8
        }
         
         
         
        let containsNUL = data.withUnsafeBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            return memchr(base, 0, buffer.count) != nil
        }
        guard !containsNUL else { throw ConfigResourceStoreError.configurationContainsNUL }
    }

    private func verifyContainerDirectory() throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: containerURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              try entryType(at: containerURL) == S_IFDIR else {
            throw ConfigResourceStoreError.unsafeFilesystemEntry(containerURL.lastPathComponent)
        }
         
    }

    private func ensureDirectory(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue, try entryType(at: url) == S_IFDIR else {
                throw ConfigResourceStoreError.unsafeFilesystemEntry(url.lastPathComponent)
            }
        } else {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        guard chmod(url.path, mode_t(0o700)) == 0 else { throw posixError("chmod directory") }
        try applyFileProtection(url)
    }

    private func ensureNewDirectory(_ url: URL) throws {
        guard mkdir(url.path, mode_t(0o700)) == 0 else { throw posixError("mkdir revision") }
        try applyFileProtection(url)
    }

    private func entryType(at url: URL) throws -> mode_t {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw posixError("lstat") }
        return info.st_mode & mode_t(S_IFMT)
    }

    static var suspensionShield: SuspensionShield = .noop

     
     
     
     
     
    static var lockObserver: ((_ operation: String, _ waitMilliseconds: Double, _ heldMilliseconds: Double) -> Void)?

    private func withExclusiveLock<T>(operation: String = #function, _ body: () throws -> T) throws -> T {
         
        guard let value = try exclusiveLock(operation: operation, waiting: true, body) else {
            throw ConfigResourceStoreError.lockTimedOut
        }
        return value
    }

     
    private func withExclusiveLockIfFree<T>(operation: String = #function, _ body: () throws -> T) throws -> T? {
        try exclusiveLock(operation: operation, waiting: false, body)
    }

    private func exclusiveLock<T>(operation: String, waiting: Bool, _ body: () throws -> T) throws -> T? {
        let entered = DispatchTime.now()
        let shieldToken = Self.suspensionShield.begin()
        defer { Self.suspensionShield.end(shieldToken) }
        try verifyContainerDirectory()
        try ensureDirectory(workingURL)
        let descriptor = open(lockURL.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { throw posixError("open lock") }
        defer { close(descriptor) }
        guard fchmod(descriptor, mode_t(0o600)) == 0 else { throw posixError("chmod lock") }
        try applyFileProtection(lockURL)
        let deadline = Date().addingTimeInterval(lockTimeout)
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EAGAIN else { throw posixError("flock") }
            guard waiting else { return nil }
            guard Date() < deadline else { throw ConfigResourceStoreError.lockTimedOut }
            usleep(10_000)
        }
        defer { flock(descriptor, LOCK_UN) }
        let acquired = DispatchTime.now()
         
         
         
         
        defer {
            if let observer = Self.lockObserver {
                let finished = DispatchTime.now()
                observer(
                    operation,
                    Double(acquired.uptimeNanoseconds - entered.uptimeNanoseconds) / 1_000_000,
                    Double(finished.uptimeNanoseconds - acquired.uptimeNanoseconds) / 1_000_000
                )
            }
        }
        return try body()
    }

    private func writeAtomicFile(_ data: Data, to destination: URL) throws {
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(
            Name.temporaryPrefix + UUID().uuidString.lowercased()
        )
        var removeTemporary = true
        defer { if removeTemporary { try? fileManager.removeItem(at: temporary) } }
        try writeDurableFile(data, to: temporary)
        try renameItem(from: temporary, to: destination)
        removeTemporary = false
        try syncDirectory(destination.deletingLastPathComponent())
    }

    private func writeDurableFile(_ data: Data, to url: URL) throws {
        let descriptor = open(
            url.path,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            mode_t(0o600)
        )
        guard descriptor >= 0 else { throw posixError("open temporary file") }
        var descriptorIsOpen = true
        defer { if descriptorIsOpen { close(descriptor) } }
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let written = Darwin.write(
                    descriptor,
                    base.advanced(by: offset),
                    rawBuffer.count - offset
                )
                guard written >= 0 else {
                    if errno == EINTR { continue }
                    throw posixError("write")
                }
                offset += written
            }
        }
        guard fchmod(descriptor, mode_t(0o600)) == 0 else { throw posixError("chmod file") }
        guard fsync(descriptor) == 0 else { throw posixError("fsync file") }
        guard close(descriptor) == 0 else { throw posixError("close file") }
        descriptorIsOpen = false
        try applyFileProtection(url)
    }

    private func readBoundedFile(_ url: URL, maximumBytes: Int) throws -> Data {
        guard try entryType(at: url) == S_IFREG else {
            throw ConfigResourceStoreError.unsafeFilesystemEntry(url.lastPathComponent)
        }
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw posixError("open file") }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw posixError("fstat") }
        guard info.st_mode & mode_t(S_IFMT) == S_IFREG else {
            throw ConfigResourceStoreError.unsafeFilesystemEntry(url.lastPathComponent)
        }
        guard info.st_size >= 0, info.st_size <= off_t(maximumBytes) else {
            throw ConfigResourceStoreError.configurationTooLarge(limit: maximumBytes)
        }
        var result = Data()
        result.reserveCapacity(Int(info.st_size))
        var buffer = [UInt8](repeating: 0, count: max(1, min(64 * 1024, maximumBytes)))
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw posixError("read")
            }
            if count == 0 { break }
            guard result.count + count <= maximumBytes else {
                throw ConfigResourceStoreError.configurationTooLarge(limit: maximumBytes)
            }
            result.append(contentsOf: buffer.prefix(count))
        }
        return result
    }

     
     
     
     
     
    private func digestBoundedFile(
        _ url: URL,
        maximumBytes: Int,
        expectedBytes: Int? = nil
    ) throws -> (bytes: Int, sha256: String) {
        guard try entryType(at: url) == S_IFREG else {
            throw ConfigResourceStoreError.unsafeFilesystemEntry(url.lastPathComponent)
        }
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw posixError("open file") }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw posixError("fstat") }
        guard info.st_mode & mode_t(S_IFMT) == S_IFREG else {
            throw ConfigResourceStoreError.unsafeFilesystemEntry(url.lastPathComponent)
        }
        guard info.st_size >= 0, info.st_size <= off_t(maximumBytes) else {
            throw ConfigResourceStoreError.configurationTooLarge(limit: maximumBytes)
        }
        if let expectedBytes, off_t(expectedBytes) != info.st_size {
            return (Int(info.st_size), "")
        }
        var hasher = SHA256()
        var total = 0
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw posixError("read")
            }
            if count == 0 { break }
            guard total + count <= maximumBytes else {
                throw ConfigResourceStoreError.configurationTooLarge(limit: maximumBytes)
            }
            buffer.withUnsafeBytes { hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: $0.prefix(count))) }
            total += count
        }
        return (total, hasher.finalize().map { String(format: "%02x", $0) }.joined())
    }

    private func removeAbandonedTemporaryEntries(
        in directory: URL,
        olderThan age: TimeInterval = 0
    ) throws {
        let entries = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )
        for entry in entries where entry.lastPathComponent.hasPrefix(Name.temporaryPrefix) {
            if age > 0 {
                let modified = try entry.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate ?? .distantPast
                guard Date().timeIntervalSince(modified) >= age else { continue }
            }
            try fileManager.removeItem(at: entry)
        }
        try syncDirectory(directory)
    }

    private func renameItem(from source: URL, to destination: URL) throws {
        guard rename(source.path, destination.path) == 0 else { throw posixError("rename") }
    }

    private func syncDirectory(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw posixError("open directory") }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw posixError("fsync directory") }
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private func applyFileProtection(_ url: URL) throws {
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }

    private func inject(_ point: ConfigResourceStoreFaultPoint) throws {
        if faultInjector?(point) == true {
            throw ConfigResourceStoreError.simulatedCrash(point)
        }
    }

    private func posixError(_ operation: String) -> ConfigResourceStoreError {
        .posix(operation: operation, code: errno)
    }

    private static func isValidRevision(_ value: String) -> Bool {
        value.count == 36 && UUID(uuidString: value) != nil && value == value.lowercased()
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

 
 
 
 
 
 
 
 
 
 
 
enum TunnelIntentStamp {
    static let key = "ClashAppliedTunnelIntentJSON"

    static func write(_ intentJSON: String, to defaults: UserDefaults) {
        defaults.set(intentJSON, forKey: key)
    }

    static func readJSON(from defaults: UserDefaults) -> String? {
        defaults.string(forKey: key)
    }
}

 

extension ConfigResourceStore {
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func orphanedProfileDirectories(registered: Set<String>) throws -> [URL] {
        try orphanedProfileDirectoriesScan(registered: registered).orphans
    }

     
     
     
     
    @discardableResult
    func removeOrphanedProfileDirectories(registered: Set<String>) throws -> [String] {
        let scan = try orphanedProfileDirectoriesScan(registered: registered)
        for leftover in scan.setAside { deleteSetAside(leftover) }
        var removed: [String] = []
        for url in scan.orphans {
            let aside = try withExclusiveLock { () -> URL? in
                guard !namedProfileIDs(registered).contains(url.lastPathComponent) else { return nil }
                return setAsideLocked(url)
            }
            guard let aside else { continue }
            deleteSetAside(aside)
            removed.append(url.lastPathComponent)
        }
        return removed
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func supersededRevisionDirectories() throws -> [URL] {
        try supersededRevisionsScan().superseded.map(\.directory)
    }

     
     
     
     
     
    @discardableResult
    func removeSupersededRevisionDirectories() throws -> [URL] {
        let scan = try supersededRevisionsScan()
        for leftover in scan.setAside { deleteSetAside(leftover) }
        var removed: [URL] = []
        for found in scan.superseded {
            let aside = try withExclusiveLock { () -> URL? in
                guard isStillSupersededLocked(found) else { return nil }
                return setAsideLocked(found.directory)
            }
            guard let aside else { continue }
            deleteSetAside(aside)
            removed.append(found.directory)
        }
        return removed
    }

     
     
    private struct SupersededRevision {
        let profileID: String
        let revision: String
        let directory: URL
        let newest: String
    }

     
     
     
     
    private func supersededRevisionsScan() throws -> (superseded: [SupersededRevision], setAside: [URL]) {
        guard fileManager.fileExists(atPath: profilesURL.path) else { return ([], []) }
        let named = [Name.activePointer, Name.lastKnownGoodPointer, Name.replacedActivePointer]
            .compactMap { try? readPointer($0) }
        let profileDirectories = try fileManager.contentsOfDirectory(
            at: profilesURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        var superseded: [SupersededRevision] = []
        var setAside: [URL] = []
        for directory in profileDirectories {
            let profileID = directory.lastPathComponent
            let profile = profilePaths(profileID)
            guard fileManager.fileExists(atPath: profile.revisions.path) else { continue }
            var protected = Set(named.filter { $0.profileID == profileID }.map(\.revision))
            if let current = try? readProfileCurrent(profile) { protected.insert(current) }


            guard let entries = try? fileManager.contentsOfDirectory(
                at: profile.revisions,
                includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }
            setAside += entries.filter { $0.lastPathComponent.hasPrefix(Name.setAsidePrefix) }
            let revisions = entries.filter { Self.isValidRevision($0.lastPathComponent) }
            func modified(_ url: URL) -> Date {
                (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            }
             
             
            guard let newest = revisions.max(by: { modified($0) < modified($1) }) else { continue }
            protected.insert(newest.lastPathComponent)
            superseded += revisions.filter { !protected.contains($0.lastPathComponent) }.map {
                SupersededRevision(profileID: profileID, revision: $0.lastPathComponent,
                                   directory: $0, newest: newest.lastPathComponent)
            }
        }
        return (superseded.sorted { $0.directory.path < $1.directory.path }, setAside)
    }

     
     
     
     
    private func isStillSupersededLocked(_ found: SupersededRevision) -> Bool {
        for name in [Name.activePointer, Name.lastKnownGoodPointer, Name.replacedActivePointer] {
            if let pointer = try? readPointer(name),
               pointer.profileID == found.profileID, pointer.revision == found.revision { return false }
        }
        let profile = profilePaths(found.profileID)
        if (try? readProfileCurrent(profile)) == found.revision { return false }
        let newest = profile.revisions.appendingPathComponent(found.newest, isDirectory: true)
        return (try? entryType(at: newest)) == S_IFDIR && (try? entryType(at: found.directory)) == S_IFDIR
    }

     
     
    private func orphanedProfileDirectoriesScan(registered: Set<String>) throws -> (orphans: [URL], setAside: [URL]) {
        let protected = namedProfileIDs(registered)
        guard fileManager.fileExists(atPath: profilesURL.path) else { return ([], []) }


        let entries = try fileManager.contentsOfDirectory(
            at: profilesURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        let orphans = entries
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .filter { !protected.contains($0.lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return (orphans, entries.filter { $0.lastPathComponent.hasPrefix(Name.setAsidePrefix) })
    }

     
     
    private func namedProfileIDs(_ registered: Set<String>) -> Set<String> {
        var protected = registered
        protected.insert(Self.defaultProfileID)
        if let active = try? readPointer(Name.activePointer) { protected.insert(active.profileID) }
        if let good = try? readPointer(Name.lastKnownGoodPointer) { protected.insert(good.profileID) }
        return protected
    }

     
     
     
    private func setAsideLocked(_ directory: URL) -> URL? {
        let aside = directory.deletingLastPathComponent()
            .appendingPathComponent(Name.setAsidePrefix + UUID().uuidString.lowercased(), isDirectory: true)
        guard rename(directory.path, aside.path) == 0 else { return nil }
        return aside
    }

     
     
     
    private func deleteSetAside(_ aside: URL) {


        try? fileManager.removeItem(at: aside)
        try? syncDirectory(aside.deletingLastPathComponent())
    }
}

 

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ProviderPayloadStore {
    let directory: URL

    init(workingDirectory: URL) {
        directory = workingDirectory.appendingPathComponent("payloads", isDirectory: true)
    }

    static let writeOptions: Data.WritingOptions =
        [.atomic, .completeFileProtectionUntilFirstUserAuthentication]

     
     
    static func blobName(for data: Data, extension ext: String) -> String {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return ext.isEmpty ? digest : digest + "." + ext
    }

     
     
     
     
    func place(_ data: Data, at target: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let blob = directory.appendingPathComponent(Self.blobName(for: data, extension: target.pathExtension))
        if !fm.fileExists(atPath: blob.path) {
            try data.write(to: blob, options: Self.writeOptions)
        }
        do {
            try Self.link(blob, to: target)
        } catch {
            try data.write(to: target, options: Self.writeOptions)
        }
    }

     
     
     
    static func link(_ source: URL, to target: URL) throws {
        let fm = FileManager.default
        let temporary = target.deletingLastPathComponent()
            .appendingPathComponent(".link-" + target.lastPathComponent)
        try? fm.removeItem(at: temporary)
        try fm.linkItem(at: source, to: temporary)
        guard rename(temporary.path, target.path) == 0 else {
            let code = errno
            try? fm.removeItem(at: temporary)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
    }

     
    func unreferencedBlobs() -> [URL] {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        )) ?? []
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .filter { Self.linkCount(of: $0) <= 1 }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    @discardableResult
    func removeUnreferencedBlobs() -> [URL] {
        unreferencedBlobs().filter { (try? FileManager.default.removeItem(at: $0)) != nil }
    }

    static func linkCount(of url: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.referenceCount] as? Int) ?? 1
    }

     
    static func inode(of url: URL) -> UInt64? {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.systemFileNumber] as? NSNumber)?.uint64Value
    }

     
    func inodes() -> [UInt64] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        )) ?? []
        return entries.compactMap { Self.inode(of: $0) }
    }
}

extension ConfigResourceStore {
     
     
     
     
     
     
     
     
     
     
     
     
     
    @discardableResult
    func adoptProviderPayloads() throws -> Int {
        guard fileManager.fileExists(atPath: profilesURL.path) else { return 0 }
        let payloads = payloadStore
        var held = Set(payloads.inodes())
        var adopted = 0
        let profiles = try fileManager.contentsOfDirectory(
            at: profilesURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        for profile in profiles {
            let revisions = profile.appendingPathComponent(Name.revisions, isDirectory: true)
            let entries = (try? fileManager.contentsOfDirectory(
                at: revisions, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            )) ?? []
            for revision in entries where Self.isValidRevision(revision.lastPathComponent) {
                let providers = revision.appendingPathComponent("providers", isDirectory: true)


                let files = (try? fileManager.contentsOfDirectory(
                    at: providers, includingPropertiesForKeys: [.isRegularFileKey], options: []
                )) ?? []
                 
                 
                let interrupted = files.filter { $0.lastPathComponent.hasPrefix(".link-") }
                if !interrupted.isEmpty {
                    try withExclusiveLock {
                        for leftover in interrupted { try? fileManager.removeItem(at: leftover) }
                    }
                }
                for file in files where !file.lastPathComponent.hasPrefix(".") {
                    guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                          let inode = ProviderPayloadStore.inode(of: file), !held.contains(inode),
                          let data = try? readBoundedFile(file, maximumBytes: Self.maximumCandidateResourceBytes)
                    else { continue }
                    let blob = payloads.directory.appendingPathComponent(
                        ProviderPayloadStore.blobName(for: data, extension: file.pathExtension)
                    )
                    let linked = try withExclusiveLock { () throws -> Bool in
                        guard ProviderPayloadStore.inode(of: file) == inode else { return false }
                        if fileManager.fileExists(atPath: blob.path) {
                            return (try? ProviderPayloadStore.link(blob, to: file)) != nil
                        }
                        try fileManager.createDirectory(at: payloads.directory, withIntermediateDirectories: true)
                        guard (try? fileManager.linkItem(at: file, to: blob)) != nil else { return false }
                        held.insert(inode)
                        return true
                    }
                    if linked { adopted += 1 }
                }
            }
        }
        return adopted
    }

     
     
     
    @discardableResult
    func removeUnreferencedPayloadBlobs() throws -> [URL] {


        var removed: [URL] = []
        for blob in payloadStore.unreferencedBlobs() {
            let went = try withExclusiveLock { () -> Bool in
                guard ProviderPayloadStore.linkCount(of: blob) <= 1 else { return false }
                return (try? fileManager.removeItem(at: blob)) != nil
            }
            if went { removed.append(blob) }
        }
        return removed
    }
}
