import Foundation

extension Notification.Name {
    /// Posted when the profile store directory changed on disk. Writes from
    /// this process post it too; observers compare the re-read store with what
    /// they already have before doing anything.
    static let clashProfileStoreDirectoryDidChange =
        Notification.Name("ClashProfileStoreDirectoryDidChange")
}

/// Watches a profile store directory so the App notices writes made outside
/// this process: `clash-cli`, or the tunnel extension's app-store endpoints.
@MainActor
final class ProfileStoreDirectoryWatcher {
    static let shared = ProfileStoreDirectoryWatcher()

    private struct Watched {
        let source: DispatchSourceFileSystemObject
    }

    private var watched: [String: Watched] = [:]
    private var retries: [String: DispatchWorkItem] = [:]

    func watch(directory: URL?) {
        guard let directory else { return }
        let path = directory.standardizedFileURL.path
        guard watched[path] == nil, retries[path] == nil else { return }
        start(path: path)
    }

    private func start(path: String) {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else {
            // The store directory is created on the first save; try again a
            // little later instead of watching nothing for the whole session.
            retry(path: path)
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            if source.data.contains(.delete) || source.data.contains(.rename) {
                // The directory itself moved or vanished: re-open it later.
                self.restart(path: path)
            } else {
                NotificationCenter.default.post(
                    name: .clashProfileStoreDirectoryDidChange, object: nil)
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watched[path] = Watched(source: source)
    }

    private func restart(path: String) {
        watched.removeValue(forKey: path)?.source.cancel()
        retry(path: path)
    }

    private func retry(path: String) {
        guard retries[path] == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.retries[path] = nil
            self?.start(path: path)
        }
        retries[path] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }
}
