import Foundation
import ClashClientKit
import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
public struct ConfigurationFieldCopy: Sendable {
     
    public enum Language: String, CaseIterable, Sendable {
        case en
        case zhHans = "zh-Hans"
        case zhHant = "zh-Hant"

         
         
         
        public init(locale: Locale) {
            let parts = locale.identifier.replacingOccurrences(of: "_", with: "-").split(separator: "-").map(String.init)
            guard parts.first?.lowercased() == "zh" else { self = .en; return }
            let rest = Set(parts.dropFirst().map { $0.lowercased() })
            if rest.contains("hant") || (!rest.contains("hans") && !rest.isDisjoint(with: ["tw", "hk", "mo"])) {
                self = .zhHant
            } else {
                self = .zhHans
            }
        }

         
         
        public static var app: Language {
            Language(locale: Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en"))
        }

         
         
         
         
         
         
        public static func shown(in locale: Locale) -> Language {
            shown(table: ClashCopy.tableName(for: locale), launch: Bundle.main.preferredLocalizations.first)
        }

         
         
        static func shown(in locale: Locale, tables: (String) -> Bool, launch: String?) -> Language {
            shown(table: ClashCopy.tableName(for: locale, has: tables), launch: launch)
        }

        private static func shown(table: String?, launch: String?) -> Language {
            Language(locale: Locale(identifier: table ?? launch ?? "en"))
        }
    }

     
     
     
    public struct Record: Equatable, Sendable, Decodable {
        public let title: [String: String]
        public let summary: [String: String]?
        public let unset: [String: String]?
        public let example: String?
         
         
        public let presets: [PresetRecord]?
         
         
         
        public let platform: [String: String]?
         
         
         
         
        public let unsetOverrides: Bool?

        public struct PresetRecord: Equatable, Sendable, Decodable {
            public let value: String
            public let label: [String: String]
        }

        private static func said(_ words: [String: String]?) -> Bool {
            Language.allCases.allSatisfy { !(words?[$0.rawValue] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

         
        public var isComplete: Bool { Self.said(title) && Self.said(summary) }

         
         
        public var isTitled: Bool { Self.said(title) }

         
         
         
        public var saysUnset: Bool { Self.said(unset) }

         
         
        public var saysPlatform: Bool { Self.said(platform) }

        static func isSaid(_ words: [String: String]?) -> Bool { said(words) }
    }

     
     
     
    private struct ValuesFile: Decodable {
        let values: [String: [String: String]]
    }

     
     
     
    public struct SectionRecord: Equatable, Sendable, Decodable {
        public let id: String
        public let title: [String: String]?
        public let footer: [String: String]?
        public let keys: [String]
    }

    private struct LayoutsFile: Decodable {
        let layouts: [String: [SectionRecord]]
    }

     
     
     
     
    public struct RuleWords: Equatable, Sendable, Decodable {
        public var kinds: [String: [String: String]] = [:]
        public var options: [String: [String: String]] = [:]
        public var targets: [String: [String: String]] = [:]
         
        public var codes: [String: [String: [String: String]]] = [:]
        public var phrases: [String: [String: String]] = [:]

        init() {}

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            kinds = try container.decodeIfPresent([String: [String: String]].self, forKey: .kinds) ?? [:]
            options = try container.decodeIfPresent([String: [String: String]].self, forKey: .options) ?? [:]
            targets = try container.decodeIfPresent([String: [String: String]].self, forKey: .targets) ?? [:]
            codes = try container.decodeIfPresent([String: [String: [String: String]]].self, forKey: .codes) ?? [:]
            phrases = try container.decodeIfPresent([String: [String: String]].self, forKey: .phrases) ?? [:]
        }

        private enum CodingKeys: String, CodingKey { case kinds, options, targets, codes, phrases }

         
         
        mutating func add(_ other: RuleWords, twice: inout [String]) {
            func merge(_ mine: inout [String: [String: String]], _ theirs: [String: [String: String]], _ section: String) {
                for key in theirs.keys.sorted() {
                    if mine[key] == nil { mine[key] = theirs[key] } else { twice.append("rules/\(section)/\(key)") }
                }
            }
            merge(&kinds, other.kinds, "kinds")
            merge(&options, other.options, "options")
            merge(&targets, other.targets, "targets")
            merge(&phrases, other.phrases, "phrases")
            for database in other.codes.keys.sorted() {
                var mine = codes[database] ?? [:]
                let theirs = (other.codes[database] ?? [:]).reduce(into: [String: [String: String]]()) { $0[$1.key.lowercased()] = $1.value }
                merge(&mine, theirs, "codes/\(database)")
                codes[database] = mine
            }
        }
    }

     
    public struct LayoutSection: Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String?
        public let footer: String?
        public let keys: [String]
    }

     
    public struct ArrangedSection: Equatable, Sendable, Identifiable {
        public let id: String
         
        public let title: ClashDisplayText?
         
        public let footer: String?
        public let keys: [String]
    }

     
    public struct Entry: Equatable, Sendable {
        public let title: String
        public let summary: String
         
         
        public let unset: String?
         
        public let example: String?
         
        public let presets: [Preset]
         
        public var unsetOverrides = false
    }

     
    public struct Preset: Equatable, Hashable, Sendable {
        public let value: String
        public let label: String

        public init(value: String, label: String) {
            self.value = value
            self.label = label
        }
    }

     
    public let records: [String: Record]
     
    public let layouts: [String: [SectionRecord]]
     
     
    public let duplicates: [String]
     
     
    public let layoutDuplicates: [String]
     
     
    public let keysInTwoSections: [String: [String]]
     
    public let unreadable: [String]
     
     
    public let unavailableValues: [String: [String: String]]
     
    public let ruleWords: RuleWords

     
     
     
     
     
    public init(tables: [(name: String, data: Data)]) {
        var records: [String: Record] = [:]
        var layouts: [String: [SectionRecord]] = [:]
        var values: [String: [String: String]] = [:]
        var rules = RuleWords()
        var duplicates: [String] = []
        var layoutDuplicates: [String] = []
        var unreadable: [String] = []
        for table in tables {
            if table.name.hasPrefix("rules-") {
                guard let read = try? JSONDecoder().decode(RuleWords.self, from: table.data) else {
                    unreadable.append(table.name)
                    continue
                }
                rules.add(read, twice: &duplicates)
                continue
            }
            if table.name.hasPrefix("values-") {
                guard let read = try? JSONDecoder().decode(ValuesFile.self, from: table.data) else {
                    unreadable.append(table.name)
                    continue
                }
                for key in read.values.keys.sorted() {
                    guard let words = read.values[key] else { continue }
                    let value = key.lowercased()
                    if values[value] == nil { values[value] = words } else { duplicates.append("values/" + value) }
                }
                continue
            }
            if table.name.hasPrefix("layouts-") {
                guard let read = try? JSONDecoder().decode(LayoutsFile.self, from: table.data) else {
                    unreadable.append(table.name)
                    continue
                }
                for key in read.layouts.keys.sorted() {
                    guard let sections = read.layouts[key] else { continue }
                    if layouts[key] == nil { layouts[key] = sections } else { layoutDuplicates.append(key) }
                }
                continue
            }
            guard let read = try? JSONDecoder().decode([String: Record].self, from: table.data) else {
                unreadable.append(table.name)
                continue
            }
            for key in read.keys.sorted() {
                guard let record = read[key] else { continue }
                if records[key] == nil { records[key] = record } else { duplicates.append(key) }
            }
        }
        var twice: [String: [String]] = [:]
        for (path, sections) in layouts {
            var seen: Set<String> = []
            var repeated: [String] = []
            for key in sections.flatMap(\.keys) where key != "*" {
                if !seen.insert(key).inserted, !repeated.contains(key) { repeated.append(key) }
            }
            if !repeated.isEmpty { twice[path] = repeated }
        }
        self.records = records
        self.layouts = layouts
        self.duplicates = duplicates.sorted()
        self.layoutDuplicates = layoutDuplicates.sorted()
        self.keysInTwoSections = twice
        self.unreadable = unreadable
        self.unavailableValues = values
        self.ruleWords = rules
    }

     
    public static let empty = ConfigurationFieldCopy(tables: [])

     
    public static let shared: ConfigurationFieldCopy = bundled()

     
    static func bundled() -> ConfigurationFieldCopy {
        let urls = (Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "FieldCopy") ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return ConfigurationFieldCopy(tables: urls.compactMap { url in
            (try? Data(contentsOf: url)).map { (url.lastPathComponent, $0) }
        })
    }

     
     
     
    public static func sharedPath(_ path: String) -> String {
        var result = ""
        var inBracket = false
        var bracket = ""
        for character in path {
            if inBracket {
                if character == "]" {
                    result += bracket.isEmpty ? "[]" : "[*]"
                    inBracket = false
                    bracket = ""
                } else {
                    bracket.append(character)
                }
            } else if character == "[" {
                inBracket = true
            } else {
                result.append(character)
            }
        }
        if inBracket { result += "[" + bracket }
        return result
    }

     
     
    public func record(forPath path: String) -> Record? {
        records[path] ?? records[Self.sharedPath(path)]
    }

     
     
    public func entry(forPath path: String, language: Language) -> Entry? {
        guard let record = record(forPath: path) else { return nil }
        func pick(_ words: [String: String]?) -> String? {
            guard let words else { return nil }
            let chosen = words[language.rawValue].flatMap { $0.isEmpty ? nil : $0 } ?? words[Language.en.rawValue]
            return chosen.flatMap { $0.isEmpty ? nil : $0 }
        }
        guard let title = pick(record.title) else { return nil }
        return Entry(title: title, summary: pick(record.summary) ?? "", unset: pick(record.unset),
                     example: record.example.flatMap { $0.isEmpty ? nil : $0 },
                     presets: (record.presets ?? []).compactMap { preset in
                         pick(preset.label).map { Preset(value: preset.value, label: $0) }
                     },
                     unsetOverrides: record.unsetOverrides == true)
    }

     
     
    public func entry(for field: ConfigurationField?, locale: Locale) -> Entry? {
        field.flatMap { entry(forPath: $0.path, language: Language(locale: locale)) }
    }

     
    public func title(for field: ConfigurationField?, key: String, locale: Locale) -> String {
        entry(for: field, locale: locale)?.title ?? key
    }

     
     
     
    public func turnOnLine(_ control: ConfigurationGoverningSwitch, locale: Locale) -> ClashDisplayText {
        let key = ConfigurationFieldCatalog.catalogComponents(control.field.path).last ?? control.field.path
        return .format("Turn on “%@” for these settings to take effect.", [title(for: control.field, key: key, locale: locale)])
    }

     
     
     
     
     
     
    public func turnOnLine(_ summary: ConfigurationOffSwitchSummary, locale: Locale) -> ClashDisplayText {
        guard summary.working > 0, summary.waiting.count == 1, let row = summary.waiting.first else {
            return turnOnLine(summary.control, locale: locale)
        }
        func name(_ field: ConfigurationField) -> String {
            title(for: field, key: ConfigurationFieldCatalog.catalogComponents(field.path).last ?? field.path, locale: locale)
        }
        return .format("Turn on “%@” for “%@” to take effect.", [name(summary.control.field), name(row)])
    }

     
     
     
     
     
    public func valueLabel(_ value: String, for field: ConfigurationField?, locale: Locale) -> String? {
        guard let field, let presets = entry(for: field, locale: locale)?.presets else { return nil }
        let fold: (String) -> String = { field.caseInsensitive == true ? $0.lowercased() : $0 }
        switch field.kind {
        case .select, .multiSelect: break
         
         
         
        case .suggest where (field.values ?? []).contains(where: { fold($0) == fold(value) }): break
        default: return nil
        }
        return presets.first { fold($0.value) == fold(value) }?.label
    }

     
     
     
     
     
     
    public func presetName(_ value: String, for field: ConfigurationField?, locale: Locale) -> String? {
        guard let field, field.kind == .text || field.kind == .suggest, field.format != .ipPort,
              let presets = entry(for: field, locale: locale)?.presets, !presets.isEmpty,
              let match = ConfigurationChoiceMatch.choice(for: value, in: presets.map(\.value),
                                                          caseInsensitive: field.caseInsensitive == true)
        else { return nil }
        return presets.first { $0.value == match }?.label
    }

     
     
     
    public func missing(in catalog: ConfigurationFieldCatalog) -> [String] {
        var missing: Set<String> = []
        for field in catalog.fields {
            let record = record(forPath: field.path)
            let said = field.kind == .object ? record?.isTitled == true : record?.isComplete == true
            if !said { missing.insert(Self.sharedPath(field.path)) }
        }
        return missing.sorted()
    }

     
     
     
     
     
    public func conflictingUnsets(in catalog: ConfigurationFieldCatalog) -> [String] {
        var conflicts: Set<String> = []
        for field in catalog.fields {
            guard case .value(let text) = field.defaultShape, let record = record(forPath: field.path),
                  record.unsetOverrides != true, let unset = record.unset,
                  let presets = record.presets, !presets.isEmpty,
                  let match = ConfigurationChoiceMatch.choice(for: text, in: presets.map(\.value),
                                                              caseInsensitive: field.caseInsensitive == true),
                  let preset = presets.first(where: { $0.value == match })
            else { continue }
            if Language.allCases.contains(where: { unset[$0.rawValue] != preset.label[$0.rawValue] }) {
                conflicts.insert(Self.sharedPath(field.path))
            }
        }
        return conflicts.sorted()
    }

     
     
     
     
     
    public func missingUnset(in catalog: ConfigurationFieldCatalog) -> [String] {
        var missing: Set<String> = []
        for field in catalog.fields where field.defaultNeedsWords {
            if record(forPath: field.path)?.saysUnset != true { missing.insert(Self.sharedPath(field.path)) }
        }
        return missing.sorted()
    }

     

     
     
    private static func pick(_ words: [String: String]?, _ language: Language) -> String? {
        guard let words else { return nil }
        let chosen = words[language.rawValue].flatMap { $0.isEmpty ? nil : $0 } ?? words[Language.en.rawValue]
        return chosen.flatMap { $0.isEmpty ? nil : $0 }
    }

     
     
     
    public func platformWords(forPath path: String, language: Language) -> String? {
        if let own = records[path]?.platform, let words = Self.pick(own, language) { return words }
        return Self.pick(records[Self.sharedPath(path)]?.platform, language)
    }

     
    public func platformWords(for field: ConfigurationField?, locale: Locale) -> String? {
        field.flatMap { platformWords(forPath: $0.path, language: Language(locale: locale)) }
    }

     
     
    public func unavailableWords(_ value: String, language: Language) -> String? {
        Self.pick(unavailableValues[value.lowercased()], language)
    }

     
    public func unavailableWords(_ value: String, locale: Locale) -> String? {
        unavailableWords(value, language: Language(locale: locale))
    }

     
     
     
    public func missingPlatform(in catalog: ConfigurationFieldCatalog) -> [String] {
        var missing: Set<String> = []
        for field in catalog.fields where field.platformDecision != nil {
            let own = records[field.path]?.platform
            let shared = records[Self.sharedPath(field.path)]?.platform
            if !Record.isSaid(own) && !Record.isSaid(shared) { missing.insert(Self.sharedPath(field.path)) }
        }
        return missing.sorted()
    }

     
     
    public func missingUnavailable(in catalog: ConfigurationFieldCatalog) -> [String] {
        var missing: Set<String> = []
        for field in catalog.fields {
            for unavailable in field.unavailableValues where !Record.isSaid(unavailableValues[unavailable.value.lowercased()]) {
                missing.insert(unavailable.value.lowercased())
            }
        }
        return missing.sorted()
    }

     

     
     
    public func layout(forPath path: String, language: Language) -> [LayoutSection]? {
        guard let sections = layouts[path] ?? layouts[Self.sharedPath(path)] else { return nil }
        func pick(_ words: [String: String]?) -> String? {
            guard let words else { return nil }
            let chosen = words[language.rawValue].flatMap { $0.isEmpty ? nil : $0 } ?? words[Language.en.rawValue]
            return chosen.flatMap { $0.isEmpty ? nil : $0 }
        }
        return sections.map { LayoutSection(id: $0.id, title: pick($0.title), footer: pick($0.footer), keys: $0.keys) }
    }

    public func layout(forPath path: String, locale: Locale) -> [LayoutSection]? {
        layout(forPath: path, language: Language(locale: locale))
    }

     
     
     
     
     
     
    public static func arrange(_ keys: [String], in layout: [LayoutSection]) -> [ArrangedSection] {
        guard !layout.isEmpty else {
            return keys.isEmpty ? [] : [ArrangedSection(id: "all", title: nil, footer: nil, keys: keys)]
        }
        let present = Set(keys)
        var placed: Set<String> = []
        var listed: [[String]] = []
        for section in layout {
            var own: [String] = []
            for key in section.keys where key != "*" && present.contains(key) && placed.insert(key).inserted {
                own.append(key)
            }
            listed.append(own)
        }
        let rest = keys.filter { !placed.contains($0) }
        let star = layout.firstIndex { $0.keys.contains("*") }
        var arranged: [ArrangedSection] = []
        for (index, section) in layout.enumerated() {
            let sectionKeys = listed[index] + (index == star ? rest : [])
            guard !sectionKeys.isEmpty else { continue }
            arranged.append(ArrangedSection(id: section.id, title: section.title.map(ClashDisplayText.verbatim),
                                            footer: section.footer, keys: sectionKeys))
        }
        if star == nil, !rest.isEmpty {
            arranged.append(ArrangedSection(id: "more.automatic", title: .copy("More"), footer: nil, keys: rest))
        }
        return arranged
    }
}

private struct ConfigurationFieldCopyKey: EnvironmentKey {
    static let defaultValue = ConfigurationFieldCopy.shared
}

public extension EnvironmentValues {
     
     
    var configurationFieldCopy: ConfigurationFieldCopy {
        get { self[ConfigurationFieldCopyKey.self] }
        set { self[ConfigurationFieldCopyKey.self] = newValue }
    }
}
