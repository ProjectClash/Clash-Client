import ClashClientKit
import Foundation

 
 
 
 
 
 
 
 
public enum ClashSubscriptionUsageFormat {
     
     
     
    public static func amount(_ bytes: Int64) -> String {
        ClashThroughputFormatter.usage(bytes)
    }

     
     
     
     
    public static func expiryDay(_ expire: Int64, locale: Locale, timeZone: TimeZone = .current) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)
        style.timeZone = timeZone
         
         
         
        style.calendar = Calendar(identifier: .gregorian)
        style.calendar.timeZone = timeZone
        return Date(timeIntervalSince1970: TimeInterval(expire)).formatted(style)
    }

     
     
     
    public static func compactExpiryDay(_ date: Date, timeZone: TimeZone = .current) -> String {
        compactFormatters.formatter(for: timeZone).string(from: date)
    }

     
    private final class CompactFormatters: @unchecked Sendable {
        private let lock = NSLock()
        private var kept: [String: DateFormatter] = [:]

        func formatter(for timeZone: TimeZone) -> DateFormatter {
            lock.lock()
            defer { lock.unlock() }
            if let formatter = kept[timeZone.identifier] { return formatter }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = timeZone
            kept[timeZone.identifier] = formatter
            return formatter
        }
    }

    private static let compactFormatters = CompactFormatters()

     
     
     
    public enum Urgency: Equatable, Sendable {
         
        case none
         
        case soon
         
        case today
         
        case expired
    }

     
     
    public static func daysUntilExpiry(_ date: Date, now: Date = Date(), timeZone: TimeZone = .current) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                       to: calendar.startOfDay(for: date)).day ?? 0
    }

    public static func urgency(of date: Date, now: Date = Date(), timeZone: TimeZone = .current) -> Urgency {
        let days = daysUntilExpiry(date, now: now, timeZone: timeZone)
        if days < 0 { return .expired }
        if days == 0 { return .today }
        return days <= 7 ? .soon : .none
    }

     
     
    public static func traffic(_ usage: ConfigurationSubscriptionUsage) -> ClashDisplayText? {
        if usage.total > 0 { return .format("%@ of %@ used", [amount(usage.used), amount(usage.total)]) }
        return usage.used > 0 ? .format("Used %@", [amount(usage.used)]) : nil
    }

     
     
     
    public static func used(_ usage: ConfigurationSubscriptionUsage) -> ClashDisplayText {
        traffic(usage) ?? .format("Used %@", [amount(usage.used)])
    }

     
    public static func expiry(_ usage: ConfigurationSubscriptionUsage, locale: Locale,
                              timeZone: TimeZone = .current) -> ClashDisplayText? {
        guard usage.expire > 0 else { return nil }
        return .format("Expires %@", [expiryDay(usage.expire, locale: locale, timeZone: timeZone)])
    }

    public static func uploaded(_ usage: ConfigurationSubscriptionUsage) -> ClashDisplayText {
        .format("Uploaded %@", [amount(max(0, usage.upload))])
    }

    public static func downloaded(_ usage: ConfigurationSubscriptionUsage) -> ClashDisplayText {
        .format("Downloaded %@", [amount(max(0, usage.download))])
    }
}
