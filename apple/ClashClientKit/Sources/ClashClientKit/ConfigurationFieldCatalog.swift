import Foundation

 
 
 
 
public enum ConfigurationFieldKind: String, Equatable, Sendable {
     
    case select
     
    case multiSelect
    case toggle
     
    case number
     
    case reference
     
    case text
     
    case textList
     
    case suggest
     
    case object, map, objectList
     
     
    case unrecognised
}

extension ConfigurationFieldKind: Decodable {
    public init(from decoder: Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unrecognised
    }
}

 
public enum ConfigurationFieldFormat: String, Equatable, Sendable {
    case domain, host, url, regex, path, password, uuid, cidr, ip, ipPort, portRange, duration
    case base64, hex, filter, dnsServer, text
    case unrecognised
}

extension ConfigurationFieldFormat: Decodable {
    public init(from decoder: Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unrecognised
    }
}

 
 
public enum ConfigurationFieldReference: String, Equatable, Sendable {
    case proxy, group, proxyProvider, ruleProvider, subRule, listener
     
    case builtin
     
    case global
     
     
    case policy
    case unrecognised

     
     
    static func sources(_ words: [String]) -> [ConfigurationFieldReference] {
        words.flatMap { word -> [ConfigurationFieldReference] in
            let source = Self(rawValue: word) ?? .unrecognised
            return source == .policy ? [.proxy, .group, .builtin] : [source]
        }
    }

    static func decodeSources<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, forKey key: Key)
        -> [ConfigurationFieldReference]? {
        if let words = try? container.decodeIfPresent([String].self, forKey: key) { return sources(words) }
        if let word = try? container.decodeIfPresent(String.self, forKey: key) { return sources([word]) }
        return nil
    }
}

 
public enum ConfigurationUnknownValue: String, Equatable, Sendable {
     
    case refused
     
    case ignored
     
    case passthrough
    case unrecognised
}

extension ConfigurationUnknownValue: Decodable {
    public init(from decoder: Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unrecognised
    }
}

 
public struct ConfigurationFieldValueSpec: Decodable, Equatable, Sendable {
    public let kind: ConfigurationFieldKind
    public let values: [String]?
    public let caseInsensitive: Bool?
    public let format: ConfigurationFieldFormat?
    public let refers: [ConfigurationFieldReference]?

    private enum CodingKeys: String, CodingKey { case kind, values, caseInsensitive, format, refers }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(ConfigurationFieldKind.self, forKey: .kind)
        values = try? container.decodeIfPresent([String].self, forKey: .values)
        caseInsensitive = try? container.decodeIfPresent(Bool.self, forKey: .caseInsensitive)
        format = try? container.decodeIfPresent(ConfigurationFieldFormat.self, forKey: .format)
        refers = ConfigurationFieldReference.decodeSources(container, forKey: .refers)
    }
}

 
 
 
 
 
 
 
public struct ConfigurationPlatformDecision: Decodable, Equatable, Sendable {
    public enum When: String, Decodable, Equatable, Sendable {
        case always, conditional
         
        case defaultOnly = "default"
        case unrecognised
        public init(from decoder: Decoder) throws {
            self = When(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unrecognised
        }
    }
    public let when: When
     
    public let condition: String?
    public let category: String?
     
    public let effective: String?
    public let reason: String?
     
    public let alternative: String?
     
     
     
     
    public let value: String?
     
     
     
    public let replaces: [String]?
     
     
     
     
    public let unwritten: String?
     
     
     
     
     
    public let onlyWhere: [String: [String]]?

     
     
     
    public var overridesTheFile: Bool { when == .always }

     
     
     
    public func applies(to entry: OrderedJSON) -> Bool { entry.meets(onlyWhere) }

    public init(when: When, condition: String? = nil, category: String? = nil, effective: String? = nil,
                reason: String? = nil, alternative: String? = nil, value: String? = nil, replaces: [String]? = nil,
                unwritten: String? = nil, onlyWhere: [String: [String]]? = nil) {
        self.when = when; self.condition = condition; self.category = category; self.effective = effective
        self.reason = reason; self.alternative = alternative; self.value = value; self.replaces = replaces
        self.unwritten = unwritten; self.onlyWhere = onlyWhere
    }

    private enum CodingKeys: String, CodingKey {
        case when, condition, category, effective, reason, alternative, value, replaces, unwritten, onlyWhere
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        when = try container.decode(When.self, forKey: .when)
        condition = try? container.decodeIfPresent(String.self, forKey: .condition)
        category = try? container.decodeIfPresent(String.self, forKey: .category)
        effective = try? container.decodeIfPresent(String.self, forKey: .effective)
        reason = try? container.decodeIfPresent(String.self, forKey: .reason)
        alternative = try? container.decodeIfPresent(String.self, forKey: .alternative)
         
        value = (try? container.decodeIfPresent(ConfigurationField.LenientScalar.self, forKey: .value))?.flatMap(\.text)
        if let list = try? container.decodeIfPresent([ConfigurationField.LenientScalar].self, forKey: .replaces) {
            replaces = list.compactMap(\.text)
        } else {
            replaces = (try? container.decodeIfPresent(ConfigurationField.LenientScalar.self, forKey: .replaces))?
                .flatMap(\.text).map { [$0] }
        }
        unwritten = (try? container.decodeIfPresent(ConfigurationField.LenientScalar.self, forKey: .unwritten))?.flatMap(\.text)
         
         
        onlyWhere = try? container.decodeIfPresent([String: [String]].self, forKey: .onlyWhere)
    }
}

 
 
 
public struct ConfigurationPlatformKey: Decodable, Equatable, Sendable {
    public let path: String
    public let category: String
    public let effective: String
    public let reason: String
    public let alternative: String?
     
     
    public let value: String?
     
    public let honoured: Bool?
     
    public let defaultOnly: Bool?
     
     
     
    public let onlyWhere: [String: [String]]?

     
    public var overridesTheFile: Bool { honoured != true && defaultOnly != true }

     
    public func applies(to entry: OrderedJSON) -> Bool { entry.meets(onlyWhere) }

    private enum CodingKeys: String, CodingKey {
        case path, category, effective, reason, alternative, value, honoured, defaultOnly, onlyWhere
    }

     
     
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        category = try container.decode(String.self, forKey: .category)
        effective = try container.decode(String.self, forKey: .effective)
        reason = try container.decode(String.self, forKey: .reason)
        alternative = try container.decodeIfPresent(String.self, forKey: .alternative)
        value = try container.decodeIfPresent(String.self, forKey: .value)
        honoured = try container.decodeIfPresent(Bool.self, forKey: .honoured)
        defaultOnly = try container.decodeIfPresent(Bool.self, forKey: .defaultOnly)
        onlyWhere = try? container.decodeIfPresent([String: [String]].self, forKey: .onlyWhere)
    }
}

 
 
 
 
 
public struct ConfigurationUnavailableValue: Decodable, Equatable, Sendable {
    public let value: String
     
    public let reason: String
     
    public let alternative: String?

    public init(value: String, reason: String, alternative: String? = nil) {
        self.value = value; self.reason = reason; self.alternative = alternative
    }

    private enum CodingKeys: String, CodingKey { case value, reason, alternative }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decode(String.self, forKey: .value)
        reason = (try? container.decodeIfPresent(String.self, forKey: .reason)) ?? ""
        let instead = (try? container.decodeIfPresent(String.self, forKey: .alternative)) ?? nil
        alternative = instead?.isEmpty == false ? instead : nil
    }
}

 
 
 
public struct ConfigurationFieldChoice: Equatable, Sendable {
    public let value: String
     
    public let unavailable: ConfigurationUnavailableValue?
    public var isAvailable: Bool { unavailable == nil }

    public init(value: String, unavailable: ConfigurationUnavailableValue? = nil) {
        self.value = value; self.unavailable = unavailable
    }
}

 
public struct ConfigurationField: Decodable, Equatable, Sendable {
     
     
    public let path: String
    public let kind: ConfigurationFieldKind
     
     
    public let values: [String]?
     
     
    public let separator: String?
    public let caseInsensitive: Bool?
     
    public let ordered: Bool?
    public let min: Double?
    public let max: Double?
    public let unit: String?
     
    public let defaultText: String?
    public let format: ConfigurationFieldFormat?
     
    public let refers: [ConfigurationFieldReference]?
    public let unknownValue: ConfigurationUnknownValue?
     
     
    public let platformReason: String?
    public let isPlatformDecided: Bool
     
     
    public let isRequired: Bool
     
     
     
    public let platformDecision: ConfigurationPlatformDecision?
     
    public let key: ConfigurationFieldValueSpec?
    public let value: ConfigurationFieldValueSpec?
     
    public let source: String?
    public let valuesSource: String?
     
     
    public let unavailableValues: [ConfigurationUnavailableValue]
     
     
     
    public let zeroMeansUnset: Bool
     
     
     
     
     
    public let requiredOneOf: [String]?

    private enum CodingKeys: String, CodingKey {
        case path, kind, values, separator, caseInsensitive, ordered, min, max, unit, format, refers, unknownValue
        case platformDecided, platformDecision, required, key, value, source, valuesSource, unavailableValues
        case zeroMeansUnset, requiredOneOf
        case defaultValue = "default"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        kind = try container.decode(ConfigurationFieldKind.self, forKey: .kind)
        values = try? container.decodeIfPresent([String].self, forKey: .values)
        let joinedBy = (try? container.decodeIfPresent(String.self, forKey: .separator)) ?? nil
        separator = joinedBy?.isEmpty == false ? joinedBy : nil
        caseInsensitive = try? container.decodeIfPresent(Bool.self, forKey: .caseInsensitive)
        ordered = try? container.decodeIfPresent(Bool.self, forKey: .ordered)
        min = try? container.decodeIfPresent(Double.self, forKey: .min)
        max = try? container.decodeIfPresent(Double.self, forKey: .max)
        unit = try? container.decodeIfPresent(String.self, forKey: .unit)
        defaultText = (try? container.decodeIfPresent(LenientScalar.self, forKey: .defaultValue))?.flatMap(\.text)
        format = try? container.decodeIfPresent(ConfigurationFieldFormat.self, forKey: .format)
        refers = ConfigurationFieldReference.decodeSources(container, forKey: .refers)
        unknownValue = try? container.decodeIfPresent(ConfigurationUnknownValue.self, forKey: .unknownValue)
         
        if let reason = try? container.decodeIfPresent(String.self, forKey: .platformDecided) {
            platformReason = reason; isPlatformDecided = true
        } else if let flag = try? container.decodeIfPresent(Bool.self, forKey: .platformDecided) {
            platformReason = nil; isPlatformDecided = flag
        } else if let object = try? container.decodeIfPresent(PlatformDecision.self, forKey: .platformDecided) {
            platformReason = object.reason; isPlatformDecided = true
        } else {
            platformReason = nil; isPlatformDecided = false
        }
        isRequired = ((try? container.decodeIfPresent(Bool.self, forKey: .required)) ?? nil) ?? false
        platformDecision = try? container.decodeIfPresent(ConfigurationPlatformDecision.self, forKey: .platformDecision)
        key = try? container.decodeIfPresent(ConfigurationFieldValueSpec.self, forKey: .key)
        value = try? container.decodeIfPresent(ConfigurationFieldValueSpec.self, forKey: .value)
        source = try? container.decodeIfPresent(String.self, forKey: .source)
        valuesSource = try? container.decodeIfPresent(String.self, forKey: .valuesSource)
         
        unavailableValues = ((try? container.decodeIfPresent([LenientUnavailable].self, forKey: .unavailableValues)) ?? nil)?
            .compactMap(\.value) ?? []
         
        zeroMeansUnset = ((try? container.decodeIfPresent(Bool.self, forKey: .zeroMeansUnset)) ?? nil) ?? false
        let group = (try? container.decodeIfPresent([String].self, forKey: .requiredOneOf)) ?? nil
        requiredOneOf = group?.isEmpty == false ? group : nil
    }

    private struct LenientUnavailable: Decodable {
        let value: ConfigurationUnavailableValue?
        init(from decoder: Decoder) throws { value = try? ConfigurationUnavailableValue(from: decoder) }
    }

     
     
     
     
     
     
    public func offeredValues(written: [String] = []) -> [ConfigurationFieldChoice] {
        let fold: (String) -> String = { caseInsensitive == true ? $0.lowercased() : $0 }
        let marked = Dictionary(unavailableValues.map { (fold($0.value), $0) }, uniquingKeysWith: { first, _ in first })
        let writes = Set(written.map(fold))
        var offered: [ConfigurationFieldChoice] = []
        var seen = Set<String>()
        for value in values ?? [] where seen.insert(fold(value)).inserted {
            if let unavailable = marked[fold(value)] {
                if writes.contains(fold(value)) { offered.append(ConfigurationFieldChoice(value: value, unavailable: unavailable)) }
            } else {
                offered.append(ConfigurationFieldChoice(value: value))
            }
        }
        for value in written where !seen.contains(fold(value)) {
            guard let unavailable = marked[fold(value)], seen.insert(fold(value)).inserted else { continue }
            offered.append(ConfigurationFieldChoice(value: value, unavailable: unavailable))
        }
        return offered
    }

     
    public func offeredValues(written: String?) -> [ConfigurationFieldChoice] {
        offeredValues(written: written.map { [$0] } ?? [])
    }

     
    public func unavailability(of value: String) -> ConfigurationUnavailableValue? {
        let fold: (String) -> String = { caseInsensitive == true ? $0.lowercased() : $0 }
        return unavailableValues.first { fold($0.value) == fold(value) }
    }

    private struct PlatformDecision: Decodable { let reason: String? }

     
     
    init(entryOf map: ConfigurationField, at path: String, spec: ConfigurationFieldValueSpec) {
        self.path = path
        kind = spec.kind
        values = spec.values
        separator = nil
        caseInsensitive = spec.caseInsensitive
        ordered = nil; min = nil; max = nil; unit = nil; defaultText = nil
        format = spec.format
        refers = spec.refers
        unknownValue = nil
        platformReason = map.platformReason
        isPlatformDecided = map.isPlatformDecided
        isRequired = false
        platformDecision = nil
        key = nil; value = nil
        source = map.source; valuesSource = nil
        unavailableValues = []
        zeroMeansUnset = false; requiredOneOf = nil
    }

     
     
     
     
     
     
    func asThePlatformRunsIt(listed entry: ConfigurationPlatformKey?) -> ConfigurationField {
        var decision = platformDecision
        var flagged = isPlatformDecided, reason = platformReason
        if let entry, !entry.overridesTheFile {
            flagged = false; reason = nil
            if entry.honoured == true {
                decision = nil
            } else if decision == nil || decision?.when == .always {
                decision = ConfigurationPlatformDecision(when: .defaultOnly, category: decision?.category ?? entry.category,
                                                         effective: decision?.effective ?? entry.effective,
                                                         reason: decision?.reason ?? entry.reason,
                                                         alternative: decision?.alternative ?? entry.alternative,
                                                         value: decision?.value ?? entry.value,
                                                         unwritten: decision?.unwritten,
                                                         onlyWhere: decision?.onlyWhere ?? entry.onlyWhere)
            }
        }
        var defaultText = self.defaultText
        if let unwritten = decision?.unwritten, !unwritten.isEmpty {
             
             
             
            defaultText = unwritten
        } else if decision?.when == .defaultOnly, let platformDefault = decision?.value, !platformDefault.isEmpty {
            defaultText = platformDefault
        }
        guard decision != platformDecision || defaultText != self.defaultText || flagged != isPlatformDecided else { return self }
        return ConfigurationField(self, platformDecision: decision, defaultText: defaultText,
                                  isPlatformDecided: flagged, platformReason: reason)
    }

    private init(_ field: ConfigurationField, platformDecision: ConfigurationPlatformDecision?, defaultText: String?,
                 isPlatformDecided: Bool, platformReason: String?) {
        path = field.path; kind = field.kind; values = field.values; separator = field.separator
        caseInsensitive = field.caseInsensitive; ordered = field.ordered; min = field.min; max = field.max
        unit = field.unit; self.defaultText = defaultText; format = field.format; refers = field.refers
        unknownValue = field.unknownValue; self.platformReason = platformReason; self.isPlatformDecided = isPlatformDecided
        isRequired = field.isRequired; self.platformDecision = platformDecision; key = field.key; value = field.value
        source = field.source; valuesSource = field.valuesSource; unavailableValues = field.unavailableValues
        zeroMeansUnset = field.zeroMeansUnset; requiredOneOf = field.requiredOneOf
    }

     
    fileprivate struct LenientScalar: Decodable {
        let text: String?
        init(from decoder: Decoder) throws {
            let single = try decoder.singleValueContainer()
            if single.decodeNil() { text = nil }
            else if let bool = try? single.decode(Bool.self) { text = bool ? "true" : "false" }
            else if let int = try? single.decode(Int.self) { text = String(int) }
            else if let double = try? single.decode(Double.self) { text = String(double) }
            else if let string = try? single.decode(String.self) { text = string }
            else if let list = try? single.decode([String].self) { text = list.joined(separator: ", ") }
            else { text = nil }
        }
    }

     
     
     
    public func canonical(_ value: String) -> String? {
        guard let values else { return nil }
        if caseInsensitive == true { return values.first { $0.lowercased() == value.lowercased() } }
        return values.first { $0 == value }
    }

     
     
    public func accepts(_ value: String) -> Bool {
        switch kind {
        case .select, .multiSelect: return canonical(value) != nil
        default: return true
        }
    }

     
     
     
     
     
     
     
     
    public func isWritten(_ value: OrderedJSON?) -> Bool {
        Self.isWritten(value, asNumber: kind == .number || zeroMeansUnset)
    }

     
     
    static func isWritten(_ value: OrderedJSON?, asNumber: Bool?) -> Bool {
        switch value {
        case nil: return false
        case .object(let entries)?: return !entries.isEmpty
        case .array(let items)?: return !items.isEmpty
        case .string(let text)?:
            if asNumber == true, let number = Double(text.trimmingCharacters(in: .whitespaces)) { return number != 0 }
            return !text.isEmpty
        case .scalar(let token)?:
             
            if token == "null" { return false }
            if asNumber != false, let number = Double(token) { return number != 0 }
            return true
        }
    }
}

 
 
public struct ConfigurationFieldCatalog: Sendable {
    public let fields: [ConfigurationField]
     
     
    public let platformKeys: [ConfigurationPlatformKey]
    private let byPath: [String: ConfigurationField]
     
     
    private let prefixes: Set<String>

     
    public init(fields: [ConfigurationField]) {
        self.init(fields: fields, platformKeys: [])
    }

     
     
     
     
     
    public init(fields: [ConfigurationField], platformKeys: [ConfigurationPlatformKey]) {
        let listed = Dictionary(platformKeys.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        let fields = fields.map { $0.asThePlatformRunsIt(listed: listed[$0.path]) }
        self.fields = fields
        self.platformKeys = platformKeys
        byPath = Dictionary(fields.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        var prefixes: Set<String> = []
        for field in fields {
            var end = field.path.startIndex
            while let dot = field.path[end...].firstIndex(of: ".") {
                prefixes.insert(String(field.path[..<dot]))
                end = field.path.index(after: dot)
            }
            prefixes.insert(field.path)
        }
        self.prefixes = prefixes
    }

     
     
     
     
    public func catalogPath(of steps: [ConfigurationDocumentStep], in document: OrderedJSON) -> String? {
        var path = ""
        var node: OrderedJSON? = document
        for step in steps {
            switch step {
            case .key(let key):
                let exact = path.isEmpty ? key : path + "." + key
                let wildcard = path.isEmpty ? "*" : path + ".*"
                if prefixes.contains(exact) { path = exact }
                else if prefixes.contains(wildcard) || byPath[path]?.kind == .map { path = wildcard }
                else { return nil }
                node = node?.child(key)
            case .index(let index):
                let item = node?.item(index)
                let type = item?.child("type").flatMap(\.scalarText)?.lowercased()
                if let type, prefixes.contains(path + "[" + type + "]") { path += "[" + type + "]" }
                else if prefixes.contains(path + "[]") { path += "[]" }
                else { return nil }
                node = item
            }
        }
        return path
    }

     
    public func field(at steps: [ConfigurationDocumentStep], in document: OrderedJSON) -> ConfigurationField? {
        guard let path = catalogPath(of: steps, in: document) else { return nil }
        if let field = byPath[path] { return field }
         
        if path.hasSuffix(".*"), let map = byPath[String(path.dropLast(2))], map.kind == .map, let spec = map.value {
            return ConfigurationField(entryOf: map, at: path, spec: spec)
        }
        return nil
    }

    public func field(atCatalogPath path: String) -> ConfigurationField? { byPath[path] }

     
     
     
     
     
    public func entryField(ofMapAt path: String) -> ConfigurationField? {
        if let own = byPath[path + ".*"] { return own }
        guard let map = byPath[path], map.kind == .map, let spec = map.value else { return nil }
        return ConfigurationField(entryOf: map, at: path + ".*", spec: spec)
    }

     
     
     
     
     
     
     
     
    public func platformDecision(forPath path: [String], in document: OrderedJSON? = nil) -> ConfigurationPlatformDecision? {
        guard let decision = field(forPath: path, in: document)?.platformDecision, decision.when != .defaultOnly else {
            return nil
        }
        return decision
    }

     
     
     
     
    public func defaultOnlyValue(forPath path: [String], in document: OrderedJSON? = nil) -> String? {
        guard let decision = field(forPath: path, in: document)?.platformDecision, decision.when == .defaultOnly,
              let value = decision.value, !value.isEmpty else { return nil }
        return value
    }

     
     
     
     
     
    public func conditionalDecision(forPath path: [String], in document: OrderedJSON?,
                                    conditions: Set<String>) -> ConfigurationPlatformDecision? {
        guard let field = field(forPath: path, in: document), let decision = field.platformDecision,
              decision.when == .conditional, let condition = decision.condition, conditions.contains(condition)
        else { return nil }
        guard let replaced = decision.replaces else { return decision }
        guard let running = document?.node(at: path)?.scalarText ?? field.defaultText else { return nil }
        let fold: (String) -> String = { field.caseInsensitive == true ? $0.lowercased() : $0 }
        return replaced.contains { fold($0) == fold(running) } ? decision : nil
    }

     
    private func field(forPath path: [String], in document: OrderedJSON?) -> ConfigurationField? {
        if let document, let field = field(at: path.map(ConfigurationDocumentStep.key), in: document) { return field }
        return field(atCatalogPath: path.joined(separator: "."))
    }

     
     
     
     
     
    public func requiredOneOfHolds(for field: ConfigurationField, in entry: OrderedJSON) -> Bool {
        guard let group = field.requiredOneOf else { return true }
        let parent = field.path.lastIndex(of: ".").map { String(field.path[...$0]) } ?? ""
        return group.contains { key in
            let value = entry.member(readAs: key)
            guard let sibling = byPath[parent + key] else { return ConfigurationField.isWritten(value, asNumber: nil) }
            return sibling.isWritten(value)
        }
    }

     
    public func children(of steps: [ConfigurationDocumentStep], in document: OrderedJSON) -> [ConfigurationField] {
        let base: String
        if steps.isEmpty { base = "" } else {
            guard let path = catalogPath(of: steps, in: document) else { return [] }
            base = path + "."
        }
        return fields.filter { field in
            guard field.path.hasPrefix(base) else { return false }
            let rest = field.path.dropFirst(base.count)
            return !rest.isEmpty && !rest.contains(".") && !rest.contains("[") && rest != "*"
        }
    }
}

 
public enum ConfigurationDocumentStep: Equatable, Sendable {
    case key(String)
    case index(Int)
}

 

public enum ConfigurationFieldCheck {
     
     
     
    public static func check(_ value: String, _ format: ConfigurationFieldFormat) -> Bool {
        switch format {
        case .path, .password, .filter, .text, .unrecognised: return true
        default: break
        }
        let text = value.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return false }
        return ConfigurationFieldValidation.problem(text, format: format) == nil
    }
}

 

public enum ConfigurationReferenceNames {
     
     
    public static let builtinPolicies = ["DIRECT", "REJECT", "REJECT-DROP", "PASS", "PASS-RULE", "COMPATIBLE"]

     
    public static func names(_ reference: ConfigurationFieldReference, in document: OrderedJSON) -> [String] {
        names([reference], in: document)
    }

     
     
    public static func names(_ sources: [ConfigurationFieldReference], in document: OrderedJSON) -> [String] {
        func listNames(_ key: String) -> [String] {
            guard case .array(let items)? = document.child(key) else { return [] }
            return items.compactMap { $0.child("name").flatMap(\.scalarText) }
        }
        func mapKeys(_ key: String) -> [String] {
            guard case .object(let entries)? = document.child(key) else { return [] }
            return entries.map(\.key)
        }
        var seen: Set<String> = []
        var names: [String] = []
        for source in sources {
            let found: [String]
            switch source {
            case .proxy: found = listNames("proxies")
            case .group: found = listNames("proxy-groups")
            case .builtin: found = builtinPolicies
            case .global: found = ["GLOBAL"]
            case .policy: found = listNames("proxies") + listNames("proxy-groups") + builtinPolicies
            case .proxyProvider: found = mapKeys("proxy-providers")
            case .ruleProvider: found = mapKeys("rule-providers")
            case .subRule: found = mapKeys("sub-rules")
            case .listener: found = listNames("listeners")
            case .unrecognised: found = []
            }
            for name in found where seen.insert(name).inserted { names.append(name) }
        }
        return names
    }
}

extension OrderedJSON {
     
    func child(_ key: String) -> OrderedJSON? {
        guard case .object(let entries) = self else { return nil }
        return entries.last { $0.key == key }?.value
    }

    func item(_ index: Int) -> OrderedJSON? {
        guard case .array(let items) = self, items.indices.contains(index) else { return nil }
        return items[index]
    }

     
    var scalarText: String? {
        switch self {
        case .string(let text): return text
        case .scalar(let token): return token
        default: return nil
        }
    }

     
     
     
     
    func member(readAs key: String) -> OrderedJSON? {
        if let exact = child(key) { return exact }
        guard case .object(let entries) = self else { return nil }
        let folded = Self.decoderFolded(key)
        return entries.first { Self.decoderFolded($0.key) == folded }?.value
    }

    private static func decoderFolded(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: "-").lowercased()
    }

     
     
     
     
    func meets(_ onlyWhere: [String: [String]]?) -> Bool {
        guard let onlyWhere else { return true }
        return onlyWhere.allSatisfy { key, values in
            guard let written = member(readAs: key)?.scalarText else { return false }
            return values.contains(written)
        }
    }
}
