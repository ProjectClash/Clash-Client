import Foundation
import WidgetKit

 
 
 
struct ClashWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: ClashWidgetSnapshot?
    let facts: ClashWidgetAppFacts?
    let tunnelActive: Bool
    let style: ClashWidgetStyle
    let group: String?
     
     
     
     
    var tunnelControllable: Bool = true
     
     
    var storedMode: ClashWidgetMode?
     
     
    var throughputUnit: ClashThroughputUnit = .bits
     
     
    var notice: String?
}

enum ClashWidgetTimelineBuilder {
     
     
     
    static func entry(style: ClashWidgetStyle, group: String?) async -> ClashWidgetEntry {
        let store = ClashWidgetMailboxClient.store
        let facts = store.readAppFacts()
         
         
         
        let shown = facts.map { $0.group(for: group) } ?? group
        let state = await ClashVPNControlDriver.state(journal: false)
        let active = state?.active ?? false
        var snapshot: ClashWidgetSnapshot?
        if active {
            snapshot = await ClashWidgetMailboxClient.requestAndWait(.refresh, group: shown, kind: style.rawValue)
        } else {
            ClashLogStore.shared.append("widget client: \(style.rawValue) timeline with the tunnel down", stream: .app, level: .info)
            snapshot = store.readSnapshot()
             
             
             
             
            if let file = snapshot, file.phase == .connected {
                snapshot = file.asDisconnected()
            }
        }
        return ClashWidgetEntry(
            date: Date(), snapshot: snapshot, facts: facts,
            tunnelActive: active, style: style, group: shown,
            tunnelControllable: state?.controllable ?? false,
            storedMode: store.restingMode(
                stored: UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite).flatMap(ClashWidgetStoredMode.read(from:))
            ),
            throughputUnit: ClashThroughputUnit.stored(in: UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite)),
            notice: store.readNotice()?.text(at: Date())
        )
    }

     
     
     
     
    static func timeline(_ entry: ClashWidgetEntry) -> Timeline<ClashWidgetEntry> {
        let policy: TimelineReloadPolicy
        let fileSaysConnected = ClashWidgetMailboxClient.store.readSnapshot()?.phase == .connected
        switch entry.snapshot?.phase {
        case .connected where entry.tunnelActive:
            policy = .after(entry.date.addingTimeInterval(30 * 60))
        case .connecting, .disconnecting, .reasserting:
            policy = .after(entry.date.addingTimeInterval(3))
        default:
             
             
            policy = (entry.tunnelActive || fileSaysConnected)
                ? .after(entry.date.addingTimeInterval(3))
                : .never
        }
        return Timeline(entries: [entry], policy: policy)
    }

    static func placeholder(style: ClashWidgetStyle) -> ClashWidgetEntry {
        ClashWidgetEntry(date: Date(), snapshot: nil, facts: nil, tunnelActive: false, style: style, group: nil,
                         throughputUnit: storedThroughputUnit)
    }

     
    private static var storedThroughputUnit: ClashThroughputUnit {
        ClashThroughputUnit.stored(in: UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite))
    }

     
     
    static func preview(style: ClashWidgetStyle) -> ClashWidgetEntry {
        let now = Date()
        let snapshot = ClashWidgetSnapshot(
            phase: .connected, profile: "Clash", mode: .rule, egress: "🇸🇬 Singapore 01",
            startedAt: now.addingTimeInterval(-3_600),
            upTotal: 24_500_000, downTotal: 318_000_000,
            proxy: ClashWidgetBytes(up: 20_000_000, down: 300_000_000),
            direct: ClashWidgetBytes(up: 4_500_000, down: 18_000_000),
            reject: ClashWidgetBytes(up: 0, down: 0), rejectCount: 12,
            connections: ClashWidgetConnections(opened: 186, active: 9, rejected: 12),
            wifi: ClashWidgetBytes(up: 24_500_000, down: 318_000_000),
            cellular: ClashWidgetBytes(up: 0, down: 0),
            group: ClashWidgetGroupSlice(
                name: "Proxy", type: "Selector", now: "🇸🇬 Singapore 01",
                all: ["🇸🇬 Singapore 01", "🇭🇰 Hong Kong 02", "🇯🇵 Tokyo 03", "🇺🇸 Los Angeles 04"]
            ),
            at: now
        )
        let facts = ClashWidgetAppFacts(profile: "Clash", firstGroup: "Proxy", groups: ["Proxy"], writtenAt: now)
        return ClashWidgetEntry(date: now, snapshot: snapshot, facts: facts, tunnelActive: true, style: style, group: "Proxy",
                                throughputUnit: storedThroughputUnit)
    }
}

struct ClashWidgetProvider: AppIntentTimelineProvider {
    typealias Entry = ClashWidgetEntry
    typealias Intent = ClashWidgetConfigurationIntent

    func placeholder(in _: Context) -> ClashWidgetEntry {
        ClashWidgetTimelineBuilder.placeholder(style: .status)
    }

    func snapshot(for configuration: Intent, in context: Context) async -> ClashWidgetEntry {
        if context.isPreview { return ClashWidgetTimelineBuilder.preview(style: configuration.style) }
        return await ClashWidgetTimelineBuilder.entry(style: configuration.style, group: configuration.group?.id)
    }

    func timeline(for configuration: Intent, in _: Context) async -> Timeline<ClashWidgetEntry> {
        ClashWidgetTimelineBuilder.timeline(
            await ClashWidgetTimelineBuilder.entry(style: configuration.style, group: configuration.group?.id)
        )
    }
}
