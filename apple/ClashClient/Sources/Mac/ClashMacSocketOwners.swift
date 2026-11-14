#if os(macOS)
import Darwin
import Foundation
import os

 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashSocketOwner: Equatable, Sendable {
    let pid: Int32
    let uid: Int32
    let path: String

    var name: String { (path as NSString).lastPathComponent }
}

 
struct ClashSocketRecord: Equatable, Sendable {
    let proto: UInt8  
    let local: String
    let localPort: UInt16
    let remote: String
    let remotePort: UInt16
    let pid: Int32
    let uid: Int32
}

final class ClashMacSocketOwners: @unchecked Sendable {
    static let shared = ClashMacSocketOwners()

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private let looseFor: UInt64 = 250_000_000

    private let lock = NSLock()
    private var records: [ClashSocketRecord] = []
    private var byLocal: [String: [Int]] = [:]
    private var readAt: UInt64 = 0  
    private var paths: [Int32: (uid: Int32, path: String)] = [:]
    private var misses = 0
    private var hits = 0
    private var source = "none"

     
     
     
     
     
    private static let log = Logger(subsystem: "org.example.clash", category: "process-owner")

    func owner(
        proto: UInt8,
        source: String,
        sourcePort: UInt16,
        destination: String = "",
        destinationPort: UInt16 = 0,
        askedAt: UInt64? = nil
    ) -> ClashSocketOwner? {
         
         
         
        let arrived = askedAt ?? DispatchTime.now().uptimeNanoseconds
        lock.lock()
        defer { lock.unlock() }
        let now = DispatchTime.now().uptimeNanoseconds
        var found = match(
            proto, source, sourcePort, destination, destinationPort,
            loose: now &- readAt <= looseFor
        )
        if found == nil, readAt <= arrived {
            reread(DispatchTime.now().uptimeNanoseconds)
            found = match(proto, source, sourcePort, destination, destinationPort, loose: true)
        }
        guard let record = found else {
            misses += 1
            if misses <= 20 || misses % 500 == 0 {
                let own = getpid()
                let mine = records.filter { $0.pid == own }.count
                Self.log.info("owner.miss n=\(self.misses, privacy: .public) source=\(self.source, privacy: .public) proto=\(proto, privacy: .public) src=\(source, privacy: .public):\(sourcePort, privacy: .public) dst=\(destination, privacy: .public):\(destinationPort, privacy: .public) records=\(self.records.count, privacy: .public) own=\(mine, privacy: .public)")
            }
            return nil
        }
        let named = process(of: record.pid)
        hits += 1
        if hits <= 5 || hits % 500 == 0 {
            Self.log.info("owner.hit n=\(self.hits, privacy: .public) source=\(self.source, privacy: .public) pid=\(record.pid, privacy: .public) path=\(named.path, privacy: .public)")
        }
        return ClashSocketOwner(
            pid: record.pid, uid: record.uid >= 0 ? record.uid : named.uid, path: named.path
        )
    }

     
     
     
     
     
     
     
     
     
     
     
     
    private(set) var readCount = 0

     
    func holdingLock(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        body()
    }

    private func reread(_ now: UInt64) {
        readCount += 1
         
         
         
         
         
        let (listed, from): ([ClashSocketRecord], String) = autoreleasepool {
            let listed = Self.readNettop()
            return listed.isEmpty ? (Self.read(proto: 6) + Self.read(proto: 17), "pcblist") : (listed, "nettop")
        }
        records = listed
        source = from
        byLocal = [:]
        for (index, record) in records.enumerated() {
            byLocal["\(record.proto)|\(record.localPort)", default: []].append(index)
        }
        readAt = now
        if paths.count > 4096 { paths.removeAll() }
    }

     
     
     
     
     
    private func match(
        _ proto: UInt8, _ source: String, _ sourcePort: UInt16,
        _ destination: String, _ destinationPort: UInt16, loose: Bool
    ) -> ClashSocketRecord? {
        guard let candidates = byLocal["\(proto)|\(sourcePort)"] else { return nil }
        let source = Self.unmapped(source), destination = Self.unmapped(destination)
        let rows = candidates.map { records[$0] }
        if !destination.isEmpty, let exact = rows.first(where: {
            $0.local == source && $0.remote == destination && $0.remotePort == destinationPort
        }) { return exact }
        guard loose else { return nil }
        if let local = rows.first(where: { $0.local == source }) { return local }
        if proto == 17 { return rows.first { $0.local == "0.0.0.0" || $0.local == "::" } }
        return nil
    }

     
     
     
    private func process(of pid: Int32) -> (uid: Int32, path: String) {
        if let known = paths[pid] { return known }
        var buffer = [CChar](repeating: 0, count: 4096)
        var found: (uid: Int32, path: String) = (-1, "")
        if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 {
            found.path = String(cString: buffer)
        }
        var info = proc_bsdshortinfo()
        let size = Int32(MemoryLayout<proc_bsdshortinfo>.size)
        if proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, size) == size {
            found.uid = Int32(bitPattern: info.pbsi_uid)
        }
        if found.path.isEmpty || !found.path.hasPrefix("/") || found.uid < 0,
           let line = Self.run("/bin/ps", ["-o", "uid=,comm=", "-p", String(pid)]) {
            found = Self.parsePS(line) ?? found
        }
        paths[pid] = found
        return found
    }

    static func parsePS(_ output: String) -> (uid: Int32, path: String)? {
        let line = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let space = line.firstIndex(of: " "), let uid = Int32(line[..<space]) else { return nil }
        let path = line[space...].trimmingCharacters(in: .whitespaces)
        return path.isEmpty ? nil : (uid, path)
    }

    static func readNettop() -> [ClashSocketRecord] {
        guard let output = run("/usr/bin/nettop", ["-L", "1", "-n", "-x", "-J", "bytes_in"]) else { return [] }
        return parseNettop(output)
    }

     
    private static let socketKinds: [Substring: (proto: UInt8, v6: Bool)] = [
        "tcp4": (6, false), "tcp6": (6, true),
        "udp4": (17, false), "udp6": (17, true),
        "quic4": (17, false), "quic6": (17, true),
    ]

     
     
     
     
     
     
     
     
     
     
     
     
    static func parseNettop(_ output: String) -> [ClashSocketRecord] {
        var records: [ClashSocketRecord] = []
        var pid: Int32?
        for raw in output.split(separator: "\n") {
            let field = raw.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
            guard !field.isEmpty else { continue }
            guard field.contains("<->") else {
                pid = field.lastIndex(of: ".").flatMap { Int32(field[field.index(after: $0)...]) }
                continue
            }
            let parts = field.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2, let kind = socketKinds[parts[0]], let owner = pid else { continue }
            let ends = parts[1].trimmingCharacters(in: .whitespaces).components(separatedBy: "<->")
            guard ends.count == 2, let local = endpoint(ends[0], v6: kind.v6) else { continue }
            let remote = endpoint(ends[1], v6: kind.v6)
            records.append(ClashSocketRecord(
                proto: kind.proto,
                local: local.host.isEmpty ? (kind.v6 ? "::" : "0.0.0.0") : local.host,
                localPort: local.port,
                remote: remote?.host ?? "", remotePort: remote?.port ?? 0,
                pid: owner, uid: -1
            ))
        }
        return records
    }

    private static func endpoint(_ text: String, v6: Bool) -> (host: String, port: UInt16)? {
        guard let cut = text.lastIndex(of: v6 ? "." : ":") else { return nil }
        let host = unmapped(String(text[..<cut]))
        let port = UInt16(text[text.index(after: cut)...]) ?? 0
        return (host == "*" ? "" : host, port)
    }

     
     
    static func unmapped(_ host: String) -> String {
        host.lowercased().hasPrefix("::ffff:") && host.contains(".") ? String(host.dropFirst(7)) : host
    }

     
     
     
    static let toolTimeout: TimeInterval = 2

     
    private static func run(_ tool: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let pid = process.processIdentifier
        let deadline = DispatchWorkItem {
            if process.isRunning { kill(pid, SIGKILL) }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + toolTimeout, execute: deadline)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        deadline.cancel()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    static func read(proto: UInt8) -> [ClashSocketRecord] {
        let name = proto == 6 ? "net.inet.tcp.pcblist_n" : "net.inet.udp.pcblist_n"
        var length = 0
        guard sysctlbyname(name, nil, &length, nil, 0) == 0, length > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctlbyname(name, &buffer, &length, nil, 0) == 0 else { return [] }
        return parse(Array(buffer.prefix(length)), proto: proto)
    }

     
     
     
     
     
     
    static func parse(_ buf: [UInt8], proto: UInt8) -> [ClashSocketRecord] {
        func u32(_ o: Int) -> UInt32 {
            buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt32.self) }
        }
        func port(_ o: Int) -> UInt16 { UInt16(buf[o]) << 8 | UInt16(buf[o + 1]) }
        func address(_ o: Int, v4: Bool) -> String {
            var text = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            let family = v4 ? AF_INET : AF_INET6
            let start = v4 ? o + 12 : o
            let count = v4 ? 4 : 16
            let bytes = Array(buf[start..<start + count])
            let ok = bytes.withUnsafeBytes { raw in
                inet_ntop(family, raw.baseAddress, &text, socklen_t(text.count)) != nil
            }
            return ok ? unmapped(String(cString: text)) : ""
        }
        guard buf.count >= 24 else { return [] }
        var records: [ClashSocketRecord] = []
        var offset = Int(u32(0))
        var pending: (local: String, lport: UInt16, remote: String, rport: UInt16)?
        while offset + 8 <= buf.count {
            let length = Int(u32(offset))
            let kind = u32(offset + 4)
            guard length > 0, offset + length <= buf.count else { break }
            if kind == 0x10, length >= 80 {
                let flags = buf[offset + 44]
                let v4 = flags & 0x1 != 0
                if v4 || flags & 0x2 != 0 {
                    pending = (
                        address(offset + 64, v4: v4), port(offset + 18),
                        address(offset + 48, v4: v4), port(offset + 16)
                    )
                } else {
                    pending = nil
                }
            } else if kind == 0x1, length >= 72, let socket = pending {
                records.append(ClashSocketRecord(
                    proto: proto, local: socket.local, localPort: socket.lport,
                    remote: socket.remote, remotePort: socket.rport,
                    pid: Int32(bitPattern: u32(offset + 68)),
                    uid: Int32(bitPattern: u32(offset + 64))
                ))
                pending = nil
            }
            offset += (length + 7) & ~7
        }
        return records
    }
}
#endif

#if os(macOS)
 
 
 
 
 
final class ClashMacProcessAttribution: @unchecked Sendable {
    static let shared = ClashMacProcessAttribution()

    private let owners: ClashMacSocketOwners
    private let lock = NSLock()
    private var named: [String: ClashSocketOwner] = [:]

    init(owners: ClashMacSocketOwners = .shared) {
        self.owners = owners
    }

     
     
     
     
     
    func fill(_ connections: [ClashConnection]) -> [ClashConnection] {
        lock.lock()
        defer { lock.unlock() }
        let askedAt = DispatchTime.now().uptimeNanoseconds
        var kept: [String: ClashSocketOwner] = [:]
        let result = connections.map { connection -> ClashConnection in
            guard connection.process.isEmpty else { return connection }
            let owner = named[connection.id] ?? lookup(connection, askedAt: askedAt)
            guard let owner, !owner.path.isEmpty else { return connection }
            kept[connection.id] = owner
            return connection.attributed(
                process: owner.name, processPath: owner.path, uid: Int64(owner.uid)
            )
        }
        named = kept
        return result
    }

    private func lookup(_ connection: ClashConnection, askedAt: UInt64) -> ClashSocketOwner? {
        guard let port = UInt16(connection.sourcePort), !connection.sourceIP.isEmpty else { return nil }
        let proto: UInt8 = connection.network.lowercased() == "udp" ? 17 : 6
        return owners.owner(
            proto: proto, source: connection.sourceIP, sourcePort: port,
            destination: connection.destinationIP,
            destinationPort: UInt16(connection.destinationPort) ?? 0,
            askedAt: askedAt
        )
    }
}
#endif
