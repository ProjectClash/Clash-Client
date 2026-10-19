#if os(iOS) || os(macOS)
import AdBlockScriptKit
import Foundation

/// Runs module scripts in the tunnel.
///
/// This is the only piece of the script feature that touches the proxy: it
/// implements `AdBlockScriptRunning`, which `AdBlockExchange` already calls at
/// its request and response stages, and does four things the exchange cannot:
///
/// * reads the script's text from the module directory, with a short cache so a
///   page's worth of requests does not re-read the same file;
/// * turns the declaration's arguments into `$argument`, applying the user's
///   choices over the module's defaults;
/// * decides which platform identity the script sees (the module's dialect);
/// * hands HTTP made by the script to the tunnel's own connector, so it obeys
///   the same routing as the app's traffic and cannot reach around the proxy.
///
/// Everything else — the platform APIs, `$done` normalisation, budgeting — is in
/// `AdBlockScriptKit`, which is tested off-device.
final class AdBlockScriptRunner: AdBlockScriptRunning {
    /// How long a script's text is kept. A module is republished as a whole, so
    /// a file's content only changes when its hash changes; the cache is keyed
    /// by that hash and cannot serve a stale script.
    private static let cacheLimit = 32

    private let queue: DispatchQueue
    private let log: AdBlockEngineLog
    private let argumentChoices: [String: String]
    private var host: AdBlockScriptHost?
    private var runner: ScriptRunner
    private let lock = NSLock()
    private var cache: [String: String] = [:]
    private var cacheOrder: [String] = []
    private var sink: AdBlockScriptSink?
    private var available = false

    init(queue: DispatchQueue, log: AdBlockEngineLog,
         argumentChoices: [String: String] = [:],
         limits: ScriptRunLimits = ScriptRunLimits()) {
        self.queue = queue
        self.log = log
        self.argumentChoices = argumentChoices
        self.limits = limits
        // Until the tunnel hands over its connector and storage, a run has
        // nowhere to send a script's HTTP; `nil` services answer "unavailable",
        // which is what a build without scripts already says.
        self.runner = ScriptRunner(limits: limits, services: AdBlockScriptHost.placeholder(queue: queue, log: log),
                                   queue: queue, makeEngine: { _, _ in try JSCEngine() })
    }

    private let limits: ScriptRunLimits

    /// Hands the runner the tunnel's connector and storage. Called once, when
    /// the engine is assembled; a script run starts only after this.
    func adopt(upstreams: AdBlockUpstreamOpening, storageURL: URL?) {
        lock.lock()
        defer { lock.unlock() }
        guard host == nil else { return }
        let host = AdBlockScriptHost(queue: queue, log: log, upstreams: upstreams, storageURL: storageURL)
        self.host = host
        runner = ScriptRunner(limits: limits, services: host, queue: queue,
                              makeEngine: { _, _ in try JSCEngine() })
        available = true
    }

    var isAvailable: Bool {
        lock.lock(); defer { lock.unlock() }
        return available && host != nil
    }

    func attach(_ sink: AdBlockScriptSink) {
        lock.lock(); self.sink = sink; lock.unlock()
    }

    func releaseAll() {
        lock.lock()
        cache.removeAll()
        cacheOrder.removeAll()
        lock.unlock()
        runner.forgetHistory()
    }

    // MARK: - Runs

    func run(_ match: AdBlockScriptMatch, request: AdBlockScriptRequest,
             completion: @escaping (AdBlockScriptOutcome) -> Void) {
        run(match, request: request, response: nil, completion: completion)
    }

    func run(_ match: AdBlockScriptMatch, request: AdBlockScriptRequest, response: AdBlockScriptResponse,
             completion: @escaping (AdBlockScriptOutcome) -> Void) {
        run(match, request: request, response: response, completion: completion)
    }

    private func run(_ match: AdBlockScriptMatch, request: AdBlockScriptRequest, response: AdBlockScriptResponse?,
                     completion: @escaping (AdBlockScriptOutcome) -> Void) {
        guard host != nil else {
            completion(.unavailable("the script runner has not been given a host"))
            sink?.scriptsUnavailable("the script runner has not started")
            return
        }
        guard let file = match.bodyFile else {
            return completion(.unavailable("its script has not been downloaded yet"))
        }
        let text: String
        do {
            text = try scriptText(at: file, key: match.script.bodySHA256 ?? file.lastPathComponent)
        } catch {
            return completion(.unavailable("its script could not be read"))
        }

        let source = ScriptSource(
            name: match.script.name,
            key: "\(match.moduleID)/\(match.script.bodySHA256 ?? match.script.name)",
            text: text,
            timeout: match.script.timeout.map(TimeInterval.init),
            sourceURL: match.script.scriptURL,
            argument: arguments(for: match.script),
            binaryBody: match.script.binaryBodyMode)

        let requestBody = match.script.requiresBody ? request.body : nil
        let origin = AdBlockScriptKit.ScriptRequest(
            id: request.id, method: request.method, url: request.url,
            headers: ScriptHeaders(request.headers.fields.map { (name: $0.name, value: $0.value) }),
            body: requestBody)
        var originResponse: AdBlockScriptKit.ScriptResponse?
        if let response {
            originResponse = AdBlockScriptKit.ScriptResponse(
                status: response.status,
                headers: ScriptHeaders(response.headers.fields.map { (name: $0.name, value: $0.value) }),
                body: match.script.requiresBody ? response.body : nil)
        }

        // The exchange wraps the completion in a call that hops to the engine
        // queue itself, so answering from this thread is what it expects.
        runner.run(script: source, request: origin, response: originResponse,
                   identity: identity(for: match)) { [weak self] outcome in
            guard let self else { return }
            completion(self.translate(outcome))
        }
    }

    /// The platform a script believes it is on.
    ///
    /// The module's dialect is the evidence: a `.lpx` plugin's scripts were
    /// written for Loon, a `.sgmodule`'s for Surge, a Stash override's for
    /// Stash, and a Quantumult X rewrite for Quantumult X. A script that was
    /// published by one platform and written against another's API is common,
    /// and this is what those scripts assume.
    private func identity(for match: AdBlockScriptMatch) -> ScriptIdentity {
        let platform = ScriptPlatform(moduleFormat: match.moduleFormat.rawValue) ?? .loon
        return ScriptIdentity(platform: platform, device: Self.device, systemVersion: Self.systemVersion)
    }

    /// The system version as a script expects it: `18.0`, not
    /// `Version 18.0 (Build 22A3354)`. `$loon` is split on spaces by the
    /// libraries that read it, so a version with spaces in it would be read as
    /// a build number.
    private static var systemVersion: String {
        let text = ProcessInfo.processInfo.operatingSystemVersionString
        guard let range = text.range(of: #"\d+(\.\d+)*"#, options: .regularExpression) else { return "18.0" }
        return String(text[range])
    }

    private static var device: String {
#if os(macOS)
        return "Mac"
#else
        return "iPhone"
#endif
    }

    /// `$argument`: the module's defaults, with the user's choices applied.
    ///
    /// A declaration with no default and no user choice is left out rather than
    /// given an empty string, because scripts test `typeof $argument.x`, and a
    /// boolean declaration must arrive as a boolean.
    private func arguments(for script: AdBlockScript) -> [String: ScriptArgumentValue] {
        var out: [String: ScriptArgumentValue] = [:]
        for argument in script.argumentDefaults ?? [] {
            let chosen = argumentChoices[argumentKey(script: script, name: argument.name)]
            guard let value = chosen ?? argument.defaultValue else { continue }
            out[argument.name] = ScriptArgumentValue(value, kind: argument.kind)
        }
        // A script may also have been declared with a single `argument=` string;
        // that string is the whole argument, as on Surge.
        if out.isEmpty, let single = script.argument, !single.isEmpty {
            out["argument"] = .text(single)
        }
        return out
    }

    private func argumentKey(script: AdBlockScript, name: String) -> String {
        "\(script.scriptURL)#\(name)"
    }

    // MARK: - Reading

    private func scriptText(at url: URL, key: String) throws -> String {
        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ScriptReadError.notText
        }
        lock.lock()
        cache[key] = text
        cacheOrder.append(key)
        while cacheOrder.count > Self.cacheLimit {
            cache.removeValue(forKey: cacheOrder.removeFirst())
        }
        lock.unlock()
        return text
    }

    private enum ScriptReadError: Error { case notText }

    // MARK: - Translating outcomes

    private func translate(_ outcome: AdBlockScriptKit.ScriptOutcome) -> AdBlockScriptOutcome {
        switch outcome {
        case .unchanged:
            return .unchanged
        case .request(let changed):
            return .request(AdBlockScriptRequest(
                id: changed.id, method: changed.method, url: changed.url,
                headers: AdBlockHTTPHeaders(changed.headers.fields.map {
                    AdBlockHTTPField(name: $0.name, value: $0.value)
                }),
                body: changed.body))
        case .response(let changed):
            return .response(AdBlockScriptResponse(
                status: changed.status,
                headers: AdBlockHTTPHeaders(changed.headers.fields.map {
                    AdBlockHTTPField(name: $0.name, value: $0.value)
                }),
                body: changed.body))
        case .drop(let why):
            return .drop(why)
        case .aborted(let why):
            return .aborted(why)
        case .timedOut:
            return .timedOut
        case .unavailable(let why):
            return .unavailable(why)
        }
    }
}
#endif
