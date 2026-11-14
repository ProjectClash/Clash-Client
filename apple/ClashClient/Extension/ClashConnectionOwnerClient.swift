#if os(macOS)
import Darwin
import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
final class ClashConnectionOwnerClient: @unchecked Sendable {
    struct Owner: Equatable, Sendable {
        let userID: Int32
        let userName: String
        let processPath: String
    }

     
     
    private final class Connection {
        let fd: Int32
        var buffer = [UInt8]()
        init(fd: Int32) { self.fd = fd }
    }

    private let path: String
    private let deadline: UInt64  
    private let retryAfter: UInt64 = 1_000_000_000
     
     
     
    private let leastExchange: UInt64
    private let waitingLimit: Int
     
    private let permits: DispatchSemaphore
    private let lock = NSLock()
    private var idle: [Connection] = []
    private var waiting = 0
    private var failedAt: UInt64 = 0

     
     
     
     
     
     
     
     
     
     
     
    init?(container: URL, deadlineMilliseconds: Int32 = 150, connectionLimit: Int = 4, waitingLimit: Int = 32) {
        let path = container.appendingPathComponent("owner.sock").path
        guard path.utf8.count < 104, connectionLimit > 0, waitingLimit >= 0 else { return nil }
        self.path = path
        self.deadline = UInt64(max(0, deadlineMilliseconds)) * 1_000_000
        self.leastExchange = min(15_000_000, deadline / 4)
        self.waitingLimit = waitingLimit
        self.permits = DispatchSemaphore(value: connectionLimit)
    }

    deinit {
        for connection in idle { close(connection.fd) }
    }

    func owner(
        ipProtocol: Int32, sourceAddress: String, sourcePort: Int32,
        destinationAddress: String, destinationPort: Int32
    ) -> Owner? {
        guard ipProtocol == 6 || ipProtocol == 17 else { return nil }
        let until = DispatchTime.now().uptimeNanoseconds &+ deadline
        let question = "Q \(ipProtocol) \(sourceAddress) \(sourcePort) \(destinationAddress) \(destinationPort)\n"
        lock.lock()
        guard waiting < waitingLimit else {
            lock.unlock()
            return nil
        }
        waiting += 1
        lock.unlock()
        let permitted = permits.wait(timeout: DispatchTime(uptimeNanoseconds: until)) == .success
        lock.lock()
        waiting -= 1
        lock.unlock()
        guard permitted else { return nil }
        defer { permits.signal() }
        while true {
             
             
            guard until > DispatchTime.now().uptimeNanoseconds &+ leastExchange,
                  let checkedOut = checkOut()
            else { return nil }
            let (connection, reused) = checkedOut
            switch exchange(question, on: connection, until: until) {
            case .answered(let line):
                lock.lock()
                idle.append(connection)
                lock.unlock()
                return Self.parse(line)
            case .timedOut:
                 
                 
                 
                 
                close(connection.fd)
                return nil
            case .broken:
                close(connection.fd)
                 
                 
                if reused { continue }
                noteRefused()
                return nil
            }
        }
    }

    private enum Exchange {
        case answered(String)
        case timedOut
        case broken
    }

    static func parse(_ line: String) -> Owner? {
        guard line.hasPrefix("O ") else { return nil }
        let fields = line.dropFirst(2).split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 3, let uid = Int32(fields[0]), !fields[2].isEmpty else { return nil }
        return Owner(userID: uid, userName: fields[1], processPath: fields[2])
    }

     
     
     
    private func checkOut() -> (Connection, reused: Bool)? {
        lock.lock()
        if let reused = idle.popLast() {
            lock.unlock()
            return (reused, true)
        }
        let now = DispatchTime.now().uptimeNanoseconds
        if failedAt != 0, now &- failedAt < retryAfter {
            lock.unlock()
            return nil
        }
        lock.unlock()
        let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else { noteRefused(); return nil }
        var on: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            let bytes = Array(path.utf8.prefix(raw.count - 1))
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            close(socketFD)
            noteRefused()
            return nil
        }
        lock.lock()
        failedAt = 0
        lock.unlock()
        return (Connection(fd: socketFD), false)
    }

    private func noteRefused() {
        lock.lock()
        failedAt = DispatchTime.now().uptimeNanoseconds
        lock.unlock()
    }

     
    private func exchange(_ question: String, on connection: Connection, until: UInt64) -> Exchange {
        let bytes = Array(question.utf8)
        var sent = 0
        while sent < bytes.count {
            switch wait(connection.fd, POLLOUT, until: until) {
            case .ready: break
            case .timedOut: return .timedOut
            case .broken: return .broken
            }
            let count = bytes.withUnsafeBytes { write(connection.fd, $0.baseAddress! + sent, bytes.count - sent) }
            guard count > 0 else { return .broken }
            sent += count
        }
        var chunk = [UInt8](repeating: 0, count: 2048)
        while true {
            if let newline = connection.buffer.firstIndex(of: 0x0A) {
                let line = String(decoding: connection.buffer[..<newline], as: UTF8.self)
                connection.buffer.removeSubrange(...newline)
                return .answered(line)
            }
            switch wait(connection.fd, POLLIN, until: until) {
            case .ready: break
            case .timedOut: return .timedOut
            case .broken: return .broken
            }
            let count = read(connection.fd, &chunk, chunk.count)
            guard count > 0 else { return .broken }
            connection.buffer.append(contentsOf: chunk[0..<count])
            if connection.buffer.count > 8192 { return .broken }
        }
    }

    private enum Readiness {
        case ready
        case timedOut
        case broken
    }

     
     
    private func wait(_ fd: Int32, _ events: Int32, until: UInt64) -> Readiness {
        let now = DispatchTime.now().uptimeNanoseconds
        guard until > now else { return .timedOut }
        let left = Int32(min(UInt64(Int32.max), (until - now + 999_999) / 1_000_000))
        var descriptor = pollfd(fd: fd, events: Int16(events), revents: 0)
        switch poll(&descriptor, 1, left) {
        case 0: return .timedOut
        case 1 where descriptor.revents & Int16(events) != 0: return .ready
        default: return .broken
        }
    }
}
#endif
