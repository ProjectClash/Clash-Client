import ClashClientUI
import Foundation
import NetworkExtension

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct VPNUnrequestedStopLog {
     
    struct Run: Equatable {
         
        let connectedSince: Date?
         
        let lastSeenUp: Date
         
         
         
         
        let readerWordGeneration: UInt64?
    }

    private enum Key {
        static let armed = "vpn.unrequestedStop.armed"
         
         
         
         
         
        static let stopAskedAt = "vpn.unrequestedStop.stopAskedAt"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var armed: Run? {
        guard let object = defaults.dictionary(forKey: Key.armed),
              let seen = object["lastSeenUp"] as? Double else { return nil }
        return Run(
            connectedSince: (object["connectedSince"] as? Double).map(Date.init(timeIntervalSinceReferenceDate:)),
            lastSeenUp: Date(timeIntervalSinceReferenceDate: seen),
            readerWordGeneration: (object["readerWordGeneration"] as? NSNumber)?.uint64Value
        )
    }

     
    func tunnelIsUp(connectedSince: Date?, readerWordGeneration: UInt64?, at now: Date = Date()) {
        if let asked = defaults.object(forKey: Key.stopAskedAt) as? Double {
            guard let connectedSince, connectedSince.timeIntervalSinceReferenceDate > asked else { return }
            defaults.removeObject(forKey: Key.stopAskedAt)
        }
         
         
         
         
        let current = armed
        let sameRun = connectedSince.flatMap { since in
            current?.connectedSince.map { abs($0.timeIntervalSince(since)) < 0.001 }
        } ?? false
        let generation = sameRun ? current?.readerWordGeneration : readerWordGeneration
        var object: [String: Any] = ["lastSeenUp": now.timeIntervalSinceReferenceDate]
        if let connectedSince { object["connectedSince"] = connectedSince.timeIntervalSinceReferenceDate }
        if let generation { object["readerWordGeneration"] = NSNumber(value: generation) }
        defaults.set(object, forKey: Key.armed)
    }

     
     
     
     
    func appWillStop(connectedSince: Date?, at now: Date = Date()) {
        defaults.removeObject(forKey: Key.armed)
        defaults.set(now.timeIntervalSinceReferenceDate, forKey: Key.stopAskedAt)
    }

     
     
    func tunnelIsDown(lastReaderWord: ReaderTunnelIntent.Record?) -> Run? {
        defaults.removeObject(forKey: Key.stopAskedAt)
        guard let run = armed else { return nil }
        defaults.removeObject(forKey: Key.armed)
        if let word = lastReaderWord, word.intent == .stop, word.generation != run.readerWordGeneration {
            return nil
        }
        return run
    }

     
    static func line(for run: Run, status: String, error: NSError?) -> String {
        let since = run.connectedSince.map(stamp) ?? "unknown"
        let seen = stamp(run.lastSeenUp)
        let account: String
        if let error {
            let domain = error.domain
            let code = error.code
            let description = error.localizedDescription
            account = "domain=\(domain) code=\(code) description=\(description)"
        } else {
            account = "error=none"
        }
        return "vpn stopped without a request from Clash  status=\(status) connectedSince=\(since) lastSeenUp=\(seen) \(account)"
    }

    static func stamp(_ date: Date) -> String {
        ISO8601DateFormatter.string(from: date, timeZone: TimeZone(secondsFromGMT: 0)!,
                                    formatOptions: [.withInternetDateTime])
    }
}

 
 
 
struct UnrequestedStopAccount: Equatable {
    enum Cause: Equatable {
         
         
        case memory(footprintBytes: Int64?)
         
         
        case unexplained
    }

    let cause: Cause
     
    let seenDownAt: Date

     
    var homeStop: ClashHomeUnrequestedStop {
        if case .memory = cause { return .memory }
        return .unexplained
    }

     
    var footprintBytes: Int64? {
        if case .memory(let bytes) = cause { return bytes }
        return nil
    }

     
     
    static let coreLogLines = 400

     
     
     
     
     
     
    static let evidenceWindow: TimeInterval = 60

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func judge(
        run: VPNUnrequestedStopLog.Run, stoppedAt: Date,
        record: ClashOOMEvidence?, coreLog: [String], error: NSError?
    ) -> UnrequestedStopAccount? {
        var readings: [(at: Date, footprint: Int64)] = []
         
         
        if let record, record.pressureLevel == "critical" {
            readings.append((Date(timeIntervalSince1970: TimeInterval(record.recordedAtUnix)), record.physicalMemoryBytes))
        }
        for line in coreLog {
            guard let pressure = CoreMemoryPressure.observed(in: [line]), let at = loggedAt(line) else { continue }
            readings.append((at, pressure.footprintBytes))
        }
        guard let newest = readings.filter({ isOfThisDrop($0.at, run: run, stoppedAt: stoppedAt) })
            .max(by: { $0.at.timeIntervalSince1970 < $1.at.timeIntervalSince1970 })
        else {
            guard providerWentAway(error) else { return nil }
            return UnrequestedStopAccount(cause: .unexplained, seenDownAt: stoppedAt)
        }
        return UnrequestedStopAccount(cause: .memory(footprintBytes: newest.footprint > 0 ? newest.footprint : nil),
                                      seenDownAt: stoppedAt)
    }

     
     
     
     
     
     
     
     
     
    static func isOfThisDrop(_ at: Date, run: VPNUnrequestedStopLog.Run, stoppedAt: Date) -> Bool {
        let before = stoppedAt.timeIntervalSince(at)
        guard before >= 0, before <= evidenceWindow else { return false }
        guard let since = run.connectedSince else { return true }
        return at.timeIntervalSince1970 >= since.timeIntervalSince1970.rounded(.down)
    }

     
     
     
     
    static func providerWentAway(_ error: NSError?) -> Bool {
        guard let error else { return false }
        return error.domain == "NEVPNConnectionErrorDomain" && error.code == 12
    }

     
     
    static func loggedAt(_ line: String) -> Date? {
        guard let stamp = line.split(separator: " ", maxSplits: 1).first.map(String.init) else { return nil }
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return precise.date(from: stamp) ?? ISO8601DateFormatter().date(from: stamp)
    }

     
     
    static let recordFileName = "clash-oom-evidence.json"
     
    static let recordMaxBytes = 4 << 10

     
     
     
     
     
    static func readRecord(inContainer container: URL) -> ClashOOMEvidence? {
        guard let handle = try? FileHandle(forReadingFrom: container.appendingPathComponent(recordFileName))
        else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: recordMaxBytes + 1), data.count <= recordMaxBytes
        else { return nil }
        return try? JSONDecoder().decode(ClashOOMEvidence.self, from: data)
    }

     
     
    static let memoryRow = "Disconnected: not enough memory"

     
     
     
    static let memoryReason: ClashDisplayText =
        .copy("The VPN disconnected. Clash used more memory than iOS allows it, and the system stopped it.")

     
     
    var footprintSentence: ClashDisplayText? {
        footprintBytes.map { .format("It was using %@ before it was stopped.", [ClashStartupExplanation.megabytes($0)]) }
    }
}
