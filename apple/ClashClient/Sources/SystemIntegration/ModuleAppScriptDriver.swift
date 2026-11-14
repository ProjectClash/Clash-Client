#if os(iOS)
import Combine
import Foundation
import UIKit

extension ModuleAppScriptRunner {
     
     
     
     
    static let shared: ModuleAppScriptRunner = ModuleAppScriptRunner(
        container: ClashAppIdentifiers.appGroupContainer
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("no-app-group", isDirectory: true),
        tunnelIsConnected: { ModuleAppScriptDriver.shared.tunnelIsConnected },
         
        config: ModuleAppScriptCoreAccess.config(),
        dns: ModuleAppScriptCoreAccess.dns(),
        selectPolicy: ModuleAppScriptCoreAccess.selectPolicy()
    )
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
final class ModuleAppScriptDriver {
     
    struct Runner {
         
         
        var load: @MainActor () async -> Void
        var entries: @MainActor (ModuleAppScriptKind) -> [ModuleAppScriptEntry]
         
        var changes: AnyPublisher<Void, Never>
         
         
        var nextFire: @MainActor (ModuleAppScriptEntry, Date) -> Date?
        var run: @MainActor (ModuleAppScriptEntry, ModuleAppScriptTrigger) async -> ModuleAppScriptResult

        @MainActor
        static func of(_ runner: ModuleAppScriptRunner) -> Runner {
            Runner(
                load: { await runner.reload() },
                entries: { runner.entries($0) },
                changes: runner.$entries.dropFirst().removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
                nextFire: { runner.nextFire(of: $0, after: $1) },
                run: { await runner.run($0, trigger: $1) }
            )
        }
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
     
    nonisolated static let checkedKey = #"moduleScripts.cron.checkedUpTo"#
     
    nonisolated static let nextFireKey = #"moduleScripts.cron.nextFire"#

    static let shared: ModuleAppScriptDriver = ModuleAppScriptDriver(
        runner: .of(.shared),
        readTunnel: { await VPNController.readTunnelIsConnected() },
         
        scheduleBackground: { Task.detached(priority: .utility) { BackgroundRefresh.schedule(earliest: BackgroundRefresh.nextEligibility()) } }
    )

     
     
     
    private(set) var tunnelState: Bool?
    var tunnelIsConnected: Bool { tunnelState == true }

    private let runner: Runner
    private let paths: AnyPublisher<NetworkPathSnapshot, Never>
    private let clock: Clock
    private let defaults: UserDefaults
    private let center: NotificationCenter
    private let readTunnel: @MainActor () async -> Bool
    private let scheduleBackground: @MainActor () -> Void
    private let log: @MainActor (String) -> Void

    private var loading: Task<Void, Never>?
    private var isLoaded = false
    private var isForeground = false
    private var timer: Task<Void, Never>?
    private var settling: Task<Void, Never>?
    private var latestPath: NetworkPathSnapshot?
    private var subscriptions: [AnyCancellable] = []
    private var observers: [NSObjectProtocol] = []
    private var running: [UUID: Task<Void, Never>] = [:]
     
    private var lastScheduled: [String: Date] = [:]
     
    private var said: Set<String> = []
     
    private var requestedFire: Date??

     
     
     
     
     
     
     
    init(
        runner: Runner,
        paths: AnyPublisher<NetworkPathSnapshot, Never> = NetworkPathObserver.shared.$snapshot.eraseToAnyPublisher(),
        clock: Clock = .system,
        defaults: UserDefaults = .standard,
        center: NotificationCenter = .default,
        readTunnel: @escaping @MainActor () async -> Bool,
        scheduleBackground: @escaping @MainActor () -> Void = {},
        log: @escaping @MainActor (String) -> Void = { ClashLogStore.shared.append($0, stream: .app, level: .info) }
    ) {
        self.runner = runner
        self.paths = paths
        self.clock = clock
        self.defaults = defaults
        self.center = center
        self.readTunnel = readTunnel
        self.scheduleBackground = scheduleBackground
        self.log = log
    }

     

     
     
    func start() {
        guard loading == nil else { return }
         
         
         
        if storedChecked.map({ $0 > clock.now() }) ?? true { setChecked(clock.now()) }
        observe()
        loading = Task { [weak self] in
            guard let self else { return }
            await self.runner.load()
            self.isLoaded = true
            self.subscriptions.append(self.runner.changes.sink { [weak self] in
                MainActor.assumeIsolated { self?.rearm() }
            })
            if self.isForeground, self.tunnelState != nil { self.arm() }
        }
    }

    func stop() {
        loading?.cancel()
        timer?.cancel()
        timer = nil
        settling?.cancel()
        settling = nil
        running.values.forEach { $0.cancel() }
        running = [:]
        subscriptions = []
        observers.forEach { center.removeObserver($0) }
        observers = []
    }

     
     
     
     
     
    func tunnelStatusChanged(_ status: String) {
        guard status != "idle" else { return }
        let first = tunnelState == nil
        tunnelState = status == "connected"
        if first, isForeground, isLoaded { arm() }
    }

     
     
    func enterForeground() {
        isForeground = true
        if isLoaded, tunnelState != nil { arm() }
    }

     
     
    func enterBackground() {
        isForeground = false
        timer?.cancel()
        timer = nil
        storeNextFire()
         
        let next = Self.storedNextFire(defaults)
        guard requestedFire != .some(next) else { return }
        requestedFire = .some(next)
        scheduleBackground()
    }

     
     
     
     
     
    func runMissedInBackground() async {
        start()
        await loading?.value
        let reading = await readTunnel()
        guard !Task.isCancelled else { return }
        tunnelState = reading
        let started = fireDue(at: clock.now())
        await Self.waitOrGiveUp(started)
        storeNextFire()
    }

     
     
    private static func waitOrGiveUp(_ runs: [Task<Void, Never>]) async {
        guard !runs.isEmpty else { return }
        let gate = Gate()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                gate.wait(continuation)
                Task {
                    for run in runs { await run.value }
                    gate.open()
                }
            }
        } onCancel: {
            runs.forEach { $0.cancel() }
            gate.open()
        }
    }

     
    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var waiter: CheckedContinuation<Void, Never>?
        private var opened = false

        func wait(_ continuation: CheckedContinuation<Void, Never>) {
            lock.lock()
            if opened {
                lock.unlock()
                return continuation.resume()
            }
            waiter = continuation
            lock.unlock()
        }

        func open() {
            lock.lock()
            opened = true
            let waiting = waiter
            waiter = nil
            lock.unlock()
            waiting?.resume()
        }
    }

     
     
     
    func rearm() {
        guard isLoaded else { return }
        setChecked(clock.now())
        if isForeground, tunnelState != nil { arm() } else { storeNextFire() }
    }

     

    private var storedChecked: Date? { defaults.object(forKey: Self.checkedKey) as? Date }

    private func setChecked(_ date: Date) { defaults.set(date, forKey: Self.checkedKey) }

    private func arm() {
        timer?.cancel()
        timer = Task { [weak self] in await self?.tick() }
    }

    private func tick() async {
        while !Task.isCancelled {
            fireDue(at: clock.now())
            storeNextFire()
            guard let next = nextDue() else { return }
            do { try await clock.sleep(next.timeIntervalSince(clock.now())) } catch { return }
        }
    }

    @discardableResult
    private func fireDue(at now: Date) -> [Task<Void, Never>] {
        let checked = storedChecked ?? now
        var started: [Task<Void, Never>] = []
        for entry in runner.entries(.cron) {
            guard let first = firstFire(of: entry, after: checked), first.timeIntervalSince(now) <= 0 else { continue }
            if let task = start(entry, trigger: .cron(scheduled: lastFire(of: entry, from: first, upTo: now))) {
                started.append(task)
            }
        }
        setChecked(now)
        return started
    }

    private func nextDue() -> Date? {
        let checked = storedChecked ?? clock.now()
        return runner.entries(.cron).compactMap { firstFire(of: $0, after: checked) }.min()
    }

     
     
    private func storeNextFire() {
        if tunnelIsConnected, let next = nextDue() {
            defaults.set(next, forKey: Self.nextFireKey)
        } else {
            defaults.removeObject(forKey: Self.nextFireKey)
        }
    }

     
     
    nonisolated static func storedNextFire(_ defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: nextFireKey) as? Date
    }

    private func firstFire(of entry: ModuleAppScriptEntry, after date: Date) -> Date? {
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

     
     
    private func lastFire(of entry: ModuleAppScriptEntry, from first: Date, upTo now: Date) -> Date {
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

     

    @discardableResult
    private func start(_ entry: ModuleAppScriptEntry, trigger: ModuleAppScriptTrigger) -> Task<Void, Never>? {
        guard tunnelIsConnected else {
            say(#"down:\#(entry.id)"#, #"module script \#(entry.name): Clash is not connected, so it did not run"#)
            return nil
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
        let task = Task { [weak self] in
            let result = await runner.run(entry, trigger)
            guard let self else { return }
            self.running[id] = nil
            if result.outcome == .notRun(.busy) {
                self.say(#"busy:\#(entry.id)"#, #"module script \#(entry.name): still running from an earlier start, so it did not start again"#)
            } else {
                self.said.remove(#"busy:\#(entry.id)"#)
            }
        }
        running[id] = task
        return task
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
        let notices: [(Notification.Name, @MainActor (ModuleAppScriptDriver) -> Void)] = [
            (UIApplication.didBecomeActiveNotification, { $0.enterForeground() }),
            (UIApplication.didEnterBackgroundNotification, { $0.enterBackground() }),
            (.NSSystemClockDidChange, { $0.rearm() }),
            (.NSSystemTimeZoneDidChange, { driver in
                 
                NSTimeZone.resetSystemTimeZone()
                driver.rearm()
            }),
        ]
        for (name, act) in notices {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    act(self)
                }
            })
        }
         
         
         
        subscriptions.append(paths
            .filter { $0.status != .unknown }
            .removeDuplicates { PathKey(status: $0.status, interface: $0.interface) == PathKey(status: $1.status, interface: $1.interface) }
            .dropFirst()
            .sink { [weak self] path in
                MainActor.assumeIsolated { self?.networkChanged(path) }
            })
    }

    private func networkChanged(_ path: NetworkPathSnapshot) {
        latestPath = path
        settling?.cancel()
        let clock = clock
        settling = Task { [weak self] in
            do { try await clock.sleep(Self.networkSettle) } catch { return }
             
            guard !Task.isCancelled else { return }
            self?.networkSettled()
        }
    }

    private func networkSettled() {
        settling = nil
        guard latestPath?.status == .satisfied else { return }
        for entry in runner.entries(.networkChanged) {
            start(entry, trigger: .networkChanged)
        }
    }
}
#endif
