import Foundation

/// Which script platform a run presents itself as.
///
/// The name matters more than it looks: `Env.js`, `OpenAPI.js` and
/// `@nsnanocat/util` decide what a host can do by looking for a handful of
/// globals (`$task`, `$loon`, `$rocket`, `$environment["surge-version"]`,
/// `$environment["stash-version"]`), and they check them in that order. A host
/// that injects every global at once is therefore read as Quantumult X by every
/// script, no matter what it really is. Each case here injects only the globals
/// its platform really has, so a script sees the host it was written for.
public enum ScriptPlatform: String, CaseIterable, Codable, Sendable {
    case loon
    case surge
    case stash
    case quantumultX
    case shadowrocket
    case jsbox

    /// The name the platform answers to in its own UI and in `$environment.app`.
    public var displayName: String {
        switch self {
        case .loon: return "Loon"
        case .surge: return "Surge"
        case .stash: return "Stash"
        case .quantumultX: return "Quantumult X"
        case .shadowrocket: return "Shadowrocket"
        case .jsbox: return "JSBox"
        }
    }

    /// The platform whose dialect a module was written in, when the module says.
    ///
    /// A module carries the proof in its own shape: a `.lpx` plugin with
    /// `[Rewrite]`/`[Argument]` is Loon, `#!name=` with `[Script]` and `type=`
    /// is Surge, a Stash override is neither, and `[rewrite_local]`/`[task_local]`
    /// is Quantumult X. Scripts published by one platform but written against
    /// another's API are common, so the module's dialect is the best evidence of
    /// what its scripts expect.
    public init?(moduleFormat: String) {
        switch moduleFormat.lowercased() {
        case "loon", "lpx", "plugin": self = .loon
        case "surge", "sgmodule", "module": self = .surge
        case "stash", "override", "stoverride": self = .stash
        case "quantumultx", "quantumult x", "qx", "conf": self = .quantumultX
        case "shadowrocket": self = .shadowrocket
        case "jsbox": self = .jsbox
        default: return nil
        }
    }

    /// Whether the platform's storage is reached through `$prefs` rather than
    /// `$persistentStore`. Quantumult X is the only one that differs.
    public var usesPrefsStorage: Bool { self == .quantumultX }

    /// Whether the platform reports a version in `$environment` instead of a
    /// bare `$loon`/`$rocket` string.
    public var reportsVersionInEnvironment: Bool {
        self == .surge || self == .stash
    }
}

/// What a script is being run for. The phase decides which of `$request` and
/// `$response` exist, and whether a returned response is a mock (request phase)
/// or a rewrite (response phase).
public enum ScriptPhase: String, Codable, Sendable {
    case request
    case response
    case cron
    case generic
}

/// The identity a run presents. Built by the host, read by the prelude.
public struct ScriptIdentity: Equatable, Sendable {
    public var platform: ScriptPlatform
    /// The version string the platform's globals carry, e.g. `3.2.0(1000)`.
    public var version: String
    /// The device the platform claims, used in `$loon`.
    public var device: String
    /// The system version the platform claims, used in `$loon` and `$environment`.
    public var systemVersion: String
    /// The tunnel's own display name, used as `$environment.app` where the
    /// platform has no fixed answer.
    public var appName: String

    public init(platform: ScriptPlatform, version: String = "3.2.0(1000)",
                device: String = "iPhone15,2", systemVersion: String = "18.0",
                appName: String = "Clash") {
        self.platform = platform
        self.version = version
        self.device = device
        self.systemVersion = systemVersion
        self.appName = appName
    }

    /// `$loon`'s format: `iPhone15,2 18.0 3.2.0(1000)`, or `Mac 3.2.0(1000)` on
    /// a Mac. `@nsnanocat/util` splits on spaces and reads positions 0, 1 and 2,
    /// so the Mac form is the only one with two fields.
    public var loonString: String {
        device == "Mac" ? "Mac \(version)" : "\(device) \(systemVersion) \(version)"
    }
}
