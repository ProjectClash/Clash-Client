#if os(iOS) || os(macOS)
import Foundation

 
 
 

 
 
 
 
 
 
 
 
final class AdBlockSessionTable {
    private struct Entry {
        let exchange: AdBlockExchange
         
        let caFingerprint: String?
    }

    private let queue: DispatchQueue
    private var entries: [ObjectIdentifier: Entry] = [:]

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    var count: Int { entries.count }
    private(set) var plainCount = 0
     
     
    fileprivate(set) var services: AdBlockExchangeServices?

    fileprivate func add(_ exchange: AdBlockExchange, caFingerprint: String?) {
        dispatchPrecondition(condition: .onQueue(queue))
        entries[ObjectIdentifier(exchange)] = Entry(exchange: exchange, caFingerprint: caFingerprint)
        if caFingerprint == nil { plainCount += 1 }
    }

    fileprivate func remove(_ key: ObjectIdentifier) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard let entry = entries.removeValue(forKey: key) else { return }
        if entry.caFingerprint == nil { plainCount -= 1 }
    }

     
     
    func closeDecrypted(notOf fingerprint: String) {
        dispatchPrecondition(condition: .onQueue(queue))
        for entry in entries.values where entry.caFingerprint != nil && entry.caFingerprint != fingerprint { entry.exchange.close() }
    }

    func closeAll() {
        dispatchPrecondition(condition: .onQueue(queue))
        for entry in entries.values { entry.exchange.close() }
    }

     
     
     
    func windDown(over limit: Int) {
        dispatchPrecondition(condition: .onQueue(queue))
         
         
         
         
         
        let candidates = entries.values.filter { $0.exchange.canWindDown }
        let relays = entries.values.filter { $0.exchange.isRelay }.count
        for index in Self.windDownPicks(candidates.map(\.exchange.isIdle), relays: relays, limit: limit) {
            candidates[index].exchange.windDown()
        }
    }

     
     
     
    static func windDownPicks(_ idle: [Bool], relays: Int, limit: Int) -> [Int] {
        var excess = idle.count + relays - limit
        guard excess > 0 else { return [] }
        var picks: [Int] = []
        for (index, isIdle) in idle.enumerated() where excess > 0 && isIdle {
            picks.append(index)
            excess -= 1
        }
        for (index, isIdle) in idle.enumerated() where excess > 0 && !isIdle {
            picks.append(index)
            excess -= 1
        }
        return picks
    }

     
     
     
     
    func adoptNewest() {
        dispatchPrecondition(condition: .onQueue(queue))
        for entry in entries.values { entry.exchange.adoptNewestIfIdle() }
    }

     
     
     
     
    func shed(for rung: AdBlockEngineReport.Rung) {
        dispatchPrecondition(condition: .onQueue(queue))
        for entry in entries.values { entry.exchange.shed(for: rung) }
    }
}

final class AdBlockInterceptor: AdBlockIntercepting {
     
     
     
    static let ownLoopWindow: TimeInterval = 10
    static let maximumOwnLoopHosts = 256
    private weak var engine: AdBlockEngine?
     
    let leaves: AdBlockLeafStore?
     
    private(set) var services: AdBlockExchangeServices
    let pinning: AdBlockPinningMonitor
     
    let sessions: AdBlockSessionTable
     
     
    let revision: AdBlockRunningRevision?
    private let onPinning: ([AdBlockEngineReport.PinnedHost]) -> Void
     
    private let onIdentityFailure: (String) -> Void
     
    private var onIdentityWorked: (() -> Void)?
    private var ownLoop: [String: Date] = [:]
    private var plainCapLog = AdBlockLogLimiter()

    init(engine: AdBlockEngine, leaves: AdBlockLeafStore?, services: AdBlockExchangeServices, pinning: AdBlockPinningMonitor,
         sessions: AdBlockSessionTable? = nil, revision: AdBlockRunningRevision? = nil,
         onPinning: @escaping ([AdBlockEngineReport.PinnedHost]) -> Void, onIdentityFailure: @escaping (String) -> Void = { _ in },
         onIdentityWorked: (() -> Void)? = nil) {
        self.engine = engine
        self.leaves = leaves
        self.services = services
        self.pinning = pinning
        self.sessions = sessions ?? AdBlockSessionTable(queue: services.queue)
        self.sessions.services = services
        self.revision = revision
        self.onPinning = onPinning
        self.onIdentityFailure = onIdentityFailure
        self.onIdentityWorked = onIdentityWorked
    }

     
    var exchangeCount: Int { sessions.count }

     
    func closeAll() {
        sessions.closeAll()
    }

    var plainSessionCount: Int { sessions.plainCount }

     
     
     
     
     
     
    func shed(for rung: AdBlockEngineReport.Rung) {
        dispatchPrecondition(condition: .onQueue(services.queue))
        if rung >= .engineStopped {
            services.program = .empty
            sessions.services = services
        }
        sessions.shed(for: rung)
    }
    var ownLoopHostCount: Int { ownLoop.count }

    func intercept(_ client: AdBlockStream, target: AdBlockConnectTarget, kind: AdBlockInterceptKind, buffered: Data,
                   clientEnded: Bool, onEnd: @escaping () -> Void) -> Bool {
        dispatchPrecondition(condition: .onQueue(services.queue))
         
         
         
        services.allowance.noteActivity()
        guard engine?.passThroughOnly != true else { return false }
        switch kind {
        case .plainHTTP(let host):
             
             
            guard sessions.plainCount < (engine?.plainSessionLimit ?? AdBlockEngine.defaultPlainSessionLimit) else {
                services.metrics.update { $0.plainSessionsCappedTotal += 1 }
                if let heldBack = plainCapLog.admit(services.now()) {
                    services.log.say("\(sessions.plainCount) plain sessions are open, the most there may be: \(host) is relayed untouched\(AdBlockLogLimiter.suffix(heldBack))")
                }
                return false
            }
             
            let decrypted = engine?.decryptedSessionCount ?? 0
            guard sessions.plainCount + decrypted < (engine?.interceptedSessionLimit ?? AdBlockEngine.defaultInterceptedSessionLimit) else {
                services.metrics.update { $0.plainSessionsCappedTotal += 1 }
                if let heldBack = plainCapLog.admit(services.now()) {
                    services.log.say("\(decrypted) decrypted and \(sessions.plainCount) plain sessions are open, the most there may be together: \(host) is relayed untouched\(AdBlockLogLimiter.suffix(heldBack))")
                }
                return false
            }
            run(client, buffered: buffered, clientEnded: clientEnded,
                context: AdBlockExchangeContext(scheme: "http", host: host, target: target), caFingerprint: nil) { _ in onEnd() }
            return true
        case .tls(let serverName):
            guard let leaves, let engine else { return false }
            let lease: AdBlockIdentityLease
            let identity: SecIdentity
            switch AdBlockLeafChoice.choose(host: serverName, leaves: leaves) {
            case .present(let presented, let leased):
                identity = presented
                lease = leased
            case .relayUntouched(let why):
                 
                services.log.say("no certificate for \(serverName): \(why); this session is relayed untouched")
                return false
            case .degrade(let why):
                 
                 
                 
                services.log.say("no certificate for \(serverName): \(why); every listed site is relayed untouched")
                engine.passThroughCauses.insert(.identity)
                onIdentityFailure(why)
                return false
            }
            if let worked = onIdentityWorked {
                onIdentityWorked = nil
                worked()
            }
            services.metrics.update {
                $0.mitmSessions += 1
                $0.mitmSessionsTotal += 1
                $0.mitmSessionsPeak = max($0.mitmSessionsPeak, $0.mitmSessions)
            }
            var over = false
             
             
             
            let metrics = services.metrics, log = services.log, queue = services.queue, grace = services.finalSendTimeout
            let sessionEnded = {
                guard !over else { return }
                over = true
                lease.end()
                metrics.update { $0.mitmSessions = max(0, $0.mitmSessions - 1) }
                onEnd()
            }
            let fingerprint = leaves.caFingerprint
            let revision = self.revision
            AdBlockTLSFront.open(client: client, buffered: buffered, clientEnded: clientEnded, identity: identity,
                                 queue: queue) { [weak self, weak engine] result in
                 
                 
                 
                 
                let successor = (engine?.interceptor as? AdBlockInterceptor).flatMap {
                    $0.revision == revision && $0.leaves?.caFingerprint == fingerprint ? $0 : nil
                }
                let serving = self ?? successor
                switch result {
                case .failure(let failure):
                    if let signal = AdBlockPinningSignal.of(failure, hello: buffered) { serving?.suspect(serverName, signal) }
                    log.say("TLS with \(serverName) failed: \(failure)")
                    sessionEnded()
                case .success(let front):
                    guard let serving else {
                         
                         
                        log.say("TLS with \(serverName) finished after its configuration was replaced: closed")
                        front.close()
                        return sessionEnded()
                    }
                    front.onClosedWithoutAsking = { [weak serving] in serving?.suspect(serverName, .closedWithoutAsking) }
                    let context = AdBlockExchangeContext(scheme: "https", host: serverName, target: target)
                    serving.run(front.plaintext, buffered: Data(), clientEnded: false, context: context, caFingerprint: fingerprint) { drains in
                        guard drains else {
                            front.close()
                            return sessionEnded()
                        }
                         
                        front.closeAfterDraining(within: grace, queue: queue) { sessionEnded() }
                    }
                }
            }
            return true
        }
    }

     
     
    private func run(_ client: AdBlockStream, buffered: Data, clientEnded: Bool, context: AdBlockExchangeContext, caFingerprint: String?,
                     onEnd: @escaping (_ drains: Bool) -> Void) {
        var key: ObjectIdentifier?
        weak var made: AdBlockExchange?
         
        let exchange = AdBlockExchange(client: client, buffered: buffered, clientEnded: clientEnded, context: context,
                                       services: services, newest: { [weak sessions] in sessions?.services }) { [sessions] in
            if let key { sessions.remove(key) }
            onEnd(made?.endedOnLastAnswer ?? false)
        }
        made = exchange
        key = ObjectIdentifier(exchange)
        sessions.add(exchange, caFingerprint: caFingerprint)
        exchange.start()
         
         
         
        let rung = engine?.ladder?.rung ?? (engine?.passThroughCauses.contains(.memory) == true ? .engineStopped : .normal)
        if rung > .normal { exchange.shed(for: rung) }
    }

     
     
     
     
    func noteOwnAuthorityRefused(_ host: String) {
        dispatchPrecondition(condition: .onQueue(services.queue))
        let now = services.now()
        if ownLoop[host] == nil, ownLoop.count >= Self.maximumOwnLoopHosts {
            ownLoop = ownLoop.filter { now.timeIntervalSince($0.value) < Self.ownLoopWindow }
            if ownLoop.count >= Self.maximumOwnLoopHosts, let oldest = ownLoop.min(by: { $0.value < $1.value })?.key {
                ownLoop[oldest] = nil
            }
        }
        ownLoop[host] = now
    }

     
     
    private func suspect(_ host: String, _ signal: AdBlockPinningSignal) {
        if let at = ownLoop[host], services.now().timeIntervalSince(at) < Self.ownLoopWindow {
            services.log.say("TLS with \(host) ended by this engine's own upstream, which refused its certificate: a route back into ad blocking, not an app that pins")
            return
        }
        if pinning.suspect(host, signal, metrics: services.metrics, log: services.log) { engine?.passedThroughHosts.insert(host) }
        onPinning(pinning.hosts)
    }
}

 
 
struct AdBlockEngineStorage {
    let leaves: URL?
    let bodies: URL?
    /// Where a script's `$persistentStore` lives. One file for every script, as
    /// the platforms have one store per host.
    var scripts: URL?

    static var tunnel: AdBlockEngineStorage {
        AdBlockEngineStorage(leaves: AdBlockLeafStore.defaultDirectory(),
                             bodies: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
                                 .appendingPathComponent("adblock-bodies", isDirectory: true),
                             scripts: ClashAppIdentifiers.appGroupContainer?
                                 .appendingPathComponent("adblock-scripts.json"))
    }
}

 
enum AdBlockEngineAssembly {
     
     
     
     
     
     
     
     
     
     
     
    static func configure(_ engine: AdBlockEngine, _ inputs: AdBlockEngineInputs, _ reporter: AdBlockEngineReporter,
                          locations: AdBlockEngineLocations, scripts: AdBlockScriptRunning,
                          thresholds: AdBlockLadderThresholds? = nil, ladderSeams: AdBlockLadderSeams = .system,
                          storage: AdBlockEngineStorage = .tunnel, trust: AdBlockServerTrust = .system) {
        dispatchPrecondition(condition: .onQueue(engine.queue))
        let entry = inputs.entry
        let previous = engine.interceptor as? AdBlockInterceptor
        if previous == nil { sweepBodies(storage.bodies) }
         
         
        let program = engine.passThroughCauses.contains(.memory) ? AdBlockRewriteProgram.empty
            : AdBlockRewriteProgram(published: inputs.modules, leavingOut: previous?.services.program.leftOutDuringRun ?? [],
                                    grownTooLarge: previous?.services.program.grewTooLargeDuringRun ?? [],
                                    scriptFile: { id, sha in locations.script(id, sha256: sha) },
                                    moduleFile: { id, sha in locations.moduleFile(id, sha256: sha) })
        let (leaves, fingerprint, problem) = certificate(engine, entry, previous: previous, locations: locations, storage: storage)
        settleCertificate(engine, reporter, decrypts: entry.assignment.decryptsTLS, fingerprint: fingerprint, problem: problem)

        let connector: AdBlockUpstreamConnector
        if let fingerprint {
            connector = AdBlockUpstreamConnector(engine: engine, ownCAFingerprint: fingerprint, trust: trust)
        } else {
             
             
            connector = AdBlockUpstreamConnector(queue: engine.queue, reinject: { [weak engine] authority, completion in
                guard let engine else { return completion(.failure(.unreachable("the engine stopped"))) }
                engine.reinject(authority, completion)
            }, trust: trust, loopCount: AdBlockUpstreamConnector.LoopCount(opened: { [weak engine] in engine?.upstreamOpened($0) },
                                                                           closed: { [weak engine] in engine?.upstreamClosed($0) }))
        }
        let allowance: AdBlockAllowance
        if let kept = engine.ladder {
             
            allowance = kept
        } else if let thresholds {
             
            var saidNoHeadroom = false
            let ladder = AdBlockMemoryLadder(thresholds: thresholds, startingAt: reporter.report.rung, takenBy: reporter.report.rungCause,
                                             probe: ladderSeams.probe, pressureLevel: ladderSeams.pressureLevel, now: ladderSeams.now,
                                             onChange: react(engine: engine, reporter: reporter, scripts: scripts),
                                             onReading: { [weak reporter, weak engine] reading in
                                                 reporter?.note {
                                                     $0.footprintBytes = reading.footprint
                                                     $0.headroomBytes = reading.headroom
                                                 }
                                                  
                                                 if reading.headroom == nil, !thresholds.followsPressureOnly, !saidNoHeadroom {
                                                     saidNoHeadroom = true
                                                     engine?.log.say("the system gives no memory headroom figure: the footprint is measured against \(thresholds.assumedLimit.map { "\($0 >> 20) MiB" } ?? "nothing")")
                                                 }
                                             },
                                             onLower: relax(engine: engine, reporter: reporter))
            if let make = ladderSeams.pressureSource { ladder.watchPressure(on: engine.queue, source: make) }
            engine.ladder = ladder
            allowance = ladder
        } else {
            allowance = AdBlockFullAllowance()
        }
        // A module's scripts are run by a runner whose HTTP goes through the
        // same connector as the intercepted traffic, and whose storage is one
        // file in the container. The runner is built here, where the connector
        // and the storage are known.
        let scriptRunner: AdBlockScriptRunning
        if let js = scripts as? AdBlockScriptRunner {
            js.adopt(upstreams: connector, storageURL: storage.scripts)
            scriptRunner = js
        } else {
            scriptRunner = scripts
        }
        let services = AdBlockExchangeServices(
            queue: engine.queue, program: program,
            budget: previous?.services.budget ?? AdBlockBodyBudget(limits: .current, metrics: engine.metrics, spillDirectory: storage.bodies),
            allowance: allowance, scripts: scriptRunner, upstreams: connector, metrics: engine.metrics, log: engine.log,
            rejects: previous?.services.rejects ?? AdBlockRejectUpgradeBox(), now: reporter.now,
            headTimeout: engine.headTimeout, finalSendTimeout: engine.finalSendTimeout)
         
         
        scripts.attach(AdBlockScriptSink(queue: engine.queue, metrics: engine.metrics) { [weak engine, weak ladder = allowance as? AdBlockMemoryLadder] reason in
            engine?.log.say("scripts cannot run: \(reason)")
            ladder?.scriptsUnavailable()
        })
        let interceptor = AdBlockInterceptor(
            engine: engine, leaves: leaves, services: services,
            pinning: previous?.pinning ?? AdBlockPinningMonitor(now: reporter.now, carrying: reporter.report.pinnedHosts),
            sessions: previous?.sessions, revision: entry.revision,
            onPinning: { hosts in reporter.record { $0.pinnedHosts = hosts } },
            onIdentityFailure: { [weak engine] reason in
                 
                 
                engine?.log.say("the certificate cannot make identities on this system (\(reason)); every listed site is relayed untouched")
                reporter.record {
                    if $0.state == .running { $0.state = .passThrough }
                    $0.failure = .certificateUnreadable(reason: "identity: \(reason)")
                    if let fingerprint { $0.identityFailedAt[fingerprint] = reporter.now() }
                }
            },
            onIdentityWorked: fingerprint.map { fingerprint in {
                 
                guard reporter.report.identityFailedAt[fingerprint] != nil || reporter.report.identityRetriedAt[fingerprint] != nil else { return }
                reporter.record { $0.noteIdentityWorked(for: fingerprint) }
            } })
        connector.onOwnAuthority = { [weak interceptor] host in interceptor?.noteOwnAuthorityRefused(host) }
        engine.interceptor = interceptor
        interceptor.sessions.adoptNewest()
        settleSessionLimit(engine, entry, inputs, program)

        let rewrites = program.rewriteMetrics
        let scriptsGate = program.scriptMetrics
        engine.metrics.update {
            $0.rewriteRules = rewrites.rules
            $0.rewritePatternBytes = rewrites.patternBytes
            $0.rewriteCompileFailed = rewrites.compileFailed
            $0.rewriteGateLiterals = rewrites.gateLiterals
            $0.rewriteGateBytes = rewrites.gateBytes
            $0.rewriteUngated = rewrites.ungated
            $0.rewriteUnsupported = program.unsupported.count
            $0.rewriteOverBudget = rewrites.overBudget
            $0.scriptRules = scriptsGate.rules
            $0.scriptGateLiterals = scriptsGate.gateLiterals
            $0.scriptUngated = scriptsGate.ungated
            $0.scriptOverBudget = scriptsGate.overBudget
             
            let handed = program.takeNewStops()
            $0.rulesLeftOutThisRun = handed?.leftOutThisRun ?? 0
            $0.rulesLeftOutTooLargeThisRun = handed?.leftOutTooLarge ?? 0
        }
        engine.log.say("rules ready: \(rewrites.rules) rewrites (\(rewrites.ungated) ungated, \(rewrites.gateLiterals) literals, \(rewrites.compileFailed) that do not compile, \(program.unsupported.count) not run), \(scriptsGate.rules) scripts, from \(inputs.modules.count) of \(entry.assignment.modules.count) modules")
    }

     
     
     
     
     
     
    private static func settleSessionLimit(_ engine: AdBlockEngine, _ entry: AdBlockEnginePlan.Entry, _ inputs: AdBlockEngineInputs,
                                           _ program: AdBlockRewriteProgram) {
        #if os(iOS)
        let lists = AdBlockEngineBudget.listsHeld(entry.assignment)
         
         
        let rules = AdBlockEngineBudget.programHeld(keptRuleBytes: inputs.modules.reduce(0) { $0 + $1.keptBytes },
                                                    compiledRegexes: program.compiledRegexesAtMost) + Int64(program.heldValueBytes)
        let limit = AdBlockEngineBudget.sharedSessionLimit(planHolding: lists + rules)
        engine.interceptedSessionLimit = limit
        engine.log.say(String(format: "the plan holds about %.2f MiB (lists %.2f, rules %.2f): at most %d sessions are taken at once",
                              Double(lists + rules) / 1_048_576, Double(lists) / 1_048_576, Double(rules) / 1_048_576, limit))
         
        if let sessions = (engine.interceptor as? AdBlockInterceptor)?.sessions, sessions.count > limit {
            engine.log.say("\(sessions.count) sessions are open, more than this configuration's \(limit): the ones over it end once idle")
            sessions.windDown(over: limit)
        }
        #endif
    }

     
     
    private static func certificate(_ engine: AdBlockEngine, _ entry: AdBlockEnginePlan.Entry, previous: AdBlockInterceptor?,
                                    locations: AdBlockEngineLocations, storage: AdBlockEngineStorage)
        -> (leaves: AdBlockLeafStore?, fingerprint: String?, problem: String?) {
        guard entry.assignment.decryptsTLS else { return (nil, nil, nil) }
        let material: AdBlockCAMaterial
        switch AdBlockCAFiles.status(locations) {
        case .ready(let ready, _): material = ready
        case .absent: return (nil, nil, "no certificate has been made")
        case .needsRegeneration(let why), .unavailable(let why): return (nil, nil, why)
        }
        let fingerprint = AdBlockCertificateFingerprint.sha256(material.certificateDER)
        if let published = entry.assignment.caFingerprintSHA256, published.lowercased() != fingerprint {
            return (nil, nil, "the certificate is not the one this configuration was published with")
        }
        if let kept = previous?.leaves, kept.caFingerprint == fingerprint, kept.directory == storage.leaves {
            return (kept, fingerprint, nil)
        }
        guard let directory = storage.leaves else { return (nil, nil, "the tunnel has no directory for its certificates") }
         
         
         
        previous?.sessions.closeDecrypted(notOf: fingerprint)
        let store: AdBlockLeafStore
        do {
            store = try AdBlockLeafStore(directory: directory, ca: material, caFingerprint: fingerprint,
                                         log: { [weak engine] line in engine?.log.say(line) })
        } catch {
            return (nil, nil, "\(error)")
        }
        if case .failed(let why) = store.sweepOtherCAs() {
            engine.log.say("the certificates another CA left could not all be removed: \(why)")
        }
        return (store, fingerprint, nil)
    }

     
     
     
    private static func settleCertificate(_ engine: AdBlockEngine, _ reporter: AdBlockEngineReporter, decrypts: Bool,
                                          fingerprint: String?, problem: String?) {
        let wasUnreadable: Bool
        if case .certificateUnreadable? = reporter.report.failure { wasUnreadable = true } else { wasUnreadable = false }
        engine.passThroughCauses.remove(.certificate)
        if let problem {
            engine.passThroughCauses.insert(.certificate)
            engine.log.say("the certificate cannot be used (\(problem)): every listed site is relayed untouched this run")
            reporter.record {
                if $0.state == .running { $0.state = .passThrough }
                $0.failure = .certificateUnreadable(reason: problem)
            }
            return
        }
        guard decrypts, let fingerprint else {
             
            engine.passThroughCauses.remove(.identity)
            if wasUnreadable { clearCertificateFailure(engine, reporter) }
            return
        }
         
        if engine.passThroughCauses.contains(.identity), reporter.report.identityFailedAt[fingerprint] == nil {
            engine.passThroughCauses.remove(.identity)
        }
        if !engine.passThroughCauses.contains(.identity), reporter.report.identityFailedAt[fingerprint] != nil {
            if reporter.report.identityRetriedAt[fingerprint] == nil {
                 
                reporter.record { _ = $0.beginIdentityRetry(for: fingerprint, at: reporter.now()) }
                engine.log.say("the certificate could not make identities in an earlier run; this start tries it once more")
            } else if reporter.report.identityDegradeHolds(for: fingerprint) {
                engine.passThroughCauses.insert(.identity)
                engine.log.say("the certificate could not make identities on this system after its retry; every listed site is relayed untouched")
                return
            }
        }
        if wasUnreadable, !engine.passThroughCauses.contains(.identity) { clearCertificateFailure(engine, reporter) }
    }

    private static func clearCertificateFailure(_ engine: AdBlockEngine, _ reporter: AdBlockEngineReporter) {
        reporter.record {
            $0.failure = nil
            if $0.state == .passThrough, !engine.passThroughOnly { $0.state = .running }
        }
    }

     
     
     
    private static func sweepBodies(_ directory: URL?) {
        guard let directory else { return }
        let manager = FileManager.default
        for name in (try? manager.contentsOfDirectory(atPath: directory.path)) ?? [] where name.hasSuffix(".body") {
            try? manager.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}
#endif
