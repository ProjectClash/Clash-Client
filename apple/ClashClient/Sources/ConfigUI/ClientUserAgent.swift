import Foundation
import Clash

 
 
 
 
 
 
 
 
 
 
 
enum ClientUserAgent {
    enum Preset: String, CaseIterable, Identifiable {
        case clash
        case flclash
        case clashVerge

        var id: String { rawValue }

        var label: String {
            switch self {
            case .clash: return "Clash (Default)"
            case .flclash: return "FlClash"
            case .clashVerge: return "Clash Verge"
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
            }
        }
    }

    static let presetKey = "ua.preset"
    private static let maximumBytes = 512

    static var appGroupDefaults: UserDefaults {
        UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite) ?? .standard
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

     

     
     
     
     
    static func downloadIdentity(from d: UserDefaults = appGroupDefaults) -> String {
        preset(from: d).value
    }

     
     
     
    static func written(in root: [String: Any]?) -> String? {
        switch root?["global-ua"] {
        case let text as String: return sanitized(text)
        case let number as NSNumber:
            return sanitized(CFGetTypeID(number) == CFBooleanGetTypeID() ? (number.boolValue ? "true" : "false") : number.stringValue)
        default: return nil
        }
    }

     
     
     
     
     
    static func choice(_ userAgent: String?, identity: String) -> String? {
        guard let userAgent = sanitized(userAgent), userAgent != identity else { return nil }
        return userAgent
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
