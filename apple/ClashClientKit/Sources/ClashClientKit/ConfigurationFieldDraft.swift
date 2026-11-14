import Foundation

 
 
 
 
 
 
public struct ConfigurationFieldDraft: Equatable, Sendable {
    public enum Control: Equatable, Sendable {
         
        case select([String])
         
        case multiSelect([String], ordered: Bool)
        case toggle
        case number(min: Double?, max: Double?, unit: String?)
         
        case reference([String])
         
        case references([String], ordered: Bool)
         
        case suggest([String])
        case text(ConfigurationFieldFormat?)
         
        case textList(ConfigurationFieldFormat?, suggestions: [String])
    }

    public let control: Control
     
     
    public let isOrdered: Bool
     
    public let original: OrderedJSON?
     
     
    public let unknown: [String]

     
    public var text: String
    public var flag: Bool
     
    public var lines: String
     
    public var selection: [String]
     
     
    public var pendingItem = ""

    private let start: Start
    private let separator: String?
    private let caseInsensitive: Bool
     
    public var readsWithoutCase: Bool { caseInsensitive }
     
    private let marks: [ConfigurationUnavailableValue]
     
    private let suggestionFormat: ConfigurationFieldFormat?
     
    private let numbers: Bool
     
    private let bareEntries: Set<String>
    private let entriesAllBare: Bool
     
     
    public let path: String
     
    private let named: [String]
     
     
    public let zeroMeansUnset: Bool

    private struct Start: Equatable, Sendable {
        let text: String
        let flag: Bool
        let lines: String
        let selection: [String]
    }

     
     
     
     
     
    public init?(field: ConfigurationField, value: OrderedJSON?, in document: OrderedJSON) {
        let options = field.values ?? []
         
         
        func offered(_ written: [String]) -> [String] { field.offeredValues(written: written).map(\.value) }
         
         
        if case .string(let text)? = value, text.contains(where: \.isNewline) { return nil }
        let written: String?
        switch value {
        case .string(let text)?: written = text
        case .scalar(let token)? where token != "null": written = token
        default: written = nil
        }
         
        let scalarShaped = value == nil || written != nil
        var control: Control
        var text = "", flag = false, lines = "", selection: [String] = [], unknown: [String] = []
        var separator: String?
        var entries: [(text: String, bare: Bool)] = []
        switch field.kind {
        case .select:
            guard !options.isEmpty, scalarShaped else { return nil }
            let choices = offered(written.map { [$0] } ?? [])
            control = .select(choices)
            if let written {
                 
                 
                text = field.canonical(written) ?? written
                if !choices.contains(text) { unknown = [written] }
            } else {
                text = field.defaultText.flatMap(field.canonical).flatMap { choices.contains($0) ? $0 : nil } ?? choices.first ?? ""
            }
        case .toggle:
            switch value {
            case nil: flag = field.defaultText == "true"
            case .scalar(let token)? where token == "true" || token == "false": flag = token == "true"
            default: return nil
            }
            control = .toggle
        case .number:
            guard value == nil || written.map(Self.isNumber) == true else { return nil }
            control = .number(min: field.min, max: field.max, unit: field.unit)
            text = written ?? field.defaultText.flatMap { Self.isNumber($0) ? $0 : nil } ?? ""
        case .text:
            guard scalarShaped else { return nil }
            control = .text(field.format)
            text = written ?? ""
        case .suggest:
            guard scalarShaped else { return nil }
            let suggestions = offered(written.map { [$0] } ?? [])
            control = suggestions.isEmpty ? .text(field.format) : .suggest(suggestions)
            text = written ?? field.defaultText.flatMap { suggestions.contains($0) ? $0 : nil } ?? suggestions.first ?? ""
        case .textList:
             
             
            let bare: Bool
            if case .scalar? = value { bare = true } else { bare = false }
            guard let items = Self.entries(value) ?? written.map({ [(text: $0, bare: bare)] }) else { return nil }
            entries = items
             
            control = .textList(field.format, suggestions: offered([]))
            lines = items.map(\.text).joined(separator: "\n")
        case .multiSelect:
            guard !options.isEmpty else { return nil }
            if let joinedBy = field.separator {
                guard scalarShaped else { return nil }
                separator = joinedBy
                selection = (written ?? "").components(separatedBy: joinedBy).filter { !$0.isEmpty }
            } else {
                guard let items = Self.entries(value) else { return nil }
                entries = items
                selection = items.map(\.text)
            }
            let choices = offered(selection)
            unknown = selection.filter { field.canonical($0) == nil && !choices.contains($0) }
            control = .multiSelect(choices, ordered: field.ordered == true)
        case .reference:
            let sources = field.refers ?? []
             
             
             
            let defined = ConfigurationReferenceNames.names(sources.filter { $0 != .builtin && $0 != .global }, in: document)
            let names = defined.isEmpty ? [] : ConfigurationReferenceNames.names(sources, in: document)
            let isList: Bool
            switch value {
            case .array?: isList = true
            case nil: isList = field.ordered == true || field.defaultText?.hasPrefix("[") == true
            default: isList = false
            }
            if isList {
                guard let items = Self.entries(value) else { return nil }
                entries = items
                if names.isEmpty {
                    control = .textList(nil, suggestions: [])
                    lines = items.map(\.text).joined(separator: "\n")
                } else {
                    control = .references(names, ordered: field.ordered == true)
                    selection = items.map(\.text)
                    unknown = selection.filter { !names.contains($0) }
                }
            } else {
                guard scalarShaped else { return nil }
                if names.isEmpty {
                    control = .text(nil)
                    text = written ?? ""
                } else {
                    control = .reference(names)
                    if let written {
                        text = written
                        if !names.contains(written) { unknown = [written] }
                    } else {
                        text = field.defaultText.flatMap { names.contains($0) ? $0 : nil } ?? names[0]
                    }
                }
            }
        case .object, .map, .objectList, .unrecognised:
            return nil
        }
        self.control = control
        self.isOrdered = field.ordered == true
        self.original = value
        self.unknown = unknown
        self.text = text
        self.flag = flag
        self.lines = lines
        self.selection = selection
        self.start = Start(text: text, flag: flag, lines: lines, selection: selection)
        self.separator = separator
        self.caseInsensitive = field.caseInsensitive == true
        self.marks = field.unavailableValues
        self.suggestionFormat = field.format
        self.numbers = !options.isEmpty && options.allSatisfy(Self.isNumber)
        self.bareEntries = Set(entries.filter(\.bare).map(\.text))
        self.entriesAllBare = !entries.isEmpty && entries.allSatisfy(\.bare)
        self.path = field.path
        self.named = options
        self.zeroMeansUnset = field.zeroMeansUnset
    }

     
     
    private static func entries(_ value: OrderedJSON?) -> [(text: String, bare: Bool)]? {
        guard let value else { return [] }
        guard case .array(let items) = value else { return nil }
        var entries: [(text: String, bare: Bool)] = []
        for item in items {
            switch item {
            case .string(let text) where !text.contains(where: \.isNewline): entries.append((text, false))
            case .scalar(let token) where token != "null": entries.append((token, true))
            default: return nil
            }
        }
        return entries
    }

     
     
    public static func isNumber(_ text: String) -> Bool {
        text.range(of: #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil
    }

    private static func lineEntries(_ lines: String) -> [String] {
        lines.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

     

     
     
    public var choices: [String] {
        switch control {
        case .select(let options), .reference(let options): return unknown + options
        case .suggest(let options): return options
        default: return []
        }
    }

     
    public var showsUnknown: Bool { unknown.contains(text) }

     
     
     
    public var unavailableInUse: [ConfigurationUnavailableValue] {
        let inUse: [String]
        switch control {
        case .select, .suggest: inUse = [text]
        case .multiSelect: inUse = selection
        case .textList: inUse = items
        default: inUse = []
        }
        var seen = Set<String>()
        return inUse.compactMap(unavailability(of:)).filter { seen.insert($0.value).inserted }
    }

     
    public func unavailability(of choice: String) -> ConfigurationUnavailableValue? {
        marks.first { matches($0.value, choice) }
    }

     
     
     
     
    public var isCustom: Bool {
        guard case .suggest(let options) = control else { return false }
        return choice(in: options) == nil
    }

    public func isSelected(_ option: String) -> Bool { selection.contains { matches($0, option) } }

    private func matches(_ entry: String, _ option: String) -> Bool {
        caseInsensitive ? entry.lowercased() == option.lowercased() : entry == option
    }

     
    public mutating func toggle(_ option: String) {
        if let index = selection.firstIndex(where: { matches($0, option) }) {
            selection.remove(at: index)
        } else {
            selection.append(option)
        }
    }

     
     
    public mutating func move(from offsets: IndexSet, to destination: Int) {
        let moving = offsets.sorted().map { selection[$0] }
        let before = offsets.filter { $0 < destination }.count
        for index in offsets.sorted(by: >) { selection.remove(at: index) }
        selection.insert(contentsOf: moving, at: destination - before)
    }

     

     
     
    public var items: [String] {
        get { Self.lineEntries(lines) }
        set { lines = newValue.joined(separator: "\n") }
    }

     
    public mutating func add(_ item: String) {
        let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isNewline), !containsItem(trimmed),
              itemProblem(trimmed) == nil else { return }
        items.append(trimmed)
    }

    public mutating func removeItems(at offsets: IndexSet) {
        var next = items
        for index in offsets.sorted(by: >) where next.indices.contains(index) { next.remove(at: index) }
        items = next
    }

     
     
    public mutating func moveItems(from offsets: IndexSet, to destination: Int) {
        var next = items
        let moving = offsets.sorted().filter(next.indices.contains).map { next[$0] }
        let before = offsets.filter { $0 < destination }.count
        for index in offsets.sorted(by: >) where next.indices.contains(index) { next.remove(at: index) }
        next.insert(contentsOf: moving, at: min(max(destination - before, 0), next.count))
        items = next
    }

    public func containsItem(_ item: String) -> Bool { items.contains { matches($0, item) } }

     
     
     
    private var pendingEntry: String? {
        let trimmed = pendingItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isNewline), !containsItem(trimmed),
              itemProblem(trimmed) == nil else { return nil }
        return trimmed
    }

     
     
     
    public func itemProblem(_ item: String) -> ConfigurationFieldProblem? {
        guard case .textList(let format, _) = control else { return nil }
        let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
        return ConfigurationFieldValidation.problem(item, format: format, path: path, allowed: named,
                                                    siblings: items.filter { !matches($0, trimmed) })
    }

     
    public var pendingProblem: ConfigurationFieldProblem? { itemProblem(pendingItem) }

     
    private var itemsWithPending: [String] { items + (pendingEntry.map { [$0] } ?? []) }

     
     
    public mutating func toggleItem(_ item: String) {
        if let index = items.firstIndex(where: { matches($0, item) }) {
            removeItems(at: IndexSet(integer: index))
        } else {
            add(item)
        }
    }

    public var isChanged: Bool {
        switch control {
        case .toggle: return flag != start.flag
        case .textList: return itemsWithPending != Self.lineEntries(start.lines)
        case .multiSelect, .references: return selection != start.selection
        case .number: return text.trimmingCharacters(in: .whitespaces) != start.text.trimmingCharacters(in: .whitespaces)
        case .select, .reference, .suggest, .text: return text != start.text
        }
    }

     
     
     
     
    public var isValid: Bool {
        switch control {
        case .number: return Self.isNumber(text.trimmingCharacters(in: .whitespaces)) && problem == nil
        case .text, .suggest: return problem == nil
        default: return true
        }
    }

     
     
    public func problem(typing candidate: String) -> ConfigurationFieldProblem? {
        var typed = self
        typed.text = candidate
        return typed.problem
    }

     
     
    public var problem: ConfigurationFieldProblem? {
        switch control {
        case .number(let min, let max, _):
             
            return ConfigurationFieldValidation.problem(number: text, min: min, max: max, whole: true,
                                                        zeroMeansUnset: zeroMeansUnset)
        case .text(let format):
            return ConfigurationFieldValidation.problem(text, format: format, path: path, allowed: named)
        case .suggest(let options):
            guard !options.contains(text) else { return nil }
            return ConfigurationFieldValidation.problem(text, format: suggestionFormat, path: path, allowed: options)
        default:
            return nil
        }
    }

    public var isOutOfRange: Bool {
        let typed = text.trimmingCharacters(in: .whitespaces)
        guard case .number(let min, let max, _) = control, Self.isNumber(typed), let number = Double(typed) else { return false }
        if zeroMeansUnset, number == 0 { return false }
        return (min.map { number < $0 } ?? false) || (max.map { number > $0 } ?? false)
    }

     
    public var format: ConfigurationFieldFormat? {
        switch control {
        case .text(let format), .textList(let format, _): return format
        case .suggest: return suggestionFormat
        default: return nil
        }
    }

     
    public var misformatted: [String] {
        switch control {
        case .text, .suggest:
            let value = text.trimmingCharacters(in: .whitespaces)
            return problem == nil ? [] : [value]
        case .textList:
            return Self.lineEntries(lines).filter { itemProblem($0) != nil }
        default:
            return []
        }
    }

     

     
     
    public var value: OrderedJSON {
        if let original, !isChanged { return original }
        switch control {
        case .select, .reference, .suggest: return word(text)
        case .toggle: return .scalar(flag ? "true" : "false")
        case .number: return .scalar(text.trimmingCharacters(in: .whitespaces))
        case .text(let format): return .string(Self.isShaped(format) ? text.trimmingCharacters(in: .whitespaces) : text)
        case .textList: return .array(itemsWithPending.map(entry))
        case .multiSelect, .references:
            if let separator { return .string(selection.joined(separator: separator)) }
            return .array(selection.map(entry))
        }
    }

     
     
     
    static func isShaped(_ format: ConfigurationFieldFormat?) -> Bool {
        switch format {
        case nil, .text?, .password?, .path?, .filter?, .unrecognised?: return false
        default: return true
        }
    }

     
     
     
    private func word(_ text: String) -> OrderedJSON {
        if case .string? = original { return .string(text) }
        let bareBefore: Bool
        if case .scalar? = original { bareBefore = true } else { bareBefore = false }
        return Self.isNumber(text) && (numbers || bareBefore) ? .scalar(text) : .string(text)
    }

    private func entry(_ text: String) -> OrderedJSON {
        if bareEntries.contains(text) { return .scalar(text) }
        return Self.isNumber(text) && (numbers || entriesAllBare) ? .scalar(text) : .string(text)
    }
}

extension ConfigurationFieldFormat {
     
    public var example: String? {
        switch self {
        case .domain, .host: return "example.com"
        case .url: return "https://example.com/"
        case .regex: return "^.*\\.example\\.com$"
        case .cidr: return "10.0.0.0/8"
        case .ip: return "1.1.1.1"
        case .ipPort: return "1.1.1.1:53"
        case .portRange: return "443,1000-2000"
        case .duration: return "30s"
        case .uuid: return "5f0a9c3e-8d5b-4c2e-9c1a-2b3c4d5e6f70"
        case .base64: return "aGFrbw=="
        case .hex: return "0aff"
        case .dnsServer: return "https://1.1.1.1/dns-query"
        case .path, .password, .filter, .text, .unrecognised: return nil
        }
    }
}
