import ClashClientUI
import Foundation
import SwiftUI

 
 
 
 
struct HomeCustomizationEditModePresenter: View {
    let content: AnyView

#if !os(macOS)
    @State private var editMode: EditMode = .active
#endif

    var body: some View {
#if os(macOS)
        content
#else
        content.environment(\.editMode, $editMode)
#endif
    }
}

 
 
 
 
struct ProfileConfigTally: Equatable {
    let proxies: Int
    let proxyGroups: Int
    let rules: Int
    let proxyProviders: Int
    let ruleProviders: Int
    let subRules: Int
    let groupNames: [String]
    let ruleProviderNames: [String]

     
     
     
     
     
     
     
     
     
     
     
    func awaitingRunningCount(shownBefore: ProfileConfigTally?) -> ProfileConfigTally {
        counting(proxies: shownBefore?.proxies ?? proxies)
    }

     
     
     
    func leavingOutTheEngine(of publication: ActiveConfigurationPointer?,
                             locations: ModuleLocations? = ModuleLocations.production) -> ProfileConfigTally {
        counting(proxies: max(0, proxies - ModuleRouteHiding.enginesAmongNodes(of: publication, locations: locations)))
    }

    func counting(proxies: Int) -> ProfileConfigTally {
        ProfileConfigTally(
            proxies: proxies, proxyGroups: proxyGroups, rules: rules, proxyProviders: proxyProviders,
            ruleProviders: ruleProviders, subRules: subRules, groupNames: groupNames,
            ruleProviderNames: ruleProviderNames
        )
    }

     
     
     
    static func make(sourceYAML: String?, tunnelRunning: Bool = true, rulesCounted: Int? = nil) -> ProfileConfigTally? {
        guard var yaml = sourceYAML else { return nil }
         
         
        let rulesElsewhere = rulesCounted ?? RulesOverviewModel.writtenCount(ofRulesElsewhere: yaml)
         
         
         
        var counted: [String: Int] = [:]
        if yaml.utf8.count > NodesInventoryProjection.wholeReadBytes,
           let reduced = ConfigurationSections.droppingLongCounting(["proxies", "rules"], from: yaml) {
            yaml = reduced.text
            counted = reduced.counts
        }
        guard let root = ConfigTransforms.parsedRoot(forYAML: yaml)?.root else { return nil }

        let groups = (root["proxy-groups"] as? [[String: Any]]) ?? []
         
         
         
         
         
        let listedGroupCount = groups.filter { !ProxiesOverviewModel.isHiddenFlag($0["hidden"]) }.count
         
        let ruleProviders =
            ModuleRuleSetSyntax.readersOwn((root["rule-providers"] as? [String: Any]) ?? [:])
        return ProfileConfigTally(
            proxies: counted["proxies"] ?? (root["proxies"] as? [Any])?.count ?? 0,
             
             
             
             
             
             
            proxyGroups: listedGroupCount
                + (tunnelRunning && !groups.contains { $0["name"] as? String == "GLOBAL" }
                    ? 1 : 0),
            rules: rulesElsewhere ?? counted["rules"] ?? (root["rules"] as? [Any])?.count ?? 0,
            proxyProviders:
                (root["proxy-providers"] as? [String: Any])?.count ?? 0,
            ruleProviders: ruleProviders.count,
            subRules: (root["sub-rules"] as? [String: Any])?.count ?? 0,
            groupNames: groups.compactMap { $0["name"] as? String },
            ruleProviderNames: ruleProviders.keys.sorted()
        )
    }
}

 
 
 
 
 
 
 
 
@MainActor
final class HomeTallyCache {
    struct Key: Equatable {
        let profileID: String
        let refreshToken: Int
    }

    struct Entry {
        let tally: ProfileConfigTally?
        let rulesOverview: RulesOverviewModel?
        let subscriptionNodeTally: Int?
        var notDownloadedProxyProviders = 0
        let resourceCounts: HomeResourceCounts?
    }

    static let shared = HomeTallyCache()

    private var key: Key?
    private var entry: Entry?

    func entry(for key: Key) -> Entry? {
        self.key == key ? entry : nil
    }

    func store(_ entry: Entry, for key: Key) {
        self.key = key
        self.entry = entry
    }

    func reset() {
        key = nil
        entry = nil
    }
}

struct HomeConnectionIssueView: View {
     
     
     
     
     
     
     
     
     
     
    enum Action: Equatable {
         
         
         
        case viewLogs
        case resetVPNProfile
    }

    static func actions(allowsSystemVPNProfileReset: Bool) -> [Action] {
        var actions: [Action] = [.viewLogs]
        if allowsSystemVPNProfileReset { actions.append(.resetVPNProfile) }
        return actions
    }

    let issue: HomeConnectionIssue
    @ObservedObject var vpn: VPNController
     
     
     
    var openLogs: () -> Void = {}
     
     
    var startupExplanation: ClashStartupExplanation?
     
     
    var geoNameCount: Int?
     
    var billLines: [MemoryBillSection.Line] = []
     
    var ruleSetItems: [MemoryTrimManageView.Item] = []
     
     
    var trimSpec: MemoryTrimSpec = MemoryTrimSpec()
    var onSaveTrim: (MemoryTrimSpec) -> Void = { _ in }
     
     
     
     
    var dnsPolicyKeys: [(String, Int64?)] = []
    var dnsFilterEntries: [(String, Int64?)] = []
    var geoSiteItems: [(String, Int64?)] = []
    var geoIPItems: [(String, Int64?)] = []
     
    var providerLoadRows: [ProviderLoadDetailView.Row] = []
    @State private var managesRuleSets = false
    @State private var managesDNS = false
    @State private var managesGeo = false
    @State private var showsProviderLoad = false
     
     
    var coreLog: [String] = []
     
     
     
     
    var refusalReason: ConfigurationRefusalReason?
    var strippedNotices: [String] = []
     
     
    var unreadableRuleSets: [ProvidersModel.Row] = []
     
     
     
    var modulesListener: ModuleActivationRecord? = nil
     
     
     
    var onDemandNote: String?
     
    var openOnDemand: () -> Void = {}

    @Environment(\.locale) private var locale

     
     
     
     
     
     
    @StateObject private var dismiss = ClashDismissHandle()
    @State private var confirmsVPNProfileReset = false
     
    @State private var wantsLogsOnDismiss = false
     
    @State private var wantsOnDemandOnDismiss = false
    @State private var feedback: ClashFeedbackPresentation?

    var body: some View {
        ClashFeatureNavigationContainer {
            content
        }
        .confirmationDialog(
            "Reset VPN Profile?",
            isPresented: $confirmsVPNProfileReset,
            titleVisibility: .visible
        ) {
            Button(
                "Reset VPN Profile",
                role: .destructive
            ) {
                resetVPNProfile()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This removes and recreates only Clash’s VPN entry in Settings."
            )
        }
         
         
#if os(iOS)
        .clashFeedbackOverlay(
            $feedback,
            dismissTitle: "Done"
        )
#endif
        .clashSheet(isPresented: $managesRuleSets) {
            ClashFeatureNavigationContainer {
                MemoryTrimManageView(
                    items: ruleSetItems,
                    dropped: Set(trimSpec.droppedRuleProviders)
                ) { dropped in
                    var spec = trimSpec
                    spec.droppedRuleProviders = dropped.sorted()
                    onSaveTrim(spec)
                    dismiss()
                }
            }
            .clashModalPresentation(.page)
        }
        .clashSheet(isPresented: $managesDNS) {
            ClashFeatureNavigationContainer {
                DNSTrimManageView(
                    policyKeys: dnsPolicyKeys,
                    filterEntries: dnsFilterEntries,
                    droppedKeys: Set(trimSpec.droppedDNSPolicyKeys),
                    droppedEntries: Set(trimSpec.droppedFakeIPFilterEntries)
                ) { keys, entries in
                    var spec = trimSpec
                    spec.droppedDNSPolicyKeys = keys.sorted()
                    spec.droppedFakeIPFilterEntries = entries.sorted()
                    onSaveTrim(spec)
                    dismiss()
                }
            }
            .clashModalPresentation(.page)
        }
        .clashSheet(isPresented: $managesGeo) {
            ClashFeatureNavigationContainer {
                GeoTrimManageView(
                    siteItems: geoSiteItems,
                    ipItems: geoIPItems,
                    droppedSites: Set(trimSpec.droppedGeoSiteRules),
                    droppedIPs: Set(trimSpec.droppedGeoIPRules)
                ) { sites, ips in
                    var spec = trimSpec
                    spec.droppedGeoSiteRules = sites.sorted()
                    spec.droppedGeoIPRules = ips.sorted()
                    onSaveTrim(spec)
                    dismiss()
                }
            }
            .clashModalPresentation(.page)
        }
        .clashSheet(isPresented: $showsProviderLoad) {
            ClashFeatureNavigationContainer {
                ProviderLoadDetailView(rows: providerLoadRows)
            }
            .clashModalPresentation(.page)
        }
        .onDisappear {
             
             
             
            if wantsOnDemandOnDismiss {
                wantsOnDemandOnDismiss = false
                openOnDemand()
                return
            }
            guard wantsLogsOnDismiss else { return }
            wantsLogsOnDismiss = false
            openLogs()
        }
        .clashCapturesDismiss(dismiss)
    }

     
     
     
     
     
     
     
    private var content: some View {
        List {
             
             
            Section {
                if let refusalReason {
                     
                     
                    VStack(alignment: .leading, spacing: 4) {
                        Text(clash: refusalReason.summary)
                            .font(.subheadline)
                            .accessibilityIdentifier("connection.issue.reason")
                        Text(clash: issue.text)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(
                        clash: startupExplanation?.detail
                            ?? issue.text
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("connection.issue.reason")
                }

                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                if let wayOut = startupExplanation?.wayOut(named: geoNameCount) {
                    Text(clash: wayOut)
                        .font(.subheadline)
                        .accessibilityIdentifier("connection.issue.way-out")
                }
            }

             
             
             
             
            if let onDemandNote {
                Section {
                    Text(verbatim: onDemandNote)
                        .font(.subheadline)
                        .accessibilityIdentifier("connection.issue.on-demand")
                    Button {
                        wantsOnDemandOnDismiss = true
                        dismiss()
                    } label: {
                        Label("Open On Demand", systemImage: ClashMoreDestination.onDemand.symbol.name)
                            .font(.subheadline)
                    }
                    .accessibilityIdentifier("connection.issue.open-on-demand")
                }
            }


            if !billLines.isEmpty {
                MemoryBillSection(lines: billLines) { id in
                    switch id {
                    case "rule-sets": managesRuleSets = true
                    case "dns": managesDNS = true
                    case "geo": managesGeo = true
                    case "providers": showsProviderLoad = true
                    default: break
                    }
                }
                .accessibilityIdentifier("connection.issue.bill")
            }

             
             
             
             
            if startupExplanation != nil, !unreadableRuleSets.isEmpty {
                Section("Not In Effect") {
                    ForEach(unreadableRuleSets) { row in
                        VStack(
                            alignment: .leading,
                            spacing: ClashTheme.Spacing.tight
                        ) {
                            Text(clash: .verbatim(row.name))
                                .font(.subheadline.weight(.medium))
                             
                             
                            if let note = row.note {
                                Text(clash: note.displayText(locale: locale))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .accessibilityIdentifier(
                            "connection.issue.unreadable.\(row.name)"
                        )
                    }
                }
            }

             
             
            if !coreLog.isEmpty {
                if !strippedNotices.isEmpty {
                Section {
                    ForEach(strippedNotices, id: \.self) { notice in
                        Text(clash: .verbatim(notice))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                         
                         
                        if let note = ModuleListenerNotice.note(for: notice, record: modulesListener) {
                            Text(clash: note.displayText)
                                .font(.caption)
                        }
                    }
                } header: {
                    Text(clash: .copy("What the Core Said This Run"))
                } footer: {
                    Text(clash: .copy("The core's own notices, verbatim: what it removed, what it kept but cannot match, and anything it wants you to know about who can reach this device."))
                }
            }

            Section("Core Log") {
                    ForEach(Array(coreLog.enumerated()), id: \.offset) {
                        _, line in
                        Text(clash: .verbatim(line))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        if let note = ModuleListenerNotice.note(for: line, record: modulesListener) {
                            Text(clash: note.displayText)
                                .font(.caption)
                        }
                    }
                    Button {
                        wantsLogsOnDismiss = true
                        dismiss()
                    } label: {
                        Label(
                            "Open Full Log",
                            systemImage: ClashSymbol.docText.name
                        )
                        .font(.subheadline)
                    }
                    .accessibilityIdentifier("connection.issue.logs")
                }
                .accessibilityIdentifier("connection.issue.core-log")
            }

             
             
            if issue.allowsSystemVPNProfileReset {
                Section {
                    Button(role: .destructive) {
                        confirmsVPNProfileReset = true
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reset VPN Profile")
                            Text(
                                "Recreates Clash’s VPN entry in Settings. Your Clash profiles, profile URLs, and credentials stay unchanged."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("connection.issue.reset")
                }
            }
        }
         
         
         
        .navigationTitle(
            issue.kind == .runningPreviousRevision
                ? Text("Not Applied")
                : Text("Can’t Connect")
        )
        .clashToolbarUnlessInPanel {
            ToolbarItem(placement: .cancellationAction) {
                ClashSheetCloseButton { dismiss() }
            }
        }
    }

    private func resetVPNProfile() {
        feedback = .loading(
            title: "Resetting VPN Profile",
            accessibilityIdentifier: "connection.issue.reset.loading"
        )
        Task { @MainActor in
            if await vpn.resetSystemVPNProfile() {
                feedback = .success(
                    title: "VPN Profile Reset",
                    message: "Clash’s VPN profile is ready. Connect when you are ready.",
                    accessibilityIdentifier:
                        "connection.issue.reset.success"
                )
                try? await Task.sleep(nanoseconds: 900_000_000)
                feedback = nil
                dismiss()
            } else {
                feedback = .error(
                    title: "Reset Failed",
                    message: .verbatim(vpn.reportableLastError),
                    accessibilityIdentifier:
                        "connection.issue.reset.failure"
                )
            }
        }
    }
}

 
 
 
 
 
struct ClashFeatureNavigationContainer<Content: View>: View {
    let ownsNavigationContainer: Bool
    private let content: Content

    init(
        ownsNavigationContainer: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.ownsNavigationContainer = ownsNavigationContainer
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        ClashSingleColumnNavigationContainer(
            ownsNavigationContainer: ownsNavigationContainer
        ) {
            content
        }
    }
}

extension View {
     
     
     
     
     
     
     
     
     
     
    @ViewBuilder
    func clashPageSizedSheet() -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            self.presentationSizing(.page)
        } else {
            self
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func clashSheetPresentation() -> some View {
        clashOwnsProductCanvas()
            .clashInlineSheetTitle()
            .clashModalPresentation(.page)
    }

    @ViewBuilder
    func clashFeaturePresentation(
        ownsNavigationContainer: Bool
    ) -> some View {
        if ownsNavigationContainer {
            clashSheetPresentation()
        } else {
            self
        }
    }

     
     
     
     
     
     
     
     
     
    @ViewBuilder
    fileprivate func clashInlineSheetTitle() -> some View {
#if os(macOS)
        self
#else
        if #available(iOS 17.0, *) {
            self.toolbarTitleDisplayMode(.inline)
        } else {
            self.navigationBarTitleDisplayMode(.inline)
        }
#endif
    }

}
