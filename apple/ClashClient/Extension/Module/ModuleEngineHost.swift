#if os(iOS) || os(macOS)
import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 

 
protocol ModuleTunnelHooks: AnyObject {
     
    func willRun(_ revision: ModuleRunningRevision?)
     
    func didRun(_ revision: ModuleRunningRevision?)
}

 
 
 
 
 
 
enum ModuleReinjectCheck {
    enum Outcome: Equatable, Sendable {
        case answers
         
        case needsAuthentication(String)
        case silent(String)
    }

    static func run(port: UInt16, queue: DispatchQueue, timeout: TimeInterval = 2,
                    authorization: ModuleReinjectAuthorization? = nil, completion: @escaping (Outcome) -> Void) {
        ModuleReinject.open(port: port, queue: queue, timeout: timeout) { opened in
            let stream: ModuleStream
            switch opened {
            case .success(let connected): stream = connected
            case .failure(let failure): return completion(.silent("\(failure)"))
            }
             
             
            var pending: ((Outcome) -> Void)? = completion
            var deadline: ModuleDeadline?
            let settle: (Outcome) -> Void = { outcome in
                guard let done = pending else { return }
                pending = nil
                deadline?.cancel()
                deadline = nil
                stream.cancel()
                done(outcome)
            }
            deadline = ModuleDeadline(after: timeout, queue: queue) { settle(.silent("no answer within \(timeout) s")) }
             
            let greeting: [UInt8] = authorization == nil ? [0x05, 0x01, 0x00] : [0x05, 0x02, 0x00, 0x02]
            stream.send(Data(greeting)) { error in
                if let error { settle(.silent("\(error)")) }
            }
            readExactly(stream, 2) { answer in
                guard let answer, answer[0] == 0x05 else { return settle(.silent("no SOCKS5 answer")) }
                switch answer[1] {
                case 0x00:
                    settle(.answers)
                case 0x02:
                    guard let authorization else {
                        return settle(.needsAuthentication("it asks for authentication, and this configuration's plan names no credentials"))
                    }
                    guard let request = signIn(authorization) else {
                        return settle(.needsAuthentication("this configuration's credentials are longer than a SOCKS5 sign-in takes"))
                    }
                    stream.send(request) { error in
                        if let error { settle(.silent("\(error)")) }
                    }
                    readExactly(stream, 2) { reply in
                        guard let reply else { return settle(.silent("no answer to the sign-in")) }
                        settle(reply[1] == 0x00 ? .answers : .needsAuthentication("it refuses this configuration's credentials"))
                    }
                default:
                    settle(.needsAuthentication("it accepts none of the offered authentication methods (answered \(answer[1]))"))
                }
            }
        }
    }

     
    private static func signIn(_ authorization: ModuleReinjectAuthorization) -> Data? {
        let user = Array(authorization.username.utf8), password = Array(authorization.password.utf8)
        guard (1...255).contains(user.count), (1...255).contains(password.count) else { return nil }
        return Data([0x01, UInt8(user.count)] + user + [UInt8(password.count)] + password)
    }

     
    private static func readExactly(_ stream: ModuleStream, _ count: Int, _ buffer: [UInt8] = [],
                                    _ done: @escaping ([UInt8]?) -> Void) {
        stream.receive(maximumLength: count - buffer.count) { data, isComplete, error in
            let buffer = buffer + [UInt8](data ?? Data())
            if buffer.count >= count { return done(Array(buffer.prefix(count))) }
            if error != nil || isComplete { return done(nil) }
            readExactly(stream, count, buffer, done)
        }
    }
}

 
final class ModuleEngineReporter {
    static let counterInterval: TimeInterval = 10

    private let locations: ModuleEngineLocations
    private let queue: DispatchQueue
     
    let now: () -> Date
    private let signal: () -> Void
    private let flushInterval: TimeInterval
    private(set) var report: ModuleEngineReport
    private var flushPending = false

    init(locations: ModuleEngineLocations, queue: DispatchQueue, now: @escaping () -> Date,
         signal: @escaping () -> Void, flushInterval: TimeInterval = ModuleEngineReporter.counterInterval) {
        self.locations = locations
        self.queue = queue
        self.now = now
        self.signal = signal
        self.flushInterval = flushInterval
        report = .initial(startedAt: now(), carrying: ModuleEngineReport.load(locations))
    }

     
     
     
    func record(_ change: (inout ModuleEngineReport) -> Void) {
        dispatchPrecondition(condition: .onQueue(queue))
        let before = (report.state, report.failure, report.rung, report.omittedModules)
        change(&report)
        write()
        if before != (report.state, report.failure, report.rung, report.omittedModules) { signal() }
    }

     
     
    func note(_ change: (inout ModuleEngineReport) -> Void) {
        dispatchPrecondition(condition: .onQueue(queue))
        change(&report)
        guard !flushPending else { return }
        flushPending = true
        queue.asyncAfter(deadline: .now() + flushInterval) { [weak self] in
            guard let self else { return }
            self.flushPending = false
            self.write()
        }
    }

    private func write() {
        report.updatedAt = now()
        guard let data = try? ModuleJSON.encoder().encode(report) else { return }
        try? ModuleEngineFiles.write(data, to: locations.engineReport)
    }
}

 
 
struct ModuleEngineInputs: Equatable, Sendable {
     
    let entry: ModuleEnginePlan.Entry
     
     
     
    let modules: [ModulePublishedModule]
     
     
    var room: Int64? = nil
}

final class ModuleEngineHost: ModuleTunnelHooks {
     
    static let moduleRereadSpacing: TimeInterval = 0.5

    private struct Running {
        var entry: ModuleEnginePlan.Entry
        let engine: ModuleEngine
    }

     
     
     
    private struct Announced {
        let revision: ModuleRunningRevision?
        let entry: ModuleEnginePlan.Entry?
        var planProblem: String? = nil
    }

    let locations: ModuleEngineLocations
    let queue: DispatchQueue
    private let log: ModuleEngineLog
    private let now: () -> Date
    private let signal: () -> Void
    private let checkAttempts: Int
     
     
    private let checkSpacing: TimeInterval
    private let checkTimeout: TimeInterval
    private let moduleRereadSpacing: TimeInterval
     
     
    private let scripts: ModuleScriptRunning
    private let runnerGiven: Bool
     
     
     
     
     
     
     
    private let configure: (ModuleEngine, ModuleEngineInputs, ModuleEngineReporter, ModuleScriptRunning) -> Void
     
     
    private let lock = NSLock()
     
    private var running: Running?
     
     
     
    private var pending: Running?
    private var madeReporter: ModuleEngineReporter?
    private var announced: Announced?
     
    private var stops = 0
     
     
     
    private var heldBindFailure: (entry: ModuleEnginePlan.Entry, failure: ModuleEngineReport.Failure)?
     
    private var activeOnQueue: ModuleEngine?
     
     
     
    private var entryOnQueue: ModuleEnginePlan.Entry?
    private var reporterOnQueue: ModuleEngineReporter?
    private var watch: ModuleWatch?
    private weak var watchedEngine: ModuleEngine?
    private let modulesSignal: String
     
    private let modulesCoalescing: TimeInterval?
     
    private var configurationOnQueue = 0
     
     
    private var checkGeneration = 0
     
     
    private let listenerRebinds: Int
     
     
     
     
     
     
     
#if os(iOS)
    static let rulesOnDemandHere = true
#else
    static let rulesOnDemandHere = false
#endif
    static let idleReleaseHere: TimeInterval = 60
    static let rebindSpacing: TimeInterval = 10
    static let listenerFailureLimit = 3
    static let listenerFailureWindow: TimeInterval = 60
    private let rebindSpacing: TimeInterval
    private let listenerFailureLimit: Int
    private let listenerFailureWindow: TimeInterval
     
     
     
     
    private let carriesEngineProxy: ((ModuleRunningRevision) -> Bool)?
     
     
     
     
     
    private let rulesOnDemand: Bool
    private let idleRelease: TimeInterval?
     
     
     
    private let checkWithoutRules: ((ModuleEngine, ModuleEnginePlan.Entry, ModuleEngineReporter) -> Void)?
     
    private var demandedAt: Date?
     
     
    private weak var builtOnQueue: ModuleEngine?
    private weak var demandedOnQueue: ModuleEngine?
     
     
    private let readPlan: (ModuleRunningRevision, ModuleEngineLocations) -> ModuleEnginePlan.Lookup
     
     
    private let headroom: () -> Int64?
     
     
     
    private var heldKeptOnQueue = 0
     
     
    private var heldRoomOnQueue: Int64 = 0
     
     
    private var leftAtReadOnQueue: Int64?

     
    private func heldInForce(_ engine: ModuleEngine) -> Int64 {
        guard builtOnQueue === engine, !engine.passThroughCauses.contains(.memory) else { return 0 }
        return ModuleEngineBudget.programHeld(keptRuleBytes: heldKeptOnQueue, compiledRegexes: 0) + heldRoomOnQueue
    }
     
     
     
     
    static let shareRetryDelays: [TimeInterval] = [15, 30, 60, 120, 240]
    private let shareRetryDelays: [TimeInterval]
     
     
    private var shareRetries = 0
     
     
     
     
     
     
     
     
     
     
     
     
     
    enum ReadCause { case readersAct, connection, readAgain, memoryStopEnded }
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static let memoryStopRetryCooldown: TimeInterval = 600
    private let memoryStopRetryCooldown: TimeInterval
     
     
     
     
    private let uptime: () -> TimeInterval
     
     
    private var memoryStopEndedAt: TimeInterval?
    private var memoryStopGaveReadsAgainAt: TimeInterval?
     
     
    private var readersActUnread = false

    init(locations: ModuleEngineLocations, log: ModuleEngineLog,
         queue: DispatchQueue = DispatchQueue(label: "modules.engine"), now: @escaping () -> Date = Date.init,
         signal: @escaping () -> Void = ModuleEngineSignal.post, checkAttempts: Int = 5, checkSpacing: TimeInterval = 0.25,
         modulesSignal: String = ModuleEngineSignal.modulesChanged,
         modulesCoalescing: TimeInterval? = ModuleWatch.coalescing,
         checkTimeout: TimeInterval = 2, moduleRereadSpacing: TimeInterval = ModuleEngineHost.moduleRereadSpacing,
         scripts: ModuleScriptRunning? = nil, listenerRebinds: Int = 1,
         rebindSpacing: TimeInterval = ModuleEngineHost.rebindSpacing,
         listenerFailureLimit: Int = ModuleEngineHost.listenerFailureLimit,
         listenerFailureWindow: TimeInterval = ModuleEngineHost.listenerFailureWindow,
         carriesEngineProxy: ((ModuleRunningRevision) -> Bool)? = nil,
         rulesOnDemand: Bool = false, idleRelease: TimeInterval? = nil,
         checkWithoutRules: ((ModuleEngine, ModuleEnginePlan.Entry, ModuleEngineReporter) -> Void)? = nil,
         readPlan: @escaping (ModuleRunningRevision, ModuleEngineLocations) -> ModuleEnginePlan.Lookup
             = ModuleEnginePlan.entry(for:locations:),
         headroom: @escaping () -> Int64? = { ModuleEngineBudget.headroomForShare() },
         shareRetryDelays: [TimeInterval] = ModuleEngineHost.shareRetryDelays,
         memoryStopRetryCooldown: TimeInterval = ModuleEngineHost.memoryStopRetryCooldown,
         uptime: @escaping () -> TimeInterval = { TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000 },
         configure: @escaping (ModuleEngine, ModuleEngineInputs, ModuleEngineReporter, ModuleScriptRunning) -> Void
             = { _, _, _, _ in }) {
        self.locations = locations
        self.log = log
        self.queue = queue
        self.now = now
        self.signal = signal
        self.checkAttempts = checkAttempts
        self.checkSpacing = checkSpacing
        self.modulesSignal = modulesSignal
        self.modulesCoalescing = modulesCoalescing
        self.checkTimeout = checkTimeout
        self.moduleRereadSpacing = moduleRereadSpacing
        self.scripts = scripts ?? ModuleNoScripts()
        self.runnerGiven = scripts != nil
        self.listenerRebinds = max(0, listenerRebinds)
        self.rebindSpacing = max(0, rebindSpacing)
        self.listenerFailureLimit = max(1, listenerFailureLimit)
        self.listenerFailureWindow = max(0, listenerFailureWindow)
        self.carriesEngineProxy = carriesEngineProxy
        self.rulesOnDemand = rulesOnDemand
        self.idleRelease = rulesOnDemand ? idleRelease : nil
        self.checkWithoutRules = checkWithoutRules
        self.readPlan = readPlan
        self.headroom = headroom
        self.shareRetryDelays = shareRetryDelays
        self.memoryStopRetryCooldown = max(0, memoryStopRetryCooldown)
        self.uptime = uptime
        self.configure = configure
    }

     
    var engine: ModuleEngine? { lock.lock(); defer { lock.unlock() }; return (running ?? pending)?.engine }
     
    var runningRevision: ModuleRunningRevision? { lock.lock(); defer { lock.unlock() }; return running?.entry.revision }
    var reporter: ModuleEngineReporter? { lock.lock(); defer { lock.unlock() }; return madeReporter }

     
     
     
     
    func willRun(_ revision: ModuleRunningRevision?) {
        announce(revision, unlessStoppedSince: nil)
    }

     
     
     
    private func announce(_ revision: ModuleRunningRevision?, unlessStoppedSince stopsBefore: Int?) {
         
         
         
        lock.lock()
        var entry = running.flatMap { $0.entry.revision == revision && $0.engine.isListening ? $0.entry : nil }
        lock.unlock()
        var planProblem: String?
         
         
        if entry == nil, let revision, FileManager.default.fileExists(atPath: locations.enginePlans.path) {
            switch readPlan(revision, locations) {
            case .entry(let found): entry = found
            case .unreadable(let why): planProblem = why
            case .notRecorded:
                planProblem = "no engine plan names \(revision.profileID)/\(revision.revision)"
            case .noPlan: break
            }
        }
        lock.lock()
        defer { lock.unlock() }
        if let stopsBefore, stops != stopsBefore { return }
        announced = Announced(revision: revision, entry: entry, planProblem: planProblem)
        heldBindFailure = nil
        guard let entry else { return letPendingGoLocked("the next configuration carries no modules") }
         
        if let current = running, current.entry.assignment.ports.engine == entry.assignment.ports.engine,
           current.engine.isListening {
             
             
             
            let announcedPair = ModuleEngineSettings(entry.assignment).engineProxyCredentials
            queue.sync { current.engine.alsoAcceptedEngineProxyCredentials = announcedPair }
            return letPendingGoLocked("the next configuration keeps the running listener")
        }
        if var waiting = pending, waiting.entry.assignment.ports.engine == entry.assignment.ports.engine,
           waiting.engine.isListening {
             
             
             
            waiting.entry = entry
            pending = waiting
            let nothingRuns = running == nil
            let reporter = madeReporter
            queue.sync {
                waiting.engine.update(settings: ModuleEngineSettings(entry.assignment),
                                      certificatePage: waiting.engine.certificatePage)
                if nothingRuns {
                    reporter?.record {
                        $0.revision = entry.revision
                        $0.ports = entry.assignment.ports
                    }
                }
            }
            return
        }
        letPendingGoLocked("the next configuration has another engine port")
        bindLocked(entry)
    }

     
     
     
    func didRun(_ revision: ModuleRunningRevision?) {
         
         
         
         
        lock.lock()
        let followed = announced.map { $0.revision == revision } ?? false
         
        let stopsBefore = stops
        var keptRunning = false
        if !followed, let revision, let current = running, current.entry.revision == revision, current.engine.isListening {
             
             
             
             
            announced = Announced(revision: revision, entry: current.entry)
            heldBindFailure = nil
            letPendingGoLocked("the core runs the configuration that already ran")
            keptRunning = true
        }
        lock.unlock()
        if !followed, !keptRunning { announce(revision, unlessStoppedSince: stopsBefore) }
        lock.lock()
        let problem = announced?.entry == nil ? announced?.planProblem : nil
        lock.unlock()
         
         
        let carries = problem != nil && revision.flatMap { revision in carriesEngineProxy?(revision) } == true
        lock.lock()
        guard stops == stopsBefore else {
            lock.unlock()
            return log.say("the connection stopped while its configuration was being looked at: nothing more is done for it")
        }
        guard let entry = announced?.entry, let reporter = madeReporter else {
            if let problem, carries, let revision {
                 
                 
                log.say("engine plan unusable for \(revision.profileID)/\(revision.revision), whose configuration routes to the engine: \(problem); modules is off until the next configuration")
                stopAllLocked(saying: "this configuration's engine plan cannot be used", revision: revision)
                reportPlanProblemLocked(revision, problem)
            } else {
                stopAllLocked(saying: revision == nil ? "nothing runs" : "this configuration carries no modules", revision: revision)
            }
            lock.unlock()
            return
        }
        if let waiting = pending, waiting.entry.assignment.ports.engine == entry.assignment.ports.engine {
            pending = nil
            heldBindFailure = nil
            stopRunningLocked(saying: "the configuration it served no longer runs")
            running = Running(entry: entry, engine: waiting.engine)
            queue.sync { waiting.engine.alsoAcceptedEngineProxyCredentials = nil }
            promoteLocked(waiting.engine, entry, reporter)
        } else if var current = running, current.entry.assignment.ports.engine == entry.assignment.ports.engine,
                  current.engine.isListening {
             
            let changed = current.entry != entry
            let page = changed ? ModuleCertificatePage.load(locations) : nil
            current.entry = entry
            running = current
            heldBindFailure = nil
            queue.sync {
                if changed {
                     
                     
                     
                     
                     
                    configurationOnQueue += 1
                    current.engine.update(settings: ModuleEngineSettings(entry.assignment), certificatePage: page)
                     
                     
                    if watchedEngine === current.engine { entryOnQueue = entry }
                }
                 
                current.engine.alsoAcceptedEngineProxyCredentials = nil
                 
                 
                checkGeneration += 1
                 
                if changed || reporter.report.revision != entry.revision || reporter.report.ports != entry.assignment.ports {
                    reporter.record {
                        $0.revision = entry.revision
                        $0.ports = entry.assignment.ports
                         
                         
                        if changed { $0.omittedModules = [] }
                    }
                }
            }
            if changed { scheduleConfiguration(current.engine, entry, reporter) }
        } else {
             
             
             
            let held = heldBindFailure.flatMap { $0.entry.revision == entry.revision ? $0 : nil }
            heldBindFailure = nil
            letPendingGoLocked("the configuration that runs has no listener")
            stopRunningLocked(saying: "the configuration it served no longer runs")
            if let held {
                queue.sync {
                    reporter.record {
                        $0.revision = held.entry.revision
                        $0.ports = held.entry.assignment.ports
                        $0.state = .failed
                        $0.failure = held.failure
                    }
                }
            }
            lock.unlock()
            return
        }
        let current = running
        lock.unlock()
        if let current { startCheck(current, reporter) }
    }

     
    func tunnelStopped() {
        lock.lock()
        defer { lock.unlock() }
        stops += 1
        stopAllLocked(saying: "the connection stopped")
         
         
         
         
         
         
        if let reporter = madeReporter {
            queue.sync { reporter.record { $0.counters = ModuleEngineCounters() } }
        }
         
         
         
    }

     

     
    private func reportPlanProblemLocked(_ revision: ModuleRunningRevision, _ problem: String) {
        let reporter = madeReporter ?? ModuleEngineReporter(locations: locations, queue: queue, now: now, signal: signal)
        madeReporter = reporter
        queue.sync {
            reporter.record {
                $0.revision = revision
                $0.ports = nil
                $0.state = .failed
                $0.failure = .planUnreadable(reason: problem)
                $0.omittedModules = []
            }
        }
    }

     
     
    private func listenerFailed(_ engine: ModuleEngine, _ reason: String) {
        DispatchQueue.global(qos: .utility).async { [weak self, weak engine] in
            guard let self, let engine else { return }
            self.rebind(engine, reason)
        }
    }

     
     
     
    private func rebind(_ engine: ModuleEngine, _ reason: String) {
        lock.lock()
        defer { lock.unlock() }
        let isRunning = running?.engine === engine
        guard let current = isRunning ? running : (pending?.engine === engine ? pending : nil) else { return }
        let port = current.entry.assignment.ports.engine
        let reporter = madeReporter
        let says = isRunning || running == nil
        log.say("engine on 127.0.0.1:\(port) stopped listening: \(reason)")
        if says {
            queue.sync {
                reporter?.record {
                    $0.revision = current.entry.revision
                    $0.ports = current.entry.assignment.ports
                    $0.state = .failed
                    $0.failure = .bindFailed(port: port, reason: "the listener stopped: \(reason)")
                }
            }
        }
         
         
         
        if isRunning { queue.sync { checkGeneration += 1 } }
        if isRunning, let waiting = pending, waiting.entry.assignment.ports.engine == port {
            return log.say("engine on 127.0.0.1:\(port) is not bound again: the next configuration's listener holds the port")
        }
         
         
         
        switch engine.noteListenerFailure(at: ModuleEngine.monotonicNow(), limit: listenerRebinds, spacing: rebindSpacing,
                                          failureLimit: listenerFailureLimit, failureWindow: listenerFailureWindow) {
        case .never(let why):
            log.say("engine on 127.0.0.1:\(port) is not bound again: \(why); it stays down until the next configuration")
            if says {
                queue.sync {
                    reporter?.record {
                        $0.failure = .bindFailed(port: port, reason: "the listener stopped (\(reason)) and is not bound again: \(why); it stays down until the next configuration")
                    }
                }
            }
        case .after(let wait):
            log.say("engine on 127.0.0.1:\(port) is bound again in \(String(format: "%.1f", wait)) s (rebinds are \(Int(rebindSpacing)) s apart)")
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + wait) { [weak self, weak engine] in
                guard let self, let engine else { return }
                self.lock.lock()
                defer { self.lock.unlock() }
                self.relistenLocked(engine, reason)
            }
        case .now:
            relistenLocked(engine, reason)
        }
    }

     
     
    private func relistenLocked(_ engine: ModuleEngine, _ reason: String) {
        let isRunning = running?.engine === engine
        guard let current = isRunning ? running : (pending?.engine === engine ? pending : nil), !engine.isListening else { return }
        let port = current.entry.assignment.ports.engine
         
         
        if isRunning, let waiting = pending, waiting.entry.assignment.ports.engine == port {
            return log.say("engine on 127.0.0.1:\(port) is not bound again: the next configuration's listener holds the port")
        }
        let reporter = madeReporter
        let says = isRunning || running == nil
        engine.noteRebind(at: ModuleEngine.monotonicNow())
        do {
            _ = try engine.relisten()
            log.say("engine listening again on 127.0.0.1:\(port)")
        } catch {
            log.say("engine could not listen again on 127.0.0.1:\(port): \(error)")
            if says {
                queue.sync {
                    reporter?.record { $0.failure = .bindFailed(port: port, reason: "the listener stopped (\(reason)) and could not be bound again: \(error)") }
                }
            }
            return
        }
        if isRunning, let reporter { startCheck(current, reporter) }
    }

    private func bindLocked(_ entry: ModuleEnginePlan.Entry) {
        let reporter = madeReporter ?? ModuleEngineReporter(locations: locations, queue: queue, now: now, signal: signal)
        madeReporter = reporter
        let settings = ModuleEngineSettings(entry.assignment)
        let engine = ModuleEngine(settings: settings, certificatePage: ModuleCertificatePage.load(locations), log: log, queue: queue)
        let nothingRuns = running == nil
        do {
            let port = try engine.start()
            log.say("engine listening on 127.0.0.1:\(port) -> \(settings.reinjectPort) for \(entry.revision.profileID)/\(entry.revision.revision), \(entry.assignment.modules.count) modules, \(settings.decryptsTLS ? "decrypting" : "certificate page and plain HTTP only")\(nothingRuns ? "" : "; it takes over when the core runs that configuration")")
            if !runnerGiven { log.say("scripts are skipped this run: no script runner is part of this build") }
            pending = Running(entry: entry, engine: engine)
            let now = self.now
            queue.sync {
                engine.onCertificateHandedOut = { [weak reporter] fingerprint in
                    reporter?.record { $0.certificateServedAt[fingerprint] = now() }
                }
                engine.onListenerFailure = { [weak self, weak engine] reason in
                    guard let self, let engine else { return }
                    self.listenerFailed(engine, reason)
                }
                 
                if reporter.report.rung >= .engineStopped { engine.passThroughCauses.insert(.memory) }
                 
                if nothingRuns {
                    reporter.record {
                        $0.revision = entry.revision
                        $0.ports = entry.assignment.ports
                        $0.state = .starting
                        $0.failure = nil
                    }
                }
            }
        } catch {
            log.say("engine could not listen on 127.0.0.1:\(settings.listenPort): \(error)")
            let failure = ModuleEngineReport.Failure.bindFailed(port: settings.listenPort, reason: "\(error)")
            guard nothingRuns else {
                 
                 
                 
                heldBindFailure = (entry, failure)
                return
            }
            queue.sync {
                reporter.record {
                    $0.revision = entry.revision
                    $0.ports = entry.assignment.ports
                    $0.state = .failed
                    $0.failure = failure
                }
            }
        }
    }

     
     
    private func promoteLocked(_ engine: ModuleEngine, _ entry: ModuleEnginePlan.Entry, _ reporter: ModuleEngineReporter) {
        let settings = ModuleEngineSettings(entry.assignment)
        queue.sync {
            if engine.settings != settings {
                 
                engine.update(settings: settings, certificatePage: engine.certificatePage)
            }
            activeOnQueue = engine
            checkGeneration += 1
            if reporter.report.rung >= .engineStopped { engine.passThroughCauses.insert(.memory) }
             
             
            engine.metrics.update { $0.carryTheRun(from: reporter.report.counters) }
            engine.metrics.onChange = { [weak reporter, weak engine] in
                guard let reporter, let engine else { return }
                reporter.note { $0.counters = engine.metrics.counters }
            }
            reporter.record {
                $0.revision = entry.revision
                $0.ports = entry.assignment.ports
                $0.state = .starting
                $0.failure = nil
                 
                $0.omittedModules = []
            }
        }
        scheduleConfiguration(engine, entry, reporter)
    }

    private func letPendingGoLocked(_ why: String) {
        guard let waiting = pending else { return }
        pending = nil
        waiting.engine.stop()
        log.say("engine on 127.0.0.1:\(waiting.entry.assignment.ports.engine) let go: \(why)")
    }

    private func stopRunningLocked(saying why: String) {
        guard let current = running else { return }
        running = nil
        current.engine.stop()
        log.say("engine stopped: \(why)")
        queue.sync {
            if activeOnQueue === current.engine { activeOnQueue = nil }
            if builtOnQueue === current.engine { builtOnQueue = nil }
            if demandedOnQueue === current.engine { demandedOnQueue = nil }
             
            configurationOnQueue += 1
            checkGeneration += 1
            if watchedEngine === current.engine || activeOnQueue == nil { stopWatching() }
        }
    }

     
     
     
     
     
    private func stopAllLocked(saying why: String, revision: ModuleRunningRevision? = nil) {
        heldBindFailure = nil
        letPendingGoLocked(why)
        stopRunningLocked(saying: why)
        guard let reporter = madeReporter else { return }
        queue.sync {
            activeOnQueue = nil
            configurationOnQueue += 1
            checkGeneration += 1
            stopWatching()
            reporter.record {
                $0.state = .stopped
                if let revision {
                    $0.revision = revision
                    $0.ports = nil
                    $0.failure = nil
                     
                    $0.omittedModules = []
                }
            }
        }
    }

     
     
    private func scheduleConfiguration(_ engine: ModuleEngine, _ entry: ModuleEnginePlan.Entry,
                                       _ reporter: ModuleEngineReporter) {
        queue.async { [weak self] in self?.configureOnQueue(engine, entry, reporter) }
    }

     

     
     
     
    private func configureOnQueue(_ engine: ModuleEngine, _ entry: ModuleEnginePlan.Entry,
                                  _ reporter: ModuleEngineReporter, settling: Bool = true, demanded: Bool = false,
                                  cause: ReadCause = .readersAct) {
        guard activeOnQueue === engine else { return }
        let entry = watching(engine, entry, reporter, settling: settling)
        configurationOnQueue += 1
        if cause == .memoryStopEnded { memoryStopEndedAt = uptime() }
        if demanded { demandedOnQueue = engine }
        if rulesOnDemand, !demanded, builtOnQueue !== engine, demandedOnQueue !== engine {
             
             
             
             
            if cause == .readersAct { readersActUnread = true }
            awaitRules(engine)
            checkWithoutRules?(engine, entry, reporter)
            return log.say("the modules are read at the first connection that needs them")
        }
        giveReadsAgain(to: cause)
        let generation = configurationOnQueue
         
         
         
         
         
         
        let lists = ModuleEngineBudget.listsHeld(entry.assignment)
        let held = heldInForce(engine)
        let left = headroom()
        leftAtReadOnQueue = left
        let ruleBytes = ModuleEngineBudget.ruleBytes(headroom: left, holding: held)
         
         
        let room = { (kept: Int) in ModuleEngineBudget.programRoom(headroom: left, holding: held, keptRuleBytes: kept) }
        if ruleBytes < ModuleReader.maximumRuleBytes, !entry.assignment.modules.isEmpty, let left {
            log.say(String(format: "%.2f MiB are left now (the host lists' %.2f MiB among what is held, a program of %.2f MiB to be replaced): the modules may keep %d bytes of rules together",
                           Double(left) / 1_048_576, Double(lists) / 1_048_576, Double(held) / 1_048_576, ruleBytes))
        }
        ModuleReader.read(
            entry.assignment.modules, locations: locations, queue: queue, spacing: moduleRereadSpacing, ruleBytes: ruleBytes,
            isCurrent: { [weak self, weak engine] in
                guard let self, let engine else { return false }
                return self.configurationOnQueue == generation && self.activeOnQueue === engine
            },
            completion: { [weak self, weak engine] reading in
                guard let self, let engine else { return }
                self.finishConfiguration(engine, entry, reporter, reading, room: room)
            })
    }

    private func finishConfiguration(_ engine: ModuleEngine, _ entry: ModuleEnginePlan.Entry,
                                     _ reporter: ModuleEngineReporter, _ reading: ModuleReading,
                                     room: (Int) -> Int64?) {
        if let problem = reading.listProblem {
            log.say("\(problem): the modules are checked against the digests this configuration was published with")
        }
        for module in reading.unlisted {
            log.say("module \(module.name) (\(module.id)) is no longer on the module list: its rewrites are off until the next configuration")
        }
        for omitted in reading.omitted {
            log.say("module \(omitted.name) (\(omitted.id)) is left out this run after \(reading.reads) reads: \(omitted.detail)")
        }
        if reporter.report.omittedModules != reading.omitted {
            reporter.record { $0.omittedModules = reading.omitted }
        }
         
         
         
        if reporter.report.rung >= .engineStopped { engine.passThroughCauses.insert(.memory) }
         
         
         
        let kept = reading.modules.reduce(0) { $0 + $1.keptBytes }
        let given = room(kept)
        configure(engine, ModuleEngineInputs(entry: entry, modules: reading.modules, room: given), reporter, scripts)
        let stopped = engine.passThroughCauses.contains(.memory)
        heldKeptOnQueue = stopped ? 0 : kept
        heldRoomOnQueue = stopped ? 0 : (engine.interceptor as? ModuleInterceptor)?.services.program.roomTaken ?? 0
         
         
        let program = (engine.interceptor as? ModuleInterceptor)?.services.program
        if Self.readsAgainForMemory(omitted: reading.omitted, room: given,
                                     rulesLeftOut: program.map { $0.rewriteMetrics.overBudget + $0.scriptMetrics.overBudget } ?? 0) {
            let modulesHeldOut = reading.omitted.contains { $0.reason == .overBudget || $0.reason == .overSharedBudget }
            readAgainAsMemoryAllows(engine, entry, onlyRules: !modulesHeldOut)
        }
        if rulesOnDemand {
            builtOnQueue = engine
            if demandedOnQueue === engine { demandedOnQueue = nil }
            if let began = demandedAt {
                log.say("the rules a connection asked for were built in \(Int(now().timeIntervalSince(began) * 1000)) ms")
                demandedAt = nil
            }
            engine.rulesReady()
        }
    }

     
    private func giveReadsAgain(to cause: ReadCause) {
        let readersAct: Bool
        switch cause {
        case .readAgain: return
        case .readersAct: readersAct = true
        case .connection: readersAct = readersActUnread
        case .memoryStopEnded: readersAct = false
        }
        readersActUnread = false
        let at = uptime()
        if !readersAct, let ended = memoryStopEndedAt, at - ended < memoryStopRetryCooldown {
             
            if let gave = memoryStopGaveReadsAgainAt, at - gave < memoryStopRetryCooldown { return }
            memoryStopGaveReadsAgainAt = at
        }
        shareRetries = 0
    }

     
     
     
     
    static func readsAgainForMemory(omitted: [ModuleEngineReport.OmittedModule], room: Int64?, rulesLeftOut: Int) -> Bool {
        omitted.contains { $0.reason == .overBudget || $0.reason == .overSharedBudget } || (room != nil && rulesLeftOut > 0)
    }

     
     
     
     
     
     
     
     
    static let moreLeftToReadAgain: Int64 = 2 << 20

     
     
     
     
     
     
    static func readsRulesAgain(leftNow: Int64?, leftAtRead: Int64?, roomNow: Int64?, shareNow: Int,
                                took: Int64, kept: Int) -> Bool {
        guard let roomNow else { return true }
        guard shareNow >= kept, roomNow > took + moreLeftToReadAgain else { return false }
        guard let leftAtRead else { return true }
        guard let leftNow else { return false }
        return leftNow > leftAtRead + moreLeftToReadAgain
    }

     
     
     
     
    private func readAgainAsMemoryAllows(_ engine: ModuleEngine, _ entry: ModuleEnginePlan.Entry, onlyRules: Bool = false) {
        guard !shareRetryDelays.isEmpty else { return }
         
         
        if onlyRules { shareRetries = min(shareRetries, shareRetryDelays.count - 1) }
        guard shareRetries < shareRetryDelays.count else { return }
        let delay = shareRetryDelays[shareRetries]
        shareRetries += 1
        let generation = configurationOnQueue
        queue.asyncAfter(deadline: .now() + delay) { [weak self, weak engine] in
            guard let self, let engine, engine === self.activeOnQueue, self.configurationOnQueue == generation,
                  !self.rulesOnDemand || self.builtOnQueue === engine, !engine.passThroughCauses.contains(.memory),
                  let entry = self.entryOnQueue, let reporter = self.reporterOnQueue else { return }
            if onlyRules {
                let left = self.headroom(), held = self.heldInForce(engine)
                let read = Self.readsRulesAgain(
                    leftNow: left, leftAtRead: self.leftAtReadOnQueue,
                    roomNow: ModuleEngineBudget.programRoom(headroom: left, holding: held, keptRuleBytes: self.heldKeptOnQueue),
                    shareNow: ModuleEngineBudget.ruleBytes(headroom: left, holding: held),
                    took: self.heldRoomOnQueue, kept: self.heldKeptOnQueue)
                 
                 
                guard read else { return self.readAgainAsMemoryAllows(engine, entry, onlyRules: true) }
            }
            self.log.say("modules were left out for memory: they are read again with what is left now")
            self.configureOnQueue(engine, entry, reporter, settling: false, cause: .readAgain)
        }
    }

     

     
     
    private func awaitRules(_ engine: ModuleEngine) {
        engine.awaitsRules = true
        engine.onRulesNeeded = { [weak self, weak engine] in
            guard let self, let engine else { return }
            self.buildDemanded(engine)
        }
        engine.idleAfter = idleRelease
        engine.onIdle = { [weak self, weak engine] in
            guard let self, let engine else { return }
            self.releaseRules(engine)
        }
    }

    private func buildDemanded(_ engine: ModuleEngine) {
        guard engine === activeOnQueue, let entry = entryOnQueue, let reporter = reporterOnQueue else {
             
            return engine.rulesReady()
        }
         
        guard demandedOnQueue !== engine else { return }
        demandedAt = now()
        configureOnQueue(engine, entry, reporter, settling: false, demanded: true, cause: .connection)
    }

    private func releaseRules(_ engine: ModuleEngine) {
        guard engine === activeOnQueue, builtOnQueue === engine else { return }
        (engine.interceptor as? ModuleInterceptor)?.releaseRules()
        builtOnQueue = nil
        heldKeptOnQueue = 0
        heldRoomOnQueue = 0
         
        configurationOnQueue += 1
        awaitRules(engine)
        log.say("no connection for \(idleRelease.map { "\($0)" } ?? "a while") s: the modules' rules are let go until a connection needs them")
    }

     

     
     
     
     
     
    private func watching(_ engine: ModuleEngine, _ entry: ModuleEnginePlan.Entry,
                          _ reporter: ModuleEngineReporter, settling: Bool) -> ModuleEnginePlan.Entry {
        if watch == nil || watchedEngine !== engine {
            stopWatching()
            let watch = ModuleWatch(locations: locations, queue: queue, log: log, notificationName: modulesSignal,
                                           coalescing: modulesCoalescing) { [weak self] found, modules in
                 
                guard let self, self.watch === found else { return }
                self.modulesMoved(modules)
            }
            watch.onDecryption = { [weak self] found, on in
                guard let self, self.watch === found, let engine = self.activeOnQueue, engine === self.watchedEngine else { return }
                self.decryption(on, engine, self.reporterOnQueue)
            }
            watch.startObserving()
            self.watch = watch
            watchedEngine = engine
            engine.onSession = { [weak watch] in watch?.sessionStarted() }
             
             
            engine.onMemoryStopEnded = { [weak self, weak engine] in
                guard let self, let engine, engine === self.watchedEngine, engine === self.activeOnQueue,
                      let entry = self.entryOnQueue, let reporter = self.reporterOnQueue else { return }
                self.log.say(#"the engine runs again after its memory stop: the modules are read again"#)
                 
                self.heldKeptOnQueue = 0
                self.heldRoomOnQueue = 0
                self.configureOnQueue(engine, entry, reporter, settling: false, cause: .memoryStopEnded)
            }
        }
        var entry = entry
        if settling, let listed = watch?.settle() {
             
             
             
             
            decryption(listed.enabled, engine, reporter, sinceThePublication: true)
            if listed.enabled, !listed.modules.isEmpty, listed.modules != entry.assignment.modules {
                log.say("the module list moved since this configuration was published: \(listed.modules.count) modules, the newest are read")
                entry.assignment.modules = listed.modules
            }
        }
        entryOnQueue = entry
        reporterOnQueue = reporter
        return entry
    }

    private func stopWatching() {
        watch?.stopObserving()
        watch = nil
        watchedEngine?.onSession = nil
        watchedEngine?.onMemoryStopEnded = nil
        watchedEngine = nil
        entryOnQueue = nil
        reporterOnQueue = nil
    }

     
     
     
     
     
     
     
     
    private func decryption(_ on: Bool, _ engine: ModuleEngine, _ reporter: ModuleEngineReporter?,
                            sinceThePublication: Bool = false) {
        guard on == engine.passThroughCauses.contains(.decryptionOff) else { return }
        if on {
            engine.passThroughCauses.remove(.decryptionOff)
            log.say("HTTPS Decryption is on again: listed sites are decrypted from the next connection")
            if let reporter, reporter.report.state == .passThrough, !engine.passThroughOnly {
                reporter.record { $0.state = .running }
            }
        } else {
            engine.passThroughCauses.insert(.decryptionOff)
            if sinceThePublication {
                log.say("HTTPS Decryption was turned off after this configuration was published: every connection is relayed untouched, and the next configuration takes the engine out")
            }
            if let reporter, reporter.report.state == .running {
                reporter.record { $0.state = .passThrough }
            }
        }
    }

     
     
     
    private func modulesMoved(_ modules: [ModuleGlobalManifest.Module]) {
        guard let engine = activeOnQueue, engine === watchedEngine, var entry = entryOnQueue, let reporter = reporterOnQueue else { return }
         
         
        guard modules != entry.assignment.modules else {
            return log.say("the module list moved, every module as it was: the rules in force stay")
        }
        entry.assignment.modules = modules
        configureOnQueue(engine, entry, reporter, settling: false)
    }

     

    private func startCheck(_ current: Running, _ reporter: ModuleEngineReporter) {
        queue.async { [weak self] in
             
            guard let self, self.activeOnQueue === current.engine else { return }
            self.checkGeneration += 1
            self.check(current, reporter, generation: self.checkGeneration, attempt: 1)
        }
    }

     
     
    private func check(_ current: Running, _ reporter: ModuleEngineReporter, generation: Int, attempt: Int) {
        guard checkGeneration == generation, activeOnQueue === current.engine else { return }
        let port = current.entry.assignment.ports.reinject
        ModuleReinjectCheck.run(port: port, queue: queue, timeout: checkTimeout,
                                 authorization: current.engine.settings.reinjectCredentials) { [weak self] outcome in
            guard let self, self.checkGeneration == generation, self.activeOnQueue === current.engine else { return }
            switch outcome {
            case .answers:
                self.log.say("re-inject listener 127.0.0.1:\(port) answers")
                 
                 
                let failure: ModuleEngineReport.Failure?
                if !current.engine.isListening {
                    failure = .bindFailed(port: current.entry.assignment.ports.engine, reason: "the engine's listener is not listening")
                } else if current.engine.settings.engineProxyCredentials == nil {
                    failure = .engineSignInMissing(reason: "this configuration's engine plan names no sign-in for the engine's port")
                } else {
                    failure = nil
                }
                reporter.record {
                    $0.state = failure != nil ? .failed : current.engine.passThroughOnly ? .passThrough : .running
                     
                     
                     
                    if failure == nil, case .certificateUnreadable? = $0.failure,
                       !current.engine.passThroughCauses.isDisjoint(with: [.certificate, .identity]) {
                        return
                    }
                    $0.failure = failure
                }
            case .needsAuthentication(let why):
                self.log.say("re-inject listener 127.0.0.1:\(port) will not let the engine in: \(why)")
                reporter.record {
                    $0.state = .failed
                    $0.failure = .reinjectNeedsAuthentication(port: port, reason: why)
                }
            case .silent(let why) where attempt < self.checkAttempts:
                let wait = self.checkSpacing * Double(1 << (attempt - 1))
                self.log.say("re-inject listener 127.0.0.1:\(port) did not answer yet (\(why)), trying again in \(wait) s")
                self.queue.asyncAfter(deadline: .now() + wait) { [weak self] in
                    self?.check(current, reporter, generation: generation, attempt: attempt + 1)
                }
            case .silent(let why):
                self.log.say("re-inject listener 127.0.0.1:\(port) does not answer: \(why)")
                reporter.record {
                    $0.state = .failed
                    $0.failure = .reinjectUnanswered(port: port, reason: why)
                }
            }
        }
    }
}
#endif
