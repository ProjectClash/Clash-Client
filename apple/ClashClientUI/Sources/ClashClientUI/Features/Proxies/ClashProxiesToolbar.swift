import Combine
import SwiftUI

 
 
 
 
 
 
 
 
 
public struct ClashProxiesToolbar<Icon: View>: ToolbarContent {
    let showsDismissControl: Bool
    let hasExpandedGroups: Bool
    let canRefreshCatalog: Bool
    let refreshDisabled: Bool
    @Binding var preferences: ClashProxiesDisplayPreferences
    let onDismiss: () -> Void
    let onToggleFold: () -> Void
    let onRefresh: () -> Void
    let onShowDisplayOptions: () -> Void
     
     
    let isTestingLatency: Bool
    let sweepDisabled: Bool
    let sweepCompleted: Int
    let sweepTotal: Int
    let sweepPulse: AnyPublisher<ClashLatencyPulse, Never>?
    let onSweepStart: (() -> Void)?
    let onSweepCancel: (() -> Void)?
    let icon: (ClashSymbol) -> Icon

    public init(
        showsDismissControl: Bool,
        hasExpandedGroups: Bool,
        canRefreshCatalog: Bool,
        refreshDisabled: Bool,
        preferences: Binding<ClashProxiesDisplayPreferences>,
        onDismiss: @escaping () -> Void,
        onToggleFold: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        onShowDisplayOptions: @escaping () -> Void,
        isTestingLatency: Bool = false,
        sweepDisabled: Bool = false,
        sweepCompleted: Int = 0,
        sweepTotal: Int = 0,
        sweepPulse: AnyPublisher<ClashLatencyPulse, Never>? = nil,
        onSweepStart: (() -> Void)? = nil,
        onSweepCancel: (() -> Void)? = nil,
        @ViewBuilder icon: @escaping (ClashSymbol) -> Icon
    ) {
        self.showsDismissControl = showsDismissControl
        self.hasExpandedGroups = hasExpandedGroups
        self.canRefreshCatalog = canRefreshCatalog
        self.refreshDisabled = refreshDisabled
        self._preferences = preferences
        self.onDismiss = onDismiss
        self.onToggleFold = onToggleFold
        self.onRefresh = onRefresh
        self.onShowDisplayOptions = onShowDisplayOptions
        self.isTestingLatency = isTestingLatency
        self.sweepDisabled = sweepDisabled
        self.sweepCompleted = sweepCompleted
        self.sweepTotal = sweepTotal
        self.sweepPulse = sweepPulse
        self.onSweepStart = onSweepStart
        self.onSweepCancel = onSweepCancel
        self.icon = icon
    }

     
    private var sweepLivesHere: Bool {
        onSweepStart != nil && onSweepCancel != nil
            && ClashPlatformLayout.proxiesSweepLivesInToolbar
    }

    public var body: some ToolbarContent {
         
         
         
         
        ToolbarItem(placement: .cancellationAction) {
            if showsDismissControl {
                ClashSheetCloseButton {
                    onDismiss()
                }
            }
        }

         
         
         
         
         
        ToolbarItem(placement: .primaryAction) {
            ControlGroup {
                if let onSweepStart, let onSweepCancel,
                   ClashPlatformLayout.proxiesSweepLivesInToolbar {
                     
                    ClashSweepToolbarButton(
                        initialIsTesting: isTestingLatency,
                        initialCompleted: sweepCompleted,
                        initialTotal: sweepTotal,
                        disabled: sweepDisabled,
                        pulse: sweepPulse,
                        onStart: onSweepStart,
                        onCancel: onSweepCancel,
                        icon: icon
                    )
                    .clashToolbarCapsuleEnd(.leading)

                    ClashToolbarDivider()
                }

                 
                 
                 
                 
                 
                Button {
                    onToggleFold()
                } label: {
                    icon(
                        hasExpandedGroups
                            ? .arrowUpRightAndArrowDownLeft
                            : .arrowDownLeftAndArrowUpRight
                    )
                    .clashToolbarGlyph()
                }
                 
                .clashToolbarCapsuleEnd(sweepLivesHere ? [] : .leading)
                .accessibilityLabel(
                     
                     
                     
                     
                     
                    hasExpandedGroups
                        ? "Collapse All Groups"
                        : "Expand Last Group"
                )
                .accessibilityIdentifier("proxies.toggleAllGroups")

                 
                 
                 
                 
                 
                ClashToolbarDivider()

                if canRefreshCatalog {
                    ClashRefreshToolbarButton(
                        heldByHost: refreshDisabled,
                        initialIsTesting: isTestingLatency,
                        pulse: sweepPulse,
                        onRefresh: onRefresh,
                        icon: icon
                    )

                    ClashToolbarDivider()
                }

                 
                if ClashPlatformLayout.immediateDisplayOptionsUseMenu {
                    Menu {
                        displayOptionsMenu
                    } label: {
                        icon(.sliderHorizontal3)
                            .clashToolbarGlyph()
                            .clashToolbarCapsuleEnd(.trailing)
                    }
                    .accessibilityLabel("Display Options")
                    .accessibilityIdentifier("proxies.display.options")
                     
                     
                     
                     
                     
                    .id(preferences.menuIdentity)
                } else {
                    Button {
                        onShowDisplayOptions()
                    } label: {
                        icon(.sliderHorizontal3)
                            .clashToolbarGlyph()
                            .clashToolbarCapsuleEnd(.trailing)
                    }
                    .accessibilityLabel("Display Options")
                    .accessibilityIdentifier("proxies.display.options")
                }
            }
            .clashReaderControlGroupStyle()
        }
    }

    @ViewBuilder
    private var displayOptionsMenu: some View {
         
         
         
         
        Picker("Icons", selection: $preferences.groupIconImages) {
            Text("Off").tag(false)
            Text("Show").tag(true)
        }
        .accessibilityIdentifier("proxies.display.groupIconImages")

        Picker("Style", selection: $preferences.style) {
            Text("List").tag(ClashProxiesDisplayPreferences.Style.list)
            Text("Tabs").tag(ClashProxiesDisplayPreferences.Style.tabs)
        }

        Picker("Sort", selection: $preferences.sort) {
            Text("Default").tag(ClashProxiesDisplayPreferences.Sort.standard)
            Text("Delay").tag(ClashProxiesDisplayPreferences.Sort.delay)
            Text("Name").tag(ClashProxiesDisplayPreferences.Sort.name)
        }
            .accessibilityIdentifier("proxies.display.sort")

        Picker("Layout", selection: $preferences.layout) {
            Text("Loose").tag(ClashProxiesDisplayPreferences.Layout.loose)
            Text("Compact").tag(ClashProxiesDisplayPreferences.Layout.compact)
        }
            .accessibilityIdentifier("proxies.display.layout")

        Picker("Size", selection: $preferences.size) {
            Text("Standard").tag(ClashProxiesDisplayPreferences.Size.standard)
            Text("Compact").tag(ClashProxiesDisplayPreferences.Size.compact)
            Text("Minimal").tag(ClashProxiesDisplayPreferences.Size.minimal)
        }
            .accessibilityIdentifier("proxies.display.size")
    }
}

extension ClashProxiesDisplayPreferences {
     
     
     
     
     
    var menuIdentity: String {
        "\(style.rawValue)|\(sort.rawValue)|\(layout.rawValue)|\(size.rawValue)|\(groupIconImages)"
    }
}

 
 
 
 
 
 
private struct ClashRefreshToolbarButton<Icon: View>: View {
    let heldByHost: Bool
    let initialIsTesting: Bool
    let pulse: AnyPublisher<ClashLatencyPulse, Never>?
    let onRefresh: () -> Void
    let icon: (ClashSymbol) -> Icon

    @State private var isTesting: Bool?

    var body: some View {
        Button {
            onRefresh()
        } label: {
            icon(.arrowClockwise)
                .clashToolbarGlyph()
        }
        .disabled(heldByHost || (isTesting ?? initialIsTesting))
        .accessibilityLabel("Refresh Proxies")
        .accessibilityIdentifier("proxies.refresh")
        .onReceive(pulse ?? Empty<ClashLatencyPulse, Never>().eraseToAnyPublisher()) { batch in
            if isTesting != batch.isTesting { isTesting = batch.isTesting }
        }
    }
}

 
 
 
 
 
 
 
 
 
private struct ClashSweepToolbarButton<Icon: View>: View {
    let initialIsTesting: Bool
    let initialCompleted: Int
    let initialTotal: Int
    let disabled: Bool
    let pulse: AnyPublisher<ClashLatencyPulse, Never>?
    let onStart: () -> Void
    let onCancel: () -> Void
    let icon: (ClashSymbol) -> Icon

    @State private var isTesting: Bool?
    @State private var completed: Int?
    @State private var total: Int?

    private var showsTesting: Bool { isTesting ?? initialIsTesting }

    var body: some View {
        Button {
            if showsTesting {
                onCancel()
                 
                 
                 
                isTesting = false
            } else {
                onStart()
                isTesting = true
                completed = 0
                total = nil
            }
        } label: {
            if showsTesting {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                    if let total, total > 0 {
                        Text(clash: .verbatim("\(completed ?? 0)/\(total)"))
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                icon(.bolt)
                    .clashToolbarGlyph()
            }
        }
        .disabled(disabled)
        .accessibilityLabel(showsTesting ? "Cancel" : "Test All")
        .accessibilityIdentifier(
            showsTesting ? "proxies.testAll.cancel" : "proxies.testAll"
        )
        .onReceive(
            pulse ?? Empty<ClashLatencyPulse, Never>().eraseToAnyPublisher()
        ) { batch in
            isTesting = batch.isTesting
            completed = batch.completed
            total = batch.total
        }
    }
}
