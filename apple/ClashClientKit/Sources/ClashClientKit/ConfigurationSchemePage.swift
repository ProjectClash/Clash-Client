import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
public enum ConfigurationSchemePage {
     
    public static var builtin: OrderedJSON {
        .object([("dns", ConfigurationDNSSettings.automatic)])
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    public static func imported(from document: OrderedJSON, rules: OrderedJSON? = nil) throws -> OrderedJSON? {
        var page = ConfigurationSettingsDocument.project(document)
        guard case .object(let entries) = page, !entries.isEmpty else { return nil }
        if let dns = page.topLevelValue("dns") {
            guard case .object = dns else { throw ConfigurationCompositionError.invalidDocument("DNS") }
        }
        page = try parse(page.serialized())
        let defined = (rules ?? document).topLevelValue("rule-providers")
        for name in ConfigurationSettingsDependencies.names(settings: page, dns: nil).sorted()
            where defined?.topLevelValue(name) == nil {
            throw ConfigurationCompositionError.unresolvedDependency(source: "Scheme page", name: name)
        }
        return page
    }

     
    public static func parse(_ json: String) throws -> OrderedJSON {
        try ConfigurationSettingsDocument.parse(json)
    }

     
    public static func of(_ scheme: ConfigurationRuleScheme?) throws -> OrderedJSON? {
        if let json = scheme?.pageJSON { return try parse(json) }
        if let scheme, ConfigurationBuiltins.isNative(scheme.id) { return builtin }
        return nil
    }

     
     
    public struct Effective: Equatable, Sendable {
        public let settings: OrderedJSON
        public let dns: OrderedJSON
    }

     
     
     
     
     
    public static func effective(schemePage: OrderedJSON?, settingsJSON: String?, dnsMode: ConfigurationDNSMode?,
                                 customDNSJSON: String?, nodeNameservers: [String]?) throws -> Effective {
        var settings = (schemePage ?? .object([])).removingTopLevel("dns")
        if case .object(let entries) = try ConfigurationSettingsDocument.parse(settingsJSON ?? "{}") {
            for entry in entries { settings = settings.settingTopLevel(entry.key, to: entry.value) }
        }
        if dnsMode == .custom {
            return Effective(settings: settings, dns: try ConfigurationDNSSettings.custom(customDNSJSON))
        }
        var dns = schemePage?.topLevelValue("dns") ?? ConfigurationDNSSettings.automatic
        if let servers = nodeNameservers {
            guard !servers.isEmpty, servers.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                throw ConfigurationLibraryError.emptyNodeNameservers
            }
            guard case .object = dns else { throw ConfigurationCompositionError.invalidDocument("DNS") }
            dns = dns.settingTopLevel("proxy-server-nameserver", to: .array(servers.map(OrderedJSON.string)))
        }
        return Effective(settings: settings, dns: dns)
    }

    public static func effective(of recipe: ConfigurationRecipe, scheme: ConfigurationRuleScheme?) throws -> Effective {
        try effective(schemePage: of(scheme), settingsJSON: recipe.settingsJSON, dnsMode: recipe.dnsMode,
                      customDNSJSON: recipe.customDNSJSON, nodeNameservers: recipe.nodeNameservers)
    }

     
     
    public static func legacy(of recipe: ConfigurationRecipe) throws -> OrderedJSON {
        let own = try effective(schemePage: nil, settingsJSON: recipe.settingsJSON, dnsMode: recipe.dnsMode,
                                customDNSJSON: recipe.customDNSJSON, nodeNameservers: recipe.nodeNameservers)
        return own.settings.removingTopLevel("dns").settingTopLevel("dns", to: own.dns)
    }
}

 
 
 
public enum ConfigurationSchemePageOwnership: Equatable, Sendable {
     
    case own(schemeID: String, label: String, configurations: Int)
     
     
     
    case shared(schemeID: String, label: String)
     
    case original
}

extension ConfigurationRuleScheme {
     
     
     
    var ownsItsPage: Bool { kind == .custom && isRetainedSnapshot != true && collectionKey == nil }
}

public extension ConfigurationLibrarySnapshot {
    func schemePageOwnership(profileID: String) -> ConfigurationSchemePageOwnership {
        guard let recipe = recipes.first(where: { $0.id == profileID }), recipe.preservesOriginal != true else { return .original }
        guard let scheme = rules.first(where: { $0.id == recipe.ruleSchemeID })
                ?? ConfigurationBuiltins.schemes.first(where: { $0.id == recipe.ruleSchemeID }) else {
            return .shared(schemeID: recipe.ruleSchemeID, label: recipe.ruleSchemeID)
        }
        guard scheme.ownsItsPage else { return .shared(schemeID: scheme.id, label: scheme.displayLabel) }
        return .own(schemeID: scheme.id, label: scheme.displayLabel,
                    configurations: recipes.filter { $0.ruleSchemeID == scheme.id && $0.preservesOriginal != true }.count)
    }

     
     
     
     
     
    func hasSchemeTakingPage(fromSource id: String) -> Bool {
        rules.contains { $0.takesPage(fromSource: id) }
    }

     
     
     
     
     
     
    func followedLinkLabel(ofScheme id: String) -> String? {
        guard let scheme = rules.first(where: { $0.id == id }) else { return nil }
        let base = scheme.rulesFromSchemeID.flatMap { baseID in rules.first { $0.id == baseID } } ?? scheme
        guard base.kind == .imported, base.isRetainedSnapshot != true,
              let source = sources.first(where: { $0.id == base.sourceID }), source.isRetainedSnapshot != true,
              case .subscription = source.origin else { return nil }
        return base.displayLabel
    }
}

extension ConfigurationRuleScheme {
     
    func takesPage(fromSource id: String) -> Bool {
        sourceID == id && kind == .imported && isRetainedSnapshot != true
            && rulesFromSchemeID == nil && collectionKey == nil
            && (pageFollowsSource == true || pageJSON == nil)
    }
}

 

public extension ConfigurationRuleScheme {
     
     
     
     
     
     
    var ownViewBaseID: String? {
        guard privateToConfigurationID != nil, kind == .custom, isRetainedSnapshot != true,
              baseSchemeID == nil, collectionKey == nil else { return nil }
        return rulesFromSchemeID ?? rulesCustomizedFromSchemeID
    }

     
     
     
     
    var plainViewBaseID: String? { ownViewBaseID == nil ? nil : rulesFromSchemeID }
}

public extension ConfigurationLibrarySnapshot {
     
     
     
     
     
     
    func ownView(of baseID: String?, for profileID: String?) -> ConfigurationRuleScheme? {
        guard let baseID, let profileID else { return nil }
        return rules.first { $0.privateToConfigurationID == profileID && $0.plainViewBaseID == baseID }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func placingOwnViews(in listed: [ConfigurationRuleScheme], for profileID: String?,
                         running current: String? = nil) -> [ConfigurationRuleScheme] {
        let owner = profileID ?? current.flatMap { id in rules.first { $0.id == id && $0.ownViewBaseID != nil } }?.privateToConfigurationID
        guard let owner else { return listed }
        var rows = listed
        let views = rules.filter { $0.privateToConfigurationID == owner && $0.ownViewBaseID != nil }
         
        for view in views.filter({ $0.plainViewBaseID != nil }) + views.filter({ $0.plainViewBaseID == nil })
        where !rows.contains(where: { $0.id == view.id }) {
            guard let baseID = view.ownViewBaseID else { continue }
            let plain = view.plainViewBaseID != nil
            if plain, baseID == current { continue }
            if plain, let index = rows.firstIndex(where: { $0.id == baseID }) {
                rows[index] = view
            } else if let index = rows.lastIndex(where: { $0.id == baseID || $0.ownViewBaseID == baseID || ($0.baseSchemeID ?? $0.id) == baseID }) {
                rows.insert(view, at: index + 1)
            } else {
                rows.append(view)
            }
        }
        return rows
    }

     
     
     
     
     
     
    mutating func namingOwnViews(of baseID: String) {
        guard let base = rules.first(where: { $0.id == baseID && $0.ownViewBaseID == nil }) else { return }
        for index in rules.indices where rules[index].ownViewBaseID == baseID && rules[index].label != base.label {
            rules[index].label = base.label
        }
    }

     
     
     
     
    var schemeIDsInUse: Set<String> {
        let previous = recipes.compactMap { $0.ownCopyOf?.previous }
        return Set(recipes.map(\.ruleSchemeID)).union(recipes.compactMap(\.composedRuleSchemeID))
            .union(previous.map(\.ruleSchemeID)).union(previous.compactMap(\.composedRuleSchemeID))
    }
}
