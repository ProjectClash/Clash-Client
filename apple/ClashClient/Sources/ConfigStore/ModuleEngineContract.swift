import Foundation

 
 
 
 
 
 

 
 
 
struct ModuleRunningRevision: Codable, Equatable, Hashable, Sendable {
    let profileID: String
    let revision: String
}

 
 
 
 
struct ModuleEngineLocations: Equatable, Sendable {
     
     
     
     
     
    enum CAKeyPlace: Equatable, Sendable {
        case file
        case keychain(accessGroup: String)
    }

    let container: URL
    var caKeyPlace: CAKeyPlace = .file

    func moduleManifest(_ id: String) -> URL {
        container.appendingPathComponent("modules", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent("manifest.json")
    }

    func script(_ id: String, sha256: String) -> URL {
        container.appendingPathComponent("modules", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent("scripts", isDirectory: true)
            .appendingPathComponent(sha256 + ".js")
    }

     
     
     
    func moduleFile(_ id: String, sha256: String) -> URL {
        container.appendingPathComponent("modules", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent("files", isDirectory: true)
            .appendingPathComponent(sha256)
    }

     
     
    var globalManifest: URL {
        container.appendingPathComponent("modules", isDirectory: true).appendingPathComponent("manifest.json")
    }

    var stateDirectory: URL {
        container.appendingPathComponent("working", isDirectory: true)
            .appendingPathComponent("adblock", isDirectory: true)
    }

     
     
    var certificateDirectory: URL { stateDirectory.appendingPathComponent("ca", isDirectory: true) }
    var caCertificate: URL { certificateDirectory.appendingPathComponent("ca.der") }
    var caPrivateKey: URL { certificateDirectory.appendingPathComponent("ca-key.der") }
    var caMetadata: URL { certificateDirectory.appendingPathComponent("ca.json") }
    var certificatePage: URL { certificateDirectory.appendingPathComponent("index.html") }
    var certificateProfile: URL { certificateDirectory.appendingPathComponent(Self.certificateProfileName) }
    var certificateFile: URL { certificateDirectory.appendingPathComponent(Self.certificateFileName) }

     
     
     
    static let certificateProfileName = "ClashModuleCA.mobileconfig"
    static let certificateFileName = "ClashModuleCA.cer"
     
    static var certificateProfilePath: String { "/" + certificateProfileName }
    static var certificateFilePath: String { "/" + certificateFileName }

     
    var enginePlans: URL { stateDirectory.appendingPathComponent("engine-plans.json") }
     
    var hostListsDirectory: URL { stateDirectory.appendingPathComponent("host-lists", isDirectory: true) }
    func hostList(_ digest: String) -> URL { hostListsDirectory.appendingPathComponent(digest + ".list") }
     
    var engineReport: URL { stateDirectory.appendingPathComponent("engine-status.json") }
     
    var engineRetry: URL { stateDirectory.appendingPathComponent("engine-retry.json") }

     
     
    static func of(_ container: URL) -> ModuleEngineLocations {
        if let production, production.container.standardizedFileURL == container.standardizedFileURL { return production }
        return ModuleEngineLocations(container: container)
    }

     
     
    static var production: ModuleEngineLocations? {
        ClashAppIdentifiers.appGroupContainer.map { container in
            #if os(macOS)
            ModuleEngineLocations(container: container, caKeyPlace: .keychain(accessGroup: ClashAppIdentifiers.appGroup))
            #else
            ModuleEngineLocations(container: container)
            #endif
        }
    }
}

enum ModuleEngineFiles {
     
     
    static let writeOptions: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]

    static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: writeOptions)
    }

     
    enum Bounded: Equatable, Sendable {
        case absent
        case tooLarge(limit: Int)
        case failed(String)
        case data(Data)
    }

     
    static func bounded(_ url: URL, maximumBytes: Int) -> Bounded {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            return FileManager.default.fileExists(atPath: url.path) ? .failed("\(error)") : .absent
        }
        defer { try? handle.close() }
        do {
             
            let data = try (maximumBytes == .max ? handle.readToEnd() : handle.read(upToCount: maximumBytes + 1)) ?? Data()
            return data.count > maximumBytes ? .tooLarge(limit: maximumBytes) : .data(data)
        } catch {
            return .failed("\(error)")
        }
    }

     
    static func data(from url: URL, maximumBytes: Int) -> Data? {
        guard case .data(let data) = bounded(url, maximumBytes: maximumBytes) else { return nil }
        return data
    }

     
     
    static func read<T: Decodable>(_ type: T.Type, from url: URL, maximumBytes: Int = 1 << 20) -> T? {
        guard let data = data(from: url, maximumBytes: maximumBytes) else { return nil }
        return try? ModuleJSON.decoder().decode(type, from: data)
    }
}

 
 
 
 
 
struct ModuleCAMetadata: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
     
     
    var fingerprintSHA256: String
    var commonName: String
    var createdAt: Date
     
     
     
    var privateKeySHA256: String? = nil
}

 
 
 
 
 
 
 
struct ModuleEngineAssignment: Codable, Equatable, Sendable {
    var ports: ModulePorts
     
    var certEntryIP: String?
     
     
    var decryptsTLS: Bool
     
    var mitmHosts: ModuleHostList
    var forceHTTPEngineHosts: ModuleHostList
     
    var modules: [ModuleGlobalManifest.Module]
    var caFingerprintSHA256: String?
     
     
     
     
     
     
    var reinjectCredentials: ModuleReinjectAuthorization? = nil
     
     
     
     
     
    var engineProxyCredentials: ModuleReinjectAuthorization? = nil

    private enum CodingKeys: String, CodingKey {
        case ports, certEntryIP, decryptsTLS, mitmHosts, forceHTTPEngineHosts, modules, caFingerprintSHA256
        case reinjectCredentials, engineProxyCredentials
    }

    init(ports: ModulePorts, certEntryIP: String?, decryptsTLS: Bool, mitmHosts: ModuleHostList,
         forceHTTPEngineHosts: ModuleHostList, modules: [ModuleGlobalManifest.Module], caFingerprintSHA256: String?,
         reinjectCredentials: ModuleReinjectAuthorization? = nil,
         engineProxyCredentials: ModuleReinjectAuthorization? = nil) {
        self.ports = ports
        self.certEntryIP = certEntryIP
        self.decryptsTLS = decryptsTLS
        self.mitmHosts = mitmHosts
        self.forceHTTPEngineHosts = forceHTTPEngineHosts
        self.modules = modules
        self.caFingerprintSHA256 = caFingerprintSHA256
        self.reinjectCredentials = reinjectCredentials
        self.engineProxyCredentials = engineProxyCredentials
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            ports: try c.decode(ModulePorts.self, forKey: .ports),
            certEntryIP: try c.decodeIfPresent(String.self, forKey: .certEntryIP),
            decryptsTLS: try c.decodeIfPresent(Bool.self, forKey: .decryptsTLS) ?? false,
            mitmHosts: try c.decodeIfPresent(ModuleHostList.self, forKey: .mitmHosts)
                ?? ModuleHostList(items: [], standardPort: ModuleHostList.mitmStandardPort),
            forceHTTPEngineHosts: try c.decodeIfPresent(ModuleHostList.self, forKey: .forceHTTPEngineHosts)
                ?? ModuleHostList(items: [], standardPort: ModuleHostList.forceHTTPStandardPort),
            modules: try c.decodeIfPresent([ModuleGlobalManifest.Module].self, forKey: .modules) ?? [],
            caFingerprintSHA256: try c.decodeIfPresent(String.self, forKey: .caFingerprintSHA256),
            reinjectCredentials: try c.decodeIfPresent(ModuleReinjectAuthorization.self, forKey: .reinjectCredentials),
            engineProxyCredentials: try c.decodeIfPresent(ModuleReinjectAuthorization.self, forKey: .engineProxyCredentials))
    }
}

 
 
 
 
struct ModuleReinjectAuthorization: Codable, Equatable, Sendable {
    let username: String
    let password: String
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ModuleEnginePlan: Equatable, Sendable {
    static let currentSchemaVersion = 1
     
     
    static let retained = 4
     
     
    #if os(macOS)
    static let maximumBytes = Int.max
    #else
    static let maximumBytes = 256 * 1024
    #endif
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    #if os(macOS)
    static let maximumListEntries = Int.max
    static let maximumListBytes = Int.max
    #else
    static let maximumListEntries = 20_000
    static let maximumListBytes = 640 * 1024
    #endif

     
    struct Entry: Equatable, Sendable {
        var revision: ModuleRunningRevision
        var assignment: ModuleEngineAssignment
        var recordedAt: Date
    }

     
    struct Record: Equatable, Sendable {
        enum State: Equatable, Sendable {
             
             
            case recorded(ModuleEngineAssignment, mitmHostsSHA256: String, forceHTTPEngineHostsSHA256: String)
             
             
            case refused(String)
        }

        var revision: ModuleRunningRevision
        var recordedAt: Date
        var state: State
    }

    var schemaVersion: Int
     
    var records: [Record]

    static let empty = ModuleEnginePlan(schemaVersion: currentSchemaVersion, records: [])

    func record(for revision: ModuleRunningRevision) -> Record? {
        records.first { $0.revision == revision }
    }

     
    enum Reading: Equatable, Sendable {
        case absent
        case index(ModuleEnginePlan)
         
         
        case unreadable(String)
         
         
        case failed(String)
    }

    static func read(_ locations: ModuleEngineLocations) -> Reading {
        let data: Data
        switch ModuleEngineFiles.bounded(locations.enginePlans, maximumBytes: maximumBytes) {
        case .absent: return .absent
        case .tooLarge(let limit): return .unreadable(#"engine-plans.json is larger than \#(limit) bytes"#)
        case .failed(let why): return .failed(#"engine-plans.json could not be read: \#(why)"#)
        case .data(let bytes): data = bytes
        }
        do {
            let plan = try ModuleJSON.decoder().decode(ModuleEnginePlan.self, from: data)
            guard plan.schemaVersion == currentSchemaVersion else {
                return .unreadable(#"engine-plans.json is schema \#(plan.schemaVersion), this tunnel reads \#(currentSchemaVersion)"#)
            }
            return .index(plan)
        } catch {
            return .unreadable(#"engine-plans.json is not an engine plan: \#(error)"#)
        }
    }

     
    static func load(_ locations: ModuleEngineLocations) -> ModuleEnginePlan? {
        guard case .index(let plan) = read(locations) else { return nil }
        return plan
    }

     
    enum Lookup: Equatable, Sendable {
         
        case noPlan
         
        case notRecorded
        case entry(Entry)
         
         
        case unreadable(String)
    }

     
    static func entry(for revision: ModuleRunningRevision, locations: ModuleEngineLocations) -> Lookup {
        let plan: ModuleEnginePlan
        switch read(locations) {
        case .absent: return .noPlan
        case .unreadable(let why), .failed(let why): return .unreadable(why)
        case .index(let index): plan = index
        }
        guard let record = plan.record(for: revision) else { return .notRecorded }
        switch record.state {
        case .refused(let why):
            return .unreadable(#"the App could not record this configuration's engine plan: \#(why)"#)
        case .recorded(var assignment, let mitm, let forced):
            do {
                var budget = ModuleHostListFile.Budget()
                assignment.mitmHosts = try ModuleHostListFile.read(mitm, locations: locations, budget: &budget)
                assignment.forceHTTPEngineHosts = try ModuleHostListFile.read(forced, locations: locations, budget: &budget)
            } catch {
                return .unreadable(#"\#(error)"#)
            }
            return .entry(Entry(revision: revision, assignment: assignment, recordedAt: record.recordedAt))
        }
    }

     
     
    private static let writeLock = NSLock()

     
     
     
     
     
     
    nonisolated(unsafe) private static var inFlight: Set<ModuleRunningRevision> = []

     
     
     
    static func settle(_ revision: ModuleRunningRevision) {
        writeLock.lock()
        defer { writeLock.unlock() }
        inFlight.remove(revision)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func record(_ assignment: ModuleEngineAssignment, for revision: ModuleRunningRevision, at: Date,
                       keeping: Set<ModuleRunningRevision>, locations: ModuleEngineLocations,
                       entryLimit: Int = maximumListEntries, listLimit: Int = maximumListBytes,
                       indexLimit: Int = maximumBytes, inFlight: Bool = false) throws {
        try record(assignment, for: revision, at: at, keepingNow: { keeping }, locations: locations,
                   entryLimit: entryLimit, listLimit: listLimit, indexLimit: indexLimit, inFlight: inFlight)
    }

     
     
     
     
     
    static func record(_ assignment: ModuleEngineAssignment, for revision: ModuleRunningRevision, at: Date,
                       keepingNow: () -> Set<ModuleRunningRevision>, locations: ModuleEngineLocations,
                       entryLimit: Int = maximumListEntries, listLimit: Int = maximumListBytes,
                       indexLimit: Int = maximumBytes, inFlight: Bool = false) throws {
        writeLock.lock()
        defer { writeLock.unlock() }
        let keeping = keepingNow().union(Self.inFlight)
        let previous = try existing(locations)
        let mitm = try ModuleHostListFile.encode(assignment.mitmHosts)
        let forced = try ModuleHostListFile.encode(assignment.forceHTTPEngineHosts)
        var refusal: ModuleEnginePlanError?
        var state: Record.State
        let entries = assignment.mitmHosts.items.count + assignment.forceHTTPEngineHosts.items.count
        if entries > entryLimit {
            refusal = .tooManyEntries(entries: entries, limit: entryLimit)
            state = .refused(#"its host lists would be \#(entries) entries, the tunnel reads at most \#(entryLimit)"#)
        } else if mitm.count + forced.count > listLimit {
            refusal = .tooLarge(bytes: mitm.count + forced.count, limit: listLimit)
            state = .refused(#"its host lists would be \#(mitm.count + forced.count) bytes, the tunnel reads at most \#(listLimit)"#)
        } else {
            try ModuleHostListFile.write(mitm, locations: locations)
            try ModuleHostListFile.write(forced, locations: locations)
            var stripped = assignment
            stripped.mitmHosts = ModuleHostList(items: [], standardPort: assignment.mitmHosts.standardPort)
            stripped.forceHTTPEngineHosts = ModuleHostList(items: [], standardPort: assignment.forceHTTPEngineHosts.standardPort)
            state = .recorded(stripped, mitmHostsSHA256: ModuleJSON.sha256(mitm), forceHTTPEngineHostsSHA256: ModuleJSON.sha256(forced))
        }
        var plan = previous.keeping(Record(revision: revision, recordedAt: at, state: state), protecting: keeping)
        var data = try ModuleJSON.encoder().encode(plan)
        while data.count > indexLimit, let dropped = plan.droppingOldestUnprotected(revision, keeping) {
            plan = dropped
            data = try ModuleJSON.encoder().encode(plan)
        }
        if data.count > indexLimit, refusal == nil {
            refusal = .tooLarge(bytes: data.count, limit: indexLimit)
            plan.records[0].state = .refused(#"the plan's index would be \#(data.count) bytes, the tunnel reads at most \#(indexLimit)"#)
            data = try ModuleJSON.encoder().encode(plan)
        }
        guard data.count <= indexLimit else { throw ModuleEnginePlanError.tooLarge(bytes: data.count, limit: indexLimit) }
        try ModuleEngineFiles.write(data, to: locations.enginePlans)
        ModuleHostListFile.sweep(keeping: plan.listDigests.union(previous.listDigests), locations: locations)
        if let refusal { throw refusal }
        if inFlight { Self.inFlight.insert(revision) }
    }

     
     
     
     
     
     
     
    static func prune(keeping: Set<ModuleRunningRevision>, locations: ModuleEngineLocations) throws {
        try prune(keepingNow: { keeping }, locations: locations)
    }

     
    static func prune(keepingNow: () -> Set<ModuleRunningRevision>, locations: ModuleEngineLocations) throws {
        writeLock.lock()
        defer { writeLock.unlock() }
        let keeping = keepingNow().union(Self.inFlight)
        let previous = try existing(locations)
        let plan = ModuleEnginePlan(schemaVersion: currentSchemaVersion,
                                     records: previous.records.filter { keeping.contains($0.revision) })
        guard !plan.records.isEmpty else {
            let manager = FileManager.default
            if manager.fileExists(atPath: locations.enginePlans.path) { try manager.removeItem(at: locations.enginePlans) }
            if manager.fileExists(atPath: locations.hostListsDirectory.path) { try manager.removeItem(at: locations.hostListsDirectory) }
            return
        }
        try ModuleEngineFiles.write(try ModuleJSON.encoder().encode(plan), to: locations.enginePlans)
        ModuleHostListFile.sweep(keeping: plan.listDigests.union(previous.listDigests), locations: locations)
    }

     
     
     
     
     
     
     
     
     
    static func forget(_ revision: ModuleRunningRevision, unlessKept: () -> Set<ModuleRunningRevision> = { [] },
                       locations: ModuleEngineLocations) throws {
        writeLock.lock()
        defer { writeLock.unlock() }
        inFlight.remove(revision)
        guard !unlessKept().contains(revision) else { return }
        let previous = try existing(locations)
        guard previous.record(for: revision) != nil else { return }
        let plan = ModuleEnginePlan(schemaVersion: currentSchemaVersion,
                                     records: previous.records.filter { $0.revision != revision })
        guard !plan.records.isEmpty else {
            let manager = FileManager.default
            if manager.fileExists(atPath: locations.enginePlans.path) { try manager.removeItem(at: locations.enginePlans) }
            if manager.fileExists(atPath: locations.hostListsDirectory.path) { try manager.removeItem(at: locations.hostListsDirectory) }
            return
        }
        try ModuleEngineFiles.write(try ModuleJSON.encoder().encode(plan), to: locations.enginePlans)
        ModuleHostListFile.sweep(keeping: plan.listDigests.union(previous.listDigests), locations: locations)
    }

     
     
    private static func existing(_ locations: ModuleEngineLocations) throws -> ModuleEnginePlan {
        switch read(locations) {
        case .absent, .unreadable: return .empty
        case .index(let plan): return plan
        case .failed(let why): throw ModuleEnginePlanError.unreadable(why)
        }
    }

     
     
    private func keeping(_ record: Record, protecting keeping: Set<ModuleRunningRevision>) -> ModuleEnginePlan {
        let others = records.filter { $0.revision != record.revision }
        let protectedCount = others.filter { keeping.contains($0.revision) }.count
        var spare = max(0, Self.retained - 1 - protectedCount)
        var kept = [record]
        for other in others {
            if keeping.contains(other.revision) {
                kept.append(other)
            } else if spare > 0 {
                kept.append(other)
                spare -= 1
            }
        }
        return ModuleEnginePlan(schemaVersion: Self.currentSchemaVersion, records: kept)
    }

     
    private func droppingOldestUnprotected(_ revision: ModuleRunningRevision,
                                           _ keeping: Set<ModuleRunningRevision>) -> ModuleEnginePlan? {
        guard let index = records.lastIndex(where: { $0.revision != revision && !keeping.contains($0.revision) }) else { return nil }
        var plan = self
        plan.records.remove(at: index)
        return plan
    }

     
    var listDigests: Set<String> {
        Set(records.flatMap { record -> [String] in
            guard case .recorded(_, let mitm, let forced) = record.state else { return [] }
            return [mitm, forced]
        })
    }
}

enum ModuleEnginePlanError: Error, Equatable, Sendable {
     
     
    case tooLarge(bytes: Int, limit: Int)
     
     
    case tooManyEntries(entries: Int, limit: Int)
     
    case unreadable(String)
}

 
 
 
 
 
 
 
 
 
 
 
 
enum ModuleHostListFile {
    static let header = ModuleRuntimeNames.hostListHeader
    static let version = 1

    struct Unreadable: Error, CustomStringConvertible, Equatable {
        let description: String
    }

     
     
     
    static func encode(_ list: ModuleHostList) throws -> Data {
        var modules: [String: Int] = [:]
        var moduleLines = ""
        var entryLines = ""
        entryLines.reserveCapacity(list.items.count * 32)
        for item in list.items {
            let spelling = item.entry.spelling
            guard ModuleHostList.entry(spelling) == item.entry else {
                throw Unreadable(description: #"the host-list entry \#(spelling) does not read back as itself"#)
            }
            let index: Int
            if let known = modules[item.moduleID] {
                index = known
            } else {
                 
                 
                guard !item.moduleID.utf8.contains(10), !item.moduleID.utf8.contains(13) else {
                    throw Unreadable(description: #"a module id holds a line end"#)
                }
                index = modules.count
                modules[item.moduleID] = index
                moduleLines += "@" + item.moduleID + "\n"
            }
            entryLines += String(index) + " " + spelling + "\n"
        }
        return Data((header + " " + String(version) + " " + String(list.standardPort) + "\n" + moduleLines + entryLines).utf8)
    }

     
    struct Budget: Equatable, Sendable {
        var entries = ModuleEnginePlan.maximumListEntries
        var bytes = ModuleEnginePlan.maximumListBytes
    }

    static func decode(_ data: Data) throws -> ModuleHostList {
        var budget = Budget(entries: .max, bytes: .max)
        return try decode(data, entries: &budget.entries)
    }

     
     
    static func decode(_ data: Data, entries: inout Int) throws -> ModuleHostList {
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> ModuleHostList in
            let bytes = raw.bindMemory(to: UInt8.self)
            let newline = UInt8(ascii: "\n")
            var lineCount = 0
            for byte in bytes where byte == newline { lineCount += 1 }
            var cursor = 0
             
            func nextLine() -> Slice<UnsafeBufferPointer<UInt8>>? {
                guard cursor < bytes.count else { return nil }
                var end = cursor
                while end < bytes.count, bytes[end] != newline { end += 1 }
                defer { cursor = end + 1 }
                return bytes[cursor..<end]
            }
            guard let first = nextLine() else { throw Unreadable(description: #"a host list without its first line"#) }
            let fields = String(decoding: UnsafeBufferPointer(rebasing: first), as: UTF8.self).split(separator: " ")
            guard fields.count == 3, ModuleRuntimeNames.isHostListHeader(fields[0]), Int(fields[1]) == version,
                  let standardPort = UInt16(fields[2]) else {
                throw Unreadable(description: #"a host list that is not version \#(version) of this encoding"#)
            }
            var modules: [String] = []
            var items: [ModuleHostList.Item] = []
            items.reserveCapacity(min(lineCount, max(0, entries)))
            while let line = nextLine() {
                if line.first == UInt8(ascii: "@") {
                    modules.append(String(decoding: UnsafeBufferPointer(rebasing: line.dropFirst()), as: UTF8.self))
                    continue
                }
                 
                var index = 0, digits = 0, position = line.startIndex
                while position < line.endIndex, let digit = Optional(line[position]), digit >= 48, digit <= 57, digits < 9 {
                    index = index * 10 + Int(digit - 48)
                    digits += 1
                    position += 1
                }
                guard digits > 0, position < line.endIndex, line[position] == UInt8(ascii: " "), modules.indices.contains(index),
                      let entry = ModuleHostList.entry(String(decoding: UnsafeBufferPointer(rebasing: line[(position + 1)...]),
                                                               as: UTF8.self)) else {
                    throw Unreadable(description: #"the host-list line \#(String(decoding: UnsafeBufferPointer(rebasing: line), as: UTF8.self)) is not an entry"#)
                }
                entries -= 1
                guard entries >= 0 else {
                    throw Unreadable(description: #"this configuration's host lists hold more than \#(ModuleEnginePlan.maximumListEntries) entries"#)
                }
                items.append(ModuleHostList.Item(entry: entry, moduleID: modules[index]))
            }
            return ModuleHostList(items: items, standardPort: standardPort)
        }
    }

     
     
     
    static func write(_ data: Data, locations: ModuleEngineLocations) throws {
        let digest = ModuleJSON.sha256(data)
        let url = locations.hostList(digest)
        if FileManager.default.fileExists(atPath: url.path),
           case .data(let there) = ModuleEngineFiles.bounded(url, maximumBytes: data.count), ModuleJSON.sha256(there) == digest {
            return
        }
        try ModuleEngineFiles.write(data, to: url)
    }

     
    static func read(_ digest: String, locations: ModuleEngineLocations, budget: inout Budget) throws -> ModuleHostList {
        let data: Data
        switch ModuleEngineFiles.bounded(locations.hostList(digest), maximumBytes: max(0, budget.bytes)) {
        case .absent: throw Unreadable(description: #"host list \#(digest) is missing"#)
        case .tooLarge: throw Unreadable(description: #"this configuration's host lists are larger than \#(ModuleEnginePlan.maximumListBytes) bytes"#)
        case .failed(let why): throw Unreadable(description: #"host list \#(digest) could not be read: \#(why)"#)
        case .data(let bytes): data = bytes
        }
        budget.bytes -= data.count
        guard ModuleJSON.sha256(data) == digest else {
            throw Unreadable(description: #"host list \#(digest) holds other bytes"#)
        }
        return try decode(data, entries: &budget.entries)
    }

     
    static func sweep(keeping: Set<String>, locations: ModuleEngineLocations) {
        let directory = locations.hostListsDirectory
        for name in (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            where name.hasSuffix(".list") && !keeping.contains(String(name.dropLast(5))) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}

 
 
 
 
 
extension ModuleEnginePlan: Codable {
    private enum Keys: String, CodingKey { case schemaVersion, entries }

    private struct PlanPorts: Codable, Equatable {
        var engine: UInt16
        var reinject: UInt16

        init(_ ports: ModulePorts) {
            engine = ports.engine
            reinject = ports.reinject
        }

        var ports: ModulePorts { ModulePorts(engine: engine, reinject: reinject) }
    }

    private struct PlanModule: Codable, Equatable {
        var id: String
        var name: String
        var irSHA256: String
        var effectiveCount: Int
        var ignoredCount: Int
         
        var leftOutOrigins: [ModuleLineOrigin]?
         
        var http2: Bool?

        private enum Keys: String, CodingKey { case id, name, irSHA256, effectiveCount, ignoredCount, leftOutOrigins, http2 }

        init(_ module: ModuleGlobalManifest.Module) {
            id = module.id
            name = module.name
            irSHA256 = module.irSHA256
            effectiveCount = module.effectiveCount
            ignoredCount = module.ignoredCount
            leftOutOrigins = module.leftOutOrigins
            http2 = module.http2
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            id = try c.decode(String.self, forKey: .id)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            irSHA256 = try c.decode(String.self, forKey: .irSHA256)
            effectiveCount = try c.decodeIfPresent(Int.self, forKey: .effectiveCount) ?? 0
            ignoredCount = try c.decodeIfPresent(Int.self, forKey: .ignoredCount) ?? 0
            leftOutOrigins = try c.decodeIfPresent([ModuleLineOrigin].self, forKey: .leftOutOrigins)
            http2 = try c.decodeIfPresent(Bool.self, forKey: .http2)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(id, forKey: .id)
            try c.encode(name, forKey: .name)
            try c.encode(irSHA256, forKey: .irSHA256)
            try c.encode(effectiveCount, forKey: .effectiveCount)
            try c.encode(ignoredCount, forKey: .ignoredCount)
            try c.encodeIfPresent(leftOutOrigins, forKey: .leftOutOrigins)
            try c.encodeIfPresent(http2, forKey: .http2)
        }

        var module: ModuleGlobalManifest.Module {
            ModuleGlobalManifest.Module(id: id, name: name, irSHA256: irSHA256, effectiveCount: effectiveCount, ignoredCount: ignoredCount,
                                         leftOutOrigins: leftOutOrigins, http2: http2)
        }
    }

     
    private struct Stored: Codable, Equatable {
        var revision: ModuleRunningRevision
        var recordedAt: Date
        var refused: String?
        var ports: PlanPorts?
        var certEntryIP: String?
        var decryptsTLS: Bool
        var mitmHostsSHA256: String?
        var mitmStandardPort: UInt16
        var forceHTTPEngineHostsSHA256: String?
        var forceHTTPStandardPort: UInt16
        var modules: [PlanModule]
        var caFingerprintSHA256: String?
        var reinjectCredentials: ModuleReinjectAuthorization?
        var engineProxyCredentials: ModuleReinjectAuthorization?

        private enum Keys: String, CodingKey {
            case revision, recordedAt, refused, ports, certEntryIP, decryptsTLS, mitmHostsSHA256, mitmStandardPort
            case forceHTTPEngineHostsSHA256, forceHTTPStandardPort, modules, caFingerprintSHA256, reinjectCredentials
            case engineProxyCredentials
        }

        init(_ record: Record) {
            revision = record.revision
            recordedAt = record.recordedAt
            switch record.state {
            case .refused(let why):
                refused = why
                ports = nil
                certEntryIP = nil
                decryptsTLS = false
                mitmHostsSHA256 = nil
                mitmStandardPort = ModuleHostList.mitmStandardPort
                forceHTTPEngineHostsSHA256 = nil
                forceHTTPStandardPort = ModuleHostList.forceHTTPStandardPort
                modules = []
                caFingerprintSHA256 = nil
                reinjectCredentials = nil
                engineProxyCredentials = nil
            case .recorded(let assignment, let mitm, let forced):
                refused = nil
                ports = PlanPorts(assignment.ports)
                certEntryIP = assignment.certEntryIP
                decryptsTLS = assignment.decryptsTLS
                mitmHostsSHA256 = mitm
                mitmStandardPort = assignment.mitmHosts.standardPort
                forceHTTPEngineHostsSHA256 = forced
                forceHTTPStandardPort = assignment.forceHTTPEngineHosts.standardPort
                modules = assignment.modules.map(PlanModule.init)
                caFingerprintSHA256 = assignment.caFingerprintSHA256
                reinjectCredentials = assignment.reinjectCredentials
                engineProxyCredentials = assignment.engineProxyCredentials
            }
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            revision = try c.decode(ModuleRunningRevision.self, forKey: .revision)
            recordedAt = try c.decodeIfPresent(Date.self, forKey: .recordedAt) ?? .distantPast
            refused = try c.decodeIfPresent(String.self, forKey: .refused)
            ports = try c.decodeIfPresent(PlanPorts.self, forKey: .ports)
            certEntryIP = try c.decodeIfPresent(String.self, forKey: .certEntryIP)
            decryptsTLS = try c.decodeIfPresent(Bool.self, forKey: .decryptsTLS) ?? false
            mitmHostsSHA256 = try c.decodeIfPresent(String.self, forKey: .mitmHostsSHA256)
            mitmStandardPort = try c.decodeIfPresent(UInt16.self, forKey: .mitmStandardPort) ?? ModuleHostList.mitmStandardPort
            forceHTTPEngineHostsSHA256 = try c.decodeIfPresent(String.self, forKey: .forceHTTPEngineHostsSHA256)
            forceHTTPStandardPort = try c.decodeIfPresent(UInt16.self, forKey: .forceHTTPStandardPort)
                ?? ModuleHostList.forceHTTPStandardPort
            modules = try c.decodeIfPresent([PlanModule].self, forKey: .modules) ?? []
            caFingerprintSHA256 = try c.decodeIfPresent(String.self, forKey: .caFingerprintSHA256)
            reinjectCredentials = try c.decodeIfPresent(ModuleReinjectAuthorization.self, forKey: .reinjectCredentials)
            engineProxyCredentials = try c.decodeIfPresent(ModuleReinjectAuthorization.self, forKey: .engineProxyCredentials)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(revision, forKey: .revision)
            try c.encode(recordedAt, forKey: .recordedAt)
            try c.encodeIfPresent(refused, forKey: .refused)
            try c.encodeIfPresent(ports, forKey: .ports)
            try c.encodeIfPresent(certEntryIP, forKey: .certEntryIP)
            try c.encode(decryptsTLS, forKey: .decryptsTLS)
            try c.encodeIfPresent(mitmHostsSHA256, forKey: .mitmHostsSHA256)
            try c.encode(mitmStandardPort, forKey: .mitmStandardPort)
            try c.encodeIfPresent(forceHTTPEngineHostsSHA256, forKey: .forceHTTPEngineHostsSHA256)
            try c.encode(forceHTTPStandardPort, forKey: .forceHTTPStandardPort)
            try c.encode(modules, forKey: .modules)
            try c.encodeIfPresent(caFingerprintSHA256, forKey: .caFingerprintSHA256)
            try c.encodeIfPresent(reinjectCredentials, forKey: .reinjectCredentials)
            try c.encodeIfPresent(engineProxyCredentials, forKey: .engineProxyCredentials)
        }

         
        func record() throws -> Record {
            if let refused { return Record(revision: revision, recordedAt: recordedAt, state: .refused(refused)) }
            guard let ports, let mitm = mitmHostsSHA256, let forced = forceHTTPEngineHostsSHA256 else {
                throw ModuleHostListFile.Unreadable(description: #"a record without its ports or its lists"#)
            }
            let assignment = ModuleEngineAssignment(
                ports: ports.ports, certEntryIP: certEntryIP, decryptsTLS: decryptsTLS,
                mitmHosts: ModuleHostList(items: [], standardPort: mitmStandardPort),
                forceHTTPEngineHosts: ModuleHostList(items: [], standardPort: forceHTTPStandardPort),
                modules: modules.map(\.module), caFingerprintSHA256: caFingerprintSHA256,
                reinjectCredentials: reinjectCredentials, engineProxyCredentials: engineProxyCredentials)
            return Record(revision: revision, recordedAt: recordedAt,
                          state: .recorded(assignment, mitmHostsSHA256: mitm, forceHTTPEngineHostsSHA256: forced))
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let stored = try c.decodeIfPresent([Stored].self, forKey: .entries) ?? []
        self.init(schemaVersion: try c.decode(Int.self, forKey: .schemaVersion), records: try stored.map { try $0.record() })
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(records.map(Stored.init), forKey: .entries)
    }
}

 
 
 
 
struct ModuleEngineCounters: Codable, Equatable, Sendable {
    var rewriteRules = 0
    var rewritePatternBytes = 0
    var rewriteCompileFailed = 0
    var rewriteGateLiterals = 0
    var rewriteGateBytes = 0
    var rewriteUngated = 0
    var rewriteUnsupported = 0
     
    var rewriteRegexTimeouts = 0
     
     
     
    var rewriteOverBudget = 0
    var rewriteOutputTooLarge = 0
    var scriptRules = 0
    var scriptGateLiterals = 0
    var scriptUngated = 0
     
    var scriptOverBudget = 0
     
     
    var rulesLeftOutThisRun = 0
     
     
    var rulesLeftOutTooLargeThisRun = 0
    var requestsTotal = 0
    var regexExecutionsTotal = 0
     
     
    var requestBudgetStopsTotal = 0
    var rejectsTotal = 0
    var dropsTotal = 0
    var redirectsTotal = 0
    var headerRewritesTotal = 0
    var bodyRewritesTotal = 0
    var scriptsRunTotal = 0
    var scriptsSkippedTotal = 0
    var scriptsAbortedTotal = 0
    var scriptsTimedOutTotal = 0
     
     
    var scriptContexts = 0
    var scriptContextsPeak = 0
    var scriptsQuarantined = 0
    var bodyCollectBytes = 0
    var bodyCollectionsTotal = 0
    var bodyCollectBytesTotal = 0
    var bodyCollectBytesPeak = 0
    var bodyLimitExceeded = 0
    var bodySkippedTotal = 0
    var mitmSessions = 0
    var mitmSessionsTotal = 0
    var mitmSessionsPeak = 0
     
     
     
    var mitmSessionsCappedTotal = 0
     
     
     
    var plainSessionsCappedTotal = 0
     
     
    var capRefusalsTotal = 0
     
     
     
     
     
     
     
     
    var ladderScriptsStoppedTotal = 0
    var ladderEngineStoppedTotal = 0
     
     
     
     
    var tlsNameMismatchRelayedTotal = 0
     
    var proxyAuthRefusedTotal = 0
     
     
    var unlistedRelayedTotal = 0
    var passThroughSessionsTotal = 0
    var refusedConnectsTotal = 0
    var loopBreaksTotal = 0
    var upstreamFailuresTotal = 0
    var upstreamUntrustedTotal = 0
    var pinningSuspectedTotal = 0
    var certificatePageServedTotal = 0
    var certificateHandedOutTotal = 0

    enum CodingKeys: String, CodingKey {
        case rewriteRules = "rewrite_rules"
        case rewritePatternBytes = "rewrite_pattern_bytes"
        case rewriteCompileFailed = "rewrite_compile_failed"
        case rewriteGateLiterals = "rewrite_gate_literals"
        case rewriteGateBytes = "rewrite_gate_bytes"
        case rewriteUngated = "rewrite_ungated"
        case rewriteUnsupported = "rewrite_unsupported"
        case rewriteRegexTimeouts = "rewrite_regex_timeouts"
        case rewriteOverBudget = "rewrite_over_budget"
        case rewriteOutputTooLarge = "rewrite_output_too_large"
        case scriptRules = "script_rules"
        case scriptGateLiterals = "script_gate_literals"
        case scriptUngated = "script_ungated"
        case scriptOverBudget = "script_over_budget"
        case rulesLeftOutThisRun = "rules_left_out_this_run"
        case rulesLeftOutTooLargeThisRun = "rules_left_out_too_large_this_run"
        case requestsTotal = "requests_total"
        case regexExecutionsTotal = "regex_executions_total"
        case requestBudgetStopsTotal = "request_budget_stops_total"
        case rejectsTotal = "rejects_total"
        case dropsTotal = "drops_total"
        case redirectsTotal = "redirects_total"
        case headerRewritesTotal = "header_rewrites_total"
        case bodyRewritesTotal = "body_rewrites_total"
        case scriptsRunTotal = "scripts_run_total"
        case scriptsSkippedTotal = "scripts_skipped_total"
        case scriptsAbortedTotal = "scripts_aborted_total"
        case scriptsTimedOutTotal = "scripts_timed_out_total"
        case scriptContexts = "script_contexts"
        case scriptContextsPeak = "script_contexts_peak"
        case scriptsQuarantined = "scripts_quarantined"
        case bodyCollectBytes = "body_collect_bytes"
        case bodyCollectionsTotal = "body_collections_total"
        case bodyCollectBytesTotal = "body_collect_bytes_total"
        case bodyCollectBytesPeak = "body_collect_bytes_peak"
        case bodyLimitExceeded = "body_limit_exceeded"
        case bodySkippedTotal = "body_skipped_total"
        case mitmSessions = "mitm_sessions"
        case mitmSessionsTotal = "mitm_sessions_total"
        case mitmSessionsPeak = "mitm_sessions_peak"
        case mitmSessionsCappedTotal = "mitm_sessions_capped_total"
        case plainSessionsCappedTotal = "plain_sessions_capped_total"
        case capRefusalsTotal = "cap_refusals_total"
        case ladderScriptsStoppedTotal = "ladder_scripts_stopped_total"
        case ladderEngineStoppedTotal = "ladder_engine_stopped_total"
        case tlsNameMismatchRelayedTotal = "tls_name_mismatch_relayed_total"
        case proxyAuthRefusedTotal = "proxy_auth_refused_total"
        case unlistedRelayedTotal = "unlisted_relayed_total"
        case passThroughSessionsTotal = "pass_through_sessions_total"
        case refusedConnectsTotal = "refused_connects_total"
        case loopBreaksTotal = "loop_breaks_total"
        case upstreamFailuresTotal = "upstream_failures_total"
        case upstreamUntrustedTotal = "upstream_untrusted_total"
        case pinningSuspectedTotal = "pinning_suspected_total"
        case certificatePageServedTotal = "certificate_page_served_total"
        case certificateHandedOutTotal = "certificate_handed_out_total"
    }
}

 
 
extension ModuleEngineCounters {
    private static let fields: [(CodingKeys, WritableKeyPath<ModuleEngineCounters, Int>)] = [
        (.rewriteRules, \.rewriteRules),
        (.rewritePatternBytes, \.rewritePatternBytes),
        (.rewriteCompileFailed, \.rewriteCompileFailed),
        (.rewriteGateLiterals, \.rewriteGateLiterals),
        (.rewriteGateBytes, \.rewriteGateBytes),
        (.rewriteUngated, \.rewriteUngated),
        (.rewriteUnsupported, \.rewriteUnsupported),
        (.rewriteRegexTimeouts, \.rewriteRegexTimeouts),
        (.rewriteOverBudget, \.rewriteOverBudget),
        (.rewriteOutputTooLarge, \.rewriteOutputTooLarge),
        (.scriptRules, \.scriptRules),
        (.scriptGateLiterals, \.scriptGateLiterals),
        (.scriptUngated, \.scriptUngated),
        (.scriptOverBudget, \.scriptOverBudget),
        (.rulesLeftOutThisRun, \.rulesLeftOutThisRun),
        (.rulesLeftOutTooLargeThisRun, \.rulesLeftOutTooLargeThisRun),
        (.requestsTotal, \.requestsTotal),
        (.regexExecutionsTotal, \.regexExecutionsTotal),
        (.requestBudgetStopsTotal, \.requestBudgetStopsTotal),
        (.rejectsTotal, \.rejectsTotal),
        (.dropsTotal, \.dropsTotal),
        (.redirectsTotal, \.redirectsTotal),
        (.headerRewritesTotal, \.headerRewritesTotal),
        (.bodyRewritesTotal, \.bodyRewritesTotal),
        (.scriptsRunTotal, \.scriptsRunTotal),
        (.scriptsSkippedTotal, \.scriptsSkippedTotal),
        (.scriptsAbortedTotal, \.scriptsAbortedTotal),
        (.scriptsTimedOutTotal, \.scriptsTimedOutTotal),
        (.scriptContexts, \.scriptContexts),
        (.scriptContextsPeak, \.scriptContextsPeak),
        (.scriptsQuarantined, \.scriptsQuarantined),
        (.bodyCollectBytes, \.bodyCollectBytes),
        (.bodyCollectionsTotal, \.bodyCollectionsTotal),
        (.bodyCollectBytesTotal, \.bodyCollectBytesTotal),
        (.bodyCollectBytesPeak, \.bodyCollectBytesPeak),
        (.bodyLimitExceeded, \.bodyLimitExceeded),
        (.bodySkippedTotal, \.bodySkippedTotal),
        (.mitmSessions, \.mitmSessions),
        (.mitmSessionsTotal, \.mitmSessionsTotal),
        (.mitmSessionsPeak, \.mitmSessionsPeak),
        (.mitmSessionsCappedTotal, \.mitmSessionsCappedTotal),
        (.plainSessionsCappedTotal, \.plainSessionsCappedTotal),
        (.capRefusalsTotal, \.capRefusalsTotal),
        (.ladderScriptsStoppedTotal, \.ladderScriptsStoppedTotal),
        (.ladderEngineStoppedTotal, \.ladderEngineStoppedTotal),
        (.tlsNameMismatchRelayedTotal, \.tlsNameMismatchRelayedTotal),
        (.proxyAuthRefusedTotal, \.proxyAuthRefusedTotal),
        (.unlistedRelayedTotal, \.unlistedRelayedTotal),
        (.passThroughSessionsTotal, \.passThroughSessionsTotal),
        (.refusedConnectsTotal, \.refusedConnectsTotal),
        (.loopBreaksTotal, \.loopBreaksTotal),
        (.upstreamFailuresTotal, \.upstreamFailuresTotal),
        (.upstreamUntrustedTotal, \.upstreamUntrustedTotal),
        (.pinningSuspectedTotal, \.pinningSuspectedTotal),
        (.certificatePageServedTotal, \.certificatePageServedTotal),
        (.certificateHandedOutTotal, \.certificateHandedOutTotal),
    ]

     
    private static let openNow: Set<CodingKeys> = [.scriptContexts, .bodyCollectBytes, .mitmSessions]

     
     
     
     
     
     
     
     
     
     
     
    mutating func carryTheRun(from before: ModuleEngineCounters) {
        for (key, path) in Self.fields where !Self.openNow.contains(key) {
            self[keyPath: path] = key.rawValue.hasSuffix("_peak") ? max(self[keyPath: path], before[keyPath: path])
                : self[keyPath: path] + before[keyPath: path]
        }
    }

    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        for (key, path) in Self.fields {
            if let value = try container.decodeIfPresent(Int.self, forKey: key) { self[keyPath: path] = value }
        }
    }
}

 
 
struct ModuleEngineReport: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let pinnedHostLimit = 32

    enum State: String, Codable, Sendable {
        case starting
        case running
         
         
        case passThrough
        case stopped
        case failed

         
         
         
        init(from decoder: Decoder) throws {
            self = State(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .starting
        }
    }

    enum Failure: Codable, Equatable, Sendable {
        case bindFailed(port: UInt16, reason: String)
        case reinjectUnanswered(port: UInt16, reason: String)
         
         
        case reinjectNeedsAuthentication(port: UInt16, reason: String)
        case certificateUnreadable(reason: String)
         
         
         
         
         
         
         
         
         
        case planUnreadable(reason: String)
         
         
         
        case engineSignInMissing(reason: String)
    }

     
     
     
    struct OmittedModule: Codable, Equatable, Sendable {
        enum Reason: String, Codable, Sendable {
             
            case unreadable
             
             
            case digestMismatch
             
            case scriptMismatch
             
             
             
             
            case overBudget
             
             
             
             
             
            case overSharedBudget

             
             
             
             
            init(from decoder: Decoder) throws {
                self = Reason(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unreadable
            }
        }

        var id: String
        var name: String
        var reason: Reason
         
        var detail: String
    }

     
     
     
     
     
     
    enum Rung: Int, Codable, Comparable, Sendable {
        case normal = 0
        case scriptsStopped = 1
        case engineStopped = 3

        static func < (lhs: Rung, rhs: Rung) -> Bool { lhs.rawValue < rhs.rawValue }

         
         
         
         
        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer().decode(Int.self)
            self = Rung(rawValue: value) ?? (value > Rung.engineStopped.rawValue ? .engineStopped : .normal)
        }
    }

     
    enum RungCause: String, Codable, Sendable {
        case memoryHeadroom
         
        case scriptsUnavailable
    }

     
    struct PinnedHost: Codable, Equatable, Sendable {
        var host: String
        var count: Int
        var lastAt: Date
         
        var passedThrough: Bool
    }

    var schemaVersion: Int
    var processStartedAt: Date
    var updatedAt: Date
    var revision: ModuleRunningRevision?
    var ports: ModulePorts?
    var state: State
    var failure: Failure?
    var rung: Rung
    var rungCause: RungCause?
    var rungAt: Date?
     
    var lastMemoryStopAt: Date?
    var footprintBytes: Int64?
    var headroomBytes: Int64?
    var counters: ModuleEngineCounters
    var pinnedHosts: [PinnedHost]
     
     
    var certificateServedAt: [String: Date]
     
     
     
     
     
     
     
    var identityFailedAt: [String: Date]
     
     
    var identityRetriedAt: [String: Date] = [:]
     
     
    var omittedModules: [OmittedModule]

    static func initial(startedAt: Date, carrying previous: ModuleEngineReport?) -> ModuleEngineReport {
        ModuleEngineReport(
            schemaVersion: currentSchemaVersion, processStartedAt: startedAt, updatedAt: startedAt,
            revision: nil, ports: nil, state: .starting, failure: nil, rung: .normal, rungCause: nil, rungAt: nil,
            lastMemoryStopAt: previous?.lastMemoryStopAt, footprintBytes: nil, headroomBytes: nil,
            counters: ModuleEngineCounters(),
            pinnedHosts: (previous?.pinnedHosts ?? []).map { host in
                var kept = host
                kept.passedThrough = false
                return kept
            },
            certificateServedAt: previous?.certificateServedAt ?? [:],
            identityFailedAt: previous?.identityFailedAt ?? [:],
            identityRetriedAt: previous?.identityRetriedAt ?? [:],
            omittedModules: [])
    }

    static func load(_ locations: ModuleEngineLocations) -> ModuleEngineReport? {
        guard let report = ModuleEngineFiles.read(ModuleEngineReport.self, from: locations.engineReport),
              report.schemaVersion == currentSchemaVersion else { return nil }
        return report
    }
}

 
 
 
extension ModuleEngineReport {
    private enum Keys: String, CodingKey {
        case schemaVersion, processStartedAt, updatedAt, revision, ports, state, failure, rung, rungCause, rungAt
        case lastMemoryStopAt, footprintBytes, headroomBytes, counters, pinnedHosts, certificateServedAt, identityFailedAt
        case identityRetriedAt, omittedModules
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(
            schemaVersion: try c.decode(Int.self, forKey: .schemaVersion),
            processStartedAt: try c.decode(Date.self, forKey: .processStartedAt),
            updatedAt: try c.decode(Date.self, forKey: .updatedAt),
            revision: try c.decodeIfPresent(ModuleRunningRevision.self, forKey: .revision),
            ports: try c.decodeIfPresent(ModulePorts.self, forKey: .ports),
            state: try c.decodeIfPresent(State.self, forKey: .state) ?? .starting,
            failure: try Self.failure(in: c),
            rung: try c.decodeIfPresent(Rung.self, forKey: .rung) ?? .normal,
             
            rungCause: try c.decodeIfPresent(String.self, forKey: .rungCause).flatMap(RungCause.init(rawValue:)),
            rungAt: try c.decodeIfPresent(Date.self, forKey: .rungAt),
            lastMemoryStopAt: try c.decodeIfPresent(Date.self, forKey: .lastMemoryStopAt),
            footprintBytes: try c.decodeIfPresent(Int64.self, forKey: .footprintBytes),
            headroomBytes: try c.decodeIfPresent(Int64.self, forKey: .headroomBytes),
            counters: try c.decodeIfPresent(ModuleEngineCounters.self, forKey: .counters) ?? ModuleEngineCounters(),
            pinnedHosts: try c.decodeIfPresent([PinnedHost].self, forKey: .pinnedHosts) ?? [],
            certificateServedAt: try c.decodeIfPresent([String: Date].self, forKey: .certificateServedAt) ?? [:],
            identityFailedAt: try c.decodeIfPresent([String: Date].self, forKey: .identityFailedAt) ?? [:],
            identityRetriedAt: try c.decodeIfPresent([String: Date].self, forKey: .identityRetriedAt) ?? [:],
            omittedModules: try c.decodeIfPresent([OmittedModule].self, forKey: .omittedModules) ?? [])
    }

    private struct SpelledKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ stringValue: String) { self.stringValue = stringValue }
        init?(stringValue: String) { self.init(stringValue) }
        init?(intValue: Int) { nil }
    }

     
     
     
     
     
    private static func failure(in c: KeyedDecodingContainer<Keys>) throws -> Failure? {
        guard c.contains(.failure), try !c.decodeNil(forKey: .failure) else { return nil }
        if let known = try? c.decode(Failure.self, forKey: .failure) { return known }
        let spelled = try? c.nestedContainer(keyedBy: SpelledKey.self, forKey: .failure)
        let name = spelled?.allKeys.first
        let reason = name.flatMap { name in
            try? spelled?.nestedContainer(keyedBy: SpelledKey.self, forKey: name).decode(String.self, forKey: SpelledKey("reason"))
        }
        return .planUnreadable(reason: "the tunnel reported a failure this version does not read: \(name?.stringValue ?? "not a failure")"
                                   + (reason.map { " (\($0))" } ?? ""))
    }
}

 
 
 
 
extension ModuleEngineReport {
     
     
    func identityDegradeHolds(for fingerprint: String) -> Bool {
        guard let failed = identityFailedAt[fingerprint], let retried = identityRetriedAt[fingerprint] else { return false }
        return failed.timeIntervalSince(retried) >= 0
    }

     
     
    mutating func beginIdentityRetry(for fingerprint: String, at now: Date) -> Bool {
        guard identityFailedAt[fingerprint] != nil, identityRetriedAt[fingerprint] == nil else { return false }
        identityRetriedAt[fingerprint] = now
        return true
    }

     
    mutating func noteIdentityWorked(for fingerprint: String) {
        identityFailedAt[fingerprint] = nil
        identityRetriedAt[fingerprint] = nil
    }
}

extension ModuleEngineReport.Failure {
     
     
     
     
     
    var newPortsMayCure: Bool {
        switch self {
        case .bindFailed, .reinjectUnanswered: return true
        case .reinjectNeedsAuthentication, .certificateUnreadable, .planUnreadable, .engineSignInMissing: return false
        }
    }
}

 
 
 
 
 
struct ModulePortRedraws: Codable, Equatable, Sendable {
    static let limit = 2
    static let window: TimeInterval = 600

     
    private(set) var drawnAt: [Date] = []

    init() {}

    func allowsAnother(at now: Date) -> Bool {
        drawnAt.filter { now.timeIntervalSince($0) < Self.window }.count < Self.limit
    }

    mutating func note(at now: Date) {
        drawnAt = drawnAt.filter { now.timeIntervalSince($0) < Self.window } + [now]
    }
}

 
 
 
enum ModuleEngineSignal {
     
    static let statusChanged = "org.example.clash.adblock.engine-status"
     
     
    static let modulesChanged = "org.example.clash.adblock.modules-changed"

    static func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(statusChanged as CFString), nil, nil, true)
    }

    static func postModulesChanged() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(modulesChanged as CFString), nil, nil, true)
    }
}

 
 
 
 
 
enum ModuleRuntimeNames {
    struct Generation: Equatable, Sendable {
         
        let engineProxy: String
         
        let reinjectListener: String
    }

    static let current = Generation(engineProxy: "MODULE-ENGINE", reinjectListener: "module-reinject")
     
    static let legacy = [Generation(engineProxy: "ADBLOCK-ENGINE", reinjectListener: "adblock-reinject")]  
     
    static let all = [current] + legacy

    static let hostListHeader = "clash-module-hosts"
     
    static let legacyHostListHeaders = ["clash-adblock-hosts"]  

    static func isHostListHeader(_ word: some StringProtocol) -> Bool {
        word == hostListHeader || legacyHostListHeaders.contains { $0 == word }
    }

     
     
    static func reinjectGeneration(of name: String) -> Generation? {
        all.first { generation in
            guard name.hasPrefix(generation.reinjectListener) else { return false }
            let rest = name.dropFirst(generation.reinjectListener.count)
            return rest.isEmpty
                || (rest.hasPrefix("-") && rest.count > 1 && rest.dropFirst().allSatisfy { $0.isASCII && $0.isNumber })
        }
    }

     
    static func engineGeneration(of name: String) -> Generation? {
        all.first { $0.engineProxy == name }
    }
}
