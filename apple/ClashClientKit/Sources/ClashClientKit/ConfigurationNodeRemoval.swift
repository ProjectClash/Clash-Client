import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 

 
 
 
 
public struct ConfigurationNodeOrigin: Equatable, Sendable {
    public let sourceID: String
    public let name: String
    public init(sourceID: String, name: String) { self.sourceID = sourceID; self.name = name }
}

 
public enum ConfigurationNodeRemovalError: Error, Equatable, Sendable {
     
     
     
     
     
     
     
     
     
     
     
     
     
    case stillInUse(node: String, places: [String])
}

 
 
 
 
public enum ConfigurationSourceTick: Equatable, Sendable {
    case node(String, checked: Bool)
    case nodeSet(String, checked: Bool)
}

 
public enum ConfigurationSourceTickError: Error, Equatable, Sendable {
     
     
     
    case lastTick(sourceID: String)
}

 
 
 
 
 
 
 
 
 
 
 
 
 
public enum ConfigurationNodeUses {
     
     
     
     
     
    public static func places(ofNode name: String, in document: OrderedJSON) -> [String] {
        var places: [String] = []
        if case .array(let groups)? = document.topLevelValue("proxy-groups") {
            for group in groups {
                guard case .array(let members)? = group.node(at: ["proxies"]),
                      members.contains(.string(name)), case .string(let groupName)? = group.node(at: ["name"]) else { continue }
                places.append(groupName)
            }
        }
        if case .array(let proxies)? = document.topLevelValue("proxies") {
            for proxy in proxies where proxy.node(at: ["dialer-proxy"]) == .string(name) {
                if case .string(let proxyName)? = proxy.node(at: ["name"]) { places.append(proxyName) }
            }
        }
        if case .object(let providers)? = document.topLevelValue("proxy-providers") {
            for provider in providers where provider.value.node(at: ["proxy"]) == .string(name)
                || provider.value.node(at: ["override", "dialer-proxy"]) == .string(name) {
                places.append(provider.key)
            }
        }
        if case .object(let providers)? = document.topLevelValue("rule-providers") {
            for provider in providers where provider.value.node(at: ["proxy"]) == .string(name) {
                places.append(provider.key)
            }
        }
        if case .array(let listeners)? = document.topLevelValue("listeners") {
            for listener in listeners where listener.node(at: ["proxy"]) == .string(name) {
                if case .string(let listenerName)? = listener.node(at: ["name"]) { places.append(listenerName) }
            }
        }
        if case .array(let tunnels)? = document.topLevelValue("tunnels") {
            for tunnel in tunnels {
                switch tunnel {
                case .string(let line):
                     
                    let fields = line.split(separator: ",", omittingEmptySubsequences: false)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                    if fields.count == 4, fields[3] == name { places.append(line) }
                case .object:
                    if tunnel.node(at: ["proxy"]) == .string(name), case .string(let address)? = tunnel.node(at: ["address"]) {
                        places.append(address)
                    }
                default:
                    break
                }
            }
        }
        if case .array(let rules)? = document.topLevelValue("rules") {
            for case .string(let rule) in rules where namesTarget(rule, name) { places.append(rule) }
        }
        if case .object(let branches)? = document.topLevelValue("sub-rules") {
            for branch in branches {
                guard case .array(let rules) = branch.value else { continue }
                for case .string(let rule) in rules where namesTarget(rule, name) { places.append(rule) }
            }
        }
        return places
    }

     
     
     
    public static func namesTarget(_ rule: String, _ name: String) -> Bool {
        rule.split(separator: ",").dropFirst().contains { $0.trimmingCharacters(in: .whitespaces) == name }
    }
}

 
 
 
 
 
public struct ConfigurationOriginalNodeDeletion: Sendable {
     
    public let current: ConfigurationSourcePayload
     
    public let node: String
    public let index: Int
     
     
     
    public let savesAsOwnCopy: Bool
     
    public let sourceID: String
    public let label: String
    public let origin: ConfigurationSourceRecord.Origin
}

 
 
 
public struct ConfigurationNodeRemoval: Equatable, Sendable {
    public let profileID: String
     
    public let node: String
    public let origin: ConfigurationNodeOrigin
    let change: Change

     
     
    public var editedOriginalText: Bool {
        if case .text = change { return true }
        return false
    }

    enum Change: Equatable, Sendable {
         
        case excluded(before: ConfigurationNodeScope?, after: ConfigurationNodeScope?)
        case text(Rewrite)
    }

     
     
    struct Rewrite: Equatable, Sendable {
        let recipeBefore: ConfigurationRecipe
        let recipeAfter: ConfigurationRecipe
        let sources: [Record<ConfigurationSourceRecord>]
        let rules: [Record<ConfigurationRuleScheme>]
        let held: [ConfigurationSourcePayload]
    }

     
    struct Record<Value: Equatable & Sendable>: Equatable, Sendable {
        let id: String
        let before: Value?
        let after: Value?
    }
}

public extension ConfigurationLibraryStore {
     
     
    func nodeOrigin(of node: String, in profileID: String,
                    resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput = {
                        .init(id: $0.record.id, document: try OrderedJSON.parse($0.documentJSON))
                    }) throws -> ConfigurationNodeOrigin? {
        let current = try snapshot()
        guard let recipe = current.recipes.first(where: { $0.id == profileID }) else {
            throw ConfigurationLibraryError.missingDependency(profileID)
        }
        return try nodeOrigin(of: node, in: recipe, snapshot: current, resolveInput: resolveInput)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    func prepareNodeRemoval(node: String, from profileID: String, expectedGeneration: UInt64,
                            deletingFromText: (ConfigurationOriginalNodeDeletion) throws -> ConfigurationSourcePayload,
                            resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput = {
                                .init(id: $0.record.id, document: try OrderedJSON.parse($0.documentJSON))
                            }) throws -> PreparedConfigurationSourceUpdate {
        let current = try snapshot()
        guard current.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        guard current.pendingPublications?.isEmpty ?? true else { throw ConfigurationLibraryError.busy }
        guard let recipe = current.recipes.first(where: { $0.id == profileID }) else {
            throw ConfigurationLibraryError.missingDependency(profileID)
        }
        if recipe.preservesOriginal == true {
            return try prepareTextDeletion(of: node, from: recipe, in: current, expectedGeneration: expectedGeneration,
                                           deletingFromText: deletingFromText, resolveInput: resolveInput)
        }
        guard let origin = try nodeOrigin(of: node, in: recipe, snapshot: current, resolveInput: resolveInput) else {
            throw ConfigurationLibraryError.missingDependency(node)
        }
        let before = recipe.nodeScopes?[origin.sourceID]
         
         
         
        guard before?.choosesNode(named: origin.name) ?? true else {
            let running = try composition(of: recipe, in: current, resolveInput: resolveInput)
            throw ConfigurationNodeRemovalError.stillInUse(node: node, places: ConfigurationNodeUses.places(ofNode: node, in: running.document))
        }
        var after = try before ?? wholeSourceScope(of: origin.sourceID, in: recipe)
        after.excludedNodeNames = Array(Set(after.excludedNodeNames ?? []).union([origin.name])).sorted()
        var prepared = try preparingScope(after, of: origin.sourceID, in: recipe, snapshot: current, resolveInput: resolveInput)
        prepared.nodeRemoval = ConfigurationNodeRemoval(profileID: profileID, node: node, origin: origin,
                                                        change: .excluded(before: before, after: after))
        return prepared
    }

     
     
     
     
     
     
    func prepareNodeChoice(_ node: String, ofSource sourceID: String, for profileID: String, checked: Bool,
                           expectedGeneration: UInt64,
                           resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput = {
                               .init(id: $0.record.id, document: try OrderedJSON.parse($0.documentJSON))
                           }) throws -> PreparedConfigurationSourceUpdate {
        let before = try snapshot().recipes.first { $0.id == profileID }?.nodeScopes?[sourceID]
        var prepared = try prepareSourceTicks([.node(node, checked: checked)], ofSource: sourceID, for: profileID,
                                              expectedGeneration: expectedGeneration, resolveInput: resolveInput)
        if !checked, !prepared.compositions.isEmpty {
            let after = prepared.candidate.recipes.first { $0.id == profileID }?.nodeScopes?[sourceID]
            prepared.nodeRemoval = ConfigurationNodeRemoval(
                profileID: profileID, node: node, origin: ConfigurationNodeOrigin(sourceID: sourceID, name: node),
                change: .excluded(before: before, after: after))
        }
        return prepared
    }

     
     
     
     
     
     
     
     
    func prepareSourceTicks(_ ticks: [ConfigurationSourceTick], ofSource sourceID: String, for profileID: String,
                            expectedGeneration: UInt64,
                            resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput = {
                                .init(id: $0.record.id, document: try OrderedJSON.parse($0.documentJSON))
                            }) throws -> PreparedConfigurationSourceUpdate {
        let current = try snapshot()
        guard current.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        guard current.pendingPublications?.isEmpty ?? true else { throw ConfigurationLibraryError.busy }
        guard let recipe = current.recipes.first(where: { $0.id == profileID }) else {
            throw ConfigurationLibraryError.missingDependency(profileID)
        }
         
        guard recipe.preservesOriginal != true else { throw ConfigurationLibraryError.invalidIdentifier.noted() }
        guard let reference = recipe.sources.first(where: { $0.id == sourceID }) else {
            throw ConfigurationLibraryError.missingDependency(sourceID)
        }
         
        let document = try OrderedJSON.parse(try payload(reference).documentJSON)
        let nodeSets: [String] = {
            guard case .object(let providers)? = document.topLevelValue("proxy-providers") else { return [] }
            return providers.map(\.key)
        }()
        let before = recipe.nodeScopes?[sourceID]
        var scope = before ?? ConfigurationNodeScope(includesInlineNodes: true, providerKeys: nodeSets)
        for tick in ticks {
            switch tick {
            case .node(let name, let checked):
                if scope.choosesNode(named: name) != checked { scope = scope.choosingNode(named: name, checked: checked) }
            case .nodeSet(let key, let checked):
                var taken = Set(scope.providerKeys)
                if checked { taken.insert(key) } else { taken.remove(key) }
                 
                scope.providerKeys = nodeSets.filter(taken.contains) + scope.providerKeys.filter { !nodeSets.contains($0) && taken.contains($0) }
            }
        }
        let inline = Self.inlineNodeNames(in: document)
        guard inline.contains(where: { scope.choosesNode(named: $0) }) || !scope.providerKeys.isEmpty else {
            throw ConfigurationSourceTickError.lastTick(sourceID: sourceID)
        }
        let after = scope.settled(nodeSets: nodeSets)
        guard after != before else { return .init(candidate: current, payloads: [], compositions: [:]) }
        return try preparingScope(after, of: sourceID, in: recipe, snapshot: current, resolveInput: resolveInput)
    }

     
     
     
     
     
     
    func prepareRestore(_ removal: ConfigurationNodeRemoval,
                        resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput = {
                            .init(id: $0.record.id, document: try OrderedJSON.parse($0.documentJSON))
                        }) throws -> PreparedConfigurationSourceUpdate {
        var candidate = try snapshot()
        guard candidate.pendingPublications?.isEmpty ?? true else { throw ConfigurationLibraryError.busy }
        guard let index = candidate.recipes.firstIndex(where: { $0.id == removal.profileID }) else {
            throw ConfigurationLibraryError.staleGeneration
        }
        switch removal.change {
        case .excluded(let before, let after):
            let recipe = candidate.recipes[index]
            let sourceID = removal.origin.sourceID
            guard recipe.preservesOriginal != true, recipe.sources.contains(where: { $0.id == sourceID }) else {
                throw ConfigurationLibraryError.staleGeneration
            }
            let now = recipe.nodeScopes?[sourceID]
            let restored: ConfigurationNodeScope?
            if now == after {
                restored = before
            } else if var scope = now, (scope.excludedNodeNames ?? []).contains(removal.origin.name) {
                scope.excludedNodeNames?.removeAll { $0 == removal.origin.name }
                restored = try settled(scope, of: sourceID, in: recipe)
            } else {
                throw ConfigurationLibraryError.staleGeneration
            }
            return try preparingScope(restored, of: sourceID, in: recipe, snapshot: candidate, resolveInput: resolveInput)
        case .text(let rewrite):
            guard candidate.recipes[index] == rewrite.recipeAfter,
                  rewrite.sources.allSatisfy({ record in candidate.sources.first { $0.id == record.id } == record.after }),
                  rewrite.rules.allSatisfy({ record in candidate.rules.first { $0.id == record.id } == record.after }) else {
                throw ConfigurationLibraryError.staleGeneration
            }
            for record in rewrite.sources { Self.put(record, into: &candidate.sources) }
            for record in rewrite.rules { Self.put(record, into: &candidate.rules) }
            let recipe = rewrite.recipeBefore
            candidate.recipes[index] = recipe
            let text = try rewrite.held.first(where: { ConfigurationSourceVersion($0.record) == recipe.ruleSource })
                ?? payload(recipe.ruleSource)
            let input = try resolveInput(text)
            guard input.id == recipe.ruleSource.id, case .object = input.document else {
                throw ConfigurationCompositionError.invalidDocument(recipe.ruleSource.id)
            }
            let composition = ConfigurationComposition(document: try overlayingAdvancedSettings(of: recipe, onto: input.document),
                                                       sourceIDs: [input.id])
            return .init(candidate: candidate, payloads: rewrite.held, compositions: [recipe.id: composition])
        }
    }
}

extension ConfigurationLibraryStore {
     
    static func inlineNodeNames(in document: OrderedJSON) -> [String] {
        guard case .array(let nodes)? = document.topLevelValue("proxies") else { return [] }
        return nodes.compactMap { node in
            if case .string(let name)? = node.topLevelValue("name") { return name }
            return nil
        }
    }

     
     
    func nodeOrigin(of node: String, in recipe: ConfigurationRecipe, snapshot: ConfigurationLibrarySnapshot,
                    resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput) throws -> ConfigurationNodeOrigin? {
        if recipe.preservesOriginal == true {
            let document = try OrderedJSON.parse(try payload(recipe.ruleSource).documentJSON)
            return Self.inlineNodeNames(in: document).contains(node) ? ConfigurationNodeOrigin(sourceID: recipe.ruleSource.id, name: node) : nil
        }
        var written: [ConfigurationNodeOrigin] = []
        for reference in recipe.sources {
            let input = try resolveInput(try payload(reference))
            guard input.id == reference.id else { throw ConfigurationLibraryError.invalidIdentifier.noted() }
            let scoped = try recipe.nodeScopes?[reference.id]?.applying(to: input) ?? input
            written += Self.inlineNodeNames(in: scoped.document).map { ConfigurationNodeOrigin(sourceID: reference.id, name: $0) }
        }
        let shown = Self.inlineNodeNames(in: try composition(of: recipe, in: snapshot, resolveInput: resolveInput).document)
        guard shown.count == written.count else { throw ConfigurationCompositionError.invalidDocument(recipe.id) }
        return zip(shown, written).first { $0.0 == node }?.1
    }

     
     
     
     
    func wholeSourceScope(of sourceID: String, in recipe: ConfigurationRecipe) throws -> ConfigurationNodeScope {
        .init(includesInlineNodes: true, providerKeys: try providerKeys(of: sourceID, in: recipe))
    }

    private func providerKeys(of sourceID: String, in recipe: ConfigurationRecipe) throws -> [String] {
        guard let reference = recipe.sources.first(where: { $0.id == sourceID }) else {
            throw ConfigurationLibraryError.missingDependency(sourceID)
        }
        guard case .object(let providers)? = try OrderedJSON.parse(try payload(reference).documentJSON)
            .topLevelValue("proxy-providers") else { return [] }
        return providers.map(\.key)
    }

     
     
     
    func settled(_ scope: ConfigurationNodeScope, of sourceID: String,
                 in recipe: ConfigurationRecipe) throws -> ConfigurationNodeScope? {
        scope.settled(nodeSets: try providerKeys(of: sourceID, in: recipe))
    }

     
    func preparingScope(_ scope: ConfigurationNodeScope?, of sourceID: String, in recipe: ConfigurationRecipe,
                        snapshot: ConfigurationLibrarySnapshot,
                        resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput) throws -> PreparedConfigurationSourceUpdate {
        guard let index = snapshot.recipes.firstIndex(where: { $0.id == recipe.id }) else {
            throw ConfigurationLibraryError.missingDependency(recipe.id)
        }
        var candidate = snapshot
        var changed = recipe
        var scopes = changed.nodeScopes ?? [:]
        scopes[sourceID] = scope
        changed.nodeScopes = scopes.isEmpty ? nil : scopes
        let composition = try composition(of: changed, in: candidate, resolveInput: resolveInput)
        changed.droppedRules = composition.droppedRules.isEmpty ? nil : composition.droppedRules
        candidate.recipes[index] = changed
        return .init(candidate: candidate, payloads: [], compositions: [recipe.id: composition])
    }

     
     
     
     
    private func prepareTextDeletion(of node: String, from recipe: ConfigurationRecipe, in snapshot: ConfigurationLibrarySnapshot,
                                     expectedGeneration: UInt64,
                                     deletingFromText: (ConfigurationOriginalNodeDeletion) throws -> ConfigurationSourcePayload,
                                     resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput) throws -> PreparedConfigurationSourceUpdate {
        guard let record = snapshot.sources.first(where: { $0.id == recipe.ruleSource.id }) else {
            throw ConfigurationLibraryError.missingDependency(recipe.ruleSource.id)
        }
        let current = try payload(recipe.ruleSource)
        let document = try OrderedJSON.parse(current.documentJSON)
         
        guard case .array(let entries)? = document.topLevelValue("proxies"),
              let index = entries.firstIndex(where: { $0.topLevelValue("name") == .string(node) }) else {
            throw ConfigurationLibraryError.missingDependency(node)
        }
        let places = ConfigurationNodeUses.places(ofNode: node, in: document)
        guard places.isEmpty else { throw ConfigurationNodeRemovalError.stillInUse(node: node, places: places) }

        let kept = record.isRetainedSnapshot == true
        let followsLink: Bool = { if !kept, case .subscription = record.origin { return true }; return false }()
        let shared = snapshot.recipes.contains { $0.id != recipe.id && $0.dependencies.contains { $0.id == record.id } }
            || snapshot.sources.contains { $0.nodeChain?.hops.contains { $0.source.id == record.id } == true }
        let ownCopy = followsLink || kept || shared
        let request = ConfigurationOriginalNodeDeletion(
            current: current, node: node, index: index, savesAsOwnCopy: ownCopy,
            sourceID: ownCopy ? "edited-" + UUID().uuidString : record.id,
            label: ownCopy ? recipe.label : record.label,
            origin: ownCopy ? .file(recipe.label + ".yaml") : record.origin)
        let edited = try deletingFromText(request)
        guard edited.record.id == request.sourceID else { throw ConfigurationLibraryError.invalidIdentifier.noted() }
        guard !Self.inlineNodeNames(in: try OrderedJSON.parse(edited.documentJSON)).contains(node) else {
            throw ConfigurationLibraryError.invalidIdentifier.noted("the edited text still has the node")
        }
         
         
        let replacement = ConfigurationSourcePayload(
            record: ownCopy ? edited.record : Self.record(record, takingContentOf: edited.record),
            original: edited.original, documentJSON: edited.documentJSON, resourceFiles: current.resourceFiles)

        var prepared: PreparedConfigurationSourceUpdate
        if ownCopy {
            let made = try prepareOwnSourceCopy(recipe.id, replacement: replacement, expectedGeneration: expectedGeneration,
                                                resolveInput: resolveInput)
            prepared = .init(candidate: made.candidate, payloads: made.payloads, compositions: [recipe.id: made.composition])
        } else {
            prepared = try prepareSourceUpdate(replacement, expectedGeneration: expectedGeneration,
                                               updatingPinnedConsumers: true, resolveInput: resolveInput)
        }
        guard let after = prepared.candidate.recipes.first(where: { $0.id == recipe.id }) else {
            throw ConfigurationLibraryError.missingDependency(recipe.id)
        }
         
         
         
        let committed = Self.pruningUnreferencedRetainedRecords(prepared.candidate).snapshot
        let rewrite = ConfigurationNodeRemoval.Rewrite(
            recipeBefore: recipe, recipeAfter: after,
            sources: Self.changes(from: snapshot.sources, to: committed.sources, id: \.id),
            rules: Self.changes(from: snapshot.rules, to: committed.rules, id: \.id),
            held: [current])
        prepared.nodeRemoval = ConfigurationNodeRemoval(
            profileID: recipe.id, node: node, origin: ConfigurationNodeOrigin(sourceID: record.id, name: node),
            change: .text(rewrite))
        return prepared
    }

     
     
     
    static func record(_ current: ConfigurationSourceRecord,
                       takingContentOf computed: ConfigurationSourceRecord) -> ConfigurationSourceRecord {
        var record = current
        record.version = computed.version
        record.nodeCount = computed.nodeCount
        record.providerCount = computed.providerCount
        record.groupCount = computed.groupCount
        record.ruleCount = computed.ruleCount
        record.ruleProviderCount = computed.ruleProviderCount
        record.updatedAt = computed.updatedAt
        record.rulesWrittenInOriginal = computed.rulesWrittenInOriginal
        return record
    }

     
    static func changes<Value: Equatable & Sendable>(from before: [Value], to after: [Value],
                                                     id: (Value) -> String) -> [ConfigurationNodeRemoval.Record<Value>] {
        let old = Dictionary(before.map { (id($0), $0) }, uniquingKeysWith: { first, _ in first })
        let new = Dictionary(after.map { (id($0), $0) }, uniquingKeysWith: { first, _ in first })
        var ids: [String] = []
        for value in before + after where !ids.contains(id(value)) { ids.append(id(value)) }
        return ids.compactMap { key in
            old[key] == new[key] ? nil : .init(id: key, before: old[key], after: new[key])
        }
    }

     
    static func put<Value: Equatable & Sendable & Identifiable>(_ record: ConfigurationNodeRemoval.Record<Value>,
                                                                 into values: inout [Value]) where Value.ID == String {
        if let before = record.before {
            if let index = values.firstIndex(where: { $0.id == record.id }) { values[index] = before } else { values.append(before) }
        } else {
            values.removeAll { $0.id == record.id }
        }
    }
}
