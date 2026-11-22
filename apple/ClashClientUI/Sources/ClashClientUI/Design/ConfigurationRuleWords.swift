import Foundation
import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
public struct ConfigurationRuleWords: Equatable, Sendable {
     
     
    public let match: String
     
     
    public let kind: String
     
     
     
    public let target: String?

    public init(match: String, kind: String, target: String?) {
        self.match = match
        self.kind = kind
        self.target = target
    }

     
     
     
     
     
    public static func of(_ raw: String, locale: Locale, copy: ConfigurationFieldCopy = .shared,
                          ruleSetNames: [String: String] = [:], hasTarget: Bool = true) -> ConfigurationRuleWords {
        Reader(copy: copy, language: .init(locale: locale), ruleSetNames: ruleSetNames)
            .words(raw.trimmingCharacters(in: .whitespacesAndNewlines), hasTarget: hasTarget)
    }

     
     
    public static func kindName(_ kind: String, locale: Locale, copy: ConfigurationFieldCopy = .shared) -> String {
        copy.ruleKindName(kind, language: .init(locale: locale)) ?? kind
    }

     
    public static func targetName(_ target: String, locale: Locale, copy: ConfigurationFieldCopy = .shared) -> String {
        copy.ruleTargetName(target, language: .init(locale: locale)) ?? target
    }

     
     
     
    public static func payloadName(_ payload: String, kind: String, locale: Locale, copy: ConfigurationFieldCopy = .shared,
                                   ruleSetNames: [String: String] = [:]) -> String {
        Reader(copy: copy, language: .init(locale: locale), ruleSetNames: ruleSetNames).named(payload, kind: kind.uppercased())
    }

     
     
    static let payloadKeepsCommas: Set<String> = ["NOT", "OR", "AND", "SUB-RULE", "DOMAIN-REGEX",
                                                   "PROCESS-NAME-REGEX", "PROCESS-PATH-REGEX"]

     
    static let logic: Set<String> = ["AND", "OR", "NOT", "SUB-RULE"]

     
     
    public static let builtInTargets = ["DIRECT", "REJECT", "REJECT-DROP", "COMPATIBLE", "PASS", "PASS-RULE", "GLOBAL"]

     
     
     
    static func conditions(of payload: String) -> [String]? {
        let characters = Array(payload)
        guard characters.first == "(", characters.last == ")" else { return nil }
        var open: [Int] = []
        var ranges: [(start: Int, end: Int)] = []
        for (index, character) in characters.enumerated() {
            if character == "(" {
                open.append(index)
            } else if character == ")" {
                guard let start = open.popLast() else { return nil }
                ranges.append((start, index))
            }
        }
        guard open.isEmpty else { return nil }
        ranges.sort { $0.start < $1.start }
        var outermost: [(start: Int, end: Int)] = []
        for range in ranges where !(range.start == 0 && range.end == characters.count - 1) {
            if outermost.contains(where: { $0.start < range.start && $0.end > range.end }) { continue }
            outermost.append(range)
        }
        return outermost.map { String(characters[($0.start + 1)..<$0.end]) }
    }

    private struct Reader {
        let copy: ConfigurationFieldCopy
        let language: ConfigurationFieldCopy.Language
        let ruleSetNames: [String: String]

        func words(_ line: String, hasTarget: Bool) -> ConfigurationRuleWords {
             
             
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " ")) }
            let written = fields.first ?? ""
            let kind = written.uppercased()
            guard fields.count > 1 else { return ConfigurationRuleWords(match: line, kind: "", target: nil) }
            if kind == "MATCH" {
                return ConfigurationRuleWords(match: copy.rulePhrase("match", language: language) ?? line,
                                              kind: kindName(kind, written: written),
                                              target: hasTarget ? targetName(fields[1]) : nil)
            }
            var rest = Array(fields.dropFirst())
            var target: String?
            var params: [String] = []
            let payload: String
            if ConfigurationRuleWords.payloadKeepsCommas.contains(kind) {
                 
                 
                if hasTarget, rest.count > 1 { target = rest.removeLast() }
                payload = rest.joined(separator: ",")
            } else {
                payload = rest[0]
                if rest.count > 1 {
                    if hasTarget {
                        target = rest[1]
                        params = Array(rest.dropFirst(2))
                    } else {
                        params = Array(rest.dropFirst())
                    }
                }
            }
            if ConfigurationRuleWords.logic.contains(kind) {
                return logicWords(kind, written: written, payload: payload, target: target)
            }
             
             
             
             
             
            let action = ClashStructuredRule.Action(rawValue: kind)
            var said: [String] = []
            for param in params where !said.contains(param) {
                let read = (param == ClashStructuredRule.srcOption && action?.supportsSrc == true)
                    || (param == ClashStructuredRule.noResolveOption && action?.supportsNoResolve == true)
                if read { said.append(param) }
            }
            let options = said.map { copy.ruleOptionName($0, language: language) ?? $0 }
            return ConfigurationRuleWords(match: payload.isEmpty ? line : named(payload, kind: kind),
                                          kind: ([kindName(kind, written: written)] + options).joined(separator: " · "),
                                          target: target.map(targetName))
        }

         
         
        private func logicWords(_ kind: String, written: String, payload: String, target: String?) -> ConfigurationRuleWords {
            let parts = (kind == "SUB-RULE" ? ConfigurationRuleWords.conditions(of: "(\(payload))")
                                            : ConfigurationRuleWords.conditions(of: payload)) ?? []
            let conditions = parts.map { words($0, hasTarget: false) }
            func summary(_ part: String, _ said: ConfigurationRuleWords) -> String {
                let head = part.split(separator: ",", maxSplits: 1).first.map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
                return ConfigurationRuleWords.logic.contains(head ?? "") ? said.match : "\(said.kind) \(said.match)"
            }
            switch kind {
            case "SUB-RULE":
                let name = target ?? ""
                return ConfigurationRuleWords(match: fill("sub-rule", name) ?? name,
                                              kind: zip(parts, conditions).map(summary).joined(separator: " · "),
                                              target: nil)
            case "NOT" where conditions.count == 1:
                return ConfigurationRuleWords(match: fill("not", conditions[0].match) ?? conditions[0].match,
                                              kind: conditions[0].kind, target: target.map(targetName))
             
             
             
            case "AND" where !conditions.isEmpty, "OR" where !conditions.isEmpty:
                return ConfigurationRuleWords(match: fill(kind.lowercased(), String(conditions.count)) ?? kindName(kind, written: written),
                                              kind: conditions.map(\.match).joined(separator: " · "),
                                              target: target.map(targetName))
            default:
                 
                 
                return ConfigurationRuleWords(match: kindName(kind, written: written),
                                              kind: conditions.map(\.match).joined(separator: " · "),
                                              target: target.map(targetName))
            }
        }

        private func fill(_ phrase: String, _ argument: String) -> String? {
            copy.rulePhrase(phrase, language: language)?.replacingOccurrences(of: "%@", with: argument)
        }

        private func kindName(_ kind: String, written: String) -> String {
            copy.ruleKindName(kind, language: language) ?? written
        }

        private func targetName(_ target: String) -> String {
            copy.ruleTargetName(target, language: language) ?? target
        }

         
         
         
        func named(_ payload: String, kind: String) -> String {
            switch kind {
            case "GEOIP", "SRC-GEOIP":
                return copy.ruleCodeName(payload, database: "geoip", language: language)
                    ?? ConfigurationRuleWords.regionName(payload, language: language) ?? payload
            case "GEOSITE":
                return copy.ruleCodeName(payload, database: "geosite", language: language) ?? payload
            case "NETWORK":
                return payload.uppercased()
            case "RULE-SET":
                return ruleSetNames[payload] ?? payload
            default:
                return payload
            }
        }
    }

    private static let regionLocales: [ConfigurationFieldCopy.Language: Locale] = [
        .en: Locale(identifier: "en"), .zhHans: Locale(identifier: "zh-Hans"), .zhHant: Locale(identifier: "zh-Hant-TW"),
    ]

     
     
    static func regionName(_ code: String, language: ConfigurationFieldCopy.Language) -> String? {
        guard code.count == 2, code.allSatisfy({ $0.isASCII && $0.isLetter }),
              let name = regionLocales[language]?.localizedString(forRegionCode: code.uppercased()),
              name.uppercased() != code.uppercased() else { return nil }
        return name
    }
}

public extension ConfigurationFieldCopy {
    private static func pick(_ words: [String: String]?, _ language: Language) -> String? {
        guard let words else { return nil }
        let chosen = words[language.rawValue].flatMap { $0.isEmpty ? nil : $0 } ?? words[Language.en.rawValue]
        return chosen.flatMap { $0.isEmpty ? nil : $0 }
    }

     
    func ruleKindName(_ kind: String, language: Language) -> String? {
        Self.pick(ruleWords.kinds[kind.uppercased()], language)
    }

     
     
    public func ruleOptionName(_ option: String, language: Language) -> String? {
        Self.pick(ruleWords.options[option], language)
    }

     
     
    func ruleTargetName(_ target: String, language: Language) -> String? {
        Self.pick(ruleWords.targets[target], language)
    }

     
    func ruleCodeName(_ code: String, database: String, language: Language) -> String? {
        Self.pick(ruleWords.codes[database]?[code.lowercased()], language)
    }

     
     
    func rulePhrase(_ key: String, language: Language) -> String? {
        Self.pick(ruleWords.phrases[key], language)
    }

     
    static let rulePhrases: [(key: String, fills: Bool)] = [("match", false), ("and", true), ("or", true), ("not", true),
                                                            ("sub-rule", true), ("opens", false)]

     
     
     
     
    func missingRuleWords(kinds: [String]) -> [String] {
        var missing: [String] = []
        for kind in kinds where !Record.isSaid(ruleWords.kinds[kind.uppercased()]) { missing.append("kinds/\(kind)") }
        for option in ["no-resolve", "src"] where !Record.isSaid(ruleWords.options[option]) { missing.append("options/\(option)") }
        for target in ConfigurationRuleWords.builtInTargets where !Record.isSaid(ruleWords.targets[target]) {
            missing.append("targets/\(target)")
        }
        for phrase in Self.rulePhrases {
            let words = ruleWords.phrases[phrase.key]
            let placed = Language.allCases.allSatisfy { (words?[$0.rawValue] ?? "").contains("%@") == phrase.fills }
            if !Record.isSaid(words) || !placed { missing.append("phrases/\(phrase.key)") }
        }
        return missing
    }
}

 
 
 
 
 
 
public struct ConfigurationRuleRow: View {
    private let raw: String
    private let ruleSetNames: [String: String]
    private let hasTarget: Bool
    private let showsChevron: Bool
    @Environment(\.locale) private var locale
    @Environment(\.configurationFieldCopy) private var copy

     
     
     
     
     
     
     
    public init(_ raw: String, ruleSetNames: [String: String] = [:], hasTarget: Bool = true, showsChevron: Bool = true) {
        self.raw = raw
        self.ruleSetNames = ruleSetNames
        self.hasTarget = hasTarget
        self.showsChevron = showsChevron
    }

    public var body: some View {
        let words = ConfigurationRuleWords.of(raw, locale: locale, copy: copy, ruleSetNames: ruleSetNames, hasTarget: hasTarget)
        HStack(spacing: ClashTheme.Spacing.compact) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: words.match)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !words.kind.isEmpty {
                    Text(verbatim: words.kind)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let target = words.target, !target.isEmpty {
                Text(verbatim: target)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if showsChevron {
                ConfigurationRuleDisclosure()
            }
        }
        .contentShape(Rectangle())
    }
}

 
 
 
 
public struct ConfigurationRuleDisclosure: View {
    @Environment(\.locale) private var locale
    @Environment(\.configurationFieldCopy) private var copy

    public init() {}

    public var body: some View {
        Image(systemName: ClashSymbol.chevronForward.rawValue)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHint(Text(verbatim: copy.rulePhrase("opens", language: .init(locale: locale)) ?? ""))
    }
}
