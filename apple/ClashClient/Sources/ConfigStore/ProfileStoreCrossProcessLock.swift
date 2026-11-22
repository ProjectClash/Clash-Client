import Foundation

/// The lock every writer of `profiles.json` takes, in this process and in the
/// others: the App, the tunnel extension's app-store endpoints and `clash-cli`
/// all flock `<store>/profiles.lock` around a read-modify-write, so a save can
/// never drop an edit made by another process in the meantime.
///
/// The file is the same one the kernel takes (`app_store_route.go`); the
/// protocol is "flock the lock file, re-read `profiles.json`, write a new file
/// and rename it over the old one". Locking the lock file rather than the
/// store itself keeps the lock valid across the rename.
final class ProfileStoreCrossProcessLock {
    enum Failure: LocalizedError, Equatable {
        case unavailable(Int32)
        case timedOut

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "The profile list's lock file could not be opened, so the change was not saved."
            case .timedOut:
                return "Another process is still editing the profile list, so the change was not saved. Try again."
            }
        }
    }

    private static let retryInterval: useconds_t = 20_000

    private let fileURL: URL
    private var descriptor: Int32 = -1
    private var depth = 0

    init(directory: URL) {
        fileURL = directory.appendingPathComponent("profiles.lock")
    }

    /// Reentrant. A nested call deepens the hold instead of opening a second
    /// descriptor, which flock would block on against its own holder.
    func lock(waitingUpTo timeout: TimeInterval = 5) throws {
        if depth > 0 {
            depth += 1
            return
        }
        let descriptor = open(fileURL.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw Failure.unavailable(errno) }
        let deadline = Date().addingTimeInterval(timeout)
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            let code = errno
            guard code == EWOULDBLOCK || code == EAGAIN else {
                close(descriptor)
                throw Failure.unavailable(code)
            }
            guard Date() < deadline else {
                close(descriptor)
                throw Failure.timedOut
            }
            usleep(Self.retryInterval)
        }
        self.descriptor = descriptor
        depth = 1
    }

    func unlock() {
        guard depth > 0 else { return }
        depth -= 1
        guard depth == 0, descriptor >= 0 else { return }
        _ = flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }
}
