import AppIntents
import NetworkExtension

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
@available(iOS 16.0, *)
struct ClashVPNControlIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set Clash VPN"

     
     
    static var openAppWhenRun: Bool { false }

    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "VPN Connected")
    var value: Bool

    func perform() async throws -> some IntentResult {
         
         
         
        if await ClashVPNControlDriver.apply(connect: value) {
            return .result()
        }
         
         
         
         
        ClashSystemActionDispatch.enqueue(.vpn(value ? .connect : .disconnect))
        return .result()
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum ReaderTunnelIntent: String, Equatable, Sendable {
    case connect, stop

    struct Record: Equatable, Sendable {
        let intent: ReaderTunnelIntent
         
         
        let at: Date
         
         
        let generation: UInt64
         
        let gesture: String?
    }

    static let fileName = "reader-tunnel-intent.json"
    static let lockName = "reader-tunnel-intent.lock"

     
    static var appGroupDirectory: URL? { ClashAppIdentifiers.appGroupContainer }

     
     
     
    enum Failure: Error, Equatable {
        case noAppGroup
        case lockUnavailable(Int32)
        case unreadable
        case unwritable
    }

     
     
     
     
     
     
     
     
    static var holdAwake: () -> (() -> Void) = { {} }

     
    enum Written: Equatable {
         
        case accepted(Record)
         
         
        case superseded(by: Record)
    }

     
     
     
     
     
     
     
    @discardableResult
    static func record(_ intent: ReaderTunnelIntent, at: Date = Date(), gesture: String? = nil,
                       basedOn seen: UInt64? = nil, in directory: URL?) throws -> Written {
        guard let directory else { throw Failure.noAppGroup }
        return try withLock(in: directory, LOCK_EX) {
             
             
             
             
             
            let current = try read(directory)
            if intent == .connect, let seen, let current, current.generation != seen {
                return .superseded(by: current)
            }
            let generation = (current?.generation ?? 0) &+ 1
             
             
             
            let stamped = Date(timeIntervalSince1970: at.timeIntervalSince1970)
            let next = Record(intent: intent, at: stamped, generation: generation, gesture: gesture)
            var object: [String: Any] = [
                "intent": next.intent.rawValue, "at": next.at.timeIntervalSince1970,
                "generation": NSNumber(value: next.generation),
            ]
            if let gesture { object["gesture"] = gesture }
            do {
                let data = try JSONSerialization.data(withJSONObject: object)
                try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
            } catch {
                throw Failure.unwritable
            }
            return .accepted(next)
        }
    }

     
     
     
     
     
    static func last(in directory: URL?) throws -> Record? {
        guard let directory else { throw Failure.noAppGroup }
        return try read(directory)
    }

    private static func read(_ directory: URL) throws -> Record? {
        let url = directory.appendingPathComponent(fileName)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            throw Failure.unreadable
        }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let raw = object["intent"] as? String, let intent = ReaderTunnelIntent(rawValue: raw),
              let seconds = object["at"] as? Double,
              let generation = (object["generation"] as? NSNumber)?.uint64Value
        else { throw Failure.unreadable }
        return Record(intent: intent, at: Date(timeIntervalSince1970: seconds), generation: generation,
                      gesture: object["gesture"] as? String)
    }

     
     
     
    private static func withLock<T>(in directory: URL, _ operation: Int32, _ body: () throws -> T) throws -> T {
        let release = holdAwake()
        defer { release() }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fd = open(directory.appendingPathComponent(lockName).path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard fd >= 0 else { throw Failure.lockUnavailable(errno) }
        defer { close(fd) }
        while flock(fd, operation) != 0 {
            guard errno == EINTR else { throw Failure.lockUnavailable(errno) }
        }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
}

 
 
 
 
 
 
 
 
 
 
 
protocol ClashTunnelHandle: AnyObject {
    var isEnabled: Bool { get }
    var status: NEVPNStatus { get }
     
     
    var providerBundleIdentifier: String? { get }
    func start() throws
    func stop()
     
     
     
     
     
    func enable() async throws
     
     
    func disarmOnDemand() async throws -> Bool
}

extension NETunnelProviderManager {
     
     
     
     
     
     
     
     
     
     
     
    func disarmOnDemandForUserStop() -> Bool {
        guard isOnDemandEnabled else { return false }
        isOnDemandEnabled = false
        return true
    }
}

@available(iOS 16.0, *)
extension NETunnelProviderManager: ClashTunnelHandle {
    var status: NEVPNStatus { connection.status }
    var providerBundleIdentifier: String? {
        (protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier
    }
    func start() throws { try connection.startVPNTunnel() }
    func stop() { connection.stopVPNTunnel() }
    func enable() async throws {
        isEnabled = true
        try await saveToPreferences()
        try await loadFromPreferences()
    }
    func disarmOnDemand() async throws -> Bool {
        guard disarmOnDemandForUserStop() else { return false }
        try await saveToPreferences()
        return true
    }
}

@available(iOS 16.0, *)
enum ClashVPNControlDriver {
     
     
    static var loadHandles: () async throws -> [any ClashTunnelHandle] = {
        try await NETunnelProviderManager.loadAllFromPreferences()
    }

     
     
     
     
     
    static var log: (String) -> Void = { line in
        ClashLogStore.shared.append("control: \(line)", stream: .app, level: .warning)
    }

     
     
    static var intentDirectory: () -> URL? = { ReaderTunnelIntent.appGroupDirectory }
     
     
    static var beforeIntentWrite: () -> Void = {}

     
     
     
    static var onDemandSaveDeadline: UInt64 = 3_000_000_000

    private struct OnDemandSaveUnanswered: LocalizedError {
        var errorDescription: String? { let seconds = Double(onDemandSaveDeadline) / 1e9; return "unanswered after \(seconds)s" }
    }

     
    private final class Once<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T, Error>?
        init(_ continuation: CheckedContinuation<T, Error>) { self.continuation = continuation }
        func resume(with result: Result<T, Error>) {
            lock.lock(); let pending = continuation; continuation = nil; lock.unlock()
            pending?.resume(with: result)
        }
    }

     
     
     
    private static func bounded(_ save: @escaping () async throws -> Bool) async throws -> Bool {
        let deadline = onDemandSaveDeadline
        return try await withCheckedThrowingContinuation { continuation in
            let once = Once(continuation)
            let timer = Task {
                try? await Task.sleep(nanoseconds: deadline)
                once.resume(with: .failure(OnDemandSaveUnanswered()))
            }
            Task {
                defer { timer.cancel() }
                do { once.resume(with: .success(try await save())) } catch { once.resume(with: .failure(error)) }
            }
        }
    }

     
     
     
     
     
     
    @discardableResult
    static func apply(connect: Bool) async -> Bool {
         
         
         
        let step = connect ? "start" : "stop"
        #if os(iOS) || os(macOS)
         
         
         
         
         
        do {
            let directory = intentDirectory()
            let seen: UInt64? = connect ? (try ReaderTunnelIntent.last(in: directory)?.generation ?? 0) : nil
            beforeIntentWrite()
            if case .superseded(let newer) = try ReaderTunnelIntent.record(
                connect ? .connect : .stop, basedOn: seen, in: directory), newer.intent == .stop {
                 
                 
                 
                 
                log("\(step): a Stop said meanwhile stands -- not started")
                return true
            }
        } catch {
            log("\(step): reader's word not written  \(describe(error))")
        }
        #endif
        guard let handle = await installed(step) else { return false }
        guard connect else {
             
             
             
             
            do {
                if try await bounded({ try await handle.disarmOnDemand() }) { log("\(step): on demand off") }
            } catch {
                log("\(step): on demand off refused  \(describe(error))")
            }
            handle.stop()
            log("\(step): asked")
            return true
        }
        if !handle.isEnabled {
             
             
            log("\(step): configuration disabled -- enabling")
            do {
                try await handle.enable()
                log("\(step): enabled")
            } catch {
                log("\(step): enabling refused  \(describe(error))")
                return false
            }
        }
        do {
            try handle.start()
            log("\(step): asked")
            return true
        } catch let error as NEVPNError where error.code == .configurationStale {
            log("\(step): \(describe(error)) -- loading again")
            let again = "\(step) again"
            guard let fresh = await installed(again) else { return false }
            do {
                try fresh.start()
                log("\(again): asked")
                return true
            } catch {
                log("\(again): \(describe(error))")
                return false
            }
        } catch {
            log("\(step): \(describe(error))")
            return false
        }
    }

     
     
    static func toggle() async -> Bool? {
        guard let active = await isActive() else { return nil }
        return await apply(connect: !active) ? !active : nil
    }

     
     
     
     
    static func currentStatus() async -> NEVPNStatus? {
        await installed("status", journal: false)?.status
    }

     
     
     
     
    static func providerSession() async -> NETunnelProviderSession? {
        (await installed("session", journal: false) as? NETunnelProviderManager)?.connection as? NETunnelProviderSession
    }

     
     
     
     
     
    static func isActive(journal: Bool = true) async -> Bool? {
        await state(journal: journal)?.active
    }

     
     
     
    static func state(journal: Bool = true) async -> (active: Bool, controllable: Bool)? {
        guard let handle = await installed("read", journal: journal) else { return nil }
        let active: Bool
        switch handle.status {
        case .connected, .connecting, .reasserting: active = true
        case .disconnected, .disconnecting, .invalid: active = false
        @unknown default: active = false
        }
        return (active, handle.isEnabled)
    }

     
     
     
     
     
     
     
    private static func installed(_ step: String, journal: Bool = true) async -> (any ClashTunnelHandle)? {
        let handles: [any ClashTunnelHandle]
        do {
            handles = try await loadHandles()
        } catch {
            log("\(step): load failed  \(describe(error))")
            return nil
        }
        let ours = handles.filter { handle in
            handle.providerBundleIdentifier.map(ClashAppIdentifiers.packetTunnelProviderBundleIDs.contains) ?? false
        }
        let chosen = ours.first(where: { $0.isEnabled }) ?? ours.first
        if journal {
            var line = "\(step): managers=\(handles.count) ours=\(ours.count) enabled=\(ours.filter(\.isEnabled).count)"
            if let chosen { line += " status=\(word(chosen.status))" }
            log(line)
        }
        return chosen
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(error.localizedDescription) [\(nsError.domain)#\(nsError.code)]"
    }

    private static func word(_ status: NEVPNStatus) -> String {
        switch status {
        case .invalid: return "invalid"
        case .disconnected: return "disconnected"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .reasserting: return "reasserting"
        case .disconnecting: return "disconnecting"
        @unknown default: return "unknown(\(status.rawValue))"
        }
    }
}
