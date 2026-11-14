import Foundation

 
 
public enum ConfigurationRuleDocument {
    public static let keys: Set<String> = ["rules", "rule-providers", "sub-rules", "proxy-groups"]

     
     
     
     
     
    public static func project(_ document: OrderedJSON) -> OrderedJSON {
        guard case .object(let pairs) = document else { return document }
        return .object(pairs.filter { keys.contains($0.key) })
    }

     
     
     
     
     
    public static func namedNodes(of document: OrderedJSON, recorded: [String]?) -> [String]? {
        let nodes = Set(nodeNames(in: document)).union(recorded ?? [])
        guard !nodes.isEmpty, case .array(let groups)? = document.topLevelValue("proxy-groups") else { return nil }
        var seen = Set<String>(), named: [String] = []
        for group in groups {
            guard case .array(let members)? = group.topLevelValue("proxies") else { continue }
            for case .string(let name) in members where nodes.contains(name) && seen.insert(name).inserted { named.append(name) }
        }
        return named.isEmpty ? nil : named
    }

     
     
    public static func namedNodesSource(of document: OrderedJSON, sourceID: String, recorded: String?) -> String? {
        recorded ?? (nodeNames(in: document).isEmpty ? nil : sourceID)
    }

     
    public static func nodeNames(in document: OrderedJSON) -> [String] {
        guard case .array(let values) = document.topLevelValue("proxies") else { return [] }
        return values.compactMap { value in
            if case .string(let name) = value.topLevelValue("name") { return name }
            return nil
        }
    }

     
     
     
     
     
     
     
     
     
     
    public static func binding(_ document: OrderedJSON, nodes: Set<String>, supplied: Set<String>) -> OrderedJSON {
        guard !nodes.isEmpty, case .array(let groups) = document.topLevelValue("proxy-groups") else { return document }
        return document.settingTopLevel("proxy-groups", to: .array(groups.map { group in
            var value = group
            var bindsNodes = false
            if case .array(let members) = group.topLevelValue("proxies") {
                var named = 0
                let retained = members.filter { member in
                    guard case .string(let name) = member, nodes.contains(name) else { return true }
                    named += 1
                    return supplied.contains(name)
                }
                bindsNodes = named > 0 && members.count - retained.count == named
                if retained.count != members.count { value = value.settingTopLevel("proxies", to: .array(retained)) }
                if case .string(let selected) = value.topLevelValue("default-selected"), nodes.contains(selected),
                   !supplied.contains(selected) {
                    value = value.removingTopLevel("default-selected")
                }
            }
             
             
             
            if bindsNodes {
                 
                 
                 
                 
                let namesProviders: Bool
                if case .array(let providers) = group.topLevelValue("use"), !providers.isEmpty { namesProviders = true }
                else { namesProviders = false }
                value = value.settingTopLevel(namesProviders ? "include-all-proxies" : "include-all", to: .scalar("true"))
            }
            return value
        }))
    }
}

 
 
public struct ConfigurationRuleDraft: Equatable, Sendable {
    public struct Row: Identifiable, Equatable, Sendable {
        public let id: UUID
        public var raw: String
        public init(id: UUID = UUID(), raw: String) { self.id = id; self.raw = raw }
        public var isFinal: Bool {
            let kind = raw.split(separator: ",", maxSplits: 1).first?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return kind == "MATCH" || kind == "FINAL"
        }
         
         
        public var ruleSetKey: String? {
            let parts = raw.split(separator: ",", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, parts[0] == "RULE-SET" else { return nil }
            return String(parts[1])
        }
    }
    public struct Group: Identifiable, Equatable, Sendable {
        public let id: UUID
        public var document: OrderedJSON
         
         
        public init(id: UUID = UUID(), document: OrderedJSON) { self.id = id; self.document = document }
        public var name: String { if case .string(let value) = document.topLevelValue("name") { return value }; return "" }
        public var type: String { if case .string(let value) = document.topLevelValue("type") { return value }; return "" }
         
        public var isHidden: Bool {
            switch document.topLevelValue("hidden") {
            case .scalar(let value): return value == "true"
            case .string(let value): return value.lowercased() == "true"
            default: return false
            }
        }
    }
    public private(set) var groups: [Group]
    private var additionalDocument: OrderedJSON
    public private(set) var schemeID: String
    public private(set) var version: ConfigurationSourceVersion
    public var label: String
    public private(set) var rows: [Row]
    public private(set) var originalDocument: OrderedJSON
    public private(set) var generatedRuleGroups: [String: String]
     
    public private(set) var disabledRules: Set<String>
    public private(set) var notes: [String: String]
     
     
     
     
    public private(set) var namedNodes: [String]?
     
    public private(set) var namedNodesSourceID: String?
     
     
     
     
     
    public struct SubRule: Identifiable, Equatable, Sendable {
        public let id: UUID
        public var name: String
        public var rows: [Row]
        public init(id: UUID = UUID(), name: String, rows: [Row] = []) { self.id = id; self.name = name; self.rows = rows }
    }
     
    public private(set) var subRules: [SubRule]
     
     
     
    public private(set) var subRulesEditable: Bool

    public init(scheme: ConfigurationRuleScheme, payload: ConfigurationSourcePayload) throws {
        schemeID = scheme.id; version = .init(payload.record); label = scheme.label
        generatedRuleGroups = scheme.generatedRuleGroups ?? [:]
        disabledRules = Set(scheme.disabledRules ?? [])
        notes = scheme.ruleNotes ?? [:]
        originalDocument = try OrderedJSON.parse(payload.documentJSON)
        additionalDocument = ConfigurationRuleDocument.project(originalDocument)
        namedNodes = ConfigurationRuleDocument.namedNodes(of: originalDocument, recorded: scheme.namedNodes)
        namedNodesSourceID = namedNodes == nil ? nil
            : ConfigurationRuleDocument.namedNodesSource(of: originalDocument, sourceID: scheme.sourceID, recorded: scheme.namedNodesSourceID)
        groups = try ConfigurationRuleGroupSnapshot.read(additionalDocument).map { Group(id: UUID(), document: $0.document) }
        guard case .array(let rules) = originalDocument.topLevelValue("rules") else { throw ConfigurationLibraryError.missingRules }
        rows = try rules.map {
            guard case .string(let raw) = $0 else { throw ConfigurationLibraryError.missingRules }
            return Row(raw: raw)
        }
        (subRules, subRulesEditable) = Self.readSubRules(additionalDocument.topLevelValue("sub-rules"))
    }

     
     
     
     
     
     
     
     
     
    public init(originalDocument document: OrderedJSON, id: String, label: String) throws {
        schemeID = id
        version = ConfigurationSourceVersion(id: id, version: "original")
        self.label = label
        generatedRuleGroups = [:]
        disabledRules = []
        notes = [:]
        originalDocument = document
        additionalDocument = document
        namedNodes = ConfigurationRuleDocument.namedNodes(of: document, recorded: nil)
        namedNodesSourceID = nil
        groups = try ConfigurationRuleGroupSnapshot.read(document).map { Group(id: UUID(), document: $0.document) }
        guard case .array(let rules) = document.topLevelValue("rules") else { throw ConfigurationLibraryError.missingRules }
        rows = try rules.map {
            guard case .string(let raw) = $0 else { throw ConfigurationLibraryError.missingRules }
            return Row(raw: raw)
        }
        (subRules, subRulesEditable) = Self.readSubRules(document.topLevelValue("sub-rules"))
    }

     
     
    private static func readSubRules(_ value: OrderedJSON?) -> ([SubRule], Bool) {
        switch value {
        case nil, .scalar("null")?:
            return ([], true)
        case .object(let pairs)?:
            var result: [SubRule] = []
            for (name, rules) in pairs {
                guard case .array(let items) = rules else { return ([], false) }
                var rows: [Row] = []
                for item in items {
                    guard case .string(let raw) = item else { return ([], false) }
                    rows.append(Row(raw: raw))
                }
                result.append(SubRule(name: name, rows: rows))
            }
            return (result, true)
        default:
            return ([], false)
        }
    }
     
     
    public struct Rebased: Equatable, Sendable {
        public var draft: ConfigurationRuleDraft
        public var droppedRuleSets: [String]
    }

     
     
     
     
     
     
    public func rebased(onto stored: Self) -> Rebased {
        var result = self
        result.version = stored.version
        result.originalDocument = stored.originalDocument
        result.additionalDocument = stored.additionalDocument
        result.namedNodes = stored.namedNodes
        result.namedNodesSourceID = stored.namedNodesSourceID
        let storedKeys: Set<String>
        if case .object(let providers)? = stored.additionalDocument.topLevelValue("rule-providers") {
            storedKeys = Set(providers.map(\.key))
        } else { storedKeys = [] }
        var dropped: [String] = []
        for key in referencedRuleSets.sorted() where !storedKeys.contains(key) {
            dropped.append(key)
            result.rows.removeAll { $0.raw.hasPrefix("RULE-SET," + key + ",") }
        }
         
        let subRuleKeys = Set(subRules.flatMap(\.rows).compactMap(\.ruleSetKey))
        for key in subRuleKeys.subtracting(storedKeys).sorted() where !dropped.contains(key) { dropped.append(key) }
        for index in result.subRules.indices {
            result.subRules[index].rows.removeAll { row in row.ruleSetKey.map { !storedKeys.contains($0) } ?? false }
        }
        let kept = Set(result.rows.map(\.raw))
        result.disabledRules = result.disabledRules.filter { kept.contains($0) }
        result.notes = result.notes.filter { kept.contains($0.key) }
        result.generatedRuleGroups = result.generatedRuleGroups.filter { key, name in
            result.containsRuleSet(key) && result.groups.contains { $0.name == name }
        }
        return Rebased(draft: result, droppedRuleSets: dropped)
    }

     
     
     
     
     
     
    public func continuing(after saved: Self) -> Self {
        var result = self
        result.schemeID = saved.schemeID
        result.label = saved.label
        result.version = saved.version
        result.originalDocument = saved.originalDocument
        return result
    }

     
    public func preservingIdentity(from previous: Self) -> Self {
        var result = self
         
         
         
        var groupIDs: [String: [UUID]] = [:]
        for group in previous.groups { groupIDs[group.name, default: []].append(group.id) }
        result.groups = groups.map { group in
            guard var ids = groupIDs[group.name], !ids.isEmpty else { return group }
            let id = ids.removeFirst()
            groupIDs[group.name] = ids
            return Group(id: id, document: group.document)
        }
        result.rows = Self.rows(rows, keepingIDsOf: previous.rows)
         
        let previousSubRules = Dictionary(previous.subRules.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        result.subRules = subRules.map { subRule in
            guard let old = previousSubRules[subRule.name] else { return subRule }
            return SubRule(id: old.id, name: subRule.name, rows: Self.rows(subRule.rows, keepingIDsOf: old.rows))
        }
        return result
    }

     
     
    private static func rows(_ rows: [Row], keepingIDsOf previous: [Row]) -> [Row] {
        var ruleIDs: [String: [UUID]] = [:]
        for row in previous { ruleIDs[row.raw, default: []].append(row.id) }
        var offsets: [String: Int] = [:]
        return rows.map { row in
            let index = offsets[row.raw, default: 0]
            offsets[row.raw] = index + 1
            guard let ids = ruleIDs[row.raw], index < ids.count else { return row }
            return Row(id: ids[index], raw: row.raw)
        }
    }
    public var referencedRuleSets: Set<String> {
        Set(rows.compactMap { row in
            guard row.raw.hasPrefix("RULE-SET,") else { return nil }
            return row.raw.split(separator: ",", maxSplits: 2).dropFirst().first.map(String.init)
        })
    }
    public mutating func reorderGroups(_ orderedIDs: [UUID]) {
         
         
        guard Set(groups.map(\.id)).count == groups.count else { return }
        let byID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
        guard orderedIDs.count == groups.count, Set(orderedIDs) == Set(byID.keys) else { return }
        groups = orderedIDs.compactMap { byID[$0] }
    }
    public mutating func setRule(_ raw: String, rowID: UUID?) {
        if let rowID, let index = rows.firstIndex(where: { $0.id == rowID }) { rows[index].raw = raw }
        else if rowID == nil { rows.insert(.init(raw: raw), at: rows.firstIndex(where: \.isFinal) ?? rows.endIndex) }
    }
    public mutating func remove(_ ids: Set<UUID>) {
        rows.removeAll { ids.contains($0.id) && !$0.isFinal }
        let kept = Set(rows.map(\.raw))
        disabledRules = disabledRules.filter { kept.contains($0) }
        notes = notes.filter { kept.contains($0.key) }
    }
     
     
    public mutating func insertRuleFirst(_ raw: String) {
        rows.insert(.init(raw: raw), at: 0)
    }
    public func isEnabled(_ raw: String) -> Bool { !disabledRules.contains(raw) }
    public func note(for raw: String) -> String { notes[raw] ?? "" }
     
    public mutating func setRule(_ raw: String, enabled: Bool, note: String, rowID: UUID?) {
        let previous = rowID.flatMap { id in rows.first { $0.id == id }?.raw }
        setRule(raw, rowID: rowID)
        if let previous, previous != raw, !rows.contains(where: { $0.raw == previous }) {
            disabledRules.remove(previous)
            notes.removeValue(forKey: previous)
        }
        if enabled { disabledRules.remove(raw) } else { disabledRules.insert(raw) }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { notes.removeValue(forKey: raw) } else { notes[raw] = trimmed }
    }
    public mutating func move(_ ids: Set<UUID>, before target: UUID?) {
        let moving = rows.filter { ids.contains($0.id) && !$0.isFinal }
        guard !moving.isEmpty, target.map({ !ids.contains($0) }) ?? true else { return }
        rows.removeAll { ids.contains($0.id) && !$0.isFinal }
        let index = target.flatMap { id in rows.firstIndex { $0.id == id } }
            ?? rows.firstIndex(where: \.isFinal) ?? rows.endIndex
        rows.insert(contentsOf: moving, at: min(index, rows.firstIndex(where: \.isFinal) ?? rows.endIndex))
    }
    public func document() throws -> OrderedJSON {
        guard !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ConfigurationLibraryError.emptyName }
        guard rows.last?.isFinal == true, rows.filter(\.isFinal).count == 1,
              rows.allSatisfy({ !$0.raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw ConfigurationLibraryError.invalidFinalRule
        }
        return currentDocument()
    }
     
     
    public var ruleSetNames: [String] {
        guard case .object(let fields)? = additionalDocument.topLevelValue("rule-providers") else { return [] }
        return fields.map(\.key).sorted()
    }

    public func currentDocument() -> OrderedJSON {
        var result = additionalDocument.settingTopLevel("rules", to: .array(rows.map { .string($0.raw) }))
        if !groups.isEmpty || originalDocument.topLevelValue("proxy-groups") != nil {
            result = result.settingTopLevel("proxy-groups", to: .array(groups.map(\.document)))
        }
        return writingSubRules(into: result)
    }

     
     
     
     
    private func writingSubRules(into document: OrderedJSON) -> OrderedJSON {
        guard subRulesEditable else { return document }
        if subRules.isEmpty {
            guard case .object(let written)? = document.topLevelValue("sub-rules"), !written.isEmpty else { return document }
            return document.removingTopLevel("sub-rules")
        }
        return document.settingTopLevel("sub-rules", to: .object(subRules.map { subRule in
            (subRule.name, .array(subRule.rows.map { .string($0.raw) }))
        }))
    }
}

public struct ConfigurationNewRuleDraft: Equatable, Sendable {
    public var label: String
     
    public var templateID: String?
    public init(label: String, templateID: String? = nil) { self.label = label; self.templateID = templateID }
}

 
 
public struct ConfigurationRuleGroupSnapshot: Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let type: String
    public let members: [String]
    public let providers: [String]
    public let includesAll: Bool
    public let includesAllProxies: Bool
    public let includesAllProviders: Bool
    public let document: OrderedJSON

    public static func read(_ document: OrderedJSON) throws -> [Self] {
        guard let value = document.topLevelValue("proxy-groups") else { return [] }
        guard case .array(let groups) = value else { throw ConfigurationLibraryError.unreadable }
        return try groups.enumerated().map { index, group in
            func string(_ key: String) -> String? {
                guard case .string(let value) = group.topLevelValue(key) else { return nil }
                return value
            }
            func strings(_ key: String, lenient: Bool = false) throws -> [String] {
                guard let value = group.topLevelValue(key) else { return [] }
                guard case .array(let items) = value else { throw ConfigurationLibraryError.unreadable }
                return try items.compactMap {
                    guard case .string(let value) = $0 else {
                         
                         
                        if lenient { return nil }
                        throw ConfigurationLibraryError.unreadable
                    }
                    return value
                }
            }
            guard let name = string("name"), let type = string("type") else { throw ConfigurationLibraryError.unreadable }
            return Self(id: index, name: name, type: type, members: try strings("proxies"),
                providers: try strings("use", lenient: true), includesAll: group.topLevelValue("include-all") == .scalar("true"),
                includesAllProxies: group.topLevelValue("include-all-proxies") == .scalar("true"),
                includesAllProviders: group.topLevelValue("include-all-providers") == .scalar("true"), document: group)
        }
    }
}

public enum ConfigurationRuleGroupError: LocalizedError, Equatable {
    case nameRequired
    case duplicate(String)
    case cycle(String)
    case inUse(String)
    public var errorDescription: String? {
        switch self {
        case .nameRequired: "Group name is required."
        case .duplicate(let name): "Group name is already in use: \(name)"
        case .cycle(let name): "Groups cannot refer back to themselves: \(name)"
        case .inUse(let name): "Change references to this group before deleting it: \(name)"
        }
    }
}

public extension ConfigurationRuleDraft {
     
    mutating func setGroup(_ document: OrderedJSON, groupID: UUID?) throws {
        var candidate = self
        guard case .string(let name) = document.topLevelValue("name"),
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ConfigurationRuleGroupError.nameRequired }
        if let groupID {
            guard let index = candidate.groups.firstIndex(where: { $0.id == groupID }) else { throw ConfigurationLibraryError.staleGeneration }
            let old = candidate.groups[index].name
            candidate.groups[index].document = document
            if name != old { candidate.rewriteReferences(from: old, to: name) }
        } else { candidate.groups.append(.init(id: UUID(), document: document)) }
        try candidate.validateGroupNamesAndCycles()
        self = candidate
    }
    mutating func removeGroups(_ ids: Set<UUID>) throws {
        var candidate = self
        let removed = candidate.groups.filter { ids.contains($0.id) }
        candidate.groups.removeAll { ids.contains($0.id) }
        let before = candidate.currentDocument()
        for group in removed {
            var probe = candidate
            probe.rewriteReferences(from: group.name, to: UUID().uuidString)
            guard probe.currentDocument() == before else { throw ConfigurationRuleGroupError.inUse(group.name) }
        }
        self = candidate
    }
    mutating func moveGroups(_ ids: Set<UUID>, before target: UUID?) {
        guard target.map({ !ids.contains($0) }) ?? true else { return }
        let moving = groups.filter { ids.contains($0.id) }
        groups.removeAll { ids.contains($0.id) }
        let index = target.flatMap { id in groups.firstIndex { $0.id == id } } ?? groups.endIndex
        groups.insert(contentsOf: moving, at: index)
    }
    private func validateGroupNamesAndCycles() throws {
        var names: Set<String> = ["DIRECT", "REJECT", "REJECT-DROP", "PASS", "PASS-RULE", "COMPATIBLE", "GLOBAL"]
         
         
        names.formUnion(ConfigurationRuleDocument.nodeNames(in: originalDocument))
        names.formUnion(namedNodes ?? [])
        for group in groups {
            guard names.insert(group.name).inserted else { throw ConfigurationRuleGroupError.duplicate(group.name) }
        }
        let graph = Dictionary(uniqueKeysWithValues: groups.map { group -> (String, [String]) in
            guard case .array(let values) = group.document.topLevelValue("proxies") else { return (group.name, []) }
            return (group.name, values.compactMap { if case .string(let name) = $0 { return name }; return nil })
        })
        var visiting: Set<String> = [], visited: Set<String> = []
        func visit(_ name: String) throws {
            guard let edges = graph[name], !visited.contains(name) else { return }
            guard visiting.insert(name).inserted else { throw ConfigurationRuleGroupError.cycle(name) }
            for edge in edges { try visit(edge) }
            visiting.remove(name); visited.insert(name)
        }
        for group in groups { try visit(group.name) }
    }
    fileprivate static func validateReplay(_ document: OrderedJSON, baseline: OrderedJSON) throws {
        guard document.topLevelValue("rules") != nil else { return }
        let record = ConfigurationSourceRecord(label: "Replay", origin: .file("replay"))
        let source = ConfigurationSourcePayload(record: record, original: Data(), documentJSON: document.serialized())
        let scheme = ConfigurationRuleScheme(label: "Replay", kind: .custom, sourceID: record.id)
        let draft = try ConfigurationRuleDraft(scheme: scheme, payload: source)
        _ = try draft.document()
        try draft.validateGroupNamesAndCycles()
        let names = Set(draft.groups.map(\.name))
        for group in try ConfigurationRuleGroupSnapshot.read(baseline) where !names.contains(group.name) {
            var probe = draft
            probe.rewriteReferences(from: group.name, to: UUID().uuidString)
            guard probe.currentDocument() == draft.currentDocument() else {
                throw ConfigurationRuleReplay.Conflict(path: ["proxy-groups", group.name])
            }
        }
    }

     
     
     
    private mutating func rewriteRuleTexts(_ transform: (String) -> String) {
        rows = rows.map { var row = $0; row.raw = transform(row.raw); return row }
        for index in subRules.indices {
            subRules[index].rows = subRules[index].rows.map { var row = $0; row.raw = transform(row.raw); return row }
        }
        disabledRules = Set(disabledRules.map(transform))
        var moved: [String: String] = [:]
        for raw in notes.keys.sorted() where moved[transform(raw)] == nil { moved[transform(raw)] = notes[raw] }
        notes = moved
    }

     
     
     
     
     
     
     
    private static func groupTargetIndex(_ fields: [String]) -> Int? {
        switch fields[0].trimmingCharacters(in: .whitespaces).uppercased() {
        case "SUB-RULE": return nil
        case "MATCH", "FINAL": return fields.count > 1 ? 1 : nil
        case "NOT", "OR", "AND", "DOMAIN-REGEX", "PROCESS-NAME-REGEX", "PROCESS-PATH-REGEX":
            return fields.count > 1 ? fields.count - 1 : nil
        default: return fields.count > 2 ? 2 : nil
        }
    }

    private mutating func rewriteReferences(from old: String, to new: String) {
        generatedRuleGroups = generatedRuleGroups.mapValues { $0 == old ? new : $0 }
        func reference(_ value: OrderedJSON) -> OrderedJSON { value == .string(old) ? .string(new) : value }
        func rule(_ raw: String) -> String {
            var fields = raw.components(separatedBy: ",")
            guard let index = Self.groupTargetIndex(fields),
                  fields[index].trimmingCharacters(in: .whitespaces) == old else { return raw }
            fields[index] = new
            return fields.joined(separator: ",")
        }
        rewriteRuleTexts(rule)
        groups = groups.map { group in
            var group = group
            if case .array(let members) = group.document.topLevelValue("proxies") {
                group.document = group.document.settingTopLevel("proxies", to: .array(members.map(reference)))
            }
            for key in ["default-selected", "dialer-proxy"] {
                if let value = group.document.topLevelValue(key) { group.document = group.document.settingTopLevel(key, to: reference(value)) }
            }
            return group
        }
        if !subRulesEditable, case .object(let sets) = additionalDocument.topLevelValue("sub-rules") {
            additionalDocument = additionalDocument.settingTopLevel("sub-rules", to: .object(sets.map { key, value in
                guard case .array(let values) = value else { return (key, value) }
                return (key, .array(values.map { if case .string(let raw) = $0 { return .string(rule(raw)) }; return $0 }))
            }))
        }
        for (key, field) in [("proxies", "dialer-proxy"), ("listeners", "proxy"), ("tunnels", "proxy")] {
            if case .array(let values) = additionalDocument.topLevelValue(key) {
                additionalDocument = additionalDocument.settingTopLevel(key, to: .array(values.map { value in
                    if key == "tunnels", case .string(let raw) = value {
                        var parts = raw.components(separatedBy: ",")
                        if parts.count == 4, parts[3].trimmingCharacters(in: .whitespaces) == old {
                            parts[3] = new
                            return .string(parts.joined(separator: ","))
                        }
                        return value
                    }
                    guard let target = value.topLevelValue(field) else { return value }
                    return value.settingTopLevel(field, to: reference(target))
                }))
            }
        }
        for key in ["proxy-providers", "rule-providers"] {
            if case .object(let providers) = additionalDocument.topLevelValue(key) {
                additionalDocument = additionalDocument.settingTopLevel(key, to: .object(providers.map { key, value in
                    var value = value
                    for field in ["proxy", "dialer-proxy"] {
                        if let target = value.topLevelValue(field) { value = value.settingTopLevel(field, to: reference(target)) }
                    }
                    if case .array(let nodes) = value.topLevelValue("payload") {
                        value = value.settingTopLevel("payload", to: .array(nodes.map { node in
                            guard let target = node.topLevelValue("dialer-proxy") else { return node }
                            return node.settingTopLevel("dialer-proxy", to: reference(target))
                        }))
                    }
                    if let override = value.topLevelValue("override"), let target = override.topLevelValue("dialer-proxy") {
                        value = value.settingTopLevel("override", to: override.settingTopLevel("dialer-proxy", to: reference(target)))
                    }
                    return (key, value)
                }))
            }
        }
        if let ntp = additionalDocument.topLevelValue("ntp"), let target = ntp.topLevelValue("dialer-proxy") {
            additionalDocument = additionalDocument.settingTopLevel("ntp", to: ntp.settingTopLevel("dialer-proxy", to: reference(target)))
        }
        func resolver(_ value: OrderedJSON) -> OrderedJSON {
            switch value {
            case .string(let raw):
                guard let hash = raw.firstIndex(of: "#") else { return value }
                let prefix = String(raw[...hash])
                let parts = raw[raw.index(after: hash)...].components(separatedBy: "&")
                let rewritten = parts.map { part -> String in
                    guard !part.contains("="), (part.removingPercentEncoding ?? part) == old else { return part }
                    return new.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed.subtracting(CharacterSet(charactersIn: "&=#"))) ?? new
                }
                return .string(prefix + rewritten.joined(separator: "&"))
            case .array(let values): return .array(values.map(resolver))
            case .object(let pairs): return .object(pairs.map { ($0.key, resolver($0.value)) })
            default: return value
            }
        }
        if var dns = additionalDocument.topLevelValue("dns") {
            for key in ["nameserver", "default-nameserver", "fallback", "proxy-server-nameserver", "direct-nameserver", "nameserver-policy", "proxy-server-nameserver-policy", "direct-nameserver-policy"] {
                if let value = dns.topLevelValue(key) { dns = dns.settingTopLevel(key, to: resolver(value)) }
            }
            additionalDocument = additionalDocument.settingTopLevel("dns", to: dns)
        }
    }
}

 
 
public enum ConfigurationRuleReplay {
    public struct Conflict: Error, Equatable, Sendable {
        public let path: [String]
    }

    public static func merge(baseline: OrderedJSON, local: OrderedJSON, incoming: OrderedJSON) throws -> OrderedJSON {
        let document = try mergeValue(baseline, local, incoming, path: [])!
        try ConfigurationRuleDraft.validateReplay(document, baseline: baseline)
        return document
    }

    private static func mergeValue(_ base: OrderedJSON?, _ local: OrderedJSON?, _ remote: OrderedJSON?, path: [String]) throws -> OrderedJSON? {
        if local == base { return remote }
        if remote == base || local == remote { return local }
        guard let base, let local, let remote else { throw Conflict(path: path) }
        if case .object(let b) = base, case .object(let l) = local, case .object(let r) = remote {
            return .object(try mergeEntries(b, l, r, path: path))
        }
        if case .array(let b) = base, case .array(let l) = local, case .array(let r) = remote {
            if path.last == "rules" || (path.count == 2 && path.first == "sub-rules") {
                func strings(_ values: [OrderedJSON]) throws -> [(key: String, value: OrderedJSON)] {
                    try values.map { value in
                        guard case .string(let key) = value else { throw Conflict(path: path) }
                        let kind = key.split(separator: ",", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces).uppercased()
                        return (kind == "MATCH" || kind == "FINAL" ? "\\0final" : key, value)
                    }
                }
                let be = try strings(b), le = try strings(l), re = try strings(r)
                let bs = Set(be.map(\.key)), ls = Set(le.map(\.key)), rs = Set(re.map(\.key))
                 
                 
                if !bs.subtracting(ls).intersection(bs.subtracting(rs)).isEmpty,
                   ls.subtracting(bs) != rs.subtracting(bs) { throw Conflict(path: path) }
                return .array(try mergeEntries(be, le, re, path: path).map(\.value))
            }
            if ["proxy-groups", "proxies", "listeners"].contains(path.last ?? "") {
                func named(_ values: [OrderedJSON]) throws -> [(key: String, value: OrderedJSON)] {
                    try values.map { value in
                        guard case .string(let key) = value.topLevelValue("name"), !key.isEmpty else { throw Conflict(path: path) }
                        return (key, value)
                    }
                }
                return .array(try mergeEntries(named(b), named(l), named(r), path: path).map(\.value))
            }
        }
        throw Conflict(path: path)
    }

    private static func mergeEntries(_ base: [(key: String, value: OrderedJSON)],
                                     _ local: [(key: String, value: OrderedJSON)],
                                     _ remote: [(key: String, value: OrderedJSON)], path: [String]) throws -> [(key: String, value: OrderedJSON)] {
        func map(_ entries: [(key: String, value: OrderedJSON)]) throws -> [String: OrderedJSON] {
            var result: [String: OrderedJSON] = [:]
            for entry in entries {
                guard result.updateValue(entry.value, forKey: entry.key) == nil else { throw Conflict(path: path) }
            }
            return result
        }
        let b = try map(base), l = try map(local), r = try map(remote)
        var values: [String: OrderedJSON] = [:]
        var keys: [String] = [], seen: Set<String> = []
        for entry in local + remote + base where seen.insert(entry.key).inserted { keys.append(entry.key) }
        for key in keys { values[key] = try mergeValue(b[key], l[key], r[key], path: path + [key]) }
        let surviving = Set(values.keys)
        let bk = base.map(\.key).filter(surviving.contains)
        let lk = local.map(\.key).filter(surviving.contains)
        let rk = remote.map(\.key).filter(surviving.contains)
        let existing = Set(bk)
        let lo = lk.filter(existing.contains), ro = rk.filter(existing.contains)
        if lo != bk && ro != bk && lo != ro { throw Conflict(path: path) }
        let order = lo != bk ? lo : ro
        var edges: [String: [String]] = [:], edgeSets: [String: Set<String>] = [:]
        var degrees = Dictionary(uniqueKeysWithValues: surviving.map { ($0, 0) })
        func link(_ from: String, _ to: String) {
            guard edgeSets[from, default: []].insert(to).inserted else { return }
            edges[from, default: []].append(to); degrees[to, default: 0] += 1
        }
        for (a, b) in zip(order, order.dropFirst()) { link(a, b) }
        for sequence in [lk, rk] {
            for (a, b) in zip(sequence, sequence.dropFirst()) where !existing.contains(a) || !existing.contains(b) { link(a, b) }
        }
         
         
        let rank = Dictionary(uniqueKeysWithValues: keys.enumerated().map { ($0.element, $0.offset) })
        var ready: [Int] = []
        func enqueue(_ value: Int) {
            ready.append(value)
            var child = ready.count - 1
            while child > 0 {
                let parent = (child - 1) / 2
                guard ready[child] < ready[parent] else { break }
                ready.swapAt(child, parent); child = parent
            }
        }
        func dequeue() -> Int {
            let value = ready[0], last = ready.removeLast()
            if !ready.isEmpty {
                ready[0] = last
                var parent = 0
                while parent * 2 + 1 < ready.count {
                    var child = parent * 2 + 1
                    if child + 1 < ready.count && ready[child + 1] < ready[child] { child += 1 }
                    guard ready[child] < ready[parent] else { break }
                    ready.swapAt(child, parent); parent = child
                }
            }
            return value
        }
        for (index, key) in keys.enumerated() where degrees[key] == 0 { enqueue(index) }
        var result: [(key: String, value: OrderedJSON)] = []
        while !ready.isEmpty {
            let key = keys[dequeue()]
            result.append((key, values[key]!))
            for next in edges[key] ?? [] {
                degrees[next]! -= 1
                if degrees[next] == 0 { enqueue(rank[next]!) }
            }
        }
        guard result.count == surviving.count else { throw Conflict(path: path) }
        return result
    }
}


public extension ConfigurationRuleDraft {
     
    mutating func replaceContents(_ document: OrderedJSON) throws {
        let record = ConfigurationSourceRecord(id: version.id, label: label, origin: .file(label), version: version.version)
        let parsed = try ConfigurationRuleDraft(scheme: .init(id: schemeID, label: label, kind: .custom, sourceID: version.id),
            payload: .init(record: record, original: Data(), documentJSON: document.serialized()))
        _ = try parsed.document()
        try parsed.validateGroupNamesAndCycles()
        try parsed.validateSubRuleCycles()
        let reconciled = parsed.preservingIdentity(from: self)
        groups = reconciled.groups; rows = reconciled.rows; additionalDocument = parsed.additionalDocument
        subRules = reconciled.subRules; subRulesEditable = parsed.subRulesEditable
        generatedRuleGroups = generatedRuleGroups.filter { key, name in
            containsRuleSet(key) && groups.contains(where: { $0.name == name })
        }
    }

    func containsRuleSet(_ key: String) -> Bool {
        rows.contains { $0.raw.hasPrefix("RULE-SET," + key + ",") }
    }

     
     
     
     
    public func ruleSetPolicy(_ key: String) -> String? {
        guard let row = rows.first(where: { $0.raw.hasPrefix("RULE-SET," + key + ",") }) else { return nil }
        return row.raw.components(separatedBy: ",")[2].trimmingCharacters(in: .whitespaces)
    }

     
     
     
     
    public mutating func setRuleSetPolicy(_ key: String, policy: String) {
        guard let index = rows.firstIndex(where: { $0.raw.hasPrefix("RULE-SET," + key + ",") }) else { return }
        var fields = rows[index].raw.components(separatedBy: ",")
        fields[2] = policy
        rows[index].raw = fields.joined(separator: ",")
        if let generated = generatedRuleGroups[key], generated != policy,
           let group = groups.first(where: { $0.name == generated }) {
            generatedRuleGroups.removeValue(forKey: key)
            try? removeGroups([group.id])
        }
    }

     
     
     
    public mutating func attachRuleSet(key: String, name: String, rules content: [String], policy: String,
                                       link: ConfigurationRuleSetLink? = nil, behavior: String? = nil) throws {
        if containsRuleSet(key) {
            var providers = additionalDocument.topLevelValue("rule-providers") ?? .object([])
            providers = providers.settingTopLevel(key, to: Self.ruleSetProvider(key: key, rules: content, link: link, behavior: behavior))
            additionalDocument = additionalDocument.settingTopLevel("rule-providers", to: providers)
            setRuleSetPolicy(key, policy: policy)
        } else {
            try addRuleSet(key: key, name: name, rules: content, defaultRoute: "proxy", policy: policy, link: link, behavior: behavior)
        }
    }

     
     
     
    static func ruleSetProvider(key: String, rules content: [String], link: ConfigurationRuleSetLink?,
                                behavior: String? = nil) -> OrderedJSON {
        if let link { return link.provider }
        return .object([("type", .string("inline")), ("behavior", .string(behavior ?? "classical")),
                        ("payload", .array(content.map(OrderedJSON.string)))])
    }

     
     
     
    mutating func addRuleSet(key: String, name: String, rules content: [String], defaultRoute: String, policy: String? = nil,
                             link: ConfigurationRuleSetLink? = nil, behavior: String? = nil) throws {
        var candidate = self
        guard !containsRuleSet(key) else { return }
        var root = currentDocument()
        var providers = root.topLevelValue("rule-providers") ?? .object([])
        providers = providers.settingTopLevel(key, to: Self.ruleSetProvider(key: key, rules: content, link: link, behavior: behavior))
        root = root.settingTopLevel("rule-providers", to: providers)
        candidate.additionalDocument = root
        if let policy {
            candidate.rows.insert(.init(raw: "RULE-SET," + key + "," + policy), at: 0)
            self = candidate
            return
        }
        let policy = name
        if !candidate.groups.contains(where: { $0.name == policy }) {
            let target = defaultRoute == "proxy" ? candidate.groups.first?.name : nil
            let members = defaultRoute == "direct" ? ["DIRECT"] : defaultRoute == "reject" ? ["REJECT"] : target.map { [$0, "DIRECT"] } ?? ["DIRECT"]
            var group = OrderedJSON.object([("name", .string(policy)), ("type", .string("select")),
                ("proxies", .array(members.map(OrderedJSON.string)))])
            if defaultRoute == "proxy" && target == nil { group = group.settingTopLevel("include-all", to: .scalar("true")) }
            try candidate.setGroup(group, groupID: nil)
            candidate.generatedRuleGroups[key] = policy
        }
        candidate.rows.insert(.init(raw: "RULE-SET," + key + "," + policy), at: 0)
        self = candidate
    }

     
    mutating func updateLocalRuleSet(_ value: ConfigurationLocalRuleSet) throws {
        let key = "local-" + value.id
        guard containsRuleSet(key) else { return }
        var candidate = self
        if let name = generatedRuleGroups[key], let group = candidate.groups.first(where: { $0.name == name }), name != value.name {
            try candidate.setGroup(group.document.settingTopLevel("name", to: .string(value.name)), groupID: group.id)
        }
        var providers = candidate.additionalDocument.topLevelValue("rule-providers") ?? .object([])
        providers = providers.settingTopLevel(key, to: Self.ruleSetProvider(key: key, rules: value.rules, link: value.link,
                                                                            behavior: value.behavior))
        candidate.additionalDocument = candidate.additionalDocument.settingTopLevel("rule-providers", to: providers)
        self = candidate
    }

    mutating func removeRuleSet(_ key: String) {
        rows.removeAll { $0.raw.hasPrefix("RULE-SET," + key + ",") }
         
         
        for index in subRules.indices { subRules[index].rows.removeAll { $0.ruleSetKey == key } }
        if let name = generatedRuleGroups.removeValue(forKey: key), let group = groups.first(where: { $0.name == name }) {
             
            try? removeGroups([group.id])
        }
        if case .object(let values) = additionalDocument.topLevelValue("rule-providers") {
            additionalDocument = additionalDocument.settingTopLevel("rule-providers", to: .object(values.filter { $0.key != key }))
        }
    }

    mutating func deleteRoutingGroup(_ id: UUID) throws {
        guard let group = groups.first(where: { $0.id == id }) else { return }
        var candidate = self
         
         
        candidate.rows.removeAll { row in
            guard !row.isFinal else { return false }
             
             
             
             
            let fields = row.raw.components(separatedBy: ",")
            return Self.groupTargetIndex(fields).map { fields[$0].trimmingCharacters(in: .whitespaces) == group.name } ?? false
        }
        try candidate.removeGroups([id])
        self = candidate
    }
}

 
 
 
 
 
 
public extension ConfigurationRuleDraft {
     
     
    private var pinnedFinalIndex: Int { Self.pinnedFinalIndex(rows) }
    private static func pinnedFinalIndex(_ rows: [Row]) -> Int { rows.last?.isFinal == true ? rows.count - 1 : rows.count }

     
    mutating func moveRows(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        rows = Self.rows(rows, movingFromOffsets: offsets, toOffset: destination)
    }

     
     
    internal static func rows(_ rows: [Row], movingFromOffsets offsets: IndexSet, toOffset destination: Int) -> [Row] {
        let limit = pinnedFinalIndex(rows)
        guard !offsets.isEmpty, offsets.allSatisfy({ rows.indices.contains($0) && $0 < limit }) else { return rows }
        var movable = Array(rows[..<limit])
        let tail = Array(rows[limit...])
         
         
        let lifted = offsets.sorted().map { movable[$0] }
        for offset in offsets.sorted(by: >) { movable.remove(at: offset) }
        let target = min(destination, limit) - offsets.filter { $0 < min(destination, limit) }.count
        movable.insert(contentsOf: lifted, at: max(0, min(target, movable.count)))
        return movable + tail
    }

     
     
    mutating func moveRow(_ id: UUID, before target: UUID?) {
        let limit = pinnedFinalIndex
        guard let source = rows.firstIndex(where: { $0.id == id }), source < limit else { return }
        var movable = Array(rows[..<limit])
        let tail = Array(rows[limit...])
        let row = movable.remove(at: source)
        let index: Int
        if let target, let found = movable.firstIndex(where: { $0.id == target }) {
            index = found
        } else if target == nil || target == tail.first?.id {
            index = movable.endIndex
        } else {
            return
        }
        movable.insert(row, at: index)
        rows = movable + tail
    }

     
     
    mutating func moveRow(_ id: UUID, offset: Int) {
        rows = Self.rows(rows, moving: id, offset: offset)
    }

    internal static func rows(_ rows: [Row], moving id: UUID, offset: Int) -> [Row] {
        let limit = pinnedFinalIndex(rows)
        guard let source = rows.firstIndex(where: { $0.id == id }), source < limit else { return rows }
        let destination = source + offset
        guard destination >= 0, destination < limit else { return rows }
        var result = rows
        result.swapAt(source, destination)
        return result
    }
}

public enum ConfigurationSubRuleError: LocalizedError, Equatable {
    case nameRequired
     
    case nameHasComma(String)
    case duplicate(String)
    case inUse(String)
    case cycle(String)
    case ruleRequired
     
    case notEditable
    public var errorDescription: String? {
        switch self {
        case .nameRequired: "Sub-rule name is required."
        case .nameHasComma(let name): "A sub-rule name cannot contain a comma: \(name)"
        case .duplicate(let name): "Sub-rule name is already in use: \(name)"
        case .inUse(let name): "Change the rules that use this sub-rule before deleting it: \(name)"
        case .cycle(let name): "Sub-rules cannot lead back to themselves: \(name)"
        case .ruleRequired: "Enter a rule."
        case .notEditable: "These sub-rules can only be changed in the source."
        }
    }
}

 
 
 
 
 
 
public extension ConfigurationRuleDraft {
     
     
    static func subRuleTarget(of raw: String) -> String? {
        let fields = raw.components(separatedBy: ",")
        guard fields.count >= 2,
              fields[0].trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "SUB-RULE" else { return nil }
        return fields[fields.count - 1].trimmingCharacters(in: .whitespacesAndNewlines)
    }

     
    func subRuleUses(of name: String) -> Int {
        (rows + subRules.flatMap(\.rows)).filter { Self.subRuleTarget(of: $0.raw) == name }.count
    }

     
    @discardableResult
    mutating func addSubRule(named name: String) throws -> UUID {
        guard subRulesEditable else { throw ConfigurationSubRuleError.notEditable }
        let subRule = SubRule(name: try validSubRuleName(name, besides: nil))
        subRules.append(subRule)
        return subRule.id
    }

    mutating func renameSubRule(_ id: UUID, to name: String) throws {
        guard subRulesEditable else { throw ConfigurationSubRuleError.notEditable }
        guard let index = subRules.firstIndex(where: { $0.id == id }) else { throw ConfigurationLibraryError.staleGeneration }
        let new = try validSubRuleName(name, besides: id)
        let old = subRules[index].name
        guard new != old else { return }
        subRules[index].name = new
        rewriteRuleTexts { raw in
            guard Self.subRuleTarget(of: raw) == old else { return raw }
            var fields = raw.components(separatedBy: ",")
            fields[fields.count - 1] = new
            return fields.joined(separator: ",")
        }
    }

    mutating func removeSubRule(_ id: UUID) throws {
        guard subRulesEditable else { throw ConfigurationSubRuleError.notEditable }
        guard let subRule = subRules.first(where: { $0.id == id }) else { return }
        let elsewhere = rows + subRules.filter { $0.id != id }.flatMap(\.rows)
        guard !elsewhere.contains(where: { Self.subRuleTarget(of: $0.raw) == subRule.name }) else {
            throw ConfigurationSubRuleError.inUse(subRule.name)
        }
        subRules.removeAll { $0.id == id }
    }

    mutating func moveSubRules(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        guard subRulesEditable, offsets.allSatisfy(subRules.indices.contains) else { return }
        var moved = subRules
        let lifted = offsets.sorted().map { moved[$0] }
        for offset in offsets.sorted(by: >) { moved.remove(at: offset) }
        let target = min(destination, subRules.count) - offsets.filter { $0 < min(destination, subRules.count) }.count
        moved.insert(contentsOf: lifted, at: max(0, min(target, moved.count)))
        subRules = moved
    }

     
     
    mutating func setSubRuleRow(_ raw: String, rowID: UUID?, in subRuleID: UUID) throws {
        guard subRulesEditable else { throw ConfigurationSubRuleError.notEditable }
        guard let index = subRules.firstIndex(where: { $0.id == subRuleID }) else { throw ConfigurationLibraryError.staleGeneration }
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ConfigurationSubRuleError.ruleRequired }
        var candidate = self
        if let rowID {
            guard let row = candidate.subRules[index].rows.firstIndex(where: { $0.id == rowID }) else {
                throw ConfigurationLibraryError.staleGeneration
            }
            candidate.subRules[index].rows[row].raw = raw
        } else {
            let rows = candidate.subRules[index].rows
            candidate.subRules[index].rows.insert(Row(raw: raw), at: Self.pinnedFinalIndex(rows))
        }
        try candidate.validateSubRuleCycles()
        self = candidate
    }

    mutating func removeSubRuleRows(_ ids: Set<UUID>, in subRuleID: UUID) {
        guard subRulesEditable, let index = subRules.firstIndex(where: { $0.id == subRuleID }) else { return }
        subRules[index].rows.removeAll { ids.contains($0.id) }
    }

    mutating func moveSubRuleRows(fromOffsets offsets: IndexSet, toOffset destination: Int, in subRuleID: UUID) {
        guard subRulesEditable, let index = subRules.firstIndex(where: { $0.id == subRuleID }) else { return }
        subRules[index].rows = Self.rows(subRules[index].rows, movingFromOffsets: offsets, toOffset: destination)
    }

    mutating func moveSubRuleRow(_ id: UUID, offset: Int, in subRuleID: UUID) {
        guard subRulesEditable, let index = subRules.firstIndex(where: { $0.id == subRuleID }) else { return }
        subRules[index].rows = Self.rows(subRules[index].rows, moving: id, offset: offset)
    }

    private func validSubRuleName(_ name: String, besides id: UUID?) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ConfigurationSubRuleError.nameRequired }
        guard !trimmed.contains(",") else { throw ConfigurationSubRuleError.nameHasComma(trimmed) }
        guard !subRules.contains(where: { $0.name == trimmed && $0.id != id }) else {
            throw ConfigurationSubRuleError.duplicate(trimmed)
        }
        return trimmed
    }

     
     
     
    internal func validateSubRuleCycles() throws {
        let names = Set(subRules.map(\.name))
        let graph = Dictionary(subRules.map { subRule in
            (subRule.name, subRule.rows.compactMap { Self.subRuleTarget(of: $0.raw) }.filter(names.contains))
        }, uniquingKeysWith: { first, _ in first })
        var visiting: Set<String> = [], visited: Set<String> = []
        func visit(_ name: String) throws {
            guard let edges = graph[name], !visited.contains(name) else { return }
            guard visiting.insert(name).inserted else { throw ConfigurationSubRuleError.cycle(name) }
            for edge in edges { try visit(edge) }
            visiting.remove(name); visited.insert(name)
        }
        for subRule in subRules { try visit(subRule.name) }
    }
}


 
 
 
 
 
 
public enum ConfigurationDocumentEdits {
     
     
    public static let mapsByEntry: Set<String> = ["sub-rules", "rule-providers", "proxy-providers"]

    public static func edits(from old: OrderedJSON, to new: OrderedJSON) -> [ConfigurationPageEdit] {
        guard case .object(let before) = old, case .object(let after) = new else {
            return old == new ? [] : [.set(path: [], to: new)]
        }
        var edits: [ConfigurationPageEdit] = []
        let oldValues = Dictionary(before.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
        let newKeys = Set(after.map(\.key))
        for (key, value) in after {
            guard let previous = oldValues[key] else {
                edits.append(.insertKey(path: [], key: key, value: value, before: nil))
                continue
            }
            guard previous != value else { continue }
            switch (previous, value) {
            case (.array(let a), .array(let b)):
                edits += list(path: [key], a, b)
            case (.object(let a), .object(let b)) where mapsByEntry.contains(key):
                edits += map(path: [key], a, b)
            default:
                edits.append(.set(path: [key], to: value))
            }
        }
        for (key, _) in before where !newKeys.contains(key) {
            edits.append(.remove(path: [key]))
        }
        return edits
    }

     
    static func list(path: [String], _ a: [OrderedJSON], _ b: [OrderedJSON]) -> [ConfigurationPageEdit] {
        var head = 0
        while head < a.count, head < b.count, a[head] == b[head] { head += 1 }
        var tail = 0
        while tail < a.count - head, tail < b.count - head, a[a.count - 1 - tail] == b[b.count - 1 - tail] { tail += 1 }
        let gone = Array(a[head..<(a.count - tail)])
        let come = Array(b[head..<(b.count - tail)])
        if gone.count == come.count {
            return zip(gone, come).enumerated().compactMap { offset, pair in
                pair.0 == pair.1 ? nil : .replace(path: path, at: head + offset, value: pair.1)
            }
        }
        var edits: [ConfigurationPageEdit] = []
        if !gone.isEmpty { edits.append(.delete(path: path, at: IndexSet(head..<(head + gone.count)))) }
        for (offset, item) in come.enumerated() { edits.append(.insert(path: path, at: head + offset, value: item)) }
        return edits
    }

    static func map(path: [String], _ a: [(key: String, value: OrderedJSON)],
                    _ b: [(key: String, value: OrderedJSON)]) -> [ConfigurationPageEdit] {
        let oldValues = Dictionary(a.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
        let newKeys = Set(b.map(\.key))
        var edits: [ConfigurationPageEdit] = []
        for (key, value) in b {
            guard let previous = oldValues[key] else {
                edits.append(.insertKey(path: path, key: key, value: value, before: nil))
                continue
            }
            guard previous != value else { continue }
            if case .array(let x) = previous, case .array(let y) = value {
                edits += list(path: path + [key], x, y)
            } else {
                edits.append(.set(path: path + [key], to: value))
            }
        }
        for (key, _) in a where !newKeys.contains(key) {
            edits.append(.remove(path: path + [key]))
        }
        return edits
    }
}
