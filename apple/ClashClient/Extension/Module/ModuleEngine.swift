#if os(iOS) || os(macOS)
import Darwin
import Foundation
import Network

 
 
 
 
 
 
 

 
struct ModuleEngineLog: Sendable {
    let sink: @Sendable (String) -> Void

    func say(_ line: String) {
        sink("[modules] " + line)
    }

    static let silent = ModuleEngineLog { _ in }
}

 
 
struct ModuleLogLimiter {
    private var lastAt: Date?
    private var heldBack = 0

     
     
    mutating func admit(_ now: Date) -> Int? {
        if let lastAt, (0..<1).contains(now.timeIntervalSince(lastAt)) {
            heldBack += 1
            return nil
        }
        lastAt = now
        defer { heldBack = 0 }
        return heldBack
    }

    static func suffix(_ heldBack: Int) -> String {
        heldBack == 0 ? "" : " (and \(heldBack) more since the last line)"
    }
}

 
final class ModuleEngineMetrics {
    private(set) var counters = ModuleEngineCounters()
    var onChange: (() -> Void)?

    func update(_ change: (inout ModuleEngineCounters) -> Void) {
        change(&counters)
        onChange?()
    }
}

 
struct ModuleConnectTarget: Equatable, Sendable {
    let host: String
    let port: UInt16
    let isAddress: Bool
    let isIPv6: Bool

    var authority: String { isIPv6 ? "[\(host)]:\(port)" : "\(host):\(port)" }

     
    var hostField: String {
        let name = isIPv6 ? "[\(host)]" : host
        return port == 80 ? name : "\(name):\(port)"
    }

     
    static func parse(_ text: String, defaultPort: UInt16?) -> ModuleConnectTarget? {
        var host = text
        var port = defaultPort
        if text.hasPrefix("[") {
            guard let close = text.firstIndex(of: "]") else { return nil }
            host = String(text[text.index(after: text.startIndex)..<close])
            let rest = text[text.index(after: close)...]
            if rest.hasPrefix(":") {
                port = UInt16(rest.dropFirst())
            } else if !rest.isEmpty {
                return nil
            }
        } else if let colon = text.lastIndex(of: ":"), text.firstIndex(of: ":") == colon {
            host = String(text[..<colon])
            port = UInt16(text[text.index(after: colon)...])
        }
        guard let port, port != 0, !host.isEmpty else { return nil }
        let lowered = host.lowercased()
        var v4 = in_addr()
        var v6 = in6_addr()
        let isV4 = inet_pton(AF_INET, lowered, &v4) == 1
        let isV6 = !isV4 && inet_pton(AF_INET6, lowered, &v6) == 1
        guard isV4 || isV6 || lowered.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-._".contains($0)) }) else {
            return nil
        }
        return ModuleConnectTarget(host: lowered, port: port, isAddress: isV4 || isV6, isIPv6: isV6)
    }
}

 
enum ModuleClientHello {
    enum Verdict: Equatable, Sendable {
        case needMore
        case serverName(String)
        case noServerName
        case notTLS
    }

     
    static let maximumBytes = 16 * 1024 + 5

    static func inspect(_ data: Data) -> Verdict {
        var scan = ModuleClientHelloScan()
        return inspect(data, scan: &scan)
    }

     
     
     
    static func inspect(_ data: Data, scan: inout ModuleClientHelloScan) -> Verdict {
        switch collect(data, scan: &scan) {
        case .needMore: return .needMore
        case .notTLS: return .notTLS
        case .noServerName: return .noServerName
        case .message(let hello):
            guard let entry = extensions(in: hello).first(where: { $0.type == 0 }) else { return .noServerName }
            var cursor = entry.start + 2
            let end = entry.start + entry.length
            while cursor + 3 <= end, let nameLength = u16(hello, cursor + 1) {
                let nameType = hello[cursor]
                cursor += 3
                guard cursor + nameLength <= end else { return .noServerName }
                if nameType == 0 {
                     
                     
                     
                     
                     
                     
                    guard let name = String(bytes: hello[cursor..<(cursor + nameLength)], encoding: .ascii)?.lowercased(),
                          isDomainName(name) else { return .noServerName }
                    return .serverName(name)
                }
                cursor += nameLength
            }
            return .noServerName
        }
    }

     
     
     
     
     
    static func isDomainName(_ name: String) -> Bool {
        let bytes = Array(name.utf8)
        guard !bytes.isEmpty, bytes.count <= 253 else { return false }
        var last = UInt8(ascii: ".")
        var nonNumeric = false
        var label = 0
        for byte in bytes {
            switch byte {
            case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "_"):
                nonNumeric = true
                label += 1
            case UInt8(ascii: "0")...UInt8(ascii: "9"):
                label += 1
            case UInt8(ascii: "-"):
                guard last != UInt8(ascii: ".") else { return false }
                label += 1
                nonNumeric = true
            case UInt8(ascii: "."):
                guard last != UInt8(ascii: "."), last != UInt8(ascii: "-"), label > 0, label <= 63 else { return false }
                label = 0
            default:
                return false
            }
            last = byte
        }
        return last != UInt8(ascii: "-") && label <= 63 && label > 0 && nonNumeric
    }

     
     
    static func random(_ data: Data) -> Data? {
        let bytes = [UInt8](data.prefix(43))
        guard bytes.count == 43, bytes[0] == 0x16, bytes[5] == 0x01 else { return nil }
        return Data(bytes[11..<43])
    }

     
     
     
    static func offersEncryptedClientHello(_ data: Data) -> Bool {
        guard case .message(let hello) = collect(data) else { return false }
        return extensions(in: hello).contains { $0.type == 0xFE0D }
    }

     
     
     
    static func applicationProtocols(_ data: Data) -> [String]? {
        guard case .message(let hello) = collect(data),
              let entry = extensions(in: hello).first(where: { $0.type == 16 }) else { return nil }
        let end = entry.start + entry.length
        guard let listLength = u16(hello, entry.start), entry.start + 2 + listLength == end else { return [] }
        var names: [String] = []
        var cursor = entry.start + 2
        while cursor < end {
            let length = Int(hello[cursor])
            cursor += 1
            guard length > 0, cursor + length <= end,
                  let name = String(bytes: hello[cursor..<(cursor + length)], encoding: .ascii) else { return [] }
            names.append(name)
            cursor += length
        }
        return names
    }

    private enum Collected {
        case needMore
        case notTLS
        case noServerName
        case message([UInt8])
    }

    private static func collect(_ data: Data) -> Collected {
        var scan = ModuleClientHelloScan()
        return collect(data, scan: &scan)
    }

     
     
    private static func collect(_ data: Data, scan: inout ModuleClientHelloScan) -> Collected {
        let available = min(data.count, maximumBytes)
        let base = data.startIndex
        guard available > 0 else { return .needMore }
        guard data[base] == 0x16 else { return .notTLS }
        let tooBig: Collected = available >= maximumBytes ? .noServerName : .needMore
        while true {
            if scan.handshake.count >= 4 {
                guard scan.handshake[0] == 0x01 else { return .noServerName }
                let messageLength = Int(scan.handshake[1]) << 16 | Int(scan.handshake[2]) << 8 | Int(scan.handshake[3])
                if scan.handshake.count >= 4 + messageLength {
                    return .message(Array(scan.handshake[4..<(4 + messageLength)]))
                }
            }
            let offset = scan.offset
            guard available >= offset + 5 else { return tooBig }
            guard data[base + offset] == 0x16, data[base + offset + 1] == 0x03 else {
                return offset == 0 ? .notTLS : .noServerName
            }
            let length = Int(data[base + offset + 3]) << 8 | Int(data[base + offset + 4])
            guard available >= offset + 5 + length else { return tooBig }
            scan.handshake += data[(base + offset + 5)..<(base + offset + 5 + length)]
            scan.offset = offset + 5 + length
            scan.recordsRead += 1
        }
    }

    private static func u16(_ bytes: [UInt8], _ at: Int) -> Int? {
        at + 1 < bytes.count ? Int(bytes[at]) << 8 | Int(bytes[at + 1]) : nil
    }

     
    private static func extensions(in hello: [UInt8]) -> [(type: Int, start: Int, length: Int)] {
        var index = 34
        guard index < hello.count else { return [] }
        index += 1 + Int(hello[index])
        guard let suites = u16(hello, index) else { return [] }
        index += 2 + suites
        guard index < hello.count else { return [] }
        index += 1 + Int(hello[index])
        guard let extensionsLength = u16(hello, index) else { return [] }
        index += 2
        let end = min(hello.count, index + extensionsLength)
        var found: [(type: Int, start: Int, length: Int)] = []
        while index + 4 <= end, let type = u16(hello, index), let length = u16(hello, index + 2) {
            index += 4
            guard index + length <= end else { break }
            found.append((type, index, length))
            index += length
        }
        return found
    }
}

 
 
struct ModuleClientHelloScan: Equatable, Sendable {
    fileprivate(set) var offset = 0
    fileprivate(set) var handshake: [UInt8] = []
     
    fileprivate(set) var recordsRead = 0

    init() {}
}

 
struct ModuleEngineSettings: Equatable, Sendable {
    var listenPort: UInt16
    var reinjectPort: UInt16
    var certEntryIP: String?
    var mitmHosts: ModuleHostList
    var forceHTTPEngineHosts: ModuleHostList
    var decryptsTLS: Bool
     
     
    var reinjectCredentials: ModuleReinjectAuthorization? = nil
     
     
    var engineProxyCredentials: ModuleReinjectAuthorization? = nil
     
     
     
    var http2Modules: Set<String> = []
}

extension ModuleEngineSettings {
    init(_ assignment: ModuleEngineAssignment) {
         
         
        func usable(_ pair: ModuleReinjectAuthorization?) -> ModuleReinjectAuthorization? {
            pair.flatMap { $0.username.isEmpty || $0.password.isEmpty ? nil : $0 }
        }
        self.init(listenPort: assignment.ports.engine, reinjectPort: assignment.ports.reinject,
                  certEntryIP: assignment.certEntryIP, mitmHosts: assignment.mitmHosts,
                  forceHTTPEngineHosts: assignment.forceHTTPEngineHosts, decryptsTLS: assignment.decryptsTLS,
                  reinjectCredentials: usable(assignment.reinjectCredentials),
                  engineProxyCredentials: usable(assignment.engineProxyCredentials),
                  http2Modules: Set(assignment.modules.filter { $0.http2 == true }.map(\.id)))
    }
}

 
struct ModuleCertificatePage: Equatable, Sendable {
    static let profileName = ModuleEngineLocations.certificateProfileName
    static let certificateName = ModuleEngineLocations.certificateFileName

    var html: Data
    var profile: Data?
    var certificate: Data?
    var fingerprint: String

     
    static let maximumPageBytes = 512 * 1024
    static let maximumFileBytes = 64 * 1024

     
    static func load(_ locations: ModuleEngineLocations) -> ModuleCertificatePage? {
        guard let metadata = ModuleEngineFiles.read(ModuleCAMetadata.self, from: locations.caMetadata,
                                                     maximumBytes: ModuleCAFiles.maximumBytes),
              let html = ModuleEngineFiles.data(from: locations.certificatePage, maximumBytes: maximumPageBytes) else { return nil }
        return ModuleCertificatePage(
            html: html, profile: ModuleEngineFiles.data(from: locations.certificateProfile, maximumBytes: maximumFileBytes),
            certificate: ModuleEngineFiles.data(from: locations.certificateFile, maximumBytes: maximumFileBytes),
            fingerprint: metadata.fingerprintSHA256)
    }

     
    func answer(_ request: ModuleHTTPRequestHead) -> (bytes: Data, handedOut: Bool) {
        var path = request.target
        if let url = URL(string: path), url.scheme != nil { path = url.path.isEmpty ? "/" : url.path }
        if let query = path.firstIndex(of: "?") { path = String(path[..<query]) }
        let chosen: (status: Int, type: String, body: Data, handedOut: Bool)
        switch path {
        case "/" + Self.profileName where profile != nil:
            chosen = (200, "application/x-apple-aspen-config", profile ?? Data(), true)
        case "/" + Self.certificateName where certificate != nil:
            chosen = (200, "application/x-x509-ca-cert", certificate ?? Data(), true)
        default:
             
             
             
            chosen = (200, "text/html; charset=utf-8", html, false)
        }
        var headers = ModuleHTTPHeaders([
            .init(name: "Content-Type", value: chosen.type),
            .init(name: "Content-Length", value: String(chosen.body.count)),
            .init(name: "Cache-Control", value: "no-store"),
            .init(name: "Connection", value: "close"),
        ])
         
        let handedOut = chosen.handedOut && request.method != "HEAD"
        if chosen.handedOut { headers.add("Content-Disposition", "attachment; filename=\"\(path.dropFirst())\"") }
        let head = ModuleHTTPResponseHead(version: .http11, status: chosen.status, reason: "OK", headers: headers)
         
         
        guard let bytes = try? ModuleHTTPSerializer.head(head) else { return (ModuleEngineAnswers.serverError, false) }
        return (bytes + (request.method == "HEAD" ? Data() : chosen.body), handedOut)
    }
}

enum ModuleEngineAnswers {
    static let serverError = Data("HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
    static let unavailable = Data("HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
}

enum ModuleInterceptKind: Equatable, Sendable {
    case tls(serverName: String)
    case plainHTTP(host: String)
}

 
protocol ModuleIntercepting: AnyObject {
     
     
     
     
     
     
     
     
     
     
     
     
     
    func intercept(_ client: ModuleStream, target: ModuleConnectTarget, kind: ModuleInterceptKind,
                   buffered: Data, clientEnded: Bool, onEnd: @escaping () -> Void) -> Bool
     
     
    func closeAll()
     
     
    func shed(for rung: ModuleEngineReport.Rung)
}

extension ModuleIntercepting {
    func closeAll() {}
    func shed(for rung: ModuleEngineReport.Rung) {}
}

enum ModuleEngineError: Error, Equatable, Sendable {
    case bindFailed(String)
}

 
 
 
 
 
 
 
 
struct ModulePassThroughCauses: OptionSet, Sendable {
    let rawValue: Int

    static let memory = ModulePassThroughCauses(rawValue: 1 << 0)
    static let certificate = ModulePassThroughCauses(rawValue: 1 << 1)
    static let identity = ModulePassThroughCauses(rawValue: 1 << 2)
     
     
     
     
    static let decryptionOff = ModulePassThroughCauses(rawValue: 1 << 3)
}

final class ModuleEngine {
    static let certificateHostName = "cert.clash"
     
     
     
     
     
     
     
     
     
     
     
     
     
    static let loopBreakerLimit = 128
     
    static let ownHelloLimit = 1024
    static let ownHelloWindow: TimeInterval = 30
     
#if os(macOS)
    static let defaultSessionLimit = 1024
#else
    static let defaultSessionLimit = 256
#endif
     
     
    static let defaultHeadTimeout: TimeInterval = 10
    static let defaultFirstByteTimeout: TimeInterval = 5
     
     
    static let defaultFinalSendTimeout: TimeInterval = 10
     
    static let proxyRealm = "Clash"
     
     
     
     
     
     
     
     
     
    static let established = Data("HTTP/1.1 200 Connection established\r\n\r\n".utf8)

    let queue: DispatchQueue
    let log: ModuleEngineLog
    let metrics: ModuleEngineMetrics
    private(set) var settings: ModuleEngineSettings {
        didSet { http2Hosts = Self.http2Hosts(of: settings) }
    }
     
     
    private(set) var http2Hosts: ModuleHostList
    private(set) var certificatePage: ModuleCertificatePage?
    var interceptor: ModuleIntercepting?
     
     
     
     
    var passThroughCauses: ModulePassThroughCauses = []
    var passThroughOnly: Bool { !passThroughCauses.isEmpty }
     
    var passedThroughHosts: Set<String> = []
     
     
     
    lazy var systemPinning: ModuleSystemPinning = .system
    private var saidSystemPinned: Set<String> = []
    var onCertificateHandedOut: ((String) -> Void)?
     
     
    var onSession: (() -> Void)?
     
    var sessionLimit = ModuleEngine.defaultSessionLimit
    var headTimeout = ModuleEngine.defaultHeadTimeout
    var firstByteTimeout = ModuleEngine.defaultFirstByteTimeout
    var finalSendTimeout = ModuleEngine.defaultFinalSendTimeout
     
     
    var ladder: ModuleMemoryLadder?
     
     
     
     
     
    var onMemoryStopEnded: (() -> Void)?
     
     
    var onListenerFailure: ((String) -> Void)?
     
    private(set) var decryptedSessionCount = 0
     
     
     
     
     
     
     
    var awaitsRules = false
    var onRulesNeeded: (() -> Void)?
    var buildHoldTimeout: TimeInterval = 10
    private var waitingForRules: [() -> Void] = []
    private var holdGeneration = 0
     
     
    private var rulesAsked = false
     
     
     
    var idleAfter: TimeInterval?
    var onIdle: (() -> Void)?
    private var rulesSessions = 0
    private var idleWork: DispatchWorkItem?

     
     
     
     
    private let stateLock = NSLock()
    private var lockedListener: NWListener?
    private var lockedGate: ModuleListenerGate?
    private var lockedBoundPort: UInt16?
    private var rebindsClaimed = 0
     
     
     
     
    private var lastRebindAt: TimeInterval?
    private var listenerFailures: [TimeInterval] = []

     
     
     
    static func monotonicNow() -> TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
    }

    private func withState<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }

    private var listener: NWListener? {
        get { withState { lockedListener } }
        set { withState { lockedListener = newValue } }
    }

    private var gate: ModuleListenerGate? {
        get { withState { lockedGate } }
        set { withState { lockedGate = newValue } }
    }

     
    private var boundPort: UInt16? {
        get { withState { lockedBoundPort } }
        set { withState { lockedBoundPort = newValue } }
    }

    private var sessions: [Int: ModuleEngineSession] = [:]
    private var lastSession = 0
    private var liveUpstreams: [String: Int] = [:]
     
    private var ownHellos: [Data: Date] = [:]

    init(settings: ModuleEngineSettings, certificatePage: ModuleCertificatePage?, log: ModuleEngineLog,
         metrics: ModuleEngineMetrics = ModuleEngineMetrics(),
         queue: DispatchQueue = DispatchQueue(label: "modules.engine")) {
        self.settings = settings
        http2Hosts = Self.http2Hosts(of: settings)
        self.certificatePage = certificatePage
        self.log = log
        self.metrics = metrics
        self.queue = queue
    }

     
     
    deinit {
        listener?.cancel()
    }

    var sessionCount: Int { sessions.count }

     
     
     
    func start() throws -> UInt16 {
        try bind(settings.listenPort)
    }

    private func bind(_ requested: UInt16) throws -> UInt16 {
        dispatchPrecondition(condition: .notOnQueue(queue))
        if let listener, let port = listener.port?.rawValue { return port }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: requested) ?? .any)
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            throw ModuleEngineError.bindFailed("\(error)")
        }
        let gate = ModuleListenerGate(listener)
        listener.stateUpdateHandler = { [weak self] state in
            if let self {
                self.listenerStateChanged(state, gate: gate)
            } else if case .cancelled = state {
                gate.markCancelled()
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return connection.cancel() }
            self.accept(connection)
        }
        listener.start(queue: queue)
        switch gate.wait(timeout: 2) {
        case .ready?:
            guard let bound = listener.port?.rawValue, bound != 0 else {
                listener.cancel()
                throw ModuleEngineError.bindFailed("ready without a port")
            }
            withState {
                lockedListener = listener
                lockedGate = gate
                lockedBoundPort = bound
                 
                rebindsClaimed = 0
            }
            return bound
        case .failed(let reason)?:
            listener.cancel()
            throw ModuleEngineError.bindFailed(reason)
        case nil:
            listener.cancel()
            throw ModuleEngineError.bindFailed("no answer from the listener within 2 s")
        }
    }

     
     
     
    var isListening: Bool {
        withState { lockedListener != nil && !(lockedGate?.failedAfterReady ?? true) }
    }

     
    enum RebindDecision: Equatable, Sendable {
        case now
         
        case after(TimeInterval)
         
        case never(String)
    }

     
     
     
     
     
    func noteListenerFailure(at now: TimeInterval, limit: Int, spacing: TimeInterval, failureLimit: Int,
                             failureWindow: TimeInterval) -> RebindDecision {
        withState {
            listenerFailures = listenerFailures.filter { now - $0 < failureWindow && $0 <= now } + [now]
            guard rebindsClaimed < limit else { return .never(limit == 0 ? "rebinds are off" : "this listener was bound again already") }
            guard listenerFailures.count < failureLimit else {
                return .never("it stopped \(listenerFailures.count) times within \(Int(failureWindow)) s")
            }
            rebindsClaimed += 1
             
             
            let wait = lastRebindAt.map { min(spacing - (now - $0), spacing) } ?? 0
            return wait > 0 ? .after(wait) : .now
        }
    }

     
    func noteRebind(at now: TimeInterval) {
        withState { lastRebindAt = now }
    }

     
     
     
     
     
     
    func listenerStateChanged(_ state: NWListener.State, gate given: ModuleListenerGate? = nil) {
        guard let gate = given ?? gate else { return }
        switch state {
        case .ready:
            gate.settle(.ready)
        case .failed(let error):
            if !gate.settle(.failed("\(error)")) {
                log.say("listener on 127.0.0.1:\(boundPort ?? settings.listenPort) stopped: \(error)")
                listenerFailedAfterReady("\(error)", gate: gate)
            }
        case .waiting(let error):
            if !gate.settle(.failed("\(error)")) {
                log.say("listener on 127.0.0.1:\(boundPort ?? settings.listenPort) is waiting: \(error); it is kept")
            }
        case .cancelled:
            gate.settle(.failed("cancelled"))
            gate.markCancelled()
        default:
            break
        }
    }

     
     
     
    func listenerFailedAfterReady(_ reason: String, gate: ModuleListenerGate? = nil) {
        dispatchPrecondition(condition: .onQueue(queue))
        let failed = gate ?? self.gate
        guard let failed, failed.noteFailedAfterReady() else { return }
         
        failed.cancelListener()
        onListenerFailure?(reason)
    }

     
     
    func relisten() throws -> UInt16 {
        dispatchPrecondition(condition: .notOnQueue(queue))
        let (old, oldGate) = withState { () -> (NWListener?, ModuleListenerGate?) in
            defer { lockedListener = nil; lockedGate = nil }
            return (lockedListener, lockedGate)
        }
        if let old {
            old.newConnectionHandler = nil
            old.cancel()
            oldGate?.waitCancelled(timeout: 1)
            old.stateUpdateHandler = nil
        }
        return try bind(boundPort ?? settings.listenPort)
    }

     
     
    func stop() {
        dispatchPrecondition(condition: .notOnQueue(queue))
        let (listener, gate) = withState { () -> (NWListener?, ModuleListenerGate?) in
            defer { lockedListener = nil; lockedGate = nil }
            return (lockedListener, lockedGate)
        }
        if let listener {
            listener.newConnectionHandler = nil
            listener.cancel()
            gate?.waitCancelled(timeout: 1)
            listener.stateUpdateHandler = nil
        }
         
        queue.sync {
            waitingForRules = []
            holdGeneration += 1
            rulesAsked = false
            idleWork?.cancel()
            idleWork = nil
            idleAfter = nil
            onIdle = nil
            let open = Array(sessions.values)
            sessions.removeAll()
            open.forEach { $0.close() }
             
             
            interceptor?.closeAll()
             
             
            ladder?.stopWatching()
             
             
            metrics.onChange = nil
        }
    }

     
    func update(settings: ModuleEngineSettings, certificatePage: ModuleCertificatePage?) {
        dispatchPrecondition(condition: .onQueue(queue))
        self.settings = settings
        self.certificatePage = certificatePage
    }

     

    func isCertificateEntry(_ target: ModuleConnectTarget) -> Bool {
        target.host == Self.certificateHostName || (settings.certEntryIP.map { $0 == target.host } ?? false)
    }

     
     
    func admitsBeforeTheTunnel(_ target: ModuleConnectTarget) -> Bool {
        let connection = ModuleHostList.Connection(host: Self.withoutTrailingDots(target.host), addressIsIPv6: false, port: target.port)
        return settings.mitmHosts.includes(connection) || settings.forceHTTPEngineHosts.includes(connection)
    }

     
    static func withoutTrailingDots(_ name: String) -> String {
        var name = name
        while name.hasSuffix(".") && name.count > 1 { name.removeLast() }
        return name
    }

    func decrypts(host: String) -> Bool {
        !passThroughOnly && settings.decryptsTLS && !passedThroughHosts.contains(host) && !systemPins(host)
    }

     
     
    private func systemPins(_ host: String) -> Bool {
        guard systemPinning.pins(host) else { return false }
        if saidSystemPinned.insert(host).inserted {
            log.say("\(host): the system pins this site's certificate, so it is relayed untouched")
        }
        return true
    }

    func loopSuspected(_ target: ModuleConnectTarget) -> Bool {
        (liveUpstreams[target.authority] ?? 0) >= Self.loopBreakerLimit
    }

     
    func noteRelayedHello(_ hello: Data) {
        guard let random = ModuleClientHello.random(hello) else { return }
        let now = clock()
        if ownHellos.count >= Self.ownHelloLimit {
            ownHellos = ownHellos.filter { now.timeIntervalSince($0.value) < Self.ownHelloWindow }
            if ownHellos.count >= Self.ownHelloLimit, let oldest = ownHellos.min(by: { $0.value < $1.value })?.key {
                ownHellos[oldest] = nil
            }
        }
        ownHellos[random] = now
    }

     
     
    func isOwnRelayedHello(_ hello: Data) -> Bool {
        guard let random = ModuleClientHello.random(hello), let at = ownHellos[random] else { return false }
        return clock().timeIntervalSince(at) < Self.ownHelloWindow
    }

     
     
     
     
    var alsoAcceptedEngineProxyCredentials: ModuleReinjectAuthorization?

     
     
     
     
     
    func signsIn(_ head: ModuleHTTPRequestHead) -> Bool {
        let accepted = [settings.engineProxyCredentials, alsoAcceptedEngineProxyCredentials].compactMap { $0 }
        guard !accepted.isEmpty else { return false }
        let values = head.headers.values("Proxy-Authorization")
        guard values.count == 1, let value = values.first, value.count > 6,
              value.prefix(6).lowercased() == "basic " else { return false }
        let token = value.dropFirst(6).trimmingCharacters(in: ModuleHTTPWhitespace.optional)
        guard let given = Data(base64Encoded: token) else { return false }
         
        let matches = accepted.map { Self.constantTimeEqual(given, Data("\($0.username):\($0.password)".utf8)) }
        return matches.contains(true)
    }

    static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        let x = [UInt8](a), y = [UInt8](b)
        var difference = UInt8(truncatingIfNeeded: x.count ^ y.count) | (x.count == y.count ? 0 : 1)
        for index in 0..<max(x.count, y.count) {
            difference |= (index < x.count ? x[index] : 0) ^ (index < y.count ? y[index] : 0)
        }
        return difference == 0
    }

    private var signInLog = ModuleLogLimiter()
    private var saidNoSignIn = false
    private var nameMismatchLog = ModuleLogLimiter()
    private var nameMismatches = ModuleRepeatTracker()

     
     
    func noteSignInRefused(_ what: String) {
        metrics.update { $0.proxyAuthRefusedTotal += 1 }
        guard settings.engineProxyCredentials != nil else {
            guard !saidNoSignIn else { return }
            saidNoSignIn = true
            return log.say("this configuration's engine plan names no sign-in for the engine's port: every request to it is refused (407), starting with \(what)")
        }
        guard let heldBack = signInLog.admit(clock()) else { return }
        log.say("refused \(what): it did not sign in as the engine proxy (407)\(ModuleLogLimiter.suffix(heldBack))")
    }

     
     
     
     
     
    func noteNameMismatch(_ target: ModuleConnectTarget, serverName: String?) {
        metrics.update { $0.tlsNameMismatchRelayedTotal += 1 }
        let asked = serverName.map { "TLS name \($0)" } ?? "no TLS name"
        if let heldBack = nameMismatchLog.admit(clock()) {
            log.say("CONNECT \(target.authority) asks for \(asked), which the host list does not take: relayed untouched\(ModuleLogLimiter.suffix(heldBack))")
        }
        if !target.isAddress, nameMismatches.record(target.host, at: clock()) {
            log.say("\(target.host) keeps asking its server for another name than its own (\(asked)): an app using Encrypted Client Hello, or a host sharing an address with an unlisted one; its sessions are relayed untouched")
        }
    }

    private var unlistedLog = ModuleLogLimiter()

     
     
     
     
     
     
    func noteUnlistedRelayed(_ target: ModuleConnectTarget, _ what: String) {
        metrics.update { $0.unlistedRelayedTotal += 1 }
        guard let heldBack = unlistedLog.admit(clock()) else { return }
        log.say("CONNECT \(target.authority) \(what), which the host list does not take: relayed untouched\(ModuleLogLimiter.suffix(heldBack))")
    }

    private var notHTTPLog = ModuleLogLimiter()

     
    func noteNotHTTPRelayed(_ target: ModuleConnectTarget) {
        guard let heldBack = notHTTPLog.admit(clock()) else { return }
        log.say("CONNECT \(target.authority) sent no HTTP request: relayed untouched\(ModuleLogLimiter.suffix(heldBack))")
    }

    func upstreamOpened(_ authority: String) {
        liveUpstreams[authority, default: 0] += 1
    }

    func upstreamClosed(_ authority: String) {
        let left = (liveUpstreams[authority] ?? 1) - 1
        liveUpstreams[authority] = left > 0 ? left : nil
    }

     
    func liveUpstreamCount(_ authority: String) -> Int {
        liveUpstreams[authority] ?? 0
    }

    func decryptedSessionOpened() {
        decryptedSessionCount += 1
    }

    func decryptedSessionClosed() {
        decryptedSessionCount = max(0, decryptedSessionCount - 1)
    }

    private var undecryptableLog = ModuleLogLimiter()

     
     
     
    func noteUndecryptable(_ host: String, offered: [String], http2: Bool = false) {
        guard let heldBack = undecryptableLog.admit(clock()) else { return }
        let missing = http2 ? "neither h2 nor http/1.1" : "no http/1.1"
        log.say("TLS name \(host) offers \(offered.isEmpty ? "no protocol" : offered.joined(separator: ", ")) by ALPN and \(missing): relayed untouched\(ModuleLogLimiter.suffix(heldBack))")
    }

     
     
     
     
     
     
    func offersHTTP2(serverName: String, target: ModuleConnectTarget) -> Bool {
        guard !http2Hosts.items.isEmpty else { return false }
        let rung = ladder?.rung ?? (passThroughCauses.contains(.memory) ? .engineStopped : .normal)
        guard rung < .engineStopped else { return false }
        let name: String? = target.isAddress && serverName == target.host ? nil : serverName
        return http2Hosts.includes(ModuleHostList.Connection(host: name, addressIsIPv6: target.isIPv6,
                                                             address: name == nil ? target.host : nil, port: target.port))
    }

    private static func http2Hosts(of settings: ModuleEngineSettings) -> ModuleHostList {
        guard !settings.http2Modules.isEmpty else { return ModuleHostList(items: [], standardPort: settings.mitmHosts.standardPort) }
        return ModuleHostList(items: settings.mitmHosts.items.filter { settings.http2Modules.contains($0.moduleID) },
                              standardPort: settings.mitmHosts.standardPort)
    }

     
    func reinject(_ authority: String, outbound: String? = nil,
                  _ completion: @escaping (Result<ModuleStream, ModuleUpstreamFailure>) -> Void) {
        ModuleReinject.connect(authority: authority, port: settings.reinjectPort, queue: queue,
                                authorization: settings.reinjectCredentials, outbound: outbound, completion: completion)
    }

     
     
    var capRefusalsTotal: Int { metrics.counters.capRefusalsTotal }
    private var capRefusalsSinceLog = 0
    private var lastCapLog: Date?
    var clock: () -> Date = Date.init

    private func noteCapRefusal() {
        metrics.update { $0.capRefusalsTotal += 1 }
        capRefusalsSinceLog += 1
        let now = clock()
        if let last = lastCapLog, now.timeIntervalSince(last) < 1 { return }
        lastCapLog = now
        log.say("refused \(capRefusalsSinceLog) connection\(capRefusalsSinceLog == 1 ? "" : "s") since the last line: \(sessions.count) sessions are open")
        capRefusalsSinceLog = 0
    }

    private func accept(_ connection: NWConnection) {
        onSession?()
         
         
         
         
         
        ladder?.noteActivity()
        connection.start(queue: queue)
        guard sessions.count < sessionLimit else {
            noteCapRefusal()
            let stream = ModuleConnectionStream(connection)
            stream.send(ModuleEngineAnswers.unavailable, isFinal: true) { _ in stream.cancel() }
            return
        }
        lastSession += 1
        let number = lastSession
        let session = ModuleEngineSession(number: number, client: ModuleConnectionStream(connection), engine: self) {
            [weak self] number in self?.sessions[number] = nil
        }
        sessions[number] = session
        session.start()
    }

     

     
     
    func whenRulesReady(_ resume: @escaping () -> Void) {
        guard awaitsRules else { return resume() }
        waitingForRules.append(resume)
        guard waitingForRules.count == 1 else { return }
        let generation = holdGeneration
        queue.asyncAfter(deadline: .now() + buildHoldTimeout) { [weak self] in
            guard let self, self.holdGeneration == generation, !self.waitingForRules.isEmpty else { return }
            self.log.say("the rules were not built within \(self.buildHoldTimeout) s: \(self.waitingForRules.count) waiting session\(self.waitingForRules.count == 1 ? "" : "s") go on without them")
            self.letWaitingGo()
        }
        guard !rulesAsked else { return }
        rulesAsked = true
        onRulesNeeded?()
    }

     
     
    func rulesReady() {
        awaitsRules = false
        rulesAsked = false
        letWaitingGo()
    }

    private func letWaitingGo() {
        holdGeneration += 1
        let waiting = waitingForRules
        waitingForRules = []
        waiting.forEach { $0() }
    }

     
     
    func rulesSessionStarted() {
        rulesSessions += 1
        idleWork?.cancel()
        idleWork = nil
    }

    func rulesSessionEnded() {
        rulesSessions = max(0, rulesSessions - 1)
        guard rulesSessions == 0, let idleAfter, onIdle != nil else { return }
        idleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.idleWork != nil, self.rulesSessions == 0 else { return }
            self.idleWork = nil
            self.onIdle?()
        }
        idleWork = work
        queue.asyncAfter(deadline: .now() + idleAfter, execute: work)
    }
}

 
final class ModuleEngineSession {
    private let number: Int
    private let reader: ModuleStreamReader
     
     
     
    private let engine: ModuleEngine
    private var onEnd: ((Int) -> Void)?
     
    private var usesRules = false
    private var relay: ModuleRelay?
    private var ended = false
     
    private var timer: ModuleDeadline?
     
    private var scan = ModuleHTTPHeadScan()
     
    private var reading = false
     
    private var superseded = false
    private var sawFirstByte = false
     
    private var liveAuthority: String?
     
    private var decrypting = false
     
    private var helloScan = ModuleClientHelloScan()

    init(number: Int, client: ModuleStream, engine: ModuleEngine, onEnd: @escaping (Int) -> Void) {
        self.number = number
        self.reader = ModuleStreamReader(client)
        self.engine = engine
        self.onEnd = onEnd
    }

    func start() {
        arm(engine.headTimeout, "request head")
        readHead()
    }

    func close() {
        guard !ended else { return }
        finalize()
        relay?.close()
        reader.stream.cancel()
    }

     
    private func finalize() {
        ended = true
        disarm()
        if usesRules {
            usesRules = false
            engine.rulesSessionEnded()
        }
        if let authority = liveAuthority {
            engine.upstreamClosed(authority)
            liveAuthority = nil
        }
        if decrypting {
            decrypting = false
            engine.decryptedSessionClosed()
        }
        onEnd?(number)
        onEnd = nil
    }

    fileprivate func endedElsewhere() {
        guard !ended else { return }
        finalize()
        reader.stream.cancel()
    }

     
     
     
     
    private func reachRules(_ go: @escaping () -> Void) {
        if !usesRules {
            usesRules = true
            engine.rulesSessionStarted()
        }
        guard engine.awaitsRules else { return go() }
        disarm()
        engine.whenRulesReady { [weak self] in
            guard let self, !self.ended else { return }
            go()
        }
    }

     
    private func handOver() -> ModuleHandOver {
        ModuleHandOver(self, queue: engine.queue)
    }

     

    private func arm(_ seconds: TimeInterval, _ what: String, _ fire: (() -> Void)? = nil) {
        timer?.cancel()
        timer = ModuleDeadline(after: seconds, queue: engine.queue) { [weak self] in
            guard let self, !self.ended else { return }
            self.timer = nil
            if let fire { return fire() }
            self.engine.log.say("no complete \(what) within \(seconds) s: closed")
            self.close()
        }
    }

    private func disarm() {
        timer?.cancel()
        timer = nil
    }

     
    private func fill(_ next: @escaping () -> Void) {
        reading = true
        reader.fill { [self] error in
            reading = false
            guard !ended else { return }
            if error != nil { return close() }
            if superseded {
                 
                 
                if let relay {
                    relay.resumeA(data: reader.take(reader.buffer.count), ended: reader.ended)
                }
                return
            }
            next()
        }
    }

     

    private func readHead() {
        guard !ended else { return }
        do {
            switch try ModuleHTTPParser.request(reader.buffer, scan: &scan) {
            case .head(let head, let consumed):
                reader.buffer = Data(reader.buffer.dropFirst(consumed))
                scan = ModuleHTTPHeadScan()
                handle(head)
            case .needMore:
                guard !reader.ended else { return close() }
                fill { [self] in readHead() }
            }
        } catch let error as ModuleHTTPError {
            engine.log.say("unreadable request head: \(error)")
            answer(status: error.status)
        } catch {
            close()
        }
    }

    private func handle(_ head: ModuleHTTPRequestHead) {
        disarm()
         
         
         
         
         
        guard engine.signsIn(head) else {
            engine.noteSignInRefused("\(head.method) \(head.target)")
            return answer(status: 407, headers: [.init(name: "Proxy-Authenticate",
                                                        value: "Basic realm=\"\(ModuleEngine.proxyRealm)\"")])
        }
        guard head.method == "CONNECT" else { return absoluteForm(head) }
        guard let target = ModuleConnectTarget.parse(head.target, defaultPort: nil) else { return answer(status: 400) }
        if engine.isCertificateEntry(target) {
            return established { [self] in
                arm(engine.headTimeout, "certificate request")
                readCertificateRequest()
            }
        }
        if !target.isAddress, !engine.admitsBeforeTheTunnel(target) {
            return refuse(target, "not on the host list")
        }
        if engine.loopSuspected(target) { return refuseLoop(target, method: "CONNECT") }
        established { [self] in
            guard !ended else { return }
            if reader.buffer.isEmpty {
                arm(engine.firstByteTimeout, "first bytes") { [self] in firstByteTimedOut(target) }
            } else {
                sawFirstByte = true
                arm(engine.headTimeout, "ClientHello or request")
            }
            classify(target)
        }
    }

     
    private static func target(ofAbsoluteForm text: String) -> ModuleConnectTarget? {
        guard text.lowercased().hasPrefix("http://") else { return nil }
        let authority = text.dropFirst("http://".count).prefix { $0 != "/" && $0 != "?" && $0 != "#" }
         
         
        guard !authority.isEmpty, !authority.contains("@") else { return nil }
        return ModuleConnectTarget.parse(String(authority), defaultPort: 80)
    }

    private func absoluteForm(_ head: ModuleHTTPRequestHead) {
        guard let target = Self.target(ofAbsoluteForm: head.target) else { return answer(status: 400) }
        if engine.isCertificateEntry(target) { return serveCertificate(head) }
        let connection = ModuleHostList.Connection(host: target.isAddress ? nil : target.host,
                                                    addressIsIPv6: target.isIPv6,
                                                    address: target.isAddress ? target.host : nil, port: target.port)
        guard engine.settings.forceHTTPEngineHosts.includes(connection) else {
            return refuse(target, "an absolute-form request that force-http-engine-hosts does not take", method: head.method)
        }
        if engine.loopSuspected(target) { return refuseLoop(target, method: head.method) }
         
         
        let framing: ModuleHTTPFraming
        do {
            framing = try ModuleHTTPFraming.ofRequest(head)
        } catch let error as ModuleHTTPError {
            engine.log.say("refused \(head.method) \(target.authority): \(error)")
            return answer(status: error.status)
        } catch {
            return answer(status: 400)
        }
        var forwarded = head
        forwarded.writeFraming(framing)
         
         
         
        forwarded.headers.set("Host", target.hostField)
         
         
        forwarded.headers.set("Proxy-Connection", "close")
         
         
        forwarded.headers.remove("Proxy-Authorization")
        if let authorization = engine.settings.reinjectCredentials {
            forwarded.headers.set("Proxy-Authorization", authorization.proxyAuthorization)
        }
        let request: Data
        do {
            request = try ModuleHTTPSerializer.head(forwarded) + reader.buffer
        } catch {
            engine.log.say("unserializable request head from \(target.authority): \(error)")
            return answer(status: 502)
        }
        guard !engine.passThroughOnly else { return absoluteFormDecided(target, request: request) }
        reachRules { [self] in absoluteFormDecided(target, request: request) }
    }

    private func absoluteFormDecided(_ target: ModuleConnectTarget, request: Data) {
        if !engine.passThroughOnly, let interceptor = engine.interceptor {
            let hand = handOver()
            if interceptor.intercept(reader.stream, target: target, kind: .plainHTTP(host: target.host), buffered: request,
                                     clientEnded: reader.ended, onEnd: { hand.end() }) {
                reader.buffer = Data()
                return
            }
            hand.disarm()
        }
        engine.metrics.update { $0.passThroughSessionsTotal += 1 }
        count(target.authority)
        ModuleReinject.open(port: engine.settings.reinjectPort, queue: engine.queue) { [self] result in
            guard !ended else { if case .success(let upstream) = result { upstream.cancel() }; return }
            switch result {
            case .success(let upstream): relay(to: upstream, first: request)
            case .failure(let failure): upstreamFailed(target, failure)
            }
        }
    }

     

    private func classify(_ target: ModuleConnectTarget) {
        guard !ended else { return }
        guard let first = reader.buffer.first else {
            guard !reader.ended else { return close() }
            return fill { [self] in classify(target) }
        }
        if !sawFirstByte {
            sawFirstByte = true
            arm(engine.headTimeout, "ClientHello or request")
        }
        guard first == 0x16 else { return plain(target) }
        switch ModuleClientHello.inspect(reader.buffer, scan: &helloScan) {
        case .needMore:
            guard !reader.ended else { return close() }
            fill { [self] in classify(target) }
        case .serverName(let name):
            tls(target, serverName: name)
        case .noServerName, .notTLS:
            tls(target, serverName: nil)
        }
    }

     
     
     
     
     
    private func firstByteTimedOut(_ target: ModuleConnectTarget) {
        superseded = true
        if target.isAddress {
            let connection = ModuleHostList.Connection(host: nil, addressIsIPv6: target.isIPv6,
                                                        address: target.host, port: target.port)
            if !engine.settings.mitmHosts.includes(connection), !engine.settings.forceHTTPEngineHosts.includes(connection) {
                engine.noteUnlistedRelayed(target, "sent no bytes within \(engine.firstByteTimeout) s")
                return passThrough(target)
            }
        }
        engine.log.say("no bytes from the client of \(target.authority) within \(engine.firstByteTimeout) s: relayed as it is")
        passThrough(target)
    }

    private func tls(_ target: ModuleConnectTarget, serverName: String?) {
        guard !ended else { return }
        disarm()
         
        helloScan = ModuleClientHelloScan()
         
        if engine.isOwnRelayedHello(reader.buffer) { return breakLoop(target) }
        let name: String?
        if target.isAddress {
             
            name = serverName
        } else {
             
             
             
             
             
            guard let serverName, takes(serverName, port: target.port) else {
                engine.noteNameMismatch(target, serverName: serverName)
                return passThrough(target)
            }
            name = serverName
        }
        let connection = ModuleHostList.Connection(host: name, addressIsIPv6: target.isIPv6,
                                                    address: name == nil ? target.host : nil, port: target.port)
        guard engine.settings.mitmHosts.includes(connection) || engine.settings.forceHTTPEngineHosts.includes(connection) else {
             
             
             
             
             
            engine.noteNameMismatch(target, serverName: name)
            return passThrough(target)
        }
        let host = name ?? target.host
        let decrypted = engine.settings.mitmHosts.includes(connection) && engine.decrypts(host: host)
         
         
         
         
        let http2 = decrypted && engine.offersHTTP2(serverName: host, target: target)
        if decrypted, !ModuleTLSFront.serves(hello: reader.buffer, http2: http2) {
            engine.noteUndecryptable(host, offered: ModuleClientHello.applicationProtocols(reader.buffer) ?? [], http2: http2)
        } else if decrypted {
            return reachRules { [self] in decrypt(target, host: host) }
        }
        passThrough(target)
    }

    private func decrypt(_ target: ModuleConnectTarget, host: String) {
         
         
        if engine.decrypts(host: host), let interceptor = engine.interceptor {
            decrypting = true
            engine.decryptedSessionOpened()
            let hand = handOver()
            if interceptor.intercept(reader.stream, target: target, kind: .tls(serverName: host), buffered: reader.buffer,
                                     clientEnded: reader.ended, onEnd: { hand.end() }) {
                reader.buffer = Data()
                return
            }
            hand.disarm()
            if decrypting {
                decrypting = false
                engine.decryptedSessionClosed()
            }
        }
        passThrough(target)
    }

     
    private func takes(_ name: String, port: UInt16) -> Bool {
        let connection = ModuleHostList.Connection(host: name, addressIsIPv6: false, port: port)
        return engine.settings.mitmHosts.includes(connection) || engine.settings.forceHTTPEngineHosts.includes(connection)
    }

     
     
    private func breakLoop(_ target: ModuleConnectTarget) {
        engine.metrics.update { $0.loopBreaksTotal += 1 }
        engine.log.say("refused CONNECT \(target.authority): its ClientHello is one this engine just relayed, so the route took it back into modules")
        close()
    }

     
    private static func withoutTrailingDot(_ name: String) -> String { ModuleEngine.withoutTrailingDots(name) }

    private func plain(_ target: ModuleConnectTarget) {
        guard !ended else { return }
         
         
         
         
        guard ModuleHTTPParser.mayBeRequest(reader.buffer) else { return notHTTP(target) }
        guard target.isAddress else {
            return plainDecided(target, host: Self.withoutTrailingDot(target.host), address: nil, addressIsIPv6: false, dial: target)
        }
         
         
        do {
            switch try ModuleHTTPParser.request(reader.buffer, scan: &scan) {
            case .head(let inner, _):
                scan = ModuleHTTPHeadScan()
                let named = inner.headers.first("Host").flatMap { ModuleConnectTarget.parse($0, defaultPort: target.port) }
                if let named, named.isAddress {
                     
                    plainDecided(target, host: nil, address: target.host, addressIsIPv6: target.isIPv6, dial: target)
                } else if let named {
                     
                     
                     
                     
                    let host = Self.withoutTrailingDot(named.host)
                    plainDecided(target, host: host, address: nil, addressIsIPv6: false,
                                 dial: ModuleConnectTarget(host: host, port: target.port, isAddress: false, isIPv6: false))
                } else {
                    plainDecided(target, host: nil, address: target.host, addressIsIPv6: target.isIPv6, dial: target)
                }
            case .needMore:
                guard !reader.ended else { return close() }
                fill { [self] in plain(target) }
            }
        } catch {
            scan = ModuleHTTPHeadScan()
            plainDecided(target, host: nil, address: target.host, addressIsIPv6: target.isIPv6, dial: target)
        }
    }

     
    private func notHTTP(_ target: ModuleConnectTarget) {
        scan = ModuleHTTPHeadScan()
        engine.noteNotHTTPRelayed(target)
        passThrough(target)
    }

     
    private func plainDecided(_ target: ModuleConnectTarget, host: String?, address: String?, addressIsIPv6: Bool,
                              dial: ModuleConnectTarget) {
        disarm()
        let connection = ModuleHostList.Connection(host: host, addressIsIPv6: addressIsIPv6, address: address, port: target.port)
        let forced = engine.settings.forceHTTPEngineHosts.includes(connection)
        guard forced || engine.settings.mitmHosts.includes(connection) else {
             
             
             
            engine.noteUnlistedRelayed(target, "asks for \((host ?? address).map { "Host \($0)" } ?? "no Host")")
            return passThrough(target)
        }
        guard forced, !engine.passThroughOnly else { return passThrough(dial) }
        reachRules { [self] in plainIntercepted(target, host: host, address: address, dial: dial) }
    }

    private func plainIntercepted(_ target: ModuleConnectTarget, host: String?, address: String?, dial: ModuleConnectTarget) {
        if !engine.passThroughOnly, let interceptor = engine.interceptor {
            let hand = handOver()
            if interceptor.intercept(reader.stream, target: dial, kind: .plainHTTP(host: host ?? address ?? target.host),
                                     buffered: reader.buffer, clientEnded: reader.ended, onEnd: { hand.end() }) {
                reader.buffer = Data()
                return
            }
            hand.disarm()
        }
        passThrough(dial)
    }

     
    private func count(_ authority: String) {
        guard liveAuthority == nil else { return }
        liveAuthority = authority
        engine.upstreamOpened(authority)
    }

    private func passThrough(_ target: ModuleConnectTarget) {
        guard !ended else { return }
        disarm()
        engine.metrics.update { $0.passThroughSessionsTotal += 1 }
        count(target.authority)
        engine.noteRelayedHello(reader.buffer)
        engine.reinject(target.authority) { [self] result in
            guard !ended else { if case .success(let upstream) = result { upstream.cancel() }; return }
            switch result {
            case .success(let upstream): relay(to: upstream, first: reader.buffer)
            case .failure(let failure): upstreamFailed(target, failure)
            }
        }
    }

    private func relay(to upstream: ModuleStream, first: Data) {
        guard !ended else { return upstream.cancel() }
         
         
        let clientEnded = reader.ended
         
         
         
        let pending = reading
        reader.buffer = Data()
        let relay = ModuleRelay(reader.stream, upstream) { [weak self] in self?.endedElsewhere() }
        self.relay = relay
        relay.start(sendingToB: first, aEnded: clientEnded, aPending: pending)
    }

    private func upstreamFailed(_ target: ModuleConnectTarget, _ failure: ModuleUpstreamFailure) {
        guard !ended else { return }
        engine.metrics.update { $0.upstreamFailuresTotal += 1 }
        engine.log.say("upstream \(target.authority) failed: \(failure)")
        close()
    }

     

    private func readCertificateRequest() {
        guard !ended else { return }
        do {
            switch try ModuleHTTPParser.request(reader.buffer, scan: &scan) {
            case .head(let head, _):
                scan = ModuleHTTPHeadScan()
                serveCertificate(head)
            case .needMore:
                 
                if let first = reader.buffer.first, !(0x41...0x5A).contains(first) { return close() }
                guard !reader.ended else { return close() }
                fill { [self] in readCertificateRequest() }
            }
        } catch {
            answer(status: 400)
        }
    }

    private func serveCertificate(_ head: ModuleHTTPRequestHead) {
        disarm()
        guard let page = engine.certificatePage else { return answer(status: 503) }
        armFinalSend()
        let (bytes, handedOut) = page.answer(head)
        engine.metrics.update {
            $0.certificatePageServedTotal += 1
            if handedOut { $0.certificateHandedOutTotal += 1 }
        }
        engine.log.say("certificate page \(head.method) \(head.target)\(handedOut ? " handed out CA \(page.fingerprint)" : "")")
        if handedOut { engine.onCertificateHandedOut?(page.fingerprint) }
        reader.stream.send(bytes, isFinal: true) { [self] _ in close() }
    }

     

    private func established(_ next: @escaping () -> Void) {
        reader.stream.send(ModuleEngine.established) { [self] error in error == nil ? next() : close() }
    }

    private func refuse(_ target: ModuleConnectTarget, _ why: String, method: String = "CONNECT") {
        engine.metrics.update { $0.refusedConnectsTotal += 1 }
        engine.log.say("refused \(method) \(target.authority): \(why)")
        answer(status: 403)
    }

     
    private func refuseLoop(_ target: ModuleConnectTarget, method: String) {
        engine.metrics.update { $0.loopBreaksTotal += 1 }
        engine.log.say("refused \(method) \(target.authority): \(ModuleEngine.loopBreakerLimit) sessions to it are already open, which looks like a route back into modules")
        answer(status: 508)
    }

     
     
    private func answer(status: Int, headers extra: [ModuleHTTPField] = []) {
        let reasons = [400: "Bad Request", 403: "Forbidden", 407: "Proxy Authentication Required", 414: "URI Too Long",
                       431: "Request Header Fields Too Large", 501: "Not Implemented", 502: "Bad Gateway",
                       503: "Service Unavailable", 505: "HTTP Version Not Supported", 508: "Loop Detected"]
        let head = ModuleHTTPResponseHead(
            version: .http11, status: status, reason: reasons[status] ?? "Error",
            headers: ModuleHTTPHeaders(extra + [.init(name: "Content-Length", value: "0"), .init(name: "Connection", value: "close")]))
        let bytes = (try? ModuleHTTPSerializer.head(head)) ?? ModuleEngineAnswers.serverError
        armFinalSend()
        reader.stream.send(bytes, isFinal: true) { [self] _ in close() }
    }

     
    private func armFinalSend() {
        arm(engine.finalSendTimeout, "final answer") { [self] in
            engine.log.say("the client did not take its answer within \(engine.finalSendTimeout) s: closed")
            close()
        }
    }
}

 
 
 
 
final class ModuleHandOver {
    private weak var session: ModuleEngineSession?
    private let queue: DispatchQueue
    private var armed = true

    init(_ session: ModuleEngineSession, queue: DispatchQueue) {
        self.session = session
        self.queue = queue
    }

     
    func end() {
        guard armed else { return }
        armed = false
        session?.endedElsewhere()
    }

    func disarm() { armed = false }

    deinit {
        guard armed, let session else { return }
        queue.async { session.endedElsewhere() }
    }
}

 
 
struct ModuleRepeatTracker {
    var threshold = 3
    var window: TimeInterval = 600
    var limit = 256
    private var events: [String: [Date]] = [:]
    private var said: Set<String> = []

    init() {}

    mutating func record(_ name: String, at now: Date) -> Bool {
        var recent = (events[name] ?? []).filter { now.timeIntervalSince($0) < window }
        recent.append(now)
        events[name] = Array(recent.suffix(threshold))
        if events.count > limit {
            events = events.filter { $0.value.last.map { now.timeIntervalSince($0) < window } ?? false }
            if events.count > limit {
                events = Dictionary(uniqueKeysWithValues: events.sorted { ($0.value.last ?? .distantPast) > ($1.value.last ?? .distantPast) }
                    .prefix(limit * 3 / 4).map { ($0.key, $0.value) })
            }
        }
        guard recent.count >= threshold, !said.contains(name) else { return false }
        if said.count >= limit { said.removeAll() }
        said.insert(name)
        return true
    }
}

 
 
final class ModuleListenerGate: @unchecked Sendable {
    enum Outcome {
        case ready
        case failed(String)
    }

    private let lock = NSLock()
    private var outcome: Outcome?
    private var failedLater = false
     
    private weak var listener: NWListener?

    init(_ listener: NWListener) {
        self.listener = listener
    }

    func cancelListener() {
        lock.lock()
        let held = listener
        lock.unlock()
        held?.cancel()
    }
    private let settled = DispatchSemaphore(value: 0)
    private let cancelled = DispatchSemaphore(value: 0)

     
    var failedAfterReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return failedLater
    }

     
    func noteFailedAfterReady() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !failedLater else { return false }
        failedLater = true
        return true
    }

    @discardableResult
    func settle(_ outcome: Outcome) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard self.outcome == nil else { return false }
        self.outcome = outcome
        settled.signal()
        return true
    }

    func wait(timeout: TimeInterval) -> Outcome? {
        guard settled.wait(timeout: .now() + timeout) == .success else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return outcome
    }

    func markCancelled() { cancelled.signal() }

    func waitCancelled(timeout: TimeInterval) {
        _ = cancelled.wait(timeout: .now() + timeout)
    }
}
#endif
