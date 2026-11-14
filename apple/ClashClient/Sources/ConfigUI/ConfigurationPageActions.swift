import Foundation
import ClashClientKit

 
 
enum ConfigurationCompileAnswer: Equatable, Sendable {
    struct Problem: Decodable, Equatable, Sendable {
        let message: String
        let section: String?
        let index: Int?
        let line: Int?

         
         
        var place: String? {
            var parts: [String] = []
            if let section { parts.append(index.map { "\(section)[\($0)]" } ?? section) }
            if let line { parts.append("line \(line)") }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }
    case accepted
    case refused([Problem])
     
     
    case unavailable(String?)

    static func decode(_ json: String) -> ConfigurationCompileAnswer {
        struct Wire: Decodable { let ok: Bool; let errors: [Problem]? }
        guard let wire = try? JSONDecoder().decode(Wire.self, from: Data(json.utf8)) else { return .unavailable(json) }
        if wire.ok { return .accepted }
        return .refused(wire.errors ?? [])
    }
}

 
 
 
 
extension ProfilesViewModel {
     
     
     
     
    func configurationOutline(_ id: String, customRules: Int) async throws -> [ConfigurationOutlineRow] {
         
         
        try await configurationOutlineReading(id, customRules: customRules, readingItsOwnFile: true).rows
    }

     
     
     
     
     
     
     
     
     
     
     
    func configurationOutlineReading(_ id: String, customRules: Int, readingItsOwnFile: Bool = false) async throws
        -> (rows: [ConfigurationOutlineRow], original: (json: String, document: OrderedJSON)?) {
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        await settleLibraryHousekeeping()
        do {
            return try await Task.detached(priority: .userInitiated) {
                () throws -> (rows: [ConfigurationOutlineRow], original: (json: String, document: OrderedJSON)?) in
                let snapshot = try library.snapshot()
                let recipe = snapshot.recipes.first { $0.id == id }
                if let recipe, recipe.preservesOriginal != true {
                    return (try library.outline(ofRecipe: id, in: snapshot, customRules: customRules), nil)
                }
                 
                 
                guard let reference = recipe?.sources.first
                        ?? snapshot.sources.first(where: { $0.id == "legacy-" + id }).map(ConfigurationSourceVersion.init) else {
                     
                     
                     
                    throw ConfigurationLibraryError.missingDependency(recipe?.ruleSource.id ?? id)
                }
                return try Self.originalOutline(of: try library.payload(reference), customRules: customRules)
            }.value
        } catch ConfigurationLibraryError.missingDependency(let missing) where missing == id && readingItsOwnFile {
            let own = try await configurationSourceFromLegacy(id)
            return try await Task.detached(priority: .userInitiated) {
                try Self.originalOutline(of: own, customRules: customRules)
            }.value
        }
    }

     
    nonisolated private static func originalOutline(of payload: ConfigurationSourcePayload, customRules: Int) throws
        -> (rows: [ConfigurationOutlineRow], original: (json: String, document: OrderedJSON)?) {
        let json = payload.documentJSON
        let document = try OrderedJSON.parse(json)
        var rows = ConfigurationOutline.rows(for: document, form: .original, customRules: customRules)
         
         
        if payload.record.rulesWrittenInOriginal == true, let index = rows.firstIndex(where: { $0.section == .rules }) {
            rows[index] = ConfigurationOutlineRow(section: .rules, count: payload.record.ruleCount, written: true)
        }
        return (rows, (json, document))
    }

     
     
     
    func switchConfigurationScheme(_ id: String, to schemeID: String) async throws {
        try await changingTheLibrary { library, generation in
            let prepared = try await Task.detached(priority: .userInitiated) {
                try library.prepareSchemeSwitch(profileID: id, to: schemeID, expectedGeneration: generation,
                                                resolveInput: ConfigurationCenterSourceBridge.BoundInputs().resolve)
            }.value
            try await self.saveConfigurationPlan(candidate: prepared.candidate, payloads: prepared.payloads,
                                                 compositions: [id: prepared.composition], generation: generation)
        }
    }

     
     
     
     
     
     
     
    func saveConfigurationAsScheme(_ id: String, label: String) async throws {
         
         
         
         
         
         
        let latest = try latestProfile(id)
        let source = latest.legacyRuntimeDNSGated == true ? try? storedSourceYAMLForSaving(latest) : nil
        let layer: OrderedJSON? = try await Task.detached(priority: .userInitiated) {
            var own = Self.pageKeysOfOwnOverride(latest)
            var legacy = OverridePatch(patchJSON: latest.legacyRuntimePatchJSON ?? "")
            if latest.legacyRuntimeDNSGated == true, legacy.hasDNSOverride,
               source.map(ProfileRuntimeConfigBuilder.hasEnabledOwnDNS(yaml:)) ?? true {
                legacy.clearDNS()
            }
            for key in legacy.topLevelKeys {
                guard let value = legacy.topLevelNode(key) else { continue }
                own.setTopLevelNode(key, Self.mergedAsTheCoreMerges(own.topLevelNode(key), value))
            }
            return own.topLevelKeys.isEmpty ? nil : try OrderedJSON.parse(own.patchJSON)
        }.value
        try await changingTheLibrary { library, generation in
            let prepared = try await Task.detached(priority: .userInitiated) {
                try library.prepareSaveAsScheme(profileID: id, label: label, expectedGeneration: generation,
                                                extraPage: layer,
                                                resolveInput: ConfigurationCenterSourceBridge.BoundInputs().resolve)
            }.value
            try await self.saveConfigurationPlan(candidate: prepared.candidate, payloads: prepared.payloads,
                                                 compositions: prepared.compositions, generation: generation)
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    func editConfigurationPage(_ id: String, edits: [ConfigurationPageEdit], readScheme: String? = nil) async throws {
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        await settleLibraryHousekeeping()
        for attempt in 1...3 {
            let latest = try latestProfile(id)
            let snapshot = try await Task.detached(priority: .userInitiated) { try library.snapshot() }.value
            guard try Self.settingsPage(of: latest, in: snapshot, scripted: isScripted(latest)) != nil,
                  let recipe = snapshot.recipes.first(where: { $0.id == id }) else {
                throw ConfigurationLibraryError.readOnlyRuleScheme
            }
            if let readScheme, recipe.ruleSchemeID != readScheme {
                throw PipelineError.sourceUnavailable("This configuration changed while its settings were open. Reopen them and try again.")
            }
            let scheme = snapshot.rules.first { $0.id == recipe.ruleSchemeID }
                ?? ConfigurationBuiltins.schemes.first { $0.id == recipe.ruleSchemeID }
            let running = try ConfigurationSchemePage.effective(of: recipe, scheme: scheme)
            let before = running.settings.removingTopLevel("dns").settingTopLevel("dns", to: running.dns)
            let placed = edits.map { edit -> ConfigurationPageEdit in
                guard case .set(let path, let node) = edit, path.count == 1 else { return edit }
                return .set(path: path, to: Self.pageNode(node, for: path[0], replacing: before.topLevelValue(path[0])))
            }
            guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
            changingConfigurationLibrary = true
            defer { changingConfigurationLibrary = false }
            do {
                let prepared = try await Task.detached(priority: .userInitiated) {
                    try library.prepareSchemePageEdit(profileID: id, expectedGeneration: snapshot.generation,
                                                      resolveInput: ConfigurationCenterSourceBridge.BoundInputs().resolve) { page in
                        for edit in placed { page = try page.applying(edit) }
                    }
                }.value
                try await saveConfigurationPlan(candidate: prepared.candidate, payloads: prepared.payloads,
                                                compositions: prepared.compositions, generation: snapshot.generation)
                return
            } catch ConfigurationLibraryError.staleGeneration where attempt < 3 {
                continue
            }
        }
    }

     
     
     
     
    nonisolated static func compileConfiguration(
        _ id: String, containerURL: URL? = ClashAppIdentifiers.appGroupContainer
    ) async -> ConfigurationCompileAnswer {
        await Task.detached(priority: .userInitiated) {
            guard let container = containerURL,
                  let input = OfflineProxyCatalogLoader.input(containerURL: container, preferredProfileID: id),
                  input.profileID == id else {
                return .unavailable(nil)
            }
            do { try AppCoreSetup.ensure(container: container) } catch { return .unavailable(error.localizedDescription) }
            var error: NSError?
            guard let answer = AppCore.compileCheck(input.configContent, input.resourceMapJSON, &error) else {
                return .unavailable(error?.localizedDescription)
            }
            return .decode(answer.value)
        }.value
    }

     
     
    private func changingTheLibrary(
        _ change: @escaping (ConfigurationLibraryStore, UInt64) async throws -> Void
    ) async throws {
        await settleLibraryHousekeeping()
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        let generation = try await Task.detached(priority: .userInitiated) { try library.snapshot().generation }.value
        try await change(library, generation)
    }
}
