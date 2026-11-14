#if os(iOS) || os(macOS)
import Darwin
import Foundation
import os

 
 
 
 
 
 
 
 
 

struct ModuleMemoryReading: Equatable, Sendable {
     
    let footprint: Int64
     
     
    let headroom: Int64?
}

enum ModuleMemoryProbe {
     
     
     
     
     
     
     
    static func read() -> ModuleMemoryReading {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        let footprint = result == KERN_SUCCESS ? Int64(info.phys_footprint) : -1
        #if os(iOS)
        let available = Int64(os_proc_available_memory())
        return ModuleMemoryReading(footprint: footprint, headroom: available > 0 ? available : nil)
        #else
        return ModuleMemoryReading(footprint: footprint, headroom: nil)
        #endif
    }

     
     
     
     
     
     
    static func available() -> Int64? {
        #if os(iOS)
        let available = Int64(os_proc_available_memory())
        return available > 0 ? available : nil
        #else
        return nil
        #endif
    }
}

 
 
protocol ModulePressureSource: AnyObject {
    func start(_ handler: @escaping (DispatchSource.MemoryPressureEvent) -> Void)
    func cancel()
}

final class ModuleSystemPressureSource: ModulePressureSource {
    private let source: DispatchSourceMemoryPressure
    private var started = false
    private var cancelled = false

    init(queue: DispatchQueue) {
        source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: queue)
    }

    func start(_ handler: @escaping (DispatchSource.MemoryPressureEvent) -> Void) {
        guard !started, !cancelled else { return }
        started = true
        source.setEventHandler { [weak source] in
            guard let source else { return }
            handler(source.data)
        }
        source.resume()
    }

    func cancel() {
        guard !cancelled else { return }
        cancelled = true
        source.setEventHandler(handler: nil)
         
        if !started { source.resume() }
        source.cancel()
    }

    deinit { cancel() }
}

struct ModuleLadderThresholds: Equatable, Sendable {
     
     
     
     
     
    var floor: Int64
     
     
     
    var relief: Int64
     
    var assumedLimit: Int64?
     
     
     
    var relievesOnCriticalOnly: Bool

    private static let mib: Int64 = 1 << 20

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static let iOS = ModuleLadderThresholds(floor: 8 * mib, relief: 14 * mib, assumedLimit: 50 * mib, relievesOnCriticalOnly: false)
     
     
     
     
    static let macOS = ModuleLadderThresholds(floor: 0, relief: 0, assumedLimit: nil, relievesOnCriticalOnly: true)

    static var current: ModuleLadderThresholds {
        #if os(macOS)
        return .macOS
        #else
        return .iOS
        #endif
    }
}

 
 
 
 
struct ModuleMemoryShortfall: Equatable, Sendable {
    let needed: Int64
    let available: Int64
    let floor: Int64

    var description: String {
        let mib = { (bytes: Int64) in String(format: #"%.1f MiB"#, Double(bytes) / 1_048_576) }
        return #"running it takes about \#(mib(needed)), and \#(mib(available)) is left, \#(mib(floor)) of it kept free"#
    }
}

 
enum ModuleMemoryRelief: Equatable, Sendable {
     
    case tight(ModuleMemoryReading)
     
    case beforeSkip
     
     
    case critical(ModuleMemoryReading)
}

 
enum ModuleLadderLowering: Equatable, Sendable {
     
     
    case headroomHeld(ModuleMemoryReading, relief: Int64)
}

final class ModuleMemoryLadder: ModuleAllowance {
    typealias Rung = ModuleEngineReport.Rung
    typealias Cause = ModuleEngineReport.RungCause

     
     
    static let readingSpacing: TimeInterval = 0.25
     
     
     
    static let reliefHold: TimeInterval = 60
     
     
     
    static let scriptRunCost: Int64 = 1 << 20

     
     
    static func monotonicNow() -> Date { Date(timeIntervalSinceReferenceDate: ModuleEngine.monotonicNow()) }

    private let thresholds: ModuleLadderThresholds
    private let probe: () -> ModuleMemoryReading
    private let now: () -> Date
    private let onChange: (Rung, Cause, ModuleMemoryReading) -> Void
    private let onReading: (ModuleMemoryReading) -> Void
     
     
    private let onLower: (Rung, Cause?, ModuleLadderLowering) -> Void
     
     
    private let onRelieve: (ModuleMemoryRelief) -> Void
    private(set) var rung: Rung
     
    private(set) var rungCause: Cause?
     
     
    private(set) var memoryRung: Rung
    private var lastReadingAt: Date?
     
     
    private var lastHeadroom: Int64?
     
    private var clearSince: Date?
     
     
    private var tight = false
     
    private var scriptsMissing = false
    private var pressureSource: ModulePressureSource?

     
     
     
    init(thresholds: ModuleLadderThresholds, startingAt start: Rung = .normal, takenBy cause: Cause? = nil,
         probe: @escaping () -> ModuleMemoryReading = ModuleMemoryProbe.read,
         now: @escaping () -> Date = ModuleMemoryLadder.monotonicNow, onChange: @escaping (Rung, Cause, ModuleMemoryReading) -> Void,
         onReading: @escaping (ModuleMemoryReading) -> Void = { _ in },
         onLower: @escaping (Rung, Cause?, ModuleLadderLowering) -> Void = { _, _, _ in },
         onRelieve: @escaping (ModuleMemoryRelief) -> Void = { _ in }) {
        self.thresholds = thresholds
        self.probe = probe
        self.now = now
        self.onChange = onChange
        self.onReading = onReading
        self.onLower = onLower
        self.onRelieve = onRelieve
        rung = start
        rungCause = start == .normal ? nil : cause
        memoryRung = cause == .scriptsUnavailable ? .normal : start
        scriptsMissing = cause == .scriptsUnavailable
    }

    deinit {
        pressureSource?.cancel()
    }

     
     
    var allowsScripts: Bool { !scriptsMissing }
    var allowsDecryption: Bool { rung < .engineStopped }

    func noteActivity() { evaluate() }

    func evaluate() { evaluate(forced: false) }

     
     
    private func evaluate(forced: Bool) {
        guard !thresholds.relievesOnCriticalOnly else { return }
        let at = now()
        let near = lastHeadroom.map { $0 < thresholds.relief } ?? false
        if !forced, !near, let last = lastReadingAt, (0..<Self.readingSpacing).contains(at.timeIntervalSince(last)) { return }
        lastReadingAt = at
        let reading = probe()
        onReading(reading)
        guard let headroom = headroom(of: reading) else { return }
        take(headroom, reading, at: at)
    }

     
    private func headroom(of reading: ModuleMemoryReading) -> Int64? {
        reading.headroom ?? thresholds.assumedLimit.map { $0 - reading.footprint }
    }

     
     
     
     
    private func take(_ headroom: Int64, _ reading: ModuleMemoryReading, at: Date) {
        lastHeadroom = headroom
        if headroom < thresholds.relief {
            clearSince = nil
            if !tight {
                tight = true
                onRelieve(.tight(reading))
            }
        } else {
            tight = false
            if clearSince.map({ at < $0 }) ?? true { clearSince = at }
        }
        if headroom <= thresholds.floor {
            raise(to: .engineStopped, cause: .memoryHeadroom, reading)
        } else if memoryRung > .normal, let since = clearSince, at.timeIntervalSince(since) >= Self.reliefHold {
            memoryRung = .normal
            lower(to: scriptsMissing ? .scriptsStopped : .normal, cause: scriptsMissing ? .scriptsUnavailable : nil,
                  why: .headroomHeld(reading, relief: thresholds.relief))
        }
    }

     
     
     
     
     
     
     
    func roomForScript() -> ModuleMemoryShortfall? {
        guard !thresholds.relievesOnCriticalOnly else { return nil }
        guard case let (short, reading)? = room(for: Self.scriptRunCost) else { return nil }
        raise(to: .scriptsStopped, cause: .memoryHeadroom, reading)
        return short
    }

     
     
    private func room(for cost: Int64) -> (ModuleMemoryShortfall, ModuleMemoryReading)? {
        func read() -> (Int64, ModuleMemoryReading)? {
            let at = now()
            lastReadingAt = at
            let reading = probe()
            onReading(reading)
            guard let headroom = headroom(of: reading) else { return nil }
            take(headroom, reading, at: at)
            return (headroom, reading)
        }
        guard case let (first, _)? = read(), first - cost < thresholds.floor else { return nil }
        onRelieve(.beforeSkip)
        guard case let (again, reading)? = read(), again - cost < thresholds.floor else { return nil }
        return (ModuleMemoryShortfall(needed: cost, available: again, floor: thresholds.floor), reading)
    }

     
     
    private func lower(to target: Rung, cause: Cause?, why: ModuleLadderLowering) {
        guard target < rung || (target == rung && cause != rungCause) else { return }
        rung = target
        rungCause = cause
        onLower(target, cause, why)
    }

     
     
     
     
     
    func pressure(_ event: DispatchSource.MemoryPressureEvent) {
        guard thresholds.relievesOnCriticalOnly else { return evaluate(forced: true) }
        guard event.contains(.critical) else { return }
        let reading = probe()
        onReading(reading)
        onRelieve(.critical(reading))
    }

     
    func scriptsUnavailable() {
        scriptsMissing = true
        raise(to: .scriptsStopped, cause: .scriptsUnavailable, probe())
    }

     
    func watchPressure(on queue: DispatchQueue,
                       source make: (DispatchQueue) -> ModulePressureSource = { ModuleSystemPressureSource(queue: $0) }) {
        guard pressureSource == nil else { return }
        let source = make(queue)
        source.start { [weak self] event in self?.pressure(event) }
        pressureSource = source
    }

     
    func stopWatching() {
        pressureSource?.cancel()
        pressureSource = nil
    }

    private func raise(to target: Rung, cause: Cause, _ reading: ModuleMemoryReading) {
        let memory = cause != .scriptsUnavailable
        let memoryRose = memory && target > memoryRung
        if memoryRose { memoryRung = target }
        if target > rung {
            rung = target
            rungCause = cause
            onChange(target, cause, reading)
        } else if memoryRose, target == rung, rungCause == .scriptsUnavailable {
             
            rungCause = cause
            onChange(target, cause, reading)
        }
    }
}

 
 
struct ModuleLadderSeams {
    var probe: () -> ModuleMemoryReading = ModuleMemoryProbe.read
    var now: () -> Date = ModuleMemoryLadder.monotonicNow
     
    var pressureSource: ((DispatchQueue) -> ModulePressureSource)? = { ModuleSystemPressureSource(queue: $0) }

    static var system: ModuleLadderSeams { ModuleLadderSeams() }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum ModuleEngineBudget {
    static let steady: Int64 = 4 << 20
    #if os(macOS)
    static let peak: Int64 = 8 << 20
    #else
    static let peak: Int64 = 10 << 20
    #endif

     
     
     
     
     
     
     
     
    static let heldPerList: Int64 = 16 << 10
    static let heldPerListEntry: Int64 = 56
    static let heldPerListNameByte: Int64 = 4

     
     
     
     
     
     
    static let heldPerProgram: Int64 = 16 << 10
    static let heldPerRuleByte: Int64 = 4
     
     
     
     
     
     
     
    static let heldPerCompiledRegex: Int64 = 1_843
     
     
     
    static let chargedPerCompiledRegex: Int64 = 3_174
     
     
     
     
     
     
     
     
    static let ruleBytesPerCompiledRegex: Int64 = 30
    static let regexesTheShareSetsAside: Int64 = 512

     
     
     
     
    static func programHeld(keptRuleBytes: Int, compiledRegexes: Int) -> Int64 {
        heldPerProgram + Int64(max(0, keptRuleBytes)) * heldPerRuleByte + Int64(max(0, compiledRegexes)) * heldPerCompiledRegex
    }

     
    static func listsHeld(_ assignment: ModuleEngineAssignment) -> Int64 {
        let lists = [assignment.mitmHosts, assignment.forceHTTPEngineHosts]
        let entries = lists.reduce(0) { $0 + $1.items.count }
        let bytes = lists.reduce(0) { total, list in
            total + list.items.reduce(0) { sum, item in
                if case .name(let name) = item.entry.pattern { return sum + name.utf8.count }
                return sum
            }
        }
        return heldPerList + Int64(entries) * heldPerListEntry + Int64(bytes) * heldPerListNameByte
    }

     
    static func programHeld(ruleBytes: Int) -> Int64 {
        let bytes = Int64(max(0, ruleBytes))
        return heldPerProgram + bytes * heldPerRuleByte
            + min(bytes / ruleBytesPerCompiledRegex, regexesTheShareSetsAside) * chargedPerCompiledRegex
    }

     
     
     
     
     
     
     
     
     
    static func programRoom(headroom: Int64?, holding held: Int64 = 0, keptRuleBytes kept: Int) -> Int64? {
        #if os(macOS)
        return nil
        #else
        guard let headroom else { return nil }
        let thresholds = ModuleLadderThresholds.iOS
        let structures = programHeld(keptRuleBytes: kept, compiledRegexes: 0)
        let steady = headroom + max(0, held) - thresholds.floor - growthReserve - structures
        let peak = headroom - thresholds.relief - structures
        return max(0, min(steady, peak))
        #endif
    }

     
     
     
     
    static let readPeakPerRuleByte: Int64 = 12

     
     
     
     
     
     
    static let growthReserve: Int64 = 6 << 20

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func ruleBytes(headroom: Int64?, holding held: Int64 = 0) -> Int {
        #if os(macOS)
        return ModuleReader.maximumRuleBytes
        #else
        guard let headroom else { return ModuleReader.maximumRuleBytes }
        let thresholds = ModuleLadderThresholds.iOS
        let peakRoom = headroom - thresholds.relief
        let steadyRoom = headroom + max(0, held) - thresholds.floor - growthReserve
        guard peakRoom > 0, steadyRoom > 0 else { return 0 }
        var low = 0, high = Int(peakRoom / readPeakPerRuleByte)
        while low < high {
            let middle = low + (high - low + 1) / 2
            if programHeld(ruleBytes: middle) <= steadyRoom { low = middle } else { high = middle - 1 }
        }
        return low
        #endif
    }

     
     
     
     
     
    static func headroomForShare(_ reading: ModuleMemoryReading = ModuleMemoryProbe.read(),
                                 onADevice: Bool = onADevice) -> Int64? {
        if let headroom = reading.headroom { return headroom }
        guard onADevice, reading.footprint >= 0, let limit = ModuleLadderThresholds.iOS.assumedLimit else { return nil }
        return max(0, limit - reading.footprint)
    }

    #if targetEnvironment(simulator)
    static let onADevice = false
    #else
    static let onADevice = true
    #endif
}

extension ModuleEngineAssembly {
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func react(engine: ModuleEngine, reporter: ModuleEngineReporter, scripts: ModuleScriptRunning)
        -> (ModuleEngineReport.Rung, ModuleEngineReport.RungCause, ModuleMemoryReading) -> Void {
        { [weak engine, weak reporter] rung, cause, reading in
            guard let engine, let reporter, rung > .normal else { return }
            let before = reporter.report.rung
            let mib = { (bytes: Int64?) in bytes.map { String(format: "%.1f MiB", Double($0) / 1_048_576) } ?? "unknown" }
            let what: String
            switch rung {
            case .normal: what = "nothing stops"
            case .scriptsStopped where cause == .scriptsUnavailable: what = "scripts stop"
            case .scriptsStopped: what = #"a script was skipped for memory; each next one is judged as it starts"#
            case .engineStopped: what = "every new session is relayed untouched"
            }
            let name = cause == .scriptsUnavailable ? "rung" : "memory rung"
            engine.log.say("\(name) \(rung.rawValue) (\(cause.rawValue)), \(what): footprint \(mib(reading.footprint)), headroom \(mib(reading.headroom))")
            if cause == .scriptsUnavailable { scripts.releaseAll() } else { relieve(engine: engine, scripts: scripts) }
            if rung >= .engineStopped { engine.passThroughCauses.insert(.memory) }
            engine.interceptor?.shed(for: rung)
            engine.metrics.update {
                if before < .scriptsStopped, rung == .scriptsStopped { $0.ladderScriptsStoppedTotal += 1 }
                if before < .engineStopped, rung >= .engineStopped { $0.ladderEngineStoppedTotal += 1 }
            }
            reporter.record {
                if rung > before {
                    $0.rung = rung
                    $0.rungAt = reporter.now()
                }
                if rung >= before { $0.rungCause = cause }
                $0.footprintBytes = reading.footprint
                $0.headroomBytes = reading.headroom
                $0.counters = engine.metrics.counters
                if rung >= .engineStopped {
                    $0.state = .passThrough
                    if before < .engineStopped { $0.lastMemoryStopAt = reporter.now() }
                }
            }
        }
    }

     
     
     
     
     
     
     
     
    static func relax(engine: ModuleEngine, reporter: ModuleEngineReporter)
        -> (ModuleEngineReport.Rung, ModuleEngineReport.RungCause?, ModuleLadderLowering) -> Void {
        { [weak engine, weak reporter] rung, cause, why in
            guard let engine, let reporter else { return }
            let reason: String
            switch why {
            case .headroomHeld(let reading, let relief):
                let mib = { (bytes: Int64?) in bytes.map { String(format: #"%.1f MiB"#, Double($0) / 1_048_576) } ?? #"unknown"# }
                reason = #"at least \#(mib(relief)) stayed free for \#(Int(ModuleMemoryLadder.reliefHold)) s: footprint \#(mib(reading.footprint)), headroom \#(mib(reading.headroom))"#
            }
            engine.log.say("memory rung \(rung.rawValue) (\(cause?.rawValue ?? "none")): \(reason)")
            let stopEnded = rung < .engineStopped && engine.passThroughCauses.contains(.memory)
            if rung < .engineStopped { engine.passThroughCauses.remove(.memory) }
            reporter.record {
                $0.rung = rung
                $0.rungCause = cause
                $0.rungAt = reporter.now()
                if rung < .engineStopped, $0.state == .passThrough, !engine.passThroughOnly { $0.state = .running }
            }
            if stopEnded {
                engine.queue.async { [weak engine] in engine?.onMemoryStopEnded?() }
            }
        }
    }

     
     
     
     
     
     
    static func relieve(engine: ModuleEngine?, scripts: ModuleScriptRunning) {
        scripts.relieve()
        (engine?.interceptor as? ModuleInterceptor)?.services.program.dropCachedRegexes()
    }
}
#endif
