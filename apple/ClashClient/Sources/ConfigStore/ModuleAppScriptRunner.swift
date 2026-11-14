#if os(iOS) || os(macOS)
import Combine
import JavaScriptCore
import Foundation

 
 
 
 
 
 
 
 
 

 
 
struct ModuleAppScriptEntry: Hashable, Identifiable, Sendable {
     
     
    static func id(module: String, origin: ModuleLineOrigin) -> String {
        #"\#(module):\#(origin.section):\#(origin.line)"#
    }

     
     
    var id: String
     
    var name: String
    var moduleID: String
    var kind: ModuleAppScriptKind
     
    var eventName: String? = nil
     
    var imageURL: String? = nil
}

 
enum ModuleAppScriptTrigger: Equatable, Sendable {
     
    case cron(scheduled: Date)
    case networkChanged
     
    case event(String)
     
     
    case generic(node: String, nodeInfo: Data?)
     
     
    case panel(byReader: Bool)
     
     
     
     
    case byReader
}

 
struct ModuleAppScriptResult: Equatable, Sendable {
     
    enum NotRun: Hashable, Sendable {
         
         
        case tunnelNotConnected
         
        case notFound
         
        case busy
         
        case bodyMissing
         
        case bodyMismatch
    }

     
     
    enum Skip: Hashable, Sendable {
         
        case quarantined
         
         
        case paused
         
        case lowMemory
         
        case other

        init(_ reason: ModuleScriptSkipReason) {
            switch reason {
            case .quarantined: self = .quarantined
            case .stopped: self = .paused
            case .lowMemory: self = .lowMemory
            case .phaseMismatch, .cancelled, .sourceMissing, .sourceMismatch: self = .other
            }
        }
    }

    enum Outcome: Hashable, Sendable {
        case done
         
        case aborted(String)
        case timedOut(Double)
         
        case skipped(Skip)
        case notRun(NotRun)
    }

     
     
    struct Panel: Equatable, Sendable {
        var title: String? = nil
        var content: String? = nil
        var icon: String? = nil
        var iconColor: String? = nil
        var style: String? = nil
    }

    var entry: ModuleAppScriptEntry
    var outcome: Outcome
     
     
    var title: String? = nil
    var htmlMessage: String? = nil
    var json: String? = nil
     
    var panel: Panel? = nil
}

 
 
 
protocol ModuleAppScriptCookieKeeping: Sendable {
     
    func cookieHeader(run: String, for url: URL) -> String?
     
    func keep(run: String, setCookies: [String], from url: URL)
     
    func forget(run: String)
}

 
 
 
final class ModuleAppScriptCookieJars: ModuleAppScriptCookieKeeping, @unchecked Sendable {
    private let lock = NSLock()
    private var jars: [String: ModuleScriptCookieJar] = [:]
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = Date.init) { self.now = now }

     
    var runs: Set<String> { lock.lock(); defer { lock.unlock() }; return Set(jars.keys) }

    func cookieHeader(run: String, for url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return jars[run]?.header(for: host, overHTTPS: url.scheme?.lowercased() == "https")
    }

    func keep(run: String, setCookies: [String], from url: URL) {
        guard let host = url.host?.lowercased() else { return }
        let at = now()
        lock.lock()
        jars[run, default: ModuleScriptCookieJar()].store(setCookies, from: host, overHTTPS: url.scheme?.lowercased() == "https", now: at)
        lock.unlock()
    }

    func forget(run: String) {
        lock.lock()
        jars[run] = nil
        lock.unlock()
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
final class ModuleAppScriptNetwork: ModuleScriptNetworking, @unchecked Sendable {
     
     
    let configuration: URLSessionConfiguration
    private let session: URLSession
    private let transfers: Transfers
    private let cookies: (any ModuleAppScriptCookieKeeping)?
    private let through: @Sendable () -> (any ModuleScriptNetworking)?
    private let log: @Sendable (String) -> Void

     
     
    init(configuration given: URLSessionConfiguration = .ephemeral, memory: ModuleScriptMemory = .process,
         cookies: (any ModuleAppScriptCookieKeeping)? = ModuleAppScriptCookieJars(),
         through: @escaping @Sendable () -> (any ModuleScriptNetworking)? = { nil },
         log: @escaping @Sendable (String) -> Void) {
        let configuration = given.copy() as! URLSessionConfiguration
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.configuration = configuration
        self.cookies = cookies
        self.through = through
        self.log = log
        transfers = Transfers(memory: memory)
        session = URLSession(configuration: configuration, delegate: transfers, delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

     
     
    func send(_ request: ModuleScriptHTTPRequest, run: ModuleScriptHTTPRun,
              completion: @escaping @Sendable (Result<ModuleScriptHTTPResponse, ModuleScriptNetworkFailure>) -> Void)
        -> ModuleScriptNetworkCancellation {
        send(request, runID: run.id, deadline: run.deadline, completion: completion)
    }

     
     
    @discardableResult
    func send(_ request: ModuleScriptHTTPRequest, runID: String?, deadline: UInt64?,
              completion: @escaping @Sendable (Result<ModuleScriptHTTPResponse, ModuleScriptNetworkFailure>) -> Void)
        -> ModuleScriptNetworkCancellation {
        if let other = through() {
            return other.send(request, run: ModuleScriptHTTPRun(id: runID ?? "", deadline: deadline ?? .max), completion: completion)
        }
        func fail(_ message: String) -> ModuleScriptNetworkCancellation {
            completion(.failure(ModuleScriptNetworkFailure(message: message)))
            return ModuleScriptNetworkCancellation()
        }
        guard let url = URL(string: request.url), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            return fail(#"not an http or https address: \#(request.url)"#)
        }
         
         
        let noTime = #"the script's run has no time left for it"#
        var seconds = request.timeoutSeconds.flatMap { $0.isFinite ? $0 : nil }
        if let given = seconds, !(given > 0) { return fail(noTime) }
        if let deadline {
            let now = DispatchTime.now().uptimeNanoseconds
            guard deadline > now else { return fail(noTime) }
            let left = Double(deadline - now) / 1_000_000_000
            seconds = min(seconds ?? left, left)
        }
        var asked = URLRequest(url: url)
        asked.httpMethod = request.method.uppercased()
         
         
        if let seconds { asked.timeoutInterval = seconds + 1 }
        for header in request.headers { asked.addValue(header.value, forHTTPHeaderField: header.name) }
        let scriptCookie = asked.value(forHTTPHeaderField: "Cookie")
        let run = runID.flatMap { id in cookies.map { (id: id, cookies: $0) } }
        if let run, let jar = run.cookies.cookieHeader(run: run.id, for: url) {
            asked.setValue(Self.cookie(scriptCookie, jar), forHTTPHeaderField: "Cookie")
        }
        asked.httpBody = request.body
         
         
        let followed = request.options.keys.filter { $0.lowercased() != "auto-redirect" }
        if !followed.isEmpty {
            log(#"[script] $httpClient \#(request.url): not followed in the App: \#(followed.sorted().joined(separator: ", "))"#)
        }
        let task = session.dataTask(with: asked)
        transfers.begin(task, Transfers.Asked(url: request.url, followsRedirects: Self.followsRedirects(request.options),
                                              run: run, scriptCookie: scriptCookie),
                        seconds: seconds, completion: completion)
        task.resume()
         
         
        return ModuleScriptNetworkCancellation { [weak task] in task?.cancel() }
    }

     
    static func cookie(_ own: String?, _ jar: String?) -> String? {
        let parts = [own, jar].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

     
    static func sameOrigin(_ a: URL, _ b: URL) -> Bool {
        func port(_ url: URL) -> Int? { url.port ?? (url.scheme?.lowercased() == "https" ? 443 : url.scheme?.lowercased() == "http" ? 80 : nil) }
        return a.scheme?.lowercased() == b.scheme?.lowercased() && a.host?.lowercased() == b.host?.lowercased() && port(a) == port(b)
    }

     
     
     
     
     
     
     
    static func setCookieLines(_ response: HTTPURLResponse, from url: URL) -> [String] {
        var fields: [String: String] = [:]
        for (name, value) in response.allHeaderFields {
            if let name = name as? String { fields[name] = "\(value)" }
        }
        return HTTPCookie.cookies(withResponseHeaderFields: fields, for: url).map { cookie in
            var line = cookie.name + "=" + cookie.value
            if cookie.domain.hasPrefix(".") { line += #"; Domain="# + cookie.domain.dropFirst() }
            line += #"; Path="# + cookie.path
            if let expires = cookie.expiresDate { line += #"; Expires="# + httpDate.string(from: expires) }
            if cookie.isSecure { line += #"; Secure"# }
            if cookie.isHTTPOnly { line += #"; HttpOnly"# }
            return line
        }
    }

     
    private static let httpDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter
    }()

     
     
    static let credentialHeaders = ["Authorization", "Cookie", "Proxy-Authorization"]

     
    func runEnded(_ id: String) {
        cookies?.forget(run: id)
        through()?.runEnded(id)
    }

     
    static func followsRedirects(_ options: [String: String]) -> Bool {
        guard let value = options.first(where: { $0.key.lowercased() == "auto-redirect" })?.value else { return true }
        return !["false", "0", "no"].contains(value.trimmingCharacters(in: .whitespaces).lowercased())
    }

     
     
     
    private final class Transfers: NSObject, URLSessionDataDelegate, @unchecked Sendable {
         
        struct Asked {
            var url: String
            var followsRedirects: Bool
             
            var run: (id: String, cookies: any ModuleAppScriptCookieKeeping)?
             
            var scriptCookie: String?
        }

        private final class Transfer {
            let asked: Asked
            let completion: @Sendable (Result<ModuleScriptHTTPResponse, ModuleScriptNetworkFailure>) -> Void
            var response: HTTPURLResponse?
            var body = Data()

            init(_ asked: Asked, completion: @escaping @Sendable (Result<ModuleScriptHTTPResponse, ModuleScriptNetworkFailure>) -> Void) {
                self.asked = asked
                self.completion = completion
            }
        }

        private let memory: ModuleScriptMemory
        private let lock = NSLock()
        private var running: [Int: Transfer] = [:]

        init(memory: ModuleScriptMemory) { self.memory = memory }

        func begin(_ task: URLSessionDataTask, _ asked: Asked, seconds: Double?,
                   completion: @escaping @Sendable (Result<ModuleScriptHTTPResponse, ModuleScriptNetworkFailure>) -> Void) {
            let url = asked.url
            lock.lock()
            running[task.taskIdentifier] = Transfer(asked, completion: completion)
            lock.unlock()
             
             
            guard let seconds else { return }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds) { [weak self, weak task] in
                guard let self, let task else { return }
                self.end(task.taskIdentifier, .failure(ModuleScriptNetworkFailure(
                    message: #"no answer from \#(url) in \#(String(format: "%g", seconds)) s"#)))
                task.cancel()
            }
        }

         
        private func end(_ id: Int, _ result: Result<ModuleScriptHTTPResponse, ModuleScriptNetworkFailure>) {
            lock.lock()
            let transfer = running.removeValue(forKey: id)
            lock.unlock()
            transfer?.completion(result)
        }

        private func transfer(_ id: Int) -> Transfer? {
            lock.lock()
            defer { lock.unlock() }
            return running[id]
        }

        private func noRoom(_ transfer: Transfer, _ bytes: Int64) -> ModuleScriptNetworkFailure {
            ModuleScriptNetworkFailure(
                message: #"not enough memory is left for the response from \#(transfer.asked.url) "#
                    + #"(\#(bytes) bytes, \#(memory.spareBytes ?? 0) left past the floor); not read"#)
        }

         
        private func room(for bytes: Int64) -> Bool {
            memory.allows(Int(clamping: bytes) * ModuleScriptMemory.bytesPerReceivedByte)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            guard let transfer = transfer(dataTask.taskIdentifier) else { return completionHandler(.cancel) }
            if response.expectedContentLength > 0, !room(for: response.expectedContentLength) {
                end(dataTask.taskIdentifier, .failure(noRoom(transfer, response.expectedContentLength)))
                return completionHandler(.cancel)
            }
            lock.lock()
            transfer.response = response as? HTTPURLResponse
            transfer.body = Data()
            lock.unlock()
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            guard let transfer = transfer(dataTask.taskIdentifier) else { return }
            lock.lock()
            let total = Int64(transfer.body.count + data.count)
            let past = !room(for: total)
            if !past { transfer.body.append(data) }
            lock.unlock()
            guard past else { return }
            end(dataTask.taskIdentifier, .failure(noRoom(transfer, total)))
            dataTask.cancel()
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            guard let transfer = transfer(task.taskIdentifier) else { return completionHandler(nil) }
            lock.lock()
             
             
            let follows = transfer.asked.followsRedirects
             
             
            if !follows { transfer.response = response }
            lock.unlock()
             
            guard follows, let to = request.url else { return completionHandler(nil) }
            var next = request
             
             
            let from = response.url ?? task.currentRequest?.url
            let sameOrigin = from.map { ModuleAppScriptNetwork.sameOrigin($0, to) } ?? false
            if !sameOrigin {
                for name in ModuleAppScriptNetwork.credentialHeaders { next.setValue(nil, forHTTPHeaderField: name) }
            }
            if let run = transfer.asked.run {
                 
                 
                if let from {
                    let lines = ModuleAppScriptNetwork.setCookieLines(response, from: from)
                    if !lines.isEmpty { run.cookies.keep(run: run.id, setCookies: lines, from: from) }
                }
                let cookie = ModuleAppScriptNetwork.cookie(sameOrigin ? transfer.asked.scriptCookie : nil,
                                                          run.cookies.cookieHeader(run: run.id, for: to))
                next.setValue(cookie, forHTTPHeaderField: "Cookie")
            }
            completionHandler(next)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            guard let transfer = transfer(task.taskIdentifier) else { return }
            if let error { return end(task.taskIdentifier, .failure(ModuleScriptNetworkFailure(message: error.localizedDescription))) }
            lock.lock()
            let http = transfer.response ?? task.response as? HTTPURLResponse
            let body = transfer.body
            lock.unlock()
            guard let http else {
                return end(task.taskIdentifier, .failure(ModuleScriptNetworkFailure(message: #"no HTTP response from \#(transfer.asked.url)"#)))
            }
            let headers = http.allHeaderFields.compactMap { field -> ModuleScriptHeader? in
                guard let name = field.key as? String else { return nil }
                return ModuleScriptHeader(name: name, value: "\(field.value)")
            }
             
            if let run = transfer.asked.run, let from = http.url ?? URL(string: transfer.asked.url) {
                let lines = ModuleAppScriptNetwork.setCookieLines(http, from: from)
                if !lines.isEmpty { run.cookies.keep(run: run.id, setCookies: lines, from: from) }
            }
            end(task.taskIdentifier, .success(ModuleScriptHTTPResponse(status: http.statusCode, headers: headers, body: body)))
        }
    }
}

 
 
@MainActor
final class ModuleAppScriptRunner: ObservableObject {
     
     
    @Published private(set) var entries: [ModuleAppScriptEntry] = []

    private struct Loaded: Sendable {
        let entry: ModuleAppScriptEntry
        let script: ModuleAppScript
        let family: ModuleScriptFamily
        let sourceFile: URL
        let sha256: String
    }

     
    private final class Subscription {
        var token: NSObjectProtocol?
        deinit { if let token { NotificationCenter.default.removeObserver(token) } }
    }

    private let locations: ModuleLocations
    private let tunnelIsConnected: @MainActor () -> Bool
    private let now: () -> Date
    private let timeZone: () -> TimeZone
    private let log: @Sendable (String) -> Void
    private let services: ModuleScriptServices
    private let configuration: ModuleScriptHost.Configuration
    private let store: ModuleScriptStore
    private let quarantine: ModuleScriptQuarantine
    private var host: ModuleScriptHost?
    private var loaded: [String: Loaded] = [:]
     
    private var schedules: [String: ModuleCronExpression?] = [:]
    private var running: Set<String> = []
     
     
    private var readerRuns: [String: [CheckedContinuation<Void, Never>]] = [:]
     
    private var reads = 0
    private let subscription = Subscription()

     
     
     
     
     
     
     
     
     
     
     
     
     
    init(
        container: URL,
        tunnelIsConnected: @escaping @MainActor () -> Bool,
        now: @escaping () -> Date = Date.init,
        timeZone: @escaping () -> TimeZone = { TimeZone.autoupdatingCurrent },
        network: (any ModuleScriptNetworking)? = nil,
        postNotification: (@Sendable (ModuleScriptNotificationRecord) -> Void)? = nil,
        log: @escaping @Sendable (String) -> Void = { ClashLogStore.shared.append($0, stream: .app) },
        config: ModuleScriptConfigAccess = .unavailable,
        dns: ModuleScriptDNSAccess = .unavailable,
        selectPolicy: ((String, String) -> Bool)? = nil,
        environment: ModuleScriptEnvironment = .current(),
        configuration: ModuleScriptHost.Configuration = .app,
        observesPublications: Bool = true
    ) {
        locations = ModuleLocations(container: container)
        self.tunnelIsConnected = tunnelIsConnected
        self.now = now
        self.timeZone = timeZone
        self.log = log
        self.configuration = configuration
        store = ModuleScriptStore(directory: container.appendingPathComponent(ModuleScriptStore.directoryName, isDirectory: true),
                                  log: log)
        quarantine = ModuleScriptQuarantine(file: container.appendingPathComponent(ModuleScriptQuarantine.fileName))
        let words = ModuleScriptNotificationWordsStore(container: container)
        let post = postNotification ?? { record in ModuleScriptNotificationPoster.post(record, words: words, log: log) }
        var services = ModuleScriptServices(
            log: log,
            notify: { request in
                post(ModuleScriptNotificationRecord(
                    scriptName: request.scriptName, title: request.title, subtitle: request.subtitle, body: request.body,
                    openURL: request.openURL, clipboardText: request.clipboardText, sound: request.sound,
                    mediaURL: request.mediaURL, delaySeconds: request.delaySeconds))
            },
            geoip: { _ in nil },
            selectPolicy: selectPolicy ?? { group, policy in
                log(#"[script] $surge.setSelectGroupPolicy(\#(group), \#(policy)): not available to the App's scripts yet"#)
                return false
            },
            environment: environment,
            network: network ?? ModuleAppScriptNetwork(log: log))
         
         
        services.config = config
        services.dns = dns
        self.services = services
        if observesPublications {
            let mine = ModuleStore.normalized(container).path
            subscription.token = NotificationCenter.default.addObserver(forName: ModuleStore.didChange, object: nil, queue: .main) {
                [weak self] note in
                guard (note.object as? URL).map({ ModuleStore.normalized($0).path }) == mine else { return }
                Task { @MainActor in await self?.reload() }
            }
        }
    }

     

     
    private struct AppView: Decodable, Sendable {
        let format: ModuleFormat
        let appScripts: [ModuleAppScript]

        private enum CodingKeys: String, CodingKey { case manifest, sections, appScripts }
        private struct Manifest: Decodable { let format: ModuleFormat }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            format = try c.decode(Manifest.self, forKey: .manifest).format
            let table = ModuleSectionTable.Table(try c.decodeIfPresent([String].self, forKey: .sections) ?? [])
            appScripts = try ModuleSectionTable.$current.withValue(table) {
                try c.decodeIfPresent([ModuleAppScript].self, forKey: .appScripts) ?? []
            }
        }
    }

     
     
     
     
     
     
    func reload() async {
        reads &+= 1
        let read = reads
        let locations = locations, log = log
        let found = await Task.detached(priority: .utility) { Self.read(locations, log: log) }.value
        guard read == reads else { return }
        loaded = found.loaded
        if entries != found.order { entries = found.order }
    }

    private nonisolated static func read(_ locations: ModuleLocations, log: @Sendable (String) -> Void)
        -> (loaded: [String: Loaded], order: [ModuleAppScriptEntry]) {
        let decoder = ModuleJSON.decoder()
        var found: [String: Loaded] = [:]
        var order: [ModuleAppScriptEntry] = []
        guard let data = try? Data(contentsOf: locations.globalManifest),
              let global = try? decoder.decode(ModuleGlobalManifest.self, from: data) else { return (found, order) }
        for module in global.modules {
            guard let ir = try? Data(contentsOf: locations.moduleManifest(module.id)) else {
                log(#"module \#(module.id): its IR is not there; its App scripts are left out"#)
                continue
            }
            guard ModuleJSON.sha256(ir) == module.irSHA256 else {
                log(#"module \#(module.id): its IR is not the one the module list names; read again at the next publication"#)
                continue
            }
            guard let view = try? decoder.decode(AppView.self, from: ir) else {
                log(#"module \#(module.id): its IR does not read; its App scripts are left out"#)
                continue
            }
            let family = ModuleScriptFamily(format: view.format)
            for script in view.appScripts {
                 
                guard let sha = script.bodySHA256 else { continue }
                let entry = ModuleAppScriptEntry(
                    id: ModuleAppScriptEntry.id(module: module.id, origin: script.origin), name: script.name,
                    moduleID: module.id, kind: script.kind, eventName: script.eventName, imageURL: script.imageURL)
                guard found[entry.id] == nil else { continue }
                found[entry.id] = Loaded(entry: entry, script: script, family: family,
                                         sourceFile: locations.script(module.id, sha256: sha), sha256: sha)
                order.append(entry)
            }
        }
        return (found, order)
    }

    func entries(_ kind: ModuleAppScriptKind) -> [ModuleAppScriptEntry] {
        entries.filter { $0.kind == kind }
    }

     
     
    func entry(id: String) -> ModuleAppScriptEntry? {
        loaded[id]?.entry
    }

     
     
    func genericScripts(forNode name: String) -> [ModuleAppScriptEntry] {
        entries(.generic)
    }

     

     
     
     
    func nextFire(of entry: ModuleAppScriptEntry, after date: Date) -> Date? {
        guard let script = loaded[entry.id]?.script, script.kind == .cron, let text = script.cronExpression,
              let schedule = schedule(text, for: entry) else { return nil }
        return schedule.nextFire(after: date, in: timeZone())
    }

    private func schedule(_ text: String, for entry: ModuleAppScriptEntry) -> ModuleCronExpression? {
        if let known = schedules[text] { return known }
        switch ModuleCronExpression.parse(text) {
        case .success(let schedule):
            schedules[text] = schedule
            return schedule
        case .failure(let failure):
            log(#"module script \#(entry.name): its schedule \#(text) does not read (\#(failure)); it never runs"#)
            schedules[text] = .some(nil)
            return nil
        }
    }

     
     
     
    func dueCron(since: Date) -> [(entry: ModuleAppScriptEntry, scheduled: Date)] {
        let upTo = now()
        return entries(.cron).compactMap { entry in
            guard let first = nextFire(of: entry, after: since), first.timeIntervalSince(upTo) <= 0 else { return nil }
            return (entry, lastFire(of: entry, from: first, upTo: upTo))
        }
    }

     
     
    private func lastFire(of entry: ModuleAppScriptEntry, from first: Date, upTo: Date) -> Date {
        var last = first
        for window in [60.0, 3_600, 86_400] {
            if let near = nextFire(of: entry, after: upTo.addingTimeInterval(-window)), near.timeIntervalSince(upTo) <= 0 {
                if near > last { last = near }
                break
            }
        }
        for _ in 0..<1_000 {
            guard let next = nextFire(of: entry, after: last), next.timeIntervalSince(upTo) <= 0 else { break }
            last = next
        }
        return last
    }

     
    func runDueCron(since: Date) async -> [ModuleAppScriptResult] {
        var results: [ModuleAppScriptResult] = []
        for (entry, scheduled) in dueCron(since: since) {
            results.append(await run(entry, trigger: .cron(scheduled: scheduled)))
        }
        return results
    }

     

     
     
    func runEvent(_ name: String) async -> [ModuleAppScriptResult] {
        let event = name.lowercased()
        var results: [ModuleAppScriptResult] = []
        for entry in entries(.event) where entry.eventName == event {
            results.append(await run(entry, trigger: .event(event)))
        }
        return results
    }

     
     
     
    func runNetworkChanged() async -> [ModuleAppScriptResult] {
        var results: [ModuleAppScriptResult] = []
        for entry in entries(.networkChanged) {
            results.append(await run(entry, trigger: .networkChanged))
        }
        return results
    }

     

     
     
    func run(_ entry: ModuleAppScriptEntry, trigger: ModuleAppScriptTrigger) async -> ModuleAppScriptResult {
         
         
         
         
         
         
         
        if case .cron = trigger {
            while readerRuns[entry.id] != nil {
                await withCheckedContinuation { readerRuns[entry.id, default: []].append($0) }
            }
            if Task.isCancelled { return ModuleAppScriptResult(entry: entry, outcome: .skipped(.other)) }
        }
        guard let script = loaded[entry.id] else {
            log(#"module script \#(entry.name): no module turned on has it now; not run"#)
            return ModuleAppScriptResult(entry: entry, outcome: .notRun(.notFound))
        }
        guard tunnelIsConnected() else {
            log(#"module script \#(entry.name): Clash is not connected, so it did not run"#)
            return ModuleAppScriptResult(entry: entry, outcome: .notRun(.tunnelNotConnected))
        }
        guard running.insert(entry.id).inserted else {
            return ModuleAppScriptResult(entry: entry, outcome: .notRun(.busy))
        }
        defer { running.remove(entry.id) }
        if trigger == .byReader {
            readerRuns[entry.id] = []
            log(#"module script \#(entry.name): run by the reader"#)
        }
        defer {
            if trigger == .byReader, let waiting = readerRuns.removeValue(forKey: entry.id) {
                waiting.forEach { $0.resume() }
            }
        }
        var declaration = ModuleScriptDeclaration(
            name: script.script.name, kind: Self.hostKind(script.script), family: script.family,
            scriptPath: script.script.scriptURL, sourceFile: script.sourceFile, sourceSHA256: script.sha256,
            requiresBody: false, binaryBodyMode: false, timeout: script.script.timeout.map(Double.init),
            argument: Self.argument(script.script))
        switch trigger {
        case .generic(let node, let info): declaration.environmentParameters = Self.parameters(node: node, info: info)
        case .panel(let byReader): declaration.trigger = byReader ? "button" : "auto-interval"
        case .cron, .networkChanged, .event, .byReader: break
        }
        let outcome = await currentHost().run(declaration, phase: nil, request: nil, response: nil, body: nil)
        return Self.result(entry, outcome)
    }

     
     
    private func currentHost() -> ModuleScriptHost {
        if let host, host.availability == .available { return host }
        if host != nil { log(#"[script] the App's script host stopped; a new one runs the App's scripts"#) }
        let made = ModuleScriptHost(configuration: configuration, services: services, store: store, quarantine: quarantine)
        host = made
        return made
    }

    private static func hostKind(_ script: ModuleAppScript) -> ModuleScriptKind {
        switch script.kind {
        case .cron: return .cron
        case .event: return .event(script.eventName ?? "")
        case .networkChanged: return .networkChanged
        case .generic: return .generic
        }
    }

     
    private static func argument(_ script: ModuleAppScript) -> ModuleScriptArgument? {
        if let typed = script.typedArguments {
            return .object(typed.map { field in
                let value: ModuleScriptArgument.Value
                switch field.value {
                case .string(let text): value = .string(text)
                case .number(let number): value = .number(number)
                case .bool(let flag): value = .bool(flag)
                case .null: value = .null
                }
                return ModuleScriptArgument.Field(name: field.name, value: value)
            })
        }
        return script.argument.map { .text($0) }
    }

     
    private static func parameters(node: String, info: Data?) -> String? {
        var object: [String: Any] = ["node": node]
        if let info, let parsed = try? JSONSerialization.jsonObject(with: info) { object["nodeInfo"] = parsed }
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private static func result(_ entry: ModuleAppScriptEntry, _ outcome: ModuleScriptHostOutcome) -> ModuleAppScriptResult {
        switch outcome {
        case .done(.completed(let json)):
            var result = ModuleAppScriptResult(entry: entry, outcome: .done, json: json)
            if let json, let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] {
                result.title = object["title"] as? String
                result.htmlMessage = object["htmlMessage"] as? String
                let panel = ModuleAppScriptResult.Panel(
                    title: object["title"] as? String, content: object["content"] as? String, icon: object["icon"] as? String,
                    iconColor: (object["icon-color"] ?? object["iconColor"]) as? String, style: object["style"] as? String)
                if panel != ModuleAppScriptResult.Panel() { result.panel = panel }
            }
            return result
        case .done:
            return ModuleAppScriptResult(entry: entry, outcome: .done)
        case .aborted(let message):
            return ModuleAppScriptResult(entry: entry, outcome: .aborted(message))
        case .timedOut(let seconds):
            return ModuleAppScriptResult(entry: entry, outcome: .timedOut(seconds))
        case .skipped(.sourceMissing):
            return ModuleAppScriptResult(entry: entry, outcome: .notRun(.bodyMissing))
        case .skipped(.sourceMismatch):
            return ModuleAppScriptResult(entry: entry, outcome: .notRun(.bodyMismatch))
        case .skipped(let reason):
            return ModuleAppScriptResult(entry: entry, outcome: .skipped(.init(reason)))
        }
    }
}
#endif
