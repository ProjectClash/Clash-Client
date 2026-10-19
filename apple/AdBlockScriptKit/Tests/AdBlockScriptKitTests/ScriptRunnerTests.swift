import XCTest
@testable import AdBlockScriptKit

/// The runner's promises: answer once, answer at the deadline, stop paying for
/// a script that keeps missing it, and never wedge the traffic behind a queue.
final class ScriptRunnerTests: XCTestCase {
    func testAScriptThatNeverAnswersTimesOut() {
        // A stub engine evaluates but never completes the run; the watchdog is
        // the only thing that can answer.
        let services = FakeServices()
        let limits = ScriptRunLimits(defaultTimeout: 0.1, grace: 0.05)
        let runner = ScriptRunner(limits: limits, services: services, makeEngine: { _, _ in StubEngine() })
        let done = expectation(description: "answer")
        runner.run(script: ScriptSource(name: "quiet", key: "quiet", text: ""),
                   request: makeRequest(), response: nil,
                   identity: ScriptIdentity(platform: .loon)) { outcome in
            XCTAssertEqual(outcome, .timedOut)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    func testWatchdogAnswersAtTheDeadline() {
        let services = FakeServices()
        // A script that never calls back: the engine evaluates but nothing
        // completes the run.
        let engine = StubEngine()
        let limits = ScriptRunLimits(defaultTimeout: 0.2, maximumTimeout: 0.2, grace: 0.05)
        let runner = ScriptRunner(limits: limits, services: services, makeEngine: { _, _ in engine })
        let done = expectation(description: "timeout")
        let started = Date()
        runner.run(script: ScriptSource(name: "loop", key: "loop", text: "while(true){}"),
                   request: makeRequest(), response: nil,
                   identity: ScriptIdentity(platform: .loon)) { outcome in
            XCTAssertEqual(outcome, .timedOut)
            XCTAssertLessThan(Date().timeIntervalSince(started), 2)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(runner.metrics.timedOut, 1)
    }

    func testRepeatedTimeoutsRefuseTheScript() {
        let services = FakeServices()
        let engine = StubEngine()
        let limits = ScriptRunLimits(defaultTimeout: 0.05, maximumTimeout: 0.05, grace: 0.02,
                                     timeoutsBeforeRefusal: 2)
        let runner = ScriptRunner(limits: limits, services: services, makeEngine: { _, _ in engine })

        func runOnce(_ finished: @escaping @Sendable (ScriptOutcome) -> Void) {
            runner.run(script: ScriptSource(name: "loop", key: "loop", text: "x"),
                       request: makeRequest(), response: nil,
                       identity: ScriptIdentity(platform: .loon), completion: finished)
        }

        for _ in 0..<2 {
            let first = expectation(description: "timeout")
            runOnce { _ in first.fulfill() }
            wait(for: [first], timeout: 3)
        }
        let third = expectation(description: "refused")
        runOnce { outcome in
            guard case .unavailable(let why) = outcome else { return XCTFail("expected a refusal, got \(outcome)") }
            XCTAssertTrue(why.contains("2"))
            third.fulfill()
        }
        wait(for: [third], timeout: 3)
        XCTAssertEqual(runner.metrics.refused, 1, "the third run must not reach the engine")
    }

    func testAConcurrencyCapQueuesRunsInsteadOfDroppingThem() {
        let services = FakeServices()
        let limits = ScriptRunLimits(defaultTimeout: 0.05, grace: 0.01, concurrentRuns: 1)
        let runner = ScriptRunner(limits: limits, services: services, makeEngine: { _, _ in
            return StubEngine()
        })
        let answered = expectation(description: "both")
        answered.expectedFulfillmentCount = 2
        for index in 0..<2 {
            runner.run(script: ScriptSource(name: "s\(index)", key: "s\(index)", text: "x"),
                       request: makeRequest(), response: nil,
                       identity: ScriptIdentity(platform: .loon)) { _ in answered.fulfill() }
        }
        wait(for: [answered], timeout: 6)
        XCTAssertEqual(runner.metrics.timedOut, 2)
    }
}
