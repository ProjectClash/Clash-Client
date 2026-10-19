#if os(iOS) || os(macOS)
import Foundation

/// The user's choices for module arguments.
///
/// A module declares its arguments with defaults (`#!arguments=`, `[Argument]`);
/// the app lets the user change them. The choices live in the App Group so the
/// tunnel, which actually runs the scripts, sees what the app's editor saved
/// without an IPC round trip.
///
/// Keys are the script's address plus the argument name, because two modules may
/// declare the same name and mean different things, and a module's address is
/// what the user is editing when they change it.
enum AdBlockScriptSettings {
    /// `moduleURL#argumentName` → chosen value.
    static let file = "adblock-arguments.json"

    static func choices(container: URL? = ClashAppIdentifiers.appGroupContainer) -> [String: String] {
        guard let container, let data = try? Data(contentsOf: container.appendingPathComponent(file)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return object
    }

    /// Saves one choice. Called by the editor when the user changes a value.
    static func set(_ value: String?, for key: String, container: URL? = ClashAppIdentifiers.appGroupContainer) {
        guard let container else { return }
        var current = choices(container: container)
        if let value { current[key] = value } else { current.removeValue(forKey: key) }
        guard let data = try? JSONSerialization.data(withJSONObject: current) else { return }
        try? data.write(to: container.appendingPathComponent(file), options: .atomic)
    }
}
#endif
