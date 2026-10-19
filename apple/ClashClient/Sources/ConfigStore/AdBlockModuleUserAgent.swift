import ClashClientKit
import Foundation

/// The User-Agent a module download presents.
///
/// Module hubs are not neutral file servers: most serve a module only to the
/// app that can run it and answer anything else with a challenge page or a 403.
/// `hub.kelee.one` is one — a plain request gets Cloudflare's block page, and
/// the same request carrying Loon's own User-Agent gets the plugin. So a
/// download has to present the platform the module belongs to.
///
/// What decides it is the module's own type, in order of certainty:
///
/// 1. The user's choice, when they made one — a hub filtering on something
///    other than a platform name is theirs to work around, and they can.
/// 2. The dialect the module was last read as, when it has been fetched before.
///    This is the real answer: `.lpx` *is* Loon, `.sgmodule` *is* Surge.
/// 3. The address's own extension, when it is being fetched for the first time.
///    `…/Block.lpx` names Loon before a byte is read. A hub that serves a
///    plugin under an opaque path is the case this cannot answer, and the
///    download falls back to trying the platforms in turn.
///
/// Nothing here keys on a particular hub's domain: addresses change and a name
/// match would rot silently.
enum AdBlockModuleUserAgent {
    /// The platform a module's dialect belongs to.
    static func preset(for format: AdBlockModuleFormat) -> ClientUserAgent.Preset {
        switch format {
        case .loon: return .loon
        case .surge: return .surge
        case .quantumultX: return .quantumultX
        case .stash: return .stash
        }
    }

    /// The platform an address names in its own extension, when it names one.
    static func preset(forAddress url: URL?) -> ClientUserAgent.Preset? {
        guard let path = url?.path.lowercased() else { return nil }
        // Loon ships plugins as `.lpx` and `.plugin`, Surge modules as
        // `.sgmodule`, and both families occasionally as `.conf`.
        if path.hasSuffix(".lpx") || path.hasSuffix(".plugin") { return .loon }
        if path.hasSuffix(".sgmodule") { return .surge }
        if path.hasSuffix(".snippet") { return .quantumultX }
        if path.hasSuffix(".stoverride") { return .stash }
        return nil
    }

    /// The User-Agent a module at `url` should be fetched with.
    ///
    /// `format` is what the caller already knows, which for a module that has
    /// been fetched before is its stored dialect.
    static func value(for url: URL?, format: AdBlockModuleFormat? = nil) -> String {
        if let chosen = ClientUserAgent.moduleOverride() { return chosen.value }
        if let format { return preset(for: format).value }
        if let named = preset(forAddress: url) { return named.value }
        return ClientUserAgent.Preset.clash.value
    }

    /// The User-Agents worth trying for a module, best first.
    ///
    /// A first fetch under an opaque address has no type to go on, so the
    /// platforms are tried in turn and the first the hub accepts is the answer.
    /// A module whose type is known gets exactly one attempt: presenting
    /// another platform's name to a hub that has already served this module
    /// would be guessing for no reason.
    static func candidates(for url: URL?, format: AdBlockModuleFormat? = nil) -> [ClientUserAgent.Preset] {
        if let chosen = ClientUserAgent.moduleOverride() { return [chosen] }
        if let format { return [preset(for: format)] }
        if let named = preset(forAddress: url) { return [named] }
        return [.loon, .surge, .quantumultX, .stash, .shadowrocket, .clash]
    }
}
