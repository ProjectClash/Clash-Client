#if os(iOS) || os(macOS)
import Foundation

 
 
 
 
 
 
 
 
 
 
 
 

protocol AdBlockUpstreamOpening: AnyObject {
    func open(authority: String, serverName: String, tls: Bool,
              completion: @escaping (Result<AdBlockStream, AdBlockUpstreamFailure>) -> Void)
}

extension AdBlockUpstreamConnector: AdBlockUpstreamOpening {}

 
protocol AdBlockAllowance: AnyObject {
    var allowsScripts: Bool { get }
    var allowsBodies: Bool { get }
     
     
    var bodiesAtOnce: Int? { get }
     
    func noteActivity()
}

final class AdBlockFullAllowance: AdBlockAllowance {
    var allowsScripts = true
    var allowsBodies = true
    var bodiesAtOnce: Int?

    init() {}

    func noteActivity() {}
}

 
 
final class AdBlockRejectUpgradeBox {
    var upgrade = AdBlockRejectUpgrade()
}

 
 
 
 
 
 
final class AdBlockScriptSkipNotes {
    private var said: Set<String> = []

     
    func first(_ match: AdBlockScriptMatch, _ why: String) -> Bool {
        said.insert("\(match.moduleID)\u{1F}\(match.origin.description)\u{1F}\(match.script.phase.rawValue)\u{1F}\(why)").inserted
    }
}

struct AdBlockExchangeServices {
    let queue: DispatchQueue
     
     
    var program: AdBlockRewriteProgram
    let budget: AdBlockBodyBudget
    let allowance: AdBlockAllowance
    let scripts: AdBlockScriptRunning
    let upstreams: AdBlockUpstreamOpening
    let metrics: AdBlockEngineMetrics
    let log: AdBlockEngineLog
    let rejects: AdBlockRejectUpgradeBox
     
     
    let now: () -> Date
     
     
    var scriptGrace: TimeInterval = AdBlockScriptCall.grace
     
    var idleTimeout: TimeInterval = AdBlockExchange.defaultIdleTimeout
     
    var headTimeout: TimeInterval = AdBlockEngine.defaultHeadTimeout
     
    var finalSendTimeout: TimeInterval = AdBlockEngine.defaultFinalSendTimeout
     
    var requestBudget: TimeInterval = AdBlockRequestBudget.perRequest
     
     
    var appStallTimeout: TimeInterval = AdBlockExchange.defaultAppStallTimeout
     
     
    var upstreamStallTimeout: TimeInterval = AdBlockExchange.defaultUpstreamStallTimeout
     
    var scriptSkips = AdBlockScriptSkipNotes()
}

struct AdBlockExchangeContext: Equatable {
     
    let scheme: String
     
    let host: String
     
    let target: AdBlockConnectTarget
}

final class AdBlockExchange {
     
     
     
     
     
     
    static let defaultIdleTimeout: TimeInterval = 30
     
     
    static let defaultAppStallTimeout: TimeInterval = 60
     
     
    static let defaultUpstreamStallTimeout: TimeInterval = 300
     
    static let idempotentMethods: Set<String> = ["GET", "HEAD", "OPTIONS", "TRACE", "PUT", "DELETE"]
     
     
     
    static let readableCodings: Set<String> = ["gzip", "x-gzip", "deflate", "identity"]
     
     
    private static let protectedHeaders: Set<String> = [
        "content-length", "transfer-encoding", "connection", "upgrade", "keep-alive", "proxy-connection", "te", "trailer",
    ]

    private struct Route: Equatable {
        var authority: String
        var serverName: String
        var tls: Bool

         
         
         
         
         
        static func to(_ url: String, head: inout AdBlockHTTPRequestHead, hostFollows: Bool) -> Route? {
            guard let components = URLComponents(string: url), let scheme = components.scheme?.lowercased(),
                  ["http", "https", "ws", "wss"].contains(scheme), let rawHost = components.host, !rawHost.isEmpty else { return nil }
            let tls = scheme == "https" || scheme == "wss"
            let defaultPort: UInt16 = tls ? 443 : 80
            guard let port = components.port.map({ UInt16(exactly: $0) }) ?? defaultPort else { return nil }
            let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
            let shown = host.contains(":") ? "[\(host)]" : host
            var path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
            if let query = components.percentEncodedQuery { path += "?" + query }
            guard AdBlockHTTPParser.isValidTarget(path[...]) else { return nil }
            head.target = path
            if hostFollows { head.headers.set("Host", port == defaultPort ? shown : "\(shown):\(port)") }
            return Route(authority: "\(shown):\(port)", serverName: host, tls: tls)
        }
    }

     
    private struct Plan {
        let urls: AdBlockRequestURLs
         
        var url: String
         
         
        var method: String
         
        let appMethod: String
        let appVersion: AdBlockHTTPVersion
         
        let keepsAlive: Bool
        let asksForUpgrade: Bool
         
        let id: String
         
         
        let responseCandidates: AdBlockResponseCandidates
        let responseScript: AdBlockScriptMatch?

        var readsResponseBody: Bool { responseCandidates.readsBody || responseScript?.script.requiresBody == true }
        var idempotent: Bool { AdBlockExchange.idempotentMethods.contains(method) }
    }

    private enum OutgoingBody {
        case none
         
         
        case buffered(Data, AdBlockHeldBody?)
        case stream(AdBlockHTTPFraming)
         
        case streamAfter(AdBlockBodyCollected, AdBlockHTTPBodyReader, rechunk: Bool)

        var replayable: Bool {
            switch self {
            case .none, .buffered: return true
            case .stream, .streamAfter: return false
            }
        }

        var held: AdBlockHeldBody? {
            if case .buffered(_, let held) = self { return held }
            return nil
        }
    }

    private enum Collected {
        case complete(AdBlockHeldBody)
        case overflow(AdBlockBodyCollected, AdBlockHTTPBodyReader, AdBlockBodySkip)
        case failed
    }

    private enum Waiting {
        case request
        case head
    }

     
    private enum Party {
        case app
        case upstream
    }

    private let client: AdBlockReader
    private let context: AdBlockExchangeContext
     
    private var services: AdBlockExchangeServices
    private let newest: (() -> AdBlockExchangeServices?)?
    private var onEnd: (() -> Void)?
     
    private var upstream: (route: Route, reader: AdBlockReader)?
    private var relay: AdBlockRelay?
    private var served = 0
    private var ended = false
     
    private var scan = AdBlockHTTPHeadScan()
    private var responseScan = AdBlockHTTPHeadScan()
    private var timer: AdBlockDeadline?
    private var waiting: Waiting?
    private var call: AdBlockScriptCall?
     
     
    private var collection: AdBlockBodyCollection?
     
    private var retryHold: AdBlockHeldBody?
     
    private var budget = AdBlockRequestBudget()
    private var current: (method: String, url: String)?
     
     
    private var clientReading = false
    private var afterClientRead: ((Bool) -> Void)?
     
     
     
    private var upstreamReading = false
    private var upstreamIdle = false
    private var afterUpstreamRead: ((Error?) -> Void)?
    private var awaitingAnswer = false
     
    private var stallTimer: DispatchSourceTimer?
    private var stallParty: Party?
    private var stallSince: UInt64 = 0
     
    private let tag = String(UUID().uuidString.prefix(8)).lowercased()
     
     
    private var windingDown = false
     
     
     
     
    private var keptRequestHeaders: AdBlockHTTPHeaders?
     
     
     
     
    private(set) var endedOnLastAnswer = false

     
     
     
     
     
    init(client: AdBlockStream, buffered: Data, clientEnded: Bool = false, context: AdBlockExchangeContext,
         services: AdBlockExchangeServices, newest: (() -> AdBlockExchangeServices?)? = nil, onEnd: @escaping () -> Void) {
        self.client = AdBlockReader(client, buffered: buffered, ended: clientEnded)
        self.context = context
        self.services = services
        self.newest = newest
        self.onEnd = onEnd
    }

     
    func start() {
        dispatchPrecondition(condition: .onQueue(services.queue))
        readRequest()
    }

     
     
    func close() {
        dispatchPrecondition(condition: .onQueue(services.queue))
        guard !ended else { return }
        ended = true
        endRequest()
        timer?.cancel()
        timer = nil
        call?.cancel()
        call = nil
        if let collection {
            self.collection = nil
            collection.discard()
        }
        retryHold?.release()
        retryHold = nil
        afterClientRead = nil
        relay?.close()
        relay = nil
        upstream?.reader.stream.cancel()
        upstream = nil
        client.stream.cancel()
        let end = onEnd
        onEnd = nil
        end?()
    }

    private func say(_ line: String) { services.log.say(line) }

     

     
     
     
     
     
     
    func adoptNewestIfIdle() {
        dispatchPrecondition(condition: .onQueue(services.queue))
        guard !ended, current == nil, relay == nil, let newer = newest?() else { return }
        services = newer
    }

     
     
     
     
     
    func shed(for rung: AdBlockEngineReport.Rung) {
        adoptNewestIfIdle()
        if rung >= .scriptsStopped { keptRequestHeaders = nil }
        if rung >= .engineStopped { windDown() }
    }

     
     
     
     
     
     
     
     
     
     
     
    func windDown() {
        dispatchPrecondition(condition: .onQueue(services.queue))
        guard !ended, relay == nil else { return }
        windingDown = true
        if isIdle {
            say("the engine stopped for memory: the idle session for \(context.host) is closed")
            close()
        }
    }

     
    var isIdle: Bool {
        !ended && relay == nil && served > 0 && current == nil && waiting == .request && client.buffer.isEmpty && collection == nil
            && call == nil
    }

    var isWindingDown: Bool { windingDown }

     
    var isRelay: Bool { relay != nil }

     
     
    var canWindDown: Bool { !ended && relay == nil && !windingDown }

     

    private func readRequest() {
        guard !ended else { return }
        let parsed: AdBlockHTTPParse<AdBlockHTTPRequestHead>
        do {
            parsed = try AdBlockHTTPParser.request(client.buffer, scan: &scan)
        } catch let error as AdBlockHTTPError {
            say("unreadable request from \(context.host): \(error)")
            return answer(status: error.status)
        } catch {
            return close()
        }
        switch parsed {
        case .head(let head, let consumed):
            client.buffer = Data(client.buffer.dropFirst(consumed))
            scan = AdBlockHTTPHeadScan()
            disarm()
            served += 1
            handle(head)
        case .needMore:
            guard !client.ended else { return close() }
            arm(client.buffer.isEmpty ? .request : .head)
            fillClient { [self] ok in ok ? readRequest() : close() }
        }
    }

    private func handle(_ received: AdBlockHTTPRequestHead) {
        var head = received
         
         
        services.allowance.noteActivity()
        if let newer = newest?() { services = newer }
        budget = AdBlockRequestBudget(seconds: services.requestBudget)
        services.metrics.update { $0.requestsTotal += 1 }
        guard head.method != "CONNECT" else {
            say("refused CONNECT \(head.target) inside \(context.scheme)://\(context.host): a session names one origin")
            return answer(status: 405)
        }
         
         
         
         
         
         
        var last = false
        if !head.target.hasPrefix("/"), head.target != "*" {
            guard let origin = originForm(head.target) else {
                say("refused \(head.method) \(head.target) on \(context.target.authority): another origin than the one admitted")
                return answer(status: 403)
            }
            head.target = origin
            head.headers.remove("Proxy-Authorization")
            head.headers.remove("Proxy-Connection")
            last = context.scheme == "http"
        }
        let framing: AdBlockHTTPFraming
        do {
            framing = try AdBlockHTTPFraming.ofRequest(head)
        } catch let error as AdBlockHTTPError {
            say("refused \(head.method) \(head.target) from \(context.host): \(error)")
            return answer(status: error.status)
        } catch {
            return close()
        }
        let urls = AdBlockRequestURLs.make(scheme: context.scheme, connectionHost: context.host, port: context.target.port, head: head)
        current = (head.method, urls.primary)
         
         
         
        let requestPlan = services.program.requestPlan(AdBlockMessageView(urls: urls, method: head.method, requestHeaders: head.headers),
                                                       budget: &budget)
         
        if let rewritten = requestPlan.requestHeaders { head.headers = rewritten }
        sayHeaderRewrites(requestPlan.headerRewrites, phase: .request, urls: urls)
         
        let keepsAlive = head.keepsAlive && !last
        var route = Route(authority: context.target.authority, serverName: context.host, tls: context.scheme == "https")
        var url = urls.primary
        switch requestPlan.ending ?? .pass {
        case .pass:
            break
        case .respond(let response, let origin, let kind):
            let redirect = response.status == 302 || response.status == 307
            if !redirect, services.rejects.upgrade.becomesDrop(kind: kind, host: context.host, at: AdBlockRejectUpgrade.now()) {
                services.metrics.update { $0.dropsTotal += 1 }
                say("\(kind) became a drop after \(AdBlockRejectUpgrade.limit) in \(Int(AdBlockRejectUpgrade.window)) s: \(head.method) \(urls.primary) (\(origin.description))")
                return close()
            }
             
            let keepAlive = keepsAlive && framing == .none && !windingDown
            let wire = response.bytes(method: head.method, keepAlive: keepAlive)
            guard !wire.isFallback else {
                say("\(kind) \(head.method) \(urls.primary): its answer could not be written as one head, so the answer is 502 and the connection closes (\(origin.description))")
                return finalSend(wire.data)
            }
            services.metrics.update { if redirect { $0.redirectsTotal += 1 } else { $0.rejectsTotal += 1 } }
            say("\(kind) \(head.method) \(urls.primary)\(response.location.map { " -> \($0)" } ?? "") (\(origin.description))")
            guard keepAlive else { return finalSend(wire.data) }
            return send(wire.data) { [self] in finished(keepAlive: true, reusable: true) }
        case .drop(let origin, let kind):
            services.metrics.update { $0.dropsTotal += 1 }
            say("\(kind) \(head.method) \(urls.primary) (\(origin.description))")
            return close()
        case .rewrite(let to, let origin):
            if let moved = Route.to(to, head: &head, hostFollows: true) {
                route = moved
                url = to
                say("header \(head.method) \(urls.primary) -> \(to) (\(origin.description))")
            } else {
                say("header rewrite of \(urls.primary) to \(to) is not an http, https or ws address; the request goes on unchanged (\(origin.description))")
            }
        }
         
        let bodies = services.allowance.allowsBodies
        let scriptsOn = bodies && services.allowance.allowsScripts
        var requestSteps = steps(requestPlan.bodySteps, urls: urls, bodiesOn: bodies)
        if framing == .chunked || head.expectsContinue, requestSteps.contains(where: { $0.family == .surge }) {
             
             
            for step in requestSteps where step.family == .surge {
                say("\(step.what) request \(urls.primary) not applied (\(step.origin.description)): Surge leaves a chunked request, or one that expects 100-continue, as it is")
            }
            requestSteps.removeAll { $0.family == .surge }
        }
        let requestScript = runnable(services.program.script(phase: .request, urls: urls, budget: &budget), allowed: scriptsOn, urls: urls)
        var responseCandidates = services.program.responseCandidates(urls, budget: &budget)
        if !bodies, responseCandidates.readsBody {
            skip(.bodiesStopped, urls: urls, script: nil, counted: false)
            responseCandidates = responseCandidates.withoutBodies()
        }
        let responseScript = runnable(services.program.script(phase: .response, urls: urls, budget: &budget), allowed: scriptsOn, urls: urls)
        let plan = Plan(urls: urls, url: url, method: head.method, appMethod: head.method, appVersion: head.version,
                        keepsAlive: keepsAlive, asksForUpgrade: head.asksForUpgrade, id: "\(tag)-\(served)",
                        responseCandidates: responseCandidates, responseScript: responseScript)
        if plan.readsResponseBody { Self.narrowAcceptEncoding(&head.headers) }
        if head.expectsContinue {
             
            head.headers.remove("Expect")
            client.stream.send(Data("HTTP/1.1 100 Continue\r\n\r\n".utf8)) { _ in }
        }
        prepareRequest(head, framing: framing, route: route, plan: plan, steps: requestSteps, script: requestScript)
    }

     
     
    private func originForm(_ target: String) -> String? {
        guard let separator = target.range(of: "://") else { return nil }
        let scheme = target[..<separator.lowerBound].lowercased()
        guard scheme == context.scheme else { return nil }
        let rest = target[separator.upperBound...]
        let end = rest.firstIndex { "/?#".contains($0) } ?? rest.endIndex
        let authority = String(rest[..<end])
        guard !authority.contains("@"),
              let named = AdBlockConnectTarget.parse(authority, defaultPort: context.target.port),
              AdBlockEngine.withoutTrailingDots(named.host.lowercased()) == AdBlockEngine.withoutTrailingDots(context.target.host.lowercased())
                || AdBlockEngine.withoutTrailingDots(named.host.lowercased()) == AdBlockEngine.withoutTrailingDots(context.host.lowercased()),
              named.port == context.target.port else { return nil }
        var path = String(rest[end...])
        if let fragment = path.firstIndex(of: "#") { path = String(path[..<fragment]) }
        if path.isEmpty { return "/" }
        return path.hasPrefix("/") ? path : "/" + path
    }

     
     
     
    static func narrowAcceptEncoding(_ headers: inout AdBlockHTTPHeaders) {
        guard headers.contains("Accept-Encoding") else { return }
        let kept = headers.values("Accept-Encoding").flatMap { $0.split(separator: ",") }
            .map { $0.trimmingCharacters(in: AdBlockHTTPWhitespace.optional) }
            .filter { member in
                let parts = member.split(separator: ";").map { $0.trimmingCharacters(in: AdBlockHTTPWhitespace.optional).lowercased() }
                guard let coding = parts.first, readableCodings.contains(coding) else { return false }
                let refused = parts.dropFirst().contains { parameter in
                    guard parameter.hasPrefix("q=") else { return false }
                    return Double(parameter.dropFirst(2)) == 0
                }
                return !refused
            }
        if kept.isEmpty {
            headers.remove("Accept-Encoding")
        } else {
            headers.set("Accept-Encoding", kept.joined(separator: ", "))
        }
    }

     
     
     
     
     
    private func sayHeaderRewrites(_ rewrites: [AdBlockHeaderRewrite], phase: AdBlockRewritePhase, urls: AdBlockRequestURLs) {
        for rewrite in rewrites {
            switch rewrite.outcome {
            case .applied:
                services.metrics.update { $0.headerRewritesTotal += 1 }
                say("header \(phase.rawValue) \(rewrite.what) \(urls.primary) (\(rewrite.origin.description))")
            case .timedOut:
                say("header \(phase.rawValue) \(rewrite.what) \(urls.primary): its regex ran past its deadline; the header is left as it was (\(rewrite.origin.description))")
            case .grewTooLarge:
                say("header \(phase.rawValue) \(rewrite.what) \(urls.primary): it would have grown the head past its limit; the header is left as it was (\(rewrite.origin.description))")
            case .skipped(let why):
                say("header \(phase.rawValue) \(rewrite.what) \(urls.primary) not applied (\(rewrite.origin.description)): \(why)")
            case .budgetSpent:
                say("header \(phase.rawValue) \(rewrite.what) \(urls.primary) not applied (\(rewrite.origin.description)): the request's processing budget ran out")
            }
        }
    }

     
     
    private func steps(_ steps: [AdBlockBodyStep], urls: AdBlockRequestURLs, bodiesOn: Bool) -> [AdBlockBodyStep] {
        guard !bodiesOn, !steps.isEmpty else { return steps }
        skip(.bodiesStopped, urls: urls, script: nil, counted: false)
        return []
    }

     
     
     
    private func runnable(_ match: AdBlockScriptMatch?, allowed: Bool, urls: AdBlockRequestURLs) -> AdBlockScriptMatch? {
        guard let match else { return nil }
        let why: String?
        if !allowed {
            why = "scripts are paused for memory"
             
            if match.script.requiresBody { services.metrics.update { $0.bodySkippedTotal += 1 } }
        } else if !services.scripts.isAvailable {
            why = "no script runner is available"
        } else if match.bodyFile == nil {
            why = "its script has not been downloaded yet"
        } else {
            why = nil
        }
        guard let why else { return match }
        services.metrics.update { $0.scriptsSkippedTotal += 1 }
        if services.scriptSkips.first(match, why) {
            say("script \(match.script.name) \(match.script.phase.rawValue) \(urls.primary) not run: \(why)")
        }
        return nil
    }

     
     
     
     
     
    private func callScript(_ match: AdBlockScriptMatch, label: String,
                            run: (@escaping (AdBlockScriptOutcome) -> Void) -> Void,
                            then handle: @escaping (AdBlockScriptOutcome) -> Void) {
        let limit = AdBlockScriptCall.limit(for: match.script, grace: services.scriptGrace)
        waitOn(nil)
        call = AdBlockScriptCall.start(on: services.queue, limit: limit, run: run) { [weak self] answer in
            guard let self, !self.ended else { return }
            self.call = nil
            switch answer {
            case .answered(let outcome):
                self.count(outcome, label: label, match: match)
                handle(outcome)
            case .noAnswer(let within):
                self.services.metrics.update { $0.scriptsTimedOutTotal += 1 }
                self.say("\(label): no answer within \(Int(within)) s; it goes on unchanged (\(match.origin.description))")
                handle(.timedOut)
            }
        }
    }

    private func count(_ outcome: AdBlockScriptOutcome, label: String, match: AdBlockScriptMatch) {
        let origin = match.origin
        let what: String
        switch outcome {
        case .unavailable(let why):
            services.metrics.update { $0.scriptsSkippedTotal += 1 }
             
            guard services.scriptSkips.first(match, why) else { return }
            return say("\(label): not run: \(why)")
        case .unchanged: what = "unchanged"
        case .request: what = "changed the request"
        case .response(let response): what = "returned a \(response.status) response"
        case .drop(let why): what = "dropped the connection (\(why))"
        case .aborted(let why): what = "aborted: \(why)"
        case .timedOut: what = "timed out"
        }
        services.metrics.update {
            $0.scriptsRunTotal += 1
            switch outcome {
            case .aborted: $0.scriptsAbortedTotal += 1
            case .timedOut: $0.scriptsTimedOutTotal += 1
            case .drop: $0.dropsTotal += 1
            default: break
            }
        }
        say("\(label): \(what) (\(origin.description))")
    }

     
     
    private static func keepingProtected(_ changed: AdBlockHTTPHeaders, from original: AdBlockHTTPHeaders) -> AdBlockHTTPHeaders {
        var out = AdBlockHTTPHeaders(changed.fields.filter { !protectedHeaders.contains($0.name.lowercased()) })
        out.fields += original.fields.filter { protectedHeaders.contains($0.name.lowercased()) }
        return out
    }

    private func prepareRequest(_ head: AdBlockHTTPRequestHead, framing: AdBlockHTTPFraming, route: Route, plan: Plan,
                                steps: [AdBlockBodyStep], script: AdBlockScriptMatch?) {
        let reads = framing != .none && (!steps.isEmpty || script?.script.requiresBody == true)
         
         
        let headOnly = script?.script.requiresBody == true ? nil : script
        guard reads else {
             
             
             
             
             
             
             
            var head = head
            let declaresEmpty = ((try? AdBlockHTTPFraming.contentLength(head.headers)) ?? nil) == 0
            let firstMock = steps.firstIndex { step in
                if case .body = step.work { return true }
                return false
            }
            let onEmpty = framing != .none ? [] : declaresEmpty ? steps : firstMock.map { Array(steps[$0...]) } ?? []
            let made = onEmpty.isEmpty ? nil : rewriteBody(Data(), steps: onEmpty, phase: .request, urls: plan.urls, headers: &head.headers)
            return runRequestScript(script, head: head, body: made ?? (framing == .none && script?.script.requiresBody == true ? Data() : nil),
                                    route: route, plan: plan) { [self] head, body, route, plan, local in
                if let local { return answerLocally(local, keepAlive: plan.keepsAlive && framing == .none, plan: plan) }
                if let made { return forward(head, .buffered(body ?? made, nil), route: route, plan: plan) }
                forward(head, framing == .none ? .none : .stream(framing), route: route, plan: plan)
            }
        }
        if let coding = head.headers.first("Content-Encoding") {
            skip(.notDecodable(coding), urls: plan.urls, script: script, counted: false)
            return runRequestScript(headOnly, head: head, body: nil, route: route, plan: plan) { [self] head, _, route, plan, local in
                if let local { return answerLocally(local, keepAlive: false, plan: plan) }
                forward(head, .stream(framing), route: route, plan: plan)
            }
        }
        let declared = (try? AdBlockHTTPFraming.contentLength(head.headers)) ?? nil
        switch services.budget.begin(declaredLength: declared, maximum: steps.isEmpty ? script?.script.maxSize : nil,
                                     atOnce: services.allowance.bodiesAtOnce) {
        case .failure(let why):
            skip(why, urls: plan.urls, script: script, counted: true)
            runRequestScript(headOnly, head: head, body: nil, route: route, plan: plan) { [self] head, _, route, plan, local in
                if let local { return answerLocally(local, keepAlive: false, plan: plan) }
                forward(head, .stream(framing), route: route, plan: plan)
            }
        case .success(let collection):
            self.collection = collection
            collect(from: client, framing: framing, limits: .request, into: collection) { [self] collected in
                self.collection = nil
                switch collected {
                case .failed:
                    close()
                case .overflow(let payload, let reader, let why):
                    skip(why, urls: plan.urls, script: script, counted: true)
                    runRequestScript(headOnly, head: head, body: nil, route: route, plan: plan) { [self] head, _, route, plan, local in
                        if let local { return answerLocally(local, keepAlive: false, plan: plan) }
                        forward(head, .streamAfter(payload, reader, rechunk: framing == .chunked), route: route, plan: plan)
                    }
                case .complete(let held):
                    let payload = held.take()
                    budget.allow(bodyBytes: payload.count)
                     
                    var head = head
                    let body = steps.isEmpty ? payload
                        : (rewriteBody(payload, steps: steps, phase: .request, urls: plan.urls, headers: &head.headers) ?? payload)
                    runRequestScript(script, head: head, body: body, route: route, plan: plan) { [self] head, body, route, plan, local in
                        if let local {
                            held.release()
                            return answerLocally(local, keepAlive: plan.keepsAlive, plan: plan)
                        }
                        forward(head, .buffered(body ?? Data(), held), route: route, plan: plan)
                    }
                }
            }
        }
    }

     
     
     
     
     
     
    private func rewriteBody(_ body: Data, steps: [AdBlockBodyStep], phase: AdBlockRewritePhase, urls: AdBlockRequestURLs,
                             headers: inout AdBlockHTTPHeaders) -> Data? {
        let result = AdBlockBodySteps.apply(steps, to: body, budget: &budget)
        if result.notText { skip(.notText, urls: urls, script: nil, counted: false) }
        for note in result.notes {
            say("\(note.what) \(phase.rawValue) \(urls.primary) not applied (\(note.origin.description)): \(note.why)")
        }
        guard let changed = result.body else { return nil }
        services.metrics.update { $0.bodyRewritesTotal += 1 }
        for acted in result.acted { say("\(acted.what) \(phase.rawValue) rewritten \(urls.primary) (\(acted.origin.description))") }
        if let contentType = result.contentType { headers.set("Content-Type", contentType) }
        return changed
    }

    private func runRequestScript(_ match: AdBlockScriptMatch?, head: AdBlockHTTPRequestHead, body: Data?, route: Route, plan: Plan,
                                  completion: @escaping (AdBlockHTTPRequestHead, Data?, Route, Plan, AdBlockScriptResponse?) -> Void) {
        guard let match else { return completion(head, body, route, plan, nil) }
        if match.script.requiresBody, let body, let maximum = match.script.maxSize, maximum > 0, body.count > maximum {
            services.metrics.update { $0.scriptsSkippedTotal += 1 }
            say("script \(match.script.name) request \(plan.urls.primary) not run: its body is \(body.count) bytes, over its max-size of \(maximum)")
            return completion(head, body, route, plan, nil)
        }
        let request = AdBlockScriptRequest(id: plan.id, method: head.method, url: plan.url, headers: head.headers,
                                           body: match.script.requiresBody ? body : nil)
        let scripts = services.scripts
        let label = "script \(match.script.name) request \(plan.urls.primary)"
        callScript(match, label: label, run: { done in scripts.run(match, request: request, completion: done) }) { [self] outcome in
            switch outcome {
            case .request(let changed):
                var next = head
                var nextPlan = plan
                if changed.method != head.method {
                     
                     
                    if !changed.method.isEmpty, changed.method.allSatisfy(AdBlockHTTPParser.isTokenCharacter), changed.method != "CONNECT" {
                        next.method = changed.method
                        nextPlan.method = changed.method
                    } else {
                        say("\(label): its method \(changed.method.debugDescription) cannot be sent; the request keeps \(head.method)")
                    }
                }
                next.headers = Self.keepingProtected(changed.headers, from: head.headers)
                var nextRoute = route
                if changed.url != plan.url {
                     
                    if let moved = Route.to(changed.url, head: &next, hostFollows: false) {
                        nextRoute = moved
                        nextPlan.url = changed.url
                    } else {
                        say("\(label): its new URL \(changed.url) is not an http, https or ws address; the request goes where it was going")
                    }
                }
                 
                completion(next, body == nil ? nil : (changed.body ?? body), nextRoute, nextPlan, nil)
            case .response(let local):
                completion(head, body, route, plan, local)
            case .drop:
                close()
            case .aborted:
                // Surge: "`$done({abort: true})` terminates the connection".
                // It is not the same as leaving the request alone, which is what
                // `.unchanged` does two lines down — a script that aborts is
                // asking for the connection to stop, and the corpus depends on
                // it: `app2smile/rules` maps its own `abort()` to
                // `$done({abort: !0})` on Surge and to a bare `$done()` on Loon,
                // so an abort that forwarded anyway would serve the ad the
                // script refused to rewrite.
                close()
            case .unchanged, .timedOut, .unavailable:
                completion(head, body, route, plan, nil)
            }
        }
    }

     

    private func forward(_ head: AdBlockHTTPRequestHead, _ body: OutgoingBody, route: Route, plan: Plan, retried: Bool = false) {
        var out = head
        switch body {
        case .buffered(let data, _):
            out.headers.remove("Transfer-Encoding")
            out.writeFraming(.length(Int64(data.count)))
        case .stream(let framing):
            out.writeFraming(framing)
        case .streamAfter(_, _, let rechunk):
            out.writeFraming(rechunk ? .chunked : (try? AdBlockHTTPFraming.ofRequest(head)) ?? .none)
        case .none:
            out.writeFraming(.none)
        }
         
         
        keptRequestHeaders = plan.responseScript == nil && !plan.responseCandidates.readsRequestHeaders ? nil : out.headers
        let bytes: Data
        do {
            bytes = try AdBlockHTTPSerializer.head(out)
        } catch {
            body.held?.release()
            say("the request head for \(plan.urls.primary) could not be written as one: \(error)")
            return answer(status: 502)
        }
        withUpstream(route) { [self] upstream, reused in
             
             
             
             
             
            let retries = reused && plan.idempotent && body.replayable && !retried
            let again: (() -> Void)? = retries ? { [self] in
                retryHold = nil
                dropUpstream()
                say("upstream of \(plan.urls.primary) closed its kept-alive connection before answering; \(plan.method) is sent once more on a new one")
                forward(head, body, route: route, plan: plan, retried: true)
            } : nil
            if retries { retryHold = body.held }
            waitOn(.upstream)
            upstream.stream.send(bytes) { [self] error in
                guard !ended else { return }
                guard error == nil else {
                    if let again { return again() }
                    body.held?.release()
                    return lostUpstream(plan, reused: reused)
                }
                let next = { [self] (ok: Bool) in
                    guard ok else { return close() }
                     
                    if !retries { body.held?.release() }
                    awaitingAnswer = true
                    watchClient()
                    readResponse(upstream, plan, again: again, reused: reused)
                }
                switch body {
                case .none:
                    next(true)
                case .buffered(let data, _):
                    guard !data.isEmpty else { return next(true) }
                    sendInPieces(data, to: upstream.stream, .upstream, then: next)
                case .stream(let framing):
                    pumpBody(from: client, .app, reader: AdBlockHTTPBodyReader(framing, limits: .request), to: upstream.stream, .upstream,
                             rechunk: false, then: next)
                case .streamAfter(let collected, let reader, let rechunk):
                    sendCollected(collected, rechunk: rechunk, to: upstream.stream, .upstream) { [self] ok in
                        guard ok else { return close() }
                        pumpBody(from: client, .app, reader: reader, to: upstream.stream, .upstream, rechunk: rechunk, then: next)
                    }
                }
            }
        }
    }

     
     
    private func withUpstream(_ route: Route, _ body: @escaping (AdBlockReader, _ reused: Bool) -> Void) {
        if let current = upstream, current.route == route, !current.reader.ended {
            upstreamIdle = false
            return body(current.reader, true)
        }
        dropUpstream()
        waitOn(nil)
        services.upstreams.open(authority: route.authority, serverName: route.serverName, tls: route.tls) { [self] result in
            guard !ended else {
                if case .success(let stream) = result { stream.cancel() }
                return
            }
            switch result {
            case .success(let stream):
                let reader = AdBlockReader(stream)
                upstream = (route, reader)
                body(reader, false)
            case .failure(let failure):
                services.metrics.update {
                    $0.upstreamFailuresTotal += 1
                    if case .untrusted = failure { $0.upstreamUntrustedTotal += 1 }
                }
                say("upstream \(route.authority) (\(route.serverName)) failed: \(failure)")
                answer(status: 502)
            }
        }
    }

    private func dropUpstream() {
        upstream?.reader.stream.cancel()
        upstream = nil
        responseScan = AdBlockHTTPHeadScan()
        upstreamReading = false
        upstreamIdle = false
        afterUpstreamRead = nil
    }

     
     
     
     
     
     
     
    private func watchIdleUpstream() {
        guard let kept = upstream, !upstreamReading, !kept.reader.ended else { return }
        let reader = kept.reader
        upstreamIdle = true
        upstreamReading = true
        reader.fill { [self] error in
             
            guard !ended, upstream?.reader === reader else { return }
            upstreamReading = false
            if upstreamIdle {
                if !reader.buffer.isEmpty {
                    say("upstream of \(context.host) sent \(reader.buffer.count) bytes while idle: its connection is closed")
                }
                return dropUpstream()
            }
            if let next = afterUpstreamRead {
                afterUpstreamRead = nil
                next(error)
            }
        }
    }

     
     
    private func fillUpstream(_ reader: AdBlockReader, _ completion: @escaping (Error?) -> Void) {
        if upstreamReading, upstream?.reader === reader {
            afterUpstreamRead = completion
            return
        }
        reader.fill { [self] error in
            guard !ended else { return }
            completion(error)
        }
    }

     
     
     
     
    private func lostUpstream(_ plan: Plan, reused: Bool) {
        if reused {
            let why = plan.idempotent ? "its body went as it came and cannot be sent again whole"
                : "\(plan.method) is not sent again (RFC 9110 §9.2.2)"
            say("upstream of \(plan.urls.primary) closed its kept-alive connection before answering; \(why): answered 502")
        } else {
            say("upstream closed before answering \(plan.urls.primary): answered 502")
        }
        answer(status: 502)
    }

     

    private func readResponse(_ upstream: AdBlockReader, _ plan: Plan, again: (() -> Void)?, reused: Bool) {
        guard !ended else { return }
        let parsed: AdBlockHTTPParse<AdBlockHTTPResponseHead>
        do {
            parsed = try AdBlockHTTPParser.response(upstream.buffer, scan: &responseScan)
        } catch {
            say("unreadable response for \(plan.urls.primary): \(error)")
            return answer(status: 502)
        }
        switch parsed {
        case .needMore:
            let nothingYet = upstream.buffer.isEmpty
            guard !upstream.ended else {
                if nothingYet, let again { return again() }
                return nothingYet ? lostUpstream(plan, reused: reused) : answer(status: 502)
            }
            waitOn(.upstream)
            fillUpstream(upstream) { [self] error in
                guard error == nil else {
                    if upstream.buffer.isEmpty, let again { return again() }
                    return upstream.buffer.isEmpty ? lostUpstream(plan, reused: reused) : answer(status: 502)
                }
                readResponse(upstream, plan, again: upstream.buffer.isEmpty ? again : nil, reused: reused)
            }
        case .head(let head, let consumed):
            upstream.buffer = Data(upstream.buffer.dropFirst(consumed))
            responseScan = AdBlockHTTPHeadScan()
             
            retryHold?.release()
            retryHold = nil
            if head.isInterim {
                 
                guard plan.appVersion == .http11 else { return readResponse(upstream, plan, again: nil, reused: reused) }
                guard let bytes = try? AdBlockHTTPSerializer.head(head) else { return answer(status: 502) }
                return send(bytes) { [self] in readResponse(upstream, plan, again: nil, reused: reused) }
            }
            awaitingAnswer = false
            if head.status == 101 {
                guard plan.asksForUpgrade else {
                    say("upstream of \(plan.urls.primary) switched protocols unasked")
                    return answer(status: 502)
                }
                return upgrade(head, upstream, plan)
            }
            respond(head, upstream, plan)
        }
    }

     
    private static func answerCarriesBody(method: String, status: Int) -> Bool {
        !(method == "HEAD" || (100..<200).contains(status) || status == 204 || status == 304)
    }

     
     
     
     
    private static func withoutBody(_ head: AdBlockHTTPResponseHead, appMethod: String) -> AdBlockHTTPResponseHead {
        var out = head
        if answerCarriesBody(method: appMethod, status: head.status) {
            out.headers.remove("Transfer-Encoding")
            out.headers.set("Content-Length", "0")
        } else if appMethod != "HEAD" {
            out.headers.remove("Transfer-Encoding")
            if out.status == 204 { out.headers.remove("Content-Length") }
        }
        return out
    }

    private func respond(_ received: AdBlockHTTPResponseHead, _ upstream: AdBlockReader, _ plan: Plan) {
        var head = received
         
         
        let view = AdBlockMessageView(urls: plan.urls, method: plan.method, requestHeaders: keptRequestHeaders ?? AdBlockHTTPHeaders(),
                                      responseStatus: head.status, responseHeaders: head.headers)
        let responsePlan = services.program.responsePlan(view, candidates: plan.responseCandidates, budget: &budget)
        if let rewritten = responsePlan.responseHeaders { head.headers = rewritten }
        sayHeaderRewrites(responsePlan.headerRewrites, phase: .response, urls: plan.urls)
        let steps = responsePlan.bodySteps
        let readsBody = !steps.isEmpty || plan.responseScript?.script.requiresBody == true
        let framing: AdBlockHTTPFraming
        do {
             
            framing = try AdBlockHTTPFraming.ofResponse(head, requestMethod: plan.method)
        } catch {
            say("unreadable response framing for \(plan.urls.primary): \(error)")
            return answer(status: 502)
        }
         
        head.writeFraming(framing)
        let reusable = head.keepsAlive(framing: framing)
        let keepAlive = plan.keepsAlive && reusable && !windingDown
        let script = plan.responseScript
        let headOnly = script?.script.requiresBody == true ? nil : script
        guard readsBody, framing != .none else {
             
            return runResponseScript(head, body: script?.script.requiresBody == true ? Data() : nil, framing: framing, plan) { [self] changed, _ in
                passResponse(changed, framing, upstream, plan, keepAlive: keepAlive, reusable: reusable)
            }
        }
        let passOn = { [self] (why: AdBlockBodySkip, counted: Bool) in
            skip(why, urls: plan.urls, script: script, counted: counted)
            runResponseScript(head, body: nil, framing: framing, plan, only: headOnly) { [self] changed, _ in
                passResponse(changed, framing, upstream, plan, keepAlive: keepAlive, reusable: reusable)
            }
        }
         
         
        guard services.allowance.allowsBodies else { return passOn(.bodiesStopped, false) }
         
        guard head.status != 206, !head.headers.contains("Content-Range") else { return passOn(.partialContent, false) }
        let transfer = head.headers.tokens("Transfer-Encoding")
        let codings = AdBlockContentCoding.parse(head.headers.first("Content-Encoding"))
        guard transfer.isEmpty || transfer == ["chunked"] else { return passOn(.notDecodable(transfer.joined(separator: ", ")), false) }
        guard codings.count <= 1 else { return passOn(.notDecodable(head.headers.first("Content-Encoding") ?? ""), false) }
        if case .unsupported(let name)? = codings.first { return passOn(.notDecodable(name), false) }
        let declared = (try? AdBlockHTTPFraming.contentLength(head.headers)) ?? nil
        let maximum = steps.isEmpty ? script?.script.maxSize : nil
        let collection: AdBlockBodyCollection
        switch services.budget.begin(declaredLength: declared, maximum: maximum, atOnce: services.allowance.bodiesAtOnce) {
        case .failure(let why):
            return passOn(why, true)
        case .success(let begun):
            collection = begun
        }
        services.allowance.noteActivity()
        self.collection = collection
        collect(from: upstream, framing: framing, limits: .response, into: collection) { [self] collected in
            self.collection = nil
            switch collected {
            case .failed:
                close()
            case .overflow(let payload, let reader, let why):
                skip(why, urls: plan.urls, script: script, counted: true)
                runResponseScript(head, body: nil, framing: framing, plan, only: headOnly) { [self] changed, _ in
                    guard Self.answerCarriesBody(method: plan.appMethod, status: changed.status) else {
                         
                        return passResponse(changed, framing, upstream, plan, keepAlive: keepAlive, reusable: false)
                    }
                    let rechunk = framing == .chunked
                    guard let bytes = serialized(changed) else { return }
                    send(bytes) { [self] in
                        sendCollected(payload, rechunk: rechunk, to: client.stream, .app) { [self] ok in
                            guard ok else { return close() }
                            pumpBody(from: upstream, .upstream, reader: reader, to: client.stream, .app, rechunk: rechunk) { [self] ok in
                                ok ? finished(keepAlive: keepAlive, reusable: reusable) : close()
                            }
                        }
                    }
                }
            case .complete(let held):
                rewrite(head, held: held, coding: codings.first ?? .identity, framing: framing, plan, steps: steps,
                        keepAlive: keepAlive, reusable: reusable, limit: maximum.flatMap { $0 > 0 ? $0 : nil })
            }
        }
    }

    private func rewrite(_ head: AdBlockHTTPResponseHead, held: AdBlockHeldBody, coding: AdBlockContentCoding, framing: AdBlockHTTPFraming,
                         _ plan: Plan, steps: [AdBlockBodyStep], keepAlive: Bool, reusable: Bool, limit: Int?) {
        let script = plan.responseScript
        let headOnly = script?.script.requiresBody == true ? nil : script
        let payload = held.take()
         
         
        let original = { [self] (head: AdBlockHTTPResponseHead) in
            let carries = Self.answerCarriesBody(method: plan.appMethod, status: head.status)
            let out = carries ? head : Self.withoutBody(head, appMethod: plan.appMethod)
            guard let bytes = serialized(out) else { return held.release() }
            let tail = !carries ? Data() : framing == .chunked
                ? AdBlockWire.join(AdBlockHTTPSerializer.chunk(payload), AdBlockHTTPSerializer.lastChunk) : payload
             
            send(AdBlockWire.join(bytes, tail)) { [self] in
                held.release()
                finished(keepAlive: keepAlive, reusable: reusable)
            }
        }
        guard !payload.isEmpty else {
             
            return runResponseScript(head, body: nil, framing: framing, plan, only: headOnly) { changed, _ in original(changed) }
        }
        let cap = min(limit ?? services.budget.limits.maximumBytes, services.budget.limits.maximumBytes)
        let decoded: Data
        switch services.budget.decode(payload, coding: coding, maximumOutputLength: cap) {
        case .failure(let why):
            skip(why, urls: plan.urls, script: script, counted: true)
            return runResponseScript(head, body: nil, framing: framing, plan, only: headOnly) { changed, _ in original(changed) }
        case .success(let data):
            decoded = data
        }
        budget.allow(bodyBytes: decoded.count)
        var unused = AdBlockHTTPHeaders()
        let rewritten = rewriteBody(decoded, steps: steps, phase: .response, urls: plan.urls, headers: &unused)
        let body = rewritten ?? decoded
        runResponseScript(head, body: body, framing: framing, plan) { [self] changed, changedBody in
            guard rewritten != nil || changedBody != nil || changed != head else { return original(head) }
            var out = changed
            let final = changedBody ?? body
            out.headers.remove("Content-Encoding")
            out.headers.remove("Transfer-Encoding")
            let carries = Self.answerCarriesBody(method: plan.appMethod, status: out.status)
            if carries {
                out.headers.writeFraming(.length(Int64(final.count)))
            } else if plan.appMethod == "HEAD" {
                out.headers.set("Content-Length", String(final.count))
            } else {
                out.headers.remove("Content-Length")
            }
            guard let bytes = serialized(out) else { return held.release() }
            send(AdBlockWire.join(bytes, carries ? final : Data())) { [self] in
                held.release()
                finished(keepAlive: keepAlive, reusable: reusable)
            }
        }
    }

     
     
     
     
     
    private func runResponseScript(_ head: AdBlockHTTPResponseHead, body: Data?, framing: AdBlockHTTPFraming, _ plan: Plan,
                                   only: AdBlockScriptMatch?? = .none,
                                   completion: @escaping (AdBlockHTTPResponseHead, Data?) -> Void) {
        let chosen: AdBlockScriptMatch?
        if case .some(let given) = only { chosen = given } else { chosen = plan.responseScript }
        guard let match = chosen else { return completion(head, nil) }
         
         
         
        guard services.allowance.allowsScripts else {
            services.metrics.update { $0.scriptsSkippedTotal += 1 }
            say("script \(match.script.name) response \(plan.urls.primary) not run: scripts are paused for memory")
            return completion(head, nil)
        }
        if match.script.requiresBody, let body, let maximum = match.script.maxSize, maximum > 0, body.count > maximum {
            services.metrics.update { $0.scriptsSkippedTotal += 1 }
            say("script \(match.script.name) response \(plan.urls.primary) not run: its body is \(body.count) bytes, over its max-size of \(maximum)")
            return completion(head, nil)
        }
        let request = AdBlockScriptRequest(id: plan.id, method: plan.method, url: plan.url, headers: keptRequestHeaders ?? AdBlockHTTPHeaders(),
                                           body: nil)
        let response = AdBlockScriptResponse(status: head.status, headers: head.headers, body: match.script.requiresBody ? body : nil)
        let scripts = services.scripts
        let label = "script \(match.script.name) response \(plan.urls.primary)"
        callScript(match, label: label, run: { done in scripts.run(match, request: request, response: response, completion: done) }) { [self] outcome in
            switch outcome {
            case .response(let changed) where changed.status == 101:
                say("\(label): a 101 switches no protocol here: answered 502")
                answer(status: 502)
            case .response(let changed):
                var out = head
                if changed.status != head.status {
                    if (200...599).contains(changed.status) {
                        out.status = changed.status
                        out.reason = Self.reason(changed.status)
                    } else {
                        say("\(label): status \(changed.status) is not a final one; the answer keeps \(head.status)")
                    }
                }
                out.headers = Self.keepingProtected(changed.headers, from: head.headers)
                completion(out, body == nil || framing == .none ? nil : changed.body)
            case .drop:
                close()
            case .aborted:
                // Same contract in the response phase: Surge's `$done({abort:
                // true})` "terminates the connection" for `http-response`
                // scripts too, and the corpus relies on it to cut a response it
                // could not rewrite rather than let it through.
                close()
            case .unchanged, .request, .timedOut, .unavailable:
                completion(head, nil)
            }
        }
    }

     
     
     
    private func passResponse(_ head: AdBlockHTTPResponseHead, _ framing: AdBlockHTTPFraming, _ upstream: AdBlockReader, _ plan: Plan,
                              keepAlive: Bool, reusable: Bool) {
        let carries = Self.answerCarriesBody(method: plan.appMethod, status: head.status)
        guard carries, framing != .none else {
            guard let bytes = serialized(Self.withoutBody(head, appMethod: plan.appMethod)) else { return }
            return send(bytes) { [self] in finished(keepAlive: keepAlive, reusable: reusable && framing == .none) }
        }
        guard let bytes = serialized(head) else { return }
        send(bytes) { [self] in
            pumpBody(from: upstream, .upstream, reader: AdBlockHTTPBodyReader(framing), to: client.stream, .app, rechunk: false) { [self] ok in
                ok ? finished(keepAlive: keepAlive, reusable: reusable) : close()
            }
        }
    }

     
    private func upgrade(_ head: AdBlockHTTPResponseHead, _ upstream: AdBlockReader, _ plan: Plan) {
        guard let bytes = serialized(head) else { return }
        say("upgrade \(plan.urls.primary) to \(head.headers.first("Upgrade") ?? "another protocol"): relayed as it is")
        endRequest()
        disarm()
        let toClient = bytes + upstream.buffer
        let toServer = client.buffer
        client.buffer = Data()
        upstream.buffer = Data()
        self.upstream = nil
        afterClientRead = nil
         
        services.program = .empty
        let relay = AdBlockRelay(client.stream, upstream.stream) { [weak self] in self?.close() }
        self.relay = relay
         
        relay.start(sendingToB: toServer, toA: toClient, aEnded: client.ended, aPending: clientReading)
    }

     

     
    private func finished(keepAlive: Bool, reusable: Bool) {
        endRequest()
        if let kept = upstream, !reusable || !kept.reader.buffer.isEmpty {
             
            if reusable { say("upstream of \(context.host) sent \(kept.reader.buffer.count) bytes past its answer: its connection is closed") }
            dropUpstream()
        }
        guard keepAlive, !windingDown else { return endAfterSending() }
         
         
        adoptNewestIfIdle()
        watchIdleUpstream()
        readRequest()
    }

     
     
     
    private func endRequest() {
        stopStallWatch()
        awaitingAnswer = false
        keptRequestHeaders = nil
        guard let request = current else { return }
        current = nil
        let work = services.program.takeNewRegexWork()
        let stops = budget.stops
        if work.executions != 0 || work.timeouts != 0 || stops != 0 {
            services.metrics.update {
                $0.regexExecutionsTotal += work.executions
                $0.rewriteRegexTimeouts += work.timeouts
                $0.requestBudgetStopsTotal += stops
            }
        }
         
         
        if let cut = services.program.takeNewStops() {
            services.metrics.update {
                $0.rewriteOutputTooLarge += cut.outputTooLarge
                $0.rulesLeftOutThisRun = cut.leftOutThisRun
                $0.rulesLeftOutTooLargeThisRun = cut.leftOutTooLarge
            }
        }
        if stops > 0 {
            say("request \(request.method) \(request.url) ran out of its processing budget: \(stops) step\(stops == 1 ? "" : "s") skipped")
        }
    }

    private func endAfterSending() {
        finalSend(Data())
    }

     
     
    private func finalSend(_ data: Data) {
        guard !ended else { return }
        endRequest()
        disarm()
        let seconds = services.finalSendTimeout
        timer = AdBlockDeadline(after: seconds, queue: services.queue) { [weak self] in
            guard let self, !self.ended else { return }
            self.timer = nil
            self.say("the client did not take its answer within \(seconds) s: closed")
            self.close()
        }
        client.stream.send(data, isFinal: true) { [weak self] _ in
            self?.endedOnLastAnswer = true
            self?.close()
        }
    }

    private func answer(status: Int) {
        let response = AdBlockLocalResponse(status: status, reason: Self.reason(status), contentType: nil, body: Data(), location: nil)
        finalSend(response.bytes(method: "GET", keepAlive: false).data)
    }

     
     
    private func answerLocally(_ local: AdBlockScriptResponse, keepAlive: Bool, plan: Plan) {
        guard local.status != 101 else {
            say("a script's answer to \(plan.urls.primary) is a 101, which switches no protocol here: answered 502")
            return answer(status: 502)
        }
        var headers = AdBlockHTTPHeaders(local.headers.fields.filter { !Self.protectedHeaders.contains($0.name.lowercased()) })
        let status = (200...599).contains(local.status) ? local.status : 200
        let body = local.body ?? Data()
        let carries = Self.answerCarriesBody(method: plan.appMethod, status: status)
        if carries || plan.appMethod == "HEAD" { headers.set("Content-Length", String(body.count)) }
        let keepAlive = keepAlive && !windingDown
        headers.set("Connection", keepAlive ? "keep-alive" : "close")
        let head = AdBlockHTTPResponseHead(version: .http11, status: status, reason: Self.reason(status), headers: headers)
        guard let bytes = try? AdBlockHTTPSerializer.head(head) else {
            say("a script's answer to \(plan.urls.primary) could not be written as one head: answered 502")
            return answer(status: 502)
        }
        let wire = AdBlockWire.join(bytes, carries ? body : Data())
         
        send(wire) { [self] in finished(keepAlive: keepAlive, reusable: true) }
    }

     
     
     
     
    private func serialized(_ head: AdBlockHTTPResponseHead) -> Data? {
        var head = head
        if windingDown, head.status >= 200 { head.headers.set("Connection", "close") }
        do {
            return try AdBlockHTTPSerializer.head(head)
        } catch {
            say("the response head for \(current?.url ?? context.host) could not be written as one: \(error); answered 502")
            answer(status: 502)
            return nil
        }
    }

    private func send(_ data: Data, then next: @escaping () -> Void) {
        sendInPieces(data, to: client.stream, .app) { [self] ok in ok ? next() : close() }
    }

     
     
     
     
     
    static let sendPiece = 64 * 1024

    private func sendInPieces(_ data: Data, from offset: Int? = nil, to sink: AdBlockStream, _ party: Party,
                              then done: @escaping (Bool) -> Void) {
        guard !ended else { return }
        let start = offset ?? data.startIndex
        let end = min(data.endIndex, start + Self.sendPiece)
        waitOn(party)
        sink.send(start == data.startIndex && end == data.endIndex ? data : data[start..<end]) { [self] error in
            guard !ended else { return }
            guard error == nil else { return done(false) }
            end == data.endIndex ? done(true) : sendInPieces(data, from: end, to: sink, party, then: done)
        }
    }

     
     
     
     
     
    private func sendCollected(_ collected: AdBlockBodyCollected, rechunk: Bool, to sink: AdBlockStream, _ party: Party,
                               then done: @escaping (Bool) -> Void) {
        switch collected {
        case .memory(let data):
            guard !data.isEmpty else { return done(true) }
            sendInPieces(rechunk ? AdBlockHTTPSerializer.chunk(data) : data, to: sink, party, then: done)
        case .spilled(let file):
            func next() {
                guard !ended else { return file.close() }
                guard let piece = file.next() else {
                    say("the file a large body of \(current?.url ?? context.host) waited in could not be read back: the session ends")
                    file.close()
                    return done(false)
                }
                guard !piece.isEmpty else {
                    file.close()
                    return done(true)
                }
                waitOn(party)
                sink.send(rechunk ? AdBlockHTTPSerializer.chunk(piece) : piece) { [self] error in
                    guard !ended, error == nil else {
                        file.close()
                        return ended ? () : done(false)
                    }
                    next()
                }
            }
            next()
        }
    }

     
     
    private func skip(_ why: AdBlockBodySkip, urls: AdBlockRequestURLs, script: AdBlockScriptMatch?, counted: Bool) {
        let scriptSkipped = script?.script.requiresBody == true
        services.metrics.update {
            if !counted {
                $0.bodySkippedTotal += 1
                if why.isOverALimit { $0.bodyLimitExceeded += 1 }
            }
            if scriptSkipped { $0.scriptsSkippedTotal += 1 }
        }
        say("body skipped \(urls.primary): \(why.description)\(scriptSkipped ? "; script \(script?.script.name ?? "") not run" : "")")
    }

    private func arm(_ kind: Waiting) {
        guard waiting != kind || timer == nil else { return }
        waiting = kind
        timer?.cancel()
        let seconds = kind == .request ? services.idleTimeout : services.headTimeout
        timer = AdBlockDeadline(after: seconds, queue: services.queue) { [weak self] in
            guard let self, !self.ended else { return }
            self.timer = nil
            switch kind {
            case .request:
                 
                if self.served == 0 { self.say("no request from \(self.context.host) within \(seconds) s: closed") }
            case .head:
                self.say("no complete request head from \(self.context.host) within \(seconds) s: closed")
            }
            self.close()
        }
    }

    private func disarm() {
        timer?.cancel()
        timer = nil
        waiting = nil
    }

    static func reason(_ status: Int) -> String {
        let phrases = [100: "Continue", 101: "Switching Protocols", 200: "OK", 201: "Created", 204: "No Content",
                       206: "Partial Content", 301: "Moved Permanently", 302: "Found", 304: "Not Modified", 307: "Temporary Redirect",
                       308: "Permanent Redirect", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found",
                       405: "Method Not Allowed", 414: "URI Too Long", 431: "Request Header Fields Too Large",
                       500: "Internal Server Error", 501: "Not Implemented", 502: "Bad Gateway", 503: "Service Unavailable",
                       504: "Gateway Timeout", 505: "HTTP Version Not Supported"]
        return phrases[status] ?? "Status \(status)"
    }

     

     
     
     
    private func fillClient(_ next: @escaping (Bool) -> Void) {
        if clientReading {
            afterClientRead = next
            return
        }
        clientReading = true
        client.fill { [self] error in
            clientReading = false
            guard !ended else { return }
            next(error == nil)
        }
    }

     
     
     
     
     
     
     
     
     
     
     
    private func watchClient() {
        guard !clientReading, !client.ended, client.buffer.isEmpty else { return }
        clientReading = true
        client.fill { [self] error in
            clientReading = false
            guard !ended else { return }
            if let relay {
                 
                return relay.resumeA(data: client.take(client.buffer.count), ended: client.ended)
            }
            if let next = afterClientRead {
                afterClientRead = nil
                return next(error == nil)
            }
            if error != nil || (client.ended && awaitingAnswer) {
                say("the app left \(current?.url ?? context.host) before its answer: its request ends")
                close()
            }
        }
    }

     
     
    private func waitOn(_ party: Party?) {
        stallParty = party
        stallSince = DispatchTime.now().uptimeNanoseconds
        guard party != nil, stallTimer == nil, current != nil, !ended else { return }
        let shortest = min(services.appStallTimeout, services.upstreamStallTimeout)
        let interval = max(0.02, min(5, shortest / 4))
        let timer = DispatchSource.makeTimerSource(queue: services.queue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in self?.checkStall() }
        stallTimer = timer
        timer.resume()
    }

    private func checkStall() {
        guard !ended, let party = stallParty else { return }
        let limit = party == .app ? services.appStallTimeout : services.upstreamStallTimeout
        let waited = Double(DispatchTime.now().uptimeNanoseconds &- stallSince) / 1_000_000_000
        guard waited > limit else { return }
        let url = current?.url ?? context.host
        switch party {
        case .app:
            say("the app of \(url) made no progress within \(limit) s: closed")
            close()
        case .upstream where awaitingAnswer:
            say("the upstream of \(url) sent nothing within \(limit) s: answered 504")
            answer(status: 504)
        case .upstream:
            say("the upstream of \(url) sent nothing within \(limit) s: closed")
            close()
        }
    }

    private func stopStallWatch() {
        stallParty = nil
        guard let stallTimer else { return }
        self.stallTimer = nil
        stallTimer.setEventHandler(handler: nil)
        stallTimer.cancel()
    }

     

     
    private func fill(_ source: AdBlockReader, _ party: Party, _ next: @escaping (Bool) -> Void) {
        waitOn(party)
        if source === client { return fillClient(next) }
        fillUpstream(source) { next($0 == nil) }
    }

     
     
     
    private func pumpBody(from source: AdBlockReader, _ sourceParty: Party, reader: AdBlockHTTPBodyReader, to sink: AdBlockStream,
                          _ sinkParty: Party, rechunk: Bool, then done: @escaping (Bool) -> Void) {
        var body = reader
        func step() {
            guard !ended else { return }
            if body.isComplete {
                guard rechunk else { return done(true) }
                waitOn(sinkParty)
                return sink.send(AdBlockHTTPSerializer.lastChunk) { done($0 == nil) }
            }
            if !source.buffer.isEmpty {
                let consumed: (raw: Int, payload: Data)
                do {
                    consumed = try body.consume(source.buffer)
                } catch {
                    return done(false)
                }
                let raw = source.take(consumed.raw)
                let out = rechunk ? AdBlockHTTPSerializer.chunk(consumed.payload) : raw
                guard !out.isEmpty else { return step() }
                waitOn(sinkParty)
                return sink.send(out) { error in error == nil ? step() : done(false) }
            }
            if source.ended {
                do {
                    try body.endOfStream()
                } catch {
                    return done(false)
                }
                return step()
            }
            fill(source, sourceParty) { ok in ok ? step() : done(false) }
        }
        step()
    }

     
     
    private func collect(from source: AdBlockReader, framing: AdBlockHTTPFraming, limits: AdBlockHTTPLimits,
                         into collection: AdBlockBodyCollection, then done: @escaping (Collected) -> Void) {
        var body = AdBlockHTTPBodyReader(framing, limits: limits)
        let party: Party = source === client ? .app : .upstream
        func fail() {
            collection.discard()
            done(.failed)
        }
        func step() {
            guard !ended else { return }
             
             
             
            guard services.allowance.allowsBodies else {
                services.metrics.update { $0.bodySkippedTotal += 1 }
                guard let taken = collection.giveWay() else { return done(.failed) }
                return done(.overflow(taken, body, .bodiesStopped))
            }
            if body.isComplete {
                 
                guard let whole = collection.finishHeld() else { return done(.failed) }
                return done(.complete(whole))
            }
            if !source.buffer.isEmpty {
                var trial = body
                let consumed: (raw: Int, payload: Data)
                do {
                    consumed = try trial.consume(source.buffer)
                } catch {
                    return fail()
                }
                guard collection.append(consumed.payload) else {
                    let why = collection.refusal ?? .grewTooLarge(collection.limit)
                    guard let taken = collection.giveWay() else { return done(.failed) }
                    return done(.overflow(taken, body, why))
                }
                body = trial
                source.buffer = Data(source.buffer.dropFirst(consumed.raw))
                return step()
            }
            if source.ended {
                do {
                    try body.endOfStream()
                } catch {
                    return fail()
                }
                return step()
            }
            fill(source, party) { ok in ok ? step() : fail() }
        }
        step()
    }
}
#endif
