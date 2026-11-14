import Foundation
import Clash
import ClashClientUI
import SwiftUI

 
 
 
 
struct RulesOverviewAdapter<ActiveRules: View>: View {
    @Environment(\.horizontalSizeClass)
    private var horizontalSizeClass

    private let sourceYAML: String?
    private let canInspectActiveRules: Bool
     
     
    private let compileVerdicts: ProviderCompileVerdicts
     
     
     
    private let activeRules: () -> ActiveRules
    private let openProxiesGroup: ((String) -> Void)?
     
     
    private let editRules: (() -> AnyView)?

     
     
     
     
     
     
     
     
     
     
    @State private var prepared: PreparedRules?

    @MainActor
    init(
        sourceYAML: String?,
        canInspectActiveRules: Bool = false,
        compileVerdicts: ProviderCompileVerdicts = ProviderCompileVerdicts(),
        openProxiesGroup: ((String) -> Void)? = nil,
        ownsNavigationContainer: Bool = true,
        editRules: (() -> AnyView)? = nil,
        @ViewBuilder activeRules: @escaping () -> ActiveRules
    ) {
        self.sourceYAML = sourceYAML
        self.canInspectActiveRules = canInspectActiveRules
        self.compileVerdicts = compileVerdicts
        self.activeRules = activeRules
        self.openProxiesGroup = openProxiesGroup
        self.editRules = editRules
        self.ownsNavigationContainer = ownsNavigationContainer
         
         
         
         
         
        _prepared = State(
            initialValue: RulesOverviewPreparationCache.shared.value(
                for: RulesPreparationKey(
                    sourceYAML: sourceYAML,
                    canInspectActiveRules: canInspectActiveRules,
                    wantsJumpableTargets: openProxiesGroup != nil,
                    compileVerdicts: compileVerdicts
                )
            )
        )
    }

     
    private let ownsNavigationContainer: Bool

    var body: some View {
         
         
         
         
         
        ClashFeatureNavigationContainer(
            ownsNavigationContainer: ownsNavigationContainer
        ) {
            page
        }
    }

    @ViewBuilder
    private var page: some View {
        if ownsNavigationContainer {
            content.clashSheetPresentation()
        } else {
            content
        }
    }

    private var content: some View {
        Group {
            if let prepared {
                 
                 
                 
                 
                 
                EquatableBrowser(
                    token: prepared.token,
                    snapshot: prepared.snapshot,
                    presentationClass:
                        horizontalSizeClass == .regular
                            ? .regularTouch
                            : .compactTouch,
                    showsDismissControl: ownsNavigationContainer,
                    actions: sharedActions,
                    editRules: editRules,
                    activeRules: activeRules
                )
                 
                 
                .environment(\.clashRulesSearch, prepared.search.map { session in
                    ClashRulesSearchHook { query in
                        await Task.detached(priority: .userInitiated) { session.search(query) }.value
                    }
                })
            } else {
                ClashOpeningProgress()
            }
        }
         
         
         
         
         
         
        .task(
            id: RulesPreparationKey(
                sourceYAML: sourceYAML,
                canInspectActiveRules: canInspectActiveRules,
                wantsJumpableTargets: openProxiesGroup != nil,
                compileVerdicts: compileVerdicts
            )
        ) {
            let key = RulesPreparationKey(
                sourceYAML: sourceYAML,
                canInspectActiveRules: canInspectActiveRules,
                wantsJumpableTargets: openProxiesGroup != nil,
                compileVerdicts: compileVerdicts
            )
            await prepare(key: key)
        }
    }

    private struct EquatableBrowser: View, Equatable {
        let token: UUID
        let snapshot: AppleClientSnapshot
        let presentationClass: ClashClientUI.ClashPresentationClass
        let showsDismissControl: Bool
        let actions: AppleClientActions
        let editRules: (() -> AnyView)?
        let activeRules: () -> ActiveRules

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.token == rhs.token
                && lhs.presentationClass == rhs.presentationClass
                && lhs.showsDismissControl == rhs.showsDismissControl
                && (lhs.editRules == nil) == (rhs.editRules == nil)
        }

        var body: some View {
            ClashClientUI.ClashRulesOverviewView(
                snapshot: snapshot,
                actions: actions,
                presentationClass: presentationClass,
                palette: ClashClientUI.ClashProductPalette.clashProduct,
                showsDismissControl: showsDismissControl,
                editRulesDestination: editRules
            ) { symbol in
                ClashSymbolImage(symbol: symbol)
            } activeRulesDestination: {
                activeRules()
            }
        }
    }

    @MainActor
    private func prepare(key: RulesPreparationKey) async {
        let yaml = sourceYAML
        let canInspect = canInspectActiveRules
        let verdicts = compileVerdicts
        let wantsJumpableTargets = openProxiesGroup != nil
        let world = await RulesOverviewPreparationCache.shared.value(
            for: key
        ) {
            let began = DispatchTime.now().uptimeNanoseconds
            let (snapshot, catalogSource) = await Task.detached(priority: .userInitiated) {
                RulesOverviewSnapshotBuilder.prepare(
                    sourceYAML: yaml,
                    canInspectActiveRules: canInspect,
                    wantsJumpableTargets: wantsJumpableTargets,
                    compileVerdicts: verdicts,
                    countEntries: RuleEntryCounts.app(sourceYAML: yaml)
                )
            }.value
            ClashPerf.span(
                "rules.prepare",
                milliseconds: Double(
                    DispatchTime.now().uptimeNanoseconds - began
                ) / 1_000_000,
                detail: "rules=\(snapshot.rules.overview.inlineCount)"
            )
            return PreparedRules(token: UUID(), snapshot: snapshot,
                                 search: catalogSource.map(RulesCatalogSession.init))
        }
        guard !Task.isCancelled,
              key == RulesPreparationKey(
                  sourceYAML: sourceYAML,
                  canInspectActiveRules: canInspectActiveRules,
                  wantsJumpableTargets: openProxiesGroup != nil,
                  compileVerdicts: compileVerdicts
              ) else { return }
        prepared = world
    }

    private var productPalette: ClashClientUI.ClashProductPalette {
        ClashClientUI.ClashProductPalette.clashProduct
    }

    private var sharedActions: AppleClientActions {
        AppleClientActions(capability: .rules) { action in
            guard case .rules(let command) = action else {
                return
            }
            switch command {
            case .openActiveRules:
                 
                break
            case .openProxiesGroup(let name):
                openProxiesGroup?(name)
            case .saveProfileRules:
                break
            }
        }
    }
}

 
 
 
private struct RulesPreparationKey: Equatable {
    let sourceYAML: String?
    let canInspectActiveRules: Bool
    let wantsJumpableTargets: Bool
     
     
    let compileVerdicts: ProviderCompileVerdicts
}

 
 
private struct PreparedRules {
    let token: UUID
    let snapshot: AppleClientSnapshot
    let search: RulesCatalogSession?
}

 
@MainActor
private enum RulesOverviewPreparationCache {
    static let shared = ClashLastPreparation<RulesPreparationKey, PreparedRules>()
}

 
 
 
 
final class RulesCatalogSession: @unchecked Sendable {
    let source: RulesOverviewModel.CatalogSource
    private let lock = NSLock()
    private var catalog: PublishedRules.Catalog?

    init(_ source: RulesOverviewModel.CatalogSource) {
        self.source = source
    }

    deinit { catalog?.close() }

     
     
    func search(_ query: String, limit: Int = 100) -> ClashRulesSearchResult? {
        lock.lock()
        defer { lock.unlock() }
        if catalog == nil {
            switch source {
            case .publication(let text): catalog = try? PublishedRules.open(publishedText: text)
            case .file(let url): catalog = try? PublishedRules.open(sourceAt: url)
            case .textFile(let file): catalog = try? PublishedRules.open(sourceAt: file.url)
            }
        }
        guard let catalog, let page = try? catalog.page(offset: 0, limit: limit, query: query) else { return nil }
        let rules = page.rules.map { entry -> ClashRuleLineSnapshot in
            let rule = ParsedRule(raw: entry.rule)
            return ClashRuleLineSnapshot(raw: rule.raw, type: rule.type, payload: rule.payload, target: rule.target)
        }
        return ClashRulesSearchResult(rules: rules, total: page.matched)
    }
}

 
 
 
 
 
enum RulesOverviewSnapshotBuilder {
     
     
     
    static func build(
        sourceYAML: String?,
        canInspectActiveRules: Bool,
        wantsJumpableTargets: Bool,
         
         
         
         
         
        compileVerdicts: ProviderCompileVerdicts = ProviderCompileVerdicts(),
         
         
         
        countEntries: ((RuleEntryCounts.Key) -> Int?)? = nil
    ) -> AppleClientSnapshot {
        prepare(sourceYAML: sourceYAML, canInspectActiveRules: canInspectActiveRules,
                wantsJumpableTargets: wantsJumpableTargets, compileVerdicts: compileVerdicts,
                countEntries: countEntries).snapshot
    }

     
     
    static func prepare(
        sourceYAML: String?,
        canInspectActiveRules: Bool,
        wantsJumpableTargets: Bool,
        compileVerdicts: ProviderCompileVerdicts = ProviderCompileVerdicts(),
        countEntries: ((RuleEntryCounts.Key) -> Int?)? = nil
    ) -> (snapshot: AppleClientSnapshot, catalogSource: RulesOverviewModel.CatalogSource?) {
         
         
        let model = RulesOverviewModel.make(sourceYAML: sourceYAML, sampling: ClashRuleBucketSnapshot.pageRowCap)
        var counts = RuleEntryCounts(count: countEntries)
        let ruleSetCounts = compileVerdicts.entryCounts
        let sharedRule = { (rule: ParsedRule) in
            Self.sharedRule(rule, counts: &counts, ruleSetCounts: ruleSetCounts)
        }
        let jumpable: Set<String>
        if wantsJumpableTargets {
            let knownGroups = Set(
                ProxiesOverviewModel.make(sourceYAML: sourceYAML)
                    .groups
                    .map(\.name)
            )
            jumpable = RulesOverviewModel.jumpableTargets(
                buckets: model.buckets,
                fallback: model.fallback,
                knownGroups: knownGroups
            )
        } else {
            jumpable = []
        }
        let snapshot = AppleClientSnapshot(
            revision: 0,
            connection: AppleClientConnectionSnapshot(
                phase: .unavailable
            ),
            rules: ClashRulesSnapshot(
                overview: ClashRulesOverviewSnapshot(
                    inlineCount: model.inlineCount,
                    inapplicableCount: model.inapplicableCount,
                    platformTitle: model.platformTitle,
                    buckets: model.buckets.map {
                        ClashRuleBucketSnapshot(
                            target: $0.target,
                            rules: $0.rules.map(sharedRule),
                            canOpenProxiesGroup:
                                jumpable.contains($0.target),
                            ruleCount: $0.count
                        )
                    },
                    ruleSets: model.ruleSets.map { set in
                        ClashRuleSetSnapshot(
                            name: set.name,
                            detail: compiledDetail(
                                set, verdicts: compileVerdicts
                            ),
                            blockedReason: compileVerdicts.blockedReason(
                                ruleProvider: set.name
                            ),
                            entryCount: compileVerdicts.entryCounts[set.name]
                        )
                    },
                    fallback: model.fallback.map(sharedRule),
                     
                     
                     
                    searchableRules: model.allRules.map(sharedRule),
                    jumpableTargets: jumpable,
                    rulesAreCounted: model.rulesAreCounted
                ),
                canInspectActiveRules: canInspectActiveRules
            ),
            capabilities: AppleClientCapabilities([
                .rules: .available,
            ])
        )
        return (snapshot, model.catalogSource)
    }

     
     
    private static func compiledDetail(
        _ set: RulesOverviewModel.RuleSet,
        verdicts: ProviderCompileVerdicts
    ) -> String {
        guard case .compiled(let compiled?)? = verdicts.ruleProviders[set.name],
              !set.behavior.isEmpty,
              compiled != set.behavior
        else { return set.detail }
        return set.detail + " → " + compiled
    }

    private static func sharedRule(
        _ rule: ParsedRule,
        counts: inout RuleEntryCounts,
        ruleSetCounts: [String: Int]
    ) -> ClashRuleLineSnapshot {
         
         
        let entryCount = rule.typeUppercased == "RULE-SET"
            ? ruleSetCounts[rule.payload]
            : counts.entries(of: rule)
        return ClashRuleLineSnapshot(
            raw: rule.raw,
            type: rule.type,
            payload: rule.payload,
            target: rule.target,
            entryCount: entryCount
        )
    }
}

 
 
 
 
 
struct RuleEntryCounts {
    enum Kind: Hashable {
        case geoIP
        case geoSite
        case asn
    }

    struct Key: Hashable {
        let kind: Kind
        let value: String
    }

    private let count: ((Key) -> Int?)?
    private var answered: [Key: Int?] = [:]

    init(count: ((Key) -> Int?)?) {
        self.count = count
    }

    static func key(of rule: ParsedRule) -> Key? {
        let kind: Kind
        switch rule.typeUppercased {
        case "GEOIP", "SRC-GEOIP": kind = .geoIP
        case "GEOSITE": kind = .geoSite
        case "IP-ASN", "SRC-IP-ASN": kind = .asn
        default: return nil
        }
        let value = rule.payload.lowercased()
        return value.isEmpty ? nil : Key(kind: kind, value: value)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    static func app(sourceYAML: String?) -> (Key) -> Int? {
         
         
         
         
        let geodataMode = sourceYAML.flatMap { yaml -> Bool? in
            if yaml.utf8.count > NodesInventoryProjection.wholeReadBytes {
                return (try? ConfigTransforms.foundationRoot(ofYAML: yaml, omitting: ConfigTransforms.nodesAndRules))??["geodata-mode"] as? Bool
            }
            return ConfigTransforms.parsedRoot(forYAML: yaml)?.root["geodata-mode"] as? Bool
        } == true
        return { key in
             
             
             
             
            guard AppCoreSetup.ensureForReaders() else { return nil }
            switch key.kind {
            case .geoIP:
                return geodataMode ? ClashGeoIPDatEntryCount(key.value) : ClashGeoIPNetworkCount(key.value)
            case .geoSite:
                return ClashGeoSiteDomainCount(key.value)
            case .asn:
                return ClashASNNetworkCount(key.value)
            }
        }
    }

    mutating func entries(of rule: ParsedRule) -> Int? {
        guard let count, let key = Self.key(of: rule) else { return nil }
        if let known = answered[key] { return known }
        let answer = count(key).flatMap { $0 >= 0 ? $0 : nil }
        answered[key] = answer
        return answer
    }
}

struct ParsedRule: Equatable {
    let raw: String
    let type: String
    let payload: String
    let target: String

     
     
    let typeUppercased: String

    init(raw: String) {
        self.raw = raw
         
         
         
         
         
         
         
         
         
        var fields: [Substring] = []
        fields.reserveCapacity(4)
        let utf8 = raw.utf8
        var start = utf8.startIndex
        var index = start
        while index < utf8.endIndex {
            if utf8[index] == 0x2C {
                fields.append(Self.trimmed(raw[start..<index]))
                start = utf8.index(after: index)
            }
            index = utf8.index(after: index)
        }
        fields.append(Self.trimmed(raw[start..<utf8.endIndex]))

        type = String(fields[0])
        typeUppercased = type.uppercased()
         
         
         
         
         
         
        if typeUppercased == "MATCH" {
             
            target = fields.count > 1 ? String(fields[1]) : ""
            payload = ""
        } else if ClashStructuredRule.headsWhosePayloadConsumesRemainingFields.contains(typeUppercased) {
             
            target = fields.count > 1 ? String(fields[fields.count - 1]) : ""
            payload = fields.count > 2 ? fields[1..<(fields.count - 1)].joined(separator: ",") : ""
        } else {
             
             
             
             
            payload = fields.count > 1 ? String(fields[1]) : ""
            target = fields.count > 2 ? String(fields[2]) : ""
        }
    }

    private static func trimmed(_ part: Substring) -> Substring {
        let bytes = part.utf8
        guard let first = bytes.firstIndex(where: { $0 != 0x20 && $0 != 0x09 }),
              let last = bytes.lastIndex(where: { $0 != 0x20 && $0 != 0x09 })
        else { return part[part.startIndex..<part.startIndex] }
        return part[first...last]
    }
}

struct RulesOverviewModel {
    struct Bucket: Identifiable {
        var id: String { target }
        let target: String
        let rules: [ParsedRule]
         
         
        var count: Int

        init(target: String, rules: [ParsedRule], count: Int? = nil) {
            self.target = target
            self.rules = rules
            self.count = count ?? rules.count
        }
    }

    struct RuleSet: Identifiable {
        var id: String { name }
        let name: String
        let detail: String
         
         
         
        var behavior: String = ""
    }

    let inlineCount: Int
    let inapplicableCount: Int
     
     
     
    let platformTitle: String
    let buckets: [Bucket]
    let ruleSets: [RuleSet]
    let fallback: [ParsedRule]
    let allRules: [ParsedRule]

    func search(_ query: String) -> [ParsedRule] {
        allRules.filter {
            $0.raw.localizedCaseInsensitiveContains(query)
        }
    }

    static func jumpableTargets(
        buckets: [Bucket],
        fallback: [ParsedRule],
        knownGroups: Set<String>
    ) -> Set<String> {
        Set(buckets.map(\.target) + fallback.map(\.target))
            .intersection(knownGroups)
    }

     
     
     
     
     
    var fingerprint: String {
        "\(inlineCount)|\(inapplicableCount)|\(fallback.count)|\(ruleSets.count)|"
            + buckets.map { "\($0.target)=\($0.count)" }.joined(separator: ",")
            + "|" + fallback.map(\.target).joined(separator: ",")
    }

     
     
     
    nonisolated(unsafe) static var listedRulesAtMost = 20_000

     
     
    enum CatalogSource: Equatable, Sendable {
         
         
        case publication(String)
         
        case file(URL)
         
         
        case textFile(RulesInTextFile)
    }

     
     
     
     
     
    final class RulesInTextFile: Equatable, Sendable {
        let url: URL

        init(url: URL) { self.url = url }

        deinit { try? FileManager.default.removeItem(at: url) }

        static func == (lhs: RulesInTextFile, rhs: RulesInTextFile) -> Bool { lhs.url == rhs.url }
    }

     
     
     
    private static let rulesInTextDirectory: URL = {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rules-in-text", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        return directory
    }()

     
     
     
    var catalogSource: CatalogSource? = nil

     
     
     
    var rulesAreCounted = false

     
     
     
    static func make(
        sourceYAML: String?,
        runtimeProfile: ClashAppleRuntimeProfile =
            clashAppleRuntimeProfile,
        sampling: Int = 0
    ) -> RulesOverviewModel {
        guard let yaml = sourceYAML else {
            return build(root: nil, runtimeProfile: runtimeProfile)
        }
         
         
         
         
        if ConfigTransforms.ruleIndexPath(in: yaml) != nil {
            return published(yaml, runtimeProfile: runtimeProfile, sampling: sampling)
        }
         
         
        if let source = PagesRuleSource.url(in: yaml) {
            return leftInSource(yaml, at: source, runtimeProfile: runtimeProfile, sampling: sampling)
        }
         
         
        if ConfigTransforms.hasLargeRuleSection(yaml),
           let counted = countedInText(yaml, runtimeProfile: runtimeProfile, sampling: sampling) {
            return counted
        }
         
         
         
        let text = yaml.utf8.count > NodesInventoryProjection.wholeReadBytes
            ? ConfigurationSections.droppingLong(["proxies"], from: yaml) ?? yaml : yaml
        guard let parsed = ConfigTransforms.parsedRoot(forYAML: text) else {
            return build(root: nil, runtimeProfile: runtimeProfile)
        }
         
         
        let key = "rules.overview|"
            + runtimeProfile.unavailableRuleActionNames.sorted().joined(separator: ",")
        return parsed.memo(key) { build(root: parsed.root, runtimeProfile: runtimeProfile) }
    }

     
     
     
     
     
    static func writtenCount(ofRulesElsewhere yaml: String) -> Int? {
        if ConfigTransforms.ruleIndexPath(in: yaml) != nil {
            return PublishedRules.summary(ofPublishedText: yaml)?.written
        }
        guard let source = PagesRuleSource.url(in: yaml),
              let catalog = try? PublishedRules.open(sourceAt: source) else { return nil }
        defer { catalog.close() }
        let own = (rootWithoutNodes(yaml)?["rules"] as? [Any])?.count ?? 0
        return catalog.total + own
    }

     
     
     
     
     
    private static func published(_ yaml: String, runtimeProfile: ClashAppleRuntimeProfile,
                                  sampling: Int = 0) -> RulesOverviewModel {
        let root = ConfigTransforms.parsedRoot(forYAML: yaml)?.root
        guard let catalog = try? PublishedRules.open(publishedText: yaml), let summary = try? catalog.summary() else {
            return build(root: root, runtimeProfile: runtimeProfile)
        }
        defer { catalog.close() }
        let removed = summary.uidRemoved ?? 0
        if let lines = try? catalog.lines(most: listedRulesAtMost) {
            var withRules = root ?? [:]
            withRules["rules"] = lines
            return build(root: withRules, runtimeProfile: runtimeProfile).counting(removed: removed)
        }
        return counted(catalog, summary: summary, root: root, ownRules: [], removed: removed,
                       runtimeProfile: runtimeProfile, sampling: sampling, source: .publication(yaml))
    }

     
     
     
     
    private static func leftInSource(_ yaml: String, at source: URL, runtimeProfile: ClashAppleRuntimeProfile,
                                     sampling: Int) -> RulesOverviewModel {
        let root = rootWithoutNodes(yaml)
        guard let catalog = try? PublishedRules.open(sourceAt: source), let summary = try? catalog.summary() else {
            return build(root: root, runtimeProfile: runtimeProfile)
        }
        defer { catalog.close() }
        let own = ((root?["rules"] as? [Any]) ?? []).compactMap { $0 as? String }.map(ParsedRule.init(raw:))
        return counted(catalog, summary: summary, root: root, ownRules: own, removed: 0,
                       runtimeProfile: runtimeProfile, sampling: sampling, source: .file(source))
    }

     
     
     
     
     
    private static func countedInText(_ yaml: String, runtimeProfile: ClashAppleRuntimeProfile,
                                      sampling: Int) -> RulesOverviewModel? {
        let directory = rulesInTextDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
         
        let file = RulesInTextFile(url: directory.appendingPathComponent("\(UUID().uuidString).yaml"))
        guard (try? ConfigTransforms.writeNewFile(yaml, to: file.url)) != nil,
              let catalog = try? PublishedRules.open(sourceAt: file.url), let summary = try? catalog.summary() else {
            return nil
        }
        defer { catalog.close() }
        let rest = TopLevelYAMLSections.cutting(["rules"], from: yaml)?.rest
        return counted(catalog, summary: summary, root: rest.flatMap(rootWithoutNodes), ownRules: [], removed: 0,
                       runtimeProfile: runtimeProfile, sampling: sampling, source: .textFile(file))
    }

     
     
     
    nonisolated(unsafe) static var setAsideRulesAtMost = 10_000

     
     
     
     
     
     
     
     
    private static func counted(_ catalog: PublishedRules.Catalog, summary: PublishedRules.Summary,
                                root: [String: Any]?, ownRules: [ParsedRule], removed: Int,
                                runtimeProfile: ClashAppleRuntimeProfile, sampling: Int,
                                source: CatalogSource?) -> RulesOverviewModel {
        let unavailable = runtimeProfile.unavailableRuleActionNames
         
         
        func setAside(_ rule: ParsedRule) -> Bool {
            rule.typeUppercased == "MATCH"
                || (unavailable.contains(rule.typeUppercased) && RuleEffect.of(rule.raw) != .matchesEverything)
        }
        var byTarget = summary.byTarget
        var inapplicable = removed
        var fallback: [ParsedRule] = []
        let types = summary.byType.keys.filter { $0.uppercased() == "MATCH" || unavailable.contains($0.uppercased()) }
        let asideEntries = types.isEmpty ? [] : ((try? catalog.rules(ofTypes: types.sorted(), most: setAsideRulesAtMost)) ?? [])
        for entry in asideEntries {
            let rule = ParsedRule(raw: entry.rule)
            guard setAside(rule) else { continue }
            byTarget[entry.target, default: 0] -= 1
            if rule.typeUppercased == "MATCH" { fallback.append(rule) } else { inapplicable += 1 }
        }
        var ownByTarget: [String: [ParsedRule]] = [:]
        for rule in ownRules {
            if rule.typeUppercased == "MATCH" {
                fallback.append(rule)
            } else if setAside(rule) {
                inapplicable += 1
            } else if !rule.target.isEmpty {
                 
                 
                byTarget[rule.target, default: 0] += 1
                ownByTarget[rule.target, default: []].append(rule)
            }
        }
        let buckets = byTarget.filter { $0.value > 0 }
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .map { target, count -> Bucket in
                guard sampling > 0 else { return Bucket(target: target, rules: [], count: count) }
                 
                 
                let read = (try? catalog.page(offset: 0, limit: min(sampling + 32, PublishedRules.pageLimit),
                                              target: target))?.rules ?? []
                let first = read.map { ParsedRule(raw: $0.rule) }.filter { !setAside($0) }
                return Bucket(target: target, rules: Array((first + (ownByTarget[target] ?? [])).prefix(sampling)),
                              count: count)
            }
        var model = RulesOverviewModel(
            inlineCount: summary.written + ownRules.count,
            inapplicableCount: inapplicable,
            platformTitle: runtimeProfile.platformTitle,
            buckets: buckets,
            ruleSets: ruleSets(of: root),
            fallback: fallback,
            allRules: []
        )
        model.catalogSource = source
        model.rulesAreCounted = true
        return model
    }

     
     
    private func counting(removed: Int) -> RulesOverviewModel {
        guard removed > 0 else { return self }
        var model = RulesOverviewModel(inlineCount: inlineCount + removed, inapplicableCount: inapplicableCount + removed,
                                       platformTitle: platformTitle, buckets: buckets, ruleSets: ruleSets,
                                       fallback: fallback, allRules: allRules)
        model.catalogSource = catalogSource
        model.rulesAreCounted = rulesAreCounted
        return model
    }

     
    private static func rootWithoutNodes(_ yaml: String) -> [String: Any]? {
        let text = yaml.utf8.count > NodesInventoryProjection.wholeReadBytes
            ? ConfigurationSections.droppingLong(["proxies"], from: yaml) ?? yaml : yaml
        return ConfigTransforms.parsedRoot(forYAML: text)?.root
    }

    private static func ruleSets(of root: [String: Any]?) -> [RuleSet] {
         
        guard let providers = (root?["rule-providers"] as? [String: Any]).map(ModuleRuleSetSyntax.readersOwn) else { return [] }
        return providers.keys.sorted().map { name in
            let spec = providers[name] as? [String: Any]
            let behavior = (spec?["behavior"] as? String) ?? ""
            let type = (spec?["type"] as? String) ?? ""
            return RuleSet(name: name, detail: [type, behavior].filter { !$0.isEmpty }.joined(separator: " · "),
                           behavior: behavior.lowercased())
        }
    }

    private static func build(
        root: [String: Any]?,
        runtimeProfile: ClashAppleRuntimeProfile
    ) -> RulesOverviewModel {
        var parsed: [ParsedRule] = []
        var sets: [RuleSet] = []
        if let root {
            parsed = ((root["rules"] as? [Any]) ?? [])
                .compactMap { $0 as? String }
                .map(ParsedRule.init(raw:))
            if let providers =
                (root["rule-providers"] as? [String: Any]).map(ModuleRuleSetSyntax.readersOwn)
            {
                sets = providers.keys.sorted().map { name in
                    let spec =
                        providers[name] as? [String: Any]
                    let behavior =
                        (spec?["behavior"] as? String) ?? ""
                    let type =
                        (spec?["type"] as? String) ?? ""
                    return RuleSet(
                        name: name,
                        detail: [type, behavior]
                            .filter { !$0.isEmpty }
                            .joined(separator: " · "),
                        behavior: behavior.lowercased()
                    )
                }
            }
        }
        let applicable = parsed.filter { rule in
             
             
             
            guard runtimeProfile.unavailableRuleActionNames
                .contains(rule.typeUppercased)
            else { return true }
             
             
             
             
             
             
             
            return RuleEffect.of(rule.raw) == .matchesEverything
        }
         
         
         
         
        let fallbackRules = applicable.filter {
            $0.typeUppercased == "MATCH"
        }
         
         
         
        let bucketable = applicable.filter {
            $0.typeUppercased != "MATCH" && !$0.target.isEmpty
        }
        let grouped = Dictionary(
            grouping: bucketable,
            by: \.target
        )
        let buckets = grouped
            .map { Bucket(target: $0.key, rules: $0.value) }
            .sorted {
                ($0.rules.count, $1.target)
                    > ($1.rules.count, $0.target)
            }
        return RulesOverviewModel(
            inlineCount: parsed.count,
            inapplicableCount:
                parsed.count - applicable.count,
            platformTitle: runtimeProfile.platformTitle,
            buckets: buckets,
            ruleSets: sets,
            fallback: fallbackRules,
            allRules: parsed
        )
    }
}


 
 
 
 
 
 
 
 
 
enum PagesRuleSource {
    static let key = "x-clash-rules-in-source"

     
    static func marking(_ document: String, rulesAt url: URL) -> String {
        var marked = document
        if marked.trimmingCharacters(in: .whitespacesAndNewlines) == "{}" { marked = "" }
        if !marked.isEmpty, !marked.hasSuffix("\n") { marked += "\n" }
        return marked + key + ": '" + url.path.replacingOccurrences(of: "'", with: "''") + "'\n"
    }

     
     
    static func url(in text: String) -> URL? {
        let tail = String(decoding: text.utf8.suffix(8_192), as: UTF8.self)
        guard let line = tail.split(separator: "\n").last, line.hasPrefix(key + ": '"), line.hasSuffix("'") else {
            return nil
        }
        let quoted = line.dropFirst(key.count + 3).dropLast()
        return URL(fileURLWithPath: quoted.replacingOccurrences(of: "''", with: "'"))
    }

     
     
     
    static func sourceLeavingLargeRules(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: [.alwaysMapped]),
              data.count >= ConfigTransforms.ruleSectionCutFromBytes else { return nil }
        return data.withUnsafeBytes { raw -> String? in
            let bytes = raw.bindMemory(to: UInt8.self)
            guard let range = TopLevelYAMLSections.sectionRange("rules", inBytes: bytes),
                  range.count >= ConfigTransforms.ruleSectionCutFromBytes,
                  RuleLines.isOneRuleALine(UnsafeBufferPointer(rebasing: bytes[range])) else { return nil }
            var rest = [UInt8]()
            rest.reserveCapacity(bytes.count - range.count)
            rest.append(contentsOf: bytes[..<range.lowerBound])
            rest.append(contentsOf: bytes[range.upperBound...])
            return String(decoding: rest, as: UTF8.self)
        }
    }
}
