import Foundation

/// When a `cron` declaration is due.
///
/// Two shapes reach the engine, and they are not the same language:
///
/// * A five-field crontab line — `0 10 * * *` — from Surge, Loon and
///   Quantumult X. Fields are minute, hour, day-of-month, month, weekday.
/// * Loon's v2 form is a condition expression, `cron "0 10 * * *"` inside a
///   `cron "…"` rule, which the rewrite reader hands over as text.
///
/// The engine only needs one question answered — is this schedule due between
/// the last run and now — so the whole schedule is compiled once into a set of
/// field matchers, and a missed window is caught up rather than lost: a task
/// that should have run at 10:00 and was not woken until 10:40 still runs.
public enum AdBlockCronSchedule {
    public struct Field: Equatable {
        public var values: Set<Int>
        /// Set when the field is `*`, which matters for the day-of-month /
        /// weekday rule: crontab runs the job when *either* matches, and only
        /// when neither is a star.
        public var isWildcard = false

        public func matches(_ value: Int) -> Bool { values.contains(value) }
    }

    /// A parsed schedule: the five fields, or the reason it could not be read.
    public struct Schedule: Equatable {
        public var minutes: Field
        public var hours: Field
        public var days: Field
        public var months: Field
        public var weekdays: Field

        /// Crontab's rule: when both day fields are restricted, either one
        /// matching is enough. When one is `*`, the other decides.
        public func matches(_ date: Date, calendar: Calendar) -> Bool {
            let parts = calendar.dateComponents([.minute, .hour, .day, .month, .weekday], from: date)
            guard let minute = parts.minute, let hour = parts.hour, let day = parts.day,
                  let month = parts.month, let weekday = parts.weekday else { return false }
            guard minutes.matches(minute), hours.matches(hour), months.matches(month) else { return false }
            // `Calendar`'s weekday is 1…7 with Sunday as 1; crontab counts
            // Sunday as 0 or 7, and most declarations use 0.
            let sundayZero = weekday - 1
            let dayMatches = days.isWildcard || days.matches(day)
            let weekdayMatches = weekdays.isWildcard || weekdays.matches(sundayZero) || (sundayZero == 0 && weekdays.matches(7))
            if days.isWildcard && weekdays.isWildcard { return true }
            if days.isWildcard { return weekdayMatches }
            if weekdays.isWildcard { return dayMatches }
            return dayMatches || weekdayMatches
        }
    }

    /// Reads a crontab line. Returns `nil` for anything this build cannot
    /// schedule, so the caller can report it rather than run it at the wrong
    /// time.
    public static func parse(_ text: String) -> Schedule? {
        var words = text.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        // A cron rule may carry its schedule in quotes: `cron "0 10 * * *"`.
        words = words.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }.filter { !$0.isEmpty }
        // A leading `cron` keyword is part of Loon's condition, not a field.
        if let first = words.first, first.lowercased() == "cron" { words.removeFirst() }
        // Quartz writes six fields — seconds first, year last — and spells "no
        // particular value" as `?`. Loon's argument defaults use it (`0 0/2 * *
        // * ?`), so both are read rather than refused.
        if words.count == 6 || words.count == 7 {
            // The first field is seconds. A schedule whose seconds are not 0
            // cannot be expressed at minute granularity, so it is refused
            // instead of silently running at the wrong second.
            guard let seconds = Int(words[0]), seconds == 0 else { return nil }
            words.removeFirst()
            // A seventh field is the year. Pinning one would need a calendar
            // rule this scheduler does not keep, so it is refused rather than
            // run in the wrong year.
            if words.count == 6 {
                guard Int(words[5]) == nil else { return nil }
                words.removeLast()
            }
        }
        guard words.count == 5 else { return nil }
        guard let minutes = field(words[0], range: 0...59),
              let hours = field(words[1], range: 0...23),
              let days = field(words[2], range: 1...31),
              let months = field(words[3], range: 1...12),
              let weekdays = weekdayField(words[4]) else { return nil }
        return Schedule(minutes: minutes, hours: hours, days: days, months: months, weekdays: weekdays)
    }

    /// One field: `*`, a number, a range `a-b`, a step `*/n` or `a-b/n`, and a
    /// comma-separated list of any of them.
    public static func field(_ text: String, range: ClosedRange<Int>) -> Field? {
        guard !text.isEmpty else { return nil }
        // `?` is Quartz's "no particular value", which for a day field means
        // the same thing `*` means here.
        if text == "*" || text == "?" { return Field(values: Set(range), isWildcard: true) }
        var values: Set<Int> = []
        for part in text.split(separator: ",") {
            guard let parsed = Self.piece(part, range: range) else { return nil }
            values.formUnion(parsed)
        }
        guard !values.isEmpty else { return nil }
        return Field(values: values)
    }

    /// The weekday field, which crontab writes as `0…7` with both 0 and 7 as
    /// Sunday, and which a declaration may also spell as a name.
    public static func weekdayField(_ text: String) -> Field? {
        let names = ["sun": 0, "mon": 1, "tue": 2, "wed": 3, "thu": 4, "fri": 5, "sat": 6]
        var lowered = text.lowercased()
        for (name, value) in names { lowered = lowered.replacingOccurrences(of: name, with: String(value)) }
        guard var field = field(lowered, range: 0...7) else { return nil }
        // Normalise 7 to 0 so `matches` only has to ask once.
        if field.values.contains(7) {
            field.values.remove(7)
            field.values.insert(0)
        }
        return field
    }

    private static func piece(_ text: Substring, range: ClosedRange<Int>) -> Set<Int>? {
        var body = text
        var step = 1
        if let slash = body.firstIndex(of: "/") {
            guard let parsed = Int(body[body.index(after: slash)...]), parsed > 0 else { return nil }
            step = parsed
            body = body[..<slash]
        }
        let bounds: ClosedRange<Int>
        if body == "*" {
            bounds = range
        } else if let dash = body.firstIndex(of: "-") {
            guard let low = Int(body[..<dash]), let high = Int(body[body.index(after: dash)...]),
                  range.contains(low), range.contains(high), low <= high else { return nil }
            bounds = low...high
        } else {
            guard let value = Int(body), range.contains(value) else { return nil }
            // `0/2` means "from 0, every 2, to the end of the field" — the step
            // widens a bare number to the field's upper bound, which is how
            // Quartz writes every-two-minutes and every-two-hours. A bare
            // number without a step is just that number.
            bounds = step > 1 ? value...range.upperBound : value...value
        }
        // `5/10` means "5 and every 10 after", which is legal crontab, so a
        // step always applies from the lower bound.
        return Set(stride(from: bounds.lowerBound, through: bounds.upperBound, by: step))
    }

    /// The run that should happen for a window `(lastRun, now]`: the latest due
    /// time in the window, or `nil` when the window holds none.
    ///
    /// A missed window is not skipped — the latest one is returned so a task
    /// woken late still runs once — and a window holding several due times
    /// still returns one, because a task's own state, not its schedule, decides
    /// what a run does.
    public static func latestDue(_ schedule: Schedule, after lastRun: Date?, now: Date,
                                 calendar: Calendar = .current) -> Date? {
        let start = lastRun ?? now.addingTimeInterval(-60)
        guard start < now else { return nil }
        // Minute granularity, walked backwards from the current minute. A
        // schedule that has not run for a day costs 1440 comparisons, which is
        // cheaper than building a calendar rule and reading it back.
        var minute = calendar.date(bySetting: .second, value: 0, of: now) ?? now
        if minute > now { minute = calendar.date(byAdding: .minute, value: -1, to: minute) ?? minute }
        let limit = 60 * 24 * 8
        for _ in 0..<limit {
            if minute <= start { return nil }
            if schedule.matches(minute, calendar: calendar) { return minute }
            guard let previous = calendar.date(byAdding: .minute, value: -1, to: minute) else { return nil }
            minute = previous
        }
        return nil
    }
}
