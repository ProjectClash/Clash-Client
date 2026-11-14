import CryptoKit
import Foundation
import ClashClientKit

 
enum OriginalEditingError: LocalizedError, Equatable {
     
    case composed
     
     
    case notYAMLText
    case gone
     
     
     
    case followsSubscription
     
     
    case changedSinceRead
     
     
     
    case keptRulesName([String])

    var errorDescription: String? {
        switch self {
        case .composed: return "This configuration is composed. Change its settings on its page."
        case .notYAMLText: return "This configuration’s file is not YAML the editor can change. Edit it in the source."
        case .gone: return "The configuration is no longer available."
        case .followsSubscription: return "Updates from the Profile URL replace changes made here."
        case .changedSinceRead: return "The configuration changed. Reopen it and try again."
        case .keptRulesName(let places):
             
             
            let sentence = ClashCopy.string(for: .copy("Rules in this configuration's file use this name. Change it in the file, then import it again."),
                                            locale: AppPreferences.language().locale)
            return ([sentence] + places.prefix(OriginalListEdits.keptPlacesShown)).joined(separator: "\n")
        }
    }
}

 
 
 
enum GroupSelectionCarryOver: Equatable {
     
    case nothing
     
     
    case carried(String)
     
     
    case needsChoosingAgain(String?)
}

 
@MainActor
protocol GroupSelectionCarrying: AnyObject {
     
     
    func currentChoice(ofGroup name: String) async -> String?
    func choose(_ member: String, inGroup name: String) async -> Bool
}

extension ClashCommandClient: GroupSelectionCarrying {
    func currentChoice(ofGroup name: String) async -> String? {
        guard isConnected else { return nil }
        await refreshMetadata()
        guard let group = NodeInventory.parse(proxiesData).0.first(where: { $0.name == name }) else { return nil }
         
        let choice = ProxyGroupControlKind(rawType: group.type).canBeUnpinned ? group.fixed : group.now
        return choice?.isEmpty == false ? choice : nil
    }

    func choose(_ member: String, inGroup name: String) async -> Bool {
        await select(group: name, name: member)
    }
}

 

extension ProfilesViewModel {
     
     
     
     
    struct OwnReferencesChange: Sendable {
        var rename: (kind: ConfigurationReferenceKind, oldName: String, newName: String)?
        let make: @Sendable (Profile) throws -> PendingOriginalRename.References?
    }

     
    nonisolated static func textDigest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

     
     
     
     
     
    nonisolated static func textDigest(fileAt url: URL) throws -> String {
        let identity = OriginalFileDigests.identity(of: url)
        if let identity, let known = OriginalFileDigests.shared.digest(of: url.path, identity: identity) { return known }
        let data = try Data(contentsOf: url, options: [.alwaysMapped])
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
         
        if let identity, OriginalFileDigests.identity(of: url) == identity {
            OriginalFileDigests.shared.record(digest, of: url.path, identity: identity)
        }
        return digest
    }

     
     
     
     
     
     
     
     
     
    func editOriginalConfiguration(_ id: String, at path: [ConfigurationTextPathStep],
                                   _ edit: ConfigurationTextEdit, readDigest: String? = nil) async throws {
        let own = Self.providerField(at: path).map { field in
            OwnReferencesChange { profile in Self.clearingDefinition(of: field.name, kind: field.kind, field: field.field, in: profile) }
        }
        _ = try await changeOriginalText(of: id, readDigest: readDigest, own: own) { text in
            (try ConfigurationTextEditing.edit(text, at: path, edit), 0)
        }
    }

     
     
     
     
     
    func deleteInOriginalConfiguration(_ id: String, at path: [String], readDigest: String? = nil) async throws {
        let own = OwnReferencesChange { profile in Self.removingFromOwnLayers(path, of: profile) }
        _ = try await changeOriginalText(of: id, readDigest: readDigest, own: own) { text in
            (try ConfigurationTextEditing.edit(text, at: path.map(ConfigurationTextPathStep.key), .delete), 0)
        }
    }

     
    nonisolated static func removingFromOwnLayers(_ path: [String], of profile: Profile) -> PendingOriginalRename.References? {
        func removing(_ json: String?) -> String? {
            guard let json, !json.isEmpty, let root = try? OrderedJSON.parse(json), root.node(at: path) != nil else { return nil }
            let next = root.setting(path: path, to: nil)
            if case .object(let entries) = next, entries.isEmpty { return "" }
            return try? next.serialized()
        }
        let legacy = removing(profile.legacyRuntimePatchJSON)
        let override = removing(profile.override.patchJSON)
        guard legacy != nil || override != nil else { return nil }
        var references = PendingOriginalRename.References(profile)
        if let legacy { references.legacyRuntimePatchJSON = legacy.isEmpty ? nil : legacy }
        if let override { references.override.patchJSON = OverridePatch(patchJSON: override).patchJSON }
        return references
    }

     
     
     
     
     
     
    @discardableResult
    func renameInOriginalConfiguration(_ id: String, kind: ConfigurationReferenceKind, from oldName: String,
                                       to newName: String, selections: GroupSelectionCarrying? = nil,
                                       readDigest: String? = nil)
        async throws -> GroupSelectionCarryOver {
         
         
         
         
        if kind != .proxyProvider, let file = try await keptRulesFile(of: id) {
            let places: [String]
            do {
                places = try await Task.detached(priority: .userInitiated) {
                    kind == .ruleProvider ? try OriginalListEdits.keptUses(ofRuleSet: oldName, keptAt: file)
                        : try OriginalListEdits.keptUses(of: oldName, keptAt: file)
                }.value
            } catch {
                 
                 
                ClashLogStore.shared.append("kept rules: \(error.localizedDescription)", stream: .app, level: .warning)
                throw PublishedRules.Unreadable()
            }
            if !places.isEmpty { throw OriginalEditingError.keptRulesName(places) }
        }
        let inUse = id == activeProfileID
        let running = kind == .proxyGroup && inUse ? await selections?.currentChoice(ofGroup: oldName) : nil
         
         
         
         
         
        let own = OwnReferencesChange(rename: (kind, oldName, newName)) { profile in
            try Self.renamedOwnReferences(of: profile, kind: kind, from: oldName, to: newName)
        }
        _ = try await changeOriginalText(of: id, readDigest: readDigest, own: own) { text in
            let renamed = try ConfigurationTextEditing.rename(text, kind: kind, from: oldName, to: newName)
            return (renamed.text, renamed.changed)
        }
        guard kind == .proxyGroup else { return .nothing }
        let recorded = try moveRecordedChoice(ofGroup: oldName, to: newName, in: id)
        if let running {
            await waitForPendingActivation()
            return await selections?.choose(running, inGroup: newName) == true ? .carried(running) : .needsChoosingAgain(running)
        }
        if let recorded { return .carried(recorded) }
        return inUse && selections != nil ? .nothing : .needsChoosingAgain(nil)
    }

     
     
    func keptRulesFile(of id: String) async throws -> URL? {
        guard let library = configurationLibraryStore else { return nil }
        return try await Task.detached(priority: .userInitiated) { () throws -> URL? in
            let snapshot = try library.snapshot()
            guard let recipe = snapshot.recipes.first(where: { $0.id == id }), recipe.preservesOriginal == true,
                  snapshot.sources.first(where: { $0.id == recipe.ruleSource.id })?.rulesWrittenInOriginal == true
            else { return nil }
            return try library.originalURL(recipe.ruleSource)
        }.value
    }

     
     
     
     
     
     
     
     
     
     
    nonisolated static func renamedOwnReferences(of profile: Profile, kind: ConfigurationReferenceKind,
                                                 from oldName: String, to newName: String) throws -> PendingOriginalRename.References? {
        guard oldName != newName, !oldName.isEmpty, !newName.isEmpty else { return nil }
        var renamed = profile
        func layer(_ json: String) throws -> String {
            guard !json.isEmpty, case .object(let entries) = try OrderedJSON.parse(json), !entries.isEmpty else { return json }
            guard let document = try renamedAsTheText(.object(entries), kind: kind, from: oldName, to: newName) else { return json }
            return OverridePatch(patchJSON: document.serialized()).patchJSON
        }
        renamed.legacyRuntimePatchJSON = try renamed.legacyRuntimePatchJSON.map(layer)
        renamed.override.patchJSON = try layer(renamed.override.patchJSON)
        if var migrated = renamed.migratedGlobalOverride {
            migrated.patchJSON = try layer(migrated.patchJSON)
            renamed.migratedGlobalOverride = migrated
        }
        if var definitions = renamed.providerDefinitions {
            definitions.proxyProviders = try renamedDefinitions(definitions.proxyProviders, section: "proxy-providers",
                                                                kind: kind, from: oldName, to: newName)
            definitions.ruleProviders = try renamedDefinitions(definitions.ruleProviders, section: "rule-providers",
                                                               kind: kind, from: oldName, to: newName)
            renamed.providerDefinitions = definitions
        }
        switch kind {
        case .proxyGroup:
            var unusedPayload: [[String: Any]] = []
            ProxyNodeRename.apply(from: oldName, to: newName, profile: &renamed, customPayload: &unusedPayload)
        case .ruleProvider:
            renamed.override = try renamedRuleSets(in: renamed.override, from: oldName, to: newName)
            if let migrated = renamed.migratedGlobalOverride {
                renamed.migratedGlobalOverride = try renamedRuleSets(in: migrated, from: oldName, to: newName)
            }
            if var custom = renamed.customOverwrite {
                custom.rules = try renamedRules(custom.rules, kind: .ruleProvider, from: oldName, to: newName)
                renamed.customOverwrite = custom
            }
        case .proxyProvider:
            break
        }
        let before = PendingOriginalRename.References(profile)
        let after = PendingOriginalRename.References(renamed)
        return after == before ? nil : after
    }

     
     
     
     
    nonisolated static func renamedAsTheText(_ document: OrderedJSON, kind: ConfigurationReferenceKind,
                                             from oldName: String, to newName: String) throws -> OrderedJSON? {
        let section: String
        let lent: OrderedJSON?
        switch kind {
        case .proxyGroup:
            section = "proxy-groups"
            let groups: [OrderedJSON]
            switch document.topLevelValue(section) {
            case .array(let items)?: groups = items
            case nil: groups = []
            default: return nil
            }
            lent = groups.contains { $0.topLevelValue("name") == .string(oldName) } ? nil
                : .array(groups + [.object([("name", .string(oldName)), ("type", .string("select")),
                                            ("proxies", .array([.string("DIRECT")]))])])
        case .ruleProvider, .proxyProvider:
            section = kind == .ruleProvider ? "rule-providers" : "proxy-providers"
            let providers: [(key: String, value: OrderedJSON)]
            switch document.topLevelValue(section) {
            case .object(let items)?: providers = items
            case nil: providers = []
            default: return nil
            }
            let stub: OrderedJSON = kind == .ruleProvider
                ? .object([("type", .string("inline")), ("behavior", .string("classical")), ("payload", .array([]))])
                : .object([("type", .string("inline")), ("payload", .array([]))])
            lent = providers.contains { $0.key == oldName } ? nil : .object(providers + [(oldName, stub)])
        }
        let asked = lent.map { document.settingTopLevel(section, to: $0) } ?? document
         
         
        let text = try ConfigTransforms.jsonToYAML(asked.serialized())
        let renamed = try ConfigurationTextEditing.rename(text, kind: kind, from: oldName, to: newName)
        guard renamed.changed > (lent == nil ? 0 : 1) else { return nil }
        var result = try OrderedJSON.parse(ConfigTransforms.yamlToJSON(renamed.text))
        guard lent != nil else { return result }
        switch result.topLevelValue(section) {
        case _ where document.topLevelValue(section) == nil:
            result = result.removingTopLevel(section)
        case .array(let items)?:
            result = result.settingTopLevel(section, to: .array(Array(items.dropLast())))
        case .object(let items)?:
            result = result.settingTopLevel(section, to: .object(items.filter { $0.key != newName }))
        default:
            break
        }
        return result
    }

     
     
     
     
    nonisolated static func renamedDefinitions(_ mutations: [ProfileProviderDefinitionMutation], section: String,
                                               kind: ConfigurationReferenceKind, from oldName: String,
                                               to newName: String) throws -> [ProfileProviderDefinitionMutation] {
        var result = mutations
        let own = (kind == .ruleProvider && section == "rule-providers") || (kind == .proxyProvider && section == "proxy-providers")
        for index in result.indices where own && result[index].name == oldName { result[index].name = newName }
         
         
        guard kind == .proxyGroup || (kind == .ruleProvider && section == "rule-providers") else { return result }
        func renamed(_ read: (ProfileProviderDefinitionMutation) -> String?,
                     _ write: (inout ProfileProviderDefinitionMutation, String) -> Void) throws {
            let entries: [(index: Int, value: OrderedJSON)] = mutations.indices.compactMap { index in
                guard let json = read(mutations[index]), json != ProfileProviderDefinitionMutation.addedBaseline,
                      let value = try? OrderedJSON.parse(json), case .object = value else { return nil }
                return (index, value)
            }
            guard !entries.isEmpty else { return }
            let document = OrderedJSON.object([(section, .object(entries.map { (mutations[$0.index].name, $0.value) }))])
            guard let answer = try renamedAsTheText(document, kind: kind, from: oldName, to: newName),
                  case .object(let values)? = answer.topLevelValue(section), values.count == entries.count else { return }
            for (entry, value) in zip(entries, values) where value.value != entry.value {
                write(&result[entry.index], value.value.serialized())
            }
        }
        try renamed({ $0.definitionJSON }) { $0.definitionJSON = $1 }
        try renamed({ $0.baselineJSON }) { $0.baselineJSON = $1 }
        return result
    }

     
     
     
    nonisolated static func renamedRules(_ rules: [String], kind: ConfigurationReferenceKind,
                                         from oldName: String, to newName: String) throws -> [String] {
        guard !rules.isEmpty,
              let answer = try renamedAsTheText(.object([("rules", .array(rules.map(OrderedJSON.string)))]),
                                                kind: kind, from: oldName, to: newName),
              case .array(let items)? = answer.topLevelValue("rules"), items.count == rules.count else { return rules }
        return zip(items, rules).map { item, rule in
            if case .string(let text) = item { return text }
            return rule
        }
    }

     
     
     
    nonisolated static func renamedRuleSets(in spec: OverrideSpec, from oldName: String, to newName: String) throws -> OverrideSpec {
        let texts = spec.appendRules + (spec.disabledAppendRules ?? []) + (spec.appendRuleComments.map { Array($0.keys) } ?? [])
        let renamed = Dictionary(zip(texts, try renamedRules(texts, kind: .ruleProvider, from: oldName, to: newName)),
                                 uniquingKeysWith: { first, _ in first })
        var spec = spec
        spec.appendRules = spec.appendRules.map { renamed[$0] ?? $0 }
        spec.disabledAppendRules = spec.disabledAppendRules?.map { renamed[$0] ?? $0 }
        spec.appendRuleComments = spec.appendRuleComments.map { notes in
            Dictionary(notes.map { (renamed[$0.key] ?? $0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        }
        return spec
    }

     
     
    nonisolated static func providerField(at path: [ConfigurationTextPathStep])
        -> (kind: ProfileProviderKind, name: String, field: String)? {
        guard path.count >= 3, case .key(let section) = path[0], case .key(let name) = path[1],
              case .key(let field) = path[2] else { return nil }
        switch section {
        case "rule-providers": return (.rule, name, field)
        case "proxy-providers": return (.proxy, name, field)
        default: return nil
        }
    }

     
     
     
     
     
     
    nonisolated static func clearingDefinition(of name: String, kind: ProfileProviderKind, field: String,
                                               in profile: Profile) -> PendingOriginalRename.References? {
        guard var definitions = profile.providerDefinitions else { return nil }
        var mutations = kind == .rule ? definitions.ruleProviders : definitions.proxyProviders
        guard let index = mutations.firstIndex(where: { $0.name == name }), let json = mutations[index].definitionJSON,
              var mine = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] else { return nil }
        switch mutations[index].baselineJSON {
        case nil:
            return nil
        case ProfileProviderDefinitionMutation.addedBaseline?:
            guard mine.removeValue(forKey: field) != nil else { return nil }
            if mine.isEmpty { mutations.remove(at: index) }
        case let ancestorJSON?:
            guard let ancestor = (try? JSONSerialization.jsonObject(with: Data(ancestorJSON.utf8))) as? [String: Any] else { return nil }
            if let value = ancestor[field] { mine[field] = value } else { mine.removeValue(forKey: field) }
            if NSDictionary(dictionary: mine).isEqual(to: ancestor) { mutations.remove(at: index) }
        }
        if index < mutations.count, mutations[index].name == name {
            guard let data = try? JSONSerialization.data(withJSONObject: mine, options: [.sortedKeys]) else { return nil }
            mutations[index].definitionJSON = String(decoding: data, as: UTF8.self)
        }
        if kind == .rule { definitions.ruleProviders = mutations } else { definitions.proxyProviders = mutations }
        var updated = profile
        updated.providerDefinitions = definitions.isEmpty ? nil : definitions
        let after = PendingOriginalRename.References(updated)
        return after == PendingOriginalRename.References(profile) ? nil : after
    }

     
     
    nonisolated static func sourceIsShared(_ sourceID: String, besides id: String, in snapshot: ConfigurationLibrarySnapshot) -> Bool {
        snapshot.recipes.contains { $0.id != id && $0.dependencies.contains { $0.id == sourceID } }
            || snapshot.sources.contains { $0.nodeChain?.hops.contains { $0.source.id == sourceID } == true }
    }

     
     
     
     
    nonisolated static func record(_ current: ConfigurationSourceRecord,
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

     
     
    private func moveRecordedChoice(ofGroup oldName: String, to newName: String, in id: String) throws -> String? {
        guard let profileStore else { return nil }
        var moved: String?
        _ = try profileStore.updateIfPresent(id: id) { profile in
            guard let choice = profile.selectedMap.removeValue(forKey: oldName) else { return }
            profile.selectedMap[newName] = choice
            moved = choice
        }
        if moved != nil { load() }
        return moved
    }

     
     
     
     
    private func applyOwnReferences(_ after: PendingOriginalRename.References, over before: PendingOriginalRename.References,
                                    rename: (kind: ConfigurationReferenceKind, oldName: String, newName: String)?,
                                    in id: String) throws {
        guard let profileStore else { throw OriginalEditingError.gone }
        let written = try profileStore.updateIfPresent(id: id, when: { PendingOriginalRename.References($0) == before }) { profile in
            after.apply(to: &profile)
            if let rename, rename.kind == .proxyGroup {
                for (group, member) in profile.selectedMap where member == rename.oldName { profile.selectedMap[group] = rename.newName }
            }
        }
        guard written != nil else { throw OriginalEditingError.changedSinceRead }
    }

     
    private func putBackOwnReferences(_ before: PendingOriginalRename.References, from after: PendingOriginalRename.References,
                                      rename: (kind: ConfigurationReferenceKind, oldName: String, newName: String)?, in id: String) {
        _ = try? profileStore?.updateIfPresent(id: id, when: { PendingOriginalRename.References($0) == after }) { profile in
            before.apply(to: &profile)
            if let rename, rename.kind == .proxyGroup {
                for (group, member) in profile.selectedMap where member == rename.newName { profile.selectedMap[group] = rename.oldName }
            }
        }
    }

     
     
     
     
     
     
    func changeOriginalText(of id: String, readDigest: String?, own: OwnReferencesChange? = nil,
                            _ change: @escaping @Sendable (String) throws -> (String, Int)) async throws -> Int {
        guard let profile = profiles.first(where: { $0.id == id }) else { throw OriginalEditingError.gone }
        await settleLibraryHousekeeping()
        let label = profile.label
        if let library = configurationLibraryStore {
            for attempt in 1...3 {
                let snapshot = try await Task.detached(priority: .userInitiated) { try library.snapshot() }.value
                guard let recipe = snapshot.recipes.first(where: { $0.id == id }) else { break }
                guard recipe.preservesOriginal == true else { throw OriginalEditingError.composed }
                guard let current = snapshot.sources.first(where: { $0.id == recipe.ruleSource.id }) else {
                    throw OriginalEditingError.gone
                }
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                let kept = current.isRetainedSnapshot == true
                let followsLink: Bool = { if !kept, case .subscription = current.origin { return true }; return false }()
                if followsLink, !detachingLinkOriginals.contains(id) { throw OriginalEditingError.followsSubscription }
                 
                 
                 
                let ownCopy = followsLink || kept || (own?.rename != nil && Self.sourceIsShared(current.id, besides: id, in: snapshot))
                guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
                changingConfigurationLibrary = true
                defer { changingConfigurationLibrary = false }
                let latest = own == nil ? nil : try latestProfile(id)
                do {
                    let (plan, result, after) = try await Task.detached(priority: .userInitiated) {
                        () -> ((candidate: ConfigurationLibrarySnapshot, payloads: [ConfigurationSourcePayload],
                                compositions: [String: ConfigurationComposition]), Int, PendingOriginalRename.References?) in
                        let previous = try library.payload(recipe.ruleSource)
                        guard let text = String(data: previous.original, encoding: .utf8),
                              (try? ConfigTransforms.validateSource(text)) != nil else {
                            throw OriginalEditingError.notYAMLText
                        }
                        if let readDigest, Self.textDigest(text) != readDigest { throw OriginalEditingError.changedSinceRead }
                        let (edited, result) = try change(text)
                        let after = try latest.flatMap { try own?.make($0) }
                         
                         
                         
                        let bound = ConfigurationCenterSourceBridge.BoundInputs()
                        let computed = try ConfigurationCenterSourceBridge.payload(label: ownCopy ? label : current.label,
                            origin: ownCopy ? .file(label + ".yaml") : current.origin, original: Data(edited.utf8), yaml: edited,
                            id: ownCopy ? "edited-" + UUID().uuidString : current.id, bound: bound)
                        let record = ownCopy ? computed.record : Self.record(current, takingContentOf: computed.record)
                        let replacement = ConfigurationSourcePayload(record: record, original: computed.original,
                            documentJSON: computed.documentJSON, resourceFiles: previous.resourceFiles)
                        if ownCopy {
                            let prepared = try library.prepareOwnSourceCopy(id, replacement: replacement,
                                expectedGeneration: snapshot.generation, resolveInput: bound.resolve)
                            return ((prepared.candidate, prepared.payloads, [id: prepared.composition]), result, after)
                        }
                        let prepared = try library.prepareSourceUpdate(replacement, expectedGeneration: snapshot.generation,
                            updatingPinnedConsumers: true, resolveInput: bound.resolve)
                        return ((prepared.candidate, prepared.payloads, prepared.compositions), result, after)
                    }.value
                    try await saveChangedText(of: id, own: own, before: latest, after: after) {


                        try await self.saveConfigurationPlan(candidate: plan.candidate, payloads: plan.payloads,
                                                             compositions: plan.compositions, generation: snapshot.generation)
                    }
                    if followsLink { detachingLinkOriginals.remove(id) }
                    return result
                } catch ConfigurationLibraryError.staleGeneration where attempt < 3 {
                    continue
                }
            }
        }
         
         
        if case .url = profile.source { throw OriginalEditingError.followsSubscription }
        guard let text = await loadSourceYAML(for: profile) else { throw OriginalEditingError.gone }
        let latest = own == nil ? nil : try latestProfile(id)
        let (edited, result, after) = try await Task.detached(priority: .userInitiated) {
            if let readDigest, Self.textDigest(text) != readDigest { throw OriginalEditingError.changedSinceRead }
            let (edited, result) = try change(text)
            return (edited, result, try latest.flatMap { try own?.make($0) })
        }.value
        try await saveChangedText(of: id, own: own, before: latest, after: after) {
             
            try await self.updateEdited(self.latestProfile(id), sourceYAML: edited)
        }
        return result
    }

     
     
     
     
    private func saveChangedText(of id: String, own: OwnReferencesChange?, before profile: Profile?,
                                 after: PendingOriginalRename.References?, save: () async throws -> Void) async throws {
        guard let own, let profile, let after else { return try await save() }
        let before = PendingOriginalRename.References(profile)
        let pending = own.rename.map {
            PendingOriginalRename(profileID: id, kind: $0.kind, oldName: $0.oldName, newName: $0.newName, before: before, after: after)
        }
        if let pending { try recordPendingRename(pending) }
        do {
            try applyOwnReferences(after, over: before, rename: own.rename, in: id)
        } catch {
            if let pending { forgetPendingRename(pending) }
            throw error
        }
        do {
            try await save()
        } catch {
            putBackOwnReferences(before, from: after, rename: own.rename, in: id)
            if let pending { forgetPendingRename(pending) }
            load()
            throw error
        }
        if let pending { forgetPendingRename(pending) }
    }
}

 

extension ConfigurationReferenceKind: Codable {}

 
 
 
 
struct PendingOriginalRename: Codable, Equatable {
     
     
     
    struct References: Codable, Equatable {
        var override: OverrideSpec
        var migratedGlobalOverride: OverrideSpec?
        var legacyRuntimePatchJSON: String?
        var customOverwrite: CustomOverwriteSpec?
        var proxyChain: ProxyChainSpec?
        var proxyNodeOverrides: ProxyNodeOverrideSpec?
        var providerDefinitions: ProfileProviderDefinitionSpec?
        var legacyRelayMigrations: [LegacyRelayMigration]?

        init(_ profile: Profile) {
            override = profile.override
            migratedGlobalOverride = profile.migratedGlobalOverride
            legacyRuntimePatchJSON = profile.legacyRuntimePatchJSON
            customOverwrite = profile.customOverwrite
            proxyChain = profile.proxyChain
            proxyNodeOverrides = profile.proxyNodeOverrides
            providerDefinitions = profile.providerDefinitions
            legacyRelayMigrations = profile.legacyRelayMigrations
        }

        func apply(to profile: inout Profile) {
            profile.override = override
            profile.migratedGlobalOverride = migratedGlobalOverride
            profile.legacyRuntimePatchJSON = legacyRuntimePatchJSON
            profile.customOverwrite = customOverwrite
            profile.proxyChain = proxyChain
            profile.proxyNodeOverrides = proxyNodeOverrides
            profile.providerDefinitions = providerDefinitions
            profile.legacyRelayMigrations = legacyRelayMigrations
        }
    }

    var id = UUID().uuidString
    let profileID: String
    let kind: ConfigurationReferenceKind
    let oldName: String
    let newName: String
    let before: References
    let after: References
}

extension ProfilesViewModel {
    private var pendingRenamesDirectory: URL? {
        workingDir?.appendingPathComponent("pending-renames", isDirectory: true)
    }

    func recordPendingRename(_ rename: PendingOriginalRename) throws {
        guard let directory = pendingRenamesDirectory else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(rename).write(to: directory.appendingPathComponent(rename.id + ".json"), options: .atomic)
    }

    func forgetPendingRename(_ rename: PendingOriginalRename) {
        guard let directory = pendingRenamesDirectory else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(rename.id + ".json"))
    }

    func pendingRenames() -> [PendingOriginalRename] {
        guard let directory = pendingRenamesDirectory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        return names.filter { $0.hasSuffix(".json") }.sorted().compactMap { name in
            (try? Data(contentsOf: directory.appendingPathComponent(name)))
                .flatMap { try? JSONDecoder().decode(PendingOriginalRename.self, from: $0) }
        }
    }

     
     
     
     
    func reconcilePendingRenames() async {
        let renames = pendingRenames()
        guard !renames.isEmpty else { return }
        for rename in renames {
            defer { forgetPendingRename(rename) }
            guard let profile = try? latestProfile(rename.profileID), let text = await loadSourceYAML(for: profile) else { continue }
            let names = await Task.detached(priority: .userInitiated) {
                try? Self.definedNames(of: rename.kind, in: text)
            }.value
            guard let names, names.contains(rename.oldName), !names.contains(rename.newName) else { continue }
            putBackOwnReferences(rename.before, from: rename.after, rename: (rename.kind, rename.oldName, rename.newName),
                                 in: rename.profileID)
        }
        load()
    }

     
    nonisolated static func definedNames(of kind: ConfigurationReferenceKind, in text: String) throws -> Set<String> {
        let document = try OrderedJSON.parse(ConfigTransforms.yamlToJSON(text))
        switch kind {
        case .proxyGroup:
            guard case .array(let groups)? = document.topLevelValue("proxy-groups") else { return [] }
            return Set(groups.compactMap { if case .string(let name)? = $0.topLevelValue("name") { return name }; return nil })
        case .ruleProvider, .proxyProvider:
            guard case .object(let providers)? = document.topLevelValue(kind == .ruleProvider ? "rule-providers" : "proxy-providers")
            else { return [] }
            return Set(providers.map(\.key))
        }
    }
}

 
 
final class OriginalFileDigests: @unchecked Sendable {
    static let shared = OriginalFileDigests()
    private let lock = NSLock()
    private var known: [String: (identity: String, digest: String)] = [:]

    static func identity(of url: URL) -> String? {
        var status = stat()
        guard stat(url.path, &status) == 0 else { return nil }
        return "\(status.st_dev)|\(status.st_ino)|\(status.st_size)|"
            + "\(status.st_mtimespec.tv_sec).\(status.st_mtimespec.tv_nsec)|"
            + "\(status.st_ctimespec.tv_sec).\(status.st_ctimespec.tv_nsec)"
    }

    func digest(of path: String, identity: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = known[path], entry.identity == identity else { return nil }
        return entry.digest
    }

    func record(_ digest: String, of path: String, identity: String) {
        lock.lock(); defer { lock.unlock() }
         
        if known.count >= 16 { known.removeAll() }
        known[path] = (identity, digest)
    }
}
