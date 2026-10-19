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

    /// A script that never yields cannot be interrupted, so its context is
    /// lost — but only once per run, and after `timeoutsBeforeRefusal` the
    /// script is refused outright, so the loss stops.
    func testSpinningScriptsAreBoundedAndThenRefused() {
        let baseline = JSCEngine.liveEngines
        let limits = ScriptRunLimits(defaultTimeout: 0.15, grace: 0.05,
                                     concurrentRuns: 4, timeoutsBeforeRefusal: 2)
        let runner = runner(limits: limits)

        let wedged = expectation(description: "wedged")
        wedged.expectedFulfillmentCount = 2
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

        let afterSpins = JSCEngine.liveEngines
        XCTAssertLessThanOrEqual(afterSpins - baseline, 2,
                                 "each spin may cost at most its own context")

        // The third run is refused before an engine is ever created, so the
        // count must not move again.
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
