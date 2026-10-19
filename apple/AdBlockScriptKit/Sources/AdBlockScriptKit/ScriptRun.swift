import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// One execution: prepares a context, hands it the prelude, the environment and
/// the script, and waits for `$done`.
///
/// The prelude is the only thing that knows what a platform looks like from
/// JavaScript. This type only gives it facts (who am I, what was asked, what the
/// traffic is) and forwards the primitives it calls.
///
/// Each run owns a thread for the life of its context. JavaScriptCore allows a
/// context to be used from more than one thread, but not at the same time
/// without the API lock, and a script's asynchronous half — an HTTP callback, a
/// timer — has to be evaluated somewhere. Owning a thread means every evaluation
/// for a run happens in order on one thread, and a run that never returns costs
/// exactly one thread until it ends.
final class ScriptRun: @unchecked Sendable {
    typealias EngineFactory = (ScriptIdentity, ScriptPhase) throws -> JSEngine

    private let script: ScriptSource
    private let request: ScriptRequest
    private let response: ScriptResponse?
    private let services: ScriptHostServices
    private let identity: ScriptIdentity
    private let makeEngine: EngineFactory
    private let phase: ScriptPhase
    /// The budget a declaration that names none still gets. Needed here, not
    /// only in the runner: the engine's own execution limit is set from it.
    private let defaultTimeout: TimeInterval

    private let lock = NSLock()
    private var finished = false
    private var delivered: ((ScriptOutcome) -> Void)?
    private var timerIDs: [Int: DispatchWorkItem] = [:]
    private var engine: JSEngine?
    private let started = Date()

    private var thread: Thread?
    /// Keeps the run alive while its thread serves callbacks. The runner holds
    /// only a weak reference for the watchdog, so without this the run would be
    /// collected the moment `begin` returns.
    private var keepAlive: ScriptRun?
    private var pending: [() -> Void] = []

    init(script: ScriptSource, request: ScriptRequest, response: ScriptResponse?,
         services: ScriptHostServices, identity: ScriptIdentity, makeEngine: @escaping EngineFactory,
         defaultTimeout: TimeInterval) {
        self.script = script
        self.request = request
        self.response = response
        self.services = services
        self.identity = identity
        self.makeEngine = makeEngine
        self.defaultTimeout = defaultTimeout
        self.phase = response == nil ? .request : .response
    }

    /// Starts the run. `completion` is called exactly once.
    func begin(completion: @escaping (ScriptOutcome) -> Void) {
        lock.lock()
        delivered = completion
        lock.unlock()

        keepAlive = self
        let worker = Thread { [weak self] in self?.main() }
        worker.stackSize = 1 << 20
        thread = worker
        worker.start()
    }

    /// Everything that touches the context, in order, on the run's own thread.
    private func main() {
        let engine: JSEngine
        do {
            engine = try makeEngine(identity, phase)
        } catch {
            finish(.unavailable("no JavaScript engine: \(error)"))
            return
        }
        lock.lock()
        self.engine = engine
        lock.unlock()

        let hooks = JSEngineHooks(
            hostCall: { [weak self] name, payload, callback in
                self?.hostCall(name, payload, callback)
            },
            log: { [weak self] line, level in
                self?.services.log(line, level: level)
            },
            schedule: { [weak self] delay, id in
                self?.schedule(delay, id: id)
            },
            cancelTimer: { [weak self] id in
                self?.cancelTimer(id)
            },
            now: { [started] in Date().timeIntervalSince(started) * 1000 }
        )

        do {
            try engine.install(hooks)
            engine.setSynchronousServices(self)
            try engine.evaluate(ScriptPrelude.source, sourceURL: "clash-prelude.js")
        } catch {
            finish(.unavailable("the prelude did not load: \(error)"))
            return
        }

        var environment = ScriptEnvironment(
            identity: identity, request: request, response: response,
            argument: script.argument, scriptName: script.name)
        environment.binaryBody = script.binaryBody
        environment.parameters = script.parameters
        guard let bootstrap = environment.bootstrapJSON else {
            finish(.unavailable("the environment could not be encoded"))
            return
        }
        do {
            try engine.evaluate("__clashBootstrap(\(bootstrap));", sourceURL: "clash-bootstrap.js")
            // The prelude and the bootstrap are trusted and cheap; the script
            // is neither. Its declared budget is what the limit is: a script
            // that loops forever is stopped by JavaScriptCore at the same
            // moment the runner would otherwise only stop listening, so it
            // cannot hold a thread — or one of the runner's `concurrentRuns`
            // slots — for the life of the process.
            engine.setExecutionTimeLimit(script.timeout ?? defaultTimeout)
            try engine.evaluate(script.text, sourceURL: script.sourceURL)
        } catch {
            // Termination is reported as a timeout, not as a script error: the
            // script did not throw, the engine stopped it, and the request it
            // was holding has already been let through unchanged.
            if isTermination(error) {
                finish(.timedOut)
            } else {
                finish(.aborted("the script threw: \(error)"))
            }
            return
        }

        // The script may have finished synchronously. If it did not, the thread
        // now serves its callbacks and timers until the run ends.
        drain()
    }

    /// Whether the engine stopped the script rather than the script throwing.
    ///
    /// JavaScriptCore reports termination as an ordinary exception whose text is
    /// "JavaScript execution terminated." — there is no error code to test, so
    /// this reads the message. A script that threw a `SyntaxError` mentioning
    /// the same words would be misread, which is why the whole phrase is matched
    /// rather than a substring of it.
    private func isTermination(_ error: Error) -> Bool {
        guard let engineError = error as? JSEngineError else { return false }
        return engineError.message == "JavaScript execution terminated."
            || engineError.message == "JavaScript execution terminated"
    }

    /// Runs queued work until the run finishes. Returns when `finish` has run or
    /// the queue is empty and nothing more can arrive.
    private func drain() {
        while true {
            queueCondition.lock()
            let next = pending.isEmpty ? nil : pending.removeFirst()
            queueCondition.unlock()
            if let next {
                next()
                continue
            }
            if isFinished { return }
            // Nothing queued: wait for work or for the end. The watchdog ends
            // the run through `abandon`, which broadcasts this condition.
            queueCondition.lock()
            if pending.isEmpty && !isFinished { queueCondition.wait() }
            let ended = isFinished
            queueCondition.unlock()
            if ended && pending.isEmpty { return }
        }
    }

    private let queueCondition = NSCondition()

    /// Queues work on the run's thread. Safe from any thread.
    private func perform(_ work: @escaping () -> Void) {
        queueCondition.lock()
        pending.append(work)
        queueCondition.signal()
        queueCondition.unlock()
    }

    // MARK: - Host calls

    private func hostCall(_ name: String, _ payload: Data, _ callback: Int) {
        switch name {
        case "done":
            let done = ScriptJSON.payload(ScriptJSON.decode(payload))
            let outcome: ScriptOutcome
            if let response {
                outcome = ScriptDoneParsing.responseOutcome(done, base: response)
            } else {
                outcome = ScriptDoneParsing.requestOutcome(done, base: request)
            }
            // `$done` is called inside an evaluation; ending the run here would
            // unwind the queue from under the engine, so it is deferred to the
            // thread that owns the context.
            perform { [weak self] in self?.finish(outcome) }
        case "notify":
            if let object = ScriptJSON.decode(payload) as? [String: Any] {
                services.notify(ScriptNotification(
                    title: ScriptJSON.string(object["title"]) ?? "",
                    subtitle: ScriptJSON.string(object["subtitle"]) ?? "",
                    body: ScriptJSON.string(object["body"]) ?? "",
                    openURL: ScriptJSON.string(object["openUrl"]),
                    mediaURL: ScriptJSON.string(object["mediaUrl"]),
                    clipboard: ScriptJSON.string(object["clipboard"]),
                    autoDismiss: object["autoDismiss"].map { ScriptJSON.flag($0) },
                    sound: object["sound"].map { ScriptJSON.flag($0) }))
            }
        default:
            let call = ScriptHostCall(name: name, payload: payload)
            services.perform(call) { [weak self] answer in
                guard let self, callback >= 0 else { return }
                self.perform {
                    guard let engine = self.engineOnQueue(), !self.isFinished else { return }
                    engine.resolve(callbackID: callback, answer: answer)
                }
            }
        }
    }

    // MARK: - Synchronous calls

    /// Answers `$persistentStore` and `$config` on the calling thread.
    ///
    /// Host storage is unspecified on the calling thread, so the answer is
    /// fetched here: either the services implement the synchronous slice (the
    /// tunnel and the tests do) or a bounded wait is made on the asynchronous
    /// one. The wait is bounded because a script's synchronous call cannot be
    /// allowed to hold its thread forever.
    private func synchronousAnswerOnQueue(_ name: String, _ payload: Data) -> String {
        if let sync = services as? ScriptSynchronousServices {
            return sync.synchronousAnswer(name: name, payload: payload)
        }
        final class Box: @unchecked Sendable {
            let lock = NSLock()
            var value: ScriptHostAnswer?
            var done = false
        }
        let box = Box()
        let ready = DispatchSemaphore(value: 0)
        services.perform(ScriptHostCall(name: name, payload: payload)) { answer in
            box.lock.lock(); box.value = answer; box.done = true; box.lock.unlock()
            ready.signal()
        }
        if ready.wait(timeout: .now() + 2) == .timedOut { return "null" }
        return box.value.map { String(decoding: $0.value, as: UTF8.self) } ?? "null"
    }

    // MARK: - Timers

    private func schedule(_ delay: Double, id: Int) {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let done = self.finished
            self.timerIDs.removeValue(forKey: id)
            self.lock.unlock()
            guard !done else { return }
            self.perform {
                self.engineOnQueue()?.fireTimer(id)
            }
        }
        lock.lock()
        timerIDs[id] = work
        lock.unlock()
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + max(0, delay) / 1000, execute: work)
    }

    private func cancelTimer(_ id: Int) {
        lock.lock()
        let work = timerIDs.removeValue(forKey: id)
        lock.unlock()
        work?.cancel()
    }

    // MARK: - Completion

    private var isFinished: Bool {
        lock.lock(); defer { lock.unlock() }
        return finished
    }

    private func engineOnQueue() -> JSEngine? {
        lock.lock(); defer { lock.unlock() }
        return engine
    }

    private func finish(_ outcome: ScriptOutcome) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        finished = true
        let completion = delivered
        delivered = nil
        let timers = Array(timerIDs.values)
        timerIDs.removeAll()
        lock.unlock()
        for timer in timers { timer.cancel() }
        queueCondition.lock()
        queueCondition.broadcast()
        queueCondition.unlock()
        completion?(outcome)
        // The run's thread returns after the broadcast; dropping the last
        // reference here is what releases the context.
        keepAlive = nil
    }

    /// Wakes the run's thread so it can notice that the run is over. Called by
    /// the runner when it gives up on a script.
    func abandon() {
        lock.lock()
        let engine = self.engine
        lock.unlock()
        engine?.abandon()
        finish(.timedOut)
    }
}

extension ScriptRun: ScriptSynchronousServices {
    func synchronousAnswer(name: String, payload: Data) -> String {
        synchronousAnswerOnQueue(name, payload)
    }
}

/// The identity, traffic and arguments handed to the prelude.
public struct ScriptEnvironment: Sendable {
    public var identity: ScriptIdentity
    public var request: ScriptRequest
    public var response: ScriptResponse?
    public var argument: ScriptArgument
    public var scriptName: String

    public init(identity: ScriptIdentity, request: ScriptRequest, response: ScriptResponse? = nil,
                argument: ScriptArgument = .none, scriptName: String = "") {
        self.identity = identity
        self.request = request
        self.response = response
        self.argument = argument
        self.scriptName = scriptName
    }

    /// The bootstrap object, JSON encoded, called by the prelude at start.
    var bootstrapJSON: String? {
        var object: [String: Any] = [
            "platform": identity.platform.rawValue,
            "version": identity.version,
            "device": identity.device,
            "systemVersion": identity.systemVersion,
            "appName": identity.appName,
            "loon": identity.loonString,
            "scriptName": scriptName,
            "phase": response == nil ? "request" : "response",
            "binaryBody": binaryBody,
            "request": ScriptEnvironment.encode(request)
        ]
        var args: [String: Any] = [:]
        // The host sends the form, not a normalised object: the prelude
        // installs exactly what the plugin wrote.
        switch argument {
        case .none:
            object["argumentKind"] = "none"
        case .text(let text):
            object["argumentKind"] = "text"
            object["argumentText"] = text
        case .values(let values):
            var args: [String: Any] = [:]
            for (key, value) in values { args[key] = value.jsonObject }
            object["argumentKind"] = "values"
            object["argument"] = args
        }
        if let response { object["response"] = ScriptEnvironment.encode(response) }
        // Loon only defines `$environment.params` when a script is run *from* a
        // node or policy, which is the case for cron and generic scripts. An
        // empty set is left out rather than sent as `{}`, because the manual
        // says `$environment` may be absent and the guard scripts write is
        // `typeof $environment === "undefined"`.
        if !parameters.isEmpty {
            object["parameters"] = parameters.object
            if let node = parameters.string { object["parameterEntry"] = node }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Whether the script was declared `binary-body-mode`, which decides whether
    /// `$request.body`/`$response.body` are `Uint8Array` or text.
    public var binaryBody = false

    /// The node or policy a generic script was run from, for
    /// `$environment.params`.
    public var parameters = ScriptRunParameters()

    static func encode(_ request: ScriptRequest) -> [String: Any] {
        var object: [String: Any] = ["url": request.url, "method": request.method,
                                     "headers": request.headers.dictionary]
        if let body = request.body { object["body"] = [ScriptJSON.bytesMarker: body.base64EncodedString()] }
        return object
    }

    static func encode(_ response: ScriptResponse) -> [String: Any] {
        var object: [String: Any] = ["status": response.status, "headers": response.headers.dictionary]
        if let body = response.body { object["body"] = [ScriptJSON.bytesMarker: body.base64EncodedString()] }
        return object
    }
}
