import CryptoKit
import Foundation
import Clash
import ClashClientKit

 
 
enum ConfigurationCenterSourceBridge {
     
     
     
    static func fetch(url: String, label: String, credentials: CredentialStore, downloader: HTTPFetching = ResourceDownloader(),
                      nodesOnly: Bool = false, unreadBody: ((Data) -> Void)? = nil) async throws -> ConfigurationSourcePayload {
        let id = UUID().uuidString
        let profile = Profile(id:id,label:label,source:.url(url),autoUpdate:true,
            updateIntervalHours:12,subscriptionInfo:nil,selectedMap:[:],override:OverrideSpec(),
            activeRevision:nil,order:0,lastUpdatedAt:nil)
         
         
        let manager = SubscriptionManager(downloader: downloader, credentials: credentials)
        guard let fetched = try await manager.fetch(profile:profile,useConditionalValidators:false,nodesOnly:nodesOnly,
                                                    unreadBody:unreadBody) else {
            throw PipelineError.sourceUnavailable("The profile URL returned no YAML.")
        }
        let proposed = label.trimmingCharacters(in:.whitespacesAndNewlines)
        let resolvedLabel = proposed.isEmpty ? (fetched.suggestedName ?? URL(string:url)?.host ?? "Profile URL") : proposed
        return try await Task.detached(priority:.userInitiated) {
            var result = try ConfigurationCenterSourceBridge.payload(label:resolvedLabel,origin:.subscription(url),
                original:fetched.rawSource,yaml:fetched.yaml,id:id)
            result.record.updateIntervalHours = 24
            result.record.subscriptionUsage = fetched.subscriptionInfo.map(subscriptionUsage)
            return result
        }.value
    }

    static func subscriptionUsage(_ info: SubscriptionInfo) -> ConfigurationSubscriptionUsage {
        .init(upload: info.upload, download: info.download, total: info.total, expire: info.expire)
    }

     
     
    static func profileOrigin(recipe: ConfigurationRecipe, in snapshot: ConfigurationLibrarySnapshot) -> Profile.Source {
        guard recipe.sources.count == 1, let reference = recipe.sources.first,
              let record = snapshot.sources.first(where: { $0.id == reference.id }),
              case let .subscription(link) = record.origin, !link.isEmpty else { return .clipboard }
        return .url(link)
    }
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func adopting(_ existing: ConfigurationSourceRecord, fetched: ConfigurationSourcePayload) -> ConfigurationSourcePayload {
        var record = ConfigurationSourceRecord(id: existing.id, label: existing.label, origin: existing.origin,
            version: fetched.record.version, nodeCount: fetched.record.nodeCount,
            providerCount: fetched.record.providerCount, groupCount: fetched.record.groupCount,
            ruleCount: fetched.record.ruleCount, suppliesNodes: existing.suppliesNodes,
            updatedAt: fetched.record.updatedAt, updateIntervalHours: existing.updateIntervalHours,
            userAgent: existing.userAgent, dnsOverHTTPS: existing.dnsOverHTTPS,
            registersSuppliedRules: existing.registersSuppliedRules)
        record.ruleProviderCount = fetched.record.ruleProviderCount
        record.subscriptionUsage = fetched.record.subscriptionUsage
         
        record.rulesWrittenInOriginal = fetched.record.rulesWrittenInOriginal
        return ConfigurationSourcePayload(record: record, original: fetched.original,
            documentJSON: fetched.documentJSON, resourceFiles: fetched.resourceFiles)
    }

    static func refreshBroughtNothingNew(previous: ConfigurationSourcePayload, fetched: ConfigurationSourcePayload) -> Bool {
        previous.original == fetched.original && previous.documentJSON == fetched.documentJSON
    }

     
     
     
    static func noted(_ record: ConfigurationSourceRecord, refreshedAt fetched: ConfigurationSourceRecord) -> ConfigurationSourceRecord {
        var noted = record
        noted.updatedAt = fetched.updatedAt
        noted.subscriptionUsage = fetched.subscriptionUsage
        return noted
    }

     
     
     
     
    static func noteUnchangedRefresh(_ record: ConfigurationSourceRecord, in library: ConfigurationLibraryStore,
                                     expectedGeneration: UInt64) throws {
        var candidate = try library.snapshot()
        guard candidate.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        guard let index = candidate.sources.firstIndex(where: { $0.id == record.id }) else {
            throw ConfigurationLibraryError.missingDependency(record.id)
        }
        candidate.sources[index] = record
        _ = try library.commit(candidate, payloads: [], expectedGeneration: expectedGeneration)
    }

    static func prepareReplacements(compositions: [String: ConfigurationComposition], planned: ConfigurationLibrarySnapshot,
                                    payloads: [ConfigurationSourcePayload], library: ConfigurationLibraryStore,
                                    originals: [Profile], workingDir: URL, rename: String? = nil) throws -> [ConfigurationCenterPublicationBridge.Replacement] {
            try compositions.keys.sorted().map { id -> ConfigurationCenterPublicationBridge.Replacement in
                guard let previous = originals.first(where: { $0.id == id }),
                      let recipe = planned.recipes.first(where: { $0.id == id }),
                      let composition = compositions[id] else { throw ConfigurationLibraryError.missingDependency(id) }
                 
                let plannedFiles = (source: ConfigurationCenterPublicationBridge.FileFingerprint(
                    ProfileSourceStore.runnableURL(workingDirectory: workingDir, profileID: id)),
                    resources: ConfigurationCenterPublicationBridge.FileFingerprint(
                        workingDir.appendingPathComponent("store/\(id)/resources", isDirectory: true)))
                let prior = try String(contentsOf: ProfileSourceStore.runnableURL(workingDirectory: workingDir,
                    profileID: id), encoding: .utf8)
                var next = previous
                 
                 
                 
                 
                 
                 
                 
                next.source = ConfigurationCenterSourceBridge.profileOrigin(recipe: recipe, in: planned)
                next.autoUpdate = false
                next.subscriptionInfo = nil
                if id == rename { next.label = recipe.label; next.labelIsUserAssigned = true }
                let files = try Set(recipe.dependencies).flatMap { reference in
                    let payload = try payloads.first(where: { ConfigurationSourceVersion($0.record) == reference })
                        ?? library.payload(reference)
                    return ConfigurationCenterSourceBridge.boundFiles(payload)
                }
                let yaml = try publicationYAML(composition, recipe: recipe) { reference in
                    try payloads.first(where: { ConfigurationSourceVersion($0.record) == reference }) ?? library.payload(reference)
                }
                 
                 
                 
                 
                 
                 
                if ConfigTransforms.keepsLargeRuleLines(yaml) {
                    try ConfigTransforms.validateSource(yaml)
                } else {
                    try ConfigTransforms.validateSourceRemembering(yaml)
                }
                let resources = try ProfileExternalResourceImporter.prepareLeavingPaths(yaml: yaml,
                    mapping: composition.document, profileID: id, source: .localFile, files: files)
                next.externalResources = resources.references.isEmpty ? nil : resources.references
                 
                 
                 
                 
                return .init(previous: previous, profile: next, previousYAML: prior,
                    yaml: resources.yaml, resources: resources.publicResources, planned: plannedFiles)
            }
    }

     
     
     
     
     
    static func refreshDueSources(container: URL, now: Date,
                                  downloader: HTTPFetching = ResourceDownloader(),
                                  refusals: UserDefaults = ConfigurationSourceRefusals.appGroup) async -> BackgroundRefreshOutcome {
        var outcome = BackgroundRefreshOutcome()
        let working = container.appendingPathComponent("working")
        let directory = working.appendingPathComponent("configuration-library")
#if canImport(UIKit)
        let library = ConfigurationLibraryStore(directory: directory, beginAccess: ConfigStoreSuspensionShield.beginLibraryAccess)
#else
        let library = ConfigurationLibraryStore(directory: directory)
#endif
        do {
            _ = try await Task.detached(priority: .userInitiated) {
                try ConfigurationCenterPublicationBridge.recoverReplacements(library: library, workingDir: working)
            }.value
            let initial = try await Task.detached {
                let profiles = ProfileStore(fileURL: working.appendingPathComponent("store/profiles.json"))
                try ConfigurationCenterPublicationBridge.reconcileDeletedProfiles(library: library, profileStore: profiles)
                return try library.snapshot()
            }.value
            let due = ConfigurationSourcesDueForRefresh.select(sources: initial.availableSources, now: now)
            let credentials = CredentialStore()
            for source in due {
                if Task.isCancelled { outcome.cancelled = true; return outcome }
                outcome.attempted += 1
                do {
                    let current = try await Task.detached { try library.snapshot() }.value
                    guard let latest = current.sources.first(where: { $0.id == source.id }), latest == source,
                          case .subscription(let url) = latest.origin else { outcome.unchanged += 1; continue }
                    let fetched = try await fetch(url: url, label: latest.label, credentials: credentials, downloader: downloader)
                    let previous = try await Task.detached { try library.payload(.init(latest)) }.value
                    if Self.refreshBroughtNothingNew(previous: previous, fetched: fetched) {
                         
                        let noted = Self.noted(latest, refreshedAt: fetched.record)
                        try await Task.detached {
                            try Self.noteUnchangedRefresh(noted, in: library, expectedGeneration: current.generation)
                        }.value
                        outcome.unchanged += 1
                        ConfigurationSourceRefusals.clearAfterUnchangedRefresh(source.id,
                            pageStillTaken: current.hasSchemeTakingPage(fromSource: source.id), in: refusals)
                         
                         
                         
                        await backfillImportedPage(of: source.id, library: library, container: container,
                            working: working, credentials: credentials, downloader: downloader, now: now,
                            refusals: refusals, outcome: &outcome)
                        continue
                    }
                    let prepared = try await Task.detached { () -> (PreparedConfigurationSourceUpdate, [ConfigurationCenterPublicationBridge.Replacement]) in
                        var record = latest
                        record.version = fetched.record.version; record.updatedAt = fetched.record.updatedAt
                        record.nodeCount = fetched.record.nodeCount; record.providerCount = fetched.record.providerCount
                        record.groupCount = fetched.record.groupCount; record.ruleCount = fetched.record.ruleCount
                        record.ruleProviderCount = fetched.record.ruleProviderCount
                        record.subscriptionUsage = fetched.record.subscriptionUsage
                         
                        record.rulesWrittenInOriginal = fetched.record.rulesWrittenInOriginal
                        let replacement = ConfigurationSourcePayload(record: record, original: fetched.original,
                            documentJSON: fetched.documentJSON, resourceFiles: previous.resourceFiles)
                        let plan = try library.prepareSourceUpdate(replacement, expectedGeneration: current.generation,
                            resolveInput: boundInput)
                        let originals = ProfileStore(fileURL: working.appendingPathComponent("store/profiles.json")).load()
                        let replacements = try prepareReplacements(compositions: plan.compositions, planned: plan.candidate,
                            payloads: plan.payloads, library: library, originals: originals, workingDir: working)
                        return (plan, replacements)
                    }.value
                    try Task.checkCancellation()
                     
                     
                     
                     
                     
                    let recomposedIDs = Set(prepared.0.compositions.keys)
                     
                     
                     
                     
                     
                     
                    try Task.checkCancellation()
                    try await ConfigurationCenterPublicationBridge.replaceOffMain(prepared.1, candidate: prepared.0.candidate,
                        payloads: prepared.0.payloads, library: library, workingDir: working, expectedGeneration: current.generation)
                    outcome.updated += 1
                    ConfigurationSourceRefusals.clear(source.id, in: refusals)
                    ConfigurationSourceRefusals.record(prepared.0.pageRefusals, in: refusals)
                     
                     
                     
                     
                     
                     
                    await restageInUseIfRecomposed(recomposedIDs, container: container, working: working,
                        credentials: credentials, downloader: downloader, now: now, outcome: &outcome)
                } catch {
                     
                    ConfigurationSourceRefusals.note(error, sourceID: source.id, in: refusals)
                    outcome.record(error)
                }
            }
        } catch { outcome.record(error) }
        if outcome.updated > 0 {
            await MainActor.run {
                NotificationCenter.default.post(name: .clashConfigurationSourcesRefreshed, object: nil)
            }
        }
        return outcome
    }

     
     
     
     
     
    private static func backfillImportedPage(of sourceID: String, library: ConfigurationLibraryStore, container: URL,
                                             working: URL, credentials: CredentialStore, downloader: HTTPFetching,
                                             now: Date, refusals: UserDefaults,
                                             outcome: inout BackgroundRefreshOutcome) async {
        do {
            let prepared = try await Task.detached { () -> (UInt64, PreparedConfigurationSourceUpdate, [ConfigurationCenterPublicationBridge.Replacement])? in
                let current = try library.snapshot()
                guard let plan = try library.prepareImportedPageBackfill(sourceID: sourceID,
                    expectedGeneration: current.generation, resolveInput: boundInput) else { return nil }
                let originals = ProfileStore(fileURL: working.appendingPathComponent("store/profiles.json")).load()
                let replacements = try prepareReplacements(compositions: plan.compositions, planned: plan.candidate,
                    payloads: plan.payloads, library: library, originals: originals, workingDir: working)
                return (current.generation, plan, replacements)
            }.value
            guard let (generation, plan, replacements) = prepared else { return }
            try Task.checkCancellation()
            try await ConfigurationCenterPublicationBridge.replaceOffMain(replacements, candidate: plan.candidate,
                payloads: plan.payloads, library: library, workingDir: working, expectedGeneration: generation)
             
            ConfigurationSourceRefusals.clear(sourceID, in: refusals)
            await restageInUseIfRecomposed(Set(plan.compositions.keys), container: container, working: working,
                credentials: credentials, downloader: downloader, now: now, outcome: &outcome)
        } catch let refusal as ConfigurationSchemePageRefusal {
            ConfigurationSourceRefusals.record(refusal.reason, sourceID: refusal.sourceID, in: refusals)
        } catch {
            outcome.record(error)
        }
    }

     
     
     
     
    private static func restageInUseIfRecomposed(_ recomposedIDs: Set<String>, container: URL, working: URL,
                                                 credentials: CredentialStore, downloader: HTTPFetching,
                                                 now: Date, outcome: inout BackgroundRefreshOutcome) async {
        guard let store = try? ConfigResourceStore(containerURL: container),
              let active = try? store.activePointer(), recomposedIDs.contains(active.profileID) else { return }
        let profileStore = ProfileStore(fileURL: working.appendingPathComponent("store/profiles.json"))
        guard let profile = profileStore.load().first(where: { $0.id == active.profileID }),
              let document = try? String(contentsOf: ProfileSourceStore.runnableURL(workingDirectory: working,
                  profileID: active.profileID), encoding: .utf8) else { return }
        do {
            let coordinator = ProfileActivationCoordinator(
                store: store, profileStore: profileStore, credentials: credentials,
                downloader: downloader, coreHomeDir: working,
                compileRuleSets: false, activator: { _ in }, now: { now })
             
             
             
            _ = try await coordinator.activate(profile: profile, sourceYAML: document, onlyIfActive: active)
        } catch is CancellationError {
            outcome.cancelled = true
        } catch where ProfileActivationCoordinator.lostToASwitch(error)
                        || ProfileActivationCoordinator.superseded(error) {
             
             
        } catch {
            outcome.record(error)
        }
    }

     
     
     
     
     
     
     
    static func nodeMaterialPayload(label: String, yaml: String) throws -> ConfigurationSourcePayload? {
        guard let root = ConfigTransforms.parsedRoot(forYAML: yaml)?.root, root.count == 1,
              let proxies = root["proxies"] as? [[String: Any]], !proxies.isEmpty else { return nil }
        let names = proxies.compactMap { $0["name"] as? String }
        return try payload(label: label.isEmpty ? (names.count == 1 ? names[0] : ConfigurationBuiltins.customNodesName) : label,
                           origin: .customNodes, original: Data(yaml.utf8), yaml: yaml)
    }

    static func payload(
        label: String, origin: ConfigurationSourceRecord.Origin,
        original: Data, yaml: String? = nil,
        resources: [ExternalResourceImportFile] = [],
        id: String = UUID().uuidString, version: String = UUID().uuidString,
        bound: BoundInputs? = nil, nodesOnly: Bool = false
    ) throws -> ConfigurationSourcePayload {
        let yaml = try yaml ?? ProxyImportBridge.derivedSubscription(from:original, nodesOnly: nodesOnly).yaml
         
         
         
         
         
         
         
        let keptRules = try documentKeepingRulesInOriginal(yaml, original: original)
        let json = try keptRules?.json ?? ConfigTransforms.validatedJSON(yaml)
        guard let document = try OrderedJSON.topLevel(json) else {
            throw ProfileExternalResourceError.invalidConfiguration
        }
        func count(_ key: String) -> Int { key == "rules" ? keptRules?.count ?? document.count(key) : document.count(key) }
        var files: [String: Data] = [:]
        for resource in resources {
            if let existing = files[resource.fileName], existing != resource.data {
                throw ProfileExternalResourceError.ambiguousSelection(field:resource.fileName)
            }
            files[resource.fileName] = resource.data
        }
        var record = ConfigurationSourceRecord(id:id,label:label,origin:origin,version:version,
            nodeCount:count("proxies"),providerCount:count("proxy-providers"),
            groupCount:count("proxy-groups"),ruleCount:count("rules"), suppliesNodes: count("proxies") > 0 || count("proxy-providers") > 0)
        record.ruleProviderCount = count("rule-providers")
        if keptRules != nil { record.rulesWrittenInOriginal = true }
        let payload = ConfigurationSourcePayload(record:record,original:original,documentJSON:json,
            resourceFiles:files.isEmpty ? nil : files)
         
         
         
         
         
         
        if let bound { _ = try bound.resolve(payload) } else if !files.isEmpty { _ = try boundInput(payload) }
        return payload
    }

     
     
     
     
     
     
     
     
     
    static func documentKeepingRulesInOriginal(_ yaml: String, original: Data) throws -> (json: String, count: Int)? {
        guard yaml.utf8.count >= ConfigTransforms.ruleSectionCutFromBytes, original.count == yaml.utf8.count,
              ConfigTransforms.hasLargeRuleSection(yaml), sameBytes(original, yaml),
              let cut = TopLevelYAMLSections.cutting(["rules"], from: yaml), let section = cut.sectionText("rules"),
              section.utf8.count >= ConfigTransforms.ruleSectionCutFromBytes,
              let lines = RuleLines(section) else { return nil }
        try ConfigTransforms.validateSource(yaml)
        AppCore.returnFreeMemoryNow(after: yaml)
         
         
         
         
         
        let json = try ConfigTransforms.yamlToJSON(cut.rest)
        AppCore.returnFreeMemoryNow(after: yaml)
        return (json, lines.count)
    }

    private static func sameBytes(_ data: Data, _ text: String) -> Bool {
        var text = text
        return text.withUTF8 { bytes in
            data.withUnsafeBytes { raw in
                raw.count == bytes.count && (raw.count == 0 || memcmp(raw.baseAddress!, bytes.baseAddress!, raw.count) == 0)
            }
        }
    }

     
     
     
     
     
     
    static func publicationYAML(_ composition: ConfigurationComposition, recipe: ConfigurationRecipe?,
                                payload: (ConfigurationSourceVersion) throws -> ConfigurationSourcePayload) throws -> String {
         
        guard composition.document.topLevelValue("rules") == nil, let recipe else {
            return try ConfigTransforms.yamlWritingNodesALine(composition.document)
        }
         
         
         
         
        let source = try payload(recipe.ruleSource)
        guard source.record.rulesWrittenInOriginal == true else {
            return try ConfigTransforms.yamlWritingNodesALine(composition.document)
        }
        guard recipe.preservesOriginal == true, let text = String(data: source.original, encoding: .utf8),
              let cut = TopLevelYAMLSections.cutting(["rules"], from: text), cut.sectionText("rules") != nil else {
            throw ConfigurationCompositionError.rulesRunOnlyAsTheOriginal(source: source.record.id)
        }
        if let asItCame = try? OrderedJSON.parse(source.documentJSON), asItCame == composition.document { return text }
        guard let spliced = cut.splicing(into: try ConfigTransforms.yamlWritingNodesALine(composition.document)) else {
            throw ConfigurationCompositionError.rulesRunOnlyAsTheOriginal(source: source.record.id)
        }
        return spliced
    }

    static func boundFiles(_ payload: ConfigurationSourcePayload) -> [ExternalResourceImportFile] {
        (payload.resourceFiles ?? [:]).map { name, data in
            .init(fileName:boundName(name,source:payload.record),data:data)
        }
    }

     
     
    static func withValidationResources<T>(
        yaml: String, files: [ExternalResourceImportFile], directory: URL,
        check: (String) throws -> T
    ) throws -> T {
         
         
         
        try BundledGeodataProvisioner.seedAllMissing(into: directory)
        var document = try OrderedJSON.parse(ConfigTransforms.yamlToJSON(yaml))
        guard let root = document.foundationValue as? [String: Any] else {
            throw ProfileExternalResourceError.invalidConfiguration
        }
        let requirements = IOSExternalResourceCatalog.requirements(root:root)
            .filter { $0.capability.confidentiality == .publicData }
        guard !requirements.isEmpty else { return try check(yaml) }
        let folder = directory.appendingPathComponent("configuration-validation-" + UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        for requirement in requirements {
            let name = URL(fileURLWithPath:requirement.rawValue).lastPathComponent
             
             
            guard let file = files.first(where: { $0.fileName == name }) else { continue }
            let destination = folder.appendingPathComponent(name)
            try file.data.write(to:destination,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
            document = try binding(document,requirement:requirement,path:destination.path)
        }
        return try check(ConfigTransforms.jsonToYAML(document.serialized()))
    }

    private static func binding(_ document: OrderedJSON, requirement: IOSExternalResourceRequirement,
                                path: String) throws -> OrderedJSON {
        switch requirement.capability.section {
        case .proxy:
            guard case .array(var nodes)? = document.topLevelValue("proxies"),
                  let index = nodes.firstIndex(where: { $0.topLevelValue("name") == .string(requirement.proxyName) }) else {
                throw ProfileExternalResourceError.invalidConfiguration
            }
            nodes[index] = nodes[index].setting(path:requirement.capability.fieldPath,to:.string(path))
            return document.settingTopLevel("proxies",to:.array(nodes))
        case .proxyProvider, .ruleProvider:
            let section = requirement.capability.section == .proxyProvider ? "proxy-providers" : "rule-providers"
            return document.setting(path:[section,requirement.proxyName] + requirement.capability.fieldPath,to:.string(path))
        }
    }

    static func boundInput(_ payload: ConfigurationSourcePayload) throws -> ConfigurationInput {
        try boundInput(payload, parsed: nil)
    }

     
    static func boundInput(_ payload: ConfigurationSourcePayload, parsed: OrderedJSON?) throws -> ConfigurationInput {
        let original = try parsed ?? OrderedJSON.parse(payload.documentJSON)
        var document: OrderedJSON
        if payload.record.rulesWrittenInOriginal == true, (payload.resourceFiles ?? [:]).isEmpty, case .object = original {
             
             
             
             
            document = original
        } else {
            let yaml = try ConfigTransforms.jsonToYAML(payload.documentJSON)
            let origin: IOSExternalResourceSource
            switch payload.record.origin {
            case .subscription: origin = .subscription
            case .file: origin = .localFile
            case .customNodes, .bundled: origin = .clipboard
            }
            let files = (payload.resourceFiles ?? [:]).map { ExternalResourceImportFile(fileName:$0.key,data:$0.value) }
            let prepared = try ProfileExternalResourceImporter.prepareLeavingPaths(yaml:yaml,mapping:original,
                profileID:payload.record.id,source:origin,files:files)
            document = try OrderedJSON.parse(ConfigTransforms.yamlToJSON(prepared.yaml))
                .reorderingMappings(following:original)
        }
        guard let root = document.foundationValue as? [String: Any] else {
            throw ProfileExternalResourceError.invalidConfiguration
        }
        var paths: [String: String] = [:]
        for requirement in IOSExternalResourceCatalog.requirements(root:root)
        where requirement.capability.confidentiality == .publicData {
            let basename = URL(fileURLWithPath:requirement.rawValue.replacingOccurrences(of:"\\",with:"/")).lastPathComponent
            let names = (payload.resourceFiles ?? [:]).keys.filter { $0.lowercased() == basename.lowercased() }
            paths[requirement.rawValue] = requirement.rawValue
            guard !names.isEmpty else { continue }
            guard names.count == 1, let name = names.first else {
                throw ProfileExternalResourceError.ambiguousSelection(field:requirement.capability.fieldPath.joined(separator:"."))
            }
            let bound = "./" + boundName(name,source:payload.record)
            paths[requirement.rawValue] = bound
            paths[bound] = bound
            document = try binding(document,requirement:requirement,path:bound)
        }
        return ConfigurationInput(id:payload.record.id,document:document,resourcePaths:paths,
            hiddenNodeNames: payload.record.nodeChain == nil ? [] : [ConfigurationNodeChain.entryName(for: payload.record.id)],
            rulesWrittenInOriginal: payload.record.rulesWrittenInOriginal == true)
    }

     
     
     
     
     
     
     
     
    final class BoundInputs: @unchecked Sendable {
        private struct Key: Equatable {
            let id: String
            let version: String
            let origin: ConfigurationSourceRecord.Origin
            let chained: Bool
            let documentJSON: String
            let resourceFiles: [String: Data]?

            init(_ payload: ConfigurationSourcePayload) {
                id = payload.record.id
                version = payload.record.version
                origin = payload.record.origin
                chained = payload.record.nodeChain != nil
                documentJSON = payload.documentJSON
                resourceFiles = payload.resourceFiles
            }
        }

        private let lock = NSLock()
        private var made: [(key: Key, input: ConfigurationInput)] = []

        func resolve(_ payload: ConfigurationSourcePayload) throws -> ConfigurationInput {
            try resolve(payload, parsed: nil)
        }

        func resolve(_ payload: ConfigurationSourcePayload, parsed: OrderedJSON?) throws -> ConfigurationInput {
            let key = Key(payload)
            lock.lock()
            let hit = made.first { $0.key == key }?.input
            lock.unlock()
            if let hit { return hit }
            let input = try ConfigurationCenterSourceBridge.boundInput(payload, parsed: parsed)
            lock.lock(); made.append((key, input)); lock.unlock()
            return input
        }
    }

    static func capturedFiles(profile: Profile, yaml: String, workingDir: URL) throws -> [ExternalResourceImportFile] {
        guard !(profile.externalResources ?? []).isEmpty else { return [] }
        let document = try OrderedJSON.parse(ConfigTransforms.yamlToJSON(yaml))
        guard let root = document.foundationValue as? [String: Any] else { throw ProfileExternalResourceError.invalidConfiguration }
        var files: [ExternalResourceImportFile] = []
        for requirement in IOSExternalResourceCatalog.requirements(root:root)
        where requirement.capability.confidentiality == .publicData {
            let reference = ProfileExternalResourceImporter.reference(profileID:profile.id,requirement:requirement)
            guard profile.externalResources?.contains(reference) == true else { continue }
            let file = workingDir.appendingPathComponent("store/\(profile.id)/resources/\(reference.storageKey)")
            let name = URL(fileURLWithPath:requirement.rawValue.replacingOccurrences(of:"\\",with:"/")).lastPathComponent
            files.append(.init(fileName:name,data:try Data(contentsOf:file)))
        }
        return files
    }

    private static func boundName(_ name: String, source: ConfigurationSourceRecord) -> String {
        let key = source.id + "\0" + source.version + "\0" + name
        let hash = SHA256.hash(data:Data(key.utf8)).map { String(format:"%02x",$0) }.joined()
        let suffix = URL(fileURLWithPath:name).pathExtension.lowercased()
        return "cc-" + hash + (suffix.isEmpty ? "" : "." + String(suffix.prefix(16)))
    }
}

 
 
 
enum ConfigurationLegacyRegistration {
    static func prepare(profile: Profile, snapshot: ConfigurationLibrarySnapshot,
                        load: () throws -> ConfigurationSourcePayload) throws
        -> (snapshot: ConfigurationLibrarySnapshot, payloads: [ConfigurationSourcePayload])? {
        guard profile.id != LocalDefaultProfileProvisioner.profileID,
              !(snapshot.registeredLegacyProfileIDs ?? []).contains(profile.id),
              !snapshot.recipes.contains(where: { $0.id == profile.id }) else { return nil }
        let sourceID = "legacy-" + profile.id
        var next = snapshot
        var payloads: [ConfigurationSourcePayload] = []
        let record: ConfigurationSourceRecord
        if let existing = snapshot.sources.first(where: { $0.id == sourceID }) {
            record = existing
        } else {
            var payload = try load()
            guard payload.record.id == sourceID else { throw ConfigurationLibraryError.invalidIdentifier }
            payload.record.registersSuppliedRules = true
            record = payload.record
            next.sources.append(record)
            payloads.append(payload)
        }
        if record.hasRules && !next.rules.contains(where: { $0.id == "rules-" + sourceID }) {
            next.rules.append(.init(id: "rules-" + sourceID, label: record.label, kind: .supplied, sourceID: sourceID))
        }
        next.registeredLegacyProfileIDs = (next.registeredLegacyProfileIDs ?? []) + [profile.id]
        return (next, payloads)
    }

     
     
    static func payload(profile: Profile, workingDir: URL) throws -> ConfigurationSourcePayload {
         
         
        guard !PlaintextSourceMigration.needsConversion(profile) else {
            throw PipelineError.sourceUnavailable(
                "A required credential is missing, invalid, or conflicts with the proxy identity.")
        }
        let yaml = try String(contentsOf: ProfileSourceStore.runnableURL(workingDirectory: workingDir,
            profileID: profile.id), encoding: .utf8)
        let origin: ConfigurationSourceRecord.Origin
        switch profile.source {
        case .url(let url): origin = .subscription(url)
        case .file(let file): origin = .file(file)
        case .clipboard: origin = .file(profile.label + ".yaml")
        }
        let original = Data((ProfileSourceStore.capturedText(workingDirectory: workingDir,
            profileID: profile.id) ?? yaml).utf8)
        let files = try ConfigurationCenterSourceBridge.capturedFiles(profile: profile, yaml: yaml, workingDir: workingDir)
        var payload = try ConfigurationCenterSourceBridge.payload(label: profile.label, origin: origin,
            original: original, yaml: yaml, resources: files, id: "legacy-" + profile.id)
        if case .subscription = origin {
            payload.record.updateIntervalHours = profile.autoUpdate ? profile.updateIntervalHours : nil
            payload.record.subscriptionUsage = profile.subscriptionInfo.map(ConfigurationCenterSourceBridge.subscriptionUsage)
        }
        return payload
    }

    static func customNodeSourceID(for profileID: String) -> String { "legacy-nodes-" + profileID }

     
     
     
     
     
     
     
     
     
    static func prepareCustomNodes(profile: Profile, snapshot: ConfigurationLibrarySnapshot,
                                   load: () throws -> ConfigurationSourcePayload?) throws
        -> (snapshot: ConfigurationLibrarySnapshot, payloads: [ConfigurationSourcePayload])? {
        guard !(snapshot.registeredLegacyNodeProfileIDs ?? []).contains(profile.id) else { return nil }
        let sourceID = customNodeSourceID(for: profile.id)
        var next = snapshot
        var payloads: [ConfigurationSourcePayload] = []
        if !snapshot.sources.contains(where: { $0.id == sourceID }) {
             
             
            guard let payload = try load() else { return nil }
            guard payload.record.id == sourceID, payload.record.origin == .customNodes else {
                throw ConfigurationLibraryError.invalidIdentifier
            }
            next.sources.append(payload.record)
            payloads.append(payload)
        }
        next.registeredLegacyNodeProfileIDs = (next.registeredLegacyNodeProfileIDs ?? []) + [profile.id]
        return (next, payloads)
    }

     
     
     
     
     
     
     
    static func customNodePayload(profile: Profile, workingDir: URL) throws -> ConfigurationSourcePayload? {
        guard let definition = profile.providerDefinitions?.proxyProviders
                .first(where: { $0.name == CustomNodePayload.providerName })?.definitionJSON else { return nil }
        guard !(try CustomNodePayload.payload(inDefinition: definition)).isEmpty,
              case .array(let nodes)? = try OrderedJSON.parse(definition).topLevelValue("payload") else { return nil }
        let yaml = try ConfigTransforms.jsonToYAML(OrderedJSON.object([(key: "proxies", value: .array(nodes))]).serialized())
        let files = try ConfigurationCenterSourceBridge.capturedFiles(profile: profile, yaml: yaml, workingDir: workingDir)
        return try ConfigurationCenterSourceBridge.payload(label: profile.label, origin: .customNodes,
            original: Data(yaml.utf8), yaml: yaml, resources: files, id: customNodeSourceID(for: profile.id))
    }
}

 
 
 
enum ConfigurationCollectionContentBridge {
    struct BatchResult {
        var updated = 0
        var failures: [String] = []
         
        var updatedEntries: [ConfigurationCollectionEntry] = []
         
         
         
         
         
        var targets: [ConfigurationCollectionEntry] = []
         
         
         
         
         
        var coreOwned: [ConfigurationCollectionEntry] = []
         
         
        static func plainLine(_ subject: String?, _ error: Error) -> String {
            subject.map { $0 + ": " } .map { $0 + error.localizedDescription } ?? error.localizedDescription
        }
         
        var failedEntries: [ConfigurationCollectionEntry] {
            let updated = Set(updatedEntries.map(\.id))
            return targets.filter { !updated.contains($0.id) }
        }
    }
     
     
     
    static let concurrentCollectionUpdates = 4
    enum NodeUpdatePhase { case sources, collections }
     
     
     
     
     
     
     
    static func updateNodeLibrary(_ sources: [ConfigurationSourceRecord],
        updateSource: (ConfigurationSourceRecord) async throws -> Void,
        collections: () async throws -> [ConfigurationCollectionEntry],
        updateCollection: (ConfigurationCollectionEntry) async throws -> Void,
        progress: (NodeUpdatePhase, Int, Int, String) async -> Void,
        naming: (ConfigurationSourceRecord) -> String = \.label,
        describe: (_ subject: String?, _ error: Error) -> String = BatchResult.plainLine) async -> BatchResult {
        var seen = Set<String>()
        let targets = sources.filter { source in
            guard source.suppliesNodes, source.isRetainedSnapshot != true,
                  case .subscription = source.origin else { return false }
            return seen.insert(source.id).inserted
        }
        var result = BatchResult()
        for (index, source) in targets.enumerated() {
            if Task.isCancelled { return result }
            await progress(.sources, index + 1, targets.count, naming(source))
            do { try await updateSource(source); result.updated += 1 }
            catch is CancellationError { return result }
            catch { result.failures.append(describe(naming(source), error)) }
        }
        if Task.isCancelled { return result }
        do {
             
             
            let entries = try await collections()
            let downloaded = await updateCollections(entries, kind: .nodes, update: updateCollection,
                progress: { index, total, name in await progress(.collections, index, total, name) },
                naming: naming, describe: describe)
            result.updated += downloaded.updated
            result.failures += downloaded.failures
            result.updatedEntries += downloaded.updatedEntries
            result.targets += downloaded.targets
             
             
            result.coreOwned += downloaded.coreOwned
        } catch { result.failures.append(describe(nil, error)) }
        return result
    }
     
     
    static func updateNodeCollections(_ entries: [ConfigurationCollectionEntry],
        update: (ConfigurationCollectionEntry) async throws -> Void,
        progress: (Int, Int, String) async -> Void = { _, _, _ in },
        naming: (ConfigurationSourceRecord) -> String = \.label,
        describe: (_ subject: String?, _ error: Error) -> String = BatchResult.plainLine) async -> BatchResult {
        await updateCollections(entries, kind: .nodes, update: update, progress: progress, naming: naming, describe: describe)
    }
    static func updateRuleCollections(_ entries: [ConfigurationCollectionEntry],
        update: (ConfigurationCollectionEntry) async throws -> Void,
        progress: (Int, Int, String) async -> Void,
        naming: (ConfigurationSourceRecord) -> String = \.label,
        describe: (_ subject: String?, _ error: Error) -> String = BatchResult.plainLine) async -> BatchResult {
        await updateCollections(entries, kind: .rules, update: update, progress: progress, naming: naming, describe: describe)
    }
    private static func updateCollections(_ entries: [ConfigurationCollectionEntry], kind: ConfigurationCollection.Kind,
        update: (ConfigurationCollectionEntry) async throws -> Void,
        progress: (Int, Int, String) async -> Void,
        naming: (ConfigurationSourceRecord) -> String,
        describe: (_ subject: String?, _ error: Error) -> String) async -> BatchResult {
        var seen = Set<ConfigurationCollection.ID>()
         
         
         
         
        let remote = entries.filter {
            $0.id.kind == kind && $0.collection.type == "http"
                && (kind != .nodes || $0.source.suppliesNodes)
                && $0.source.isRetainedSnapshot != true && seen.insert($0.id).inserted
        }
        let targets = remote.filter { $0.collection.fetchingOutbound == nil }
         
         
        var result = BatchResult()
        result.targets = targets
        result.coreOwned = remote.filter { $0.collection.fetchingOutbound != nil }
        var outcomes: [Int: Error?] = [:]
         
         
        await withoutActuallyEscaping(update) { update in
            await withTaskGroup(of: (Int, Error?).self) { group in
                var next = 0
                func start() {
                    let index = next
                    next += 1
                    group.addTask {
                        do { try await update(targets[index]); return (index, nil) }
                        catch { return (index, error) }
                    }
                }
                while next < min(concurrentCollectionUpdates, targets.count) { start() }
                for await (index, error) in group {
                    outcomes[index] = error
                    await progress(outcomes.count, targets.count, targets[index].collection.name)
                    if next < targets.count, !Task.isCancelled { start() }
                }
            }
        }
         
        for (index, entry) in targets.enumerated() {
            guard let outcome = outcomes[index] else { continue }
            if let error = outcome {
                if error is CancellationError { continue }
                result.failures.append(describe(naming(entry.source) + " / " + entry.collection.name, error))
            } else {
                result.updated += 1
                result.updatedEntries.append(entry)
            }
        }
        return result
    }
    struct Page: Sendable {
        var nodes: [String] = []
        var lines: [String] = []
        var count: Int?
        var updatedAt: Date?
        var nextOffset: Int?
         
         
        var notes: [String] = []
         
        var issues: [String] = []
        var subscriptionUsage: ConfigurationSubscriptionUsage?
         
         
        var message: String? {
            let lines = notes + issues
            return lines.isEmpty ? nil : lines.joined(separator: "\n")
        }
    }
     
     
     
    static func runningProviders(matching entries: [ConfigurationCollectionEntry],
                                 in catalog: ProviderCatalog) -> Set<String> {
        let wanted = Set(entries.compactMap { entry -> String? in
            guard entry.collection.type == "http", let location = entry.collection.location else { return nil }
            return runningKey(kind: entry.id.kind, address: location)
        })
        guard !wanted.isEmpty else { return [] }
        return Set(catalog.entries.filter { entry in
            guard let kind = runningKind(entry.kind) else { return false }
            return wanted.contains(runningKey(kind: kind, address: entry.url))
        }.map(\.name))
    }

     
     
     
     
    struct RunningIndex {
        fileprivate var byKey: [String: Set<String>] = [:]
         
        func providers(of entry: ConfigurationCollectionEntry) -> Set<String> {
            guard entry.collection.type == "http", let location = entry.collection.location else { return [] }
            return byKey[ConfigurationCollectionContentBridge.runningKey(kind: entry.id.kind, address: location)] ?? []
        }
    }

    static func runningIndex(_ catalog: ProviderCatalog) -> RunningIndex {
        var index = RunningIndex()
        for entry in catalog.entries {
            guard let kind = runningKind(entry.kind) else { continue }
            index.byKey[runningKey(kind: kind, address: entry.url), default: []].insert(entry.name)
        }
        return index
    }

     
     
     
    static func libraryCopyDate(of entry: ConfigurationCollectionEntry) -> Date? {
        guard let cache = cachedState(entry) else { return nil }
        let file = directory(entry).appendingPathComponent(cache.payloadFile ?? "payload")
        return (try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate]) as? Date
    }

     
     
     
    static func libraryCopyRequest(of entry: ConfigurationCollectionEntry) -> String? {
        guard let location = entry.collection.location, let cache = cachedState(entry) else { return nil }
        return cache.requestIdentity ?? ProviderRequestIdentity.bare(url: location)
    }

     
     
    struct RunningTake: Equatable {
         
        var forced: Set<String> = []
         
        var fromLibrary: Set<String> = []
         
        var byCore: Set<String> = []
         
         
         
         
         
        var failedAsAsked: Set<String> = []
        var isEmpty: Bool { forced.isEmpty && fromLibrary.isEmpty && byCore.isEmpty && failedAsAsked.isEmpty }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func runningTake(updated: [ConfigurationCollectionEntry], failed: [ConfigurationCollectionEntry],
                            coreOwned: [ConfigurationCollectionEntry] = [],
                            catalog: ProviderCatalog, coreFetched: Set<String>, index given: RunningIndex? = nil,
                            copyRequest: (ConfigurationCollectionEntry) -> String? = ConfigurationCollectionContentBridge.libraryCopyRequest(of:),
                            failedRequest: ((ConfigurationCollectionEntry) -> String?)? = nil) -> RunningTake {
        let index = given ?? runningIndex(catalog)
        func running(_ entries: [ConfigurationCollectionEntry]) -> Set<String> {
            entries.reduce(into: Set<String>()) { $0.formUnion(index.providers(of: $1)) }
        }
        let fresh = running(updated).subtracting(coreFetched)
        var headed = running(updated.filter {
            $0.id.kind == .rules && $0.collection.definition.topLevelValue("header") != nil
        })
        let records = Dictionary(catalog.entries.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        for entry in updated {
            guard let copy = copyRequest(entry) else { continue }
            for name in index.providers(of: entry) where fresh.contains(name) {
                 
                 
                 
                 
                if let request = records[name]?.request ?? records[name]?.payloadRequest, request != copy { headed.insert(name) }
            }
        }
        let owned = running(coreOwned)
         
         
        let asked = failedRequest ?? { entry in
            catalog.userAgent.flatMap {
                ConfigurationCollectionContentBridge.libraryRequest(of: entry, userAgent: ClientUserAgent.sanitized($0))
            }
        }
        var asAsked: Set<String> = []
        for entry in failed {
            guard let request = asked(entry) else { continue }
            for name in index.providers(of: entry) where records[name]?.request == request { asAsked.insert(name) }
        }
        let forced = running(failed).subtracting(asAsked).union(owned.subtracting(fresh)).union(headed).subtracting(coreFetched)
        return RunningTake(forced: forced, fromLibrary: fresh.subtracting(forced),
                           byCore: running(updated + failed).union(owned).intersection(coreFetched),
                           failedAsAsked: asAsked.subtracting(fresh).subtracting(forced).subtracting(coreFetched))
    }

     
     
     
     
     
    static func runningCatalog(planned: ProviderCatalog, recorded: ProviderCatalog) -> ProviderCatalog {
        let records = Dictionary(recorded.entries.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var catalog = planned
        catalog.entries = planned.entries.map { entry in
            guard let record = records[entry.name], record.kind == entry.kind, record.url == entry.url else { return entry }
            return record
        }
        return catalog
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    static func copiesNotTaken(_ names: Set<String>, of updated: [ConfigurationCollectionEntry],
                               matchedIn catalog: ProviderCatalog, published: ProviderCatalog,
                               index given: RunningIndex? = nil,
                               copyDate: (ConfigurationCollectionEntry) -> Date? = ConfigurationCollectionContentBridge.libraryCopyDate(of:)) -> [String] {
        let index = given ?? runningIndex(catalog)
        var copyDates: [String: Date] = [:]
        for entry in updated {
            let matched = index.providers(of: entry)
            guard !matched.isEmpty, let date = copyDate(entry) else { continue }
            for name in matched { copyDates[name] = date }
        }
        let records = Dictionary(published.entries.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        return names.filter { name in
            guard let record = records[name] else { return false }
             
             
            guard let date = copyDates[name], let received = ProviderMaterializer.received(record) else { return true }
            if received == date || record.lastUpdatedAt == date { return false }
            let ownDownload = record.payloadURL == record.url && record.payloadRequest != nil && record.note == nil
            return !(ownDownload && received > date)
        }.sorted()
    }

     
     
     
     
    static func withRunningCounts(_ entries: [ConfigurationCollectionEntry], container: URL?) -> [ConfigurationCollectionEntry] {
        guard let container, let store = try? ConfigResourceStore(containerURL: container),
              let directory = try? store.activeProvidersDirectory(),
              let catalog = ProviderCatalog.load(providersDir: directory) else { return entries }
        return withRunningCounts(entries, catalog: catalog)
    }

    static func withRunningCounts(_ entries: [ConfigurationCollectionEntry], catalog: ProviderCatalog) -> [ConfigurationCollectionEntry] {
        let coreFetched = catalog.coreFetchedProviders ?? []
         
         
         
         
         
        var counts: [String: Int] = [:]
        var ambiguous: Set<String> = []
        for entry in catalog.entries where !coreFetched.contains(entry.name) {
             
             
            guard let kind = runningKind(entry.kind),
                  let count = entry.count ?? (entry.note == nil ? nil : 0) else { continue }
            let key = runningKey(kind: kind, address: entry.url)
            if let known = counts[key], known != count { ambiguous.insert(key) }
            counts[key] = count
        }
        for key in ambiguous { counts.removeValue(forKey: key) }
        guard !counts.isEmpty else { return entries }
        return entries.map { entry in
            guard entry.collection.type == "http", let location = entry.collection.location,
                  let count = counts[runningKey(kind: entry.id.kind, address: location)] else { return entry }
            var result = entry
            result.memberCount = count
            return result
        }
    }

     
     
     
     
     
    struct RunningProviders: Sendable {
        let catalog: ProviderCatalog
         
         
        private let answers: [String: [ProviderRefreshState.Entry]]

        init(catalog: ProviderCatalog, state: ProviderRefreshState?) {
            self.catalog = catalog
            var answers: [String: [ProviderRefreshState.Entry]] = [:]
            for provider in catalog.entries where provider.kind == "proxy" {
                guard let answer = state?.entry(kind: provider.kind, name: provider.name, url: provider.url) else { continue }
                answers[runningKey(kind: .nodes, address: provider.url), default: []].append(answer)
            }
            self.answers = answers
        }

        static func load(container: URL?) -> RunningProviders? {
            guard let container, let store = try? ConfigResourceStore(containerURL: container),
                  let directory = try? store.activeProvidersDirectory(),
                  let catalog = ProviderCatalog.load(providersDir: directory) else { return nil }
            return RunningProviders(
                catalog: catalog,
                state: ProviderRefreshState.read(workingDirectory: container.appendingPathComponent("working")))
        }

         
         
         
         
         
         
         
         
         
         
         
         
        func newerUsage(of entry: ConfigurationCollectionEntry, than date: Date?) -> ConfigurationSubscriptionUsage? {
            guard entry.id.kind == .nodes, entry.collection.type == "http", let location = entry.collection.location,
                  let candidates = answers[runningKey(kind: .nodes, address: location)] else { return nil }
            var found: ConfigurationSubscriptionUsage?
            for answer in candidates where answer.isNewer(than: date) {
                guard let usage = answer.usage.map(ConfigurationCenterSourceBridge.subscriptionUsage) else { continue }
                if let known = found, known != usage { return nil }
                found = usage
            }
            return found
        }
    }

     
     
     
     
    static func withRunningUsage(_ entries: [ConfigurationCollectionEntry],
                                 running: RunningProviders?) -> [ConfigurationCollectionEntry] {
        guard let running else { return entries }
        return entries.map { entry in
            guard let usage = running.newerUsage(of: entry, than: entry.copyUpdatedAt) else { return entry }
            var result = entry
            result.subscriptionUsage = usage
            return result
        }
    }

     
     
     
    static func shownUsage(_ page: Page, of entry: ConfigurationCollectionEntry,
                           running: RunningProviders?) -> ConfigurationSubscriptionUsage? {
        running?.newerUsage(of: entry, than: page.updatedAt) ?? page.subscriptionUsage
    }

    private static func runningKind(_ catalogKind: String) -> ConfigurationCollection.Kind? {
        switch catalogKind {
        case "rule": return .rules
        case "proxy": return .nodes
        default: return nil
        }
    }

    private static func runningKey(kind: ConfigurationCollection.Kind, address: String) -> String {
        kind.rawValue + "\n" + address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func catalog(_ library: ConfigurationLibraryStore, snapshot: ConfigurationLibrarySnapshot) throws -> [ConfigurationCollectionEntry] {
        try library.collectionCatalog(snapshot).map { entry in
            var result = entry
            if entry.collection.type == "inline" { return result }
            if entry.collection.type == "file", entry.id.kind == .nodes {
                let source = try library.payload(.init(entry.source))
                if let path = entry.collection.location,
                   let bytes = source.resourceFiles?[path] ?? source.resourceFiles?[URL(fileURLWithPath: path).lastPathComponent] {
                     
                     
                    result.memberCount = try? ProxyImportBridge.readSummary(bytes, context: .nodeBundle).count
                }
                return result
            }
            let folder = directory(entry)
            if let data = try? Data(contentsOf: folder.appendingPathComponent("state.json")),
               let cache = try? JSONDecoder().decode(Cache.self, from: data), cache.count >= 0 {
                let filename = cache.payloadFile ?? "payload"
                if filename == URL(fileURLWithPath: filename).lastPathComponent, filename != ".", filename != "..",
                   FileManager.default.fileExists(atPath: folder.appendingPathComponent(filename).path) {
                    result.memberCount = cache.count
                    result.subscriptionUsage = cache.subscriptionUsage
                    result.copyUpdatedAt = cache.updatedAt
                }
            }
            return result
        }
    }
     
     
     
    struct Cache: Codable {
        let count: Int; let updatedAt: Date; var payloadFile: String? = nil
        var subscriptionUsage: ConfigurationSubscriptionUsage? = nil; var requestIdentity: String? = nil
    }
    static func directory(_ entry: ConfigurationCollectionEntry) -> URL {
        let key = entry.source.id + "\n" + entry.id.kind.rawValue + "\n" + entry.collection.name + "\n" + entry.collection.definition.serialized()
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("configuration-collections").appendingPathComponent(digest)
    }
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func cachedNodeFiles(requests: [String: String], workingDirectory: URL,
                                unrecordedCopiesFor addresses: [String: String] = [:]) -> [String: URL] {
        guard !requests.isEmpty else { return [:] }
        let library = ConfigurationLibraryStore(directory: workingDirectory.appendingPathComponent("configuration-library"))
        guard let snapshot = try? library.snapshot(),
              let entries = try? library.collectionCatalog(snapshot) else { return [:] }
        return cachedFiles(requests: requests, kind: .nodes, entries: entries, unrecordedCopiesFor: addresses)
    }

     
     
    private static func cachedFiles(requests: [String: String], kind: ConfigurationCollection.Kind,
                                    entries: [ConfigurationCollectionEntry],
                                    unrecordedCopiesFor addresses: [String: String] = [:]) -> [String: URL] {
        cachedCopies(requests: requests, kind: kind, entries: entries, unrecordedCopiesFor: addresses).mapValues(\.file)
    }

     
    private static func cachedCopies(requests: [String: String], kind: ConfigurationCollection.Kind,
                                     entries: [ConfigurationCollectionEntry],
                                     unrecordedCopiesFor addresses: [String: String] = [:]) -> [String: (file: URL, cache: Cache)] {
        guard !requests.isEmpty else { return [:] }
        let wanted = Set(requests.values)
        let shown = Set(addresses.values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        var newest: [String: (file: URL, cache: Cache)] = [:]
        var unrecorded: [String: (file: URL, cache: Cache)] = [:]
        for entry in entries where entry.id.kind == kind && entry.collection.type == "http" {
            guard let url = entry.collection.location, let cache = cachedState(entry) else { continue }
            let file = directory(entry).appendingPathComponent(cache.payloadFile ?? "payload")
            let identity = cache.requestIdentity ?? ProviderRequestIdentity.bare(url: url)
            if wanted.contains(identity), newest[identity].map({ $0.cache.updatedAt < cache.updatedAt }) ?? true {
                newest[identity] = (file, cache)
            }
            let address = url.trimmingCharacters(in: .whitespacesAndNewlines)
            if cache.requestIdentity == nil, shown.contains(address),
               unrecorded[address].map({ $0.cache.updatedAt < cache.updatedAt }) ?? true {
                unrecorded[address] = (file, cache)
            }
        }
        var files: [String: (file: URL, cache: Cache)] = [:]
        for (name, identity) in requests {
            if let copy = newest[identity] {
                files[name] = copy
            } else if let address = addresses[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
                      let copy = unrecorded[address] {
                files[name] = copy
            }
        }
        return files
    }

     
     
     
     
     
     
    static func cachedNodeFiles(for providers: [RemoteResourcePlan.Provider], workingDirectory: URL) -> [String: URL] {
        let direct = providers.filter { !ProviderFetchedByCore.applies(toProxy: $0.proxy) }
        return cachedNodeFiles(requests: Dictionary(direct.map { ($0.name, ProviderRequestIdentity.of($0)) },
                                                    uniquingKeysWith: { first, _ in first }),
                               workingDirectory: workingDirectory)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    static func cachedLibraryFiles(for providers: [RemoteResourcePlan.Provider], workingDirectory: URL)
        -> (nodes: [String: URL], rules: [String: URL], nodeUsage: [String: SubscriptionInfo]) {
        func requests(_ kind: String) -> [String: String] {
            Dictionary(providers.filter { $0.kind == kind && !ProviderFetchedByCore.applies(toProxy: $0.proxy) }
                .map { ($0.name, ProviderRequestIdentity.of($0)) }, uniquingKeysWith: { first, _ in first })
        }
        let nodeRequests = requests("proxy"), ruleRequests = requests("rule")
        guard !nodeRequests.isEmpty || !ruleRequests.isEmpty else { return ([:], [:], [:]) }
        let library = ConfigurationLibraryStore(directory: workingDirectory.appendingPathComponent("configuration-library"))
        guard let snapshot = try? library.snapshot(),
              let entries = libraryCatalog(library, snapshot: snapshot, at: workingDirectory) else { return ([:], [:], [:]) }
        let nodes = cachedCopies(requests: nodeRequests, kind: .nodes, entries: entries)
        return (nodes.mapValues(\.file),
                cachedFiles(requests: ruleRequests, kind: .rules, entries: entries),
                nodes.compactMapValues { copy in
                    copy.cache.subscriptionUsage.map {
                        SubscriptionInfo(upload: $0.upload, download: $0.download, total: $0.total, expire: $0.expire)
                    }
                })
    }

     
     
     
     
    private static let catalogMemoLock = NSLock()
    nonisolated(unsafe) private static var catalogMemo: (directory: URL, generation: UInt64, entries: [ConfigurationCollectionEntry])?
    private static func libraryCatalog(_ library: ConfigurationLibraryStore, snapshot: ConfigurationLibrarySnapshot,
                                       at directory: URL) -> [ConfigurationCollectionEntry]? {
        catalogMemoLock.lock()
        if let memo = catalogMemo, memo.directory == directory, memo.generation == snapshot.generation {
            catalogMemoLock.unlock()
            return memo.entries
        }
        catalogMemoLock.unlock()
        guard let entries = try? library.collectionCatalog(snapshot) else { return nil }
        catalogMemoLock.lock()
        catalogMemo = (directory, snapshot.generation, entries)
        catalogMemoLock.unlock()
        return entries
    }

     
     
     
     
    private static func requestIdentities(ofHTTP definitions: [String: [String: Any]],
                                          userAgent: String?) -> [String: String] {
        var identities: [String: String] = [:]
        var headed: [String: Any] = [:]
        for (name, definition) in definitions {
            guard let url = definition["url"] as? String else { continue }
            if let header = definition["header"] {
                headed[name] = ["type": "http", "url": url, "header": header]
            } else {
                identities[name] = ProviderRequestIdentity.of(url: url, headers: userAgent.map { ["User-Agent": [$0]] } ?? [:])
            }
        }
         
         
        let root: [String: Any] = ["proxy-providers": headed]
        if !headed.isEmpty, JSONSerialization.isValidJSONObject(root),
           let data = try? JSONSerialization.data(withJSONObject: root, options: [.withoutEscapingSlashes]),
           let plan = try? ConfigTransforms.planResources(mergedYAML: String(decoding: data, as: UTF8.self))
            .carrying(userAgent: userAgent) {
            for provider in plan.providers where provider.kind == "proxy" {
                identities[provider.name] = ProviderRequestIdentity.of(provider)
            }
        }
        return identities
    }

    static func cachedNodeFiles(yaml: String, workingDirectory: URL) -> [String: URL] {
         
         
        let definitionsText = yaml.utf8.count > NodesInventoryProjection.wholeReadBytes
            ? ConfigurationSections.droppingLong(["proxies", "rules"], from: yaml) ?? yaml
            : yaml
        let root = ConfigTransforms.parsedRoot(forYAML: definitionsText)?.root
        let definitions = root?["proxy-providers"] as? [String: [String: Any]] ?? [:]
         
         
        var requests = requestIdentities(ofHTTP: definitions.filter { $0.value["type"] as? String == "http" },
                                         userAgent: ClientUserAgent.choice(ClientUserAgent.written(in: root),
                                                                           identity: ClientUserAgent.downloadIdentity()))
        var publishedFiles: [String: URL] = [:]
        for (name, definition) in definitions where definition["type"] as? String == "file" {
            guard let path = definition["path"] as? String else { continue }
            let file = URL(fileURLWithPath: path, relativeTo: workingDirectory).standardizedFileURL
            guard file.path.hasPrefix(workingDirectory.standardizedFileURL.path + "/"),
                  FileManager.default.fileExists(atPath: file.path) else { continue }
            publishedFiles[name] = file
             
             
             
            if let entry = ProviderCatalog.load(providersDir: file.deletingLastPathComponent())?.entries.first(where: {
                $0.kind == "proxy" && $0.name == name && $0.path == file.lastPathComponent
            }) { requests[name] = ProviderRequestIdentity.bare(url: entry.url) }
        }
         
         
        let addresses = definitions.compactMapValues { $0["type"] as? String == "http" ? $0["url"] as? String : nil }
        let libraryFiles = cachedNodeFiles(requests: requests, workingDirectory: workingDirectory, unrecordedCopiesFor: addresses)
        let files = publishedFiles.merging(libraryFiles) { published, library in
            let publishedDate = (try? FileManager.default.attributesOfItem(atPath: published.path)[.modificationDate]) as? Date
            let libraryDate = (try? FileManager.default.attributesOfItem(atPath: library.path)[.modificationDate]) as? Date
            return (publishedDate ?? .distantPast) > (libraryDate ?? .distantPast) ? published : library
        }
        return files
    }

    static func page(_ entry: ConfigurationCollectionEntry, source: ConfigurationSourcePayload,
                     query: String, offset: Int = 0) throws -> Page {
        let collection = entry.collection
        let dir = directory(entry)
        let cache = try? JSONDecoder().decode(Cache.self, from: Data(contentsOf: dir.appendingPathComponent("state.json")))
        var result = Page(count: cache?.count ?? collection.inlineCount, updatedAt: cache?.updatedAt)
        let data: Data
        if collection.type == "inline" {
            let payload = collection.definition.topLevelValue("payload") ?? .array([])
            data = Data(OrderedJSON.object([(entry.id.kind == .nodes ? "proxies" : "payload", payload)]).serialized().utf8)
        } else if collection.type == "file" {
            guard let path = collection.location,
                  let value = source.resourceFiles?[path] ?? source.resourceFiles?[URL(fileURLWithPath: path).lastPathComponent] else {
                result.notes = ["The collection file is missing. Import its companion file again from the source."]; return result
            }
            data = value
        } else {
            guard cache != nil, let bytes = try? Data(contentsOf: dir.appendingPathComponent(cache?.payloadFile ?? "payload"), options: .mappedIfSafe) else {
                result.notes = [entry.id.kind == .rules
                    ? "The rules are at a link. Use Update Source to download and view them."
                    : "The nodes are at a link. Use Update Source to download and view them."]
                return result
            }
            data = bytes
            result.subscriptionUsage = cache?.subscriptionUsage
        }
        if entry.id.kind == .nodes {
             
             
             
             
             
            let key = "\(dir.path)|\(data.count)|\(cache?.updatedAt.timeIntervalSince1970 ?? 0)|\(entry.id.kind)"
            let pages = try ProxyPayloadPages.open(data, context: .nodeBundle, key: key)
            let summary = try pages.summary()
            var shown: [String] = []
            var position = offset
            while position < summary.count, shown.count < 200 {
                let nodes = try pages.page(offset: position, limit: query.isEmpty ? 200 : 1_000)
                guard !nodes.isEmpty else { break }
                for node in nodes {
                    position += 1
                    let json = String(decoding: try JSONSerialization.data(withJSONObject: node, options: .sortedKeys), as: UTF8.self)
                    if query.isEmpty || json.localizedCaseInsensitiveContains(query) { shown.append(json) }
                    if shown.count >= 200 { break }
                }
            }
            result.count = summary.count
            result.nodes = shown
            result.nextOffset = position < summary.count ? position : nil
            result.issues = summary.issues.map { $0.message }
            if ["filter", "exclude-filter", "exclude-type", "override"].contains(where: { collection.definition.topLevelValue($0) != nil }) {
                result.notes.append("Shows the collection's own nodes. Filters and overrides apply when it runs.")
            }
        } else if collection.format == "mrs" {
            var count = 0; var error: NSError?
            guard AppCore.inspectProvider("rule", collection.behavior ?? "domain", "mrs", data, &count, &error) else {
                throw error ?? ConfigurationLibraryError.unreadable
            }
            result.count = count
            result.notes = ["MRS rule sets can't be browsed line by line."]
        } else if collection.type == "inline", case .array(let values) = collection.definition.topLevelValue("payload") {
            let lines = values.map { $0.foundationValue as? String ?? $0.serialized() }
                .filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
            result.count = values.count
            result.lines = Array(lines.dropFirst(offset).prefix(200))
            result.nextOffset = offset + result.lines.count < lines.count ? offset + result.lines.count : nil
        } else {
             
             
            var cursor = data.startIndex, skipped = 0
            while cursor < data.endIndex && result.lines.count <= 200 {
                let end = data[cursor...].firstIndex(of: 10) ?? data.endIndex
                let line = String(decoding: data[cursor..<end], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                cursor = end < data.endIndex ? end + 1 : data.endIndex
                if line.isEmpty || line.hasPrefix("#") || line == "payload:" { continue }
                if !query.isEmpty && !line.localizedCaseInsensitiveContains(query) { continue }
                if skipped < offset { skipped += 1; continue }
                result.lines.append(line)
            }
            if result.lines.count > 200 { result.lines.removeLast(); result.nextOffset = offset + 200 }
        }
        return result
    }
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func fetchNeverFetchedNodeCollections(_ library: ConfigurationLibraryStore,
                                                 inUse: ProviderCatalog? = nil,
                                                 downloader: HTTPFetching = ResourceDownloader(),
                                                 credentials: CredentialStore = CredentialStore()) async -> Int {
        guard let snapshot = try? library.snapshot(),
              let entries = try? library.collectionCatalog(snapshot) else { return 0 }
        let userAgents = CollectionUserAgents(inUse: inUse)
        let nodeCollections = entries.filter {
            $0.id.kind == .nodes && $0.collection.type == "http"
                && $0.source.suppliesNodes && $0.source.isRetainedSnapshot != true
        }
        var held = requestsAnswered(by: nodeCollections)
        var fetched = 0
        for entry in nodeCollections {
            if Task.isCancelled { break }
            let userAgent = userAgents.of(entry)
            guard let request = try? runtimeRequest(for: entry, userAgent: userAgent, identity: userAgents.identity),
                  let location = entry.collection.location,
                  !ProviderFetchedByCore.applies(toProxy: request.provider.proxy) else { continue }
             
            let identity = ProviderRequestIdentity.of(request.provider)
            let address = request.provider.url
            guard !held.contains(identity), !ProviderDownloadActivity.claim([address]).isEmpty else { continue }
            defer { ProviderDownloadActivity.release([address]) }
             
            held.formUnion(requestsAnswered(by: nodeCollections))
            guard held.insert(identity).inserted else { continue }
            ProviderDownloadActivity.begin([location])
            do {
                try await download(entry, root: request.root, provider: request.provider,
                                   userAgent: userAgent ?? userAgents.identity,
                                   downloader: downloader, credentials: credentials)
                ProviderDownloadActivity.end(location, failure: nil)
                fetched += 1
            } catch {
                ProviderDownloadActivity.end(location, failure: ProviderDownloadActivity.reason(for: error, url: location))
            }
        }
        return fetched
    }

     
     
    private static func requestsAnswered(by entries: [ConfigurationCollectionEntry]) -> Set<String> {
        Set(entries.compactMap { entry in
            guard let location = entry.collection.location, let cache = cachedState(entry) else { return nil }
            return cache.requestIdentity ?? ProviderRequestIdentity.bare(url: location)
        })
    }

     
     
     
     
     
     
     
     
    private static func runtimeRequest(for entry: ConfigurationCollectionEntry, userAgent: String?,
                                       identity: String) throws
        -> (root: OrderedJSON, provider: RemoteResourcePlan.Provider) {
        try planned(entry, definition: definition(of: entry, carrying: ["header", "proxy", "age-secret-key"]),
                    userAgent: userAgent, identity: identity)
    }

     
    private static func definition(of entry: ConfigurationCollectionEntry, carrying keys: [String]) throws -> OrderedJSON {
        var definition = try entry.collection.browserDownloadDefinition()
        for key in keys {
            if let value = entry.collection.definition.topLevelValue(key) { definition = definition.settingTopLevel(key, to: value) }
        }
        return definition
    }

    private static func planned(_ entry: ConfigurationCollectionEntry, definition: OrderedJSON,
                                userAgent: String?, identity: String) throws
        -> (root: OrderedJSON, provider: RemoteResourcePlan.Provider) {
        let root = OrderedJSON.object([(entry.id.kind.rawValue, .object([(entry.collection.name, definition)]))])
        let plan = try ConfigTransforms.planResources(mergedYAML: root.serialized())
            .carrying(userAgent: ClientUserAgent.choice(userAgent, identity: identity))
        let kind = entry.id.kind == .nodes ? "proxy" : "rule"
        guard let provider = plan.providers.first(where: { $0.name == entry.collection.name && $0.kind == kind }) else {
            throw ConfigurationLibraryError.unreadable
        }
        return (root, provider)
    }

     
     
     
    private static func requestIdentity(of entry: ConfigurationCollectionEntry, userAgent: String?,
                                        identity: String) -> String? {
        guard let location = entry.collection.location else { return nil }
        guard entry.collection.definition.topLevelValue("header") != nil
                || ClientUserAgent.choice(userAgent, identity: identity) != nil else {
            return ProviderRequestIdentity.bare(url: location)
        }
        return (try? runtimeRequest(for: entry, userAgent: userAgent, identity: identity))
            .map { ProviderRequestIdentity.of($0.provider) }
    }

     
     
     
     
    static func libraryRequest(of entry: ConfigurationCollectionEntry, userAgent: String?,
                               identity: String = ClientUserAgent.downloadIdentity()) -> String? {
        guard entry.collection.type == "http" else { return nil }
        if entry.id.kind == .nodes {
            return (try? runtimeRequest(for: entry, userAgent: userAgent, identity: identity))
                .map { ProviderRequestIdentity.of($0.provider) }
        }
        return (try? entry.collection.browserDownloadDefinition())
            .flatMap { try? planned(entry, definition: $0, userAgent: userAgent, identity: identity) }
            .map { ProviderRequestIdentity.of($0.provider) }
    }

     
     
     
     
     
     
     
    struct CollectionUserAgents {
        let inUse: ProviderCatalog?
        let identity: String
        private let running: RunningIndex?

        init(inUse: ProviderCatalog?, identity: String = ClientUserAgent.downloadIdentity()) {
            self.inUse = inUse
            self.identity = identity
            running = inUse.map(ConfigurationCollectionContentBridge.runningIndex)
        }

         
         
         
         
        func of(_ entry: ConfigurationCollectionEntry) -> String? {
            if let inUse, let recorded = inUse.userAgent, let running, !running.providers(of: entry).isEmpty {
                return ClientUserAgent.sanitized(recorded)
            }
            return ClientUserAgent.sanitized(entry.sourceUserAgent)
        }
    }

     
     
     
     
     
     
     
     
     
    static func downloadedNodeCounts(_ library: ConfigurationLibraryStore,
                                     snapshot: ConfigurationLibrarySnapshot,
                                     inUse: ProviderCatalog? = nil) -> [String: Int] {
        guard let entries = try? library.collectionCatalog(snapshot) else { return [:] }
        let userAgents = CollectionUserAgents(inUse: inUse)
        let nodeCollections = entries.filter { $0.id.kind == .nodes && $0.collection.type == "http" }
        var newest: [String: (Date, Int)] = [:]
        var unrecorded: [String: (Date, Int)] = [:]
        for entry in nodeCollections {
            guard let location = entry.collection.location, let cache = cachedState(entry) else { continue }
            let identity = cache.requestIdentity ?? ProviderRequestIdentity.bare(url: location)
            if newest[identity].map({ $0.0 < cache.updatedAt }) ?? true { newest[identity] = (cache.updatedAt, max(cache.count, 0)) }
            let address = location.trimmingCharacters(in: .whitespacesAndNewlines)
            if cache.requestIdentity == nil, unrecorded[address].map({ $0.0 < cache.updatedAt }) ?? true {
                unrecorded[address] = (cache.updatedAt, max(cache.count, 0))
            }
        }
        guard !newest.isEmpty else { return [:] }
        var counts: [String: Int] = [:]
        for entry in nodeCollections {
            guard let identity = requestIdentity(of: entry, userAgent: userAgents.of(entry), identity: userAgents.identity),
                  let copy = newest[identity] ?? entry.collection.location.flatMap({
                      unrecorded[$0.trimmingCharacters(in: .whitespacesAndNewlines)]
                  }) else { continue }
            counts[entry.source.id, default: 0] += copy.1
        }
        return counts
    }

     
     
     
     
     
     
     
     
     
     
     
     
    static func keepInLibrary(_ downloads: [(provider: RemoteResourcePlan.Provider, file: URL, count: Int,
                                             usage: ConfigurationSubscriptionUsage?)],
                              userAgent: String? = nil, identity: String = ClientUserAgent.downloadIdentity(),
                              workingDirectory: URL) {
        guard !downloads.isEmpty else { return }
        let library = ConfigurationLibraryStore(directory: workingDirectory.appendingPathComponent("configuration-library"))
        guard let snapshot = try? library.snapshot(),
              let entries = try? library.collectionCatalog(snapshot) else { return }
        let nodeCollections = entries.filter {
            $0.id.kind == .nodes && $0.collection.type == "http"
                && $0.source.suppliesNodes && $0.source.isRetainedSnapshot != true
        }
        var held = requestsAnswered(by: nodeCollections)
        for download in downloads {
            let downloaded = ProviderRequestIdentity.of(download.provider)
            guard !held.contains(downloaded),
                  let entry = nodeCollections.first(where: {
                      $0.collection.location?.trimmingCharacters(in: .whitespacesAndNewlines) == download.provider.url
                          && requestIdentity(of: $0, userAgent: userAgent, identity: identity) == downloaded
                  }),
                  let bytes = try? Data(contentsOf: download.file, options: .mappedIfSafe),
                  (try? store(bytes, count: download.count, subscriptionUsage: download.usage,
                              requestIdentity: downloaded, in: entry)) != nil
            else { continue }
            held.insert(downloaded)
        }
    }

     
    private static func cachedState(_ entry: ConfigurationCollectionEntry) -> Cache? {
        let folder = directory(entry)
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("state.json")),
              let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return nil }
        let filename = cache.payloadFile ?? "payload"
        guard filename == URL(fileURLWithPath: filename).lastPathComponent, filename != ".", filename != "..",
              FileManager.default.fileExists(atPath: folder.appendingPathComponent(filename).path) else { return nil }
        return cache
    }
     
     
     
     
    enum CollectionRefresh: Equatable {
        case downloaded
        case coreOwned
         
        case local
    }

     
     
     
     
     
     
    @discardableResult
    static func refresh(_ entry: ConfigurationCollectionEntry, source: ConfigurationSourcePayload,
                        inUse: ProviderCatalog? = nil, downloader: HTTPFetching = ResourceDownloader(),
                        credentials: CredentialStore = CredentialStore()) async throws -> CollectionRefresh {
        guard entry.collection.type == "http" else { return .local }
        let userAgents = CollectionUserAgents(inUse: inUse)
        let userAgent = userAgents.of(entry)
         
         
         
         
         
         
         
         
         
         
        if entry.id.kind == .nodes {
            let request = try runtimeRequest(for: entry, userAgent: userAgent, identity: userAgents.identity)
            guard !ProviderFetchedByCore.applies(toProxy: request.provider.proxy) else { return .coreOwned }
            try await download(entry, root: request.root, provider: request.provider,
                               userAgent: userAgent ?? userAgents.identity,
                               downloader: downloader, credentials: credentials)
            return .downloaded
        }
         
         
         
        guard entry.collection.fetchingOutbound == nil else { return .coreOwned }
        let request = try planned(entry, definition: entry.collection.browserDownloadDefinition(),
                                  userAgent: userAgent, identity: userAgents.identity)
        try await download(entry, root: request.root, provider: request.provider,
                           userAgent: userAgent ?? userAgents.identity,
                           downloader: downloader, credentials: credentials)
        return .downloaded
    }

     
     
     
    private static func download(_ entry: ConfigurationCollectionEntry, root: OrderedJSON,
                                 provider: RemoteResourcePlan.Provider, userAgent: String,
                                 downloader: HTTPFetching, credentials: CredentialStore) async throws {
        let directory = directory(entry)
        let stage = directory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: stage) }
        let result = try await ProviderMaterializer(downloader: downloader, credentials: credentials)
            .materializeDetailed(plan: .init(providers: [provider]), into: stage, publishedProvidersDir: stage,
                maxBytesEach: 32 * 1024 * 1024, forceRefresh: [provider.name],
                ageSecretKeys: try ConfigTransforms.providerAgeSecretKeys(mergedYAML: root.serialized()),
                userAgent: userAgent)
        if let warning = result.validationWarnings.first {
            throw AuthoredError(text: ProviderMaterializer.failureText(of: warning.note))
        }
        guard result.firstLoadPending.isEmpty, let path = result.readPaths[provider.name] else { throw ConfigurationLibraryError.unreadable }
        let bytes = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
         
        if entry.id.kind == .nodes { _ = try ProxyImportBridge.inspectSummary(bytes, context: .nodeBundle) }
        try store(bytes, count: result.entryCounts[provider.name] ?? 0,
                  subscriptionUsage: entry.id.kind == .nodes ? result.subscriptionUserInfo[provider.name]
                      .flatMap { SubscriptionInfo.parse(header: $0) }.map(ConfigurationCenterSourceBridge.subscriptionUsage) : nil,
                  requestIdentity: ProviderRequestIdentity.of(provider), in: entry)
    }

     
     
    private static func store(_ bytes: Data, count: Int, subscriptionUsage: ConfigurationSubscriptionUsage?,
                              requestIdentity: String, in entry: ConfigurationCollectionEntry) throws {
        let directory = directory(entry)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = UUID().uuidString + ".payload"
        try bytes.write(to: directory.appendingPathComponent(file), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try JSONEncoder().encode(Cache(count: count, updatedAt: Date(), payloadFile: file,
                                       subscriptionUsage: subscriptionUsage, requestIdentity: requestIdentity))
            .write(to: directory.appendingPathComponent("state.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

 
 
 
 
 
enum ConfigurationSourceRefusals {
    static let key = "configuration.sources.refusals"
    static let didChange = Notification.Name("ClashConfigurationSourceRefusalsDidChange")
    static var appGroup: UserDefaults { UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite) ?? .standard }

    static func all(in defaults: UserDefaults = appGroup) -> [String: String] {
        defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    static func reason(for sourceID: String, in defaults: UserDefaults = appGroup) -> String? {
        all(in: defaults)[sourceID]
    }

     
     
    static func note(_ error: Error, sourceID: String, in defaults: UserDefaults = appGroup) {
        guard case .refusedConfiguration(let reason, _)? = error as? ProxyImportBridgeError else { return }
        write(sourceID, reason, page: false, in: defaults)
    }

     
     
     
    static func record(_ reason: String, sourceID: String, in defaults: UserDefaults = appGroup) {
        write(sourceID, reason, page: true, in: defaults)
    }

    static func record(_ refusals: [String: String], in defaults: UserDefaults = appGroup) {
        for (sourceID, reason) in refusals { record(reason, sourceID: sourceID, in: defaults) }
    }

    static func clear(_ sourceID: String, in defaults: UserDefaults = appGroup) {
        guard all(in: defaults)[sourceID] != nil else { return }
        write(sourceID, nil, page: false, in: defaults)
    }

     
     
     
     
    static func clearAfterUnchangedRefresh(_ sourceID: String, pageStillTaken: Bool,
                                           in defaults: UserDefaults = appGroup) {
        if pageStillTaken, isPageRefusal(sourceID, in: defaults) { return }
        clear(sourceID, in: defaults)
    }

     
     
    static let pageKey = "configuration.sources.refusals.page"
    static func isPageRefusal(_ sourceID: String, in defaults: UserDefaults = appGroup) -> Bool {
        (defaults.stringArray(forKey: pageKey) ?? []).contains(sourceID)
    }

    private static let lock = NSLock()
    private static func write(_ sourceID: String, _ reason: String?, page: Bool, in defaults: UserDefaults) {
        lock.lock()
        var current = all(in: defaults)
        current[sourceID] = reason
        defaults.set(current, forKey: key)
        var pages = Set(defaults.stringArray(forKey: pageKey) ?? [])
        if reason != nil && page { pages.insert(sourceID) } else { pages.remove(sourceID) }
        defaults.set(pages.isEmpty ? nil : pages.sorted(), forKey: pageKey)
        lock.unlock()
         
         
        DispatchQueue.main.async { NotificationCenter.default.post(name: didChange, object: defaults) }
    }
}
