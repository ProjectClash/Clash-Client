import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

 
public struct ConfigurationSubscriptionUsage: Codable, Equatable, Sendable {
    public var upload: Int64
    public var download: Int64
    public var total: Int64
    public var expire: Int64
    public init(upload: Int64, download: Int64, total: Int64, expire: Int64) {
        self.upload = upload; self.download = download; self.total = total; self.expire = expire
    }
    public var used: Int64 {
        let (sum, overflow) = max(0, upload).addingReportingOverflow(max(0, download))
        return overflow ? Int64.max : sum
    }
    public var fraction: Double? {
        total > 0 ? min(Double(used) / Double(total), 1) : nil
    }
}

public struct ConfigurationSourceRecord: Codable, Equatable, Identifiable, Sendable {
    public enum Origin: Codable, Equatable, Sendable {
        case subscription(String)
        case file(String)
        case customNodes
        case bundled(String)
    }
    public let id: String
    public var label: String
    public var origin: Origin
    public var version: String
    public var nodeCount: Int
    public var providerCount: Int
    public var groupCount: Int
    public var ruleCount: Int
    public var ruleProviderCount: Int? = nil
    public var hasRules: Bool { ruleCount > 0 || (ruleProviderCount ?? 0) > 0 }
    public var suppliesNodes: Bool
    public var updatedAt: Date
    public var updateIntervalHours: Int?
    public var userAgent: String?
    public var dnsOverHTTPS: String?
    public var ruleBaselineRequired: Bool?
     
     
    public var registersSuppliedRules: Bool?
     
     
     
    public var isRetainedSnapshot: Bool? = nil
     
     
     
     
     
     
    public var privateToConfigurationID: String? = nil
     
     
    public var isListedInLibrary: Bool { isRetainedSnapshot != true && privateToConfigurationID == nil }
    public var nodeChain: ConfigurationNodeChain? = nil
    public var subscriptionUsage: ConfigurationSubscriptionUsage? = nil
     
     
     
     
     
    public var rulesWrittenInOriginal: Bool? = nil

    public init(id: String = UUID().uuidString, label: String, origin: Origin,
                version: String = UUID().uuidString, nodeCount: Int = 0,
                providerCount: Int = 0, groupCount: Int = 0, ruleCount: Int = 0,
                suppliesNodes: Bool = true, updatedAt: Date = Date(),
                updateIntervalHours: Int? = nil, userAgent: String? = nil,
                dnsOverHTTPS: String? = nil, registersSuppliedRules: Bool? = false) {
        self.id = id; self.label = label; self.origin = origin; self.version = version
        self.nodeCount = nodeCount; self.providerCount = providerCount
        self.groupCount = groupCount; self.ruleCount = ruleCount
        self.suppliesNodes = suppliesNodes; self.updatedAt = updatedAt
        self.updateIntervalHours = updateIntervalHours
        self.userAgent = userAgent; self.dnsOverHTTPS = dnsOverHTTPS
        self.registersSuppliedRules = registersSuppliedRules
    }
}

public extension ConfigurationSourceRecord {
     
     
     
     
     
     
    var hasBuiltinName: Bool { Self.isBuiltinName(label, origin: origin) }

    static func isBuiltinName(_ label: String, origin: Origin) -> Bool {
        origin == .customNodes && label == ConfigurationBuiltins.customNodesName
    }
}

public struct ConfigurationSourceSettingsDraft: Equatable, Sendable {
    public var url: String
     
    public var intervalHours: Int
    public init(source: ConfigurationSourceRecord) {
        if case .subscription(let value) = source.origin { url = value } else { url = "" }
        intervalHours = source.updateIntervalHours ?? 0
    }
}

public struct ConfigurationRuleScheme: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case supplied, builtin, community, imported, custom }
    public let id: String
    public var label: String
    public var kind: Kind
    public let sourceID: String
     
    public var isRetainedSnapshot: Bool? = nil
     
     
     
    public var privateToConfigurationID: String? = nil
    public var isListedInLibrary: Bool { isRetainedSnapshot != true && privateToConfigurationID == nil }
    public var collectionKey: String? = nil
    public var baseSchemeID: String? = nil
    public var initialDocumentJSON: String? = nil
    public var generatedRuleGroups: [String: String]? = nil
     
     
     
    public var disabledRules: [String]? = nil
    public var ruleNotes: [String: String]? = nil
     
     
     
     
     
    public var pageJSON: String? = nil
     
     
     
     
     
    public var pageFollowsSource: Bool? = nil
     
     
     
     
     
    public var rulesFromSchemeID: String? = nil
     
     
     
     
     
     
     
    public var rulesCustomizedFromSchemeID: String? = nil
     
     
     
     
    public var ownViewOfCustomScheme: Bool? = nil
     
     
     
     
     
     
     
     
    public var namedNodes: [String]? = nil
     
     
     
    public var namedNodesSourceID: String? = nil
    public init(id: String = UUID().uuidString, label: String, kind: Kind, sourceID: String) {
        self.id = id; self.label = label; self.kind = kind; self.sourceID = sourceID
    }
}

public struct ConfigurationSourceVersion: Codable, Hashable, Sendable {
    public let id: String
    public let version: String
    public init(id: String, version: String) { self.id = id; self.version = version }
    public init(_ record: ConfigurationSourceRecord) { id = record.id; version = record.version }
}

public enum ConfigurationDNSMode: String, Codable, Equatable, Sendable {
    case system
    case source  
    case custom
}

public enum ConfigurationDNSSettings {
    public static var automatic: OrderedJSON {
        .object([("enable", .scalar("true")), ("enhanced-mode", .string("fake-ip")),
                 ("nameserver", .array([.string("system")])),
                 ("default-nameserver", .array([.string("system")])),
                 ("proxy-server-nameserver", .array([.string("system")]))])
    }
    public static func custom(_ json: String?) throws -> OrderedJSON {
        guard let json, case .object = try OrderedJSON.parse(json) else {
            throw ConfigurationCompositionError.invalidDocument("DNS")
        }
        return try OrderedJSON.parse(json).settingTopLevel("enable", to: .scalar("true"))
    }
}

 
 
public enum ConfigurationSettingsDocument {
    public static func project(_ document: OrderedJSON) -> OrderedJSON {
        guard case .object(let entries) = document else { return .object([]) }
        let resourceKeys = ConfigurationRuleDocument.keys.union(["proxies", "proxy-providers"])
        return .object(entries.filter { !resourceKeys.contains($0.key) })
    }
    public static func parse(_ json: String) throws -> OrderedJSON {
        let document = try OrderedJSON.parse(json)
        guard case .object = document, project(document) == document else {
            throw ConfigurationCompositionError.invalidDocument("Profile settings")
        }
        return document
    }
}

public struct ConfigurationRecipe: Codable, Equatable, Identifiable, Sendable {
     
    public let id: String
    public var label: String
    public var sources: [ConfigurationSourceVersion]
    public var ruleSchemeID: String
    public var ruleSource: ConfigurationSourceVersion
    public var followsUpdates: Bool
     
    public var preservesOriginal: Bool? = nil
    public var nodeScopes: [String: ConfigurationNodeScope]? = nil
    public var settingsRuleDependencies: [String: ConfigurationSourceVersion]? = nil
     
    public var nodeNameservers: [String]?
     
    public var customDNSJSON: String?
     
    public var settingsJSON: String?
     
     
     
     
     
     
     
    public var originalSettingsJSON: String? = nil
     
    public var settingsSource: ConfigurationSourceVersion?
     
     
     
     
     
     
    public var droppedRules: [String]? = nil
     
     
     
     
    public var composedRuleSchemeID: String? = nil
     
     
     
     
     
     
     
     
     
    public var ownCopyOf: ConfigurationOwnCopyOrigin? = nil
    public var dependencies: [ConfigurationSourceVersion] {
        sources + [ruleSource] + (settingsSource.map { [$0] } ?? []) + Array((settingsRuleDependencies ?? [:]).values)
    }
    public var dnsMode: ConfigurationDNSMode?

     
     
    public mutating func clearLegacyPage() {
        settingsJSON = "{}"
        dnsMode = nil
        customDNSJSON = nil
        nodeNameservers = nil
    }

    public init(id: String = UUID().uuidString.lowercased(), label: String,
                sources: [ConfigurationSourceVersion], ruleSchemeID: String,
                ruleSource: ConfigurationSourceVersion, followsUpdates: Bool = true, nodeNameservers: [String]? = nil, dnsMode: ConfigurationDNSMode? = nil, customDNSJSON: String? = nil, settingsJSON: String? = nil, settingsSource: ConfigurationSourceVersion? = nil) {
        self.id = id; self.label = label; self.sources = sources
        self.ruleSchemeID = ruleSchemeID; self.ruleSource = ruleSource
        self.followsUpdates = followsUpdates; self.nodeNameservers = nodeNameservers; self.dnsMode = dnsMode; self.customDNSJSON = customDNSJSON; self.settingsJSON = settingsJSON; self.settingsSource = settingsSource
    }
}

 
 
 
public indirect enum ConfigurationOwnCopyOrigin: Codable, Equatable, Sendable {
    case recipe(ConfigurationRecipe)
    public var previous: ConfigurationRecipe {
        switch self { case .recipe(let recipe): return recipe }
    }
}

 
 
public struct ConfigurationLibrarySnapshot: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var generation: UInt64 = 0
    public var sources: [ConfigurationSourceRecord] = []
    public var rules: [ConfigurationRuleScheme] = []
    public var recipes: [ConfigurationRecipe] = []
     
     
    public var availableSources: [ConfigurationSourceRecord] { sources.filter(\.isListedInLibrary) }
    public var availableRules: [ConfigurationRuleScheme] { rules.filter(\.isListedInLibrary) }
    public var pendingPublications: [ConfigurationPublicationReference]? = nil
     
     
    public var lastMaterializationID: String? = nil
     
     
    public var registeredLegacyProfileIDs: [String]? = nil
     
     
    public var registeredLegacyNodeProfileIDs: [String]? = nil
    public var updateIssues: [ConfigurationUpdateIssue]? = nil
    public var selectedRuleSchemeID: String? = nil
    public var localRuleSets: [ConfigurationLocalRuleSet]? = nil
     
     
     
     
     
     
     
    public var compositionRevision: Int? = nil
     
     
     
     
     
    public var schemePageRevision: Int? = nil
     
     
     
     
     
    public var legacyEditedCopiesMarked: Bool? = nil
    public init() {}
}

public struct ConfigurationSourcePayload: Codable, Equatable, Sendable {
    public var record: ConfigurationSourceRecord
    public let original: Data
    public let documentJSON: String
    public let resourceFiles: [String: Data]?
     
    public let ruleBaselineJSON: String?
    public init(record: ConfigurationSourceRecord, original: Data, documentJSON: String,
                resourceFiles: [String: Data]? = nil, ruleBaselineJSON: String? = nil) {
        self.record = record; self.original = original; self.documentJSON = documentJSON
        self.resourceFiles = resourceFiles; self.ruleBaselineJSON = ruleBaselineJSON
        self.record.ruleBaselineRequired = ruleBaselineJSON == nil ? nil : true
    }
}

 
 
public struct ConfigurationCreationDraft: Equatable, Sendable {
    public enum Step: Int, CaseIterable, Sendable { case sources, rules, finish }
    public var step: Step = .sources
    public var selectedSourceIDs: [String] = []
    public var originalSourceID: String? = nil
    public var nodeScopes: [String: ConfigurationNodeScope]? = nil
    public var selectedRuleID: String?
    public var label = ""
    public var customDNSJSON: String? = nil
    public var dnsMode: ConfigurationDNSMode = .system
    public var nodeNameservers: [String]? = nil
    public var connectAfterCreation = false
    public var newSources: [ConfigurationSourcePayload] = []
    public var newRules: [ConfigurationRuleScheme] = []
    public init() {}
     
    public func needsInitialNodeImport(in snapshot: ConfigurationLibrarySnapshot,
                                      hasLegacyNodes: Bool = false, isEditing: Bool = false) -> Bool {
        !isEditing && step == .sources && !hasLegacyNodes && !sources(in: snapshot).contains {
            $0.suppliesNodes && $0.isRetainedSnapshot != true && ($0.nodeCount > 0 || $0.providerCount > 0)
        }
    }

     
    public mutating func acceptInitialNodeImport(_ payload: ConfigurationSourcePayload) throws {
        guard payload.record.suppliesNodes,
              payload.record.nodeCount > 0 || payload.record.providerCount > 0 else {
            throw ConfigurationLibraryError.missingNodes
        }
        var source = payload
        source.record.registersSuppliedRules = false
        add(source, rule: nil)
        selectedRuleID = selectedRuleID ?? ConfigurationBuiltins.basicRuleID
        connectAfterCreation = false
        step = .rules
    }

    public mutating func toggleSource(_ id: String) {
        if selectedSourceIDs.contains(id) { selectedSourceIDs.removeAll { $0 == id } }
        else { selectedSourceIDs.append(id) }
    }
    public mutating func add(_ source: ConfigurationSourcePayload, rule: ConfigurationRuleScheme?) {
        newSources.removeAll { $0.record.id == source.record.id }
        newSources.append(source)
        if source.record.suppliesNodes && !selectedSourceIDs.contains(source.record.id) {
            selectedSourceIDs.append(source.record.id)
        }
        if let rule { newRules.removeAll { $0.id == rule.id }; newRules.append(rule) }
    }
    public func sources(in snapshot: ConfigurationLibrarySnapshot) -> [ConfigurationSourceRecord] {
        snapshot.sources.filter { old in !newSources.contains { $0.record.id == old.id } } + newSources.map(\.record)
    }
    public func rules(in snapshot: ConfigurationLibrarySnapshot) -> [ConfigurationRuleScheme] {
        let stored = snapshot.rules.filter { old in !newRules.contains { $0.id == old.id } } + newRules
        return stored + ConfigurationBuiltins.schemes.filter { item in !stored.contains { $0.id == item.id } }
    }
}

 
 
 
 
 
 
 
public enum ConfigurationLibraryDiagnostics {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var last: String?
    public static var lastIdentifierNote: String? {
        lock.lock(); defer { lock.unlock() }
        return last
    }
    static func record(_ note: String) {
        lock.lock(); defer { lock.unlock() }
        last = note
    }
}

public enum ConfigurationLibraryError: LocalizedError, Equatable {
    case invalidAdvancedSettings
    case invalidIdentifier
    case emptyNodeNameservers
    case emptyName
    case readOnlySource
    case retainedSnapshot
    case readOnlyRuleScheme
    case missingRules
    case missingNodes
     
     
    case missingNodeSource
    case referencedBy(String)
    case invalidFinalRule
    case unreadable
    case staleGeneration
    case missingDependency(String)
    case immutableVersion
    case busy
     
     
     
    case originalKeepsSourceDNS
    public var errorDescription: String? {
        switch self {
        case .originalKeepsSourceDNS: return "Use Original Configuration keeps the source's own DNS. Turn it off to choose DNS for this configuration."
        case .invalidAdvancedSettings: return NSLocalizedString("Edit nodes and rules in their own settings.", comment: "Advanced settings field ownership")
        case .readOnlyRuleScheme: return "Copy this rule scheme before editing it."
        case .invalidFinalRule: return "Keep exactly one MATCH rule at the end."
        case .referencedBy: return "Something still references this item. Change that reference before deleting it."
        case .missingNodes: return NSLocalizedString("No nodes were found. Try another link or file, or create a node manually.", comment: "First profile import")
        case .missingNodeSource: return "Turn on a node source for this configuration first."
        case .missingRules: return "No routing rules were found in this source."
        case .retainedSnapshot: return "Its link or file was deleted, so this kept copy can't be changed."
        case .readOnlySource: return "Built-in sources cannot be deleted."
        case .emptyName: return "Enter a name."
        case .emptyNodeNameservers: return "Add at least one node DNS server, or choose Inherit."
        case .invalidIdentifier: return "The profile library contains an invalid identifier."
        case .unreadable: return "The profile library could not be read. Its contents were left unchanged."
        case .staleGeneration: return "The profile library changed. Reopen it and try again."
        case .missingDependency: return "This item is still required, or is missing."
        case .busy: return "The profile library is busy. Try again."
        case .immutableVersion: return "This source version already exists with different contents."
        }
    }

     
     
     
     
     
    public var copyKey: String {
        switch self {
        case .originalKeepsSourceDNS: return "Use Original Configuration keeps the source's own DNS. Turn it off to choose DNS for this configuration."
        case .invalidAdvancedSettings: return "Edit nodes and rules in their own settings."
        case .readOnlyRuleScheme: return "Copy this rule scheme before editing it."
        case .invalidFinalRule: return "Keep exactly one MATCH rule at the end."
        case .referencedBy: return "Something still references this item. Change that reference before deleting it."
        case .missingNodes: return "No nodes were found. Try another link or file, or create a node manually."
        case .missingNodeSource: return "Turn on a node source for this configuration first."
        case .missingRules: return "No routing rules were found in this source."
        case .retainedSnapshot: return "Its link or file was deleted, so this kept copy can't be changed."
        case .readOnlySource: return "Built-in sources cannot be deleted."
        case .emptyName: return "Enter a name."
        case .emptyNodeNameservers: return "Add at least one node DNS server, or choose Inherit."
        case .invalidIdentifier: return "The profile library contains an invalid identifier."
        case .unreadable: return "The profile library could not be read. Its contents were left unchanged."
        case .staleGeneration: return "The profile library changed. Reopen it and try again."
        case .missingDependency: return "This item is still required, or is missing."
        case .busy: return "The profile library is busy. Try again."
        case .immutableVersion: return "This source version already exists with different contents."
        }
    }
}

public final class ConfigurationLibraryStore: Sendable {
    private let directory: URL
    private let beginAccess: @Sendable () -> (@Sendable () -> Void)
    public init(directory: URL, beginAccess: @escaping @Sendable () -> (@Sendable () -> Void) = { {} }) {
        self.directory = directory
        self.beginAccess = beginAccess
    }

    public func commitPublication(_ candidate: ConfigurationLibrarySnapshot,
                                  payloads: [ConfigurationSourcePayload],
                                  publication: ConfigurationPublicationPayload,
                                  expectedGeneration: UInt64) throws -> ConfigurationLibrarySnapshot {
        var candidate = candidate
        guard candidate.recipes.contains(where: { $0.id == publication.reference.profileID }) else {
            throw ConfigurationLibraryError.missingDependency(publication.reference.profileID)
        }
        var pending = candidate.pendingPublications ?? []
        pending.removeAll { $0.profileID == publication.reference.profileID }
        pending.append(publication.reference)
        candidate.pendingPublications = pending
        return try commit(candidate, payloads:payloads, publications:[publication], expectedGeneration:expectedGeneration)
    }

    public func publication(_ reference: ConfigurationPublicationReference) throws -> ConfigurationPublicationPayload {
        let file = try publicationURL(reference)
        let stored = try JSONDecoder().decode(StoredPublication.self, from:Data(contentsOf:file))
        guard stored.reference == reference else { throw ConfigurationLibraryError.unreadable }
         
        let yaml = try stored.yaml ?? String(contentsOf: publicationTextURL(reference), encoding: .utf8)
        return ConfigurationPublicationPayload(reference: reference, profileMetadata: stored.profileMetadata, yaml: yaml)
    }

     
     
     
    private struct StoredPublication: Codable {
        let reference: ConfigurationPublicationReference
        let profileMetadata: Data
        let yaml: String?
    }

    private func publicationTextURL(_ reference: ConfigurationPublicationReference) throws -> URL {
        try publicationURL(reference).deletingPathExtension().appendingPathExtension("yaml")
    }

    public func acknowledgePublication(_ reference: ConfigurationPublicationReference) throws {
        let acknowledged = try locked { () throws -> Bool in
            var current = try readSnapshot()
            guard current.pendingPublications?.contains(reference) == true else { return false }
            current.pendingPublications?.removeAll { $0 == reference }
            current.generation += 1
            try writeSnapshot(current)
            return true
        }
        if acknowledged { sweepTail() }
    }


    public func snapshot() throws -> ConfigurationLibrarySnapshot {
         
         
         
        try readSnapshot()
    }

     
     
    public func addSource(_ source: ConfigurationSourcePayload, expectedGeneration: UInt64) throws -> ConfigurationLibrarySnapshot {
        var candidate = try snapshot()
        guard candidate.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        guard !candidate.sources.contains(where: { $0.id == source.record.id }) else {
            throw ConfigurationLibraryError.invalidIdentifier.noted()
        }
        candidate.sources.append(source.record)
        if source.record.hasRules && source.record.registersSuppliedRules != false {
            candidate.rules.append(.init(id: "rules-" + source.record.id, label: source.record.label,
                kind: .supplied, sourceID: source.record.id))
        }
        return try commit(candidate, payloads: [source], expectedGeneration: expectedGeneration)
    }

     
     
    public func renameSource(_ id: String, label: String, expectedGeneration: UInt64) throws -> ConfigurationLibrarySnapshot {
        var candidate = try snapshot()
        guard candidate.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ConfigurationLibraryError.emptyName }
        guard let index = candidate.sources.firstIndex(where: { $0.id == id }) else {
            throw ConfigurationLibraryError.missingDependency(id)
        }
        guard candidate.sources[index].isRetainedSnapshot != true else { throw ConfigurationLibraryError.retainedSnapshot }
        let previousName = candidate.sources[index].label
        candidate.sources[index].label = name
        for index in candidate.rules.indices
            where Self.followsSourceName(candidate.rules[index], sourceID: id, previous: previousName) {
            candidate.rules[index].label = name
            candidate.namingOwnViews(of: candidate.rules[index].id)
        }
        return try commit(candidate, payloads: [], expectedGeneration: expectedGeneration)
    }

    public func updateSourceSettings(_ id: String, draft: ConfigurationSourceSettingsDraft,
                                     label: String? = nil, expectedGeneration: UInt64) throws -> ConfigurationLibrarySnapshot {
        var candidate = try snapshot()
        guard candidate.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        guard let index = candidate.sources.firstIndex(where: { $0.id == id }),
              case .subscription = candidate.sources[index].origin else { throw ConfigurationLibraryError.readOnlySource }
        guard candidate.sources[index].isRetainedSnapshot != true else { throw ConfigurationLibraryError.retainedSnapshot }
        let url = draft.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URLComponents(string: url), let host = parsed.host, !host.isEmpty,
              parsed.scheme != nil, parsed.url != nil else { throw URLError(.badURL) }
        guard (0...168).contains(draft.intervalHours) else {
            throw ConfigurationLibraryError.unreadable
        }
        candidate.sources[index].dnsOverHTTPS = nil
        candidate.sources[index].origin = .subscription(url)
        candidate.sources[index].userAgent = nil
        candidate.sources[index].updateIntervalHours = draft.intervalHours == 0 ? nil : draft.intervalHours
        if let label {
            let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw ConfigurationLibraryError.emptyName }
            let previous = candidate.sources[index].label
            candidate.sources[index].label = name
            for index in candidate.rules.indices
                where Self.followsSourceName(candidate.rules[index], sourceID: id, previous: previous) {
                candidate.rules[index].label = name
                candidate.namingOwnViews(of: candidate.rules[index].id)
            }
        }
        return try commit(candidate, payloads: [], expectedGeneration: expectedGeneration)
    }

     
     
     
     
     
    static func followsSourceName(_ scheme: ConfigurationRuleScheme, sourceID: String, previous: String) -> Bool {
        scheme.sourceID == sourceID && scheme.label == previous
            && (scheme.kind == .supplied || scheme.kind == .imported)
            && scheme.rulesFromSchemeID == nil && scheme.collectionKey == nil
    }

     
     
     
    public func commit(_ candidate: ConfigurationLibrarySnapshot, payloads: [ConfigurationSourcePayload],
                       publications: [ConfigurationPublicationPayload] = [], expectedGeneration: UInt64) throws -> ConfigurationLibrarySnapshot {
        let committed = try commitLocked(candidate, payloads: payloads, publications: publications,
                                         expectedGeneration: expectedGeneration)
         
         
         
        sweepTail()
        return committed
    }

    private func commitLocked(_ candidate: ConfigurationLibrarySnapshot, payloads: [ConfigurationSourcePayload],
                              publications: [ConfigurationPublicationPayload],
                              expectedGeneration: UInt64) throws -> ConfigurationLibrarySnapshot {
        try locked {
            let previous = try readSnapshot()
            guard previous.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
             
             
             
            let candidate = Self.pruningUnreferencedRetainedRecords(candidate).snapshot
             
             
            let payloads = payloads.filter { payload in
                candidate.sources.contains { $0.id == payload.record.id }
                    || candidate.recipes.contains { $0.settingsSource == ConfigurationSourceVersion(payload.record) }
            }
            try validate(candidate, payloads: payloads)
            let pending = candidate.pendingPublications ?? []
            guard Set(pending.map(\.profileID)).count == pending.count,
                  publications.allSatisfy({ pending.contains($0.reference) }) else {
                throw ConfigurationLibraryError.invalidIdentifier.noted()
            }
            for reference in pending {
                let existingFile = try publicationURL(reference)
                guard candidate.recipes.contains(where: { $0.id == reference.profileID }),
                      publications.contains(where: { $0.reference == reference })
                        || FileManager.default.fileExists(atPath:existingFile.path) else {
                    throw ConfigurationLibraryError.missingDependency(reference.profileID)
                }
            }
            for payload in payloads { try writePayload(payload) }
            for publication in publications { try writePublication(publication) }
            var committed = candidate
            committed.generation = previous.generation + 1
             
             
             
             
             
            if committed.compositionRevision == nil,
               !previous.recipes.contains(where: { $0.preservesOriginal != true }) {
                committed.compositionRevision = Self.currentCompositionRevision
            }
             
             
            if committed.schemePageRevision == nil,
               !previous.recipes.contains(where: { $0.preservesOriginal != true }) {
                committed.schemePageRevision = Self.currentSchemePageRevision
            }
            try writeSnapshot(committed)
            return committed
        }
    }

     
     
     
     
    public func originalURL(_ reference: ConfigurationSourceVersion) throws -> URL {
        try versionDirectory(reference).appendingPathComponent("original")
    }

     
     
     
     
     
     
     
    func providerSections(_ reference: ConfigurationSourceVersion) throws -> [String: OrderedJSON] {
        let file = try versionDirectory(reference).appendingPathComponent("document.json")
        let identity = ProviderSectionsMemo.identity(of: file)
        if let identity, let known = ProviderSectionsMemo.shared.sections(of: file.path, identity: identity) { return known }
        let members = try OrderedJSON.topLevel(payload(reference).documentJSON)
        var sections: [String: OrderedJSON] = [:]
        for key in ["proxy-providers", "rule-providers", "global-ua"] {
            if let value = try members?.value(key) { sections[key] = value }
        }
        if let identity, ProviderSectionsMemo.identity(of: file) == identity {
            ProviderSectionsMemo.shared.record(sections, of: file.path, identity: identity)
        }
        return sections
    }

    public func payload(_ reference: ConfigurationSourceVersion) throws -> ConfigurationSourcePayload {
        let folder = try versionDirectory(reference)
        do {
            let record = try JSONDecoder().decode(ConfigurationSourceRecord.self,
                from: Data(contentsOf: folder.appendingPathComponent("record.json")))
            guard record.id == reference.id, record.version == reference.version else {
                throw ConfigurationLibraryError.unreadable
            }
            let baseline = try readRuleBaseline(in: folder)
            guard (record.ruleBaselineRequired == true) == (baseline != nil) else { throw ConfigurationLibraryError.unreadable }
             
             
             
             
            return ConfigurationSourcePayload(record: record,
                original: try Data(contentsOf: folder.appendingPathComponent("original"), options: .alwaysMapped),
                documentJSON: try String(contentsOf: folder.appendingPathComponent("document.json"), encoding: .utf8),
                resourceFiles:try readResourceFiles(in:folder), ruleBaselineJSON: baseline)
        } catch { throw ConfigurationLibraryError.unreadable }
    }

    private func writeSnapshot(_ snapshot: ConfigurationLibrarySnapshot) throws {
        try JSONEncoder().encode(snapshot).write(to:directory.appendingPathComponent("library.json"), options:Self.writeOptions)
    }

    private func publicationURL(_ reference: ConfigurationPublicationReference) throws -> URL {
        guard Self.safeID(reference.profileID), Self.safeID(reference.version) else {
            throw ConfigurationLibraryError.invalidIdentifier.noted()
        }
        return directory.appendingPathComponent("publications").appendingPathComponent(reference.profileID)
            .appendingPathComponent(reference.version + ".json")
    }

    private func writePublication(_ publication: ConfigurationPublicationPayload) throws {
        let destination = try publicationURL(publication.reference)
        if FileManager.default.fileExists(atPath:destination.path) {
            guard try self.publication(publication.reference) == publication else { throw ConfigurationLibraryError.immutableVersion }
            return
        }
        try FileManager.default.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
         
        try ConfigurationTextFile.write(publication.yaml, to: publicationTextURL(publication.reference))
        try JSONEncoder().encode(StoredPublication(reference: publication.reference,
                                                   profileMetadata: publication.profileMetadata, yaml: nil))
            .write(to:destination, options:Self.writeOptions)
    }

    private func readSnapshot() throws -> ConfigurationLibrarySnapshot {
        let file = directory.appendingPathComponent("library.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return .init() }
        do {
            let result = try JSONDecoder().decode(ConfigurationLibrarySnapshot.self, from: Data(contentsOf: file))
            guard result.schemaVersion == 1 else { throw ConfigurationLibraryError.unreadable }
            return result
        } catch { throw ConfigurationLibraryError.unreadable }
    }

     
     
    public func validateArchive(_ archive: ConfigurationLibraryArchive) throws {
        guard archive.schemaVersion == 1 else { throw ConfigurationLibraryError.unreadable }
        let references = Set(archive.payloads.map { ConfigurationSourceVersion($0.record) })
        let required = archive.snapshot.sources.map(ConfigurationSourceVersion.init)
            + archive.snapshot.recipes.flatMap { $0.dependencies }
            + archive.payloads.flatMap { $0.record.nodeChain?.hops.map(\.source) ?? [] }
        for reference in required where !references.contains(reference) {
            throw ConfigurationLibraryError.missingDependency(reference.id)
        }
        let pending = archive.snapshot.pendingPublications ?? []
        let publications = archive.publications ?? []
        guard Set(pending.map(\.profileID)).count == pending.count,
              Set(publications.map(\.reference)).count == publications.count,
              Set(pending) == Set(publications.map(\.reference)),
              pending.allSatisfy({ ref in archive.snapshot.recipes.contains { $0.id == ref.profileID } }) else {
            throw ConfigurationLibraryError.invalidIdentifier.noted()
        }
        for reference in pending { _ = try publicationURL(reference) }
        try validate(archive.snapshot, payloads: archive.payloads)
    }

    private func validate(_ candidate: ConfigurationLibrarySnapshot, payloads: [ConfigurationSourcePayload]) throws {
        guard candidate.schemaVersion == 1 else { throw ConfigurationLibraryError.unreadable }
        func unique(_ ids: [String]) throws {
            guard ids.allSatisfy(Self.safeID), Set(ids).count == ids.count else {
                throw ConfigurationLibraryError.invalidIdentifier.noted()
            }
        }
        try unique(candidate.sources.map(\.id)); try unique(candidate.rules.map(\.id)); try unique(candidate.recipes.map(\.id))
        let payloadReferences = payloads.map { ConfigurationSourceVersion($0.record) }
        guard Set(payloadReferences).count == payloadReferences.count else { throw ConfigurationLibraryError.invalidIdentifier.noted() }
        let sourceIDs = Set(candidate.sources.map(\.id))
        let ruleIDs = Set(candidate.rules.map(\.id))
        func require(_ reference: ConfigurationSourceVersion, archivedSettings: Bool = false) throws {
            let path = try versionDirectory(reference)
            guard (sourceIDs.contains(reference.id) || archivedSettings),
                  payloads.contains(where: { $0.record.id == reference.id && $0.record.version == reference.version })
                    || ["document.json", "original", "record.json"].allSatisfy({ FileManager.default.fileExists(atPath:path.appendingPathComponent($0).path) }) else {
                throw ConfigurationLibraryError.missingDependency(reference.id)
            }
        }
        for source in candidate.sources {
            try require(.init(source))
            if let chain = source.nodeChain {
                guard source.origin == .customNodes, source.suppliesNodes else { throw ConfigurationLibraryError.invalidIdentifier.noted() }
                for hop in chain.hops {
                    guard hop.source.id != source.id,
                          candidate.sources.first(where: { $0.id == hop.source.id })?.nodeChain == nil else {
                        throw ConfigurationNodeChainError.nestedChain
                    }
                    try require(hop.source)
                }
            }
        }
        for rule in candidate.rules where !sourceIDs.contains(rule.sourceID) {
            throw ConfigurationLibraryError.missingDependency(rule.sourceID)
        }
        for rule in candidate.rules {
            if let page = rule.pageJSON { _ = try ConfigurationSchemePage.parse(page) }
             
             
            if let baseID = rule.rulesFromSchemeID {
                let base = candidate.rules.first { $0.id == baseID } ?? ConfigurationBuiltins.schemes.first { $0.id == baseID }
                guard let base, base.rulesFromSchemeID == nil, base.sourceID == rule.sourceID, rule.collectionKey == nil else {
                    throw ConfigurationLibraryError.missingDependency(baseID)
                }
            }
        }
        for recipe in candidate.recipes {
            if let settings = recipe.settingsJSON { _ = try ConfigurationSettingsDocument.parse(settings) }
            if recipe.dnsMode == .custom { _ = try ConfigurationDNSSettings.custom(recipe.customDNSJSON) }
            if let servers = recipe.nodeNameservers,
               servers.isEmpty || servers.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                throw ConfigurationLibraryError.emptyNodeNameservers
            }
            if recipe.preservesOriginal == true {
                guard recipe.sources == [recipe.ruleSource] else { throw ConfigurationLibraryError.invalidIdentifier.noted() }
            } else {
            guard ruleIDs.contains(recipe.ruleSchemeID),
                  candidate.rules.first(where: { $0.id == recipe.ruleSchemeID })?.sourceID == recipe.ruleSource.id else {
                throw ConfigurationLibraryError.missingDependency(recipe.ruleSchemeID)
            }
            }
            if let scopes = recipe.nodeScopes {
                guard scopes.allSatisfy({ entry in recipe.sources.contains { $0.id == entry.key } && !entry.value.isEmpty }) else {
                    throw ConfigurationLibraryError.invalidIdentifier.noted()
                }
            }
            try unique(recipe.sources.map(\.id))
            for reference in recipe.sources + [recipe.ruleSource] { try require(reference) }
            if let reference = recipe.settingsSource {
                guard recipe.settingsJSON != nil else { throw ConfigurationLibraryError.invalidIdentifier.noted() }
                try require(reference, archivedSettings: true)
            }
        }
        for payload in payloads {
            _ = try versionDirectory(.init(payload.record))
            guard (payload.record.ruleBaselineRequired == true) == (payload.ruleBaselineJSON != nil) else {
                throw ConfigurationLibraryError.unreadable
            }
            if let baseline = payload.ruleBaselineJSON {
                guard case .object = try OrderedJSON.parse(baseline) else { throw ConfigurationLibraryError.unreadable }
            }
             
             
            guard (payload.resourceFiles ?? [:]).keys.allSatisfy(Self.safeResourceName),
                  (sourceIDs.contains(payload.record.id) || candidate.recipes.contains { $0.settingsSource == ConfigurationSourceVersion(payload.record) }),
                  try OrderedJSON.topLevel(payload.documentJSON) != nil else {
                throw ConfigurationLibraryError.invalidIdentifier.noted()
            }
        }
    }

    private static func safeID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 128 && id.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }
    }
    private func versionDirectory(_ ref: ConfigurationSourceVersion) throws -> URL {
        guard Self.safeID(ref.id), Self.safeID(ref.version) else { throw ConfigurationLibraryError.invalidIdentifier.noted() }
        return directory.appendingPathComponent("sources").appendingPathComponent(ref.id).appendingPathComponent(ref.version)
    }
    private static var writeOptions: Data.WritingOptions {
        #if os(iOS) || os(tvOS)
        [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        #else
        [.atomic]
        #endif
    }
    private func readRuleBaseline(in folder: URL) throws -> String? {
        let url = folder.appendingPathComponent("rule-baseline.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let json = try String(contentsOf: url, encoding: .utf8)
        guard case .object = try OrderedJSON.parse(json) else { throw ConfigurationLibraryError.unreadable }
        return json
    }

    private func writePayload(_ payload: ConfigurationSourcePayload) throws {
        let destination = try versionDirectory(.init(payload.record))
        if FileManager.default.fileExists(atPath: destination.path) {
            guard try Data(contentsOf: destination.appendingPathComponent("original"), options: .alwaysMapped)
                    == payload.original,
                  try String(contentsOf: destination.appendingPathComponent("document.json"), encoding:.utf8) == payload.documentJSON,
                  try readResourceFiles(in:destination) == payload.resourceFiles,
                  try readRuleBaseline(in: destination) == payload.ruleBaselineJSON else {
                throw ConfigurationLibraryError.immutableVersion
            }
            return
        }
        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent("staging-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at:staging) }
        try payload.original.write(to:staging.appendingPathComponent("original"), options:Self.writeOptions)
        try Data(payload.documentJSON.utf8).write(to:staging.appendingPathComponent("document.json"), options:Self.writeOptions)
        try JSONEncoder().encode(payload.record).write(to:staging.appendingPathComponent("record.json"), options:Self.writeOptions)
        if let baseline = payload.ruleBaselineJSON {
            try Data(baseline.utf8).write(to: staging.appendingPathComponent("rule-baseline.json"), options: Self.writeOptions)
        }
        if let resources = payload.resourceFiles {
            let folder = staging.appendingPathComponent("resources")
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            for (name, data) in resources {
                guard Self.safeResourceName(name) else { throw ConfigurationLibraryError.invalidIdentifier.noted() }
                try data.write(to:folder.appendingPathComponent(name),options:Self.writeOptions)
            }
            try JSONEncoder().encode(resources.keys.sorted()).write(
                to:staging.appendingPathComponent("resource-names.json"),options:Self.writeOptions)
        }
        try FileManager.default.moveItem(at:staging, to:destination)
    }

    private static func safeResourceName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
    }

    private func readResourceFiles(in folder: URL) throws -> [String: Data]? {
        let index = folder.appendingPathComponent("resource-names.json")
        guard FileManager.default.fileExists(atPath:index.path) else { return nil }
        let names = try JSONDecoder().decode([String].self,from:Data(contentsOf:index))
        var result: [String: Data] = [:]
        for name in names {
            guard Self.safeResourceName(name) else { throw ConfigurationLibraryError.invalidIdentifier.noted() }
            result[name] = try Data(contentsOf:folder.appendingPathComponent("resources").appendingPathComponent(name))
        }
        return result
    }

    private func locked<T>(_ body: () throws -> T) throws -> T {
        let finishAccess = beginAccess()
        defer { finishAccess() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories:true)
        let path = directory.appendingPathComponent("library.lock").path
        let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw ConfigurationLibraryError.unreadable }
        defer { close(fd) }
         
         
         
         
         
         
        let deadline = Date().addingTimeInterval(1)
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EAGAIN, Date() < deadline else {
                throw ConfigurationLibraryError.busy
            }
            usleep(10_000)
        }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
}

 
public struct ConfigurationLibraryGarbageCollection: Equatable, Sendable {
     
    public var removedRecords: Int = 0
     
    public var removedVersions: Int = 0
     
    public var removedPublications: Int = 0
    public init(removedRecords: Int = 0, removedVersions: Int = 0, removedPublications: Int = 0) {
        self.removedRecords = removedRecords
        self.removedVersions = removedVersions
        self.removedPublications = removedPublications
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
extension ConfigurationLibraryStore {
     
    public static func referencedVersions(of snapshot: ConfigurationLibrarySnapshot) -> Set<ConfigurationSourceVersion> {
        var kept = Set(snapshot.sources.map(ConfigurationSourceVersion.init))
        for source in snapshot.sources { for hop in source.nodeChain?.hops ?? [] { kept.insert(hop.source) } }
        for recipe in snapshot.recipes { kept.formUnion(recipe.dependencies) }
        return kept
    }

     
    static func pruningUnreferencedRetainedRecords(_ snapshot: ConfigurationLibrarySnapshot)
        -> (snapshot: ConfigurationLibrarySnapshot, removed: Int) {
        var result = snapshot
        let dependedOn = Set(snapshot.recipes.flatMap { $0.dependencies.map(\.id) })
        let hoppedThrough = Set(snapshot.sources.flatMap { ($0.nodeChain?.hops ?? []).map(\.source.id) })
         
         
         
         
         
         
         
         
        let configurations = Set(snapshot.recipes.map(\.id))
        let inUse = snapshot.schemeIDsInUse
        let retained = Dictionary(snapshot.rules.map { ($0.id, $0.isRetainedSnapshot == true) }, uniquingKeysWith: { first, _ in first })
        let ownViewsGone = Set(snapshot.rules.filter { view in
            guard view.ownViewBaseID != nil else { return false }
            if !configurations.contains(view.privateToConfigurationID ?? "") { return true }
            guard let baseID = view.rulesFromSchemeID, !inUse.contains(view.id) else { return false }
            let live = retained[baseID].map { !$0 } ?? ConfigurationBuiltins.schemes.contains { $0.id == baseID }
            return !live
        }.map(\.id))
        let ownViewSources = Set(snapshot.rules.filter { $0.ownViewBaseID != nil && !ownViewsGone.contains($0.id) }.map(\.sourceID))
         
         
        let orphanSources = Set(snapshot.sources.filter {
            ($0.isRetainedSnapshot == true || $0.privateToConfigurationID != nil)
                && !dependedOn.contains($0.id) && !hoppedThrough.contains($0.id) && !ownViewSources.contains($0.id)
        }.map(\.id))
         
        let runOn = Set(snapshot.recipes.map(\.ruleSchemeID))
            .union(snapshot.rules.filter { !ownViewsGone.contains($0.id) }.compactMap(\.rulesFromSchemeID))
        var removed = 0
        result.sources.removeAll { orphanSources.contains($0.id) }
        removed += orphanSources.count
        result.rules.removeAll { rule in
            let goes = orphanSources.contains(rule.sourceID)
                || (rule.isRetainedSnapshot == true && !runOn.contains(rule.id))
                || ownViewsGone.contains(rule.id)
            if goes { removed += 1 }
            return goes
        }
        return (result, removed)
    }

     
     
     
    public func collectGarbage() throws -> ConfigurationLibraryGarbageCollection {
        try locked {
            var current = try readSnapshot()
            let pruned = Self.pruningUnreferencedRetainedRecords(current)
            if pruned.removed > 0 {
                current = pruned.snapshot
                current.generation += 1
                try writeSnapshot(current)
            }
            var result = sweep(current)
            result.removedRecords = pruned.removed
            return result
        }
    }



     
     
     
    func sweep(_ snapshot: ConfigurationLibrarySnapshot) -> ConfigurationLibraryGarbageCollection {
        remove(garbage(by: snapshot), keptBy: snapshot)
    }

     
     
     
     
     
     
     
     
    @discardableResult
    func sweepTail() -> ConfigurationLibraryGarbageCollection {
        guard let onDisk = try? readSnapshot() else { return .init() }
        let found = garbage(by: onDisk)
        guard !found.isEmpty else { return .init() }
        return (try? locked { remove(found, keptBy: try readSnapshot()) }) ?? .init()
    }

     
     
     
    struct SweepFindings {
        var versions: [(id: String, url: URL)] = []
        var publications: [(reference: ConfigurationPublicationReference, url: URL)] = []
        var partials: [URL] = []
        var folders: [URL] = []
        var isEmpty: Bool { versions.isEmpty && publications.isEmpty && partials.isEmpty && folders.isEmpty }
    }

    func garbage(by snapshot: ConfigurationLibrarySnapshot) -> SweepFindings {
        let fm = FileManager.default
        var found = SweepFindings()
        func subdirectories(_ url: URL) -> [URL] {
            (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]))?
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true } ?? []
        }
        let kept = Self.referencedVersions(of: snapshot)
        for sourceDirectory in subdirectories(directory.appendingPathComponent("sources")) {
            let id = sourceDirectory.lastPathComponent


            let versions = subdirectories(sourceDirectory)
            let dropped = versions.filter { !kept.contains(.init(id: id, version: $0.lastPathComponent)) }
            found.versions += dropped.map { (id, $0) }
            if dropped.count == versions.count, ((try? fm.contentsOfDirectory(atPath: sourceDirectory.path)) ?? []).count == versions.count {
                found.folders.append(sourceDirectory)
            }
        }
        let pending = Set(snapshot.pendingPublications ?? [])
        for profileDirectory in subdirectories(directory.appendingPathComponent("publications")) {
            let profileID = profileDirectory.lastPathComponent
            let names = (try? fm.contentsOfDirectory(atPath: profileDirectory.path)) ?? []
            var leaves = 0
            for name in names {
                let file = profileDirectory.appendingPathComponent(name)
                 
                 
                 
                 
                if name.hasPrefix(".") {
                    if name.hasSuffix(".partial") { found.partials.append(file); leaves += 1 }
                    continue
                }
                 
                guard file.pathExtension == "json" || file.pathExtension == "yaml" else { continue }
                let reference = ConfigurationPublicationReference(profileID: profileID, version: file.deletingPathExtension().lastPathComponent)
                guard !pending.contains(reference) else { continue }
                found.publications.append((reference, file))
                leaves += 1
            }
            if leaves == names.count { found.folders.append(profileDirectory) }
        }
        return found
    }

     
     
     
    func remove(_ found: SweepFindings, keptBy snapshot: ConfigurationLibrarySnapshot) -> ConfigurationLibraryGarbageCollection {
        let fm = FileManager.default
        var result = ConfigurationLibraryGarbageCollection()
        let kept = Self.referencedVersions(of: snapshot)
        for (id, url) in found.versions where !kept.contains(.init(id: id, version: url.lastPathComponent)) {
            if (try? fm.removeItem(at: url)) != nil { result.removedVersions += 1 }
        }
        let pending = Set(snapshot.pendingPublications ?? [])
        for (reference, url) in found.publications where !pending.contains(reference) {
            if (try? fm.removeItem(at: url)) != nil, url.pathExtension == "json" { result.removedPublications += 1 }
        }
        for url in found.partials { try? fm.removeItem(at: url) }
        for folder in found.folders where ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? [""]).isEmpty {
            try? fm.removeItem(at: folder)
        }
        return result
    }
}

public extension ConfigurationLibraryError {
     
     
     
     
    func noted(_ detail: String? = nil, file: StaticString = #fileID, line: UInt = #line) -> ConfigurationLibraryError {
        ConfigurationLibraryDiagnostics.record("\(file):\(line)" + (detail.map { " " + $0 } ?? ""))
        return self
    }
}

 
 
final class ProviderSectionsMemo: @unchecked Sendable {
    static let shared = ProviderSectionsMemo()
    private let lock = NSLock()
    private var known: [String: (identity: String, sections: [String: OrderedJSON])] = [:]

    static func identity(of url: URL) -> String? {
        var status = stat()
        guard stat(url.path, &status) == 0 else { return nil }
        #if canImport(Darwin)
        let (modified, changed) = (status.st_mtimespec, status.st_ctimespec)
        #else
        let (modified, changed) = (status.st_mtim, status.st_ctim)
        #endif
        return "\(status.st_dev)|\(status.st_ino)|\(status.st_size)|"
            + "\(modified.tv_sec).\(modified.tv_nsec)|\(changed.tv_sec).\(changed.tv_nsec)"
    }

    func sections(of path: String, identity: String) -> [String: OrderedJSON]? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = known[path], entry.identity == identity else { return nil }
        return entry.sections
    }

    func record(_ sections: [String: OrderedJSON], of path: String, identity: String) {
        lock.lock(); defer { lock.unlock() }
         
        if known.count >= 512 { known.removeAll() }
        known[path] = (identity, sections)
    }
}
