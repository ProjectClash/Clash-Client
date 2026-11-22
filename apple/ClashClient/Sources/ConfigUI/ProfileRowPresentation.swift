import Foundation
import ClashClientKit
import ClashClientUI

 
 
 
 
 
 
enum ProfileRowPresentation {
     
     
     
     
     
     
    static func label(for profile: Profile, locale: Locale) -> String {
        guard profile.id == LocalDefaultProfileProvisioner.profileID else { return profile.label }
        return ClashCopy.string("Profile Center", locale: locale)
    }

     
     
     
     
     
    static func badges(for profile: Profile, in library: ConfigurationLibrarySnapshot) -> [ClashDisplayText] {
        if profile.id == LocalDefaultProfileProvisioner.profileID { return [.copy("Built-in")] }
        guard let recipe = library.recipes.first(where: { $0.id == profile.id }) else {
            return [.copy("Original")]
        }
        if recipe.preservesOriginal == true { return [.copy("Original")] }
        switch builtinBase(of: recipe.ruleSchemeID, in: library) ?? recipe.ruleSchemeID {
        case ConfigurationBuiltins.basicRuleID: return [.copy("Default Rules")]
        case ConfigurationBuiltins.lazyRuleID: return [.copy("Lazy Rules")]
        default:
             
             
             
             
             
            guard let scheme = library.rules.first(where: { $0.id == recipe.ruleSchemeID }) else { return [] }
             
             
             
            let named = scheme.ownViewBaseID.flatMap { base in library.rules.first { $0.id == base } } ?? scheme
            return [.verbatim(Self.tagText(named.displayLabel))]
        }
    }

     
     
     
     
     
     
     
     
     
     
     
    static func builtinBase(of schemeID: String, in library: ConfigurationLibrarySnapshot) -> String? {
        var next: String? = schemeID
        var seen = Set<String>()
        while let id = next, seen.insert(id).inserted {
            if ConfigurationBuiltins.isNative(id) { return id == schemeID ? nil : id }
            guard let scheme = library.rules.first(where: { $0.id == id }) else { return nil }
            if let base = scheme.baseSchemeID, ConfigurationBuiltins.isNative(base), scheme.builtinNamedAfter == nil {
                return nil
            }
            next = scheme.baseSchemeID ?? scheme.rulesFromSchemeID ?? scheme.rulesCustomizedFromSchemeID
        }
        return nil
    }

     
     
     
     
    static let tagWidthLimit = 8

    static func tagText(_ label: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard tagWidth(trimmed) > tagWidthLimit else { return trimmed }
        var kept = ""
        for character in trimmed {
             
            guard tagWidth(kept + String(character)) <= tagWidthLimit - 1 else { break }
            kept.append(character)
        }
        return kept + "…"
    }

    private static func tagWidth(_ text: String) -> Int {
        text.unicodeScalars.reduce(0) { width, scalar in
            width + (isWide(scalar) ? 2 : 1)
        }
    }

     
    private static func isWide(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF,
             0x4E00...0x9FFF, 0xA000...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF,
             0xFE30...0xFE4F, 0xFF00...0xFF60, 0xFFE0...0xFFE6, 0x20000...0x3FFFD:
            return true
        default:
            return false
        }
    }

     
     
     
     
     
     
    static func note(for profile: Profile, in library: ConfigurationLibrarySnapshot,
                     providerNodes: [String: Int] = [:],
                     locale: Locale = .current) -> ClashDisplayText? {
        guard let recipe = library.recipes.first(where: { $0.id == profile.id }) else { return nil }
        let records = recipe.sources.compactMap { pin in library.sources.first(where: { $0.id == pin.id }) }
        let nodes = records.reduce(0) { $0 + $1.nodeCount + (providerNodes[$1.id] ?? 0) }
        guard nodes > 0 else {
            let providers = records.reduce(0) { $0 + $1.providerCount }
            guard providers > 0 else { return nil }
            return .format(providers == 1 ? "%@ proxy provider (not downloaded yet)" : "%@ proxy providers (not downloaded yet)",
                           [String(providers)])
        }
        return .format(nodes == 1 ? "%@ node" : "%@ nodes", [compactCount(nodes, locale: locale)])
    }

     
     
     
     
     
     
    static func compactCount(_ count: Int, locale: Locale) -> String {
        guard count >= 10_000 else { return String(count) }
        return count.formatted(.number.notation(.compactName).locale(locale))
    }
}
