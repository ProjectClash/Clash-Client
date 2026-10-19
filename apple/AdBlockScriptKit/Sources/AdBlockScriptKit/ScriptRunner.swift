import Foundation

/// Bounds and caps for script runs.
public struct ScriptRunLimits: Equatable, Sendable {
    /// The budget a script gets when its declaration names none.
    public var defaultTimeout: TimeInterval
    /// The largest budget a declaration may ask for, whatever it says.
    public var maximumTimeout: TimeInterval
    /// Slack added on top of the declared budget before the run is abandoned,
    /// so a script that is about to answer is not cut off by scheduler jitter.
    public var grace: TimeInterval
    /// How many runs may execute at once. Each is a context of its own; the
    /// cap keeps a busy page from holding a hundred VMs.
    public var concurrentRuns: Int
    /// Largest script body that will be loaded, in bytes.
    public var maximumScriptBytes: Int
    /// Consecutive timeouts after which a script is not run again in this
    /// process. A script that cannot finish in its budget once will keep
    /// failing, and every attempt costs the proxy a stalled request.
    public var timeoutsBeforeRefusal: Int

    public init(defaultTimeout: TimeInterval = 5, maximumTimeout: TimeInterval = 300,
                grace: TimeInterval = 5, concurrentRuns: Int = 6,
                maximumScriptBytes: Int = 8 << 20, timeoutsBeforeRefusal: Int = 3) {
        self.defaultTimeout = defaultTimeout
        self.maximumTimeout = maximumTimeout
        self.grace = grace
        self.concurrentRuns = max(1, concurrentRuns)
        self.maximumScriptBytes = maximumScriptBytes
        self.timeoutsBeforeRefusal = max(1, timeoutsBeforeRefusal)
    }

    /// The wall-clock budget for a declaration, grace included.
    public func budget(for declared: TimeInterval?) -> TimeInterval {
        let asked = declared.map { min(maximumTimeout, max(0, $0)) } ?? defaultTimeout
        return asked + max(0, grace)
    }
}

/// Counters a host can publish.
public struct ScriptMetrics: Equatable, Sendable {
    public var runs = 0
    public var unchanged = 0
    public var changedRequests = 0
    public var changedResponses = 0
    public var mocked = 0
    public var aborted = 0
    public var timedOut = 0
    public var refused = 0
    public var failed = 0
    public var timedOutTotal = 0

    public init() {}
}

/// Runs one script against one request/response.
///
/// The runner owns the bookkeeping that must not depend on the engine: the
/// budget, the concurrency cap, the timeout history and the outcome. The engine
/// only evaluates and delivers.
///
/// A run is abandoned, not interrupted. JavaScriptCore has no public way to stop
/// a running script, so a script that never returns keeps its thread until it
/// does; what the proxy gets is the original traffic, at the deadline, and the
/// script is refused after repeated timeouts so the cost is paid a few times and
/// not for every request.
public final class ScriptRunner: @unchecked Sendable {
    public typealias EngineFactory = @Sendable (_ identity: ScriptIdentity, _ phase: ScriptPhase) throws -> JSEngine

    private let limits: ScriptRunLimits
    private let services: ScriptHostServices
    private let makeEngine: EngineFactory
    private let queue: DispatchQueue
    private let lock = NSLock()

    private var active = 0
    private var waiting: [@Sendable () -> Void] = []
    private var timeouts: [String: Int] = [:]
    private var refused: Set<String> = []
    private var metricsStorage = ScriptMetrics()

    public init(limits: ScriptRunLimits = ScriptRunLimits(), services: ScriptHostServices,
                queue: DispatchQueue = DispatchQueue(label: "adblock.scripts", qos: .userInitiated),
                makeEngine: @escaping EngineFactory) {
        self.limits = limits
        self.services = services
        self.queue = queue
        self.makeEngine = makeEngine
    }

    public var metrics: ScriptMetrics {
        lock.lock(); defer { lock.unlock() }
        return metricsStorage
    }

    /// Forgets every timeout and refusal. Called when a module changes, since a
    /// fixed script deserves a fresh budget.
    public func forgetHistory() {
        lock.lock()
        timeouts.removeAll()
        refused.removeAll()
        lock.unlock()
    }

    /// Runs `script` and reports the outcome on `queue`.
    public func run(script: ScriptSource, request: ScriptRequest, response: ScriptResponse?,
                    identity: ScriptIdentity,
                    completion: @escaping @Sendable (ScriptOutcome) -> Void) {
        guard script.byteCount <= limits.maximumScriptBytes else {
            completion(.unavailable("the script is larger than \(limits.maximumScriptBytes) bytes"))
            return
        }
        enqueue { [weak self] in
            self?.start(script: script, request: request, response: response, identity: identity,
                        completion: completion)
        }
    }

    /// A scheduled run, which has no traffic behind it: a cron or generic script
    /// gets a request-shaped context with the platform's own placeholder so
    /// scripts that read `$request.url` at the top do not throw.
    public func runScheduled(script: ScriptSource, identity: ScriptIdentity,
                             parameters: ScriptRunParameters = ScriptRunParameters(),
                             completion: @escaping @Sendable (ScriptOutcome) -> Void) {
        let placeholder = ScriptRequest(method: "GET", url: "https://clash.invalid/cron", headers: ScriptHeaders())
        // The entry parameters travel on the source, because that is what the
        // run reads: the same script run from two nodes must be able to report
        // two different nodes, and a copy is the only way to say that.
        var source = script
        source.parameters = parameters
        run(script: source, request: placeholder, response: nil, identity: identity,
            completion: completion)
    }

    // MARK: - Admission

    private func enqueue(_ work: @escaping @Sendable () -> Void) {
        lock.lock()
        if active < limits.concurrentRuns {
            active += 1
            lock.unlock()
            work()
        } else {
            waiting.append(work)
            lock.unlock()
        }
    }

    fileprivate func release() {
        lock.lock()
        if waiting.isEmpty {
            active = max(0, active - 1)
            lock.unlock()
        } else {
            let next = waiting.removeFirst()
            lock.unlock()
            queue.async(execute: next)
        }
    }

    // MARK: - A run

    private func start(script: ScriptSource, request: ScriptRequest, response: ScriptResponse?,
                       identity: ScriptIdentity,
                       completion: @escaping @Sendable (ScriptOutcome) -> Void) {
        let key = script.key
        lock.lock()
        let isRefused = refused.contains(key)
        let budget = limits.budget(for: script.timeout)
        lock.unlock()

        if isRefused {
            count { $0.refused += 1 }
            release()
            return completion(.unavailable("the script ran past its budget \(limits.timeoutsBeforeRefusal) times and is not run again"))
        }

        let run = ScriptRun(script: script, request: request, response: response, services: services,
                            identity: identity, makeEngine: makeEngine,
                            defaultTimeout: limits.defaultTimeout)
        let finished = RunCompletion(completion: completion, runner: self)

        // The watchdog runs on its own queue so a busy script queue cannot delay
        // it: an answer that arrives at the deadline is worth nothing to the
        // request it was holding.
        let watchdog = DispatchWorkItem { [weak self, weak run] in
            guard finished.claim() else { return }
            guard let self else { return }
            // Waking the run's thread is what lets an abandoned run release
            // its context instead of waiting for a script that never returns.
            run?.abandon()
            self.noteTimeout(key)
            self.count { $0.timedOut += 1; $0.timedOutTotal += 1 }
            self.services.log("script \(script.name) gave no answer within \(Int(budget)) s; the traffic goes on unchanged", level: "warning")
            finished.deliver(.timedOut)
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + budget, execute: watchdog)

        run.begin { [weak self] outcome in
            watchdog.cancel()
            guard finished.claim() else { return }
            guard let self else { return }
            // A timeout can now arrive from the run itself: the engine stops a
            // spinning script at its limit, so the run finishes before the
            // watchdog fires. Counting the timeout only in the watchdog would
            // make `timeoutsBeforeRefusal` never trip for exactly the scripts it
            // exists for, which is how this was found — the spin test stopped
            // being refused.
            if case .timedOut = outcome {
                self.noteTimeout(key)
                self.count { $0.timedOut += 1; $0.timedOutTotal += 1 }
            }
            self.record(outcome, script: script)
            finished.deliver(outcome)
        }
    }

    private func noteTimeout(_ key: String) {
        lock.lock()
        let count = (timeouts[key] ?? 0) + 1
        timeouts[key] = count
        if count >= limits.timeoutsBeforeRefusal { refused.insert(key) }
        lock.unlock()
    }

    private func record(_ outcome: ScriptOutcome, script: ScriptSource) {
        if case .unchanged = outcome {
            lock.lock(); timeouts[script.key] = 0; lock.unlock()
        }
        count { metrics in
            metrics.runs += 1
            switch outcome {
            case .unchanged: metrics.unchanged += 1
            case .request: metrics.changedRequests += 1
            case .response(let response):
                if response.status == 200 || true { metrics.changedResponses += 1 }
            case .drop: metrics.aborted += 1
            case .aborted: metrics.aborted += 1
            case .timedOut: metrics.timedOut += 1
            case .unavailable: metrics.failed += 1
            // A cron/generic script answering with a result changed nothing
            // about any traffic; it produced something to show.
            case .result: metrics.unchanged += 1
            }
        }
    }

    private func count(_ change: (inout ScriptMetrics) -> Void) {
        lock.lock()
        change(&metricsStorage)
        lock.unlock()
    }
}

/// The one-shot latch a run's completion goes through, so a late answer and the
/// watchdog cannot both deliver.
private final class RunCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false
    private let completion: @Sendable (ScriptOutcome) -> Void
    private unowned let runner: ScriptRunner

    init(completion: @escaping @Sendable (ScriptOutcome) -> Void, runner: ScriptRunner) {
        self.completion = completion
        self.runner = runner
    }

    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }

    func deliver(_ outcome: ScriptOutcome) {
        completion(outcome)
        runner.release()
    }
}

/// What Loon puts in `$environment.params` when a script is run from the node
/// or policy it is attached to.
///
/// Loon's manual, §3.4: "手动或 Generic 脚本从节点、策略等入口运行时，Loon 会把入口
/// 参数放在 `$environment.params`。没有运行参数时，`$environment` 可能不存在。" The
/// fields it lists are `node`, `nodeInfo`, `policyGroup` and `proxyChainInfo`.
///
/// The distinction that matters for compatibility is `nil` versus an empty
/// value, and scripts disagree about which spelling they expect:
///
/// * `NodeLinkCheck.js` reads `$environment['params']` as a **string** — the old
///   Loon form, where the entry parameter *was* the node name.
/// * `NodeUnlockDetection.js` reads `$environment.params.node`.
///
/// So `params` cannot be normalised to one shape without breaking the other.
/// `entry` carries the string form; the named fields carry the object form. A
/// run with neither leaves `$environment` off entirely, which is what the
/// manual says happens and what a `typeof $environment === "undefined"` guard
/// (the one Loon's own example uses) is written for.
public struct ScriptRunParameters: Equatable, Sendable {
    /// The node name, and the old string form of `$environment.params`.
    public var node: String?
    /// A short description of the node, without credentials.
    public var nodeInfo: String?
    public var policyGroup: String?
    public var proxyChainInfo: String?

    public init(node: String? = nil, nodeInfo: String? = nil,
                policyGroup: String? = nil, proxyChainInfo: String? = nil) {
        self.node = node
        self.nodeInfo = nodeInfo
        self.policyGroup = policyGroup
        self.proxyChainInfo = proxyChainInfo
    }

    /// Whether anything at all was supplied. A run with no entry parameters
    /// must not carry a `params` object, because a script asking for
    /// `params.node` would then get `undefined` instead of noticing that there
    /// were no parameters at all.
    public var isEmpty: Bool {
        node == nil && nodeInfo == nil && policyGroup == nil && proxyChainInfo == nil
    }

    /// The object form, for scripts that read `params.node`.
    var object: [String: Any] {
        var out: [String: Any] = [:]
        if let node { out["node"] = node }
        if let nodeInfo { out["nodeInfo"] = nodeInfo }
        if let policyGroup { out["policyGroup"] = policyGroup }
        if let proxyChainInfo { out["proxyChainInfo"] = proxyChainInfo }
        return out
    }

    /// The string form, for scripts that treat `params` as the node name.
    var string: String? { node }
}

/// A script as the runner receives it: where it came from, what it costs, and
/// how long it may take.
public struct ScriptSource: Equatable, Sendable {
    public var name: String
    /// Stable identity for timeout bookkeeping: module id plus script hash.
    public var key: String
    public var text: String
    public var timeout: TimeInterval?
    /// The URL the script was fetched from, for stack traces.
    public var sourceURL: String?
    /// What the script receives as `$argument`, in the form the plugin wrote
    /// it: a string, an object of its `[Argument]` values, or nothing.
    public var argument: ScriptArgument
    /// Whether the declaration said `binary-body-mode`, which decides whether
    /// the script sees `Uint8Array` or text.
    public var binaryBody: Bool
    /// What Loon puts in `$environment.params`: the node or policy a generic
    /// script was run from. Empty for every other phase, because a request
    /// script has no entry parameters to report.
    public var parameters: ScriptRunParameters

    public init(name: String, key: String, text: String, timeout: TimeInterval? = nil,
                sourceURL: String? = nil, argument: ScriptArgument = .none,
                binaryBody: Bool = false, parameters: ScriptRunParameters = ScriptRunParameters()) {
        self.name = name
        self.key = key
        self.text = text
        self.timeout = timeout
        self.sourceURL = sourceURL
        self.argument = argument
        self.binaryBody = binaryBody
        self.parameters = parameters
    }

    public var byteCount: Int { text.utf8.count }
}
