import Foundation
import ClashClientUI
import SwiftUI

 
struct RulePolicyOptions {
    let groups: [(name: String, type: String)]
    let proxies: [(name: String, type: String)]
    var ruleSets: [String]
     
     
    var hiddenGroups: Set<String> = []
     
     
     
     
    var domainRuleSets: [String] = []
     
    var subRuleNames: [String]? = nil
     
     
     
    var ruleSetsAreKnown = false

    static let empty = RulePolicyOptions(
        groups: [],
        proxies: [],
        ruleSets: []
    )

    static func make(sourceYAML: String?) -> RulePolicyOptions {
        let proxiesModel = ProxiesOverviewModel.make(
            sourceYAML: sourceYAML
        )
        let rulesModel = RulesOverviewModel.make(
            sourceYAML: sourceYAML
        )
        return RulePolicyOptions(
            groups: proxiesModel.groups.map {
                ($0.name, $0.type)
            },
            proxies: proxiesModel.proxies.map {
                ($0.name, $0.type)
            },
            ruleSets: rulesModel.ruleSets.map(\.name),
            hiddenGroups: Set(proxiesModel.groups.filter(\.hidden).map(\.name)),
            domainRuleSets: rulesModel.ruleSets
                .filter { $0.behavior != "ipcidr" }
                .map(\.name),
            subRuleNames: subRuleBranchNames(in: sourceYAML)
             
             
        )
    }

     
     
     
    func adopting(published: ClashClientUI.ClashRulePolicyOptions?) -> RulePolicyOptions {
        guard let published, published.ruleSetsAreKnown else { return self }
        var options = self
        options.ruleSets = published.ruleSets
        options.ruleSetsAreKnown = true
        return options
    }

     
     
     
     
     
     
    func including(customGroups: [CustomProxyGroup]) -> RulePolicyOptions {
        let known = Set(groups.map(\.name))
        let fresh = customGroups
            .filter { !$0.name.isEmpty && !known.contains($0.name) }
            .map { (name: $0.name, type: $0.type) }
        guard !fresh.isEmpty else { return self }
        return RulePolicyOptions(
            groups: groups + fresh,
            proxies: proxies,
            ruleSets: ruleSets,
            hiddenGroups: hiddenGroups,
            domainRuleSets: domainRuleSets,
            subRuleNames: subRuleNames,
            ruleSetsAreKnown: ruleSetsAreKnown
        )
    }

     
     
     
    private static func subRuleBranchNames(in yaml: String?) -> [String]? {
        guard let yaml,
              let json = try? ConfigTransforms.yamlToJSON(yaml),
              let root = try? JSONSerialization.jsonObject(
                with: Data(json.utf8)
              ) as? [String: Any],
              let subRules = root["sub-rules"] as? [String: Any] else {
            return nil
        }
        return Array(subRules.keys)
    }

    var shared: ClashRulePolicyOptions {
        ClashRulePolicyOptions(
            groups: groups.map {
                ClashRulePolicySnapshot(
                    name: $0.name,
                    type: $0.type,
                    isHidden: hiddenGroups.contains($0.name)
                )
            },
            proxies: proxies.map {
                ClashRulePolicySnapshot(
                    name: $0.name,
                    type: $0.type
                )
            },
            ruleSets: ruleSets,
            subRuleNames: subRuleNames,
            ruleSetsAreKnown: ruleSetsAreKnown
        )
    }
}

typealias RuleTargetVerdict = ClashRuleTargetVerdict

extension RulePolicyOptions {
     
     
     
    init(shared: ClashRulePolicyOptions) {
        self.init(
            groups: shared.groups.map { ($0.name, $0.type) },
            proxies: shared.proxies.map { ($0.name, $0.type) },
            ruleSets: shared.ruleSets,
            hiddenGroups: Set(shared.groups.filter(\.isHidden).map(\.name)),
            subRuleNames: shared.subRuleNames,
            ruleSetsAreKnown: shared.ruleSetsAreKnown
        )
    }
}

extension RulePolicyOptions {
    static let builtinPolicies =
        ClashRulePolicyOptions.builtinPolicies

    func verdict(forTarget target: String) -> RuleTargetVerdict {
        shared.verdict(forTarget: target)
    }

    func flagsUnknownTarget(
        of rule: StructuredRule
    ) -> Bool {
        shared.flagsUnknownTarget(of: rule)
    }
}

 
 
 
struct RuleBuilderAdapter: View {
    private let delete: (() -> Void)?
    private let showsPersonalMetadata: Bool
    private let showsTarget: Bool
    private let createGroup: ((@escaping (String?) -> Void) -> AnyView)?
    private let pageTitle: String
    private let raw: String
    private let options: RulePolicyOptions
    private let enabled: Bool
    private let comment: String
    private let saveDetails:
        ((_ raw: String, _ enabled: Bool, _ comment: String) -> Void)?
    private let save: (String) -> Void
     
     
    private let draftKey: String?

    init(
        raw: String,
        options: RulePolicyOptions = .empty,
        showsPersonalMetadata: Bool = true,
        showsTarget: Bool = true,
        createGroup: ((@escaping (String?) -> Void) -> AnyView)? = nil,
        delete: (() -> Void)? = nil,
        enabled: Bool = true,
        comment: String = "",
        pageTitle: String = "Rule",
        saveDetails: (
            (_ raw: String, _ enabled: Bool, _ comment: String) -> Void
        )? = nil,
        draftKey: String? = nil,
        save: @escaping (String) -> Void
    ) {
        self.draftKey = draftKey
        self.pageTitle = pageTitle
        self.delete = delete
        self.showsPersonalMetadata = showsPersonalMetadata
        self.showsTarget = showsTarget
        self.createGroup = createGroup
        self.raw = raw
        self.options = options
        self.enabled = enabled
        self.comment = comment
        self.saveDetails = saveDetails
        self.save = save
    }

    var body: some View {
        ClashClientUI.ClashRuleEditorView(
            rule: ClashPersonalRuleSnapshot(
                raw: raw,
                isEnabled: enabled,
                comment: comment.isEmpty ? nil : comment
            ),
            options: options.shared,
            showsPersonalMetadata: showsPersonalMetadata,
            showsTarget: showsTarget,
            createGroup: createGroup,
            delete: delete,
            initialRoute: initialRoute,
            pageTitle: pageTitle,
            runtimeProfile: clashAppleRuntimeProfile,
            palette: ClashClientUI.ClashProductPalette.clashProduct,
            draftStore: draftKey == nil ? nil : SourceEditDrafts.shared,
            draftKey: draftKey,
            loadGeoValues: { resource in
                await GeoCategoryCache.shared.categories(
                    for:
                        resource == .geoIP
                            ? .geoip
                            : .geosite
                )
            },
            icon: { symbol in
                ClashSymbolImage(symbol: symbol)
            }
        ) { updated in
            if let saveDetails {
                saveDetails(
                    updated.raw,
                    updated.isEnabled,
                    updated.comment ?? ""
                )
            } else {
                save(updated.raw)
            }
        }
    }

    private var initialRoute: ClashRuleBuilderRoute? {

        return nil

    }
}

 
 
struct GeoValuePickerView: View {
    let resource: GeoResource
    let localizeRegions: Bool
    let title: String
    let current: String
    let pick: (String) -> Void

     
     
     
     
     
     
    @StateObject private var dismiss = ClashDismissHandle()
    @State private var query = ""
    @State private var values: [String] = []
    @State private var loaded = false

    private func regionName(_ code: String) -> String? {
        guard localizeRegions, code.count == 2 else {
            return nil
        }
        return Locale.current.localizedString(
            forRegionCode: code.uppercased()
        )
    }

    private var filtered: [String] {
        guard !query.isEmpty else { return values }
        return values.filter {
            $0.localizedCaseInsensitiveContains(query)
                || (
                    regionName($0)?
                        .localizedCaseInsensitiveContains(query)
                        ?? false
                )
        }
    }

    var body: some View {
        Group {
            if !loaded {
                ProgressView()
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )
                    .accessibilityIdentifier("rule-geo.loading")
            } else {
                List(filtered, id: \.self) { value in
                    Button {
                        pick(value)
                        dismiss()
                    } label: {
                        HStack(spacing: ClashTheme.Spacing.row) {
                            Text(
                                localizeRegions
                                    && value.count == 2
                                    ? value.uppercased()
                                    : value
                            )
                            if let name = regionName(value) {
                                Text(name)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            if value == current {
                                ClashSymbolImage(
                                    symbol: .checkmark
                                )
                                .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(
                        "rule-geo.\(value)"
                    )
                }
                .searchable(
                    text: $query,
                    prompt: Text("Search code or name")
                )
            }
        }
        .clashPageTitle(.copy(title))
        .task {
            guard !loaded else { return }
            values = await GeoCategoryCache.shared.categories(
                for: resource
            )
            loaded = true
        }
        .clashCapturesDismiss(dismiss)
    }
}

 
struct RuleSetPickerView: View {
    let sets: [String]
    let current: String
    let pick: (String) -> Void

     
    @StateObject private var dismiss = ClashDismissHandle()

    var body: some View {
        List(sets, id: \.self) { name in
            Button {
                pick(name)
                dismiss()
            } label: {
                HStack {
                    Text(name)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    if name == current {
                        ClashSymbolImage(symbol: .checkmark)
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .clashPageTitle("Rule Sets")
        .clashCapturesDismiss(dismiss)
    }
}
