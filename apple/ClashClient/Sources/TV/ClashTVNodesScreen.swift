import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashTVNodesScreen: View {
    @Binding var state: ClashTVProductState
     
     
     
    var onPin: ((_ member: String, _ group: String) -> Void)?
     
     
     
    var onUnpin: ((ClashProxyGroupSnapshot) -> Void)?
     
     
    var onTestAll: ((ClashProxyGroupSnapshot) -> Void)?
     
    var onTest: ((ClashProxyMemberSnapshot, ClashProxyGroupSnapshot) -> Void)?
     
     
     
    var onNeedMoreMembers: ((String) -> Void)? = nil
     
     
     
     
    var opening: String? = nil
     
     
    var openingState: OpeningGroup = .listed

    @State private var shownGroupName: String?

     
     
     
     
    private enum HeaderButton: Hashable { case unfix, testAll }
    @FocusState private var headerFocus: HeaderButton?

     
     
    private var browsingMode: ClashTVOutboundMode {
        let mode = state.observations.mode.hasValue ? state.outboundMode : .rule
        return Self.browsingMode(mode, opening: opening)
    }

     
     
     
     
    private func memberMode(_ group: ClashProxyGroupSnapshot) -> ClashTVOutboundMode {
        Self.memberMode(for: group.name, browsing: browsingMode, opening: opening)
    }

     
    private var visibleGroups: [ClashProxyGroupSnapshot] {
        guard state.observations.proxies.hasValue else { return [] }
        return Self.visibleGroups(state.proxyGroups, mode: browsingMode, opening: opening, hidden: state.hiddenProxyGroups)
    }

     
     
     
     
     
    private var shownGroup: ClashProxyGroupSnapshot? {
        visibleGroups.first { $0.name == shownGroupName } ?? visibleGroups.first
    }

    var body: some View {
        switch Self.shown(openingState, opening: opening, in: state.proxyGroups + state.hiddenProxyGroups) {
        case .reading:
            VStack(alignment: .leading, spacing: 12) {
                 
                ClashTVObservationNote(observations: [state.observations.proxies])
                ProgressView("Loading GLOBAL")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .missing:
            VStack(alignment: .leading, spacing: 12) {
                ClashTVObservationNote(observations: [state.observations.proxies])
                 
                Text(ClashTunnelOutboundMode.globalNotLoadedKey.localizedForTelevision)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .listed:
            browser
        }
    }

     
     
    enum OpeningGroup: Equatable { case listed, reading, missing }

     
     
     
     
    static func shown(_ state: OpeningGroup, opening name: String?, in groups: [ClashProxyGroupSnapshot]) -> OpeningGroup {
        guard let name, state != .listed, !groups.contains(where: { $0.name == name }) else { return .listed }
        return state
    }

    private var browser: some View {
        VStack(alignment: .leading, spacing: 12) {
            ClashTVObservationNote(observations: [state.observations.proxies, state.observations.latency, state.observations.mode])
            HStack(alignment: .top, spacing: 40) {
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                if vacancy != .directMode {
                    groups
                        .frame(maxWidth: 520)
                }
                grid
                    .focusSection()
            }
        }
    }

    private var vacancy: Vacancy? {
        guard state.observations.proxies.hasValue else { return .noGroups }
        return Self.vacancy(mode: browsingMode, visibleGroups: visibleGroups)
    }

     

    private var groups: some View {
        List {
            Section("Policy groups") {
                ForEach(visibleGroups) { group in
                    Button {
                        shownGroupName = group.name
                    } label: {
                         
                         
                         
                         
                         
                         
                         
                         
                         
                         
                         
                         
                         
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(group.name)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Text(Self.groupRowValue(for: group, state: state))
                                    .lineLimit(1)
                                    .fixedSize()
                                    .monospacedDigit()
                                    .font(Self.detailFont)
                                    .foregroundStyle(.secondary)
                            }
                             
                             
                             
                             
                            HStack(spacing: 0) {
                                Text(Self.groupRowTypeLead(for: group))
                                    .lineLimit(1)
                                    .fixedSize()
                                if let selection = Self.groupRowSelection(for: group) {
                                    Text(selection)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                            .font(Self.detailFont)
                            .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                     
                     
                     
                     
                    .onClashTVFocus { shownGroupName = group.name }
                    .accessibilityIdentifier("tvos.nodes.group.\(group.name)")
                }
            }
        }
        .listStyle(.grouped)
        .safeAreaPadding(.horizontal, 44)
    }

     

    @ViewBuilder
    private var grid: some View {
        if let group = shownGroup {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Self.header(for: group, mode: memberMode(group)))
                        .font(.caption)
                        .textCase(.uppercase)
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 20)
                    if Self.offersUnpin(for: group) {
                         
                         
                         
                         
                         
                        Button {
                            headerFocus = .testAll
                            if let onUnpin {
                                onUnpin(group)
                            } else {
                                state.unpin(group: group.name)
                            }
                        } label: {
                            Text(Self.unfixTitle)
                                .font(.caption)
                        }
                        .accessibilityIdentifier("tvos.nodes.unfix")
                        .focused($headerFocus, equals: .unfix)
                    }
                    if Self.offersTestAll(for: group) {
                         
                         
                         
                         
                         
                        Button {
                            onTestAll?(group)
                        } label: {
                            Text(Self.testAllTitle(isTesting: Self.isTesting(group, state: state)))
                                .font(.caption)
                        }
                        .accessibilityIdentifier("tvos.nodes.test-all")
                        .focused($headerFocus, equals: .testAll)
                    }
                }
                 
                 
                 
                 
                 
                 
                .focusSection()
                if let refusal = group.memberChoiceRefusal {
                     
                    Text(refusal.localizedForTelevision)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                 
                 
                if let feedback = state.feedback(for: [.pin, .unpin, .test]) {
                    ClashTVFeedbackLine(presentation: feedback)
                }
                ScrollView {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: Self.columnCount(for: group, mode: memberMode(group))),
                        alignment: .leading,
                        spacing: 20
                    ) {
                        ForEach(Self.browsedMembers(of: group, mode: memberMode(group))) { member in
                            cell(member, in: group)
                                .onAppear {
                                    if Self.needsMoreMembers(group, after: member.name) { onNeedMoreMembers?(group.name) }
                                }
                        }
                    }
                     
                     
                     
                     
                     
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            switch vacancy {
            case .directMode:
                directModeNotice
            case .noGroups, .none:
                Text(state.observations.proxies.hasValue ? String(localized: "No policy groups in this configuration") : "—")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

     
     
     
     
     
     
    private var directModeNotice: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: ClashSymbol.arrowLeftAndRight.rawValue)
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Direct Mode")
                .font(.title3)
            Text("This mode sends all traffic without a proxy, so proxy groups and nodes are not listed.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("tvos.nodes.direct-mode-notice")
    }

    private func cell(_ member: ClashProxyMemberSnapshot, in group: ClashProxyGroupSnapshot) -> some View {
        let inUse = group.currentSelection == member.name
        return Button {
            if let onPin {
                onPin(member.name, group.name)
            } else {
                Self.select(member: member.name, in: group.name, state: &state)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                     
                     
                     
                     
                     
                    Text(member.name)
                        .font(Self.nameFont)
                        .lineLimit(Self.nameLineLimit)
                        .minimumScaleFactor(Self.nameMinimumScale)
                        .multilineTextAlignment(.leading)
                    if inUse {
                        Image(systemName: ClashSymbol.checkmark.rawValue)
                            .font(Self.nameFont)
                            .accessibilityLabel("In use")
                    }
                }
                HStack {
                    Text(Self.typeLabel(for: member, state: state))
                        .font(Self.detailFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 12)
                    Text(Self.readingLabel(for: member, in: group, state: state))
                        .font(Self.detailFont.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
        .accessibilityIdentifier("tvos.nodes.member.\(member.name)")
        .accessibilityAddTraits(inUse ? .isSelected : [])
         
         
         
         
         
         
         
         
        .contextMenu {
            if let onTest {
                Button(Self.testOneTitle) { onTest(member, group) }
            }
        }
    }

     

     
     
     
     
     
     
    static let nameFont: Font = .body
    static let detailFont: Font = .caption

     
    static let nameLineLimit = 2

     
     
     
    static let nameMinimumScale: CGFloat = 0.8

     
     
     
     
     
     
     
    static let longNameThreshold = 48

     
     
     
     
     
    static func columnCount(for group: ClashProxyGroupSnapshot) -> Int {
        columnCount(for: group.members)
    }

     
    static func columnCount(for group: ClashProxyGroupSnapshot, mode: ClashTVOutboundMode) -> Int {
        columnCount(for: browsedMembers(of: group, mode: mode))
    }

    private static func columnCount(for members: [ClashProxyMemberSnapshot]) -> Int {
        let longest = members.map(\.name.count).max() ?? 0
        return longest > longNameThreshold ? 2 : 3
    }

     
    enum Vacancy: Equatable {
         
         
        case directMode
         
        case noGroups
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func browsedMembers(of group: ClashProxyGroupSnapshot, mode: ClashTVOutboundMode) -> [ClashProxyMemberSnapshot] {
        ProxyBrowsingVisibility.members(
            group.members,
            of: group.name,
            mode: .init(coreValue: mode.kernelToken),
            name: { $0.name }
        )
    }

     
    static func browsingMode(_ mode: ClashTVOutboundMode, opening: String?) -> ClashTVOutboundMode {
        opening != nil && mode == .direct ? .rule : mode
    }

    static func memberMode(for group: String, browsing: ClashTVOutboundMode, opening: String?) -> ClashTVOutboundMode {
        group == opening ? .global : browsing
    }

    static func visibleGroups(
        _ groups: [ClashProxyGroupSnapshot],
        mode: ClashTVOutboundMode,
        opening: String? = nil,
        hidden: [ClashProxyGroupSnapshot] = []
    ) -> [ClashProxyGroupSnapshot] {
        var shown = ProxyBrowsingVisibility.groups(
            groups,
            mode: .init(coreValue: mode.kernelToken),
            name: { $0.name },
            isHidden: { _ in false }
        )
         
         
         
        if let opening, let group = groups.first(where: { $0.name == opening }) ?? hidden.first(where: { $0.name == opening }) {
            shown.removeAll { $0.name == opening }
            shown.insert(group, at: 0)
        }
        return shown
    }

     
     
     
     
     
     
    static func vacancy(
        mode: ClashTVOutboundMode,
        visibleGroups: [ClashProxyGroupSnapshot]
    ) -> Vacancy? {
        if mode == .direct { return .directMode }
        return visibleGroups.isEmpty ? .noGroups : nil
    }

    static func select(member: String, in groupName: String, state: inout ClashTVProductState) {
        state.pin(member: member, in: groupName)
    }

     
     
    static func header(for group: ClashProxyGroupSnapshot) -> String {
        header(for: group, count: group.isEmpty ? 0 : group.memberCount)
    }

     
     
     
    static func header(for group: ClashProxyGroupSnapshot, mode: ClashTVOutboundMode) -> String {
        let offered = browsedMembers(of: group, mode: mode).count
        return header(for: group, count: group.isEmpty ? 0 : group.memberCount - (group.members.count - offered))
    }

     
     
    static func needsMoreMembers(_ group: ClashProxyGroupSnapshot, after name: String) -> Bool {
        !group.hasEveryMember && group.members.last?.name == name
    }

    private static func header(for group: ClashProxyGroupSnapshot, count: Int) -> String {
        count == 1
            ? String(localized: "\(group.name) · 1 node · \(group.type)")
            : String(localized: "\(group.name) · \(count) nodes · \(group.type)")
    }

     
     
    static var testOneTitle: String { String(localized: "Test") }

     
     
     
    static func testAllTitle(isTesting: Bool) -> String {
        isTesting ? String(localized: "Testing…") : String(localized: "Test all")
    }

     
     
     
     
    static func offersTestAll(for group: ClashProxyGroupSnapshot) -> Bool {
        !group.isEmpty && !group.members.isEmpty
    }

     
     
     
     
    static func group(named name: String, state: ClashTVProductState) -> ClashProxyGroupSnapshot? {
        state.proxyGroups.first { $0.name == name } ?? state.hiddenProxyGroups.first { $0.name == name }
    }

     
     
     
    static func isEmptyGroup(_ member: ClashProxyMemberSnapshot, state: ClashTVProductState) -> Bool {
        member.isGroup && group(named: member.name, state: state)?.isEmpty == true
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func displayedLatency(for member: ClashProxyMemberSnapshot, in group: ClashProxyGroupSnapshot? = nil,
                                 state: ClashTVProductState) -> ClashProxyLatencyState {
         
        guard let probe = probe(for: member, in: group, state: state) else { return .untested }
        return state.latency[probe.key] ?? state.latency[probe.name] ?? .untested
    }

     
     
     
    static func displayedLatency(forGroup group: ClashProxyGroupSnapshot, state: ClashTVProductState) -> ClashProxyLatencyState {
        displayedLatency(for: ClashProxyMemberSnapshot(name: group.name, type: group.type, isGroup: true), state: state)
    }

     
     
     
    static func readingLabel(for member: ClashProxyMemberSnapshot, in group: ClashProxyGroupSnapshot? = nil,
                             state: ClashTVProductState) -> String {
        if isEmptyGroup(member, state: state) { return "" }
        return latencyLabel(
            displayedLatency(for: member, in: group, state: state),
            failureCategory: state.failureReasons[member.name] ?? ""
        )
    }

     
     
     
     
     
     
    static func groupRowSubtitle(for group: ClashProxyGroupSnapshot, state: ClashTVProductState) -> String {
        groupRowTypeLead(for: group) + (groupRowSelection(for: group) ?? "")
    }

     
     
     
    static func groupRowTypeLead(for group: ClashProxyGroupSnapshot) -> String {
        if group.isEmpty { return "\(group.type) \(noNodes)" }
        return group.currentSelection == nil ? group.type : "\(group.type) · "
    }

     
     
    static func groupRowSelection(for group: ClashProxyGroupSnapshot) -> String? {
        group.isEmpty ? nil : group.currentSelection
    }

     
     
     
     
     
    static func groupRowValue(for group: ClashProxyGroupSnapshot, state: ClashTVProductState) -> String {
        guard !group.isEmpty else { return "" }
        return latencyLabel(
            displayedLatency(forGroup: group, state: state),
            failureCategory: state.failureReasons[group.name] ?? ""
        )
    }

     
     
     
     
     
    static func offersUnpin(for group: ClashProxyGroupSnapshot) -> Bool {
        group.canBeUnpinned && group.configuredSelection != nil
    }

     
    static var unfixTitle: String { String(localized: "Unfix") }

     
     
     
     
     
    static func typeLabel(for member: ClashProxyMemberSnapshot, state: ClashTVProductState) -> String {
        if state.easyTierNodeNames.contains(member.name) {
            return String(localized: "easytier · Not supported")
        }
        if isEmptyGroup(member, state: state) {
            return "\(member.type) \(noNodes)"
        }
        return member.type
    }

     
     
    private static var noNodes: String { String(localized: "· No nodes") }

     
     
     
    static func sweepMembers(of group: ClashProxyGroupSnapshot, state: ClashTVProductState) -> [ClashProxyMemberSnapshot] {
        guard !group.isEmpty else { return [] }
        return group.members.filter { !isEmptyGroup($0, state: state) }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func probeName(for member: ClashProxyMemberSnapshot, state: ClashTVProductState) -> String? {
        probe(for: member, in: nil, state: state)?.name
    }

     
     
     
     
     
    struct Probe: Hashable {
        let name: String
        let url: String?
         
        var key: String { ClashTVKernelSnapshots.latencyKey(name, readingURL: url) }
    }

    static func probe(for member: ClashProxyMemberSnapshot, in group: ClashProxyGroupSnapshot?,
                      state: ClashTVProductState) -> Probe? {
        guard member.isGroup else { return Probe(name: member.name, url: readingURL(of: group, state: state)) }
        if isEmptyGroup(member, state: state) { return nil }
        var name = member.name
        var routing: ClashProxyGroupSnapshot?
        var visited = Set<String>()
        while let inner = self.group(named: name, state: state) {
            guard visited.insert(name).inserted else { return nil }
            guard let next = inner.runtimeSelection else { return Probe(name: name, url: nil) }
            routing = inner
            name = next
        }
        return Probe(name: name, url: readingURL(of: routing, state: state))
    }

     
     
    static func readingURL(of group: ClashProxyGroupSnapshot?, state: ClashTVProductState) -> String? {
        group.flatMap { state.groupReadingURLs[$0.name] }
    }

     
     
     
     
    static func sweepProbes(of group: ClashProxyGroupSnapshot, state: ClashTVProductState) -> [Probe] {
        let probes = sweepMembers(of: group, state: state).compactMap { probe(for: $0, in: group, state: state) }
        let measuredByURL = Set(probes.filter { $0.url != nil }.map(\.name))
        var seen = Set<String>()
        return probes.filter { ($0.url != nil || !measuredByURL.contains($0.name)) && seen.insert($0.key).inserted }
    }

    static func isTesting(_ group: ClashProxyGroupSnapshot, state: ClashTVProductState) -> Bool {
        sweepProbes(of: group, state: state).contains { state.latency[$0.key] == .testing || state.latency[$0.name] == .testing }
    }

     
     
     
     
     
     
    static func beginTesting(_ group: ClashProxyGroupSnapshot, state: inout ClashTVProductState) {
        for probe in sweepProbes(of: group, state: state) {
            state.latency[probe.name] = .testing
            state.latency[probe.key] = .testing
        }
    }

     
     
     
     
     
     
     
    static func record(delay: Int, for member: String, state: inout ClashTVProductState) {
        state.latency[member] = ClashProxyLatencyState.measured(milliseconds: delay).normalized
    }

     
     
    static func record(delay: Int, for probe: Probe, state: inout ClashTVProductState) {
        record(delay: delay, for: probe.name, state: &state)
        record(delay: delay, for: probe.key, state: &state)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func merge(
        polled: [String: ClashProxyLatencyState],
        over current: [String: ClashProxyLatencyState],
        sweeping: Set<String>
    ) -> [String: ClashProxyLatencyState] {
        guard !sweeping.isEmpty else { return polled }
        var merged = polled
        for name in sweeping {
            merged[name] = current[name]
        }
        return merged
    }

     
     
    static func latencyLabel(
        _ state: ClashProxyLatencyState,
        failureCategory: String = ""
    ) -> String {
        switch state {
        case .measured(let milliseconds): String(localized: "\(milliseconds) ms")
        case .untested: "—"
        case .testing: "…"
         
         
         
        case .failed, .timedOut:
            String(
                localized: String.LocalizationValue(
                    ClashProbeFailureCopy.badge(
                        for: state == .timedOut ? "timeout" : failureCategory
                    )
                )
            )
        }
    }
}
