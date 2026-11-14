import AppIntents
import SwiftUI
import WidgetKit

 
 
 
 
 

enum ClashWidgetSlotFactory {
    static func slots(for entry: ClashWidgetEntry) -> ClashWidgetSlots {
        let active = entry.tunnelActive
        let group = entry.group ?? entry.facts?.firstGroup
        let powerLabel = Image(systemName: "power")
            .font(.body.weight(.semibold))
            .frame(width: 22, height: 22)
            .accessibilityLabel(Text(clash: .copy(active ? "Connected" : "Not Connected")))
        return ClashWidgetSlots(
            power: entry.tunnelControllable
                ? AnyView(
                     
                     
                     
                     
                     
                    Toggle(isOn: active, intent: ClashWidgetPowerIntent(value: !active)) { powerLabel }
                        .toggleStyle(.button)
                        .buttonBorderShape(.circle)
                        .widgetAccentable()
                )
                : AnyView(
                     
                     
                     
                     
                    Link(destination: ClashSystemRoute.vpn(.connect).url) { powerLabel }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                        .widgetAccentable()
                ),
             
             
            mode: { mode, label in
                AnyView(Button(intent: ClashWidgetSetModeIntent(mode: mode)) { label }.buttonStyle(.plain))
            },
            member: { name, label in
                if active, let group {
                    return AnyView(Button(intent: ClashWidgetSelectIntent(group: group, name: name)) { label }.buttonStyle(.plain))
                }
                 
                 
                return label
            },
            refresh: { label in AnyView(Button(intent: ClashWidgetRefreshIntent()) { label }.buttonStyle(.plain)) },
            accent: { AnyView($0.widgetAccentable()) },
            needsSetup: !entry.tunnelControllable
        )
    }

    static func size(for family: WidgetFamily) -> ClashWidgetSize {
        switch family {
        case .systemSmall: return .small
        case .systemLarge, .systemExtraLarge: return .large
        default: return .medium
        }
    }
}

struct ClashWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.locale) private var locale
    let entry: ClashWidgetEntry

    var body: some View {
        let size = ClashWidgetSlotFactory.size(for: family)
        let slots = ClashWidgetSlotFactory.slots(for: entry)
        Group {
             
             
             
            switch size == .large ? .status : entry.style {
            case .status:
                ClashWidgetMainView(
                    snapshot: entry.snapshot, facts: entry.facts, now: entry.date, locale: locale,
                    size: size, slots: slots, configuredMode: entry.storedMode,
                     
                    countsWiredByDefault: ClashWidgetPlatform.countsWired,
                    throughputUnit: entry.throughputUnit,
                    notice: entry.notice
                )
            case .group:
                ClashWidgetGroupView(snapshot: entry.snapshot, facts: entry.facts, group: entry.group, now: entry.date, size: size, slots: slots)
            case .stats:
                ClashWidgetStatsView(
                    snapshot: entry.snapshot, now: entry.date, locale: locale, size: size,
                    throughputUnit: entry.throughputUnit
                )
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(ClashSystemRoute.open(entry.style == .group ? .proxies : .home).url)
    }
}

struct ClashMainWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: ClashWidgetMailbox.Kind.main,
            intent: ClashWidgetConfigurationIntent.self,
            provider: ClashWidgetProvider()
        ) { entry in
            ClashWidgetView(entry: entry)
        }
        .configurationDisplayName(Text(clash: .copy("Widget: Clash")))
        .description(Text(clash: .copy("Status and the switch, a proxy group, or network stats — choose in Edit Widget.")))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
