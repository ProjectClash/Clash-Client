import Foundation

 
 
 
 
 
 
 
enum ProviderDownloadActivity {
     
     
    static let didChangeNotification = Notification.Name("ClashProviderDownloadActivityDidChange")

    private static let addressesKey = "addresses"

     
     
     
    static func addresses(in note: Notification) -> Set<String>? {
        (note.userInfo?[addressesKey] as? [String]).map(Set.init)
    }

     
    static let downloadingNote = "Downloading…"

    private static let lock = NSLock()
    nonisolated(unsafe) private static var running: [String: Int] = [:]
    nonisolated(unsafe) private static var failures: [String: ProviderNote] = [:]
    nonisolated(unsafe) private static var claimed: Set<String> = []

     
     
     
     
     
     
    static func claim(_ urls: [String]) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        var taken: [String] = []
        for url in urls where !claimed.contains(url) {
            claimed.insert(url)
            taken.append(url)
        }
        return taken
    }

    static func release(_ urls: [String]) {
        lock.lock()
        for url in urls { claimed.remove(url) }
        lock.unlock()
    }

     
     
    static func begin(_ urls: [String]) {
        guard !urls.isEmpty else { return }
        lock.lock()
        for url in urls { running[url, default: 0] += 1 }
        lock.unlock()
        post(urls)
    }

     
     
     
     
    static func end(_ url: String, failure: ProviderNote?, answered: Bool = true) {
        lock.lock()
        if let count = running[url], count > 1 { running[url] = count - 1 } else { running[url] = nil }
        if answered { failures[url] = failure }
        lock.unlock()
        post([url])
    }

    static var downloading: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(running.keys)
    }

    static var recentFailures: [String: ProviderNote] {
        lock.lock()
        defer { lock.unlock() }
        return failures
    }

     
    static var fingerprint: String {
        lock.lock()
        defer { lock.unlock() }
        return running.keys.sorted().joined(separator: ",") + "|"
            + failures.sorted { $0.key < $1.key }.map { $0.key + "=" + $0.value.englishText }.joined(separator: ",")
    }

    static func resetForTesting() {
        lock.lock()
        running = [:]
        failures = [:]
        claimed = []
        lock.unlock()
    }

     
     
     
     
     
    static func reason(for error: Error, url: String) -> ProviderNote {
        if let batch = error as? ProviderDownloadFailuresError, let first = batch.failures.first {
            return .downloadFailed(url: first.url ?? url, reason: .of(first.underlying))
        }
        if let refused = error as? ProviderValidationFailure {
            return .failed(.of(refused.underlying))
        }
        if let refusal = error as? MaterializeError, let text = refusal.providerRowText {
            return .failed(text)
        }
        return .downloadFailed(url: url, reason: .of(error))
    }

     
     
    private static func post(_ urls: [String]) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: didChangeNotification, object: nil, userInfo: [addressesKey: urls])
        }
    }
}
