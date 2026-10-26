import ClashClientKit
import Foundation

/// Settings that every configuration receives on top of its own.
///
/// They live outside profiles and outside rule schemes on purpose: a profile
/// that follows a built-in scheme can be refreshed without losing them, and a
/// scheme can be updated without carrying a private copy of them.
///
/// Two shapes, for two different reasons:
/// - `rules` are order-sensitive, so they are prepended to the document;
/// - `patchJSON` is any other app-level field (`dns.*`, `tun.*`, `sniffer.*`,
///   `hosts`, …), applied under every profile so the profile stays in charge.
struct GlobalOverridesConfig: Codable, Equatable {
    static let defaultsKey = "config.globalRules.v1"

    static let didChangeNotification = Notification.Name("ClashGlobalRulesDidChange")

    var isEnabled: Bool
    var rules: [String]
    /// A JSON object. Applied to the source before the profile's own overrides,
    /// so a profile that sets the same field wins.
    var patchJSON: String

    init(isEnabled: Bool = true, rules: [String] = [], patchJSON: String = "") {
        self.isEnabled = isEnabled
        self.rules = rules
        self.patchJSON = patchJSON
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, rules, patchJSON
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        rules = try container.decodeIfPresent([String].self, forKey: .rules) ?? []
        patchJSON = try container.decodeIfPresent(String.self, forKey: .patchJSON) ?? ""
    }

    var isEmpty: Bool {
        rules.isEmpty && patchJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static var appGroupDefaults: UserDefaults {
        UserDefaults(suiteName: ClashAppIdentifiers.appGroup) ?? .standard
    }

    static func load(from defaults: UserDefaults = appGroupDefaults) -> GlobalOverridesConfig {
        guard let data = defaults.data(forKey: defaultsKey),
              let stored = try? JSONDecoder().decode(GlobalOverridesConfig.self, from: data)
        else { return GlobalOverridesConfig() }
        return stored
    }

    static func save(_ config: GlobalOverridesConfig, in defaults: UserDefaults = appGroupDefaults) {
        var cleaned = config
        cleaned.rules = normalized(config.rules)
        cleaned.patchJSON = Self.normalizedPatch(config.patchJSON)
        guard let data = try? JSONEncoder().encode(cleaned) else { return }
        defaults.set(data, forKey: defaultsKey)
        NotificationCenter.default.post(name: didChangeNotification, object: defaults)
    }

    static func normalized(_ entries: [String]) -> [String] {
        var seen: Set<String> = []
        return entries
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// `{}` and blank mean "no patch", so the stored value never carries an
    /// empty object into every build.
    static func normalizedPatch(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "{}" { return "" }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object.isEmpty == false,
              let canonical = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.sortedKeys, .withoutEscapingSlashes]
              )
        else { return trimmed }
        return String(decoding: canonical, as: UTF8.self)
    }

    static func patchIsValid(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "{}" { return true }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
        else { return false }
        return object is [String: Any]
    }

    /// Prepends the stored rules to a generated configuration.
    ///
    /// Rules whose policy the configuration does not define are left out for it
    /// instead of failing its build, the same way personal rules are handled.
    func merging(into yaml: String) throws -> String {
        guard isEnabled, !rules.isEmpty else { return yaml }
        var kept = try ProfileRuntimeConfigBuilder.resolvedFallbackTargets(rules, mergedInto: yaml)
        kept = ProfileRuntimeConfigBuilder.droppingUnknownTargets(kept, mergedInto: yaml).kept
        guard !kept.isEmpty else { return yaml }
        let payload = OrderedJSON.object([
            (key: "appendRules", value: .array(kept.map(OrderedJSON.string))),
            (key: "prependRules", value: .scalar("true")),
        ])
        return try ConfigTransforms.mergeOverride(raw: yaml, overrideJSON: payload.serialized())
    }

    /// Applies the patch to the source, before the profile's own overrides run,
    /// so anything the profile sets wins over the same field here.
    func applyingBase(to yaml: String) throws -> String {
        guard isEnabled else { return yaml }
        let patch = Self.normalizedPatch(patchJSON)
        guard !patch.isEmpty else { return yaml }
        let payload = OrderedJSON.object([(key: "patch", value: try OrderedJSON.parse(patch))])
        return try ConfigTransforms.mergeOverride(raw: yaml, overrideJSON: payload.serialized())
    }
}
