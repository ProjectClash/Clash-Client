#if os(iOS) || os(macOS)
import Foundation
import Network

 
 
 
 
 

protocol ModuleStream: AnyObject {
     
     
    func receive(maximumLength: Int, _ completion: @escaping (_ data: Data?, _ isComplete: Bool, _ error: Error?) -> Void)
     
    func send(_ data: Data, isFinal: Bool, _ completion: @escaping (_ error: Error?) -> Void)
     
    func cancel()
}

extension ModuleStream {
    func send(_ data: Data, _ completion: @escaping (_ error: Error?) -> Void) {
        send(data, isFinal: false, completion)
    }

    func finish() {
        send(Data(), isFinal: true) { _ in }
    }
}

 
 
 
 
 
 
final class ModuleDeadline {
    private var timer: DispatchSourceTimer?

    init(after seconds: TimeInterval, queue: DispatchQueue, _ fire: @escaping () -> Void) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        self.timer = timer
        timer.setEventHandler { [weak self] in
             
             
            self?.cancel()
            fire()
        }
        timer.schedule(deadline: .now() + seconds, repeating: .never)
        timer.resume()
    }

    var isArmed: Bool { timer != nil }

    func cancel() {
        guard let timer else { return }
        self.timer = nil
        timer.setEventHandler(handler: nil)
        timer.cancel()
    }

    deinit {
        cancel()
    }
}

 
final class ModuleConnectionStream: ModuleStream {
    let connection: NWConnection
    private var cancelled = false

    init(_ connection: NWConnection) {
        self.connection = connection
    }

    func receive(maximumLength: Int, _ completion: @escaping (Data?, Bool, Error?) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: maximumLength) { data, _, isComplete, error in
            completion(data, isComplete, error)
        }
    }

    func send(_ data: Data, isFinal: Bool, _ completion: @escaping (Error?) -> Void) {
        if isFinal {
            connection.send(content: data.isEmpty ? nil : data, contentContext: .finalMessage, isComplete: true,
                            completion: .contentProcessed { completion($0) })
        } else {
            connection.send(content: data, completion: .contentProcessed { completion($0) })
        }
    }

    func cancel() {
        guard !cancelled else { return }
        cancelled = true
        connection.stateUpdateHandler = nil
        connection.cancel()
    }
}

 
final class ModulePrefixedStream: ModuleStream {
    private let base: ModuleStream
    private var prefix: Data

    init(_ base: ModuleStream, prefix: Data) {
        self.base = base
        self.prefix = Data(prefix)
    }

    func receive(maximumLength: Int, _ completion: @escaping (Data?, Bool, Error?) -> Void) {
        guard prefix.isEmpty else {
            let chunk = Data(prefix.prefix(maximumLength))
            prefix.removeFirst(chunk.count)
            return completion(chunk, false, nil)
        }
        base.receive(maximumLength: maximumLength, completion)
    }

    func send(_ data: Data, isFinal: Bool, _ completion: @escaping (Error?) -> Void) {
        base.send(data, isFinal: isFinal, completion)
    }

    func cancel() { base.cancel() }
}

 
 
final class ModuleMemoryPipe {
    final class End: ModuleStream {
        fileprivate weak var peer: End?
        private let queue: DispatchQueue
        private var inbound = Data()
        private var peerFinished = false
        private var cancelled = false
        private var waiting: (maximum: Int, completion: (Data?, Bool, Error?) -> Void)?
        private(set) var finished = false
         
        private(set) var sent = Data()

        fileprivate init(queue: DispatchQueue) {
            self.queue = queue
        }

        func receive(maximumLength: Int, _ completion: @escaping (Data?, Bool, Error?) -> Void) {
            waiting = (maximumLength, completion)
            deliver()
        }

        func send(_ data: Data, isFinal: Bool, _ completion: @escaping (Error?) -> Void) {
            guard !cancelled, !finished, let peer else {
                return queue.async { completion(POSIXError(.EPIPE)) }
            }
            sent += data
            peer.inbound += data
            if isFinal {
                finished = true
                peer.peerFinished = true
            }
            peer.deliver()
            queue.async { completion(nil) }
        }

        func cancel() {
            guard !cancelled else { return }
            cancelled = true
            deliver()
            peer?.peerCancelled()
        }

        private func peerCancelled() {
            cancelled = true
            deliver()
        }

        private func deliver() {
            guard let (maximum, completion) = waiting else { return }
            if !inbound.isEmpty {
                waiting = nil
                let chunk = Data(inbound.prefix(maximum))
                inbound.removeFirst(chunk.count)
                return queue.async { completion(chunk, false, nil) }
            }
            if cancelled {
                waiting = nil
                return queue.async { completion(nil, true, POSIXError(.ECONNRESET)) }
            }
            if peerFinished {
                waiting = nil
                queue.async { completion(nil, true, nil) }
            }
        }
    }

    let a: End
    let b: End

    init(queue: DispatchQueue) {
        a = End(queue: queue)
        b = End(queue: queue)
        a.peer = b
        b.peer = a
    }
}

 
final class ModuleRelay {
    private let a: ModuleStream
    private let b: ModuleStream
    private let chunk: Int
    private var onEnd: (() -> Void)?
    private var aFinished = false
    private var bFinished = false
    private var closed = false
     
     
    private var aWaitsForResume = false
    private var aResume: (data: Data, ended: Bool)?

    init(_ a: ModuleStream, _ b: ModuleStream, chunk: Int = 16 * 1024, onEnd: @escaping () -> Void) {
        self.a = a
        self.b = b
        self.chunk = chunk
        self.onEnd = onEnd
    }

     
     
     
     
     
     
     
     
     
    func start(sendingToB first: Data = Data(), toA firstBack: Data = Data(), aEnded: Bool = false, aPending: Bool = false) {
        send(first, to: b) { [self] in
            if aEnded {
                finish(true)
            } else if aPending {
                if let held = aResume {
                    aResume = nil
                    forwardA(data: held.data, ended: held.ended)
                } else {
                    aWaitsForResume = true
                }
            } else {
                pump(from: a, to: b, aToB: true)
            }
        }
        send(firstBack, to: a) { [self] in pump(from: b, to: a, aToB: false) }
    }

     
    func resumeA(data: Data, ended: Bool) {
        guard !closed else { return }
        guard aWaitsForResume else {
             
            aResume = (data, ended)
            return
        }
        aWaitsForResume = false
        forwardA(data: data, ended: ended)
    }

    private func forwardA(data: Data, ended: Bool) {
        send(data, to: b) { [self] in
            if ended { finish(true) } else { pump(from: a, to: b, aToB: true) }
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        a.cancel()
        b.cancel()
        onEnd?()
        onEnd = nil
    }

    private func pump(from source: ModuleStream, to sink: ModuleStream, aToB: Bool) {
        source.receive(maximumLength: chunk) { [self] data, isComplete, error in
            guard !closed else { return }
            if error != nil { return close() }
            let next = { [self] in
                if isComplete {
                    finish(aToB)
                } else {
                    pump(from: source, to: sink, aToB: aToB)
                }
            }
            if let data, !data.isEmpty {
                send(data, to: sink, then: next)
            } else {
                next()
            }
        }
    }

    private func send(_ data: Data, to sink: ModuleStream, then next: @escaping () -> Void) {
        guard !data.isEmpty else { return next() }
        sink.send(data) { [self] error in
            guard !closed else { return }
            if error != nil { return close() }
            next()
        }
    }

    private func finish(_ aToB: Bool) {
        if aToB {
            aFinished = true
            b.finish()
        } else {
            bFinished = true
            a.finish()
        }
        if aFinished && bFinished { close() }
    }
}

 
 
 
 
enum ModuleWire {
    static func join(_ parts: Data...) -> Data {
        var out = Data(capacity: parts.reduce(0) { $0 + $1.count })
        for part in parts { out.append(part) }
        return out
    }
}

 
final class ModuleStreamReader {
     
     
     
    static let growthStep = 16 * 1024

    let stream: ModuleStream
     
    var buffer: Data { didSet { room = buffer.count } }
    private(set) var ended = false
     
    private var room: Int
     
    private(set) var growths = 0

     
     
    init(_ stream: ModuleStream, buffered: Data = Data(), ended: Bool = false) {
        self.stream = stream
        self.buffer = Data(buffered)
        self.room = buffered.count
        self.ended = ended
    }

     
    func fill(maximumLength: Int = 16 * 1024, _ completion: @escaping (Error?) -> Void) {
        guard !ended else { return completion(nil) }
        stream.receive(maximumLength: maximumLength) { [weak self] data, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty { self.append(data) }
            if isComplete { self.ended = true }
            completion(error)
        }
    }

     
     
     
     
     
     
     
     
     
    private func append(_ data: Data) {
        let needed = buffer.count + data.count
        if needed <= room {
            let kept = room
            buffer.append(data)
            room = kept
            return
        }
        let step = Self.growthStep
        let grown = needed <= step ? max(needed, min(step, 2 * room)) : (needed + step - 1) / step * step
        growths += 1
        var into = Data(capacity: grown)
        into.append(buffer)
        into.append(data)
        buffer = into
        room = grown
    }

     
     
     
    func take(_ count: Int) -> Data {
        let out = Data(buffer.prefix(count))
        buffer = buffer.count > out.count ? Data(buffer.dropFirst(out.count)) : Data()
        return out
    }
}

enum ModuleUpstreamFailure: Error, Equatable, Sendable {
    case unreachable(String)
    case refused(status: Int)
    case untrusted(String)
    case timedOut
}

 
 
extension ModuleReinjectAuthorization {
     
     
    var proxyAuthorization: String {
        "Basic " + Data("\(username):\(password)".utf8).base64EncodedString()
    }
}

 
final class ModuleSharedLogLimiter: @unchecked Sendable {
    private let lock = NSLock()
    private var limiter = ModuleLogLimiter()

    func admit(_ now: Date) -> Int? {
        lock.lock(); defer { lock.unlock() }
        return limiter.admit(now)
    }
}

 
enum ModuleReinject {
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func open(port: UInt16, queue: DispatchQueue, timeout: TimeInterval = 15, log: ModuleEngineLog = .silent,
                     limiter: ModuleSharedLogLimiter = collisions,
                     decide: @escaping (Seen, Int) -> Step = step,
                     completion: @escaping (Result<ModuleStream, ModuleUpstreamFailure>) -> Void) {
        guard port != 0, let endpointPort = NWEndpoint.Port(rawValue: port) else {
            return completion(.failure(.unreachable("no re-inject port")))
        }
         
         
         
        var pending: ((Result<ModuleStream, ModuleUpstreamFailure>) -> Void)? = completion
        var deadline: ModuleDeadline?
        var current: ModuleConnectionStream?
        func settle(_ result: Result<ModuleStream, ModuleUpstreamFailure>) {
            guard let done = pending else { return }
            pending = nil
            deadline?.cancel()
            deadline = nil
            current?.connection.stateUpdateHandler = nil
            if case .failure = result { current?.cancel() }
            current = nil
            done(result)
        }
        func start(attempt: Int) {
            guard pending != nil else { return }
            let connection = NWConnection(host: .ipv4(.loopback), port: endpointPort, using: .tcp)
            let stream = ModuleConnectionStream(connection)
            current = stream
            connection.stateUpdateHandler = { state in
                switch decide(seen(state), attempt) {
                case .connected: settle(.success(stream))
                case .tryAgain(let why):
                    connection.stateUpdateHandler = nil
                    stream.cancel()
                    current = nil
                    if let held = limiter.admit(Date()) {
                        log.say("re-inject 127.0.0.1:\(port): the local port of a connection was taken (\(why)); "
                                + "trying once more\(ModuleLogLimiter.suffix(held))")
                    }
                    queue.asyncAfter(deadline: .now() + .milliseconds(Int.random(in: 10...60))) { start(attempt: 2) }
                case .fail(let why): settle(.failure(.unreachable(why)))
                case .keepWaiting: break
                }
            }
            connection.start(queue: queue)
        }
        deadline = ModuleDeadline(after: timeout, queue: queue) { settle(.failure(.timedOut)) }
        start(attempt: 1)
    }

     
     
    static let collisions = ModuleSharedLogLimiter()

     
     
     
     
     
     
     
     
    enum Seen: Equatable {
        case ready
         
         
        case unusable(String, addressInUse: Bool)
        case cancelled
        case other
    }

    static func seen(_ state: NWConnection.State) -> Seen {
        switch state {
        case .ready: return .ready
        case .waiting(let error), .failed(let error):
            if case .posix(.EADDRINUSE) = error { return .unusable("\(error)", addressInUse: true) }
            return .unusable("\(error)", addressInUse: false)
        case .cancelled: return .cancelled
        default: return .other
        }
    }

     
    enum Step: Equatable {
        case connected
         
         
        case tryAgain(String)
        case fail(String)
        case keepWaiting
    }

     
     
     
     
    static func step(_ seen: Seen, attempt: Int) -> Step {
        switch seen {
        case .ready: return .connected
        case .unusable(let said, let addressInUse):
            return attempt == 1 && addressInUse ? .tryAgain(said) : .fail(said)
        case .cancelled: return .fail("cancelled")
        case .other: return .keepWaiting
        }
    }

     
     
     
     
     
    static func connect(authority: String, port: UInt16, queue: DispatchQueue, timeout: TimeInterval = 15,
                        authorization: ModuleReinjectAuthorization? = nil, outbound: String? = nil,
                        log: ModuleEngineLog = .silent,
                        completion: @escaping (Result<ModuleStream, ModuleUpstreamFailure>) -> Void) {
        open(port: port, queue: queue, timeout: timeout, log: log) { opened in
            guard case .success(let stream) = opened else { return completion(opened) }
            var pending: ((Result<ModuleStream, ModuleUpstreamFailure>) -> Void)? = completion
            var deadline: ModuleDeadline?
            let settle: (Result<ModuleStream, ModuleUpstreamFailure>) -> Void = { result in
                guard let done = pending else { return }
                pending = nil
                deadline?.cancel()
                deadline = nil
                if case .failure = result { stream.cancel() }
                done(result)
            }
            let signIn = authorization.map { "Proxy-Authorization: \($0.proxyAuthorization)\r\n" } ?? ""
            let named = outbound.map { "\(ModuleScriptOutbound.header): \(ModuleScriptOutbound.encoded($0))\r\n" } ?? ""
            stream.send(Data("CONNECT \(authority) HTTP/1.1\r\nHost: \(authority)\r\n\(signIn)\(named)\r\n".utf8)) { error in
                if let error { settle(.failure(.unreachable("\(error)"))) }
            }
            readAnswer(stream, Data(), settle)
            deadline = ModuleDeadline(after: timeout, queue: queue) { settle(.failure(.timedOut)) }
        }
    }

    private static func readAnswer(_ stream: ModuleStream, _ buffer: Data,
                                   _ done: @escaping (Result<ModuleStream, ModuleUpstreamFailure>) -> Void) {
        stream.receive(maximumLength: 16 * 1024) { data, isComplete, error in
            var buffer = buffer
            if let data { buffer += data }
            if let error { return done(.failure(.unreachable("\(error)"))) }
            do {
                switch try ModuleHTTPParser.response(buffer) {
                case .needMore:
                    if isComplete { return done(.failure(.unreachable("closed before answering the CONNECT"))) }
                    readAnswer(stream, buffer, done)
                case .head(let head, let consumed):
                    guard head.status == 200 else { return done(.failure(.refused(status: head.status))) }
                    done(.success(ModulePrefixedStream(stream, prefix: buffer.dropFirst(consumed))))
                }
            } catch {
                done(.failure(.unreachable("the CONNECT answer could not be read: \(error)")))
            }
        }
    }
}
#endif
