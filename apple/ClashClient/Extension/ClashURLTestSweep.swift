#if os(tvOS)
import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
final class ClashURLTestSweep: @unchecked Sendable {
    struct Probe: Equatable, Sendable {
        let name: String
         
        let url: String
    }

     
     
     
     
     
    struct Reading: Equatable, Sendable {
        let sweep: UInt64
        let delays: [Int?]
        let done: Bool
        var stopped = false

         
        var reply: [String: Any] {
            ["sweep": NSNumber(value: sweep), "done": done, "stopped": stopped,
             "delays": delays.map { $0.map { NSNumber(value: $0) as Any } ?? NSNull() }]
        }
    }

     
     
     
    static let widest = 16

     
    static func probes(from request: [String: Any]) -> [Probe]? {
        guard let list = request["probes"] as? [[String: Any]] else { return nil }
        let probes = list.compactMap { entry in
            (entry["name"] as? String).map { Probe(name: $0, url: entry["url"] as? String ?? "") }
        }
        return probes.count == list.count ? probes : nil
    }

     
    static func startReply(sweep: UInt64, count: Int) -> [String: Any] {
        ["sweep": NSNumber(value: sweep), "count": count]
    }

    typealias Measure = @Sendable (_ name: String, _ url: String) -> Int32

     
     
     
     
    static let longestFailureFloor: TimeInterval = 1

     
     
     
     
     
     
     
    static let unreadLease: TimeInterval = 30

    private let measure: Measure
    private let leaseNanoseconds: UInt64
    private let condition = NSCondition()
     
     
     
     
    private var sweep = UInt64.random(in: 1 ..< (1 << 52))
    private var probes: [Probe] = []
    private var delays: [Int?] = []
    private var next = 0
    private var width = 1
    private var failureFloor: TimeInterval = 0
    private var stopped = true
    private var closed = false
     
    private var workers = 0
     
    private var inHand = 0
     
    private var lastRead: UInt64 = 0

     
     
     
     
    private static var now: UInt64 { clock_gettime_nsec_np(CLOCK_MONOTONIC) }

    init(unreadLease: TimeInterval = ClashURLTestSweep.unreadLease, measure: @escaping Measure) {
        self.leaseNanoseconds = UInt64(max(0, min(unreadLease, 3_600)) * 1_000_000_000)
        self.measure = measure
    }

     
     
     
     
     
     
    func start(_ probes: [Probe], width: Int, failureFloor: TimeInterval) -> UInt64? {
        condition.lock()
        guard !closed else {
            condition.unlock()
            return nil
        }
        sweep &+= 1
        let id = sweep
        self.probes = probes
        delays = Array(repeating: nil, count: probes.count)
        next = 0
        self.width = min(max(width, 1), Self.widest)
        self.failureFloor = failureFloor.isNaN ? 0 : min(max(0, failureFloor), Self.longestFailureFloor)
        stopped = false
        lastRead = Self.now
        let count = min(self.width, probes.count)
        workers = count
        condition.broadcast()
        condition.unlock()
        for _ in 0..<count {
            let thread = Thread { [self] in work(id) }
            thread.name = "clash.urltest.sweep"
            thread.start()
        }
        return id
    }

     
     
    func read(_ id: UInt64) -> Reading? {
        condition.lock()
        defer { condition.unlock() }
        guard id == sweep else { return nil }
        lastRead = Self.now
        return Reading(sweep: id, delays: delays, done: stopped || workers == 0, stopped: stopped)
    }

     
     
     
     
    func stop(_ id: UInt64? = nil) {
        condition.lock()
        if id == nil || id == sweep { stopped = true }
        condition.broadcast()
        condition.unlock()
    }

     
    func close() {
        condition.lock()
        closed = true
        stopped = true
        condition.broadcast()
        condition.unlock()
    }

    private func work(_ id: UInt64) {
        while let (index, probe, floor) = take(id) {
            let began = DispatchTime.now().uptimeNanoseconds
            let delay = Int(measure(probe.name, probe.url))
            if delay <= 0 {
                let floor = UInt64(floor * 1_000_000_000)
                let spent = DispatchTime.now().uptimeNanoseconds &- began
                if spent < floor { Thread.sleep(forTimeInterval: Double(floor - spent) / 1_000_000_000) }
            }
            land(id, index, delay)
        }
        condition.lock()
        if id == sweep { workers -= 1 }
        condition.broadcast()
        condition.unlock()
    }

    private func take(_ id: UInt64) -> (Int, Probe, TimeInterval)? {
        condition.lock()
        defer { condition.unlock() }
        while id == sweep, !stopped, next < probes.count, inHand >= width {
            condition.wait()
        }
        if id == sweep, !stopped, next < probes.count,
           Self.now &- lastRead > leaseNanoseconds {
             
             
            stopped = true
            condition.broadcast()
        }
        guard id == sweep, !stopped, next < probes.count else { return nil }
        let index = next
        next += 1
        inHand += 1
        return (index, probes[index], failureFloor)
    }

    private func land(_ id: UInt64, _ index: Int, _ delay: Int) {
        condition.lock()
        inHand -= 1
        if id == sweep { delays[index] = delay }
        condition.broadcast()
        condition.unlock()
    }
}
#endif
