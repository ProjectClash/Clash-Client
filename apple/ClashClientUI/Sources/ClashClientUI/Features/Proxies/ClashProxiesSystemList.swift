import Combine
import SwiftUI
import ClashClientKit

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashProxiesSystemList<Icon: View>: View {
    let snapshot: AppleClientSnapshot
     
     
     
    @State private var choiceRefusal: ClashProxyChoiceRefusalNote?
     
    @State private var refusalDetail: ClashGroupRefusalDetail?
     
    @State private var locateRequest: ClashProxyLocateRequest?
    @Environment(\.locale) private var locale
    let palette: ClashProductPalette
     
    let send: (ClashProxiesCommand) -> Void
    @Binding var expanded: Set<String>
    let query: String
     
     
    let memberOrder: (ClashProxyGroupSnapshot) -> [ClashProxyMemberSnapshot]
    let latencyPulse: AnyPublisher<ClashLatencyPulse, Never>?
    let latencyPulseSnapshot: (() -> ClashLatencyPulse)?
    let density: ClashProxiesRowDensity
     
     
    let showsIconImages: Bool
    let icon: (ClashSymbol) -> Icon
     
     
    var index: ProxyDerivedIndex = .empty
    var sort: ClashProxiesDisplayPreferences.Sort = .standard
     
     
     
    var expandedValue: Set<String> = []

    private var browsedGroups: [ClashProxyGroupSnapshot] {
        snapshot.proxies.groups(matching: query)
    }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
         
         
        let _ = ClashPerf.count("proxies.list.body")
        return listBody
    }

     
     
     
     
    private var locatedGroupIsWhole: Bool? {
        guard let request = locateRequest, request.awaitsWhole else { return nil }
        return snapshot.proxies.group(named: request.group)?.hasEveryMember
    }

    private var listBody: some View {
        refusalSheet(ScrollViewReader { reader in
            listContent
                .onChange(of: locateRequest) { request in
                    guard let request else { return }
                     
                    DispatchQueue.main.asyncAfter(deadline: .now() + (request.opened ? 0.2 : 0)) {
                        withAnimation {
                            reader.scrollTo(ClashProxyBrowsing.memberAnchor(group: request.group, member: request.member),
                                            anchor: .center)
                        }
                    }
                }
                 
                 
                 
                 
                .onChange(of: locatedGroupIsWhole) { whole in
                    guard whole == true, let request = locateRequest else { return }
                    guard request.stillWanted() else { locateRequest = nil; return }
                    locateRequest = ClashProxyLocateRequest(group: request.group, member: request.member, opened: false)
                }
                .onChange(of: isSearching) { searching in
                    if searching, locateRequest?.awaitsWhole == true { locateRequest = nil }
                }
                .onChange(of: expanded) { open in
                    if let request = locateRequest, request.awaitsWhole, !open.contains(request.group) { locateRequest = nil }
                }
        })
    }

     
    private func refusalSheet<Content: View>(_ content: Content) -> some View {
        content.clashSheet(item: $refusalDetail) { detail in
            ClashGroupRefusalDetailView(detail: detail)
                .clashModalPresentation(.form)
        }
    }

     
     
    @ViewBuilder
    private func refusalLine(_ refusal: ClashGroupActionRefusal, group: String) -> some View {
        let line = Text(clash: refusal.result)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        if refusal.coreSentence != nil {
            Button {
                refusalDetail = ClashGroupRefusalDetail(group: group, refusal: refusal)
            } label: {
                HStack(spacing: ClashTheme.Spacing.compact) {
                    line
                    Image(systemName: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("proxies.refusal.\(group)")
        } else {
            line.accessibilityIdentifier("proxies.refusal.\(group)")
        }
    }

    private var listContent: some View {
        List {
            switch snapshot.proxies.effectiveCatalogState {
            case .disconnected:
                stateRow(
                    title: "Connect to View Proxies",
                    message: "The active connection supplies the current groups, nodes, and selections.",
                    symbol: .serverRack,
                    identifier: "proxies.state.empty"
                )
            case .loading:
                stateRow(
                    title: "Loading Proxies",
                    message: "Reading the current proxy catalog.",
                    symbol: .serverRack,
                    identifier: "proxies.state.loading",
                    isLoading: true
                )
            case .failed(let message):
                stateRow(
                    title: "Proxies Unavailable",
                    message: message,
                    symbol: .exclamationmarkTriangle,
                    identifier: "proxies.state.empty"
                )
            case .ready:
                readySections
            }

            if !snapshot.proxies.providers.isEmpty {
                providersSection
            }
        }
    }

     

    @ViewBuilder
    private var readySections: some View {
         
         
        if browsedGroups.isEmpty
            && !snapshot.proxies.showsOnlyUngroupedNodes(matching: query)
        {
            if snapshot.proxies.browsingSuppressedByDirectMode {
                Section {
                    ClashEmptyState(
                        title: "Direct Mode",
                        message:
                            "This mode sends all traffic without a proxy, so proxy groups and nodes are not listed.",
                        isLoading: false
                    ) {
                        icon(.arrowRight)
                    }
                    .accessibilityIdentifier("proxies.direct-mode-notice")
                }
            } else if isSearching {
                Section {
                    Text("No Results for \u{201C}\(query)\u{201D}")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("proxies.search.empty")
                }
            } else if snapshot.proxies.providers.isEmpty {
                stateRow(
                    title: "No Proxies",
                    message: "This profile has no proxy groups or nodes.",
                    symbol: .serverRack,
                    identifier: "proxies.state.empty"
                )
            }
        } else {
             
             
             
            let countSlot = ClashProxyGroupHeaderRow.countSlot(
                forLargest: snapshot.proxies.groups.map(\.memberCount).max() ?? 0
            )
            ForEach(browsedGroups) { group in
                groupSection(group, countSlot: countSlot)
            }
            if !snapshot.proxies.ungroupedNodes(matching: query).isEmpty {
                ungroupedSection
            }
        }
    }

    private func groupSection(_ group: ClashProxyGroupSnapshot, countSlot: String) -> some View {
         
         
         
        let isOpen = isSearching || expanded.contains(group.name)
        let toggle = {
            if expanded.contains(group.name) {
                expanded.remove(group.name)
                send(.setGroupExpanded(name: group.name, isExpanded: false))
            } else {
                expanded.insert(group.name)
                send(.setGroupExpanded(name: group.name, isExpanded: true))
                send(.setVisibleGroup(name: group.name))
            }
        }
        let header = { (drawsDisclosure: Bool) in
            ClashProxyGroupHeaderRow(
                group: group,
                isOpen: isOpen,
                initialLatency: snapshot.proxies.displayedLatency(forGroup: group),
                canTest: snapshot.proxies.isConnected,
                showsIconImages: showsIconImages,
                drawsDisclosure: drawsDisclosure,
                icon: { AnyView(icon($0)) },
                latencyPulse: latencyPulse,
                toggle: toggle,
                 
                 
                test: {
                    if isSearching {
                        send(.testShown([ClashProxiesShownMembers(group: group.name,
                                                                  members: group.members.map(\.name))]))
                    } else {
                        send(.testGroup(name: group.name))
                    }
                },
                showsUnpin: snapshot.proxies.offersUnpin(for: group),
                unpin: { send(.unpin(group: group.name)) },
                countSlot: countSlot,
                 
                 
                 
                 
                 
                locate: ClashProxyBrowsing.locatableSelection(of: group).map { member in
                    {
                        let opened = !isOpen
                        if opened { toggle() }
                         
                         
                         
                        let carried = group.carriesSelection
                        if carried { send(.loadMembers(group: group.name)) }
                        locateRequest = ClashProxyLocateRequest(group: group.name, member: member, opened: opened,
                                                                awaitsWhole: carried)
                    }
                }
            )
            .equatable()
        }
         
         
         
         
         
        return Section {
            header(true)
             
             
             
             
            if let refusal = snapshot.proxies.actionRefusals[group.name] {
                refusalLine(refusal, group: group.name)
            } else if choiceRefusal?.group == group.name, let message = choiceRefusal?.message {
                Text(clash: .copy(message))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("proxies.refusal.\(group.name)")
            }
            if isOpen {
                memberRows(group)
            }
        }
    }

    @ViewBuilder
    private func memberRows(_ group: ClashProxyGroupSnapshot) -> some View {
        let current = group.currentSelection
         
         
         
        ForEach(memberOrder(group)) { member in
            memberRow(member, in: group, current: current)
                .id(ClashProxyBrowsing.memberAnchor(group: group.name, member: member.name))
        }
         
         
        if !group.hasEveryMember, !isSearching {
            Button {
                send(.loadMembers(group: group.name))
            } label: {
                Text(clash: .format("Show all %@ nodes", [group.memberCount.formatted(.number.locale(locale))]))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(.tint)
            .accessibilityIdentifier("proxies.showAll.\(group.name)")
        }
    }

    private func memberRow(_ member: ClashProxyMemberSnapshot, in group: ClashProxyGroupSnapshot,
                           current: String?) -> some View {
            ClashProxyMemberListRow(
                row: ClashProxyFrozenRow(member, in: group, of: snapshot.proxies),
                initialLatency: snapshot.proxies
                    .displayedLatency(for: member).normalized,
                initialRoute: ClashProxyFrozenRow.route(of: member, in: snapshot.proxies),
                failureCategory:
                    snapshot.proxies.failureCategories[member.name] ?? "",
                isCurrent: member.name == current,
                canTest: snapshot.proxies.isConnected,
                density: density,
                latencyPulse: latencyPulse,
                latencyPulseSnapshot: latencyPulseSnapshot,
                select: {
                     
                     
                     
                    guard group.allowsMemberChoice else {
                        if let reason = group.memberChoiceRefusal {
                            choiceRefusal = ClashProxyChoiceRefusalNote(group: group.name, message: reason)
                        }
                        return
                    }
                    choiceRefusal = nil
                    send(.select(group: group.name, member: member.name))
                },
                editNode: snapshot.proxies.canEdit(member)
                    ? { send(.editMember(name: member.name)) }
                    : nil,
                 
                 
                 
                 
                 
                testNode: { send(.testMember(name: member.name, group: group.name)) },
                inspectNode: ClashProxyBrowsing.inspects(member)
                    ? { send(.inspectMember(name: member.name)) }
                    : nil,
                 
                 
                showsLatency: !snapshot.proxies.isEmptyGroup(member),
                nodeScripts: snapshot.proxies.scriptsForNodes,
                runScript: { send(.runNodeScript(id: $0.id, node: member.name)) }
            )
            .equatable()
        }

    private var ungroupedSection: some View {
        let nodes = snapshot.proxies.ungroupedNodes(matching: query)
        let isOpen = ClashProxyBrowsing.showsMembers(
            of: ClashProxyBrowsing.ungroupedKey,
            expanded: expanded,
            isSearching: isSearching
        )
        return Section {
             
             
             
            ClashUngroupedHeaderRow(
                count: snapshot.proxies.ungrouped.count,
                isOpen: isOpen,
                icon: icon
            ) {
                if expanded.contains(ClashProxyBrowsing.ungroupedKey) {
                    expanded.remove(ClashProxyBrowsing.ungroupedKey)
                    send(.setGroupExpanded(name: ClashProxyBrowsing.ungroupedKey, isExpanded: false))
                } else {
                    expanded.insert(ClashProxyBrowsing.ungroupedKey)
                    send(.setGroupExpanded(name: ClashProxyBrowsing.ungroupedKey, isExpanded: true))
                }
            }
            if isOpen {
                 
                 
                ForEach(nodes) { node in
                    ClashProxyMemberListRow(
                        row: ClashProxyFrozenRow(
                            name: node.name,
                            type: node.type,
                            chainedThrough: nil,
                            groupName: nil
                        ),
                        initialLatency: .untested,
                        failureCategory: "",
                        isCurrent: false,
                        canTest: snapshot.proxies.isConnected,
                        density: density,
                        latencyPulse: latencyPulse,
                        latencyPulseSnapshot: latencyPulseSnapshot,
                        select: nil,
                        editNode: snapshot.proxies.editableMembers.contains(node.name)
                            ? { send(.editMember(name: node.name)) }
                            : nil,
                        testNode: { send(.testMember(name: node.name)) },
                        inspectNode: ClashProxyBrowsing.inspects(
                            ClashProxyMemberSnapshot(name: node.name, type: node.type)
                        )
                            ? { send(.inspectMember(name: node.name)) }
                            : nil,
                        nodeScripts: snapshot.proxies.scriptsForNodes,
                        runScript: { send(.runNodeScript(id: $0.id, node: node.name)) }
                    )
                    .equatable()
                }
            }
        }
    }

     

    private var providersSection: some View {
        Section {
            ForEach(snapshot.proxies.providers) { provider in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: ClashTheme.Spacing.row) {
                        ClashRegionalFlag.label(provider.title, pointSize: 17, relativeTo: .body)
                            .font(.body.weight(.semibold))
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
                .accessibilityIdentifier("proxies.provider.\(provider.name)")
            }
        } header: {
            Text(clash: providersTitle)
        }
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

     

    private func stateRow(
        title: String,
        message: String,
        symbol: ClashSymbol,
        identifier: String,
        isLoading: Bool = false
    ) -> some View {
        Section {
            ClashEmptyState(
                title: title,
                message: message,
                isLoading: isLoading
            ) {
                icon(symbol)
            }
            .accessibilityIdentifier(identifier)
        }
    }
}

 
 
 
public enum ClashProxiesRowDensity: String, Sendable {
     
    case standard
     
    case compact

     
     
     
    public static func from(
        _ preferences: ClashProxiesDisplayPreferences
    ) -> ClashProxiesRowDensity {
        switch preferences.size {
        case .standard: return .standard
        case .compact, .minimal: return .compact
        }
    }
}

 
 
 
struct ClashProxyFrozenRow: Equatable, Identifiable {
    var id: String { name }
    let name: String
    let type: String
    let chainedThrough: String?
    let groupName: String?
     
     
    var isEmptyGroup: Bool = false
     
     
    var placeholderType: String? = nil
     
     
     
     
    var readingKey: String? = nil
     
     
    var emptyNote: String? = nil
}

extension ClashProxyFrozenRow {
     
     
     
     
    static func route(
        of member: ClashProxyMemberSnapshot,
        in proxies: ClashProxiesSnapshot
    ) -> String? {
        guard member.isGroup,
              let route = proxies.resolvedDisplayRoute(for: member),
              route != member.name else { return nil }
        return route
    }

     
     
     
     
     
     
     
    init(
        _ member: ClashProxyMemberSnapshot,
        in group: ClashProxyGroupSnapshot,
        of proxies: ClashProxiesSnapshot
    ) {
        self.init(
            name: member.name,
            type: member.type,
            chainedThrough: member.chainedThrough,
            groupName: group.name,
            isEmptyGroup: proxies.isEmptyGroup(member),
            placeholderType: member.placeholderType,
            readingKey: member.isGroup ? nil : member.latencyKey,
            emptyNote: proxies.isEmptyGroup(member) ? proxies.group(named: member.name)?.emptyNote : nil
        )
    }
}

 
 
 
 
struct ClashProxyMemberListRow: View, Equatable {
    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.row == b.row
            && a.initialLatency == b.initialLatency
            && a.initialRoute == b.initialRoute
             
             
             
            && a.failureCategory == b.failureCategory
            && a.isCurrent == b.isCurrent
            && a.canTest == b.canTest
            && a.showsLatency == b.showsLatency
            && a.density == b.density
             
             
            && (a.editNode == nil) == (b.editNode == nil)
             
            && a.nodeScripts == b.nodeScripts
    }

    let row: ClashProxyFrozenRow
    let initialLatency: ClashProxyLatencyState
     
     
     
     
    var initialRoute: String? = nil

     
     
     
     
     
    let failureCategory: String

    let isCurrent: Bool
    let canTest: Bool
    let density: ClashProxiesRowDensity
    let latencyPulse: AnyPublisher<ClashLatencyPulse, Never>?
    let latencyPulseSnapshot: (() -> ClashLatencyPulse)?
    let select: (() -> Void)?
    let editNode: (() -> Void)?
    let testNode: (() -> Void)?
     
     
    let inspectNode: (() -> Void)?

     
    var showsLatency: Bool = true

     
     
    var nodeScripts: [ClashProxyNodeScript] = []
    var runScript: ((ClashProxyNodeScript) -> Void)? = nil

     
    var offersScripts: Bool { !nodeScripts.isEmpty && runScript != nil }

    @State private var liveLatency: ClashProxyLatencyState?
     
     
    @State private var settledLatency: ClashProxyLatencyState?
     
    @State private var latencyTap: ClashLatencyTap?
    @State private var liveRoute: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var shownLatency: ClashProxyLatencyState {
        liveLatency ?? initialLatency
    }

     
     
    private func setLive(_ value: ClashProxyLatencyState?) {
        let settled = ClashLatencySlotFace.settled(writing: value, over: shownLatency, kept: settledLatency)
        if settled != settledLatency { settledLatency = settled }
        liveLatency = value
    }

     
     
     
    private var shownRoute: String? {
        guard let route = liveRoute ?? initialRoute, route != row.name else { return nil }
        return route
    }

    var body: some View {
        let _ = ClashPerf.count("proxies.list.row")
         
         
         
        return HStack(spacing: 0) {
    Button {
                select?()
            } label: {
                HStack(spacing: ClashTheme.Spacing.row) {
                     
                     
                     
                    Image(systemName: ClashSymbol.checkmark.rawValue)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tint)
                        .opacity(isCurrent ? 1 : 0)
                        .frame(width: 18)
                        .accessibilityHidden(!isCurrent)
                    if density == .standard {
                        VStack(alignment: .leading, spacing: 2) {
                             
                             
                             
                             
                            ClashRegionalFlag.label(row.name, pointSize: 15, relativeTo: .subheadline)
                                .font(.subheadline)
                                 
                                 
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                                .truncationMode(.middle)
                            subtitle
                            if dynamicTypeSize.isAccessibilitySize {
                                latencyControl(stacked: true)
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            ClashRegionalFlag.label(row.name, pointSize: 15, relativeTo: .subheadline)
                                .font(.subheadline)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                                .truncationMode(.middle)
                            if dynamicTypeSize.isAccessibilitySize {
                                latencyControl(stacked: true)
                            }
                        }
                    }
                    Spacer(minLength: 8)
                    if !dynamicTypeSize.isAccessibilitySize {
                        latencyControl(stacked: false)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(select == nil)
            .accessibilityElement(children: .combine)
            .accessibilityValue(isCurrent ? "Selected" : "")
            .accessibilityIdentifier("proxies.member.\(row.name)")
            .contextMenu {
                if let editNode {
                    Button { editNode() } label: {
                        Label {
                            Text(ClashCopy.key("Edit Node"))
                        } icon: {
                            Image(systemName: ClashSymbol.pencil.rawValue)
                        }
                    }
                }
                if offersScripts, let runScript {
                     
                     
                    Menu {
                        ForEach(nodeScripts) { script in
                            Button { runScript(script) } label: {
                                Label {
                                    Text(verbatim: script.name)
                                } icon: {
                                    Image(systemName: script.symbol ?? ClashSymbol.curlybraces.rawValue)
                                }
                            }
                        }
                    } label: {
                        Label {
                            Text(ClashCopy.key("Scripts"))
                        } icon: {
                            Image(systemName: ClashSymbol.curlybraces.rawValue)
                        }
                    }
                    .accessibilityIdentifier("proxies.member.scripts")
                }
            }
            .onAppear {
                 
                 
                 
                if liveLatency == nil, let latest = latencyPulseSnapshot?() {
                    apply(latest)
                }
            }
            .onReceive(
                latencyPulse
                    ?? Empty<ClashLatencyPulse, Never>().eraseToAnyPublisher()
            ) { batch in
                apply(batch)
            }
             
             
             
            .task(id: latencyTap?.at) {
                guard let tap = latencyTap else { return }
                try? await Task.sleep(nanoseconds: UInt64(ClashLatencyTap.expiry * 1_000_000_000))
                guard latencyTap == tap, liveLatency == .testing else { return }
                setLive(tap.before)
                latencyTap = nil
            }
            if let inspectNode {
                Button(action: inspectNode) {
                    Image(systemName: ClashSymbol.infoCircle.rawValue)
                        .font(.body)
                        .foregroundStyle(Color.blue)
                        .frame(minWidth: ClashTheme.Control.proxyRowTrailingControlWidth, maxHeight: .infinity, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text(ClashCopy.key("Node Details")))
                .accessibilityIdentifier("proxies.member.info.\(row.name)")
            }
        }
    }

     
     
    @ViewBuilder
    private func latencyControl(stacked: Bool) -> some View {
         
         
        if showsLatency {
            if let testNode {
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                Button {
                     
                     
                     
                     
                    guard canTest, ClashLatencyTap.canTap(shown: shownLatency, tap: latencyTap, now: Date()) else { return }
                    latencyTap = ClashLatencyTap(before: latencyTap?.before ?? shownLatency, at: Date())
                    testNode()
                     
                     
                     
                     
                     
                     
                     
                     
                    setLive(.testing)
                } label: {
                    if stacked {
                         
                         
                         
                         
                        latencyBadge
                            .frame(minWidth: ClashTheme.Control.proxyRowTrailingControlWidth, minHeight: ClashTheme.Control.minimumHitTarget, alignment: .leading)
                            .contentShape(Rectangle())
                    } else {
                        latencyBadge
                            .frame(minWidth: ClashTheme.Control.proxyRowTrailingControlWidth, maxHeight: .infinity, alignment: .trailing)
                            .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
                 
                 
                 
                 
                .accessibilityIdentifier("proxies.member.latency.\(row.name)")
            } else {
                latencyBadge
            }
        }
    }

    private func apply(_ batch: ClashLatencyPulse) {
         
         
         
         
        if !batch.isTesting {
             
            liveRoute = batch.groupTerminals[row.name].flatMap { $0.isEmpty ? nil : $0 }
        }
         
         
         
         
         
         
         
         
         
        let latencyKey = shownRoute ?? row.name
         
         
        let lookupKey = shownRoute == nil
            ? row.readingKey ?? latencyKey
            : shownRoute == batch.groupTerminals[row.name]
                ? batch.groupTerminalKeys[row.name] ?? latencyKey
                : latencyKey
        if !batch.isTesting {
             
             
             
            if let landed = ClashLatencyKey.reading(lookupKey, in: batch.results),
               latencyTap == nil || ClashLatencyKey.isNamed(lookupKey, in: batch.landed) {
                setLive(landed)
                latencyTap = nil
            } else if liveLatency == .testing {
                 
                 
                 
                 
                 
                let settled = latencyTap?.afterSilentPulse(now: Date()) ?? .untested
                setLive(settled)
                if settled != .testing { latencyTap = nil }
            }
        } else if let live = ClashLatencySlotFace.liveReading(testingPulse: batch, key: lookupKey, tapped: latencyTap != nil) {
            setLive(live)
            if live != .testing { latencyTap = nil }
        }
    }


    @ViewBuilder
    private var subtitle: some View {
        if let placeholder = row.placeholderType {
             
             
            HStack(spacing: 4) {
                Text(clash: .verbatim(placeholder))
                Text(clash: .copy("· Not supported"))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        } else if row.isEmptyGroup {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(clash: .verbatim(row.type.uppercased()))
                    Text(clash: .copy("· No nodes"))
                }
                .lineLimit(1)
                 
                 
                if let note = row.emptyNote {
                    Text(clash: .verbatim(note))
                        .lineLimit(2)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        } else if let entry = row.chainedThrough {
            ClashRegionalFlag.label("\(entry) → \(row.name)", pointSize: 11, relativeTo: .caption2)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        } else if let route = shownRoute {
             
             
             
             
            HStack(spacing: 4) {
                Text(clash: .verbatim(row.type.uppercased()))
                    .fixedSize()
                ClashRegionalFlag.label("· \(route)", pointSize: 11, relativeTo: .caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        } else {
            Text(clash: .verbatim(row.type.uppercased()))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

     
     
     
     
     
     
     
     
     
     
    private var latencyBadge: some View {
        let slot = ClashLatencySlotFace(shown: shownLatency, settled: settledLatency)
        return ZStack(alignment: .trailing) {
            badgeFace(slot.face)
                .opacity(slot.isTesting ? 0 : 1)
                .accessibilityHidden(slot.isTesting)
            if slot.isTesting {
                ClashLatencySpinner(diameter: 15)
            }
        }
    }

    @ViewBuilder
    private func badgeFace(_ face: ClashProxyLatencyState) -> some View {
        switch face {
        case .untested, .testing:
            Image(systemName: ClashSymbol.bolt.rawValue)
                .font(.body)
                 
                 
                .foregroundStyle(canTest ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .accessibilityLabel("Test latency")
        case .measured(let milliseconds):
            Text(clash: .verbatim("\(milliseconds)ms"))
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                 
                .fixedSize()
                 
                 
                .foregroundStyle(
                    face.tier == .fast
                        ? Color.green
                        : face.tier == .slow ? .yellow : .orange
                )
        case .failed, .timedOut:
             
             
             
             
             
             
             
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .accessibilityLabel(
                    Text(clash: .copy(ClashProbeFailureCopy.badge(
                        for: face == .timedOut
                            ? "timeout"
                            : failureCategory
                    )))
                )
        }
    }
}

 
 
struct ClashProxyLocateRequest: Equatable {
    let group: String
    let member: String
    let opened: Bool
     
     
    var awaitsWhole = false
    let id = UUID()
    let at = Date()
     
     
    static let patience: TimeInterval = 10

    func stillWanted(now: Date = Date()) -> Bool { now.timeIntervalSince(at) <= Self.patience }
}

struct ClashProxyGroupHeaderRow: View, Equatable {
    nonisolated static func == (a: Self, b: Self) -> Bool {
         
         
         
         
         
         
        a.group == b.group && a.isOpen == b.isOpen && a.canTest == b.canTest
            && a.initialLatency == b.initialLatency
            && a.showsIconImages == b.showsIconImages
            && a.drawsDisclosure == b.drawsDisclosure
            && a.showsUnpin == b.showsUnpin
            && a.countSlot == b.countSlot
            && (a.locate == nil) == (b.locate == nil)
    }

    let group: ClashProxyGroupSnapshot
    let isOpen: Bool
     
     
     
    let initialLatency: ClashProxyLatencyState
     
     
     
    let canTest: Bool
    let showsIconImages: Bool
     
     
    let drawsDisclosure: Bool
    let icon: (ClashSymbol) -> AnyView
    let latencyPulse: AnyPublisher<ClashLatencyPulse, Never>?
    let toggle: () -> Void
    let test: () -> Void
     
     
     
     
    let showsUnpin: Bool
    let unpin: () -> Void
     
    var countSlot = "000"
     
     
    var locate: (() -> Void)? = nil

     
     
     
     
     
     
    static func countSlot(forLargest count: Int) -> String {
        count > 999 ? "999+" : String(repeating: "0", count: String(max(count, 0)).count)
    }

     
     
     
     
     
     
    struct LiveLatency: Equatable {
        let terminal: String
        let state: ClashProxyLatencyState
    }

     
     
     
    static func displayedLatency(
        live: LiveLatency?,
        route: String?,
        initial: ClashProxyLatencyState
    ) -> ClashProxyLatencyState {
        if let live, live.terminal == route { return live.state }
        return initial
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
                connected: canTest
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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var live: LiveLatency?

    private var latency: ClashProxyLatencyState {
        Self.displayedLatency(
            live: live,
            route: group.resolvedRuntimeRoute ?? group.runtimeSelection,
            initial: initialLatency
        )
    }

    var body: some View {
        let _ = ClashPerf.count("proxies.list.header")
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                 
                 
                 
                 
                VStack(alignment: .leading, spacing: 0) {
                    titleButton
                    HStack(spacing: 8) {
                        unfixButton
                        locateButton
                        testButton
                        Spacer(minLength: 8)
                        countButton
                    }
                }
            } else {
                HStack(spacing: 8) {
                    titleButton
                    unfixButton
                    locateButton
                    testButton
                    countButton
                }
            }
        }
        .onReceive(
            latencyPulse
                ?? Empty<ClashLatencyPulse, Never>().eraseToAnyPublisher()
        ) { batch in
            guard !group.isEmpty, let terminal = batch.groupTerminals[group.name] else {
                if !batch.isTesting { live = nil }
                return
            }
             
             
             
            let key = batch.groupTerminalKeys[group.name] ?? terminal
            if let landed = ClashLatencyKey.reading(key, in: batch.results) {
                live = LiveLatency(terminal: terminal, state: landed)
            } else if ClashLatencyKey.isTesting(key, in: batch.testing) || batch.testing.contains(terminal) {
                live = LiveLatency(terminal: terminal, state: .testing)
            } else if !batch.isTesting {
                 
                 
                 
                 
                live = LiveLatency(terminal: terminal, state: .untested)
            }
        }
    }

    private var titleButton: some View {
        Button(action: toggle) {
            HStack(spacing: ClashTheme.Spacing.row) {
                 
                 
                 
                 
                 
                groupIcon
                VStack(alignment: .leading, spacing: 2) {
                    ClashRegionalFlag.label(group.name, pointSize: 17, relativeTo: .body)
                        .font(.body.weight(.semibold))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                        .truncationMode(.middle)
                    Group {
                         
                         
                         
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 2) { subtitleParts }
                        } else {
                            HStack(spacing: 4) { subtitleParts }
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    if group.isEmpty, let note = group.emptyNote {
                         
                         
                        Text(clash: .verbatim(note))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("proxies.group.emptyNote.\(group.name)")
                    }
                }
                 
                 
                 
                 
                 
                 
                 
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("proxies.group.\(group.name)")
    }

     
    @ViewBuilder
    private var subtitleParts: some View {
         
         
        Text(clash: .verbatim(group.type.uppercased()))
            .fixedSize()
        if group.isEmpty {
            Text(clash: .copy("· No nodes"))
        } else if let now = group.currentSelection {
            ClashRegionalFlag.label("· \(now)", pointSize: 11, relativeTo: .caption2)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        if !group.isEmpty,
           case .measured(let milliseconds) = latency {
            Text(clash: .verbatim("(\(milliseconds) ms)"))
                .monospacedDigit()
                .fixedSize()
                .foregroundStyle(ClashProxyLatencyPalette.color(milliseconds))
                .accessibilityLabel("\(milliseconds)ms")
        }
    }

    @ViewBuilder
    private var unfixButton: some View {
         
         
         
        if showsUnpin {
            Button(action: unpin) {
                Text("Unfix")
                    .font(.caption.weight(.semibold))
                     
                    .fixedSize()
                    .frame(height: 44)
                    .contentShape(Rectangle().inset(by: -8))
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("proxies.unfix.\(group.name)")
        }
    }

    @ViewBuilder
    private var locateButton: some View {
         
         
         
         
         
         
         
         
        if let locate {
            Button(action: locate) {
                Image(systemName: ClashSymbol.scope.rawValue)
                    .font(.body)
                    .frame(minWidth: 28, minHeight: 44)
                    .contentShape(Rectangle().inset(by: -8))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(ClashCopy.key("Jump to Current Node")))
            .accessibilityIdentifier("proxies.locate.\(group.name)")
        }
    }

    private var testButton: some View {
        Button {
            test()
             
             
            live = LiveLatency(terminal: group.resolvedRuntimeRoute ?? group.runtimeSelection ?? "",
                               state: .testing)
        } label: {
             
             
             
            ZStack {
                Image(systemName: ClashSymbol.bolt.rawValue)
                     
                     
                    .font(.body)
                    .opacity(latency == .testing ? 0 : 1)
                    .accessibilityHidden(latency == .testing)
                ClashLatencySpinner(isSpinning: latency == .testing, diameter: 15)
            }
             
             
             
            .frame(minWidth: 28, minHeight: 44)
            .contentShape(Rectangle().inset(by: -8))
        }
        .buttonStyle(.borderless)
        .disabled(!canTest)
        .accessibilityLabel("Test \(group.name)")
        .accessibilityIdentifier("proxies.testGroup.\(group.name)")
    }

    private var countButton: some View {
         
         
         
        Button(action: toggle) {
            HStack(spacing: 4) {
                 
                 
                 
                 
                 
                Text(clash: .verbatim(countSlot))
                    .font(.body)
                    .monospacedDigit()
                    .hidden()
                    .overlay(alignment: .trailing) {
                        Text(clash: .verbatim(
                            group.memberCount > 999 ? "999+" : "\(group.memberCount)"
                        ))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                    }
                if drawsDisclosure {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
    }
}

 
struct ClashProxyChoiceRefusalNote: Equatable {
    let group: String
    let message: String
}

 
 
 
 
 
 
 
 
 
 
 
 
extension ClashProxiesSystemList: @MainActor Equatable {
    static func == (a: Self, b: Self) -> Bool {
        let equal = a.snapshot.proxies == b.snapshot.proxies
            && a.snapshot.connection == b.snapshot.connection
            && a.expandedValue == b.expandedValue
            && a.query == b.query
            && a.density == b.density
            && a.showsIconImages == b.showsIconImages
            && a.palette == b.palette
            && a.index == b.index
            && a.sort == b.sort
        ClashPerf.count(equal ? "proxies.list.eq.hit" : "proxies.list.eq.miss")
        return equal
    }
}

 
struct ClashGroupRefusalDetail: Identifiable {
    let group: String
    let refusal: ClashGroupActionRefusal
    var id: String { group }
}

 
struct ClashGroupRefusalDetailView: View {
    let detail: ClashGroupRefusalDetail
     
     
    @StateObject private var dismiss = ClashDismissHandle()

    var body: some View {
         
         
         
        ClashSingleColumnNavigationContainer {
            List {
                Section {
                    sentence
                } header: {
                    Text(verbatim: detail.group)
                }
            }
            .clashPageTitle(detail.refusal.result)
            .clashToolbarUnlessInPanel {
                ToolbarItem(placement: .cancellationAction) {
                    ClashSheetCloseButton {
                        dismiss()
                    }
                }
            }
        }
        .modifier(ClashRefusalDetailDetents())
        .clashCapturesDismiss(dismiss)
    }

    @ViewBuilder
    private var sentence: some View {
        let text = Text(verbatim: detail.refusal.coreSentence ?? "")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("proxies.refusal.detail.\(detail.group)")
#if os(tvOS)
        text
#else
        text.textSelection(.enabled)
#endif
    }
}

 
private struct ClashRefusalDetailDetents: ViewModifier {
    func body(content: Content) -> some View {
#if os(iOS)
        if #available(iOS 16.0, *) {
            content.presentationDetents([.medium, .large])
        } else {
            content
        }
#else
        content
#endif
    }
}

 
 
 
 
 
 
 
struct ClashLatencyTap: Equatable {
     
     
    let before: ClashProxyLatencyState
    let at: Date

     
    static let settling: TimeInterval = 2
     
     
    static let expiry: TimeInterval = 15

    init(before: ClashProxyLatencyState, at: Date) {
         
        self.before = before == .testing ? .untested : before
        self.at = at
    }

     
    func afterSilentPulse(now: Date) -> ClashProxyLatencyState {
        now.timeIntervalSince(at) < Self.settling ? .testing : before
    }

     
     
    static func canTap(shown: ClashProxyLatencyState, tap: ClashLatencyTap?, now: Date) -> Bool {
        guard shown == .testing else { return true }
        guard let tap else { return false }
        return now.timeIntervalSince(tap.at) >= expiry
    }
}
