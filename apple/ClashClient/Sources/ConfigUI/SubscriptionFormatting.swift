import ClashClientKit
import ClashClientUI
import SwiftUI

enum SubscriptionExpiryStatus: Equatable {
    case never
    case active
    case expiringSoon
    case expiresToday
    case expired
}

struct SubscriptionExpiryPresentation: Equatable {
    let status: SubscriptionExpiryStatus
    let text: String
}

extension SubscriptionInfo {
    var usedBytes: Int64 {
        let (sum, overflow) = upload.addingReportingOverflow(download)
        return max(0, overflow ? Int64.max : sum)
    }

    var usageFraction: Double? {
        guard total > 0 else { return nil }
        return min(max(Double(usedBytes) / Double(total), 0), 1)
    }

     
     
    var remainingBytes: Int64? {
        guard total > 0 else { return nil }
        return max(0, total - usedBytes)
    }

     
     
    static func compactBytes(_ bytes: Int64) -> String {
        let units = ["K", "M", "G", "T"]
        var value = Double(bytes) / 1024
        var unit = 0
        while value >= 1000, unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        let text = value < 100
            ? String(format: "%.1f", value)
            : String(format: "%.0f", value)
        return text.replacingOccurrences(of: ".0", with: "") + units[unit]
    }

     
     
     
     
    var usageSummary: String {
        let used = ByteCountFormatter.string(usedBytes)
        var summary = total > 0 ? "\(used) / \(ByteCountFormatter.string(total))" : used
        if expire > 0 {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: "UTC")
            summary += " · expires \(formatter.string(from: Date(timeIntervalSince1970: TimeInterval(expire))))"
        }
        return summary
    }

     
     
     
     
     
    func humanSummary(locale: Locale, timeZone: TimeZone = .current) -> String {
        [usageSentence(locale: locale), expirySentence(locale: locale, timeZone: timeZone)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

     
     
     
    func usageSentence(locale: Locale) -> String {
        let usage = ConfigurationSubscriptionUsage(upload: upload, download: download, total: total, expire: expire)
        return ClashCopy.string(for: ClashSubscriptionUsageFormat.used(usage), locale: locale)
    }

     
     
     
     
     
    func expirySentence(locale: Locale, timeZone: TimeZone = .current) -> String? {
        guard expire > 0 else { return nil }
        let day = ClashSubscriptionUsageFormat.expiryDay(expire, locale: locale, timeZone: timeZone)
        return ClashCopy.format("Expires %@", locale: locale, day)
    }

     
     
     
    func expiryPresentation(now: Date = Date(), timeZone: TimeZone = .current) -> SubscriptionExpiryPresentation {
        guard expire > 0 else {
            return SubscriptionExpiryPresentation(status: .never, text: "No expiry")
        }
        let expiryDate = Date(timeIntervalSince1970: TimeInterval(expire))
         
         
        let days = ClashSubscriptionUsageFormat.daysUntilExpiry(expiryDate, now: now, timeZone: timeZone)
        let date = ClashSubscriptionUsageFormat.compactExpiryDay(expiryDate, timeZone: timeZone)
        if days < 0 {
            return SubscriptionExpiryPresentation(status: .expired, text: "Expired \(date)")
        }
        if days == 0 {
            return SubscriptionExpiryPresentation(status: .expiresToday, text: "Expires today")
        }
        if days <= 7 {
            return SubscriptionExpiryPresentation(
                status: .expiringSoon,
                text: "Expires in \(days) day\(days == 1 ? "" : "s")"
            )
        }
        return SubscriptionExpiryPresentation(status: .active, text: "Expires \(date)")
    }
}

struct SubscriptionInfoView: View {
    let info: SubscriptionInfo
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
             
             
            summaryLine
                .font(ClashPlatformLayout.pageUsesSystemSettingsIdiom ? ClashMacSettingsType.value : .caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let fraction = info.usageFraction {
                ProgressView(value: fraction)
                     
                     
                     
                    .tint(fraction >= 1 ? Color.red : nil)
                    .accessibilityLabel("Data Usage")
                    .accessibilityValue("\(Int(fraction * 100)) percent")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var summaryLine: Text {
        var line = Text(verbatim: info.usageSentence(locale: locale))
        if let expiry = info.expirySentence(locale: locale) {
            line = line + Text(verbatim: " · ") + Text(verbatim: expiry).foregroundColor(expiryTint)
        }
        return line
    }

    private var expiry: SubscriptionExpiryPresentation {
        info.expiryPresentation()
    }

    private var expiryTint: Color {
        switch expiry.status {
        case .expired, .expiresToday: return .red
        case .expiringSoon: return .orange
        case .never, .active: return .secondary
        }
    }
}

enum SubscriptionURLPresentation {
     
     
     
     
     
     
    static func hostDescription(
        _ rawValue: String,
        locale: Locale
    ) -> String {
        guard let host = URLComponents(string: rawValue)?.host, !host.isEmpty else {
            return ClashCopy.string("Profile URL", locale: locale)
        }
        return host
    }

     
     
     
     
    static func autoLabel(for rawValue: String) -> String {
        guard let host = URLComponents(string: rawValue)?.host else { return "Profile URL" }
        let parts = host.split(separator: ".")
        guard parts.count >= 2 else { return host }
        return String(parts[parts.count - 2])
    }

     
    static func safeDescription(_ rawValue: String) -> String {
        guard var components = URLComponents(string: rawValue) else {
            return "Profile URL"
        }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        let pathSegments = components.path.split(
            separator: "/", omittingEmptySubsequences: false
        ).map { segment -> String in
            let text = String(segment)
            let isOpaqueToken = text.count >= 16 && text.allSatisfy {
                $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_")
            }
            return isOpaqueToken ? "…" : text
        }
        components.path = pathSegments.joined(separator: "/")
        return components.url?.absoluteString
            .replacingOccurrences(of: "%E2%80%A6", with: "…")
            ?? "Profile URL"
    }
}
