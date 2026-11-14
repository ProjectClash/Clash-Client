import Combine
import Foundation
import SwiftUI

 
 
 
 
 
 
 
struct ClashProxyAccordionRow: Identifiable {
    enum Kind: Equatable {
        case groupHeader
        case ungroupedHeader
        case memberSlice
        case showAll
        case divider
    }

    let id: String
    let kind: Kind
    let group: ClashProxyGroupSnapshot?
     
     
     
    let members: [ClashProxyMemberSnapshot]
    let range: Range<Int>?
    let revealKey: String?
    let totalCount: Int
}

 
 
 
 
 
 
 
 
enum ClashProxyMemberSlicePlan {
    static let chunkSize = 8

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func chunkSize(columns: Int) -> Int {
         
         
         
        if let fixed = ClashPlatformLayout.columnStableSliceLength {
            return fixed
        }
        let columns = max(columns, 1)
        let rows = max(Int((Double(chunkSize) / Double(columns)).rounded(.up)), 1)
        return rows * columns
    }

    static func make(count: Int, columns: Int = 1) -> [Range<Int>] {
        guard count > 0 else { return [] }
        let stripe = chunkSize(columns: columns)
        return stride(from: 0, to: count, by: stripe).map { start in
            start..<min(start + stripe, count)
        }
    }

     
     
    static func rowAnchor(slice: String, row: Int) -> String {
        "\(slice).row.\(row)"
    }
}

 
 
 
 
 
 
 
 
 
 
struct ClashProxyLocatePlan: Equatable {
     
    let slice: String
     
    let row: Int
     
     
     
    let offset: Int
     
    let anchor: String
    let revealsAll: Bool
     
     
    let awaitsWhole: Bool

     
     
     
    static let wait: TimeInterval = 10

    static func make(group: String, ordered: [String], selection: String?, isRevealed: Bool,
                     carriesSelection: Bool = false, renderCap: Int, columns: Int) -> Self? {
        guard let selection, let position = ordered.firstIndex(of: selection) else { return nil }
        let revealsAll = !isRevealed && (position >= renderCap || carriesSelection)
        let shown = isRevealed || revealsAll ? ordered.count : min(ordered.count, renderCap)
        guard let range = ClashProxyMemberSlicePlan.make(count: shown, columns: columns)
            .first(where: { $0.contains(position) }) else { return nil }
        let slice = "group.\(group).members.\(range.lowerBound)"
        let row = (position - range.lowerBound) / max(columns, 1)
        return Self(slice: slice, row: row, offset: position - range.lowerBound,
                    anchor: ClashProxyMemberSlicePlan.rowAnchor(slice: slice, row: row),
                    revealsAll: revealsAll, awaitsWhole: carriesSelection)
    }
}

enum ClashProxyAccordionPlan {

    static func make(
        groups: [ClashProxyGroupSnapshot],
        ungrouped: [ClashProxySnapshot],
        expanded: Set<String>,
        isSearching: Bool,
        revealedFullGroups: Set<String>,
         
         
         
        columns: Int = 1,
        renderCap: Int,
        memberOrder: (ClashProxyGroupSnapshot) -> [ClashProxyMemberSnapshot] = {
            $0.members
        }
    ) -> [ClashProxyAccordionRow] {
        var rows: [ClashProxyAccordionRow] = []
        rows.reserveCapacity(groups.count * 2 + 20)

        for (index, group) in groups.enumerated() {
            rows.append(
                ClashProxyAccordionRow(
                    id: "group.\(group.name)",
                    kind: .groupHeader,
                    group: group,
                    members: [],
                    range: nil,
                    revealKey: nil,
                    totalCount: group.memberCount
                )
            )
            if ClashProxyBrowsing.showsMembers(
                of: group.name,
                expanded: expanded,
                isSearching: isSearching
            ) {
                let orderedMembers = memberOrder(group)
                appendMemberRows(
                    group: group,
                    members: orderedMembers,
                    revealKey: group.name,
                    memberCount: orderedMembers.count,
                    revealedFullGroups: revealedFullGroups,
                    renderCap: renderCap,
                    columns: columns,
                    rows: &rows
                )
            }
            if index != groups.count - 1 || !ungrouped.isEmpty {
                rows.append(
                    ClashProxyAccordionRow(
                        id: "group.\(group.name).divider",
                        kind: .divider,
                        group: nil,
                        members: [],
                        range: nil,
                        revealKey: nil,
                        totalCount: 0
                    )
                )
            }
        }

        if !ungrouped.isEmpty {
            let members = ungrouped.map {
                ClashProxyMemberSnapshot(name: $0.name, type: $0.type)
            }
            rows.append(
                ClashProxyAccordionRow(
                    id: "group.ungrouped",
                    kind: .ungroupedHeader,
                    group: nil,
                    members: members,
                    range: nil,
                    revealKey: nil,
                    totalCount: members.count
                )
            )
            if ClashProxyBrowsing.showsMembers(
                of: ClashProxyBrowsing.ungroupedKey,
                expanded: expanded,
                isSearching: isSearching
            ) {
                appendMemberRows(
                    group: nil,
                    members: members,
                    revealKey: ClashProxyBrowsing.ungroupedKey,
                    memberCount: members.count,
                    revealedFullGroups: revealedFullGroups,
                    renderCap: renderCap,
                    columns: columns,
                    rows: &rows
                )
            }
        }
        return rows
    }

    private static func appendMemberRows(
        group: ClashProxyGroupSnapshot?,
        members: [ClashProxyMemberSnapshot],
        revealKey: String,
        memberCount: Int,
        revealedFullGroups: Set<String>,
        renderCap: Int,
        columns: Int,
        rows: inout [ClashProxyAccordionRow]
    ) {
         
         
        let partial = group.map { !$0.hasEveryMember } ?? false
        let capped = !revealedFullGroups.contains(revealKey)
            && memberCount > renderCap
        let shownCount = capped ? renderCap : memberCount
        for range in ClashProxyMemberSlicePlan.make(
            count: shownCount, columns: columns
        ) {
            let prefix = group.map { "group.\($0.name)" } ?? "group.ungrouped"
            let slice = Array(members[range])
            rows.append(
                ClashProxyAccordionRow(
                    id: "\(prefix).members.\(range.lowerBound)",
                    kind: .memberSlice,
                    group: group,
                    members: slice,
                    range: slice.indices,
                    revealKey: revealKey,
                    totalCount: memberCount
                )
            )
        }
        if capped || partial {
            let prefix = group.map { "group.\($0.name)" } ?? "group.ungrouped"
            rows.append(
                ClashProxyAccordionRow(
                    id: "\(prefix).show-all",
                    kind: .showAll,
                    group: group,
                    members: members,
                    range: nil,
                    revealKey: revealKey,
                    totalCount: group?.memberCount ?? memberCount
                )
            )
        }
    }
}

 
 
 
 
 
 
 
struct ProxyIndexPreparationKey: Equatable {
    let groups: [ClashProxyGroupSnapshot]
     
     
     
    let hiddenGroups: [ClashProxyGroupSnapshot]
     
     
     
     
     
     
    let latencyByName: [String: ClashProxyLatencyState]
    let isConnected: Bool
    let sort: ClashProxiesDisplayPreferences.Sort
     
     
     
     
    let orderingGroupNames: Set<String>

    init(
        proxies: ClashProxiesSnapshot,
        sort: ClashProxiesDisplayPreferences.Sort,
        orderingGroupNames: Set<String>
    ) {
        groups = proxies.groups
        hiddenGroups = proxies.hiddenGroups
        latencyByName = sort == .delay ? proxies.latencyByName : [:]
        isConnected = proxies.isConnected
        self.sort = sort
        self.orderingGroupNames = orderingGroupNames
    }
}

@MainActor
private enum ProxyIndexPreparationCache {
    static let shared = ClashLastPreparation<
        ProxyIndexPreparationKey,
        ProxyDerivedIndex
    >()
}

 
 
 
 
 
 
public struct ClashProxiesView<Icon: View>: View, Equatable {

     
     
     
     
     
     
    nonisolated public static func == (a: Self, b: Self) -> Bool {
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        let p = a.snapshot.proxies, q = b.snapshot.proxies
        let dataEqual = p.groups == q.groups
            && p.hiddenGroups == q.hiddenGroups
            && p.searchableProxies == q.searchableProxies
            && p.providers == q.providers
            && p.ungrouped == q.ungrouped
             
             
             
             
             
             
             
             
             
             
             
             
             
             
            && (!Self.ordersByLatency(p) || p.latencyByName == q.latencyByName)
        let sweepEqual = p.isConnected == q.isConnected
             
             
            && p.liveCatalog == q.liveCatalog
        let chromeEqual = p.displayPreferences == q.displayPreferences
            && p.catalogState == q.catalogState
            && p.canRefreshCatalog == q.canRefreshCatalog
            && p.canUnpinGroups == q.canUnpinGroups
             
             
             
             
             
            && p.browsingSuppressedByDirectMode == q.browsingSuppressedByDirectMode
         
         
         
         
         
         
        let cardsEqual = p.actionRefusals == q.actionRefusals
            && p.editableMembers == q.editableMembers
            && p.scriptsForNodes == q.scriptsForNodes
            && p.failureCategories == q.failureCategories
        let equal = dataEqual && sweepEqual && chromeEqual && cardsEqual
            && a.presentationClass == b.presentationClass
            && a.showsDismissControl == b.showsDismissControl
         
         
         
         
         
         
         
         
         
         
         
        Task { @MainActor in
            ClashPerf.count(equal ? "proxies.eq.hit" : "proxies.eq.miss")
            if !equal {
                let field: String
                if p.groups != q.groups { field = "groups" }
                else if p.searchableProxies != q.searchableProxies { field = "searchable" }
                else if p.providers != q.providers { field = "providers" }
                else if p.ungrouped != q.ungrouped { field = "ungrouped" }
                else if Self.ordersByLatency(p), p.latencyByName != q.latencyByName { field = "latency" }
                else if p.isConnected != q.isConnected { field = "connected" }
                else if p.liveCatalog != q.liveCatalog { field = "live-catalog" }
                else if p.displayPreferences != q.displayPreferences { field = "prefs" }
                else if p.catalogState != q.catalogState { field = "catalog-state" }
                else if p.canRefreshCatalog != q.canRefreshCatalog { field = "can-refresh" }
                else if p.canUnpinGroups != q.canUnpinGroups { field = "can-unpin" }
                else if p.actionRefusals != q.actionRefusals { field = "refusals" }
                else if p.failureCategories != q.failureCategories { field = "failure-categories" }
                else { field = "other" }
                ClashPerf.count("proxies.eq.miss." + field)
            }
        }
        return equal
    }

     
     
    nonisolated static func ordersByLatency(_ p: ClashProxiesSnapshot) -> Bool {
        p.displayPreferences.sort == .delay
    }

    private let snapshot: AppleClientSnapshot
    private let actions: AppleClientActions
    private let presentationClass: ClashPresentationClass
    private let searchPlacement: SearchFieldPlacement
    private let palette: ClashProductPalette
    private let showsDismissControl: Bool
     
     
     
     
     
     
     
     
    private let latencyPulseSource: AnyPublisher<ClashLatencyPulse, Never>?

     
     
     
     
    private var latencyPulse: AnyPublisher<ClashLatencyPulse, Never>? {
         
         
         
        latencyPulseSource
    }

    @State private var pulseGate = ClashLatencyPulseGate()
    @Environment(\.clashLatencyPulseGate) private var injectedPulseGate

     
     
    private var activePulseGate: ClashLatencyPulseGate {
        injectedPulseGate ?? pulseGate
    }
     
     
     
     
    private let latencyPulseSnapshot: (() -> ClashLatencyPulse)?
    private let icon: (ClashSymbol) -> Icon

    @Environment(\.dismiss) private var dismiss
    @Environment(\.clashScrollToID) private var scrollToID
     
     
    @State private var pageScroll = ClashProxiesPageScroll()
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
     
     
     
     
     
    @Environment(\.clashRegularRootSearchText) private var externalSearchText
    @Environment(\.clashRegularRootFoldCommand) private var foldCommand
    @Environment(\.clashRegularRootFoldStateSink) private var foldStateSink
    @Environment(\.clashRegularRootOpenGroup) private var openGroupSignal
    @Environment(\.clashRegularRootDisplayPreferences) private var displaySignal
    @State private var query = ""
     
     
     
     
    @State private var index = ProxyDerivedIndex.empty
     
     
     
     
     
    @State private var expandedProvider: String?
     
     
     
     
     
     
     
     
    @State private var gridColumnCount = 2
    @State private var expanded: Set<String> = []
     
     
     
     
     
    @State private var entryRoutine = ClashEntryRoutineBox()
     
     
     
     
     
    @State private var identityStamp = UUID()

     
     
     
    @State private var lastExpandedGroup: String?
     
     
    @State private var revealedFullGroups: Set<String> = []
     
     
    @State private var locateMarker: ClashProxyLocatePlan?
     
     
    @State private var locateAwaitedGroup: String?
    @State private var locateAwaitedSince: Date?
    @State private var preferences: ClashProxiesDisplayPreferences
    @State private var showsDisplayOptions = false
     
     
     
     
    @State private var displayOptionsDraft = ClashProxiesDisplayDraftBox()
     
     
    @State private var pendingDisplayPreferences:
        ClashProxiesDisplayPreferences?
    @State private var selectedTab: String?
    @State private var offlineSelections: [String: String] = [:]
     
    @State private var choiceRefusal: ClashProxyChoiceRefusal?

    @MainActor
    public init(
        snapshot: AppleClientSnapshot,
        actions: AppleClientActions,
        presentationClass: ClashPresentationClass,
        searchPlacement: SearchFieldPlacement = .automatic,
        palette: ClashProductPalette,
        showsDismissControl: Bool = true,
        latencyPulse: AnyPublisher<ClashLatencyPulse, Never>? = nil,
        latencyPulseSnapshot: (() -> ClashLatencyPulse)? = nil,
        @ViewBuilder icon: @escaping (ClashSymbol) -> Icon
    ) {
        self.snapshot = snapshot
        self.actions = actions
        self.presentationClass = presentationClass
        self.searchPlacement = searchPlacement
        self.palette = palette
        self.showsDismissControl = showsDismissControl
        self.latencyPulseSource = latencyPulse
        self.latencyPulseSnapshot = latencyPulseSnapshot
        self.icon = icon
        let initialPreferences = snapshot.proxies.displayPreferences
        let initialExpanded = ClashProxyBrowsing.groupsToOpenOnEntry(
             
             
             
             
            remembered: [],
            destination: snapshot.proxies.initiallyExpandedGroup
        )
        let initialOrderingGroupNames = Self.orderingGroupNames(
            groups: snapshot.proxies.groups,
            preferences: initialPreferences,
            expanded: initialExpanded,
            isSearching: false,
            selectedTab: nil,
            liveCatalog: snapshot.proxies.liveCatalog ?? false
        )
        _preferences = State(initialValue: initialPreferences)
        _index = State(
            initialValue: ProxyIndexPreparationCache.shared.value(
                for: ProxyIndexPreparationKey(
                    proxies: snapshot.proxies,
                    sort: initialPreferences.sort,
                    orderingGroupNames: initialOrderingGroupNames
                )
            ) ?? .empty
        )
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        _expanded = State(initialValue: initialExpanded)
    }

    @Environment(\.clashHostedInRootPool) private var hostedInRootPool

    public var body: some View {
         
         
         
         
         
        let _ = ClashPerf.count(
            hostedInRootPool ? "proxies.body.pool" : "proxies.body.free"
        )
         
         
         
         
         
         
         
         
         
         
         
        if externalSearchText == nil {
            chromed
        } else {
            undecorated
        }
    }

    private var chromed: some View {
        undecorated
            .searchable(
                text: $query,
                placement: searchPlacement,
                prompt: Text("Search proxies")
            )
            .clashToolbarUnlessInPanel { toolbarContent }
    }

    private var undecorated: some View {
        root
            .clashContentHeading("Proxies")
            .background(partialGroupSearch)
            .clashSheet(
                isPresented: $showsDisplayOptions,
                onDismiss: commitDisplayOptions
            ) {
                ClashProxiesDisplayOptionsView(
                    preferences: displayOptionsDraft.value,
                    palette: palette,
                    onDraftChange: { value in
                        displayOptionsDraft.value = value
                    }
                )
                .clashModalPresentation(.form)
            }
            .onAppear {
                applyInitialDestination()
            }
            .task(id: ProxyIndexPreparationKey(
                proxies: snapshot.proxies,
                sort: preferences.sort,
                orderingGroupNames: orderingGroupNames
            )) {
                await prepareIndex()
            }
            .task(id: DisplayCommitKey(
                value: pendingDisplayPreferences,
                canCommit: activePulseGate.isOpen
            )) {
                 
                 
                 
                 
                 
                if let pendingDisplayPreferences {
                    await prepareDisplayPreferences(pendingDisplayPreferences)
                }
            }
            .onChange(of: preferences.groupIconImages) { on in
                 
                 
                 
                 
                guard on else { return }
                Task { await ProxyGroupIconStore.shared.forgetRefusals() }
            }
            .onChange(of: preferences) { value in
                ClashPerf.markDisplayPreferencesChange()
                send(.setDisplayPreferences(value))
            }
            .onChange(of: snapshot.proxies.displayPreferences) { value in
                if preferences != value {
                    preferences = value
                }
            }
            .onDisappear {
                 
                 
                 
                 
                 
                 
                 
                 
                 
                ClashPerf.mark("proxies page disappears")
                send(.cancelLatency)
            }
            .onChange(of: visibleGroupNames) { _ in
                keepOneGroupOpen()
            }
            .onAppear {
                keepOneGroupOpen()
            }
            .onChange(of: foldCommand) { _ in
                 
                 
                 
                 
                toggleAllGroups()
            }
            .onChange(of: displaySignal) { signal in
                 
                 
                 
                 
                guard let value = signal.preferences else { return }
                applyDisplayPreferences(value)
            }
            .onChange(of: openGroupSignal) { signal in
                 
                 
                 
                 
                 
                 
                guard let name = signal.group else { return }
                expanded = [name]
                if selectedTab != name {
                    selectedTab = name
                }
                send(.setVisibleGroup(name: name))
                scrollToGroup(name)
            }
            .onChange(of: hasExpandedGroups) { value in
                foldStateSink?(value)
            }
            .onAppear {
                foldStateSink?(hasExpandedGroups)
            }
            .accessibilityIdentifier("proxies.overview")
             
             
             
             
            .clashFrameWatch("proxies-page")
            .environment(\.clashDetailCanvas, palette.canvas)
    }

     
     
     
     
     
     
    @MainActor
    private func prepareIndex() async {
         
         
         
         
         
         
        guard activePulseGate.isOpen else { return }
        let proxies = snapshot.proxies
        let sort = preferences.sort
        let previous = index
        let groupNames = orderingGroupNames
        let key = ProxyIndexPreparationKey(
            proxies: proxies,
            sort: sort,
            orderingGroupNames: groupNames
        )
        let prepared = await ProxyIndexPreparationCache.shared.value(
            for: key
        ) {
            let began = DispatchTime.now().uptimeNanoseconds
            let value = await Task.detached(priority: .userInitiated) {
                ProxyDerivedIndex.build(
                    from: proxies,
                    sortedBy: sort,
                    reusing: previous,
                    freshDelayOrder: !proxies.isTestingLatency,
                    orderingGroupNames: groupNames
                )
            }.value
            ClashPerf.span(
                "proxies.index.prepare",
                milliseconds: Double(
                    DispatchTime.now().uptimeNanoseconds - began
                ) / 1_000_000,
                detail: "groups=\(proxies.groups.count) ordered=\(groupNames.count)"
            )
            return value
        }
        guard !Task.isCancelled,
              key == ProxyIndexPreparationKey(
                proxies: snapshot.proxies,
                sort: preferences.sort,
                orderingGroupNames: orderingGroupNames
              ) else { return }
        index = prepared
    }

     
     
     
     
     
    private var orderingGroupNames: Set<String> {
        Self.orderingGroupNames(
            groups: browsedGroups,
            preferences: preferences,
            expanded: expanded,
            isSearching: isSearching,
            selectedTab: selectedTab,
            liveCatalog: snapshot.proxies.liveCatalog ?? false
        )
    }

    static func orderingGroupNames(
        groups: [ClashProxyGroupSnapshot],
        preferences: ClashProxiesDisplayPreferences,
        expanded: Set<String>,
        isSearching: Bool,
        selectedTab: String?,
        liveCatalog: Bool = true,
        drawsTabs: Bool = ClashProxiesBrowserPlatform.drawsTabs
    ) -> Set<String> {
        if drawsTabs, preferences.style == .tabs {
            if let selectedTab,
               groups.contains(where: { $0.name == selectedTab }) {
                return [selectedTab]
            }
             
            return ClashProxyBrowsing.defaultTab(groups.map(\.name),
                                                 skipping: ClashProxyBrowsing.notOpenedUnasked(groups, liveCatalog: liveCatalog))
                .map { [$0] } ?? []
        }
        return Set(groups.lazy.filter {
            isSearching || expanded.contains($0.name)
        }.map(\.name))
    }

    private func applyDisplayPreferences(
        _ value: ClashProxiesDisplayPreferences
    ) {
        guard preferences != value else { return }
         
         
         
         
         
         
        pendingDisplayPreferences = value
    }

    private func beginDisplayOptions() {
        displayOptionsDraft.value = preferences
        showsDisplayOptions = true
    }

    private func commitDisplayOptions() {
        applyDisplayPreferences(displayOptionsDraft.value)
    }

    @MainActor
    private func prepareDisplayPreferences(
        _ value: ClashProxiesDisplayPreferences
    ) async {
         
         
        try? await Task.sleep(nanoseconds: 50_000_000)
        guard !Task.isCancelled,
              pendingDisplayPreferences == value else { return }

        let proxies = snapshot.proxies
        let groupNames = Self.orderingGroupNames(
            groups: browsedGroups,
            preferences: value,
            expanded: expanded,
            isSearching: isSearching,
            selectedTab: selectedTab,
            liveCatalog: snapshot.proxies.liveCatalog ?? false
        )
        let previous = index
        let key = ProxyIndexPreparationKey(
            proxies: proxies,
            sort: value.sort,
            orderingGroupNames: groupNames
        )
        let prepared = await ProxyIndexPreparationCache.shared.value(
            for: key
        ) {
            let began = DispatchTime.now().uptimeNanoseconds
            let prepared = await Task.detached(priority: .userInitiated) {
                ProxyDerivedIndex.build(
                    from: proxies,
                    sortedBy: value.sort,
                    reusing: previous,
                    freshDelayOrder: !proxies.isTestingLatency,
                    orderingGroupNames: groupNames
                )
            }.value
            ClashPerf.span(
                "proxies.display.prepare",
                milliseconds: Double(
                    DispatchTime.now().uptimeNanoseconds - began
                ) / 1_000_000,
                detail:
                    "groups=\(proxies.groups.count) ordered=\(groupNames.count) sort=\(value.sort.rawValue)"
            )
            return prepared
        }
        guard !Task.isCancelled,
              pendingDisplayPreferences == value else { return }
         
         
         
         
         
        guard activePulseGate.isOpen else { return }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
             
             
             
             
             
            #if !os(macOS)
            revealedFullGroups.removeAll()
            #endif
            index = prepared
            preferences = value
            pendingDisplayPreferences = nil
        }
         
         
         
         
         
         
         
    }

     
     
    private struct DisplayCommitKey: Equatable {
        let value: ClashProxiesDisplayPreferences?
        let canCommit: Bool
    }

    private var root: some View {
         
         
         
         
         
        ClashProxiesBrowserHost {
            ClashProxiesSystemList(
                snapshot: snapshot,
                palette: palette,
                send: { send($0) },
                expanded: $expanded,
                query: effectiveQuery,
                memberOrder: { group in
                    index.renderingMembers(
                        in: group,
                        for: snapshot.proxies,
                        sortedBy: preferences.sort
                    )
                },
                latencyPulse: latencyPulseSource,
                latencyPulseSnapshot: latencyPulseSnapshot,
                density: ClashProxiesRowDensity.from(preferences),
                showsIconImages: preferences.groupIconImages,
                icon: icon,
                index: index,
                sort: preferences.sort,
                expandedValue: expanded
            )
             
            .equatable()
            .accessibilityIdentifier("proxies.product.root")
        } legacy: {
            legacyRoot
        }
    }

    private var legacyRoot: some View {
        ClashProductRootPage(
            palette: palette,
            accessibilityIdentifier: "proxies.product.root",
             
             
             
             
             
             
            hostsSelfDrawnCards: true
        ) {
            if pendingDisplayPreferences != nil,
               ClashPlatformLayout.displayChangeSwapsToPlaceholder {
                ClashPageLoadingPlaceholder(title: .copy("Loading"))
                    .accessibilityIdentifier("proxies.display.applying")
            } else {
                catalogContent
                    .background(ClashProxiesPageScrollReader(scroll: pageScroll))
            }
        }
         
         
        .onChange(of: locateOnceWhole) { locateAgain($0) }
    }

    @ViewBuilder
    private var catalogContent: some View {
        switch snapshot.proxies.effectiveCatalogState {
            case .disconnected:
                catalogStateCard(
                    title: "Connect to View Proxies",
                    message:
                        "The active connection supplies the current groups, nodes, and selections.",
                    symbol: .serverRack
                )
            case .loading:
                catalogStateCard(
                    title: "Loading Proxies",
                    message:
                        "Reading the current proxy catalog.",
                    symbol: .serverRack,
                    isLoading: true
                )
            case .failed(let message):
                catalogStateCard(
                    title: "Proxies Unavailable",
                    message: message,
                    symbol: .exclamationmarkTriangle
                )
            case .ready:
                browserSections
        }
    }

    private func catalogStateCard(
        title: String,
        message: String,
        symbol: ClashSymbol,
        isLoading: Bool = false
    ) -> some View {
        ClashCardSurface(
            fill: palette.card,
            separator: palette.separator
        ) {
            ClashEmptyState(
                title: title,
                message: message,
                isLoading: isLoading
            ) {
                icon(symbol)
            }
        }
        .accessibilityIdentifier(
            isLoading ? "proxies.state.loading" : "proxies.state.empty"
        )
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
         
         
        ClashProxiesToolbar(
            showsDismissControl: showsDismissControl,
            hasExpandedGroups: hasExpandedGroups,
            canRefreshCatalog: snapshot.proxies.canRefreshCatalog == true,
             
             
            refreshDisabled: snapshot.proxies.effectiveCatalogState == .loading,
            preferences: $preferences,
            onDismiss: { dismiss() },
            onToggleFold: { toggleAllGroups() },
            onRefresh: { send(.refresh) },
            onShowDisplayOptions: beginDisplayOptions,
            isTestingLatency: snapshot.proxies.isTestingLatency,
            sweepDisabled: !snapshot.proxies.isConnected,
            sweepCompleted: snapshot.proxies.latencyCompletedCount,
            sweepTotal: snapshot.proxies.latencyTotalCount,
            sweepPulse: latencyPulseSource,
            onSweepStart: {
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                if isSearching {
                    send(.testShown(snapshot.proxies.shownMembers(matching: effectiveQuery)))
                } else {
                    send(.testAll(
                        visibleGroupNames: browsedGroups.map(\.name)
                    ))
                }
            },
            onSweepCancel: { send(.cancelLatency) },
            icon: icon
        )
    }

     
     
    private var effectiveQuery: String {
        externalSearchText ?? query
    }

     
     
     
     
     
    private var partialGroupSearch: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task(id: effectiveQuery) {
                let query = effectiveQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty, snapshot.proxies.groups.contains(where: { !$0.hasEveryMember }) else { return }
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                send(.searchMembers(query: query))
            }
    }

    private var browsedGroups: [ClashProxyGroupSnapshot] {
        snapshot.proxies.groups(matching: effectiveQuery)
    }

    private var browsedUngrouped: [ClashProxySnapshot] {
        snapshot.proxies.ungroupedNodes(matching: effectiveQuery)
    }

    private var isSearching: Bool {
        !effectiveQuery
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var browserSections: some View {
        if !failedProviders.isEmpty {
            failedProvidersCard
        }
        if !browsedGroups.isEmpty {
            groupsCard
        } else if snapshot.proxies.browsingSuppressedByDirectMode {
             
             
             
             
            directModeCard
        } else if snapshot.proxies.showsOnlyUngroupedNodes(
            matching: effectiveQuery
        ) {
             
             
            nodesCard
        } else if isSearching {
            noMatchesCard
        } else if snapshot.proxies.providers.isEmpty {
            emptyCard
        }

        if !snapshot.proxies.providers.isEmpty {
            providersCard
        }
    }

    @ViewBuilder
    private var groupsCard: some View {
         
         
         
         
        ClashProductGroup(
            groupsTitle,
            palette: palette,
            trailing: { testAllButton }
        ) {
            VStack(alignment: .leading, spacing: ClashTheme.Spacing.standard) {
                if preferences.style == .tabs {
                    tabsBody
                } else {
                     
                     
                     
                     
                     
                     
                     
                    let rows = ClashProxyAccordionPlan.make(
                        groups: browsedGroups,
                        ungrouped: browsedUngrouped,
                        expanded: expanded,
                        isSearching: isSearching,
                        revealedFullGroups: revealedFullGroups,
                        columns: gridColumns.count,
                        renderCap: Self.memberRenderCap,
                         
                         
                         
                        memberOrder: { group in
                            index.renderingMembers(
                                in: group,
                                for: snapshot.proxies,
                                sortedBy: preferences.sort
                            )
                        }
                    )
                     
                     
                     
                     
                     
                     
                    VStack(spacing: 0) {
                        ForEach(rows) { row in
                            accordionRow(row)
                        }
                    }
                    .modifier(ClashProxyGridColumnReader(
                columns: $gridColumnCount,
                layout: preferences.layout
            ))
                }
            }
        }
    }

    private var groupsTitle: ClashDisplayText {
         
         
        .format("Groups (%@)", [String(browsedGroups.count)])
    }

     
     
    private var headerControlHeight: CGFloat { 32 }

    private var failedProviders: [ClashProxyProviderSnapshot] {
        snapshot.proxies.providers.filter { $0.loadFailure != nil }
    }

     
     
     
     
    private var failedProvidersCard: some View {
        ClashCardSurface(fill: palette.card, separator: palette.separator) {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: ClashTheme.Spacing.compact) {
                    ForEach(failedProviders, id: \.name) { provider in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: provider.name)
                                .font(.subheadline.weight(.semibold))
                            Text(verbatim: provider.loadFailure ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, ClashTheme.Spacing.compact)
            } label: {
                Label {
                     
                    Text(clash: .format(
                        failedProviders.count == 1
                            ? "%@ source could not be read: %@"
                            : "%@ sources could not be read: %@",
                        [String(failedProviders.count), failedProviders.map(\.name).joined(separator: ", ")]
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                } icon: {
                    icon(.exclamationmarkTriangle)
                        .foregroundStyle(.orange)
                }
            }
             
             
            .clashRowDisclosure()
            .padding(ClashTheme.Spacing.standard)
        }
        .accessibilityIdentifier("proxies.providers.failedSummary")
    }

    private var providersTitle: ClashDisplayText {
         
         
         
         
         
         
        let failed = snapshot.proxies.providers.filter {
            $0.loadFailure != nil
        }.count
        guard failed > 0 else {
            return .format(
                "Sources (%@)", [String(snapshot.proxies.providers.count)]
            )
        }
         
         
        return .format(
            "Sources (%@ · %@ failed)",
            [String(snapshot.proxies.providers.count), String(failed)]
        )
    }

    private var testAllButton: some View {
        ClashSweepControl(
            isConnected: snapshot.proxies.isConnected,
            isTesting: snapshot.proxies.isTestingLatency,
            completed: snapshot.proxies.latencyCompletedCount,
            total: snapshot.proxies.latencyTotalCount,
            height: headerControlHeight,
            pulse: latencyPulse,
            onStart: {
                 
                if isSearching {
                    send(.testShown(snapshot.proxies.shownMembers(matching: effectiveQuery)))
                    return
                }
                send(
                    .testAll(
                        visibleGroupNames: browsedGroups
                            .map(\.name)
                            .filter {
                                ClashProxyBrowsing.showsMembers(
                                    of: $0,
                                    expanded: expanded,
                                    isSearching: isSearching
                                )
                            }
                    )
                )
            },
            onCancel: { send(.cancelLatency) },
            icon: icon
        )
    }

     
     
     
    private static func groupAnchor(_ name: String) -> AnyHashable {
        ClashProxyBrowsing.groupAnchor(name)
    }

     
     
     
     
     
     
     
     
     
     
    private func groupSection(
        _ group: ClashProxyGroupSnapshot
    ) -> some View {
        let isOpen = ClashProxyBrowsing.showsMembers(
            of: group.name,
            expanded: expanded,
            isSearching: isSearching
        )
         
         
         
         
        let isTesting = ClashPerf.measure(
            "proxies.section.testing",
            detail: "group=\(group.name) members=\(group.members.count)"
        ) {
            group.members.contains {
                snapshot.proxies.latency(for: $0.latencyKey) == .testing
            }
        }
        let selection = visibleSelection(in: group)

         
         
         
         
        return VStack(alignment: .leading, spacing: 0) {
            groupHeader(group, isOpen: isOpen, isTesting: isTesting, selection: selection)
            if let refusal = snapshot.proxies.actionRefusals[group.name] {
                ClashGroupRefusalLine(group: group.name, refusal: refusal)
                    .padding(.bottom, ClashTheme.Spacing.compact)
            }
             
             
             
             
             
             
            refusalCaption(for: group)
        }
        .id("group.\(group.name)")
    }

    private func groupHeader(
        _ group: ClashProxyGroupSnapshot,
        isOpen: Bool,
        isTesting: Bool,
        selection: String?
    ) -> some View {
        ClashProxyGroupHeader(
            group: group,
            isOpen: isOpen,
            isTesting: isTesting,
            isConnected: snapshot.proxies.isConnected,
            currentSelection: selection,
            latency: snapshot.proxies.displayedLatency(forGroup: group),
            latencyPulse: latencyPulse,
            gate: activePulseGate,
            seed: (latencyPulseSnapshot?()).map {
                ClashLatencyGroupFace.reading(
                    $0, group: group, memberKeys: { ClashLatencyGroupFace.memberKeys(of: group) }, kept: .init())
            } ?? .init(),
            showsUnpin: snapshot.proxies.offersUnpin(for: group)
                && selection != nil,
             
            showsLocate: selection.map { chosen in group.members.contains { $0.name == chosen } } ?? false,
            showsIconImages: preferences.groupIconImages,
            icon: icon,
            onToggle: { toggle(group) },
             
            onTestGroup: {
                if isSearching {
                    send(.testShown([ClashProxiesShownMembers(group: group.name, members: group.members.map(\.name))]))
                } else {
                    send(.testGroup(name: group.name))
                }
            },
            onUnpin: { unpin(group) },
            onLocate: { locate(group) }
        )
        .equatable()
    }

    @ViewBuilder
    private func accordionRow(_ row: ClashProxyAccordionRow) -> some View {
        switch row.kind {
        case .groupHeader:
            if let group = row.group {
                groupSection(group)
                    .id(Self.groupAnchor(group.name))
            }
        case .ungroupedHeader:
            ungroupedHeader(count: row.totalCount)
                .id(Self.groupAnchor(ClashProxyBrowsing.ungroupedKey))
        case .memberSlice:
            accordionMemberSlice(row)
                .id(AnyHashable(row.id))
        case .showAll:
            if let revealKey = row.revealKey {
                showAllButton(
                    revealKey: revealKey,
                    totalCount: row.totalCount,
                    group: row.group
                )
            }
        case .divider:
            Divider()
        }
    }

    private func ungroupedHeader(count: Int) -> some View {
        let isOpen = ClashProxyBrowsing.showsMembers(
            of: ClashProxyBrowsing.ungroupedKey,
            expanded: expanded,
            isSearching: isSearching
        )

        return ClashUngroupedHeaderRow(
            count: count,
            isOpen: isOpen,
            verticalPadding: ClashTheme.Spacing.row,
            icon: icon
        ) {
            applyFoldChange {
                if isOpen {
                    expanded.remove(ClashProxyBrowsing.ungroupedKey)
                } else {
                    expanded.insert(ClashProxyBrowsing.ungroupedKey)
                }
            }
        }
    }

    @ViewBuilder
    private var tabsBody: some View {
        let tabs = browsedGroups.map(\.name)
            + (browsedUngrouped.isEmpty ? [] : [ClashProxyBrowsing.ungroupedKey])
         
         
        let active = tabs.contains(selectedTab ?? "") ? selectedTab
            : ClashProxyBrowsing.defaultTab(tabs, skipping: ClashProxyBrowsing.notOpenedUnasked(
                browsedGroups, liveCatalog: snapshot.proxies.liveCatalog ?? false))

        HStack(spacing: ClashTheme.Spacing.compact) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ClashTheme.Spacing.compact) {
                    ForEach(tabs, id: \.self) { tab in
                        Button {
                            select(tab: tab)
                        } label: {
                            Text(tabTitle(tab))
                                .font(
                                    .subheadline.weight(
                                        tab == active
                                            ? .semibold
                                            : .regular
                                    )
                                )
                                .foregroundStyle(
                                    tab == active ? Color.blue : Color.primary
                                )
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule().fill(
                                        tab == active
                                            ? Color.blue.opacity(0.12)
                                            : palette.raisedFill
                                    )
                                )
                                .overlay(
                                    Capsule().strokeBorder(
                                        tab == active
                                            ? Color.blue.opacity(0.45)
                                            : .clear,
                                        lineWidth: 1
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(
                            "proxies.tab.\(tabTitle(tab))"
                        )
                    }
                }
            }

             
             
             
             
             
            if tabs.count > 3 {
                Menu {
                    ForEach(tabs, id: \.self) { tab in
                        Button {
                            select(tab: tab)
                        } label: {
                            if tab == active {
                                Label(tabTitle(tab), systemImage: "checkmark")
                            } else {
                                Text(tabTitle(tab))
                            }
                        }
                    }
                } label: {
                    icon(.chevronDown)
                }
                 
                 
                 
                 
                 
                 
                 
                 
                 
                .menuIndicator(.hidden)
                .accessibilityLabel("All Groups")
                .accessibilityIdentifier("proxies.tab.all")
            }
        }

        if let active {
            if active == ClashProxyBrowsing.ungroupedKey {
                memberGrid(
                    members: browsedUngrouped.map {
                        ClashProxyMemberSnapshot(
                            name: $0.name,
                            type: $0.type
                        )
                    },
                    group: nil
                )
            } else if let group = browsedGroups.first(where: {
                $0.name == active
            }) {
                let selection = visibleSelection(in: group)
                HStack(spacing: 6) {
                    Text(group.type)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                     
                     
                     
                     
                     
                     
                    if snapshot.proxies.offersUnpin(for: group), selection != nil {
                        Button("Unfix") {
                            unpin(group)
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .accessibilityIdentifier("proxies.unfix.\(group.name)")
                    }
                    if group.isEmpty {
                         
                         
                         
                        Text(clash: .copy("· No nodes"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let current = selection {
                        ClashRegionalFlag.label("→ \(current)", pointSize: 12, relativeTo: .caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                 
                 
                if let refusal = snapshot.proxies.actionRefusals[group.name] {
                    ClashGroupRefusalLine(group: group.name, refusal: refusal)
                }
                 
                 
                 
                if group.isEmpty, let note = group.emptyNote {
                    Text(clash: .verbatim(note))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("proxies.group.emptyNote.\(group.name)")
                }
                memberGrid(group)
            }
        }
    }

    private func tabTitle(_ tab: String) -> String {
        tab == ClashProxyBrowsing.ungroupedKey ? "Ungrouped" : tab
    }

    private func select(tab: String) {
        selectedTab = tab
        send(
            .setVisibleGroup(
                name: tab == ClashProxyBrowsing.ungroupedKey ? nil : tab
            )
        )
    }

    private func memberGrid(
        _ group: ClashProxyGroupSnapshot
    ) -> some View {
        memberGrid(
            members: index.renderingMembers(
                in: group,
                for: snapshot.proxies,
                sortedBy: preferences.sort
            ),
            group: group
        )
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    private static var memberRenderCap: Int {
        ClashPlatformLayout.pageUsesSystemSettingsIdiom ? 56 : 120
    }

    @ViewBuilder
    private func accordionMemberSlice(
        _ row: ClashProxyAccordionRow
    ) -> some View {
        if let range = row.range {
            if let group = row.group {
                let end = min(range.upperBound, row.members.count)
                if range.lowerBound < end {
                    LazyVGrid(
                        columns: gridColumns,
                        spacing: ClashTheme.Spacing.compact
                    ) {
                        ForEach(row.members[range.lowerBound..<end]) { member in
                            memberCard(member, in: group)
                        }
                    }
                    .overlay(alignment: .top) {
                        locateMarkerOverlay(for: row, count: end - range.lowerBound)
                    }
                    .padding(.bottom, ClashTheme.Spacing.compact)
                }
            } else {
                let end = min(range.upperBound, row.members.count)
                if range.lowerBound < end {
                    LazyVGrid(
                        columns: gridColumns,
                        spacing: ClashTheme.Spacing.compact
                    ) {
                        ForEach(row.members[range.lowerBound..<end]) { member in
                            memberCard(member, in: nil)
                        }
                    }
                    .padding(.bottom, ClashTheme.Spacing.compact)
                }
            }
        }
    }

    private func showAllButton(
        revealKey: String,
        totalCount: Int,
        group: ClashProxyGroupSnapshot? = nil
    ) -> some View {
        Button {
            revealedFullGroups.insert(revealKey)
            if let group, !group.hasEveryMember { send(.loadMembers(group: group.name)) }
        } label: {
            Text(clash: .format("Show all %@ nodes", [totalCount.formatted(.number.locale(locale))]))
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, ClashTheme.Spacing.row)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .accessibilityIdentifier("proxies.showAll.\(revealKey)")
    }

    private func memberGrid(
        members: [ClashProxyMemberSnapshot],
        group: ClashProxyGroupSnapshot?
    ) -> some View {
        let revealKey = group?.name ?? ClashProxyBrowsing.ungroupedKey
        let partial = group.map { !$0.hasEveryMember } ?? false
        let capped = !revealedFullGroups.contains(revealKey)
            && members.count > Self.memberRenderCap
        let shown = capped
            ? Array(members.prefix(Self.memberRenderCap))
            : members
        return VStack(spacing: ClashTheme.Spacing.compact) {
            LazyVGrid(
                columns: gridColumns,
                spacing: ClashTheme.Spacing.compact
            ) {
                ForEach(shown) { member in
                    memberCard(member, in: group)
                }
            }
            if capped || partial {
                Button {
                    revealedFullGroups.insert(revealKey)
                    if let group, !group.hasEveryMember { send(.loadMembers(group: group.name)) }
                } label: {
                    Text(clash: .format(
                        "Show all %@ nodes",
                        [(group?.memberCount ?? members.count).formatted(.number.locale(locale))]
                    ))
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, ClashTheme.Spacing.row)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .accessibilityIdentifier(
                    "proxies.showAll.\(revealKey)"
                )
            }
        }
        .modifier(ClashProxyGridColumnReader(
                columns: $gridColumnCount,
                layout: preferences.layout
            ))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            refusalCaption(for: group)
        }
    }

     
     
    @ViewBuilder
    private func memberCard(
        _ member: ClashProxyMemberSnapshot,
        in group: ClashProxyGroupSnapshot?
    ) -> some View {
        let _ = ClashPerf.count("proxies.card.make")
         
         
         
         
         
         
         
         
        if snapshot.proxies.canEdit(member) {
            plainMemberCard(member, in: group)
                .contextMenu {
                    Button {
                        send(.editMember(name: member.name))
                    } label: {
                        Label {
                            Text(ClashCopy.key("Edit Node"))
                        } icon: {
                            Image(systemName: ClashSymbol.pencil.rawValue)
                        }
                    }
                }
        } else {
            plainMemberCard(member, in: group)
        }
    }

    private func plainMemberCard(
        _ member: ClashProxyMemberSnapshot,
        in group: ClashProxyGroupSnapshot?
    ) -> some View {
         
         
         
         
         
        let empty = snapshot.proxies.isEmptyGroup(member)
        return ClashProxyMemberCard(
             
            onTest: empty ? nil : { send(.testMember(name: member.name, group: group?.name)) },
            member: member,
            detail: memberDetail(member),
            latency: pulseLatency(member) ?? memberLatency(member),
            showsLatency: !empty,
            failureCategory:
                snapshot.proxies.failureCategories[member.name] ?? "",
            isCurrent: group.flatMap(visibleSelection) == member.name,
            size: preferences.size,
            fill: palette.raisedFill,
            action: { choose(member, in: group) },
            inspect: ClashProxyBrowsing.inspects(member)
                ? { send(.inspectMember(name: member.name)) }
                : nil,
            pulse: empty ? nil : latencyPulse,
            gate: activePulseGate
        )
        .equatable()
         
         
         
         
         
         
         
        .accessibilityIdentifier("proxies.member.\(member.name)")
    }

     
     
     
     
     
    private func pulseLatency(
        _ member: ClashProxyMemberSnapshot
    ) -> ClashProxyLatencyState? {
         
        if snapshot.proxies.isEmptyGroup(member) { return .untested }
        guard let pulse = latencyPulseSnapshot?() else { return nil }
        let name = member.isGroup
            ? pulse.groupTerminalKeys[member.name] ?? pulse.groupTerminals[member.name]
            : member.latencyKey
        guard let name else { return nil }
        if let result = ClashLatencyKey.reading(name, in: pulse.results) { return result }
        if pulse.isTesting, ClashLatencyKey.isTesting(name, in: pulse.testing) { return .testing }
        return pulse.isTesting ? nil : .untested
    }

     
     
     
     
     
    private func choose(
        _ member: ClashProxyMemberSnapshot,
        in group: ClashProxyGroupSnapshot?
    ) {
        guard let group else { return }
        guard group.allowsMemberChoice else {
            if let reason = group.memberChoiceRefusal {
                choiceRefusal = ClashProxyChoiceRefusal(
                    group: group.name,
                    message: reason
                )
            }
            return
        }
        choiceRefusal = nil
        if !snapshot.proxies.isConnected {
            offlineSelections[group.name] = member.name
        }
        send(.select(group: group.name, member: member.name))
    }

    @ViewBuilder
    private func refusalCaption(
        for group: ClashProxyGroupSnapshot?
    ) -> some View {
         
         
         
        if let group, let refusal = choiceRefusal,
           refusal.group == group.name,
           snapshot.proxies.actionRefusals[group.name] == nil {
            Text(clash: .copy(refusal.message))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, ClashTheme.Spacing.compact)
                .accessibilityIdentifier("proxies.refusal.\(group.name)")
        }
    }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(
                .flexible(),
                spacing: ClashTheme.Spacing.compact
            ),
            count: gridColumnCount
        )
    }

    private var nodesCard: some View {
        ClashCardSurface(
            fill: palette.card,
            separator: palette.separator
        ) {
            VStack(alignment: .leading, spacing: ClashTheme.Spacing.standard) {
                Label {
                    Text("Nodes (\(browsedUngrouped.count))")
                        .font(.headline)
                } icon: {
                    icon(.serverRack)
                        .foregroundStyle(.primary)
                }
                memberGrid(
                    members: browsedUngrouped.map {
                        ClashProxyMemberSnapshot(
                            name: $0.name,
                            type: $0.type
                        )
                    },
                    group: nil
                )
            }
            .padding(ClashTheme.Spacing.standard)
        }
    }

     
     
     
     
    @ViewBuilder
    private var providersCard: some View {
        if ClashPlatformLayout.pageUsesSystemSettingsIdiom {
             
             
             
             
            ClashProductGroup(
                providersTitle,
                palette: palette
            ) {
                providerRows
            }
        } else {
            ClashCardSurface(
                fill: palette.card,
                separator: palette.separator
            ) {
                VStack(
                    alignment: .leading,
                    spacing: ClashTheme.Spacing.standard
                ) {
                    Label {
                        Text(clash: providersTitle)
                            .font(.headline)
                    } icon: {
                        icon(.shippingbox)
                            .foregroundStyle(.primary)
                    }
                    providerRows
                }
                .padding(ClashTheme.Spacing.standard)
            }
        }
    }

     
    private var providerRows: some View {
        VStack(alignment: .leading, spacing: ClashTheme.Spacing.standard) {
                VStack(spacing: 0) {
                    ForEach(snapshot.proxies.providers) { provider in
                        providerRow(
                            provider,
                            verticalInset: ClashTheme.Spacing.row
                        )
                        providerExpansion(provider)

                        if provider.id
                            != snapshot.proxies.providers.last?.id
                        {
                            Divider()
                        }
                    }
                }
            }
    }

     
     
     
     
     
    private func providerRow(
        _ provider: ClashProxyProviderSnapshot,
        verticalInset: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            providerRowLine(provider, verticalInset: verticalInset)
            if let failure = provider.loadFailure {
                 
                 
                 
                 
                 
                Label {
                    Text(failure)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    icon(.exclamationmarkTriangle)
                }
                .font(.caption)
                .foregroundStyle(.orange)
                .accessibilityIdentifier(
                    "proxies.provider.loadFailure.\(provider.name)"
                )
            } else if let note = provider.note {
                 
                 
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("proxies.provider.note.\(provider.name)")
            }
        }
    }

    private func providerRowLine(
        _ provider: ClashProxyProviderSnapshot,
        verticalInset: CGFloat
    ) -> some View {
         
        let canOpen = !(provider.nodes ?? []).isEmpty || (provider.nodeCount ?? 0) > 0
        let isOpen = expandedProvider == provider.name
        return HStack(spacing: ClashTheme.Spacing.row) {
            ClashRegionalFlag.label(provider.title, pointSize: 17, relativeTo: .body)
                .font(.body.weight(.semibold))
            if canOpen {
                icon(.chevronDown)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isOpen ? 0 : -90))
            }
            Spacer(minLength: 8)
            if let count = provider.nodeCount {
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Text(provider.type)
                .font(.caption)
                .foregroundStyle(.secondary)

             
             
             
             
            if provider.isUpdatable {
                Button {
                    send(.updateProvider(name: provider.name))
                } label: {
                    icon(.arrowClockwise)
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Update \(provider.name)")
                .accessibilityIdentifier(
                    "proxies.provider.update.\(provider.name)"
                )
            }
        }
        .padding(.vertical, verticalInset)
         
         
         
         
         
         
         
        .contentShape(Rectangle())
        .onTapGesture {
            guard canOpen else { return }
            expandedProvider = isOpen ? nil : provider.name
            if !isOpen, (provider.nodes?.count ?? 0) < (provider.nodeCount ?? 0) {
                send(.loadProviderNodes(provider: provider.name))
            }
        }
        .accessibilityAddTraits(canOpen ? .isButton : [])
        .accessibilityValue(
            canOpen ? (isOpen ? "Expanded" : "Collapsed") : ""
        )
        .accessibilityIdentifier("proxies.provider.\(provider.name)")
    }

    @ViewBuilder
    private func providerExpansion(
        _ provider: ClashProxyProviderSnapshot
    ) -> some View {
        if expandedProvider == provider.name,
           let nodes = provider.nodes, !nodes.isEmpty {
             
             
             
             
             
             
             
            let slices = ClashProxyMemberSlicePlan.make(
                count: nodes.count,
                columns: gridColumns.count
            )
            VStack(spacing: ClashTheme.Spacing.compact) {
                ForEach(slices, id: \.lowerBound) { range in
                    LazyVGrid(
                        columns: gridColumns,
                        spacing: ClashTheme.Spacing.compact
                    ) {
                        ForEach(nodes[range]) { member in
                            memberCard(member, in: nil)
                        }
                    }
                }
            }
            .modifier(ClashProxyGridColumnReader(
                columns: $gridColumnCount,
                layout: preferences.layout
            ))
            .padding(.bottom, ClashTheme.Spacing.row)
            .clashHeightProbe(
                "providers-expansion", count: nodes.count
            )
        }
    }

     
     
     
     
     
     
     
     
    private var directModeCard: some View {
        ClashCardSurface(
            fill: palette.card,
            separator: palette.separator
        ) {
            VStack(spacing: ClashTheme.Spacing.compact) {
                 
                 
                icon(.arrowLeftAndRight)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Direct Mode")
                    .font(.headline)
                Text(
                    "This mode sends all traffic without a proxy, so proxy groups and nodes are not listed."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, ClashTheme.Spacing.section)
            .padding(.horizontal, ClashTheme.Spacing.standard)
        }
        .accessibilityIdentifier("proxies.direct-mode-notice")
    }

    private var emptyCard: some View {
        ClashCardSurface(
            fill: palette.card,
            separator: palette.separator
        ) {
            VStack(spacing: ClashTheme.Spacing.compact) {
                icon(.serverRack)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("No Proxies")
                    .font(.headline)
                Text("This profile has no proxy groups or nodes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, ClashTheme.Spacing.section)
            .padding(.horizontal, ClashTheme.Spacing.standard)
        }
    }

     
     
    private var noMatchesCard: some View {
        ClashCardSurface(
            fill: palette.card,
            separator: palette.separator
        ) {
            VStack(spacing: ClashTheme.Spacing.row) {
                icon(.magnifyingglass)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("No Results for \u{201C}\(effectiveQuery)\u{201D}")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, ClashTheme.Spacing.section)
            .padding(.horizontal, ClashTheme.Spacing.standard)
        }
        .accessibilityIdentifier("proxies.search.empty")
    }

     
     
     
     
    private var visibleGroupNames: [String] {
        var names = snapshot.proxies.groups.map(\.name)
        if !snapshot.proxies.ungrouped.isEmpty {
            names.append(ClashProxyBrowsing.ungroupedKey)
        }
        return names
    }

     
    private func keepOneGroupOpen() {
        guard ClashPlatformLayout.proxiesKeepsOneGroupOpen else { return }
        guard let name = ClashProxyBrowsing.groupToKeepOpen(
            visible: visibleGroupNames,
            expanded: expanded,
             
             
             
             
             
            lastOpened: lastExpandedGroup
                ?? snapshot.proxies.initiallyExpandedGroup
                ?? snapshot.proxies.rememberedOpenGroup,
            isSearching: isSearching,
            readerFoldedAll: snapshot.proxies.readerFoldedAll ?? false,
             
             
            notAsFallback: ClashProxyBrowsing.notOpenedUnasked(snapshot.proxies.groups,
                                                               liveCatalog: snapshot.proxies.liveCatalog ?? false)
        ) else { return }
        ClashPerf.emit("proxies keep-open group=\(name)")
        expanded = [name]
        send(.setGroupExpanded(name: name, isExpanded: true))
        send(.setVisibleGroup(name: name))
    }

    private var hasExpandedGroups: Bool {
        browsedGroups.contains { expanded.contains($0.name) }
            || expanded.contains(ClashProxyBrowsing.ungroupedKey)
    }

     
     
     
     
     
     
     
     
     
     
     
    private func toggleAllGroups() {
        let collapsing = hasExpandedGroups
        ClashPerf.markFoldAll(collapsing: collapsing)
        let affected = browsedGroups
            .map(\.name)
            .filter { expanded.contains($0) == collapsing }
         
         
         
         
         
         
         
        if collapsing {
             
             
            lastExpandedGroup = expanded.first
            expanded.removeAll()
            send(.setGroupsExpanded(names: affected, isExpanded: false))
        } else if let reopening = groupToReopen {
             
             
             
             
             
             
             
            expanded = [reopening]
            send(.setGroupExpanded(name: reopening, isExpanded: true))
        }
    }

     
     
     
     
    private var groupToReopen: String? {
        if let last = lastExpandedGroup,
           browsedGroups.contains(where: { $0.name == last }) {
            return last
        }
        return browsedGroups.first?.name
    }

     
     
     
     
     
     
    private func locate(_ group: ClashProxyGroupSnapshot) -> String? {
        guard let plan = locatePlan(group) else { return nil }
        if !expanded.contains(group.name) { toggle(group) }
        if plan.revealsAll { revealedFullGroups.insert(group.name) }
        if plan.awaitsWhole { send(.loadMembers(group: group.name)) }
        locateMarker = plan
        locateAwaitedGroup = plan.awaitsWhole ? group.name : nil
        locateAwaitedSince = plan.awaitsWhole ? Date() : nil
        return plan.anchor
    }

    private func locatePlan(_ group: ClashProxyGroupSnapshot) -> ClashProxyLocatePlan? {
        let ordered = index.renderingMembers(in: group, for: snapshot.proxies, sortedBy: preferences.sort).map(\.name)
        return ClashProxyLocatePlan.make(
            group: group.name, ordered: ordered, selection: visibleSelection(in: group),
            isRevealed: revealedFullGroups.contains(group.name), carriesSelection: group.carriesSelection,
            renderCap: Self.memberRenderCap, columns: gridColumns.count
        )
    }

     
     
     
     
     
     
     
     
    private var locateOnceWhole: ClashProxyLocatePlan? {
        guard let name = locateAwaitedGroup, expanded.contains(name), !isSearching,
              let group = snapshot.proxies.group(named: name), group.hasEveryMember
        else { return nil }
        return locatePlan(group)
    }

     
    private func locateAgain(_ plan: ClashProxyLocatePlan?) {
        guard let plan else { return }
        let since = locateAwaitedSince
        locateAwaitedGroup = nil
        locateAwaitedSince = nil
        guard let since, Date().timeIntervalSince(since) <= ClashProxyLocatePlan.wait else { return }
        locateMarker = plan
        scrollPage(to: AnyHashable(plan.anchor), anchor: .center)
    }

     
    @ViewBuilder
    private func locateMarkerOverlay(for row: ClashProxyAccordionRow, count: Int) -> some View {
        if let marker = locateMarker, marker.slice == row.id, count > 0 {
            let columns = max(gridColumns.count, 1)
            let rows = (count + columns - 1) / columns
            if marker.offset < count {
                ClashGridRowMarker(rows: rows, row: marker.offset / columns, id: AnyHashable(marker.anchor))
            }
        }
    }

    private func toggle(_ group: ClashProxyGroupSnapshot) {
        let wasOpen = expanded.contains(group.name)
        ClashPerf.markGroupFold(wasOpen: wasOpen)
         
         
        if locateAwaitedGroup != nil {
            locateAwaitedGroup = nil
            locateAwaitedSince = nil
        }
         
         
         
         
         
         
        let closing = wasOpen ? [] : expanded.subtracting([group.name])
        applyFoldChange {
            if wasOpen {
                expanded.remove(group.name)
            } else {
                expanded = [group.name]
            }
        }
        if !closing.isEmpty {
            send(.setGroupsExpanded(names: Array(closing), isExpanded: false))
        }
        send(.setGroupExpanded(name: group.name, isExpanded: !wasOpen))
    }

     
     
     
     
     
     
     
     
    private func applyFoldChange(_ change: () -> Void) {
        if ClashPlatformLayout.pageUsesSystemSettingsIdiom {
            change()
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                change()
            }
        }
    }

     
     
     
     
     
    private func unpin(_ group: ClashProxyGroupSnapshot) {
        offlineSelections[group.name] = nil
        send(.unpin(group: group.name))
    }

    private func visibleSelection(
        in group: ClashProxyGroupSnapshot
    ) -> String? {
        if !snapshot.proxies.isConnected,
           let offlineSelection = offlineSelections[group.name]
        {
            return offlineSelection
        }
        return group.currentSelection
    }

    private func memberDetail(
        _ member: ClashProxyMemberSnapshot
    ) -> String {
         
         
         
         
         
         
         
         
        if !member.isGroup,
           index.answersDetails(for: snapshot.proxies),
           let detail = index.detail(for: member)
        {
            return detail
        }
        if snapshot.proxies.isEmptyGroup(member) {
            return "\(member.type) " + ClashCopy.string("· No nodes", locale: locale)
        }
        guard member.isGroup, let route = memberRouteForDisplay(member) else {
            return member.type
        }
        return "\(member.type) → \(route)"
    }

     
     
     
     
     
     
     
     
     
     
    private func memberRouteForDisplay(
        _ member: ClashProxyMemberSnapshot
    ) -> String? {
         
         
         
         
         
         
         
         
        if snapshot.proxies.isConnected,
           !snapshot.proxies.isEmptyGroup(member),
           let terminal = latencyPulseSnapshot?().groupTerminals[member.name]
        {
            return terminal
        }
        return memberResolvedRoute(member)
    }

    private func memberResolvedRoute(
        _ member: ClashProxyMemberSnapshot
    ) -> String? {
        snapshot.proxies.resolvedDisplayRoute(for: member)
    }


    private func memberLatency(
        _ member: ClashProxyMemberSnapshot
    ) -> ClashProxyLatencyState {
        if index.source == snapshot.proxies, let latency = index.latency(for: member) {
            return latency
        }
        return snapshot.proxies.displayedLatency(for: member)
    }

    private func applyInitialDestination() {
        ClashPerf.emit(
            "proxies entry-open expandedEmpty=\(expanded.isEmpty) id=\(identityStamp.uuidString.prefix(5))"
        )
         
         
         
         
         
         
         
         
         
        guard !entryRoutine.didApply else { return }
        entryRoutine.didApply = true
        let destination = snapshot.proxies.initiallyExpandedGroup
        if let destination, selectedTab != destination {
            selectedTab = destination
        }
         
         
        if let destination {
            send(.setVisibleGroup(name: destination))
        }
         
         
         
         
        if let destination { scrollToGroup(destination) }
    }

     
     
     
     
     
    private func scrollToGroup(_ name: String) {
        scrollPage(to: Self.groupAnchor(name), anchor: .top) {
            ClashPerf.emit("proxies entry-scroll dest=\(name)")
        }
    }

     
     
     
    private func scrollPage(to id: AnyHashable, anchor: UnitPoint, then trace: @escaping () -> Void = {}) {
        let outer = scrollToID
        let page = pageScroll
        DispatchQueue.main.async {
            guard let scroll = outer ?? page.request else { return }
            trace()
            scroll(id, anchor: anchor)
        }
    }

    private func send(_ command: ClashProxiesCommand) {
         
         
         
        ClashPerf.log.notice("proxies send \(String(describing: command), privacy: .public)")
        Task {
            do {
                try await actions.perform(
                    .proxies(command),
                    allowedBy: snapshot
                )
            } catch {
                ClashPerf.log.error("proxies command refused \(String(describing: command), privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
    }
}

 
 
 
 
 
 
 
 
private enum ClashLatencyRowAlignment: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat {
        context[VerticalAlignment.center]
    }
}

private extension VerticalAlignment {
    static let clashLatencyRow = VerticalAlignment(ClashLatencyRowAlignment.self)
}

struct ClashProxyMemberCard: View, Equatable {
     
     
     
     
     
    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.member == b.member
            && a.detail == b.detail
            && a.latency == b.latency
            && a.showsLatency == b.showsLatency
            && a.failureCategory == b.failureCategory
            && a.isCurrent == b.isCurrent
            && a.size == b.size
            && a.fill == b.fill
            && (a.inspect == nil) == (b.inspect == nil)
            && (a.onTest == nil) == (b.onTest == nil)
    }

     
     
     
     
     
     
     
     
     
     
    var onTest: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let member: ClashProxyMemberSnapshot
    let detail: String
    let latency: ClashProxyLatencyState
     
     
     
     
     
    var showsLatency = true
     
     
     
     
     
     
    var failureCategory: String = ""
    let isCurrent: Bool
    let size: ClashProxiesDisplayPreferences.Size
    let fill: Color
    let action: () -> Void
     
     
     
    var inspect: (() -> Void)?

     
     
     
     
    let pulse: AnyPublisher<ClashLatencyPulse, Never>?
     
     
     
    var gate: ClashLatencyPulseGate?
    @State private var liveLatency: ClashProxyLatencyState?
     
     
    @State private var settledLatency: ClashProxyLatencyState?
     
     
     
     
    @State private var latencyTap: ClashLatencyTap?

     
     
     
     
    private var shownLatency: ClashProxyLatencyState { pulse == nil ? latency : liveLatency ?? latency }

     
     
    private func setLive(_ value: ClashProxyLatencyState?) {
        let settled = ClashLatencySlotFace.settled(writing: value, over: shownLatency, kept: settledLatency)
        if settled != settledLatency { settledLatency = settled }
        liveLatency = value
    }

     
     
     
     
     
    private var slotTest: (() -> Void)? {
        onTest.map { test in
            {
                guard ClashLatencyTap.canTap(shown: shownLatency, tap: latencyTap, now: Date()) else { return }
                let tap = ClashLatencyTap(before: latencyTap?.before ?? shownLatency, at: Date())
                latencyTap = tap
                test()
                setLive(.testing)
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(ClashLatencyTap.expiry * 1_000_000_000))
                    guard latencyTap == tap, liveLatency == .testing else { return }
                    setLive(tap.before)
                    latencyTap = nil
                }
            }
        }
    }

    var body: some View {
         
         
         
         
         
         
         
        ZStack(alignment: Alignment(horizontal: .trailing, vertical: .clashLatencyRow)) {
        Button(action: action) {
            content
                .padding(.trailing, inspect == nil ? 0 : 24)
                .background(
                    RoundedRectangle(
                        cornerRadius: ClashTheme.Radius.control,
                        style: .continuous
                    )
                     
                     
                     
                     
                     
                     
                     
                     
                    .fill(isCurrent
                        ? AnyShapeStyle(.tint.opacity(0.16))
                        : AnyShapeStyle(fill))
                )
                .overlay(alignment: .leading) {
                     
                     
                     
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(.tint)
                        .frame(width: 3)
                        .padding(.vertical, 6)
                        .padding(.leading, 1)
                        .opacity(isCurrent ? 1 : 0)
                }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isCurrent ? "Selected" : "")
        .latencyTestAction(
            slotTest.map { test in ClashProxyLatencyAffordance.of(shownLatency) == .inProgress ? {} : test },
            offered: showsLatency
        )
        .accessibilityIdentifier("proxies.member.\(member.name)")
        inspectButton
            .alignmentGuide(.clashLatencyRow) { $0[VerticalAlignment.center] }
            .padding(.trailing, ClashTheme.Spacing.compact)
        }
        .onReceive(
            pulse ?? Empty<ClashLatencyPulse, Never>().eraseToAnyPublisher()
        ) { batch in
             
             
             
             
            guard gate?.isOpen ?? true else { return }
             
             
             
            let name = member.isGroup
                ? batch.groupTerminalKeys[member.name] ?? batch.groupTerminals[member.name]
                : member.latencyKey
            if let name {
                if !batch.isTesting {
                     
                     
                     
                     
                    if let tap = latencyTap, !ClashLatencyKey.isNamed(name, in: batch.landed) {
                         
                         
                         
                        let settled = tap.afterSilentPulse(now: Date())
                        setLive(settled)
                        if settled != .testing { latencyTap = nil }
                    } else {
                        setLive(ClashLatencyKey.reading(name, in: batch.results) ?? .untested)
                        if latencyTap != nil { latencyTap = nil }
                    }
                } else if let live = ClashLatencySlotFace.liveReading(testingPulse: batch, key: name, tapped: latencyTap != nil) {
                    setLive(live)
                    if live != .testing, latencyTap != nil { latencyTap = nil }
                }
            } else if !batch.isTesting {
                 
                 
                 
                 
                setLive(nil)
            }
        }
    }

     
     
     
     
     
     
    @ViewBuilder
    private var inspectButton: some View {
        if let inspect {
            Button(action: inspect) {
                Image(systemName: ClashSymbol.infoCircle.rawValue)
                    .font(.body)
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(ClashCopy.key("Node Details")))
            .accessibilityIdentifier("proxies.member.info.\(member.name)")
        }
    }

    @ViewBuilder
    private var chainLine: some View {
        if let entry = member.chainedThrough {
            HStack(spacing: 3) {
                Image(systemName: ClashSymbol.link.rawValue)
                    .font(.caption2)
                 
                 
                 
                 
                ClashRegionalFlag.label("\(entry) → \(member.name)", pointSize: 11, relativeTo: .caption2)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(ClashCopy.key("Enters through"))
            .accessibilityValue(entry)
        }
    }

    @ViewBuilder
    private var content: some View {
        if dynamicTypeSize.isAccessibilitySize {
            accessibilityContent
        } else {
            switch size {
            case .standard:
                standardContent
            case .compact:
                compactContent
            case .minimal:
                minimalContent
            }
        }
    }

    private var accessibilityContent: some View {
        VStack(
            alignment: .leading,
            spacing: ClashTheme.Spacing.compact
        ) {
            ClashRegionalFlag.label(member.name, pointSize: 15, relativeTo: .subheadline)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            Text(clash: .copy(detail))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            chainLine
             
             
            ClashProxyLatencyIndicator(
                state: shownLatency,
                settled: settledLatency,
                failureCategory: failureCategory,
                onTest: slotTest
            )
                .latencySlot(shown: showsLatency)
                .alignmentGuide(.clashLatencyRow) { $0[VerticalAlignment.center] }
        }
        .padding(ClashTheme.Spacing.row)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var standardContent: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                ClashRegionalFlag.label(member.name, pointSize: 15, relativeTo: .subheadline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text(clash: .copy(detail))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    ClashProxyLatencyIndicator(
                        state: shownLatency,
                        settled: settledLatency,
                        failureCategory: failureCategory,
                        onTest: slotTest
                    )
                        .latencySlot(shown: showsLatency)
                        .alignmentGuide(.clashLatencyRow) { $0[VerticalAlignment.center] }
                }
                chainLine
            }
        }
        .padding(ClashTheme.Spacing.row)
         
         
         
         
        .frame(
            maxWidth: .infinity,
            minHeight: 64,
            alignment: .topLeading
        )
    }

    private var compactContent: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                ClashRegionalFlag.label(member.name, pointSize: 13, relativeTo: .footnote)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    Text(clash: .copy(detail))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    ClashProxyLatencyIndicator(
                        state: shownLatency,
                        settled: settledLatency,
                        failureCategory: failureCategory,
                        onTest: slotTest
                    )
                        .latencySlot(shown: showsLatency)
                        .alignmentGuide(.clashLatencyRow) { $0[VerticalAlignment.center] }
                }
            }
        }
        .padding(ClashTheme.Spacing.compact)
        .frame(
            maxWidth: .infinity,
            minHeight: 48,
            alignment: .topLeading
        )
    }

    private var minimalContent: some View {
        HStack(spacing: 4) {
            ClashRegionalFlag.label(member.name, pointSize: 12, relativeTo: .caption)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 2)
             
             
             
             
             
             
             
             
            ClashProxyLatencyIndicator(
                state: shownLatency,
                settled: settledLatency,
                failureCategory: failureCategory,
                onTest: slotTest
            )
                .latencySlot(shown: showsLatency)
                .alignmentGuide(.clashLatencyRow) { $0[VerticalAlignment.center] }
        }
        .padding(.horizontal, ClashTheme.Spacing.compact)
        .padding(.vertical, 6)
         
         
        .frame(
            maxWidth: .infinity,
            minHeight: 30,
            alignment: .leading
        )
    }
}

private extension View {
     
    func latencySlot(shown: Bool) -> some View {
        opacity(shown ? 1 : 0)
            .allowsHitTesting(shown)
            .accessibilityHidden(!shown)
    }

     
     
     
     
    @ViewBuilder
    func latencyTestAction(_ onTest: (() -> Void)?, offered: Bool) -> some View {
        if offered, let onTest {
            accessibilityAction(named: Text(ClashCopy.key("Test latency")), onTest)
        } else {
            self
        }
    }
}

private struct ClashProxyLatencyIndicator: View {
    let state: ClashProxyLatencyState
     
    var settled: ClashProxyLatencyState? = nil
     
     
    var failureCategory: String = ""
     
     
    var onTest: (() -> Void)?

     
     
     
     
     
     
     
     
     
    private static let slotHeight: CGFloat = 16

    var body: some View {
        Group {
            if let onTest {
                 
                 
                 
                 
                let inProgress = ClashProxyLatencyAffordance.of(state) == .inProgress
                Button(action: inProgress ? {} : onTest) { indicator }
                    .buttonStyle(.borderless)
            } else {
                indicator
            }
        }
         
         
         
         
        .fixedSize(horizontal: true, vertical: false)
        .frame(
            minHeight: Self.slotHeight,
            maxHeight: Self.slotHeight,
            alignment: .trailing
        )
        .layoutPriority(1)
    }

     
     
     
    private var indicator: some View {
        let slot = ClashLatencySlotFace(shown: state, settled: settled)
        return ZStack(alignment: .trailing) {
            face(slot.face)
                .opacity(slot.isTesting ? 0 : 1)
                .accessibilityHidden(slot.isTesting)
            if slot.isTesting {
                ClashLatencySpinner(diameter: 10)
            }
        }
    }

    @ViewBuilder
    private func face(_ state: ClashProxyLatencyState) -> some View {
        switch state {
        case .untested, .testing:
             
             
            Image(systemName: ClashSymbol.bolt.rawValue)
                .font(.caption2)
                .foregroundStyle(.tint)
                .accessibilityLabel("Test latency")
        case .measured(let milliseconds):
            Text("\(milliseconds)ms")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(color(milliseconds))
        case .failed, .timedOut:
             
             
             
             
             
             
             
             
            status(
                .copy(ClashProbeFailureCopy.badge(
                    for: state == .timedOut ? "timeout" : failureCategory
                )),
                color: .red
            )
        }
    }

    private func status(_ title: ClashDisplayText, color: Color) -> some View {
        Text(clash: title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
    }

    private func color(_ milliseconds: Int) -> Color {
        ClashProxyLatencyPalette.color(milliseconds)
    }
}

 
 
 
enum ClashProxyLatencyPalette {
    static func color(_ milliseconds: Int) -> Color {
        if milliseconds < 800 { return .green }
        if milliseconds < 1_600 { return .yellow }
        return .orange
    }
}


 
 
 
 
 
 
 
 
 
 
 
 
private final class ClashEntryRoutineBox {
    var didApply = false
}

 
 
 
 
 
 
 
private final class ClashProxiesDisplayDraftBox {
    var value = ClashProxiesDisplayPreferences()
}

private struct ClashProxyGroupHeader<Icon: View>: View, Equatable {
    let group: ClashProxyGroupSnapshot
    let isOpen: Bool
    let isTesting: Bool
    let isConnected: Bool
    let currentSelection: String?
     
    let latency: ClashProxyLatencyState
     
     
     
    let latencyPulse: AnyPublisher<ClashLatencyPulse, Never>?
     
     
    var gate: ClashLatencyPulseGate?
     
     
     
     
    let seed: ClashLatencyGroupFace
    let showsUnpin: Bool
     
    let showsLocate: Bool
     
     
     
    let showsIconImages: Bool
    let icon: (ClashSymbol) -> Icon
    let onToggle: () -> Void
    let onTestGroup: () -> Void
    let onUnpin: () -> Void
     
    let onLocate: () -> String?
     
     
     
    @Environment(\.clashScrollToID) private var scrollToID
    @State private var live: ClashLatencyGroupFace?
    @State private var memberKeys = ClashLatencyMemberKeys()
     
     
     
     
     
    @State private var pressedAt: Date?
    private var face: ClashLatencyGroupFace { live ?? seed }
    private var shownTesting: Bool { pressedAt != nil || (face.isTesting ?? isTesting) }
    private var shownLatency: ClashProxyLatencyState { face.latency(of: group, initial: latency) }

    nonisolated static func == (a: Self, b: Self) -> Bool {
        ClashPerf.count("proxies.header.eq")
        return a.group == b.group
            && a.isOpen == b.isOpen
            && a.isTesting == b.isTesting
            && a.isConnected == b.isConnected
            && a.currentSelection == b.currentSelection
            && a.latency == b.latency
            && a.seed == b.seed
            && a.showsUnpin == b.showsUnpin
            && a.showsLocate == b.showsLocate
             
             
             
             
             
            && a.showsIconImages == b.showsIconImages
    }

     
     
     
     
     
     
     
     
     
     
     
     
    @ViewBuilder
    private var groupIcon: some View {
        switch ClashProxyGroupIconKind.of(group.icon) {
        case .emoji(let text):
            Text(text)
                .font(.body)
                .accessibilityHidden(true)
        case .symbol(let symbol):
            icon(symbol)
                .font(.body)
                .foregroundStyle(.secondary)
        case .remote where !showsIconImages:
             
             
             
            EmptyView()
        case .remote:
             
             
             
            ProxyGroupIconView(
                address: group.icon,
                size: ClashTheme.Layout.proxyGroupIconSize,
                connected: isConnected
            ) {
                RoundedRectangle(
                    cornerRadius: ClashTheme.Layout.proxyGroupIconCornerRadius,
                    style: .continuous
                )
                .fill(.quaternary)
                .frame(
                    width: ClashTheme.Layout.proxyGroupIconSize,
                    height: ClashTheme.Layout.proxyGroupIconSize
                )
                .accessibilityHidden(true)
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: ClashTheme.Layout.proxyGroupIconCornerRadius,
                    style: .continuous
                )
            )
        case .unrecognized, .none:
            EmptyView()
        }
    }

    var body: some View {
        ClashPerf.count("proxies.section.make")
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(
                    alignment: .center,
                    spacing: ClashTheme.Spacing.compact
                ) {
                    Button {
                        onToggle()
                    } label: {
                        HStack(
                            alignment: .center,
                            spacing: ClashTheme.Spacing.compact
                        ) {
                            groupIcon
                            ClashRegionalFlag.label(group.name, pointSize: 17, relativeTo: .body)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: ClashTheme.Spacing.compact)
                            Text("\(group.memberCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .frame(
                                    minWidth: 28,
                                    alignment: .trailing
                                )
                                .accessibilityLabel(
                                    Text(clash: .format(
                                        "%@ members",
                                        ["\(group.memberCount)"]
                                    ))
                                )
                            icon(.chevronDown)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(
                                    .degrees(isOpen ? 180 : 0)
                                )
                                .frame(width: 20)
                        }
                        .frame(minHeight: ClashTheme.Control.pointerRowTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(
                        "proxies.group.\(group.name)"
                    )
                    .accessibilityValue(isOpen ? "Expanded" : "Collapsed")

                     
                     
                    if showsLocate, let scrollToID {
                        Button {
                            guard let anchor = onLocate() else { return }
                             
                            DispatchQueue.main.async {
                                scrollToID(AnyHashable(anchor), anchor: .center)
                            }
                        } label: {
                            icon(.scope)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: ClashTheme.Control.pointerRowTarget,
                                       height: ClashTheme.Control.pointerRowTarget)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(Text(clash: .copy("Jump to Current Node")))
                        .accessibilityLabel(Text(clash: .copy("Jump to Current Node")))
                        .accessibilityIdentifier("proxies.locate.\(group.name)")
                    }

                    Button {
                        onTestGroup()
                         
                         
                         
                        let press = Date()
                        pressedAt = press
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: UInt64(ClashLatencyTap.expiry * 1_000_000_000))
                            if pressedAt == press { pressedAt = nil }
                        }
                    } label: {
                         
                         
                         
                         
                        ZStack {
                            icon(.boltHorizontalCircle)
                                .opacity(shownTesting ? 0 : 1)
                                .accessibilityHidden(shownTesting)
                            ClashLatencySpinner(isSpinning: shownTesting, diameter: 14)
                        }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(
                             
                             
                            width: ClashTheme.Control.pointerRowTarget,
                            height: ClashTheme.Control.pointerRowTarget
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!isConnected || shownTesting)
                    .accessibilityLabel(
                        Text(clash: .format(
                            "Test all proxies in %@",
                            [group.name]
                        ))
                    )
                    .accessibilityHint(
                        isConnected
                            ? "Measures proxy latency"
                            : "Connect before testing latency"
                    )
                    .accessibilityIdentifier(
                        "proxies.testGroup.\(group.name)"
                    )
                }

                HStack(spacing: 6) {
                    Text(group.type)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                     
                     
                     
                     
                    if showsUnpin {
                        Button("Unfix") {
                            onUnpin()
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                         
                         
                         
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .accessibilityIdentifier("proxies.unfix.\(group.name)")
                    }
                    if group.isEmpty {
                        Text(clash: .copy("· No nodes"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let current = currentSelection {
                        Text("→")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        ClashRegionalFlag.label(current, pointSize: 12, relativeTo: .caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if case .measured(let milliseconds) = shownLatency {
                            Text(clash: .verbatim("(\(milliseconds) ms)"))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(ClashProxyLatencyPalette.color(milliseconds))
                                .accessibilityLabel("\(milliseconds)ms")
                        }
                    }
                    Spacer(minLength: 0)
                }
                if group.isEmpty, let note = group.emptyNote {
                     
                     
                    Text(clash: .verbatim(note))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("proxies.group.emptyNote.\(group.name)")
                }
            }
            .padding(.vertical, ClashTheme.Spacing.compact)
        }
        .onReceive(latencyPulse ?? Empty<ClashLatencyPulse, Never>().eraseToAnyPublisher()) { batch in
            guard gate?.isOpen ?? true else { return }
            let next = ClashLatencyGroupFace.reading(
                batch, group: group, memberKeys: { memberKeys.of(group) }, kept: face)
            if next != face { live = next }
             
            if pressedAt != nil, next.isTesting == true || !batch.isTesting { pressedAt = nil }
        }
    }
}

private struct ClashProxiesDisplayOptionsView: View {
     
     
     
     
    @State private var preferences: ClashProxiesDisplayPreferences
    let palette: ClashProductPalette
    let onDraftChange: (ClashProxiesDisplayPreferences) -> Void

    @Environment(\.dismiss) private var dismiss

    init(
        preferences: ClashProxiesDisplayPreferences,
        palette: ClashProductPalette,
        onDraftChange: @escaping (ClashProxiesDisplayPreferences) -> Void
    ) {
        _preferences = State(initialValue: preferences)
        self.palette = palette
        self.onDraftChange = onDraftChange
    }

    var body: some View {
        ClashSingleColumnNavigationContainer {
            content
        }
        .accessibilityIdentifier("proxies.display.sheet")
        .onChange(of: preferences) { _ in
            onDraftChange(preferences)
        }
    }

    private var content: some View {
        ClashProductRootPage(
            palette: palette,
            accessibilityIdentifier: "proxies.display.content"
        ) {
            ClashCardSurface(
                fill: palette.card,
                separator: palette.separator
            ) {
                VStack(
                    alignment: .leading,
                    spacing: ClashTheme.Spacing.standard
                ) {
                     
                     
                     
                    labeled("Icons") {
                        Picker(
                            "Icons",
                            selection: $preferences.groupIconImages
                        ) {
                            Text("Off").tag(false)
                            Text("Show").tag(true)
                        }
                        .accessibilityIdentifier(
                            "proxies.display.groupIconImages"
                        )
                    }
                     
                     
                     
                     
                     
                     
                    if ClashPlatformLayout.proxiesDisplayOptionsUseListAxes {
                        listAxes
                    } else {
                        cardAxes
                    }
                }
                .padding(ClashTheme.Spacing.standard)
            }
        }
        .clashPageTitle("Display Options")
        .clashToolbarUnlessInPanel {
            ToolbarItem(placement: .cancellationAction) {
                ClashSheetCloseButton {
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private var listAxes: some View {
        labeled("Sort") {
            Picker("Sort", selection: $preferences.sort) {
                Text("Default").tag(
                    ClashProxiesDisplayPreferences.Sort.standard
                )
                Text("Delay").tag(
                    ClashProxiesDisplayPreferences.Sort.delay
                )
                Text("Name").tag(
                    ClashProxiesDisplayPreferences.Sort.name
                )
            }
                .accessibilityIdentifier("proxies.display.sort.sheet")
        }
        labeled("Rows") {
            Picker(
                "Rows",
                selection: Binding(
                    get: {
                        ClashProxiesRowDensity.from(preferences)
                    },
                    set: { density in
                         
                         
                         
                        preferences.size =
                            density == .standard ? .standard : .compact
                    }
                )
            ) {
                Text("Standard").tag(ClashProxiesRowDensity.standard)
                Text("Compact").tag(ClashProxiesRowDensity.compact)
            }
                .accessibilityIdentifier("proxies.display.size.sheet")
        }
    }

    @ViewBuilder
    private var cardAxes: some View {
        labeled("Style") {
            Picker("Style", selection: $preferences.style) {
                Text("List").tag(
                    ClashProxiesDisplayPreferences.Style.list
                )
                Text("Tabs").tag(
                    ClashProxiesDisplayPreferences.Style.tabs
                )
            }
                .accessibilityIdentifier("proxies.display.style")
        }
        labeled("Sort") {
            Picker("Sort", selection: $preferences.sort) {
                Text("Default").tag(
                    ClashProxiesDisplayPreferences.Sort.standard
                )
                Text("Delay").tag(
                    ClashProxiesDisplayPreferences.Sort.delay
                )
                Text("Name").tag(
                    ClashProxiesDisplayPreferences.Sort.name
                )
            }
                .accessibilityIdentifier("proxies.display.sort.sheet")
        }
        labeled("Layout") {
            Picker(
                "Layout",
                selection: $preferences.layout
            ) {
                Text("Loose").tag(
                    ClashProxiesDisplayPreferences.Layout.loose
                )
                Text("Compact").tag(
                    ClashProxiesDisplayPreferences.Layout.compact
                )
            }
                .accessibilityIdentifier("proxies.display.layout.sheet")
        }
        labeled("Size") {
            Picker("Size", selection: $preferences.size) {
                Text("Standard").tag(
                    ClashProxiesDisplayPreferences.Size.standard
                )
                Text("Compact").tag(
                    ClashProxiesDisplayPreferences.Size.compact
                )
                Text("Minimal").tag(
                    ClashProxiesDisplayPreferences.Size.minimal
                )
            }
                .accessibilityIdentifier("proxies.display.size.sheet")
        }
    }

    private func labeled<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: ClashTheme.Spacing.compact
        ) {
            Text(clash: .copy(title))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .pickerStyle(.segmented)
                .labelsHidden()
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashProxyColumnAdoption {
    private(set) var columns: Int
    private var pending: Int?

    init(columns: Int) {
        self.columns = columns
    }

    mutating func measured(_ value: Int, frozen: Bool) -> Int? {
        guard !frozen else {
            pending = value
            return nil
        }
        pending = nil
        guard value != columns else { return nil }
        columns = value
        return value
    }

    mutating func resizeEnded() -> Int? {
        guard let landed = pending else { return nil }
        pending = nil
        guard landed != columns else { return nil }
        columns = landed
        return landed
    }
}

 
 
 
private struct ClashLiveResizeFreezeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    public var clashLiveResizeFreeze: Bool {
        get { self[ClashLiveResizeFreezeKey.self] }
        set { self[ClashLiveResizeFreezeKey.self] = newValue }
    }
}

private struct ClashProxyGridColumnReader: ViewModifier {
    @Binding var columns: Int
    let layout: ClashProxiesDisplayPreferences.Layout
    @Environment(\.clashLiveResizeFreeze) private var frozen
    @Environment(\.clashLatencyPulseGate) private var pulseGate
    @State private var adoption: ClashProxyColumnAdoption?

    func body(content: Content) -> some View {
        if #available(iOS 18, macOS 15, tvOS 18, *) {
             
             
             
             
             
            content.onGeometryChange(for: Int.self) { proxy in
                ClashProxyBrowsing.columnCount(
                    availableWidth: proxy.size.width,
                    layout: layout
                )
            } action: { measured in
                 
                 
                 
                 
                 
                 
                guard pulseGate?.isOpen ?? true else { return }
                var machine = adoption ?? ClashProxyColumnAdoption(columns: columns)
                if let adopt = machine.measured(measured, frozen: frozen) {
                    columns = adopt
                }
                adoption = machine
            }
            .onChange(of: frozen) { isFrozen in
                guard !isFrozen, var machine = adoption else { return }
                if let adopt = machine.resizeEnded() {
                    columns = adopt
                }
                adoption = machine
            }
        } else {
            content
        }
    }
}

 
private struct ClashProxyChoiceRefusal: Equatable {
    let group: String
    let message: String
}

 
 
 
 
 
 
 
 
public struct ClashLatencyPulse: Equatable, Sendable {
     
    public let results: [String: ClashProxyLatencyState]
     
    public let testing: Set<String>
     
     
     
     
     
    public let groupTerminals: [String: String]
     
     
     
    public let groupTerminalKeys: [String: String]
    public let completed: Int
    public let total: Int
    public let isTesting: Bool
     
     
     
     
     
     
    public let landed: Set<String>

    public init(
        results: [String: ClashProxyLatencyState],
        testing: Set<String>,
        groupTerminals: [String: String] = [:],
        groupTerminalKeys: [String: String] = [:],
        completed: Int,
        total: Int,
        isTesting: Bool,
        landed: Set<String> = []
    ) {
        self.results = results
        self.testing = testing
        self.groupTerminals = groupTerminals
        self.groupTerminalKeys = groupTerminalKeys
        self.completed = completed
        self.total = total
        self.isTesting = isTesting
        self.landed = landed
    }
}

 
 
 
 
 
 
 
 
 
struct ProxyDerivedIndex: Equatable {
    static let empty = ProxyDerivedIndex(
        source: nil, latencyByKey: [:], detailByKey: [:], sortedMembers: [:],
        membershipSignature: 0)

     
     
    let source: ClashProxiesSnapshot?
    private let latencyByKey: [String: ClashProxyLatencyState]
    private let detailByKey: [String: String]
    fileprivate let sortedMembers: [String: [ClashProxyMemberSnapshot]]
     
     
    fileprivate let membershipSignature: Int

    private init(
        source: ClashProxiesSnapshot?,
        latencyByKey: [String: ClashProxyLatencyState],
        detailByKey: [String: String],
        sortedMembers: [String: [ClashProxyMemberSnapshot]],
        membershipSignature: Int
    ) {
        self.source = source
        self.latencyByKey = latencyByKey
        self.detailByKey = detailByKey
        self.sortedMembers = sortedMembers
        self.membershipSignature = membershipSignature
    }

    private static func key(_ member: ClashProxyMemberSnapshot) -> String {
        (member.isGroup ? "g:" : "p:") + member.latencyKey
    }

    func latency(for member: ClashProxyMemberSnapshot) -> ClashProxyLatencyState? {
        latencyByKey[Self.key(member)]
    }

    func detail(for member: ClashProxyMemberSnapshot) -> String? {
        detailByKey[Self.key(member)]
    }

    func members(
        in group: ClashProxyGroupSnapshot,
        sortedBy sort: ClashProxiesDisplayPreferences.Sort
    ) -> [ClashProxyMemberSnapshot]? {
        guard sort != .standard else { return group.members }
        guard let ordered = sortedMembers["\(sort.rawValue):\(group.name)"]
        else { return nil }
         
         
         
        guard ordered.count != group.members.count else { return ordered }
        let kept = Set(group.members.map(\.name))
        let thinned = ordered.filter { kept.contains($0.name) }
         
        return thinned.count == group.members.count ? thinned : nil
    }

     
     
     
    func renderingMembers(
        in group: ClashProxyGroupSnapshot,
        for proxies: ClashProxiesSnapshot,
        sortedBy sort: ClashProxiesDisplayPreferences.Sort
    ) -> [ClashProxyMemberSnapshot] {
         
         
        guard let source else { return group.members }
        if Self.hasSameAnswers(source, proxies, sortedBy: sort) {
            return members(in: group, sortedBy: sort) ?? group.members
        }
         
         
         
         
         
         
         
         
        if membershipSignature == Self.membershipSignature(of: proxies),
           let ordered = members(in: group, sortedBy: sort) {
            return ordered
        }
        return group.members
    }

     
     
     
     
     
     
     
    private static func hasSameAnswers(
        _ lhs: ClashProxiesSnapshot,
        _ rhs: ClashProxiesSnapshot,
        sortedBy sort: ClashProxiesDisplayPreferences.Sort
    ) -> Bool {
        hasSameShape(lhs, rhs)
            && (sort != .delay || lhs.latencyByName == rhs.latencyByName)
    }

     
     
     
    fileprivate static func hasSameShape(_ lhs: ClashProxiesSnapshot, _ rhs: ClashProxiesSnapshot) -> Bool {
        lhs.groups == rhs.groups
            && lhs.hiddenGroups == rhs.hiddenGroups
            && lhs.isConnected == rhs.isConnected
    }

    func answersDetails(for proxies: ClashProxiesSnapshot) -> Bool {
        source.map { Self.hasSameShape($0, proxies) } ?? false
    }

     
     
     
    static func membershipSignature(of proxies: ClashProxiesSnapshot) -> Int {
        var hasher = Hasher()
        for group in proxies.groups {
            hasher.combine(group.name)
            for member in group.members {
                hasher.combine(member.name)
                 
                 
                hasher.combine(member.latencyKey)
            }
        }
        return hasher.finalize()
    }

     
     
     
     
     
     
     
     
     
    static func build(
        from proxies: ClashProxiesSnapshot,
        sortedBy sort: ClashProxiesDisplayPreferences.Sort = .delay,
        reusing previous: ProxyDerivedIndex? = nil,
        freshDelayOrder: Bool = false,
        orderingGroupNames: Set<String>? = nil
    ) -> ProxyDerivedIndex {
        var latencyByKey: [String: ClashProxyLatencyState] = [:]
        var detailByKey: [String: String] = [:]
        var sorted: [String: [ClashProxyMemberSnapshot]] = [:]
        let signature = membershipSignature(of: proxies)
        let reusableNameOrder =
            previous?.membershipSignature == signature ? previous : nil
        if let reusableNameOrder {
             
             
             
            sorted = reusableNameOrder.sortedMembers
        }
        for group in proxies.groups where
            orderingGroupNames?.contains(group.name) != false
        {
            for member in group.members {
                let memberKey = key(member)
                if latencyByKey[memberKey] == nil {
                    latencyByKey[memberKey] = proxies.displayedLatency(for: member)
                }
                 
                 
                 
                 
                if !member.isGroup, detailByKey[memberKey] == nil {
                    detailByKey[memberKey] = detail(of: member, in: proxies)
                }
            }
        }
         
         
         
        for group in proxies.groups where
            orderingGroupNames?.contains(group.name) != false
        {
            let nameKey = "\(ClashProxiesDisplayPreferences.Sort.name.rawValue):\(group.name)"
            if sort == .name {
                if let carried = reusableNameOrder?.sortedMembers[nameKey] {
                    sorted[nameKey] = carried
                } else {
                     
                     
                    sorted[nameKey] = ClashProxiesDisplayPreferences.Sort.name.ordered(
                        group.members, name: \.name, latency: { _ in .untested }
                    )
                }
            }
            if sort == .delay {
                let delayOrderKey =
                    "\(ClashProxiesDisplayPreferences.Sort.delay.rawValue):\(group.name)"
                 
                 
                 
                 
                 
                 
                 
                if !freshDelayOrder,
                   let carried = reusableNameOrder?.sortedMembers[delayOrderKey] {
                    sorted[delayOrderKey] = carried
                } else {
                    sorted[delayOrderKey] = ClashProxiesDisplayPreferences.Sort.delay.ordered(
                        group.members, name: \.name, latency: { latencyByKey[key($0)] ?? .untested }
                    )
                }
            }
        }
        return ProxyDerivedIndex(
            source: proxies,
            latencyByKey: latencyByKey,
            detailByKey: detailByKey,
            sortedMembers: sorted,
            membershipSignature: signature
        )
    }

    private static func detail(
        of member: ClashProxyMemberSnapshot, in proxies: ClashProxiesSnapshot
    ) -> String {
        guard member.isGroup,
              let route = proxies.resolvedDisplayRoute(for: member) else {
            return member.type
        }
        return "\(member.type) → \(route)"
    }
}

 
 
 
 
 
 
 
private struct ClashSweepControl<Icon: View>: View {
    let isConnected: Bool
    let height: CGFloat
    let pulse: AnyPublisher<ClashLatencyPulse, Never>?
    let onStart: () -> Void
    let onCancel: () -> Void
    let icon: (ClashSymbol) -> Icon

    @State private var isTesting: Bool
    @State private var completed: Int
    @State private var total: Int

    init(
        isConnected: Bool,
        isTesting: Bool,
        completed: Int,
        total: Int,
        height: CGFloat,
        pulse: AnyPublisher<ClashLatencyPulse, Never>?,
        onStart: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        icon: @escaping (ClashSymbol) -> Icon
    ) {
        self.isConnected = isConnected
        self.height = height
        self.pulse = pulse
        self.onStart = onStart
        self.onCancel = onCancel
        self.icon = icon
        _isTesting = State(initialValue: isTesting)
        _completed = State(initialValue: completed)
        _total = State(initialValue: total)
    }

    var body: some View {
        Button {
            if isTesting {
                isTesting = false
                onCancel()
            } else {
                isTesting = true
                completed = 0
                onStart()
            }
        } label: {
            Group {
                if isTesting {
                    HStack(spacing: 6) {
                        icon(.xmarkCircle)
                         
                         
                        Text(clash: .format(
                            "Stop %@",
                            ["\(completed)/\(total)"]
                        ))
                        .monospacedDigit()
                    }
                    .accessibilityLabel(
                        "Stop proxy latency test, \(completed) of \(total) complete"
                    )
                } else {
                    Label {
                        Text("Test All")
                    } icon: {
                        icon(.boltHorizontalCircle)
                    }
                }
            }
            .font(.subheadline.weight(.medium))
            .frame(
                minWidth: 68,
                minHeight: height,
                maxHeight: height
            )
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(!isConnected)
        .accessibilityHint(
            isConnected
                ? "Measures proxy latency"
                : "Connect before testing latency"
        )
        .accessibilityIdentifier(
            isTesting ? "proxies.testAll.cancel" : "proxies.testAll"
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

 
 
final class ClashProxiesPageScroll: @unchecked Sendable {
    var request: ClashScrollRequest?
}

 
private struct ClashProxiesPageScrollReader: View {
    let scroll: ClashProxiesPageScroll
    @Environment(\.clashScrollToID) private var request

    var body: some View {
        Color.clear
            .onAppear { scroll.request = request }
            .onChange(of: request) { scroll.request = $0 }
    }
}
