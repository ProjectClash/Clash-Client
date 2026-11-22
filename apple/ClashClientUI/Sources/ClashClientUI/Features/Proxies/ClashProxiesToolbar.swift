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
     
     
     
     
    let collectsIntoMore: Bool
     
    let onAddNodes: (() -> Void)?
     
    let onUpdateNodeSources: (() -> Void)?
     
    let onReorderGroups: (() -> Void)?
     
    let addItems: [ClashProxiesAddItem]
    let onAdd: (ClashProxiesAddItem) -> Void
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
        collectsIntoMore: Bool = false,
        onAddNodes: (() -> Void)? = nil,
        onUpdateNodeSources: (() -> Void)? = nil,
        onReorderGroups: (() -> Void)? = nil,
        addItems: [ClashProxiesAddItem] = [],
        onAdd: @escaping (ClashProxiesAddItem) -> Void = { _ in },
        @ViewBuilder icon: @escaping (ClashSymbol) -> Icon
    ) {
        self.addItems = addItems
        self.onAdd = onAdd
        self.collectsIntoMore = collectsIntoMore
        self.onAddNodes = onAddNodes
        self.onUpdateNodeSources = onUpdateNodeSources
        self.onReorderGroups = onReorderGroups
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
                if collectsIntoMore {
                    configurationControls
                } else {
                    legacyControls
                     
                     
                    if !addItems.isEmpty { addMenu }
                    if onUpdateNodeSources != nil || onReorderGroups != nil { moreMenu }
                }
            }
            .clashReaderControlGroupStyle()
        }
    }

     
     
     
    @ViewBuilder
    private var configurationControls: some View {
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
        if let onAddNodes {
            Button {
                onAddNodes()
            } label: {
                icon(.plus)
                    .clashToolbarGlyph()
            }
            .clashToolbarCapsuleEnd(sweepLivesHere ? [] : .leading)
            .accessibilityLabel("Add Nodes")
            .accessibilityIdentifier("proxies.addNodes")

            ClashToolbarDivider()
        }
         
         
         
        Menu {
            moreMenuItems
        } label: {
            Label {
                Text(ClashCopy.key("More"))
            } icon: {
                icon(.ellipsis)
            }
        }
        .clashToolbarGlyph()
        .clashToolbarCapsuleEnd(sweepLivesHere || onAddNodes != nil ? .trailing : [.leading, .trailing])
        .accessibilityIdentifier("proxies.more")
    }

     
     
    @ViewBuilder
    private var moreMenuItems: some View {
        let items = ClashProxiesMoreMenu.items(canRefreshCatalog: canRefreshCatalog,
                                               updatesNodeSources: onUpdateNodeSources != nil,
                                               reordersGroups: onReorderGroups != nil)
        if items.contains(.updateNodeSources), let onUpdateNodeSources {
            Section {
                Button(action: onUpdateNodeSources) {
                    Label(ClashCopy.key("Update Node Sources"), systemImage: ClashSymbol.arrowClockwise.rawValue)
                }
                .accessibilityIdentifier("proxies.updateNodeSources")
            }
        }
        if items.contains(.reorderGroups), let onReorderGroups {
            Button(action: onReorderGroups) {
                Label(ClashCopy.key("Reorder Policy Groups"), systemImage: "arrow.up.arrow.down")
            }
            .accessibilityIdentifier("proxies.reorderGroups")
        }
         
         
         
         
         
        Button(action: onToggleFold) {
            Label(ClashCopy.key(hasExpandedGroups ? "Collapse All Groups" : "Expand Last Group"),
                  systemImage: (hasExpandedGroups ? ClashSymbol.arrowUpRightAndArrowDownLeft
                                : ClashSymbol.arrowDownLeftAndArrowUpRight).rawValue)
        }
        .accessibilityIdentifier("proxies.toggleAllGroups")
        Button(action: onShowDisplayOptions) {
            Label(ClashCopy.key("Display Options"), systemImage: ClashSymbol.sliderHorizontal3.rawValue)
        }
        .accessibilityIdentifier("proxies.display.options")
        if items.contains(.refresh) {
            Section {
                Button(action: onRefresh) {
                    Label(ClashCopy.key("Refresh Proxies"), systemImage: ClashSymbol.arrowClockwise.rawValue)
                }
                 
                 
                .disabled(refreshDisabled || isTestingLatency)
                .accessibilityIdentifier("proxies.refresh")
            }
        }
    }

     
    private var addMenu: some View {
        Menu {
            ForEach(addItems, id: \.self) { item in
                Button { onAdd(item) } label: { Text(clash: item.title) }
            }
        } label: {
            Label { Text(clash: .copy("Add")) } icon: { icon(.plus) }
        }
        .help(Text(clash: .copy("Add")))
        .accessibilityIdentifier("proxies.toolbar.add")
    }

     
     
    private var moreMenu: some View {
        Menu {
            if let onUpdateNodeSources {
                Button(action: onUpdateNodeSources) { Text(clash: .copy("Update Node Sources")) }
            }
            if let onReorderGroups {
                Button(action: onReorderGroups) { Text(clash: .copy("Reorder Policy Groups")) }
            }
        } label: {
            Label { Text(clash: .copy("More")) } icon: { icon(.ellipsisCircle) }
        }
        .help(Text(clash: .copy("More")))
        .accessibilityIdentifier("proxies.toolbar.more")
    }

    @ViewBuilder
    private var legacyControls: some View {
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

 
 
 
 
public enum ClashProxiesMoreMenu {
    public enum Item: Equatable, Sendable {
        case updateNodeSources, reorderGroups, toggleFold, displayOptions, refresh
    }

    public static func items(canRefreshCatalog: Bool, updatesNodeSources: Bool, reordersGroups: Bool = false) -> [Item] {
        var items: [Item] = []
        if updatesNodeSources { items.append(.updateNodeSources) }
        if reordersGroups { items.append(.reorderGroups) }
        items += [.toggleFold, .displayOptions]
        if canRefreshCatalog { items.append(.refresh) }
        return items
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
