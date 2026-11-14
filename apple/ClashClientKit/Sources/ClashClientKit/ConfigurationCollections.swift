import Foundation

 
 
public struct ConfigurationCollection: Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case nodes = "proxy-providers", rules = "rule-providers" }
    public struct ID: Hashable, Sendable { public let sourceID: String; public let kind: Kind; public let key: String }
    public let id: ID
    public let definition: OrderedJSON
    public var name: String { id.key }
    public var type: String { definition.topLevelValue("type")?.foundationValue as? String ?? "" }
    public var format: String { definition.topLevelValue("format")?.foundationValue as? String ?? "yaml" }
    public var behavior: String? { definition.topLevelValue("behavior")?.foundationValue as? String }
    public var location: String? {
        definition.topLevelValue("url")?.foundationValue as? String ?? definition.topLevelValue("path")?.foundationValue as? String
    }
    public var inlineCount: Int? {
        guard type == "inline", case .array(let entries) = definition.topLevelValue("payload") else { return nil }
        return entries.count
    }
     
     
     
     
     
    public var fetchingOutbound: String? {
        guard let proxy = definition.topLevelValue("proxy")?.foundationValue as? String,
              Self.namesOutbound(proxy) else { return nil }
        return proxy
    }
     
     
     
    public static func namesOutbound(_ proxy: String) -> Bool {
        !proxy.isEmpty && proxy != "DIRECT"
    }
    public static func read(sourceID: String, document: OrderedJSON, kind: Kind) -> [Self] {
        guard case .object(let entries) = document.topLevelValue(kind.rawValue) else { return [] }
        return entries.map { .init(id: .init(sourceID: sourceID, kind: kind, key: $0.key), definition: $0.value) }
    }
}

 
 
public struct ConfigurationNodeScope: Codable, Equatable, Sendable {
    public var includesInlineNodes: Bool
    public var providerKeys: [String]
     
    public var inlineNodeNames: [String]?
    public init(includesInlineNodes: Bool, providerKeys: [String], inlineNodeNames: [String]? = nil) {
        self.includesInlineNodes = includesInlineNodes; self.providerKeys = providerKeys
        self.inlineNodeNames = inlineNodeNames
    }
    public var isEmpty: Bool { (!includesInlineNodes || inlineNodeNames?.isEmpty == true) && providerKeys.isEmpty }

    public func applying(to input: ConfigurationInput) throws -> ConfigurationInput {
        guard !isEmpty, Set(providerKeys).count == providerKeys.count else { throw ConfigurationLibraryError.invalidIdentifier.noted() }
        let document = input.document
        func entries(_ key: String) -> [(key: String, value: OrderedJSON)] {
            guard case .object(let values) = document.topLevelValue(key) else { return [] }; return values
        }
        func array(_ key: String) -> [OrderedJSON] {
            guard case .array(let values) = document.topLevelValue(key) else { return [] }; return values
        }
        func string(_ value: OrderedJSON?) -> String? { value?.foundationValue as? String }
        func strings(_ value: OrderedJSON?) -> [String] { value?.foundationValue as? [String] ?? [] }
        let allNodes = array("proxies"), allGroups = array("proxy-groups"), allProviders = entries("proxy-providers")
        var nodes = Set<String>(), providers = Set<String>(), done = Set<String>()
         
         
        var path: [(identity: String, viaIncludeAll: Bool)] = []
        let publicNodes = includesInlineNodes
            ? Set(inlineNodeNames ?? allNodes.compactMap { string($0.topLevelValue("name")) }) : []
        func missing(_ name: String) -> ConfigurationCompositionError { .unresolvedDependency(source: input.id, name: name) }
        let availableNodes = Set(allNodes.compactMap { string($0.topLevelValue("name")) })
        if let unavailable = publicNodes.subtracting(availableNodes).sorted().first { throw missing(unavailable) }
        func isOutbound(_ name: String) -> Bool {
            availableNodes.contains(name) || ConfigurationComposer.builtins.contains(name)
                || allGroups.contains { string($0.topLevelValue("name")) == name }
        }
        func walk(_ kind: String, _ name: String, viaIncludeAll: Bool = false) throws {
            let identity = kind + ":" + name
             
             
             
             
             
             
             
             
            if let start = path.firstIndex(where: { $0.identity == identity }) {
                if viaIncludeAll || path[(start + 1)...].contains(where: \.viaIncludeAll) { return }
                throw missing("cycle: " + name)
            }
            guard !done.contains(identity) else { return }
            path.append((identity, viaIncludeAll))
            defer { path.removeLast() }
            if kind == "provider" {
                guard let value = allProviders.first(where: { $0.key == name })?.value else { throw missing(name) }
                providers.insert(name)
                 
                 
                 
                 
                for target in [string(value.topLevelValue("proxy")), string(value.topLevelValue("override")?.topLevelValue("dialer-proxy"))].compactMap({ $0 })
                where !target.isEmpty && isOutbound(target) {
                    try walk("outbound", target)
                }
            } else if ["DIRECT", "REJECT", "REJECT-DROP", "PASS", "COMPATIBLE", "GLOBAL"].contains(name) {
                 
            } else if let value = allNodes.first(where: { string($0.topLevelValue("name")) == name }) {
                nodes.insert(name)
                if let target = string(value.topLevelValue("dialer-proxy")), !target.isEmpty { try walk("outbound", target) }
            } else if let group = allGroups.first(where: { string($0.topLevelValue("name")) == name }) {
                for target in strings(group.topLevelValue("proxies")) { try walk("outbound", target) }
                for key in strings(group.topLevelValue("use")) { try walk("provider", key) }
                if group.topLevelValue("include-all") == .scalar("true") || group.topLevelValue("include-all-proxies") == .scalar("true") {
                    for value in allNodes { if let name = string(value.topLevelValue("name")) { try walk("outbound", name, viaIncludeAll: true) } }
                }
                if group.topLevelValue("include-all") == .scalar("true") || group.topLevelValue("include-all-providers") == .scalar("true") {
                    for entry in allProviders { try walk("provider", entry.key, viaIncludeAll: true) }
                }
            } else { throw missing(name) }
            done.insert(identity)
        }
        for name in publicNodes { try walk("outbound", name) }
        for key in providerKeys { try walk("provider", key) }
        let projected = document.settingTopLevel("proxies", to: .array(allNodes.filter { nodes.contains(string($0.topLevelValue("name")) ?? "") }))
            .settingTopLevel("proxy-providers", to: .object(allProviders.filter { providers.contains($0.key) }))
        return .init(id: input.id, document: projected, resourcePaths: input.resourcePaths,
            hiddenNodeNames: input.hiddenNodeNames.union(nodes.subtracting(publicNodes)),
            hiddenProviderNames: input.hiddenProviderNames.union(providers.subtracting(providerKeys)))
    }
}

public struct ConfigurationUpdateIssue: Codable, Equatable, Sendable {
    public let sourceID: String
    public let itemID: String
    public let message: String
    public init(sourceID: String, itemID: String, message: String) {
        self.sourceID = sourceID; self.itemID = itemID; self.message = message
    }
}

 
 
public struct ConfigurationCollectionEntry: Identifiable, Equatable, Sendable {
    public let source: ConfigurationSourceRecord
    public let collection: ConfigurationCollection
    public var memberCount: Int?
    public var subscriptionUsage: ConfigurationSubscriptionUsage? = nil
     
     
     
     
    public var copyUpdatedAt: Date? = nil
     
     
     
    public var sourceUserAgent: String? = nil
    public var id: ConfigurationCollection.ID { collection.id }
    public init(source: ConfigurationSourceRecord, collection: ConfigurationCollection) {
        self.source = source; self.collection = collection; self.memberCount = collection.inlineCount
    }
}

public extension ConfigurationCollectionEntry {
     
     
     
     
     
     
    var definitionIsEditable: Bool {
        if case .bundled = source.origin { return false }
        return source.isRetainedSnapshot != true
    }
}

public extension ConfigurationLibraryStore {
    func collectionCatalog(_ snapshot: ConfigurationLibrarySnapshot) throws -> [ConfigurationCollectionEntry] {
        let read = snapshot.sourcesWhoseRulesAreRead
        return try snapshot.sources.flatMap { source in
             
             
             
             
            let sections = try providerSections(.init(source))
            let sourceUserAgent: String? = {
                switch sections["global-ua"] {
                case .string(let value)?: return value
                 
                case .scalar(let value)? where value != "null": return value
                default: return nil
                }
            }()
             
             
             
             
             
            return try [ConfigurationCollection.Kind.nodes, .rules].filter { kind in
                kind == .nodes ? source.suppliesNodes
                    : (!source.suppliesNodes || (source.registersSuppliedRules != false && read.contains(source.id)))
            }.flatMap { kind -> [ConfigurationCollectionEntry] in
                let section = sections[kind.rawValue]
                let document = OrderedJSON.object(section.map { [(key: kind.rawValue, value: $0)] } ?? [])
                return ConfigurationCollection.read(sourceID: source.id, document: document, kind: kind)
                    .map {
                        var entry = ConfigurationCollectionEntry(source: source, collection: $0)
                        entry.sourceUserAgent = sourceUserAgent
                        return entry
                    }
            }
        }
    }
}

public extension ConfigurationLibrarySnapshot {
     
     
     
     
    func readsRules(of sourceID: String) -> Bool {
        rules.contains { $0.sourceID == sourceID } || recipes.contains { recipe in
            recipe.ruleSource.id == sourceID
                || (recipe.settingsRuleDependencies ?? [:]).values.contains { $0.id == sourceID }
        }
    }

     
     
     
     
     
    func configurationKeepingRules(of sourceID: String) -> String? {
        guard !availableRules.contains(where: { $0.sourceID == sourceID && $0.collectionKey == nil }),
              let kept = rules.first(where: { $0.id == "rules-" + sourceID && $0.isRetainedSnapshot == true }) else { return nil }
        return recipes.first { $0.ruleSchemeID == kept.id }?.label ?? kept.label
    }

     
     
    var sourcesWhoseRulesAreRead: Set<String> {
        var ids = Set(rules.map(\.sourceID))
        for recipe in recipes {
            ids.insert(recipe.ruleSource.id)
            for dependency in (recipe.settingsRuleDependencies ?? [:]).values { ids.insert(dependency.id) }
        }
        return ids
    }
}

public extension ConfigurationRuleScheme {
    func projectingCollection(_ document: OrderedJSON) throws -> OrderedJSON {
        guard let key = collectionKey else { return document }
        guard let definition = document.topLevelValue("rule-providers")?.topLevelValue(key) else {
            throw ConfigurationCompositionError.unresolvedDependency(source: sourceID, name: key)
        }
        return .object([
            ("rule-providers", .object([(key, definition)])),
            ("proxy-groups", .array([.object([("name", .string("PROXY")), ("type", .string("select")),
                ("include-all", .scalar("true")), ("proxies", .array([.string("DIRECT")]))])])),
            ("rules", .array([.string("RULE-SET," + key + ",PROXY"), .string("MATCH,PROXY")]))
        ])
    }
}

public extension ConfigurationLibraryStore {
    func addRuleScheme(collection entry: ConfigurationCollectionEntry, expectedGeneration: UInt64) throws -> ConfigurationLibrarySnapshot {
        var candidate = try snapshot()
        guard candidate.generation == expectedGeneration,
              candidate.sources.contains(where: { $0.id == entry.source.id && $0.version == entry.source.version }) else {
            throw ConfigurationLibraryError.staleGeneration
        }
        guard entry.id.kind == .rules else { throw ConfigurationLibraryError.missingRules }
        if candidate.rules.contains(where: { $0.sourceID == entry.source.id && $0.collectionKey == entry.collection.name }) { return candidate }
        var scheme = ConfigurationRuleScheme(label: entry.collection.name, kind: .custom, sourceID: entry.source.id)
        scheme.collectionKey = entry.collection.name
        _ = try scheme.projectingCollection(OrderedJSON.parse(payload(.init(entry.source)).documentJSON))
        candidate.rules.append(scheme)
        return try commit(candidate, payloads: [], expectedGeneration: expectedGeneration)
    }
}


 
 
public enum ConfigurationCollectionError: LocalizedError, Equatable {
     
    case noDownloadAddress

    public var errorDescription: String? {
        switch self {
        case .noDownloadAddress: "This collection has no valid download address. Enter its URL in the collection's settings."
        }
    }
}

public extension ConfigurationCollection {
     
     
    func browserDownloadDefinition() throws -> OrderedJSON {
        guard let location, let url = URL(string: location),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
            throw ConfigurationCollectionError.noDownloadAddress
        }
        var result = OrderedJSON.object([("type", .string("http")), ("url", .string(location))])
        if id.kind == .rules {
            if let behavior { result = result.settingTopLevel("behavior", to: .string(behavior)) }
            result = result.settingTopLevel("format", to: .string(format))
        }
        return result
    }
}
