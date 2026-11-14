import Foundation

 
 
 
 
 
 
 
 
 
public enum ClashConnectionDuration {
     
     
     
     
     
     
     
     
     
     
     
    public static func text(secondsElapsed: Int, locale: Locale = .current) -> String {
        let total = max(secondsElapsed, 0)
        let days = total / 86_400
        let rest = total % 86_400
        let clock = String(
            format: "%02d:%02d:%02d", rest / 3600, (rest % 3600) / 60, rest % 60
        )
        guard days > 0 else { return clock }
        return dayText(days, locale: locale) + " " + clock
    }

    private static func dayText(_ days: Int, locale: Locale) -> String {
        dayFormatterLock.lock()
        defer { dayFormatterLock.unlock() }
         
        let formatter: DateComponentsFormatter
        if let kept = dayFormatters[locale.identifier] {
            formatter = kept
        } else {
            formatter = DateComponentsFormatter()
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = locale
            formatter.calendar = calendar
            formatter.allowedUnits = [.day]
            formatter.unitsStyle = .abbreviated
            dayFormatters[locale.identifier] = formatter
        }
        return formatter.string(from: DateComponents(day: days)) ?? "\(days)d"
    }

    private static let dayFormatterLock = NSLock()
    nonisolated(unsafe) private static var dayFormatters: [String: DateComponentsFormatter] = [:]

     
     
     
    public static func secondsElapsed(
        sinceUnixSeconds start: Int64,
        now: Date = Date()
    ) -> Int? {
        guard start > 0 else { return nil }
        return Int(now.timeIntervalSince1970) - Int(start)
    }
}

 
public enum HomeConnectionClock {
     
     
     
     
     
     
     
     
     
     
    public static func startedAtUnixSeconds(coreReported: Int64?, connectedSince: Date?) -> Int64 {
        let core = max(coreReported ?? 0, 0)
        guard let connectedSince else { return core }
        return max(core, Int64(connectedSince.timeIntervalSince1970))
    }
}

 
 
 
 
public enum ClashTrafficSeries {
     
     
     
    public static func normalized(_ samples: [Int64]) -> [Double] {
        guard let peak = samples.max(), peak > 0 else {
            return samples.map { _ in 0 }
        }
        return samples.map { Double(max($0, 0)) / Double(peak) }
    }

     
     
     
     
     
     
    public static func normalizedPair(
        upload: [Int64],
        download: [Int64]
    ) -> (upload: [Double], download: [Double]) {
        let peak = max(upload.max() ?? 0, download.max() ?? 0)
        guard peak > 0 else {
            return (upload.map { _ in 0 }, download.map { _ in 0 })
        }
        let scale = { (samples: [Int64]) in
            samples.map { Double(max($0, 0)) / Double(peak) }
        }
        return (scale(upload), scale(download))
    }
}
