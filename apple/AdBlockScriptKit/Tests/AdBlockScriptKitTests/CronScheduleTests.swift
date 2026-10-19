import XCTest
@testable import AdBlockScriptKit

final class CronScheduleTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testPlainLineParses() throws {
        let schedule = try XCTUnwrap(AdBlockCronSchedule.parse("0 10 * * *"))
        XCTAssertTrue(schedule.matches(date(2026, 10, 19, 10, 0), calendar: calendar))
        XCTAssertFalse(schedule.matches(date(2026, 10, 19, 10, 1), calendar: calendar))
        XCTAssertFalse(schedule.matches(date(2026, 10, 19, 9, 0), calendar: calendar))
    }

    func testEveryFifteenMinutes() throws {
        let schedule = try XCTUnwrap(AdBlockCronSchedule.parse("*/15 * * * *"))
        XCTAssertTrue(schedule.matches(date(2026, 10, 19, 3, 0), calendar: calendar))
        XCTAssertTrue(schedule.matches(date(2026, 10, 19, 3, 45), calendar: calendar))
        XCTAssertFalse(schedule.matches(date(2026, 10, 19, 3, 20), calendar: calendar))
    }

    func testRangeAndList() throws {
        let schedule = try XCTUnwrap(AdBlockCronSchedule.parse("0,30 9-11 * * *"))
        XCTAssertTrue(schedule.matches(date(2026, 10, 19, 9, 30), calendar: calendar))
        XCTAssertTrue(schedule.matches(date(2026, 10, 19, 11, 0), calendar: calendar))
        XCTAssertFalse(schedule.matches(date(2026, 10, 19, 12, 0), calendar: calendar))
        XCTAssertFalse(schedule.matches(date(2026, 10, 19, 10, 15), calendar: calendar))
    }

    /// Crontab runs a job when either day field matches once both are
    /// restricted; that is the rule most declarations rely on and the one a
    /// naïve `&&` gets wrong.
    func testDayFieldsAreOredWhenBothRestricted() throws {
        // The 1st of the month, or any Monday.
        let schedule = try XCTUnwrap(AdBlockCronSchedule.parse("0 8 1 * 1"))
        let monday = date(2026, 10, 19, 8, 0)   // 19 Oct 2026 is a Monday
        let first = date(2026, 12, 1, 8, 0)
        let neither = date(2026, 12, 2, 8, 0)
        XCTAssertTrue(schedule.matches(monday, calendar: calendar))
        XCTAssertTrue(schedule.matches(first, calendar: calendar))
        XCTAssertFalse(schedule.matches(neither, calendar: calendar))
    }

    func testWildcardDayIsNotOred() throws {
        let schedule = try XCTUnwrap(AdBlockCronSchedule.parse("0 8 * * 1"))
        XCTAssertTrue(schedule.matches(date(2026, 10, 19, 8, 0), calendar: calendar))
        XCTAssertFalse(schedule.matches(date(2026, 10, 20, 8, 0), calendar: calendar))
    }

    func testSundayAsZeroAndSeven() throws {
        for text in ["0 8 * * 0", "0 8 * * 7", "0 8 * * sun"] {
            let schedule = try XCTUnwrap(AdBlockCronSchedule.parse(text), text)
            let sunday = date(2026, 10, 18, 8, 0)
            XCTAssertTrue(schedule.matches(sunday, calendar: calendar), text)
        }
    }

    /// Loon's argument defaults ship Quartz schedules — `0 0/2 * * * ?` — and
    /// reading one as five fields shifts every field by one, which would run
    /// the task in the wrong hour for the rest of its life.
    ///
    /// Quartz puts seconds first: `0 0/2 * * * ?` is seconds 0 and minutes
    /// 0,2,4…; `0 0 */2 * * ?` is the every-two-hours shape.
    func testQuartzSixFields() throws {
        let everyTwoHours = try XCTUnwrap(AdBlockCronSchedule.parse("0 0 */2 * * ?"))
        XCTAssertTrue(everyTwoHours.matches(date(2026, 10, 19, 10, 0), calendar: calendar))
        XCTAssertTrue(everyTwoHours.matches(date(2026, 10, 19, 0, 0), calendar: calendar))
        XCTAssertFalse(everyTwoHours.matches(date(2026, 10, 19, 11, 0), calendar: calendar))
        XCTAssertFalse(everyTwoHours.matches(date(2026, 10, 19, 10, 1), calendar: calendar))

        let everyTwoMinutes = try XCTUnwrap(AdBlockCronSchedule.parse("0 0/2 * * * ?"))
        XCTAssertTrue(everyTwoMinutes.matches(date(2026, 10, 19, 13, 4), calendar: calendar))
        XCTAssertFalse(everyTwoMinutes.matches(date(2026, 10, 19, 13, 5), calendar: calendar))

        // `0 * * * * ?` is every minute at second zero, which is what the
        // TestFlight monitor asks for.
        let everyMinute = try XCTUnwrap(AdBlockCronSchedule.parse("0 * * * * ?"))
        XCTAssertTrue(everyMinute.matches(date(2026, 10, 19, 13, 30), calendar: calendar))

        // Seconds that are not zero cannot be honoured at minute granularity.
        XCTAssertNil(AdBlockCronSchedule.parse("30 0 * * * ?"))
        // A pinned year would need a rule this scheduler does not keep.
        XCTAssertNil(AdBlockCronSchedule.parse("0 0 10 * * ? 2027"))
    }

    func testQuotedAndKeywordForms() throws {
        XCTAssertNotNil(AdBlockCronSchedule.parse("cron \"0 10 * * *\""))
        XCTAssertNotNil(AdBlockCronSchedule.parse("0 10 * * * "))
        XCTAssertNil(AdBlockCronSchedule.parse("0 10 * *"))
        XCTAssertNil(AdBlockCronSchedule.parse("61 10 * * *"))
        XCTAssertNil(AdBlockCronSchedule.parse("nonsense"))
    }

    /// A task woken late still runs once: the window is `(lastRun, now]` and the
    /// latest due time in it is what is reported.
    func testLateWakeUpCatchesUpOnce() throws {
        let schedule = try XCTUnwrap(AdBlockCronSchedule.parse("0 10 * * *"))
        let lastRun = date(2026, 10, 18, 10, 0)
        let late = date(2026, 10, 19, 14, 30)
        let due = AdBlockCronSchedule.latestDue(schedule, after: lastRun, now: late, calendar: calendar)
        XCTAssertEqual(due, date(2026, 10, 19, 10, 0))
        // And a second call with that run recorded finds nothing.
        XCTAssertNil(AdBlockCronSchedule.latestDue(schedule, after: due, now: late, calendar: calendar))
    }

    /// Several missed windows still produce one run, not several: a task's own
    /// state decides what a run does, and running it five times at once is not
    /// what the schedule meant.
    func testSeveralMissedRunsProduceOne() throws {
        let schedule = try XCTUnwrap(AdBlockCronSchedule.parse("*/15 * * * *"))
        let lastRun = date(2026, 10, 19, 9, 0)
        let now = date(2026, 10, 19, 12, 7)
        let due = AdBlockCronSchedule.latestDue(schedule, after: lastRun, now: now, calendar: calendar)
        XCTAssertEqual(due, date(2026, 10, 19, 12, 0))
    }

    func testNoDueTimeWhenWindowIsEmpty() throws {
        let schedule = try XCTUnwrap(AdBlockCronSchedule.parse("0 10 * * *"))
        let now = date(2026, 10, 19, 9, 0)
        XCTAssertNil(AdBlockCronSchedule.latestDue(schedule, after: date(2026, 10, 19, 8, 0), now: now, calendar: calendar))
    }
}
