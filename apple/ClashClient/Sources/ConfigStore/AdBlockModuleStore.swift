import ClashClientKit
import Foundation

 
 
 
 
struct AdBlockModuleLocations: Equatable, Sendable {
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

     
    static var production: AdBlockModuleLocations? {
        ClashAppIdentifiers.appGroupContainer.map(AdBlockModuleLocations.init(container:))
    }
}

 
struct AdBlockModuleRecord: Equatable, Identifiable, Sendable {
     
     
     
     
     
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
     
     
     
    var fileStates: [String: AdBlockFileState] = [:]
    var schemaVersion = AdBlockModuleRecord.currentSchemaVersion
     
     
     
    var failureFromALaterBuild = false
}

 
 
 
 
struct AdBlockFileState: Codable, Equatable, Sendable {
    var sha256: String?
    var fetchedAt: Date?
    var attemptedAt: Date?
     
     
    var failures = 0
    var etag: String?
    var lastModified: String?
}

extension AdBlockModuleRecord.Origin: Codable {
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

extension AdBlockModuleRecord: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, origin, enabled, name, updateInterval, lastCheckedAt, lastUpdatedAt, lastFailure
        case scriptFetchedAt, sourceSHA256, scriptAttemptedAt, scriptFailureCount, linkFailureCount, fileStates, schemaVersion
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
        updateInterval = try c.decodeIfPresent(Int.self, forKey: .updateInterval) ?? AdBlockLineSyntax.defaultScriptUpdateInterval
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
        fileStates = (try? c.decodeIfPresent([String: AdBlockFileState].self, forKey: .fileStates)) ?? [:]
        schemaVersion = version
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(origin, forKey: .origin)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(name, forKey: .name)
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
        try c.encode(schemaVersion, forKey: .schemaVersion)
    }

     
    static let knownKeys: Set<String> = Set(["id", "origin", "enabled", "name", "updateInterval", "lastCheckedAt", "lastUpdatedAt",
                                              "lastFailure", "scriptFetchedAt", "sourceSHA256", "scriptAttemptedAt",
                                              "scriptFailureCount", "linkFailureCount", "fileStates", "schemaVersion"])
}

extension AdBlockModuleRecord {
     
     
    var isUnprotectedLink: Bool {
        guard case .url(let link) = origin else { return false }
        return link.hasPrefix("http://")
    }

     
     
     
    mutating func adopt(refreshOwnedFieldsOf other: AdBlockModuleRecord) {
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
    }

     
    mutating func absorb(_ prepared: AdBlockModuleStore.Prepared) {
        scriptFetchedAt = prepared.scriptFetchedAt
        for (address, at) in prepared.attemptedAt {
            scriptAttemptedAt[address] = at
            if prepared.failedAddresses.contains(address) {
                scriptFailureCount[address, default: 0] += 1
            } else {
                scriptFailureCount[address] = nil
            }
        }
        let current = Set(prepared.ir.scripts.map(\.scriptURL)).union(prepared.failedAddresses).union(prepared.waiting)
        scriptAttemptedAt = scriptAttemptedAt.filter { current.contains($0.key) }
        scriptFailureCount = scriptFailureCount.filter { current.contains($0.key) }
        fileStates = prepared.fileStates
    }
}

struct AdBlockModuleState: Equatable, Sendable {
     
     
     
    static let currentSchemaVersion = 1

     
     
     
     
    var enabled = false
    var modules: [AdBlockModuleRecord] = []
    var ports: AdBlockPorts?
     
     
     
     
    var reinjectCredentials: AdBlockReinjectCredentials?
     
     
    var engineProxyCredentials: AdBlockEngineProxyCredentials?
    var schemaVersion = AdBlockModuleState.currentSchemaVersion

     
    mutating func drawCredentials() {
        let listener = AdBlockReinjectCredentials.random()
        var engine = AdBlockEngineProxyCredentials.random()
        while engine == listener { engine = .random() }
        reinjectCredentials = listener
        engineProxyCredentials = engine
    }

     
     
    mutating func drawEngineCredentialsIfUnusable() {
        guard engineProxyCredentials?.isWellFormed != true || engineProxyCredentials == reinjectCredentials else { return }
        var engine = AdBlockEngineProxyCredentials.random()
        while engine == reinjectCredentials { engine = .random() }
        engineProxyCredentials = engine
    }
}

extension AdBlockModuleState: Codable {
    private enum CodingKeys: String, CodingKey { case enabled, modules, ports, reinjectCredentials, engineProxyCredentials, schemaVersion }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard version <= Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: c, debugDescription: "schema \(version)")
        }
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        modules = try c.decodeIfPresent([AdBlockModuleRecord].self, forKey: .modules) ?? []
        ports = try c.decodeIfPresent(AdBlockPorts.self, forKey: .ports)
        reinjectCredentials = try c.decodeIfPresent(AdBlockReinjectCredentials.self, forKey: .reinjectCredentials)
        engineProxyCredentials = try c.decodeIfPresent(AdBlockEngineProxyCredentials.self, forKey: .engineProxyCredentials)
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
            pairs = merged(pairs, before, known: AdBlockModuleRecord.knownKeys)
            if let origin = pairs.firstIndex(where: { $0.key == "origin" }), case .object(let now) = pairs[origin].value,
               case .object(let was)? = value("origin", in: before) {
                if case .string(let kind)? = value("kind", in: was), !AdBlockModuleRecord.Origin.knownKinds.contains(kind) {
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
        let decoder = AdBlockJSON.decoder()
        if let top = try? decoder.decode(Version.self, from: data), (top.schemaVersion ?? 1) > currentSchemaVersion { return true }
        let records = (try? decoder.decode(Records.self, from: data))?.modules ?? []
        return records.contains { ($0.schemaVersion ?? 1) > AdBlockModuleRecord.currentSchemaVersion }
    }
}

extension AdBlockModuleStoreError {
     
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
        }
    }
}

 
enum AdBlockModuleStoreError: Error, Equatable, Sendable {
     
     
     
     
     
     
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
}

 
 
 
 
 
 
actor AdBlockModuleStore {
     
     
     
    static let didChange = Notification.Name("ClashAdBlockModulesDidChange")
     
    static let recordsDidChange = Notification.Name("ClashAdBlockModuleRecordsDidChange")
     
     
     
     
     
    enum AnnouncementOrigin: String, Sendable {
        case scheduledRefresh = "scheduled-refresh"
    }
    static let originKey = "origin"

     
     
    static func isScheduledRefresh(_ note: Notification) -> Bool {
        (note.userInfo?[originKey] as? String) == AnnouncementOrigin.scheduledRefresh.rawValue
    }

     
     
     
     
    @TaskLocal static var publishing: AnnouncementOrigin?

     
     
    static let maximumScriptBytes = 4 << 20
    static let defaultUpdateInterval = AdBlockLineSyntax.defaultScriptUpdateInterval
    static let portRange: ClosedRange<UInt16> = 42_000...48_999

     
     
     
    nonisolated static func shared(_ container: URL) -> AdBlockModuleStore {
        registry.store(for: container)
    }

     
     
    static func normalized(_ url: URL) -> URL { url.resolvingSymlinksInPath().standardizedFileURL }

    private static let registry = Registry()

    private final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var stores: [String: AdBlockModuleStore] = [:]

        func store(for container: URL) -> AdBlockModuleStore {
            let key = AdBlockModuleStore.normalized(container).path
            lock.lock()
            defer { lock.unlock() }
            if let existing = stores[key] { return existing }
            let made = AdBlockModuleStore(locations: AdBlockModuleLocations(container: container))
            stores[key] = made
            return made
        }
    }

     
    nonisolated let locations: AdBlockModuleLocations
    private let fetcher: HTTPFetching
    private let now: () -> Date
    private let platform: AdBlockPlatform
    private let randomPort: () -> UInt16
    private let check: AdBlockRuleMapping.Check
    private let log: (String) -> Void
     
     
     
    private let writeFile: (Data, URL, Data.WritingOptions) throws -> Void

    init(locations: AdBlockModuleLocations,
         fetcher: HTTPFetching = ResourceDownloader.verified(),
         now: @escaping () -> Date = Date.init,
         platform: AdBlockPlatform = .current,
         randomPort: @escaping () -> UInt16 = { UInt16.random(in: AdBlockModuleStore.portRange) },
         check: @escaping AdBlockRuleMapping.Check = AdBlockRuleMapping.kernelCheck,
         log: @escaping (String) -> Void = { ClashLogStore.shared.append($0, stream: .app) },
         writeFile: @escaping (Data, URL, Data.WritingOptions) throws -> Void = { try $0.write(to: $1, options: $2) },
         runsScripts: Bool = AdBlockModuleStore.scriptHostRuns) {
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

     
     
     
     
     
     
    static let scriptHostRuns = false
     
     
    private(set) var runsScripts: Bool

    func allowScripts(_ runs: Bool) { runsScripts = runs }

    static let scriptHeld = AuthoredText.app("This script can't be used, so it was skipped.")

     
    static func isDownloadSentence(_ reason: AdBlockIgnoredReason) -> Bool {
        if case .scriptDownloadFailed = reason { return true }
        return false
    }

     
     
    func downloadsFromVerifiedServers() -> Bool {
        (fetcher as? ResourceDownloader)?.serverTrust == .verified
    }

     

    private var settled = false
     
     
     
    private var generations: [String: Int] = [:]
     
     
     
     
     
    private var editSequences: [String: Int] = [:]
     
     
     
    private var preparing: [String: Int] = [:]

     
     
     
    func publishedModule(_ id: String) -> AdBlockModuleIR? {
        settle()
        return storedIR(id)
    }

     
    private func storedIR(_ id: String) -> AdBlockModuleIR? {
        guard let data = try? Data(contentsOf: locations.moduleManifest(id)) else { return nil }
        return try? AdBlockJSON.decoder().decode(AdBlockModuleIR.self, from: data)
    }

     
     
     
     
     
    private func publishedIR(of record: AdBlockModuleRecord) -> (data: Data, ir: AdBlockModuleIR)? {
        let url = locations.moduleManifest(record.id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let ir = try? AdBlockJSON.decoder().decode(AdBlockModuleIR.self, from: data),
           ir.schemaVersion == AdBlockModuleIR.currentSchemaVersion {
            return (data, ir)
        }
        guard readAgainFromSavedText(record, earlier: data), let again = try? Data(contentsOf: url),
              let ir = try? AdBlockJSON.decoder().decode(AdBlockModuleIR.self, from: again),
              ir.schemaVersion == AdBlockModuleIR.currentSchemaVersion else { return nil }
        return (again, ir)
    }

     
     
     
     
     
     
     
     
    private func readAgainFromSavedText(_ record: AdBlockModuleRecord, earlier data: Data) -> Bool {
         
        struct Version: Decodable { let schemaVersion: Int }
        guard let version = (try? AdBlockJSON.decoder().decode(Version.self, from: data))?.schemaVersion,
              version < AdBlockModuleIR.currentSchemaVersion else { return false }
        guard let source = try? Data(contentsOf: locations.source(record.id)) else {
            log("ad-block module \(record.id) was published in IR \(version) and has no saved copy to read again; it is left out until it is updated")
            return false
        }
         
        let earlier = try? AdBlockJSON.decoder().decode(AdBlockModuleIR.self, from: data)
        var link: String?
        if case .url(let address) = record.origin { link = address }
        var ir: AdBlockModuleIR
        do {
            switch try AdBlockModuleParser.parse(source, sourceURL: link, fetchedAt: earlier?.manifest.fetchedAt,
                                                 platform: platform, check: check) {
            case .success(let parsed): ir = parsed
            case .failure(let refusal):
                log("ad-block module \(record.id) was published in IR \(version), and its saved copy is not read as a module now (\(refusal)); it is left out until it is updated")
                return false
            }
        } catch {
            log("ad-block module \(record.id) was published in IR \(version) and could not be read again now (\(error.localizedDescription))")
            return false
        }
        let scripts = ir.scripts
        ir.scripts = []
        for var script in scripts {
            let address = script.scriptURL
            if let sha = earlier?.scripts.first(where: { $0.scriptURL == address && $0.bodySHA256 != nil })?.bodySHA256,
               FileManager.default.fileExists(atPath: locations.script(record.id, sha256: sha).path) {
                script.bodySHA256 = sha
                ir.scripts.append(script)
            } else if let setAside = earlier?.ignored.first(where: { $0.text == address && $0.origin == script.origin }),
                      runsScripts || !Self.isDownloadSentence(setAside.reason) {
                 
                 
                 
                ir.ignored.append(AdBlockIgnoredEntry(text: address, reason: setAside.reason, origin: script.origin))
            } else {
                let sentence = runsScripts ? Self.notDownloadedYet : Self.scriptHeld
                ir.ignored.append(AdBlockIgnoredEntry(text: address, reason: .scriptDownloadFailed(Self.sentence(sentence)),
                                                      origin: script.origin))
            }
        }
         
         
         
         
        if let earlier {
            ir = carryingDownloads(of: earlier, into: ir, id: record.id)
            ir = adoptRuleSetCopies(ir, id: record.id, previous: earlier)
        }
        do {
            try write(try AdBlockJSON.encoder().encode(ir), to: locations.moduleManifest(record.id))
        } catch {
            log("ad-block module \(record.id) was read again from its saved copy, and its IR could not be written (\(error.localizedDescription))")
            return false
        }
        log("ad-block module \(record.id) was published in IR \(version): read again from its saved copy, nothing downloaded")
        return true
    }

     
     
     
     
     
     
     
    private func carryingDownloads(of earlier: AdBlockModuleIR, into given: AdBlockModuleIR, id: String) -> AdBlockModuleIR {
        var ir = given
        func here(_ sha: String?, _ place: AdBlockModuleResourceFetcher.Place) -> Bool {
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
         
        func carried(_ action: AdBlockRewriteAction, from before: AdBlockRewriteAction) -> AdBlockRewriteAction? {
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

    func publishedGlobalManifest() -> AdBlockGlobalManifest? {
        guard let data = try? Data(contentsOf: locations.globalManifest) else { return nil }
        return try? AdBlockJSON.decoder().decode(AdBlockGlobalManifest.self, from: data)
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

     
     
     
     
    private func switchOffWithoutTheList(_ refusal: AdBlockModuleStoreError) throws {
        guard FileManager.default.fileExists(atPath: locations.globalManifest.path) else { return }
        guard var manifest = publishedGlobalManifest() else { throw refusal }
        guard manifest.enabled else { return }
        manifest.enabled = false
        manifest.publishedAt = now()
        try write(try AdBlockJSON.encoder().encode(manifest), to: locations.globalManifest)
        log("ad blocking was switched off with a module list this build cannot use (\(refusal)); the list is left as it is")
        announce(Self.didChange)
    }

    func setModule(_ id: String, enabled: Bool) throws {
        settle()
        var state = try loadForWrite()
        guard let index = state.modules.firstIndex(where: { $0.id == id }),
              state.modules[index].enabled != enabled else { return }
        state.modules[index].enabled = enabled
        try save(state)
        try publish(state)
    }

    func remove(_ id: String) throws {
        settle()
        var state = try loadForWrite()
        guard state.modules.contains(where: { $0.id == id }) else { return }
        state.modules.removeAll { $0.id == id }
        generations[id, default: 0] += 1
        try save(state)
        try? FileManager.default.removeItem(at: locations.source(id))
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
        guard case .ready(_, let metadata) = AdBlockCAFiles.status(AdBlockEngineLocations.of(container)) else { return nil }
        return metadata.fingerprintSHA256
    }

     
     
    func republish() throws {
        try publish(try state())
    }

     
    @discardableResult
    func add(url raw: String) async throws -> AdBlockModuleRecord {
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
        var record = AdBlockModuleRecord(
            id: id, origin: .url(link), enabled: true, name: Self.name(of: prepared.ir, fallback: address.host ?? link),
            updateInterval: Self.defaultUpdateInterval, lastCheckedAt: fetchedAt, lastUpdatedAt: fetchedAt,
            lastFailure: nil, scriptFetchedAt: prepared.scriptFetchedAt, sourceSHA256: AdBlockJSON.sha256(data))
        record.absorb(prepared)
        try commit(record, ir: prepared.ir, source: data, bodies: prepared.bodies, isNew: true)
        log("ad-block module \(id) added from \(link): \(prepared.ir.effectiveCount) kept, \(prepared.ir.ignoredCount) set aside")
        if record.isUnprotectedLink { log("ad-block module \(id) is read over plain http, as the reader typed \(link)") }
        return record
    }

     
    @discardableResult
    func add(text: String) async throws -> AdBlockModuleRecord {
        try await saveLocalModule(id: nil, text: text)
    }

     
     
     
     
     
     
     
     
     
     
     
     
    @discardableResult
    func saveLocalModule(id: String?, text: String) async throws -> AdBlockModuleRecord {
        settle()
        let data = Data(text.utf8)
        let at = now()
        guard let id else {
            let id = UUID().uuidString.lowercased()
            let prepared = try await prepare(data: data, sourceURL: nil, fetchedAt: at, id: id,
                                             previous: nil, previousFetchedAt: [:])
            var record = AdBlockModuleRecord(
                id: id, origin: .local, enabled: true, name: Self.name(of: prepared.ir, fallback: ""),
                updateInterval: Self.defaultUpdateInterval, lastCheckedAt: at, lastUpdatedAt: at,
                lastFailure: nil, scriptFetchedAt: prepared.scriptFetchedAt, sourceSHA256: AdBlockJSON.sha256(data))
            record.absorb(prepared)
            try commit(record, ir: prepared.ir, source: data, bodies: prepared.bodies, isNew: true)
            log("ad-block module \(id) added as a local module: \(prepared.ir.effectiveCount) kept, \(prepared.ir.ignoredCount) set aside")
            return record
        }
        editSequences[id, default: 0] += 1
        let edit = editSequences[id, default: 0]
        let editable = try editableLocalModule(id)
        let prepared = try await prepare(data: data, sourceURL: nil, fetchedAt: at, id: id,
                                         previous: publishedModule(id), previousFetchedAt: editable.scriptFetchedAt,
                                         retrying: editable)
         
         
        guard editSequences[id] == edit else {
            log("ad-block module \(id): an edit was overtaken by a later one and was not written")
            throw AdBlockModuleStoreError.editSuperseded
        }
         
         
        var record = try editableLocalModule(id)
        record.name = Self.name(of: prepared.ir, fallback: record.name)
        record.lastCheckedAt = at
        record.lastUpdatedAt = at
        record.lastFailure = nil
        record.sourceSHA256 = AdBlockJSON.sha256(data)
        record.absorb(prepared)
         
         
        generations[id, default: 0] += 1
        guard try commit(record, ir: prepared.ir, source: data, bodies: prepared.bodies, isNew: false) else {
            throw AdBlockModuleStoreError.moduleGone
        }
        log("ad-block module \(id) edited: \(prepared.ir.effectiveCount) kept, \(prepared.ir.ignoredCount) set aside")
        return try state().modules.first { $0.id == id } ?? record
    }

     
     
    private func editableLocalModule(_ id: String) throws -> AdBlockModuleRecord {
        guard let record = try state().modules.first(where: { $0.id == id }) else { throw AdBlockModuleStoreError.moduleGone }
        switch record.origin {
        case .local: return record
        case .url: throw AdBlockModuleStoreError.linkedModuleNotEditable
        case .unknown: throw AdBlockModuleStoreError.moduleFromANewerVersion
        }
    }

     

     
     
    static func address(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed), let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = components.host, !host.isEmpty
        else { throw AdBlockModuleRefusal.notAnAddress }
        components.scheme = scheme
        components.host = host.lowercased()
        guard let url = components.url else { throw AdBlockModuleRefusal.notAnAddress }
        return url
    }

     
     
    static func authoredText(for error: Error) -> AuthoredText { AuthoredText.of(error) }

     
     
     
     
    static func updateFailureText(for error: Error, linked: Bool) -> AuthoredText {
        switch error as? AdBlockModuleRefusal {
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
        case .tooLarge?:
             
            return .app(AdBlockStoredSentence.scriptTooLarge, arguments: [AdBlockModuleCopy.size(maximumScriptBytes)])
        case .badStatus(let status)? where status >= 0:
             
            return .app(AdBlockStoredSentence.scriptStatus, arguments: [String(status)])
        default:
            return authoredText(for: error)
        }
    }

     
    static func isMissingFile(_ error: Error) -> Bool {
        let ns = error as NSError
        return (ns.domain == NSCocoaErrorDomain && ns.code == NSFileReadNoSuchFileError)
            || (ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOENT))
    }

     
     
    static func sentence(_ text: AuthoredText) -> AdBlockSentence {
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

    static func name(of ir: AdBlockModuleIR, fallback: String) -> String {
        ir.manifest.name.flatMap { $0.isEmpty ? nil : $0 } ?? fallback
    }

     
     
    static func checkScript(_ body: Data) throws {
        guard let text = String(data: body, encoding: .utf8) else { throw AdBlockModuleStoreError.notAScript }
        guard let first = text.first(where: { !$0.isWhitespace }) else { throw AdBlockModuleStoreError.emptyScript }
        guard first != "<" else { throw AdBlockModuleStoreError.notAScript }
    }

    private enum StateRead {
        case missing
        case readable(AdBlockModuleState)
         
        case newer
         
        case corrupt(Data)
         
         
        case readFailed(String)
    }

    private func readState() -> StateRead {
        guard FileManager.default.fileExists(atPath: locations.stateFile.path) else { return .missing }
        let data: Data
        do { data = try Data(contentsOf: locations.stateFile) } catch { return .readFailed(error.localizedDescription) }
        if AdBlockModuleState.isFromANewerBuild(data) { return .newer }
        guard let state = try? AdBlockJSON.decoder().decode(AdBlockModuleState.self, from: data) else { return .corrupt(data) }
        return .readable(state)
    }

     
     
     
     
    func state() throws -> AdBlockModuleState {
        settle()
        switch readState() {
        case .missing: return AdBlockModuleState()
        case .readable(let state): return state
        case .newer: throw AdBlockModuleStoreError.stateUnreadable(.newerVersion)
        case .corrupt: throw AdBlockModuleStoreError.stateUnreadable(.corrupt)
        case .readFailed: throw AdBlockModuleStoreError.stateUnreadable(.readFailed)
        }
    }

     
     
     
     
     
     
    func loadForWrite() throws -> AdBlockModuleState {
        switch readState() {
        case .missing: return AdBlockModuleState()
        case .readable(let state): return state
        case .readFailed(let why):
            log("ad-block module list could not be read right now (\(why)); nothing was changed")
            throw AdBlockModuleStoreError.stateUnreadable(.readFailed)
        case .newer:
             
            log("ad-block module list was written by a newer version (schema above \(AdBlockModuleState.currentSchemaVersion)); nothing was changed")
            throw AdBlockModuleStoreError.stateUnreadable(.newerVersion)
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
                    log("ad-block module list could not be understood; a copy is kept as \(target.lastPathComponent)")
                } catch {
                    log("ad-block module list could not be understood, and a copy could not be kept (\(error.localizedDescription))")
                }
            }
            throw AdBlockModuleStoreError.stateUnreadable(.corrupt)
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
        case .readFailed: throw AdBlockModuleStoreError.stateUnreadable(.readFailed)
        case .newer: throw AdBlockModuleStoreError.stateUnreadable(.newerVersion)
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
            try publish(AdBlockModuleState())
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
            log("ad-block module list was discarded, with \(removed) kept copies; the modules' texts are kept in \(aside.deletingLastPathComponent().lastPathComponent)")
        } else {
            log("ad-block module list was discarded, with \(removed) kept copies")
        }
    }

     
     
     
    func save(_ state: AdBlockModuleState) throws {
        let encoded = try AdBlockJSON.encoder().encode(state)
        let earlier = try? Data(contentsOf: locations.stateFile)
        try write(earlier.flatMap { state.keepingWhatThisBuildDoesNotKnow(encoded, from: $0) } ?? encoded, to: locations.stateFile)
    }

    func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeFile(data, url, ProviderPayloadStore.writeOptions)
    }

     
     
     
    func download(_ url: URL, maxBytes: Int) async throws -> Data {
        let result = try await download(url, maxBytes: maxBytes, etag: nil, lastModified: nil)
         
         
         
        if result.notModified { throw DownloadError.badStatus(-1) }
        return result.data
    }

     
     
     
    func download(_ url: URL, maxBytes: Int, etag: String?, lastModified: String?, headers: [String: String] = [:],
                  redirects: DownloadRedirectPolicy = .followAcrossOrigins(maxHops: 5),
                  format: AdBlockModuleFormat? = nil) async throws -> DownloadResult {
        var request = URLRequest(url: url)
         
         
        let own: Set<String> = ["user-agent", "if-none-match", "if-modified-since"]
        for (field, value) in headers where !own.contains(field.lowercased()) { request.setValue(value, forHTTPHeaderField: field) }
         
         
         
        // A hub usually serves one platform only, so the download presents the
        // platform this module belongs to, falling through to the others when
        // the address named no type. See `AdBlockModuleUserAgent`.
        let candidates = AdBlockModuleUserAgent.candidates(for: url, format: format)
        var lastError: Error?
        for (index, preset) in candidates.enumerated() {
            request.setValue(preset.value, forHTTPHeaderField: "User-Agent")
            if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
            if let lastModified { request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since") }
            do {
                return try await fetcher.fetch(request, maxBytes: maxBytes, redirectPolicy: redirects)
            } catch where Self.isUnverifiedServer(error) {
                log("ad-block download from \(url.absoluteString) refused: the server could not be verified (\(error.localizedDescription))")
                throw AdBlockModuleStoreError.serverNotVerified
            } catch {
                lastError = error
                // Only a refusal is worth another platform's name; a timeout or
                // a network error would repeat for every candidate.
                guard Self.isRefusal(error), index < candidates.count - 1 else { break }
                log("ad-block download from \(url.absoluteString) refused for \(preset.value): trying another platform")
            }
        }
        throw lastError ?? DownloadError.badStatus(0)
    }

    /// Whether an error is the server turning the request away — a status a hub
    /// uses for "wrong app", which another User-Agent may answer.
    private static func isRefusal(_ error: Error) -> Bool {
        guard case DownloadError.badStatus(let status) = error else { return false }
        return status == 403 || status == 404 || status == 451 || (300...399).contains(status)
    }

     
     
     
    /// Fetches a module, presenting the platform it belongs to.
    ///
    /// `format` is the dialect the module was last read as, which is the
    /// certain answer to "which app is this for"; a first fetch has none and
    /// the address's extension is used instead. See `AdBlockModuleUserAgent`.
    func downloadModule(_ url: URL, format: AdBlockModuleFormat? = nil) async throws -> Data {
        do {
            return try await download(url, maxBytes: AdBlockModuleParser.maximumBytes, format: format)
        } catch DownloadError.tooLarge(let observed) {
            throw AdBlockModuleRefusal.tooLarge(observed)
        }
    }

    /// The dialect a module was last published as, read from what the store
    /// already wrote for the tunnel. A module that has never been read has
    /// none, which is what a first fetch is.
    func publishedFormat(of id: String) -> AdBlockModuleFormat? {
        struct Published: Decodable {
            struct Manifest: Decodable { var format: AdBlockModuleFormat }
            var manifest: Manifest?
        }
        guard let data = try? Data(contentsOf: locations.moduleManifest(id)) else { return nil }
        return (try? JSONDecoder().decode(Published.self, from: data))?.manifest?.format
    }

    private func drawPorts(avoiding taken: Set<UInt16>) -> AdBlockPorts {
        var engine = randomPort()
        var tries = 0
        while taken.contains(engine), tries < 64 { engine = randomPort(); tries += 1 }
        var reinject = randomPort()
        tries = 0
        while reinject == engine || taken.contains(reinject), tries < 64 { reinject = randomPort(); tries += 1 }
        if reinject == engine { reinject = engine == Self.portRange.upperBound ? engine - 1 : engine + 1 }
        return AdBlockPorts(engine: engine, reinject: reinject)
    }

     
     
     
     
     
     
     
    struct Prepared {
        var ir: AdBlockModuleIR
        var scriptFetchedAt: [String: Date]
        var bodies: [String: Data]
         
        var attemptedAt: [String: Date] = [:]
        var failedAddresses: Set<String> = []
         
         
        var waiting: Set<String> = []
         
         
        var ranOutOfTime = false
         
        var fileStates: [String: AdBlockFileState] = [:]
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func prepare(data: Data, sourceURL: String?, fetchedAt: Date, id: String, previous: AdBlockModuleIR?,
                 previousFetchedAt: [String: Date], retrying record: AdBlockModuleRecord? = nil,
                 fetchingScripts: Bool = true) async throws -> Prepared {
        preparing[id, default: 0] += 1
        defer {
            if let count = preparing[id], count > 1 { preparing[id] = count - 1 } else { preparing[id] = nil }
        }
         
         
         
        let (platform, check) = (self.platform, self.check)
        let read = await AdBlockJQLargeStack.moduleReads.run {
            try AdBlockModuleParser.parse(data, sourceURL: sourceURL, fetchedAt: fetchedAt, platform: platform, check: check)
        }
        var ir: AdBlockModuleIR
        switch try read.get() {
        case .success(let parsed): ir = parsed
        case .failure(let refusal): throw refusal
        }
        var fetched: [String: Date] = [:]
        var shas: [String: String] = [:]
        var newBodies: [String: Data] = [:]
        var failed: [String: AdBlockSentence] = [:]
        var attempted: [String: Date] = [:]
        var failedAddresses = Set<String>()
        var waiting = Set<String>()
         
         
        var keptAt: [Int: AdBlockScript] = [:]
        var setAsideAt: [Int: AdBlockIgnoredEntry] = [:]
        var ranOutOfTime = false
        let scripts = ir.scripts
         
         
         
        var sizes: [String: Int] = [:]
        var refusedRead = 0
        func size(of sha: String) -> Int {
            if let known = sizes[sha] { return known }
            let bytes = newBodies[sha]?.count
                ?? ((try? FileManager.default.attributesOfItem(atPath: locations.script(id, sha256: sha).path))?[.size] as? Int) ?? 0
            sizes[sha] = bytes
            return bytes
        }
        func scriptBytes() -> Int { Set(shas.values).reduce(refusedRead) { $0 + size(of: $1) } }
         
         
         
        var order = Array(scripts.indices)
        if timeLeft() != nil {
            let bodied = scripts.map { script -> Bool in
                guard let sha = previous?.scripts.first(where: { $0.scriptURL == script.scriptURL && $0.bodySHA256 != nil })?.bodySHA256
                else { return false }
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
            let earlier = previous?.scripts.first { $0.scriptURL == address && $0.bodySHA256 != nil }?.bodySHA256
            let earlierOnDisk = earlier.map { FileManager.default.fileExists(atPath: locations.script(id, sha256: $0).path) } ?? false
            if let earlier, earlierOnDisk, failed[address] == nil, let at = previousFetchedAt[address],
               now().timeIntervalSince(at) < TimeInterval(script.updateInterval) {
                shas[address] = earlier
                fetched[address] = at
                script.bodySHA256 = earlier
                keptAt[index] = script
                continue
            }
            if let sentence = failed[address] {
                setAsideAt[index] = AdBlockIgnoredEntry(text: address, reason: .scriptDownloadFailed(sentence), origin: script.origin)
                continue
            }
             
             
             
            func keptAsItWas(_ script: AdBlockScript) -> Bool {
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
                    setAsideAt[index] = AdBlockIgnoredEntry(text: address, reason: .scriptDownloadFailed(sentence), origin: script.origin)
                    waiting.insert(address)
                    return true
                }
                return false
            }
             
             
             
             
            func setAsideForLater(_ script: AdBlockScript, because why: String, saying: AuthoredText = Self.notDownloadedYet) {
                failed[address] = Self.sentence(saying)
                setAsideAt[index] = AdBlockIgnoredEntry(text: address, reason: .scriptDownloadFailed(Self.sentence(saying)),
                                                        origin: script.origin)
                waiting.insert(address)
                log("ad-block module \(id): script \(script.name) from \(address) is not downloaded yet; \(why)")
            }
             
             
             
            func pastTheBytes() {
                failedAddresses.insert(address)
                if let earlier, earlierOnDisk, size(of: earlier) <= maximumModuleFileBytes - scriptBytes() {
                    shas[address] = earlier
                    if let at = previousFetchedAt[address] { fetched[address] = at }
                    script.bodySHA256 = earlier
                    keptAt[index] = script
                    log("ad-block module \(id): script \(script.name) from \(address) is past the \(maximumModuleFileBytes) bytes the module's files may come to; the copy downloaded before stays")
                } else {
                    failed[address] = Self.tooManyFiles
                    setAsideAt[index] = AdBlockIgnoredEntry(text: address, reason: .scriptDownloadFailed(Self.tooManyFiles), origin: script.origin)
                    log("ad-block module \(id): script \(script.name) from \(address) is past the \(maximumModuleFileBytes) bytes the module's files may come to")
                }
            }
             
             
            if !runsScripts {
                 
                if earlier == nil || !earlierOnDisk || !keptAsItWas(script) {
                    setAsideForLater(script, because: #"no script runs in this build"#, saying: Self.scriptHeld)
                }
                continue
            }
             
             
            if !fetchingScripts {
                if !keptAsItWas(script) { setAsideForLater(script, because: #"HTTPS Decryption is off"#) }
                continue
            }
             
             
             
            if let record, let failures = record.scriptFailureCount[address], failures > 0,
               let tried = record.scriptAttemptedAt[address],
               now().timeIntervalSince(tried) < Self.retryDelay(
                   failures: failures, interval: earlier != nil && earlierOnDisk ? script.updateInterval : record.updateInterval),
               keptAsItWas(script) {
                continue
            }
             
             
             
            if !ranOutOfTime, let left = timeLeft(), left < Self.moduleTimeFloor { ranOutOfTime = true }
            if ranOutOfTime {
                if !keptAsItWas(script) { setAsideForLater(script, because: #"the background task's time ran out"#) }
                continue
            }
            attempted[address] = now()
             
            let room = maximumModuleFileBytes - scriptBytes()
            guard room >= 1 else {
                pastTheBytes()
                continue
            }
            do {
                let body = try await download(try Self.address(address), maxBytes: min(Self.maximumScriptBytes, room))
                do { try Self.checkScript(body) } catch { refusedRead += body.count; throw error }
                let sha = AdBlockJSON.sha256(body)
                newBodies[sha] = body
                shas[address] = sha
                fetched[address] = now()
                script.bodySHA256 = sha
                keptAt[index] = script
                log("ad-block module \(id): script \(script.name) downloaded from \(address), \(body.count) bytes, sha256 \(sha)")
            } catch DownloadError.tooLarge(let observed) where room < Self.maximumScriptBytes {
                 
                 
                refusedRead += min(max(0, observed), room + 1)
                pastTheBytes()
            } catch AdBlockModuleRefusal.notAnAddress {
                 
                 
                 
                 
                attempted.removeValue(forKey: address)
                setAsideAt[index] = AdBlockIgnoredEntry(text: address, reason: .scriptWithoutAddress, origin: script.origin)
                log("ad-block module \(id): script \(script.name) names \(address), which no request can be made from")
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
                    log("ad-block module \(id): script \(script.name) was not updated from \(address) (\(message)); the copy downloaded before stays")
                } else {
                    let sentence = Self.sentence(why)
                    failed[address] = sentence
                    setAsideAt[index] = AdBlockIgnoredEntry(text: address, reason: .scriptDownloadFailed(sentence), origin: script.origin)
                    log("ad-block module \(id): script \(script.name) could not be downloaded from \(address) (\(message))")
                }
            }
        }
        ir.scripts = scripts.indices.compactMap { keptAt[$0] }
        ir.ignored += scripts.indices.compactMap { setAsideAt[$0] }
        if !ranOutOfTime, let left = timeLeft(), left < Self.moduleTimeFloor { ranOutOfTime = true }
        let files = try await resolveFiles(ir, id: id, previous: previous, states: record?.fileStates ?? [:],
                                           interval: record?.updateInterval ?? Self.defaultUpdateInterval, at: fetchedAt,
                                           spent: scriptBytes(),
                                           fetchingFiles: fetchingScripts && !ranOutOfTime, fetchingSets: !ranOutOfTime)
        ir = files.ir
        if files.ranOutOfTime { ranOutOfTime = true }
         
         
         
        ir = adoptRuleSetCopies(ir, id: id, previous: previous)
        return Prepared(ir: ir, scriptFetchedAt: fetched, bodies: newBodies, attemptedAt: attempted,
                        failedAddresses: failedAddresses, waiting: waiting, ranOutOfTime: ranOutOfTime, fileStates: files.states)
    }

     

     
     
    nonisolated var maximumAnswerFileBytes: Int { platform == .mac ? AdBlockAnswerFileLimit.macOS : AdBlockAnswerFileLimit.iOS }
     
    static let maximumJQFileBytes = AdBlockLoonRewriteSyntax.maximumJQBytes
     
    static let maximumRuleSetBytes = 16 << 20
     
     
     
    static let maximumFileReferences = max(64, 2 * 39)
     
     
     
    nonisolated var maximumModuleFileBytes: Int { platform == .mac ? 256 << 20 : 64 << 20 }

     
     
     
    static func fileRetryDelay(failures: Int, interval: Int) -> TimeInterval {
        let delay: TimeInterval = failures <= 1 ? 300 : failures == 2 ? 3600 : TimeInterval(interval)
        return min(delay, TimeInterval(interval))
    }

     
     
     
     
     
    static func setInterval(_ own: Int?, module interval: Int) -> Int {
        guard let own else { return interval }
        return own < 0 ? setNeverAgain : max(AdBlockRuleSetSyntax.minimumListInterval, own)
    }

     
     
    static let setNeverAgain = Int.max

     
     
     
    static func retryInterval(_ interval: Int, module: Int) -> Int {
        interval == setNeverAgain ? module : interval
    }

     
     
     
    static func fileIsDue(_ state: AdBlockFileState, interval: Int, retryInterval: Int? = nil, now: Date) -> Bool {
        if state.failures > 0, let at = state.attemptedAt {
            return now.timeIntervalSince(at) >= fileRetryDelay(failures: state.failures, interval: retryInterval ?? interval)
        }
        guard let at = state.fetchedAt else { return true }
        return now.timeIntervalSince(at) >= TimeInterval(interval)
    }

     
     
    static func fileKey(_ place: AdBlockModuleResourceFetcher.Place, _ url: String, base64: Bool = false) -> String {
        "\(place.rawValue)\(base64 ? "+base64" : "") \(url)"
    }

     
     
    static let fileNotDownloaded = AdBlockSentence.app("The file this line uses couldn't be downloaded, so it was skipped.", arguments: [])
    static let fileNotSecure = AdBlockSentence.app("The file this line uses isn't at an HTTPS address, so it was skipped.", arguments: [])
    static let tooManyFiles = AdBlockSentence.app("This module uses too many or too large files, so this line was skipped.", arguments: [])

     
     
    struct ResolvedFiles {
        var ir: AdBlockModuleIR
        var states: [String: AdBlockFileState]
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
        var place: AdBlockModuleResourceFetcher.Place
        var base64: Bool
        var interval: Int
         
         
        var headers: [String: String] = [:]
         
        var uses: [(reference: Int, slot: Slot)] = []
    }

    private enum Resolution {
        case file(sha256: String, byteCount: Int)
         
        case waiting
        case failed(AdBlockIgnoredReason)
         
        case capped
    }

     
     
    private static func placeholders(_ ir: AdBlockModuleIR) -> [AdBlockLineOrigin: [Slot]] {
        var slots: [AdBlockLineOrigin: [Slot]] = [:]
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

    private static func placeholder(_ action: AdBlockRewriteAction, at place: Slot.Place) -> Slot? {
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

     
     
     
    private static func filled(_ action: AdBlockRewriteAction, sha256: String, byteCount: Int) -> AdBlockRewriteAction {
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

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func resolveFiles(_ ir: AdBlockModuleIR, id: String, previous: AdBlockModuleIR?, states: [String: AdBlockFileState] = [:],
                      interval: Int = AdBlockModuleStore.defaultUpdateInterval, at passTime: Date? = nil, spent scripts: Int = 0,
                      fetchingFiles: Bool, fetchingSets: Bool) async throws -> ResolvedFiles {
        guard !ir.answerFiles.isEmpty || ir.ruleSets.contains(where: { $0.url != nil }) else { return ResolvedFiles(ir: ir, states: [:]) }
         
        preparing[id, default: 0] += 1
        defer {
            if let count = preparing[id], count > 1 { preparing[id] = count - 1 } else { preparing[id] = nil }
        }
        let passTime = passTime ?? now()
        let log = self.log
        // A module's scripts live beside the module, so they are served to the
        // same app: the dialect the module was read as decides the User-Agent
        // for them too.
        let dialect = ir.manifest.format
        let fetcher = AdBlockModuleResourceFetcher(
            locations: locations,
            download: { [unowned self] url, limit, etag, lastModified, headers in
                try await self.download(url, maxBytes: limit, etag: etag, lastModified: lastModified, headers: headers,
                                        redirects: .followWithinAModulesReach(maxHops: 5), format: dialect)
            },
            isOutOfTime: { [unowned self] error in await self.isOutOfTime(error) },
            write: { [unowned self] data, url in try await self.write(data, to: url) },
            log: { log($0) })

         
         
        let slots = Self.placeholders(ir)
        var wanted: [Wanted] = []
        var index: [String: Int] = [:]
        var keyOfReference: [Int: String] = [:]
        var ordinals: [AdBlockLineOrigin: Int] = [:]
        for (r, reference) in ir.answerFiles.enumerated() {
            let ordinal = ordinals[reference.origin, default: 0]
            ordinals[reference.origin] = ordinal + 1
            guard let line = slots[reference.origin], ordinal < line.count else {
                log("ad-block module \(id): \(reference.url) is named by \(reference.origin.section) line \(reference.origin.line), where no action waits for a file")
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
             
            let headers = AdBlockRuleSetSyntax.downloadHeaders(of: set).filter { $0.key.lowercased() != "user-agent" }
            wanted.append(Wanted(key: key, url: url, place: .sets, base64: false, interval: own, headers: headers))
        }

        var resolution: [String: Resolution] = [:]
        var newStates: [String: AdBlockFileState] = [:]
        var jqTexts: [String: JQText] = [:]
         
         
        var spent = scripts
        var admitted = 0
        var ranOutOfTime = false
        for item in wanted {
            guard admitted < Self.maximumFileReferences else {
                resolution[item.key] = .capped
                continue
            }
            admitted += 1
            var state = states[item.key] ?? AdBlockFileState()
            let exists = { (sha: String) in FileManager.default.fileExists(atPath: self.published(id, sha, item.place).path) }
             
            let earlier = [state.sha256, Self.namedBefore(item, in: previous)].compactMap { $0 }.first(where: exists)
            let jqUses = item.uses.filter(\.slot.jq).count
            let bodyUse = item.uses.contains { !$0.slot.jq }
            let cap = item.place == .sets ? Self.maximumRuleSetBytes : bodyUse ? maximumAnswerFileBytes : Self.maximumJQFileBytes
            let tried = item.place == .sets ? fetchingSets : fetchingFiles
            let due: Bool = {
                if state.failures > 0, let at = state.attemptedAt {
                    let widest = Self.retryInterval(item.interval, module: interval)
                    return now().timeIntervalSince(at) >= Self.fileRetryDelay(failures: state.failures, interval: widest)
                }
                guard earlier != nil, let at = state.fetchedAt else { return true }
                return passTime.timeIntervalSince(at) >= TimeInterval(item.interval)
            }()
            var sha = earlier
            var failure: AdBlockModuleResourceFetcher.Failure?
            var jqWords: String?
             
            var pastTheBytes = false
            var fetchedNow = false
            if due, tried, !ranOutOfTime {
                try Task.checkCancellation()
                 
                if let left = timeLeft(), left < Self.moduleTimeFloor { ranOutOfTime = true }
            }
            let room = max(0, maximumModuleFileBytes - spent)
            if due, tried, !ranOutOfTime, room < 1 {
                 
                log("ad-block module \(id): \(item.url) was not downloaded: the module's files have come to the \(maximumModuleFileBytes) bytes they may")
                pastTheBytes = true
                state.failures += 1
                state.attemptedAt = now()
            } else if due, tried, !ranOutOfTime {
                let request = AdBlockModuleResourceFetcher.Request(
                    url: item.url, place: item.place, cap: cap, budget: room,
                    base64: item.base64, acceptsHTML: item.uses.contains { $0.slot.acceptsHTML(item.url) },
                    earlier: earlier.map { .init(sha256: $0, etag: state.etag, lastModified: state.lastModified) },
                    headers: item.headers)
                switch try await fetcher.fetch(request, module: id) {
                case .fetched(let new, let count, let etag, let lastModified):
                     
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
                        fetchedNow = true
                        state = AdBlockFileState(sha256: new, fetchedAt: passTime, attemptedAt: now(), failures: 0,
                                                 etag: etag, lastModified: lastModified)
                    } else {
                        log("ad-block module \(id): \(item.url) is not a jq program Clash reads (\(jqWords ?? #"not text"#))")
                        spent += count
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
                case .failed(.overTheModuleBudget, let read):
                    spent += read
                    pastTheBytes = true
                    state.failures += 1
                    state.attemptedAt = now()
                case .failed(let why, let read):
                    spent += read
                    failure = why
                    state.failures += 1
                    state.attemptedAt = now()
                case .notTried:
                    ranOutOfTime = true
                }
            }
            if state != AdBlockFileState() { newStates[item.key] = state }
            if let current = sha {
                 
                let size = ((try? FileManager.default.attributesOfItem(atPath: published(id, current, item.place).path))?[.size] as? Int) ?? 0
                guard size <= maximumModuleFileBytes - spent else {
                    log("ad-block module \(id): \(item.url) is past the \(maximumModuleFileBytes) bytes the module's files may come to")
                    resolution[item.key] = .capped
                    if fetchedNow {
                         
                        state.failures += 1
                        state.attemptedAt = now()
                        newStates[item.key] = state
                    }
                    continue
                }
                spent += size
                if jqUses > 0, jqTexts[current] == nil { jqTexts[current] = await Self.jqText(published(id, current, .files)) }
                if failure != nil || pastTheBytes { log("ad-block module \(id): \(item.url) was not updated; the copy downloaded before stays") }
                resolution[item.key] = .file(sha256: current, byteCount: size)
            } else if pastTheBytes {
                resolution[item.key] = .capped
            } else if let failure {
                 
                 
                resolution[item.key] = .failed(item.place == .sets && failure == .unusable
                    ? .ruleSetNotDownloadedYet : Self.reason(for: failure, jqWords: jqWords, answers: bodyUse))
            } else if state.failures > 0, let had = Self.skippedBefore(item, in: previous) {
                 
                resolution[item.key] = .failed(had)
            } else {
                resolution[item.key] = .waiting
            }
        }

         
         
        var out = ir
        var skipped: [AdBlockLineOrigin: (url: String, reason: AdBlockIgnoredReason)] = [:]
        var fills: [Slot.Place: (sha256: String, byteCount: Int)] = [:]
        func skip(_ origin: AdBlockLineOrigin, _ url: String, _ reason: AdBlockIgnoredReason) {
            if skipped[origin] == nil { skipped[origin] = (url, reason) }
        }
        for item in wanted where item.place == .files {
            for use in item.uses {
                let origin = ir.answerFiles[use.reference].origin
                switch resolution[item.key] {
                case .capped?: skip(origin, item.url, .fileDownloadFailed(Self.tooManyFiles))
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
            guard let key = keyOfReference[r] else { return nil }
            if case .capped? = resolution[key] { return nil }
            return reference
        }
        out.ignored += skipped.sorted { ($0.key.section, $0.key.line) < ($1.key.section, $1.key.line) }
            .map { AdBlockIgnoredEntry(text: $0.value.url, reason: $0.value.reason, origin: $0.key) }

         
         
         
         
        var keptSets: [AdBlockRuleSet] = []
        var leftOut: [String] = []
        for var set in ir.ruleSets {
            guard let url = set.url else { keptSets.append(set); continue }
            switch resolution[Self.fileKey(.sets, url)] {
            case .file(let sha, _)?:
                set.sha256 = sha
                keptSets.append(set)
            case .capped?:
                out.ignored.append(AdBlockIgnoredEntry(text: url, reason: .fileDownloadFailed(Self.tooManyFiles), origin: set.origin))
                leftOut.append(set.reference)
            case .failed(let reason)?:
                out.ignored.append(AdBlockIgnoredEntry(text: url, reason: reason, origin: set.origin))
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

    private func published(_ id: String, _ sha256: String, _ place: AdBlockModuleResourceFetcher.Place) -> URL {
        place == .files ? locations.file(id, sha256: sha256) : locations.ruleSet(id, sha256: sha256)
    }

     
     
    private static func namedBefore(_ item: Wanted, in previous: AdBlockModuleIR?) -> String? {
        guard let previous else { return nil }
        if item.place == .sets { return previous.ruleSets.first { $0.url == item.url && $0.sha256 != nil }?.sha256 }
        return previous.answerFiles.first { $0.url == item.url && ($0.base64 == true) == item.base64 && $0.sha256 != nil }?.sha256
    }

     
     
    private static func skippedBefore(_ item: Wanted, in previous: AdBlockModuleIR?) -> AdBlockIgnoredReason? {
        previous?.ignored.first { entry in
            guard entry.text == item.url else { return false }
            switch entry.reason {
            case .fileDownloadFailed, .jqExpressionInvalid, .answerFileTooLarge, .noEffectInItsOwnApp, .ruleSetNotDownloadedYet: return true
            default: return false
            }
        }?.reason
    }

    private static func reason(for failure: AdBlockModuleResourceFetcher.Failure, jqWords: String?,
                               answers: Bool) -> AdBlockIgnoredReason {
        if let jqWords { return jqReason(jqWords) }
        switch failure {
        case .tooLarge(let limit) where answers: return .answerFileTooLarge(limit)
        case .notSecure: return .fileDownloadFailed(fileNotSecure)
        case .overTheModuleBudget: return .fileDownloadFailed(tooManyFiles)
        case .tooLarge, .unusable: return .fileDownloadFailed(fileNotDownloaded)
        }
    }

     
     
     
    static func jqReason(_ words: String) -> AdBlockIgnoredReason {
        words == AdBlockJQ.noProgram ? .noEffectInItsOwnApp(.noEffect) : .jqExpressionInvalid(words)
    }

    enum JQText: Equatable {
        case text(String)
         
        case invalid(String)
         
        case unusable
    }

     
     
    static func jqText(_ file: URL) async -> JQText {
        guard let data = try? Data(contentsOf: file), data.count <= maximumJQFileBytes,
              let text = String(data: data, encoding: .utf8) else { return .unusable }
        do {
            _ = try await AdBlockJQ.parseOnLargeStack(text)
            return .text(text)
        } catch let error as AdBlockJQ.ParseError {
            return .invalid(error.message)
        } catch {
            return .invalid("\(error)")
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    @discardableResult
    func commit(_ record: AdBlockModuleRecord, ir: AdBlockModuleIR, source: Data,
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
        for script in ir.scripts {
            guard let sha = script.bodySHA256 else { throw AdBlockModuleStoreError.scriptMissing(script.scriptURL) }
            if bodies[sha] == nil, !FileManager.default.fileExists(atPath: locations.script(record.id, sha256: sha).path) {
                throw AdBlockModuleStoreError.scriptMissing(script.scriptURL)
            }
        }
         
        for reference in ir.answerFiles {
            guard let sha = reference.sha256 else { continue }
            guard FileManager.default.fileExists(atPath: locations.file(record.id, sha256: sha).path) else {
                throw AdBlockModuleStoreError.fileMissing(reference.url)
            }
        }
        for set in ir.ruleSets {
            guard let sha = set.sha256 else { continue }
            guard FileManager.default.fileExists(atPath: locations.ruleSet(record.id, sha256: sha).path) else {
                throw AdBlockModuleStoreError.fileMissing(set.url ?? sha)
            }
        }
        let encoded = try AdBlockJSON.encoder().encode(ir)
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
                log("ad-block module \(record.id) was not written (\(error.localizedDescription)); what was published stays")
            } else {
                 
                 
                log("ad-block module \(record.id) was not written (\(error.localizedDescription)), and its files could not all be put back; what is on disk is published again")
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

     
     
    func note(_ record: AdBlockModuleRecord) throws {
        var state = try loadForWrite()
        guard let index = state.modules.firstIndex(where: { $0.id == record.id }) else { return }
        state.modules[index].adopt(refreshOwnedFieldsOf: record)
        try save(state)
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

     
     
     
    func publish(_ state: AdBlockModuleState) throws {
        var modules: [AdBlockGlobalManifest.Module] = []
        var mitm: [(moduleID: String, lines: [AdBlockHostListLine])] = []
        var plainHTTP: [(moduleID: String, lines: [AdBlockHostListLine])] = []
        var enabled: [(moduleID: String, ir: AdBlockModuleIR, choice: String?)] = []
        for record in state.modules where record.enabled {
             
            guard let (data, ir) = publishedIR(of: record) else {
                log("ad-block module \(record.id) is left out of the publication: its manifest could not be read")
                continue
            }
            modules.append(AdBlockGlobalManifest.Module(
                id: record.id, name: record.name, irSHA256: AdBlockJSON.sha256(data),
                effectiveCount: ir.effectiveCount, ignoredCount: ir.ignoredCount))
            mitm.append((moduleID: record.id, lines: ir.mitmHostLines))
            plainHTTP.append((moduleID: record.id, lines: ir.forceHTTPEngineHostLines))
             
             
             
            enabled.append((moduleID: record.id, ir: ir, choice: nil))
        }
         
         
        let builtIns = enabled.contains { $0.ir.ruleSets.contains { $0.kind == .builtInLAN || $0.kind == .builtInSystem } }
        let lanCopy = builtIns ? builtInRuleSetCopy(.builtInLAN) : nil
        let systemCopy = builtIns ? builtInRuleSetCopy(.builtInSystem) : nil
        let sets = AdBlockRuleSetSyntax.publication(enabled, builtInCopy: { kind in
            kind == .builtInLAN ? lanCopy : kind == .builtInSystem ? systemCopy : nil
        })
         
         
        for index in modules.indices {
            if let origins = sets.leftOutOrigins[modules[index].id] { modules[index].leftOutOrigins = origins }
        }
        var manifest = AdBlockGlobalManifest(
            schemaVersion: AdBlockGlobalManifest.currentSchemaVersion, enabled: state.enabled, modules: modules,
            mitmHosts: AdBlockHostList.merged(mitm, standardPort: AdBlockHostList.mitmStandardPort),
            forceHTTPEngineHosts: AdBlockHostList.merged(plainHTTP, standardPort: AdBlockHostList.forceHTTPStandardPort),
            routingRules: sets.rules, ports: state.ports,
             
             
            caFingerprintSHA256: Self.caFingerprint(in: locations.container),
            reinjectCredentials: state.reinjectCredentials, engineProxyCredentials: state.engineProxyCredentials,
            publishedAt: now(), settings: sets.settings, ruleProviders: sets.providers)
         
         
         
         
        do {
            try AdBlockDeviceSettingOverlay(manifest.settings ?? []).publish(to: locations)
        } catch {
            log("ad-block modules' device settings were not written, the ones before stay: \(error.localizedDescription)")
        }
        var changed = true
        if let existing = publishedGlobalManifest() {
            var same = manifest
            same.publishedAt = existing.publishedAt
            changed = same != existing
        }
        if changed {
            manifest.publishedAt = now()
            try write(try AdBlockJSON.encoder().encode(manifest), to: locations.globalManifest)
        }
        var root = locations.publishedRoot
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? root.setResourceValues(values)
         
         
         
        if changed || hasOrphans(state) { collectGarbage(keeping: state, published: changed) }
        if changed {
            announce(Self.didChange)
             
             
             
             
            if let group = ClashAppIdentifiers.appGroupContainer, Self.normalized(locations.container) == Self.normalized(group) {
                AdBlockEngineSignal.postModulesChanged()
            }
        }
    }

    private func hasOrphans(_ state: AdBlockModuleState) -> Bool {
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

     
     
     
     
     
     
     
     
     
     
     
    private func collectGarbage(keeping state: AdBlockModuleState, published: Bool) {
        let files = FileManager.default
        let ids = Set(state.modules.map(\.id))
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
        let decoder = AdBlockJSON.decoder()
         
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
            sweep(locations.scriptsDirectory(id), keeping: Set(ir.scripts.compactMap { $0.bodySHA256.map { $0 + ".js" } }), prefix: id + "/")
            sweep(locations.filesDirectory(id), keeping: Set(ir.answerFiles.compactMap(\.sha256)), prefix: id + "/files/")
            sweep(locations.setsDirectory(id), keeping: Set(ir.ruleSets.compactMap(\.sha256)), prefix: id + "/sets/")
        }
        if let data = try? AdBlockJSON.encoder().encode(after), data != stored, stored != nil || !after.isEmpty {
            try? write(data, to: retiredFile)
        }
         
         
         
         
        do {
            var named = Set<String>()
            for id in ids { for set in storedIR(id)?.ruleSets ?? [] { if let sha = set.copy?.sha256 { named.insert(sha) } } }
            for kind in [AdBlockRuleSetKind.builtInLAN, .builtInSystem] { if let sha = builtInRuleSetCopy(kind) { named.insert(sha) } }
             
             
             
            if let mitm = publishedGlobalManifest()?.mitmHosts {
                for set in AdBlockEngineRoute.hostSets(for: AdBlockInjection.hostsForTheDocument(mitm).list) { named.insert(set.sha256) }
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

 
 
 
 
 
 
 
 
 
 
 
final class AdBlockModuleChangeTakers: @unchecked Sendable {
    static let shared = AdBlockModuleChangeTakers()

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
     
     
    private var askedToRecompose: [String: AdBlockStaleComposition] = [:]

    private static func key(_ container: URL) -> String { AdBlockModuleStore.normalized(container).path }

     
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
    func recompose(_ stale: AdBlockStaleComposition, in container: URL, fallback: @MainActor () -> Void) -> Bool {
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

 

extension AdBlockModuleStore {
     
     
     
     
    func builtInRuleSetCopy(_ kind: AdBlockRuleSetKind) -> String? {
        guard let lines = AdBlockRuleSetSyntax.builtInLines(kind, platform: platform) else { return nil }
        return try? keepRuleSetCopy(Data((lines.joined(separator: "\n") + "\n").utf8))
    }

     
     
     
    func keepRuleSetCopy(_ data: Data) throws -> String {
        let sha = AdBlockJSON.sha256(data)
        let url = locations.ruleSetCopy(sha256: sha)
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.setAttributes([.modificationDate: now()], ofItemAtPath: url.path)
        } else {
            try write(data, to: url)
        }
        return sha
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func adoptRuleSetCopies(_ given: AdBlockModuleIR, id: String, previous: AdBlockModuleIR?) -> AdBlockModuleIR {
        var ir = given
        guard ir.ruleSets.contains(where: { $0.url != nil }) else { return ir }
        var dropped: [(reference: String, reason: AdBlockIgnoredReason, origin: AdBlockLineOrigin)] = []
        let family: AdBlockModuleFormat = ir.manifest.format == .loon ? .loon : .surge
         
         
         
        let room = max(0, min(AdBlockRuleSetSyntax.maximumListRuleBytes,
                              AdBlockRuleSetSyntax.maximumModuleKeptBytes - AdBlockRuleSetSyntax.keptBytes(of: given)))
        var listBytes = 0
        func admit(_ rules: [AdBlockRewriteRule]) -> (kept: [AdBlockRewriteRule], left: Int) {
            var kept: [AdBlockRewriteRule] = []
            for rule in rules {
                let bytes = AdBlockRuleSetSyntax.encodedBytes(rule)
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
                    if skipped > 0 { ir.notes.append(AdBlockLineNote(sentence: Self.setLinesSkipped(skipped), origin: set.origin)) }
                } else {
                    dropped.append((set.reference, .ruleSetNotDownloadedYet, set.origin))
                }
                continue
            }
            var converted: AdBlockRuleSetSyntax.Converted
            var copyData: Data
            switch set.kind {
            case .provider(_, let format) where format == "mrs":
                 
                 
                converted = AdBlockRuleSetSyntax.Converted()
                copyData = raw
            case .provider:
                 
                converted = AdBlockRuleSetSyntax.convert(String(decoding: raw, as: UTF8.self), kind: set.kind, policy: set.policy,
                                                         origin: set.origin, family: .stash, platform: platform)
                copyData = raw
            default:
                converted = AdBlockRuleSetSyntax.convert(String(decoding: raw, as: UTF8.self), kind: set.kind, policy: set.policy,
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
                log("ad-block module \(id): the copy of \(set.reference) could not be written (\(error.localizedDescription))")
                dropped.append((set.reference, .ruleSetNotDownloadedYet, set.origin))
                continue
            }
            set.copy = AdBlockRuleSetCopy(sha256: copy, lines: converted.kernelLines.count, skipped: converted.skipped, held: converted.heapLines)
            ir.ruleSets[index] = set
            ir.rewriteRules += rewrites.kept
            if converted.skipped > 0 { ir.notes.append(AdBlockLineNote(sentence: Self.setLinesSkipped(converted.skipped), origin: set.origin)) }
            log("ad-block module \(id): \(set.reference) as the kernel reads it: \(converted.kernelLines.count) lines, "
                + "\(rewrites.kept.count) URL rewrites, \(converted.skipped) left out, "
                + "\(converted.heapLines) held, sha256 \(copy)")
        }
        for (reference, reason, origin) in dropped {
            ir = Self.leavingOut(reference, of: ir)
            ir.ignored.append(AdBlockIgnoredEntry(text: reference, reason: reason, origin: origin))
            log("ad-block module \(id): \(reference) is left out: \(reason.authoredText.englishText)")
        }
        return ir
    }

     
     
     
    static func leavingOut(_ reference: String, of given: AdBlockModuleIR) -> AdBlockModuleIR {
        var ir = given
        let token = "rule-set:" + reference
        ir.ruleSets.removeAll { $0.reference == reference }
        ir.routingRules.removeAll { $0.head == reference }
        ir.hosts.removeAll { $0.pattern == token }
        ir.edits = ir.edits.compactMap { edit in
            guard edit.path.first == "dns", edit.valueJSON.contains(token), let value = try? OrderedJSON.parse(edit.valueJSON) else { return edit }
            guard let kept = AdBlockRuleSetSyntax.renderingSets(value, { $0 == reference ? nil : $0 }), !kept.isEmptyContainer else { return nil }
            var copy = edit
            copy.valueJSON = kept.serialized()
            return copy
        }
        return ir
    }

     
     
     
    static func setLinesSkipped(_ count: Int) -> AdBlockSentence {
        .app("Some lines in this rule set were skipped (%@).", arguments: [String(count)])
    }
}

 

extension AdBlockModuleStore {
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

     
     
     
     
     
     
     
     
     
     
     
     
     
    func refresh(_ id: String, refetchModule: Bool = true, fetchingScripts: Bool = true) async -> RefreshResult {
        let list: AdBlockModuleState
        do { list = try state() } catch {
            log("ad-block module \(id) was not checked: the module list could not be used right now")
            return .listUnreadable
        }
        guard let record = list.modules.first(where: { $0.id == id }) else { return .missing }
        generations[id, default: 0] += 1
        let mine = generations[id, default: 0]
        let checkedAt = now()
        var link: String?
        if case .url(let address) = record.origin { link = address }
        let movesClock = link == nil || refetchModule
        let origin = link.map { " from \($0)" } ?? ""
        do {
            let data: Data
            if let link, refetchModule {
                data = try await downloadModule(try Self.address(link), format: publishedFormat(of: id))
            } else {
                do {
                    data = try Data(contentsOf: locations.source(id))
                } catch where Self.isMissingFile(error) {
                     
                     
                     
                    log("ad-block module \(id) has no saved copy to read again (\(error.localizedDescription))")
                    throw link == nil ? AdBlockModuleStoreError.savedCopyMissing : .linkedCopyMissing
                }
            }
            let previous = publishedModule(id)
            let prepared = try await prepare(data: data, sourceURL: link, fetchedAt: checkedAt, id: id,
                                             previous: previous, previousFetchedAt: record.scriptFetchedAt,
                                             retrying: record, fetchingScripts: fetchingScripts)
            guard generations[id] == mine else { return .superseded }
            var updated = record
            if movesClock {
                updated.lastCheckedAt = checkedAt
                updated.lastFailure = nil
                updated.linkFailureCount = 0
            }
            updated.absorb(prepared)
            if let previous, Self.sameContent(previous, prepared.ir) {
                 
                 
                 
                for (sha, body) in prepared.bodies where !FileManager.default.fileExists(atPath: locations.script(id, sha256: sha).path) {
                    try write(body, to: locations.script(id, sha256: sha))
                }
                 
                 
                let digest = AdBlockJSON.sha256(data)
                if digest != record.sourceSHA256 || !FileManager.default.fileExists(atPath: locations.source(id).path) {
                    try write(data, to: locations.source(id))
                    updated.sourceSHA256 = digest
                }
                try note(updated)
                if prepared.ranOutOfTime {
                    log("ad-block module \(id) checked in part\(origin): the background task's time ran out; the rest is checked next time")
                    return .outOfTime
                }
                return .unchanged
            }
            updated.lastUpdatedAt = checkedAt
            updated.name = Self.name(of: prepared.ir, fallback: record.name)
            updated.sourceSHA256 = AdBlockJSON.sha256(data)
            guard try commit(updated, ir: prepared.ir, source: data, bodies: prepared.bodies, isNew: false) else {
                log("ad-block module \(id) was gone when its update came to be written; nothing was written")
                return .superseded
            }
            log("ad-block module \(id) updated\(origin): \(prepared.ir.effectiveCount) kept, \(prepared.ir.ignoredCount) set aside")
            if prepared.ranOutOfTime {
                log("ad-block module \(id) updated in part: the background task's time ran out; the rest is checked next time")
                return .outOfTime
            }
            return .updated
        } catch {
            if Self.isCancellation(error) { return .cancelled }
             
             
            if isOutOfTime(error) {
                log("ad-block module \(id) was not checked\(origin): the background task's time ran out")
                return .outOfTime
            }
            guard generations[id] == mine else { return .superseded }
            let failure = Self.updateFailureText(for: error, linked: link != nil)
            var failed = record
            if movesClock { failed.lastCheckedAt = checkedAt }
             
            if link != nil, refetchModule { failed.linkFailureCount += 1 }
            failed.lastFailure = failure
            try? note(failed)
             
            let count = (error as? AdBlockModuleRefusal).flatMap { refusal -> String? in
                if case .tooLarge(let bytes) = refusal { return " (\(bytes) bytes)" } else { return nil }
            } ?? ""
            log("ad-block module \(id) was not updated\(origin): \(failure.englishText)\(count); the published copy stays")
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
        defer { if stoppedShort { setScanCursor(reached ?? cursor) } else { setScanCursor(nil) } }
        for listed in order {
            if Task.isCancelled { stoppedShort = true; break }
            let current: AdBlockModuleState
            do { current = try state() } catch {
                log("ad-block modules were not checked: the module list could not be used right now (\(error))")
                break
            }
            guard let record = current.modules.first(where: { $0.id == listed.id }), record.enabled else { continue }
             
             
            let fetchingScripts = current.enabled
            let due = isDue(record)
             
             
            guard due.module || due.sets || (fetchingScripts && ((runsScripts && due.scripts) || due.files)) else { continue }
             
             
            if let left = timeLeft(), left < Self.moduleTimeFloor {
                log("ad-block modules were not all checked: the background task had \(Int(max(0, left))) s left")
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
        return min(doubled, TimeInterval(interval))
    }

     
     
     
     
     
     
     
     
     
     
    func isDue(_ record: AdBlockModuleRecord) -> (module: Bool, scripts: Bool, files: Bool, sets: Bool) {
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
        guard let published = publishedModule(record.id) else { return (module, false, false, false) }
        func due(_ address: String, interval: Int) -> Bool {
            if let failures = record.scriptFailureCount[address], failures > 0, let at = record.scriptAttemptedAt[address] {
                return current.timeIntervalSince(at) >= Self.retryDelay(failures: failures, interval: interval)
            }
            guard let at = record.scriptFetchedAt[address] else { return true }
            return current.timeIntervalSince(at) >= TimeInterval(interval)
        }
        let passed = published.scripts.contains { due($0.scriptURL, interval: $0.updateInterval) }
        let setAside = published.ignored.contains { entry in
            guard case .scriptDownloadFailed = entry.reason else { return false }
            return due(entry.text, interval: record.updateInterval)
        }
        let setPrefix = AdBlockModuleResourceFetcher.Place.sets.rawValue + " "
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
        return (module, setAside || passed, files, sets)
    }

     
     
     
    static func listAddress(_ text: String) -> String {
        for head in ["RULE-SET,", "DOMAIN-SET,"] where text.hasPrefix(head) { return String(text.dropFirst(head.count)) }
        return text
    }

     
     
     
     
     
     
    static func sameContent(_ a: AdBlockModuleIR, _ b: AdBlockModuleIR) -> Bool {
        let held = sentence(scriptHeld)
        func plain(_ ir: AdBlockModuleIR) -> AdBlockModuleIR {
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

 

extension AdBlockModuleStore {
     
     
     
     
     
     
     
     
     
     
     
    @discardableResult
    func restore(_ section: AdBlockBackupSection) async -> [String] {
        settle()
        guard section.schemaVersion <= AdBlockBackupSection.currentSchemaVersion else {
            log("ad-block modules not restored: the backup's section is version \(section.schemaVersion)")
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
                                                 previous: nil, previousFetchedAt: [:], fetchingScripts: decrypting)
                 
                 
                if try hasModule(like: module) { continue }
                var record = AdBlockModuleRecord(
                    id: id, origin: module.origin, enabled: module.enabled, name: module.name,
                    updateInterval: module.updateInterval, lastCheckedAt: nil,
                    lastUpdatedAt: module.source.isEmpty ? at : module.lastUpdatedAt,
                    lastFailure: nil, scriptFetchedAt: prepared.scriptFetchedAt, sourceSHA256: AdBlockJSON.sha256(source))
                record.absorb(prepared)
                try commit(record, ir: prepared.ir, source: source, bodies: prepared.bodies, isNew: true)
                log("ad-block module \(id) restored from a backup: \(module.name), \(prepared.ir.effectiveCount) kept, \(prepared.ir.ignoredCount) set aside")
            } catch {
                failed.append(module.name)
                log("ad-block module \(module.name) not restored from a backup: \(error.localizedDescription)")
            }
        }
        return failed
    }

    private func hasModule(like module: AdBlockBackupSection.Module) throws -> Bool {
        let carried = AdBlockJSON.sha256(module.source)
        return try loadForWrite().modules.contains { record in
            switch (record.origin, module.origin) {
            case (.url(let mine), .url(let theirs)):
                return mine == theirs
            case (.local, .local):
                let kept = record.sourceSHA256 ?? (try? Data(contentsOf: locations.source(record.id))).map(AdBlockJSON.sha256)
                return kept == carried
            default:
                return false
            }
        }
    }
}
