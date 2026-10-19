#if os(iOS) || os(macOS)
import Foundation

/// The file behind `$persistentStore` and Script-Hub's `$prefs`.
///
/// One file for every script, as the platforms have one store per host: a
/// script's keys are namespaced by its own prefix, not by the host. It is read
/// once and kept in memory, because a rewrite script reads it on every exchange
/// and a file read per request would be the slowest thing in the tunnel.
final class ScriptStore: @unchecked Sendable {
    private let url: URL?
    private let lock = NSLock()
    private var values: [String: String]?
    private static let maximumBytes = 4 << 20

    init(url: URL?) { self.url = url }

    func read(_ key: String?) -> String? {
        guard let key else { return nil }
        lock.lock(); defer { lock.unlock() }
        return loaded()[key]
    }

    func write(_ value: String?, for key: String?) {
        guard let key else { return }
        lock.lock(); defer { lock.unlock() }
        var current = loaded()
        if let value { current[key] = value } else { current.removeValue(forKey: key) }
        store(current)
    }

    func removeAll() {
        lock.lock(); defer { lock.unlock() }
        store([:])
    }

    private func loaded() -> [String: String] {
        if let values { return values }
        var values: [String: String] = [:]
        if let url, let data = try? Data(contentsOf: url),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            values = object
        }
        self.values = values
        return values
    }

    private func store(_ values: [String: String]) {
        self.values = values
        guard let url, let data = try? JSONSerialization.data(withJSONObject: values),
              data.count <= Self.maximumBytes else { return }
        try? data.write(to: url, options: .atomic)
    }
}

#endif
