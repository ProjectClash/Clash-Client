import Foundation
import SwiftUI

 
 
 
 
 
 
struct ClashRuleBucketRoute: Hashable {
    let target: String
}

 
 
 
struct ClashRulesEditRoute: Hashable {}

 
 
 
 
 
 
 
 
 
 
 
enum ClashRuleRowLayout {
    static func showsTypeLine(payload: String) -> Bool {
        !payload.isEmpty
    }
}

private struct ClashRuleBucketRowChrome: ViewModifier {
    let bucket: ClashRuleBucketSnapshot
    @Environment(\.locale) private var locale

    func body(content: Content) -> some View {
        content
            .buttonStyle(.plain)
            .accessibilityLabel(
                ClashRulesCountCopy.rulesTo(bucket.ruleCount, target: bucket.target, locale: locale)
            )
            .accessibilityIdentifier("rules.bucket.\(bucket.target)")
    }
}

public struct ClashRulesOverviewView<
    Icon: View,
    ActiveRules: View
>: View {
     
     
    @Environment(\.locale)
    private var locale
    private let snapshot: AppleClientSnapshot
    private let actions: AppleClientActions
    private let presentationClass: ClashPresentationClass
    private let searchPlacement: SearchFieldPlacement
    private let palette: ClashProductPalette
    private let icon: (ClashSymbol) -> Icon
     
     
     
     
     
     
     
    private let activeRulesDestination: () -> ActiveRules
     
     
     
     
     
     
    private let editRulesDestination: (() -> AnyView)?
    private let showsDismissControl: Bool

     
     
     
     
     
    @StateObject private var dismiss = ClashDismissHandle()
    @Environment(\.clashPushRoute) private var pushRoute
    @Environment(\.clashPopRoute) private var popRoute
    @Environment(\.clashDetailCanvas) private var inheritedDetailCanvas
     
     
     
    @Environment(\.clashRegularRootSearchText) private var externalSearchText
    @Environment(\.clashHostedInRootPool) private var hostedInRootPool
    @State private var query = ""
     
     
    @Environment(\.clashRulesSearch) private var rulesSearch
    @State private var countedSearch: (query: String, result: ClashRulesSearchResult?)?
     
     
     
     
    @State private var identityStamp = UUID()

    public init(
        snapshot: AppleClientSnapshot,
        actions: AppleClientActions,
        presentationClass: ClashPresentationClass,
        searchPlacement: SearchFieldPlacement = .automatic,
        palette: ClashProductPalette,
        showsDismissControl: Bool = true,
        editRulesDestination: (() -> AnyView)? = nil,
        @ViewBuilder icon: @escaping (ClashSymbol) -> Icon,
        @ViewBuilder activeRulesDestination: @escaping () -> ActiveRules
    ) {
        self.snapshot = snapshot
        self.actions = actions
        self.presentationClass = presentationClass
        self.searchPlacement = searchPlacement
        self.palette = palette
        self.showsDismissControl = showsDismissControl
        self.editRulesDestination = editRulesDestination
        self.icon = icon
        self.activeRulesDestination = activeRulesDestination
    }

     
    var offersRuleEditing: Bool { editRulesDestination != nil }

    public var body: some View {
        routedRootPage
            .onAppear {
                ClashPerf.emit(
                    "rules entry-open id=\(identityStamp.uuidString.prefix(5))"
                )
            }
        .clashCapturesDismiss(dismiss)
    }

     
     
     
     
     
     
     
     
     
     
    @ViewBuilder
    private var routedRootPage: some View {
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, *) {
            rootPage
                .navigationDestination(for: ClashRuleBucketRoute.self) { route in
                    ClashLazyView {
                        Group {
                            if let bucket = overview.buckets.first(
                                where: { $0.target == route.target }
                            ) {
                                bucketDetail(bucket)
                            } else {
                                 
                                 
                                 
                                ClashEmptyState(
                                    title: "Rules Changed",
                                    message:
                                        "This group is no longer in the profile's rules."
                                ) {
                                    icon(.exclamationmarkTriangle)
                                }
                            }
                        }
                        .clashPushedDetailPage()
                        .modifier(ClashSetterRoutedBack())
                         
                        .clashDeparturePage()
                         
                         
                        .environment(\.clashPushRoute, pushRoute)
                        .environment(\.clashPopRoute, popRoute)
                        .environment(\.clashDetailCanvas, inheritedDetailCanvas)
                        .environment(
                            \.clashRegularShellOwnsCanvas,
                            ClashPushedCanvasOwnership.shellOwnsPushedCanvas
                        )
                    }
                }
                .navigationDestination(for: ClashRulesEditRoute.self) { _ in
                    editRulesPage
                        .clashPushedDetailPage()
                }
        } else {
            rootPage
        }
    }

     
     
    @ViewBuilder
    private var editRulesPage: some View {
        if let editRulesDestination {
            ClashLazyView {
                editRulesDestination()
                    .environment(\.clashPushRoute, pushRoute)
                    .environment(\.clashPopRoute, popRoute)
                    .environment(\.clashDetailCanvas, inheritedDetailCanvas)
            }
        }
    }

     
     
     
     
    @ViewBuilder
    private var editRulesControl: some View {
        if let editRulesDestination {
            Group {
                if #available(iOS 16.0, macOS 13.0, tvOS 16.0, *) {
                    NavigationLink(value: ClashRulesEditRoute()) { Text("Edit") }
                } else {
                    NavigationLink {
                        editRulesDestination()
                            .clashPushedDetailPage()
                            .clashNativePushBoundary()
                    } label: { Text("Edit") }
                }
            }
            .accessibilityIdentifier("rules.overview.edit")
        }
    }

     
     
    private var effectiveQuery: String {
        externalSearchText ?? query
    }

     
     
     
     
    @ViewBuilder
    private var rootPage: some View {
        if externalSearchText == nil {
            undecoratedRootPage
                 
                 
                .clashFrameWatch("rules-page")
                .searchable(
                    text: $query,
                    placement: searchPlacement,
                    prompt: Text("Search rules")
                )
                .clashToolbarUnlessInPanel {
                     
                     
                     
                     
                    ToolbarItem(placement: .cancellationAction) {
                        if showsDismissControl {
                            ClashSheetCloseButton { dismiss() }
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        editRulesControl
                    }
                }
        } else {
            undecoratedRootPage
        }
    }

    private var undecoratedRootPage: some View {
        ClashRulesBrowserHost {
             
             
            ClashRulesSystemOverview(
                overview: overview,
                query: effectiveQuery,
                palette: palette,
                icon: icon,
                activeRulesEntry: AnyView(activeRulesEntry(selfDrawnDisclosure: false))
            )
             
             
             
            .clashRootHeading("Rules")
            .accessibilityIdentifier("rules.overview")
            .environment(\.clashDetailCanvas, palette.canvas)
        } legacy: {
            legacyRootPage
        }
    }

    private var legacyRootPage: some View {
        ClashProductRootPage(
            palette: palette,
            accessibilityIdentifier: "rules.product.root",
             
             
             
             
             
             
             
            hostsSelfDrawnCards: true
        ) {
            if effectiveQuery.isEmpty {
                overviewSections
            } else {
                searchResults
            }
            activeRulesEntry(selfDrawnDisclosure: true)
        }
         
         
        .task(id: overview.rulesAreCounted ? effectiveQuery : "") {
            let normalized = effectiveQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard overview.rulesAreCounted, !normalized.isEmpty else {
                countedSearch = nil
                return
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            let found = await rulesSearch?.search(normalized)
            if Task.isCancelled { return }
            countedSearch = (normalized, found)
        }
        .clashContentHeading("Rules")
        .accessibilityIdentifier("rules.overview")
        .environment(\.clashDetailCanvas, palette.canvas)
    }

    private var overview: ClashRulesOverviewSnapshot {
        snapshot.rules.overview
    }

     
     
     
     
     
    private func activeRulesEntry(selfDrawnDisclosure: Bool) -> some View {
        ClashCardSurface(
            fill: palette.card,
            separator: palette.separator
        ) {
            ClashRoutedViewLink(showsDisclosureIndicator: false) {
                activeRulesDestination()
                .clashPushedDetailPage()
            } label: {
                HStack(spacing: ClashTheme.Spacing.row) {
                    icon(.docTextMagnifyingglass)
                        .font(.title3)
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)

                    VStack(
                        alignment: .leading,
                        spacing: ClashTheme.Spacing.tight
                    ) {
                        Text("Active Rules")
                            .font(.body.weight(.semibold))
                        Text(
                            snapshot.rules.canInspectActiveRules
                                ? "Inspect the rules currently loaded by the running core."
                                : "Connect Clash to inspect the rules loaded by the running core."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: ClashTheme.Spacing.compact)

                     
                     
                    if selfDrawnDisclosure {
                        icon(.chevronForward)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .padding(ClashTheme.Spacing.standard)
            }
            .buttonStyle(.plain)
            .disabled(!snapshot.rules.canInspectActiveRules)
            .accessibilityIdentifier("rules.overview.active-rules")
        }
    }

    @ViewBuilder
    private var overviewSections: some View {
         
         
         
         
         
         
        if overview.hasRulesGroup {
            let groupedByDestination: ClashDisplayText? = overview.buckets.isEmpty
                ? nil
                : "Grouped by destination. What the tunnel runs: the profile's rules with your custom rules and the override script applied."
            ClashProductGroup(
                .format(
                    "Rules (%@)",
                    [ClashCopy.count(overview.inlineCount, locale: locale)]
                ),
                footer: groupedByDestination,
                palette: palette
            ) {
                 
                 
                 
                 
                 
                 
                VStack(
                    alignment: .leading,
                    spacing: ClashTheme.Spacing.standard
                ) {
                    if overview.inapplicableCount > 0 {
                        inapplicableNotice
                    }

                     
                     
                     
                     
                    if !overview.buckets.isEmpty {
                        LazyVStack(spacing: 0) {
                            ForEach(overview.buckets) { bucket in
                                bucketLink(bucket)
                                if bucket.id != overview.buckets.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
        }

        if !overview.ruleSets.isEmpty {
            ClashProductGroup(
                .format(
                    "Rule Sets (%@)",
                    [String(overview.ruleSets.count)]
                ),
                palette: palette
            ) {
                LazyVStack(spacing: 0) {
                    ForEach(overview.ruleSets) { ruleSet in
                        ruleSetRow(ruleSet)
                        if ruleSet.id != overview.ruleSets.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }

        if !overview.fallback.isEmpty {
            ClashProductGroup(
                "Fallback",
                footer: "Traffic that matches nothing above.",
                palette: palette
            ) {
                LazyVStack(spacing: 0) {
                    ForEach(overview.fallback) { rule in
                        ruleRow(
                            rule,
                            verticalInset: ClashTheme.Spacing.compact
                        )
                        if rule.id != overview.fallback.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }

         
         
        if !overview.hasRulesGroup
            && overview.ruleSets.isEmpty
            && overview.fallback.isEmpty
        {
            ClashProductGroup(palette: palette) {
                ClashEmptyState(
                    title: "No Rules",
                    message:
                        "This profile does not declare routing rules or rule providers."
                ) {
                    icon(.listBulletRectangle)
                }
            }
        }
    }

    @ViewBuilder
    private var searchResults: some View {
         
         
        let counted = overview.rulesAreCounted
            ? countedSearch.flatMap { $0.query == effectiveQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                ? $0.result : nil }
            : nil
        let hits = counted?.rules ?? overview.search(effectiveQuery)
        let hitCount = counted?.total ?? hits.count
        let rows = Array(hits.prefix(100))
        ClashProductGroup(
            .format(hitCount == 1 ? "%@ match" : "%@ matches", [ClashCopy.count(hitCount, locale: locale)]),
            palette: palette
        ) {
             
             
            VStack(
                alignment: .leading,
                spacing: ClashTheme.Spacing.standard
            ) {
                    if hits.isEmpty {
                        Text("No matching rules")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(rows) { rule in
                                ruleRow(
                                    rule,
                                    verticalInset: ClashTheme.Spacing.compact
                                )
                                if rule.id != rows.last?.id {
                                    Divider()
                                }
                            }
                            if hitCount > rows.count {
                                Text(clash: .verbatim(ClashRulesCountCopy.moreMatches(hitCount - rows.count, locale: locale)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(
                                        .top,
                                        ClashTheme.Spacing.row
                                    )
                            }
                        }
                    }
            }
        }
    }

     
     
     
     
     
    @ViewBuilder
    private func bucketLink(_ bucket: ClashRuleBucketSnapshot) -> some View {
        if hostedInRootPool, let pushRoute {
             
             
             
             
             
             
            Button {
                let token = UUID()
                let bucket = bucket
                ClashViewRouteRegistry.set(token, onReturn: {}) {
                    AnyView(bucketDetail(bucket))
                }
                pushRoute(ClashViewRoute(id: token))
            } label: {
                bucketRowLabel(bucket)
            }
            .modifier(ClashRuleBucketRowChrome(bucket: bucket))
        } else if #available(iOS 16.0, macOS 13.0, tvOS 16.0, *) {
            NavigationLink(
                value: ClashRuleBucketRoute(target: bucket.target)
            ) {
                bucketRowLabel(bucket)
            }
            .modifier(ClashRuleBucketRowChrome(bucket: bucket))
        } else {
            ClashRoutedViewLink {
                bucketDetail(bucket)
                    .clashPushedDetailPage()
            } label: {
                bucketRowLabel(bucket)
            }
            .modifier(ClashRuleBucketRowChrome(bucket: bucket))
        }
    }

    private func bucketRowLabel(
        _ bucket: ClashRuleBucketSnapshot
    ) -> some View {
        HStack(spacing: ClashTheme.Spacing.row) {
            Text(bucket.target)
                .font(.body.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(bucket.ruleCount)")
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
             
             
             
             
            icon(.chevronForward)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, ClashTheme.Spacing.row)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func bucketDetail(
        _ bucket: ClashRuleBucketSnapshot
    ) -> some View {
        ClashRulesBrowserHost {
            ClashRuleBucketSystemPage(
                bucket: bucket,
                jumpCard: overview.jumpableTargets.contains(bucket.target)
                    ? AnyView(bucketJumpLabel(bucket, inset: 0))
                    : nil,
                palette: palette
            )
        } legacy: {
          Group {
            if ClashPlatformLayout.pageUsesSystemSettingsIdiom {
                ClashRuleBucketLazyPage(
                    bucket: bucket,
                     
                     
                     
                    jumpCard: overview.jumpableTargets.contains(bucket.target)
                        ? AnyView(
                            ClashCardSurface(
                                fill: palette.card,
                                separator: palette.separator
                            ) {
                                bucketJumpLabel(
                                    bucket,
                                    inset: ClashTheme.Spacing.standard
                                )
                            }
                        )
                        : nil,
                    palette: palette
                )
            } else {
                bucketCardPage(bucket)
            }
          }
        }
        .clashPageTitle(.verbatim(bucket.target), watchAs: "rules-bucket")
    }

     
    private func bucketCardPage(
        _ bucket: ClashRuleBucketSnapshot
    ) -> some View {
        ClashProductRootPage(
            palette: palette,
            accessibilityIdentifier: "rules.bucket.\(bucket.target)"
        ) {
             
             
            if overview.jumpableTargets.contains(bucket.target) {
                ClashCardSurface(
                    fill: palette.card,
                    separator: palette.separator
                ) {
                    bucketJumpLabel(
                        bucket,
                        inset: ClashTheme.Spacing.standard
                    )
                }
            }
             
             
            let rows = Array(bucket.rules.prefix(200))
            ClashCardSurface(
                fill: palette.card,
                separator: palette.separator
            ) {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { rule in
                        ruleRow(
                            rule,
                            verticalInset: ClashTheme.Spacing.compact
                        )
                        if rule.id != rows.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(ClashTheme.Spacing.standard)
            }
        }
    }

     
     
     
     
    private func bucketJumpLabel(
        _ bucket: ClashRuleBucketSnapshot,
        inset: CGFloat = 0
    ) -> some View {
        Button {
            send(.openProxiesGroup(name: bucket.target))
        } label: {
            HStack(spacing: ClashTheme.Spacing.row) {
                icon(.serverRack)
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
                VStack(
                    alignment: .leading,
                    spacing: ClashTheme.Spacing.tight
                ) {
                    Text(
                        ClashCopy.format(
                            "Open %@ in Proxies",
                            locale: locale,
                            bucket.target
                        )
                    )
                    .font(.body.weight(.semibold))
                    Text("These rules send traffic there.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: ClashTheme.Spacing.compact)
                 
                icon(.chevronForward)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(inset)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("rules.jump.\(bucket.target)")
    }


     
    private var inapplicableNotice: some View {
        HStack(spacing: 4) {
            icon(.infoCircle)
                .font(.caption)
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
            Text(overview.inapplicableLine(locale: locale))
                .font(.footnote)
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("rules.inapplicable")
    }

     
     
    private func ruleSetRow(_ ruleSet: ClashRuleSetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ClashRegionalFlag.label(ruleSet.name, pointSize: 17, relativeTo: .body)
                .font(.body.weight(.semibold))
            Text(clash: .verbatim(ruleSet.subtitle(locale: locale)))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let note = ruleSet.localFileNote(locale: locale) {
                Text(clash: .verbatim(note))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("rules.rule-set.local-file.\(ruleSet.name)")
            }
            if let reason = ruleSet.blockedReason {
                 
                 
                 
                 
                Text(clash: .copy("Not in the runtime"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier(
                        "rules.rule-set.blocked.\(ruleSet.name)"
                    )
                Text(clash: .verbatim(reason))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
         
         
         
        .padding(.vertical, ClashTheme.Spacing.row)
    }

    private func ruleRow(
        _ rule: ClashRuleLineSnapshot,
        verticalInset: CGFloat
    ) -> some View {
         
         
         
         
        ClashPerf.count("rules.row.make")
        return HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.payload.isEmpty ? rule.type : rule.payload)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if ClashRuleRowLayout.showsTypeLine(payload: rule.payload) {
                    Text(clash: .verbatim(rule.typeLine(locale: locale)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
             
             
             
            Text(rule.target)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(palette.raisedFill))
        }
        .padding(.vertical, verticalInset)
    }

    private func send(_ command: ClashRulesCommand) {
        Task {
            try? await actions.perform(
                .rules(command),
                allowedBy: snapshot
            )
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashRuleBucketLazyPage: View {
    let bucket: ClashRuleBucketSnapshot
     
     
    let jumpCard: AnyView?
    let palette: ClashProductPalette

     
    static var renderedRowCap: Int { ClashRuleBucketSnapshot.pageRowCap }

    @Environment(\.locale) private var locale

    var body: some View {
        edgeFaded(scroll)
         
         
         
        .environment(\.clashPageDrawsOwnCards, true)
        .accessibilityIdentifier("rules.bucket.\(bucket.target)")
    }

     
     
     
     
     
     
    private func edgeFaded(_ scroll: some View) -> AnyView {
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, *) {
            return AnyView(scroll.scrollEdgeEffectStyle(.soft, for: .top))
        }
        return AnyView(scroll)
    }

    private var scroll: some View {
        let rows = Array(bucket.rules.prefix(Self.renderedRowCap))
        let lastIndex = rows.count - 1
        return ScrollView {
            LazyVStack(spacing: 0) {
                if let jumpCard {
                    jumpCard
                        .padding(.bottom, ClashTheme.Spacing.section)
                }
                ClashSectionCaption(
                     
                     
                     
                    .verbatim(ClashRulesCountCopy.rules(bucket.ruleCount, locale: locale))
                )
                 
                 
                 
                .padding(.bottom, ClashTheme.Spacing.cardGap)
                ForEach(
                    Array(rows.enumerated()),
                    id: \.offset
                ) { index, rule in
                    ruleRow(rule)
                        .padding(.horizontal, ClashTheme.Spacing.standard)
                        .padding(
                            .top,
                            index == 0 ? ClashTheme.Spacing.standard : 0
                        )
                        .padding(
                            .bottom,
                            index == lastIndex
                                ? ClashTheme.Spacing.standard
                                : 0
                        )
                        .background(
                            rowCardSlice(index: index, lastIndex: lastIndex)
                        )
                        .overlay(alignment: .bottom) {
                            if index != lastIndex {
                                Divider()
                                    .padding(
                                        .horizontal,
                                        ClashTheme.Spacing.standard
                                    )
                            }
                        }
                }
                if bucket.ruleCount > rows.count {
                    Text(clash: .verbatim(ClashRulesCountCopy.moreRules(bucket.ruleCount - rows.count, locale: locale)))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, ClashTheme.Spacing.row)
                }
            }
            .padding(.vertical, ClashTheme.Spacing.section)
             
             
             
             
             
             
             
             
            .padding(.horizontal, ClashTheme.Spacing.standard)
        }
    }

     
    @ViewBuilder
    private func rowCardSlice(index: Int, lastIndex: Int) -> some View {
        if #available(iOS 16.4, macOS 13.3, tvOS 16.4, *) {
            UnevenRoundedRectangle(
                topLeadingRadius:
                    index == 0 ? ClashTheme.Radius.card : 0,
                bottomLeadingRadius:
                    index == lastIndex ? ClashTheme.Radius.card : 0,
                bottomTrailingRadius:
                    index == lastIndex ? ClashTheme.Radius.card : 0,
                topTrailingRadius:
                    index == 0 ? ClashTheme.Radius.card : 0,
                style: .continuous
            )
            .fill(palette.card)
        } else {
             
             
             
            Rectangle().fill(palette.card)
        }
    }

     
     
     
     
    private func ruleRow(_ rule: ClashRuleLineSnapshot) -> some View {
         
         
        ClashPerf.count("rules.row.make")
        return HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.payload.isEmpty ? rule.type : rule.payload)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if ClashRuleRowLayout.showsTypeLine(payload: rule.payload) {
                    Text(clash: .verbatim(rule.typeLine(locale: locale)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text(rule.target)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(palette.raisedFill))
        }
        .padding(.vertical, ClashTheme.Spacing.compact)
    }
}

 
 
 
 
 
 
 
 
 
 
public typealias ClashRuleGeoValueLoader = @MainActor (
    ClashRuleGeoResource
) async -> [String]

public struct ClashProfileRulesView<Icon: View, Trailing: View>: View {
    public typealias GeoValueLoader = ClashRuleGeoValueLoader
    public typealias PolicyOptionsLoader = @MainActor () async
        -> ClashRulePolicyOptions

    private let snapshot: AppleClientSnapshot
    private let actions: AppleClientActions
    private let presentationClass: ClashPresentationClass
    private let runtimeProfile: ClashAppleRuntimeProfile
    private let palette: ClashProductPalette
    private let showsDismissControl: Bool
    private let loadPolicyOptions: PolicyOptionsLoader?
    private let loadGeoValues: GeoValueLoader
    private let icon: (ClashSymbol) -> Icon
     
     
     
     
     
     
     
     
     
     
    private let trailing: Trailing

     
     
     
     
     
     
     
     
    @StateObject private var dismiss = ClashDismissHandle()
    @Environment(\.clashInsideProductModalPresentation)
    private var insideProductModal
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
     
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale
    @State private var draft: ClashProfileRulesDraft
     
     
     
     
     
     
     
    @State private var openedWith: ClashProfileRulesDraft
    @State private var editingRule: ClashRuleEditTarget?
    @State private var pendingRule: ClashRuleEditTarget?
    @State private var loadedPolicyOptions: ClashRulePolicyOptions?
    @State private var isLoadingPolicyOptions = false
    @State private var showsRuleOrder = false
    @State private var isSaving = false
     
    @State private var draftRows = ClashIdentifiedRows()
    @State private var error = ""
    @State private var didOpenInitialRule = false
     
     
    @State private var draftSlot: ClashDraftSlot<ClashProfileRulesDraft>
    @State private var showsRestoredDraft: Bool
     
    private let draftStore: (any ClashUnsavedDraftStore)?
    private let draftKey: String?
     
     
     
    private let loadRuleSets: PolicyOptionsLoader?
    @State private var arrivalRuleSets: ClashRulePolicyOptions?

    public init(
        snapshot: AppleClientSnapshot,
        actions: AppleClientActions,
        presentationClass: ClashPresentationClass,
        runtimeProfile: ClashAppleRuntimeProfile,
        palette: ClashProductPalette,
        showsDismissControl: Bool = true,
        loadPolicyOptions: PolicyOptionsLoader? = nil,
        loadRuleSets: PolicyOptionsLoader? = nil,
        draftStore: (any ClashUnsavedDraftStore)? = nil,
        draftKey: String? = nil,
        loadGeoValues: @escaping GeoValueLoader,
        @ViewBuilder icon: @escaping (ClashSymbol) -> Icon,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.snapshot = snapshot
        self.actions = actions
        self.presentationClass = presentationClass
        self.runtimeProfile = runtimeProfile
        self.palette = palette
        self.showsDismissControl = showsDismissControl
        self.loadPolicyOptions = loadPolicyOptions
        self.loadRuleSets = loadRuleSets
        self.loadGeoValues = loadGeoValues
        self.icon = icon
        self.trailing = trailing()
        let editor = snapshot.rules.editor
        let initialPolicyOptions = editor?.policyOptions ?? .empty
        _loadedPolicyOptions = State(
            initialValue:
                loadPolicyOptions == nil || initialPolicyOptions != .empty
                    ? initialPolicyOptions
                    : nil
        )
        let openingDraft = ClashProfileRulesDraft(
            rules: editor?.rules ?? [],
            prependRules: editor?.prependRules
                ?? ClashProfileRulesSnapshot.prependsByDefault
        )
        self.draftStore = draftStore
        self.draftKey = draftKey
        let slot = ClashDraftSlot(key: draftKey ?? "", original: openingDraft,
                                  store: draftKey == nil ? nil : draftStore)
        _draftSlot = State(initialValue: slot)
        let opening = slot.opening()
        _openedWith = State(initialValue: openingDraft)
        _draft = State(initialValue: opening.value)
        _showsRestoredDraft = State(initialValue: opening.needsNotice)
    }

}

public extension ClashProfileRulesView where Trailing == EmptyView {
     
     
     
    init(
        snapshot: AppleClientSnapshot,
        actions: AppleClientActions,
        presentationClass: ClashPresentationClass,
        runtimeProfile: ClashAppleRuntimeProfile,
        palette: ClashProductPalette,
        showsDismissControl: Bool = true,
        loadGeoValues: @escaping GeoValueLoader,
        @ViewBuilder icon: @escaping (ClashSymbol) -> Icon
    ) {
        self.init(
            snapshot: snapshot, actions: actions,
            presentationClass: presentationClass, runtimeProfile: runtimeProfile,
            palette: palette, showsDismissControl: showsDismissControl,
            loadGeoValues: loadGeoValues, icon: icon, trailing: { EmptyView() }
        )
    }
}

extension ClashProfileRulesView {
    public var body: some View {
        ClashProductRootPage(
            palette: palette,
            accessibilityIdentifier: "profile-rules.product.root"
        ) {
            if showsRestoredDraft {
                HStack(spacing: ClashTheme.Spacing.compact) {
                    statusMessage("Unsaved edits from last time were restored.", symbol: .infoCircle, color: .secondary)
                        .accessibilityIdentifier("profile-rules.restored")
                    Button("Discard", role: .destructive) { discardRestoredDraft() }
                        .buttonStyle(.borderless)
                        .font(.subheadline)
                        .padding(.trailing, ClashTheme.Spacing.standard)
                        .accessibilityIdentifier("profile-rules.restored.discard")
                }
            }
            profileSummary
            personalRules
            priority
            saveBehavior
            trailing
            if !error.isEmpty {
                statusMessage(
                    error,
                    symbol: .exclamationmarkTriangle,
                    color: .red
                )
            }
        }
        .clashPageTitle("Routing Rules")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if showsDismissControl && !insideProductModal {
                    Button {
                        dismissPresentation()
                    } label: {
                        if dynamicTypeSize.isAccessibilitySize {
                            icon(.xmark)
                        } else {
                            Text("Cancel")
                        }
                    }
                    .accessibilityLabel("Cancel")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if !insideProductModal {
                    Button {
                        persist()
                    } label: {
                        ClashActionProgressLabel(.copy("Save"), isBusy: isSaving)
                    }
                    .disabled(isSaving)
                    .accessibilityLabel("Save")
                    .accessibilityIdentifier("profile-rules.save")
                }
            }
        }
         
         
         
         
         
        .clashRegistersDeparture(
            isDirty: draft != openedWith,
            isBusy: isSaving,
            save: { completion in
                persist(then: completion)
            },
            discard: { draft = openedWith; draftSlot.clear() }
        )
        .onChange(of: draft) { draftSlot.record($0) }
         
         
         
        .task {
            guard let loadRuleSets, draft.rules.contains(where: { !ClashStructuredRule.ruleSetNames(in: $0.raw).isEmpty })
            else { return }
            arrivalRuleSets = await loadRuleSets()
        }
        .clashProductModalRoot(title: "Routing Rules")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if insideProductModal {
                ClashModalActionBar(
                    primaryTitle: "Save",
                    primaryDisabled: isSaving,
                    onPrimary: { persist() }
                )
            }
        }
        .clashProductModal(item: $editingRule, role: .form) { target in
            ClashRuleBuilderView(
                rule: target.rule,
                options: loadedPolicyOptions ?? editor.policyOptions,
                 
                 
                delete: target.rowID.map { id in { draftRows.remove(id, from: &draft.rules) } },
                initialRoute: target.initialRoute,
                runtimeProfile: runtimeProfile,
                palette: palette,
                draftStore: draftKey == nil ? nil : draftStore,
                draftKey: draftKey.map {
                    ClashRuleBuilderDraft.key(scope: $0, raw: target.rule.raw,
                                              index: target.rowID.flatMap(draftRows.index(of:)),
                                              in: draft.rules.map(\.raw))
                },
                loadGeoValues: loadGeoValues,
                icon: icon
            ) { updated in
                apply(updated, rowID: target.rowID)
            }
            .clashModalPresentation(.page)
        }
        .clashProductModal(isPresented: $showsRuleOrder, role: .form) {
            ClashProfileRuleOrderView(
                rules: $draft.rules,
                palette: palette,
                icon: icon
            )
            .clashModalPresentation(.form)
        }
        .onAppear {
            guard !didOpenInitialRule,
                let raw = editor.initialRuleBuilderRaw
            else {
                return
            }
            didOpenInitialRule = true
            openRuleEditor(ClashRuleEditTarget(
                rowID: nil,
                rule: ClashPersonalRuleSnapshot(raw: raw),
                initialRoute: editor.initialRuleBuilderRoute
            ))
        }
        .accessibilityIdentifier("profile-rules.screen")
        .clashCapturesDismiss(dismiss)
    }

    private var editor: ClashProfileRulesSnapshot {
        snapshot.rules.editor
            ?? ClashProfileRulesSnapshot(profileName: "Profile")
    }

    private var profileSummary: some View {
        ClashCardSurface(
            fill: palette.card,
            separator: palette.separator
        ) {
            ClashProfileContextHeader(
                profileName: editor.profileName,
                message:
                    "These exceptions belong to this profile. Its imported source stays unchanged."
            ) {
                icon(.profileClipboard)
            }
             
             
             
             
            .padding(.horizontal, ClashTheme.Spacing.standard)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private var personalRules: some View {
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        if ClashPlatformLayout.pageUsesSystemSettingsIdiom {
            groupedPersonalRules
        } else {
            handBuiltPersonalRules
        }
    }

    @ViewBuilder
    private var groupedPersonalRules: some View {
        if draft.rules.isEmpty {
            Section {
                ClashCardEmptyState(
                    title: "No Personal Rules",
                    message: "The profile's own rules remain in effect. Add only the exception you need."
                ) {
                    icon(.listBulletRectangle)
                }
                .padding(.vertical, 10)
                .accessibilityIdentifier("profile-rules.empty")
            } header: {
                personalRulesHeader
            }
            Section {
                addRuleRow
            } footer: {
                personalRulesFootnote
            }
        } else {
            Section {
                rulesRows
                addRuleRow
            } header: {
                personalRulesHeader
            } footer: {
                personalRulesFootnote
            }
        }
    }

    private var personalRulesFootnote: some View {
        Text(
            ClashPlatformLayout.pageUsesSystemSettingsIdiom
                ? "Click a rule to edit it. Use Reorder to change match priority."
                : "Tap to edit. Use Reorder to change match priority."
        )
    }

     
     
     
     
    private var personalRulesHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("PERSONAL RULES")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if draft.rules.count >= 2 {
                Button {
                    showsRuleOrder = true
                } label: {
                    Label {
                        Text("Reorder")
                    } icon: {
                        icon(.arrowUpArrowDown)
                    }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .frame(
                    minWidth: ClashTheme.Control.minimumHitTarget,
                    minHeight: ClashTheme.Control.minimumHitTarget
                )
                .contentShape(Rectangle())
                .accessibilityIdentifier("profile-rules.reorder")
            } else {
                Text("Checked top to bottom")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var handBuiltPersonalRules: some View {
        VStack(
            alignment: .leading,
            spacing: ClashTheme.Spacing.cardGap
        ) {
            personalRulesHeader
                .padding(.horizontal, ClashTheme.Spacing.compact)

            if ClashPlatformLayout.collectionLeadsWithEmptyState {
                 
                 
                 
                 
                if draft.rules.isEmpty {
                    rulesCard
                     
                     
                     
                     
                     
                     
                     
                    if ClashPlatformLayout.pageUsesSystemSettingsIdiom {
                         
                         
                         
                         
                        Color.clear
                            .frame(height: ClashTheme.Spacing.section)
                    }
                    addRuleCard
                } else {
                    ClashCardSurface(
                        fill: palette.card,
                        separator: palette.separator
                    ) {
                        VStack(spacing: 0) {
                            rulesRows
                            Divider()
                                .padding(.leading, 62)
                            addRuleRow
                        }
                    }
                }
            } else {
                addRuleCard
                rulesCard
            }

            Text(
                ClashPlatformLayout.pageUsesSystemSettingsIdiom
                    ? "Click a rule to edit it. Use Reorder to change match priority."
                    : "Tap to edit. Use Reorder to change match priority."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, ClashTheme.Spacing.compact)
        }
    }


     
     
     
     
     
     
     
     
    private var addRuleRow: some View {
        ClashAddRow(
            Text("Add Rule"),
            context: .standaloneCard,
            action: {
                openRuleEditor(ClashRuleEditTarget(
                    rowID: nil,
                    rule: ClashPersonalRuleSnapshot(raw: ""),
                    initialRoute: nil
                ))
            }
        ) {
            HStack(spacing: ClashTheme.Spacing.row) {
                icon(.plusCircleFill)
                    .font(.title3)
                    .foregroundStyle(.tint)
                Text("Add Rule")
                    .foregroundStyle(.tint)
                Spacer(minLength: 0)
            }
            .padding(ClashTheme.Spacing.standard)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("profile-rules.add")
    }

    private var addRuleCard: some View {
        ClashCardSurface(
            fill: palette.card,
            separator: palette.separator
        ) {
            addRuleRow
        }
    }

    private var rulesCard: some View {
        ClashCardSurface(
            fill: palette.card,
            separator: palette.separator
        ) {
            VStack(spacing: 0) {
                if draft.rules.isEmpty {
                    ClashCardEmptyState(
                        title: "No Personal Rules",
                        message: "The profile's own rules remain in effect. Add only the exception you need."
                    ) {
                        icon(.listBulletRectangle)
                    }
                     
                     
                     
                    .padding(.vertical, 10)
                    .accessibilityIdentifier(
                        "profile-rules.empty"
                    )
                } else {
                    rulesRows
                }
            }
        }
    }

     
     
     
     
    @ViewBuilder
    private var rulesRows: some View {
        ForEach(draftRows.current(for: draft.rules)) { row in
            let index = row.index
            let rule = draftRows.index(of: row.id).map { draft.rules[$0] }
                ?? ClashPersonalRuleSnapshot(raw: "")
            Button {
                openRuleEditor(ClashRuleEditTarget(
                    rowID: row.id,
                    rule: rule,
                    initialRoute: nil
                ))
            } label: {
                personalRuleRow(
                    rule,
                    index: index
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(
                "profile-rules.rule.\(index)"
            )
            .contextMenu {
                Button {
                    if let index = draftRows.index(of: row.id) {
                        toggleRule(at: index)
                    }
                } label: {
                    Label(
                        rule.isEnabled
                            ? "Disable"
                            : "Enable",
                        systemImage:
                            rule.isEnabled
                                ? "minus.circle"
                                : "checkmark"
                    )
                }
                .accessibilityIdentifier(
                    "profile-rules.rule.\(index).\(rule.isEnabled ? "disable" : "enable")"
                )
                Button(role: .destructive) {
                    draftRows.remove(row.id, from: &draft.rules)
                } label: {
                    Label(
                        "Delete",
                        systemImage: "trash"
                    )
                }
                .accessibilityIdentifier(
                    "profile-rules.rule.\(index).delete"
                )
            }

            if index < draft.rules.count - 1 {
                Divider()
                    .padding(.leading, 62)
            }
        }
        .onAppear { draftRows.resync(count: draft.rules.count) }
        .onChange(of: draft.rules.count) { draftRows.resync(count: $0) }
    }

    private var priority: some View {
         
         
         
         
        ClashProductGroup(
            "PRIORITY",
            footer: priorityFootnote,
            palette: palette,
            touchSpacing: ClashTheme.Spacing.cardGap
        ) {
            ClashSettingsToggleRow(
                Text("Apply before profile rules"),
                isOn: $draft.prependRules
            )
             
             
             
            .padding(.horizontal, ClashTheme.Spacing.standard)
            .frame(
                minHeight: ClashPlatformLayout.pageUsesSystemSettingsIdiom
                    ? nil
                    : ClashTheme.Control
                        .fullWidthRowMinHeightOnItsOwnPlatform
            )
            .accessibilityIdentifier("profile-rules.prepend")
        }
    }

    private var priorityFootnote: ClashDisplayText {
        .formatCopy("%@\n%@", [
            draft.prependRules
                ? "Personal rules are checked first for deliberate exceptions."
                : "Personal rules are checked after the rules supplied by this profile.",
            ClashProfileRulesCopy.everyProfileHint,
        ])
    }

    private var saveBehavior: some View {
        ClashCardSurface(
            fill: palette.card,
            separator: palette.separator
        ) {
            statusMessage(
                "Saving rebuilds the current profile automatically. If VPN is off, it stays off until the next connection.",
                symbol: .checkmarkShieldFill,
                color: .green
            )
        }
    }

    private func personalRuleRow(
        _ rule: ClashPersonalRuleSnapshot,
        index: Int
    ) -> some View {
        let parsed = ClashStructuredRule.parse(rule.raw)
         
         
        let words = ConfigurationRuleWords.of(rule.raw, locale: locale, copy: fieldCopy)
        let invalidTarget = parsed.map {
            policyOptionsForValidation?.flagsUnknownTarget(of: $0) ?? false
        } ?? false
         
         
         
        let ruleSetNotInEffect = rule.isEnabled
            ? (policyOptionsForValidation ?? arrivalRuleSets)?.ruleSetNotInEffect(rule.raw) : nil

        return HStack(
            alignment: .center,
            spacing: ClashTheme.Spacing.row
        ) {
            VStack(
                alignment: .leading,
                spacing: ClashTheme.Spacing.tight
            ) {
                Text(verbatim: words.match)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !words.kind.isEmpty {
                    Text(verbatim: words.kind)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let comment = rule.comment, !comment.isEmpty {
                    Text(comment)
                        .font(.caption.italic())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityIdentifier(
                            "profile-rules.rule.\(index).comment"
                        )
                }
                if invalidTarget {
                    Text("Target not in this profile")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier(
                            "profile-rules.rule.\(index).invalid-target"
                        )
                }
                if let ruleSetNotInEffect {
                    Text(clash: ruleSetNotInEffect)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier(
                            "profile-rules.rule.\(index).missing-rule-set"
                        )
                }
            }
            Spacer(minLength: 0)
            if let target = words.target, !target.isEmpty {
                Text(verbatim: target)
                    .foregroundStyle(
                        invalidTarget
                            ? AnyShapeStyle(Color.red)
                            : AnyShapeStyle(Color.secondary)
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if !rule.isEnabled {
                Text("Off")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(palette.raisedFill)
                    )
                    .accessibilityIdentifier(
                        "profile-rules.rule.\(index).off"
                    )
            }
            if !ClashPlatformLayout.pageUsesSystemSettingsIdiom {
                 
                 
                 
                 
                icon(.chevronForward)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHint(Text(verbatim: fieldCopy.rulePhrase("opens", language: .init(locale: locale)) ?? ""))
            }
        }
         
         
         
         
         
         
        .padding(.horizontal, ClashTheme.Spacing.standard)
        .padding(
            .vertical,
            ClashMacSettingsMetrics.rowVerticalInset(
                touch: ClashTheme.Spacing.row
            )
        )
        .frame(
            minHeight: ClashPlatformLayout.pageUsesSystemSettingsIdiom
                ? nil
                : 60
        )
        .contentShape(Rectangle())
        .opacity(rule.isEnabled ? 1 : 0.5)
    }

    private func statusMessage(
        _ text: String,
        symbol: ClashSymbol,
        color: Color
    ) -> some View {
        HStack(
            alignment: .top,
            spacing: ClashTheme.Spacing.compact
        ) {
            icon(symbol)
                .foregroundStyle(color)
            Text(clash: .copy(text))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
         
         
         
         
         
         
        .padding(.horizontal, ClashTheme.Spacing.standard)
        .padding(.vertical, ClashTheme.Spacing.compact)
    }

    private func apply(
        _ updated: ClashPersonalRuleSnapshot,
        rowID: UUID?
    ) {
        if let rowID {
            draftRows.update(rowID, in: &draft.rules, to: updated)
        } else if !draft.rules.contains(where: {
            $0.raw == updated.raw
        }) {
            draftRows.append(updated, to: &draft.rules)
        }
    }

    private func toggleRule(at index: Int) {
        guard draft.rules.indices.contains(index) else { return }
        let current = draft.rules[index]
        draft.rules[index] = ClashPersonalRuleSnapshot(
            raw: current.raw,
            isEnabled: !current.isEnabled,
            comment: current.comment
        )
    }

     
     
    private func persist(then: ((Bool) -> Void)? = nil) {
        guard !isSaving else { then?(false); return }
        isSaving = true
        error = ""
        Task {
            do {
                try await actions.perform(
                    .rules(.saveProfileRules(draft)),
                    allowedBy: snapshot
                )
                draftSlot.commit()
                if let then { then(true) } else { dismissPresentation() }
            } catch {
                then?(false)
                self.error =
                    "Rules could not be saved. The previous configuration is still available."
            }
            isSaving = false
        }
    }

     
     
     
     
     
    private func openRuleEditor(_ target: ClashRuleEditTarget) {
        if loadedPolicyOptions != nil {
            pendingRule = nil
            editingRule = target
            return
        }
        guard loadPolicyOptions != nil else {
            loadedPolicyOptions = editor.policyOptions
            pendingRule = nil
            editingRule = target
            return
        }
        pendingRule = target
        readDeferredPolicyOptions()
    }

     
     
    private func readDeferredPolicyOptions() {
        guard loadedPolicyOptions == nil, !isLoadingPolicyOptions, let loadPolicyOptions else { return }
        isLoadingPolicyOptions = true
        Task { @MainActor in
            let options = await loadPolicyOptions()
            if loadedPolicyOptions == nil { loadedPolicyOptions = options }
            isLoadingPolicyOptions = false
             
            if let requested = pendingRule {
                pendingRule = nil
                editingRule = requested
            }
        }
    }

     
     
     
    private var policyOptionsForValidation: ClashRulePolicyOptions? {
        if let loadedPolicyOptions {
            return loadedPolicyOptions
        }
        return loadPolicyOptions == nil ? editor.policyOptions : nil
    }

    private func dismissPresentation() {
        dismiss.closeModalOrDismiss()
    }

    private func discardRestoredDraft() {
        draft = openedWith
        draftSlot.clear()
        showsRestoredDraft = false
    }
}

private struct ClashRuleEditTarget: Identifiable {
    let id = UUID()
     
     
    let rowID: UUID?
    let rule: ClashPersonalRuleSnapshot
    let initialRoute: ClashRuleBuilderRoute?
}

private struct ClashProfileRuleOrderView<Icon: View>: View {
    @Binding var rules: [ClashPersonalRuleSnapshot]
    let palette: ClashProductPalette
    let icon: (ClashSymbol) -> Icon

     
     
     
     
     
    @StateObject private var dismiss = ClashDismissHandle()
     
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale
     
     
     
     
    @State private var rows = ClashIdentifiedRows()

    var body: some View {
        ClashSingleColumnNavigationContainer {
            List {
                ForEach(rows.current(for: rules)) { row in
                    let index = row.index
                    let rule = rows.index(of: row.id).map { rules[$0] }
                        ?? ClashPersonalRuleSnapshot(raw: "")
                    let words = ConfigurationRuleWords.of(rule.raw, locale: locale, copy: fieldCopy)
                    HStack(spacing: ClashTheme.Spacing.row) {
                         
                         
                        ConfigurationRuleRow(rule.raw, showsChevron: false)
                        Spacer(minLength: 8)
                        Button {
                            guard let now = rows.index(of: row.id),
                                  now > 0 else { return }
                            rows.swapAt(now, now - 1, in: &rules)
                        } label: {
                            icon(.arrowUp)
                        }
                        .buttonStyle(.borderless)
                        .frame(
                            width: ClashTheme.Control.minimumHitTarget,
                            height: ClashTheme.Control.minimumHitTarget
                        )
                        .contentShape(Rectangle())
                        .disabled(index == 0)
                        .accessibilityLabel("Move rule up")
                        .accessibilityIdentifier(
                            "profile-rules.order.\(index).move-up"
                        )
                        Button {
                            guard let now = rows.index(of: row.id),
                                  now + 1 < rules.count else {
                                return
                            }
                            rows.swapAt(now, now + 1, in: &rules)
                        } label: {
                            icon(.arrowDown)
                        }
                        .buttonStyle(.borderless)
                        .frame(
                            width: ClashTheme.Control.minimumHitTarget,
                            height: ClashTheme.Control.minimumHitTarget
                        )
                        .contentShape(Rectangle())
                        .disabled(index + 1 == rules.count)
                        .accessibilityLabel("Move rule down")
                        .accessibilityIdentifier(
                            "profile-rules.order.\(index).move-down"
                        )
                    }
                    .tag(index)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(
                        "profile-rules.order.\(index)"
                    )
                    .accessibilityLabel(Text(verbatim: "\(words.match), \(words.kind)"))
                }
                .onAppear { rows.resync(count: rules.count) }
                .onChange(of: rules.count) { rows.resync(count: $0) }
            }
            .clashPageTitle("Rule Priority")
            .clashToolbarUnlessInPanel {
                ToolbarItem(placement: .cancellationAction) {
                    ClashSheetCloseButton {
                        dismiss()
                    }
                }
            }
            .clashProductModalRoot(title: "Rule Priority")
        }
         
         
         
         
         
        .clashRegistersDeparture(isDirty: false, save: { $0(true) }, discard: {})
        .clashCapturesDismiss(dismiss)
    }
}

private extension String {
    var nonempty: String? {
        isEmpty ? nil : self
    }
}

 
 
 
public struct ClashRuleEditorView<Icon: View>: View {
    private let delete: (() -> Void)?
    private let showsPersonalMetadata: Bool
     
     
     
    private let showsTarget: Bool
    private let rule: ClashPersonalRuleSnapshot
    private let options: ClashRulePolicyOptions
     
     
    private let createGroup: ((@escaping (String?) -> Void) -> AnyView)?
    private let initialRoute: ClashRuleBuilderRoute?
    private let runtimeProfile: ClashAppleRuntimeProfile
    private let palette: ClashProductPalette
    private let loadGeoValues:
        ClashRuleGeoValueLoader
    private let icon: (ClashSymbol) -> Icon
    private let save: (ClashPersonalRuleSnapshot) -> Void
    private let draftStore: (any ClashUnsavedDraftStore)?
    private let draftKey: String?

     
     
     
    public init(
        rule: ClashPersonalRuleSnapshot,
        options: ClashRulePolicyOptions = .empty,
        showsPersonalMetadata: Bool = true,
        showsTarget: Bool = true,
        createGroup: ((@escaping (String?) -> Void) -> AnyView)? = nil,
        delete: (() -> Void)? = nil,
        initialRoute: ClashRuleBuilderRoute? = nil,
        pageTitle: String = "Rule",
        runtimeProfile: ClashAppleRuntimeProfile,
        palette: ClashProductPalette,
        draftStore: (any ClashUnsavedDraftStore)? = nil,
        draftKey: String? = nil,
        loadGeoValues: @escaping
            ClashRuleGeoValueLoader,
        @ViewBuilder icon: @escaping (ClashSymbol) -> Icon,
        save: @escaping (ClashPersonalRuleSnapshot) -> Void
    ) {
        self.draftStore = draftStore
        self.draftKey = draftKey
        self.delete = delete
        self.showsPersonalMetadata = showsPersonalMetadata
        self.showsTarget = showsTarget
        self.createGroup = createGroup
        self.rule = rule
        self.options = options
        self.initialRoute = initialRoute
        self.pageTitle = pageTitle
        self.runtimeProfile = runtimeProfile
        self.palette = palette
        self.loadGeoValues = loadGeoValues
        self.icon = icon
        self.save = save
    }
     
     
     
    private let pageTitle: String

    public var body: some View {
        ClashRuleBuilderView(
            rule: rule,
            options: options,
            showsPersonalMetadata: showsPersonalMetadata,
            showsTarget: showsTarget,
            createGroup: createGroup,
            delete: delete,
            initialRoute: initialRoute,
            pageTitle: pageTitle,
            runtimeProfile: runtimeProfile,
            palette: palette,
            draftStore: draftStore,
            draftKey: draftKey,
            loadGeoValues: loadGeoValues,
            icon: icon,
            save: save
        )
    }
}

 
 
public struct ClashRuleBuilderDraft: Codable, Equatable {
    var action: ClashStructuredRule.Action
    var content: String
    var target: String
    var noResolve: Bool
    var src: Bool
    var rawMode: Bool
    var rawText: String
    var enabled: Bool
    var comment: String
    var logicConditions: [ClashLogicCondition]?
    var additionalParams: [String]

     
     
     
     
     
     
     
    public static func key(scope: String, raw: String, index: Int?, in rows: [String]) -> String {
        guard !raw.isEmpty || index != nil else { return "Rule|\(scope)|new" }
         
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in rows.joined(separator: "\n").utf8 + [UInt8(truncatingIfNeeded: rows.count)] {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        let list = String(hash, radix: 16)
        return "Rule|\(scope)|" + (index.map { "\($0)|" } ?? "") + "list:\(list)|raw:\(raw)"
    }
}

private struct ClashRuleBuilderView<Icon: View>: View {
    let delete: (() -> Void)?
    let showsPersonalMetadata: Bool
    let showsTarget: Bool
    let createGroup: ((@escaping (String?) -> Void) -> AnyView)?
    let pageTitle: String
    let options: ClashRulePolicyOptions
    let initialRoute: ClashRuleBuilderRoute?
    let runtimeProfile: ClashAppleRuntimeProfile
    let palette: ClashProductPalette
    let loadGeoValues:
        ClashRuleGeoValueLoader
    let icon: (ClashSymbol) -> Icon
    let save: (ClashPersonalRuleSnapshot) -> Void

    @Environment(\.clashInsideProductModalPresentation)
    private var insideProductModal
     
     
     
     
     
     
     
     
     
    @StateObject private var dismiss = ClashDismissHandle()
     
     
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

    @State private var action: ClashStructuredRule.Action
     
     
    private let openedAction: ClashStructuredRule.Action?
    @State private var content: String
    @State private var target: String
    @State private var noResolve: Bool
    @State private var src: Bool
    @State private var rawMode: Bool
    @State private var rawText: String
    @State private var enabled: Bool
    @State private var comment: String
    @State private var logicConditions: [ClashLogicCondition]?
    @State private var newCondition = ClashLogicCondition(
        action: .network,
        content: "tcp"
    )
    @State private var addingCondition = false
     
     
     
    @State private var error: ClashDisplayText?
     
     
     
    @State private var additionalParams: [String]
    @State private var lastAction: ClashStructuredRule.Action
    @State private var autoRoute: ClashRuleBuilderRoute?
    @FocusState private var contentFieldFocused: Bool
    @FocusState private var targetFieldFocused: Bool
    @FocusState private var rawFieldFocused: Bool
     
     
    @State private var draftSlot: ClashDraftSlot<ClashRuleBuilderDraft>
    @State private var showsRestoredDraft: Bool
     
     
    @State private var restoringDraft = false

    init(
        rule: ClashPersonalRuleSnapshot,
        options: ClashRulePolicyOptions,
        showsPersonalMetadata: Bool = true,
        showsTarget: Bool = true,
        createGroup: ((@escaping (String?) -> Void) -> AnyView)? = nil,
        delete: (() -> Void)? = nil,
        initialRoute: ClashRuleBuilderRoute?,
        pageTitle: String = "Rule",
        runtimeProfile: ClashAppleRuntimeProfile,
        palette: ClashProductPalette,
        draftStore: (any ClashUnsavedDraftStore)? = nil,
        draftKey: String? = nil,
        loadGeoValues: @escaping
            ClashRuleGeoValueLoader,
        icon: @escaping (ClashSymbol) -> Icon,
        save: @escaping (ClashPersonalRuleSnapshot) -> Void
    ) {
        self.delete = delete
        self.showsPersonalMetadata = showsPersonalMetadata
        self.showsTarget = showsTarget
        self.createGroup = createGroup
        self.pageTitle = pageTitle
        self.options = options
        self.initialRoute = initialRoute
        self.runtimeProfile = runtimeProfile
        self.palette = palette
        self.loadGeoValues = loadGeoValues
        self.icon = icon
        self.save = save
         
         
         
        let parsed = showsTarget ? ClashStructuredRule.parse(rule.raw) : ClashStructuredRule.parsePayload(rule.raw)
        let initialAction = parsed?.action ?? .domainSuffix
        let logicConditions: [ClashLogicCondition]? = Self.isLogic(initialAction)
            ? ((parsed?.content.isEmpty ?? true)
                ? []
                : ClashLogicExpressionCodec.parse(action: initialAction, content: parsed?.content ?? ""))
            : nil
        let opened = ClashRuleBuilderDraft(
            action: initialAction,
            content: parsed?.content ?? "",
            target: parsed?.target ?? options.pickableGroups.first?.name ?? "DIRECT",
            noResolve: parsed?.noResolve ?? false,
            src: parsed?.src ?? false,
             
             
             
            rawMode: !rule.raw.isEmpty
                && (parsed == nil || !ClashStructuredRule.builderWritesBack(rule.raw, hasTarget: showsTarget)),
            rawText: rule.raw,
            enabled: rule.isEnabled,
            comment: rule.comment ?? "",
            logicConditions: logicConditions,
            additionalParams: parsed?.additionalParams ?? []
        )
         
         
        var basis = opened
        basis.target = parsed?.target ?? ""
        let slot = ClashDraftSlot(key: draftKey ?? "", original: opened,
                                  store: draftKey == nil ? nil : draftStore, basis: basis)
        _draftSlot = State(initialValue: slot)
        let opening = slot.opening()
        let draft = opening.value
        _showsRestoredDraft = State(initialValue: opening.needsNotice)
        _enabled = State(initialValue: draft.enabled)
        _comment = State(initialValue: draft.comment)
        _action = State(initialValue: draft.action)
        openedAction = rule.raw.isEmpty ? nil : parsed?.action
        _content = State(initialValue: draft.content)
        _target = State(initialValue: draft.target)
        _noResolve = State(initialValue: draft.noResolve)
        _src = State(initialValue: draft.src)
         
         
        _additionalParams = State(initialValue: draft.additionalParams)
        _rawMode = State(initialValue: draft.rawMode)
        _rawText = State(initialValue: draft.rawText)
        _lastAction = State(initialValue: draft.action)
        _logicConditions = State(initialValue: draft.logicConditions)
    }

    private var currentDraft: ClashRuleBuilderDraft {
        ClashRuleBuilderDraft(action: action, content: content, target: target, noResolve: noResolve, src: src,
                              rawMode: rawMode, rawText: rawText, enabled: enabled, comment: comment,
                              logicConditions: logicConditions, additionalParams: additionalParams)
    }

     
    private func discardDraft() {
        let opened = draftSlot.original
        restoringDraft = opened.action != action
        action = opened.action
        lastAction = opened.action
        content = opened.content
        target = opened.target
        noResolve = opened.noResolve
        src = opened.src
        rawMode = opened.rawMode
        rawText = opened.rawText
        enabled = opened.enabled
        comment = opened.comment
        logicConditions = opened.logicConditions
        additionalParams = opened.additionalParams
        draftSlot.clear()
        showsRestoredDraft = false
    }

    var body: some View {
        ClashSingleColumnNavigationContainer {
            ClashModalEditorBody {
                if showsRestoredDraft {
                    Section {
                        HStack(spacing: ClashTheme.Spacing.compact) {
                            icon(.infoCircle)
                                .foregroundStyle(.secondary)
                            Text(clash: .copy("Unsaved edits from last time were restored."))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("profile-rule.restored")
                            Spacer(minLength: 0)
                            Button("Discard", role: .destructive) { discardDraft() }
                                .buttonStyle(.borderless)
                                .font(.subheadline)
                                .accessibilityIdentifier("profile-rule.restored.discard")
                        }
                    }
                }
                builderSections
                if let delete {
                    Section {
                        Button("Delete This Rule", role: .destructive) {
                            draftSlot.clear()
                            delete()
                            dismiss.closeModalOrDismiss()
                        }.accessibilityIdentifier("configuration.rule.delete-current")
                    }
                }
            }
            .onChange(of: action) { updated in
                guard !restoringDraft else {
                    restoringDraft = false
                    lastAction = updated
                    return
                }
                content = updated == .network ? "tcp" : ""
                logicConditions = Self.isLogic(updated) ? [] : nil
                if (updated == .subRule)
                    != (lastAction == .subRule)
                {
                    target = ""
                }
                noResolve = false
                src = false
                additionalParams = []
                lastAction = updated
            }
            .background(autoRouteLinks.opacity(0))
            .onAppear {
                autoRoute = initialRoute
            }
            .clashPageTitle(.copy(pageTitle))
            .clashRegistersDeparture(
            isDirty: !openedWith.isEmpty && currentFingerprint != openedWith,
            save: { completion in
                completion(submit())
            },
            discard: { draftSlot.clear() }
        )
         
        .onAppear {
            if openedWith.isEmpty {
                openedWith = showsRestoredDraft ? Self.fingerprint(draftSlot.original) : currentFingerprint
            }
        }
        .onChange(of: currentDraft) { draftSlot.record($0) }
        .clashProductModalRoot(title: "Rule")
             
             
             
             
             
             
             
            .clashModalEditorToolbar(
                confirmTitle: "Done",
                confirmationIdentifier: "profile-rule.save",
                confirmationDisabled: !saysSomething,
                onCancel: { draftSlot.clear(); dismiss() },
                onConfirm: { submit() }
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if ClashPlatformLayout.modalEditorUsesGroupedForm
                    && insideProductModal
                {
                    ClashModalActionBar(
                        primaryTitle: "Done",
                        primaryDisabled: !saysSomething,
                         
                         
                         
                        primaryHint: saysSomething
                            ? nil
                            : (rawMode
                                ? "Write the rule line to add it."
                                : "Enter what this rule matches."),
                        onPrimary: { submit() }
                    )
                }
            }
        }
        .clashCapturesDismiss(dismiss)
    }

    @ViewBuilder
    private var builderSections: some View {
        if rawMode {
            rawSections
        } else {
            structuredSections
        }
        if let error {
            Section {
                Text(clash: error)
                    .foregroundStyle(.red)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
            }
        }
    }

    @ViewBuilder
    private var rawSections: some View {
        Section {
            if showsPersonalMetadata {
            ClashSettingsToggleRow(
                Text("Enabled"),
                isOn: $enabled
            )
            .accessibilityIdentifier("profile-rule.enabled")
            }
        }
        Section {
            rawRuleField
        } header: {
            Text("Raw rule")
        } footer: {
            Text(
                "This rule is not available in the structured editor. Imported source rules are never rewritten."
            )
        }
        if showsPersonalMetadata { commentSection }
    }

    @ViewBuilder
    private var structuredSections: some View {
        Section {
            if showsPersonalMetadata {
            ClashSettingsToggleRow(
                Text("Enabled"),
                isOn: $enabled
            )
            .accessibilityIdentifier("profile-rule.enabled")
            }
            ClashRoutedViewLink {
                ClashRuleTypeSelectionView(
                    selection: $action,
                    runtimeProfile: runtimeProfile,
                     
                     
                     
                     
                     
                     
                     
                     
                     
                    excludedActions: showsTarget
                        ? options.unofferedKinds.subtracting([action] + (openedAction.map { [$0] } ?? []))
                        : ClashStructuredRule.refusedInARuleSet,
                    icon: icon
                        )
                        .clashPushedDetailPage()
                        .modifier(ClashSetterRoutedBack())
                         
                        .clashDeparturePage()
            } label: {
                HStack {
                    Text("Type")
                    Spacer()
                    Text(verbatim: ConfigurationRuleWords.kindName(action.rawValue, locale: locale, copy: fieldCopy))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: ClashTheme.Control.fullWidthRowMinHeightOnItsOwnPlatform)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("profile-rule.action")
        } header: {
            Text("Rule")
        } footer: {
            Text(clash: .copy(action.summary))
        }

        if action.needsContent {
            Section {
                valueEditor
                if let note = action.iOSInertNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                if ClashPlatformLayout.modalEditorUsesGroupedForm {
                    Text(ClashCopy.key(action.contentLabel))
                } else {
                    Text("Value")
                }
            } footer: {
                if Self.isLogic(action),
                    logicConditions != nil
                {
                    Text(clash: .copy(logicFooter))
                } else if ClashPlatformLayout.pageUsesSystemSettingsIdiom,
                          !action.contentPlaceholder.isEmpty {
                     
                     
                     
                     
                     
                     
                     
                     
                    Text(verbatim: action.contentPlaceholder)
                        .font(.caption.monospaced())
                }
            }
        }

        if showsTarget {
        Section("Target") {
            if action == .subRule {
                if ClashPlatformLayout.modalEditorUsesGroupedForm {
                    HStack {
                         
                         
                         
                        ClashValueField(
                            hint: "sub-rule name",
                            label: action.targetLabel,
                            bordered: ClashPlatformLayout
                                .pageUsesSystemSettingsIdiom,
                            text: $target
                        )
                        .font(.body.monospaced())
                        .focused($targetFieldFocused)
                        .accessibilityIdentifier(
                            "profile-rule.target"
                        )
                    }
                    .frame(maxWidth: .infinity, minHeight: ClashTheme.Control.fullWidthRowMinHeightOnItsOwnPlatform)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        targetFieldFocused = true
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(
                        "profile-rule.target.row"
                    )
                } else {
                    VStack(
                        alignment: .leading,
                        spacing: ClashTheme.Spacing.tight
                    ) {
                        Text(action.targetLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField(
                            "",
                            text: $target,
                            prompt: Text("sub-rule name")
                        )
                            .font(.body.monospaced())
                            .accessibilityIdentifier(
                                "profile-rule.target"
                            )
                    }
                }
            } else {
                ClashRoutedViewLink {
                    ClashRulePolicyPickerView(
                        options: options,
                        current: target,
                        createGroup: createGroup,
                        icon: icon
                    ) {
                        target = $0
                    }
                    .clashPushedDetailPage()
                } label: {
                     
                    enumValueRow("Target", value: target.isEmpty ? "" : ConfigurationRuleWords.targetName(
                        target, locale: locale, copy: fieldCopy))
                }
                .accessibilityIdentifier(
                    "profile-rule.target.picker"
                )
            }
        }
        }

        if action.supportsNoResolve || action.supportsSrc {
            Section("Params") {
                if action.supportsNoResolve {
                    ClashSettingsToggleRow(
                        Text("Skip DNS resolution"),
                        isOn: $noResolve
                    )
                    .accessibilityIdentifier(
                        "profile-rule.no-resolve"
                    )
                }
                if action.supportsSrc {
                    ClashSettingsToggleRow(
                        Text("Match source instead"),
                        isOn: $src
                    )
                    .accessibilityIdentifier("profile-rule.src")
                }
            }
        }

        if action.hasLimitedIOSMeaning {
            Section {
                Text(
                    "This condition only matches metadata created inside Clash's single TUN inbound. It does not identify another app or process."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }

        if showsPersonalMetadata { commentSection }

         
         
         
        if !writtenLine.isEmpty {
            Section {
                EmptyView()
            } footer: {
                Text(clash: .format("Written as %@ in the configuration file", [writtenLine]))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

     
     
    private var writtenLine: String {
        var effectiveContent = content.trimmingCharacters(in: .whitespaces)
        if Self.isLogic(action), let conditions = logicConditions {
            guard !conditions.isEmpty else { return "" }
            effectiveContent = ClashLogicExpressionCodec.serialize(action: action, conditions: conditions)
        }
        guard !action.needsContent || !effectiveContent.isEmpty else { return "" }
        let rule = ClashStructuredRule(action: action, content: effectiveContent,
                                      target: target.trimmingCharacters(in: .whitespaces),
                                      noResolve: noResolve, src: src, additionalParams: additionalParams)
        return showsTarget ? rule.rawValue : Self.payloadLine(rule)
    }

    private var commentSection: some View {
        Section {
            if ClashPlatformLayout.modalEditorUsesGroupedForm {
                ClashFieldRow(
                    "Comment",
                    hint: "Optional note, stored only on this device",
                    text: $comment
                )
                .accessibilityIdentifier("profile-rule.comment")
            } else {
                TextField(
                    "",
                    text: $comment,
                    prompt: Text(
                        "Optional note, stored only on this device"
                    )
                )
                .accessibilityIdentifier("profile-rule.comment")
            }
        } header: {
            if !ClashPlatformLayout.modalEditorUsesGroupedForm {
                Text("Comment")
            }
        } footer: {
            Text(
                "Never written into the generated configuration."
            )
        }
    }

    @ViewBuilder
    private var valueEditor: some View {
        if Self.isLogic(action) {
            logicValueContent
        } else if action == .network {
            ClashRuleNetworkMenuRow(
                selection: $content,
                identifier: "profile-rule.content"
            )
        } else if action == .geoip || action == .srcGeoIP {
            ClashRoutedViewLink {
                ClashRuleGeoValuePickerView(
                    resource: .geoIP,
                    localizeRegions: true,
                    title: "Country / Region",
                    current: content,
                    loadValues: loadGeoValues,
                    icon: icon
                ) {
                    content = $0.uppercased()
                }
                .clashPushedDetailPage()
            } label: {
                 
                enumValueRow(
                    "Country / Region",
                    value: content.isEmpty ? "" : ConfigurationRuleWords.payloadName(
                        content, kind: action.rawValue, locale: locale, copy: fieldCopy)
                )
            }
            .accessibilityIdentifier(
                "profile-rule.content.picker"
            )
        } else if action == .geosite {
            ClashRoutedViewLink {
                ClashRuleGeoValuePickerView(
                    resource: .geoSite,
                    localizeRegions: false,
                    title: "GeoSite category",
                    current: content,
                    loadValues: loadGeoValues,
                    icon: icon
                ) {
                    content = $0
                }
                .clashPushedDetailPage()
            } label: {
                enumValueRow("Category", value: content.isEmpty ? "" : ConfigurationRuleWords.payloadName(
                    content, kind: action.rawValue, locale: locale, copy: fieldCopy))
            }
            .accessibilityIdentifier(
                "profile-rule.content.picker"
            )
        } else if action == .ruleSet,
            !options.ruleSets.isEmpty
        {
            ClashRoutedViewLink {
                ClashRuleSetPickerView(
                    sets: options.ruleSets,
                    current: content,
                    icon: icon
                ) {
                    content = $0
                }
                .clashPushedDetailPage()
            } label: {
                enumValueRow("Rule Set", value: content)
            }
            .accessibilityIdentifier(
                "profile-rule.content.picker"
            )
        } else {
            VStack(
                alignment: .leading,
                spacing: ClashTheme.Spacing.tight
            ) {
                if !ClashPlatformLayout.modalEditorUsesGroupedForm {
                     
                     
                    Text(action.contentLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                structuredContentField
            }
        }
    }

    private var structuredContentField: some View {
        HStack {
             
             
             
             
             
             
             
             
             
             
             
            ClashValueField(
                hint: action.contentPlaceholder,
                label: action.contentLabel,
                bordered: ClashPlatformLayout.pageUsesSystemSettingsIdiom,
                text: $content
            )
            .font(.body.monospaced())
            .focused($contentFieldFocused)
            .accessibilityIdentifier("profile-rule.content")
        }
        .frame(maxWidth: .infinity, minHeight: ClashTheme.Control.fullWidthRowMinHeightOnItsOwnPlatform)
        .contentShape(Rectangle())
        .onTapGesture {
            contentFieldFocused = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile-rule.content.row")
    }

    private var rawRuleField: some View {
        HStack {
             
             
            ClashValueField(
                hint: "DOMAIN-SUFFIX,example.com,PROXY",
                label: "Rule",
                bordered: ClashPlatformLayout.pageUsesSystemSettingsIdiom,
                text: $rawText
            )
            .font(.body.monospaced())
            .focused($rawFieldFocused)
            .accessibilityIdentifier("profile-rule.raw")
        }
        .frame(maxWidth: .infinity, minHeight: ClashTheme.Control.fullWidthRowMinHeightOnItsOwnPlatform)
        .contentShape(Rectangle())
        .onTapGesture {
            rawFieldFocused = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile-rule.raw.row")
    }

     
     
     
    @State private var conditionRows = ClashIdentifiedRows()

    private func condition(_ id: UUID) -> ClashLogicCondition? {
        guard let conditions = logicConditions,
              let index = conditionRows.index(of: id),
              conditions.indices.contains(index) else { return nil }
        return conditions[index]
    }

    private func conditionBinding(
        _ id: UUID, fallback: ClashLogicCondition
    ) -> Binding<ClashLogicCondition> {
        Binding(
            get: { condition(id) ?? fallback },
            set: { updated in
                guard var conditions = logicConditions else { return }
                conditionRows.update(id, in: &conditions, to: updated)
                logicConditions = conditions
            }
        )
    }

    @ViewBuilder
    private var logicValueContent: some View {
        if let conditions = logicConditions {
            ForEach(conditionRows.current(for: conditions)) { row in
                let index = row.index
                let condition = self.condition(row.id)
                    ?? ClashLogicCondition(action: .network, content: "tcp")
                ClashRoutedViewLink {
                    ClashLazyView {
                        ClashRuleConditionEditorView(
                            condition: conditionBinding(
                                row.id, fallback: condition
                            ),
                            options: options,
                            runtimeProfile: runtimeProfile,
                            loadGeoValues: loadGeoValues,
                            icon: icon
                        )
                    }
                    .clashPushedDetailPage()
                } label: {
                     
                     
                    ConfigurationRuleRow(condition.raw, hasTarget: false, showsChevron: false)
                }
                .accessibilityIdentifier(
                    "profile-rule.condition.\(index)"
                )
                .contextMenu {
                    Button(role: .destructive) {
                        guard var conditions = logicConditions else { return }
                        conditionRows.remove(row.id, from: &conditions)
                        logicConditions = conditions
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            let conditionCount = logicConditions?.count ?? 0
            Color.clear.frame(width: 0, height: 0)
                .onAppear { conditionRows.resync(count: conditionCount) }
                .onChange(of: conditionCount) {
                    conditionRows.resync(count: $0)
                }
            if canAddCondition {
                ClashAddRow(Text("Add Condition")) {
                    newCondition = ClashLogicCondition(
                        action: .network,
                        content: "tcp"
                    )
                    addingCondition = true
                } touchLabel: {
                    Label {
                        Text("Add Condition")
                    } icon: {
                        icon(.plus)
                    }
                }
                .accessibilityIdentifier(
                    "profile-rule.condition.add"
                )
                .background(
                    ClashRoutedViewDestination(
                        isPresented: $addingCondition
                    ) {
                        ClashRuleConditionEditorView(
                            condition: $newCondition,
                            options: options,
                            runtimeProfile: runtimeProfile,
                            commitLabel: "Add",
                            loadGeoValues: loadGeoValues,
                            icon: icon
                        ) {
                            logicConditions?.append($0)
                        }
                        .clashPushedDetailPage()
                    }
                    .opacity(0)
                )
            }
        } else {
            VStack(
                alignment: .leading,
                spacing: ClashTheme.Spacing.tight
            ) {
                if !ClashPlatformLayout.modalEditorUsesGroupedForm {
                     
                     
                    Text(action.contentLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                structuredContentField
                Text(
                    "This expression uses nesting the condition builder does not cover; edit it verbatim."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var autoRouteLinks: some View {
        Group {
            ClashRoutedViewDestination(
                isPresented: Binding(
                    get: { autoRoute == .country },
                    set: {
                        if !$0 {
                            autoRoute = nil
                        }
                    }
                )
            ) {
                ClashRuleGeoValuePickerView(
                    resource: .geoIP,
                    localizeRegions: true,
                    title: "Country / Region",
                    current: content,
                    loadValues: loadGeoValues,
                    icon: icon
                ) {
                    content = $0.uppercased()
                }
                .clashPushedDetailPage()
            }
            ClashRoutedViewDestination(
                isPresented: Binding(
                    get: { autoRoute == .policy },
                    set: {
                        if !$0 {
                            autoRoute = nil
                        }
                    }
                )
            ) {
                ClashRulePolicyPickerView(
                    options: options,
                    current: target,
                    icon: icon
                ) {
                    target = $0
                }
                .clashPushedDetailPage()
            }
            ClashRoutedViewDestination(
                isPresented: Binding(
                    get: { autoRoute == .category },
                    set: {
                        if !$0 {
                            autoRoute = nil
                        }
                    }
                )
            ) {
                ClashRuleGeoValuePickerView(
                    resource: .geoSite,
                    localizeRegions: false,
                    title: "GeoSite category",
                    current: content,
                    loadValues: loadGeoValues,
                    icon: icon
                ) {
                    content = $0
                }
                .clashPushedDetailPage()
            }
        }
    }

     
    private func enumValueRow(
        _ label: String,
        value: String
    ) -> some View {
        HStack {
            Text(clash: .copy(label))
            Spacer(minLength: ClashTheme.Spacing.compact)
            if value.isEmpty {
                Text("Required")
                    .foregroundStyle(.secondary)
            } else {
                Text(verbatim: value)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: ClashTheme.Control.fullWidthRowMinHeightOnItsOwnPlatform, alignment: .leading)
    }

    private static func isLogic(
        _ action: ClashStructuredRule.Action
    ) -> Bool {
        [.and, .or, .not, .subRule].contains(action)
    }

    private var canAddCondition: Bool {
        guard let conditions = logicConditions else {
            return false
        }
        if action == .not || action == .subRule {
            return conditions.isEmpty
        }
        return true
    }

    private var logicFooter: String {
        switch action {
        case .not:
            "NOT matches when its single condition does not match."
        case .subRule:
            "SUB-RULE branches when its single condition matches."
        case .and:
            "All conditions must match. Long-press a condition to remove it."
        default:
            "Any one condition may match. Long-press a condition to remove it."
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
    private var saysSomething: Bool {
        if rawMode {
            return !rawText.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return !action.needsContent || !content.trimmingCharacters(in: .whitespaces).isEmpty
    }

     
     
     
     
     
     
     
     
    @State private var openedWith = ""

     
     
     
    private var currentFingerprint: String {
        [
            String(describing: action), content, target,
            String(src), String(rawMode), rawText,
            String(noResolve), comment,
            String(describing: logicConditions), String(enabled),
            String(describing: additionalParams),
        ].joined(separator: "\u{1F}")
    }

    private static func fingerprint(_ draft: ClashRuleBuilderDraft) -> String {
        [
            String(describing: draft.action), draft.content, draft.target,
            String(draft.src), String(draft.rawMode), draft.rawText,
            String(draft.noResolve), draft.comment,
            String(describing: draft.logicConditions), String(draft.enabled),
            String(describing: draft.additionalParams),
        ].joined(separator: "\u{1F}")
    }

    @discardableResult
    private func submit() -> Bool {
        let candidate: String
        if rawMode {
            candidate = rawText.trimmingCharacters(
                in: .whitespaces
            )
        } else {
            var effectiveContent = content.trimmingCharacters(
                in: .whitespaces
            )
            if Self.isLogic(action),
                let conditions = logicConditions
            {
                let minimum =
                    action == .not || action == .subRule ? 1 : 2
                guard conditions.count >= minimum else {
                    error =
                        minimum == 1
                        ? .copy("Add the condition first.")
                        : .copy("Add at least two conditions.")
                    return false
                }
                guard conditions.allSatisfy({
                    !$0.content.isEmpty
                }) else {
                    error = .copy("Every condition needs a value.")
                    return false
                }
                effectiveContent =
                    ClashLogicExpressionCodec.serialize(
                        action: action,
                        conditions: conditions
                    )
            }
            let rule = ClashStructuredRule(
                action: action,
                content: effectiveContent,
                target: target.trimmingCharacters(
                    in: .whitespaces
                ),
                noResolve: noResolve,
                src: src,
                additionalParams: additionalParams
            )
            guard !action.needsContent || !rule.content.isEmpty
            else {
                error = .formatCopy("%@ is required.", [action.contentLabel])
                return false
            }
            guard !showsTarget || !rule.target.isEmpty else {
                error = .formatCopy("%@ is required.", [action.targetLabel])
                return false
            }
             
             
            guard showsTarget || !ClashStructuredRule.refusedInARuleSet.contains(action) else {
                error = .copy("A rule set cannot carry a final rule, a rule set or a sub-rule. Pick another type.")
                return false
            }
            candidate = showsTarget ? rule.rawValue : Self.payloadLine(rule)
        }
         
         
        let judged = showsTarget || rawMode ? candidate : candidate + ",DIRECT"
        let disallowReason =
            rawMode
            ? ClashStructuredRule.rawDisallowReason(
                candidate,
                runtimeProfile: runtimeProfile
            )
            : ClashStructuredRule.disallowReason(
                judged,
                runtimeProfile: runtimeProfile
            )
        if let reason = disallowReason
        {
             
             
             
            error = .formatCopy("%@ The previous rule is unchanged.", [reason])
            return false
        }
        draftSlot.commit()
        save(
            ClashPersonalRuleSnapshot(
                raw: candidate,
                isEnabled: enabled,
                comment: comment.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).nonempty
            )
        )
         
        dismiss.closeModalOrDismiss()
        return true
    }

     
     
     
    static func payloadLine(_ rule: ClashStructuredRule) -> String {
        rule.payloadValue
    }
}

 
 
 
 
 
private struct ClashRuleNetworkMenuRow: View {
    @Binding var selection: String
    let identifier: String

    var body: some View {
        Menu {
            ForEach(["tcp", "udp"], id: \.self) { value in
                Button {
                    selection = value
                } label: {
                    if selection == value {
                        Label(value, systemImage: "checkmark")
                    } else {
                        Text(value)
                    }
                }
                .accessibilityIdentifier(
                    "\(identifier).choice.\(value)"
                )
            }
        } label: {
             
             
             
             
             
            HStack(spacing: ClashTheme.Spacing.compact) {
                Text(selection)
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
                Image(
                    systemName:
                        ClashSymbol.chevronUpChevronDown.rawValue
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .frame(minHeight: ClashTheme.Control.fullWidthRowMinHeightOnItsOwnPlatform)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Value")
            .accessibilityValue(selection)
            .accessibilityIdentifier(identifier)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .clashSettingsMenuRow("Value")
        .id("\(identifier)-\(selection)")
        .transaction { $0.animation = nil }
    }
}

private struct ClashRuleTypeSelectionView<Icon: View>: View {
    @Binding var selection: ClashStructuredRule.Action
    let runtimeProfile: ClashAppleRuntimeProfile
    var excludesLogic = false
     
     
    var excludedActions: Set<ClashStructuredRule.Action> = []
    var title = "Rule Type"
    let icon: (ClashSymbol) -> Icon

     
     
     
     
     
    @StateObject private var dismiss = ClashDismissHandle()
    @Environment(\.clashPopRoute) private var popRoute
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
     
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

    var body: some View {
        Form {
            ForEach(visibleCategories) { category in
                Section {
                    ForEach(offered(in: category)) { value in
                        Button {
                            selection = value
                            dismissRoute()
                        } label: {
                            HStack {
                                VStack(
                                    alignment: .leading,
                                    spacing: 3
                                ) {
                                    Text(verbatim: ConfigurationRuleWords.kindName(value.rawValue, locale: locale, copy: fieldCopy))
                                        .foregroundStyle(.primary)
                                    Text(clash: .copy(value.summary))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(
                                            horizontal: false,
                                            vertical: true
                                        )
                                     
                                     
                                     
                                     
                                    if let note = ClashStructuredRule.platformNote(
                                        for: value.rawValue,
                                        runtimeProfile: runtimeProfile
                                    ) {
                                        Text(clash: note)
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                Spacer(
                                    minLength:
                                        ClashTheme.Spacing.compact
                                )
                                ClashSelectionMark(
                                    isSelected:
                                        selection == value
                                )
                            }
                            .frame(
                                maxWidth: .infinity,
                                minHeight: ClashTheme.Control.fullWidthRowMinHeightOnItsOwnPlatform,
                                alignment: .leading
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(
                            "rule-type.\(value.rawValue)"
                        )
                    }
                } header: {
                    Text(clash: .copy(category.title))
                } footer: {
                    if let note = categoryNote(category) {
                         
                         
                        Text(clash: .copy(note))
                    }
                }
            }
        }
        .clashPageTitle(.copy(title))
        .accessibilityIdentifier("profile-rule.type.screen")
        .clashProductModalChild(title: .copy(title))
        .clashCapturesDismiss(dismiss)
    }

     
     
     
     
    private func offered(in category: ClashStructuredRule.Category) -> [ClashStructuredRule.Action] {
        let available = ClashStructuredRule.availableActions(for: runtimeProfile)
        return ClashStructuredRule.Action.allCases.filter {
            (available.contains($0) || $0 == selection)
                && $0.category == category
                && !excludedActions.contains($0)
                && (!excludesLogic || ($0.category != .logic && $0 != .match))
        }
    }

     
     
    private var visibleCategories: [ClashStructuredRule.Category] {
        ClashStructuredRule.Category.allCases.filter { !offered(in: $0).isEmpty }
    }

    private func categoryNote(
        _ category: ClashStructuredRule.Category
    ) -> String? {
        switch category {
        case .domain:
            "GEOSITE reads the built-in GeoSite database."
        case .address:
            "GEOIP and ASN heads read the built-in GeoIP, country and ASN databases."
        case .resources:
            "Rule sets come from this configuration's Rule Sets."
        default:
            nil
        }
    }

    private func dismissRoute() {
#if os(macOS)
        if let popRoute {
            popRoute(ClashPopToken())
        } else {
            dismiss()
        }
#else
         
         
         
        dismiss()
#endif
    }
}


private struct ClashRuleConditionEditorView<Icon: View>: View {
    @Binding var condition: ClashLogicCondition
    let options: ClashRulePolicyOptions
    let runtimeProfile: ClashAppleRuntimeProfile
    var commitLabel: String?
    let loadGeoValues:
        ClashRuleGeoValueLoader
    let icon: (ClashSymbol) -> Icon
    var onCommit: ((ClashLogicCondition) -> Void)?

     
     
     
     
     
    @StateObject private var dismiss = ClashDismissHandle()
    @Environment(\.clashPopRoute) private var popRoute
     
     
    @Environment(\.clashInsideProductModalPresentation)
    private var insideProductModal
     
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

    var body: some View {
        Form {
            Section {
                ClashRoutedViewLink {
                    ClashRuleTypeSelectionView(
                        selection: Binding(
                            get: { condition.action },
                            set: {
                                condition.action = $0
                                condition.content =
                                    $0 == .network ? "tcp" : ""
                                condition.noResolve = false
                                condition.src = false
                            }
                        ),
                        runtimeProfile: runtimeProfile,
                        excludesLogic: true,
                        excludedActions: options.unofferedKinds.subtracting([condition.action]),
                        title: "Condition Type",
                        icon: icon
                    )
                    .clashPushedDetailPage()
                } label: {
                    HStack {
                        Text("Type")
                        Spacer()
                        Text(verbatim: ConfigurationRuleWords.kindName(condition.action.rawValue, locale: locale, copy: fieldCopy))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: ClashTheme.Control.fullWidthRowMinHeightOnItsOwnPlatform)
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("condition.type")
            } footer: {
                Text(condition.action.summary)
            }

            Section("Value") {
                conditionValueEditor
            }

            if condition.action.supportsNoResolve
                || condition.action.supportsSrc
            {
                Section("Params") {
                    if condition.action.supportsNoResolve {
                        ClashSettingsToggleRow(
                            Text("Skip DNS resolution"),
                            isOn: $condition.noResolve
                        )
                        .accessibilityIdentifier(
                            "condition.no-resolve"
                        )
                    }
                    if condition.action.supportsSrc {
                        ClashSettingsToggleRow(
                            Text("Match source instead"),
                            isOn: $condition.src
                        )
                        .accessibilityIdentifier("condition.src")
                    }
                }
            }
        }
        .clashPageTitle("Condition")
        .clashToolbarUnlessInPanel {
            ToolbarItem(placement: .confirmationAction) {
                if let commitLabel {
                     
                     
                     
                    Button {
                        onCommit?(condition)
                        dismissRoute()
                    } label: {
                        Text(clash: .copy(commitLabel))
                    }
                    .disabled(condition.content.isEmpty)
                    .accessibilityIdentifier("condition.commit")
                }
            }
        }
        .accessibilityIdentifier("condition.screen")
         
         
         
         
         
         
        .clashProductModalChild(title: "Condition")
         
         
         
         
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if insideProductModal, let commitLabel {
                ClashModalActionBar(
                    primaryTitle: commitLabel,
                    primaryDisabled: condition.content.isEmpty
                ) {
                    onCommit?(condition)
                    dismissRoute()
                }
            }
        }
        .clashCapturesDismiss(dismiss)
    }

    private var modalCommitAction: (() -> Void)? {
        guard commitLabel != nil else { return nil }
        return {
            guard !condition.content.isEmpty else { return }
            onCommit?(condition)
            dismissRoute()
        }
    }

    private func dismissRoute() {
#if os(macOS)
        if let popRoute {
            popRoute(ClashPopToken())
        } else {
            dismiss()
        }
#else
         
         
         
        dismiss()
#endif
    }

    @ViewBuilder
    private var conditionValueEditor: some View {
        if condition.action == .network {
            ClashRuleNetworkMenuRow(
                selection: $condition.content,
                identifier: "condition.content"
            )
        } else if condition.action == .geoip
            || condition.action == .srcGeoIP
        {
            ClashRoutedViewLink {
                ClashRuleGeoValuePickerView(
                    resource: .geoIP,
                    localizeRegions: true,
                    title: "Country / Region",
                    current: condition.content,
                    loadValues: loadGeoValues,
                    icon: icon
                ) {
                    condition.content = $0.uppercased()
                }
                .clashPushedDetailPage()
            } label: {
                conditionValueRow("Country / Region")
            }
            .accessibilityIdentifier(
                "condition.content.picker"
            )
        } else if condition.action == .geosite {
            ClashRoutedViewLink {
                ClashRuleGeoValuePickerView(
                    resource: .geoSite,
                    localizeRegions: false,
                    title: "GeoSite category",
                    current: condition.content,
                    loadValues: loadGeoValues,
                    icon: icon
                ) {
                    condition.content = $0
                }
                .clashPushedDetailPage()
            } label: {
                conditionValueRow("Category")
            }
            .accessibilityIdentifier(
                "condition.content.picker"
            )
        } else if condition.action == .ruleSet,
            !options.ruleSets.isEmpty
        {
            ClashRoutedViewLink {
                ClashRuleSetPickerView(
                    sets: options.ruleSets,
                    current: condition.content,
                    icon: icon
                ) {
                    condition.content = $0
                }
                .clashPushedDetailPage()
            } label: {
                conditionValueRow("Rule Set")
            }
            .accessibilityIdentifier(
                "condition.content.picker"
            )
        } else {
            ClashFieldRow(
                condition.action.contentLabel,
                hint: condition.action.contentPlaceholder,
                text: $condition.content,
                monospaced: true,
                identifier: "condition.content"
            )
        }
    }

    private func conditionValueRow(
        _ label: String
    ) -> some View {
        HStack {
            Text(clash: .copy(label))
            Spacer(minLength: ClashTheme.Spacing.compact)
             
            if condition.content.isEmpty {
                Text("Required").foregroundStyle(.secondary)
            } else {
                Text(verbatim: ConfigurationRuleWords.payloadName(condition.content, kind: condition.action.rawValue,
                                                                  locale: locale, copy: fieldCopy))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: ClashTheme.Control.fullWidthRowMinHeightOnItsOwnPlatform)
        .contentShape(Rectangle())
    }
}

 
 
 
 
 
 
 
 
 
 
 
public enum ClashRulePolicyBuiltIns {
    public static let rule: [(name: String, caption: String)] = [
        ("DIRECT", "Do not proxy; connect directly."),
        ("REJECT", "Abort the request."),
        ("REJECT-DROP", "Drop silently, without answering."),
        ("PASS", "Skip this rule; keep matching the ones below."),
        ("PASS-RULE", "Skip this rule but stay inside the sub-rule list."),
        ("MATCH", "Follow this profile's final MATCH policy."),
    ]
}

 
 
 
 
private struct ClashRulePolicyGroupCreationPage: View {
    let make: (@escaping (String?) -> Void) -> AnyView
    let onCreated: (String) -> Void
     
     
     
    @StateObject private var dismiss = ClashDismissHandle()
    @Environment(\.clashPopRoute) private var popRoute

    var body: some View {
        make { name in
            leave()
            if let name, !name.isEmpty { onCreated(name) }
        }
        .clashCapturesDismiss(dismiss)
    }

    private func leave() {
#if os(macOS)
        if let popRoute {
            popRoute(ClashPopToken())
        } else {
            dismiss()
        }
#else
        dismiss()
#endif
    }
}

public struct ClashRulePolicyPickerView<Icon: View>: View {
    let title: String
    let builtIns: [(name: String, caption: String)]
    let builtInsTitle: String?
    let axPrefix: String
    let offersGlobal: Bool
    let options: ClashRulePolicyOptions
    let current: String
     
     
     
     
    let createGroup: ((@escaping (String?) -> Void) -> AnyView)?
    let icon: (ClashSymbol) -> Icon
    let pick: (String) -> Void

    private static var ruleBuiltIns: [(name: String, caption: String)] {
        ClashRulePolicyBuiltIns.rule
    }

    public init(
        title: String = "Target",
        builtIns: [(name: String, caption: String)]? = nil,
        builtInsTitle: String? = "Built-in",
        axPrefix: String = "rule-policy",
        offersGlobal: Bool = true,
        options: ClashRulePolicyOptions,
        current: String,
        createGroup: ((@escaping (String?) -> Void) -> AnyView)? = nil,
        icon: @escaping (ClashSymbol) -> Icon,
        pick: @escaping (String) -> Void
    ) {
        self.title = title
        self.builtIns = builtIns ?? Self.ruleBuiltIns
        self.builtInsTitle = builtInsTitle
        self.axPrefix = axPrefix
        self.offersGlobal = offersGlobal
        self.options = options
        self.current = current
        self.createGroup = createGroup
        self.icon = icon
        self.pick = pick
    }

     
     
     
     
     
    @StateObject private var dismiss = ClashDismissHandle()
    @Environment(\.clashPopRoute) private var popRoute
     
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale
    @Environment(\.clashRuleTargetSearch) private var targetSearch
    @State private var query = ""
     
     
    @State private var searched: [ClashRulePolicySnapshot] = []

    public var body: some View {
        catalogue
            .clashProductModalSearchable(
                text: $query,
                prompt: Text("Search proxies")
            )
            .task(id: query) {
                guard let targetSearch, !query.isEmpty else { searched = []; return }
                try? await Task.sleep(nanoseconds: ClashRuleTargetSearchHook.settle)
                guard !Task.isCancelled else { return }
                let sections = await targetSearch.sections(query, [current])
                guard !Task.isCancelled else { return }
                searched = sections.flatMap { section in
                    section.names.map { ClashRulePolicySnapshot(name: $0, type: section.sourceLabel ?? "") }
                }
            }
            .clashPageTitle(.copy(title))
            .clashProductModalChild(
                title: .copy(title),
                searchText: $query
            )
            .clashCapturesDismiss(dismiss)
    }

     
     
     
     
     
     
     
     
     
     
     
     
    @ViewBuilder
    private var catalogue: some View {
        if ClashPlatformLayout.pageUsesSystemSettingsIdiom {
            List { sections }
                .clashMacSettingsList()
        } else {
            Form { sections }
        }
    }

    @ViewBuilder
    private var sections: some View {
        if !builtIns.isEmpty {
            Section {
                ForEach(builtIns, id: \.name) { entry in
                    policyRow(entry.name, caption: entry.caption)
                }
            } header: {
                if let builtInsTitle {
                    Text(clash: .copy(builtInsTitle))
                }
            }
        }
        if !filteredGroups.isEmpty || query.isEmpty {
            Section("Groups") {
                ForEach(filteredGroups) {
                    policyRow($0.name, caption: $0.type)
                }
                if offersGlobal,
                    !options.groups.contains(where: {
                    $0.name == "GLOBAL"
                }),
                    query.isEmpty
                        || "GLOBAL"
                        .localizedCaseInsensitiveContains(query)
                {
                    policyRow(
                        "GLOBAL",
                        caption: "Kernel built-in group"
                    )
                }
                if let createGroup, query.isEmpty {
                     
                     
                     
                     
                     
                     
                    ClashRoutedViewLink {
                        ClashRulePolicyGroupCreationPage(make: createGroup) { name in
                            choose(name)
                            dismissRoute()
                        }
                        .clashPushedDetailPage()
                    } label: {
                        Label {
                            Text(clash: .copy("Add Policy Group"))
                        } icon: {
                            Image(systemName: ClashSymbol.plus.rawValue)
                        }
                    }
                    .accessibilityIdentifier("\(axPrefix).group.add")
                }
            }
        }
        if !filteredProxies.isEmpty {
            Section("Proxies") {
                ForEach(filteredProxies) {
                    policyRow($0.name, caption: $0.type)
                }
            }
        }
    }

    private var filteredGroups: [ClashRulePolicySnapshot] {
        query.isEmpty
            ? options.pickableGroups
            : options.pickableGroups.filter {
                $0.name.localizedCaseInsensitiveContains(query)
            }
    }

    private var filteredProxies: [ClashRulePolicySnapshot] {
        guard !query.isEmpty else { return options.proxies }
        let local = options.proxies.filter {
            $0.name.localizedCaseInsensitiveContains(query)
        }
        var seen = Set(local.map(\.name)).union(options.groups.map(\.name))
        return local + searched.filter { seen.insert($0.name).inserted }
    }

     
    private func choose(_ name: String) {
        targetSearch?.recordUse(name)
        pick(name)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    @ViewBuilder
    private func policyRow(
        _ name: String,
        caption: String
    ) -> some View {
#if os(macOS)
        policyRowLabel(name, caption: caption)
            .contentShape(Rectangle())
            .onTapGesture {
                choose(name)
                dismissRoute()
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                choose(name)
                dismissRoute()
            }
            .accessibilityIdentifier("\(axPrefix).\(name)")
#else
        Button {
            choose(name)
            dismissRoute()
        } label: {
            policyRowLabel(name, caption: caption)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("\(axPrefix).\(name)")
#endif
    }

    private func policyRowLabel(
        _ name: String,
        caption: String
    ) -> some View {
        HStack(spacing: ClashTheme.Spacing.row) {
            VStack(alignment: .leading, spacing: 2) {
                 
                 
                Text(verbatim: ConfigurationRuleWords.targetName(name, locale: locale, copy: fieldCopy))
                    .foregroundStyle(.primary)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if name == current {
                icon(.checkmark)
                    .foregroundStyle(.tint)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: ClashTheme.Control.fullWidthRowMinHeightOnItsOwnPlatform,
            alignment: .leading
        )
    }

    private func dismissRoute() {
#if os(macOS)
        if let popRoute {
            popRoute(ClashPopToken())
        } else {
            dismiss()
        }
#else
         
         
         
        dismiss()
#endif
    }
}

 
 
 
 
 
enum ClashGeoValueSearch {
    static func matches(
        values: [String],
        folded: [String],
        needle: String,
        cap: Int,
        localizeRegions: Bool
    ) -> [String] {
        let lowered = needle.lowercased()
        var hits: [String] = []
        hits.reserveCapacity(cap)
        for (index, entry) in folded.enumerated() where index < values.count {
            let value = values[index]
            var matched = entry.contains(lowered)
            if !matched, localizeRegions, value.count == 2 {
                matched = Locale.current
                    .localizedString(forRegionCode: value.uppercased())?
                    .lowercased()
                    .contains(lowered) ?? false
            }
            if matched {
                hits.append(value)
                if hits.count == cap { break }
            }
        }
        return hits
    }
}

private struct ClashRuleGeoValuePickerView<Icon: View>: View {
    let resource: ClashRuleGeoResource
    let localizeRegions: Bool
    let title: String
    let current: String
    let loadValues:
        ClashRuleGeoValueLoader
    let icon: (ClashSymbol) -> Icon
    let pick: (String) -> Void

     
     
     
     
     
    @StateObject private var dismiss = ClashDismissHandle()
    @Environment(\.clashPopRoute) private var popRoute
    @State private var query = ""
    @State private var values: [String] = []
     
     
     
    @State private var foldedValues: [String] = []
     
     
     
     
     
     
     
    @State private var matches: [String] = []
    @State private var loaded = false

    var body: some View {
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        List {
            if !loaded {
                Section {
                    ProgressView()
                        .frame(
                            maxWidth: .infinity,
                            minHeight: 96
                        )
                        .accessibilityIdentifier("rule-geo.loading")
                }
            } else if values.isEmpty {
                Section {
                    ClashRuleCatalogUnavailableView(
                        title: "No categories available",
                        detail:
                            "The active Geo database does not publish any \(resourceTitle) categories.",
                        systemImage: "tray"
                    )
                    .accessibilityIdentifier("rule-geo.empty")
                }
            } else if filtered.isEmpty {
                Section {
                    ClashRuleCatalogUnavailableView(
                        title: "No results",
                        detail: "No category matches “\(query)”.",
                        systemImage: "magnifyingglass"
                    )
                    .accessibilityIdentifier(
                        "rule-geo.no-results"
                    )
                }
            } else {
                Section {
                    ForEach(filtered, id: \.self) { value in
                        Button {
                            pick(value)
                            dismissRoute()
                        } label: {
                            HStack(spacing: ClashTheme.Spacing.row) {
                                Text(displayValue(value))
                                    .foregroundStyle(.primary)
                                if let name = regionName(value) {
                                    Text(name)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                if value == current {
                                    icon(.checkmark)
                                        .foregroundStyle(.tint)
                                }
                            }
                            .frame(
                                maxWidth: .infinity,
                                minHeight: ClashTheme.Control.fullWidthRowMinHeightOnItsOwnPlatform,
                                alignment: .leading
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(
                            "rule-geo.\(value)"
                        )
                    }
                }
            }
        }
         
         
        .clashMacSettingsList(
            minRowHeight: ClashMacSettingsMetrics.listRowMinHeight
        )
        .clashProductModalSearchable(
            text: $query,
            prompt: Text("Search code or name")
        )
        .clashPageTitle(.copy(title))
        .task(id: query) { await prepareMatches() }
        .task {
            guard !loaded else { return }
            let loadedValues = await loadValues(resource)
            let folded = await Task.detached(priority: .userInitiated) {
                loadedValues.map { $0.lowercased() }
            }.value
            values = loadedValues
            foldedValues = folded
            loaded = true
            await prepareMatches()
        }
        .clashProductModalChild(
            title: .copy(title),
            searchText: $query
        )
        .clashCapturesDismiss(dismiss)
    }

    private func dismissRoute() {
#if os(macOS)
        if let popRoute {
            popRoute(ClashPopToken())
        } else {
            dismiss()
        }
#else
         
         
         
        dismiss()
#endif
    }

     
     
     
     
     
     
     
     
    private static var geoMatchCap: Int { 300 }

    private var filtered: [String] { matches }

    @MainActor
    private func prepareMatches() async {
        guard !query.isEmpty else {
             
             
             
             
             
            matches = values
            return
        }
        let needle = query
        let values = values
        let folded = foldedValues
        let cap = Self.geoMatchCap
        let localize = localizeRegions
        let hits = await Task.detached(priority: .userInitiated) {
            ClashGeoValueSearch.matches(
                values: values,
                folded: folded,
                needle: needle,
                cap: cap,
                localizeRegions: localize
            )
        }.value
         
         
        if Task.isCancelled { return }
        matches = hits
    }

    private var resourceTitle: String {
        resource == .geoIP ? "GeoIP" : "GeoSite"
    }

    private func regionName(_ code: String) -> String? {
        guard localizeRegions, code.count == 2 else {
            return nil
        }
        return Locale.current.localizedString(
            forRegionCode: code.uppercased()
        )
    }

    private func displayValue(_ value: String) -> String {
        localizeRegions && value.count == 2
            ? value.uppercased()
            : value
    }
}

private struct ClashRuleSetPickerView<Icon: View>: View {
    let sets: [String]
    let current: String
    let icon: (ClashSymbol) -> Icon
    let pick: (String) -> Void

     
     
     
     
     
    @StateObject private var dismiss = ClashDismissHandle()
    @Environment(\.clashPopRoute) private var popRoute
    @State private var query = ""
     
     
     
     
    @State private var folded: [String] = []
    @State private var matches: [String] = []

    var body: some View {
        Form {
            if filtered.isEmpty {
                Section {
                    ClashRuleCatalogUnavailableView(
                        title: "No results",
                        detail: "No rule set matches “\(query)”.",
                        systemImage: "magnifyingglass"
                    )
                    .accessibilityIdentifier(
                        "rule-set.no-results"
                    )
                }
            } else {
                Section {
                    ForEach(filtered, id: \.self) { name in
                        Button {
                            pick(name)
                            dismissRoute()
                        } label: {
                            HStack {
                                Text(name)
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 8)
                                if name == current {
                                    icon(.checkmark)
                                        .foregroundStyle(.tint)
                                }
                            }
                            .frame(
                                maxWidth: .infinity,
                                minHeight: ClashTheme.Control.fullWidthRowMinHeightOnItsOwnPlatform,
                                alignment: .leading
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(
                            "rule-set.\(name)"
                        )
                    }
                }
            }
        }
        .task(id: query) { await prepareMatches() }
        .clashProductModalSearchable(
            text: $query,
            prompt: Text("Search rule sets")
        )
        .clashPageTitle("Rule Sets")
        .clashProductModalChild(
            title: "Rule Sets",
            searchText: $query
        )
        .clashCapturesDismiss(dismiss)
    }

    private func dismissRoute() {
#if os(macOS)
        if let popRoute {
            popRoute(ClashPopToken())
        } else {
            dismiss()
        }
#else
         
         
         
        dismiss()
#endif
    }

    private var filtered: [String] { matches }

    @MainActor
    private func prepareMatches() async {
        if folded.count != sets.count {
            folded = sets.map { $0.lowercased() }
        }
        guard !query.isEmpty else {
             
             
            matches = sets
            return
        }
        let needle = query
        let values = sets
        let foldedValues = folded
        let cap = Self.ruleSetMatchCap
        let hits = await Task.detached(priority: .userInitiated) {
            ClashGeoValueSearch.matches(
                values: values,
                folded: foldedValues,
                needle: needle,
                cap: cap,
                localizeRegions: false
            )
        }.value
         
        guard !Task.isCancelled else { return }
        matches = hits
    }

     
     
    private static var ruleSetMatchCap: Int { 300 }
}

private struct ClashRuleCatalogUnavailableView: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        VStack(spacing: ClashTheme.Spacing.compact) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(clash: .copy(title))
                .font(.headline)
            Text(clash: .copy(detail))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ClashTheme.Spacing.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension ClashRuleLineSnapshot {
     
     
     
     
    func typeLine(locale: Locale) -> String {
        guard let entryCount else { return type }
        let format = entryCount == 1 ? "%@ entry" : "%@ entries"
        return type + " · " + ClashCopy.format(format, locale: locale, ClashCopy.count(entryCount, locale: locale))
    }
}

extension ClashRulesOverviewSnapshot {
     
     
     
     
     
     
     
     
     
    func inapplicableLine(locale: Locale) -> String {
        let format = inapplicableCount == 1
            ? "%1$@ rule will not take effect on %2$@"
            : "%1$@ rules will not take effect on %2$@"
        return ClashCopy.format(format, locale: locale, ClashCopy.count(inapplicableCount, locale: locale), platformTitle)
    }
}

 
 
 
 
 
 
 
 
 
enum ClashRulesCountCopy {
     
     
    static func rules(_ count: Int, locale: Locale) -> String {
        ClashCopy.format(count == 1 ? "%@ rule" : "%@ rules", locale: locale, ClashCopy.count(count, locale: locale))
    }

     
    static func moreRules(_ count: Int, locale: Locale) -> String {
        ClashCopy.format(count == 1 ? "%@ more rule" : "%@ more rules", locale: locale, ClashCopy.count(count, locale: locale))
    }

     
    static func moreMatches(_ count: Int, locale: Locale) -> String {
        ClashCopy.format(count == 1 ? "%@ more match…" : "%@ more matches…", locale: locale, ClashCopy.count(count, locale: locale))
    }

     
     
     
     
    static func rulesTo(_ count: Int, target: String, locale: Locale) -> String {
        ClashCopy.format(count == 1 ? "%1$@ rule to %2$@" : "%1$@ rules to %2$@", locale: locale,
                         ClashCopy.count(count, locale: locale), target)
    }
}

extension ClashRuleSetSnapshot {
     
     
     
     
     
     
     
    func subtitle(locale: Locale) -> String {
        guard let entryCount else { return detail }
        let counted = ClashRulesCountCopy.rules(entryCount, locale: locale)
        return detail.isEmpty ? counted : detail + " · " + counted
    }

     
     
     
     
     
     
     
     
     
     
     
    func localFileNote(locale: Locale) -> String? {
        let kind = detail.split(separator: "·").first?
            .trimmingCharacters(in: .whitespaces).lowercased()
         
         
         
         
         
         
        guard kind == "file", entryCount == 0 else { return nil }
        return ClashCopy.string(
            "This set is read from a file on the device that wrote the configuration, which is not carried with it. Give it a link instead, or paste its rules into the configuration.",
            locale: locale
        )
    }
}

public enum ClashProfileRulesCopy {
     
     
     
     
     
    public static let everyProfileHint = "To apply rules to every profile, create a module in Profiles › Modules."
}
