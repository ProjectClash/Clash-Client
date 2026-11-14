import Foundation

public struct ConfigurationInput: Equatable, Sendable {
    public let id: String
    public let document: OrderedJSON
     
    public let resourcePaths: [String: String]
    public let hiddenProviderNames: Set<String>
    public let hiddenNodeNames: Set<String>
     
     
     
    public let rulesWrittenInOriginal: Bool
    public init(id: String, document: OrderedJSON, resourcePaths: [String: String] = [:], hiddenNodeNames: Set<String> = [],
                hiddenProviderNames: Set<String> = [], rulesWrittenInOriginal: Bool = false) {
        self.id = id
        self.document = document
        self.resourcePaths = resourcePaths
        self.hiddenNodeNames = hiddenNodeNames
        self.hiddenProviderNames = hiddenProviderNames
        self.rulesWrittenInOriginal = rulesWrittenInOriginal
    }
}

public struct ConfigurationComposition: Equatable, Sendable {
    public let document: OrderedJSON
    public let sourceIDs: [String]
     
     
     
     
     
    public let droppedRules: [String]

    public init(document: OrderedJSON, sourceIDs: [String], droppedRules: [String] = []) {
        self.document = document; self.sourceIDs = sourceIDs; self.droppedRules = droppedRules
    }

     
     
     
     
    public func replacingDocument(_ document: OrderedJSON) -> ConfigurationComposition {
        ConfigurationComposition(document: document, sourceIDs: sourceIDs, droppedRules: droppedRules)
    }
}

public extension ConfigurationCompositionError {
     
     
     
     
    var leavesTheConfigurationAsItWas: Bool {
        switch self {
        case .unresolvedDependency, .rulesRunOnlyAsTheOriginal: return true
        default: return false
        }
    }
}

public enum ConfigurationCompositionError: LocalizedError, Equatable {
    case duplicateSource(String)
    case invalidDocument(String)
    case duplicateName(source: String, name: String)
    case unresolvedDependency(source: String, name: String)
     
     
     
     
    case patternNameCollision(name: String, sources: [String])
     
     
    case rulesRunOnlyAsTheOriginal(source: String)
     
     
     
     
    case rulesCannotLeaveTheOriginal(source: String)

    public var errorDescription: String? {
        switch self {
        case .rulesRunOnlyAsTheOriginal:
             
             
             
            return "These rules work only in their original configuration, so choose Original or another scheme under Rule Scheme."
        case .rulesCannotLeaveTheOriginal:
            return "These rules work only in their original configuration and can't be saved as a rule scheme."
        case .duplicateSource: return "A source was selected more than once."
        case .invalidDocument: return "A selected source is not a configuration object."
        case .duplicateName: return "Two entries in one source share a name. Rename one of them."
        case .unresolvedDependency(_, let name):
             
             
             
             
            return String(format: "A selected source needs \u{201C}%@\u{201D}, which no selected source supplies.", name)
        case .patternNameCollision(let name, _):
            return String(format: "Two selected sources each have a node named \u{201C}%@\u{201D} that they pick by name, so rename it in one of them.", name)
        }
    }
}

 
 
 
 
public enum ConfigurationComposer {
     
     
     
    public static func compose(
        sources: [ConfigurationInput],
        rules: ConfigurationInput,
        namedNodesFrom: String? = nil
    ) throws -> ConfigurationComposition {
        var ids = Set<String>()
        for source in sources {
            guard !source.id.isEmpty, case .object = source.document else {
                throw ConfigurationCompositionError.invalidDocument(source.id)
            }
            guard ids.insert(source.id).inserted else {
                throw ConfigurationCompositionError.duplicateSource(source.id)
            }
        }
        guard case .object = rules.document else {
            throw ConfigurationCompositionError.invalidDocument(rules.id)
        }
        for input in sources + [rules] { try validateShape(input) }
         
         
        if sources.count == 1, sources[0] == rules {
            var document = rules.document
            for section in ["proxy-providers", "rule-providers"] {
                guard let providers = document.topLevelValue(section)?.compositionObject else { continue }
                document = document.settingTopLevel(section,to:.object(providers.map { pair in
                    guard pair.value.topLevelValue("type")?.compositionString == "file",
                          let path = pair.value.topLevelValue("path")?.compositionString,
                          let bound = rules.resourcePaths[path] else { return pair }
                    return (pair.key,pair.value.settingTopLevel("path",to:.string(bound)))
                }))
            }
            return ConfigurationComposition(document: document, sourceIDs: sources.map(\.id))
        }
        let groups = rules.document.topLevelValue("proxy-groups")?.compositionArray ?? []
        let groupNames = Set(groups.compactMap { $0.topLevelValue("name")?.compositionString })
         
         
         
         
         
        let ownNodesID = namedNodesFrom ?? rules.id
        let nodeNames = try nameTable(sources, key: "proxies", preferred: ownNodesID,
            reserved: groupNames.union(builtins), favoured: Set(sources.filter(Self.picksNodesByPattern).map(\.id)))
         
         
         
         
        for source in sources where Self.picksNodesByPattern(source) {
            for (name, composed) in (nodeNames[source.id] ?? [:]).sorted(by: { $0.key < $1.key }) where composed != name {
                guard let kept = sources.first(where: { $0.id != source.id && nodeNames[$0.id]?[name] == name }) else { continue }
                throw ConfigurationCompositionError.patternNameCollision(name: name, sources: [kept.id, source.id])
            }
        }
        let sourceGroupNames = Set(sources.flatMap {
            ($0.document.topLevelValue("proxy-groups")?.compositionArray ?? []).compactMap {
                $0.topLevelValue("name")?.compositionString
            }
        })
         
         
        var sourceGroupOwners: [String: String] = [:]
        for source in sources {
            for group in source.document.topLevelValue("proxy-groups")?.compositionArray ?? [] {
                guard let name = group.topLevelValue("name")?.compositionString, sourceGroupOwners[name] == nil else { continue }
                sourceGroupOwners[name] = source.id
            }
        }
        let providerNames = try nameTable(sources, key: "proxy-providers", preferred: rules.id,
            reserved: groupNames.union(sourceGroupNames))
        var dependencyGroups = DependencyGroups(sources: sources, rules: rules, nodes: nodeNames,
            providers: providerNames, planGroups: groupNames)
        var nodes: [OrderedJSON] = []
        var localPaths: [String: String] = [:]
        var providers: [(key: String, value: OrderedJSON)] = []
        for source in sources {
            for node in source.document.topLevelValue("proxies")?.compositionArray ?? [] {
                guard let name = node.topLevelValue("name")?.compositionString,
                      let mapped = nodeNames[source.id]?[name] else {
                    throw ConfigurationCompositionError.invalidDocument(source.id)
                }
                var value = node.settingTopLevel("name", to: .string(mapped))
                if let dialer = node.topLevelValue("dialer-proxy")?.compositionString {
                     
                     
                    value = value.settingTopLevel("dialer-proxy", to: .string(
                        try dependencyGroups.resolveOrPassThrough(dialer, source: source)
                    ))
                }
                nodes.append(value)
            }
            for pair in source.document.topLevelValue("proxy-providers")?.compositionObject ?? [] {
                guard let name = providerNames[source.id]?[pair.key] else { continue }
                var value = pair.value
                 
                 
                 
                 
                 
                 
                 
                 
                if let proxy = value.topLevelValue("proxy")?.compositionString {
                    value = value.settingTopLevel("proxy", to: .string(
                        try dependencyGroups.resolveOrPassThrough(proxy, source: source)
                    ))
                }
                if let dialer = value.topLevelValue("override")?.topLevelValue("dialer-proxy")?.compositionString,
                   let override = value.topLevelValue("override") {
                    value = value.settingTopLevel("override", to: override.settingTopLevel("dialer-proxy", to:
                        .string(try dependencyGroups.resolveOrPassThrough(dialer, source: source))))
                }
                 
                 
                 
                if value.topLevelValue("type")?.compositionString == "http" {
                    value = value.removingTopLevel("path")
                }
                if value.topLevelValue("type")?.compositionString == "file",
                   let original = value.topLevelValue("path")?.compositionString {
                     
                     
                     
                     
                     
                     
                     
                     
                    let path = source.resourcePaths[original] ?? original
                    if let owner = localPaths[path], owner != source.id {
                        throw ConfigurationCompositionError.unresolvedDependency(source: source.id, name: original)
                    }
                    localPaths[path] = source.id
                    value = value.settingTopLevel("path", to: .string(path))
                }
                providers.append((name, value))
            }
        }
         
         
         
         
        func resolveNode(_ name: String) -> String? {
            if let own = sources.first(where: { $0.id == ownNodesID }), !own.hiddenNodeNames.contains(name),
               let mapped = nodeNames[ownNodesID]?[name] { return mapped }
            return sources.lazy.filter { !$0.hiddenNodeNames.contains(name) }.compactMap { nodeNames[$0.id]?[name] }.first
                ?? sources.lazy.compactMap { nodeNames[$0.id]?[name] }.first
        }
        let originalNodes = Set((rules.document.topLevelValue("proxies")?.compositionArray ?? [])
            .compactMap { $0.topLevelValue("name")?.compositionString })
        let hiddenNames = sources.flatMap { source in
            source.hiddenNodeNames.compactMap { nodeNames[source.id]?[$0] }
        }.sorted()
        let hiddenProviders = Set(sources.flatMap { source in
            source.hiddenProviderNames.compactMap { providerNames[source.id]?[$0] }
        })
        var outputGroups: [OrderedJSON] = []
        for group in groups {
            var value = group
            let members = group.topLevelValue("proxies")?.compositionArray ?? []
            let uses = group.topLevelValue("use")?.compositionArray ?? []
             
             
             
             
            let ownNamed = members.compactMap(\.compositionString).filter(originalNodes.contains)
            let takesNodes = !ownNamed.isEmpty && !ownNamed.contains { nodeNames[rules.id]?[$0] != nil }
            let takesProviders = !uses.isEmpty
            let includes = ["include-all", "include-all-proxies", "include-all-providers"]
                .contains { group.topLevelValue($0) == .scalar("true") }
            var rewritten: [OrderedJSON] = []
             
             
             
             
            var resolvedUses: [OrderedJSON] = []
            for use in uses {
                guard let key = use.compositionString else { continue }
                if let mapped = providerNames[rules.id]?[key]
                    ?? sources.lazy.compactMap({ providerNames[$0.id]?[key] }).first,
                   !hiddenProviders.contains(mapped) {
                    resolvedUses.append(.string(mapped))
                }
            }
            let providersUnresolved = takesProviders && resolvedUses.isEmpty
             
             
             
             
             
             
             
            var referencedNodes = 0, resolvedNodes = 0
            for member in members {
                guard let name = member.compositionString else { rewritten.append(member); continue }
                if originalNodes.contains(name) {
                    if let mapped = nodeNames[rules.id]?[name] {
                        rewritten.append(.string(mapped))
                    }
                     
                     
                } else if groupNames.contains(name) || Self.builtins.contains(name) {
                    rewritten.append(member)  
                } else if let owner = sourceGroupOwners[name] {
                     
                     
                     
                     
                     
                    if let resolved = try? dependencyGroups.resolve(name, source: owner) {
                        rewritten.append(.string(resolved))
                    }
                } else {
                    referencedNodes += 1
                     
                     
                     
                    if let mapped = resolveNode(name) {
                        rewritten.append(.string(mapped))
                        resolvedNodes += 1
                    }
                }
            }
            if group.topLevelValue("proxies") != nil {
                value = value.settingTopLevel("proxies", to: .array(rewritten))
            }
             
             
             
             
            let onlyBuiltinsLeft = rewritten.allSatisfy { Self.builtins.contains($0.compositionString ?? "") }
            let fallsBackToEveryNode = referencedNodes > 0 && resolvedNodes == 0 && onlyBuiltinsLeft && resolvedUses.isEmpty
            if takesNodes || includes || fallsBackToEveryNode || providersUnresolved {
                 
                 
                value = value.settingTopLevel("include-all-proxies", to: .scalar("true"))
                 
                 
                 
                 
                let asksForEveryProvider = ["include-all", "include-all-providers"]
                    .contains { group.topLevelValue($0) == .scalar("true") }
                if takesProviders, !providersUnresolved, !asksForEveryProvider {
                    value = value.settingTopLevel("use", to: .array(resolvedUses))
                } else {
                    let every = providers.filter { !hiddenProviders.contains($0.key) }.map { OrderedJSON.string($0.key) }
                    value = every.isEmpty ? value.removingTopLevel("use") : value.settingTopLevel("use", to: .array(every))
                }
                if !hiddenProviders.isEmpty {
                     
                     
                     
                    value = value.removingTopLevel("include-all").removingTopLevel("include-all-providers")
                }
            } else if takesProviders {
                 
                 
                value = value.settingTopLevel("use", to: .array(resolvedUses))
            }
            if !hiddenNames.isEmpty {
                let hidden = "^(" + hiddenNames.map(Self.literalPattern).joined(separator: "|") + ")$"
                let existing = value.topLevelValue("exclude-filter")?.compositionString ?? ""
                 
                 
                 
                 
                let combined = existing.isEmpty ? hidden
                    : existing.contains("`") ? existing + "`" + hidden : "(" + existing + ")|" + hidden
                value = value.settingTopLevel("exclude-filter", to: .string(combined))
            }
            outputGroups.append(value)
        }
        var result = rules.document
            .settingTopLevel("proxies", to: .array(nodes))
            .settingTopLevel("proxy-providers", to: .object(providers))
         
         
        var droppedRules: [String] = []
        func rewriteRules(_ value: OrderedJSON) throws -> OrderedJSON {
            guard let rows = value.compositionArray else { return value }
            return .array(try rows.compactMap { rule -> OrderedJSON? in
                guard let text = rule.compositionString else { return rule }
                var fields = text.components(separatedBy: ",")
                let type = fields[0].trimmingCharacters(in: .whitespaces).uppercased()
                guard type != "SUB-RULE" else { return rule }
                 
                 
                let index: Int
                switch type {
                case "MATCH": index = 1
                case "NOT", "OR", "AND", "DOMAIN-REGEX", "PROCESS-NAME-REGEX", "PROCESS-PATH-REGEX":
                    index = fields.count - 1
                default: index = 2
                }
                guard fields.indices.contains(index) else { return rule }
                let target = fields[index].trimmingCharacters(in: .whitespaces)
                if originalNodes.contains(target) {
                    fields[index] = try dependency(target, source: rules.id, nodes: nodeNames, groups: groupNames)
                } else if !groupNames.contains(target), !Self.builtins.contains(target), let owner = sourceGroupOwners[target] {
                     
                     
                     
                    guard let resolved = try? dependencyGroups.resolve(target, source: owner) else {
                        droppedRules.append(text)
                        if type == "MATCH" {
                            fields[index] = "DIRECT"
                            return .string(fields.joined(separator: ","))
                        }
                        return nil
                    }
                    fields[index] = resolved
                } else if !groupNames.contains(target), !sourceGroupNames.contains(target), !Self.builtins.contains(target) {
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                    guard let mapped = resolveNode(target) else {
                        droppedRules.append(text)
                         
                         
                         
                         
                         
                        if type == "MATCH" {
                            fields[index] = "DIRECT"
                            return .string(fields.joined(separator: ","))
                        }
                        return nil
                    }
                    fields[index] = mapped
                }
                return .string(fields.joined(separator: ","))
            })
        }
        if let rows = result.topLevelValue("rules") {
            result = result.settingTopLevel("rules", to: try rewriteRules(rows))
        }
        if let subrules = result.topLevelValue("sub-rules")?.compositionObject {
            result = result.settingTopLevel("sub-rules", to: .object(try subrules.map {
                ($0.key, try rewriteRules($0.value))
            }))
        }
        var finalGroups = outputGroups + dependencyGroups.output
        if let global = Self.globalWithout(hidden: Set(hiddenNames), nodes: nodes, groups: finalGroups,
                                           providers: providers.map(\.key)) {
            finalGroups.append(global)
        }
        if !finalGroups.isEmpty || rules.document.topLevelValue("proxy-groups") != nil {
            result = result.settingTopLevel("proxy-groups", to: .array(finalGroups))
        }
        return ConfigurationComposition(document: result, sourceIDs: sources.map(\.id), droppedRules: droppedRules)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func globalWithout(hidden: Set<String>, nodes: [OrderedJSON], groups: [OrderedJSON],
                              providers: [String] = []) -> OrderedJSON? {
        guard !hidden.isEmpty, !providers.contains("GLOBAL") else { return nil }
        let groupNames = groups.compactMap { $0.topLevelValue("name")?.compositionString }
        let allNodes = nodes.compactMap { $0.topLevelValue("name")?.compositionString }
        guard !groupNames.contains("GLOBAL"), !allNodes.contains("GLOBAL") else { return nil }
        return .object([("name", .string("GLOBAL")), ("type", .string("select")),
                        ("proxies", .array(globalMembers(nodes: allNodes, groups: groupNames, hidden: hidden).map(OrderedJSON.string))),
                        ("exclude-filter", .string(chainEntriesPattern(hidden)))])
    }

     
     
    public static let chainEntriesMarker = "(?#Clash: a chain's entry nodes)"

    static func chainEntriesPattern(_ names: Set<String>) -> String {
        chainEntriesMarker + "^(" + names.sorted().map(literalPattern).joined(separator: "|") + ")$"
    }

     
     
     
     
     
    static func literalPattern(_ name: String) -> String {
        NSRegularExpression.escapedPattern(for: name).replacingOccurrences(of: "`", with: "\\x60")
    }

     
     
    public static func globalMembers(nodes: [String], groups: [String], hidden: Set<String>) -> [String] {
        ["DIRECT", "REJECT"] + nodes.filter { !hidden.contains($0) } + groups.filter { $0 != "GLOBAL" }
    }

     
     
     
     
     
     
     
     
    @discardableResult
    public static func refreshingGeneratedGlobal(_ document: inout [String: Any]) -> Bool {
        guard var groups = document["proxy-groups"] as? [[String: Any]],
              let index = groups.firstIndex(where: { name(of: $0) == "GLOBAL" }),
              let pattern = groups[index]["exclude-filter"] as? String, pattern.hasPrefix(chainEntriesMarker) else { return false }
        let nodes = ((document["proxies"] as? [[String: Any]]) ?? []).compactMap(name(of:))
        let providers = (document["proxy-providers"] as? [String: Any]).map { Array($0.keys) } ?? []
        if nodes.contains("GLOBAL") || providers.contains("GLOBAL") {
            groups.remove(at: index)
            document["proxy-groups"] = groups
            return true
        }
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let hidden = Set(nodes.filter { regex.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil })
        let members = globalMembers(nodes: nodes, groups: groups.compactMap(name(of:)), hidden: hidden)
        guard groups[index]["proxies"] as? [String] != members else { return false }
        groups[index]["proxies"] = members
        document["proxy-groups"] = groups
        return true
    }

     
     
     
     
    private static func name(of entry: [String: Any]) -> String? {
        entry["name"] as? String
    }

     
     
     
     
     
     
    private static func validateShape(_ input: ConfigurationInput) throws {
        for key in ["proxies", "proxy-groups", "rules"] {
            if let value = input.document.topLevelValue(key), !value.isCompositionNull, value.compositionArray == nil {
                throw ConfigurationCompositionError.invalidDocument(input.id + ": " + key)
            }
        }
        for key in ["proxy-providers", "rule-providers", "sub-rules"] {
            if let value = input.document.topLevelValue(key), !value.isCompositionNull, value.compositionObject == nil {
                throw ConfigurationCompositionError.invalidDocument(input.id + ": " + key)
            }
        }
    }

     
     
    private struct DependencyGroups {
        let sources: [ConfigurationInput]
        let rules: ConfigurationInput
        let nodes: [String: [String: String]]
        let providers: [String: [String: String]]
        let planGroups: Set<String>
        var names: [String: [String: String]] = [:]
        var output: [OrderedJSON] = []
        var visited: Set<String> = []

         
         
         
         
        mutating func resolveOrPassThrough(_ name: String, source: ConfigurationInput) throws -> String {
            do { return try resolve(name, source: source.id) }
            catch ConfigurationCompositionError.unresolvedDependency(_, let missing) where missing == name {
                let ownGroups = source.document.topLevelValue("proxy-groups")?.compositionArray ?? []
                guard !ownGroups.contains(where: { $0.topLevelValue("name")?.compositionString == name }) else {
                    throw ConfigurationCompositionError.unresolvedDependency(source: source.id, name: name)
                }
                return name
            }
        }

        mutating func resolve(_ name: String, source id: String) throws -> String {
            if let node = nodes[id]?[name] { return node }
            if builtins.contains(name) { return name }
            if id == rules.id, planGroups.contains(name) { return name }
            guard let source = sources.first(where: { $0.id == id }),
                  let original = source.document.topLevelValue("proxy-groups")?.compositionArray?
                    .first(where: { $0.topLevelValue("name")?.compositionString == name }) else {
                throw ConfigurationCompositionError.unresolvedDependency(source: id, name: name)
            }
            if names.isEmpty {
                let allNodes = Set(nodes.values.flatMap { $0.values })
                names = try nameTable(sources.filter { $0.id != rules.id }, key: "proxy-groups",
                    preferred: rules.id, reserved: planGroups.union(allNodes).union(builtins))
            }
            guard let mapped = names[id]?[name] else {
                throw ConfigurationCompositionError.unresolvedDependency(source: id, name: name)
            }
            let key = id + "\u{0}" + name
            guard visited.insert(key).inserted else { return mapped }  
             
             
             
             
             
             
             
             
             
             
            var group = original.settingTopLevel("name", to: .string(mapped))
            if let members = original.topLevelValue("proxies")?.compositionArray {
                var rewritten: [OrderedJSON] = []
                for item in members {
                    guard let target = item.compositionString else { rewritten.append(item); continue }
                    rewritten.append(.string(try reference(target, source: source)))
                }
                group = group.settingTopLevel("proxies", to: .array(rewritten))
            }
            if let uses = original.topLevelValue("use")?.compositionArray {
                 
                 
                group = group.settingTopLevel("use", to: .array(uses.map { item in
                    guard let key = item.compositionString, let provider = providers[id]?[key] else { return item }
                    return .string(provider)
                }))
            }
            output.append(scopedToItsSource(group, source: id))
            return mapped
        }

         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        private func scopedToItsSource(_ group: OrderedJSON, source id: String) -> OrderedJSON {
            func on(_ key: String) -> Bool { group.topLevelValue(key) == .scalar("true") }
            var value = group
            let takesEveryProvider = on("include-all") || on("include-all-providers")
            let takesEveryNode = on("include-all") || on("include-all-proxies")
            let own = Set(providers[id]?.values.map { $0 } ?? [])
            let every = Set(providers.values.flatMap { $0.values })
            if takesEveryProvider, own != every {
                value = value.removingTopLevel("include-all").removingTopLevel("include-all-providers")
                if takesEveryNode { value = value.settingTopLevel("include-all-proxies", to: .scalar("true")) }
                value = own.isEmpty ? value.removingTopLevel("use")
                    : value.settingTopLevel("use", to: .array(own.sorted().map(OrderedJSON.string)))
            }
            let foreign = nodes.filter { $0.key != id }.flatMap { $0.value.values }.sorted()
            if takesEveryNode, !foreign.isEmpty {
                let pattern = "^(" + foreign.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|") + ")$"
                let existing = value.topLevelValue("exclude-filter")?.compositionString ?? ""
                value = value.settingTopLevel("exclude-filter", to: .string(existing.isEmpty ? pattern : existing + "`" + pattern))
            }
            return value
        }

         
         
         
        mutating func reference(_ name: String, source: ConfigurationInput) throws -> String {
            do { return try resolve(name, source: source.id) }
            catch ConfigurationCompositionError.unresolvedDependency(_, let missing) where missing == name {
                return name
            }
        }
    }

     
     
     
     
     
     
     
     
     
    public static func displayName(forComposedProviderName name: String) -> String {
        guard name.hasPrefix("["), let close = name.firstIndex(of: "]") else { return name }
        let id = String(name[name.index(after: name.startIndex)..<close])
        guard isSourceIdentifier(id) else { return name }
        let rest = name[name.index(after: close)...]
        guard rest.hasPrefix(" "), rest.count > 1 else { return name }
        return String(rest.dropFirst())
    }

     
     
     
    static func isSourceIdentifier(_ id: String) -> Bool {
        var body = Substring(id)
        for prefix in ["legacy-nodes-", "legacy-", "chain-"] where body.hasPrefix(prefix) {
            body = body.dropFirst(prefix.count); break
        }
        let parts = body.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.map(\.count) == [8, 4, 4, 4, 12] else { return false }
        return parts.allSatisfy { $0.allSatisfy { $0.isHexDigit } }
    }

     
     
     
     
     
     
     
    public static let builtins: Set<String> = ["DIRECT", "REJECT", "REJECT-DROP", "PASS", "PASS-RULE", "COMPATIBLE", "GLOBAL"]

    private static func dependency(
        _ name: String, source: String, nodes: [String: [String: String]], groups: Set<String>
    ) throws -> String {
        if let mapped = nodes[source]?[name] { return mapped }
        if groups.contains(name) || builtins.contains(name) { return name }
        throw ConfigurationCompositionError.unresolvedDependency(source: source, name: name)
    }

     
     
     
     
    private static func picksNodesByPattern(_ source: ConfigurationInput) -> Bool {
        (source.document.topLevelValue("proxy-groups")?.compositionArray ?? []).contains { group in
            (group.topLevelValue("include-all") == .scalar("true") || group.topLevelValue("include-all-proxies") == .scalar("true"))
                && ["filter", "exclude-filter"].contains { !(group.topLevelValue($0)?.compositionString ?? "").isEmpty }
        }
    }

    private static func nameTable(
        _ sources: [ConfigurationInput], key: String, preferred: String, reserved: Set<String>,
        favoured: Set<String> = []
    ) throws -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        var owners: [String: [String]] = [:]
        for source in sources {
            let names: [String]
            if key != "proxy-providers" {
                let rows = source.document.topLevelValue(key)?.compositionArray ?? []
                names = rows.compactMap { $0.topLevelValue("name")?.compositionString }
                guard names.count == rows.count else { throw ConfigurationCompositionError.invalidDocument(source.id) }
            } else {
                names = (source.document.topLevelValue(key)?.compositionObject ?? []).map(\.key)
            }
            var seen = Set<String>()
            for name in names {
                guard !name.isEmpty, seen.insert(name).inserted else {
                    throw ConfigurationCompositionError.duplicateName(source: source.id, name: name)
                }
                owners[name, default: []].append(source.id)
            }
            result[source.id] = [:]
        }
        var used = reserved.union(owners.keys)
        for name in owners.keys.sorted() {
            let sourceIDs = owners[name]!.sorted()
            let primary = sourceIDs.contains(preferred) ? preferred
                : sourceIDs.first(where: favoured.contains) ?? sourceIDs[0]
            for id in sourceIDs {
                if id == primary && !reserved.contains(name) {
                    result[id]![name] = name
                } else {
                    let base = "[\(id)] \(name)"
                    var candidate = base
                    var suffix = 2
                    while used.contains(candidate) { candidate = "\(base) (\(suffix))"; suffix += 1 }
                    used.insert(candidate)
                    result[id]![name] = candidate
                }
            }
        }
        return result
    }
}

private extension OrderedJSON {
    var compositionArray: [OrderedJSON]? { if case .array(let values) = self { return values }; return nil }
    var compositionObject: [(key: String, value: OrderedJSON)]? { if case .object(let values) = self { return values }; return nil }
    var compositionString: String? { if case .string(let value) = self { return value }; return nil }
     
    var isCompositionNull: Bool { if case .scalar("null") = self { return true }; return false }
}
