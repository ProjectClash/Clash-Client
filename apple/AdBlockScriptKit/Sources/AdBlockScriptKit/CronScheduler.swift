import Foundation

/// The `cron` and `generic` scripts a module declares, and when each is due.
///
/// Surge, Loon and Quantumult X all run scheduled scripts from the *app*, not
/// from the tunnel: the tunnel is only up while the VPN is, and a task that is
/// supposed to run at 10:00 has to run whether or not the user was browsing.
/// So the scheduler lives here, above the engine, and the app asks it for work
/// on whatever wake-up it already gets.
///
/// It owns three things the engine must not:
///
/// * **Due times.** A schedule is compiled once per module load, and a run is
///   chosen from the window since the last one, so a late wake-up still runs.
/// * **Last-run bookkeeping.** Kept beside the module's argument choices, in
///   the app group, so a restart does not re-run a task that just ran nor skip
///   one that has not.
/// * **A budget.** A wake-up is short; the scheduler hands out work until the
///   budget is spent and leaves the rest for the next wake-up rather than
///   overrunning the time iOS gave it.
public struct AdBlockCronTask: Equatable {
    public var script: ScriptSource
    /// The module the script came from, for reporting.
    public var module: String
    /// The identity its platform APIs follow.
    public var identity: ScriptIdentity
    /// Absent for a `generic` script, which has no cadence: the app runs it
    /// when the user asks, and the scheduler owns only what is due by itself.
    public var schedule: AdBlockCronSchedule.Schedule?
    /// The declaration's own timeout, in seconds.
    public var timeout: TimeInterval?

    /// The app builds these from what the publisher wrote, which is a different
    /// module from this one, so the initialiser has to be public. The tests are
    /// `@testable` and would not have caught its absence.
    public init(script: ScriptSource, module: String, identity: ScriptIdentity,
                schedule: AdBlockCronSchedule.Schedule?, timeout: TimeInterval?) {
        self.script = script
        self.module = module
        self.identity = identity
        self.schedule = schedule
        self.timeout = timeout
    }
}

/// Where the last run of a task is remembered. A file in the app group, so the
/// app and the tunnel agree on it.
public protocol AdBlockCronBookkeeping: AnyObject {
    func lastRun(for key: String) -> Date?
    func record(_ date: Date, for key: String)
}

/// A small JSON file of `key → ISO-8601 date`.
public final class AdBlockCronFile: AdBlockCronBookkeeping {
    private let url: URL
    private let lock = NSLock()
    private var dates: [String: Date]

    public init(url: URL) {
        self.url = url
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: url),
           let decoded = try? decoder.decode([String: Date].self, from: data) {
            dates = decoded
        } else {
            dates = [:]
        }
    }

    public func lastRun(for key: String) -> Date? {
        lock.lock(); defer { lock.unlock() }
        return dates[key]
    }

    public func record(_ date: Date, for key: String) {
        lock.lock()
        dates[key] = date
        let snapshot = dates
        lock.unlock()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snapshot) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }
}

/// Picks the tasks a wake-up should run.
public final class AdBlockCronScheduler {
    private let bookkeeping: AdBlockCronBookkeeping
    private var calendar: Calendar

    public init(bookkeeping: AdBlockCronBookkeeping, calendar: Calendar = .current) {
        self.bookkeeping = bookkeeping
        self.calendar = calendar
    }

    /// The tasks due in `(lastRun, now]`, newest first, each with the time it
    /// was due. A task that has never run is due if its schedule matches now.
    public func due(_ tasks: [AdBlockCronTask], now: Date = Date()) -> [(task: AdBlockCronTask, due: Date)] {
        var out: [(AdBlockCronTask, Date)] = []
        for task in tasks {
            let key = Self.key(task)
            guard let schedule = task.schedule,
                  let due = AdBlockCronSchedule.latestDue(schedule, after: bookkeeping.lastRun(for: key),
                                                          now: now, calendar: calendar) else { continue }
            out.append((task, due))
        }
        return out.sorted { $0.0.module == $1.0.module ? $0.1 > $1.1 : $0.0.module < $1.0.module }
            .map { (task: $0.0, due: $0.1) }
    }

    /// Hands due tasks to `run` until `budget` is spent, then records the ones
    /// that ran. A task that throws is still recorded, so a script that is
    /// broken does not run on every wake-up.
    @discardableResult
    public func drain(_ tasks: [AdBlockCronTask], now: Date = Date(), budget: TimeInterval,
                      run: (AdBlockCronTask) -> Void) -> Int {
        let start = Date()
        var ran = 0
        for entry in due(tasks, now: now) {
            if Date().timeIntervalSince(start) >= budget { break }
            run(entry.task)
            bookkeeping.record(entry.due, for: Self.key(entry.task))
            ran += 1
        }
        return ran
    }

    /// A task's key is its script address plus its module, because the same
    /// address can be declared by two modules with different schedules.
    public static func key(_ task: AdBlockCronTask) -> String {
        "\(task.module)#\(task.script.key)"
    }

    /// The next time any task is due after `now`, which is what a wake-up
    /// request should ask for. A minute of slack keeps a wake-up from landing
    /// one second early, which would find nothing due.
    public func nextWake(_ tasks: [AdBlockCronTask], after now: Date = Date()) -> Date? {
        var earliest: Date?
        for task in tasks {
            guard let schedule = task.schedule, let next = nextDue(schedule, after: now) else { continue }
            if let current = earliest, current <= next { continue }
            earliest = next
        }
        return earliest?.addingTimeInterval(60)
    }

    /// The first matching minute after `now`. The search is bounded to eight
    /// days, which covers every schedule including `0 0 29 2 *`.
    public func nextDue(_ schedule: AdBlockCronSchedule.Schedule, after now: Date) -> Date? {
        guard let start = calendar.date(bySetting: .second, value: 0, of: now) else { return nil }
        var minute = calendar.date(byAdding: .minute, value: 1, to: start) ?? start
        for _ in 0..<(60 * 24 * 8) {
            if schedule.matches(minute, calendar: calendar) { return minute }
            guard let next = calendar.date(byAdding: .minute, value: 1, to: minute) else { return nil }
            minute = next
        }
        return nil
    }
}
