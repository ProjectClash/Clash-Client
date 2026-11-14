import SwiftUI

 
 
 
 
 
 
 

 
struct ClashRuleBucketFrozenRow: Equatable, Hashable, Identifiable {
    let target: String
    let count: Int
    var id: String { target }
}

 
struct ClashRuleFrozenRow: Equatable, Hashable, Identifiable {
    let raw: String
    let type: String
    let payload: String
    let target: String
     
     
     
     
    let entryCount: Int?
    var id: String { raw }

    init(_ rule: ClashRuleLineSnapshot) {
        raw = rule.raw
        type = rule.type
        payload = rule.payload
        target = rule.target
        entryCount = rule.entryCount
    }

    func typeLine(locale: Locale) -> String {
        ClashRuleLineSnapshot(raw: raw, type: type, payload: payload, target: target, entryCount: entryCount)
            .typeLine(locale: locale)
    }
}

 
 
 
struct ClashRulesSystemOverview<Icon: View>: View {
    let overview: ClashRulesOverviewSnapshot
    let query: String
    let palette: ClashProductPalette
    let icon: (ClashSymbol) -> Icon
    let activeRulesEntry: AnyView

     
     
     
     
    @State private var searchHits: [ClashRuleFrozenRow] = []
    @State private var searchHitCount = 0
    @State private var searchedQuery = ""
     
     
    @Environment(\.clashRulesSearch) private var rulesSearch
    @Environment(\.locale) private var locale

    var body: some View {
        let _ = ClashPerf.count("rules.list.body")
        return List {
            if query.isEmpty {
                overviewSections
            } else {
                searchSection
            }
            Section {
                activeRulesEntry
            }
        }
        .task(id: query) {
            let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                searchHits = []; searchHitCount = 0; searchedQuery = ""
                return
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            if overview.rulesAreCounted {
                let found = await rulesSearch?.search(normalized)
                if Task.isCancelled { return }
                searchHitCount = found?.total ?? 0
                searchHits = (found?.rules ?? []).prefix(50).map(ClashRuleFrozenRow.init)
                searchedQuery = normalized
                return
            }
            let raws = overview.searchableRules.map(\.raw)
            let indices = await Task.detached(priority: .userInitiated) { () -> [Int] in
                var out: [Int] = []
                for (i, raw) in raws.enumerated() where raw.localizedCaseInsensitiveContains(normalized) {
                    out.append(i)
                }
                return out
            }.value
            if Task.isCancelled { return }
             
             
             
             
            searchHitCount = indices.count
            searchHits = indices.prefix(50).map { ClashRuleFrozenRow(overview.searchableRules[$0]) }
            searchedQuery = normalized
        }
    }

    @ViewBuilder
    private var overviewSections: some View {
         
         
         
        if overview.hasRulesGroup {
            Section {
                ForEach(overview.buckets.map { ClashRuleBucketFrozenRow(target: $0.target, count: $0.ruleCount) }) { row in
                    ClashRuleBucketListRow(row: row)
                        .equatable()
                }
                if overview.inapplicableCount > 0 {
                     
                     
                     
                     
                     
                     
                     
                     
                    Text(clash: .verbatim(overview.inapplicableLine(locale: locale)))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("rules.inapplicable")
                }
            } header: {
                Text(clash: .format("Rules (%@)", [ClashCopy.count(overview.inlineCount, locale: locale)]))
            } footer: {
                 
                if !overview.buckets.isEmpty {
                    Text("Grouped by destination. What the tunnel runs: the profile's rules with your custom rules and the override script applied.")
                }
            }
        }
        if !overview.ruleSets.isEmpty {
            Section {
                ForEach(overview.ruleSets) { ruleSet in
                    ClashRuleSetListRow(ruleSet: ruleSet)
                }
            } header: {
                Text(clash: .format("Rule Sets (%@)", [String(overview.ruleSets.count)]))
            }
        }
        if !overview.fallback.isEmpty {
            Section {
                ForEach(overview.fallback.map(ClashRuleFrozenRow.init)) { row in
                    ClashRuleListRow(row: row, palette: palette)
                        .equatable()
                }
            } header: {
                Text("Fallback")
            } footer: {
                Text("Traffic that matches nothing above.")
            }
        }
         
        if !overview.hasRulesGroup && overview.ruleSets.isEmpty && overview.fallback.isEmpty {
            Section {
                ClashEmptyState(
                    title: "No Rules",
                    message: "This profile does not declare routing rules or rule providers."
                ) {
                    icon(.listBulletRectangle)
                }
            }
        }
    }

    @ViewBuilder
    private var searchSection: some View {
        Section {
            if searchedQuery.isEmpty && searchHits.isEmpty {
                 
                ProgressView()
                    .controlSize(.small)
            } else if searchHits.isEmpty {
                Text("No matching rules")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(searchHits) { row in
                    ClashRuleListRow(row: row, palette: palette)
                        .equatable()
                }
                if searchHitCount > 50 {
                    Text(clash: .verbatim(ClashRulesCountCopy.moreMatches(searchHitCount - 50, locale: locale)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(clash: .format(searchHitCount == 1 ? "%@ match" : "%@ matches", [ClashCopy.count(searchHitCount, locale: locale)]))
        }
    }
}

 
 
struct ClashRuleBucketListRow: View, Equatable {
    nonisolated static func == (a: Self, b: Self) -> Bool { a.row == b.row }

    let row: ClashRuleBucketFrozenRow
    @Environment(\.locale) private var locale

    var body: some View {
        let _ = ClashPerf.count("rules.list.bucket")
        return Group {
            if #available(iOS 16.0, macOS 13.0, tvOS 16.0, *) {
                NavigationLink(value: ClashRuleBucketRoute(target: row.target)) {
                    label
                }
            } else {
                label
            }
        }
        .accessibilityLabel(ClashRulesCountCopy.rulesTo(row.count, target: row.target, locale: locale))
        .accessibilityIdentifier("rules.bucket.\(row.target)")
    }

    private var label: some View {
        HStack(spacing: ClashTheme.Spacing.row) {
            Text(row.target)
                .font(.body.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(row.count)")
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

 
 
struct ClashRuleListRow: View, Equatable {
    nonisolated static func == (a: Self, b: Self) -> Bool { a.row == b.row }

    let row: ClashRuleFrozenRow
    let palette: ClashProductPalette
    @Environment(\.locale) private var locale

    var body: some View {
        let _ = ClashPerf.count("rules.list.row")
        return HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.payload.isEmpty ? row.type : row.payload)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if ClashRuleRowLayout.showsTypeLine(payload: row.payload) {
                     
                    Text(clash: .verbatim(row.typeLine(locale: locale)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text(row.target)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(palette.raisedFill))
        }
    }
}

 
 
struct ClashRuleSetListRow: View {
    let ruleSet: ClashRuleSetSnapshot
    @Environment(\.locale) private var locale

    var body: some View {
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
                    .accessibilityIdentifier("rules.rule-set.blocked.\(ruleSet.name)")
                Text(clash: .verbatim(reason))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

 
 
struct ClashRuleBucketSystemPage: View {
    let bucket: ClashRuleBucketSnapshot
    let jumpCard: AnyView?
    let palette: ClashProductPalette
    @Environment(\.locale) private var locale

    static var renderedRowCap: Int { ClashRuleBucketLazyPage.renderedRowCap }

    var body: some View {
        let _ = ClashPerf.count("rules.list.bucket-page")
        let rows = Array(bucket.rules.prefix(Self.renderedRowCap)).map(ClashRuleFrozenRow.init)
        return List {
            if let jumpCard {
                Section { jumpCard }
            }
            Section {
                ForEach(rows) { row in
                    ClashRuleListRow(row: row, palette: palette)
                        .equatable()
                }
            } header: {
                Text(clash: .verbatim(ClashRulesCountCopy.rules(bucket.ruleCount, locale: locale)))
            }
        }
    }
}
