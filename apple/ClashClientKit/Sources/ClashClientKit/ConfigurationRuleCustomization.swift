import Foundation

public struct ConfigurationLocalRuleSet: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var input: String
    public var rules: [String]
     
     
     
     
    public var link: ConfigurationRuleSetLink?
     
     
     
     
    public var behavior: String?
    public init(id: String = UUID().uuidString.lowercased(), name: String, input: String, rules: [String],
                link: ConfigurationRuleSetLink? = nil, behavior: String? = nil) {
        self.id = id; self.name = name; self.input = input; self.rules = rules; self.link = link; self.behavior = behavior
    }

     
     
     
    public var ruleCount: Int { link?.count ?? rules.count }
}

 
 
public struct ConfigurationRuleSetContent: Sendable {
    public var rules: [String]
    public var link: ConfigurationRuleSetLink?
     
    public var behavior: String?
    public init(rules: [String], link: ConfigurationRuleSetLink? = nil, behavior: String? = nil) {
        self.rules = rules; self.link = link; self.behavior = behavior
    }
}

 
 
 
 
 
public struct ConfigurationRuleSetLink: Codable, Equatable, Sendable {
    public var url: String
     
     
    public var format: String
     
     
     
     
     
    public var behavior: String
     
     
     
    public var count: Int?

    public init(url: String, format: String, behavior: String = "classical", count: Int? = nil) {
        self.url = url; self.format = format; self.behavior = behavior; self.count = count
    }

    private enum CodingKeys: String, CodingKey { case url, format, behavior, count }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(String.self, forKey: .url)
        format = try container.decode(String.self, forKey: .format)
        behavior = try container.decodeIfPresent(String.self, forKey: .behavior) ?? "classical"
        count = try container.decodeIfPresent(Int.self, forKey: .count)
    }

     
     
     
     
     
    public var provider: OrderedJSON {
        .object([("type", .string("http")), ("behavior", .string(behavior)), ("format", .string(format)),
                 ("url", .string(url)), ("interval", .scalar("86400"))])
    }

     
     
     
     
     
     
    public static let writtenInLimit = 1 << 20

     
    public static func writtenInBytes(_ routing: OrderedJSON) -> Int {
        guard case .object(let providers)? = routing.topLevelValue("rule-providers") else { return 0 }
        return providers.reduce(0) { total, pair in
            guard pair.value.topLevelValue("type") == .string("inline"),
                  case .array(let payload)? = pair.value.topLevelValue("payload") else { return total }
            return total + payload.reduce(0) { sum, rule in
                if case .string(let text) = rule { return sum + text.utf8.count + 1 }
                return sum
            }
        }
    }

     
     
     
     
     
     
     
     
    public static func linkingWrittenSets(in routing: OrderedJSON, localSets: [ConfigurationLocalRuleSet]) -> OrderedJSON {
        guard writtenInBytes(routing) >= writtenInLimit,
              case .object(let providers)? = routing.topLevelValue("rule-providers") else { return routing }
        var changed = false
        let linked: [(key: String, value: OrderedJSON)] = providers.map { pair in
            guard pair.key.hasPrefix("local-"), pair.value.topLevelValue("type") == .string("inline"),
                  case .array(let payload)? = pair.value.topLevelValue("payload"),
                  let set = localSets.first(where: { "local-" + $0.id == pair.key }), let link = set.link,
                  payload == set.rules.map(OrderedJSON.string) else { return pair }
            changed = true
            return (pair.key, link.provider)
        }
        return changed ? routing.settingTopLevel("rule-providers", to: .object(linked)) : routing
    }
}

public extension ConfigurationLibrarySnapshot {
     
     
     
     
    func keepsRulesInOriginal(_ scheme: ConfigurationRuleScheme) -> Bool {
        let base = scheme.rulesFromSchemeID.flatMap { id in rules.first { $0.id == id } } ?? scheme
        guard base.collectionKey == nil else { return false }
        return sources.first { $0.id == base.sourceID }?.rulesWrittenInOriginal == true
    }

    var visibleRuleSchemes: [ConfigurationRuleScheme] {
         
         
         
         
         
         
        let keepsAny = sources.contains { $0.rulesWrittenInOriginal == true }
        let available = keepsAny ? availableRules.filter { !keepsRulesInOriginal($0) } : availableRules
        let baseIDs = Set(available.filter { $0.baseSchemeID == nil }.map(\.id))
         
         
         
         
        let bases = ConfigurationBuiltins.schemes + available.filter {
            guard let base = $0.baseSchemeID else { return true }
            return ConfigurationBuiltins.isNative(base) || !baseIDs.contains(base)
        }
        var seen = Set<String>()
        return bases.filter { seen.insert($0.id).inserted }.map { base in
            ConfigurationBuiltins.isNative(base.id) ? base : (familyRepresentative(of: base.id, in: available) ?? base)
        }
    }

     
     
     
     
     
     
    func familyRepresentative(of baseID: String) -> ConfigurationRuleScheme? {
        familyRepresentative(of: baseID, in: availableRules)
    }

    private func familyRepresentative(of baseID: String, in available: [ConfigurationRuleScheme]) -> ConfigurationRuleScheme? {
        let derivatives = available.filter { $0.baseSchemeID == baseID }
        return derivatives.first { derivative in recipes.contains { $0.ruleSchemeID == derivative.id } } ?? derivatives.last
    }
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func effectiveRuleScheme(_ id: String) -> ConfigurationRuleScheme? {
        let available = availableRules
        if ConfigurationBuiltins.isNative(id) {
            let representative = familyRepresentative(of: id, in: available)
            if let representative, recipes.contains(where: { $0.ruleSchemeID == representative.id }) { return representative }
            return ConfigurationBuiltins.schemes.first { $0.id == id }
        }
        if let own = rules.first(where: { $0.id == id }), own.isRetainedSnapshot != true,
           own.collectionKey == nil, own.kind == .custom || own.kind == .imported {
            return own
        }
        return familyRepresentative(of: id, in: available) ?? rules.first { $0.id == id } ?? ConfigurationBuiltins.schemes.first { $0.id == id }
    }

     
     
     
    func ruleSchemeAfterSavingCustomization(_ id: String) -> ConfigurationRuleScheme? {
        if let own = rules.first(where: { $0.id == id }), own.isRetainedSnapshot != true,
           own.collectionKey == nil, own.kind == .custom || own.kind == .imported {
            return own
        }
        return familyRepresentative(of: id) ?? effectiveRuleScheme(id)
    }
}
