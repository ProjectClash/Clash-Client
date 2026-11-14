import Foundation
import ClashClientKit

 
 
 
 
 
 
 
public enum ConfigurationValueWords {
     
     
     
     
     
    public static func summary(_ value: OrderedJSON?, field: ConfigurationField?, locale: Locale,
                               copy: ConfigurationFieldCopy? = nil, marksDefault: Bool = true) -> ClashDisplayText {
        if let value {
             
             
             
            let written = scalarText(of: value)
            let isDefault: Bool = {
                guard marksDefault, let written, let field, case .value(let text) = field.defaultShape else { return false }
                return ConfigurationChoiceMatch.choice(for: written, in: [text], caseInsensitive: field.caseInsensitive == true) != nil
            }()
             
            if let copy, let label = written.flatMap({ copy.valueLabel($0, for: field, locale: locale) }) {
                return isDefault ? .format("Default: %@", [label]) : .verbatim(label)
            }
             
             
            if let copy, let name = written.flatMap({ copy.presetName($0, for: field, locale: locale) }) {
                return isDefault ? .format("Default: %@", [name]) : .verbatim(name)
            }
            return rowWords(value, field: field, locale: locale, copy: copy)
        }
        if let copy, let field {
            let entry = copy.entry(for: field, locale: locale)
             
             
            if let unset = entry?.unset, entry?.unsetOverrides == true {
                return .verbatim(copy.valueLabel(unset, for: field, locale: locale) ?? unset)
            }
             
             
            if case .value(let text) = field.defaultShape,
               let name = copy.valueLabel(text, for: field, locale: locale) ?? copy.presetName(text, for: field, locale: locale) {
                return .format("Default: %@", [name])
            }
            if let unset = entry?.unset {
                 
                 
                return .verbatim(copy.valueLabel(unset, for: field, locale: locale) ?? unset)
            }
        }
        if let field, let defaultWords = defaultWords(for: field, locale: locale) { return defaultWords }
        return .copy("Not set")
    }

     
     
     
     
     
    static func rowWords(_ value: OrderedJSON, field: ConfigurationField?, locale: Locale,
                         copy: ConfigurationFieldCopy?) -> ClashDisplayText {
        let said = words(value, field: field, locale: locale)
        guard case .string(let text) = value, case .verbatim(let shown) = said, shown == text else { return said }
        let offersPresets = copy?.entry(for: field, locale: locale)?.presets.isEmpty == false
        return rowText(text, field: field, custom: offersPresets)
    }

     
     
    static func rowText(_ text: String, field: ConfigurationField?, custom: Bool) -> ClashDisplayText {
        if field?.format == .url, let host = linkHost(text) {
            let short = cutInMiddle(host, width: rowValueWidth - 6)
            return custom ? .format("Custom · %@", [short]) : .verbatim(short)
        }
        return .verbatim(cutInMiddle(text, width: rowValueWidth))
    }

     
     
    static func linkHost(_ text: String) -> String? {
        guard let host = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines))?.host, !host.isEmpty else { return nil }
        let bare = host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
        if bare.contains(":") || bare.split(separator: ".").allSatisfy({ Int($0) != nil }) { return bare }
        let labels = bare.split(separator: ".").map(String.init)
        guard labels.count > 2 else { return bare }
        let secondLevel: Set<String> = ["co", "com", "net", "org", "gov", "edu", "ac"]
        let keep = labels[labels.count - 1].count == 2 && secondLevel.contains(labels[labels.count - 2]) ? 3 : 2
        return labels.suffix(keep).joined(separator: ".")
    }

     
     
    static func cutInMiddle(_ text: String, width: Int) -> String {
        guard rowWidth(text) > width else { return text }
        let characters = Array(text)
        let side = max((width - 1) / 2, 1)
        var head = "", headWidth = 0
        for character in characters {
            let next = characterWidth(character)
            if headWidth + next > side { break }
            head.append(character); headWidth += next
        }
        var tail = "", tailWidth = 0
        for character in characters.reversed() {
            let next = characterWidth(character)
            if tailWidth + next > width - 1 - headWidth { break }
            tail.insert(character, at: tail.startIndex); tailWidth += next
        }
        return head + "…" + tail
    }

     
     
    private static func characterWidth(_ character: Character) -> Int {
        let wide: [ClosedRange<UInt32>] = [0x1100...0x115F, 0x2E80...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF,
                                           0xFE30...0xFE4F, 0xFF00...0xFF60, 0xFFE0...0xFFE6, 0x20000...0x3FFFD]
        return character.unicodeScalars.contains { scalar in wide.contains { $0.contains(scalar.value) } } ? 2 : 1
    }

     
     
    public static let rowValueWidth = 20

     
    public static func rowWidth(_ text: String) -> Int {
        text.reduce(0) { $0 + characterWidth($1) }
    }

     
    public static func words(_ value: OrderedJSON, field: ConfigurationField?, locale: Locale) -> ClashDisplayText {
        switch value {
        case .string(let text):
            if field?.kind == .number, isNumber(text) { return number(text, unit: field?.unit, locale: locale) }
             
            if let address = ConfigurationFormatWords.summary(text, field: field) { return address }
             
            return text.isEmpty ? .copy("None") : .verbatim(text)
        case .scalar(let token):
            switch token {
            case "true": return .copy("On")
            case "false": return .copy("Off")
            case "null", "~", "": return .copy("Not set")
            default:
                return isNumber(token) ? number(token, unit: field?.unit, locale: locale) : .verbatim(token)
            }
        case .array(let items):
            return items.isEmpty ? .copy("None") : itemCount(items.count, locale: locale)
        case .object(let entries):
            if field?.kind == .object {
                 
                for entry in entries {
                    switch entry.value {
                    case .string, .scalar: return words(entry.value, field: nil, locale: locale)
                    default: continue
                    }
                }
                return entries.isEmpty ? .copy("Not set") : entryCount(entries.count, locale: locale)
            }
            return entries.isEmpty ? .copy("None") : entryCount(entries.count, locale: locale)
        }
    }

     
     
     
     
     
     
    public static func defaultWords(for field: ConfigurationField, locale: Locale) -> ClashDisplayText? {
        switch field.defaultShape {
        case .none:
            return nil
        case .note:
            return .formatCopy("Default: %@", ["Automatic"])
        case .map(let count):
            return count == 0 ? .formatCopy("Default: %@", ["None"])
                : .format("Default: %@", [entryCount(count, locale: locale).resolved(locale: locale)])
        case .list(let items):
            guard !items.isEmpty else { return .formatCopy("Default: %@", ["None"]) }
            return .format("Default: %@", [listWords(items, locale: locale)])
        case .value(let text):
            switch text {
            case "true": return .formatCopy("Default: %@", ["On"])
            case "false": return .formatCopy("Default: %@", ["Off"])
            default:
                 
                 
                let inner: ClashDisplayText = isNumber(text) ? number(text, unit: field.unit, locale: locale)
                    : rowText(text, field: field, custom: false)
                return .format("Default: %@", [inner.resolved(locale: locale)])
            }
        }
    }

     
     
     
    public static func defaultPrompt(for field: ConfigurationField?, locale: Locale,
                                     copy: ConfigurationFieldCopy? = nil) -> String? {
        guard let field else { return nil }
        switch field.defaultShape {
        case .none: return nil
        case .value(let text): return text
        case .list(let items) where !items.isEmpty && items.count <= 3:
            return items.joined(separator: ", ")
        case .list, .map, .note:
            return copy?.entry(for: field, locale: locale)?.unset
        }
    }

     
     
    static func listWords(_ items: [String], locale: Locale) -> String {
        guard items.count <= 3 else { return itemCount(items.count, locale: locale).resolved(locale: locale) }
        return listJoined(items, locale: locale)
    }

     
     
     
    public static func listJoined(_ items: [String], locale: Locale) -> String {
        items.joined(separator: ConfigurationFieldCopy.Language(locale: locale) == .en ? ", " : "、")
    }

     
    static func scalarText(of value: OrderedJSON) -> String? {
        switch value {
        case .string(let text): return text
        case .scalar(let token): return token
        default: return nil
        }
    }

     
     
     
     
     
    public static func number(_ token: String, unit: String?, locale: Locale) -> ClashDisplayText {
        switch unit {
         
        case "s", "ms", "min", "h": return ConfigurationFormatWords.number(token, unit: unit)
        case "us": return .format("%@ µs", [token])
        case "ns": return .format("%@ ns", [token])
        case "bytes": return .format("%@ bytes", [token])
        case "packets": return .format("%@ packets", [token])
        case nil, "count", "port": return .verbatim(token)
        case "%": return .verbatim(token + "%")
        case "bytes/s": return .format("%@ B/s", [token])
        case "bits/s": return .format("%@ bps", [token])
        case let other?: return .verbatim(token + " " + other)
        }
    }

     
    public static func itemCount(_ count: Int, locale: Locale) -> ClashDisplayText {
        .format(count == 1 ? "%@ item" : "%@ items", [ClashCopy.count(count, locale: locale)])
    }

     
    public static func entryCount(_ count: Int, locale: Locale) -> ClashDisplayText {
        .format(count == 1 ? "%@ entry" : "%@ entries", [ClashCopy.count(count, locale: locale)])
    }

     
     
     
    public static func conditionalLine(for field: ConfigurationField, conditions: Set<String>) -> ClashDisplayText? {
        guard let decision = field.platformDecision, decision.when == .conditional,
              let condition = decision.condition, conditions.contains(condition) else { return nil }
        switch condition {
        case "includeAllNetworks":
             
             
            if let head = decision.value.flatMap({ $0.isEmpty ? nil : $0 }) ?? valueHead(of: decision.effective) {
                return .format("Fixed to %@ while Include All Networks is on", [head])
            }
            return .copy("Fixed by Clash under some settings")
        case "lanSharingOff":
            return .copy("Only this device can connect while LAN Proxy Share is off")
        default:
            return .copy("Fixed by Clash under some settings")
        }
    }

     
     
    public static func categoryLine(for decision: ConfigurationPlatformDecision?, device: String) -> ClashDisplayText {
        switch decision?.category {
        case "forced": return .copy("Clash sets this itself")
        case "stripped": return .copy("Not needed here, left out")
        case "unavailable": return .format("Not available on %@", [device])
        default: return .copy("Not used here")
        }
    }

     
     
    public static func notApplyingRow(count: Int, device: String, locale: Locale) -> ClashDisplayText {
        count == 1
            ? .format("1 setting doesn’t apply on %@", [device])
            : .format("%@ settings don’t apply on %@", [ClashCopy.count(count, locale: locale), device])
    }

     
    public static let notApplyingTitle: ClashDisplayText = .copy("Settings That Don’t Apply")

    public static func notApplyingFooter(device: String) -> ClashDisplayText {
        .format("On %@, Clash handles these itself; values written for them are not used.", [device])
    }

     
     
     
    static func valueHead(of effective: String?) -> String? {
        guard let effective, let colon = effective.firstIndex(of: ":") else { return nil }
        let head = effective[..<colon].trimmingCharacters(in: .whitespaces)
        guard !head.isEmpty, head.count <= 24, !head.contains(" ") else { return nil }
        return head
    }

    static func isNumber(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && Double(trimmed) != nil
    }
}
