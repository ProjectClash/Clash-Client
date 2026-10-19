import XCTest
@testable import AdBlockScriptKit

final class CronSchedulerTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func task(_ schedule: String, module: String = "m", key: String = "k") -> AdBlockCronTask {
        AdBlockCronTask(script: ScriptSource(name: key, key: key, text: ""), module: module,
                        identity: ScriptIdentity(platform: .surge),
                        schedule: AdBlockCronSchedule.parse(schedule)!, timeout: nil)
    }

    /// A `generic` script has no cadence, so it carries no schedule and the
    /// scheduler must never pick it up — the app runs it when the user asks.
    /// `AdBlockCronRunner.genericScripts` builds exactly this shape.
    private func manualTask(key: String = "g") -> AdBlockCronTask {
        AdBlockCronTask(script: ScriptSource(name: key, key: key, text: ""), module: "m",
                        identity: ScriptIdentity(platform: .loon),
                        schedule: nil, timeout: nil)
    }

    func testAGenericScriptIsNeverDue() {
        let memory = Memory()
        let scheduler = AdBlockCronScheduler(bookkeeping: memory, calendar: calendar)
        // A cron beside it so the call has work to do either way.
        let jobs = [task("* * * * *", key: "cron"), manualTask()]
        let due = scheduler.due(jobs, now: date(15, 12, 0))
        XCTAssertEqual(due.map(\.task.script.key), ["cron"],
                       "only the scheduled script may be due")
    }

    /// And it cannot become due later, however far the clock is wound.
    func testAGenericScriptIsNeverADueTimeOrAWakeTime() {
        let scheduler = AdBlockCronScheduler(bookkeeping: Memory(), calendar: calendar)
        let jobs = [manualTask()]
        XCTAssertTrue(scheduler.due(jobs, now: date(15, 12, 0)).isEmpty)
        XCTAssertNil(scheduler.nextWake(jobs, after: date(15, 12, 0)),
                     "a generic script must not schedule a wake-up")
        XCTAssertTrue(scheduler.due(jobs, now: date(15, 12, 1)).isEmpty)
    }

    private final class Memory: AdBlockCronBookkeeping {
        var dates: [String: Date] = [:]
        func lastRun(for key: String) -> Date? { dates[key] }
        func record(_ date: Date, for key: String) { dates[key] = date }
    }

    func testNothingIsDueBeforeTheFirstWindow() {
        let memory = Memory()
        let scheduler = AdBlockCronScheduler(bookkeeping: memory, calendar: calendar)
        // Never run, and the schedule is 10:00 — at 09:00 nothing is due.
        XCTAssertTrue(scheduler.due([task("0 10 * * *")], now: date(19, 9, 0)).isEmpty)
    }

    func testFirstRunIsDueWhenTheScheduleMatches() {
        let memory = Memory()
        let scheduler = AdBlockCronScheduler(bookkeeping: memory, calendar: calendar)
        let due = scheduler.due([task("0 10 * * *")], now: date(19, 10, 0))
        XCTAssertEqual(due.count, 1)
        XCTAssertEqual(due.first?.due, date(19, 10, 0))
    }

    func testARecordedRunIsNotDueAgain() {
        let memory = Memory()
        let scheduler = AdBlockCronScheduler(bookkeeping: memory, calendar: calendar)
        let one = task("0 10 * * *")
        _ = scheduler.drain([one], now: date(19, 10, 0), budget: 30) { _ in }
        XCTAssertEqual(memory.dates.count, 1)
        XCTAssertTrue(scheduler.due([one], now: date(19, 10, 30)).isEmpty)
    }

    /// Two modules declaring the same script address keep separate run times,
    /// which is why the key includes the module.
    func testKeyIncludesModule() {
        let a = task("0 10 * * *", module: "a", key: "https://x/y.js")
        let b = task("0 10 * * *", module: "b", key: "https://x/y.js")
        XCTAssertNotEqual(AdBlockCronScheduler.key(a), AdBlockCronScheduler.key(b))
    }

    func testBudgetStopsTheDrain() {
        let memory = Memory()
        let scheduler = AdBlockCronScheduler(bookkeeping: memory, calendar: calendar)
        let tasks = (0..<50).map { task("0 10 * * *", module: "m\($0)", key: "k\($0)") }
        var ran = 0
        let started = Date()
        let count = scheduler.drain(tasks, now: date(19, 10, 0), budget: 0.05) { _ in
            ran += 1
            // Burn the budget so later tasks are left for the next wake-up.
            Thread.sleep(forTimeInterval: 0.02)
        }
        XCTAssertLessThan(count, tasks.count)
        XCTAssertEqual(count, ran)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.0)
    }

    func testDrainRecordsOnlyWhatRan() {
        let memory = Memory()
        let scheduler = AdBlockCronScheduler(bookkeeping: memory, calendar: calendar)
        let tasks = (0..<10).map { task("0 10 * * *", module: "m\($0)", key: "k\($0)") }
        let count = scheduler.drain(tasks, now: date(19, 10, 0), budget: 0.03) { _ in
            Thread.sleep(forTimeInterval: 0.02)
        }
        XCTAssertEqual(memory.dates.count, count)
    }

    func testNextWakeIsTheEarliestDuePlusSlack() {
        let scheduler = AdBlockCronScheduler(bookkeeping: Memory(), calendar: calendar)
        let early = task("30 9 * * *", module: "a", key: "a")
        let late = task("0 10 * * *", module: "b", key: "b")
        let wake = scheduler.nextWake([early, late], after: date(19, 8, 0))
        XCTAssertEqual(wake, date(19, 9, 30).addingTimeInterval(60))
    }

    func testNextDueWalksForward() {
        let scheduler = AdBlockCronScheduler(bookkeeping: Memory(), calendar: calendar)
        let schedule = AdBlockCronSchedule.parse("0 10 * * *")!
        XCTAssertEqual(scheduler.nextDue(schedule, after: date(19, 10, 0)), date(20, 10, 0))
        XCTAssertEqual(scheduler.nextDue(schedule, after: date(19, 9, 59)), date(19, 10, 0))
    }

    func testFileBookkeepingRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cron-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let first = AdBlockCronFile(url: url)
        XCTAssertNil(first.lastRun(for: "a#b"))
        first.record(date(19, 10, 0), for: "a#b")
        let second = AdBlockCronFile(url: url)
        XCTAssertEqual(second.lastRun(for: "a#b"), date(19, 10, 0))
        XCTAssertNil(second.lastRun(for: "other"))
    }
}

/// A scheduled script has no traffic behind it, but platform code reaches for
/// `$request` anyway; the placeholder is what keeps that from throwing.
final class ScheduledRunTests: XCTestCase {
    func testScheduledRunGetsARequestContext() {
        let runner = ScriptRunner(limits: ScriptRunLimits(defaultTimeout: 5, grace: 0.5),
                                  services: FakeServices(), makeEngine: { _, _ in try JSCEngine() })
        let done = XCTestExpectation(description: "ran")
        let script = ScriptSource(name: "cron", key: "cron", text: """
        $done({ body: $request && $request.url ? 'saw-request' : 'none' });
        """)
        runner.runScheduled(script: script, identity: ScriptIdentity(platform: .surge)) { outcome in
            // A scheduled run has no response to modify, so its `$done` body is
            // a request change like any other; what matters is that it ran.
            XCTAssertNotEqual(outcome, .unchanged)
            done.fulfill()
        }
        XCTAssertEqual(XCTWaiter().wait(for: [done], timeout: 12), .completed)
    }
}
