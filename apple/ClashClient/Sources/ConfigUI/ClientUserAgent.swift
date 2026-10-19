import Foundation
import Clash

 
 
 
 
 
 
 
 
enum ClientUserAgent {
    enum Preset: String, CaseIterable, Identifiable {
        case clash
        case flclash
        case clashVerge
        // The platforms whose names the script hubs filter on. A hub that
        // serves modules tends to serve them only to the app that can run them,
        // so a request that means to fetch one has to look like that app.
        case loon
        case surge
        case quantumultX
        case stash
        case shadowrocket

        var id: String { rawValue }

        var label: String {
            switch self {
            case .clash: return "Clash (Default)"
            case .flclash: return "FlClash"
            case .clashVerge: return "Clash Verge"
            case .loon: return "Loon"
            case .surge: return "Surge"
            case .quantumultX: return "Quantumult X"
            case .stash: return "Stash"
            case .shadowrocket: return "Shadowrocket"
            }
        }

        var value: String {
            switch self {
            case .clash:
                let app = Bundle.main
                    .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
                let build = Bundle.main
                    .object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
                 
                 
                 
                 
                 
                let head = "clash.meta/\(ClashVersion()) Clash/\(ClashDeviceModel.appToken(version: app, build: build))"
                guard let tail = ClashDeviceModel.userAgentTail else { return head }
                return head + " " + tail
            case .flclash:
                 
                return "FlClash/v0.8.94 clash-verge Platform/android"
            case .clashVerge:
                 
                return "clash-verge/v2.4.2"
            // These are the versions the hubs themselves see in the wild; a
            // number far from them is as conspicuous as a wrong name.
            case .loon: return "Loon/868 CFNetwork/1494.0.7 Darwin/23.4.0"
            case .surge: return "Surge/5.10.0 CFNetwork/1494.0.7 Darwin/23.4.0"
            case .quantumultX: return "Quantumult%20X/1.4.1 CFNetwork/1494.0.7 Darwin/23.4.0"
            case .stash: return "Stash/2.5.0 CFNetwork/1494.0.7 Darwin/23.4.0"
            case .shadowrocket: return "Shadowrocket/2.2.60 CFNetwork/1494.0.7 Darwin/23.4.0"
            }
        }
    }

    static let presetKey = "ua.preset"

    /// A User-Agent chosen for module downloads alone.
    ///
    /// It is separate from `presetKey` because the two answer different
    /// questions. `presetKey` is what this app calls itself when it fetches a
    /// subscription — a hub that serves subscriptions recognises it. A module
    /// hub usually serves one platform only and refuses the rest, so what a
    /// module download should present is that platform, and a user who knows
    /// which one should not have to change what their subscriptions announce.
    static let modulePresetKey = "ua.modulePreset"

    /// The user's override for module downloads, or `nil` when the module's own
    /// dialect and address are left to decide.
    static func moduleOverride(from d: UserDefaults = appGroupDefaults) -> Preset? {
        guard let stored = d.string(forKey: modulePresetKey), !stored.isEmpty else { return nil }
        return Preset(rawValue: stored)
    }

    static func saveModuleOverride(_ preset: Preset?, in d: UserDefaults = appGroupDefaults) {
        guard let preset else { return d.removeObject(forKey: modulePresetKey) }
        d.set(preset.rawValue, forKey: modulePresetKey)
    }
    private static let maximumBytes = 512

    static var appGroupDefaults: UserDefaults {
        UserDefaults(suiteName: ClashAppIdentifiers.appGroup) ?? .standard
    }

     
     
     
    static let retiredPresets: Set<String> = ["clashForWindows"]

     
     
     
     
    static func preset(from d: UserDefaults = appGroupDefaults) -> Preset {
        let stored = d.string(forKey: presetKey) ?? ""
        if let preset = Preset(rawValue: stored) { return preset }
        if retiredPresets.contains(stored) { save(preset: .clash, in: d) }
        return .clash
    }

    static func save(preset: Preset, in d: UserDefaults = appGroupDefaults) {
        d.set(preset.rawValue, forKey: presetKey)
    }

     
     
    static func resolved(configYAML: String, fallback: String) -> String {
        resolved(root: (try? ConfigTransforms.foundationRoot(ofYAML: configYAML)) ?? nil, fallback: fallback)
    }

     
     
    static func resolved(root: [String: Any]?, fallback: String) -> String {
        sanitized(root?["global-ua"] as? String) ?? fallback
    }

     
     
     
    static func sanitized(_ value: String?) -> String? {
        guard let value else { return nil }
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...maximumBytes).contains(candidate.utf8.count),
              candidate.unicodeScalars.allSatisfy({
                  !CharacterSet.controlCharacters.contains($0)
              }) else {
            return nil
        }
        return candidate
    }
}
