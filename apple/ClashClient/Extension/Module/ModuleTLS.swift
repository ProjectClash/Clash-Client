#if os(iOS) || os(macOS)
import Foundation
import Network
import Security

 
 
 
 
 
 
 
 

enum ModuleTLSFailure: Error, Equatable, Sendable {
     
     
    case listener(String)
     
     
     
     
    case clientRejected(String, status: Int32? = nil)
     
     
    case clientWentAway(String)
     
     
    case handshakeFailed(String)
    case timedOut

     
    static func from(_ error: NWError) -> ModuleTLSFailure {
        switch error {
        case .tls(let status):
            if alertStatuses.contains(Int(status)) { return .clientRejected("\(error)", status: status) }
            if closedStatuses.contains(Int(status)) { return .clientWentAway("\(error)") }
            return .handshakeFailed("\(error)")
        case .posix:
            return .clientWentAway("\(error)")
        default:
            return .handshakeFailed("\(error)")
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
    private static let alertStatuses: Set<Int> = Set([-9802, -9808]).union(-9840 ... -9819).union(-9865 ... -9855)
     
     
     
    private static let closedStatuses: Set<Int> = [-9805, -9806, -9816, -9852]
}

 
 
 
 
enum ModuleLoopbackHop {
    enum Verdict: Equatable, Sendable {
        case ours
        case stranger
         
        case undecided
    }

    static func judge(peer: NWEndpoint?, hopLocal: NWEndpoint?) -> Verdict {
        guard let peer = socket(peer) else { return .stranger }
        guard let ours = socket(hopLocal) else { return .undecided }
        return peer == ours ? .ours : .stranger
    }

     
    private static func socket(_ endpoint: NWEndpoint?) -> [UInt8]? {
        guard case .hostPort(let host, let port)? = endpoint else { return nil }
        let address: Data
        switch host {
        case .ipv4(let v4): address = v4.rawValue
        case .ipv6(let v6): address = v6.rawValue
        default: return nil
        }
        return [UInt8(address.count)] + address + [UInt8(port.rawValue >> 8), UInt8(port.rawValue & 0xFF)]
    }

     
    enum Undecided {
         
         
        case wait
         
         
         
         
        case provisional
    }

     
    enum Admission: Equatable, Sendable {
        case ours
         
        case stranger
         
         
         
        case gaveUp
    }

     
     
    static func admit(_ connection: NWConnection, hop: @escaping () -> NWConnection?, queue: DispatchQueue,
                      undecided: Undecided = .wait, attempts: Int = 10, attempt: Int = 0,
                      _ decided: @escaping (Admission) -> Void) {
        guard let ours = hop() else {
            connection.cancel()
            return decided(.stranger)
        }
        switch judge(peer: connection.endpoint, hopLocal: ours.currentPath?.localEndpoint) {
        case .ours:
            decided(.ours)
        case .stranger:
            connection.cancel()
            decided(.stranger)
        case .undecided where undecided == .provisional:
            decided(.ours)
        case .undecided:
            guard attempt < attempts else {
                connection.cancel()
                return decided(.gaveUp)
            }
            queue.asyncAfter(deadline: .now() + 0.02) {
                admit(connection, hop: hop, queue: queue, undecided: undecided, attempts: attempts, attempt: attempt + 1, decided)
            }
        }
    }
}

 
final class ModuleTLSFront {
     
     
     
     
     
    static let silentCloseWindow: TimeInterval = 3

    let plaintext: ModuleStream
     
     
    let negotiatedProtocol: String?
     
     
     
     
    var onClosedWithoutAsking: (() -> Void)? {
        get { watch.handler }
        set { watch.handler = newValue }
    }

     
     
     
     
    var onAsked: (() -> Void)? {
        get { watch.askedHandler }
        set { watch.askedHandler = newValue }
    }

    private let watch: ModuleFirstReadWatch
    private let splice: ModuleRelay
    private let spliceEnd: SpliceEnd

     
    fileprivate final class SpliceEnd {
        var ended = false
        var handler: (() -> Void)?

        func fire() {
            ended = true
            let told = handler
            handler = nil
            told?()
        }
    }

    private init(connection: NWConnection, splice: ModuleRelay, spliceEnd: SpliceEnd, window: TimeInterval) {
        let watch = ModuleFirstReadWatch(ModuleConnectionStream(connection), window: window)
        self.watch = watch
        plaintext = watch
        negotiatedProtocol = ModuleTLSFront.negotiated(connection)
        self.splice = splice
        self.spliceEnd = spliceEnd
    }

    func close() {
        plaintext.cancel()
        splice.close()
    }

     
     
     
     
     
     
     
    func closeAfterDraining(within grace: TimeInterval, queue: DispatchQueue, done: @escaping () -> Void) {
        dispatchPrecondition(condition: .onQueue(queue))
        plaintext.cancel()
        var deadline: ModuleDeadline?
        var finished = false
        let finish = { [splice] in
            guard !finished else { return }
            finished = true
            deadline?.cancel()
            deadline = nil
            splice.close()
            done()
        }
        guard !spliceEnd.ended else { return finish() }
        spliceEnd.handler = finish
        deadline = ModuleDeadline(after: grace, queue: queue) { finish() }
    }

     
     
     
    static let http11Protocols = [#"http/1.1"#]
    static let http2Protocols = [#"h2"#, #"http/1.1"#]

     
     
     
     
     
    static func serves(hello: Data, http2: Bool = false) -> Bool {
        guard let offered = ModuleClientHello.applicationProtocols(hello) else { return true }
        let ours = http2 ? http2Protocols : http11Protocols
        return offered.contains { ours.contains($0) }
    }

     
    static func negotiated(_ connection: NWConnection) -> String? {
        guard let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata,
              let raw = sec_protocol_metadata_get_negotiated_protocol(metadata.securityProtocolMetadata) else { return nil }
        let name = String(cString: raw)
        return name.isEmpty ? nil : name
    }

     
     
     
     
     
     
     
     
     
    static func open(client: ModuleStream, buffered: Data, clientEnded: Bool = false, identity: SecIdentity,
                     queue: DispatchQueue, timeout: TimeInterval = 10,
                     applicationProtocols: [String] = ModuleTLSFront.http11Protocols,
                     silentCloseWindow: TimeInterval = ModuleTLSFront.silentCloseWindow,
                     beforeJoining: ((_ port: UInt16, _ join: @escaping () -> Void) -> Void)? = nil,
                     completion: @escaping (Result<ModuleTLSFront, ModuleTLSFailure>) -> Void) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard let secIdentity = sec_identity_create(identity) else {
            client.cancel()
            return completion(.failure(.listener("the identity could not be used")))
        }
        let options = NWProtocolTLS.Options()
        sec_protocol_options_set_local_identity(options.securityProtocolOptions, secIdentity)
        for name in applicationProtocols { sec_protocol_options_add_tls_application_protocol(options.securityProtocolOptions, name) }
        sec_protocol_options_set_min_tls_protocol_version(options.securityProtocolOptions, .TLSv12)
        let parameters = NWParameters(tls: options)
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            client.cancel()
            return completion(.failure(.listener("\(error)")))
        }
        var finish: ((Result<ModuleTLSFront, ModuleTLSFailure>) -> Void)? = completion
        var splice: ModuleRelay?
        let spliceEnd = ModuleTLSFront.SpliceEnd()
        var hop: NWConnection?
        var accepted: NWConnection?
         
        var deadline: ModuleDeadline?
        var grace: ModuleDeadline?
        var settled: Bool { finish == nil }
        let settle: (Result<ModuleTLSFront, ModuleTLSFailure>) -> Void = { result in
            guard let done = finish else { return }
             
             
            finish = nil
            deadline?.cancel()
            grace?.cancel()
            deadline = nil
            grace = nil
            listener.newConnectionHandler = nil
            listener.stateUpdateHandler = nil
            listener.cancel()
            accepted?.stateUpdateHandler = nil
            if case .failure = result {
                accepted?.cancel()
                splice?.close()
                hop?.cancel()
                client.cancel()
            }
             
            splice = nil
            hop = nil
            accepted = nil
            done(result)
        }
        listener.newConnectionHandler = { connection in
            guard accepted == nil else { return connection.cancel() }
             
             
            ModuleLoopbackHop.admit(connection, hop: { hop }, queue: queue) { admission in
                switch admission {
                case .ours: break
                case .stranger: return
                case .gaveUp:
                     
                     
                    return settle(.failure(.listener("the client's end of the loopback hop was not known in time")))
                }
                guard !settled, accepted == nil else { return connection.cancel() }
                accepted = connection
                listener.cancel()
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        connection.stateUpdateHandler = nil
                         
                        guard let ours = hop,
                              ModuleLoopbackHop.judge(peer: connection.endpoint, hopLocal: ours.currentPath?.localEndpoint) == .ours else {
                            return settle(.failure(.listener("a connection other than the client's reached the loopback hop")))
                        }
                        guard let relay = splice else { return settle(.failure(.listener("the hop was never joined"))) }
                        settle(.success(ModuleTLSFront(connection: connection, splice: relay, spliceEnd: spliceEnd,
                                                        window: silentCloseWindow)))
                    case .failed(let error), .waiting(let error):
                        settle(.failure(.from(error)))
                    case .cancelled:
                        settle(.failure(.clientWentAway("the handshake was cut off")))
                    default:
                        break
                    }
                }
                connection.start(queue: queue)
            }
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                guard let port = listener.port else { return settle(.failure(.listener("ready without a port"))) }
                let join = {
                    guard !settled, hop == nil else { return }
                    let connection = NWConnection(host: .ipv4(.loopback), port: port, using: .tcp)
                    hop = connection
                    connection.start(queue: queue)
                    let relay = ModuleRelay(client, ModuleConnectionStream(connection)) {
                         
                        guard !settled else { return spliceEnd.fire() }
                         
                         
                         
                        guard accepted != nil else {
                            return settle(.failure(.clientWentAway("the client went away before its handshake began")))
                        }
                        grace = ModuleDeadline(after: 1, queue: queue) {
                            settle(.failure(.clientWentAway("the client went away during the handshake")))
                        }
                    }
                    splice = relay
                    relay.start(sendingToB: buffered, aEnded: clientEnded)
                }
                if let beforeJoining { beforeJoining(port.rawValue, join) } else { join() }
            case .failed(let error), .waiting(let error):
                settle(.failure(.listener("\(error)")))
            default:
                break
            }
        }
        listener.start(queue: queue)
        deadline = ModuleDeadline(after: timeout, queue: queue) { settle(.failure(.timedOut)) }
    }
}

 
 
 
 
private final class ModuleFirstReadWatch: ModuleStream {
    var handler: (() -> Void)?
    var askedHandler: (() -> Void)?
    private let base: ModuleStream
    private let deadline: DispatchTime
    private var decided = false

    init(_ base: ModuleStream, window: TimeInterval) {
        self.base = base
        deadline = .now() + window
    }

    func receive(maximumLength: Int, _ completion: @escaping (Data?, Bool, Error?) -> Void) {
        guard !decided else { return base.receive(maximumLength: maximumLength, completion) }
        base.receive(maximumLength: maximumLength) { [weak self] data, isComplete, error in
            if let self, !self.decided {
                if let data, !data.isEmpty {
                    self.decided = true
                    self.handler = nil
                    let asked = self.askedHandler
                    self.askedHandler = nil
                    asked?()
                } else if isComplete || error != nil {
                    self.decided = true
                    let handler = self.handler
                    self.handler = nil
                    self.askedHandler = nil
                    if DispatchTime.now() <= self.deadline { handler?() }
                }
            }
            completion(data, isComplete, error)
        }
    }

    func send(_ data: Data, isFinal: Bool, _ completion: @escaping (Error?) -> Void) {
        base.send(data, isFinal: isFinal, completion)
    }

    func cancel() {
         
        decided = true
        handler = nil
        askedHandler = nil
        base.cancel()
    }
}

 
 
enum ModuleServerTrust {
     
     
     
     
    case system
#if false || MODULES_ENGINE_TESTS

     
     
     
     
     
    case anchors([SecCertificate])
#endif



     
    func evaluate(_ trust: SecTrust, host: String, queue: DispatchQueue, completion: @escaping (Bool, String) -> Void) {
        dispatchPrecondition(condition: .onQueue(queue))
         
         
         
         
         
         
        var policies: [SecPolicy] = [SecPolicyCreateSSL(true, host as CFString)]
        var existing: CFArray?
        if SecTrustCopyPolicies(trust, &existing) == errSecSuccess, let existing = existing as? [SecPolicy] {
            policies += existing.filter { policy in
                let oid = (SecPolicyCopyProperties(policy) as? [CFString: Any])?[kSecPolicyOid] as? String
                return oid != (kSecPolicyAppleSSL as String)
            }
        }
        var status = SecTrustSetPolicies(trust, policies as CFArray)
        guard status == errSecSuccess else {
            return completion(false, "the check for \(host) could not be set up (\(status))")
        }
#if false || MODULES_ENGINE_TESTS

        if case .anchors(let anchors) = self {
            status = SecTrustSetAnchorCertificates(trust, anchors as CFArray)
            if status == errSecSuccess { status = SecTrustSetAnchorCertificatesOnly(trust, true) }
            if status == errSecSuccess { status = SecTrustSetNetworkFetchAllowed(trust, false) }
            guard status == errSecSuccess else { return completion(false, "the test anchors could not be set (\(status))") }
        }
#endif


        status = SecTrustEvaluateAsyncWithError(trust, queue) { _, trusted, error in
            let why = error.map { CFErrorCopyDescription($0) as String } ?? (trusted ? "" : "not trusted")
            completion(trusted && error == nil, why)
        }
        if status != errSecSuccess { completion(false, "the check could not start (\(status))") }
    }
}

 
 
 
 
private final class ModuleUpstreamStream: ModuleStream {
    private let base: ModuleStream
    private let splice: ModuleRelay?
    private let queue: DispatchQueue
    private var onEnd: (() -> Void)?

    init(_ base: ModuleStream, splice: ModuleRelay?, queue: DispatchQueue, onEnd: (() -> Void)?) {
        self.base = base
        self.splice = splice
        self.queue = queue
        self.onEnd = onEnd
    }

    deinit {
        let base = self.base, splice = self.splice, onEnd = self.onEnd
        queue.async {
            base.cancel()
            splice?.close()
            onEnd?()
        }
    }

    func receive(maximumLength: Int, _ completion: @escaping (Data?, Bool, Error?) -> Void) {
        base.receive(maximumLength: maximumLength, completion)
    }

    func send(_ data: Data, isFinal: Bool, _ completion: @escaping (Error?) -> Void) {
        base.send(data, isFinal: isFinal, completion)
    }

    func cancel() {
        base.cancel()
        splice?.close()
        let end = onEnd
        onEnd = nil
        end?()
    }
}

 
 
final class ModuleUpstreamConnector {
     
    typealias Reinject = (_ authority: String, _ outbound: String?,
                          _ completion: @escaping (Result<ModuleStream, ModuleUpstreamFailure>) -> Void) -> Void

     
     
    struct LoopCount {
        let opened: (String) -> Void
        let closed: (String) -> Void
    }

    static let handshakeTimeout: TimeInterval = 15

    private let queue: DispatchQueue
    private let reinject: Reinject
    private let trust: ModuleServerTrust
    private let loopCount: LoopCount?
    private let ownCAFingerprint: String?
     
     
    var beforeJoining: ((_ port: UInt16, _ join: @escaping () -> Void) -> Void)?
     
     
     
    var redirectingTheTLSClient: ((_ port: UInt16) -> UInt16)?
     
     
     
     
    var onOwnAuthority: ((_ serverName: String) -> Void)?

     
     
     
     
    init(queue: DispatchQueue, reinject: @escaping Reinject, trust: ModuleServerTrust = .system, loopCount: LoopCount? = nil,
         ownCAFingerprint: String? = nil) {
        self.queue = queue
        self.reinject = reinject
        self.trust = trust
        self.loopCount = loopCount
        self.ownCAFingerprint = ownCAFingerprint?.lowercased()
    }

     
     
     
     
     
     
    convenience init(engine: ModuleEngine, ownCAFingerprint: String, trust: ModuleServerTrust = .system) {
        self.init(queue: engine.queue, reinject: { [weak engine] authority, outbound, completion in
            guard let engine else { return completion(.failure(.unreachable("the engine stopped"))) }
            engine.reinject(authority, outbound: outbound, completion)
        }, trust: trust, loopCount: LoopCount(opened: { [weak engine] in engine?.upstreamOpened($0) },
                                             closed: { [weak engine] in engine?.upstreamClosed($0) }),
        ownCAFingerprint: ownCAFingerprint)
    }

     
     
     
     
     
    func open(authority: String, serverName: String, tls: Bool,
              completion: @escaping (Result<ModuleStream, ModuleUpstreamFailure>) -> Void) {
        open(authority: authority, serverName: serverName, tls: tls, insecure: false, outbound: nil, completion: completion)
    }

     
     
     
     
     
     
    func open(authority: String, serverName: String, tls: Bool, insecure: Bool, outbound: String?,
              completion: @escaping (Result<ModuleStream, ModuleUpstreamFailure>) -> Void) {
        open(authority: authority, serverName: serverName, tls: tls, insecure: insecure, offering: [#"http/1.1"#],
             outbound: outbound) {
            completion($0.map(\.stream))
        }
    }

     
     
    func open(authority: String, serverName: String, offering protocols: [String],
              completion: @escaping (Result<(stream: ModuleStream, negotiated: String?), ModuleUpstreamFailure>) -> Void) {
        open(authority: authority, serverName: serverName, insecure: false, offering: protocols, completion: completion)
    }

     
     
    func open(authority: String, serverName: String, insecure: Bool, offering protocols: [String],
              completion: @escaping (Result<(stream: ModuleStream, negotiated: String?), ModuleUpstreamFailure>) -> Void) {
        open(authority: authority, serverName: serverName, tls: true, insecure: insecure, offering: protocols, completion: completion)
    }

     
     
    private func open(authority: String, serverName: String, tls: Bool, insecure: Bool, offering protocols: [String],
                      outbound: String? = nil,
                      completion: @escaping (Result<(stream: ModuleStream, negotiated: String?), ModuleUpstreamFailure>) -> Void) {
        dispatchPrecondition(condition: .onQueue(queue))
        let queue = self.queue
        let ended: (() -> Void)? = loopCount.map { count in { count.closed(authority) } }
         
         
        var pending: ((Result<(stream: ModuleStream, negotiated: String?), ModuleUpstreamFailure>) -> Void)? = completion
        let deliver: (Result<(stream: ModuleStream, negotiated: String?), ModuleUpstreamFailure>) -> Void = { result in
            let done = pending
            pending = nil
            done?(result)
        }
        loopCount?.opened(authority)
        reinject(authority, outbound) { [self] result in
            switch result {
            case .failure(let failure):
                ended?()
                deliver(.failure(failure))
            case .success(let toKernel) where !tls:
                deliver(.success((ModuleUpstreamStream(toKernel, splice: nil, queue: queue, onEnd: ended), nil)))
            case .success(let toKernel):
                handshake(over: toKernel, serverName: serverName, insecure: insecure, protocols: protocols) { result in
                    switch result {
                    case .success(let (connection, splice)):
                        deliver(.success((ModuleUpstreamStream(ModuleConnectionStream(connection), splice: splice,
                                                                queue: queue, onEnd: ended), ModuleTLSFront.negotiated(connection))))
                    case .failure(let failure):
                        ended?()
                        deliver(.failure(failure))
                    }
                }
            }
        }
    }

     
     
    static func chain(of trust: SecTrust, contains fingerprint: String) -> Bool {
        let chain = (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []
        return chain.contains { ModuleCertificateFingerprint.sha256(SecCertificateCopyData($0) as Data) == fingerprint }
    }

     
     
     
     
     
    private static func clientOptions(serverName: String, protocols: [String], trust: ModuleServerTrust, insecure: Bool,
                                      ownCAFingerprint: String?,
                                      queue: DispatchQueue, ownAuthority: ((String) -> Void)?,
                                      refused: @escaping (String) -> Void) -> NWProtocolTLS.Options {
        let options = NWProtocolTLS.Options()
        let security = options.securityProtocolOptions
        var v4 = in_addr()
        var v6 = in6_addr()
        if inet_pton(AF_INET, serverName, &v4) != 1, inet_pton(AF_INET6, serverName, &v6) != 1 {
            sec_protocol_options_set_tls_server_name(security, serverName)
        }
        for name in protocols { sec_protocol_options_add_tls_application_protocol(security, name) }
        sec_protocol_options_set_min_tls_protocol_version(security, .TLSv12)
        sec_protocol_options_set_tls_ocsp_enabled(security, true)
        sec_protocol_options_set_tls_sct_enabled(security, true)
        sec_protocol_options_set_verify_block(security, { _, presented, complete in
            let secTrust = sec_trust_copy_ref(presented).takeRetainedValue()
            trust.evaluate(secTrust, host: serverName, queue: queue) { trusted, why in
                if trusted || insecure, let ownCAFingerprint, chain(of: secTrust, contains: ownCAFingerprint) {
                    refused("the server presented a certificate of this engine's own authority: a route back into modules")
                    ownAuthority?(serverName)
                    return complete(false)
                }
                if !trusted, !insecure { refused(why.isEmpty ? "not trusted" : why) }
                complete(trusted || insecure)
            }
        }, queue)
        return options
    }

    private func handshake(over toKernel: ModuleStream, serverName: String, insecure: Bool, protocols: [String],
                           completion: @escaping (Result<(NWConnection, ModuleRelay), ModuleUpstreamFailure>) -> Void) {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        guard let listener = try? NWListener(using: parameters) else {
            toKernel.cancel()
            return completion(.failure(.unreachable("no loopback listener for the upstream hop")))
        }
        let queue = self.queue
        let trust = self.trust
        let ownCAFingerprint = self.ownCAFingerprint
        let beforeJoining = self.beforeJoining
        let redirect = self.redirectingTheTLSClient
        let ownAuthority = self.onOwnAuthority
        var finish: ((Result<(NWConnection, ModuleRelay), ModuleUpstreamFailure>) -> Void)? = completion
        var splice: ModuleRelay?
        var client: NWConnection?
        var accepted: NWConnection?
        var verdict: String?
        var deadline: ModuleDeadline?
        var settled: Bool { finish == nil }
        let settle: (Result<(NWConnection, ModuleRelay), ModuleUpstreamFailure>) -> Void = { result in
            guard let done = finish else { return }
             
             
             
            finish = nil
            deadline?.cancel()
            deadline = nil
            listener.newConnectionHandler = nil
            listener.stateUpdateHandler = nil
            listener.cancel()
            client?.stateUpdateHandler = nil
            if case .failure = result {
                client?.cancel()
                accepted?.cancel()
                splice?.close()
                toKernel.cancel()
            }
            splice = nil
            client = nil
            accepted = nil
            done(result)
        }
        let failure: (String) -> ModuleUpstreamFailure = { why in verdict.map { .untrusted($0) } ?? .unreachable(why) }
        listener.newConnectionHandler = { connection in
            guard accepted == nil else { return connection.cancel() }
             
             
             
             
             
             
             
             
             
            ModuleLoopbackHop.admit(connection, hop: { client }, queue: queue, undecided: .provisional) { admission in
                guard admission == .ours else { return }
                guard !settled, accepted == nil else { return connection.cancel() }
                accepted = connection
                listener.cancel()
                connection.start(queue: queue)
                let relay = ModuleRelay(ModuleConnectionStream(connection), toKernel) {
                    settle(.failure(failure("the connection closed during the handshake")))
                }
                splice = relay
                relay.start()
            }
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                guard let port = listener.port else { return settle(.failure(.unreachable("ready without a port"))) }
                let join = {
                    guard !settled, client == nil else { return }
                    let options = Self.clientOptions(serverName: serverName, protocols: protocols, trust: trust, insecure: insecure,
                                                     ownCAFingerprint: ownCAFingerprint,
                                                     queue: queue, ownAuthority: ownAuthority) { why in verdict = why }
                    let destination = redirect.flatMap { NWEndpoint.Port(rawValue: $0(port.rawValue)) } ?? port
                    let connection = NWConnection(host: .ipv4(.loopback), port: destination, using: NWParameters(tls: options))
                    client = connection
                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            guard verdict == nil else { return settle(.failure(failure("the server was not trusted"))) }
                            guard let relay = splice, let hop = accepted else {
                                return settle(.failure(failure("the TLS client was ready with no hop spliced to the CONNECT")))
                            }
                             
                             
                            switch ModuleLoopbackHop.judge(peer: hop.endpoint, hopLocal: connection.currentPath?.localEndpoint) {
                            case .ours:
                                settle(.success((connection, relay)))
                            case .stranger:
                                settle(.failure(failure("the hop was not the TLS client's own")))
                            case .undecided:
                                settle(.failure(failure("the TLS client's own end was still not known when it was ready")))
                            }
                        case .failed(let error), .waiting(let error):
                            settle(.failure(failure("\(error)")))
                        case .cancelled:
                            settle(.failure(failure("cancelled")))
                        default:
                            break
                        }
                    }
                    connection.start(queue: queue)
                }
                if let beforeJoining { beforeJoining(port.rawValue, join) } else { join() }
            case .failed(let error), .waiting(let error):
                settle(.failure(.unreachable("\(error)")))
            default:
                break
            }
        }
        listener.start(queue: queue)
        deadline = ModuleDeadline(after: Self.handshakeTimeout, queue: queue) {
            settle(.failure(verdict.map { .untrusted($0) } ?? .timedOut))
        }
    }
}

 
enum ModulePinningSignal: Equatable, Sendable {
     
    case refusedLeaf(String)
     
     
    case closedWithoutAsking
     
     
     
    case encryptedClientHello(String)

     
    static let echRequiredStatus: Int32 = -9802

     
     
     
     
     
     
     
    static func of(_ failure: ModuleTLSFailure, hello: Data) -> ModulePinningSignal? {
        guard case .clientRejected(let why, let status) = failure else { return nil }
        guard status == echRequiredStatus, ModuleClientHello.offersEncryptedClientHello(hello) else { return .refusedLeaf(why) }
        return .encryptedClientHello(why)
    }

    var detail: String {
        switch self {
        case .refusedLeaf(let why):
            return "the app broke off the handshake with the module certificate (\(why))"
        case .closedWithoutAsking:
            return "the app closed the connection right after the handshake without asking anything"
        case .encryptedClientHello(let why):
            return "the app offered Encrypted Client Hello, which modules cannot answer, and broke off the handshake (\(why))"
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
final class ModulePinningMonitor {
    static let threshold = 3
    static let window: TimeInterval = 600
     
     
    static let silentCloseBurst: TimeInterval = 1
     
     
    static let maximumTrackedHosts = 256

    private let now: () -> Date
    private var events: [String: [Date]] = [:]
     
    private var askedAt: [String: Date] = [:]
     
    private var silentCloseAt: [String: Date] = [:]
     
    private var exemptionSaid: [String: (at: Date, quiet: Int)] = [:]
    private(set) var hosts: [ModuleEngineReport.PinnedHost]

    init(now: @escaping () -> Date = Date.init, carrying: [ModuleEngineReport.PinnedHost] = []) {
        self.now = now
        hosts = Array(carrying.prefix(ModuleEngineReport.pinnedHostLimit))
    }

     
    var trackedHostCount: Int { max(events.count, askedAt.count, silentCloseAt.count, exemptionSaid.count) }

     
     
     
    func asked(_ host: String) {
        let at = now()
        askedAt[host] = at
        if askedAt.count > Self.maximumTrackedHosts { askedAt = Self.bounded(askedAt, at: at, within: Self.window) { $0 } }
    }

     
    private func discounting(_ host: String, at: Date) -> String? {
        if let asked = askedAt[host], at.timeIntervalSince(asked) < Self.window {
            return #"and another of its sessions asked something within \#(Int(Self.window / 60)) minutes (the app takes the module certificate)"#
        }
        if let last = silentCloseAt[host], at.timeIntervalSince(last) < Self.silentCloseBurst {
            return #"within \#(Int(Self.silentCloseBurst)) second of the one counted before it"#
        }
        silentCloseAt[host] = at
        if silentCloseAt.count > Self.maximumTrackedHosts {
            silentCloseAt = Self.bounded(silentCloseAt, at: at, within: Self.silentCloseBurst) { $0 }
        }
        return nil
    }

     
     
    private func sayExempted(_ host: String, _ line: String, at: Date, log: ModuleEngineLog) {
        if let said = exemptionSaid[host], at.timeIntervalSince(said.at) < Self.window {
            exemptionSaid[host] = (said.at, said.quiet + 1)
            return
        }
        let quiet = exemptionSaid[host]?.quiet ?? 0
        exemptionSaid[host] = (at, 0)
        if exemptionSaid.count > Self.maximumTrackedHosts {
            exemptionSaid = Self.bounded(exemptionSaid, at: at, within: Self.window) { $0.at }
        }
        log.say(quiet == 0 ? line : #"\#(line); \#(quiet) more since the last such line were not logged"#)
    }

     
    private static func bounded<Entry>(_ table: [String: Entry], at: Date, within: TimeInterval,
                                       time: (Entry) -> Date) -> [String: Entry] {
        let recent = table.filter { at.timeIntervalSince(time($0.value)) < within }
        guard recent.count > maximumTrackedHosts else { return recent }
        return Dictionary(uniqueKeysWithValues: recent.sorted { time($0.value) > time($1.value) }.prefix(maximumTrackedHosts * 3 / 4)
            .map { ($0.key, $0.value) })
    }

     
    func record(_ host: String) -> Bool {
        let at = now()
        var recent = (events[host] ?? []).filter { at.timeIntervalSince($0) < Self.window }
        recent.append(at)
        events[host] = Array(recent.suffix(Self.threshold))
        if events.count > Self.maximumTrackedHosts { prune(at) }
        let passed = recent.count >= Self.threshold
        var entry = hosts.first { $0.host == host }
            ?? ModuleEngineReport.PinnedHost(host: host, count: 0, lastAt: at, passedThrough: false)
        entry.count += 1
        entry.lastAt = at
        entry.passedThrough = entry.passedThrough || passed
        hosts.removeAll { $0.host == host }
        hosts.insert(entry, at: 0)
        hosts = Array(hosts.prefix(ModuleEngineReport.pinnedHostLimit))
        return passed
    }

     
     
     
    @discardableResult
    func suspect(_ host: String, _ signal: ModulePinningSignal, metrics: ModuleEngineMetrics, log: ModuleEngineLog) -> Bool {
        let wasPassed = hosts.first { $0.host == host }?.passedThrough ?? false
        let at = now()
        if signal == .closedWithoutAsking, let why = discounting(host, at: at) {
            sayExempted(host, #"not counted as pinning \#(host): \#(signal.detail), \#(why)"#, at: at, log: log)
            return wasPassed
        }
        metrics.update { $0.pinningSuspectedTotal += 1 }
        log.say("pinning suspected \(host): \(signal.detail)")
        let passed = record(host)
        if passed, !wasPassed {
            log.say("\(host) looked like an app that pins its certificate \(Self.threshold) times in \(Int(Self.window / 60)) minutes; it is relayed untouched for the rest of this run")
        }
        return passed || wasPassed
    }

     
     
    private func prune(_ at: Date) {
        events = events.filter { $0.value.last.map { at.timeIntervalSince($0) < Self.window } ?? false }
        guard events.count > Self.maximumTrackedHosts else { return }
        let kept = events.sorted { ($0.value.last ?? .distantPast) > ($1.value.last ?? .distantPast) }
            .prefix(Self.maximumTrackedHosts * 3 / 4)
        events = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
    }
}

 
enum ModuleLeafChoice {
     
    case present(SecIdentity, ModuleIdentityLease)
     
     
     
    case relayUntouched(String)
     
     
     
     
    case degrade(String)

    static func choose(host: String, leaves: ModuleLeafStore) -> ModuleLeafChoice {
        let lease: ModuleIdentityLease
        do {
            lease = try leaves.lease(hostname: host)
        } catch {
            switch ModuleCertificateError.scope(of: error) {
            case .thisHost: return .relayUntouched("\(error)")
            case .structural: return .degrade("\(error)")
            case .passing:
                guard leaves.passingFailuresDegrade else { return .relayUntouched("\(error); the next session tries again") }
                return .degrade("\(error), for \(ModuleLeafStore.passingFailureLimit) hosts within \(Int(ModuleLeafStore.passingFailureWindow / 60)) minutes")
            }
        }
         
        guard let identity = lease.identity else {
            lease.end()
            return .relayUntouched("the certificate was let go before the session began")
        }
        return .present(identity, lease)
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ModuleSystemPinning: @unchecked Sendable {
     
     
    let rules: [String: [NSRegularExpression]]

    static let none = ModuleSystemPinning(rules: [:])

     
    static let system: ModuleSystemPinning = systemRulesURL.flatMap { try? Data(contentsOf: $0) }.map(parse) ?? .none

     
     
     
     
    static var systemRulesURL: URL? {
        Bundle(path: "/System/Library/Security/Certificates.bundle")?.url(forResource: "CertificatePinning", withExtension: "plist")
    }

     
     
     
     
    static func parse(_ data: Data) -> ModuleSystemPinning {
        guard let items = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [Any] else { return .none }
        var rules: [String: [NSRegularExpression]] = [:]
        for case let item as [String: Any] in items {
            for case let domain as [String: Any] in item["domains"] as? [Any] ?? [] {
                guard let suffix = (domain["suffix"] as? String)?.lowercased(), !suffix.isEmpty,
                      let pattern = domain["labelRegex"] as? String,
                      let label = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
                rules[suffix, default: []].append(label)
            }
        }
        return ModuleSystemPinning(rules: rules)
    }

    var ruleCount: Int { rules.values.reduce(0) { $0 + $1.count } }

     
     
     
    func pins(_ host: String) -> Bool {
        var name = host.lowercased()
        while name.hasSuffix("."), name.count > 1 { name.removeLast() }
        guard let dot = name.firstIndex(of: ".") else { return false }
        let label = String(name[..<dot])
        guard !label.isEmpty, let patterns = rules[String(name[name.index(after: dot)...])] else { return false }
        let range = NSRange(label.startIndex..., in: label)
        return patterns.contains { $0.firstMatch(in: label, range: range) != nil }
    }
}
#endif
