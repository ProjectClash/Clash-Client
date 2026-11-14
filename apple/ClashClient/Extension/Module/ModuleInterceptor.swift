#if os(iOS) || os(macOS)
import Foundation

 
 
 

 
 
 
 
 
 
 
 
final class ModuleSessionTable {
    private struct Entry {
         
        let exchange: ModuleTableSession
         
        let caFingerprint: String?
    }

    private let queue: DispatchQueue
    private var entries: [ObjectIdentifier: Entry] = [:]

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    var count: Int { entries.count }
     
     
    fileprivate(set) var services: ModuleExchangeServices?

    fileprivate func add(_ exchange: ModuleTableSession, caFingerprint: String?) {
        dispatchPrecondition(condition: .onQueue(queue))
        entries[ObjectIdentifier(exchange)] = Entry(exchange: exchange, caFingerprint: caFingerprint)
    }

    fileprivate func remove(_ key: ObjectIdentifier) {
        dispatchPrecondition(condition: .onQueue(queue))
        entries.removeValue(forKey: key)
    }

     
     
    func closeDecrypted(notOf fingerprint: String) {
        dispatchPrecondition(condition: .onQueue(queue))
        for entry in entries.values where entry.caFingerprint != nil && entry.caFingerprint != fingerprint { entry.exchange.close() }
    }

    func closeAll() {
        dispatchPrecondition(condition: .onQueue(queue))
        for entry in entries.values { entry.exchange.close() }
    }

     
     
     
     
    func adoptNewest() {
        dispatchPrecondition(condition: .onQueue(queue))
        for entry in entries.values { entry.exchange.adoptNewestIfIdle() }
    }

     
     
     
     
    func shed(for rung: ModuleEngineReport.Rung) {
        dispatchPrecondition(condition: .onQueue(queue))
        for entry in entries.values { entry.exchange.shed(for: rung) }
    }
}

final class ModuleInterceptor: ModuleIntercepting {
     
     
     
    static let ownLoopWindow: TimeInterval = 10
    static let maximumOwnLoopHosts = 256
    private weak var engine: ModuleEngine?
     
    let leaves: ModuleLeafStore?
     
    private(set) var services: ModuleExchangeServices
    let pinning: ModulePinningMonitor
     
    let sessions: ModuleSessionTable
     
     
    let revision: ModuleRunningRevision?
    private let onPinning: ([ModuleEngineReport.PinnedHost]) -> Void
     
    private let onIdentityFailure: (String) -> Void
     
    private var onIdentityWorked: (() -> Void)?
    private var ownLoop: [String: Date] = [:]

    init(engine: ModuleEngine, leaves: ModuleLeafStore?, services: ModuleExchangeServices, pinning: ModulePinningMonitor,
         sessions: ModuleSessionTable? = nil, revision: ModuleRunningRevision? = nil,
         onPinning: @escaping ([ModuleEngineReport.PinnedHost]) -> Void, onIdentityFailure: @escaping (String) -> Void = { _ in },
         onIdentityWorked: (() -> Void)? = nil) {
        self.engine = engine
        self.leaves = leaves
        self.services = services
        self.pinning = pinning
        self.sessions = sessions ?? ModuleSessionTable(queue: services.queue)
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

     
     
     
     
     
     
    func shed(for rung: ModuleEngineReport.Rung) {
        dispatchPrecondition(condition: .onQueue(services.queue))
        if rung >= .engineStopped {
            services.program = .empty
            sessions.services = services
        }
        sessions.shed(for: rung)
    }
    var ownLoopHostCount: Int { ownLoop.count }

     
     
     
     
    func releaseRules() {
        dispatchPrecondition(condition: .onQueue(services.queue))
        services.program = .empty
        sessions.services = services
    }

    func intercept(_ client: ModuleStream, target: ModuleConnectTarget, kind: ModuleInterceptKind, buffered: Data,
                   clientEnded: Bool, onEnd: @escaping () -> Void) -> Bool {
        dispatchPrecondition(condition: .onQueue(services.queue))
         
         
         
        services.allowance.noteActivity()
        guard engine?.passThroughOnly != true else { return false }
        switch kind {
        case .plainHTTP(let host):
             
             
             
            run(client, buffered: buffered, clientEnded: clientEnded,
                context: ModuleExchangeContext(scheme: "http", host: host, target: target), caFingerprint: nil) { _ in onEnd() }
            return true
        case .tls(let serverName):
            guard let leaves, let engine else { return false }
            let lease: ModuleIdentityLease
            let identity: SecIdentity
            switch ModuleLeafChoice.choose(host: serverName, leaves: leaves) {
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
             
            let protocols = engine.offersHTTP2(serverName: serverName, target: target)
                ? ModuleTLSFront.http2Protocols : ModuleTLSFront.http11Protocols
            ModuleTLSFront.open(client: client, buffered: buffered, clientEnded: clientEnded, identity: identity,
                                 queue: queue, applicationProtocols: protocols) { [weak self, weak engine] result in
                 
                 
                 
                 
                let successor = (engine?.interceptor as? ModuleInterceptor).flatMap {
                    $0.revision == revision && $0.leaves?.caFingerprint == fingerprint ? $0 : nil
                }
                let serving = self ?? successor
                switch result {
                case .failure(let failure):
                    if let signal = ModulePinningSignal.of(failure, hello: buffered) { serving?.suspect(serverName, signal) }
                    log.say("TLS with \(serverName) failed: \(failure)")
                    sessionEnded()
                case .success(let front):
                    guard let serving else {
                         
                         
                        log.say("TLS with \(serverName) finished after its configuration was replaced: closed")
                        front.close()
                        return sessionEnded()
                    }
                    front.onClosedWithoutAsking = { [weak serving] in serving?.suspect(serverName, .closedWithoutAsking) }
                     
                    front.onAsked = { [weak serving] in serving?.pinning.asked(serverName) }
                    let context = ModuleExchangeContext(scheme: "https", host: serverName, target: target)
                    let ended = { (drains: Bool) in
                        guard drains else {
                            front.close()
                            return sessionEnded()
                        }
                         
                        front.closeAfterDraining(within: grace, queue: queue) { sessionEnded() }
                    }
                     
                    if front.negotiatedProtocol == #"h2"# {
                        serving.runHTTP2(front.plaintext, context: context, caFingerprint: fingerprint, onEnd: ended)
                    } else {
                        serving.run(front.plaintext, buffered: Data(), clientEnded: false, context: context, caFingerprint: fingerprint,
                                    onEnd: ended)
                    }
                }
            }
            return true
        }
    }

     
     
    private func run(_ client: ModuleStream, buffered: Data, clientEnded: Bool, context: ModuleExchangeContext, caFingerprint: String?,
                     onEnd: @escaping (_ drains: Bool) -> Void) {
        var key: ObjectIdentifier?
        weak var made: ModuleExchange?
         
        let exchange = ModuleExchange(client: client, buffered: buffered, clientEnded: clientEnded, context: context,
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

     
     
    private func runHTTP2(_ client: ModuleStream, context: ModuleExchangeContext, caFingerprint: String?,
                          onEnd: @escaping (_ drains: Bool) -> Void) {
        var key: ObjectIdentifier?
        let session = ModuleH2Session(client: client, context: context, services: services,
                                      newest: { [weak sessions] in sessions?.services }) { [sessions] drains in
            if let key { sessions.remove(key) }
            onEnd(drains)
        }
        key = ObjectIdentifier(session)
        sessions.add(session, caFingerprint: caFingerprint)
        session.start()
        let rung = engine?.ladder?.rung ?? (engine?.passThroughCauses.contains(.memory) == true ? .engineStopped : .normal)
        if rung > .normal { session.shed(for: rung) }
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

     
     
    private func suspect(_ host: String, _ signal: ModulePinningSignal) {
        if let at = ownLoop[host], services.now().timeIntervalSince(at) < Self.ownLoopWindow {
            services.log.say("TLS with \(host) ended by this engine's own upstream, which refused its certificate: a route back into modules, not an app that pins")
            return
        }
        if pinning.suspect(host, signal, metrics: services.metrics, log: services.log) { engine?.passedThroughHosts.insert(host) }
        onPinning(pinning.hosts)
    }
}

 
 
struct ModuleEngineStorage {
    let leaves: URL?
    let bodies: URL?

     
    static var tunnel: ModuleEngineStorage {
        ModuleEngineStorage(leaves: ModuleLeafStore.defaultDirectory(),
                             bodies: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
                                 .appendingPathComponent("adblock-bodies", isDirectory: true))
    }
}

 
enum ModuleEngineAssembly {
     
     
     
     
     
     
     
     
     
     
     
    static func configure(_ engine: ModuleEngine, _ inputs: ModuleEngineInputs, _ reporter: ModuleEngineReporter,
                          locations: ModuleEngineLocations, scripts: ModuleScriptRunning,
                          thresholds: ModuleLadderThresholds? = nil, ladderSeams: ModuleLadderSeams = .system,
                          storage: ModuleEngineStorage = .tunnel, trust: ModuleServerTrust = .system) {
        dispatchPrecondition(condition: .onQueue(engine.queue))
        let entry = inputs.entry
        let previous = engine.interceptor as? ModuleInterceptor
        if previous == nil { sweepBodies(storage.bodies) }
         
         
         
        let program = engine.passThroughCauses.contains(.memory) ? ModuleRewriteProgram.empty
            : ModuleRewriteProgram(published: inputs.modules, leavingOut: previous?.services.program.leftOutDuringRun ?? [],
                                    grownTooLarge: previous?.services.program.grewTooLargeDuringRun ?? [],
                                    scriptFile: { id, sha in locations.script(id, sha256: sha) },
                                    moduleFile: { id, sha in locations.moduleFile(id, sha256: sha) },
                                    room: inputs.room)
        let (leaves, fingerprint, problem) = certificate(engine, entry, previous: previous, locations: locations, storage: storage)
        settleCertificate(engine, reporter, decrypts: entry.assignment.decryptsTLS, fingerprint: fingerprint, problem: problem)

        let connector: ModuleUpstreamConnector
        if let fingerprint {
            connector = ModuleUpstreamConnector(engine: engine, ownCAFingerprint: fingerprint, trust: trust)
        } else {
             
             
            connector = ModuleUpstreamConnector(queue: engine.queue, reinject: { [weak engine] authority, outbound, completion in
                guard let engine else { return completion(.failure(.unreachable("the engine stopped"))) }
                engine.reinject(authority, outbound: outbound, completion)
            }, trust: trust, loopCount: ModuleUpstreamConnector.LoopCount(opened: { [weak engine] in engine?.upstreamOpened($0) },
                                                                           closed: { [weak engine] in engine?.upstreamClosed($0) }))
        }
        let allowance: ModuleAllowance
        if let kept = engine.ladder {
             
            allowance = kept
        } else if let thresholds {
             
            var saidNoHeadroom = false
            let ladder = ModuleMemoryLadder(thresholds: thresholds, startingAt: reporter.report.rung, takenBy: reporter.report.rungCause,
                                             probe: ladderSeams.probe, now: ladderSeams.now,
                                             onChange: react(engine: engine, reporter: reporter, scripts: scripts),
                                             onReading: { [weak reporter, weak engine] reading in
                                                 reporter?.note {
                                                     $0.footprintBytes = reading.footprint
                                                     $0.headroomBytes = reading.headroom
                                                 }
                                                  
                                                 if reading.headroom == nil, !thresholds.relievesOnCriticalOnly, !saidNoHeadroom {
                                                     saidNoHeadroom = true
                                                     engine?.log.say("the system gives no memory headroom figure: the footprint is measured against \(thresholds.assumedLimit.map { "\($0 >> 20) MiB" } ?? "nothing")")
                                                 }
                                             },
                                             onLower: relax(engine: engine, reporter: reporter),
                                             onRelieve: { [weak engine] relief in
                                                  
                                                 let mib = { (bytes: Int64?) in bytes.map { String(format: #"%.1f MiB"#, Double($0) / 1_048_576) } ?? #"unknown"# }
                                                 switch relief {
                                                 case .tight(let reading):
                                                     engine?.log.say(#"memory: headroom \#(mib(reading.headroom)), footprint \#(mib(reading.footprint)), under \#(mib(thresholds.relief)): idle scripts and cached regexes are let go"#)
                                                 case .critical(let reading):
                                                     engine?.log.say(#"memory: the system's memory pressure is critical, footprint \#(mib(reading.footprint)): idle scripts and cached regexes are let go"#)
                                                 case .beforeSkip:
                                                     break
                                                 }
                                                 relieve(engine: engine, scripts: scripts)
                                             })
            if let make = ladderSeams.pressureSource { ladder.watchPressure(on: engine.queue, source: make) }
            engine.ladder = ladder
            allowance = ladder
        } else {
            allowance = ModuleFullAllowance()
        }
        var services = ModuleExchangeServices(
            queue: engine.queue, program: program,
            budget: previous?.services.budget ?? ModuleBodyBudget(limits: .current, metrics: engine.metrics, spillDirectory: storage.bodies,
                                                                  relieve: { [weak engine] in relieve(engine: engine, scripts: scripts) }),
            allowance: allowance, scripts: scripts, upstreams: connector, metrics: engine.metrics, log: engine.log,
            rejects: previous?.services.rejects ?? ModuleRejectUpgradeBox(), now: reporter.now,
            headTimeout: engine.headTimeout, finalSendTimeout: engine.finalSendTimeout)
        if let carried = previous?.services.http2Buffers { services.http2Buffers = carried }
         
         
         
        scripts.attach(ModuleScriptSink(queue: engine.queue, metrics: engine.metrics, upstreams: connector) { [weak engine, weak ladder = allowance as? ModuleMemoryLadder] reason in
            engine?.log.say("scripts cannot run: \(reason)")
            ladder?.scriptsUnavailable()
        })
        let interceptor = ModuleInterceptor(
            engine: engine, leaves: leaves, services: services,
            pinning: previous?.pinning ?? ModulePinningMonitor(now: reporter.now, carrying: reporter.report.pinnedHosts),
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
         
         
        let room = inputs.room.map { String(format: "%.2f MiB", Double($0) / 1_048_576) } ?? "no bound"
        let taken = String(format: "%.2f MiB", Double(program.roomTaken) / 1_048_576)
        let forMemoryReasons: Set<String> = [ModuleGatedMatcher.overBudgetReason, ModuleRewriteProgram.jqOverBudgetReason,
                                             ModuleRewriteProgram.carriedForMemoryReason]
        let forMemory = rewrites.overBudget + scriptsGate.overBudget > 0
            ? program.leftOut.filter { forMemoryReasons.contains($0.reason) } : []
        if forMemory.isEmpty {
            engine.log.say("compiled as built: \(taken) of \(room)")
        } else {
            let byModule = Dictionary(grouping: forMemory, by: \.origin.moduleName).map { "\($0.key) \($0.value.count)" }.sorted()
            engine.log.say("compiled as built: \(taken) of \(room); left out for memory: \(byModule.joined(separator: ", "))")
        }
    }

     
     
    private static func certificate(_ engine: ModuleEngine, _ entry: ModuleEnginePlan.Entry, previous: ModuleInterceptor?,
                                    locations: ModuleEngineLocations, storage: ModuleEngineStorage)
        -> (leaves: ModuleLeafStore?, fingerprint: String?, problem: String?) {
        guard entry.assignment.decryptsTLS else { return (nil, nil, nil) }
        let material: ModuleCAMaterial
        switch ModuleCAFiles.status(locations) {
        case .ready(let ready, _): material = ready
        case .absent: return (nil, nil, "no certificate has been made")
        case .needsRegeneration(let why), .unavailable(let why): return (nil, nil, why)
        }
        let fingerprint = ModuleCertificateFingerprint.sha256(material.certificateDER)
        if let published = entry.assignment.caFingerprintSHA256, published.lowercased() != fingerprint {
            return (nil, nil, "the certificate is not the one this configuration was published with")
        }
        if let kept = previous?.leaves, kept.caFingerprint == fingerprint, kept.directory == storage.leaves {
            return (kept, fingerprint, nil)
        }
        guard let directory = storage.leaves else { return (nil, nil, "the tunnel has no directory for its certificates") }
         
         
         
        previous?.sessions.closeDecrypted(notOf: fingerprint)
        let store: ModuleLeafStore
        do {
            store = try ModuleLeafStore(directory: directory, ca: material, caFingerprint: fingerprint,
                                         log: { [weak engine] line in engine?.log.say(line) })
        } catch {
            return (nil, nil, "\(error)")
        }
        if case .failed(let why) = store.sweepOtherCAs() {
            engine.log.say("the certificates another CA left could not all be removed: \(why)")
        }
        return (store, fingerprint, nil)
    }

     
     
     
     
     
    static func checkCertificate(_ engine: ModuleEngine, _ entry: ModuleEnginePlan.Entry, _ reporter: ModuleEngineReporter,
                                 locations: ModuleEngineLocations, storage: ModuleEngineStorage = .tunnel) {
        dispatchPrecondition(condition: .onQueue(engine.queue))
        guard entry.assignment.decryptsTLS else {
            return settleCertificate(engine, reporter, decrypts: false, fingerprint: nil, problem: nil)
        }
        var fingerprint: String?
        var problem: String?
        switch ModuleCAFiles.status(locations) {
        case .ready(let ready, _):
            let found = ModuleCertificateFingerprint.sha256(ready.certificateDER)
            if let published = entry.assignment.caFingerprintSHA256, published.lowercased() != found {
                problem = "the certificate is not the one this configuration was published with"
            } else if storage.leaves == nil {
                problem = "the tunnel has no directory for its certificates"
            } else {
                fingerprint = found
            }
        case .absent: problem = "no certificate has been made"
        case .needsRegeneration(let why), .unavailable(let why): problem = why
        }
        settleCertificate(engine, reporter, decrypts: true, fingerprint: fingerprint, problem: problem)
    }

     
     
     
    private static func settleCertificate(_ engine: ModuleEngine, _ reporter: ModuleEngineReporter, decrypts: Bool,
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

    private static func clearCertificateFailure(_ engine: ModuleEngine, _ reporter: ModuleEngineReporter) {
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
