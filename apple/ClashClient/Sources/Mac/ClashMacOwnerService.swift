#if os(macOS)
import Darwin
import Foundation
import os

 
 
 
 
 
 
 
 
 
 
 
 
 
 
final class ClashMacOwnerService: @unchecked Sendable {
    static let socketName = "owner.sock"
     
     
    static var stagingName: String { "o.\(String(getpid(), radix: 16))" }

    private let path: String
     
     
    private let stagingPath: String
    private let owners: ClashMacSocketOwners
     
    private let checkEvery: DispatchTimeInterval
     
     
    private let state = NSLock()
    private var listening: DispatchSourceRead?
    private var boundInode: ino_t = 0
    private var missed = 0
    private var watchdog: DispatchSourceTimer?
    private let accepting = DispatchQueue(label: "clash.owner-service", qos: .userInitiated)
    private let counter = NSLock()
    private var asked = 0
    private var answered = 0
    private var took: [UInt64] = []
    private static let log = Logger(subsystem: "org.example.clash", category: "process-owner")

    init?(container: URL, owners: ClashMacSocketOwners = .shared, checkEvery: DispatchTimeInterval = .seconds(5)) {
        let path = container.appendingPathComponent(Self.socketName).path
        let stagingPath = container.appendingPathComponent(Self.stagingName).path
         
        guard path.utf8.count < 104, stagingPath.utf8.count < 104 else { return nil }
        self.path = path
        self.stagingPath = stagingPath
        self.owners = owners
        self.checkEvery = checkEvery
    }

    deinit { stop() }

     
     
     
     
    func start() {
        state.lock()
        defer { state.unlock() }
        if listening == nil, let bound = bindListener(reportingFailure: true) {
            listen(on: bound.fd, inode: bound.inode)
        }
        guard watchdog == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + checkEvery, repeating: checkEvery)
        timer.setEventHandler { [weak self] in self?.reclaimIfLost() }
        timer.resume()
        watchdog = timer
    }

     
     
     
    func stop() {
        state.lock()
        defer { state.unlock() }
        watchdog?.cancel()
        watchdog = nil
        listening?.cancel()
        listening = nil
    }

     
     
     
     
     
     
     
     
     
     
     
    func reclaimIfLost() {
        state.lock()
        defer { state.unlock() }
        guard watchdog != nil else { return }
        guard listening != nil else {
             
            if !Self.answers(path), let bound = bindListener(reportingFailure: false) {
                listen(on: bound.fd, inode: bound.inode)
            }
            return
        }
        guard Self.inode(of: path) != boundInode, !Self.answers(path) else {
            missed = 0
            return
        }
        missed += 1
        guard missed >= 2, let bound = bindListener(reportingFailure: true) else { return }
        listening?.cancel()
        listen(on: bound.fd, inode: bound.inode)
        Self.log.info("owner.sock taken back path=\(self.path, privacy: .public)")
    }

     
     
     
     
    private func bindListener(reportingFailure: Bool) -> (fd: Int32, inode: ino_t)? {
        unlink(stagingPath)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var address = Self.address(stagingPath)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        let inode = bound == 0 ? Self.inode(of: stagingPath) : 0
        guard bound == 0, inode != 0,
              fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) == 0,
              Darwin.listen(fd, 8) == 0,
              rename(stagingPath, path) == 0
        else {
            if reportingFailure {
                Self.log.error("owner.sock listen failed errno=\(errno, privacy: .public) path=\(self.path, privacy: .public)")
            }
            if bound == 0 { unlink(stagingPath) }
            close(fd)
            return nil
        }
        return (fd, inode)
    }

     
     
     
     
    private func listen(on fd: Int32, inode: ino_t) {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: accepting)
        source.setEventHandler { [weak self] in self?.acceptWaiting(fd) }
        source.setCancelHandler { close(fd) }
        source.resume()
        listening = source
        boundInode = inode
        missed = 0
        Self.log.info("owner.sock listening path=\(self.path, privacy: .public)")
    }

     
    private static func inode(of path: String) -> ino_t {
        var info = stat()
        return stat(path, &info) == 0 ? info.st_ino : 0
    }

     
    private static func answers(_ path: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var target = Self.address(path)
        return withUnsafePointer(to: &target) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }
        }
    }

     
    private func acceptWaiting(_ fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                 
                 
                if errno == EMFILE || errno == ENFILE { usleep(100_000) }
                return
            }
             
            _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
            var on: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            let thread = Thread { [weak self] in self?.serve(client) }
            thread.name = "clash.owner-service.client"
            thread.qualityOfService = .userInitiated
            thread.start()
        }
    }

    private func serve(_ client: Int32) {
        defer { close(client) }
        var pending = [UInt8]()
        var chunk = [UInt8](repeating: 0, count: 1024)
        while true {
            let count = read(client, &chunk, chunk.count)
            guard count > 0 else { return }
            pending.append(contentsOf: chunk[0..<count])
            while let newline = pending.firstIndex(of: 0x0A) {
                let line = String(decoding: pending[..<newline], as: UTF8.self)
                pending.removeSubrange(...newline)
                let started = DispatchTime.now().uptimeNanoseconds
                 
                 
                let text = autoreleasepool { answer(line) }
                note(question: line, reply: text, took: DispatchTime.now().uptimeNanoseconds &- started)
                let reply = Array((text + "\n").utf8)
                guard reply.withUnsafeBytes({ write(client, $0.baseAddress, reply.count) }) == reply.count else { return }
            }
            if pending.count > 4096 { return }
        }
    }

     
     
     
     
    private func note(question: String, reply: String, took nanoseconds: UInt64) {
        counter.lock()
        asked += 1
        if reply.hasPrefix("O ") { answered += 1 }
        took.append(nanoseconds)
        let (n, hits) = (asked, answered)
        var window: [UInt64] = []
        if took.count == 200 { window = took.sorted(); took.removeAll(keepingCapacity: true) }
        counter.unlock()
        if !window.isEmpty {
            func ms(_ q: Double) -> String {
                String(format: "%.2f", Double(window[min(window.count - 1, Int(Double(window.count) * q))]) / 1e6)
            }
            Self.log.info("owner.sock took n=\(n, privacy: .public) answered=\(hits, privacy: .public) p50=\(ms(0.5), privacy: .public)ms p90=\(ms(0.9), privacy: .public)ms p99=\(ms(0.99), privacy: .public)ms max=\(ms(1), privacy: .public)ms")
        }
        guard n <= 20 || n % 500 == 0 else { return }
        Self.log.info("owner.sock n=\(n, privacy: .public) answered=\(hits, privacy: .public) q=\(question, privacy: .public) a=\(reply, privacy: .public)")
    }

     
    func answer(_ line: String) -> String {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 6, parts[0] == "Q",
              let proto = UInt8(parts[1]), proto == 6 || proto == 17,
              let sourcePort = UInt16(parts[3]),
              let destinationPort = UInt16(parts[5])
        else { return "N" }
        guard let owner = owners.owner(
            proto: proto, source: parts[2], sourcePort: sourcePort,
            destination: parts[4], destinationPort: destinationPort
        ), !owner.path.isEmpty else { return "N" }
        return "O \(owner.uid)\t\(Self.userName(owner.uid))\t\(owner.path)"
    }

    private static func userName(_ uid: Int32) -> String {
        var record = passwd()
        var result: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: 1024)
        guard getpwuid_r(uid_t(bitPattern: uid), &record, &buffer, buffer.count, &result) == 0,
              let name = result?.pointee.pw_name
        else { return "" }
        return String(cString: name)
    }

    static func address(_ path: String) -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            let bytes = Array(path.utf8.prefix(raw.count - 1))
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return address
    }
}
#endif
