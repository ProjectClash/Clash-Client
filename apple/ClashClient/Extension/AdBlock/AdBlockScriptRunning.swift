#if os(iOS) || os(macOS)
import Foundation

 
 
 
 
 
 
 

struct AdBlockScriptMatch {
    let script: AdBlockScript
    let moduleID: String
    /// The dialect of the module the script came from. A script's identity —
    /// which platform's globals it sees — follows the module, because that is
    /// the host its author wrote it for.
    let moduleFormat: AdBlockModuleFormat
     
    let bodyFile: URL?
    let origin: AdBlockRuleOrigin
     
    let url: String
}

struct AdBlockScriptRequest: Equatable, Sendable {
     
     
    var id: String
    var method: String
    var url: String
    var headers: AdBlockHTTPHeaders
     
    var body: Data?
}

struct AdBlockScriptResponse: Equatable, Sendable {
    var status: Int
    var headers: AdBlockHTTPHeaders
    var body: Data?
}

enum AdBlockScriptOutcome: Equatable, Sendable {
     
    case unchanged
     
    case request(AdBlockScriptRequest)
     
    case response(AdBlockScriptResponse)
     
     
    case drop(String)
     
    case aborted(String)
     
    case timedOut
     
    case unavailable(String)
}

 
 
 
final class AdBlockScriptSink {
    private let queue: DispatchQueue
    private let metrics: AdBlockEngineMetrics
    private let unavailable: (String) -> Void

    init(queue: DispatchQueue, metrics: AdBlockEngineMetrics, unavailable: @escaping (String) -> Void) {
        self.queue = queue
        self.metrics = metrics
        self.unavailable = unavailable
    }

     
    func scriptsUnavailable(_ reason: String) {
        queue.async { [self] in unavailable(reason) }
    }

     
     
    func update(_ change: @escaping (inout AdBlockEngineCounters) -> Void) {
        queue.async { [self] in metrics.update(change) }
    }
}

protocol AdBlockScriptRunning: AnyObject {
     
     
    var isAvailable: Bool { get }
     
    func attach(_ sink: AdBlockScriptSink)
     
     
     
     
    func run(_ match: AdBlockScriptMatch, request: AdBlockScriptRequest,
             completion: @escaping (AdBlockScriptOutcome) -> Void)
    func run(_ match: AdBlockScriptMatch, request: AdBlockScriptRequest, response: AdBlockScriptResponse,
             completion: @escaping (AdBlockScriptOutcome) -> Void)
     
     
     
     
     
    func releaseAll()
}

 
 
final class AdBlockNoScripts: AdBlockScriptRunning {
    init() {}

    var isAvailable: Bool { false }

    func attach(_ sink: AdBlockScriptSink) {}

    func run(_ match: AdBlockScriptMatch, request: AdBlockScriptRequest, completion: @escaping (AdBlockScriptOutcome) -> Void) {
        completion(.unavailable("scripts are not part of this build"))
    }

    func run(_ match: AdBlockScriptMatch, request: AdBlockScriptRequest, response: AdBlockScriptResponse,
             completion: @escaping (AdBlockScriptOutcome) -> Void) {
        completion(.unavailable("scripts are not part of this build"))
    }

    func releaseAll() {}
}

 
 
 
 
 
 
 
 
final class AdBlockScriptCall {
    /// The budget a script gets when its declaration names none, per Loon's
    /// documentation: a request or response script must answer while the
    /// request is held open, so it gets 20 seconds, while a scheduled or
    /// manually-run script has 300. A single 5-second default cut off scripts
    /// that the hub explicitly gives `timeout=300` or `timeout=600`, and gave
    /// the ones that say nothing less than half of what the platform does.
    static func defaultTimeout(for phase: AdBlockRewritePhase) -> Int {
        switch phase {
        case .request, .response: return 20
        case .cron, .generic: return 300
        }
    }

    static let maximumTimeout = 300

    static let grace: TimeInterval = 5

    enum Answer: Equatable, Sendable {
         
        case answered(AdBlockScriptOutcome)
         
        case noAnswer(within: TimeInterval)
    }

     
    static func limit(for script: AdBlockScript, grace: TimeInterval = AdBlockScriptCall.grace) -> TimeInterval {
        let asked = script.timeout ?? defaultTimeout(for: script.phase)
        return TimeInterval(min(maximumTimeout, max(0, asked))) + max(0, grace)
    }

    private var timer: DispatchSourceTimer?
    private var deliver: ((Answer) -> Void)?

    private init(deliver: @escaping (Answer) -> Void) {
        self.deliver = deliver
    }

     
     
     
    @discardableResult
    static func start(on queue: DispatchQueue, limit: TimeInterval,
                      run: (@escaping (AdBlockScriptOutcome) -> Void) -> Void,
                      deliver: @escaping (Answer) -> Void) -> AdBlockScriptCall {
        dispatchPrecondition(condition: .onQueue(queue))
        let call = AdBlockScriptCall(deliver: deliver)
         
         
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + max(0, limit))
        timer.setEventHandler { call.finish(.noAnswer(within: limit)) }
        call.timer = timer
        timer.resume()
         
        run { [weak call] outcome in queue.async { call?.finish(.answered(outcome)) } }
        return call
    }

     
    func cancel() {
        deliver = nil
        timer?.cancel()
        timer = nil
    }

    private func finish(_ answer: Answer) {
        guard let deliver else { return }
        cancel()
        deliver(answer)
    }
}
#endif
