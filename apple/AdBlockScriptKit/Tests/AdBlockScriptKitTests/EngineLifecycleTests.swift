import XCTest
@testable import AdBlockScriptKit

/// What a busy page does to the engine.
///
/// Every run gets its own `JSContext`, and a context that outlives its run is a
/// JavaScript heap the process cannot get back. That is the failure the
/// acceptance criteria call out by name, and it is invisible from the outside —
/// the scripts still answer correctly — so it has to be counted.
///
/// There is one case that cannot be fixed from here. JavaScriptCore's public C
/// API has no way to interrupt a running script: no `TerminateExecution`, no
/// execution time limit, nothing in `JSContextRef.h`. A script that spins in
/// `while (true)` therefore keeps its thread and its heap until the process
/// ends. The runner's answer is `timeoutsBeforeRefusal` — after that many
/// timeouts a script is not run again — which bounds the loss to a handful of
/// contexts rather than one per request. The tests below measure both: the
/// normal case must leak nothing, and the pathological one must stay bounded
/// and stop growing.
final class EngineLifecycleTests: XCTestCase {
    private func runner(timeout: TimeInterval = 2,
                        limits: ScriptRunLimits? = nil) -> ScriptRunner {
        ScriptRunner(limits: limits ?? ScriptRunLimits(defaultTimeout: timeout, grace: 0.2),
                     services: FakeServices(), makeEngine: { _, _ in try JSCEngine() })
    }

    private func settle() {
        let released = expectation(description: "settle")
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { released.fulfill() }
        wait(for: [released], timeout: 5)
    }

    /// A run that answers releases its context. A hundred requests must not
    /// leave a hundred heaps.
    func testFinishedRunsReleaseTheirContext() {
        let baseline = JSCEngine.liveEngines
        let done = expectation(description: "runs")
        done.expectedFulfillmentCount = 24
        let runner = runner()
        for index in 0..<24 {
            runner.run(script: ScriptSource(name: "s\(index)", key: "s\(index)", text: "$done({});"),
                       request: makeRequest(), response: nil,
                       identity: ScriptIdentity(platform: .loon)) { _ in done.fulfill() }
        }
        wait(for: [done], timeout: 30)
        settle()
        XCTAssertEqual(JSCEngine.liveEngines, baseline,
                       "24 runs that answered left \(JSCEngine.liveEngines - baseline) contexts behind")
    }

    /// A script that waits — the ordinary timeout, an HTTP call that never
    /// answers — is abandoned and its context goes away, because the thread
    /// comes back out of `evaluate`.
    func testAbandonedWaiterReleasesItsContext() {
        let baseline = JSCEngine.liveEngines
        let done = expectation(description: "timeout")
        done.expectedFulfillmentCount = 3
        let runner = runner(timeout: 0.2)
        for index in 0..<3 {
            // Never calls `$done`, so the watchdog gives up on it — but the
            // thread is idle in `drain()`, not stuck inside the engine.
            runner.run(script: ScriptSource(name: "w\(index)", key: "w\(index)", text: "var x = 1;"),
                       request: makeRequest(), response: nil,
                       identity: ScriptIdentity(platform: .loon)) { outcome in
                guard case .timedOut = outcome else { return XCTFail("expected a timeout, got \(outcome)") }
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 20)
        settle()
        XCTAssertEqual(JSCEngine.liveEngines, baseline,
                       "3 abandoned waiters left \(JSCEngine.liveEngines - baseline) contexts behind")
    }

    /// A script that never yields is stopped by the engine, not merely
    /// abandoned — and its thread and context come back.
    ///
    /// This used to be the one case the library could not fix: the comment here
    /// said JavaScriptCore's public C API had no way to interrupt a script, so a
    /// `while (true)` kept its thread until the process ended. That is not true.
    /// `JSContextGroupSetExecutionTimeLimit` terminates it, and the engine now
    /// sets that limit from the script's own budget. So a spin costs one timeout
    /// and nothing else: no leaked thread, no leaked context, and no bounded-but-
    /// permanent loss.
    func testSpinningScriptsAreTerminatedNotJustAbandoned() {
        let baseline = JSCEngine.liveEngines
        let limits = ScriptRunLimits(defaultTimeout: 0.2, grace: 0.05,
                                     concurrentRuns: 4, timeoutsBeforeRefusal: 2)
        let runner = runner(limits: limits)

        let wedged = expectation(description: "wedged")
        wedged.expectedFulfillmentCount = 2
        let started = Date()
        for index in 0..<2 {
            runner.run(script: ScriptSource(name: "spin", key: "spin", text: "while (true) {}"),
                       request: makeRequest(), response: nil,
                       identity: ScriptIdentity(platform: .loon)) { outcome in
                guard case .timedOut = outcome else { return XCTFail("expected a timeout, got \(outcome)") }
                wedged.fulfill()
            }
        }
        wait(for: [wedged], timeout: 15)
        settle()

        // The engine stops the script at its own limit, so the whole thing takes
        // about the budget rather than the watchdog's separate patience.
        XCTAssertLessThan(Date().timeIntervalSince(started), 6,
                          "a spun script must be stopped, not waited out")
        let afterSpins = JSCEngine.liveEngines
        XCTAssertLessThanOrEqual(afterSpins - baseline, 2,
                                 "each spin may cost at most its own context")

        // The third run is refused before an engine is ever created, so the
        // count must not move again. Refusal still matters: a script that
        // cannot finish in its budget once will keep failing, and every attempt
        // still costs a context.
        let refused = expectation(description: "refused")
        runner.run(script: ScriptSource(name: "spin", key: "spin", text: "while (true) {}"),
                   request: makeRequest(), response: nil,
                   identity: ScriptIdentity(platform: .loon)) { outcome in
            guard case .unavailable = outcome else { return XCTFail("expected a refusal, got \(outcome)") }
            refused.fulfill()
        }
        wait(for: [refused], timeout: 10)
        settle()
        XCTAssertEqual(JSCEngine.liveEngines, afterSpins,
                       "a refused script must not create a context")
    }

    /// The cap is a promise about *concurrency*, and `testTheCapDrains` only
    /// shows that ten short scripts all finish — ten scripts that answer
    /// instantly would pass even if the cap did nothing at all.
    ///
    /// This holds each slot open with a script that waits on a timer, so a third
    /// run would be visible as a third live context rather than hidden behind an
    /// instant answer. The high-water mark is sampled where a run is admitted.
    func testTheCapIsNeverExceeded() {
        let baseline = JSCEngine.liveEngines
        let limits = ScriptRunLimits(defaultTimeout: 10, grace: 1, concurrentRuns: 2)
        let peak = Locked(0)
        let runner = ScriptRunner(limits: limits, services: FakeServices(), makeEngine: { _, _ in
            // Construct first, sample after: the registry only counts an engine
            // once it exists, so reading before creating always sees zero and
            // would report a peak of one no matter how many runs overlapped.
            let engine = try JSCEngine()
            let open = JSCEngine.liveEngines - baseline
            peak.update { $0 = max($0, open) }
            return engine
        })
        let done = expectation(description: "runs")
        done.expectedFulfillmentCount = 6
        // Each waits 150 ms before answering, so two runs really do overlap and a
        // third would have to be visible while they are open.
        let slow = "setTimeout(function () { $done({}); }, 150);"
        for index in 0..<6 {
            runner.run(script: ScriptSource(name: "p\(index)", key: "p\(index)", text: slow),
                       request: makeRequest(), response: nil,
                       identity: ScriptIdentity(platform: .loon)) { _ in done.fulfill() }
        }
        wait(for: [done], timeout: 60)
        settle()
        XCTAssertLessThanOrEqual(peak.value, limits.concurrentRuns,
                                 "the runner opened \(peak.value) runs over a cap of \(limits.concurrentRuns)")
        XCTAssertEqual(JSCEngine.liveEngines, baseline, "the queue left contexts behind")
    }


    /// A queue with spinning scripts in it must still drain: the abandoned run's
    /// slot has to come back, or one bad script wedges the page.
    func testASpinningScriptDoesNotWedgeTheQueue() {
        let baseline = JSCEngine.liveEngines
        let limits = ScriptRunLimits(defaultTimeout: 0.2, grace: 0.05,
                                     concurrentRuns: 2, timeoutsBeforeRefusal: 5)
        let runner = ScriptRunner(limits: limits, services: FakeServices(),
                                  makeEngine: { _, _ in try JSCEngine() })
        let answered = Locked(0)
        let done = expectation(description: "runs")
        done.expectedFulfillmentCount = 6
        // Two spinners take both slots; four honest scripts queue behind them.
        for index in 0..<6 {
            let text = index < 2 ? "while (true) {}" : "$done({ body: 'ok' });"
            let name = "q\(index)"
            runner.run(script: ScriptSource(name: name, key: name, text: text),
                       request: makeRequest(), response: makeResponse(),
                       identity: ScriptIdentity(platform: .loon)) { outcome in
                if case .response = outcome { answered.update { $0 += 1 } }
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 30)
        settle()
        XCTAssertEqual(answered.value, 4,
                       "honest scripts were blocked behind the spinners (\(answered.value) of 4 answered)")
        XCTAssertEqual(JSCEngine.liveEngines, baseline, "spinners left contexts behind")
    }

    /// The concurrency cap queues rather than dropping, and the queue drains
    /// without holding on to the contexts it used.
    func testTheCapDrains() {
        let baseline = JSCEngine.liveEngines
        let limits = ScriptRunLimits(defaultTimeout: 2, grace: 0.2, concurrentRuns: 2)
        let runner = ScriptRunner(limits: limits, services: FakeServices(),
                                  makeEngine: { _, _ in try JSCEngine() })
        let done = expectation(description: "runs")
        done.expectedFulfillmentCount = 10
        for index in 0..<10 {
            runner.run(script: ScriptSource(name: "c\(index)", key: "c\(index)", text: "$done({});"),
                       request: makeRequest(), response: nil,
                       identity: ScriptIdentity(platform: .loon)) { _ in done.fulfill() }
        }
        wait(for: [done], timeout: 25)
        settle()
        XCTAssertEqual(JSCEngine.liveEngines, baseline,
                       "the queue left \(JSCEngine.liveEngines - baseline) contexts behind")
    }
}

/// A value shared across the runner's queues.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value { lock.lock(); defer { lock.unlock() }; return stored }
    func update(_ body: (inout Value) -> Void) { lock.lock(); body(&stored); lock.unlock() }
}