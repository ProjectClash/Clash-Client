import Foundation
import JavaScriptCore

 
 
 
 
 
 
enum ScriptEngine {
    enum ScriptError: Error, Equatable, LocalizedError {
        case contextUnavailable
        case evaluationFailed(String)
        case missingMain
        case threw(String)
        case invalidResult
         
         
         
         
         
        case timedOut

        var errorDescription: String? {
            switch self {
            case .timedOut:
                return "The script ran too long and was stopped. A loop that never ends will do this."
            case .contextUnavailable: return "script engine unavailable"
            case .evaluationFailed(let message): return "script error: \(message)"
            case .missingMain: return "script must define main(config)"
            case .threw(let message): return "script threw: \(message)"
            case .invalidResult: return "script must return the config object"
            }
        }
    }

     
     
     
     
    private static let configBinding = "__clashScriptConfig"
    private static let profileNameBinding = "__clashScriptProfileName"

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static let executionLimit: TimeInterval = 5

     
     
     
     
     
     
    static let waitLimit: TimeInterval = 15

     
     
     
     
    enum Caller: Sendable {
         
         
         
        case silent
         
         
         
         
        case surfaced
    }

     
     
     
     
    enum LogName {
        static let appWide = "app-wide script"
        static let tvOverride = "override script"
    }

     
     
     
    struct Timing: Sendable {
         
        var slice: TimeInterval = 0.1
         
        var wait: @Sendable (DispatchSemaphore, TimeInterval) -> DispatchTimeoutResult = { $0.wait(timeout: .now() + $1) }
         
         
        var cpuTime: @Sendable (thread_t) -> TimeInterval? = { ScriptEngine.cpuTime(of: $0) }

        static let system = Timing()
    }

     
     
     
     
    static func cpuTime(of thread: thread_t) -> TimeInterval? {
        guard thread != 0 else { return nil }
        var info = thread_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
        let answer = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
            }
        }
        guard answer == KERN_SUCCESS else { return nil }
        return TimeInterval(info.user_time.seconds) + TimeInterval(info.user_time.microseconds) / 1_000_000
            + TimeInterval(info.system_time.seconds) + TimeInterval(info.system_time.microseconds) / 1_000_000
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private static let lock = NSLock()
    nonisolated(unsafe) private static var abandoned: [Int: Int] = [:]
    nonisolated(unsafe) private static var runsPastTheBound: [Int: Int] = [:]
     
     
     
    nonisolated(unsafe) private static var refusalSaid: Set<Int> = []
    static let silentRunsStopAfter = 3

     
     
     
    private static let hooks = NSLock()



     
     
     
     
    static var log: @Sendable (String, ClashLogLevel) -> Void {
        get { hooks.lock(); defer { hooks.unlock() }; return logSink }
        set { hooks.lock(); logSink = newValue; hooks.unlock() }
    }
    nonisolated(unsafe) private static var logSink: @Sendable (String, ClashLogLevel) -> Void = { line, level in
        ClashLogStore.shared.append(line, stream: .app, level: level)
    }

     
     
    static func hasExceededItsBound(_ script: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return abandoned[script.hashValue] != nil
    }

     
    private enum Ending {
        case inTime
         
        case usedItsBound(cpu: TimeInterval)
         
        case outOfWait(cpu: TimeInterval?)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func run(
        script: String,
        configJSON: String,
        profileName: String = "",
        caller: Caller,
        name: String = "",
        bound: TimeInterval = executionLimit,
        waitBound: TimeInterval = waitLimit,
        timing: Timing = .system,
        atTheDeadline: ((DispatchSemaphore) -> Void)? = nil
    ) throws -> String {
        let key = script.hashValue
        let called = name.isEmpty ? "a script" : "script \"\(name)\""
        lock.lock()
        let stillOut = abandoned[key] != nil
        let pastTheBound = runsPastTheBound[key, default: 0]
        let knownSlow = caller == .silent && pastTheBound >= silentRunsStopAfter
         
         
        let saysRefusal = (stillOut || knownSlow) && (caller == .surfaced || refusalSaid.insert(key).inserted)
        lock.unlock()
        if stillOut || knownSlow {
            if saysRefusal {
                log(stillOut
                    ? "\(called) was not run: a run of it that was given up on is still running"
                    : "\(called) was not run for a page's own build: its last \(pastTheBound) runs each used the whole \(seconds(bound)) s",
                    .warning)
            }
            throw ScriptError.timedOut
        }



         
         
         
         
        final class Attempt: @unchecked Sendable {
             
            var result: Result<String, Error>?
            var givenUpOn = false
             
            var thread: thread_t = 0
             
            var used: TimeInterval = 0
        }
        let attempt = Attempt()
        let finished = DispatchSemaphore(value: 0)
        let worker = Thread {
            let mine = pthread_mach_thread_np(pthread_self())
            lock.lock()
            attempt.thread = mine
            lock.unlock()
            let began = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            let result: Result<String, Error>
            do {
                result = .success(try runOnCurrentThread(
                    script: script, configJSON: configJSON, profileName: profileName
                ))
            }
            catch { result = .failure(error) }
            let used = TimeInterval(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) &- began) / 1_000_000_000
            lock.lock()
            attempt.result = result
            attempt.used = used
             
            attempt.thread = 0
             
             
            let wasGivenUpOn = attempt.givenUpOn
            if wasGivenUpOn {
                let stillOut = abandoned[key, default: 1] - 1
                abandoned[key] = stillOut > 0 ? stillOut : nil
                if stillOut <= 0 { refusalSaid.remove(key) }
            }
            lock.unlock()
            if wasGivenUpOn {
                log("\(called): the run that was given up on came back after \(seconds(used)) s of its own time", .info)
            }
            finished.signal()
        }
        worker.stackSize = 1 << 20
        worker.start()

         
         
         
         
         
        let slice = max(0, min(timing.slice, bound / 4))
        var awake: TimeInterval = 0
        var ending = Ending.inTime
        while timing.wait(finished, slice) != .success {
            awake += slice
            lock.lock()
            let isBack = attempt.result != nil
             
             
             
            let begun = attempt.thread != 0
            let cpu = isBack ? nil : (begun ? timing.cpuTime(attempt.thread) : 0)
            lock.unlock()
            if isBack { break }
             
             
            if (cpu ?? awake) >= bound { ending = .usedItsBound(cpu: cpu ?? awake); break }
            if awake >= waitBound { ending = .outOfWait(cpu: cpu); break }
        }
        if case .inTime = ending {} else { atTheDeadline?(finished) }

        lock.lock()
         
         
         
         
        guard let result = attempt.result else {
            attempt.givenUpOn = true
             
             
            let othersAreOut = abandoned[key] != nil
            abandoned[key, default: 0] += 1
            if case .usedItsBound = ending, !othersAreOut { runsPastTheBound[key, default: 0] += 1 }
            let inARow = runsPastTheBound[key, default: 0]
            lock.unlock()
            switch ending {
            case .usedItsBound(let cpu):
                log("\(called) was given up on: it used \(seconds(cpu)) s of its own time (the bound is \(seconds(bound)) s), "
                    + "waited for \(seconds(awake)) s; \(inARow) in a row", .warning)
            case .outOfWait(let cpu):
                log("\(called) was given up on after \(seconds(awake)) s of waiting: its thread had used "
                    + "\(cpu.map { seconds($0) } ?? "?") s of its own time (the bound is \(seconds(bound)) s)", .warning)
            case .inTime:
                break
            }
            throw ScriptError.timedOut
        }
         
         
         
         
        if case .inTime = ending, runsPastTheBound.removeValue(forKey: key) != nil { refusalSaid.remove(key) }
        let used = attempt.used
        lock.unlock()
        if caller == .surfaced {
            log("\(called) ran: \(seconds(used)) s of its own time, waited for \(seconds(awake)) s", .info)
        }
        return try result.get()
    }

    private static func seconds(_ value: TimeInterval) -> String {
        String(format: "%.2f", value)
    }

    private static func runOnCurrentThread(
        script: String, configJSON: String, profileName: String
    ) throws -> String {
        guard let context = JSContext() else { throw ScriptError.contextUnavailable }


        var thrown: String?
        context.exceptionHandler = { _, value in thrown = value?.toString() ?? "exception" }

        context.evaluateScript(script)
        if let thrown { throw ScriptError.evaluationFailed(thrown) }

        let isFunction = context
            .evaluateScript("(typeof main === 'function')")?.toBool() ?? false
        guard isFunction else { throw ScriptError.missingMain }

         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        context.setObject(
            configJSON.isEmpty ? "{}" : configJSON,
            forKeyedSubscript: configBinding as NSString
        )
         
         
         
         
         
        context.setObject(
            profileName, forKeyedSubscript: profileNameBinding as NSString
        )
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        let result = context.evaluateScript("""
            (function () {
              var config = JSON.parse(\(configBinding));
              if (config !== null && typeof config === 'object' && !Array.isArray(config)
                  && config['proxy-providers'] === undefined) {
                config['proxy-providers'] = {};
              }
              var result = main(config, \(profileNameBinding));
              if (result === null || typeof result !== 'object' || Array.isArray(result)) {
                return null;
              }
              return JSON.stringify(result);
            })();
            """)
        if let thrown { throw ScriptError.threw(thrown) }

        guard let result, result.isString, let json = result.toString() else {
            throw ScriptError.invalidResult
        }
        return json
    }
}
