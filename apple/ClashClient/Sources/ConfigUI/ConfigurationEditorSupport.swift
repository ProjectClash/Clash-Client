import Combine
import Foundation
import ClashClientKit
import ClashClientUI

 
 
 
 
enum ConfigurationKnownValues {
    static func values(for set: ConfigurationKnownValueSet,
                       homeDir: URL? = GeoCategoryIndex.coreHomeDir()) async -> [String] {
        switch set {
        case .geosite:
            return await GeoCategoryCache.shared.categories(for: .geosite, homeDir: homeDir)
        case .geoip:
             
            return await GeoCategoryCache.shared.categories(for: .geoip, homeDir: homeDir).map { $0.uppercased() }
        }
    }
}

 
 
 
 
extension ProfilesViewModel {
    struct ConfigurationEditorPage: Equatable {
        enum Form: Equatable {
             
            case composed(scheme: ConfigurationRuleScheme, ownership: ConfigurationSchemePageOwnership)
             
            case original
        }
        let profileID: String
        let label: String
        let form: Form
        let rows: [ConfigurationOutlineRow]
         
         
        let document: OrderedJSON
         
         
        var followsSubscription = false
         
         
        var readDigest: String? = nil
         
         
         
         
        var ownLayer: OrderedJSON? = nil
         
         
         
        var ownDNSSwitch: Bool? = nil
         
         
        var followedLink: String? = nil
         
         
         
        var keptRules: KeptRules? = nil
         
         
         
         
         
         
         
        var schemeChoices: [ConfigurationRuleScheme] = []
         
         
         
        var sourceTooLargeToReadWhole = false

         
         
        var opensEditSource: Bool { keptRules == nil && !sourceTooLargeToReadWhole }

        struct KeptRules: Equatable, Sendable {
             
            let count: Int
             
            let file: URL
        }
    }

     
     
    nonisolated static func ownDNSSwitch(of profile: Profile) -> Bool? {
        guard OverridePatch(patchJSON: profile.legacyRuntimePatchJSON ?? "").hasDNSOverride else { return nil }
        return profile.legacyRuntimeDNSGated != true
    }

     
     
     
     
     
     
    func loadConfigurationEditorPage(profileID: String, withMenu: Bool = false) async throws -> ConfigurationEditorPage {
        let (loaded, snapshot) = try await loadingConfigurationEditorPage(profileID: profileID)
        var page = loaded
        if withMenu {
            var running: ConfigurationRuleScheme?
            if case .composed(let scheme, _) = page.form { running = scheme }
            page.schemeChoices = await Task.detached(priority: .userInitiated) { [running] in
                Self.menuChoices(Self.schemeChoices(snapshot, for: snapshot.recipes.first { $0.id == profileID }),
                                 running: running)
            }.value
        }
        let profile = profiles.first { $0.id == profileID }
        let workingDir = self.workingDir
        page.sourceTooLargeToReadWhole = await Task.detached(priority: .userInitiated) {
            profile.map { Self.sourceIsTooLargeToReadWhole($0, workingDir: workingDir) } ?? false
        }.value
        return page
    }

    private func loadingConfigurationEditorPage(profileID: String) async throws -> (ConfigurationEditorPage, ConfigurationLibrarySnapshot) {
        guard let library = configurationLibraryStore,
              let profile = profiles.first(where: { $0.id == profileID }) else {
            throw PipelineError.sourceUnavailable("the profile is no longer available")
        }
        let outline: (rows: [ConfigurationOutlineRow], original: (json: String, document: OrderedJSON)?)
        do {
            outline = try await configurationOutlineReading(profileID, customRules: profile.override.appendRules.count)
        } catch ConfigurationLibraryError.missingDependency(let missing) where missing == profileID {
             
             
             
             
             
             
            do { try await registerLegacyConfigurationSources() } catch {
                ClashLogStore.shared.append(#"configuration page: registering before reading its own file failed: \#(error.localizedDescription)"#,
                                            stream: .app)
            }
            outline = try await configurationOutlineReading(profileID, customRules: profile.override.appendRules.count,
                                                            readingItsOwnFile: true)
        }
        let rows = outline.rows
        let snapshot = try await Task.detached(priority: .userInitiated) { try library.snapshot() }.value
         
         
         
        let latest = (try? latestProfile(profileID)) ?? profile
         
         
        let own = await Task.detached(priority: .userInitiated) { () -> OrderedJSON in
            Self.ownSettings(of: latest)
        }.value
        if let recipe = snapshot.recipes.first(where: { $0.id == profileID }), recipe.preservesOriginal != true {
            guard let scheme = snapshot.rules.first(where: { $0.id == recipe.ruleSchemeID })
                    ?? ConfigurationBuiltins.schemes.first(where: { $0.id == recipe.ruleSchemeID }) else {
                throw ConfigurationLibraryError.missingDependency(recipe.ruleSchemeID)
            }
            let scripted = isScripted(latest)
            let (page, onPage) = try await Task.detached(priority: .userInitiated) { () throws -> (OrderedJSON, Bool) in
                let running = try ConfigurationSchemePage.effective(of: recipe, scheme: scheme)
                return (running.settings.removingTopLevel("dns").settingTopLevel("dns", to: running.dns),
                        try Self.settingsPage(of: latest, in: snapshot, scripted: scripted) != nil)
            }.value
            return (ConfigurationEditorPage(profileID: profileID, label: profile.label,
                form: .composed(scheme: scheme, ownership: snapshot.schemePageOwnership(profileID: profileID)),
                rows: rows, document: page, ownLayer: onPage ? nil : own,
                ownDNSSwitch: onPage ? nil : Self.ownDNSSwitch(of: latest),
                followedLink: snapshot.followedLinkLabel(ofScheme: scheme.id)), snapshot)
        }
        let outlined = outline.original
         
         
        let source = snapshot.recipes.first { $0.id == profileID }.flatMap { recipe in
            snapshot.sources.first { $0.id == recipe.ruleSource.id }
        }
        var followsSubscription = false
        if let source {
            if case .subscription = source.origin, source.isRetainedSnapshot != true { followsSubscription = true }
        } else if case .url = latest.source {
            followsSubscription = true
        }
         
         
         
         
         
         
        if let source, source.rulesWrittenInOriginal == true, let outlined,
           let recipe = snapshot.recipes.first(where: { $0.id == profileID }) {
            let file = try library.originalURL(recipe.ruleSource)
            let digest = try await Task.detached(priority: .userInitiated) { try Self.textDigest(fileAt: file) }.value
            return (ConfigurationEditorPage(profileID: profileID, label: profile.label, form: .original,
                                           rows: rows, document: outlined.document, followsSubscription: followsSubscription,
                                           readDigest: digest, ownLayer: own, ownDNSSwitch: Self.ownDNSSwitch(of: latest),
                                           keptRules: .init(count: source.ruleCount, file: file)), snapshot)
        }
        guard let text = await loadSourceYAML(for: profile) else {
            throw PipelineError.sourceUnavailable("The saved configuration is unavailable.")
        }
        let (document, digest) = try await Task.detached(priority: .userInitiated) { () throws -> (OrderedJSON, String) in
            let json = try ConfigTransforms.yamlToJSON(text)
             
             
            let document = try outlined.flatMap { $0.json == json ? $0.document : nil } ?? OrderedJSON.parse(json)
            return (document, Self.textDigest(text))
        }.value
        return (ConfigurationEditorPage(profileID: profileID, label: profile.label, form: .original,
                                       rows: rows, document: document, followsSubscription: followsSubscription,
                                       readDigest: digest, ownLayer: own, ownDNSSwitch: Self.ownDNSSwitch(of: latest)), snapshot)
    }



     
     
     
     
     
     
    nonisolated static func ownSettings(of profile: Profile) -> OrderedJSON {


         
         
         
        var own = OverridePatch(patchJSON: profile.override.patchJSON).profileOwnedPatch
        let layer = OverridePatch(patchJSON: profile.legacyRuntimePatchJSON ?? "")
        for key in layer.topLevelKeys {
            guard let value = layer.topLevelNode(key) else { continue }
            own.setTopLevelNode(key, mergedAsTheCoreMerges(own.topLevelNode(key), value))
        }
        return (try? OrderedJSON.parse(own.patchJSON)) ?? .object([])
    }

     
     
     
     
     
     
     
     
    func editConfigurationSettings(_ id: String, edits: [ConfigurationPageEdit], readScheme: String? = nil) async throws {
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        await settleLibraryHousekeeping()
        let latest = try latestProfile(id)
        let scripted = isScripted(latest)
        let onPage = try await Task.detached(priority: .userInitiated) {
            try Self.settingsPage(of: latest, in: library.snapshot(), scripted: scripted) != nil
        }.value
        switch (onPage, readScheme) {
        case (true, .some):
            try await editConfigurationPage(id, edits: edits, readScheme: readScheme)
        case (false, nil):
             
             
            try updateOwnSettings(profileID: id, edits: edits)
        default:
            throw PipelineError.sourceUnavailable("This configuration changed while its settings were open. Reopen them and try again.")
        }
    }

     
     
     
     
    nonisolated static func menuChoices(_ choices: [ConfigurationRuleScheme],
                                        running: ConfigurationRuleScheme?) -> [ConfigurationRuleScheme] {
        guard let running, !choices.contains(where: { $0.id == running.id }) else { return choices }
        return [running] + choices
    }

     
     
     
     
     
     
    nonisolated static func schemeChoices(_ snapshot: ConfigurationLibrarySnapshot,
                                          for recipe: ConfigurationRecipe?) -> [ConfigurationRuleScheme] {
        schemeChoices(snapshot, keeping: recipe?.preservesOriginal == true ? nil : recipe?.ruleSchemeID, profileID: recipe?.id)
    }

     
     
     
     
     
     
     
     
     
    nonisolated static func schemeChoices(_ snapshot: ConfigurationLibrarySnapshot, keeping current: String?,
                                          profileID: String? = nil) -> [ConfigurationRuleScheme] {
        let visible = Set(snapshot.visibleRuleSchemes.map(\.id))
        let builtinIDs = Set(ConfigurationBuiltins.schemes.map(\.id))
        var choices = schemeChoices(library: snapshot.rules).filter { builtinIDs.contains($0.id) || visible.contains($0.id) }
         
        let order = Dictionary(snapshot.visibleRuleSchemes.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        let builtins = choices.prefix { builtinIDs.contains($0.id) }
        choices = Array(builtins) + choices.dropFirst(builtins.count).sorted { (order[$0.id] ?? .max) < (order[$1.id] ?? .max) }
        choices = snapshot.placingOwnViews(in: choices, for: profileID, running: current)
         
         
         
        guard let current, !choices.contains(where: { $0.id == current }),
              let kept = snapshot.rules.first(where: { $0.id == current }),
              !snapshot.keepsRulesInOriginal(kept) else { return choices }
        let family = kept.baseSchemeID ?? kept.id
        if kept.isRetainedSnapshot != true, let index = choices.firstIndex(where: {
            ConfigurationBuiltins.isNative(family) ? $0.id == kept.id : ($0.baseSchemeID ?? $0.id) == family
        }) {
            choices[index] = kept
        } else {
            choices.append(kept)
        }
        return choices
    }

     
     
     
     
    nonisolated static func schemeChoices(library rules: [ConfigurationRuleScheme]) -> [ConfigurationRuleScheme] {
        let listed = rules.filter(\.isListedInLibrary)
        let builtinIDs = Set(ConfigurationBuiltins.schemes.map(\.id))
        let builtins = ConfigurationBuiltins.schemes.map { builtin in listed.first { $0.id == builtin.id } ?? builtin }
        return builtins + listed.filter { !builtinIDs.contains($0.id) }
    }

     
     
    func configurationExportText(profileID: String) async throws -> String {
        guard let profile = profiles.first(where: { $0.id == profileID }),
              let text = await loadSourceYAML(for: profile) else {
            throw PipelineError.sourceUnavailable("The saved configuration is unavailable.")
        }
        return text
    }

     

     
     
    struct SyntaxCatalog: Decodable, Equatable {
        struct RuleType: Decodable, Equatable {
            let name: String
            let payload: String
            let options: [String]?
            let logical: Bool?
            let matchesHere: Bool?
        }
        struct GroupType: Decodable, Equatable {
            let name: String
            let fields: [String]?
            let enums: [String: [String]]?
        }
        struct RuleProvider: Decodable, Equatable {
            let types: [String]?
            let behaviors: [String]?
            let formats: [String]?
            let fields: [String]?
        }
         
        typealias PlatformKey = ConfigurationPlatformKey
        let schemaVersion: Int
        let ruleTypes: [RuleType]
        let groupTypes: [GroupType]
        let ruleProvider: RuleProvider
        let dnsEnhancedModes: [String]?
        let snifferProtocols: [String]?
        let platformDecidedKeys: [PlatformKey]?
         
         
         
        let fields: [ConfigurationField]?
         
         
        let fieldCatalog: ConfigurationFieldCatalog?

        private enum CodingKeys: String, CodingKey {
            case schemaVersion, ruleTypes, groupTypes, ruleProvider, dnsEnhancedModes, snifferProtocols
            case platformDecidedKeys, fields
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            ruleTypes = try container.decode([RuleType].self, forKey: .ruleTypes)
            groupTypes = try container.decode([GroupType].self, forKey: .groupTypes)
            ruleProvider = try container.decode(RuleProvider.self, forKey: .ruleProvider)
            dnsEnhancedModes = try container.decodeIfPresent([String].self, forKey: .dnsEnhancedModes)
            snifferProtocols = try container.decodeIfPresent([String].self, forKey: .snifferProtocols)
            platformDecidedKeys = try container.decodeIfPresent([PlatformKey].self, forKey: .platformDecidedKeys)
             
            fields = (try? container.decodeIfPresent([Lenient<ConfigurationField>].self, forKey: .fields))?
                .compactMap(\.value)
             
            let keys = platformDecidedKeys ?? []
            fieldCatalog = fields.flatMap { $0.isEmpty ? nil : ConfigurationFieldCatalog(fields: $0, platformKeys: keys) }
        }

        static func == (lhs: SyntaxCatalog, rhs: SyntaxCatalog) -> Bool {
            lhs.schemaVersion == rhs.schemaVersion && lhs.ruleTypes == rhs.ruleTypes && lhs.groupTypes == rhs.groupTypes
                && lhs.ruleProvider == rhs.ruleProvider && lhs.dnsEnhancedModes == rhs.dnsEnhancedModes
                && lhs.snifferProtocols == rhs.snifferProtocols && lhs.platformDecidedKeys == rhs.platformDecidedKeys
                && lhs.fields == rhs.fields
        }

        private struct Lenient<Value: Decodable>: Decodable {
            let value: Value?
            init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
        }

         
        func field(at steps: [ConfigurationDocumentStep], in document: OrderedJSON) -> ConfigurationField? {
            fieldCatalog?.field(at: steps, in: document)
        }

         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        func platformReason(for path: [String], in document: OrderedJSON? = nil) -> String? {
            let dotted = path.joined(separator: ".")
            if schemaVersion >= 3 {
                guard let decision = fieldCatalog?.platformDecision(forPath: path, in: document), decision.overridesTheFile
                else { return nil }
                return decision.reason ?? ""
            }
            if let keys = platformDecidedKeys {
                return keys.first { $0.path == dotted && $0.overridesTheFile }?.reason
            }
            guard let field = fieldCatalog?.field(atCatalogPath: dotted), field.isPlatformDecided else { return nil }
            return field.platformReason ?? ""
        }

         
         
         
         
        func conditionalEffective(for path: [String], in document: OrderedJSON?, conditions: Set<String>) -> String? {
            guard schemaVersion >= 3,
                  let decision = fieldCatalog?.conditionalDecision(forPath: path, in: document, conditions: conditions)
            else { return nil }
            return decision.effective ?? ""
        }

         
        func choices(for path: [String]) -> [String]? {
            switch path {
            case ["dns", "enhanced-mode"]: return dnsEnhancedModes
            default: return nil
            }
        }
    }

     
     
     
     
    nonisolated private static let catalogLock = NSLock()
    nonisolated(unsafe) private static var catalogMemo: SyntaxCatalog?

     
    nonisolated static var rememberedSyntaxCatalog: SyntaxCatalog? {
        catalogLock.lock()
        defer { catalogLock.unlock() }
        return catalogMemo
    }

    private nonisolated static func rememberSyntaxCatalog(_ catalog: SyntaxCatalog) {
        catalogLock.lock()
        defer { catalogLock.unlock() }
        catalogMemo = catalog
    }

     
     
    nonisolated static func loadSyntaxCatalog() async throws -> SyntaxCatalog {
        if let remembered = rememberedSyntaxCatalog { return remembered }
        let catalog = try await Task.detached(priority: .userInitiated) { () throws -> SyntaxCatalog in
            let text = try ConfigTransforms.syntaxCatalog(targetProfile: clashAppleRuntimeProfile.rawValue)
            return try JSONDecoder().decode(SyntaxCatalog.self, from: Data(text.utf8))
        }.value
        rememberSyntaxCatalog(catalog)
        return catalog
    }
}

 
 
 
 
 
 
enum ConfigurationSectionKeys {
     
     
     
     
     
     
    static let changedOnOtherPages: Set<String> = OverridePatch.listenerKeys
        .union(["mode", "log-level"])

     
     
     
     
     
    static let lanShareKeys: Set<String> = OverridePatch.listenerKeys.union(lanShareAccessKeys)

     
    static let lanShareAccessKeys = ["bind-address", "authentication", "skip-auth-prefixes", "lan-allowed-ips",
                                     "lan-disallowed-ips"]

     
     
     
    static var lanSharePageOwnsItsKeys: Bool { true }

     
     
     
     
     
     
    static func changedElsewhere(for section: ConfigurationOutlineSection, original: Bool) -> Set<String> {
        var keys = changedOnOtherPages
            .union(ConfigurationOutline.knownTopLevelKeys.filter { ConfigurationOutline.section(forTopLevelKey: $0) != section })
        if section == .general, original { keys.insert("tls") }
        return keys
    }

     
     
     
     
     
     
     
    static func owner(of key: String, in section: ConfigurationOutlineSection, original: Bool) -> ConfigurationKeyOwner? {
        owner(at: [key], in: section, original: original)
    }

     
     
     
    static func owner(at path: [String], in section: ConfigurationOutlineSection, original: Bool) -> ConfigurationKeyOwner? {
        if path.count == 2, path[0] == "tun" { return tunnelPageKeys.contains(path[1]) ? .tunnelAndRoutes : nil }
        guard path.count == 1, let key = path.first else { return nil }
        if OverridePatch.listenerKeys.contains(key) { return .lanSharing }
        switch key {
         
         
        case "tls" where original: return .certificatesAndTrust
        default: return nil
        }
    }
}

 
 
 
 
 
 
struct ConfigurationSectionLayout: Equatable {
    struct Row: Identifiable, Equatable {
        enum Control: Equatable {
             
            case inline
             
             
            case page
             
             
            case drill
             
            case owned(ConfigurationKeyOwner)
             
             
            case platform(String)
        }
        let key: String
        let path: [String]
        let field: ConfigurationField?
         
        let value: OrderedJSON?
        let control: Control
         
         
        var conditionalEffective: String? = nil
        var id: String { path.joined(separator: ".") }

         
        var isPlatformDecided: Bool {
            if case .platform = control { return true }
            return false
        }
    }

    struct Group: Identifiable, Equatable {
        enum Title: Equatable {
            case none
             
            case copy(String)
             
            case key(String)
             
             
            case words(String)
        }
        let id: String
        let title: Title
        var rows: [Row]
         
         
         
        var path: [String] = []
         
         
        var footer: String? = nil
    }

    let groups: [Group]
     
     
     
     
    var platformDecided: [Row] = []

     
     
    static let menuLimit = 12

     
     
     
    static let generalGroups: [(title: String, keys: [String])] = [
        ("Outbound", ["mode"]),
        ("Log", ["log-level"]),
        ("Connection", ["ipv6", "unified-delay", "tcp-concurrent", "disable-keep-alive", "keep-alive-idle",
                        "keep-alive-interval", "geosite-matcher"]),
        ("LAN Proxy Share", ["allow-lan", "bind-address", "authentication", "skip-auth-prefixes", "lan-allowed-ips",
                             "lan-disallowed-ips"]),
        ("Process Lookup", ["find-process-mode"]),
    ]

     
    static func key(of field: ConfigurationField) -> String {
        field.path.split(separator: ".").last.map(String.init) ?? field.path
    }

     
     
     
    static func base(of section: ConfigurationOutlineSection) -> [String] { [] }

     
     
     
     
    static func isInline(_ field: ConfigurationField, value: OrderedJSON?, in document: OrderedJSON) -> Bool {
        switch field.kind {
        case .toggle, .select, .reference: break
#if os(iOS)
         
         
        case .number, .text: break
#endif
        default: return false
        }
        guard let draft = ConfigurationFieldDraft(field: field, value: value, in: document) else { return false }
        switch draft.control {
        case .toggle: return true
        case .select, .reference: return draft.choices.count <= menuLimit
        case .number, .text: return ConfigurationPresetMenuRow.applies(to: draft)
        default: return false
        }
    }

     
     
    static func entryField(of basePath: [String], in document: OrderedJSON,
                           catalog: ProfilesViewModel.SyntaxCatalog?) -> ConfigurationField? {
        guard !basePath.isEmpty, let fieldCatalog = catalog?.fieldCatalog,
              fieldCatalog.field(at: basePath.map(ConfigurationDocumentStep.key), in: document)?.kind == .map
        else { return nil }
        return fieldCatalog.field(at: (basePath + ["\u{1F}"]).map(ConfigurationDocumentStep.key), in: document)
    }

     
     
    static func make(section: ConfigurationOutlineSection, basePath: [String], document: OrderedJSON,
                     catalog: ProfilesViewModel.SyntaxCatalog?, original: Bool,
                     conditions: Set<String> = []) -> ConfigurationSectionLayout {
        splittingOffThePlatformsRows(of: laidOut(section: section, basePath: basePath, document: document,
                                                 catalog: catalog, original: original, conditions: conditions))
    }

     
     
     
     
     
     
    func arranged(by copy: ConfigurationFieldCopy, locale: Locale, catalog: ProfilesViewModel.SyntaxCatalog?,
                  document: OrderedJSON) -> ConfigurationSectionLayout {
        var arranged: [Group] = []
        for group in groups {
            guard !group.path.isEmpty else {
                arranged.append(group)
                continue
            }
            let object = catalog?.fieldCatalog?.field(at: group.path.map(ConfigurationDocumentStep.key), in: document)
            let catalogPath = object?.path ?? group.path.joined(separator: ".")
            guard let sections = copy.layout(forPath: catalogPath, locale: locale) else {
                var kept = group
                if let summary = copy.entry(for: object, locale: locale)?.summary, !summary.isEmpty { kept.footer = summary }
                arranged.append(kept)
                continue
            }
            let byKey = Dictionary(group.rows.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
            for section in ConfigurationFieldCopy.arrange(group.rows.map(\.key), in: sections) {
                let title: Group.Title
                switch section.title {
                case .verbatim(let words)?: title = .words(words)
                case .copy(let key)?: title = .copy(key)
                default: title = .none
                }
                arranged.append(Group(id: group.id + "#" + section.id, title: title,
                                      rows: section.keys.compactMap { byKey[$0] }, footer: section.footer))
            }
        }
        return ConfigurationSectionLayout(groups: arranged, platformDecided: platformDecided)
    }

     
     
    static func splittingOffThePlatformsRows(of layout: ConfigurationSectionLayout) -> ConfigurationSectionLayout {
        var platform: [Row] = []
        let groups = layout.groups.compactMap { group -> Group? in
            var group = group
            platform += group.rows.filter(\.isPlatformDecided)
            group.rows.removeAll(where: \.isPlatformDecided)
            return group.rows.isEmpty ? nil : group
        }
        return ConfigurationSectionLayout(groups: groups, platformDecided: platform)
    }

    private static func laidOut(section: ConfigurationOutlineSection, basePath: [String], document: OrderedJSON,
                                catalog: ProfilesViewModel.SyntaxCatalog?, original: Bool,
                                conditions: Set<String>) -> ConfigurationSectionLayout {
        let builder = Builder(section: section, document: document, catalog: catalog,
                              original: original, conditions: conditions)
        let steps = basePath.map(ConfigurationDocumentStep.key)
         
        if !basePath.isEmpty, catalog?.fieldCatalog?.field(at: steps, in: document)?.kind == .map {
            var loose: [Row] = []
            var groups: [Group] = []
            for entry in builder.written(at: basePath) {
                let path = basePath + [entry.key]
                if case .object = entry.value {
                    groups += builder.objectGroups(key: entry.key, path: path, title: entry.key, idPrefix: "entry", depth: 0)
                } else {
                    loose.append(builder.row(key: entry.key, path: path, field: nil, value: entry.value))
                }
            }
            return ConfigurationSectionLayout(groups: (loose.isEmpty ? [] : [Group(id: "entries", title: .none, rows: loose)]) + groups)
        }
        let (listed, objects) = builder.rowsAndObjects(at: basePath, depth: 0)
         
         
        let rows = basePath.isEmpty && ConfigurationSectionKeys.lanSharePageOwnsItsKeys
            ? listed.filter { !ConfigurationSectionKeys.lanShareKeys.contains($0.key) } : listed
        guard basePath.isEmpty, section == .general else {
            let main = rows.isEmpty ? [] : [Group(id: "main", title: .none, rows: rows)]
             
             
            if basePath.isEmpty, section == .dns { return ConfigurationSectionLayout(groups: objects + main) }
            return ConfigurationSectionLayout(groups: main + objects)
        }
        var groups: [Group] = []
        var placed: Set<String> = []
        for (title, keys) in generalGroups {
             
            let members = keys.compactMap { key in rows.first { $0.key == key } }
            placed.formUnion(members.map(\.key))
            if !members.isEmpty { groups.append(Group(id: title, title: .copy(title), rows: members)) }
        }
        let rest = rows.filter { !placed.contains($0.key) }
        if !rest.isEmpty { groups.append(Group(id: "Other Fields", title: .copy("Other Fields"), rows: rest)) }
        return ConfigurationSectionLayout(groups: groups + objects)
    }

    private struct Builder {
        let section: ConfigurationOutlineSection
        let document: OrderedJSON
        let catalog: ProfilesViewModel.SyntaxCatalog?
        let original: Bool
        let conditions: Set<String>

         
        func written(at path: [String]) -> [(key: String, value: OrderedJSON)] {
            guard case .object(let entries)? = document.node(at: path) else { return [] }
            var seen: Set<String> = []
            let latest = entries.reversed().filter { seen.insert($0.key).inserted }.reversed()
            guard path.isEmpty else { return Array(latest) }
            return latest.filter { ConfigurationOutline.section(forTopLevelKey: $0.key) == section }
        }

         
         
         
        func keys(at path: [String]) -> [(key: String, field: ConfigurationField?)] {
            var keys: [(key: String, field: ConfigurationField?)] = []
            if let fieldCatalog = catalog?.fieldCatalog {
                keys = fieldCatalog.children(of: path.map(ConfigurationDocumentStep.key), in: document)
                    .map { (ConfigurationSectionLayout.key(of: $0), Optional($0)) }
                    .filter { !path.isEmpty || ConfigurationOutline.section(forTopLevelKey: $0.key) == section }
            } else if path.isEmpty {
                keys = ConfigurationOutline.settingKeys(in: section).map { ($0, nil) }
            }
            var known = Set(keys.map(\.key))
            for entry in written(at: path) where known.insert(entry.key).inserted {
                keys.append((entry.key, nil))
            }
             
             
             
            if path == ["dns"] {
                keys.removeAll { entry in
                    DNSConfigurationFieldCatalog.iOSManagedKeys.contains(entry.key)
                        && catalog?.platformReason(for: path + [entry.key], in: document) == nil
                }
            }
            return keys
        }

        func rowsAndObjects(at path: [String], depth: Int) -> (rows: [Row], objects: [Group]) {
            let values = Dictionary(written(at: path).map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
            var rows: [Row] = []
            var objects: [Group] = []
            for (key, field) in keys(at: path) {
                let child = path + [key]
                let value = values[key]
                let isObject: Bool
                switch value {
                case nil, .object?: isObject = field?.kind == .object
                default: isObject = false
                }
                if isObject, depth < 4, owner(of: key, under: path) == nil,
                   catalog?.platformReason(for: child, in: document) == nil {
                    objects += objectGroups(key: key, path: child, title: child.suffix(depth + 1).joined(separator: "."),
                                            idPrefix: "object", depth: depth + 1)
                } else {
                    rows.append(row(key: key, path: child, field: field, value: value))
                }
            }
            return (rows, objects)
        }

         
         
        func objectGroups(key: String, path: [String], title: String, idPrefix: String, depth: Int) -> [Group] {
            let (rows, objects) = rowsAndObjects(at: path, depth: depth)
             
            return [Group(id: idPrefix + ":" + path.joined(separator: "."), title: .key(title), rows: rows,
                          path: idPrefix == "entry" ? [] : path)] + objects
        }

        func owner(of key: String, under parent: [String]) -> ConfigurationKeyOwner? {
            ConfigurationSectionKeys.owner(at: parent + [key], in: section, original: original)
        }

        func row(key: String, path: [String], field: ConfigurationField?, value: OrderedJSON?) -> Row {
            let control: Row.Control
            if let owner = owner(of: key, under: Array(path.dropLast())) {
                control = .owned(owner)
            } else if let reason = catalog?.platformReason(for: path, in: document) {
                control = .platform(reason)
            } else if let field, field.kind == .map || field.kind == .objectList {
                control = .drill
            } else if field == nil, case .object? = value {
                control = .drill
            } else if let field, ConfigurationSectionLayout.isInline(field, value: value, in: document) {
                control = .inline
            } else {
                control = .page
            }
            return Row(key: key, path: path, field: field, value: value, control: control,
                       conditionalEffective: catalog?.conditionalEffective(for: path, in: document, conditions: conditions))
        }
    }
}

extension ConfigurationSectionKeys {
     
     
    static let tunnelPageKeys: Set<String> = [
        "route-address", "route-exclude-address", "route-address-set", "route-exclude-address-set",
        "inet6-address", "loopback-address", "strict-route", "endpoint-independent-nat", "udp-timeout", "icmp-timeout",
    ]
}

 
 
enum ConfigurationKeyOwner: String, Equatable, Sendable, CaseIterable {
     
    case tunnelAndRoutes
     
    case lanSharing
     
    case clientSettings
     
    case certificatesAndTrust
}

 
 
 
 
 
enum ConfigurationLANShareStatus {
     
     
     
    static func words(override: KernelLANShareOverride, document: OrderedJSON,
                      modules: KernelLANShareOverride = KernelLANShareOverride()) -> ClashDisplayText {
        func port(_ key: String) -> Int32? {
            switch document.node(at: [key]) {
            case .scalar(let token)?: return Int32(token)
            case .string(let text)?: return Int32(text)
            default: return nil
            }
        }
        let written: Bool
        switch document.node(at: ["allow-lan"]) {
        case .scalar("true")?, .string("true")?: written = true
        default: written = false
        }
         
         
         
         
         
        let mixed: Int32? = override.mixedPort ?? modules.mixedPort ?? port("mixed-port")
        let http: Int32? = override.httpPort ?? modules.httpPort ?? port("port")
        let socks: Int32? = override.socksPort ?? modules.socksPort ?? port("socks-port")
        guard let open = [mixed, http, socks].compactMap({ $0 }).first(where: { (1...65535).contains($0) }) else {
            return .copy("No Ports Open")
        }
         
         
        let ownAddressOnly: Bool
        switch document.node(at: ["bind-address"]) {
        case .string(let address)?, .scalar(let address)?:
            ownAddressOnly = ProxyShareAddressList.isThisDeviceOnly(address.trimmingCharacters(in: CharacterSet(charactersIn: "[] ")))
                || address.lowercased() == "localhost"
        default: ownAddressOnly = false
        }
        let allowsLAN = (override.allowLAN ?? modules.allowLAN ?? written) && !ownAddressOnly
        return .format(allowsLAN ? "LAN Allowed · %@" : "This Device Only · %@", [String(open)])
    }

     
     
    static func matches(_ query: String, copy: ConfigurationFieldCopy, locale: Locale) -> Bool {
        let language = ConfigurationFieldCopy.Language(locale: locale)
        let words = [ClashCopy.string("LAN Proxy Share", locale: locale)]
            + ConfigurationSectionKeys.lanShareKeys.flatMap { [$0, copy.entry(forPath: $0, language: language)?.title ?? ""] }
        return words.contains { !$0.isEmpty && $0.lowercased().contains(query) }
    }
}

 
 
 
 
@MainActor
final class KeptRulesPager: ObservableObject {
    @Published private(set) var rules: [PublishedRules.Entry] = []
    @Published private(set) var matched: Int?
    @Published private(set) var total: Int?
    @Published private(set) var loading = false
    @Published private(set) var failure: String?
    private(set) var query = ""
    private var opening: Task<PublishedRules.Catalog, Error>?
    private var generation = 0

    func load(file: URL, query: String) async {
        generation += 1
        let mine = generation
        loading = true
        defer { if mine == generation { loading = false } }
        do {
            let catalog = try await opened(file)
            let page = try await Task.detached(priority: .userInitiated) { try catalog.page(offset: 0, query: query) }.value
            guard mine == generation else { return }
            self.query = query
            rules = page.rules
            matched = page.matched
            if query.trimmingCharacters(in: .whitespaces).isEmpty { total = page.total }
            failure = nil
        } catch {
            guard mine == generation else { return }
            rules = []
            matched = nil
             
             
            ClashLogStore.shared.append("kept rules: \(error.localizedDescription)", stream: .app, level: .warning)
            failure = PublishedRules.Unreadable().errorDescription
        }
    }

     
    func more() async {
        guard !loading, let opening, let matched, rules.count < matched else { return }
        let mine = generation
        let offset = rules.count
        let query = self.query
        loading = true
        defer { if mine == generation { loading = false } }
        guard let catalog = try? await opening.value,
              let page = try? await Task.detached(priority: .userInitiated, operation: {
                  try catalog.page(offset: offset, query: query)
              }).value,
              mine == generation else { return }
        rules += page.rules
    }

    func close() {
        generation += 1
        let opening = self.opening
        self.opening = nil
        Task.detached { (try? await opening?.value)?.close() }
    }

    private func opened(_ file: URL) async throws -> PublishedRules.Catalog {
        if let opening { return try await opening.value }
        let task = Task.detached(priority: .userInitiated) { try PublishedRules.open(sourceAt: file) }
        opening = task
        do {
            return try await task.value
        } catch {
            if opening == task { opening = nil }
            throw error
        }
    }
}

 
 
 
 
 
struct ScriptedSettings: Equatable, Sendable {
    let with: OrderedJSON
    let without: OrderedJSON

     
     
    func change(at path: [String]) -> OrderedJSON?? {
        let after = with.node(at: path)
        return after == without.node(at: path) ? nil : .some(after)
    }

     
    func changes(within path: [String]) -> Bool {
        with.node(at: path) != without.node(at: path)
    }

     
    static let bulk: Set<String> = ["proxies", "proxy-groups", "rules", "proxy-providers", "rule-providers", "sub-rules"]

     
    static func runs(on profile: Profile) -> Bool {
        (profile.overwriteMode == .script && profile.selectedScriptID != nil) || profile.postMergeScriptID != nil
            || ScriptSettings.enabled()
    }

     
    static func make(raw: String, profile: Profile) -> ScriptedSettings? {
        let unchanged: (String?, String, String) throws -> String = { _, yaml, _ in yaml }
        guard let scripted = try? ProfileRuntimeConfigBuilder.buildProduction(raw: raw, profile: profile, scripts: .silent),
              let plain = try? ProfileRuntimeConfigBuilder.build(
                  raw: raw, profile: profile, globalOverride: GlobalConfig.load(), runtimeOverride: FlClashRuntimeConfig.load(),
                  profileScript: unchanged, configScript: { yaml, _ in yaml }, postMergeScript: unchanged),
              let with = settings(of: scripted), let without = settings(of: plain) else { return nil }
        return with == without ? nil : ScriptedSettings(with: with, without: without)
    }

    private static func settings(of yaml: String) -> OrderedJSON? {
        guard case .object(let pairs)? = try? OrderedJSON.parse(ConfigTransforms.yamlToJSON(yaml)) else { return nil }
        return .object(pairs.filter { !bulk.contains($0.key) })
    }
}

 
 
 
 
 
enum ConfigurationRunsOverNote {
     
     
     
    static func words(path: [String], field: ConfigurationField?, opensPage: Bool, document: OrderedJSON,
                      modules: ModuleGlobalManifest?, held: Set<String>, scripted: ScriptedSettings?,
                      locale: Locale, copy: ConfigurationFieldCopy = .shared) -> ClashDisplayText? {
        func value(_ written: OrderedJSON?) -> String {
            ClashCopy.string(for: ConfigurationValueWords.summary(written, field: field, locale: locale, copy: copy, marksDefault: false),
                             locale: locale)
        }
        if let modules {
            if let note = modules.settingNote(at: path, in: document, held: held) {
                switch note.effect {
                case .sets(let written):
                    return .format("Module “%@” sets “%@”, which runs over this.", [note.module, value(written)])
                case .adds(let count):
                    return .format("Module “%@” adds %@ more.", [note.module, String(count)])
                }
            }
            if opensPage, let module = modules.moduleWriting(within: path) {
                return .format("Module “%@” changes settings in here.", [module])
            }
        }
        if let scripted {
             
             
            if opensPage { return scripted.changes(within: path) ? .copy("A script changes settings in here.") : nil }
            if let change = scripted.change(at: path) {
                return .format("A script sets “%@”, which runs over this.", [value(change)])
            }
        }
        return nil
    }
}

 
 
 
 
 
 
enum ConfigurationOutboundModeWords {
    static func title(_ mode: Profile.OutboundMode) -> String {
        switch mode {
        case .global: "Global"
        case .rule: "Rule"
        case .direct: "Direct"
        }
    }
}

 
 
 
enum ConfigurationEditorCopy {
     
     
     
     
    static func title(of section: ConfigurationOutlineSection) -> String {
        switch section {
        case .general: "General Configuration (Configuration Chapter)"
        case .dns: "DNS"
        case .sniffer: "Domain Sniffing (Configuration Chapter)"
        case .inbound: "Inbounds (Configuration Chapter)"
        case .proxies: "Proxies (Configuration Chapter)"
        case .proxyProviders: "Proxy Providers (Configuration Chapter)"
        case .proxyGroups: "Proxy Groups (Configuration Chapter)"
        case .rules: "Route Rules (Configuration Chapter)"
        case .ruleProviders: "Rule Providers (Configuration Chapter)"
        case .subRules: "Sub-rules"
        case .tunnels: "Tunnels (Configuration Chapter)"
        case .ntp: "NTP"
        case .experimental: "Experimental (Configuration Chapter)"
        case .unknown: "Unknown Keys"
        case .customRules: "Custom Rules"
        case .overrideScript: "Override Script"
        }
    }
}

 
 
 
 
 
 
 
 
struct PatchKeysSetElsewhere: LocalizedError, Equatable {
    enum Place: Hashable {
        case chapter(ConfigurationOutlineSection)
         
        case outboundMode
         
        case unavailable
    }

    struct Group: Equatable {
        let place: Place
        let keys: [String]
    }

    let groups: [Group]

    static let unavailableKeys: Set<String> = ["redir-port", "tproxy-port"]

    static func place(of key: String) -> Place {
        if unavailableKeys.contains(key) { return .unavailable }
        if key == "mode" { return .outboundMode }
        return .chapter(ConfigurationOutline.section(forTopLevelKey: key))
    }

     
    init?(patchJSON: String) {
        let keys = OverridePatch(patchJSON: patchJSON).topLevelKeys.filter(OverridePatch.globalRuntimeKeys.contains)
        guard !keys.isEmpty else { return nil }
        let order = ConfigurationOutlineSection.allCases.map(Place.chapter) + [.outboundMode, .unavailable]
        groups = order.compactMap { place in
            let here = keys.filter { Self.place(of: $0) == place }
            return here.isEmpty ? nil : Group(place: place, keys: here)
        }
    }

    private static let header = "Not saved. Set these on their own pages and remove them from Patch JSON:"
    private static let chapterLine = "%@ — this configuration's %@"
    private static let outboundModeLine = "%@ — Outbound Mode on Home"
    private static let unavailableLine = "%@ — not available on this device; remove them"
    static let copyKeys = [header, chapterLine, outboundModeLine, unavailableLine]

     
     
    var errorDescription: String? { sentence(locale: .current) }

     
    func sentence(locale: Locale) -> String {
         
        let separator = locale.identifier.hasPrefix("zh") ? "、" : ", "
        let lines = groups.map { group -> String in
            let keys = group.keys.joined(separator: separator)
            switch group.place {
            case .chapter(let section):
                let page = ClashCopy.string(ConfigurationEditorCopy.title(of: section), locale: locale)
                return ClashCopy.format(Self.chapterLine, locale: locale, keys, page)
            case .outboundMode:
                return ClashCopy.format(Self.outboundModeLine, locale: locale, keys)
            case .unavailable:
                return ClashCopy.format(Self.unavailableLine, locale: locale, keys)
            }
        }
        return ([ClashCopy.string(Self.header, locale: locale)] + lines).joined(separator: "\n")
    }
}
