import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
enum ClashMacFieldControl: Equatable {
     
    case choose([String], caseInsensitive: Bool)
     
     
     
    case chooseSome([String], ordered: Bool, caseInsensitive: Bool, separator: String? = nil)
    case toggle
     
     
    case number(min: Double?, max: Double?, unit: String?, zeroMeansUnset: Bool = false)
     
    case text(format: ConfigurationFieldFormat?, suggestions: [String])
     
     
     
    case lines(format: ConfigurationFieldFormat?, suggestions: [String] = [], ordered: Bool = false)

     
    static func written(_ value: OrderedJSON?, separator: String?) -> [String] {
        switch value {
        case .string(let text)?: return separator.map { text.components(separatedBy: $0).map { $0.trimmingCharacters(in: .whitespaces) } } ?? [text]
        case .scalar(let token)?: return token == "null" ? [] : [token]
        case .array(let items)?: return items.compactMap { item in
            switch item {
            case .string(let text): return text
            case .scalar(let token): return token
            default: return nil
            }
        }
        default: return []
        }
    }

     
     
     
     
    static func make(_ field: ConfigurationField, value: OrderedJSON?,
                     names: ([ConfigurationFieldReference]) -> [String]) -> Self? {
         
         
         
         
        let values = field.offeredValues(written: Self.written(value, separator: field.separator)).map(\.value)
        let caseInsensitive = field.caseInsensitive == true
        switch field.kind {
        case .select: return .choose(values, caseInsensitive: caseInsensitive)
        case .multiSelect:
            return .chooseSome(values, ordered: field.ordered == true, caseInsensitive: caseInsensitive, separator: field.separator)
        case .toggle: return .toggle
        case .number: return .number(min: field.min, max: field.max, unit: field.unit, zeroMeansUnset: field.zeroMeansUnset)
        case .reference:
            let pool = field.refers.map(names) ?? []
            var isList = field.ordered == true
            if case .array? = value { isList = true }
            return isList ? .chooseSome(pool, ordered: field.ordered == true, caseInsensitive: false, separator: field.separator)
                          : .choose(pool, caseInsensitive: false)
        case .text: return .text(format: field.format, suggestions: [])
        case .suggest: return .text(format: field.format, suggestions: values)
        case .textList: return .lines(format: field.format, suggestions: values, ordered: field.ordered == true)
        case .object, .map, .objectList, .unrecognised: return nil
        }
    }
}

 
struct ClashMacFieldDraft: Equatable {
    let control: ClashMacFieldControl
     
     
    let path: String
    var text = ""
    var flag = false
    var chosen: [String] = []
    var lines = ""
     
     
    var pendingItem = ""
     
     
     
    var partsProblem: ConfigurationFieldProblem?

     
     
     
     
     
     
     
    init(control: ClashMacFieldControl, value: OrderedJSON?, defaultText: String? = nil, path: String = "") {
        self.control = control
        self.path = path
        let written = value.flatMap(Self.words) ?? []
        let single = value.flatMap(Self.word)
        let shape = ConfigurationField.defaultShape(of: defaultText)
        let plainDefault: String? = { if case .value(let text) = shape { return text }; return nil }()
        switch control {
        case .choose(let options, let caseInsensitive):
            text = single.map { Self.canonical($0, in: options, caseInsensitive: caseInsensitive) }
                ?? plainDefault.map { Self.canonical($0, in: options, caseInsensitive: caseInsensitive) }.flatMap { options.contains($0) ? $0 : nil }
                ?? ""
        case .chooseSome(let options, _, let caseInsensitive, let separator):
            let items = separator.map { separator in written.flatMap { $0.components(separatedBy: separator) } } ?? written
            chosen = items.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                .map { Self.canonical($0, in: options, caseInsensitive: caseInsensitive) }
        case .toggle:
             
             
            switch (single, shape) {
            case (let token?, _): flag = token == "true"
            case (nil, .value(let text)): flag = text == "true"
            case (nil, .note(let text)): flag = text.split(separator: " ").first == "true"
            default: flag = false
            }
        case .number:
            text = single ?? plainDefault.flatMap { ConfigurationFieldDraft.isNumber($0) ? $0 : nil } ?? ""
        case .text(_, let suggestions):
             
             
            text = single ?? plainDefault.flatMap { suggestions.contains($0) ? $0 : nil } ?? ""
        case .lines:
            lines = written.joined(separator: "\n")
        }
        startLines = Self.entries(lines)
    }

     
     
     
    private var startLines: [String] = []

    static func entries(_ lines: String) -> [String] {
        lines.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

     
     
     
    var changedProblems: [String] {
        guard case .lines = control else { return [] }
        let current = Self.entries(lines)
        var before = startLines
        return current.enumerated().compactMap { index, entry in
            if let found = before.firstIndex(of: entry) { before.remove(at: found); return nil }
            return itemProblem(entry, siblings: Self.others(current, but: index)) != nil ? entry : nil
        }
    }

     
    static func others(_ entries: [String], but index: Int) -> [String] {
        var others = entries
        if others.indices.contains(index) { others.remove(at: index) }
        return others
    }

    private static func word(_ value: OrderedJSON) -> String? {
        switch value {
        case .string(let text): return text
        case .scalar(let token): return token == "null" ? nil : token
        default: return nil
        }
    }

    private static func words(_ value: OrderedJSON) -> [String]? {
        if case .array(let items) = value { return items.compactMap(word) }
        return word(value).map { [$0] }
    }

    private static func canonical(_ value: String, in options: [String], caseInsensitive: Bool) -> String {
        guard caseInsensitive else { return value }
        return options.first { $0.lowercased() == value.lowercased() } ?? value
    }

     
     
    var options: [String] {
        switch control {
        case .choose(let options, _):
            return options.contains(text) || text.isEmpty ? options : options + [text]
        case .chooseSome(let options, _, _, _):
            return options + chosen.filter { !options.contains($0) }
        default:
            return []
        }
    }

     
    var unknownChoices: [String] {
        switch control {
        case .choose(let options, _): return text.isEmpty || options.contains(text) ? [] : [text]
        case .chooseSome(let options, _, _, _): return chosen.filter { !options.contains($0) }
        default: return []
        }
    }

    private var typedLines: [String] {
        let entries = Self.entries(lines)
        return Self.withPending(lines.split(whereSeparator: \.isNewline).map(String.init), pendingItem) {
            itemProblem($0, siblings: entries)
        }
    }

     
     
     
     
    static func withPending(_ items: [String], _ pending: String,
                            problem: (String) -> ConfigurationFieldProblem? = { _ in nil }) -> [String] {
        var entries = items.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let typed = pending.trimmingCharacters(in: .whitespaces)
        if !typed.isEmpty, !entries.contains(typed), problem(typed) == nil { entries.append(typed) }
        return entries
    }

     
     
    var hasEntries: Bool { !typedLines.isEmpty }

     
     
     
     
     
    var problem: ConfigurationFieldProblem? {
        if let partsProblem { return partsProblem }
        switch control {
        case .number(let min, let max, _, let zeroMeansUnset):
             
             
            return ConfigurationFieldValidation.problem(number: text, min: min, max: max, whole: true,
                                                        zeroMeansUnset: zeroMeansUnset)
        case .text(let format, let suggestions):
            return ConfigurationFieldValidation.problem(text, format: format, path: path, allowed: suggestions)
        default:
            return nil
        }
    }

     
     
     
     
    func itemProblem(_ item: String, siblings: [String] = []) -> ConfigurationFieldProblem? {
        guard case .lines(let format, let suggestions, _) = control else { return nil }
        return Self.itemProblem(item, format: format, path: path, allowed: suggestions, siblings: siblings)
    }

     
     
     
    static func itemProblem(_ item: String, format: ConfigurationFieldFormat?, path: String,
                            allowed: [String], siblings: [String] = []) -> ConfigurationFieldProblem? {
        if format == .domain || format == .host, item.hasPrefix("geosite:") || item.hasPrefix("rule-set:") { return nil }
        return ConfigurationFieldValidation.problem(item, format: format, path: path, allowed: allowed, siblings: siblings)
    }

     
     
     
    var isValid: Bool {
        switch control {
        case .choose: return !text.isEmpty
        case .number: return ConfigurationFieldDraft.isNumber(text.trimmingCharacters(in: .whitespaces)) && problem == nil
        case .text: return problem == nil
        case .lines: return changedProblems.isEmpty
        default: return true
        }
    }

     
     
    var writesNothing: Bool {
        guard case .text(.ipPort?, _) = control, partsProblem == nil else { return false }
        return text.trimmingCharacters(in: .whitespaces).isEmpty && ConfigurationFormatPresets.addressChoices(path: path) != nil
    }

    var value: OrderedJSON {
        switch control {
        case .choose: return .string(text)
        case .chooseSome(_, _, _, let separator?): return .string(chosen.joined(separator: separator))
        case .chooseSome: return .array(chosen.map(OrderedJSON.string))
        case .toggle: return .scalar(flag ? "true" : "false")
        case .number: return .scalar(text.trimmingCharacters(in: .whitespaces))
         
        case .text(let format, _): return .string(Self.isShaped(format) ? text.trimmingCharacters(in: .whitespaces) : text)
        case .lines: return .array(typedLines.map(OrderedJSON.string))
        }
    }

     
     
     
    static func isShaped(_ format: ConfigurationFieldFormat?) -> Bool {
        switch format {
        case nil, .text?, .password?, .path?, .filter?, .unrecognised?: return false
        default: return true
        }
    }

     
    var items: [String] {
        get { lines.isEmpty ? [] : lines.components(separatedBy: "\n") }
        set { lines = newValue.joined(separator: "\n") }
    }

     
    mutating func appendLine(_ entry: String) {
        let trimmed = lines.trimmingCharacters(in: .newlines)
        lines = trimmed.isEmpty ? entry : trimmed + "\n" + entry
    }

     
    mutating func toggle(_ option: String) {
        if let index = chosen.firstIndex(of: option) { chosen.remove(at: index) } else { chosen.append(option) }
    }

     
    static func range(min: Double?, max: Double?) -> ClashDisplayText? {
        func words(_ number: Double) -> String {
            number == number.rounded() ? String(Int(number)) : String(number)
        }
        switch (min, max) {
        case (let low?, let high?): return .format("Between %@ and %@", [words(low), words(high)])
        case (let low?, nil): return .format("At least %@", [words(low)])
        case (nil, let high?): return .format("At most %@", [words(high)])
        case (nil, nil): return nil
        }
    }
}

 
 
 
 
struct ClashMacFieldEditor: View {
    @Binding var draft: ClashMacFieldDraft
     
     
    var label: String? = nil
     
    var field: ConfigurationField? = nil
    @Environment(\.configurationFieldCopy) private var copy
    @Environment(\.locale) private var locale

    private func name(_ option: String) -> String { copy.valueLabel(option, for: field, locale: locale) ?? option }

    private var title: Text { label.map { Text(verbatim: $0) } ?? Text(clash: .copy("Value")) }

    var body: some View {
        Group {
            switch draft.control {
            case .choose:
                Picker(selection: $draft.text) {
                    ForEach(draft.options, id: \.self) { Text(verbatim: name($0)).tag($0) }
                } label: { title }
                .pickerStyle(.menu)
                .accessibilityIdentifier("configuration-center.section.field.choice")
            case .chooseSome:
                ForEach(draft.options, id: \.self) { option in
                    Toggle(isOn: Binding(get: { draft.chosen.contains(option) }, set: { _ in draft.toggle(option) })) {
                        Text(verbatim: name(option))
                    }
                    .accessibilityIdentifier("configuration-center.section.field.option")
                }
            case .toggle:
                Toggle(isOn: $draft.flag) { label.map { Text(verbatim: $0) } ?? Text(clash: .copy("On")) }
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("configuration-center.section.field.toggle")
            case .number(let min, let max, let unit, _):
                if let unit, ConfigurationDurationEntry(stored: draft.text, fieldUnit: unit) != nil {
                     
                    ClashMacDurationEditor(draft: $draft, min: min, max: max, fieldUnit: unit, title: title)
                } else {
                    TextField(text: $draft.text, prompt: ClashMacValueWords.placeholder(field, locale: locale, copy: copy).map { Text(verbatim: $0) }) {
                        title
                        if let range = ClashMacFieldDraft.range(min: min, max: max) { Text(clash: range) }
                        else if let unit { Text(verbatim: unit) }
                    }
                    .accessibilityIdentifier("configuration-center.section.field.number")
                }
            case .text(let format, let suggestions):
                switch format {
                case .ipPort? where !draft.path.hasSuffix("dns-hijack"):
                     
                     
                    ClashMacHostPortEditor(draft: $draft, title: title)
                case .password?:
                    ClashMacSecretField(draft: $draft, title: title, prompt: prompt(format), secure: true)
                case .uuid?:
                    ClashMacSecretField(draft: $draft, title: title, prompt: prompt(format), secure: false)
                default:
                    TextField(text: $draft.text, prompt: prompt(format).map { Text(verbatim: $0) }) { title }
                        .disableAutocorrection(true)
                        .accessibilityIdentifier("configuration-center.section.field.text")
                }
                if !suggestions.isEmpty {
                     
                     
                    Picker(selection: Binding(get: { suggestion(matching: draft.text, in: suggestions) ?? "" },
                                              set: { if !$0.isEmpty { draft.text = $0 } })) {
                        Text(clash: .copy("Other")).tag("")
                        ForEach(suggestions, id: \.self) { Text(verbatim: name($0)).tag($0) }
                    } label: { Text(clash: .copy("Common Values")) }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("configuration-center.section.field.suggestions")
                }
            case .lines(let format, let suggestions, let ordered):
                 
                ClashMacListValueEditor(items: $draft.items, format: format, ordered: ordered, suggestions: suggestions,
                                       field: field, path: draft.path, pending: $draft.pendingItem)
                    .accessibilityIdentifier("configuration-center.section.field.lines")
            }
            ForEach(draft.unknownChoices, id: \.self) { value in
                Text(clash: .format("“%@” is not a value the core takes.", [value])).foregroundStyle(.orange)
            }
             
            if case .lines = draft.control {} else if let problem = draft.problem {
                ClashMacProblemLine(problem: problem)
            }
        }
    }

     
     
    private func prompt(_ format: ConfigurationFieldFormat?) -> String? {
        copy.entry(for: field, locale: locale)?.example ?? ConfigurationFieldExamples.example(for: format)
    }

     
     
    private func suggestion(matching typed: String, in suggestions: [String]) -> String? {
        ConfigurationChoiceMatch.choice(for: typed, in: suggestions, caseInsensitive: field?.caseInsensitive == true)
    }
}
