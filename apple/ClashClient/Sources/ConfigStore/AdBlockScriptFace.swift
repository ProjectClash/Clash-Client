#if os(iOS) || os(macOS)
import AdBlockScriptKit
import Foundation

/// The two things a run needs that both the tunnel and the app's scheduler have
/// to agree on: which platform a script believes it is on, and what its
/// `$argument` is.
///
/// They live here rather than beside the tunnel's runner because a scheduled
/// script runs in the app, where the tunnel's files are not compiled; a
/// disagreement between the two would show up as a script behaving differently
/// on its schedule than on a page load.
enum AdBlockScriptFace {
    /// The platform a script believes it is on.
    ///
    /// The module's dialect is the evidence: a `.lpx` plugin's scripts were
    /// written for Loon, a `.sgmodule`'s for Surge, a Stash override's for
    /// Stash, and a Quantumult X rewrite for Quantumult X. A script published
    /// by one platform and written against another's API is common, and the
    /// dialect is what those scripts assume.
    static func identity(for format: AdBlockModuleFormat) -> ScriptIdentity {
        let platform = ScriptPlatform(moduleFormat: format.rawValue) ?? .loon
        return ScriptIdentity(platform: platform, device: device, systemVersion: systemVersion)
    }

    /// The `$argument` the script receives, in the form the plugin wrote it.
    ///
    /// Loon's script syntax takes an optional second argument, and what is
    /// written there is what the script gets: `script("x.js")` gives nothing,
    /// `script("x.js", "a=1&b=2")` gives that string, and
    /// `script("x.js", {${region}, ${level}})` gives an object whose values
    /// keep the types the plugin declared. Scripts read the string with
    /// `.split('&')` and the object by name, so the form has to be preserved
    /// rather than normalised.
    ///
    /// A declaration with no default and no user choice is left out of the
    /// object rather than given an empty string, because scripts test
    /// `typeof $argument.x`.
    static func argument(for script: AdBlockScript, choices: [String: String]) -> ScriptArgument {
        if let names = script.argumentNames, !names.isEmpty {
            var values: [String: ScriptArgumentValue] = [:]
            for name in names {
                let declared = script.argumentDefaults?.first { $0.name == name }
                guard let value = choices[key(script: script, name: name)] ?? declared?.defaultValue else {
                    // The plugin named the parameter but has no value for it
                    // yet; Loon passes `null` rather than leaving the key out.
                    values[name] = .empty
                    continue
                }
                values[name] = ScriptArgumentValue(value, kind: declared?.kind)
            }
            return .values(values)
        }
        if let single = script.argument, !single.isEmpty { return .text(single) }
        return .none
    }

    /// The key a choice is stored under: the script's address and the argument's
    /// name. Two modules may declare an argument of the same name.
    static func key(script: AdBlockScript, name: String) -> String {
        "\(script.scriptURL)#\(name)"
    }

    /// The system version as a script expects it: `18.0`, not
    /// `Version 18.0 (Build 22A3354)`. `$loon` is split on spaces by the
    /// libraries that read it, so a version with spaces in it would be read as
    /// a build number.
    static var systemVersion: String {
        let text = ProcessInfo.processInfo.operatingSystemVersionString
        guard let range = text.range(of: #"\d+(\.\d+)*"#, options: .regularExpression) else { return "18.0" }
        return String(text[range])
    }

    static var device: String {
#if os(macOS)
        return "Mac"
#else
        return "iPhone"
#endif
    }
}
#endif
