import CryptoKit
import Foundation

public struct PreparedConfigurationCreation: Sendable {
    public let recipe: ConfigurationRecipe
    public let composition: ConfigurationComposition
    public let candidate: ConfigurationLibrarySnapshot
    public let payloads: [ConfigurationSourcePayload]
}

public struct PreparedConfigurationSourceUpdate: Sendable {
    public let candidate: ConfigurationLibrarySnapshot
    public let payloads: [ConfigurationSourcePayload]
    public let compositions: [String: ConfigurationComposition]
     
     
     
    public var pageRefusals: [String: String] = [:]
}

 
 
 
public struct ConfigurationSchemePageRefusal: Error, Equatable, Sendable {
    public let sourceID: String
    public let reason: String
}

public struct ConfigurationLibraryArchive: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var snapshot: ConfigurationLibrarySnapshot
    public var payloads: [ConfigurationSourcePayload]
    public var publications: [ConfigurationPublicationPayload]?
    public init(snapshot: ConfigurationLibrarySnapshot, payloads: [ConfigurationSourcePayload],
                publications: [ConfigurationPublicationPayload] = []) {
        self.snapshot = snapshot; self.payloads = payloads; self.publications = publications
    }
}

public enum ConfigurationBuiltins {
    public static let basicRuleID = "clash-basic-rules"
    public static let directYAML = "rules:\n  - MATCH,DIRECT\n"

     
    private static let localRules = ["GEOIP,private,DIRECT,no-resolve", "GEOSITE,private,DIRECT"]
    private static let fallbackRules = ["GEOSITE,geolocation-!cn,PROXY", "GEOSITE,cn,DIRECT", "GEOIP,CN,DIRECT", "MATCH,PROXY"]

    fileprivate static var basicDocument: OrderedJSON {
        let automatic = try! OrderedJSON.parse(#"{"name":"AUTO","type":"url-test","include-all":true,"url":"https://www.gstatic.com/generate_204","interval":300}"#)
        let selector = try! OrderedJSON.parse(#"{"name":"PROXY","type":"select","include-all":true,"proxies":["AUTO","DIRECT"]}"#)
        let rules = localRules + fallbackRules
        return .object([("proxy-groups", .array([automatic, selector])), ("rules", .array(rules.map(OrderedJSON.string)))])
    }
    public static var basicRecord: ConfigurationSourceRecord { basicSource.record }
    fileprivate static var basicSource: ConfigurationSourcePayload { shippedBasic }
    private static let shippedBasic: ConfigurationSourcePayload = {
        let json = basicDocument.serialized()
        let record = ConfigurationSourceRecord(id: basicRuleID, label: "Default Configuration", origin: .bundled("basic"),
            version: contentVersion(json), groupCount: 2, ruleCount: localRules.count + fallbackRules.count, suppliesNodes: false, updatedAt: Date(timeIntervalSince1970: 0))
        return .init(record: record, original: Data(json.utf8), documentJSON: json)
    }()

     
     
     
     
     
     
     
    static func contentVersion(_ document: String) -> String {
        SHA256.hash(data: Data(document.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }
    public static var basicScheme: ConfigurationRuleScheme {
        .init(id: basicRuleID, label: "Default Configuration", kind: .builtin, sourceID: basicRuleID)
    }
}

extension ConfigurationLibraryStore {
     
     
     
    public func prepare(_ draft: ConfigurationCreationDraft, profileID: String,
                        expectedGeneration: UInt64,
                        resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput = {
                            .init(id:$0.record.id,document:try OrderedJSON.parse($0.documentJSON))
                        }) throws -> PreparedConfigurationCreation {
        let current = try snapshot()
        guard current.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        guard !current.sources.contains(where: { $0.id == draft.originalSourceID && $0.isRetainedSnapshot == true }),
              !draft.selectedSourceIDs.contains(where: { id in current.sources.contains { $0.id == id && $0.isRetainedSnapshot == true } }),
              !current.rules.contains(where: { $0.id == draft.selectedRuleID && $0.isRetainedSnapshot == true }) else {
            throw ConfigurationLibraryError.retainedSnapshot
        }
         
        guard !Self.picksAnotherConfigurationsOwn(draft, profileID: profileID, in: current) else {
            throw ConfigurationLibraryError.missingDependency("another configuration's own")
        }
        if draft.originalSourceID != nil {
            return try prepareOriginal(draft, profileID: profileID, starting: current, resolveInput: resolveInput)
        }
        return try prepareCreation(draft, profileID: profileID, starting: current, resolveInput: resolveInput)
    }

     
     
     
    static func picksAnotherConfigurationsOwn(_ draft: ConfigurationCreationDraft, profileID: String,
                                              in snapshot: ConfigurationLibrarySnapshot) -> Bool {
        let named = Set(draft.selectedSourceIDs + [draft.originalSourceID].compactMap { $0 })
        return snapshot.sources.contains { named.contains($0.id) && ($0.privateToConfigurationID ?? profileID) != profileID }
            || snapshot.rules.contains { $0.id == draft.selectedRuleID && ($0.privateToConfigurationID ?? profileID) != profileID }
    }

    private func prepareCreation(_ draft: ConfigurationCreationDraft, profileID: String,
                                 starting: ConfigurationLibrarySnapshot,
                                 pinnedRule: ConfigurationSourceVersion? = nil,
                                 pinnedNodes: [ConfigurationSourceVersion] = [],
                                 settingsJSON: String = "{}",
                                 settingsSource: ConfigurationSourceVersion? = nil,
                                 settingsRuleDependencies: [String: ConfigurationSourceVersion]? = nil,
                                 resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput) throws -> PreparedConfigurationCreation {
        var candidate = starting
        guard !candidate.recipes.contains(where: { $0.id == profileID }) else {
            throw ConfigurationLibraryError.invalidIdentifier.noted()
        }
        guard Set(draft.selectedSourceIDs).count == draft.selectedSourceIDs.count else {
            throw ConfigurationLibraryError.invalidIdentifier.noted()
        }
        var available = draft.sources(in: candidate)
        var schemes = draft.rules(in: candidate)
        var staged = draft.newSources
         
         
        if pinnedRule == nil, let picked = draft.selectedRuleID,
           case let id = schemes.first(where: { $0.id == picked })?.rulesFromSchemeID ?? picked,
           let bundled = try ConfigurationBuiltins.source(for: id) {
            if !available.contains(where: { $0.id == id && $0.version == bundled.record.version }) {
                staged.removeAll { $0.record.id == id }
                available.removeAll { $0.id == id }
                staged.append(bundled); available.append(bundled.record)
            }
            if !schemes.contains(where: { $0.id == id }), let scheme = ConfigurationBuiltins.schemes.first(where: { $0.id == id }) {
                schemes.append(scheme)
            }
        }
        guard let ruleID = draft.selectedRuleID,
              let scheme = schemes.first(where: { $0.id == ruleID }),
              let currentRuleRecord = available.first(where: { $0.id == scheme.sourceID }) else {
            throw ConfigurationLibraryError.missingDependency("rule scheme")
        }
        let ruleRecord = try pinnedRule.map { try payload($0).record } ?? currentRuleRecord
        func record(_ id: String) throws -> ConfigurationSourceRecord {
            if let pin = pinnedNodes.first(where: { $0.id == id }) { return try payload(pin).record }
            guard let value = available.first(where: { $0.id == id }) else {
                throw ConfigurationLibraryError.missingDependency(id)
            }
            return value
        }
        func input(_ record: ConfigurationSourceRecord) throws -> ConfigurationInput {
            let source = try staged.first(where: { $0.record.id == record.id && $0.record.version == record.version })
                ?? payload(.init(record))
            let resolved = try resolveInput(source)
            guard resolved.id == record.id else { throw ConfigurationLibraryError.invalidIdentifier.noted() }
            return resolved
        }
        let records = try draft.selectedSourceIDs.map(record)
        let inputs = try records.map(input)
        let composition = try composeInputs(inputs, ruleInput: input(ruleRecord), schemeID: scheme.id, scheme: scheme, page: try ConfigurationSchemePage.effective(schemePage: ConfigurationSchemePage.of(scheme), settingsJSON: settingsJSON, dnsMode: draft.dnsMode, customDNSJSON: draft.customDNSJSON, nodeNameservers: draft.nodeNameservers), nodeScopes: draft.nodeScopes, settingsProviders: try settingsProviders(settingsRuleDependencies, resolveInput: resolveInput), ruleSchemes: schemes)
        let used = Set(records.map(\.id) + [ruleRecord.id])
        let payloads = staged.filter { used.contains($0.record.id) }
         
         
         
        for value in available where used.contains(value.id) {
            if let i = candidate.sources.firstIndex(where: { $0.id == value.id }) { candidate.sources[i] = value }
            else { candidate.sources.append(value) }
        }
        for value in schemes where value.id == scheme.id {
            if let i = candidate.rules.firstIndex(where: { $0.id == value.id }) { candidate.rules[i] = value }
            else { candidate.rules.append(value) }
        }
        let label = draft.label.trimmingCharacters(in:.whitespacesAndNewlines)
        var recipe = ConfigurationRecipe(id:profileID, label:label.isEmpty ? (records.first?.label ?? "Direct") : label,
            sources:records.map(ConfigurationSourceVersion.init), ruleSchemeID:scheme.id, ruleSource:.init(ruleRecord), nodeNameservers: draft.nodeNameservers, dnsMode: draft.dnsMode, customDNSJSON: draft.customDNSJSON, settingsJSON: settingsJSON, settingsSource: settingsSource)
        recipe.settingsRuleDependencies = settingsRuleDependencies
        recipe.nodeScopes = draft.nodeScopes?.filter { draft.selectedSourceIDs.contains($0.key) }
        recipe.droppedRules = composition.droppedRules.isEmpty ? nil : composition.droppedRules
        candidate.recipes.append(recipe)
        return PreparedConfigurationCreation(recipe:recipe, composition:composition, candidate:candidate, payloads:payloads)
    }

     
     
     
    public func prepareEditing(_ draft: ConfigurationCreationDraft, profileID: String,
                               expectedGeneration: UInt64,
                               resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput = {
                                   .init(id: $0.record.id, document: try OrderedJSON.parse($0.documentJSON))
                               }) throws -> PreparedConfigurationCreation {
        var current = try snapshot()
        guard current.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        guard current.pendingPublications?.isEmpty ?? true else { throw ConfigurationLibraryError.busy }
        guard var existing = current.recipes.first(where: { $0.id == profileID }) else {
            throw ConfigurationLibraryError.missingDependency(profileID)
        }
        guard !Self.picksAnotherConfigurationsOwn(draft, profileID: profileID, in: current) else {
            throw ConfigurationLibraryError.missingDependency("another configuration's own")
        }
        try adoptComposition(in: &existing, resolveInput: resolveInput)
        try freezeSettings(in: &existing, resolveInput: resolveInput)
        current.recipes.removeAll { $0.id == profileID }
        var draft = draft
         
         
         
         
        if draft.selectedRuleID != existing.ruleSchemeID,
           let own = current.ownView(of: draft.selectedRuleID, for: profileID) { draft.selectedRuleID = own.id }
        if draft.step == .rules || draft.step == .finish { draft.nodeScopes = existing.nodeScopes }
        existing.dnsMode = draft.dnsMode
        existing.customDNSJSON = draft.customDNSJSON
        try captureSettingsDependencies(in: &existing, resolveInput: resolveInput)
        if draft.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { draft.label = existing.label }
        let prepared = try prepareCreation(draft, profileID: profileID, starting: current,
            pinnedRule: (draft.step == .sources || draft.step == .finish || current.rules.first(where: { $0.id == existing.ruleSchemeID })?.isRetainedSnapshot == true) && draft.selectedRuleID == existing.ruleSchemeID ? existing.ruleSource : nil,
            pinnedNodes: (draft.step == .rules || draft.step == .finish) ? existing.sources : existing.sources.filter { reference in current.sources.contains { $0.id == reference.id && $0.isRetainedSnapshot == true } },
            settingsJSON: existing.settingsJSON ?? "{}", settingsSource: existing.settingsSource, settingsRuleDependencies: existing.settingsRuleDependencies, resolveInput: resolveInput)
        existing.preservesOriginal = nil  
        existing.composedRuleSchemeID = nil
        existing.droppedRules = prepared.recipe.droppedRules  
        existing.label = prepared.recipe.label
        existing.sources = prepared.recipe.sources
        existing.nodeScopes = prepared.recipe.nodeScopes
        existing.ruleSchemeID = prepared.recipe.ruleSchemeID
        existing.ruleSource = prepared.recipe.ruleSource
        existing.nodeNameservers = prepared.recipe.nodeNameservers
        existing.dnsMode = prepared.recipe.dnsMode
        existing.customDNSJSON = prepared.recipe.customDNSJSON
        existing.settingsJSON = prepared.recipe.settingsJSON
        var candidate = prepared.candidate
        candidate.recipes.removeAll { $0.id == profileID }; candidate.recipes.append(existing)
        return .init(recipe: existing, composition: prepared.composition, candidate: candidate, payloads: prepared.payloads)
    }

    public func prepareSourceUpdate(_ replacement: ConfigurationSourcePayload,
                                    expectedGeneration: UInt64, updatingPinnedConsumers: Bool = false,
                                    replaceEditedRules: Bool = false,
                                    resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput = {
                                        .init(id: $0.record.id, document: try OrderedJSON.parse($0.documentJSON))
                                    }) throws -> PreparedConfigurationSourceUpdate {
        let current = try snapshot()
        guard current.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        return try prepareSourceUpdate(replacement, from: current, updatingPinnedConsumers: updatingPinnedConsumers,
            replaceEditedRules: replaceEditedRules, resolveInput: resolveInput)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    public func prepareBuiltinSchemeUpgrade(expectedGeneration: UInt64,
        resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput = {
            .init(id: $0.record.id, document: try OrderedJSON.parse($0.documentJSON))
        }) throws -> PreparedConfigurationSourceUpdate? {
        var candidate = try snapshot()
        guard candidate.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        var payloads: [ConfigurationSourcePayload] = []
        var compositions: [String: ConfigurationComposition] = [:]
        for id in [ConfigurationBuiltins.basicRuleID, ConfigurationBuiltins.lazyRuleID] {
            guard let bundled = try ConfigurationBuiltins.source(for: id),
                  let stored = candidate.sources.first(where: { $0.id == id }),
                  stored.isRetainedSnapshot != true else { continue }
            let to = ConfigurationSourceVersion(bundled.record)
            let recordMoves = stored.version != bundled.record.version
             
             
             
             
             
             
            let stuck = Set((candidate.updateIssues ?? []).filter { $0.sourceID == id }.map(\.itemID))
            let behind = candidate.recipes.indices.filter {
                let recipe = candidate.recipes[$0]
                return recipe.preservesOriginal != true && recipe.ruleSource.id == id && recipe.ruleSource != to
                    && (recordMoves || !stuck.contains(recipe.id))
                    && candidate.rules.first(where: { $0.id == recipe.ruleSchemeID })?.isRetainedSnapshot != true
            }
            guard recordMoves || !behind.isEmpty else { continue }
            guard candidate.pendingPublications?.isEmpty ?? true else { throw ConfigurationLibraryError.busy }
             
             
            var sameDocument: [ConfigurationSourceVersion: Bool] = [:]
            func holdsTheShippedDocument(_ version: ConfigurationSourceVersion) -> Bool {
                if let known = sameDocument[version] { return known }
                let same = (try? payload(version).documentJSON) == bundled.documentJSON
                sameDocument[version] = same
                return same
            }
            if behind.allSatisfy({ holdsTheShippedDocument(candidate.recipes[$0].ruleSource) }) {
                if let index = candidate.sources.firstIndex(where: { $0.id == id }) { candidate.sources[index] = bundled.record }
                for index in behind { candidate.recipes[index].ruleSource = to }
                payloads.append(bundled)
                continue
            }
             
             
             
            let prepared = try prepareSourceUpdate(bundled, from: candidate, includingFrozenConsumers: true,
                                                   onlyRecipes: Set(behind.map { candidate.recipes[$0].id }),
                                                   resolveInput: resolveInput)
            candidate = prepared.candidate
            payloads += prepared.payloads
            compositions.merge(prepared.compositions) { _, new in new }
        }
        guard !payloads.isEmpty else { return nil }
        return .init(candidate: candidate, payloads: payloads, compositions: compositions)
    }

    private func prepareSourceUpdate(_ replacement: ConfigurationSourcePayload, from starting: ConfigurationLibrarySnapshot,
                                     updatingPinnedConsumers: Bool = false, replaceEditedRules: Bool = false,
                                     includingFrozenConsumers: Bool = false, onlyRecipes: Set<String>? = nil,
                                     resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput) throws -> PreparedConfigurationSourceUpdate {
        var candidate = starting
        guard candidate.pendingPublications?.isEmpty ?? true else { throw ConfigurationLibraryError.busy }
        guard let index = candidate.sources.firstIndex(where: { $0.id == replacement.record.id }) else {
            throw ConfigurationLibraryError.missingDependency(replacement.record.id)
        }
        guard candidate.sources[index].isRetainedSnapshot != true else { throw ConfigurationLibraryError.retainedSnapshot }
         
        var replacement = replacement
        replacement.record.suppliesNodes = candidate.sources[index].suppliesNodes
         
        replacement.record.privateToConfigurationID = candidate.sources[index].privateToConfigurationID
         
         
         
         
         
         
        let followers = candidate.rules.indices.filter { candidate.rules[$0].takesPage(fromSource: replacement.record.id) }
        let incomingDocument = followers.isEmpty ? nil : try OrderedJSON.parse(replacement.documentJSON)
        var pageRefusals: [String: String] = [:]
        let previous = try payload(.init(candidate.sources[index]))
        if let baseline = previous.ruleBaselineJSON, !replaceEditedRules {
             
             
             
             
             
            if replacement.record.rulesWrittenInOriginal == true || previous.record.rulesWrittenInOriginal == true {
                throw ConfigurationRuleReplay.Conflict(path: ["rules"])
            }
             
             
             
             
             
             
            let slots = Set(ConfigurationRuleDocument.nodeNames(in: try OrderedJSON.parse(replacement.documentJSON)))
                .union(candidate.rules.filter { $0.sourceID == replacement.record.id }.flatMap { $0.namedNodes ?? [] })
            func asSlots(_ document: OrderedJSON) -> OrderedJSON {
                ConfigurationRuleDocument.binding(ConfigurationRuleDocument.project(document), nodes: slots, supplied: [])
            }
            let incoming = asSlots(try OrderedJSON.parse(replacement.documentJSON))
            let merged = try ConfigurationRuleReplay.merge(baseline: asSlots(OrderedJSON.parse(baseline)),
                local: asSlots(OrderedJSON.parse(previous.documentJSON)), incoming: incoming)
            for i in candidate.rules.indices where candidate.rules[i].sourceID == replacement.record.id {
                candidate.rules[i].namedNodes = nil
                candidate.rules[i].namedNodesSourceID = nil
            }
            var record = replacement.record
            if case .array(let rules) = merged.topLevelValue("rules") { record.ruleCount = rules.count }
            record.groupCount = try ConfigurationRuleGroupSnapshot.read(merged).count
            var working = merged
            if record.suppliesNodes, case .object(let entries) = try OrderedJSON.parse(replacement.documentJSON),
               case .object(let routing) = merged {
                working = .object(entries.filter { !ConfigurationRuleDocument.keys.contains($0.key) } + routing)
            }
            replacement = .init(record: record, original: replacement.original, documentJSON: working.serialized(),
                resourceFiles: replacement.resourceFiles, ruleBaselineJSON: merged == incoming ? nil : incoming.serialized())
        }
         
        let resolved = try resolveInput(replacement)
        guard resolved.id == replacement.record.id else { throw ConfigurationLibraryError.invalidIdentifier.noted() }
        candidate.sources[index] = replacement.record
         
         
         
         
        if let incomingDocument {
            let rulesDocument = try OrderedJSON.parse(replacement.documentJSON)
             
             
            switch Result(catching: { try ConfigurationSchemePage.imported(from: incomingDocument, rules: rulesDocument) }) {
            case .success(let incomingPage):
                for i in followers {
                    candidate.rules[i].pageJSON = incomingPage?.serialized()
                    candidate.rules[i].pageFollowsSource = true
                }
            case .failure(let refusal):
                pageRefusals[replacement.record.id] = refusal.localizedDescription
            }
        }
        var replacements = [replacement]
         
        var issues = (candidate.updateIssues ?? []).filter { issue in
            issue.sourceID != replacement.record.id || onlyRecipes.map { !$0.contains(issue.itemID) } == true
        }
        var blockedChains = Set<String>()
        for chainIndex in candidate.sources.indices {
            let record = candidate.sources[chainIndex]
            guard record.isRetainedSnapshot != true, let chain = record.nodeChain, chain.hops.contains(where: { $0.source.id == replacement.record.id }) else { continue }
            do {
            let refreshed = try ConfigurationNodeChain.materialize(record: record, chain: chain.updating(replacement.record)) { reference in
                if reference == ConfigurationSourceVersion(replacement.record) { return replacement }
                return try payload(reference)
            }
            _ = try resolveInput(refreshed)
            replacements.append(refreshed); candidate.sources[chainIndex] = refreshed.record
            } catch let issue as ConfigurationNodeChainError {
                guard !updatingPinnedConsumers else { throw issue }
                blockedChains.insert(record.id)
                issues.append(.init(sourceID: replacement.record.id, itemID: record.id, message: issue.localizedDescription))
            }
        }
        let byID = Dictionary(uniqueKeysWithValues: replacements.map { ($0.record.id, $0) })
        var compositions: [String: ConfigurationComposition] = [:]
        for index in candidate.recipes.indices {
            var recipe = candidate.recipes[index]
            if let onlyRecipes, !onlyRecipes.contains(recipe.id) { continue }
             
             
             
            guard (recipe.followsUpdates || updatingPinnedConsumers || includingFrozenConsumers),
                  recipe.sources.contains(where: { byID[$0.id] != nil }) || byID[recipe.ruleSource.id] != nil else { continue }
            if recipe.sources.contains(where: { blockedChains.contains($0.id) }) { continue }
            let unchanged = recipe
            do {
            if recipe.preservesOriginal != true { try freezeSettings(in: &recipe, resolveInput: resolveInput) }
            recipe.sources = recipe.sources.map { reference in byID[reference.id].map { .init($0.record) } ?? reference }
             
             
             
            if recipe.preservesOriginal == true || candidate.rules.first(where: { $0.id == recipe.ruleSchemeID })?.isRetainedSnapshot != true,
               let source = byID[recipe.ruleSource.id] { recipe.ruleSource = .init(source.record) }
            func input(_ reference: ConfigurationSourceVersion) throws -> ConfigurationInput {
                let source = try replacements.first(where: { ConfigurationSourceVersion($0.record) == reference }) ?? payload(reference)
                let input = try resolveInput(source)
                guard input.id == reference.id else { throw ConfigurationLibraryError.invalidIdentifier.noted() }
                return input
            }
            if recipe.preservesOriginal == true {
                let original = try input(recipe.ruleSource)
                compositions[recipe.id] = .init(document: try overlayingAdvancedSettings(of: recipe, onto: original.document),
                                                sourceIDs: [original.id])
                recipe.droppedRules = nil
            } else {
            compositions[recipe.id] = try composeInputs(recipe.sources.map(input),
                ruleInput: input(recipe.ruleSource), schemeID: recipe.ruleSchemeID, scheme: candidate.rules.first { $0.id == recipe.ruleSchemeID }, page: try ConfigurationSchemePage.effective(of: recipe, scheme: candidate.rules.first { $0.id == recipe.ruleSchemeID }), nodeScopes: recipe.nodeScopes, settingsProviders: try settingsProviders(recipe.settingsRuleDependencies, resolveInput: resolveInput), ruleSchemes: candidate.rules)
            recipe.droppedRules = compositions[recipe.id].flatMap { $0.droppedRules.isEmpty ? nil : $0.droppedRules }
            }
            candidate.recipes[index] = recipe
            } catch let issue as ConfigurationCompositionError {
                 
                 
                 
                 
                 
                guard !updatingPinnedConsumers, issue.leavesTheConfigurationAsItWas else { throw issue }
                candidate.recipes[index] = unchanged
                issues.append(.init(sourceID: replacement.record.id, itemID: recipe.id, message: issue.localizedDescription))
            }
        }
        candidate.updateIssues = issues.isEmpty ? nil : issues
        return .init(candidate: candidate, payloads: replacements, compositions: compositions, pageRefusals: pageRefusals)
    }

     
     
     
     
     
     
     
     
    public func prepareImportedPageBackfill(sourceID: String, expectedGeneration: UInt64,
        resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput = {
            .init(id: $0.record.id, document: try OrderedJSON.parse($0.documentJSON))
        }) throws -> PreparedConfigurationSourceUpdate? {
        var candidate = try snapshot()
        guard candidate.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        guard let record = candidate.sources.first(where: { $0.id == sourceID }), record.isRetainedSnapshot != true else {
            return nil
        }
        let owed = candidate.rules.indices.filter {
            let scheme = candidate.rules[$0]
            return scheme.sourceID == sourceID && scheme.kind == .imported && scheme.isRetainedSnapshot != true
                && scheme.rulesFromSchemeID == nil && scheme.collectionKey == nil
                && scheme.pageJSON == nil && scheme.pageFollowsSource != true
        }
        guard !owed.isEmpty else { return nil }
        guard candidate.pendingPublications?.isEmpty ?? true else { throw ConfigurationLibraryError.busy }
        do {
            let document = try OrderedJSON.parse(payload(.init(record)).documentJSON)
            let page = try ConfigurationSchemePage.imported(from: document)
            for i in owed {
                candidate.rules[i].pageJSON = page?.serialized()
                candidate.rules[i].pageFollowsSource = true
            }
            var compositions: [String: ConfigurationComposition] = [:]
             
            guard page != nil else { return .init(candidate: candidate, payloads: [], compositions: [:]) }
            let schemeIDs = Set(owed.map { candidate.rules[$0].id })
            for index in candidate.recipes.indices where candidate.recipes[index].preservesOriginal != true
                && candidate.recipes[index].followsUpdates && schemeIDs.contains(candidate.recipes[index].ruleSchemeID) {
                var recipe = candidate.recipes[index]
                try freezeSettings(in: &recipe, resolveInput: resolveInput)
                func input(_ reference: ConfigurationSourceVersion) throws -> ConfigurationInput {
                    let resolved = try resolveInput(payload(reference))
                    guard resolved.id == reference.id else { throw ConfigurationLibraryError.invalidIdentifier.noted() }
                    return resolved
                }
                let scheme = candidate.rules.first { $0.id == recipe.ruleSchemeID }
                let composition = try composeInputs(recipe.sources.map(input), ruleInput: input(recipe.ruleSource),
                    schemeID: recipe.ruleSchemeID, scheme: scheme,
                    page: try ConfigurationSchemePage.effective(of: recipe, scheme: scheme),
                    nodeScopes: recipe.nodeScopes,
                    settingsProviders: try settingsProviders(recipe.settingsRuleDependencies, resolveInput: resolveInput),
                    ruleSchemes: candidate.rules)
                recipe.droppedRules = composition.droppedRules.isEmpty ? nil : composition.droppedRules
                compositions[recipe.id] = composition
                candidate.recipes[index] = recipe
            }
            return .init(candidate: candidate, payloads: [], compositions: compositions)
        } catch let error as ConfigurationLibraryError {
            throw error
        } catch {
            throw ConfigurationSchemePageRefusal(sourceID: sourceID, reason: error.localizedDescription)
        }
    }

     
     
     
     
    public static let currentCompositionRevision = 1

     
     
     
     
     
     
     
     
     
     
     
     
     
    public func prepareRecompositionForCurrentRevision(expectedGeneration: UInt64,
        resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput = {
            .init(id: $0.record.id, document: try OrderedJSON.parse($0.documentJSON))
        }) throws -> PreparedConfigurationSourceUpdate? {
        var candidate = try snapshot()
        guard candidate.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        guard candidate.compositionRevision ?? 0 < Self.currentCompositionRevision else { return nil }
         
         
         
         
         
         
        guard candidate.recipes.contains(where: { $0.preservesOriginal != true }) else { return nil }
        guard candidate.pendingPublications?.isEmpty ?? true else { throw ConfigurationLibraryError.busy }
        var compositions: [String: ConfigurationComposition] = [:]
        var issues = (candidate.updateIssues ?? []).filter { $0.sourceID != Self.recompositionIssueSource }
        for index in candidate.recipes.indices where candidate.recipes[index].preservesOriginal != true {
            var recipe = candidate.recipes[index]
            do {
                try freezeSettings(in: &recipe, resolveInput: resolveInput)
                func input(_ reference: ConfigurationSourceVersion) throws -> ConfigurationInput {
                    let resolved = try resolveInput(payload(reference))
                    guard resolved.id == reference.id else { throw ConfigurationLibraryError.invalidIdentifier.noted() }
                    return resolved
                }
                let composition = try composeInputs(recipe.sources.map(input), ruleInput: input(recipe.ruleSource),
                    schemeID: recipe.ruleSchemeID, scheme: candidate.rules.first { $0.id == recipe.ruleSchemeID },
                    page: try ConfigurationSchemePage.effective(of: recipe, scheme: candidate.rules.first { $0.id == recipe.ruleSchemeID }),
                    nodeScopes: recipe.nodeScopes,
                    settingsProviders: try settingsProviders(recipe.settingsRuleDependencies, resolveInput: resolveInput), ruleSchemes: candidate.rules)
                recipe.droppedRules = composition.droppedRules.isEmpty ? nil : composition.droppedRules
                compositions[recipe.id] = composition
                candidate.recipes[index] = recipe
            } catch {
                issues.append(.init(sourceID: Self.recompositionIssueSource, itemID: recipe.id, message: error.localizedDescription))
            }
        }
        candidate.updateIssues = issues.isEmpty ? nil : issues
        candidate.compositionRevision = Self.currentCompositionRevision
        return .init(candidate: candidate, payloads: [], compositions: compositions)
    }

     
     
    public static let recompositionIssueSource = "clash-composition-revision"

     
     
     
     
     
     
     
    public func localRuleSetsToLink() throws -> [ConfigurationLocalRuleSet] {
        let current = try snapshot()
        let unlinked = (current.localRuleSets ?? []).filter { $0.link == nil && Self.isLink($0.input) }
        guard !unlinked.isEmpty else { return [] }
        var wanted = Set<String>()
        for scheme in current.rules where (scheme.kind == .custom || scheme.kind == .imported)
            && scheme.collectionKey == nil && scheme.rulesFromSchemeID == nil {
            guard let document = try? ConfigurationRuleDraft(scheme: scheme, payload: ruleSchemePayload(scheme.id)).currentDocument(),
                  ConfigurationRuleSetLink.writtenInBytes(document) >= ConfigurationRuleSetLink.writtenInLimit else { continue }
            for set in unlinked where Self.writesIn(set, document) { wanted.insert(set.id) }
        }
        return unlinked.filter { wanted.contains($0.id) }
    }

     
     
     
     
     
     
     
     
     
     
     
    public func prepareLinkingWrittenSets(_ read: [ConfigurationLocalRuleSet], expectedGeneration: UInt64,
        resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput = {
            .init(id: $0.record.id, document: try OrderedJSON.parse($0.documentJSON))
        }) throws -> PreparedConfigurationSourceUpdate? {
        var candidate = try snapshot()
        guard candidate.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        guard candidate.pendingPublications?.isEmpty ?? true else { throw ConfigurationLibraryError.busy }
        var sets = candidate.localRuleSets ?? []
        var recorded: [ConfigurationLocalRuleSet] = []
        for index in sets.indices where sets[index].link == nil {
            guard let found = read.first(where: { $0.id == sets[index].id }), let link = found.link,
                  found.input == sets[index].input, found.rules == sets[index].rules else { continue }
            sets[index].link = link
            recorded.append(sets[index])
        }
        guard !recorded.isEmpty else { return nil }
        candidate.localRuleSets = sets
        var compositions: [String: ConfigurationComposition] = [:]
        for index in candidate.recipes.indices where candidate.recipes[index].preservesOriginal != true {
            var recipe = candidate.recipes[index]
             
             
            guard let scheme = candidate.rules.first(where: { $0.id == recipe.ruleSchemeID }) else { continue }
             
            let base = (try? ruleBase(of: scheme, in: candidate.rules)) ?? scheme
            guard let document = try? ConfigurationRuleDraft(scheme: base, payload: ruleSchemePayload(base.id)).currentDocument(),
                  ConfigurationRuleSetLink.writtenInBytes(document) >= ConfigurationRuleSetLink.writtenInLimit,
                  recorded.contains(where: { Self.writesIn($0, document) }) else { continue }
            try freezeSettings(in: &recipe, resolveInput: resolveInput)
            func input(_ reference: ConfigurationSourceVersion) throws -> ConfigurationInput {
                let resolved = try resolveInput(payload(reference))
                guard resolved.id == reference.id else { throw ConfigurationLibraryError.invalidIdentifier.noted() }
                return resolved
            }
            let composition = try composeInputs(recipe.sources.map(input), ruleInput: input(recipe.ruleSource),
                schemeID: recipe.ruleSchemeID, scheme: scheme,
                page: try ConfigurationSchemePage.effective(of: recipe, scheme: scheme),
                nodeScopes: recipe.nodeScopes,
                settingsProviders: try settingsProviders(recipe.settingsRuleDependencies, resolveInput: resolveInput),
                ruleSchemes: candidate.rules, localRuleSets: sets)
            recipe.droppedRules = composition.droppedRules.isEmpty ? nil : composition.droppedRules
            compositions[recipe.id] = composition
            candidate.recipes[index] = recipe
        }
        return .init(candidate: candidate, payloads: [], compositions: compositions)
    }

     
    private static func writesIn(_ set: ConfigurationLocalRuleSet, _ document: OrderedJSON) -> Bool {
        guard let provider = document.topLevelValue("rule-providers")?.topLevelValue("local-" + set.id) else { return false }
        return provider.topLevelValue("type") == .string("inline")
            && provider.topLevelValue("payload") == .array(set.rules.map(OrderedJSON.string))
    }

     
    private static func isLink(_ input: String) -> Bool {
        guard let url = URL(string: input.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return ["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.host != nil
    }

     
     
     
     
    public static let currentSchemePageRevision = 2

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    public func prepareSchemePagesForCurrentRevision(expectedGeneration: UInt64,
        extraPage: (ConfigurationRecipe) -> OrderedJSON? = { _ in nil },
        label: (ConfigurationRuleScheme, ConfigurationRecipe) -> String = { "\($0.displayLabel) (\($1.label))" },
        resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput = {
            .init(id: $0.record.id, document: try OrderedJSON.parse($0.documentJSON))
        }) throws -> PreparedConfigurationSourceUpdate? {
        var candidate = try snapshot()
        guard candidate.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        guard candidate.schemePageRevision ?? 0 < Self.currentSchemePageRevision else { return nil }
         
         
         
         
        guard candidate.recipes.contains(where: { $0.preservesOriginal != true }) else {
            guard !candidate.recipes.isEmpty else { return nil }
            candidate.schemePageRevision = Self.currentSchemePageRevision
            return .init(candidate: candidate, payloads: [], compositions: [:])
        }
        guard candidate.pendingPublications?.isEmpty ?? true else { throw ConfigurationLibraryError.busy }
         
         
         
        let original = candidate
        var payloads: [ConfigurationSourcePayload] = []
        var compositions: [String: ConfigurationComposition] = [:]
         
        var copies: [String: [(page: OrderedJSON, schemeID: String)]] = [:]
         
        func input(_ reference: ConfigurationSourceVersion) throws -> ConfigurationInput {
            let source = try payloads.first { ConfigurationSourceVersion($0.record) == reference } ?? payload(reference)
            let resolved = try resolveInput(source)
            guard resolved.id == reference.id else { throw ConfigurationLibraryError.invalidIdentifier.noted() }
            return resolved
        }
        func scheme(of recipe: ConfigurationRecipe) throws -> ConfigurationRuleScheme {
            guard let scheme = original.rules.first(where: { $0.id == recipe.ruleSchemeID })
                    ?? ConfigurationBuiltins.schemes.first(where: { $0.id == recipe.ruleSchemeID }) else {
                throw ConfigurationLibraryError.missingDependency(recipe.ruleSchemeID)
            }
            return scheme
        }
         
         
        var pages: [String: OrderedJSON] = [:]
        var pagesOnScheme: [String: Set<String>] = [:]
        var firstPage: [String: OrderedJSON] = [:]
        for recipe in candidate.recipes where recipe.preservesOriginal != true {
            let scheme = try scheme(of: recipe)
            let running = try ConfigurationSchemePage.effective(of: recipe, scheme: scheme)
            var page = running.settings.removingTopLevel("dns").settingTopLevel("dns", to: running.dns)
            if case .object(let entries)? = extraPage(recipe) {
                for entry in entries { page = page.settingTopLevel(entry.key, to: entry.value) }
            }
            pages[recipe.id] = page
            pagesOnScheme[scheme.id, default: []].insert(page.serialized())
            if firstPage[scheme.id] == nil { firstPage[scheme.id] = page }
        }
         
        for index in candidate.recipes.indices where candidate.recipes[index].preservesOriginal != true {
            var recipe = candidate.recipes[index]
            let scheme = try scheme(of: recipe)
            guard let page = pages[recipe.id] else { continue }
            var target = scheme
            let ownsItsRules = scheme.kind == .custom && scheme.rulesFromSchemeID == nil && scheme.collectionKey == nil
            let unchanged = try ConfigurationSchemePage.of(scheme) ?? ConfigurationSchemePage.builtin
            if page == unchanged {
                 
            } else if ownsItsRules, scheme.pageJSON == nil, firstPage[scheme.id] == page,
                      pagesOnScheme[scheme.id]?.contains(unchanged.serialized()) != true {
                 
                 
                 
                 
                if let i = candidate.rules.firstIndex(where: { $0.id == scheme.id }) {
                    if candidate.rules[i].pageJSON == nil { candidate.rules[i].pageJSON = page.serialized() }
                    target = candidate.rules[i]
                }
            } else if ownsItsRules {
                 
                if let copy = copies[scheme.id]?.first(where: { $0.page == page }),
                   let existing = candidate.rules.first(where: { $0.id == copy.schemeID }) {
                    target = existing
                    recipe.ruleSource = .init(id: existing.sourceID,
                        version: candidate.sources.first { $0.id == existing.sourceID }?.version ?? recipe.ruleSource.version)
                } else {
                    let name = label(scheme, recipe)
                    let rulesSource = try Self.copyable(payload(recipe.ruleSource))
                    let rules = ConfigurationRuleDocument.project(try OrderedJSON.parse(rulesSource.documentJSON))
                    let record = ConfigurationSourceRecord(label: name, origin: .file(name + ".yaml"),
                        groupCount: rulesSource.record.groupCount, ruleCount: rulesSource.record.ruleCount, suppliesNodes: false)
                    let copy = ConfigurationSourcePayload(record: record, original: Data(rules.serialized().utf8),
                        documentJSON: rules.serialized(), resourceFiles: rulesSource.resourceFiles)
                    var copied = ConfigurationRuleScheme(label: name, kind: .custom, sourceID: record.id)
                    copied.generatedRuleGroups = scheme.generatedRuleGroups
                    copied.disabledRules = scheme.disabledRules
                    copied.ruleNotes = scheme.ruleNotes
                    copied.namedNodes = ConfigurationRuleDocument.namedNodes(of: try OrderedJSON.parse(rulesSource.documentJSON),
                                                                             recorded: scheme.namedNodes)
                    copied.namedNodesSourceID = copied.namedNodes == nil ? nil : ConfigurationRuleDocument.namedNodesSource(
                        of: try OrderedJSON.parse(rulesSource.documentJSON), sourceID: rulesSource.record.id, recorded: scheme.namedNodesSourceID)
                    copied.pageJSON = page.serialized()
                    candidate.sources.append(record); candidate.rules.append(copied); payloads.append(copy)
                    copies[scheme.id, default: []].append((page, copied.id))
                    target = copied
                    recipe.ruleSource = .init(record)
                }
            } else if let view = candidate.rules.first(where: { own in
                own.rulesFromSchemeID == scheme.id && (try? own.pageJSON.map(ConfigurationSchemePage.parse)) == page
            }) {
                target = view
            } else {
                var view = ConfigurationRuleScheme(label: label(scheme, recipe), kind: .custom, sourceID: scheme.sourceID)
                view.rulesFromSchemeID = scheme.id
                view.pageJSON = page.serialized()
                if !candidate.rules.contains(where: { $0.id == scheme.id }) { candidate.rules.append(scheme) }
                candidate.rules.append(view)
                target = view
            }
            if target.id != scheme.id, recipe.ruleSource.id != target.sourceID {
                throw ConfigurationLibraryError.invalidIdentifier.noted("scheme page target on another source")
            }
            recipe.ruleSchemeID = target.id
            recipe.clearLegacyPage()
             
            let names = ConfigurationSettingsDependencies.names(settings: page.removingTopLevel("dns"), dns: page.topLevelValue("dns"))
            var references = (recipe.settingsRuleDependencies ?? [:]).filter { names.contains($0.key) && $0.value.id == recipe.ruleSource.id }
            for name in names.sorted() where references[name] == nil {
                guard try input(recipe.ruleSource).document.topLevelValue("rule-providers")?.topLevelValue(name) != nil else {
                    throw ConfigurationCompositionError.unresolvedDependency(source: "Scheme page", name: name)
                }
                references[name] = recipe.ruleSource
            }
            recipe.settingsRuleDependencies = references.isEmpty ? nil : references
            let composition = try composeInputs(recipe.sources.map(input), ruleInput: input(recipe.ruleSource),
                schemeID: target.id, scheme: target,
                page: try ConfigurationSchemePage.effective(of: recipe, scheme: target), nodeScopes: recipe.nodeScopes,
                settingsProviders: try settingsProviders(recipe.settingsRuleDependencies, resolveInput: resolveInput),
                ruleSchemes: candidate.rules)
            recipe.droppedRules = composition.droppedRules.isEmpty ? nil : composition.droppedRules
            compositions[recipe.id] = composition
            candidate.recipes[index] = recipe
        }
        candidate.schemePageRevision = Self.currentSchemePageRevision
        return .init(candidate: candidate, payloads: payloads, compositions: compositions)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    public func prepareSchemePageEdit(profileID: String, expectedGeneration: UInt64,
        resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput = {
            .init(id: $0.record.id, document: try OrderedJSON.parse($0.documentJSON))
        },
        change: (inout OrderedJSON) throws -> Void) throws -> PreparedConfigurationSourceUpdate {
        var candidate = try snapshot()
        guard candidate.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        guard candidate.schemePageRevision ?? 0 >= Self.currentSchemePageRevision else { throw ConfigurationLibraryError.busy }
        guard let index = candidate.recipes.firstIndex(where: { $0.id == profileID }) else {
            throw ConfigurationLibraryError.missingDependency(profileID)
        }
        var recipe = candidate.recipes[index]
        guard recipe.preservesOriginal != true else { throw ConfigurationLibraryError.readOnlyRuleScheme }
        guard let scheme = candidate.rules.first(where: { $0.id == recipe.ruleSchemeID })
                ?? ConfigurationBuiltins.schemes.first(where: { $0.id == recipe.ruleSchemeID }) else {
            throw ConfigurationLibraryError.missingDependency(recipe.ruleSchemeID)
        }
         
        let running = try ConfigurationSchemePage.effective(of: recipe, scheme: scheme)
        let before = running.settings.removingTopLevel("dns").settingTopLevel("dns", to: running.dns)
        var after = before
        try change(&after)
        after = try ConfigurationSchemePage.parse(after.serialized())
        let changed = Self.changedTopLevelKeys(from: before, to: after)
        guard !changed.isEmpty else { return .init(candidate: candidate, payloads: [], compositions: [:]) }

        let target: ConfigurationRuleScheme
        let recomposed: [String]
        if scheme.ownsItsPage {
            var page = try ConfigurationSchemePage.of(scheme) ?? ConfigurationSchemePage.builtin
            for key in changed.sorted() {
                page = after.topLevelValue(key).map { page.settingTopLevel(key, to: $0) } ?? page.removingTopLevel(key)
            }
            guard let schemeIndex = candidate.rules.firstIndex(where: { $0.id == scheme.id }) else {
                throw ConfigurationLibraryError.missingDependency(scheme.id)
            }
            candidate.rules[schemeIndex].pageJSON = page.serialized()
            target = candidate.rules[schemeIndex]
             
            if case .object(let entries) = try ConfigurationSettingsDocument.parse(recipe.settingsJSON ?? "{}") {
                recipe.settingsJSON = OrderedJSON.object(entries.filter { !changed.contains($0.key) }).serialized()
            }
            if changed.contains("dns") { recipe.dnsMode = nil; recipe.customDNSJSON = nil; recipe.nodeNameservers = nil }
            recomposed = candidate.recipes.filter { $0.ruleSchemeID == scheme.id && $0.preservesOriginal != true }.map(\.id)
        } else {
             
             
            let baseID = scheme.rulesFromSchemeID ?? scheme.id
            let base = candidate.rules.first { $0.id == baseID } ?? ConfigurationBuiltins.schemes.first { $0.id == baseID } ?? scheme
             
             
            var view = ConfigurationRuleScheme(label: base.label, kind: .custom, sourceID: scheme.sourceID)
            if base.baseSchemeID.map(ConfigurationBuiltins.isNative) == true { view.ownViewOfCustomScheme = true }
            view.rulesFromSchemeID = baseID
            view.privateToConfigurationID = recipe.id
            view.pageJSON = after.serialized()
            if !candidate.rules.contains(where: { $0.id == baseID }),
               let builtin = ConfigurationBuiltins.schemes.first(where: { $0.id == baseID }) {
                candidate.rules.append(builtin)
            }
            guard recipe.ruleSource.id == view.sourceID else {
                throw ConfigurationLibraryError.invalidIdentifier.noted("scheme page view on another source")
            }
             
             
             
            let inUse = candidate.schemeIDsInUse
            candidate.rules.removeAll { old in
                old.privateToConfigurationID == recipe.id && old.plainViewBaseID == baseID && !inUse.contains(old.id)
            }
            candidate.rules.append(view)
            target = view
            recipe.ruleSchemeID = view.id
            recipe.clearLegacyPage()
            recomposed = [recipe.id]
        }
        candidate.recipes[index] = recipe

        func input(_ reference: ConfigurationSourceVersion) throws -> ConfigurationInput {
            let resolved = try resolveInput(payload(reference))
            guard resolved.id == reference.id else { throw ConfigurationLibraryError.invalidIdentifier.noted() }
            return resolved
        }
        var compositions: [String: ConfigurationComposition] = [:]
        for id in recomposed {
            guard let position = candidate.recipes.firstIndex(where: { $0.id == id }) else { continue }
            var consumer = candidate.recipes[position]
            let page = try ConfigurationSchemePage.effective(of: consumer, scheme: target)
             
            let names = ConfigurationSettingsDependencies.names(settings: page.settings, dns: page.dns)
            var references = (consumer.settingsRuleDependencies ?? [:]).filter { names.contains($0.key) }
            for name in names.sorted() where references[name] == nil {
                guard try input(consumer.ruleSource).document.topLevelValue("rule-providers")?.topLevelValue(name) != nil else {
                    throw ConfigurationCompositionError.unresolvedDependency(source: "Scheme page", name: name)
                }
                references[name] = consumer.ruleSource
            }
            consumer.settingsRuleDependencies = references.isEmpty ? nil : references
            let composition = try composeInputs(consumer.sources.map(input), ruleInput: input(consumer.ruleSource),
                schemeID: target.id, scheme: target, page: page, nodeScopes: consumer.nodeScopes,
                settingsProviders: try settingsProviders(consumer.settingsRuleDependencies, resolveInput: resolveInput),
                ruleSchemes: candidate.rules)
            consumer.droppedRules = composition.droppedRules.isEmpty ? nil : composition.droppedRules
            compositions[consumer.id] = composition
            candidate.recipes[position] = consumer
        }
        return .init(candidate: candidate, payloads: [], compositions: compositions)
    }

     
     
     
     
     
     
    public func prepareSchemeSwitch(profileID: String, to schemeID: String, expectedGeneration: UInt64,
        resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput = {
            .init(id: $0.record.id, document: try OrderedJSON.parse($0.documentJSON))
        }) throws -> PreparedConfigurationCreation {
        let current = try snapshot()
        guard current.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        guard current.pendingPublications?.isEmpty ?? true else { throw ConfigurationLibraryError.busy }
        return try switchingScheme(in: current, profileID: profileID, to: schemeID, takingOwnView: true, resolveInput: resolveInput)
    }

     
     
     
     
     
     
    internal func switchingScheme(in starting: ConfigurationLibrarySnapshot, profileID: String, to schemeID: String,
        takingOwnView: Bool = false,
        resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput) throws -> PreparedConfigurationCreation {
        var candidate = starting
        guard let index = candidate.recipes.firstIndex(where: { $0.id == profileID }) else {
            throw ConfigurationLibraryError.missingDependency(profileID)
        }
        var recipe = candidate.recipes[index]
        guard recipe.preservesOriginal != true else { throw ConfigurationLibraryError.readOnlyRuleScheme }
         
         
        guard let target = (takingOwnView ? candidate.ownView(of: schemeID, for: profileID) : nil)
                ?? candidate.rules.first(where: { $0.id == schemeID })
                ?? ConfigurationBuiltins.schemes.first(where: { $0.id == schemeID }) else {
            throw ConfigurationLibraryError.missingDependency(schemeID)
        }
        guard target.isRetainedSnapshot != true else { throw ConfigurationLibraryError.retainedSnapshot }
         
         
         
        var payloads: [ConfigurationSourcePayload] = []
        let ruleRecord: ConfigurationSourceRecord
        let rulesID = target.rulesFromSchemeID ?? target.id
        if let bundled = try ConfigurationBuiltins.source(for: rulesID) {
            if !candidate.sources.contains(where: { $0.id == bundled.record.id && $0.version == bundled.record.version }) {
                candidate.sources.removeAll { $0.id == bundled.record.id }
                candidate.sources.append(bundled.record)
                payloads.append(bundled)
            }
            ruleRecord = bundled.record
            if !candidate.rules.contains(where: { $0.id == rulesID }),
               let builtin = ConfigurationBuiltins.schemes.first(where: { $0.id == rulesID }) { candidate.rules.append(builtin) }
            if !candidate.rules.contains(where: { $0.id == target.id }) { candidate.rules.append(target) }
        } else {
            guard let record = candidate.sources.first(where: { $0.id == target.sourceID }) else {
                throw ConfigurationLibraryError.missingDependency(target.sourceID)
            }
            ruleRecord = record
        }
        func input(_ reference: ConfigurationSourceVersion) throws -> ConfigurationInput {
            let source = try payloads.first { ConfigurationSourceVersion($0.record) == reference } ?? payload(reference)
            let resolved = try resolveInput(source)
            guard resolved.id == reference.id else { throw ConfigurationLibraryError.invalidIdentifier.noted() }
            return resolved
        }
        recipe.ruleSchemeID = target.id
        recipe.ruleSource = .init(ruleRecord)
        recipe.composedRuleSchemeID = nil
        recipe.clearLegacyPage()
        let page = try ConfigurationSchemePage.effective(of: recipe, scheme: target)
         
        let names = ConfigurationSettingsDependencies.names(settings: page.settings, dns: page.dns)
        var references = (recipe.settingsRuleDependencies ?? [:]).filter { names.contains($0.key) }
        for name in names.sorted() where references[name] == nil {
            guard try input(recipe.ruleSource).document.topLevelValue("rule-providers")?.topLevelValue(name) != nil else {
                throw ConfigurationCompositionError.unresolvedDependency(source: "Scheme page", name: name)
            }
            references[name] = recipe.ruleSource
        }
        recipe.settingsRuleDependencies = references.isEmpty ? nil : references
        let composition = try composeInputs(recipe.sources.map(input), ruleInput: input(recipe.ruleSource),
            schemeID: target.id, scheme: target, page: page, nodeScopes: recipe.nodeScopes,
            settingsProviders: try settingsProviders(recipe.settingsRuleDependencies, resolveInput: resolveInput),
            ruleSchemes: candidate.rules)
        recipe.droppedRules = composition.droppedRules.isEmpty ? nil : composition.droppedRules
        candidate.recipes[index] = recipe
        return .init(recipe: recipe, composition: composition, candidate: candidate, payloads: payloads)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    public func prepareSaveAsScheme(profileID: String, label: String, expectedGeneration: UInt64,
        extraPage: OrderedJSON? = nil,
        resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput = {
            .init(id: $0.record.id, document: try OrderedJSON.parse($0.documentJSON))
        }) throws -> PreparedConfigurationSourceUpdate {
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ConfigurationLibraryError.emptyName }
        var candidate = try snapshot()
        guard candidate.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        guard candidate.pendingPublications?.isEmpty ?? true else { throw ConfigurationLibraryError.busy }
        guard let index = candidate.recipes.firstIndex(where: { $0.id == profileID }) else {
            throw ConfigurationLibraryError.missingDependency(profileID)
        }
        var recipe = candidate.recipes[index]
        let original = recipe.preservesOriginal == true
        let rulesSource: ConfigurationSourcePayload
        var page: OrderedJSON
        var template: ConfigurationRuleScheme?
        if original {
            rulesSource = try Self.copyable(payload(recipe.ruleSource))
             
             
            page = ConfigurationSettingsDocument.project(
                try overlayingAdvancedSettings(of: recipe, onto: OrderedJSON.parse(rulesSource.documentJSON)))
        } else {
            guard let scheme = candidate.rules.first(where: { $0.id == recipe.ruleSchemeID })
                    ?? ConfigurationBuiltins.schemes.first(where: { $0.id == recipe.ruleSchemeID }) else {
                throw ConfigurationLibraryError.missingDependency(recipe.ruleSchemeID)
            }
            rulesSource = try Self.copyable(ruleSchemePayload(recipe.ruleSchemeID))
            let running = try ConfigurationSchemePage.effective(of: recipe, scheme: scheme)
            page = running.settings.removingTopLevel("dns").settingTopLevel("dns", to: running.dns)
            template = try ruleBase(of: scheme, in: candidate.rules) ?? scheme
             
             
             
            if recipe.sources.isEmpty, let base = template?.id, ConfigurationBuiltins.isNative(base) {
                throw ConfigurationLibraryError.missingNodeSource
            }
        }
         
         
         
        if case .object(let entries)? = extraPage {
            for entry in entries {
                page = page.settingTopLevel(entry.key, to: page.topLevelValue(entry.key)
                    .map { $0.mergingAsTheCoreMerges(entry.value) } ?? entry.value)
            }
        }
        page = try ConfigurationSchemePage.parse(page.serialized())
        let rules = ConfigurationRuleDocument.project(try OrderedJSON.parse(rulesSource.documentJSON))
        func count(_ key: String) -> Int {
            if case .array(let items)? = rules.topLevelValue(key) { return items.count }
            return 0
        }
        let record = ConfigurationSourceRecord(label: name, origin: .file(name + ".yaml"),
            groupCount: count("proxy-groups"), ruleCount: count("rules"), suppliesNodes: false)
        let copy = ConfigurationSourcePayload(record: record, original: Data(rules.serialized().utf8),
            documentJSON: rules.serialized(), resourceFiles: rulesSource.resourceFiles)
        var saved = ConfigurationRuleScheme(label: name, kind: .custom, sourceID: record.id)
         
         
         
        saved.generatedRuleGroups = template?.generatedRuleGroups
        saved.disabledRules = template?.disabledRules
        saved.ruleNotes = template?.ruleNotes
        saved.namedNodes = ConfigurationRuleDocument.namedNodes(of: try OrderedJSON.parse(rulesSource.documentJSON),
                                                                recorded: template?.namedNodes)
        saved.namedNodesSourceID = saved.namedNodes == nil ? nil : ConfigurationRuleDocument.namedNodesSource(
            of: try OrderedJSON.parse(rulesSource.documentJSON), sourceID: rulesSource.record.id, recorded: template?.namedNodesSourceID)
        saved.pageJSON = page.serialized()
        candidate.sources.append(record)
        candidate.rules.append(saved)
        var compositions: [String: ConfigurationComposition] = [:]
        if !original {
            let previousRules = recipe.ruleSource
            recipe.ruleSchemeID = saved.id
            recipe.ruleSource = .init(record)
            recipe.clearLegacyPage()
             
             
            let effective = try ConfigurationSchemePage.effective(of: recipe, scheme: saved)
            let names = ConfigurationSettingsDependencies.names(settings: effective.settings, dns: effective.dns)
            var references = (recipe.settingsRuleDependencies ?? [:]).filter { names.contains($0.key) }
            for name in names.sorted() where references[name] == nil { references[name] = previousRules }
            recipe.settingsRuleDependencies = references.isEmpty ? nil : references
            let composition = try composeInputs(recipe.sources.map { try resolveInput(payload($0)) },
                ruleInput: resolveInput(copy), schemeID: saved.id, scheme: saved, page: effective,
                nodeScopes: recipe.nodeScopes,
                settingsProviders: try settingsProviders(recipe.settingsRuleDependencies, resolveInput: resolveInput),
                ruleSchemes: candidate.rules)
            recipe.droppedRules = composition.droppedRules.isEmpty ? nil : composition.droppedRules
            compositions[recipe.id] = composition
            candidate.recipes[index] = recipe
        }
        return .init(candidate: candidate, payloads: [copy], compositions: compositions)
    }

     
     
     
     
    public func outline(ofRecipe id: String, in snapshot: ConfigurationLibrarySnapshot,
                        customRules: Int = 0) throws -> [ConfigurationOutlineRow] {
        guard let recipe = snapshot.recipes.first(where: { $0.id == id }), recipe.preservesOriginal != true else {
            throw ConfigurationLibraryError.missingDependency(id)
        }
        let scheme = snapshot.rules.first { $0.id == recipe.ruleSchemeID }
            ?? ConfigurationBuiltins.schemes.first { $0.id == recipe.ruleSchemeID }
        let running = try ConfigurationSchemePage.effective(of: recipe, scheme: scheme)
        let page = running.settings.removingTopLevel("dns").settingTopLevel("dns", to: running.dns)
        let rules = try OrderedJSON.parse(ruleSchemePayload(recipe.ruleSchemeID).documentJSON)
        return ConfigurationOutline.rows(for: ConfigurationOutline.composedDocument(page: page, rules: rules),
                                         form: .composed, customRules: customRules)
    }

     
    public func prepareSchemePageEdit(profileID: String, expectedGeneration: UInt64, edits: [ConfigurationPageEdit],
        resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput = {
            .init(id: $0.record.id, document: try OrderedJSON.parse($0.documentJSON))
        }) throws -> PreparedConfigurationSourceUpdate {
        try prepareSchemePageEdit(profileID: profileID, expectedGeneration: expectedGeneration, resolveInput: resolveInput) { page in
            for edit in edits { page = try page.applying(edit) }
        }
    }

     
    static func changedTopLevelKeys(from before: OrderedJSON, to after: OrderedJSON) -> Set<String> {
        guard case .object(let old) = before, case .object(let new) = after else { return [] }
        return Set(old.map(\.key) + new.map(\.key)).filter { before.topLevelValue($0) != after.topLevelValue($0) }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    public func prepareSourceRemoval(_ id: String, expectedGeneration: UInt64,
                                     resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput = {
                                         .init(id: $0.record.id, document: try OrderedJSON.parse($0.documentJSON))
                                     }) throws -> PreparedConfigurationSourceUpdate {
        var candidate = try snapshot()
        guard candidate.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        guard candidate.pendingPublications?.isEmpty ?? true else { throw ConfigurationLibraryError.busy }
        guard let index = candidate.sources.firstIndex(where: { $0.id == id && $0.isRetainedSnapshot != true }) else {
            throw ConfigurationLibraryError.missingDependency(id)
        }
        if case .bundled = candidate.sources[index].origin { throw ConfigurationLibraryError.readOnlySource }
        var compositions: [String: ConfigurationComposition] = [:]
        for position in candidate.recipes.indices {
            var recipe = candidate.recipes[position]
            guard recipe.preservesOriginal != true, recipe.sources.contains(where: { $0.id == id }) else { continue }
            recipe.sources.removeAll { $0.id == id }
            recipe.nodeScopes?[id] = nil
            if recipe.nodeScopes?.isEmpty == true { recipe.nodeScopes = nil }
            guard let composition = try? composition(of: recipe, in: candidate, resolveInput: resolveInput) else { continue }
            recipe.droppedRules = composition.droppedRules.isEmpty ? nil : composition.droppedRules
            candidate.recipes[position] = recipe
            compositions[recipe.id] = composition
        }
        let retained = candidate.recipes.contains { $0.dependencies.contains { $0.id == id } }
            || candidate.sources.contains { $0.id != id && $0.nodeChain?.hops.contains { $0.source.id == id } == true }
        if retained {
            candidate.sources[index].isRetainedSnapshot = true
            candidate.sources[index].updateIntervalHours = 0
            for index in candidate.rules.indices where candidate.rules[index].sourceID == id {
                candidate.rules[index].isRetainedSnapshot = true
            }
        } else {
            candidate.sources.removeAll { $0.id == id }
            candidate.rules.removeAll { $0.sourceID == id }
        }
        candidate.updateIssues?.removeAll { $0.sourceID == id || $0.itemID == id }
        return .init(candidate: candidate, payloads: [], compositions: compositions)
    }

    public func createRuleScheme(label: String, templateID: String?, expectedGeneration: UInt64) throws -> ConfigurationLibrarySnapshot {
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ConfigurationLibraryError.emptyName }
        if let templateID { return try copyRuleScheme(templateID, label: name, expectedGeneration: expectedGeneration) }
        let group = OrderedJSON.object([("name", .string("PROXY")), ("type", .string("select")), ("include-all", .scalar("true"))])
        let document = OrderedJSON.object([("proxy-groups", .array([group])), ("rules", .array([.string("MATCH,PROXY")]))])
        let record = ConfigurationSourceRecord(label: name, origin: .file(name + ".yaml"),
            groupCount: 1, ruleCount: 1, suppliesNodes: false)
        let source = ConfigurationSourcePayload(record: record, original: Data(document.serialized().utf8), documentJSON: document.serialized())
        return try registerRuleScheme(source, kind: .custom, expectedGeneration: expectedGeneration)
    }

     
     
     
    public func addRuleScheme(_ source: ConfigurationSourcePayload, expectedGeneration: UInt64,
                              pageRefused: ((String) -> Void)? = nil) throws -> ConfigurationLibrarySnapshot {
        try registerRuleScheme(source, kind: .imported, expectedGeneration: expectedGeneration, pageRefused: pageRefused)
    }

     
     
     
     
     
     
     
    public func renameRuleScheme(_ id: String, label: String, expectedGeneration: UInt64) throws -> ConfigurationLibrarySnapshot {
        var candidate = try snapshot()
        guard candidate.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ConfigurationLibraryError.emptyName }
        guard let index = candidate.rules.firstIndex(where: { $0.id == id }) else {
            throw ConfigurationLibraryError.missingDependency(id)
        }
        let scheme = candidate.rules[index]
        guard scheme.kind == .custom || scheme.kind == .imported else { throw ConfigurationLibraryError.readOnlyRuleScheme }
        guard scheme.isRetainedSnapshot != true else { throw ConfigurationLibraryError.retainedSnapshot }
         
         
        guard scheme.ownViewBaseID == nil else { throw ConfigurationLibraryError.readOnlyRuleScheme }
        candidate.rules[index].label = name
        candidate.namingOwnViews(of: id)
        if scheme.rulesFromSchemeID == nil, scheme.collectionKey == nil,
           let source = candidate.sources.firstIndex(where: { $0.id == scheme.sourceID }),
           candidate.sources[source].label == scheme.label, !candidate.sources[source].suppliesNodes {
            candidate.sources[source].label = name
        }
        return try commit(candidate, payloads: [], expectedGeneration: expectedGeneration)
    }

    private func registerRuleScheme(_ source: ConfigurationSourcePayload, kind: ConfigurationRuleScheme.Kind,
                                    expectedGeneration: UInt64, generatedRuleGroups: [String: String]? = nil,
                                    disabledRules: [String]? = nil, ruleNotes: [String: String]? = nil,
                                    pageJSON: String? = nil, namedNodes: [String]? = nil, namedNodesSourceID: String? = nil,
                                    pageRefused: ((String) -> Void)? = nil) throws -> ConfigurationLibrarySnapshot {
        var candidate = try snapshot()
        guard candidate.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        guard !candidate.sources.contains(where: { $0.id == source.record.id }) else { throw ConfigurationLibraryError.invalidIdentifier.noted() }
        let document = try OrderedJSON.parse(source.documentJSON)
        guard case .array(let rules) = document.topLevelValue("rules"), !rules.isEmpty else { throw ConfigurationLibraryError.missingRules }
        var stored = source; stored.record.suppliesNodes = false
        candidate.sources.append(stored.record)
        var scheme = ConfigurationRuleScheme(id: "rules-" + stored.record.id, label: stored.record.label, kind: kind, sourceID: stored.record.id)
        scheme.generatedRuleGroups = generatedRuleGroups
        scheme.disabledRules = disabledRules.flatMap { $0.isEmpty ? nil : $0 }
        scheme.ruleNotes = ruleNotes.flatMap { $0.isEmpty ? nil : $0 }
        scheme.pageJSON = pageJSON
        scheme.namedNodes = namedNodes
        scheme.namedNodesSourceID = namedNodes == nil ? nil : namedNodesSourceID
        var refusal: String?
        if kind == .imported, pageJSON == nil {
             
             
             
             
             
             
             
             
             
             
            do { scheme.pageJSON = try ConfigurationSchemePage.imported(from: document)?.serialized() }
            catch { refusal = error.localizedDescription }
            scheme.pageFollowsSource = true
        }
        candidate.rules.append(scheme)
        let committed = try commit(candidate, payloads: [stored], expectedGeneration: expectedGeneration)
        if let refusal { pageRefused?(refusal) }
        return committed
    }

    public func ruleSchemePayload(_ id: String) throws -> ConfigurationSourcePayload {
        if let bundled = try ConfigurationBuiltins.source(for: id) { return bundled }
        let current = try snapshot()
        guard let scheme = current.rules.first(where: { $0.id == id }),
              let record = current.sources.first(where: { $0.id == scheme.sourceID }) else {
            throw ConfigurationLibraryError.missingDependency(id)
        }
         
        if let baseID = scheme.rulesFromSchemeID { return try ruleSchemePayload(baseID) }
        let original = try payload(.init(record))
        guard scheme.collectionKey != nil else { return original }
        let document = try scheme.projectingCollection(OrderedJSON.parse(original.documentJSON))
        var metadata = original.record; metadata.nodeCount = 0; metadata.providerCount = 0
        metadata.groupCount = 1; metadata.ruleCount = 2; metadata.ruleProviderCount = 1; metadata.suppliesNodes = false
         
         
        metadata.rulesWrittenInOriginal = nil
        return .init(record: metadata, original: original.original, documentJSON: document.serialized(), resourceFiles: original.resourceFiles)
    }

     
     
     
     
    static func copyable(_ source: ConfigurationSourcePayload) throws -> ConfigurationSourcePayload {
        guard source.record.rulesWrittenInOriginal != true else {
            throw ConfigurationCompositionError.rulesCannotLeaveTheOriginal(source: source.record.id)
        }
        return source
    }

     
     
     
    static func ruleSetCount(_ document: OrderedJSON) -> Int? {
        guard case .object(let sets) = document.topLevelValue("rule-providers") else { return nil }
        return sets.count
    }

    public func copyRuleScheme(_ id: String, label: String, expectedGeneration: UInt64) throws -> ConfigurationLibrarySnapshot {
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ConfigurationLibraryError.emptyName }
        let current = try snapshot()
        guard current.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        let original = try Self.copyable(ruleSchemePayload(id))
        var record = ConfigurationSourceRecord(label: name, origin: .file(name + ".yaml"),
            nodeCount: 0, providerCount: 0,
            groupCount: original.record.groupCount, ruleCount: original.record.ruleCount, suppliesNodes: false)
        let rules = ConfigurationRuleDocument.project(try OrderedJSON.parse(original.documentJSON))
        record.ruleProviderCount = Self.ruleSetCount(rules)
        let copied = ConfigurationSourcePayload(record: record, original: Data(rules.serialized().utf8),
            documentJSON: rules.serialized(), resourceFiles: original.resourceFiles)
         
         
         
        let copiedScheme = current.rules.first { $0.id == id } ?? ConfigurationBuiltins.schemes.first { $0.id == id }
        return try registerRuleScheme(copied, kind: .custom, expectedGeneration: expectedGeneration,
            generatedRuleGroups: copiedScheme?.generatedRuleGroups,
            disabledRules: copiedScheme?.disabledRules, ruleNotes: copiedScheme?.ruleNotes,
            pageJSON: copiedScheme?.pageJSON,
            namedNodes: ConfigurationRuleDocument.namedNodes(of: try OrderedJSON.parse(original.documentJSON),
                                                             recorded: copiedScheme?.namedNodes),
            namedNodesSourceID: ConfigurationRuleDocument.namedNodesSource(of: try OrderedJSON.parse(original.documentJSON),
                sourceID: original.record.id, recorded: copiedScheme?.namedNodesSourceID))
    }

     
     
     
     
     
     
    public func copyRuleScheme(_ draft: ConfigurationRuleDraft, label: String, expectedGeneration: UInt64) throws -> ConfigurationLibrarySnapshot {
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ConfigurationLibraryError.emptyName }
        let current = try snapshot()
        guard current.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        let document = try draft.document()
        let original = try Self.copyable(ruleSchemePayload(draft.schemeID))
        var record = ConfigurationSourceRecord(label: name, origin: .file(name + ".yaml"),
            nodeCount: 0, providerCount: 0,
            groupCount: draft.groups.count, ruleCount: draft.rows.count, suppliesNodes: false)
        record.ruleProviderCount = Self.ruleSetCount(document)
        let copied = ConfigurationSourcePayload(record: record, original: Data(document.serialized().utf8),
            documentJSON: document.serialized(), resourceFiles: original.resourceFiles)
         
        let copiedScheme = current.rules.first { $0.id == draft.schemeID }
            ?? ConfigurationBuiltins.schemes.first { $0.id == draft.schemeID }
        return try registerRuleScheme(copied, kind: .custom, expectedGeneration: expectedGeneration,
            generatedRuleGroups: draft.generatedRuleGroups.isEmpty ? nil : draft.generatedRuleGroups,
            disabledRules: draft.disabledRules.isEmpty ? nil : draft.disabledRules.sorted(),
            ruleNotes: draft.notes.isEmpty ? nil : draft.notes,
            pageJSON: copiedScheme?.pageJSON, namedNodes: draft.namedNodes, namedNodesSourceID: draft.namedNodesSourceID)
    }

    public func prepareRuleEditing(_ draft: ConfigurationRuleDraft, expectedGeneration: UInt64, localRuleSets: [ConfigurationLocalRuleSet]? = nil,
                                   resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput = {
                                       .init(id: $0.record.id, document: try OrderedJSON.parse($0.documentJSON))
                                   }) throws -> PreparedConfigurationSourceUpdate {
        var candidate = try snapshot()
        guard candidate.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        guard candidate.pendingPublications?.isEmpty ?? true else { throw ConfigurationLibraryError.busy }
        guard let schemeIndex = candidate.rules.firstIndex(where: { $0.id == draft.schemeID }),
              let sourceIndex = candidate.sources.firstIndex(where: { $0.id == candidate.rules[schemeIndex].sourceID }) else {
            throw ConfigurationLibraryError.missingDependency(draft.schemeID)
        }
        guard candidate.rules[schemeIndex].isRetainedSnapshot != true else { throw ConfigurationLibraryError.retainedSnapshot }
        let kind = candidate.rules[schemeIndex].kind
        guard kind == .custom || kind == .imported else { throw ConfigurationLibraryError.readOnlyRuleScheme }
         
         
         
        guard candidate.rules[schemeIndex].collectionKey == nil,
              candidate.rules[schemeIndex].rulesFromSchemeID == nil else { throw ConfigurationLibraryError.readOnlyRuleScheme }
        var record = candidate.sources[sourceIndex]
        guard ConfigurationSourceVersion(record) == draft.version else { throw ConfigurationLibraryError.staleGeneration }
        let previous = try payload(draft.version)
        guard try OrderedJSON.parse(previous.documentJSON) == draft.originalDocument else { throw ConfigurationLibraryError.staleGeneration }
        let document = try draft.document()
        record.version = UUID().uuidString; record.updatedAt = Date()
        let name = draft.label.trimmingCharacters(in: .whitespacesAndNewlines)
         
        let ownView = candidate.rules[schemeIndex].ownViewBaseID != nil
        if kind == .custom, !ownView { record.label = name }
        record.ruleCount = draft.rows.count
        record.groupCount = draft.groups.count
        record.nodeCount = 0; record.providerCount = 0; record.suppliesNodes = false
        let replacement = ConfigurationSourcePayload(record: record,
            original: kind == .custom ? Data(document.serialized().utf8) : previous.original,
            documentJSON: document.serialized(), resourceFiles: previous.resourceFiles,
            ruleBaselineJSON: kind == .custom ? nil : ConfigurationRuleDocument.project(try OrderedJSON.parse(previous.ruleBaselineJSON ?? previous.documentJSON)).serialized())
        candidate.sources[sourceIndex] = replacement.record
         
         
        if !ownView {
            candidate.rules[schemeIndex].label = name
            candidate.namingOwnViews(of: candidate.rules[schemeIndex].id)
        }
        candidate.rules[schemeIndex].disabledRules = draft.disabledRules.isEmpty ? nil : draft.disabledRules.sorted()
        candidate.rules[schemeIndex].ruleNotes = draft.notes.isEmpty ? nil : draft.notes
         
         
        candidate.rules[schemeIndex].namedNodes = draft.namedNodes
        candidate.rules[schemeIndex].namedNodesSourceID = draft.namedNodesSourceID
        let rules = try resolveInput(replacement)
        guard rules.id == record.id else { throw ConfigurationLibraryError.invalidIdentifier.noted() }
        var compositions: [String: ConfigurationComposition] = [:]
         
        let followers = Set(candidate.rules.filter { $0.rulesFromSchemeID == draft.schemeID }.map(\.id))
        for index in candidate.recipes.indices where candidate.recipes[index].ruleSchemeID == draft.schemeID
            || followers.contains(candidate.recipes[index].ruleSchemeID) {
            var recipe = candidate.recipes[index]
            try adoptComposition(in: &recipe, resolveInput: resolveInput)
            try freezeSettings(in: &recipe, resolveInput: resolveInput)
            recipe.ruleSource = .init(record)
            let inputs = try recipe.sources.map { reference in
                let resolved = try resolveInput(payload(reference))
                guard resolved.id == reference.id else { throw ConfigurationLibraryError.invalidIdentifier.noted() }
                return resolved
            }
            let own = candidate.rules.first { $0.id == recipe.ruleSchemeID }
            compositions[recipe.id] = try composeInputs(inputs, ruleInput: rules, schemeID: recipe.ruleSchemeID, scheme: own,
                page: try ConfigurationSchemePage.effective(of: recipe, scheme: own), nodeScopes: recipe.nodeScopes, settingsProviders: try settingsProviders(recipe.settingsRuleDependencies, resolveInput: resolveInput), ruleSchemes: candidate.rules,
                localRuleSets: localRuleSets)
            recipe.droppedRules = compositions[recipe.id].flatMap { $0.droppedRules.isEmpty ? nil : $0.droppedRules }
            candidate.recipes[index] = recipe
        }
        return .init(candidate: candidate, payloads: [replacement], compositions: compositions)
    }

    public func prepareRuleRemoval(_ id: String, expectedGeneration: UInt64,
                                   resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput = {
                                       .init(id: $0.record.id, document: try OrderedJSON.parse($0.documentJSON))
                                   }) throws -> PreparedConfigurationSourceUpdate {
        var candidate = try snapshot()
        guard candidate.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        guard candidate.pendingPublications?.isEmpty ?? true else { throw ConfigurationLibraryError.busy }
        if ConfigurationBuiltins.isNative(id) { throw ConfigurationLibraryError.readOnlyRuleScheme }
        guard let scheme = candidate.rules.first(where: { $0.id == id }) else { throw ConfigurationLibraryError.missingDependency(id) }
        try Self.removeRuleScheme(scheme, from: &candidate)
         
         
         
         
         
        if let baseID = scheme.baseSchemeID, !ConfigurationBuiltins.isNative(baseID),
           let base = candidate.availableRules.first(where: { $0.id == baseID }) {
            for member in candidate.availableRules where member.baseSchemeID == baseID {
                try Self.removeRuleScheme(member, from: &candidate)
            }
            if !(base.kind == .supplied && candidate.recipes.contains(where: { $0.preservesOriginal == true && $0.ruleSchemeID == baseID })) {
                try Self.removeRuleScheme(base, from: &candidate)
            }
        }
        return .init(candidate: candidate, payloads: [], compositions: [:])
    }

    private static func removeRuleScheme(_ scheme: ConfigurationRuleScheme, from candidate: inout ConfigurationLibrarySnapshot) throws {
        let id = scheme.id
        guard scheme.kind == .imported || scheme.kind == .custom || scheme.kind == .supplied else { throw ConfigurationLibraryError.readOnlyRuleScheme }
        guard scheme.isRetainedSnapshot != true else { throw ConfigurationLibraryError.retainedSnapshot }
         
         
         
         
        if scheme.kind == .supplied, candidate.recipes.contains(where: { $0.preservesOriginal == true && $0.ruleSchemeID == id }) {
            throw ConfigurationLibraryError.referencedBy(scheme.label)
        }
         
         
         
         
        let inUse = candidate.schemeIDsInUse
        candidate.rules.removeAll { view in
            view.plainViewBaseID == id && !inUse.contains(view.id)
        }
         
         
        if candidate.recipes.contains(where: { $0.ruleSchemeID == id }) || candidate.rules.contains(where: { $0.rulesFromSchemeID == id }) {
            if let index = candidate.rules.firstIndex(where: { $0.id == id }) { candidate.rules[index].isRetainedSnapshot = true }
        } else { candidate.rules.removeAll { $0.id == id } }
         
        if scheme.rulesFromSchemeID != nil { return }
         
         
        if let index = candidate.sources.firstIndex(where: { $0.id == scheme.sourceID && !$0.suppliesNodes }),
           !candidate.availableRules.contains(where: { $0.sourceID == scheme.sourceID }) {
            if candidate.recipes.contains(where: { $0.dependencies.contains { $0.id == scheme.sourceID } }) {
                candidate.sources[index].isRetainedSnapshot = true
                candidate.sources[index].updateIntervalHours = 0
            } else { candidate.sources.remove(at: index) }
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private func adoptComposition(in recipe: inout ConfigurationRecipe,
                                  resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput) throws {
        guard recipe.preservesOriginal == true else { return }
         
         
         
         
         
         
        let block = try OrderedJSON.parse(recipe.settingsJSON ?? "{}")
        let delta = try OrderedJSON.parse(recipe.originalSettingsJSON ?? "{}")
        recipe.settingsJSON = Self.settingsExpanded(baseline: block, delta: delta).serialized()
        recipe.originalSettingsJSON = nil
        recipe.preservesOriginal = nil
    }

    private func freezeSettings(in recipe: inout ConfigurationRecipe,
        resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput) throws {
        if recipe.preservesOriginal == true {
             
             
             
             
             
             
             
             
            if recipe.originalSettingsJSON == nil { recipe.originalSettingsJSON = "{}" }
            try captureSettingsDependencies(in: &recipe, settingsJSON: recipe.originalSettingsJSON, resolveInput: resolveInput)
            return
        }
         
         
         
         
        if recipe.settingsJSON == nil { recipe.settingsJSON = "{}" }
        try captureSettingsDependencies(in: &recipe, resolveInput: resolveInput)
    }

     
     
     
    private func captureSettingsDependencies(in recipe: inout ConfigurationRecipe, settingsJSON: String? = nil,
        resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput) throws {
        let page: ConfigurationSchemePage.Effective
        if let settingsJSON {
            page = try ConfigurationSchemePage.effective(schemePage: nil, settingsJSON: settingsJSON, dnsMode: recipe.dnsMode,
                                                         customDNSJSON: recipe.customDNSJSON, nodeNameservers: nil)
        } else {
            page = try ConfigurationSchemePage.effective(of: recipe, scheme: snapshot().rules.first { $0.id == recipe.ruleSchemeID })
        }
        let names = ConfigurationSettingsDependencies.names(settings: page.settings, dns: page.dns)
        var references = (recipe.settingsRuleDependencies ?? [:]).filter { names.contains($0.key) }
        for name in names.sorted() where references[name] == nil {
            let input = try resolveInput(payload(recipe.ruleSource))
            guard input.document.topLevelValue("rule-providers")?.topLevelValue(name) != nil else {
                throw ConfigurationCompositionError.unresolvedDependency(source: "Advanced settings", name: name)
            }
            references[name] = recipe.ruleSource
        }
        recipe.settingsRuleDependencies = references.isEmpty ? nil : references
    }

    private func settingsProviders(_ references: [String: ConfigurationSourceVersion]?,
        resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput) throws -> OrderedJSON {
        var entries: [(key: String, value: OrderedJSON)] = []
        for (name, reference) in (references ?? [:]).sorted(by: { $0.key < $1.key }) {
            let input = try resolveInput(payload(reference))
            guard var definition = input.document.topLevelValue("rule-providers")?.topLevelValue(name) else {
                throw ConfigurationCompositionError.unresolvedDependency(source: "Advanced settings", name: name)
            }
            if case .string(let path) = definition.topLevelValue("path"), let bound = input.resourcePaths[path] {
                definition = definition.settingTopLevel("path", to: .string(bound))
            }
            entries.append((name, definition))
        }
        return .object(entries)
    }

     
     
     
     
     
     
     
     
     
     
     
    func originalSettingsBaseline(of recipe: ConfigurationRecipe,
                                  resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput) throws -> OrderedJSON {
        let input = try resolveInput(payload(recipe.ruleSource))
        guard input.id == recipe.ruleSource.id else { throw ConfigurationLibraryError.invalidIdentifier.noted() }
        return ConfigurationSettingsDocument.project(input.document)
    }

     
     
     
     
     
     
    static func settingsDelta(full: OrderedJSON, baseline: OrderedJSON) -> OrderedJSON {
        guard case .object(let entries) = full else { return .object([]) }
        return .object(entries.filter { entry in
            entry.key != "dns" && baseline.topLevelValue(entry.key) != entry.value
        })
    }

     
     
    static func settingsExpanded(baseline: OrderedJSON, delta: OrderedJSON) -> OrderedJSON {
        guard case .object(let entries) = delta else { return baseline }
        var result = baseline
        for entry in entries { result = result.settingTopLevel(entry.key, to: entry.value) }
        return result
    }

    func overlayingAdvancedSettings(of recipe: ConfigurationRecipe, onto document: OrderedJSON) throws -> OrderedJSON {
        guard let json = recipe.originalSettingsJSON,
              case .object(let entries) = try ConfigurationSettingsDocument.parse(json) else { return document }
        var result = document
        for entry in entries where entry.key != "dns" {
            result = result.settingTopLevel(entry.key, to: entry.value)
        }
        return result
    }

     
     
     
     
     
     
     
    func ruleBase(of scheme: ConfigurationRuleScheme, in candidates: [ConfigurationRuleScheme]? = nil) throws -> ConfigurationRuleScheme? {
        guard let baseID = scheme.rulesFromSchemeID else { return nil }
        if let base = candidates?.first(where: { $0.id == baseID }) { return base }
        if let base = try snapshot().rules.first(where: { $0.id == baseID }) { return base }
        if let base = ConfigurationBuiltins.schemes.first(where: { $0.id == baseID }) { return base }
        throw ConfigurationLibraryError.missingDependency(baseID)
    }

     
     
     
    private func composeInputs(_ allInputs: [ConfigurationInput], ruleInput original: ConfigurationInput,
                               schemeID: String, scheme candidateScheme: ConfigurationRuleScheme? = nil,
                               page: ConfigurationSchemePage.Effective, nodeScopes: [String: ConfigurationNodeScope]? = nil,
                               settingsProviders: OrderedJSON = .object([]),
                               ruleSchemes: [ConfigurationRuleScheme]? = nil,
                               localRuleSets: [ConfigurationLocalRuleSet]? = nil) throws -> ConfigurationComposition {
        let inputs = try allInputs.map { input in try nodeScopes?[input.id]?.applying(to: input) ?? input }
        let viewOrScheme = try candidateScheme ?? snapshot().rules.first { $0.id == schemeID }
         
         
        let scheme = try viewOrScheme.flatMap { try ruleBase(of: $0, in: ruleSchemes) } ?? viewOrScheme
         
         
         
         
        if original.rulesWrittenInOriginal, scheme?.collectionKey == nil, schemeID != ConfigurationBuiltins.basicRuleID,
           schemeID != ConfigurationBuiltins.lazyRuleID {
            throw ConfigurationCompositionError.rulesRunOnlyAsTheOriginal(source: original.id)
        }
        let schemeID = scheme?.id ?? schemeID
         
         
         
         
         
         
         
         
        let ownNodes = ConfigurationRuleDocument.nodeNames(in: original.document)
        let named = Set(ownNodes).union(scheme?.namedNodes ?? [])
        var routing = ConfigurationRuleDocument.project(try scheme?.projectingCollection(original.document) ?? original.document)
        if !named.isEmpty {
            let supplied = Set(inputs.flatMap { input in
                ConfigurationRuleDocument.nodeNames(in: input.document).filter { !input.hiddenNodeNames.contains($0) }
            })
            routing = ConfigurationRuleDocument.binding(routing, nodes: named, supplied: supplied)
        }
        let namedNodesFrom = ownNodes.isEmpty ? scheme?.namedNodesSourceID : nil
         
         
        if let off = scheme?.disabledRules, !off.isEmpty, case .array(let rules) = routing.topLevelValue("rules") {
            let offSet = Set(off)
            routing = routing.settingTopLevel("rules", to: .array(rules.filter { rule in
                if case .string(let raw) = rule { return !offSet.contains(raw) }
                return true
            }))
        }
         
         
         
        if ConfigurationRuleSetLink.writtenInBytes(routing) >= ConfigurationRuleSetLink.writtenInLimit {
            routing = ConfigurationRuleSetLink.linkingWrittenSets(in: routing,
                localSets: try localRuleSets ?? snapshot().localRuleSets ?? [])
        }
        if schemeID == ConfigurationBuiltins.basicRuleID {
            routing = inputs.isEmpty
                ? .object([("proxy-groups", .array([])), ("rules", .array([.string("MATCH,DIRECT")]))])
                : ConfigurationBuiltins.basicDocument
        }
        if schemeID == ConfigurationBuiltins.lazyRuleID, inputs.isEmpty,
           case .array(let groups) = routing.topLevelValue("proxy-groups") {
            routing = routing.settingTopLevel("proxy-groups", to: .array(groups.map { group in
                guard group.topLevelValue("name") == .string("AUTO") else { return group }
                return .object([("name", .string("AUTO")), ("type", .string("select")),
                                ("proxies", .array([.string("DIRECT")]))])
            }))
        }
        if case .object(let retained) = settingsProviders, !retained.isEmpty {
            var providers = routing.topLevelValue("rule-providers") ?? .object([])
            for (name, definition) in retained {
                if let existing = providers.topLevelValue(name), existing != definition {
                    throw ConfigurationCompositionError.duplicateName(source: "Advanced settings and rule scheme", name: name)
                }
                providers = providers.settingTopLevel(name, to: definition)
            }
            routing = routing.settingTopLevel("rule-providers", to: providers)
        }
        let ruleInput = ConfigurationInput(id: original.id, document: routing, resourcePaths: original.resourcePaths)
        var composition = try ConfigurationComposer.compose(sources: inputs, rules: ruleInput, namedNodesFrom: namedNodesFrom)
         
         
         
        if case .object(let settings) = page.settings,
           case .object(let combined) = composition.document {
            composition = composition.replacingDocument(.object(settings + combined))
        }
         
         
         
         
         
         
         
         
         
        return composition.replacingDocument(composition.document.settingTopLevel("dns", to: page.dns))
    }

     
     
     
    public func composition(ofRecipe id: String, in snapshot: ConfigurationLibrarySnapshot,
        resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput = {
            .init(id: $0.record.id, document: try OrderedJSON.parse($0.documentJSON))
        }) throws -> ConfigurationComposition {
        guard let recipe = snapshot.recipes.first(where: { $0.id == id }), recipe.preservesOriginal != true else {
            throw ConfigurationLibraryError.missingDependency(id)
        }
        return try composition(of: recipe, in: snapshot, resolveInput: resolveInput)
    }

     
     
     
    func composition(of recipe: ConfigurationRecipe, in snapshot: ConfigurationLibrarySnapshot,
                     held: [ConfigurationSourcePayload] = [],
                     resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput) throws -> ConfigurationComposition {
        func input(_ reference: ConfigurationSourceVersion) throws -> ConfigurationInput {
            let source = try held.first { ConfigurationSourceVersion($0.record) == reference } ?? payload(reference)
            let resolved = try resolveInput(source)
            guard resolved.id == reference.id else { throw ConfigurationLibraryError.invalidIdentifier.noted() }
            return resolved
        }
        let scheme = snapshot.rules.first { $0.id == recipe.ruleSchemeID }
        return try composeInputs(recipe.sources.map(input), ruleInput: input(recipe.ruleSource),
            schemeID: recipe.ruleSchemeID, scheme: scheme,
            page: try ConfigurationSchemePage.effective(of: recipe, scheme: scheme), nodeScopes: recipe.nodeScopes,
            settingsProviders: try settingsProviders(recipe.settingsRuleDependencies, resolveInput: resolveInput),
            ruleSchemes: snapshot.rules)
    }

    public func exportArchive() throws -> ConfigurationLibraryArchive {
        let current = try snapshot()
        var pending = current.sources.map(ConfigurationSourceVersion.init) + current.recipes.flatMap { $0.dependencies }
        var seen = Set<ConfigurationSourceVersion>(), payloads: [ConfigurationSourcePayload] = []
        while let reference = pending.popLast() {
            guard seen.insert(reference).inserted else { continue }
            let value = try payload(reference)
            payloads.append(value)
            pending += value.record.nodeChain?.hops.map(\.source) ?? []
        }
        payloads.sort { ($0.record.id, $0.record.version) < ($1.record.id, $1.record.version) }

        return .init(snapshot:current, payloads:payloads, publications:try (current.pendingPublications ?? []).map(publication))
    }

     
     
    public func restoreArchive(_ archive: ConfigurationLibraryArchive,
                               expectedGeneration: UInt64) throws -> ConfigurationLibrarySnapshot {
        try validateArchive(archive)
        return try commit(archive.snapshot, payloads:archive.payloads, publications:archive.publications ?? [], expectedGeneration:expectedGeneration)
    }
}

public extension ConfigurationBuiltins {
     
     
     
    static let retiredCommunityRuleIDs = ["acl4ssr-default", "acl4ssr-mini", "acl4ssr-full"]
    static var schemes: [ConfigurationRuleScheme] { [basicScheme, lazyScheme] }
    static var records: [ConfigurationSourceRecord] { [basicRecord, lazyRecord] }

     
     
    public static func source(for id: String) throws -> ConfigurationSourcePayload? {
        if id == basicRuleID { return basicSource }
        if id == lazyRuleID { return shippedLazy }
        return nil
    }

     
     
     
     
     
     
    static func retiringCommunitySchemes(in snapshot: ConfigurationLibrarySnapshot)
        -> (snapshot: ConfigurationLibrarySnapshot, payloads: [ConfigurationSourcePayload])? {
        let retired = Set(retiredCommunityRuleIDs)
        var candidate = snapshot
        let affected = candidate.recipes.indices.filter { retired.contains(candidate.recipes[$0].ruleSchemeID) }
        let stale = candidate.rules.contains { retired.contains($0.id) } || candidate.sources.contains { retired.contains($0.id) }
        guard !affected.isEmpty || stale else { return nil }
        var payloads: [ConfigurationSourcePayload] = []
        if !affected.isEmpty {
            let basic = basicSource
            if !candidate.rules.contains(where: { $0.id == basicRuleID }) { candidate.rules.append(basicScheme) }
            if !candidate.sources.contains(where: { $0.id == basic.record.id }) {
                candidate.sources.append(basic.record); payloads.append(basic)
            }
            for index in affected {
                candidate.recipes[index].ruleSchemeID = basicRuleID
                candidate.recipes[index].ruleSource = .init(basic.record)
            }
        }
        candidate.rules.removeAll { retired.contains($0.id) }
        candidate.sources.removeAll { retired.contains($0.id) }
        return (candidate, payloads)
    }
}


public extension ConfigurationLibraryStore {
     
     
     
     
     
     
     
     
     
    func prepareRuleCustomization(_ draft: ConfigurationRuleDraft, profileID: String? = nil, expectedGeneration: UInt64,
        localRuleSets: [ConfigurationLocalRuleSet]? = nil,
        resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput) throws -> PreparedConfigurationSourceUpdate {
        let current = try snapshot()
        guard current.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        let scheme: ConfigurationRuleScheme
        if let profileID {
            guard let recipe = current.recipes.first(where: { $0.id == profileID }), recipe.preservesOriginal != true else {
                throw ConfigurationLibraryError.missingDependency(profileID)
            }
            guard draft.schemeID == recipe.ruleSchemeID,
                  let own = current.rules.first(where: { $0.id == recipe.ruleSchemeID })
                    ?? ConfigurationBuiltins.schemes.first(where: { $0.id == recipe.ruleSchemeID }) else {
                throw ConfigurationLibraryError.staleGeneration
            }
            scheme = own
        } else {
            guard let effective = current.effectiveRuleScheme(draft.schemeID) else { throw ConfigurationLibraryError.missingDependency(draft.schemeID) }
            scheme = effective
        }
         
         
         
         
         
        let kept = scheme.isRetainedSnapshot == true
        guard !kept || profileID != nil else { throw ConfigurationLibraryError.retainedSnapshot }
        if !kept, scheme.collectionKey == nil && scheme.rulesFromSchemeID == nil && (scheme.kind == .custom || scheme.kind == .imported) {
            let prepared = try prepareRuleEditing(draft, expectedGeneration: expectedGeneration, localRuleSets: localRuleSets,
                                                  resolveInput: resolveInput)
            var candidate = prepared.candidate
            if let i = candidate.rules.firstIndex(where: { $0.id == draft.schemeID }), candidate.rules[i].initialDocumentJSON == nil {
                candidate.rules[i].initialDocumentJSON = draft.originalDocument.serialized()
            }
            if let i = candidate.rules.firstIndex(where: { $0.id == draft.schemeID }) { candidate.rules[i].generatedRuleGroups = draft.generatedRuleGroups }
            return .init(candidate: candidate, payloads: prepared.payloads, compositions: prepared.compositions)
        }
        guard current.pendingPublications?.isEmpty ?? true else { throw ConfigurationLibraryError.busy }
        let previous = try ruleSchemePayload(scheme.id)
        guard draft.version == ConfigurationSourceVersion(previous.record), try OrderedJSON.parse(previous.documentJSON) == draft.originalDocument else { throw ConfigurationLibraryError.staleGeneration }
        let document = try draft.document()
         
        let sourceName = scheme.rulesFromSchemeID != nil && scheme.ownViewBaseID != nil ? scheme.label : draft.label
        var record = ConfigurationSourceRecord(label: sourceName, origin: .file(sourceName + ".yaml"),
            groupCount: draft.groups.count, ruleCount: draft.rows.count, suppliesNodes: false)
         
         
         
        record.ruleProviderCount = Self.ruleSetCount(document)
         
         
         
         
        let turnsView = scheme.rulesFromSchemeID != nil
         
         
         
         
         
         
        let owner = kept ? profileID : turnsView ? scheme.privateToConfigurationID : nil
        if let owner { record.privateToConfigurationID = owner }
        let replacement = ConfigurationSourcePayload(record: record, original: Data(document.serialized().utf8),
            documentJSON: document.serialized(), resourceFiles: previous.resourceFiles)
         
         
        var customized = ConfigurationRuleScheme(id: turnsView ? scheme.id : UUID().uuidString,
            label: turnsView ? scheme.label : draft.label, kind: .custom, sourceID: record.id)
        customized.ownViewOfCustomScheme = turnsView ? scheme.ownViewOfCustomScheme : nil
        if !turnsView { customized.baseSchemeID = scheme.id }
        customized.rulesCustomizedFromSchemeID = turnsView ? scheme.rulesFromSchemeID : scheme.id
        customized.initialDocumentJSON = previous.documentJSON
        customized.pageJSON = scheme.pageJSON
        customized.generatedRuleGroups = draft.generatedRuleGroups
         
         
         
        customized.disabledRules = draft.disabledRules.isEmpty ? nil : draft.disabledRules.sorted()
        customized.ruleNotes = draft.notes.isEmpty ? nil : draft.notes
        customized.namedNodes = draft.namedNodes
        customized.namedNodesSourceID = draft.namedNodesSourceID
        if let owner { customized.privateToConfigurationID = owner }
        var candidate = current
        candidate.sources.append(record)
        if turnsView, let index = candidate.rules.firstIndex(where: { $0.id == scheme.id }) {
            candidate.rules[index] = customized
        } else {
            candidate.rules.append(customized)
        }
        if profileID == nil, candidate.selectedRuleSchemeID == scheme.id || (candidate.selectedRuleSchemeID == nil && current.visibleRuleSchemes.first?.id == scheme.id) { candidate.selectedRuleSchemeID = customized.id }
        var compositions: [String: ConfigurationComposition] = [:]
        let ruleInput = try resolveInput(replacement)
         
         
        for index in candidate.recipes.indices where candidate.recipes[index].ruleSchemeID == scheme.id
            && (turnsView || profileID == nil || candidate.recipes[index].id == profileID) {
            var recipe = candidate.recipes[index]
            try adoptComposition(in: &recipe, resolveInput: resolveInput)
            try freezeSettings(in: &recipe, resolveInput: resolveInput)
            recipe.ruleSchemeID = customized.id; recipe.ruleSource = .init(record)
            let inputs = try recipe.sources.map { try resolveInput(payload($0)) }
            compositions[recipe.id] = try composeInputs(inputs, ruleInput: ruleInput, schemeID: customized.id, scheme: customized,
                page: try ConfigurationSchemePage.effective(of: recipe, scheme: customized), nodeScopes: recipe.nodeScopes, settingsProviders: try settingsProviders(recipe.settingsRuleDependencies, resolveInput: resolveInput), ruleSchemes: candidate.rules)
            recipe.droppedRules = compositions[recipe.id].flatMap { $0.droppedRules.isEmpty ? nil : $0.droppedRules }
            candidate.recipes[index] = recipe
        }
        return .init(candidate: candidate, payloads: [replacement], compositions: compositions)
    }
}


public extension ConfigurationLibraryStore {
     
    func prepareLocalRuleSet(_ value: ConfigurationLocalRuleSet?, deleting id: String?, expectedGeneration: UInt64,
        resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput) throws -> PreparedConfigurationSourceUpdate {
        let original = try snapshot()
        guard original.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        guard original.pendingPublications?.isEmpty ?? true else { throw ConfigurationLibraryError.busy }
        guard let targetID = value?.id ?? id else { throw ConfigurationLibraryError.invalidIdentifier.noted() }
        if let value {
            guard !value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ConfigurationLibraryError.emptyName }
             
            guard !value.rules.isEmpty || value.link?.format == "mrs" else { throw ConfigurationLibraryError.missingRules }
        }
        var candidate = original
        var sets = original.localRuleSets ?? []
        if let index = sets.firstIndex(where: { $0.id == targetID }) {
            if let value { sets[index] = value } else { sets.remove(at: index) }
        } else if let value { sets.append(value) }
        candidate.localRuleSets = sets
        var payloads: [ConfigurationSourcePayload] = []
        var compositions: [String: ConfigurationComposition] = [:]
        var changedSources = Set<String>()
         
         
         
        for scheme in original.availableRules where (scheme.kind == .custom || scheme.kind == .imported) && scheme.collectionKey == nil
            && scheme.rulesFromSchemeID == nil {
            var draft = try ConfigurationRuleDraft(scheme: scheme, payload: ruleSchemePayload(scheme.id))
            guard draft.containsRuleSet("local-" + targetID) else { continue }
            if let value { try draft.updateLocalRuleSet(value) } else { draft.removeRuleSet("local-" + targetID) }
             
             
            let prepared = try prepareRuleCustomization(draft, expectedGeneration: original.generation,
                                                        localRuleSets: sets, resolveInput: resolveInput)
            for payload in prepared.payloads {
                guard changedSources.insert(payload.record.id).inserted else { throw ConfigurationLibraryError.invalidIdentifier.noted() }
                guard let index = candidate.sources.firstIndex(where: { $0.id == payload.record.id }) else { throw ConfigurationLibraryError.missingDependency(payload.record.id) }
                candidate.sources[index] = payload.record; payloads.append(payload)
            }
            if let index = candidate.rules.firstIndex(where: { $0.id == scheme.id }), let updated = prepared.candidate.rules.first(where: { $0.id == scheme.id }) { candidate.rules[index] = updated }
            for (key, composition) in prepared.compositions {
                compositions[key] = composition
                if let index = candidate.recipes.firstIndex(where: { $0.id == key }), let updated = prepared.candidate.recipes.first(where: { $0.id == key }) { candidate.recipes[index] = updated }
            }
        }
        return .init(candidate: candidate, payloads: payloads, compositions: compositions)
    }
}

public extension ConfigurationBuiltins {
    static let lazyRuleID = "clash-lazy-rules"
    static func isNative(_ id: String) -> Bool { id == basicRuleID || id == lazyRuleID }

     
    static func displayName(for id: String) -> String? {
        if id == basicRuleID { return NSLocalizedString("Default Configuration", comment: "Built-in routing template") }
        if id == lazyRuleID { return NSLocalizedString("Lazy Configuration", comment: "Built-in routing template") }
        return nil
    }

     
     
     
     
     
     
    static let customNodesName = "Custom Nodes"

     
     
    internal static var lazyServices: [(name: String, direct: Bool, domains: [String], ips: [String])] {
        [
            ("AI", false, ["category-ai-!cn"], []),
            ("YouTube", false, ["youtube"], []),
            ("Netflix", false, ["netflix"], ["netflix"]),
            ("Telegram", false, ["telegram"], ["telegram"]),
             
             
            ("Streaming", false, ["disney", "hbo", "spotify", "tiktok", "twitch", "primevideo",
                "bahamut", "biliintl", "dazn", "hulu", "abema", "bbc", "dmm", "niconico",
                "viu", "soundcloud", "discoveryplus"], []),
            ("Gaming", false, ["epicgames", "origin", "sony", "nintendo", "steam"], []),
             
             
             
            ("GitHub", false, ["github"], []),
            ("Apple", true, ["apple"], []),
            ("Microsoft", true, ["microsoft"], []),
            ("Bilibili", true, ["bilibili"], []),
            ("Google FCM", false, ["googlefcm"], [])
        ]
    }
    static var lazyRecord: ConfigurationSourceRecord { shippedLazy.record }
    static var lazyScheme: ConfigurationRuleScheme {
        .init(id: lazyRuleID, label: "Lazy Configuration", kind: .builtin, sourceID: lazyRuleID)
    }
    private static let shippedLazy = lazySource(services: lazyServices)
     
     
    internal static func lazySource(services: [(name: String, direct: Bool, domains: [String], ips: [String])]) -> ConfigurationSourcePayload {
        var groups: [OrderedJSON] = []
        if case .array(let baseGroups) = basicDocument.topLevelValue("proxy-groups") { groups = baseGroups }
        var rules = localRules.map(OrderedJSON.string)
        for service in services {
            groups.append(.object([
                ("name", .string(service.name)), ("type", .string("select")),
                ("include-all", .scalar("true")),
                ("proxies", .array((service.direct ? ["DIRECT", "PROXY"] : ["PROXY", "DIRECT"]).map(OrderedJSON.string)))
            ]))
            rules.append(contentsOf: service.domains.map { .string("GEOSITE,\($0),\(service.name)") })
            rules.append(contentsOf: service.ips.map { .string("GEOIP,\($0),\(service.name),no-resolve") })
        }
        rules.append(contentsOf: fallbackRules.map(OrderedJSON.string))
        let document = OrderedJSON.object([("proxy-groups", .array(groups)), ("rules", .array(rules))]).serialized()
        let serviceRuleCount = services.reduce(0) { $0 + $1.domains.count + $1.ips.count }
        var record = ConfigurationSourceRecord(id: lazyRuleID, label: "Lazy Configuration", origin: .bundled("lazy"),
              version: contentVersion(document), groupCount: 2 + services.count,
              ruleCount: localRules.count + fallbackRules.count + serviceRuleCount, suppliesNodes: false,
              updatedAt: Date(timeIntervalSince1970: 0))
        record.ruleProviderCount = 0
        return .init(record: record, original: Data(document.utf8), documentJSON: document)
    }
}

public extension ConfigurationRuleScheme {
     
    var displayLabel: String {
        if let builtin = ConfigurationBuiltins.displayName(for: id) { return builtin }
         
         
         
         
         
         
        if let base = ownViewBaseID {
            let custom = " · " + NSLocalizedString("Custom", comment: "Customized rule scheme")
            let scheme = ConfigurationBuiltins.displayName(for: base) ?? label + (ownViewOfCustomScheme == true ? custom : "")
            return plainViewBaseID != nil ? scheme : scheme + custom
        }
        if baseSchemeID.map(ConfigurationBuiltins.isNative) == true { return label + " · " + NSLocalizedString("Custom", comment: "Customized rule scheme") }
        return label
    }
}

public extension ConfigurationLibraryStore {
    func prepareAdvancedSettingsEditing(_ profileID: String, settingsJSON: String, expectedGeneration: UInt64, includingDNS: Bool = false,
        resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput = {
            .init(id: $0.record.id, document: try OrderedJSON.parse($0.documentJSON))
        }) throws -> PreparedConfigurationSourceUpdate {
        let edited = try ConfigurationAdvancedSettingsDocument.parse(settingsJSON, includingDNS: includingDNS)
        var candidate = try snapshot()
        guard candidate.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        guard candidate.pendingPublications?.isEmpty ?? true else { throw ConfigurationLibraryError.busy }
        guard let index = candidate.recipes.firstIndex(where: { $0.id == profileID }) else {
            throw ConfigurationLibraryError.missingDependency(profileID)
        }
        var recipe = candidate.recipes[index]
        try freezeSettings(in: &recipe, resolveInput: resolveInput)
        if recipe.preservesOriginal == true {
             
             
             
             
            if includingDNS {
                let running = try resolveInput(payload(recipe.ruleSource)).document.topLevelValue("dns")
                if running != edited.topLevelValue("dns") { throw ConfigurationLibraryError.originalKeepsSourceDNS }
            }
            let baseline = try originalSettingsBaseline(of: recipe, resolveInput: resolveInput)
            recipe.originalSettingsJSON = Self.settingsDelta(full: edited, baseline: baseline).serialized()
            try captureSettingsDependencies(in: &recipe, settingsJSON: recipe.originalSettingsJSON, resolveInput: resolveInput)
            let original = try resolveInput(payload(recipe.ruleSource))
            guard original.id == recipe.ruleSource.id else { throw ConfigurationLibraryError.invalidIdentifier.noted() }
            candidate.recipes[index] = recipe
            return .init(candidate: candidate, payloads: [],
                         compositions: [profileID: .init(document: try overlayingAdvancedSettings(of: recipe, onto: original.document),
                                                         sourceIDs: [original.id])])
        }
        let original = try OrderedJSON.parse(recipe.settingsJSON ?? "{}")
         
         
        if recipe.dnsMode == nil || recipe.dnsMode == .source { recipe.dnsMode = .system }
        if includingDNS {
             
             
            let updated = edited.topLevelValue("dns")
            let previous = try advancedSourceDocument(recipe).topLevelValue("dns")
            if previous != updated {
                recipe.dnsMode = updated == nil ? .system : .custom
                recipe.customDNSJSON = updated?.serialized()
                if updated != nil { _ = try ConfigurationDNSSettings.custom(recipe.customDNSJSON) }
            }
            recipe.settingsJSON = edited.removingTopLevel("dns").serialized()
        } else {
             
            recipe.settingsJSON = (original.topLevelValue("dns").map {
                edited.settingTopLevel("dns", to: $0)
            } ?? edited).serialized()
        }
        try captureSettingsDependencies(in: &recipe, resolveInput: resolveInput)
        let inputs = try recipe.sources.map { try resolveInput(payload($0)) }
        let rule = try resolveInput(payload(recipe.ruleSource))
        let composition = try composeInputs(inputs, ruleInput: rule, schemeID: recipe.ruleSchemeID, scheme: candidate.rules.first { $0.id == recipe.ruleSchemeID },
            page: try ConfigurationSchemePage.effective(of: recipe, scheme: candidate.rules.first { $0.id == recipe.ruleSchemeID }),
            nodeScopes: recipe.nodeScopes, settingsProviders: try settingsProviders(recipe.settingsRuleDependencies, resolveInput: resolveInput), ruleSchemes: candidate.rules)
        var recorded = recipe
        recorded.droppedRules = composition.droppedRules.isEmpty ? nil : composition.droppedRules
        candidate.recipes[index] = recorded
        return .init(candidate: candidate, payloads: [], compositions: [profileID: composition])
    }
}

public enum ConfigurationAdvancedSettingsDocument {
    public static func project(_ value: OrderedJSON, includingDNS: Bool = false) -> OrderedJSON {
        let settings = ConfigurationSettingsDocument.project(value)
        return includingDNS ? settings : settings.removingTopLevel("dns")
    }
    public static func parse(_ json: String, includingDNS: Bool = false) throws -> OrderedJSON {
        let value = try OrderedJSON.parse(json)
        guard case .object = value, project(value, includingDNS: includingDNS) == value else {
            throw ConfigurationLibraryError.invalidAdvancedSettings
        }
        return value
    }
}

public extension ConfigurationLibraryStore {
    func advancedSettings(_ profileID: String, includingDNS: Bool = false,
        resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput = {
            .init(id: $0.record.id, document: try OrderedJSON.parse($0.documentJSON))
        }) throws -> (json: String, generation: UInt64) {
        let current = try snapshot()
        guard var recipe = current.recipes.first(where: { $0.id == profileID }) else {
            throw ConfigurationLibraryError.missingDependency(profileID)
        }
        try freezeSettings(in: &recipe, resolveInput: resolveInput)
        let document: OrderedJSON
        if recipe.preservesOriginal == true {
             
             
            document = try Self.settingsExpanded(baseline: originalSettingsBaseline(of: recipe, resolveInput: resolveInput),
                                                 delta: OrderedJSON.parse(recipe.originalSettingsJSON ?? "{}"))
        } else {
            document = try includingDNS ? advancedSourceDocument(recipe) : OrderedJSON.parse(recipe.settingsJSON ?? "{}")
        }
        return (ConfigurationAdvancedSettingsDocument.project(document, includingDNS: includingDNS).serialized(), current.generation)
    }
}

private func advancedSourceDocument(_ recipe: ConfigurationRecipe) throws -> OrderedJSON {
    let settings = try OrderedJSON.parse(recipe.settingsJSON ?? "{}")
    if recipe.dnsMode == .system || recipe.dnsMode == .source || recipe.dnsMode == nil {
         
         
         
        return settings.settingTopLevel("dns", to: ConfigurationDNSSettings.automatic)
    }
    if recipe.dnsMode == .custom { return settings.settingTopLevel("dns", to: try ConfigurationDNSSettings.custom(recipe.customDNSJSON)) }
    return settings
}
