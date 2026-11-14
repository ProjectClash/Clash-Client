#if os(iOS) || os(macOS)
import Foundation
import JavaScriptCore

 
 
 
 
 
 
struct ModuleScriptServices {
    var log: (String) -> Void
    var notify: (ModuleScriptNotificationRequest) -> Void
     
    var geoip: (String) -> String?
     
    var selectPolicy: (_ group: String, _ policy: String) -> Bool
    var environment: ModuleScriptEnvironment
     
     
    var network: any ModuleScriptNetworking = ModuleScriptNoNetwork()
     
     
     
     
    var installWebGlobals: ((JSContext) -> Bool)? = { ModuleScriptWebGlobals.install(into: $0) }
     
     
     
     
    var installDOM: ((JSContext, Int?) -> Bool)? = { ModuleScriptDOM.install(into: $0, maximumSourceBytes: $1) }
     
     
     
     
    var config: ModuleScriptConfigAccess = .unavailable
     
     
    var dns: ModuleScriptDNSAccess = .unavailable
}

 
struct ModuleScriptDNSQuery: Equatable, Sendable {
    var domain: String
     
     
     
    var protocolName: String?
     
    var server: String?
    var timeoutMilliseconds: Int
}

 
struct ModuleScriptDNSRecord: Equatable, Sendable {
    var name: String
    var type: String
    var value: String
    var ttl: Int
}

struct ModuleScriptDNSResult: Equatable, Sendable {
    var domain: String
    var protocolName: String
    var server: String
    var fromCache: Bool
    var answers: [ModuleScriptDNSRecord]
}

 
 
 
struct ModuleScriptDNSFailure: Error, Equatable, Sendable {
    var code: String
    var message: String
}

 
 
struct ModuleScriptDNSAccess {
    var query: (ModuleScriptDNSQuery, @escaping @Sendable (Result<ModuleScriptDNSResult, ModuleScriptDNSFailure>) -> Void) -> Void

    static let unavailable = ModuleScriptDNSAccess { _, completion in
        completion(.failure(ModuleScriptDNSFailure(code: #"UNAVAILABLE"#, message: #"no DNS to ask here"#)))
    }
}

 
 
 
 
struct ModuleScriptPolicy: Equatable, Sendable {
    var name: String
    var kind: String
}

 
struct ModuleScriptConfigAccess {
     
    var isAvailable: () -> Bool
     
    var mode: () -> String?
    var setMode: (String) -> Bool
     
    var groups: () -> [String]
     
    var members: (_ group: String, _ limit: Int) -> [ModuleScriptPolicy]?
     
    var selected: (_ group: String) -> String?
     
    var final: () -> String?
     
    var builtins: () -> [String]
     
     
    var groupTypes: () -> [String: String] = { [:] }
     
     
     
     
    var globalRefusal: () -> String? = { nil }

    static let unavailable = ModuleScriptConfigAccess(
        isAvailable: { false }, mode: { nil }, setMode: { _ in false }, groups: { [] }, members: { _, _ in nil },
        selected: { _ in nil }, final: { nil }, builtins: { [] })
}

 
struct ModuleScriptNotificationRequest: Equatable, Sendable {
    var scriptName: String
    var title: String
    var subtitle: String
    var body: String
     
     
    var openURL: String?
     
     
    var clipboardText: String?
    var sound: Bool
     
     
    var mediaURL: String? = nil
     
    var delaySeconds: Double? = nil
}

 
 
 
 
 
struct ModuleScriptSessionLimits: Equatable, Sendable {
     
    var maximumConsoleLineBytes = 65_536
     
     
    var maximumPendingRequests: Int
    var memory: ModuleScriptMemory = .process

    init(_ run: ModuleScriptLimitsTable.Run = ModuleScriptLimitsTable.current.tunnelRun) {
        maximumPendingRequests = run.maximumPendingRequests
    }

     
    var pageBytesNow: Int? { memory.spareBytes.map { $0 / ModuleScriptMemory.bytesPerPageByte } }
     
    var decompressedBytesNow: Int? { memory.spareBytes.map { $0 / ModuleScriptMemory.bytesPerReceivedByte } }
}

 
 
final class ModuleScriptSession {
    private struct Timer {
        let id: Int
        var due: UInt64
        var sequence: Int
        let callback: JSValue
        let arguments: [Any]
         
        let interval: UInt64?
    }

    let declaration: ModuleScriptDeclaration
     
    let request: ModuleScriptHostRequest?
    let response: ModuleScriptHostResponse?
    let body: Data?
    let sessionID: String
    let timeoutSeconds: Double
    let startedAt = Date()
    let services: ModuleScriptServices
    let store: ModuleScriptStore
    let limits: ModuleScriptSessionLimits

    private let deadline: UInt64
    private let thread: ModuleScriptThread
    private let monitor: ModuleScriptSliceMonitor
    private let runID: UUID
     
     
     
    private let settled: ModuleScriptFlag
    private let now: () -> UInt64
    private let completion: (ModuleScriptHostOutcome) -> Void
    private var context: JSContext?
    private var timers: [Timer] = []
    private var nextTimerID = 1
    private var sequence = 0
    private var wakeAt: UInt64?
    private var result: ModuleScriptResult?
    private var exceptionMessage: String?
    private var finished = false
    private var notificationsPosted = 0
     
     
     
    private var pendingRequests: [Int: JSValue] = [:]
     
     
    private var outstanding: [Int: (request: ModuleScriptHTTPRequest, cancellation: ModuleScriptNetworkCancellation)] = [:]
     
     
    private var waitingRequests: [(id: Int, request: ModuleScriptHTTPRequest)] = []
    private var nextRequestID = 1
     
    private var unansweredDNS: Set<Int> = []
    private var dnsCallbacks: [Int: JSValue] = [:]
    private var nextDNSID = 1
     
    private var pendingEngineWork = 0
    private var engineTurnScheduled = false
     
    private var engineTurnStep = 0
     
    private(set) var engineTurns = 0
     
     
     
    private var sentRequests = false

    init(
        declaration: ModuleScriptDeclaration,
        request: ModuleScriptHostRequest?,
        response: ModuleScriptHostResponse?,
        body: Data?,
        context: JSContext,
        thread: ModuleScriptThread,
        monitor: ModuleScriptSliceMonitor,
        runID: UUID,
        store: ModuleScriptStore,
        services: ModuleScriptServices,
        limits: ModuleScriptSessionLimits,
        timeoutSeconds: Double,
        deadline: UInt64,
        sessionID: String,
        settled: ModuleScriptFlag = ModuleScriptFlag(),
        now: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
        completion: @escaping (ModuleScriptHostOutcome) -> Void
    ) {
        self.declaration = declaration
        self.request = request
        self.response = response
        self.body = body
        self.context = context
        self.thread = thread
        self.monitor = monitor
        self.runID = runID
        self.store = store
        self.services = services
        self.limits = limits
        self.timeoutSeconds = timeoutSeconds
        self.deadline = deadline
        self.sessionID = sessionID
        self.settled = settled
        self.now = now
        self.completion = completion
    }

    var pendingTimerCount: Int { timers.count }

     
     
     
     
    var isLive: Bool { !finished && !settled.isRaised }

     
    var phase: ModuleScriptPhase? { declaration.phase }

     
    func start(source: String) {
        guard let context else { return }
        context.name = #"\#(declaration.name) \#(sessionID)"#
        context.exceptionHandler = { [weak self] _, exception in self?.noteException(exception) }
        if let install = services.installWebGlobals, !install(context) {
            log(#"the Web globals did not install in this context; the script runs without them"#)
        }
        if let install = services.installDOM, ModuleScriptDOM.isWanted(by: source), !install(context, limits.pageBytesNow) {
            log(#"DOMParser did not install in this context; the script runs without it"#)
        }
        ModuleScriptGlobals.install(in: context, for: self)
         
         
        thread.asyncAfter(deadline: deadline) { [weak self] in
            self?.deadlinePassed()
        }
        let sourceURL = URL(string: declaration.scriptPath)
        runSlice {
            _ = context.evaluateScript(source, withSourceURL: sourceURL)
             
             
             
             
            guard let message = exceptionMessage, message.contains(Self.topLevelReturn) else { return }
            exceptionMessage = nil
            log(#"its top-level return is read as a function's: the script runs as one"#)
            _ = context.evaluateScript(#"(function () {"# + "\n" + source + "\n" + #"})();"#, withSourceURL: sourceURL)
        }
    }

     
    static let topLevelReturn = #"Return statements are only valid inside functions"#

     
    func end(_ outcome: ModuleScriptHostOutcome) {
        finish(outcome)
    }

     

    func log(_ line: String) {
        guard isLive else { return }
        services.log(#"[script] \#(declaration.name) \#(sessionID) \#(line)"#)
    }

    func console(_ line: String) {
        guard isLive else { return }
        let size = line.utf8.count
        guard size > limits.maximumConsoleLineBytes else { return log(line) }
        let kept = String(decoding: line.utf8.prefix(limits.maximumConsoleLineBytes), as: UTF8.self)
        log(#"\#(kept)… (\#(size - limits.maximumConsoleLineBytes) more bytes not kept)"#)
    }

     
     
     
     
    func addTimer(_ callback: JSValue, milliseconds: Double, arguments: [Any], repeating: Bool = false) -> Int {
        let name = repeating ? "setInterval" : "setTimeout"
        guard isLive else { return 0 }
        guard ModuleScriptValues.isFunction(callback) else {
            log(#"\#(name): the first argument is not a function; nothing scheduled"#)
            return 0
        }
         
         
         
        let delay = max(milliseconds.isFinite ? milliseconds : 0, 0)
        let nanoseconds = delay < ModuleScriptDefaults.neverSeconds * 1000 ? UInt64(delay * 1_000_000) : UInt64.max >> 2
        let id = nextTimerID
        nextTimerID += 1
        sequence += 1
         
         
        timers.append(Timer(id: id, due: now() + nanoseconds, sequence: sequence, callback: callback,
                            arguments: arguments, interval: repeating ? max(nanoseconds, 1_000_000) : nil))
        return id
    }

    func clearTimer(_ id: Int) {
        timers.removeAll { $0.id == id }
    }

     
     
    func reportUncaught(_ exception: JSValue?) {
        noteException(exception)
    }

    func done(_ value: JSValue?) {
        guard isLive else { return }
        guard result == nil else {
            log(#"$done called again; ignored"#)
            return
        }
        result = ModuleScriptDoneReader(session: self).read(value)
    }

     
     
     
     
    func send(_ request: ModuleScriptHTTPRequest, callback: JSValue?) {
        guard isLive else { return }
        log(#"[$httpClient] \#(request.method) \#(request.url)"#)
        let id = nextRequestID
        nextRequestID += 1
        if let callback { pendingRequests[id] = callback }
        guard outstanding.count < limits.maximumPendingRequests else {
            waitingRequests.append((id, request))
            return
        }
        dispatch(id, request)
    }

     
     
     
    func queryDNS(_ asked: Result<ModuleScriptDNSQuery, ModuleScriptDNSFailure>, callback: JSValue?) {
        guard isLive else { return }
        let id = nextDNSID
        nextDNSID += 1
        unansweredDNS.insert(id)
        if let callback { dnsCallbacks[id] = callback }
        let answer = ModuleScriptPendingAnswer(session: self)
        let thread = self.thread
        switch asked {
        case .failure(let refusal):
            log(#"[$dns] not asked: \#(refusal.code) \#(refusal.message)"#)
            thread.async { answer.session?.answerDNS(id, nil, .failure(refusal)) }
        case .success(let query):
            let server = query.server.map { #" via \#($0)"# } ?? ""
            log(#"[$dns] \#(query.protocolName ?? "no protocol") \#(query.domain)\#(server)"#)
            let timeout = ModuleScriptDNSFailure(code: "TIMEOUT", message: #"no answer within \#(query.timeoutMilliseconds) ms"#)
            thread.asyncAfter(deadline: now() + UInt64(query.timeoutMilliseconds) * 1_000_000) {
                answer.session?.answerDNS(id, query, .failure(timeout))
            }
            services.dns.query(query) { result in
                thread.async { answer.session?.answerDNS(id, query, result) }
            }
        }
    }

    private func answerDNS(_ id: Int, _ query: ModuleScriptDNSQuery?,
                           _ result: Result<ModuleScriptDNSResult, ModuleScriptDNSFailure>) {
        guard isLive, unansweredDNS.remove(id) != nil else { return }
        let callback = dnsCallbacks.removeValue(forKey: id)
        let arguments: [Any]
        switch result {
        case .success(let answered):
            if let query { log(#"[$dns] \#(query.domain): \#(answered.answers.count) answer\#(answered.answers.count == 1 ? "" : "s")"#) }
            let object: [String: Any] = [
                "domain": answered.domain, "protocol": answered.protocolName, "server": answered.server,
                "fromCache": answered.fromCache,
                "answers": answered.answers.map { ["name": $0.name, "type": $0.type, "value": $0.value, "ttl": $0.ttl] as [String: Any] },
            ]
            arguments = [NSNull(), object]
        case .failure(let failure):
            if let query { log(#"[$dns] \#(query.domain): \#(failure.code) \#(failure.message)"#) }
            arguments = [["code": failure.code, "message": failure.message] as [String: Any], NSNull()]
        }
        guard let callback else { return }
        runSlice { _ = callback.call(withArguments: arguments) }
    }

    private func dispatch(_ id: Int, _ request: ModuleScriptHTTPRequest) {
        let thread = self.thread
        let answer = ModuleScriptPendingAnswer(session: self)
        sentRequests = true
        let cancellation = services.network.send(request, run: ModuleScriptHTTPRun(id: sessionID, deadline: deadline)) { result in
            thread.async { answer.session?.answer(id, to: request, with: result) }
        }
        outstanding[id] = (request, cancellation)
    }


     
     
     
     
     
     
     
     
     
     
     
     
    func engineWorkBegan() -> Bool {
        guard isLive else { return false }
        pendingEngineWork += 1
        engineTurnStep = 0
        scheduleEngineTurn()
        return true
    }

     
     
     
     
     
    func engineWorkSettled() {
        monitor.begin(runID, at: now())
        pendingEngineWork = max(pendingEngineWork - 1, 0)
        engineTurnStep = 0
        thread.async { [weak self] in self?.afterSlice() }
    }

     
     
     
    static func engineTurnInterval(after turns: Int) -> UInt64 {
        2_000_000 << UInt64(min(max(turns, 0), 6))
    }

    private func scheduleEngineTurn() {
        guard !finished, pendingEngineWork > 0, !engineTurnScheduled else { return }
        engineTurnScheduled = true
        thread.asyncAfter(deadline: now() + Self.engineTurnInterval(after: engineTurnStep)) { [weak self] in
            guard let self else { return }
            self.engineTurnScheduled = false
            guard !self.finished, self.pendingEngineWork > 0 else { return }
            self.engineTurns += 1
            self.engineTurnStep += 1
            self.runSlice { _ = CFRunLoopRunInMode(.defaultMode, 0, true) }
            self.scheduleEngineTurn()
        }
    }

     
    func notify(_ request: ModuleScriptNotificationRequest) -> Bool {
        guard isLive else { return false }
        notificationsPosted += 1
        services.notify(request)
        return true
    }

     

     
     
     
    private func runSlice(_ body: () -> Void) {
         
         
        guard !settled.isRaised else { return finish(.skipped(.cancelled)) }
        monitor.begin(runID, at: now())
        autoreleasepool { body() }
        monitor.end()
        afterSlice()
    }

    private func afterSlice() {
        guard !finished else { return }
        if let result { return finish(.done(result)) }
        if let exceptionMessage { return finish(.aborted(message: exceptionMessage)) }
         
         
        thread.async { [weak self] in self?.pump() }
    }

    private func pump() {
        guard !finished else { return }
        guard let next = timers.min(by: { ($0.due, $0.sequence) < ($1.due, $1.sequence) }) else { return }
        if next.due <= now() {
            if let interval = next.interval, let index = timers.firstIndex(where: { $0.id == next.id }) {
                 
                 
                sequence += 1
                timers[index].due = now() + interval
                timers[index].sequence = sequence
            } else {
                timers.removeAll { $0.id == next.id }
            }
            runSlice { _ = next.callback.call(withArguments: next.arguments) }
        } else if next.due < deadline, wakeAt.map({ next.due < $0 }) ?? true {
            wakeAt = next.due
            thread.asyncAfter(deadline: next.due) { [weak self] in
                self?.wakeAt = nil
                self?.pump()
            }
        }
         
    }

    private func answer(_ id: Int, to request: ModuleScriptHTTPRequest,
                        with answered: Result<ModuleScriptHTTPResponse, ModuleScriptNetworkFailure>) {
        guard isLive else { return }
        outstanding[id] = nil
        while outstanding.count < limits.maximumPendingRequests, !waitingRequests.isEmpty {
            let next = waitingRequests.removeFirst()
            dispatch(next.id, next.request)
        }
        let callback = pendingRequests.removeValue(forKey: id)
        var result = answered
        switch answered {
        case .success(var response):
            log(#"[$httpClient] \#(request.method) \#(request.url): \#(response.status), \#(response.body.count) bytes"#)
        case .failure(let failure):
            log(#"[$httpClient] \#(request.method) \#(request.url): \#(failure.message)"#)
        }
        guard let callback, let context else { return }
        let arguments: [Any]
        switch result {
        case .success(let response):
            let object = JSValue(newObjectIn: context)!
            object.setObject(response.status, forKeyedSubscript: "status" as NSString)
            let headers = JSValue(newObjectIn: context)!
            for header in ModuleScriptHeaderFolding.fold(response.headers) {
                headers.setObject(header.value, forKeyedSubscript: header.name as NSString)
            }
            object.setObject(headers, forKeyedSubscript: "headers" as NSString)
            if declaration.family == .quantumultX {
                 
                arguments = [NSNull(), object, String(decoding: response.body, as: UTF8.self),
                             ModuleScriptValues.uint8Array(response.body, in: context) ?? NSNull()]
            } else {
                let data: Any = request.binaryMode
                    ? (ModuleScriptValues.uint8Array(response.body, in: context) ?? NSNull())
                    : String(decoding: response.body, as: UTF8.self)
                arguments = [NSNull(), object, data]
            }
        case .failure(let failure):
            arguments = [failure.message, NSNull(), NSNull()]
        }
        runSlice { _ = callback.call(withArguments: arguments) }
    }

    private func deadlinePassed() {
        guard !finished else { return }
        finish(.timedOut(seconds: timeoutSeconds))
    }

    private func noteException(_ exception: JSValue?) {
        guard exceptionMessage == nil else { return }
        exceptionMessage = ModuleScriptValues.describeException(exception)
    }

    private func finish(_ outcome: ModuleScriptHostOutcome) {
        guard !finished else { return }
        finished = true
         
        for (_, entry) in outstanding.sorted(by: { $0.key < $1.key }) {
            services.log(#"[script] \#(declaration.name) \#(sessionID) [$httpClient] \#(entry.request.method) "#
                         + #"\#(entry.request.url): still out when the run ended; cancelled"#)
            entry.cancellation.cancel()
        }
        outstanding.removeAll()
        for entry in waitingRequests {
            services.log(#"[script] \#(declaration.name) \#(sessionID) [$httpClient] \#(entry.request.method) "#
                         + #"\#(entry.request.url): still waiting when the run ended; not sent"#)
        }
        waitingRequests.removeAll()
         
        if sentRequests { services.network.runEnded(sessionID) }
         
         
        timers.removeAll()
        pendingRequests.removeAll()
        context?.exceptionHandler = nil
        context = nil
        completion(outcome)
    }
}

 
 
private final class ModuleScriptPendingAnswer: @unchecked Sendable {
    weak var session: ModuleScriptSession?

    init(session: ModuleScriptSession) {
        self.session = session
    }
}

 
 
 
struct ModuleScriptDoneReader {
    let session: ModuleScriptSession

    func read(_ value: JSValue?) -> ModuleScriptResult {
        guard let phase = session.phase else { return .completed(json: json(value)) }
        if session.declaration.family == .quantumultX { return quantumultX(value, phase: phase) }
        guard let value, !ModuleScriptValues.isAbsent(value) else { return nothingGiven(phase) }
        guard value.isObject else { return .passThrough }
        if let abort = value.objectForKeyedSubscript("abort"), !ModuleScriptValues.isAbsent(abort), abort.toBool() {
            return .closeConnection
        }
        switch phase {
        case .request:
            if let answer = value.objectForKeyedSubscript("response"), answer.isObject {
                return .respond(ModuleScriptEdit(
                    status: ModuleScriptValues.integer(answer.objectForKeyedSubscript("status")) ?? 200,
                    headers: headers(answer.objectForKeyedSubscript("headers"), original: []),
                     
                    body: body(answer.objectForKeyedSubscript("body"), allowed: true)))
            }
            let edit = ModuleScriptEdit(
                url: ModuleScriptValues.string(value.objectForKeyedSubscript("url")),
                headers: headers(value.objectForKeyedSubscript("headers"), original: session.request?.headers ?? []),
                body: body(value.objectForKeyedSubscript("body"), allowed: session.declaration.requiresBody))
            return edit.isEmpty ? .passThrough : .modifyRequest(edit)
        case .response:
             
             
             
             
             
             
            var given: JSValue = value
            if let answer = value.objectForKeyedSubscript("response"), answer.isObject { given = answer }
            let edit = ModuleScriptEdit(
                status: ModuleScriptValues.integer(given.objectForKeyedSubscript("status")),
                headers: headers(given.objectForKeyedSubscript("headers"), original: session.response?.headers ?? []),
                body: body(given.objectForKeyedSubscript("body"), allowed: session.declaration.requiresBody))
            return edit.isEmpty ? .passThrough : .modifyResponse(edit)
        }
    }

     
     
     
     
     
     
     
     
     
    private func quantumultX(_ value: JSValue?, phase: ModuleScriptPhase) -> ModuleScriptResult {
        guard let value, !ModuleScriptValues.isAbsent(value) else { return .passThrough }
        let allowed = session.declaration.requiresBody
        if value.isString {
            guard let body = body(value, allowed: allowed) else { return .passThrough }
            return phase == .request ? .modifyRequest(ModuleScriptEdit(body: body)) : .modifyResponse(ModuleScriptEdit(body: body))
        }
        guard value.isObject else { return .passThrough }
        func field(_ name: String) -> JSValue? {
            guard let found = value.objectForKeyedSubscript(name), !ModuleScriptValues.isAbsent(found) else { return nil }
            return found
        }
        let given = field("bodyBytes") ?? field("body")
        switch phase {
        case .request:
            if let status = field("status") {
                return .respond(ModuleScriptEdit(status: ModuleScriptQuantumultX.statusCode(status) ?? 200,
                                                 headers: headers(field("headers"), original: []), body: body(given, allowed: true)))
            }
            if let answer = field("response"), answer.isObject {
                let bytes = answer.objectForKeyedSubscript("bodyBytes")
                return .respond(ModuleScriptEdit(
                    status: ModuleScriptQuantumultX.statusCode(answer.objectForKeyedSubscript("status")) ?? 200,
                    headers: headers(answer.objectForKeyedSubscript("headers"), original: []),
                    body: body(ModuleScriptValues.isAbsent(bytes) ? answer.objectForKeyedSubscript("body") : bytes, allowed: true)))
            }
            var url = ModuleScriptValues.string(field("url"))
            if url == nil, let path = ModuleScriptValues.string(field("path")), let request = session.request {
                url = ModuleScriptQuantumultX.url(request.url, withPath: path)
                if url == nil { session.log(#"$done: the path does not make an address with the request's; ignored"#) }
            }
            let edit = ModuleScriptEdit(url: url, headers: headers(field("headers"), original: session.request?.headers ?? []),
                                        body: body(given, allowed: allowed))
            return edit.isEmpty ? .passThrough : .modifyRequest(edit)
        case .response:
            let edit = ModuleScriptEdit(status: ModuleScriptQuantumultX.statusCode(field("status")),
                                        headers: headers(field("headers"), original: session.response?.headers ?? []),
                                        body: body(given, allowed: allowed))
            return edit.isEmpty ? .passThrough : .modifyResponse(edit)
        }
    }

     
     
     
     
    private func nothingGiven(_ phase: ModuleScriptPhase) -> ModuleScriptResult {
        switch (session.declaration.family, phase) {
        case (.loon, .request), (.stash, .request): return .closeConnection
        default: return .passThrough
        }
    }

     
     
    private func json(_ value: JSValue?) -> String? {
        guard let value, !ModuleScriptValues.isAbsent(value), let context = value.context else { return nil }
        let handler = context.exceptionHandler
        context.exceptionHandler = { _, _ in }
        let text = context.objectForKeyedSubscript("JSON")?.invokeMethod("stringify", withArguments: [value])
        context.exceptionHandler = handler
        guard let text, text.isString else {
            session.log(#"$done: the value cannot be written as JSON; nothing is kept"#)
            return nil
        }
        return text.toString()
    }

    private func headers(_ value: JSValue?, original: [ModuleScriptHeader]) -> [ModuleScriptHeader]? {
        guard let value, !ModuleScriptValues.isAbsent(value) else { return nil }
        guard value.isObject, !value.isArray else {
            session.log(#"$done: headers is not an object; ignored"#)
            return nil
        }
        var lines: [ModuleScriptHeader] = []
        for name in ModuleScriptValues.propertyNames(of: value) {
            guard let field = value.objectForKeyedSubscript(name), !ModuleScriptValues.isAbsent(field) else { continue }
            if field.isArray {
                for item in field.toArray() ?? [] { lines.append(ModuleScriptHeader(name: name, value: "\(item)")) }
            } else {
                lines.append(ModuleScriptHeader(name: name, value: field.toString() ?? ""))
            }
        }
        return ModuleScriptHeaderFolding.unfold(lines, original: original)
    }

     
     
    private func body(_ value: JSValue?, allowed: Bool) -> Data? {
        guard let value, !ModuleScriptValues.isAbsent(value) else { return nil }
        guard allowed else {
            session.log(#"$done: a body without requires-body is ignored"#)
            return nil
        }
        guard let data = ModuleScriptValues.bytes(value, textAllowed: true) else {
            session.log(#"$done: the body is neither text nor bytes; ignored"#)
            return nil
        }
        return data
    }
}
#endif
