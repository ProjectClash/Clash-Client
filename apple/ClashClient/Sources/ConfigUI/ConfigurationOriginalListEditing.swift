import Foundation
import ClashClientKit
import ClashClientUI

 
 
struct ConfigurationTextStep: Equatable, Sendable {
    let path: [ConfigurationTextPathStep]
    let edit: ConfigurationTextEdit
}

extension ConfigurationTextEditing {
     
     
     
     
     
    static func edit(_ original: String, steps: [ConfigurationTextStep]) throws -> String {
        guard let last = steps.last else { return original }
        let before = try steps.dropLast().reduce(original) { text, step in try editAlone(text, at: step.path, step.edit) }
        return try edit(before, at: last.path, last.edit)
    }
}

 
 
 
enum OriginalListEdits {
     
     
    static func deleting(_ indices: [Int], under base: [ConfigurationTextPathStep]) -> [ConfigurationTextStep] {
        Set(indices).sorted(by: >).map { ConfigurationTextStep(path: base + [.index($0)], edit: .delete) }
    }

     
     
     
    static func insertionIndex(forNewRuleIn rules: [String]) -> Int {
        guard let last = rules.last, ["MATCH", "FINAL"].contains(type(of: last)) else { return rules.count }
        return rules.count - 1
    }

     
     
     
     
     
     
     
    static func isWrittenAsText(_ rule: String, catalog: ProfilesViewModel.SyntaxCatalog?) -> Bool {
        let kind = type(of: rule)
        let logical: Bool
        if kind == "SUB-RULE" {
            logical = true
        } else if let known = catalog?.ruleTypes.first(where: { $0.name.uppercased() == kind }) {
            logical = known.logical == true
        } else {
            logical = ["AND", "OR", "NOT"].contains(kind)
        }
        return logical && !ClashStructuredRule.builderWritesBack(rule)
    }

     
    static func type(of rule: String) -> String {
        (rule.split(separator: ",", maxSplits: 1).first.map(String.init) ?? rule)
            .trimmingCharacters(in: .whitespaces).uppercased()
    }

     
     
     
     
     
    static func nodeEdits(written: OrderedJSON?, formOriginal: OrderedJSON, formEdited: OrderedJSON,
                          at base: [ConfigurationTextPathStep]) -> [ConfigurationTextStep] {
        changes(written: written, from: formOriginal, to: formEdited, at: base, leaving: ["name"])
    }

     
     
     
    private static func changes(written: OrderedJSON?, from before: OrderedJSON, to after: OrderedJSON,
                                at base: [ConfigurationTextPathStep], leaving left: Set<String>) -> [ConfigurationTextStep] {
        guard case .object(let old) = before, case .object(let new) = after else {
            return [ConfigurationTextStep(path: base, edit: .set(json: after.serialized()))]
        }
        func value(_ key: String, _ pairs: [(key: String, value: OrderedJSON)]) -> OrderedJSON? {
            pairs.first { $0.key == key }?.value
        }
        var keys: [String] = []
        for key in old.map(\.key) + new.map(\.key) where !left.contains(key) && !keys.contains(key) { keys.append(key) }
        var steps: [ConfigurationTextStep] = []
        for key in keys {
            let was = value(key, old), now = value(key, new)
            guard was != now else { continue }
            let path = base + [.key(key)]
            let writtenValue = written?.node(at: [key])
            if let now {
                if let was, case .object = was, case .object = now, case .object? = writtenValue {
                    steps += changes(written: writtenValue, from: was, to: now, at: path, leaving: [])
                } else {
                    steps.append(ConfigurationTextStep(path: path, edit: writtenValue == nil ? .insert(json: now.serialized())
                                                                                          : .set(json: now.serialized())))
                }
            } else if writtenValue != nil {
                steps.append(ConfigurationTextStep(path: path, edit: .delete))
            }
        }
        return steps
    }

     
     
     
    static func uses(ofNode name: String, in document: OrderedJSON) -> [String] {
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

     
     
     
     
    static func namesTarget(_ rule: String, _ name: String) -> Bool {
        rule.split(separator: ",").dropFirst().contains { $0.trimmingCharacters(in: .whitespaces) == name }
    }
}

extension OriginalListEdits {
     
    static func uses(ofProvider name: String, in document: OrderedJSON) -> [String] {
        guard case .array(let groups)? = document.topLevelValue("proxy-groups") else { return [] }
        return groups.compactMap { group in
            guard case .array(let used)? = group.node(at: ["use"]), used.contains(.string(name)),
                  case .string(let groupName)? = group.node(at: ["name"]) else { return nil }
            return groupName
        }
    }

     
     
    static func uses(ofSubRule name: String, in document: OrderedJSON) -> [String] {
        func sends(_ rule: String) -> Bool {
            type(of: rule) == "SUB-RULE"
                && rule.split(separator: ",").last.map { $0.trimmingCharacters(in: .whitespaces) } == name
        }
        var places: [String] = []
        if case .array(let rules)? = document.topLevelValue("rules") {
            for case .string(let rule) in rules where sends(rule) { places.append(rule) }
        }
        if case .object(let branches)? = document.topLevelValue("sub-rules") {
            for branch in branches {
                guard case .array(let rules) = branch.value else { continue }
                for case .string(let rule) in rules where sends(rule) { places.append(rule) }
            }
        }
        return places
    }
}

 

extension OriginalListEdits {
     
    static let keptPlacesShown = 5

     
     
     
     
     
     
     
     
    static func keptUses(of name: String, keptAt file: URL) throws -> [String] {
        let catalog = try PublishedRules.open(sourceAt: file)
        defer { catalog.close() }
        return try keptUses(of: name, in: catalog)
    }

     
     
    static func keptUses(of name: String, in catalog: PublishedRules.Catalog) throws -> [String] {
        try catalog.page(offset: 0, limit: keptPlacesShown, target: name).rules.map(\.rule)
    }

     
     
     
     
     
    static func keptUses(ofRuleSet name: String, keptAt file: URL) throws -> [String] {
        let catalog = try PublishedRules.open(sourceAt: file)
        defer { catalog.close() }
        return try keptUses(ofRuleSet: name, in: catalog)
    }

     
    static func keptUses(ofRuleSet name: String, in catalog: PublishedRules.Catalog) throws -> [String] {
        var places: [String] = []
        var offset = 0
        while places.count < keptPlacesShown {
            let page = try catalog.page(offset: offset, query: name, types: ["RULE-SET", "AND", "OR", "NOT", "SUB-RULE"])
            places += page.rules.map(\.rule).filter { namesRuleSet($0, name) }
            offset += page.rules.count
            guard !page.rules.isEmpty, offset < page.matched else { break }
        }
        return Array(places.prefix(keptPlacesShown))
    }

     
     
     
    static func namesRuleSet(_ rule: String, _ name: String) -> Bool {
        let kind = type(of: rule)
        if kind == "RULE-SET" {
            let fields = rule.split(separator: ",", omittingEmptySubsequences: false)
            return fields.count > 1 && fields[1].trimmingCharacters(in: .whitespaces) == name
        }
        guard ["AND", "OR", "NOT", "SUB-RULE"].contains(kind) else { return false }
         
         
         
        for opening in rule.indices where rule[opening] == "(" {
            let condition = rule[rule.index(after: opening)...].prefix { $0 != ")" && $0 != "(" }
            let fields = condition.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if fields.count > 1, fields[0].uppercased() == "RULE-SET", fields[1] == name { return true }
        }
        return false
    }

     
     
     
     
     
    static func uses(ofRuleSet name: String, in document: OrderedJSON) -> [String] {
        var places: [String] = []
         
        func listsSet(_ text: String) -> Bool {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("rule-set:") else { return false }
            return trimmed.dropFirst("rule-set:".count).split(separator: ",")
                .contains { $0.trimmingCharacters(in: .whitespaces) == name }
        }
        func walk(_ node: OrderedJSON, _ path: String) {
            switch node {
            case .object(let entries):
                for (key, value) in entries {
                    if listsSet(key) { places.append(path + "." + key) }
                    walk(value, path + "." + key)
                }
            case .array(let items):
                if items.contains(where: { if case .string(let text) = $0 { return listsSet(text) }; return false }) {
                    places.append(path)
                }
                for item in items { if case .string = item { continue }; walk(item, path) }
            case .string(let text):
                if listsSet(text) { places.append(path) }
            default:
                break
            }
        }
        for key in ["dns", "sniffer"] {
            if let node = document.topLevelValue(key) { walk(node, key) }
        }
        for key in ["route-address-set", "route-exclude-address-set"] {
            if case .array(let sets)? = document.node(at: ["tun", key]), sets.contains(.string(name)) {
                places.append("tun." + key)
            }
        }
        if case .array(let rules)? = document.topLevelValue("rules") {
            for case .string(let rule) in rules where namesRuleSet(rule, name) { places.append(rule) }
        }
        if case .object(let branches)? = document.topLevelValue("sub-rules") {
            for branch in branches {
                guard case .array(let rules) = branch.value else { continue }
                for case .string(let rule) in rules where namesRuleSet(rule, name) { places.append(rule) }
            }
        }
        return places
    }
}

extension OriginalListEdits {
     
    static func settingRule(_ rule: String, at index: Int, under base: [ConfigurationTextPathStep]) -> ConfigurationTextStep {
        ConfigurationTextStep(path: base + [.index(index)], edit: .set(json: OrderedJSON.string(rule).serialized()))
    }

     
     
    static func addingRule(_ rule: String, to rules: [String]?, under base: [ConfigurationTextPathStep]) -> ConfigurationTextStep {
        guard let rules else {
            return ConfigurationTextStep(path: base, edit: .insert(json: OrderedJSON.array([.string(rule)]).serialized()))
        }
        return ConfigurationTextStep(path: base + [.index(insertionIndex(forNewRuleIn: rules))],
                                     edit: .insert(json: OrderedJSON.string(rule).serialized()))
    }

     
    static func moving(_ from: Int, to: Int, under base: [ConfigurationTextPathStep]) -> ConfigurationTextStep {
        ConfigurationTextStep(path: base + [.index(from)], edit: .move(to: to))
    }

     
     
     
    static func moveSteps(_ offsets: IndexSet, to destination: Int,
                          under base: [ConfigurationTextPathStep]) -> [ConfigurationTextStep] {
        guard let from = offsets.first, offsets.count == 1 else { return [] }
        let to = destination > from ? destination - 1 : destination
        return to == from ? [] : [moving(from, to: to, under: base)]
    }

     
     
    static func appending(_ item: OrderedJSON, toListOf count: Int?, at key: String) -> ConfigurationTextStep {
        guard let count else {
            return ConfigurationTextStep(path: [.key(key)], edit: .insert(json: OrderedJSON.array([item]).serialized()))
        }
        return ConfigurationTextStep(path: [.key(key), .index(count)], edit: .insert(json: item.serialized()))
    }

     
     
    static func adding(_ name: String, _ value: OrderedJSON, toMappingAt key: String, exists: Bool) -> ConfigurationTextStep {
        guard exists else {
            return ConfigurationTextStep(path: [.key(key)], edit: .insert(json: OrderedJSON.object([(name, value)]).serialized()))
        }
        return ConfigurationTextStep(path: [.key(key), .key(name)], edit: .insert(json: value.serialized()))
    }

     
    static func deleting(_ names: [String], fromMappingAt key: String) -> [ConfigurationTextStep] {
        var seen: Set<String> = []
        return names.filter { seen.insert($0).inserted }.map { ConfigurationTextStep(path: [.key(key), .key($0)], edit: .delete) }
    }

     
     
    static func newProxyProvider(type: String, location: String) -> OrderedJSON {
        var fields: [(key: String, value: OrderedJSON)] = [("type", .string(type))]
        switch type {
        case "http": fields += [("url", .string(location)), ("interval", .scalar("3600"))]
        case "file": fields.append(("path", .string(location)))
        case "inline": fields.append(("payload", .array([])))
        default: break
        }
        return .object(fields)
    }

     
     
     
     
    static func handWrittenOrder(_ node: OrderedJSON) -> OrderedJSON {
        guard case .object(let pairs) = node else { return node }
        let first = ["name", "type", "server", "port"]
        return .object(first.compactMap { key in pairs.first { $0.key == key } } + pairs.filter { !first.contains($0.key) })
    }

     
     
     
     
    @MainActor
    static func nodeEdits(written: OrderedJSON?, formOriginalJSON: String, formEditedJSON: String,
                          at base: [ConfigurationTextPathStep]) throws -> [ConfigurationTextStep] {
        nodeEdits(written: written, formOriginal: try OrderedJSON.parse(ProxyNodeDetailsView.strippingEmptyStrings(formOriginalJSON)),
                  formEdited: try OrderedJSON.parse(formEditedJSON), at: base)
    }
}

extension RulePolicyOptions {
     
     
     
    static func make(document: OrderedJSON?) -> RulePolicyOptions {
        func named(_ key: String) -> [(name: String, type: String, hidden: Bool)] {
            guard case .array(let items)? = document?.topLevelValue(key) else { return [] }
            return items.compactMap { item in
                guard case .string(let name)? = item.node(at: ["name"]) else { return nil }
                let type: String
                switch item.node(at: ["type"]) {
                case .string(let text)?: type = text
                case .scalar(let token)?: type = token
                default: type = ""
                }
                return (name, type, item.node(at: ["hidden"]) == .scalar("true"))
            }
        }
        let groups = named("proxy-groups")
        var ruleSets: [String] = [], domainRuleSets: [String] = []
        if case .object(let providers)? = document?.topLevelValue("rule-providers") {
            for provider in providers {
                ruleSets.append(provider.key)
                if provider.value.node(at: ["behavior"]) != .string("ipcidr") { domainRuleSets.append(provider.key) }
            }
        }
        var subRuleNames: [String]?
        if case .object(let branches)? = document?.topLevelValue("sub-rules") { subRuleNames = branches.map(\.key) }
        return RulePolicyOptions(groups: groups.map { ($0.name, $0.type) },
                                 proxies: named("proxies").map { ($0.name, $0.type) },
                                 ruleSets: ruleSets,
                                 hiddenGroups: Set(groups.filter(\.hidden).map(\.name)),
                                 domainRuleSets: domainRuleSets,
                                 subRuleNames: subRuleNames ?? [],
                                  
                                  
                                 ruleSetsAreKnown: false)
    }
}

extension ProfilesViewModel {
     
     
     
     
     
    func editOriginalConfiguration(_ id: String, steps: [ConfigurationTextStep], readDigest: String? = nil) async throws {
        guard !steps.isEmpty else { return }
        _ = try await changeOriginalText(of: id, readDigest: readDigest) { text in
            (try ConfigurationTextEditing.edit(text, steps: steps), steps.count)
        }
    }
}
