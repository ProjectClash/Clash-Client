import Combine
import SwiftUI

private struct ClashRegularRootScrollsContentKey: EnvironmentKey {
    static let defaultValue = false
}

 
 
 
 
 
 
struct ClashScrollRequestKey: EnvironmentKey {
     
     
    static let defaultValue: ClashScrollRequest? = nil
}

 
 
 
 
 
public struct ClashScrollRequest: @unchecked Sendable, Equatable {
     
     
     
    private let token: UUID
    private let perform: (AnyHashable, UnitPoint) -> Void

    init(token: UUID = UUID(), perform: @escaping (AnyHashable, UnitPoint) -> Void) {
        self.token = token
        self.perform = perform
    }

     
    public func callAsFunction(_ id: AnyHashable) {
        perform(id, .top)
    }

     
    public func callAsFunction(_ id: AnyHashable, anchor: UnitPoint) {
        perform(id, anchor)
    }

    public static func == (a: Self, b: Self) -> Bool {
        a.token == b.token
    }
}

struct ClashShellDrawsRootHeadingKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    internal var clashScrollToID: ClashScrollRequest? {
        get { self[ClashScrollRequestKey.self] }
        set { self[ClashScrollRequestKey.self] = newValue }
    }
}

private struct ClashRegularRootLargeTitleKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

private struct ClashRegularShellOwnsCanvasKey: EnvironmentKey {
    static let defaultValue = false
}

 
 
 
 
 
 
 
 
 
private struct ClashRegularRootIsActiveKey: EnvironmentKey {
    static let defaultValue = true
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
public final class ClashLatencyPulseGate: @unchecked Sendable, Equatable {
    public var isOpen = true
     
     
     
     
     
     
     
    public let opened = PassthroughSubject<Void, Never>()
     
     
     
     
    public let closed = PassthroughSubject<Void, Never>()
    public init() {}

     
    public func setOpen(_ open: Bool) {
        let wasOpen = isOpen
        isOpen = open
        if open, !wasOpen { opened.send() }
        if !open, wasOpen { closed.send() }
    }

     
     
     
     
     
     
     
    public static func == (a: ClashLatencyPulseGate, b: ClashLatencyPulseGate) -> Bool {
        a === b
    }
}

private struct ClashLatencyPulseGateKey: EnvironmentKey {
     
     
    static let defaultValue: ClashLatencyPulseGate? = nil
}

 
 
 
 
 
 
 
 
 
@MainActor
public final class ClashRegularRootChannels: ObservableObject {
    @Published public var searchText = ""
    @Published public var foldCommand = 0
     
     
     
    @Published public var contentGeneration = 0
    @Published public var isActive = true
     
     
     
     
     
    public let latencyPulseGate = ClashLatencyPulseGate()
     
     
     
    public var uiTransitionSink: (() -> Void)?
     
     
     
     
     
     
     
     
    @Published public var openGroup = ClashRootOpenGroupSignal()
    @Published public var displayPreferences = ClashRootDisplaySignal()

    public init() {}

     
     
     
     
    public func requestOpenGroup(
        _ name: String,
        opening: ClashRootOpenGroupSignal.Opening = .browsing
    ) {
        openGroup = ClashRootOpenGroupSignal(
            token: openGroup.token &+ 1,
            group: name,
            opening: opening
        )
    }

     
     
     
     
     
     
    public func requestBrowsing() {
        openGroup = ClashRootOpenGroupSignal(
            token: openGroup.token &+ 1,
            group: nil,
            opening: .browsing
        )
    }

     
     
     
     
     
     
     
     
    public func requestDisplayPreferences(
        _ value: ClashProxiesDisplayPreferences
    ) {
        displayPreferences = ClashRootDisplaySignal(
            token: displayPreferences.token &+ 1,
            preferences: value
        )
    }
}

 
 
public struct ClashRootOpenGroupSignal: Equatable, Sendable {
     
     
     
    public enum Opening: Equatable, Hashable, Sendable {
         
        case browsing
         
         
        case choosingInGlobal
    }

    public var token = 0
    public var group: String?
    public var opening: Opening = .browsing

    public init(token: Int = 0, group: String? = nil, opening: Opening = .browsing) {
        self.token = token
        self.group = group
        self.opening = opening
    }
}

 
 
public struct ClashRootDisplaySignal: Equatable, Sendable {
    public var token = 0
    public var preferences: ClashProxiesDisplayPreferences?

    public init(
        token: Int = 0,
        preferences: ClashProxiesDisplayPreferences? = nil
    ) {
        self.token = token
        self.preferences = preferences
    }
}

private struct ClashRegularRootOpenGroupKey: EnvironmentKey {
    static let defaultValue = ClashRootOpenGroupSignal()
}

private struct ClashRegularRootDisplayKey: EnvironmentKey {
    static let defaultValue = ClashRootDisplaySignal()
}

 
 
 
 
 
 
private struct ClashHostedInRootPoolKey: EnvironmentKey {
    static let defaultValue = false
}

 
 
 
public struct ClashPooledRootFeed: View {
    @ObservedObject private var channels: ClashRegularRootChannels
    private let foldStateSink: ClashBoolSink?
     
     
    private let background: Color
    private let build: () -> AnyView

    public init(
        channels: ClashRegularRootChannels,
        foldStateSink: ClashBoolSink? = nil,
        background: Color,
        build: @escaping () -> AnyView
    ) {
        self.channels = channels
        self.foldStateSink = foldStateSink
        self.background = background
        self.build = build
    }

    public var body: some View {
         
         
         
         
         
        ClashRegularDetailNavigationFrame(background: background) {
            fed
        }
    }

    private var fed: some View {
        build()
            .environment(\.clashRegularRootSearchText, channels.searchText)
            .environment(\.clashRegularRootFoldCommand, channels.foldCommand)
            .environment(\.clashRegularRootFoldStateSink, foldStateSink)
            .environment(\.clashRegularRootIsActive, channels.isActive)
            .environment(\.clashLatencyPulseGate, channels.latencyPulseGate)
            .environment(\.clashRegularRootOpenGroup, channels.openGroup)
            .environment(
                \.clashRegularRootDisplayPreferences, channels.displayPreferences
            )
            .environment(\.clashHostedInRootPool, true)
             
             
             
             
             
             
             
            .environment(\.clashRegularRootScrollsContent, false)
            .environment(\.clashRegularRootLargeTitle, nil)
            .environment(\.clashShellDrawsRootHeading, true)
            .environment(\.clashRegularShellOwnsCanvas, true)
    }
}

 
 
 
 
 
 
 
 
 
 
private struct ClashPageDrawsOwnCardsKey: EnvironmentKey {
    static let defaultValue = false
}

 
 
 
 
 
 
 
private struct ClashRegularRootSearchTextKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

 
 
 
 
 
 
private struct ClashRegularRootFoldCommandKey: EnvironmentKey {
    static let defaultValue = 0
}

 
 
private struct ClashRegularRootFoldStateSinkKey: EnvironmentKey {
     
     
    nonisolated(unsafe) static let defaultValue: ClashBoolSink? = nil
}

 
 
 
 
public struct ClashBoolSink: Equatable {
    private let token: UUID
    private let sink: (Bool) -> Void

    public init(token: UUID = UUID(), _ sink: @escaping (Bool) -> Void) {
        self.token = token
        self.sink = sink
    }

    public func callAsFunction(_ value: Bool) {
        sink(value)
    }

    public static func == (a: Self, b: Self) -> Bool {
        a.token == b.token
    }
}

extension EnvironmentValues {
    var clashRegularRootScrollsContent: Bool {
        get { self[ClashRegularRootScrollsContentKey.self] }
        set { self[ClashRegularRootScrollsContentKey.self] = newValue }
    }

    var clashPageDrawsOwnCards: Bool {
        get { self[ClashPageDrawsOwnCardsKey.self] }
        set { self[ClashPageDrawsOwnCardsKey.self] = newValue }
    }

    public var clashRegularRootIsActive: Bool {
        get { self[ClashRegularRootIsActiveKey.self] }
        set { self[ClashRegularRootIsActiveKey.self] = newValue }
    }

    public var clashLatencyPulseGate: ClashLatencyPulseGate? {
        get { self[ClashLatencyPulseGateKey.self] }
        set { self[ClashLatencyPulseGateKey.self] = newValue }
    }

    public var clashRegularRootOpenGroup: ClashRootOpenGroupSignal {
        get { self[ClashRegularRootOpenGroupKey.self] }
        set { self[ClashRegularRootOpenGroupKey.self] = newValue }
    }

    public var clashRegularRootDisplayPreferences: ClashRootDisplaySignal {
        get { self[ClashRegularRootDisplayKey.self] }
        set { self[ClashRegularRootDisplayKey.self] = newValue }
    }

    public var clashHostedInRootPool: Bool {
        get { self[ClashHostedInRootPoolKey.self] }
        set { self[ClashHostedInRootPoolKey.self] = newValue }
    }

    public var clashRegularRootSearchText: String? {
        get { self[ClashRegularRootSearchTextKey.self] }
        set { self[ClashRegularRootSearchTextKey.self] = newValue }
    }

    public var clashRegularRootFoldCommand: Int {
        get { self[ClashRegularRootFoldCommandKey.self] }
        set { self[ClashRegularRootFoldCommandKey.self] = newValue }
    }

    public var clashRegularRootFoldStateSink: ClashBoolSink? {
        get { self[ClashRegularRootFoldStateSinkKey.self] }
        set { self[ClashRegularRootFoldStateSinkKey.self] = newValue }
    }

    var clashRegularRootLargeTitle: String? {
        get { self[ClashRegularRootLargeTitleKey.self] }
        set { self[ClashRegularRootLargeTitleKey.self] = newValue }
    }

     
     
     
     
     
     
    var clashShellDrawsRootHeading: Bool {
        get { self[ClashShellDrawsRootHeadingKey.self] }
        set { self[ClashShellDrawsRootHeadingKey.self] = newValue }
    }

    var clashRegularShellOwnsCanvas: Bool {
        get { self[ClashRegularShellOwnsCanvasKey.self] }
        set { self[ClashRegularShellOwnsCanvasKey.self] = newValue }
    }
}

 
 
 
 
 
 
 
public struct ClashRegularRootTopVisibilityPreferenceKey: PreferenceKey {
    public static let defaultValue = true

    public static func reduce(
        value: inout Bool,
        nextValue: () -> Bool
    ) {
        value = value && nextValue()
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
public struct ClashProductDestinationPresentation: Equatable, Sendable {
    public let title: ClashDisplayText
    public let subtitle: ClashDisplayText
    public let badge: ClashDisplayText?

    public init(
        title: ClashDisplayText,
        subtitle: ClashDisplayText,
        badge: ClashDisplayText? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
    }
}

 
 
 
 
 
struct ClashProductRootPage<Content: View>: View {
    @Environment(\.clashRegularRootScrollsContent)
    private var regularShellScrollsContent
    @Environment(\.clashRegularRootLargeTitle)
    private var regularRootLargeTitle
    @Environment(\.clashRegularShellOwnsCanvas)
    private var regularShellOwnsCanvas
    @State private var isScrollTopVisible = true
     
    @State private var scrollRequestToken = UUID()

    let palette: ClashProductPalette
    let accessibilityIdentifier: String
     
     
     
     
     
     
     
     
     
     
     
    let hostsSelfDrawnCards: Bool
    let content: Content

    init(
        palette: ClashProductPalette,
        accessibilityIdentifier: String,
        hostsSelfDrawnCards: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.palette = palette
        self.accessibilityIdentifier = accessibilityIdentifier
        self.hostsSelfDrawnCards = hostsSelfDrawnCards
        self.content = content()
    }

    var body: some View {
        let _ = ClashPerf.count("root.page.body")
        Group {
            if regularShellScrollsContent {
                productContent
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(accessibilityIdentifier)
            } else {
                internallyScrollingContent
            }
        }
         
         
        .environment(\.clashPageDrawsOwnCards, hostsSelfDrawnCards)
        .background(rootCanvas)
    }

    @ViewBuilder
    private var productContent: some View {
         
         
         
         
        if ClashPlatformLayout.pageUsesSystemSettingsIdiom,
           !hostsSelfDrawnCards,
           #available(iOS 16.0, macOS 13.0, *) {
            VStack(alignment: .leading, spacing: 0) {
                alignedLargeTitle
                    .padding(.horizontal, ClashTheme.Spacing.standard)
                    .padding(.top, ClashTheme.Spacing.section)
                Form { content }
                    .formStyle(.grouped)
                    .environment(\.defaultMinListRowHeight, 0)
                     
                     
                     
                    .scrollContentBackground(.hidden)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: ClashTheme.Spacing.section) {
                alignedLargeTitle
                content
            }
            .padding(.horizontal, ClashTheme.Layout.cardHorizontalInset)
            .padding(.vertical, ClashTheme.Spacing.section)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var internallyScrollingContent: some View {
        ScrollViewReader { proxy in
            scrollingBody
                .environment(
                    \.clashScrollToID,
                    ClashScrollRequest(token: scrollRequestToken) { id, anchor in
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(id, anchor: anchor)
                        }
                    }
                )
        }
    }

    @ViewBuilder
    private var scrollingBody: some View {
        if ClashPlatformLayout.pageUsesSystemSettingsIdiom,
           !hostsSelfDrawnCards {
             
             
             
             
             
            productContent
        } else if #available(iOS 18.0, macOS 15.0, tvOS 18.0, *) {
            ScrollView {
                productContent
            }
            .onScrollGeometryChange(for: String.self) { geo in
                "content=\(Int(geo.contentSize.height)) off=\(Int(geo.contentOffset.y)) view=\(Int(geo.containerSize.height))"
            } action: { old, new in
                guard old != new else { return }
                ClashScrollGeoProbe.emit(new, id: accessibilityIdentifier)
            }
            .onScrollPhaseChange { _, newPhase in
                if newPhase.isScrolling {
                    isScrollTopVisible = false
                }
            }
            .accessibilityIdentifier(accessibilityIdentifier)
            .preference(
                key: ClashRegularRootTopVisibilityPreferenceKey.self,
                value: isScrollTopVisible
            )
        } else {
            ScrollView {
                productContent
            }
            .accessibilityIdentifier(accessibilityIdentifier)
            .preference(
                key: ClashRegularRootTopVisibilityPreferenceKey.self,
                value: isScrollTopVisible
            )
        }
    }

    @ViewBuilder
    private var alignedLargeTitle: some View {
        if let title = regularRootLargeTitle {
            largeTitle(title)
        }
    }

    private func largeTitle(_ title: String) -> some View {
         
         
         
        Text(clash: .copy(title))
            .font(.title2.bold())
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("regular.detail.title")
    }

    @ViewBuilder
    private var rootCanvas: some View {
        if regularShellOwnsCanvas {
            Color.clear
        } else {
            palette.canvas.ignoresSafeArea()
        }
    }
}

public extension View {
     
     
     
     
     
     
     
     
    func clashOwnsProductCanvas() -> some View {
        environment(\.clashRegularShellOwnsCanvas, false)
    }
}

 
struct ClashProductPageSection<Content: View>: View {
    let title: String
    let palette: ClashProductPalette
    let presentationClass: ClashPresentationClass
    let content: Content

    init(
        title: String,
        palette: ClashProductPalette,
        presentationClass: ClashPresentationClass,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.palette = palette
        self.presentationClass = presentationClass
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
         
         
         
         
         
         
         
        if ClashPlatformLayout.pageUsesSystemSettingsIdiom {
            Section {
                content
            } header: {
                Text(clash: .copy(title))
            }
        } else {
            VStack(alignment: .leading, spacing: ClashTheme.Spacing.compact) {
                Text(clash: .copy(title))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, ClashTheme.Layout.cardHorizontalInset)

                primaryCard
            }
        }
    }

     
     
     
    private var primaryCard: AnyView {
        let rows = VStack(spacing: 0) {
            content
        }
        .padding(
            .vertical,
            presentationClass == .regularTouch
                || presentationClass == .desktop
                ? ClashTheme.Spacing.compact
                : 0
        )
        .padding(.horizontal, ClashTheme.Spacing.standard)
        .frame(maxWidth: .infinity, alignment: .leading)
        let traditionalCard = ClashCardSurface(
            fill: palette.card,
            separator: palette.separator,
            cornerRadius: ClashTheme.Radius.groupedSection
        ) {
            rows
        }

         
         
         
         
         
         
         
        if usesTraditionalPrimaryCard
            || !ClashPlatformLayout.touchCardWearsSystemMaterial {
            return AnyView(traditionalCard)
        }
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, *) {
             
             
             
             
            return AnyView(
                rows
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: ClashTheme.Radius.liquidGlassCard,
                            style: .continuous
                        )
                    )
                    .glassEffect(
                        .regular,
                        in: .rect(
                            cornerRadius: ClashTheme.Radius.liquidGlassCard
                        )
                    )
            )
        }
        return AnyView(traditionalCard)
    }

     
     
     
     
    static func usesTraditionalPrimaryCard(
        for presentationClass: ClashPresentationClass
    ) -> Bool {
         
         
         
         
         
         
        presentationClass == .desktop
    }

    private var usesTraditionalPrimaryCard: Bool {
        Self.usesTraditionalPrimaryCard(for: presentationClass)
    }
}

 
public struct ClashProductDestinationRow<Icon: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    public let presentation: ClashProductDestinationPresentation
    public let symbol: ClashSymbol
    public let tint: Color
    public let presentationClass: ClashPresentationClass
    public let palette: ClashProductPalette
    private let icon: (ClashSymbol) -> Icon

    public init(
        presentation: ClashProductDestinationPresentation,
        symbol: ClashSymbol,
        tint: Color,
        presentationClass: ClashPresentationClass,
        palette: ClashProductPalette,
        @ViewBuilder icon: @escaping (ClashSymbol) -> Icon
    ) {
        self.presentation = presentation
        self.symbol = symbol
        self.tint = tint
        self.presentationClass = presentationClass
        self.palette = palette
        self.icon = icon
    }

    public var body: some View {
        Group {
            if dynamicTypeSize >= .accessibility1 {
                VStack(
                    alignment: .leading,
                    spacing: ClashTheme.Spacing.standard
                ) {
                    HStack {
                        leadingIcon
                        Spacer(minLength: ClashTheme.Spacing.standard)
                        disclosureIcon
                    }

                    destinationCopy
                }
            } else {
                 
                 
                 
                 
                HStack(
                    alignment: .center,
                    spacing: ClashTheme.Spacing.row
                ) {
                    leadingIcon
                    destinationCopy
                    Spacer(minLength: 0)
                    disclosureIcon
                }
            }
        }
         
         
         
         
         
        .padding(
            .vertical,
            ClashMacSettingsMetrics.rowVerticalInset(
                touch: ClashTheme.Spacing.compact
            )
        )
         
         
         
         
        .frame(minHeight: rowFloor)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var leadingIcon: some View {
        ClashIconWell(tint: tint) {
            icon(symbol)
                .font(.body.weight(.semibold))
        }
    }

    private var destinationCopy: some View {
        VStack(
            alignment: .leading,
            spacing: ClashTheme.Typography.rowSubtitleGap(locale)
        ) {
            Text(clash: presentation.title)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(clash: presentation.subtitle)
                .font(ClashTheme.Typography.rowSubtitle(locale))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var disclosureIcon: some View {
        icon(.chevronForward)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

     
     
     
     
    private var ownsRowMetrics: Bool {
        !ClashPlatformLayout.pageUsesSystemSettingsIdiom
    }

     
     
     
     
     
     
    private var rowFloor: CGFloat? {
        guard ownsRowMetrics else { return nil }
        if let regular = destinationRowMinHeight { return regular }
        return hasSubtitle ? ClashTheme.Layout.destinationRowTargetHeight : nil
    }

    private var hasSubtitle: Bool {
        switch presentation.subtitle {
        case .verbatim(let value), .copy(let value): return !value.isEmpty
        default: return true
        }
    }

    private var destinationRowMinHeight: CGFloat? {
        presentationClass == .regularTouch || presentationClass == .desktop
            ? ClashTheme.Regular.Detail.destinationRowMinHeight
            : nil
    }
}

 
 
@MainActor
enum ClashScrollGeoProbe {
    private static var last = Date.distantPast
    static func emit(_ line: String, id: String) {
        let now = Date()
        guard now.timeIntervalSince(last) > 1 else { return }
        last = now
        ClashPerf.emit("scrollgeo \(id) \(line)")
    }
}
