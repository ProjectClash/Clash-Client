import AppKit
import Combine
import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
final class ClashMacScriptDriver {
     
    struct Entry: Hashable, Sendable {
        var id: String
        var name: String
    }

    enum Trigger: Equatable, Sendable {
         
        case cron(scheduled: Date)
        case networkChanged
    }

     
    enum Answer: Equatable, Sendable {
        case ran
         
        case busy
    }

     
     
    struct Runner {
        var cronEntries: @MainActor () -> [Entry]
        var networkChangedEntries: @MainActor () -> [Entry]
         
         
        var nextFire: @MainActor (Entry, Date) -> Date?
        var run: @MainActor (Entry, Trigger) async -> Answer
    }

    struct Clock {
        var now: @MainActor () -> Date
        var sleep: @MainActor (TimeInterval) async throws -> Void

        static let system = Clock(
            now: { Date() },
            sleep: { seconds in try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000)) }
        )
    }

     
     
     
     
     
    static let minimumGap: TimeInterval = 60
     
    static let networkSettle: TimeInterval = 2

    private let runner: Runner
    private let paths: AnyPublisher<NetworkPathSnapshot, Never>
    private let tunnelIsConnected: @MainActor () -> Bool
    private let clock: Clock
    private let log: @MainActor (String) -> Void
    private let wakeCenter: NotificationCenter
    private let systemCenter: NotificationCenter

     
    private var anchor: Date?
    private var timer: Task<Void, Never>?
    private var settling: Task<Void, Never>?
    private var latestPath: NetworkPathSnapshot?
    private var pathSubscription: AnyCancellable?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var running: [UUID: Task<Void, Never>] = [:]
     
    private var lastScheduled: [String: Date] = [:]
     
    private var said: Set<String> = []

    init(
        runner: Runner,
        paths: AnyPublisher<NetworkPathSnapshot, Never> = NetworkPathObserver.shared.$snapshot.eraseToAnyPublisher(),
        tunnelIsConnected: @escaping @MainActor () -> Bool,
        clock: Clock = .system,
        wakeCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        systemCenter: NotificationCenter = .default,
        log: @escaping @MainActor (String) -> Void = { ClashLogStore.shared.append($0, stream: .app, level: .info) }
    ) {
        self.runner = runner
        self.paths = paths
        self.tunnelIsConnected = tunnelIsConnected
        self.clock = clock
        self.wakeCenter = wakeCenter
        self.systemCenter = systemCenter
        self.log = log
    }

    var isStarted: Bool { anchor != nil }

    func start() {
        guard anchor == nil else { return }
        anchor = clock.now()
        observe()
        arm()
    }

    func stop() {
        anchor = nil
        timer?.cancel()
        timer = nil
        settling?.cancel()
        settling = nil
        running.values.forEach { $0.cancel() }
        running = [:]
        pathSubscription = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers = []
    }

     
     
     
    func rearm() {
        guard anchor != nil else { return }
        anchor = clock.now()
        arm()
    }

     
     
    func wake() {
        guard anchor != nil else { return }
        arm()
    }

     

    private func arm() {
        timer?.cancel()
        timer = Task { [weak self] in await self?.tick() }
    }

    private func tick() async {
        while !Task.isCancelled {
            let now = clock.now()
            fireDue(at: now)
            guard let next = nextDue() else { return }
            do { try await clock.sleep(next.timeIntervalSince(clock.now())) } catch { return }
        }
    }

    private func fireDue(at now: Date) {
        guard let anchor else { return }
        for entry in runner.cronEntries() {
            guard let first = firstFire(of: entry, after: anchor), first.timeIntervalSince(now) <= 0 else { continue }
            start(entry, trigger: .cron(scheduled: lastFire(of: entry, from: first, upTo: now)))
        }
        self.anchor = now
    }

    private func nextDue() -> Date? {
        guard let anchor else { return nil }
        return runner.cronEntries().compactMap { firstFire(of: $0, after: anchor) }.min()
    }

    private func firstFire(of entry: Entry, after date: Date) -> Date? {
        var after = date
        if let last = lastScheduled[entry.id] {
             
             
            after = max(after, last.addingTimeInterval(Self.minimumGap - 1))
        }
        guard let fire = runner.nextFire(entry, after) else {
            say(#"never:\#(entry.id)"#, #"module script \#(entry.name): its schedule never fires again; not scheduled"#)
            return nil
        }
        return fire
    }

     
     
    private func lastFire(of entry: Entry, from first: Date, upTo now: Date) -> Date {
        var last = first
        for window in [60.0, 3_600, 86_400] {
            if let near = runner.nextFire(entry, now.addingTimeInterval(-window)), near.timeIntervalSince(now) <= 0 {
                if near > last { last = near }
                break
            }
        }
        for _ in 0..<1_000 {
            guard let next = runner.nextFire(entry, last), next.timeIntervalSince(now) <= 0 else { break }
            last = next
        }
        return last
    }

     

    private func start(_ entry: Entry, trigger: Trigger) {
        guard tunnelIsConnected() else {
            say(#"down:\#(entry.id)"#, #"module script \#(entry.name): Clash is not connected, so it did not run"#)
            return
        }
        said.remove(#"down:\#(entry.id)"#)
        if case .cron(let scheduled) = trigger {
            lastScheduled[entry.id] = scheduled
            if let next = runner.nextFire(entry, scheduled), next < scheduled.addingTimeInterval(Self.minimumGap - 1) {
                say(#"dense:\#(entry.id)"#, #"module script \#(entry.name): its schedule fires more than once a minute; it runs at most once a minute"#)
            }
        }
        let id = UUID()
        let runner = runner
        running[id] = Task { [weak self] in
            let answer = await runner.run(entry, trigger)
            guard let self else { return }
            self.running[id] = nil
            if answer == .busy {
                self.say(#"busy:\#(entry.id)"#, #"module script \#(entry.name): still running from an earlier start, so it did not start again"#)
            } else {
                self.said.remove(#"busy:\#(entry.id)"#)
            }
        }
    }

    private func say(_ key: String, _ line: String) {
        guard said.insert(key).inserted else { return }
        log(line)
    }

     

    private struct PathKey: Equatable {
        var status: NetworkPathStatus
        var interface: NetworkPathInterfaceKind
    }

    private func observe() {
        observers.append((wakeCenter, wakeCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.wake() }
        }))
        for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            observers.append((systemCenter, systemCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                     
                    NSTimeZone.resetSystemTimeZone()
                    self?.rearm()
                }
            }))
        }
         
         
         
         
        pathSubscription = paths
            .filter { $0.status != .unknown }
            .removeDuplicates { PathKey(status: $0.status, interface: $0.interface) == PathKey(status: $1.status, interface: $1.interface) }
            .dropFirst()
            .sink { [weak self] path in
                MainActor.assumeIsolated { self?.networkChanged(path) }
            }
    }

    private func networkChanged(_ path: NetworkPathSnapshot) {
        latestPath = path
        settling?.cancel()
        let clock = clock
        settling = Task { [weak self] in
            do { try await clock.sleep(Self.networkSettle) } catch { return }
            self?.networkSettled()
        }
    }

    private func networkSettled() {
        settling = nil
        guard latestPath?.status == .satisfied else { return }
        for entry in runner.networkChangedEntries() {
            start(entry, trigger: .networkChanged)
        }
    }
}
