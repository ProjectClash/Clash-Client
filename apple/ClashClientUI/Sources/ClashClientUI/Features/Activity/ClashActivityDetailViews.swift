import SwiftUI

 
 
 
 
 
 
 
enum ClashActivityByteFormatter {
     
     
     
     
    @MainActor private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.includesUnit = true
        return formatter
    }()

    @MainActor static func count(_ bytes: Int64) -> String {
        formatter.string(fromByteCount: max(0, bytes))
    }
}

 
 
 
 
 
 
 
struct ClashActivityRowText: Equatable, Sendable {
     
     
     
    let host: String
     
    let traffic: String
     
    let download: String
    let upload: String
     
     
    let time: String?
}

 
struct ClashActivityConnectionRowModel: Identifiable, Equatable, Sendable {
    let connection: ClashActivityConnectionSnapshot
    let text: ClashActivityRowText
    var id: String { connection.id }
}

 
 
 
 
enum ClashActivityRowTextFactory {
    static func bytesFormatter() -> ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.includesUnit = true
        return formatter
    }

    static func timeStyle(locale: Locale) -> Date.FormatStyle {
        Date.FormatStyle(date: .omitted, time: .standard, locale: locale)
    }

    static func text(
        for connection: ClashActivityConnectionSnapshot,
        at moment: Date?,
        locale: Locale,
        bytes: ByteCountFormatter,
        time: Date.FormatStyle
    ) -> ClashActivityRowText {
        let download = bytes.string(fromByteCount: connection.download)
        let upload = bytes.string(fromByteCount: connection.upload)
        return ClashActivityRowText(
            host: host(of: connection),
            traffic: "↓ \(download)  ↑ \(upload)",
            download: connection.download == 0 ? "–" : download,
            upload: connection.upload == 0 ? "–" : upload,
            time: moment.map { time.format($0) }
        )
    }

    static func host(of connection: ClashActivityConnectionSnapshot) -> String {
        let destination = connection.destination
        let implied: String
        switch ClashActivityTableRow(connection: connection).trafficProtocol {
        case .https, .quic: implied = ":443"
        case .http: implied = ":80"
        default: return destination
        }
         
         
         
        guard destination.hasSuffix(implied),
              destination.hasSuffix("]" + implied) || destination.filter({ $0 == ":" }).count == 1
        else { return destination }
        return String(destination.dropLast(implied.count))
    }

    static func rows(
        _ connections: [ClashActivityConnectionSnapshot],
        locale: Locale
    ) -> [ClashActivityConnectionRowModel] {
        let bytes = bytesFormatter()
        let time = timeStyle(locale: locale)
        return connections.map {
            ClashActivityConnectionRowModel(
                connection: $0,
                text: text(for: $0, at: $0.start, locale: locale, bytes: bytes, time: time)
            )
        }
    }
}

 
 
 
@MainActor
final class ClashActivityRowTextCache {
    private struct Key: Equatable {
        let upload: Int64
        let download: Int64
        let firstSeen: Date?
        let locale: Locale
    }

    private var entries: [String: (key: Key, text: ClashActivityRowText)] = [:]
    private let bytes = ClashActivityRowTextFactory.bytesFormatter()
    private var time: (locale: Locale, style: Date.FormatStyle)?
     
    private(set) var builds = 0

    func text(for entry: ClashActivityRequestSnapshot, locale: Locale) -> ClashActivityRowText {
        let connection = entry.connection
        let key = Key(
            upload: connection.upload, download: connection.download,
            firstSeen: entry.firstSeen, locale: locale
        )
        if let cached = entries[entry.id], cached.key == key { return cached.text }
        if time?.locale != locale {
            time = (locale, ClashActivityRowTextFactory.timeStyle(locale: locale))
        }
        builds += 1
        let text = ClashActivityRowTextFactory.text(
            for: connection, at: entry.firstSeen, locale: locale,
            bytes: bytes, time: time?.style ?? ClashActivityRowTextFactory.timeStyle(locale: locale)
        )
        entries[entry.id] = (key, text)
        return text
    }

     
     
    func retain(_ ids: Set<String>) {
        guard entries.count > ids.count else { return }
        entries = entries.filter { ids.contains($0.key) }
    }
}

 
 
 
 
enum ClashActivityAutoScroll {
     
     
    static let logsKey = "activityLogsAutoScroll"
}

 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
public final class ClashActivityRequestsPause: ObservableObject {
    public static let shared = ClashActivityRequestsPause()

     
    @Published private(set) var held: [ClashActivityRequestSnapshot]?

    var isPaused: Bool { held != nil }

    func rows(live: [ClashActivityRequestSnapshot]) -> [ClashActivityRequestSnapshot] {
        held ?? live
    }

     
    func hold(_ live: [ClashActivityRequestSnapshot]) {
        if held == nil { held = live }
    }

    func release() { held = nil }

     
     
     
    public func clear() {
        if held != nil { held = [] }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
public final class ClashActivityScrollReading {
     
    nonisolated(unsafe) public static var rowProbe: (@MainActor (ClashActivityScrollReading) -> AnyView)?

     
    public var isReaderScrolling: @MainActor () -> Bool = { false }

     
     
     
    public var scrollToTop: (@MainActor () -> Void)?

     
     
    public var isFingerOnList: @MainActor () -> Bool = { false }

     
     
     
    public private(set) var fingerTouches = 0

     
    public func fingerTouched() { fingerTouches += 1 }

    public init() {}
}

 
 
 
 
 
 
 
 
 
 
 
@MainActor
final class ClashActivityPendingTop {
    static let retryInterval: TimeInterval = 0.1
    static let maximumTries = 300

    private let reading: ClashActivityScrollReading
    private var generation = 0
    private(set) var isPending = false
     
    var schedule: (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { work() } }
    }

    init(reading: ClashActivityScrollReading) {
        self.reading = reading
    }

     
    private var touchesAtRequest = 0

     
    func request(_ go: @escaping @MainActor () -> Void) {
        generation += 1
        let mine = generation
        isPending = true
        touchesAtRequest = reading.fingerTouches
        schedule(0) { self.attempt(mine, go, tries: 0) }
    }

     
    private var readerTookTheList: Bool {
        reading.isFingerOnList() || reading.fingerTouches != touchesAtRequest
    }

    func cancel() {
        generation += 1
        isPending = false
    }

    private func attempt(_ mine: Int, _ go: @escaping @MainActor () -> Void, tries: Int) {
        guard mine == generation else { return }
        if readerTookTheList || tries >= Self.maximumTries {
            isPending = false
            return
        }
        if reading.isReaderScrolling() {
            schedule(Self.retryInterval) { self.attempt(mine, go, tries: tries + 1) }
            return
        }
        go()
        isPending = false
        schedule(0) {
            guard mine == self.generation, !self.readerTookTheList, !self.reading.isReaderScrolling() else { return }
            go()
        }
    }
}

 
private struct ClashActivityScrollProbeSlot: View {
    let reading: ClashActivityScrollReading

    var body: some View {
        if let probe = ClashActivityScrollReading.rowProbe {
            probe(reading)
        }
    }
}

 
 
 
 
 
 
 
 
@MainActor
final class ClashActivityTopFollower {
    private var visible: Set<String> = []
    private var newest: String?
     
     
    let scrolling = ClashActivityScrollReading()
     
    private(set) lazy var pendingTop = ClashActivityPendingTop(reading: scrolling)

    func appeared(_ id: String) { visible.insert(id) }
    func disappeared(_ id: String) { visible.remove(id) }
     
     
    func remember(_ newestID: String?) { newest = newestID }

     
    func shouldFollow(to newestID: String?, enabled: Bool) -> Bool {
        defer { newest = newestID }
        guard enabled, let newestID, let previous = newest, previous != newestID,
              !scrolling.isReaderScrolling()
        else {
            return false
        }
        return visible.contains(previous)
    }
}

public struct ClashConnectionsView<Icon: View>: View {
    private let snapshot: AppleClientSnapshot
    private let actions: AppleClientActions
    private let presentationClass: ClashPresentationClass
    private let palette: ClashProductPalette
    private let icon: (ClashSymbol) -> Icon

    private let query: String
     
     
     
     
    private let isShown: Bool
    @State private var sort: ClashActivityConnectionSort =
        .recent
    @State private var keywords: Set<String> = []
    @State private var confirmsCloseAll = false
     
     
     
     
     
     
     
     
    @State private var prepared: [ClashActivityConnectionRowModel] = []
     
    @Environment(\.locale) private var locale
     
     
    @State private var preparedTotal = 0
     
     
     
    @State private var preparedSummaries: [ClashActivityChainSummary] = []
     
    @State private var preparedBarTotal = 0
    @State private var preparedBarSummaries: [ClashActivityChainSummary] = []
     
     
    @State private var hasPrepared = false
     
    @State private var showsAllChains = false
    @State private var selected:
        ClashActivityConnectionSnapshot?
     
     
     
    @State private var preparedConnections: [ClashActivityConnectionSnapshot] = []
    @State private var preparedTraffic: (upload: Int64, download: Int64) = (0, 0)
    @State private var tableSelectionCount = 0
    @Environment(\.clashPushRoute) private var pushRoute

    public init(
        snapshot: AppleClientSnapshot,
        actions: AppleClientActions,
        presentationClass: ClashPresentationClass,
        palette: ClashProductPalette,
        query: String = "",
        isShown: Bool = true,
        @ViewBuilder icon: @escaping (ClashSymbol) -> Icon
    ) {
        self.snapshot = snapshot
        self.actions = actions
        self.presentationClass = presentationClass
        self.palette = palette
        self.query = query
        self.isShown = isShown
        self.icon = icon
    }

    public var body: some View {
        content
            .accessibilityIdentifier("connections.overview")
            .accessibilityValue(activityAccessibilityValue)
             
             
             
             
             
             
             
            .task(id: isShown ? preparationKey : nil) {
                guard isShown else { return }
                await prepareConnections()
            }
            .clashActivityLensToolbar(active: isShown) { toolbarContent }
            .confirmationDialog(
                "Close all active connections?",
                isPresented: $confirmsCloseAll
            ) {
                Button("Close All", role: .destructive) {
                    send(.closeAllConnections)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Apps may reconnect automatically.")
            }
            .modifier(
                ClashActivityDetailHost(
                    selected: $selected,
                    title: "Connection Details",
                    actions: actions,
                    snapshot: snapshot
                )
            )
    }

    @ViewBuilder
    private var content: some View {
#if os(macOS)
        macTable
#else
        list
#endif
    }

     
    private var list: some View {
        ClashActivityRowLayoutReader(presentationClass: presentationClass) { layout in
            groupedList(layout)
        }
    }

    private func groupedList(_ layout: ClashActivityRowLayout) -> some View {
        List {
            if !keywords.isEmpty {
                filterSection
            }

            if let error = snapshot.activity.errorDescription,
               !error.isEmpty
            {
                Section {
                    VStack(
                        alignment: .leading,
                        spacing: ClashTheme.Spacing.compact
                    ) {
                        Text(error)
                            .foregroundStyle(.red)
                         
                         
                         
                        Button {
                            send(.refresh)
                        } label: {
                            Label(
                                "Retry",
                                systemImage:
                                    ClashSymbol
                                    .arrowClockwise
                                    .rawValue
                            )
                        }
                    }
                }
            }

            if hasPrepared && visibleConnections.isEmpty {
                emptyState
            }

            if !chainSummaries.isEmpty {
                Section {
                    ForEach(
                        layout.isRegular || showsAllChains
                            ? chainSummaries
                            : Array(chainSummaries.prefix(Self.compactChainCount))
                    ) { summary in
                        Group {
                        if layout.isRegular {
                             
                             
                            HStack(spacing: ClashActivityRowColumns.spacing) {
                                Text(summary.path)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Group {
                                    Text(verbatim: "\(summary.connectionCount)")
                                    Text(verbatim: ClashActivityByteFormatter.count(summary.download))
                                    Text(verbatim: ClashActivityByteFormatter.count(summary.upload))
                                }
                                .frame(width: ClashActivityRowColumns.bytes, alignment: .trailing)
                                .font(.subheadline.monospacedDigit())
                            }
                            .font(.subheadline)
                        } else {
                         
                         
                         
                         
                         
                         
                        let totals = (Text(clash: .format(summary.connectionCount == 1 ? "%@ connection" : "%@ connections", [String(summary.connectionCount)]))
                            + Text(verbatim: " · ↓ \(ClashActivityByteFormatter.count(summary.download))"))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(ClashActivityBadgeStyle.detailInk)
                        let route = ClashActivityRouteText.text(chains: summary.chains, route: summary.path)
                            .font(.subheadline)
                        if layout.isAccessibilityText {
                             
                             
                             
                            VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                                route
                                totals
                            }
                        } else {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                route
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 4)
                                totals
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                        }
                        }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if !layout.isRegular, !showsAllChains, chainSummaries.count > Self.compactChainCount {
                        Button {
                            showsAllChains = true
                        } label: {
                            Text(clash: .format("Show all %@ chains", [String(chainSummaries.count)]))
                                .font(.subheadline)
                        }
                        .accessibilityIdentifier("activity.chains.showAll")
                    }
                } header: {
                    if layout.isRegular {
                         
                        HStack(spacing: ClashActivityRowColumns.spacing) {
                            Text("Chain Totals").frame(maxWidth: .infinity, alignment: .leading)
                            Group {
                                Text("Connections")
                                Text("Download")
                                Text("Upload")
                            }
                            .frame(width: ClashActivityRowColumns.bytes, alignment: .trailing)
                        }
                        .modifier(ClashActivityColumnTitleStyle())
                    } else {
                        Text("Chain Totals")
                    }
                }
            }

             
             
             
             
            Section {
            ForEach(visibleConnections) { row in
                let connection = row.connection
                ClashActivityConnectionRow(
                    connection: connection,
                    text: row.text,
                    detailTitle: "Connection Details",
                    actions: actions,
                    snapshot: snapshot,
                    isBusy:
                        snapshot.activity.closingConnectionIDs
                        .contains(connection.id),
                    showsCloseAction:
                        snapshot.activity.canManageConnections,
                    isCloseDisabled:
                        snapshot.activity.isClosingAll
                        || snapshot.activity
                        .closingConnectionIDs
                        .contains(connection.id),
                    palette: palette,
                    isRegular: layout.isRegular,
                    onKeyword: { keywords.insert($0) },
                    onClose: {
                        send(
                            .closeConnection(
                                id: connection.id
                            )
                        )
                    }
                )
                .modifier(
                    ClashActivityTouchSelection(
                        selected: $selected,
                        connection: connection
                    )
                )
                .modifier(ClashActivityRowWidthReporter(layout: layout))
            }

             
             
            if preparedTotal > visibleConnections.count {
                Text(clash: .format(
                    "Showing first %@ of %@ connections",
                    ["\(visibleConnections.count)", "\(preparedTotal)"]
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("connections.renderCap")
            }
            } header: {
                if layout.isRegular && !visibleConnections.isEmpty {
                    ClashActivityColumnHeader(showsAction: snapshot.activity.canManageConnections)
                }
            }
        }
        .clashGroupedList()
         
         
         
        .clashListRetainsRowSelection()
        .clashActivityListCanvas(palette.canvas)
        .refreshable {
            await perform(.refresh)
        }
    }

#if os(macOS)
     
     
     
    private var macTable: some View {
        VStack(alignment: .leading, spacing: ClashTheme.Spacing.compact) {
            if let error = snapshot.activity.errorDescription, !error.isEmpty {
                ClashActivityMacBanner(
                    message: error,
                    retry: { send(.refresh) }
                )
            }
            ClashActivityMacFilterBar(
                summaries: preparedBarSummaries,
                total: preparedBarTotal,
                keywords: $keywords
            )
            if !chainSummaries.isEmpty {
                ClashActivityMacChainTotals(summaries: chainSummaries, palette: palette) { outbound in
                    keywords.insert(outbound)
                }
            }
            if hasPrepared && preparedConnections.isEmpty {
                ScrollView { emptyState }
            } else {
                ClashActivityTableCard(palette: palette) {
                ClashActivityTable(
                    kind: .connections,
                    rows: preparedConnections.map(ClashActivityTableRow.init(connection:)),
                    locale: locale,
                    canClose: snapshot.activity.canManageConnections
                        && !snapshot.activity.isClosingAll,
                    onOpen: { row in openDetails(row.connection, title: "Connection Details") },
                    onClose: { rows in
                        for row in rows { send(.closeConnection(id: row.connection.id)) }
                    },
                    onFilter: { keywords.insert($0) },
                    onSelectionCount: { tableSelectionCount = $0 }
                )
                }
            }
            ClashActivityMacStatusLine(
                count: preparedConnections.count,
                total: preparedTotal,
                selected: tableSelectionCount,
                upload: preparedTraffic.upload,
                download: preparedTraffic.download,
                kind: .connections
            )
        }
        .padding(.vertical, ClashTheme.Spacing.standard)
    }

    private func openDetails(_ connection: ClashActivityConnectionSnapshot, title: String) {
        guard let pushRoute else { selected = connection; return }
        let token = UUID()
        let actions = actions
        let snapshot = snapshot
        ClashViewRouteRegistry.set(token, ownership: .oneShot, onReturn: {}) {
            AnyView(ClashActivityMacConnectionDetail(
                connection: connection, title: title, palette: palette
            ) { text in
                Task { @MainActor in
                    try? await actions.perform(.activity(.copyText(text)), allowedBy: snapshot)
                }
            })
        }
        pushRoute(ClashViewRoute(id: token))
    }
#endif

    private var visibleConnections:
        [ClashActivityConnectionRowModel]
    { prepared }

    private struct ConnectionsPreparationKey: Equatable {
        let count: Int
        let firstID: String?
        let lastID: String?
        let trafficChecksum: UInt64
        let query: String
        let sort: ClashActivityConnectionSort
        let keywords: Set<String>
    }

    private var preparationKey: ConnectionsPreparationKey {
         
         
         
         
         
        var checksum: UInt64 = 0
        for connection in snapshot.activity.connections {
            checksum = checksum
                &+ UInt64(bitPattern: Int64(connection.upload))
                &+ UInt64(bitPattern: Int64(connection.download)) &* 31
        }
        return ConnectionsPreparationKey(
            count: snapshot.activity.connections.count,
            firstID: snapshot.activity.connections.first?.id,
            lastID: snapshot.activity.connections.last?.id,
            trafficChecksum: checksum,
            query: query,
            sort: sort,
            keywords: keywords
        )
    }

    @MainActor
    private func prepareConnections() async {
        let values = snapshot.activity.connections
        let query = query
        let sort = sort
        let keywords = keywords
        let locale = locale
         
         
         
        let result = await Task.detached(priority: .userInitiated) {
            () -> (
                rows: [ClashActivityConnectionRowModel],
                connections: [ClashActivityConnectionSnapshot],
                traffic: (upload: Int64, download: Int64),
                total: Int,
                summaries: [ClashActivityChainSummary],
                barTotal: Int,
                barSummaries: [ClashActivityChainSummary]
            ) in
#if os(macOS)
             
             
             
             
             
             
            let outbounds = Set(values.compactMap(\.chains.first))
            let chosen = keywords.intersection(outbounds).map { $0.lowercased() }
            let projectionKeywords = keywords.subtracting(outbounds)
#else
            let projectionKeywords = keywords
#endif
            let projected = ClashActivityProjection.connections(
                values, query: query, sort: sort, keywords: projectionKeywords,
                limit: nil
            )
#if os(macOS)
            let unchosen = projected
            let full = chosen.isEmpty ? projected : projected.filter { connection in
                chosen.allSatisfy { keyword in
                    connection.process.lowercased() == keyword
                        || connection.chains.contains { $0.lowercased() == keyword }
                }
            }
#else
            let full = projected
#endif
#if os(macOS)
             
             
            var upload: Int64 = 0
            var download: Int64 = 0
            for connection in full {
                upload = upload &+ connection.upload
                download = download &+ connection.download
            }
            return (
                rows: [],
                connections: Array(full.prefix(ClashActivityProjection.tableRenderCap)),
                traffic: (upload, download),
                total: full.count,
                summaries: ClashActivityProjection.chainSummaries(full),
                barTotal: unchosen.count,
                barSummaries: ClashActivityProjection.chainSummaries(unchosen)
            )
#else
            return (
                rows: ClashActivityRowTextFactory.rows(
                    Array(full.prefix(ClashActivityProjection.connectionRenderCap)),
                    locale: locale
                ),
                connections: [],
                traffic: (0, 0),
                total: full.count,
                summaries: ClashActivityProjection.chainSummaries(full),
                barTotal: 0,
                barSummaries: []
            )
#endif
        }.value
         
         
        if Task.isCancelled { return }
        prepared = result.rows
        preparedConnections = result.connections
        preparedTraffic = result.traffic
        preparedTotal = result.total
        preparedSummaries = result.summaries
        preparedBarTotal = result.barTotal
        preparedBarSummaries = result.barSummaries
        hasPrepared = true
    }

    private var chainSummaries:
        [ClashActivityChainSummary]
    { preparedSummaries }

     
     
    static var compactChainCount: Int { 3 }

    private var filterSection: some View {
        Section("Filters") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ClashTheme.Spacing.compact) {
                    ForEach(keywords.sorted(), id: \.self) {
                        keyword in
                        ClashActivityKeywordButton(
                            title: .verbatim(keyword)
                        ) {
                            keywords.remove(keyword)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        ClashCardSurface(
            fill: palette.card,
            separator: palette.separator,
            cornerRadius: ClashTheme.Radius.groupedSection
        ) {
            ClashEmptyState(
                title: emptyTitle,
                message: emptyMessage,
                isLoading: snapshot.activity.phase == .loading
            ) {
                icon(
                    snapshot.activity.phase == .disconnected
                        ? .boltSlash
                        : query.isEmpty && keywords.isEmpty
                            ? .rectangleStack
                            : .magnifyingglass
                )
            }
            .padding(.vertical, ClashTheme.Spacing.section)
        }
        .listRowBackground(Color.clear)
    }

    private var emptyTitle: String {
        switch snapshot.activity.phase {
        case .loading:
            "Loading Connections"
        case .disconnected:
            "Clash Is Disconnected"
        case .failed:
            "Connections Unavailable"
        case .ready:
            query.isEmpty && keywords.isEmpty
                ? "No Active Connections"
                : "No Matches"
        }
    }

    private var emptyMessage: String {
        switch snapshot.activity.phase {
        case .loading:
            "Reading the live connection snapshot."
        case .disconnected:
            "Connect Clash to inspect live sessions."
        case .failed:
            "Retry after the current connection is available."
        case .ready:
            query.isEmpty && keywords.isEmpty
                ? "Connections appear here while apps use the tunnel."
                : "Try a different search term or remove a filter."
        }
    }

    private var activityAccessibilityValue: String {
        switch snapshot.activity.phase {
        case .ready:
            "Connected"
        case .loading:
            "Loading"
        case .disconnected, .failed:
            "Disconnected"
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
         
         
        ToolbarItem(placement: .primaryAction) {
            ControlGroup {
#if !os(macOS)
                 
                 
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(
                            ClashActivityConnectionSort.allCases
                        ) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                        .accessibilityIdentifier("activity.detail.sort")
                    .clashFlattensMenuChoices()
                } label: {
                    Label(
                        "Sort",
                        systemImage:
                            ClashSymbol.arrowUpArrowDown.rawValue
                    )
                }
                .accessibilityIdentifier("connections.sort")
#endif

                if snapshot.activity.canManageConnections {
#if !os(macOS)
                     
                     
                     
                    ClashToolbarDivider()
#endif

                    Button(role: .destructive) {
                        confirmsCloseAll = true
                    } label: {
                        Label(
                            "Close All",
                            systemImage:
                                ClashSymbol.xmark.rawValue
                        )
                    }
                    .disabled(
                        snapshot.activity.activeConnectionCount == 0
                            || snapshot.activity.isClosingAll
                            || !snapshot.activity
                            .closingConnectionIDs.isEmpty
                    )
                    .accessibilityIdentifier("connections.closeAll")
                }
            }
            .clashReaderControlGroupStyle()
        }
    }

    private func send(_ command: ClashActivityCommand) {
        Task { @MainActor in
            await perform(command)
        }
    }

    @MainActor
    private func perform(
        _ command: ClashActivityCommand
    ) async {
        try? await actions.perform(
            .activity(command),
            allowedBy: snapshot
        )
    }
}

public struct ClashRequestsView<Icon: View>: View {
    private let snapshot: AppleClientSnapshot
    private let actions: AppleClientActions
    private let palette: ClashProductPalette
    private let icon: (ClashSymbol) -> Icon

    private let query: String
     
     
     
     
    private let isShown: Bool
    @State private var keywords: Set<String> = []
     
    @ObservedObject private var pause = ClashActivityRequestsPause.shared
    private var isPaused: Bool { pause.isPaused }
     
    @State private var rowTexts = ClashActivityRowTextCache()
     
    @State private var follower = ClashActivityTopFollower()
    @Environment(\.locale) private var rowLocale
    @State private var selected:
        ClashActivityConnectionSnapshot?

    public init(
        snapshot: AppleClientSnapshot,
        actions: AppleClientActions,
        presentationClass: ClashPresentationClass,
        palette: ClashProductPalette,
        query: String = "",
        isShown: Bool = true,
        @ViewBuilder icon: @escaping (ClashSymbol) -> Icon
    ) {
        self.snapshot = snapshot
        self.actions = actions
        self.presentationClass = presentationClass
        self.palette = palette
        self.query = query
        self.isShown = isShown
        self.icon = icon
    }

    private let presentationClass: ClashPresentationClass

    public var body: some View {
        requestsContent
         
        .clashActivityLensToolbar(active: isShown) {
            ToolbarItem(placement: .primaryAction) {
                 
                 
                 
                 
                ControlGroup {
                Button {
                    if isPaused {
                        pause.release()
                    } else {
                        pause.hold(snapshot.activity.requests)
                    }
                } label: {
                     
                     
                     
                     
                     
                     
                     
                    Label(
                        isPaused
                            ? "Resume updates"
                            : "Pause updates",
                        systemImage:
                            isPaused
                            ? ClashSymbol.play.rawValue   
                            : ClashSymbol.pause.rawValue
                    )
                }
                .accessibilityIdentifier("requests.autoScroll")
#if !os(macOS)
                 
                 
                ClashToolbarDivider()
#endif
                 
                 
                Button(role: .destructive) {
                    pause.clear()
                    send(.clearRequests)
                } label: {
                    Label("Clear", systemImage: ClashSymbol.trash.rawValue)
                }
                 
                 
                .disabled(shownRequests.isEmpty)
                .accessibilityIdentifier("requests.clear")
                }
                .clashReaderControlGroupStyle()
            }
        }
        .modifier(
            ClashActivityDetailHost(
                selected: $selected,
                title: "Request Details",
                actions: actions,
                snapshot: snapshot
            )
        )
        .accessibilityIdentifier("requests.overview")
    }

    @ViewBuilder
    private var requestsContent: some View {
#if os(macOS)
        macTable
            .onChange(of: isShown) { shown in
                frozenEntries = shown ? nil : entries
            }
#else
        ScrollViewReader { proxy in
            ClashActivityRowLayoutReader(presentationClass: presentationClass) { layout in
                requestsList(layout, proxy: proxy)
            }
        }
#endif
    }

#if !os(macOS)
     
     
    private func requestsList(_ layout: ClashActivityRowLayout, proxy: ScrollViewProxy) -> some View {
        List {
             
             
            if let error = snapshot.activity.errorDescription, !error.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: ClashTheme.Spacing.compact) {
                        Text(error)
                            .foregroundStyle(.red)
                        Button {
                            send(.refresh)
                        } label: {
                            Label("Retry", systemImage: ClashSymbol.arrowClockwise.rawValue)
                        }
                    }
                }
            }
            if !keywords.isEmpty {
                Section("Filters") {
                    ScrollView(
                        .horizontal,
                        showsIndicators: false
                    ) {
                        HStack(
                            spacing:
                                ClashTheme.Spacing.compact
                        ) {
                            ForEach(
                                keywords.sorted(),
                                id: \.self
                            ) { keyword in
                                ClashActivityKeywordButton(
                                    title: .verbatim(keyword)
                                ) {
                                    keywords.remove(
                                        keyword
                                    )
                                }
                            }
                        }
                    }
                }
            }

            if entries.isEmpty {
                ClashCardSurface(
                    fill: palette.card,
                    separator: palette.separator,
                    cornerRadius:
                        ClashTheme.Radius.groupedSection
                ) {
                    ClashEmptyState(
                        title: requestEmptyTitle,
                        message:
                            requestEmptyMessage,
                        isLoading:
                            snapshot.activity.phase
                                == .loading
                    ) {
                        icon(
                            query.isEmpty
                                && keywords.isEmpty
                                ? .listBulletRectanglePortrait
                                : .magnifyingglass
                        )
                    }
                    .padding(
                        .vertical,
                        ClashTheme.Spacing.section
                    )
                }
                .listRowBackground(Color.clear)
            }

             
            Section {
            ForEach(entries) { entry in
                ClashActivityRequestRow(
                    entry: entry,
                    text: rowTexts.text(for: entry, locale: rowLocale),
                    detailTitle: "Request Details",
                    actions: actions,
                    snapshot: snapshot,
                    palette: palette,
                    isRegular: layout.isRegular,
                    onKeyword: {
                        keywords.insert($0)
                    }
                )
                .id(entry.id)
                .onAppear { follower.appeared(entry.id) }
                .onDisappear { follower.disappeared(entry.id) }
                .background(ClashActivityScrollProbeSlot(reading: follower.scrolling))
                .modifier(
                    ClashActivityTouchSelection(
                        selected: $selected,
                        connection: entry.connection
                    )
                )
                .modifier(ClashActivityRowWidthReporter(layout: layout))
            }
            } header: {
                if layout.isRegular && !entries.isEmpty {
                    ClashActivityColumnHeader(showsAction: false)
                }
            }
        }
         
         
        .task(id: entries.count) {
            rowTexts.retain(Set(entries.map(\.id)))
        }
        .clashGroupedList()
        .clashListRetainsRowSelection()
        .clashActivityListCanvas(palette.canvas)
        .onAppear { follower.remember(entries.first?.id) }
        .onDisappear { follower.pendingTop.cancel() }
         
         
         
        .onChange(of: entries.first?.id) { newestID in
            guard follower.shouldFollow(to: newestID, enabled: !isPaused),
                  let newestID
            else { return }
            showNewest(newestID, proxy: proxy)
        }
         
         
        .onChange(of: isPaused) { paused in
            if paused {
                follower.pendingTop.cancel()
                return
            }
            guard let newestID = entries.first?.id else { return }
            showNewest(newestID, proxy: proxy, onceAtRest: true)
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private func showNewest(_ newestID: String, proxy: ScrollViewProxy, onceAtRest: Bool = false) {
        let scrolling = follower.scrolling
        let attempt: @MainActor () -> Void = {
            if let scrollToTop = scrolling.scrollToTop {
                scrollToTop()
            } else {
                proxy.scrollTo(newestID, anchor: .top)
            }
        }
        if onceAtRest {
            follower.pendingTop.request(attempt)
            return
        }
        DispatchQueue.main.async {
            attempt()
            DispatchQueue.main.async { attempt() }
        }
    }
#endif

#if os(macOS)
    @State private var tableSelectionCount = 0
    @Environment(\.clashPushRoute) private var pushRoute

     
     
     
     
     
    @State private var frozenEntries: [ClashActivityRequestSnapshot]?

    private var macTable: some View {
        let entries = isShown ? entries : (frozenEntries ?? entries)
        return VStack(alignment: .leading, spacing: ClashTheme.Spacing.compact) {
            if let error = snapshot.activity.errorDescription, !error.isEmpty {
                ClashActivityMacBanner(
                    message: error,
                    retry: { send(.refresh) }
                )
            }
            ClashActivityMacFilterBar(summaries: [], total: entries.count, keywords: $keywords)
            if entries.isEmpty {
                ScrollView {
                    ClashEmptyState(
                        title: requestEmptyTitle,
                        message: requestEmptyMessage,
                        isLoading: snapshot.activity.phase == .loading
                    ) {
                        icon(query.isEmpty && keywords.isEmpty ? .listBulletRectanglePortrait : .magnifyingglass)
                    }
                    .padding(.vertical, ClashTheme.Spacing.section)
                }
            } else {
                ClashActivityTableCard(palette: palette) {
                ClashActivityTable(
                    kind: .requests,
                    rows: entries.map(ClashActivityTableRow.init(request:)),
                    locale: rowLocale,
                    canClose: false,
                    followsNewest: !isPaused,
                    onOpen: { row in openDetails(row.connection) },
                    onFilter: { keywords.insert($0) },
                    onSelectionCount: { tableSelectionCount = $0 }
                )
                }
            }
            ClashActivityMacStatusLine(
                count: entries.count,
                total: entries.count,
                selected: tableSelectionCount,
                upload: nil,
                download: nil,
                kind: .requests
            )
        }
        .padding(.vertical, ClashTheme.Spacing.standard)
    }

    private func openDetails(_ connection: ClashActivityConnectionSnapshot) {
        guard let pushRoute else { selected = connection; return }
        let token = UUID()
        let actions = actions
        let snapshot = snapshot
        ClashViewRouteRegistry.set(token, ownership: .oneShot, onReturn: {}) {
            AnyView(ClashActivityMacConnectionDetail(
                connection: connection, title: "Request Details", palette: palette
            ) { text in
                Task { @MainActor in
                    try? await actions.perform(.activity(.copyText(text)), allowedBy: snapshot)
                }
            })
        }
        pushRoute(ClashViewRoute(id: token))
    }
#endif

     
    @State private var projection = ClashActivityProjectionMemo()

    private var entries: [ClashActivityRequestSnapshot] {
        projection.requests(
            shownRequests,
            query: query,
            keywords: keywords
        )
    }

     
    private var shownRequests: [ClashActivityRequestSnapshot] {
        pause.rows(live: snapshot.activity.requests)
    }

    private func send(_ command: ClashActivityCommand) {
        Task { @MainActor in
            try? await actions.perform(.activity(command), allowedBy: snapshot)
        }
    }

     
     
    private var requestEmptyTitle: String {
        if !query.isEmpty || !keywords.isEmpty { return "No Matches" }
        return snapshot.activity.phase == .failed ? "Unavailable" : "No Requests"
    }

    private var requestEmptyMessage: String {
        if !query.isEmpty || !keywords.isEmpty {
            return
                "Try a different search term or remove a filter."
        }
        if snapshot.activity.phase == .failed {
            return "Retry after the current connection is available."
        }
         
         
        if snapshot.activity.phase == .ready && isPaused {
            return "Paused. Resume to see new requests."
        }
        return snapshot.activity.phase == .ready
            ? "Requests appear here as apps use the tunnel."
            : "Connect Clash to record requests."
    }
}

 
 
 
public enum ClashLogsEmptyState {
    public static func offersStartRecording(isRecordingLogs: Bool?, isLoading: Bool, isFiltered: Bool) -> Bool {
        isRecordingLogs == false && !isLoading && !isFiltered
    }
}

public struct ClashLogsView<Icon: View>: View {
    private let snapshot: AppleClientSnapshot
    private let actions: AppleClientActions
    private let palette: ClashProductPalette
    private let icon: (ClashSymbol) -> Icon

    private let query: String
     
     
     
     
    private let isShown: Bool
     
     
    @State private var severities: Set<ClashActivityLogSeverity>
    @AppStorage(ClashActivityAutoScroll.logsKey) private var autoScrollToEnd = true

    public init(
        snapshot: AppleClientSnapshot,
        actions: AppleClientActions,
        presentationClass: ClashPresentationClass,
        palette: ClashProductPalette,
        query: String = "",
        isShown: Bool = true,
        @ViewBuilder icon: @escaping (ClashSymbol) -> Icon
    ) {
        self.snapshot = snapshot
        self.actions = actions
        _ = presentationClass
        self.palette = palette
        self.query = query
        self.isShown = isShown
        self.icon = icon
        _severities = State(
            initialValue: ClashActivityLogSeverity.severities(
                fromRawValues: snapshot.activity.logSeverityFilter
            )
        )
    }

    public var body: some View {
         
         
         
         
         
         
         
         
        ClashDeferredPageContent {
            listBody
        } placeholder: {
            ClashPageLoadingPlaceholder(title: .copy("Loading Logs"))
        }
         
        .clashActivityLensToolbar(active: isShown) { toolbarContent }
         
         
         
         
         
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("logs.overview")
    }

     
     
     
     
     
    @ViewBuilder
    private var listBody: some View {
        VStack(spacing: 0) {
             
             
             
             
            if !shownSeverities.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: ClashTheme.Spacing.compact) {
                        ForEach(shownSeverities.sorted { $0.title < $1.title }) { severity in
                            ClashActivityKeywordButton(title: .copy(severity.title)) {
                                 
                                 
                                 
                                severities.removeAll()
                                _ = severity
                            }
                        }
                    }
                    .padding(.horizontal, ClashTheme.Spacing.standard)
                    .padding(.vertical, ClashTheme.Spacing.compact)
                }
                .accessibilityIdentifier("logs.filters")
            }

            if entries.isEmpty {
                List {
                    ClashCardSurface(
                        fill: palette.card,
                        separator: palette.separator,
                        cornerRadius: ClashTheme.Radius.groupedSection
                    ) {
                        VStack(spacing: 0) {
                            ClashEmptyState(
                                title: logEmptyTitle,
                                message: logEmptyMessage,
                                isLoading: snapshot.activity.phase == .loading
                            ) {
                                icon(
                                    query.isEmpty && severities.isEmpty
                                        ? .textAlignleft
                                        : .magnifyingglass
                                )
                            }
                             
                             
                             
                            if ClashLogsEmptyState.offersStartRecording(
                                isRecordingLogs: snapshot.activity.isRecordingLogs,
                                isLoading: snapshot.activity.phase == .loading,
                                isFiltered: !query.isEmpty || !severities.isEmpty
                            ) {
                                Button {
                                    send(.setLogRecording(true))
                                } label: {
                                    Text("Start Recording")
                                }
                                .clashPrimaryActionButtonStyle()
                                .accessibilityIdentifier("logs.startRecording")
                                .padding(.bottom, ClashTheme.Spacing.section)
                            }
                        }
                        .padding(.vertical, ClashTheme.Spacing.section)
                    }
                    .listRowBackground(Color.clear)
                }
                .clashGroupedList()
            } else {
                ClashLogTextView(entries: entries, followsEnd: autoScrollToEnd)
            }
        }
        .clashActivityListCanvas(palette.canvas)
         
         
         
         
        .onChange(of: severities) { severities in
            send(
                .setLogSeverityFilter(
                    ClashActivityLogSeverity.allCases
                        .filter(severities.contains)
                        .map(\.rawValue)
                )
            )
        }
    }

     
     
     
    @State private var projection = ClashActivityProjectionMemo()

     
     
     
    private var shownSeverities: Set<ClashActivityLogSeverity> {
        ClashActivityLogSeverity.expandedSeverities(from: severities)
    }

    private var entries: [ClashActivityLogEntry] {
        projection.logs(
            snapshot.activity.logLines,
            query: query,
            severities: ClashActivityLogSeverity.expandedSeverities(
                from: severities
            )
        )
    }

    private var logEmptyTitle: String {
        if snapshot.activity.phase == .loading {
            return "Connecting to Live Logs"
        }
        return query.isEmpty && severities.isEmpty
            ? (snapshot.activity.isRecordingLogs == false
                ? "Recording Off"
                : "No Logs Yet")
            : "No Matches"
    }

    private var logEmptyMessage: String {
        if !query.isEmpty || !severities.isEmpty {
            return
                "Try a different search term or remove a filter."
        }
         
         
         
         
        if snapshot.activity.isRecordingLogs == false {
            return "Recording is off. Earlier logs are kept; switch it back on to record new ones."
        }
        let kept = snapshot.activity.logRetentionSummary.map { " \($0)" } ?? ""
        return snapshot.activity.phase == .ready
            ? "Nothing has been recorded yet.\(kept)"
            : "Logs are recorded whenever the tunnel runs, and kept after it stops.\(kept)"
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
         
         
         
         
         
         
         
         
         
         
         
        ToolbarItem(placement: .primaryAction) {
            ControlGroup {
                levelsMenu
                    .clashToolbarGlyph()
                    .accessibilityIdentifier("logs.levels")

                if snapshot.activity.canExportLogs {
                    ClashToolbarDivider()

                    Button {
                        send(.exportLogs)
                    } label: {
                        Label(
                            "Export Logs",
                            systemImage: ClashSymbol.squareAndArrowUp.rawValue
                        )
                    }
                    .clashToolbarGlyph()
                    .disabled(snapshot.activity.logLines.isEmpty)
                    .accessibilityIdentifier("logs.export")
                }

                if snapshot.activity.isRecordingLogs != nil
                    || snapshot.activity.canClearLogs {
                    ClashToolbarDivider()

                    Menu {
                        if snapshot.activity.isRecordingLogs != nil {
                            Button {
                                send(.openLogSettings)
                            } label: {
                                Label(
                                    "Log Settings",
                                    systemImage: ClashSymbol.gearshape.rawValue
                                )
                            }
                            .accessibilityIdentifier("logs.settings")
                        }
                        if snapshot.activity.canClearLogs {
                            Button(role: .destructive) {
                                send(.clearLogs)
                            } label: {
                                Label(
                                    "Clear",
                                    systemImage: ClashSymbol.trash.rawValue
                                )
                            }
                            .disabled(snapshot.activity.logLines.isEmpty)
                            .accessibilityIdentifier("logs.clear")
                        }
                    } label: {
                        Label(
                            "More",
                            systemImage: ClashSymbol.ellipsis.rawValue
                        )
                    }
                    .accessibilityIdentifier("logs.more")
                }
            }
            .clashReaderControlGroupStyle()
        }
    }

    private var levelsMenu: some View {
        Menu {
             
             
             
             
             
             
             
             
            Button {
                severities.removeAll()
            } label: {
                if severities.isEmpty {
                    Label("All", systemImage: ClashSymbol.checkmark.rawValue)
                } else {
                    Text(clash: .copy("All"))
                }
            }

            Divider()

            ForEach(ClashActivityLogSeverity.allCases) { severity in
                Button {
                    if severities == [severity] {
                        severities.removeAll()
                    } else {
                        severities = [severity]
                    }
                } label: {
                    let isSelected = severities.contains(severity)
                     
                     
                     
                     
                     
                     
                     
                    if isSelected {
                        Label(severity.title, systemImage: ClashSymbol.checkmark.rawValue)
                    } else {
                        Text(clash: .copy(severity.title))
                    }
                }
            }

             
             
             
             
             
             
             
             
             
             
             
        } label: {
             
             
             
             
             
             
            Label(
                shownSeverities.isEmpty
                    ? "Levels"
                    : "Levels · \(shownSeverities.count)",
                systemImage: ClashSymbol.line3HorizontalDecrease.rawValue
            )
        }
    }

    private func send(_ command: ClashActivityCommand) {
        Task { @MainActor in
            try? await actions.perform(
                .activity(command),
                allowedBy: snapshot
            )
        }
    }
}

 
 
private struct ClashActivityListCanvas: ViewModifier {
    @Environment(\.clashRegularShellOwnsCanvas)
    private var regularShellOwnsCanvas

    let canvas: Color

    func body(content: Content) -> some View {
        content.background(regularShellOwnsCanvas ? Color.clear : canvas)
    }
}

private extension View {
    func clashActivityListCanvas(_ canvas: Color) -> some View {
        modifier(ClashActivityListCanvas(canvas: canvas))
    }
}

 
 
 
enum ClashActivityRowColumns {
    static let dot: CGFloat = 8
    static let proxy: CGFloat = 116
    static let network: CGFloat = 64
    static let bytes: CGFloat = 76
     
    static let time: CGFloat = 90
     
     
     
     
     
     
    static let minimumRegularWidth: CGFloat = 840
    static let action: CGFloat = 24
    static let spacing: CGFloat = 10
}

 
 
 
 
 
 
 
 
 
private struct ClashActivityRowDetail: View {
    enum Place { case endOfLine, ownLine }

    let text: String
    let place: Place
    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ text: String, at place: Place) {
        self.text = text
        self.place = place
    }

    var body: some View {
        if typeSize.isAccessibilitySize == (place == .ownLine) {
             
             
            let label = Text(verbatim: text)
                .font(.caption.monospacedDigit())
                .foregroundColor(ClashActivityBadgeStyle.detailInk)
            if place == .endOfLine {
                label
                    .lineLimit(1)
                    .fixedSize()
            } else {
                label
            }
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashActivityRowLayout {
     
    let rowWidth: CGFloat
     
    let measuresRows: Bool
     
    var isAccessibilityText = false
     
    let report: (CGFloat) -> Void

    var isRegular: Bool {
        rowWidth >= ClashActivityRowColumns.minimumRegularWidth && !isAccessibilityText
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashActivityRowLayoutReader<Content: View>: View {
    let presentationClass: ClashPresentationClass
    @ViewBuilder let content: (ClashActivityRowLayout) -> Content

     
     
    @SceneStorage("activityRowInset") private var storedInset: Double = -1
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GeometryReader { geometry in
            content(layout(listWidth: geometry.size.width))
        }
    }

    private func layout(listWidth: CGFloat) -> ClashActivityRowLayout {
        let measures = presentationClass == .regularTouch
        let stored = $storedInset
        return ClashActivityRowLayout(
            rowWidth: Self.rowWidth(listWidth: listWidth, inset: storedInset, measures: measures),
            measuresRows: measures,
            isAccessibilityText: typeSize.isAccessibilitySize,
            report: { rowWidth in
                guard let inset = Self.inset(listWidth: listWidth, rowWidth: rowWidth),
                      stored.wrappedValue != inset
                else { return }
                stored.wrappedValue = inset
            }
        )
    }

     
     
    static func rowWidth(listWidth: CGFloat, inset: Double, measures: Bool) -> CGFloat {
        guard measures, inset >= 0 else { return 0 }
        return max(0, listWidth - CGFloat(inset))
    }

     
    static func inset(listWidth: CGFloat, rowWidth: CGFloat) -> Double? {
        let inset = Double((listWidth - rowWidth).rounded())
        return rowWidth > 0 && inset >= 0 ? inset : nil
    }
}

 
 
 
 
 
 
 
 
 
 
struct ClashActivityRowWidthReporter: ViewModifier {
    let layout: ClashActivityRowLayout

    @ViewBuilder
    func body(content: Content) -> some View {
        if layout.measuresRows {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { layout.report(proxy.size.width) }
                            .onChange(of: proxy.size.width) { layout.report($0) }
                    }
                )
        } else {
            content
        }
    }
}

 
 
struct ClashActivityColumnHeader: View {
    let showsAction: Bool

    var body: some View {
        HStack(spacing: ClashActivityRowColumns.spacing) {
            Color.clear.frame(width: ClashActivityRowColumns.dot)
            Text("Host").frame(maxWidth: .infinity, alignment: .leading)
            Text("Rule").frame(maxWidth: .infinity, alignment: .leading)
            Text("Proxy").frame(width: ClashActivityRowColumns.proxy, alignment: .leading)
            Text("Protocol").frame(width: ClashActivityRowColumns.network, alignment: .leading)
            Text("Download").frame(width: ClashActivityRowColumns.bytes, alignment: .trailing)
            Text("Upload").frame(width: ClashActivityRowColumns.bytes, alignment: .trailing)
            Text("Time").frame(width: ClashActivityRowColumns.time, alignment: .leading)
            if showsAction {
                Color.clear.frame(width: ClashActivityRowColumns.action)
            }
        }
        .modifier(ClashActivityColumnTitleStyle())
        .accessibilityHidden(true)
    }
}

 
 
struct ClashActivityColumnTitleStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
             
            .textCase(nil)
    }
}

 
 
 
private struct ClashActivityRuleCell: View {
    let row: ClashActivityTableRow
    var isReadable = false

    var body: some View {
        HStack(spacing: ClashTheme.Spacing.tight) {
            if !row.connection.rule.isEmpty {
                ClashActivityBadge(text: row.ruleKind, badge: .ruleKind, isReadable: isReadable)
            }
            if !row.connection.rulePayload.isEmpty {
                Text(verbatim: row.connection.rulePayload)
                    .font(isReadable ? .footnote : .caption)
                    .foregroundStyle(isReadable ? AnyShapeStyle(ClashActivityBadgeStyle.detailInk) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

 
 
private struct ClashActivityProxyCell: View {
    let row: ClashActivityTableRow
    let onKeyword: (String) -> Void

    var body: some View {
        if row.isRejected {
            ClashActivityBadge(text: row.proxy, badge: .refused)
        } else if row.connection.chains.isEmpty {
             
             
            Text(verbatim: row.proxy)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
        } else if !row.proxy.isEmpty {
            Button {
                onKeyword(row.proxy)
            } label: {
                 
                 
                 
                Text(verbatim: row.proxy)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(clash: .format("Filter by %@", [row.proxy])))
        }
    }
}

 
 
private struct ClashActivityStatusDot: View {
    let isLive: Bool

    var body: some View {
        Circle()
            .fill(isLive ? Color.orange : Color.secondary.opacity(0.5))
            .frame(width: 7, height: 7)
            .frame(width: ClashActivityRowColumns.dot)
            .accessibilityLabel(isLive ? Text("Live") : Text("Closed"))
    }
}

private struct ClashActivityConnectionRow: View {
    let connection: ClashActivityConnectionSnapshot
    let text: ClashActivityRowText
    let detailTitle: String
    let actions: AppleClientActions
    let snapshot: AppleClientSnapshot
    let isBusy: Bool
    let showsCloseAction: Bool
    let isCloseDisabled: Bool
    let palette: ClashProductPalette
     
    let isRegular: Bool
    let onKeyword: (String) -> Void
    let onClose: () -> Void

    var body: some View {
        let row = ClashActivityTableRow(connection: connection)
        let network = ClashActivityTableColumn.network.badge(of: row)
        if isRegular {
            HStack(spacing: ClashActivityRowColumns.spacing) {
                ClashActivityStatusDot(isLive: true)
                ClashActivityInspectLink(
                    connection: connection,
                    title: detailTitle,
                    actions: actions,
                    snapshot: snapshot
                ) {
                    Text(verbatim: text.host)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ClashActivityRuleCell(row: row)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ClashActivityProxyCell(row: row, onKeyword: onKeyword)
                    .frame(width: ClashActivityRowColumns.proxy, alignment: .leading)
                Group {
                    if let network {
                        ClashActivityBadge(text: row.trafficProtocol.label, badge: network)
                    }
                }
                .frame(width: ClashActivityRowColumns.network, alignment: .leading)
                Group {
                    Text(verbatim: text.download)
                        .frame(width: ClashActivityRowColumns.bytes, alignment: .trailing)
                    Text(verbatim: text.upload)
                        .frame(width: ClashActivityRowColumns.bytes, alignment: .trailing)
                    Text(verbatim: text.time ?? "")
                        .frame(width: ClashActivityRowColumns.time, alignment: .leading)
                }
                .font(.subheadline.monospacedDigit())
                .lineLimit(1)
                if showsCloseAction || isBusy {
                    closeControl
                        .frame(width: ClashActivityRowColumns.action)
                }
            }
            .font(.subheadline)
            .accessibilityElement(children: .contain)
        } else {
             
             
             
             
             
             
             
            ClashActivityCompactRow(
                connection: connection,
                row: row,
                text: text,
                detailTitle: detailTitle,
                actions: actions,
                snapshot: snapshot,
                isBusy: isBusy
            )
            .accessibilityElement(children: .contain)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if showsCloseAction && !isCloseDisabled {
                    closeButton
                }
            }
            .contextMenu {
                ClashActivityFilterButton(row: row, onKeyword: onKeyword)
                if showsCloseAction && !isCloseDisabled {
                    closeButton
                }
            }
        }
    }

    private var closeButton: some View {
        Button(role: .destructive, action: onClose) {
            Label("Close connection", systemImage: ClashSymbol.xmarkCircle.rawValue)
        }
    }

    @ViewBuilder
    private var closeControl: some View {
        if isBusy {
            ProgressView()
                .controlSize(.small)
        } else if showsCloseAction {
            Button(
                role: .destructive,
                action: onClose
            ) {
                Image(
                    systemName:
                        ClashSymbol.xmarkCircle.rawValue
                )
            }
            .buttonStyle(.borderless)
            .disabled(isCloseDisabled)
            .accessibilityLabel("Close connection")
        }
    }
}

private struct ClashActivityRequestRow: View {
    let entry: ClashActivityRequestSnapshot
    let text: ClashActivityRowText
    let detailTitle: String
    let actions: AppleClientActions
    let snapshot: AppleClientSnapshot
    let palette: ClashProductPalette
     
    let isRegular: Bool
    let onKeyword: (String) -> Void

    var body: some View {
        let connection = entry.connection
        let row = ClashActivityTableRow(request: entry)
        let network = ClashActivityTableColumn.network.badge(of: row)
        if isRegular {
            HStack(spacing: ClashActivityRowColumns.spacing) {
                ClashActivityStatusDot(isLive: entry.isActive)
                ClashActivityInspectLink(
                    connection: connection,
                    title: detailTitle,
                    actions: actions,
                    snapshot: snapshot
                ) {
                    Text(verbatim: text.host)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ClashActivityRuleCell(row: row)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ClashActivityProxyCell(row: row, onKeyword: onKeyword)
                    .frame(width: ClashActivityRowColumns.proxy, alignment: .leading)
                Group {
                    if let network {
                        ClashActivityBadge(text: row.trafficProtocol.label, badge: network)
                    }
                }
                .frame(width: ClashActivityRowColumns.network, alignment: .leading)
                Group {
                    Text(verbatim: text.download)
                        .frame(width: ClashActivityRowColumns.bytes, alignment: .trailing)
                    Text(verbatim: text.upload)
                        .frame(width: ClashActivityRowColumns.bytes, alignment: .trailing)
                    Text(verbatim: text.time ?? "")
                        .frame(width: ClashActivityRowColumns.time, alignment: .leading)
                }
                .font(.subheadline.monospacedDigit())
                .lineLimit(1)
            }
            .font(.subheadline)
            .accessibilityElement(children: .combine)
        } else {
             
             
            ClashActivityCompactRow(
                connection: connection,
                row: row,
                text: text,
                detailTitle: detailTitle,
                actions: actions,
                snapshot: snapshot,
                isLive: entry.isActive
            )
            .accessibilityElement(children: .combine)
            .contextMenu {
                ClashActivityFilterButton(row: row, onKeyword: onKeyword)
            }
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
private struct ClashActivityCompactRow: View {
    let connection: ClashActivityConnectionSnapshot
    let row: ClashActivityTableRow
    let text: ClashActivityRowText
    let detailTitle: String
    let actions: AppleClientActions
    let snapshot: AppleClientSnapshot
     
    var isLive: Bool? = nil
    var isBusy = false

     
     
     
     
    private var hasRule: Bool {
        !row.connection.rule.isEmpty || !row.connection.rulePayload.isEmpty
    }

    var body: some View {
        let network = ClashActivityTableColumn.network.badge(of: row)
        VStack(alignment: .leading, spacing: 3) {
            ClashActivityInspectLink(
                connection: connection,
                title: detailTitle,
                actions: actions,
                snapshot: snapshot
            ) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let isLive {
                        ClashActivityStatusDot(isLive: isLive)
                    }
                    if let network {
                        ClashActivityBadge(text: row.trafficProtocol.label, badge: network)
                    }
                    Text(verbatim: text.host)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    if !hasRule, let time = text.time {
                        ClashActivityRowDetail(time, at: .endOfLine)
                    }
                    if isBusy {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
            }
            if hasRule {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    ClashActivityRuleCell(row: row, isReadable: true)
                    Spacer(minLength: 4)
                    if let time = text.time {
                        ClashActivityRowDetail(time, at: .endOfLine)
                    }
                }
            }
             
             
            if let time = text.time {
                ClashActivityRowDetail(time, at: .ownLine)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                ClashActivityRouteText(row: row)
                Spacer(minLength: 4)
                ClashActivityRowDetail(text.traffic, at: .endOfLine)
                    .layoutPriority(1)
            }
            ClashActivityRowDetail(text.traffic, at: .ownLine)
        }
        .padding(.vertical, 2)
    }
}

 
 
 
 
struct ClashActivityRouteText: View {
    let row: ClashActivityTableRow

    var body: some View {
        if row.isRejected {
            ClashActivityBadge(text: row.proxy, badge: .refused)
        } else {
            Self.text(chains: row.connection.chains, route: row.proxy)
                .font(.footnote)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

     
    static func parts(chains: [String], route: String) -> (group: String?, node: String) {
        guard let node = chains.first else { return (nil, route) }
        guard chains.count > 1, let group = chains.last, group != node else { return (nil, node) }
        return (group, node)
    }

    static func text(chains: [String], route: String) -> Text {
        let parts = parts(chains: chains, route: route)
         
         
        let node = Text(verbatim: parts.node).fontWeight(.semibold)
        guard let group = parts.group else { return node }
        return Text(verbatim: group + " → ").foregroundColor(ClashActivityBadgeStyle.detailInk) + node
    }
}

 
 
private struct ClashActivityFilterButton: View {
    let row: ClashActivityTableRow
    let onKeyword: (String) -> Void

    var body: some View {
        if !row.isRejected, !row.connection.chains.isEmpty, !row.proxy.isEmpty {
            Button {
                onKeyword(row.proxy)
            } label: {
                Label {
                    Text(clash: .format("Filter by %@", [row.proxy]))
                } icon: {
                    Image(systemName: ClashSymbol.line3HorizontalDecrease.rawValue)
                }
            }
        }
    }
}

private struct ClashActivityKeywordButton: View {
     
     
     
     
     
    let title: ClashDisplayText
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(clash: title)
                .font(.caption)
                .lineLimit(1)
                .padding(
                    .horizontal,
                    ClashTheme.Spacing.compact
                )
                .padding(
                    .vertical,
                    ClashTheme.Spacing.tight
                )
                .background(
                    Capsule().fill(
                        Color.secondary.opacity(0.12)
                    )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            Text(clash: .format("Filter by %@", [title.rawValue]))
        )
    }
}

 
 
private struct ClashActivityDetailHost: ViewModifier {
    @Binding var selected: ClashActivityConnectionSnapshot?
    let title: String
    let actions: AppleClientActions
    let snapshot: AppleClientSnapshot

    @ViewBuilder
    func body(content: Content) -> some View {
#if os(macOS)
        content
#else
        content.clashSheet(item: $selected) { connection in
            ClashSingleColumnNavigationContainer {
                ClashActivityConnectionDetailView(
                    connection: connection,
                    title: title,
                    actions: actions,
                    snapshot: snapshot
                )
                .clashToolbarUnlessInPanel {
                    ToolbarItem(placement: .cancellationAction) {
                        ClashSheetCloseButton { selected = nil }
                    }
                }
            }
            .clashModalPresentation(.page)
        }
#endif
    }
}

 
 
 
private struct ClashActivityInspectLink<Label: View>: View {
    let connection: ClashActivityConnectionSnapshot
    let title: String
    let actions: AppleClientActions
    let snapshot: AppleClientSnapshot
    let label: Label

    init(
        connection: ClashActivityConnectionSnapshot,
        title: String,
        actions: AppleClientActions,
        snapshot: AppleClientSnapshot,
        @ViewBuilder label: () -> Label
    ) {
        self.connection = connection
        self.title = title
        self.actions = actions
        self.snapshot = snapshot
        self.label = label()
    }

    @ViewBuilder
    var body: some View {
#if os(macOS)
        ClashRoutedViewLink(
            showsDisclosureIndicator: true
        ) {
            ClashActivityConnectionDetailView(
                connection: connection,
                title: title,
                actions: actions,
                snapshot: snapshot
            )
        } label: {
            label
        }
#else
        label
#endif
    }
}

 
 
private struct ClashActivityTouchSelection: ViewModifier {
    @Binding var selected: ClashActivityConnectionSnapshot?
    let connection: ClashActivityConnectionSnapshot

    @ViewBuilder
    func body(content: Content) -> some View {
#if os(macOS)
        content
#else
        content
            .contentShape(Rectangle())
            .onTapGesture { selected = connection }
#endif
    }
}

private struct ClashActivityConnectionDetailView: View {
    let connection: ClashActivityConnectionSnapshot
    let title: String
    let actions: AppleClientActions
    let snapshot: AppleClientSnapshot
     
     
    @Environment(\.clashThroughputUnit) private var throughputUnit

    var body: some View {
        List {
            Section("Session") {
                if let start = connection.start {
                    detailRow(
                        "Created",
                        start.formatted(
                            date: .abbreviated,
                            time: .standard
                        )
                    )
                }
                detailRow("Network", connection.network)
                detailRow(
                    "Process",
                    connection.processDescription,
                    copyable: true
                )
                detailRow(
                    "Process path",
                    connection.processPath,
                    copyable: true
                )
                detailRow(
                    "Rule",
                    connection.ruleDescription
                )
            }

            Section("Endpoints") {
                detailRow(
                    "Host",
                    connection.host,
                    copyable: true
                )
                detailRow(
                    "Source",
                    connection.source,
                    copyable: true
                )
                detailRow(
                    "Destination",
                    ipDestination,
                    copyable: true
                )
                detailRow(
                    "Remote destination",
                    connection.remoteDestination,
                    copyable: true
                )
            }

            Section("Traffic") {
                detailRow(
                    "Upload",
                    ClashActivityByteFormatter.count(
                        connection.upload
                    )
                )
                detailRow(
                    "Download",
                    ClashActivityByteFormatter.count(
                        connection.download
                    )
                )
                if let speed = connection.uploadSpeed {
                    detailRow(
                        "Upload speed",
                        ClashThroughputFormatter.rate(speed, unit: throughputUnit)
                    )
                }
                if let speed = connection.downloadSpeed {
                    detailRow(
                        "Download speed",
                        ClashThroughputFormatter.rate(speed, unit: throughputUnit)
                    )
                }
            }

            if !connection.chains.isEmpty {
                Section("Proxy chain") {
                    ForEach(
                        Array(connection.chains.enumerated()),
                        id: \.offset
                    ) { _, chain in
                        detailRow("Proxy", chain)
                    }
                }
            }

            Section("Metadata") {
                detailRow(
                    "Destination GeoIP",
                    connection.destinationGeoIP.joined(
                        separator: " "
                    )
                )
                detailRow(
                    "Destination ASN",
                    connection.destinationIPASN
                )
                detailRow(
                    "Source GeoIP",
                    connection.sourceGeoIP.joined(
                        separator: " "
                    )
                )
                detailRow(
                    "Source ASN",
                    connection.sourceIPASN
                )
                detailRow("DNS mode", connection.dnsMode)
                detailRow(
                    "Special proxy",
                    connection.specialProxy
                )
                detailRow(
                    "Special rules",
                    connection.specialRules
                )
            }
        }
        .clashPageTitle(.copy(title))
    }

    private var ipDestination: String {
        guard !connection.destinationIP.isEmpty else {
            return connection.destination
        }
        guard !connection.destinationPort.isEmpty,
              connection.destinationPort != "0"
        else {
            return connection.destinationIP
        }
        if connection.destinationIP.contains(":") {
            return
                "[\(connection.destinationIP)]:\(connection.destinationPort)"
        }
        return
            "\(connection.destinationIP):\(connection.destinationPort)"
    }

    @ViewBuilder
    private func detailRow(
        _ label: String,
        _ value: String,
        copyable: Bool = false
    ) -> some View {
        if !value.isEmpty {
            HStack(
                alignment: .firstTextBaseline,
                spacing: ClashTheme.Spacing.standard
            ) {
                Text(clash: .copy(label))
                    .foregroundStyle(.secondary)
                Spacer(minLength: ClashTheme.Spacing.standard)
                Text(value)
                    .multilineTextAlignment(.trailing)
                if copyable {
                    Button {
                        send(.copyText(value))
                    } label: {
                        Image(
                            systemName:
                                ClashSymbol
                                .docOnClipboard.rawValue
                        )
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Copy \(label)")
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func send(_ command: ClashActivityCommand) {
        Task { @MainActor in
            try? await actions.perform(
                .activity(command),
                allowedBy: snapshot
            )
        }
    }
}
