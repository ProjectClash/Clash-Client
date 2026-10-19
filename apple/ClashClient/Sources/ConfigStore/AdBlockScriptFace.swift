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

    /// The `$argument` tree, with the user's choices over the module's defaults.
    ///
    /// A declaration with no default and no user choice is left out rather than
    /// given an empty string, because scripts test `typeof $argument.x`, and a
    /// boolean declaration must arrive as a boolean.
    static func arguments(for script: AdBlockScript, choices: [String: String]) -> [String: ScriptArgumentValue] {
        var out: [String: ScriptArgumentValue] = [:]
        for argument in script.argumentDefaults ?? [] {
            guard let value = choices[key(script: script, name: argument.name)] ?? argument.defaultValue else { continue }
            out[argument.name] = ScriptArgumentValue(value, kind: argument.kind)
        }
        // A script may also have been declared with a single `argument=` string;
        // that string is the whole argument, as on Surge.
        if out.isEmpty, let single = script.argument, !single.isEmpty {
            out["argument"] = .text(single)
        }
        return out
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
