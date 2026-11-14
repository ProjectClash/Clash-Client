import ClashClientKit
import Foundation

 
 
 
 
struct ModuleLocations: Equatable, Sendable {
    let container: URL

    var stateFile: URL { container.appendingPathComponent("working/adblock/state.json") }
    var sourcesDirectory: URL { container.appendingPathComponent("working/adblock/sources", isDirectory: true) }
    var publishedRoot: URL { container.appendingPathComponent("modules", isDirectory: true) }
    var globalManifest: URL { publishedRoot.appendingPathComponent("manifest.json") }

    func source(_ id: String) -> URL { sourcesDirectory.appendingPathComponent(id + ".txt") }
    func moduleDirectory(_ id: String) -> URL { publishedRoot.appendingPathComponent(id, isDirectory: true) }
    func moduleManifest(_ id: String) -> URL { moduleDirectory(id).appendingPathComponent("manifest.json") }
    func scriptsDirectory(_ id: String) -> URL { moduleDirectory(id).appendingPathComponent("scripts", isDirectory: true) }
    func script(_ id: String, sha256: String) -> URL { scriptsDirectory(id).appendingPathComponent(sha256 + ".js") }
     
     
    func filesDirectory(_ id: String) -> URL { moduleDirectory(id).appendingPathComponent("files", isDirectory: true) }
    func file(_ id: String, sha256: String) -> URL { filesDirectory(id).appendingPathComponent(sha256) }
     
    func setsDirectory(_ id: String) -> URL { moduleDirectory(id).appendingPathComponent("sets", isDirectory: true) }
    func ruleSet(_ id: String, sha256: String) -> URL { setsDirectory(id).appendingPathComponent(sha256) }
     
     
     
    var ruleSetCopiesDirectory: URL { container.appendingPathComponent("working/adblock/sets", isDirectory: true) }
    func ruleSetCopy(sha256: String) -> URL { ruleSetCopiesDirectory.appendingPathComponent(sha256) }

     
    static var production: ModuleLocations? {
        ClashAppIdentifiers.appGroupContainer.map(ModuleLocations.init(container:))
    }
}

 
struct ModuleRecord: Equatable, Identifiable, Sendable {
     
     
     
     
     
    static let currentSchemaVersion = 1

    enum Origin: Equatable, Sendable {
        case url(String)
         
         
         
         
        case local
         
         
        case unknown(String)
    }

    let id: String
    var origin: Origin
    var enabled: Bool
    var name: String
     
     
    var label: String?
     
    var updateInterval: Int
    var lastCheckedAt: Date?
    var lastUpdatedAt: Date?
     
    var lastFailure: AuthoredText? {
        didSet { failureFromALaterBuild = false }
    }
     
    var scriptFetchedAt: [String: Date]
     
     
    var sourceSHA256: String?
     
     
    var scriptAttemptedAt: [String: Date] = [:]
    var scriptFailureCount: [String: Int] = [:]
     
     
     
    var linkFailureCount = 0
     
     
     
    var fileStates: [String: ModuleFileState] = [:]
     
     
     
     
    var appScriptAddresses: Set<String> = []
     
     
     
     
     
     
     
     
    var argumentValues: [String: String] = [:]
     
     
     
     
     
    var storedValues: [String: String] = [:]
     
     
     
     
    var heldScriptBodies: [String: ModuleHeldScriptBody] = [:]
     
     
     
     
     
     
     
    var countedWithoutSizeCaps = true
    var schemaVersion = ModuleRecord.currentSchemaVersion
     
     
     
    var failureFromALaterBuild = false
}

 
 
 
 
 
struct ModuleHeldScriptBody: Codable, Equatable, Sendable {
    var sha256: String
    var fetchedAt: Date?
}

struct ModuleFileState: Codable, Equatable, Sendable {
    var sha256: String?
    var fetchedAt: Date?
    var attemptedAt: Date?
     
     
    var failures = 0
    var etag: String?
    var lastModified: String?
}

extension ModuleRecord.Origin: Codable {
    private enum CodingKeys: String, CodingKey { case kind, url }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "url": self = .url(try container.decode(String.self, forKey: .url))
         
         
        case "local", "pasted": self = .local
        case let other: self = .unknown(other)
        }
    }

     
    static let knownKinds: Set<String> = ["url", "local", "pasted"]

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .url(let link):
            try container.encode("url", forKey: .kind)
            try container.encode(link, forKey: .url)
        case .local:
            try container.encode("local", forKey: .kind)
        case .unknown(let kind):
             
            try container.encode(kind, forKey: .kind)
        }
    }
}

extension ModuleRecord: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, origin, enabled, name, label, updateInterval, lastCheckedAt, lastUpdatedAt, lastFailure
        case scriptFetchedAt, sourceSHA256, scriptAttemptedAt, scriptFailureCount, linkFailureCount, fileStates, appScriptAddresses
        case argumentValues, storedValues, heldScriptBodies
        case countedWithoutSizeCaps
        case schemaVersion
    }

     
     
     
     
     
     
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard version <= Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: c, debugDescription: "schema \(version)")
        }
        id = try c.decode(String.self, forKey: .id)
        origin = try c.decode(Origin.self, forKey: .origin)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        label = try c.decodeIfPresent(String.self, forKey: .label)
        updateInterval = try c.decodeIfPresent(Int.self, forKey: .updateInterval) ?? ModuleLineSyntax.defaultScriptUpdateInterval
        lastCheckedAt = try c.decodeIfPresent(Date.self, forKey: .lastCheckedAt)
        lastUpdatedAt = try c.decodeIfPresent(Date.self, forKey: .lastUpdatedAt)
         
        if c.contains(.lastFailure), (try? c.decodeNil(forKey: .lastFailure)) != true {
            lastFailure = try? c.decode(AuthoredText.self, forKey: .lastFailure)
            failureFromALaterBuild = lastFailure == nil
        } else {
            lastFailure = nil
        }
        scriptFetchedAt = try c.decodeIfPresent([String: Date].self, forKey: .scriptFetchedAt) ?? [:]
        sourceSHA256 = try c.decodeIfPresent(String.self, forKey: .sourceSHA256)
        scriptAttemptedAt = try c.decodeIfPresent([String: Date].self, forKey: .scriptAttemptedAt) ?? [:]
        scriptFailureCount = try c.decodeIfPresent([String: Int].self, forKey: .scriptFailureCount) ?? [:]
        linkFailureCount = try c.decodeIfPresent(Int.self, forKey: .linkFailureCount) ?? 0
        fileStates = (try? c.decodeIfPresent([String: ModuleFileState].self, forKey: .fileStates)) ?? [:]
        appScriptAddresses = Set(try c.decodeIfPresent([String].self, forKey: .appScriptAddresses) ?? [])
        argumentValues = try c.decodeIfPresent([String: String].self, forKey: .argumentValues) ?? [:]
        storedValues = try c.decodeIfPresent([String: String].self, forKey: .storedValues) ?? [:]
        heldScriptBodies = (try? c.decodeIfPresent([String: ModuleHeldScriptBody].self, forKey: .heldScriptBodies)) ?? [:]
        if try c.decodeIfPresent(Bool.self, forKey: .countedWithoutSizeCaps) != true {
            scriptAttemptedAt = [:]
            scriptFailureCount = [:]
            linkFailureCount = 0
            fileStates = fileStates.mapValues { state in
                var state = state
                state.failures = 0
                state.attemptedAt = nil
                return state
            }
        }
        countedWithoutSizeCaps = true
        schemaVersion = version
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(origin, forKey: .origin)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(name, forKey: .name)
         
         
        try c.encodeIfPresent(label, forKey: .label)
        try c.encode(updateInterval, forKey: .updateInterval)
        try c.encodeIfPresent(lastCheckedAt, forKey: .lastCheckedAt)
        try c.encodeIfPresent(lastUpdatedAt, forKey: .lastUpdatedAt)
        try c.encodeIfPresent(lastFailure, forKey: .lastFailure)
        try c.encode(scriptFetchedAt, forKey: .scriptFetchedAt)
        try c.encodeIfPresent(sourceSHA256, forKey: .sourceSHA256)
        try c.encode(scriptAttemptedAt, forKey: .scriptAttemptedAt)
        try c.encode(scriptFailureCount, forKey: .scriptFailureCount)
        try c.encode(linkFailureCount, forKey: .linkFailureCount)
        if !fileStates.isEmpty { try c.encode(fileStates, forKey: .fileStates) }
         
        if !appScriptAddresses.isEmpty { try c.encode(appScriptAddresses.sorted(), forKey: .appScriptAddresses) }
         
         
         
        if !argumentValues.isEmpty { try c.encode(argumentValues, forKey: .argumentValues) }
        if !storedValues.isEmpty { try c.encode(storedValues, forKey: .storedValues) }
        if !heldScriptBodies.isEmpty { try c.encode(heldScriptBodies, forKey: .heldScriptBodies) }
        try c.encode(countedWithoutSizeCaps, forKey: .countedWithoutSizeCaps)
        try c.encode(schemaVersion, forKey: .schemaVersion)
    }

     
    static let knownKeys: Set<String> = Set(["id", "origin", "enabled", "name", "label", "updateInterval", "lastCheckedAt", "lastUpdatedAt",
                                              "lastFailure", "scriptFetchedAt", "sourceSHA256", "scriptAttemptedAt",
                                              "scriptFailureCount", "linkFailureCount", "fileStates", "appScriptAddresses",
                                              "argumentValues", "storedValues", "heldScriptBodies", "countedWithoutSizeCaps",
                                              "schemaVersion"])
}

extension ModuleRecord {
     
    var displayName: String { label ?? name }

     
     
    var isUnprotectedLink: Bool {
        guard case .url(let link) = origin else { return false }
        return link.hasPrefix("http://")
    }

     
     
     
    mutating func adopt(refreshOwnedFieldsOf other: ModuleRecord) {
        name = other.name
        lastCheckedAt = other.lastCheckedAt
        lastUpdatedAt = other.lastUpdatedAt
        lastFailure = other.lastFailure
        failureFromALaterBuild = other.failureFromALaterBuild
        scriptFetchedAt = other.scriptFetchedAt
        sourceSHA256 = other.sourceSHA256
        scriptAttemptedAt = other.scriptAttemptedAt
        scriptFailureCount = other.scriptFailureCount
        linkFailureCount = other.linkFailureCount
        fileStates = other.fileStates
        appScriptAddresses = other.appScriptAddresses
        heldScriptBodies = other.heldScriptBodies
    }

     
    mutating func absorb(_ prepared: ModuleStore.Prepared) {
        scriptFetchedAt = prepared.scriptFetchedAt
        for (address, at) in prepared.attemptedAt {
            scriptAttemptedAt[address] = at
            if prepared.failedAddresses.contains(address) {
                scriptFailureCount[address, default: 0] += 1
            } else {
                scriptFailureCount[address] = nil
            }
        }
        let current = Set(prepared.ir.scripts.map(\.scriptURL)).union(prepared.ir.appScripts.map(\.scriptURL))
            .union(prepared.failedAddresses).union(prepared.waiting)
        scriptAttemptedAt = scriptAttemptedAt.filter { current.contains($0.key) }
        scriptFailureCount = scriptFailureCount.filter { current.contains($0.key) }
        fileStates = prepared.fileStates
        appScriptAddresses = prepared.appScriptAddresses
        heldScriptBodies = prepared.heldScriptBodies
    }
}

struct ModuleState: Equatable, Sendable {
     
     
     
    static let currentSchemaVersion = 1

     
     
     
     
    var enabled = false
    var modules: [ModuleRecord] = []
    var ports: ModulePorts?
     
     
     
     
    var reinjectCredentials: ModuleReinjectCredentials?
     
     
    var engineProxyCredentials: ModuleEngineProxyCredentials?
    var schemaVersion = ModuleState.currentSchemaVersion

     
    mutating func drawCredentials() {
        let listener = ModuleReinjectCredentials.random()
        var engine = ModuleEngineProxyCredentials.random()
        while engine == listener { engine = .random() }
        reinjectCredentials = listener
        engineProxyCredentials = engine
    }

     
     
    mutating func drawEngineCredentialsIfUnusable() {
        guard engineProxyCredentials?.isWellFormed != true || engineProxyCredentials == reinjectCredentials else { return }
        var engine = ModuleEngineProxyCredentials.random()
        while engine == reinjectCredentials { engine = .random() }
        engineProxyCredentials = engine
    }
}

extension ModuleState: Codable {
    private enum CodingKeys: String, CodingKey { case enabled, modules, ports, reinjectCredentials, engineProxyCredentials, schemaVersion }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard version <= Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: c, debugDescription: "schema \(version)")
        }
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        modules = try c.decodeIfPresent([ModuleRecord].self, forKey: .modules) ?? []
        ports = try c.decodeIfPresent(ModulePorts.self, forKey: .ports)
        reinjectCredentials = try c.decodeIfPresent(ModuleReinjectCredentials.self, forKey: .reinjectCredentials)
        engineProxyCredentials = try c.decodeIfPresent(ModuleEngineProxyCredentials.self, forKey: .engineProxyCredentials)
        schemaVersion = version
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(modules, forKey: .modules)
        try c.encodeIfPresent(ports, forKey: .ports)
        try c.encodeIfPresent(reinjectCredentials, forKey: .reinjectCredentials)
        try c.encodeIfPresent(engineProxyCredentials, forKey: .engineProxyCredentials)
        try c.encode(schemaVersion, forKey: .schemaVersion)
    }

     
     
     
     
     
     
     
     
    func keepingWhatThisBuildDoesNotKnow(_ encoded: Data, from earlier: Data) -> Data? {
        typealias Pairs = [(key: String, value: OrderedJSON)]
        guard case .object(var top)? = try? OrderedJSON.parse(String(decoding: encoded, as: UTF8.self)),
              case .object(let old)? = try? OrderedJSON.parse(String(decoding: earlier, as: UTF8.self)) else { return nil }
        func value(_ key: String, in pairs: Pairs) -> OrderedJSON? { pairs.first { $0.key == key }?.value }
        func merged(_ new: Pairs, _ old: Pairs, known: Set<String>, inside: [String: Set<String>] = [:]) -> Pairs {
            var out = new
            for pair in old where !known.contains(pair.key) && !out.contains(where: { $0.key == pair.key }) { out.append(pair) }
            for (key, keys) in inside {
                guard let at = out.firstIndex(where: { $0.key == key }), case .object(let now) = out[at].value,
                      case .object(let before)? = value(key, in: old) else { continue }
                out[at].value = .object(merged(now, before, known: keys))
            }
            return out
        }
        let credentials: Set<String> = ["username", "password"]
        top = merged(top, old, known: ["enabled", "modules", "ports", "reinjectCredentials", "engineProxyCredentials", "schemaVersion"],
                     inside: ["ports": ["engine", "reinject"], "reinjectCredentials": credentials, "engineProxyCredentials": credentials])
        guard let at = top.firstIndex(where: { $0.key == "modules" }), case .array(let records) = top[at].value,
              case .array(let earlierRecords)? = value("modules", in: old) else { return Data(OrderedJSON.object(top).serialized().utf8) }
        var byID: [String: Pairs] = [:]
        for case .object(let pairs) in earlierRecords {
            if case .string(let id)? = value("id", in: pairs), byID[id] == nil { byID[id] = pairs }
        }
        top[at].value = .array(records.map { record in
            guard case .object(var pairs) = record, case .string(let id)? = value("id", in: pairs), let before = byID[id] else { return record }
            pairs = merged(pairs, before, known: ModuleRecord.knownKeys)
            if let origin = pairs.firstIndex(where: { $0.key == "origin" }), case .object(let now) = pairs[origin].value,
               case .object(let was)? = value("origin", in: before) {
                if case .string(let kind)? = value("kind", in: was), !ModuleRecord.Origin.knownKinds.contains(kind) {
                    pairs[origin].value = .object(was)
                } else {
                    pairs[origin].value = .object(merged(now, was, known: ["kind", "url"]))
                }
            }
            if !pairs.contains(where: { $0.key == "lastFailure" }), modules.first(where: { $0.id == id })?.failureFromALaterBuild == true,
               let failure = value("lastFailure", in: before) {
                pairs.append((key: "lastFailure", value: failure))
            }
            return .object(pairs)
        })
        return Data(OrderedJSON.object(top).serialized().utf8)
    }

     
     
     
    static func isFromANewerBuild(_ data: Data) -> Bool {
        struct Version: Decodable { let schemaVersion: Int? }
        struct Records: Decodable { let modules: [Version]? }
        let decoder = ModuleJSON.decoder()
        if let top = try? decoder.decode(Version.self, from: data), (top.schemaVersion ?? 1) > currentSchemaVersion { return true }
        let records = (try? decoder.decode(Records.self, from: data))?.modules ?? []
        return records.contains { ($0.schemaVersion ?? 1) > ModuleRecord.currentSchemaVersion }
    }
}

extension ModuleStoreError {
     
    var authoredText: AuthoredText {
        switch self {
        case .stateUnreadable(.newerVersion):
            return .app("This module list was saved by a newer version of Clash, so nothing was changed.")
        case .stateUnreadable(.corrupt): return .app("The module list could not be read, so nothing was changed.")
         
         
        case .stateUnreadable(.readFailed): return .app("The module list cannot be read right now. Try again.")
        case .scriptMissing: return .app("A script this module needs is missing, so nothing was changed.")
        case .fileMissing: return .app("A file this module needs is missing, so nothing was changed.")
        case .notAScript: return .app("The server answered with a page, not a script.")
        case .emptyScript: return .app("The server sent an empty file instead of a script.")
         
         
        case .serverNotVerified: return .app("Clash could not verify the server, so nothing was downloaded.")
        case .savedCopyMissing: return .app("This module's saved copy is missing; paste it again.")
         
        case .linkedCopyMissing: return .app("This module's saved copy is missing; it's being downloaded again.")
        case .linkedModuleNotEditable: return .app("This module updates from its link, so it can't be edited.")
        case .moduleGone: return .app("This module is no longer in the list.")
        case .moduleFromANewerVersion: return .app("This module was saved by a newer version of Clash, so it can't be edited here.")
        case .editSuperseded: return .app("A newer edit of this module was saved instead.")
        case .argumentValueHasALineBreak: return .app("A setting's value can't contain a line break.")
        }
    }
}

 
enum ModuleStoreError: Error, Equatable, Sendable {
     
     
     
     
     
     
    enum Unreadable: Equatable, Sendable { case corrupt, newerVersion, readFailed }

     
     
     
     
     
     
    case stateUnreadable(Unreadable)
     
    case scriptMissing(String)
     
     
    case fileMissing(String)
     
    case notAScript
     
    case emptyScript
     
     
    case serverNotVerified
     
     
    case savedCopyMissing
     
     
    case linkedCopyMissing
     
     
    case linkedModuleNotEditable
     
    case moduleGone
     
    case moduleFromANewerVersion
     
     
    case editSuperseded
     
     
    case argumentValueHasALineBreak
}

 
 
 
 
 
 
actor ModuleStore {
     
     
     
    static let didChange = Notification.Name("ClashModulesDidChange")
     
    static let recordsDidChange = Notification.Name("ClashModuleRecordsDidChange")
     
     
     
     
     
    enum AnnouncementOrigin: String, Sendable {
        case scheduledRefresh = "scheduled-refresh"
    }
    static let originKey = "origin"

     
     
    static func isScheduledRefresh(_ note: Notification) -> Bool {
        (note.userInfo?[originKey] as? String) == AnnouncementOrigin.scheduledRefresh.rawValue
    }

     
     
     
     
    @TaskLocal static var publishing: AnnouncementOrigin?

    static let defaultUpdateInterval = ModuleLineSyntax.defaultScriptUpdateInterval
    static let portRange: ClosedRange<UInt16> = 42_000...48_999

     
     
     
    nonisolated static func shared(_ container: URL) -> ModuleStore {
        registry.store(for: container)
    }

     
     
    static func normalized(_ url: URL) -> URL { url.resolvingSymlinksInPath().standardizedFileURL }

    private static let registry = Registry()

    private final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var stores: [String: ModuleStore] = [:]

        func store(for container: URL) -> ModuleStore {
            let key = ModuleStore.normalized(container).path
            lock.lock()
            defer { lock.unlock() }
            if let existing = stores[key] { return existing }
            let made = ModuleStore(locations: ModuleLocations(container: container))
            stores[key] = made
            return made
        }
    }

     
    nonisolated let locations: ModuleLocations
    private let fetcher: HTTPFetching
    private let now: () -> Date
    private let platform: ModulePlatform
    private let randomPort: () -> UInt16
    private let check: ModuleRuleMapping.Check
    private let log: (String) -> Void
     
     
     
    private let writeFile: (Data, URL, Data.WritingOptions) throws -> Void

    init(locations: ModuleLocations,
         fetcher: HTTPFetching = ResourceDownloader.verified(),
         now: @escaping () -> Date = Date.init,
         platform: ModulePlatform = .current,
         randomPort: @escaping () -> UInt16 = { UInt16.random(in: ModuleStore.portRange) },
         check: @escaping ModuleRuleMapping.Check = ModuleRuleMapping.kernelCheck,
         log: @escaping (String) -> Void = { ClashLogStore.shared.append($0, stream: .app) },
         writeFile: @escaping (Data, URL, Data.WritingOptions) throws -> Void = { try $0.write(to: $1, options: $2) },
         runsScripts: Bool = ModuleStore.scriptHostRuns) {
        self.locations = locations
        self.writeFile = writeFile
        self.runsScripts = runsScripts
        self.fetcher = fetcher
        self.now = now
        self.platform = platform
        self.randomPort = randomPort
        self.check = check
        self.log = log
    }

     
     
     
     
     
     
#if os(tvOS)
    static let scriptHostRuns = false
#else
    static let scriptHostRuns = true
#endif
     
     
    private(set) var runsScripts: Bool
     
     
    private var scriptDownloadsLeft: Int?
     
     
     
     
     
     
    static let scriptDownloadsPerScan = 32

    func allowScripts(_ runs: Bool) { runsScripts = runs }

    static let scriptHeld = AuthoredText.app("This script can't be used, so it was skipped.")

     
    static func isDownloadSentence(_ reason: ModuleIgnoredReason) -> Bool {
        if case .scriptDownloadFailed = reason { return true }
        return false
    }

     
     
     
     
    func downloadsWithoutDirectFallback() -> Bool {
        (fetcher as? ResourceDownloader).map { !$0.fallsBackDirect } ?? false
    }

     

    private var settled = false
     
     
     
    private var generations: [String: Int] = [:]
     
     
     
     
     
    private var editSequences: [String: Int] = [:]
     
     
     
    private var preparing: [String: Int] = [:]

     
     
     
    func publishedModule(_ id: String) -> ModuleIR? {
        settle()
        return storedIR(id)
    }

     
     
     
     
    func publishedModules(_ ids: [String]) -> [String: ModuleIR] {
        settle()
        var out: [String: ModuleIR] = [:]
        for id in ids { out[id] = storedIR(id) }
        return out
    }

     
     
     
     
    private var decodedIRs: [String: (sha256: String, ir: ModuleIR)] = [:]

    private func decodedIR(_ id: String, _ data: Data) -> (sha256: String, ir: ModuleIR)? {
        let sha256 = ModuleJSON.sha256(data)
        if let decoded = decodedIRs[id], decoded.sha256 == sha256 { return decoded }
        guard let ir = try? ModuleJSON.decoder().decode(ModuleIR.self, from: data) else {
            decodedIRs[id] = nil
            return nil
        }
        decodedIRs[id] = (sha256, ir)
        return (sha256, ir)
    }

     
    private func storedIR(_ id: String) -> ModuleIR? {
        guard let data = try? Data(contentsOf: locations.moduleManifest(id)) else { return nil }
        return decodedIR(id, data)?.ir
    }

     
     
     
     
     
    private func publishedIR(of record: ModuleRecord) -> (sha256: String, ir: ModuleIR)? {
        let url = locations.moduleManifest(record.id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let decoded = decodedIR(record.id, data), decoded.ir.schemaVersion == ModuleIR.currentSchemaVersion {
            return decoded
        }
        guard readAgainFromSavedText(record, earlier: data), let again = try? Data(contentsOf: url),
              let decoded = decodedIR(record.id, again),
              decoded.ir.schemaVersion == ModuleIR.currentSchemaVersion else { return nil }
        return decoded
    }

     
     
     
     
     
     
     
     
     
    private func readAgainFromSavedText(_ record: ModuleRecord, earlier data: Data) -> Bool {
         
        struct Version: Decodable { let schemaVersion: Int }
        guard let version = (try? ModuleJSON.decoder().decode(Version.self, from: data))?.schemaVersion,
              version < ModuleIR.currentSchemaVersion else { return false }
        guard let source = try? Data(contentsOf: locations.source(record.id)) else {
            log("module \(record.id) was published in IR \(version) and has no saved copy to read again; it is left out until it is updated")
            return false
        }
         
        let earlier = try? ModuleJSON.decoder().decode(ModuleIR.self, from: data)
        var link: String?
        if case .url(let address) = record.origin { link = address }
        var ir: ModuleIR
        do {
            switch try ModuleParser.parse(source, sourceURL: link, fetchedAt: earlier?.manifest.fetchedAt,
                                                 platform: platform, argumentValues: record.argumentValues, check: check) {
            case .success(let parsed): ir = parsed
            case .failure(let refusal):
                log("module \(record.id) was published in IR \(version), and its saved copy is not read as a module now (\(refusal)); it is left out until it is updated")
                return false
            }
        } catch {
            log("module \(record.id) was published in IR \(version) and could not be read again now (\(error.localizedDescription))")
            return false
        }
         
        let scripts: [ModuleLineSyntax.DeclaredScript] = ir.scripts.map { .http($0) } + ir.appScripts.map { .app($0) }
        ir.scripts = []
        ir.appScripts = []
        for var script in scripts {
            let address = script.scriptURL
            if let sha = earlier?.scripts.first(where: { $0.scriptURL == address && $0.bodySHA256 != nil })?.bodySHA256
                ?? earlier?.appScripts.first(where: { $0.scriptURL == address && $0.bodySHA256 != nil })?.bodySHA256,
               FileManager.default.fileExists(atPath: locations.script(record.id, sha256: sha).path) {
                script.bodySHA256 = sha
                switch script {
                case .http(let kept): ir.scripts.append(kept)
                case .app(let kept): ir.appScripts.append(kept)
                }
            } else if let setAside = earlier?.ignored.first(where: { $0.text == address && $0.origin == script.origin }),
                      runsScripts || !Self.isDownloadSentence(setAside.reason) {
                 
                 
                 
                ir.ignored.append(ModuleIgnoredEntry(text: address, reason: setAside.reason, origin: script.origin))
            } else {
                let sentence = runsScripts ? Self.notDownloadedYet : Self.scriptHeld
                ir.ignored.append(ModuleIgnoredEntry(text: address, reason: .scriptDownloadFailed(Self.sentence(sentence)),
                                                      origin: script.origin))
            }
        }
         
         
         
         
        if let earlier {
            ir = carryingDownloads(of: earlier, into: ir, id: record.id)
            ir = adoptRuleSetCopies(ir, id: record.id, previous: earlier)
        }
        do {
            try write(try ModuleJSON.encoder().encode(ir), to: locations.moduleManifest(record.id))
        } catch {
            log("module \(record.id) was read again from its saved copy, and its IR could not be written (\(error.localizedDescription))")
            return false
        }
         
         
         
        let appAddresses = Set(scripts.compactMap { $0.app?.scriptURL })
        if record.appScriptAddresses != appAddresses, var state = try? loadForWrite(),
           let index = state.modules.firstIndex(where: { $0.id == record.id }) {
            state.modules[index].appScriptAddresses = appAddresses
            do { try save(state) } catch {
                log(#"module \#(record.id) was read again, and the App scripts it names could not be recorded (\#(error.localizedDescription))"#)
            }
        }
        log("module \(record.id) was published in IR \(version): read again from its saved copy, nothing downloaded")
        return true
    }

     
     
     
     
     
     
     
    private func carryingDownloads(of earlier: ModuleIR, into given: ModuleIR, id: String) -> ModuleIR {
        var ir = given
        func here(_ sha: String?, _ place: ModuleResourceFetcher.Place) -> Bool {
            guard let sha, !sha.isEmpty else { return false }
            return FileManager.default.fileExists(atPath: published(id, sha, place).path)
        }
        for index in ir.ruleSets.indices where ir.ruleSets[index].url != nil && ir.ruleSets[index].sha256 == nil {
            let set = ir.ruleSets[index]
            if let before = earlier.ruleSets.first(where: { $0.url == set.url && $0.origin == set.origin && here($0.sha256, .sets) }) {
                ir.ruleSets[index].sha256 = before.sha256
            }
        }
        for index in ir.answerFiles.indices where ir.answerFiles[index].sha256 == nil {
            let reference = ir.answerFiles[index]
            if let before = earlier.answerFiles.first(where: {
                $0.url == reference.url && ($0.base64 == true) == (reference.base64 == true) && $0.origin == reference.origin
                    && here($0.sha256, .files)
            }) {
                ir.answerFiles[index].sha256 = before.sha256
            }
        }
         
        func carried(_ action: ModuleRewriteAction, from before: ModuleRewriteAction) -> ModuleRewriteAction? {
            guard Self.placeholder(action, at: .engine(rule: 0)) != nil, Self.placeholder(before, at: .engine(rule: 0)) == nil else { return nil }
            switch (action, before) {
            case (.localAnswer, .localAnswer(let answer)):
                guard case .file(let sha, _) = answer.body, here(sha, .files) else { return nil }
            case (.requestBody, .requestBody(.file(let sha, _), _)):
                guard here(sha, .files) else { return nil }
            case (.bodyJQ, .bodyJQ(_, _, let sha?)):
                guard here(sha, .files) else { return nil }
            default:
                return nil
            }
            return before
        }
        for r in ir.rewriteRules.indices {
            let rule = ir.rewriteRules[r]
            guard let before = earlier.rewriteRules.first(where: { $0.origin == rule.origin }), before.actions.count == rule.actions.count else {
                continue
            }
            for a in rule.actions.indices {
                if let action = carried(rule.actions[a], from: before.actions[a]) { ir.rewriteRules[r].actions[a] = action }
            }
        }
        for r in ir.engineRules.indices {
            guard case .answer(let action) = ir.engineRules[r].decision,
                  let before = earlier.engineRules.first(where: { $0.origin == ir.engineRules[r].origin }),
                  case .answer(let filled) = before.decision, let action = carried(action, from: filled) else { continue }
            ir.engineRules[r].decision = .answer(action)
        }
        return ir
    }

    func publishedGlobalManifest() -> ModuleGlobalManifest? { Self.publishedGlobalManifest(locations) }

     
     
    nonisolated static func publishedGlobalManifest(_ locations: ModuleLocations) -> ModuleGlobalManifest? {
        guard let data = try? Data(contentsOf: locations.globalManifest) else { return nil }
        return try? ModuleJSON.decoder().decode(ModuleGlobalManifest.self, from: data)
    }

     

     
     
     
    func setEnabled(_ on: Bool) throws {
        settle()
         
         
         
         
         
        if !on {
            switch readState() {
            case .newer: return try switchOffWithoutTheList(.stateUnreadable(.newerVersion))
            case .corrupt: return try switchOffWithoutTheList(.stateUnreadable(.corrupt))
            case .readFailed, .missing, .readable: break
            }
        }
        var state = try loadForWrite()
        if state.enabled == on,
           !on || (state.ports != nil && state.reinjectCredentials != nil && state.engineProxyCredentials != nil) { return }
        let wasOn = state.enabled
        state.enabled = on
        if on, state.ports == nil { state.ports = drawPorts(avoiding: []) }
         
         
        if on, !wasOn || state.reinjectCredentials == nil { state.drawCredentials() }
        if on { state.drawEngineCredentialsIfUnusable() }
        try save(state)
        try publish(state)
    }

     
     
     
     
    private func switchOffWithoutTheList(_ refusal: ModuleStoreError) throws {
        guard FileManager.default.fileExists(atPath: locations.globalManifest.path) else { return }
        guard var manifest = publishedGlobalManifest() else { throw refusal }
        guard manifest.enabled else { return }
        manifest.enabled = false
        manifest.publishedAt = now()
        try write(try ModuleJSON.encoder().encode(manifest), to: locations.globalManifest)
        log("modules was switched off with a module list this build cannot use (\(refusal)); the list is left as it is")
        announce(Self.didChange)
    }

    func setModule(_ id: String, enabled: Bool) throws {
        settle()
        var state = try loadForWrite()
        guard let index = state.modules.firstIndex(where: { $0.id == id }),
              state.modules[index].enabled != enabled else { return }
        state.modules[index].enabled = enabled
         
        if enabled, let ir = storedIR(id) { seedStoredChoices(&state.modules[index], ir: ir) }
        try save(state)
        try publish(state)
    }

     
     
     
    func rename(_ id: String, to label: String) throws {
        settle()
        var state = try loadForWrite()
        guard let index = state.modules.firstIndex(where: { $0.id == id }) else { throw ModuleStoreError.moduleGone }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let given = trimmed.isEmpty || trimmed == state.modules[index].name ? nil : trimmed
        guard state.modules[index].label != given else { return }
        state.modules[index].label = given
        try save(state)
        try publish(state)
    }

     
     
    func move(_ ids: [String]) throws {
        settle()
        var state = try loadForWrite()
        var rest = state.modules
        var ordered: [ModuleRecord] = []
        for id in ids {
            if let at = rest.firstIndex(where: { $0.id == id }) { ordered.append(rest.remove(at: at)) }
        }
        let modules = ordered + rest
        guard modules.map(\.id) != state.modules.map(\.id) else { return }
        state.modules = modules
        try save(state)
        try publish(state)
    }

    func remove(_ id: String) throws {
        settle()
        var state = try loadForWrite()
        guard let removed = state.modules.first(where: { $0.id == id }) else { return }
        state.modules.removeAll { $0.id == id }
        generations[id, default: 0] += 1
        try save(state)
        try? FileManager.default.removeItem(at: locations.source(id))
         
         
         
         
        let store = scriptStore
        var removedKeys: [String] = []
        for (key, wrote) in removed.storedValues.sorted(by: { $0.key < $1.key }) where store.readShared(key: key) == wrote {
            if store.writeShared(nil, key: key) {
                removedKeys.append(key)
            } else {
                log(#"module \#(id) removed; its stored value \#(key) could not be removed"#)
            }
        }
        if !removedKeys.isEmpty {
            for index in state.modules.indices where state.modules[index].enabled {
                guard let ir = storedIR(state.modules[index].id) else { continue }
                seedStoredChoices(&state.modules[index], ir: ir)
            }
            try save(state)
        }
        try publish(state)
    }

     
     
    func rerollPorts(avoiding taken: Set<UInt16>) throws {
        settle()
        var state = try loadForWrite()
        state.ports = drawPorts(avoiding: taken)
         
         
        if state.reinjectCredentials?.isWellFormed != true { state.drawCredentials() }
        state.drawEngineCredentialsIfUnusable()
        try save(state)
        try publish(state)
    }

    private static func caFingerprint(in container: URL) -> String? {
        guard case .ready(_, let metadata) = ModuleCAFiles.status(ModuleEngineLocations.of(container)) else { return nil }
        return metadata.fingerprintSHA256
    }

     
     
    func republish() throws {
        try publish(try state())
    }

     
    @discardableResult
    func add(url raw: String) async throws -> ModuleRecord {
        settle()
        let address = try Self.address(raw)
        let link = address.absoluteString
        if let existing = try state().modules.first(where: { $0.origin == .url(link) }) { return existing }
        let fetchedAt = now()
        let data = try await downloadModule(address)
        let id = UUID().uuidString.lowercased()
        let prepared = try await prepare(data: data, sourceURL: link, fetchedAt: fetchedAt, id: id,
                                         previous: nil, previousFetchedAt: [:])
         
         
         
         
        if let existing = try state().modules.first(where: { $0.origin == .url(link) }) { return existing }
        var record = ModuleRecord(
            id: id, origin: .url(link), enabled: true, name: Self.name(of: prepared.ir, fallback: Self.fallbackName(forLink: link)),
            updateInterval: Self.defaultUpdateInterval, lastCheckedAt: fetchedAt, lastUpdatedAt: fetchedAt,
            lastFailure: nil, scriptFetchedAt: prepared.scriptFetchedAt, sourceSHA256: ModuleJSON.sha256(data))
        record.absorb(prepared)
        try commit(record, ir: prepared.ir, source: data, bodies: prepared.bodies, isNew: true)
        log("module \(id) added from \(link): \(prepared.ir.effectiveCount) kept, \(prepared.ir.ignoredCount) set aside")
        if record.isUnprotectedLink { log("module \(id) is read over plain http, as the reader typed \(link)") }
        return record
    }

     
    @discardableResult
    func add(text: String) async throws -> ModuleRecord {
        try await saveLocalModule(id: nil, text: text)
    }

     
     
     
     
     
     
     
     
     
     
     
     
    @discardableResult
    func saveLocalModule(id: String?, text: String) async throws -> ModuleRecord {
        settle()
        let data = Data(text.utf8)
        let at = now()
        guard let id else {
            let id = UUID().uuidString.lowercased()
            let prepared = try await prepare(data: data, sourceURL: nil, fetchedAt: at, id: id,
                                             previous: nil, previousFetchedAt: [:])
            var record = ModuleRecord(
                id: id, origin: .local, enabled: true, name: Self.name(of: prepared.ir, fallback: ""),
                updateInterval: Self.defaultUpdateInterval, lastCheckedAt: at, lastUpdatedAt: at,
                lastFailure: nil, scriptFetchedAt: prepared.scriptFetchedAt, sourceSHA256: ModuleJSON.sha256(data))
            record.absorb(prepared)
            try commit(record, ir: prepared.ir, source: data, bodies: prepared.bodies, isNew: true)
            log("module \(id) added as a local module: \(prepared.ir.effectiveCount) kept, \(prepared.ir.ignoredCount) set aside")
            return record
        }
        editSequences[id, default: 0] += 1
        let edit = editSequences[id, default: 0]
        let editable = try editableLocalModule(id)
        let prepared = try await prepare(data: data, sourceURL: nil, fetchedAt: at, id: id,
                                         previous: publishedModule(id), previousFetchedAt: editable.scriptFetchedAt,
                                         retrying: editable)
         
         
        guard editSequences[id] == edit else {
            log("module \(id): an edit was overtaken by a later one and was not written")
            throw ModuleStoreError.editSuperseded
        }
         
         
        var record = try editableLocalModule(id)
        record.name = Self.name(of: prepared.ir, fallback: record.name)
        record.lastCheckedAt = at
        record.lastUpdatedAt = at
        record.lastFailure = nil
        record.sourceSHA256 = ModuleJSON.sha256(data)
        record.absorb(prepared)
         
         
        generations[id, default: 0] += 1
        guard try commit(record, ir: prepared.ir, source: data, bodies: prepared.bodies, isNew: false) else {
            throw ModuleStoreError.moduleGone
        }
        log("module \(id) edited: \(prepared.ir.effectiveCount) kept, \(prepared.ir.ignoredCount) set aside")
        return try state().modules.first { $0.id == id } ?? record
    }

     
     
    private func editableLocalModule(_ id: String) throws -> ModuleRecord {
        guard let record = try state().modules.first(where: { $0.id == id }) else { throw ModuleStoreError.moduleGone }
        switch record.origin {
        case .local: return record
        case .url: throw ModuleStoreError.linkedModuleNotEditable
        case .unknown: throw ModuleStoreError.moduleFromANewerVersion
        }
    }

     

     
     
    static func address(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed), let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = components.host, !host.isEmpty
        else { throw ModuleRefusal.notAnAddress }
        components.scheme = scheme
        components.host = host.lowercased()
        guard let url = components.url else { throw ModuleRefusal.notAnAddress }
        return url
    }

     
     
    static func authoredText(for error: Error) -> AuthoredText { AuthoredText.of(error) }

     
     
     
     
    static func updateFailureText(for error: Error, linked: Bool) -> AuthoredText {
        switch error as? ModuleRefusal {
        case .tooLarge?: return .app("The new version is too large, so the last one is still in use.")
        case .otherPlatform?: return .app("The new version is for another kind of device, so the last one is still in use.")
        case .requirementNotMet?: return .app("The new version needs features Clash doesn't have yet, so the last one is still in use.")
        case .notAModule?, .notText?, .quantumultX?, .unreadableYAML?:
            return linked ? .app("The link no longer returns a module, so the last one is still in use.")
                : .app("This module's text can no longer be read, so the last one is still in use.")
        default: return authoredText(for: error)
        }
    }

     
     
     
     
     
     
    static func scriptFailureText(for error: Error) -> AuthoredText {
        switch error as? DownloadError {
        case .badStatus(let status)? where status >= 0, .refusedAuthorization(let status)?,
             .linkRefused(let status, _)?:
             
             
             
            return .app(ModuleStoredSentence.scriptStatus, arguments: [String(status)])
        case .badStatus?:
             
             
             
             
             
            return ModuleStoredSentence.scriptNotDownloaded
        case .tooLarge?, .invalidLimit?, .invalidPayload?, nil:
             
             
             
             
             
             
            if Self.reachedNoAnswer(error) { return ModuleStoredSentence.scriptNotReached }
            return authoredText(for: error)
        }
    }

     
     
     
    static func reachedNoAnswer(_ error: Error) -> Bool {
        if case ModuleStoreError.serverNotVerified? = error as? ModuleStoreError { return true }
        if error is URLError { return true }
        return (error as NSError).domain == NSURLErrorDomain
    }

     
    static func isMissingFile(_ error: Error) -> Bool {
        let ns = error as NSError
        return (ns.domain == NSCocoaErrorDomain && ns.code == NSFileReadNoSuchFileError)
            || (ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOENT))
    }

     
     
    static func sentence(_ text: AuthoredText) -> ModuleSentence {
        switch text {
        case .app(let key, let arguments): return .app(key, arguments: arguments)
        case .verbatim(let words): return .verbatim(words)
        }
    }

     
     
    static func isUnverifiedServer(_ error: Error) -> Bool {
        if error is UnprotectedRedirectRefused { return true }
        guard let code = (error as? URLError)?.code else { return false }
        return [.serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
                .serverCertificateNotYetValid].contains(code)
    }

     
     
    static let notDownloadedYet = AuthoredText.app("This script is not downloaded yet; it will be at the next update.")

    static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled
    }

     
     
     
    static let moduleTimeFloor: TimeInterval = 5

     
     
     
    func timeLeft() -> TimeInterval? {
        DirectFetchFallback.deadline.map { $0.timeIntervalSince(now()) }
    }

     
     
     
     
    func isOutOfTime(_ error: Error) -> Bool {
        guard (error as? URLError)?.code == .timedOut, let left = timeLeft() else { return false }
        return left < 2
    }

    static func name(of ir: ModuleIR, fallback: String) -> String {
        ir.manifest.name.flatMap { $0.isEmpty ? nil : $0 } ?? fallback
    }

     
     
     
     
     
     
     
     
     
     
     
     
    static func fallbackName(forLink link: String) -> String {
        guard let url = URL(string: link) else { return link }
        let file = url.lastPathComponent as NSString
        if moduleFileExtensions.contains(file.pathExtension.lowercased()) {
            let stem = file.deletingPathExtension.trimmingCharacters(in: .whitespaces)
            if !stem.isEmpty, !genericFileNames.contains(stem.lowercased()) { return stem }
        }
        return url.host.flatMap { $0.isEmpty ? nil : $0 } ?? link
    }

     
    static let moduleFileExtensions: Set<String> = ["conf", "js", "sgmodule", "module", "plugin", "lpx", "snippet",
                                                    "yaml", "yml", "stoverride", "list", "txt"]

     
     
    static let genericFileNames: Set<String> = ["raw", "download", "file", "files", "get", "index", "main", "master",
                                                "default", "module", "modules", "plugin", "plugins", "script", "scripts",
                                                "rewrite", "rule", "rules", "config", "configuration", "content", "latest",
                                                "export", "view"]

     
     
     
    static func fallbackName(of record: ModuleRecord) -> String {
        guard case .url(let link) = record.origin else { return record.name }
        return fallbackName(forLink: link)
    }

     
     
    static func checkScript(_ body: Data) throws {
        guard let text = String(data: body, encoding: .utf8) else { throw ModuleStoreError.notAScript }
        guard let first = text.first(where: { !$0.isWhitespace }) else { throw ModuleStoreError.emptyScript }
        guard first != "<" else { throw ModuleStoreError.notAScript }
    }

    private enum StateRead {
        case missing
        case readable(ModuleState)
         
        case newer
         
        case corrupt(Data)
         
         
        case readFailed(String)
    }

    private func readState() -> StateRead {
        guard FileManager.default.fileExists(atPath: locations.stateFile.path) else { return .missing }
        let data: Data
        do { data = try Data(contentsOf: locations.stateFile) } catch { return .readFailed(error.localizedDescription) }
        if ModuleState.isFromANewerBuild(data) { return .newer }
        guard let state = try? ModuleJSON.decoder().decode(ModuleState.self, from: data) else { return .corrupt(data) }
        return .readable(state)
    }

     
     
     
     
    func state() throws -> ModuleState {
        settle()
        switch readState() {
        case .missing: return ModuleState()
        case .readable(let state): return state
        case .newer: throw ModuleStoreError.stateUnreadable(.newerVersion)
        case .corrupt: throw ModuleStoreError.stateUnreadable(.corrupt)
        case .readFailed: throw ModuleStoreError.stateUnreadable(.readFailed)
        }
    }

     
     
     
     
     
     
    func loadForWrite() throws -> ModuleState {
        switch readState() {
        case .missing: return ModuleState()
        case .readable(let state): return state
        case .readFailed(let why):
            log("module list could not be read right now (\(why)); nothing was changed")
            throw ModuleStoreError.stateUnreadable(.readFailed)
        case .newer:
             
            log("module list was written by a newer version (schema above \(ModuleState.currentSchemaVersion)); nothing was changed")
            throw ModuleStoreError.stateUnreadable(.newerVersion)
        case .corrupt(let data):
            let directory = locations.stateFile.deletingLastPathComponent()
            let kept = unreadableCopies().contains { (try? Data(contentsOf: $0)) == data }
            if !kept {
                let stamp = Int(now().timeIntervalSince1970)
                var target = directory.appendingPathComponent("state.unreadable-\(stamp).json")
                var n = 1
                while FileManager.default.fileExists(atPath: target.path) {
                    n += 1
                    target = directory.appendingPathComponent("state.unreadable-\(stamp)-\(n).json")
                }
                do {
                    try writeFile(data, target, ProviderPayloadStore.writeOptions)
                    log("module list could not be understood; a copy is kept as \(target.lastPathComponent)")
                } catch {
                    log("module list could not be understood, and a copy could not be kept (\(error.localizedDescription))")
                }
            }
            throw ModuleStoreError.stateUnreadable(.corrupt)
        }
    }

    private func unreadableCopies() -> [URL] {
        let directory = locations.stateFile.deletingLastPathComponent()
        return ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("state.unreadable-") }
    }

     
     
     
     
     
     
     
     
     
     
     
    func discardUnreadableList() throws {
        switch readState() {
        case .readable, .missing: return
        case .readFailed: throw ModuleStoreError.stateUnreadable(.readFailed)
        case .newer: throw ModuleStoreError.stateUnreadable(.newerVersion)
        case .corrupt: break
        }
        let files = FileManager.default
        var aside: URL?
        if files.fileExists(atPath: locations.sourcesDirectory.path) {
            let directory = locations.stateFile.deletingLastPathComponent()
            let stamp = Int(now().timeIntervalSince1970)
            var target = directory.appendingPathComponent("discarded-\(stamp)", isDirectory: true)
            var n = 1
            while files.fileExists(atPath: target.path) {
                n += 1
                target = directory.appendingPathComponent("discarded-\(stamp)-\(n)", isDirectory: true)
            }
            try files.createDirectory(at: target, withIntermediateDirectories: true)
            let moved = target.appendingPathComponent("sources", isDirectory: true)
            try files.moveItem(at: locations.sourcesDirectory, to: moved)
            aside = moved
        }
        do {
            try publish(ModuleState())
        } catch {
            if let aside, (try? files.moveItem(at: aside, to: locations.sourcesDirectory)) != nil {
                try? files.removeItem(at: aside.deletingLastPathComponent())
            }
            throw error
        }
        try files.removeItem(at: locations.stateFile)
        let copies = unreadableCopies()
        var removed = 0
        for copy in copies where (try? files.removeItem(at: copy)) != nil { removed += 1 }
        if let aside {
            log("module list was discarded, with \(removed) kept copies; the modules' texts are kept in \(aside.deletingLastPathComponent().lastPathComponent)")
        } else {
            log("module list was discarded, with \(removed) kept copies")
        }
    }

     
     
     
    func save(_ state: ModuleState) throws {
        let encoded = try ModuleJSON.encoder().encode(state)
        let earlier = try? Data(contentsOf: locations.stateFile)
        try write(earlier.flatMap { state.keepingWhatThisBuildDoesNotKnow(encoded, from: $0) } ?? encoded, to: locations.stateFile)
    }

    func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeFile(data, url, ProviderPayloadStore.writeOptions)
    }

     
     
     
    func download(_ url: URL, maxBytes: Int, agent: String) async throws -> Data {
        let result = try await download(url, maxBytes: maxBytes, etag: nil, lastModified: nil, agent: agent)
         
         
         
        if result.notModified { throw DownloadError.badStatus(-1) }
        return result.data
    }

     
     
     
    func download(_ url: URL, maxBytes: Int, etag: String?, lastModified: String?, headers: [String: String] = [:],
                  redirects: DownloadRedirectPolicy = .followAcrossOrigins(maxHops: 5), agent: String) async throws -> DownloadResult {
        var request = URLRequest(url: url)
         
         
        let own: Set<String> = ["user-agent", "if-none-match", "if-modified-since"]
        for (field, value) in headers where !own.contains(field.lowercased()) { request.setValue(value, forHTTPHeaderField: field) }
         
         
         
        request.setValue(agent, forHTTPHeaderField: "User-Agent")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let lastModified { request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since") }
        do {
            return try await fetcher.fetch(request, maxBytes: maxBytes, redirectPolicy: redirects)
        } catch where Self.isUnverifiedServer(error) {
            log("module download from \(url.absoluteString) refused: the server could not be verified (\(error.localizedDescription))")
            throw ModuleStoreError.serverNotVerified
        }
    }

     
     
    func downloadModule(_ url: URL) async throws -> Data {
        try await download(url, maxBytes: .max, agent: ModuleUserAgent.forLink(url.absoluteString))
    }

    private func drawPorts(avoiding taken: Set<UInt16>) -> ModulePorts {
        var engine = randomPort()
        var tries = 0
        while taken.contains(engine), tries < 64 { engine = randomPort(); tries += 1 }
        var reinject = randomPort()
        tries = 0
        while reinject == engine || taken.contains(reinject), tries < 64 { reinject = randomPort(); tries += 1 }
        if reinject == engine { reinject = engine == Self.portRange.upperBound ? engine - 1 : engine + 1 }
        return ModulePorts(engine: engine, reinject: reinject)
    }

     
     
     
     
     
     
     
    struct Prepared {
        var ir: ModuleIR
        var scriptFetchedAt: [String: Date]
        var bodies: [String: Data]
         
        var attemptedAt: [String: Date] = [:]
        var failedAddresses: Set<String> = []
         
         
        var waiting: Set<String> = []
         
         
        var ranOutOfTime = false
         
        var fileStates: [String: ModuleFileState] = [:]
         
         
        var appScriptAddresses: Set<String> = []
         
        var heldScriptBodies: [String: ModuleHeldScriptBody] = [:]
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func prepare(data: Data, sourceURL: String?, fetchedAt: Date, id: String, previous: ModuleIR?,
                 previousFetchedAt: [String: Date], retrying record: ModuleRecord? = nil,
                 fetchingScripts: Bool = true, argumentValues given: [String: String]? = nil,
                 readerAsked: Bool = false) async throws -> Prepared {
         
         
         
         
        let argumentValues = given ?? record?.argumentValues ?? [:]
        for (name, value) in argumentValues where value.unicodeScalars.contains(where: { $0 == "\r" || $0 == "\n" }) {
            log(#"module \#(id): the value of its setting \#(name) holds a line break; read without it"#)
        }
        preparing[id, default: 0] += 1
        defer {
            if let count = preparing[id], count > 1 { preparing[id] = count - 1 } else { preparing[id] = nil }
        }
         
         
         
         
        let (platform, check) = (self.platform, self.check)
        let read = await ModuleJQLargeStack.moduleReads.run {
            try ModuleParser.parse(data, sourceURL: sourceURL, fetchedAt: fetchedAt, platform: platform,
                                   argumentValues: argumentValues, check: check)
        }
        var ir: ModuleIR
        switch try read.get() {
        case .success(let parsed): ir = parsed
        case .failure(let refusal): throw refusal
        }
        var fetched: [String: Date] = [:]
        var shas: [String: String] = [:]
        var newBodies: [String: Data] = [:]
        var failed: [String: ModuleSentence] = [:]
        var attempted: [String: Date] = [:]
        var failedAddresses = Set<String>()
        var waiting = Set<String>()
         
         
        var keptAt: [Int: ModuleLineSyntax.DeclaredScript] = [:]
        var setAsideAt: [Int: ModuleIgnoredEntry] = [:]
        var ranOutOfTime = false
         
         
         
        let scripts: [ModuleLineSyntax.DeclaredScript] = ir.scripts.map { .http($0) } + ir.appScripts.map { .app($0) }
        let appAddresses = Set(ir.appScripts.map(\.scriptURL))
         
         
        func earlierBody(_ address: String) -> String? {
            previous?.scripts.first { $0.scriptURL == address && $0.bodySHA256 != nil }?.bodySHA256
                ?? previous?.appScripts.first { $0.scriptURL == address && $0.bodySHA256 != nil }?.bodySHA256
                ?? record?.heldScriptBodies[address]?.sha256
        }
         
        func earlierFetchedAt(_ address: String) -> Date? {
            previousFetchedAt[address] ?? record?.heldScriptBodies[address]?.fetchedAt
        }
         
         
         
         
         
         
         
         
         
        func longestAgoFirst(_ indices: [Int]) -> [Int] {
            indices.enumerated().sorted { a, b in
                let first = previousFetchedAt[scripts[a.element].scriptURL] ?? .distantPast
                let second = previousFetchedAt[scripts[b.element].scriptURL] ?? .distantPast
                return first != second ? first < second : a.offset < b.offset
            }.map(\.element)
        }
        var order = longestAgoFirst(scripts.indices.filter { scripts[$0].isApp })
            + longestAgoFirst(scripts.indices.filter { !scripts[$0].isApp })
        if timeLeft() != nil {
            let bodied = scripts.map { script -> Bool in
                guard let sha = earlierBody(script.scriptURL) else { return false }
                return FileManager.default.fileExists(atPath: locations.script(id, sha256: sha).path)
            }
            order = order.filter { !bodied[$0] } + order.filter { bodied[$0] }
        }
        for index in order {
            var script = scripts[index]
            try Task.checkCancellation()
            let address = script.scriptURL
            if let sha = shas[address] {
                 
                 
                script.bodySHA256 = sha
                keptAt[index] = script
                continue
            }
            let earlier = earlierBody(address)
            let earlierOnDisk = earlier.map { FileManager.default.fileExists(atPath: locations.script(id, sha256: $0).path) } ?? false
            if let earlier, earlierOnDisk, failed[address] == nil, let at = earlierFetchedAt(address),
               now().timeIntervalSince(at) < ModuleLineSyntax.scriptCheckInterval(script.updateInterval) {
                shas[address] = earlier
                fetched[address] = at
                script.bodySHA256 = earlier
                keptAt[index] = script
                continue
            }
            if let sentence = failed[address] {
                setAsideAt[index] = ModuleIgnoredEntry(text: address, reason: .scriptDownloadFailed(sentence), origin: script.origin)
                continue
            }
             
             
             
            func keptAsItWas(_ script: ModuleLineSyntax.DeclaredScript) -> Bool {
                var script = script
                if let earlier, earlierOnDisk {
                    shas[address] = earlier
                    if let at = previousFetchedAt[address] { fetched[address] = at }
                    script.bodySHA256 = earlier
                    keptAt[index] = script
                    waiting.insert(address)
                    return true
                }
                if case .scriptDownloadFailed(let sentence)? = previous?.ignored.first(where: { entry in
                    guard case .scriptDownloadFailed = entry.reason else { return false }
                    return entry.text == address
                })?.reason {
                    failed[address] = sentence
                    setAsideAt[index] = ModuleIgnoredEntry(text: address, reason: .scriptDownloadFailed(sentence), origin: script.origin)
                    waiting.insert(address)
                    return true
                }
                return false
            }
             
             
             
             
            func setAsideForLater(_ script: ModuleLineSyntax.DeclaredScript, because why: String, saying: AuthoredText = Self.notDownloadedYet) {
                failed[address] = Self.sentence(saying)
                setAsideAt[index] = ModuleIgnoredEntry(text: address, reason: .scriptDownloadFailed(Self.sentence(saying)),
                                                        origin: script.origin)
                waiting.insert(address)
                log("module \(id): script \(script.name) from \(address) is not downloaded yet; \(why)")
            }
             
             
            if !runsScripts {
                 
                if earlier == nil || !earlierOnDisk || !keptAsItWas(script) {
                    setAsideForLater(script, because: #"no script runs in this build"#, saying: Self.scriptHeld)
                }
                continue
            }
             
             
             
            if !fetchingScripts, !script.isApp {
                if !keptAsItWas(script) { setAsideForLater(script, because: #"HTTPS Decryption is off"#) }
                continue
            }
             
             
             
             
            if !readerAsked, let record, let failures = record.scriptFailureCount[address], failures > 0,
               let tried = record.scriptAttemptedAt[address],
               now().timeIntervalSince(tried) < Self.retryDelay(
                   failures: failures, interval: earlier != nil && earlierOnDisk ? script.updateInterval : record.updateInterval),
               keptAsItWas(script) {
                continue
            }
             
             
             
             
            if !ranOutOfTime, let left = timeLeft(), left < Self.moduleTimeFloor { ranOutOfTime = true }
            if !ranOutOfTime, let left = scriptDownloadsLeft, left <= 0 {
                ranOutOfTime = true
                log(#"module \#(id): this scan has downloaded its \#(Self.scriptDownloadsPerScan) script bodies; the rest wait for the next"#)
            }
            if ranOutOfTime {
                if !keptAsItWas(script) { setAsideForLater(script, because: #"the background task's time ran out"#) }
                continue
            }
            if let left = scriptDownloadsLeft { scriptDownloadsLeft = left - 1 }
            attempted[address] = now()
             
             
            do {
                let body = try await download(try Self.address(address), maxBytes: .max, agent: ModuleUserAgent.forModule(ir.manifest))
                try Self.checkScript(body)
                let sha = ModuleJSON.sha256(body)
                newBodies[sha] = body
                shas[address] = sha
                fetched[address] = now()
                script.bodySHA256 = sha
                keptAt[index] = script
                log("module \(id): script \(script.name) downloaded from \(address), \(body.count) bytes, sha256 \(sha)")
            } catch ModuleRefusal.notAnAddress {
                 
                 
                 
                 
                attempted.removeValue(forKey: address)
                setAsideAt[index] = ModuleIgnoredEntry(text: address, reason: .scriptWithoutAddress, origin: script.origin)
                log("module \(id): script \(script.name) names \(address), which no request can be made from")
            } catch {
                 
                if Self.isCancellation(error) { throw error }
                 
                 
                if isOutOfTime(error) {
                    attempted.removeValue(forKey: address)
                    ranOutOfTime = true
                    if !keptAsItWas(script) { setAsideForLater(script, because: #"the background task's time ran out"#) }
                    continue
                }
                failedAddresses.insert(address)
                let why = Self.scriptFailureText(for: error)
                let message = why.englishText
                if let earlier, earlierOnDisk {
                    shas[address] = earlier
                    if let at = previousFetchedAt[address] { fetched[address] = at }
                    script.bodySHA256 = earlier
                    keptAt[index] = script
                    log("module \(id): script \(script.name) was not updated from \(address) (\(message)); the copy downloaded before stays")
                } else {
                    let sentence = Self.sentence(why)
                    failed[address] = sentence
                    setAsideAt[index] = ModuleIgnoredEntry(text: address, reason: .scriptDownloadFailed(sentence), origin: script.origin)
                    log("module \(id): script \(script.name) could not be downloaded from \(address) (\(message))")
                }
            }
        }
        ir.scripts = scripts.indices.compactMap { keptAt[$0]?.http }
        ir.appScripts = scripts.indices.compactMap { keptAt[$0]?.app }
        ir.ignored += scripts.indices.compactMap { setAsideAt[$0] }
        if !ranOutOfTime, let left = timeLeft(), left < Self.moduleTimeFloor { ranOutOfTime = true }
        let files = try await resolveFiles(ir, id: id, previous: previous, states: record?.fileStates ?? [:],
                                           interval: record?.updateInterval ?? Self.defaultUpdateInterval, at: fetchedAt,
                                           fetchingFiles: fetchingScripts && !ranOutOfTime, fetchingSets: !ranOutOfTime,
                                           readerAsked: readerAsked)
        ir = files.ir
        if files.ranOutOfTime { ranOutOfTime = true }
         
         
         
        ir = adoptRuleSetCopies(ir, id: id, previous: previous)
        return Prepared(ir: ir, scriptFetchedAt: fetched, bodies: newBodies, attemptedAt: attempted,
                        failedAddresses: failedAddresses, waiting: waiting, ranOutOfTime: ranOutOfTime, fileStates: files.states,
                        appScriptAddresses: appAddresses,
                        heldScriptBodies: heldBodies(ir, id: id, previous: previous, previousFetchedAt: previousFetchedAt, record: record))
    }

     
     
     
     
     
     
    func heldBodies(_ ir: ModuleIR, id: String, previous: ModuleIR?, previousFetchedAt: [String: Date],
                    record: ModuleRecord?) -> [String: ModuleHeldScriptBody] {
        let off = Set(ir.ignored.filter { $0.reason == .scriptTurnedOff }.compactMap {
            ModuleLineSyntax.scriptAddress(ofLine: $0.text, moduleURL: ir.manifest.sourceURL)
        })
        guard !off.isEmpty else { return [:] }
        var had = record?.heldScriptBodies ?? [:]
        let earlier = (previous?.scripts.map { ($0.scriptURL, $0.bodySHA256) } ?? [])
            + (previous?.appScripts.map { ($0.scriptURL, $0.bodySHA256) } ?? [])
        for (address, sha) in earlier {
            if let sha { had[address] = ModuleHeldScriptBody(sha256: sha, fetchedAt: previousFetchedAt[address]) }
        }
        let inUse = Set(ir.scripts.map(\.scriptURL) + ir.appScripts.map(\.scriptURL))
        return had.filter { address, body in
            !inUse.contains(address) && off.contains(address)
                && FileManager.default.fileExists(atPath: locations.script(id, sha256: body.sha256).path)
        }
    }

     

     
     
     
     
     
     
     
    static let maximumRuleSetBytes = 16 << 20

     
     
     
    static func fileRetryDelay(failures: Int, interval: Int) -> TimeInterval {
        let delay: TimeInterval = failures <= 1 ? 300 : failures == 2 ? 3600 : TimeInterval(interval)
        return min(delay, TimeInterval(interval))
    }

     
     
     
     
     
    static func setInterval(_ own: Int?, module interval: Int) -> Int {
        guard let own else { return interval }
        return own < 0 ? setNeverAgain : max(ModuleRuleSetSyntax.minimumListInterval, own)
    }

     
     
    static let setNeverAgain = Int.max

     
     
     
    static func retryInterval(_ interval: Int, module: Int) -> Int {
        interval == setNeverAgain ? module : interval
    }

     
     
     
    static func fileIsDue(_ state: ModuleFileState, interval: Int, retryInterval: Int? = nil, now: Date) -> Bool {
        if state.failures > 0, let at = state.attemptedAt {
            return now.timeIntervalSince(at) >= fileRetryDelay(failures: state.failures, interval: retryInterval ?? interval)
        }
        guard let at = state.fetchedAt else { return true }
        return now.timeIntervalSince(at) >= TimeInterval(interval)
    }

     
     
    static func fileKey(_ place: ModuleResourceFetcher.Place, _ url: String, base64: Bool = false) -> String {
        "\(place.rawValue)\(base64 ? "+base64" : "") \(url)"
    }

     
     
    static let fileNotDownloaded = ModuleSentence.app("The file this line uses couldn't be downloaded, so it was skipped.", arguments: [])
     
     
     
    static let fileNotSecure = ModuleSentence.app("The file this line uses isn't at an HTTPS address, so it was skipped.", arguments: [])
     
     
     
    static let tooManyFiles = ModuleSentence.app("This module uses too many or too large files, so this line was skipped.", arguments: [])

     
     
    struct ResolvedFiles {
        var ir: ModuleIR
        var states: [String: ModuleFileState]
        var ranOutOfTime = false
    }

     
     
    private struct Slot {
        enum Place: Hashable {
            case rewrite(rule: Int, action: Int)
            case engine(rule: Int)
        }
        var place: Place
        var jq: Bool
         
        var type: String?

         
         
        func acceptsHTML(_ url: String) -> Bool {
            guard !jq else { return false }
            if let type { return type.lowercased().contains("html") }
            return ["htm", "html"].contains(URL(string: url)?.pathExtension.lowercased() ?? "")
        }
    }

     
    private struct Wanted {
        var key: String
        var url: String
        var place: ModuleResourceFetcher.Place
        var base64: Bool
        var interval: Int
         
         
        var headers: [String: String] = [:]
         
        var uses: [(reference: Int, slot: Slot)] = []
    }

    private enum Resolution {
        case file(sha256: String, byteCount: Int)
         
        case waiting
        case failed(ModuleIgnoredReason)
    }

     
     
    private static func placeholders(_ ir: ModuleIR) -> [ModuleLineOrigin: [Slot]] {
        var slots: [ModuleLineOrigin: [Slot]] = [:]
        for (r, rule) in ir.rewriteRules.enumerated() {
            for (a, action) in rule.actions.enumerated() {
                if let slot = placeholder(action, at: .rewrite(rule: r, action: a)) { slots[rule.origin, default: []].append(slot) }
            }
        }
        for (r, rule) in ir.engineRules.enumerated() {
            guard case .answer(let action) = rule.decision, let slot = placeholder(action, at: .engine(rule: r)) else { continue }
            slots[rule.origin, default: []].append(slot)
        }
        return slots
    }

    private static func placeholder(_ action: ModuleRewriteAction, at place: Slot.Place) -> Slot? {
        switch action {
        case .localAnswer(let answer):
            guard case .file(let sha, _) = answer.body, sha.isEmpty else { return nil }
            let type = answer.headers.last { $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value
            return Slot(place: place, jq: false, type: type)
        case .requestBody(.file(let sha, _), let contentType) where sha.isEmpty:
            return Slot(place: place, jq: false, type: contentType)
        case .bodyJQ(_, let expression, nil) where expression.isEmpty:
            return Slot(place: place, jq: true, type: nil)
        default:
            return nil
        }
    }

     
     
     
    private static func filled(_ action: ModuleRewriteAction, sha256: String, byteCount: Int) -> ModuleRewriteAction {
        switch action {
        case .localAnswer(var answer):
            answer.body = .file(sha256: sha256, byteCount: byteCount)
            return .localAnswer(answer)
        case .requestBody(_, let contentType):
            return .requestBody(.file(sha256: sha256, byteCount: byteCount), contentType: contentType)
        case .bodyJQ(let phase, _, _):
            return .bodyJQ(phase: phase, expression: "", sha256: sha256)
        default:
            return action
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func resolveFiles(_ ir: ModuleIR, id: String, previous: ModuleIR?, states: [String: ModuleFileState] = [:],
                      interval: Int = ModuleStore.defaultUpdateInterval, at passTime: Date? = nil,
                      fetchingFiles: Bool, fetchingSets: Bool, readerAsked: Bool = false) async throws -> ResolvedFiles {
        guard !ir.answerFiles.isEmpty || ir.ruleSets.contains(where: { $0.url != nil }) else { return ResolvedFiles(ir: ir, states: [:]) }
         
        preparing[id, default: 0] += 1
        defer {
            if let count = preparing[id], count > 1 { preparing[id] = count - 1 } else { preparing[id] = nil }
        }
        let passTime = passTime ?? now()
        let log = self.log
        let agent = ModuleUserAgent.forModule(ir.manifest)
        let fetcher = ModuleResourceFetcher(
            locations: locations,
            download: { [unowned self] url, limit, etag, lastModified, headers in
                try await self.download(url, maxBytes: limit, etag: etag, lastModified: lastModified, headers: headers,
                                        redirects: .followWithinAModulesReach(maxHops: 5), agent: agent)
            },
            isOutOfTime: { [unowned self] error in await self.isOutOfTime(error) },
            write: { [unowned self] data, url in try await self.write(data, to: url) },
            log: { log($0) })

         
         
        let slots = Self.placeholders(ir)
        var wanted: [Wanted] = []
        var index: [String: Int] = [:]
        var keyOfReference: [Int: String] = [:]
        var ordinals: [ModuleLineOrigin: Int] = [:]
        for (r, reference) in ir.answerFiles.enumerated() {
            let ordinal = ordinals[reference.origin, default: 0]
            ordinals[reference.origin] = ordinal + 1
            guard let line = slots[reference.origin], ordinal < line.count else {
                log("module \(id): \(reference.url) is named by \(reference.origin.section) line \(reference.origin.line), where no action waits for a file")
                continue
            }
            let key = Self.fileKey(.files, reference.url, base64: reference.base64 == true)
            if index[key] == nil {
                index[key] = wanted.count
                wanted.append(Wanted(key: key, url: reference.url, place: .files, base64: reference.base64 == true, interval: interval))
            }
            wanted[index[key]!].uses.append((r, line[ordinal]))
            keyOfReference[r] = key
        }
        for set in ir.ruleSets {
            guard let url = set.url else { continue }
            let key = Self.fileKey(.sets, url)
            let own = Self.setInterval(set.interval, module: interval)
            if let at = index[key] {
                wanted[at].interval = min(wanted[at].interval, own)
                continue
            }
            index[key] = wanted.count
             
            let headers = ModuleRuleSetSyntax.downloadHeaders(of: set).filter { $0.key.lowercased() != "user-agent" }
            wanted.append(Wanted(key: key, url: url, place: .sets, base64: false, interval: own, headers: headers))
        }

        var resolution: [String: Resolution] = [:]
        var newStates: [String: ModuleFileState] = [:]
        var jqTexts: [String: JQText] = [:]
        var ranOutOfTime = false
        for item in wanted {
            var state = states[item.key] ?? ModuleFileState()
            let exists = { (sha: String) in FileManager.default.fileExists(atPath: self.published(id, sha, item.place).path) }
             
            let earlier = [state.sha256, Self.namedBefore(item, in: previous)].compactMap { $0 }.first(where: exists)
            let jqUses = item.uses.filter(\.slot.jq).count
            let cap = item.place == .sets ? Self.maximumRuleSetBytes : .max
            let tried = item.place == .sets ? fetchingSets : fetchingFiles
            let due: Bool = {
                 
                if state.failures > 0, let at = state.attemptedAt {
                    if readerAsked { return true }
                    let widest = Self.retryInterval(item.interval, module: interval)
                    return now().timeIntervalSince(at) >= Self.fileRetryDelay(failures: state.failures, interval: widest)
                }
                guard earlier != nil, let at = state.fetchedAt else { return true }
                return passTime.timeIntervalSince(at) >= TimeInterval(item.interval)
            }()
            var sha = earlier
            var failure: ModuleResourceFetcher.Failure?
            var jqWords: String?
            if due, tried, !ranOutOfTime {
                try Task.checkCancellation()
                 
                if let left = timeLeft(), left < Self.moduleTimeFloor { ranOutOfTime = true }
            }
            if due, tried, !ranOutOfTime {
                let request = ModuleResourceFetcher.Request(
                    url: item.url, place: item.place, cap: cap,
                    base64: item.base64, acceptsHTML: item.uses.contains { $0.slot.acceptsHTML(item.url) },
                    earlier: earlier.map { .init(sha256: $0, etag: state.etag, lastModified: state.lastModified) },
                    headers: item.headers)
                switch try await fetcher.fetch(request, module: id) {
                case .fetched(let new, _, let etag, let lastModified):
                     
                    var reads = true
                    if jqUses > 0 {
                        let text = await Self.jqText(published(id, new, .files))
                        jqTexts[new] = text
                        switch text {
                        case .text: break
                        case .invalid(let words): reads = false; jqWords = words
                        case .unusable: reads = false
                        }
                    }
                    if reads {
                        sha = new
                        state = ModuleFileState(sha256: new, fetchedAt: passTime, attemptedAt: now(), failures: 0,
                                                 etag: etag, lastModified: lastModified)
                    } else {
                        log("module \(id): \(item.url) is not a jq program Clash reads (\(jqWords ?? #"not text"#))")
                        failure = .unusable
                        state.failures += 1
                        state.attemptedAt = now()
                    }
                case .notModified(let etag, let lastModified):
                    state.sha256 = earlier
                    state.fetchedAt = passTime
                    state.attemptedAt = now()
                    state.failures = 0
                    state.etag = etag
                    state.lastModified = lastModified
                case .failed(let why):
                    failure = why
                    state.failures += 1
                    state.attemptedAt = now()
                case .notTried:
                    ranOutOfTime = true
                }
            }
            if state != ModuleFileState() { newStates[item.key] = state }
            if let current = sha {
                let size = ((try? FileManager.default.attributesOfItem(atPath: published(id, current, item.place).path))?[.size] as? Int) ?? 0
                if jqUses > 0, jqTexts[current] == nil { jqTexts[current] = await Self.jqText(published(id, current, .files)) }
                if failure != nil { log("module \(id): \(item.url) was not updated; the copy downloaded before stays") }
                resolution[item.key] = .file(sha256: current, byteCount: size)
            } else if let failure {
                 
                 
                resolution[item.key] = .failed(item.place == .sets && failure == .unusable
                    ? .ruleSetNotDownloadedYet : Self.reason(for: failure, jqWords: jqWords))
            } else if state.failures > 0, let had = Self.skippedBefore(item, in: previous) {
                 
                resolution[item.key] = .failed(had)
            } else {
                resolution[item.key] = .waiting
            }
        }

         
         
        var out = ir
        var skipped: [ModuleLineOrigin: (url: String, reason: ModuleIgnoredReason)] = [:]
        var fills: [Slot.Place: (sha256: String, byteCount: Int)] = [:]
        func skip(_ origin: ModuleLineOrigin, _ url: String, _ reason: ModuleIgnoredReason) {
            if skipped[origin] == nil { skipped[origin] = (url, reason) }
        }
        for item in wanted where item.place == .files {
            for use in item.uses {
                let origin = ir.answerFiles[use.reference].origin
                switch resolution[item.key] {
                case .failed(let reason)?: skip(origin, item.url, reason)
                case .file(let sha, let size)?:
                    out.answerFiles[use.reference].sha256 = sha
                    guard use.slot.jq else {
                        fills[use.slot.place] = (sha, size)
                        continue
                    }
                    switch jqTexts[sha] {
                    case .text?: fills[use.slot.place] = (sha, size)
                    case .invalid(let words)?: skip(origin, item.url, Self.jqReason(words))
                    case .unusable?, nil: skip(origin, item.url, .fileDownloadFailed(Self.fileNotDownloaded))
                    }
                case .waiting?, nil:
                    break
                }
            }
        }
        out.rewriteRules = ir.rewriteRules.enumerated().compactMap { r, rule in
            guard skipped[rule.origin] == nil else { return nil }
            var rule = rule
            for a in rule.actions.indices {
                guard let fill = fills[.rewrite(rule: r, action: a)] else { continue }
                rule.actions[a] = Self.filled(rule.actions[a], sha256: fill.sha256, byteCount: fill.byteCount)
            }
            return rule
        }
        out.engineRules = ir.engineRules.enumerated().compactMap { r, rule in
            guard skipped[rule.origin] == nil else { return nil }
            guard let fill = fills[.engine(rule: r)], case .answer(let action) = rule.decision else { return rule }
            var rule = rule
            rule.decision = .answer(Self.filled(action, sha256: fill.sha256, byteCount: fill.byteCount))
            return rule
        }
         
        out.answerFiles = out.answerFiles.enumerated().compactMap { r, reference in
            keyOfReference[r] == nil ? nil : reference
        }
        out.ignored += skipped.sorted { ($0.key.section, $0.key.line) < ($1.key.section, $1.key.line) }
            .map { ModuleIgnoredEntry(text: $0.value.url, reason: $0.value.reason, origin: $0.key) }

         
         
         
        var keptSets: [ModuleRuleSet] = []
        var leftOut: [String] = []
        for var set in ir.ruleSets {
            guard let url = set.url else { keptSets.append(set); continue }
            switch resolution[Self.fileKey(.sets, url)] {
            case .file(let sha, _)?:
                set.sha256 = sha
                keptSets.append(set)
            case .failed(let reason)?:
                out.ignored.append(ModuleIgnoredEntry(text: url, reason: reason, origin: set.origin))
                leftOut.append(set.reference)
            case .waiting?, nil:
                set.sha256 = nil
                keptSets.append(set)
            }
        }
        out.ruleSets = keptSets
        for reference in leftOut where !keptSets.contains(where: { $0.reference == reference }) {
            out = Self.leavingOut(reference, of: out)
        }
        return ResolvedFiles(ir: out, states: newStates, ranOutOfTime: ranOutOfTime)
    }

    private func published(_ id: String, _ sha256: String, _ place: ModuleResourceFetcher.Place) -> URL {
        place == .files ? locations.file(id, sha256: sha256) : locations.ruleSet(id, sha256: sha256)
    }

     
     
    private static func namedBefore(_ item: Wanted, in previous: ModuleIR?) -> String? {
        guard let previous else { return nil }
        if item.place == .sets { return previous.ruleSets.first { $0.url == item.url && $0.sha256 != nil }?.sha256 }
        return previous.answerFiles.first { $0.url == item.url && ($0.base64 == true) == item.base64 && $0.sha256 != nil }?.sha256
    }

     
     
    private static func skippedBefore(_ item: Wanted, in previous: ModuleIR?) -> ModuleIgnoredReason? {
        previous?.ignored.first { entry in
            guard entry.text == item.url else { return false }
            switch entry.reason {
            case .fileDownloadFailed, .jqExpressionInvalid, .noEffectInItsOwnApp, .ruleSetNotDownloadedYet: return true
            default: return false
            }
        }?.reason
    }

    private static func reason(for failure: ModuleResourceFetcher.Failure, jqWords: String?) -> ModuleIgnoredReason {
        if let jqWords { return jqReason(jqWords) }
        switch failure {
        case .tooLarge, .unusable: return .fileDownloadFailed(fileNotDownloaded)
        }
    }

     
     
     
    static func jqReason(_ words: String) -> ModuleIgnoredReason {
        words == ModuleJQ.noProgram ? .noEffectInItsOwnApp(.noEffect) : .jqExpressionInvalid(words)
    }

    enum JQText: Equatable {
        case text(String)
         
        case invalid(String)
         
        case unusable
    }

     
     
    static func jqText(_ file: URL) async -> JQText {
        guard let data = try? Data(contentsOf: file),
              let text = String(data: data, encoding: .utf8) else { return .unusable }
        do {
            _ = try await ModuleJQ.parseOnLargeStack(text)
            return .text(text)
        } catch let error as ModuleJQ.ParseError {
            return .invalid(error.message)
        } catch {
            return .invalid("\(error)")
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    @discardableResult
    func commit(_ record: ModuleRecord, ir: ModuleIR, source: Data,
                bodies: [String: Data] = [:], isNew: Bool) throws -> Bool {
        var state = try loadForWrite()
        let before = state
        if let index = state.modules.firstIndex(where: { $0.id == record.id }) {
            state.modules[index].adopt(refreshOwnedFieldsOf: record)
        } else if isNew {
            state.modules.append(record)
        } else {
            return false
        }
         
        let named = ir.scripts.map { (url: $0.scriptURL, sha: $0.bodySHA256) } + ir.appScripts.map { (url: $0.scriptURL, sha: $0.bodySHA256) }
        for script in named {
            guard let sha = script.sha else { throw ModuleStoreError.scriptMissing(script.url) }
            if bodies[sha] == nil, !FileManager.default.fileExists(atPath: locations.script(record.id, sha256: sha).path) {
                throw ModuleStoreError.scriptMissing(script.url)
            }
        }
         
        for reference in ir.answerFiles {
            guard let sha = reference.sha256 else { continue }
            guard FileManager.default.fileExists(atPath: locations.file(record.id, sha256: sha).path) else {
                throw ModuleStoreError.fileMissing(reference.url)
            }
        }
        for set in ir.ruleSets {
            guard let sha = set.sha256 else { continue }
            guard FileManager.default.fileExists(atPath: locations.ruleSet(record.id, sha256: sha).path) else {
                throw ModuleStoreError.fileMissing(set.url ?? sha)
            }
        }
         
        if let index = state.modules.firstIndex(where: { $0.id == record.id }), state.modules[index].enabled {
            seedStoredChoices(&state.modules[index], ir: ir)
        }
        let encoded = try ModuleJSON.encoder().encode(ir)
        for (sha, body) in bodies { try write(body, to: locations.script(record.id, sha256: sha)) }
        let manifestFile = locations.moduleManifest(record.id), sourceFile = locations.source(record.id)
        let earlierManifest = Earlier(manifestFile), earlierSource = Earlier(sourceFile)
        do {
            try write(source, to: sourceFile)
            try write(encoded, to: manifestFile)
            try save(state)
            try publish(state)
        } catch {
             
             
             
            var restored = true
            func restore(_ earlier: Earlier, _ url: URL) {
                do {
                    switch earlier {
                    case .absent: if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                    case .bytes(let data): try write(data, to: url)
                    case .unreadable: restored = false
                    }
                } catch {
                    restored = false
                }
            }
            restore(earlierManifest, manifestFile)
            restore(earlierSource, sourceFile)
            do { try save(before) } catch { restored = false }
            if restored {
                log("module \(record.id) was not written (\(error.localizedDescription)); what was published stays")
            } else {
                 
                 
                log("module \(record.id) was not written (\(error.localizedDescription)), and its files could not all be put back; what is on disk is published again")
                if let list = try? loadForWrite() { try? publish(list) }
            }
            throw error
        }
        return true
    }

     
    private enum Earlier {
        case absent
        case bytes(Data)
         
        case unreadable

        init(_ url: URL) {
            guard FileManager.default.fileExists(atPath: url.path) else { self = .absent; return }
            if let data = try? Data(contentsOf: url) { self = .bytes(data) } else { self = .unreadable }
        }
    }

     
     
     
     
     
     
    func note(_ record: ModuleRecord) throws {
        var state = try loadForWrite()
        guard let index = state.modules.firstIndex(where: { $0.id == record.id }) else { return }
        let published = state.modules[index].displayName
        state.modules[index].adopt(refreshOwnedFieldsOf: record)
        try save(state)
        if state.modules[index].displayName != published { try publish(state) }
        announce(Self.recordsDidChange)
    }

     
     
     
     
     
     
    private func settle() {
        guard !settled else { return }
        switch readState() {
        case .readable(let state):
            settled = true
            for record in state.modules where !record.enabled { _ = publishedIR(of: record) }
            try? publish(state)
        case .missing:
            settled = true
        case .corrupt, .newer, .readFailed:
             
             
             
            return
        }
    }

     
     
     
    func publish(_ state: ModuleState) throws {
        var modules: [ModuleGlobalManifest.Module] = []
        var mitm: [(moduleID: String, lines: [ModuleHostListLine])] = []
        var plainHTTP: [(moduleID: String, lines: [ModuleHostListLine])] = []
        var enabled: [(moduleID: String, ir: ModuleIR, choice: String?)] = []
        for record in state.modules where record.enabled {
             
            guard let (irSHA256, ir) = publishedIR(of: record) else {
                log("module \(record.id) is left out of the publication: its manifest could not be read")
                continue
            }
            var published = ModuleGlobalManifest.Module(
                id: record.id, name: record.displayName, irSHA256: irSHA256,
                effectiveCount: ir.effectiveCount, ignoredCount: ir.ignoredCount)
             
            if ir.mitmOverHTTP2 { published.http2 = true }
            modules.append(published)
            mitm.append((moduleID: record.id, lines: ir.mitmHostLines))
            plainHTTP.append((moduleID: record.id, lines: ir.forceHTTPEngineHostLines))
             
             
             
            enabled.append((moduleID: record.id, ir: ir, choice: nil))
        }
         
         
        let builtIns = enabled.contains { $0.ir.ruleSets.contains { $0.kind == .builtInLAN || $0.kind == .builtInSystem } }
        let lanCopy = builtIns ? builtInRuleSetCopy(.builtInLAN) : nil
        let systemCopy = builtIns ? builtInRuleSetCopy(.builtInSystem) : nil
        let sets = ModuleRuleSetSyntax.publication(enabled, builtInCopy: { kind in
            kind == .builtInLAN ? lanCopy : kind == .builtInSystem ? systemCopy : nil
        })
         
         
        for index in modules.indices {
            if let origins = sets.leftOutOrigins[modules[index].id] { modules[index].leftOutOrigins = origins }
        }
        var manifest = ModuleGlobalManifest(
            schemaVersion: ModuleGlobalManifest.currentSchemaVersion, enabled: state.enabled, modules: modules,
            mitmHosts: ModuleHostList.merged(mitm, standardPort: ModuleHostList.mitmStandardPort,
                                             preferring: Set(modules.filter { $0.http2 == true }.map(\.id))),
            forceHTTPEngineHosts: ModuleHostList.merged(plainHTTP, standardPort: ModuleHostList.forceHTTPStandardPort),
            routingRules: sets.rules, ports: state.ports,
             
             
            caFingerprintSHA256: Self.caFingerprint(in: locations.container),
            reinjectCredentials: state.reinjectCredentials, engineProxyCredentials: state.engineProxyCredentials,
            publishedAt: now(), settings: sets.settings, ruleProviders: sets.providers)
         
         
         
         
        do {
            try ModuleDeviceSettingOverlay(manifest.settings ?? []).publish(to: locations)
        } catch {
            log("module modules' device settings were not written, the ones before stay: \(error.localizedDescription)")
        }
        var changed = true
        if let existing = publishedGlobalManifest() {
            var same = manifest
            same.publishedAt = existing.publishedAt
            changed = same != existing
        }
        if changed {
            manifest.publishedAt = now()
            try write(try ModuleJSON.encoder().encode(manifest), to: locations.globalManifest)
        }
        var root = locations.publishedRoot
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? root.setResourceValues(values)
         
         
         
        if changed || hasOrphans(state) { collectGarbage(keeping: state, published: changed) }
        if changed {
            announce(Self.didChange)
             
             
             
             
            if let group = ClashAppIdentifiers.appGroupContainer, Self.normalized(locations.container) == Self.normalized(group) {
                ModuleEngineSignal.postModulesChanged()
            }
        }
    }

    private func hasOrphans(_ state: ModuleState) -> Bool {
        let files = FileManager.default
        let ids = Set(state.modules.map(\.id))
        let directories = (try? files.contentsOfDirectory(at: locations.publishedRoot, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for entry in directories {
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory, !ids.contains(entry.lastPathComponent) { return true }
        }
        let texts = (try? files.contentsOfDirectory(at: locations.sourcesDirectory, includingPropertiesForKeys: nil)) ?? []
        return texts.contains { !ids.contains($0.deletingPathExtension().lastPathComponent) }
    }

     
     
     
     
     
    static let retiredScriptMinimumAge: TimeInterval = 600
    static let retiredScriptPublications = 2

     
    private struct Retired: Codable, Equatable {
        var since: Date
        var publications: Int
    }

     
     
     
     
     
     
     
     
     
     
     
    private func collectGarbage(keeping state: ModuleState, published: Bool) {
        let files = FileManager.default
        let ids = Set(state.modules.map(\.id))
        decodedIRs = decodedIRs.filter { ids.contains($0.key) || preparing[$0.key] != nil }
        do {
            for entry in (try? files.contentsOfDirectory(at: locations.publishedRoot, includingPropertiesForKeys: [.isDirectoryKey])) ?? [] {
                let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDirectory, !ids.contains(entry.lastPathComponent), preparing[entry.lastPathComponent] == nil {
                    try? files.removeItem(at: entry)
                }
            }
        }
        let retiredFile = locations.stateFile.deletingLastPathComponent().appendingPathComponent("retired-scripts.json")
        let stored = try? Data(contentsOf: retiredFile)
        let decoder = ModuleJSON.decoder()
         
        let before: [String: Retired] = stored.flatMap { try? decoder.decode([String: Retired].self, from: $0) }
            ?? stored.flatMap { try? decoder.decode([String].self, from: $0) }
                .map { Dictionary(uniqueKeysWithValues: $0.map { ($0, Retired(since: now(), publications: 0)) }) }
            ?? [:]
        let current = now()
        var after: [String: Retired] = [:]
         
         
         
        func sweep(_ directory: URL, keeping named: Set<String>, prefix: String) {
            for file in (try? files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            where !named.contains(file.lastPathComponent) {
                let key = prefix + file.lastPathComponent
                guard var retired = before[key] else {
                    after[key] = Retired(since: current, publications: 0)
                    continue
                }
                if published { retired.publications += 1 }
                if retired.publications >= Self.retiredScriptPublications,
                   current.timeIntervalSince(retired.since) > Self.retiredScriptMinimumAge {
                    try? files.removeItem(at: file)
                } else {
                    after[key] = retired
                }
            }
        }
        for id in ids {
            guard preparing[id] == nil else {
                for (key, retired) in before where key.hasPrefix(id + "/") { after[key] = retired }
                continue
            }
            guard let ir = storedIR(id) else { continue }
             
            let held = state.modules.first { $0.id == id }?.heldScriptBodies.values.map(\.sha256) ?? []
            let named = ir.scripts.compactMap(\.bodySHA256) + ir.appScripts.compactMap(\.bodySHA256) + held
            sweep(locations.scriptsDirectory(id), keeping: Set(named.map { $0 + ".js" }), prefix: id + "/")
            sweep(locations.filesDirectory(id), keeping: Set(ir.answerFiles.compactMap(\.sha256)), prefix: id + "/files/")
            sweep(locations.setsDirectory(id), keeping: Set(ir.ruleSets.compactMap(\.sha256)), prefix: id + "/sets/")
        }
        if let data = try? ModuleJSON.encoder().encode(after), data != stored, stored != nil || !after.isEmpty {
            try? write(data, to: retiredFile)
        }
         
         
         
         
        do {
            var named = Set<String>()
            for id in ids { for set in storedIR(id)?.ruleSets ?? [] { if let sha = set.copy?.sha256 { named.insert(sha) } } }
            for kind in [ModuleRuleSetKind.builtInLAN, .builtInSystem] { if let sha = builtInRuleSetCopy(kind) { named.insert(sha) } }
             
             
             
            if let mitm = publishedGlobalManifest()?.mitmHosts {
                for set in ModuleEngineRoute.hostSets(for: ModuleInjection.hostsForTheDocument(mitm).list) { named.insert(set.sha256) }
            }
            for file in (try? files.contentsOfDirectory(at: locations.ruleSetCopiesDirectory,
                                                        includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            where !named.contains(file.lastPathComponent) {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if current.timeIntervalSince(modified) > Self.retiredScriptMinimumAge { try? files.removeItem(at: file) }
            }
        }
        do {
            for file in (try? files.contentsOfDirectory(at: locations.sourcesDirectory, includingPropertiesForKeys: nil)) ?? []
            where !ids.contains(file.deletingPathExtension().lastPathComponent) {
                try? files.removeItem(at: file)
            }
        }
    }

     
     
     
    private func announce(_ name: Notification.Name) {
        let container = Self.normalized(locations.container)
        let userInfo = Self.publishing.map { [Self.originKey: $0.rawValue] }
        Task { @MainActor in NotificationCenter.default.post(name: name, object: container, userInfo: userInfo) }
    }
}

 
 
 
 
 
 
 
 
 
 
 
final class ModuleChangeTakers: @unchecked Sendable {
    static let shared = ModuleChangeTakers()

    private struct Taker {
        let id: ObjectIdentifier
        weak var owner: AnyObject?
         
        let listening: @MainActor () -> Bool
         
        let inFront: @MainActor () -> Bool
         
        let restage: @MainActor () -> Void
         
         
        let busy: @MainActor () -> Bool
         
         
         
        let reconnect: @MainActor () async -> Void
    }

    private let lock = NSLock()
     
    private var takers: [String: [Taker]] = [:]
     
     
    private var askedToRecompose: [String: ModuleStaleComposition] = [:]

    private static func key(_ container: URL) -> String { ModuleStore.normalized(container).path }

     
    func register(_ owner: AnyObject, container: URL, listening: @escaping @MainActor () -> Bool,
                  inFront: @escaping @MainActor () -> Bool, restage: @escaping @MainActor () -> Void = {},
                  busy: @escaping @MainActor () -> Bool = { false },
                  reconnect: @escaping @MainActor () async -> Void = {}) {
        lock.lock(); defer { lock.unlock() }
        let key = Self.key(container), id = ObjectIdentifier(owner)
        takers[key, default: []].removeAll { $0.id == id || $0.owner == nil }
        takers[key, default: []].append(Taker(id: id, owner: owner, listening: listening, inFront: inFront, restage: restage,
                                              busy: busy, reconnect: reconnect))
    }

     
     
     
     
     
    @MainActor
    @discardableResult
    func reconnect(in container: URL) async -> Bool {
        guard let taker = elected(in: container) else { return false }
        await taker.reconnect()
        return true
    }

     
     
     
     
     
     
     
     
     
    @MainActor
    @discardableResult
    func recompose(_ stale: ModuleStaleComposition, in container: URL, fallback: @MainActor () -> Void) -> Bool {
        let taker = elected(in: container)
        if let taker, taker.busy() { return false }
        let key = Self.key(container)
        lock.lock()
        let asked = askedToRecompose[key] == stale
        if !asked { askedToRecompose[key] = stale }
        lock.unlock()
        guard !asked else { return false }
        if let taker { taker.restage() } else { fallback() }
        return true
    }

    func deregister(_ owner: ObjectIdentifier, container: URL) {
        lock.lock(); defer { lock.unlock() }
        let key = Self.key(container)
        takers[key]?.removeAll { $0.id == owner || $0.owner == nil }
        if takers[key]?.isEmpty == true { takers[key] = nil }
    }

     
     
    @MainActor
    private func elected(in container: URL) -> Taker? {
        lock.lock()
        let registered = takers[Self.key(container)] ?? []
        lock.unlock()
        return registered.first { $0.owner != nil && $0.listening() }
    }

     
    @MainActor
    func isElected(_ owner: AnyObject, in container: URL) -> Bool {
        elected(in: container)?.id == ObjectIdentifier(owner)
    }

     
    @MainActor
    func aLiveModelTakesChanges(in container: URL) -> Bool {
        elected(in: container)?.inFront() ?? false
    }
}

 

extension ModuleStore {
     
     
     
     
    func builtInRuleSetCopy(_ kind: ModuleRuleSetKind) -> String? {
        guard let lines = ModuleRuleSetSyntax.builtInLines(kind, platform: platform) else { return nil }
        return try? keepRuleSetCopy(Data((lines.joined(separator: "\n") + "\n").utf8))
    }

     
     
     
    func keepRuleSetCopy(_ data: Data) throws -> String {
        let sha = ModuleJSON.sha256(data)
        let url = locations.ruleSetCopy(sha256: sha)
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.setAttributes([.modificationDate: now()], ofItemAtPath: url.path)
        } else {
            try write(data, to: url)
        }
        return sha
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func adoptRuleSetCopies(_ given: ModuleIR, id: String, previous: ModuleIR?) -> ModuleIR {
        var ir = given
        guard ir.ruleSets.contains(where: { $0.url != nil }) else { return ir }
        var dropped: [(reference: String, reason: ModuleIgnoredReason, origin: ModuleLineOrigin)] = []
        let family: ModuleFormat = ir.manifest.format == .loon ? .loon : .surge
         
         
         
        let room = max(0, min(ModuleRuleSetSyntax.maximumListRuleBytes,
                              ModuleRuleSetSyntax.maximumModuleKeptBytes - ModuleRuleSetSyntax.keptBytes(of: given)))
        var listBytes = 0
        func admit(_ rules: [ModuleRewriteRule]) -> (kept: [ModuleRewriteRule], left: Int) {
            var kept: [ModuleRewriteRule] = []
            for rule in rules {
                let bytes = ModuleRuleSetSyntax.encodedBytes(rule)
                guard listBytes + bytes <= room else { continue }
                listBytes += bytes
                kept.append(rule)
            }
            return (kept, rules.count - kept.count)
        }
        for index in ir.ruleSets.indices {
            var set = ir.ruleSets[index]
            guard set.url != nil else { continue }
            guard let sha = set.sha256, let raw = try? Data(contentsOf: locations.ruleSet(id, sha256: sha)) else {
                if let before = previous?.ruleSets.first(where: { $0.reference == set.reference && $0.copy != nil }), let copy = before.copy,
                   FileManager.default.fileExists(atPath: locations.ruleSetCopy(sha256: copy.sha256).path) {
                    set.copy = copy
                    ir.ruleSets[index] = set
                    let rewrites = admit(previous?.rewriteRules.filter { $0.origin == before.origin } ?? [])
                    ir.rewriteRules += rewrites.kept.map { rule in
                        var moved = rule
                        moved.origin = set.origin
                        return moved
                    }
                    let skipped = copy.skipped + rewrites.left
                    if skipped > 0 { ir.notes.append(ModuleLineNote(sentence: Self.setLinesSkipped(skipped), origin: set.origin)) }
                } else {
                    dropped.append((set.reference, .ruleSetNotDownloadedYet, set.origin))
                }
                continue
            }
            var converted: ModuleRuleSetSyntax.Converted
            var copyData: Data
            switch set.kind {
            case .provider(_, let format) where format == "mrs":
                 
                 
                converted = ModuleRuleSetSyntax.Converted()
                copyData = raw
            case .provider:
                 
                converted = ModuleRuleSetSyntax.convert(String(decoding: raw, as: UTF8.self), kind: set.kind, policy: set.policy,
                                                         origin: set.origin, family: .stash, platform: platform)
                copyData = raw
            default:
                converted = ModuleRuleSetSyntax.convert(String(decoding: raw, as: UTF8.self), kind: set.kind, policy: set.policy,
                                                         origin: set.origin, family: family, platform: platform)
                copyData = Data((converted.kernelLines.joined(separator: "\n") + "\n").utf8)
            }
            if converted.tooHeavy {
                dropped.append((set.reference, .ruleSetTooLarge, set.origin))
                continue
            }
            let rewrites = admit(converted.rewriteRules)
            converted.skipped += rewrites.left
            let copy: String
            do {
                copy = try keepRuleSetCopy(copyData)
            } catch {
                log("module \(id): the copy of \(set.reference) could not be written (\(error.localizedDescription))")
                dropped.append((set.reference, .ruleSetNotDownloadedYet, set.origin))
                continue
            }
            set.copy = ModuleRuleSetCopy(sha256: copy, lines: converted.kernelLines.count, skipped: converted.skipped, held: converted.heapLines)
            ir.ruleSets[index] = set
            ir.rewriteRules += rewrites.kept
            if converted.skipped > 0 { ir.notes.append(ModuleLineNote(sentence: Self.setLinesSkipped(converted.skipped), origin: set.origin)) }
            log("module \(id): \(set.reference) as the kernel reads it: \(converted.kernelLines.count) lines, "
                + "\(rewrites.kept.count) URL rewrites, \(converted.skipped) left out, "
                + "\(converted.heapLines) held, sha256 \(copy)")
        }
        for (reference, reason, origin) in dropped {
            ir = Self.leavingOut(reference, of: ir)
            ir.ignored.append(ModuleIgnoredEntry(text: reference, reason: reason, origin: origin))
            log("module \(id): \(reference) is left out: \(reason.authoredText.englishText)")
        }
        return ir
    }

     
     
     
    static func leavingOut(_ reference: String, of given: ModuleIR) -> ModuleIR {
        var ir = given
        let token = "rule-set:" + reference
        ir.ruleSets.removeAll { $0.reference == reference }
        ir.routingRules.removeAll { $0.head == reference }
        ir.hosts.removeAll { $0.pattern == token }
        ir.edits = ir.edits.compactMap { edit in
            guard edit.path.first == "dns", edit.valueJSON.contains(token), let value = try? OrderedJSON.parse(edit.valueJSON) else { return edit }
            guard let kept = ModuleRuleSetSyntax.renderingSets(value, { $0 == reference ? nil : $0 }), !kept.isEmptyContainer else { return nil }
            var copy = edit
            copy.valueJSON = kept.serialized()
            return copy
        }
        return ir
    }

     
     
     
    static func setLinesSkipped(_ count: Int) -> ModuleSentence {
        .app("Some lines in this rule set were skipped (%@).", arguments: [String(count)])
    }
}

 

extension ModuleStore {
    enum RefreshResult: Equatable {
         
        case updated
         
        case unchanged
         
         
        case superseded
         
        case cancelled
         
         
         
         
         
        case outOfTime
         
        case failed(AuthoredText)
         
        case missing
         
        case listUnreadable
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func refresh(_ id: String, refetchModule: Bool = true, fetchingScripts: Bool = true,
                 movingClocks: Bool = true, readerAsked: Bool = false) async -> RefreshResult {
        let list: ModuleState
        do { list = try state() } catch {
            log("module \(id) was not checked: the module list could not be used right now")
            return .listUnreadable
        }
        guard let record = list.modules.first(where: { $0.id == id }) else { return .missing }
        generations[id, default: 0] += 1
        let mine = generations[id, default: 0]
        let checkedAt = now()
        var link: String?
        if case .url(let address) = record.origin { link = address }
        let movesClock = movingClocks && (link == nil || refetchModule)
        let origin = link.map { " from \($0)" } ?? ""
        do {
            let data: Data
            if let link, refetchModule {
                data = try await downloadModule(try Self.address(link))
            } else {
                do {
                    data = try Data(contentsOf: locations.source(id))
                } catch where Self.isMissingFile(error) {
                     
                     
                     
                    log("module \(id) has no saved copy to read again (\(error.localizedDescription))")
                    throw link == nil ? ModuleStoreError.savedCopyMissing : .linkedCopyMissing
                }
            }
            let previous = publishedModule(id)
            let prepared = try await prepare(data: data, sourceURL: link, fetchedAt: checkedAt, id: id,
                                             previous: previous, previousFetchedAt: record.scriptFetchedAt,
                                             retrying: record, fetchingScripts: fetchingScripts, readerAsked: readerAsked)
            guard generations[id] == mine else { return .superseded }
            var updated = record
            if movesClock {
                updated.lastCheckedAt = checkedAt
                updated.lastFailure = nil
                updated.linkFailureCount = 0
            }
            updated.absorb(prepared)
             
             
            updated.name = Self.name(of: prepared.ir, fallback: Self.fallbackName(of: record))
            if let previous, Self.sameContent(previous, prepared.ir) {
                 
                 
                 
                for (sha, body) in prepared.bodies where !FileManager.default.fileExists(atPath: locations.script(id, sha256: sha).path) {
                    try write(body, to: locations.script(id, sha256: sha))
                }
                 
                 
                let digest = ModuleJSON.sha256(data)
                if digest != record.sourceSHA256 || !FileManager.default.fileExists(atPath: locations.source(id).path) {
                    try write(data, to: locations.source(id))
                    updated.sourceSHA256 = digest
                }
                try note(updated)
                if prepared.ranOutOfTime {
                    log("module \(id) checked in part\(origin): the background task's time ran out; the rest is checked next time")
                    return .outOfTime
                }
                return .unchanged
            }
            if movingClocks { updated.lastUpdatedAt = checkedAt }
            updated.sourceSHA256 = ModuleJSON.sha256(data)
            guard try commit(updated, ir: prepared.ir, source: data, bodies: prepared.bodies, isNew: false) else {
                log("module \(id) was gone when its update came to be written; nothing was written")
                return .superseded
            }
            log("module \(id) updated\(origin): \(prepared.ir.effectiveCount) kept, \(prepared.ir.ignoredCount) set aside")
            if prepared.ranOutOfTime {
                log("module \(id) updated in part: the background task's time ran out; the rest is checked next time")
                return .outOfTime
            }
            return .updated
        } catch {
            if Self.isCancellation(error) { return .cancelled }
             
             
            if isOutOfTime(error) {
                log("module \(id) was not checked\(origin): the background task's time ran out")
                return .outOfTime
            }
            guard generations[id] == mine else { return .superseded }
            let failure = Self.updateFailureText(for: error, linked: link != nil)
            var failed = record
            if movesClock { failed.lastCheckedAt = checkedAt }
             
            if link != nil, refetchModule { failed.linkFailureCount += 1 }
            failed.lastFailure = failure
            try? note(failed)
             
            let count = (error as? ModuleRefusal).flatMap { refusal -> String? in
                if case .tooLarge(let bytes) = refusal { return " (\(bytes) bytes)" } else { return nil }
            } ?? ""
            log("module \(id) was not updated\(origin): \(failure.englishText)\(count); the published copy stays")
            return .failed(failure)
        }
    }

     
     
     
     
     
     
     
     
     
     
    @discardableResult
    func refreshDue(announcedAs origin: AnnouncementOrigin?) async -> [String: RefreshResult] {
        await Self.$publishing.withValue(origin) { await refreshEachDue() }
    }

     
     
     
     
     
     
    private var scanCursorFile: URL { locations.stateFile.deletingLastPathComponent().appendingPathComponent("scan-cursor.json") }

    func scanCursor() -> String? {
        guard let data = try? Data(contentsOf: scanCursorFile) else { return nil }
        return try? JSONDecoder().decode(String.self, from: data)
    }

    private func setScanCursor(_ id: String?) {
        guard id != scanCursor() else { return }
        if let id, let data = try? JSONEncoder().encode(id) {
            try? write(data, to: scanCursorFile)
        } else {
            try? FileManager.default.removeItem(at: scanCursorFile)
        }
    }

    private func refreshEachDue() async -> [String: RefreshResult] {
         
         
        guard let first = try? state(), first.modules.contains(where: \.enabled) else { return [:] }
        var results: [String: RefreshResult] = [:]
        var order = first.modules.filter(\.enabled)
        let cursor = scanCursor()
        if let cursor, let at = order.firstIndex(where: { $0.id == cursor }) {
            order = Array(order[(at + 1)...] + order[...at])
        }
         
        var reached: String?
        var stoppedShort = false
        scriptDownloadsLeft = Self.scriptDownloadsPerScan
        defer {
            scriptDownloadsLeft = nil
            if stoppedShort { setScanCursor(reached ?? cursor) } else { setScanCursor(nil) }
        }
        for listed in order {
            if Task.isCancelled { stoppedShort = true; break }
            let current: ModuleState
            do { current = try state() } catch {
                log("module modules were not checked: the module list could not be used right now (\(error))")
                break
            }
            guard let record = current.modules.first(where: { $0.id == listed.id }), record.enabled else { continue }
             
             
            let fetchingScripts = current.enabled
            let due = isDue(record)
             
             
             
            guard due.module || due.sets || (runsScripts && due.appScripts)
                    || (fetchingScripts && ((runsScripts && due.scripts) || due.files)) else { continue }
             
             
            if let left = timeLeft(), left < Self.moduleTimeFloor {
                log("module modules were not all checked: the background task had \(Int(max(0, left))) s left")
                results[record.id] = .outOfTime
                stoppedShort = true
                break
            }
            reached = record.id
            let result = await refresh(record.id, refetchModule: due.module, fetchingScripts: fetchingScripts)
            results[record.id] = result
            if result == .cancelled || result == .outOfTime { stoppedShort = true; break }
        }
        return results
    }

     
     
     
     
     
    static func retryDelay(failures: Int, interval: Int) -> TimeInterval {
        let doubled = 3600.0 * pow(2.0, Double(max(0, min(failures - 1, 20))))
        return min(doubled, TimeInterval(interval > 0 ? interval : ModuleLineSyntax.defaultScriptUpdateInterval))
    }

     
     
     
     
     
     
     
     
     
     
    func isDue(_ record: ModuleRecord) -> (module: Bool, scripts: Bool, files: Bool, sets: Bool, appScripts: Bool) {
        let current = now()
        var module = false
        if case .url = record.origin {
            let wait = record.linkFailureCount > 0
                ? Self.retryDelay(failures: record.linkFailureCount, interval: record.updateInterval)
                : TimeInterval(record.updateInterval)
            module = record.lastCheckedAt.map { current.timeIntervalSince($0) >= wait } ?? true
             
             
             
            if !module, record.linkFailureCount == 0,
               !FileManager.default.fileExists(atPath: locations.source(record.id).path) { module = true }
        }
        guard let published = publishedModule(record.id) else { return (module, false, false, false, false) }
        func due(_ address: String, interval: Int) -> Bool {
            if let failures = record.scriptFailureCount[address], failures > 0, let at = record.scriptAttemptedAt[address] {
                return current.timeIntervalSince(at) >= Self.retryDelay(failures: failures, interval: interval)
            }
            guard let at = record.scriptFetchedAt[address] else { return true }
            return current.timeIntervalSince(at) >= ModuleLineSyntax.scriptCheckInterval(interval)
        }
        let passed = published.scripts.contains { due($0.scriptURL, interval: $0.updateInterval) }
         
         
         
        let appPassed = published.appScripts.contains { due($0.scriptURL, interval: $0.updateInterval) }
        let appSetAside = published.ignored.contains { entry in
            guard case .scriptDownloadFailed = entry.reason, record.appScriptAddresses.contains(entry.text) else { return false }
            return due(entry.text, interval: record.updateInterval)
        }
        let setAside = published.ignored.contains { entry in
            guard case .scriptDownloadFailed = entry.reason else { return false }
            return due(entry.text, interval: record.updateInterval)
        }
        let setPrefix = ModuleResourceFetcher.Place.sets.rawValue + " "
        var setIntervals: [String: Int] = [:]
        for set in published.ruleSets {
            guard let url = set.url else { continue }
            let own = Self.setInterval(set.interval, module: record.updateInterval)
            setIntervals[url] = min(setIntervals[url] ?? own, own)
        }
        var files = false, sets = false
        var retrying = Set<String>()
        for (key, state) in record.fileStates {
            let isSet = key.hasPrefix(setPrefix)
            let interval = isSet ? setIntervals[String(key.dropFirst(setPrefix.count))] ?? record.updateInterval : record.updateInterval
            if isSet, state.failures > 0 { retrying.insert(String(key.dropFirst(setPrefix.count))) }
            guard Self.fileIsDue(state, interval: interval, retryInterval: Self.retryInterval(interval, module: record.updateInterval),
                                 now: current) else { continue }
            if isSet { sets = true } else { files = true }
        }
         
        if published.answerFiles.contains(where: { reference in
            reference.sha256 == nil && record.fileStates[Self.fileKey(.files, reference.url, base64: reference.base64 == true)] == nil
        }) { files = true }
        if published.ruleSets.contains(where: { set in
            guard let url = set.url else { return false }
            return set.sha256 == nil && record.fileStates[Self.fileKey(.sets, url)] == nil
        }) { sets = true }
         
         
         
        if published.ignored.contains(where: { entry in
            entry.reason == .ruleSetNotDownloadedYet && !retrying.contains(Self.listAddress(entry.text))
        }) { sets = true }
         
         
         
         
         
        let readAgain = published.ignored.contains { $0.reason == .scriptAddressNotSecure }
            || ModuleRuleMapping.listingPlainHTTPHosts(published).forceHTTPEngineHostLines.count != published.forceHTTPEngineHostLines.count
        return (module, setAside || passed || appPassed || readAgain, files, sets, appPassed || appSetAside || readAgain)
    }

     
     
     
    static func listAddress(_ text: String) -> String {
        for head in ["RULE-SET,", "DOMAIN-SET,"] where text.hasPrefix(head) { return String(text.dropFirst(head.count)) }
        return text
    }

     
     
     
     
     
     
    static func sameContent(_ a: ModuleIR, _ b: ModuleIR) -> Bool {
        let held = sentence(scriptHeld)
        func plain(_ ir: ModuleIR) -> ModuleIR {
            var out = ir
            out.manifest.fetchedAt = nil
            for index in out.ignored.indices {
                if case .scriptDownloadFailed(let said) = out.ignored[index].reason, said != held {
                    out.ignored[index].reason = .scriptDownloadFailed(.verbatim(""))
                }
                if case .fileDownloadFailed = out.ignored[index].reason { out.ignored[index].reason = .fileDownloadFailed(.verbatim("")) }
            }
            return out
        }
        return plain(a) == plain(b)
    }
}

 

extension ModuleLineSyntax.DeclaredScript {
    var name: String {
        switch self {
        case .http(let script): return script.name
        case .app(let script): return script.name
        }
    }

    var scriptURL: String {
        switch self {
        case .http(let script): return script.scriptURL
        case .app(let script): return script.scriptURL
        }
    }

    var updateInterval: Int {
        switch self {
        case .http(let script): return script.updateInterval
        case .app(let script): return script.updateInterval
        }
    }

    var origin: ModuleLineOrigin {
        switch self {
        case .http(let script): return script.origin
        case .app(let script): return script.origin
        }
    }

    var bodySHA256: String? {
        get {
            switch self {
            case .http(let script): return script.bodySHA256
            case .app(let script): return script.bodySHA256
            }
        }
        set {
            switch self {
            case .http(var script):
                script.bodySHA256 = newValue
                self = .http(script)
            case .app(var script):
                script.bodySHA256 = newValue
                self = .app(script)
            }
        }
    }

     
    var isApp: Bool { app != nil }
}

 

extension ModuleStore {
     
     
    var scriptStore: ModuleScriptStore {
        ModuleScriptStore(directory: locations.container.appendingPathComponent(ModuleScriptStore.directoryName, isDirectory: true),
                          log: log)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func setArgumentValue(_ value: String?, for name: String, module id: String) async throws {
        settle()
        if let value, value.unicodeScalars.contains(where: { $0 == "\r" || $0 == "\n" }) {
            throw ModuleStoreError.argumentValueHasALineBreak
        }
        var state = try loadForWrite()
        guard let index = state.modules.firstIndex(where: { $0.id == id }) else { throw ModuleStoreError.moduleGone }
        guard let setting = storedIR(id)?.manifest.arguments.first(where: { $0.name == name }) else {
            log(#"module \#(id): no setting \#(name) to set"#)
            return
        }
        switch setting.kind {
        case .storedChoice, .storedInput:
            if let given = value.flatMap({ $0.isEmpty ? nil : $0 }) {
                guard scriptStore.writeShared(given, key: name) else {
                    log(#"module \#(id): its stored value \#(name) could not be written"#)
                    return
                }
                state.modules[index].storedValues[name] = given
            } else {
                removeStoredValue(name, of: &state.modules[index])
            }
            try save(state)
        case .text, .toggle, .choice, .input:
            guard state.modules[index].argumentValues[name] != value else { return }
            state.modules[index].argumentValues[name] = value
            try save(state)
            try await publishWithItsValues(id)
        }
    }

     
     
     
     
    func resetArguments(module id: String) async throws {
        settle()
        var state = try loadForWrite()
        guard let index = state.modules.firstIndex(where: { $0.id == id }) else { throw ModuleStoreError.moduleGone }
        for setting in storedIR(id)?.manifest.arguments ?? [] {
            switch setting.kind {
            case .storedChoice(let options):
                guard let first = options.first else { continue }
                 
                 
                 
                if let current = scriptStore.readShared(key: setting.name), current != state.modules[index].storedValues[setting.name] {
                    log(#"module \#(id): the stored value of its setting \#(setting.name) is not one it wrote; left on reset"#)
                } else if scriptStore.writeShared(first, key: setting.name) {
                    state.modules[index].storedValues[setting.name] = first
                } else {
                    log(#"module \#(id): its stored value \#(setting.name) could not be written"#)
                }
            case .storedInput:
                removeStoredValue(setting.name, of: &state.modules[index])
            default:
                break
            }
        }
        let hadValues = !state.modules[index].argumentValues.isEmpty
        state.modules[index].argumentValues = [:]
        try save(state)
        if hadValues { try await publishWithItsValues(id) }
    }

     
     
     
     
    private func removeStoredValue(_ key: String, of record: inout ModuleRecord) {
        guard let wrote = record.storedValues.removeValue(forKey: key), scriptStore.readShared(key: key) == wrote else { return }
        if !scriptStore.writeShared(nil, key: key) {
            log(#"module \#(record.id): its stored value \#(key) could not be removed"#)
        }
    }

     
     
     
     
    private func publishWithItsValues(_ id: String) async throws {
         
         
        switch await refresh(id, refetchModule: false, fetchingScripts: false, movingClocks: false) {
        case .missing: throw ModuleStoreError.moduleGone
        case .listUnreadable: throw ModuleStoreError.stateUnreadable(.readFailed)
        default: return
        }
    }

     
     
     
     
     
     
    func seedStoredChoices(_ record: inout ModuleRecord, ir: ModuleIR) {
        let store = scriptStore
        for setting in ir.manifest.arguments where record.storedValues[setting.name] == nil {
            guard case .storedChoice(let options) = setting.kind, let first = options.first,
                  store.readShared(key: setting.name) == nil else { continue }
            guard store.writeShared(first, key: setting.name) else {
                log(#"module \#(record.id): its stored value \#(setting.name) could not be seeded"#)
                continue
            }
            record.storedValues[setting.name] = first
        }
    }
}

 

extension ModuleStore {
     
     
     
     
     
     
     
     
     
     
     
    @discardableResult
    func restore(_ section: ModuleBackupSection) async -> [String] {
        settle()
        guard section.schemaVersion <= ModuleBackupSection.currentSchemaVersion else {
            log("module modules not restored: the backup's section is version \(section.schemaVersion)")
            return section.modules.map(\.name)
        }
        var failed: [String] = []
        let decrypting = (try? loadForWrite().enabled) ?? false
        for module in section.modules {
            do {
                if try hasModule(like: module) { continue }
                let id = UUID().uuidString.lowercased()
                let at = now()
                var link: String?
                if case .url(let value) = module.origin { link = value }
                var source = module.source
                if source.isEmpty, let link { source = try await downloadModule(Self.address(link)) }
                let prepared = try await prepare(data: source, sourceURL: link, fetchedAt: at, id: id,
                                                 previous: nil, previousFetchedAt: [:], fetchingScripts: decrypting,
                                                 argumentValues: module.argumentValues ?? [:])
                 
                 
                if try hasModule(like: module) { continue }
                var record = ModuleRecord(
                    id: id, origin: module.origin, enabled: module.enabled, name: module.name,
                    updateInterval: module.updateInterval, lastCheckedAt: nil,
                    lastUpdatedAt: module.source.isEmpty ? at : module.lastUpdatedAt,
                    lastFailure: nil, scriptFetchedAt: prepared.scriptFetchedAt, sourceSHA256: ModuleJSON.sha256(source))
                record.absorb(prepared)
                 
                 
                 
                record.argumentValues = module.argumentValues ?? [:]
                record.label = module.label
                let store = scriptStore
                for (key, value) in (module.storedValues ?? [:]).sorted(by: { $0.key < $1.key }) where store.readShared(key: key) == nil {
                    guard store.writeShared(value, key: key) else {
                        log(#"module \#(id): its stored value \#(key) could not be restored"#)
                        continue
                    }
                    record.storedValues[key] = value
                }
                try commit(record, ir: prepared.ir, source: source, bodies: prepared.bodies, isNew: true)
                log("module \(id) restored from a backup: \(module.name), \(prepared.ir.effectiveCount) kept, \(prepared.ir.ignoredCount) set aside")
            } catch {
                failed.append(module.name)
                log("module \(module.name) not restored from a backup: \(error.localizedDescription)")
            }
        }
        return failed
    }

    private func hasModule(like module: ModuleBackupSection.Module) throws -> Bool {
        let carried = ModuleJSON.sha256(module.source)
        return try loadForWrite().modules.contains { record in
            switch (record.origin, module.origin) {
            case (.url(let mine), .url(let theirs)):
                return mine == theirs
            case (.local, .local):
                let kept = record.sourceSHA256 ?? (try? Data(contentsOf: locations.source(record.id))).map(ModuleJSON.sha256)
                return kept == carried
            default:
                return false
            }
        }
    }
}
