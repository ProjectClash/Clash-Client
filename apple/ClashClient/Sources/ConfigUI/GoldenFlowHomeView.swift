import Combine
import SwiftUI
import Clash
import ClashClientKit
import ClashClientUI

 
 
 
 
 
 
 
private struct DirectGlobalQuestion {
    let profileID: String
    let previousMode: Profile.OutboundMode
    let exit: ClashTunnelOutboundMode.GlobalExit
}

private struct OutboundModeRefusal {
    let title: String
     
     
     
    let message: ClashDisplayText
     
     
     
    var offersNodeChoice: Bool = false

    static func saveFailed(
        mode: Profile.OutboundMode,
        error: Error
    ) -> OutboundModeRefusal {
        OutboundModeRefusal(
            title: "Mode Not Changed",
             
             
             
             
            message: .format(saveFailedRow(mode), [error.localizedDescription])
        )
    }

    private static func saveFailedRow(_ mode: Profile.OutboundMode) -> String {
        switch mode {
        case .global: return "Global mode could not be saved to this profile: %@"
        case .rule: return "Rule mode could not be saved to this profile: %@"
        case .direct: return "Direct mode could not be saved to this profile: %@"
        }
    }
}

 
 
 
 
 
private struct RuntimeConfigurationPresentation {
    let profileID: String
    let snapshot: ProfileFinalConfigurationSnapshot
    let sourceYAML: String?
    let comparisonYAML: String?
    let baseYAML: String?
    let includesBlockedRuleSets: Bool
}

 
 
private struct PreparedProxiesPresentation {
    let profileID: String
    let sourceModel: ProxiesOverviewModel
}

 
 
 
 
 
struct GoldenFlowHomeAdapter: View {
     
     
     
     
    @State private var startupExplanation: ClashStartupExplanation?
     
     
     
     
     
     
    @StateObject private var trafficFeedOwner: HomeTrafficFeedOwner
     
     
     
     
     
     
     
     
     
     
    @State private var unreadableRuleSets: [ProvidersModel.Row] = []
     
    @State private var billLines: [MemoryBillSection.Line] = []
     
    @State private var ruleSetItems: [MemoryTrimManageView.Item] = []
     
    @State private var providerLoadRows: [ProviderLoadDetailView.Row] = []
     
     
     
    @State private var dnsPolicyItems: [(String, Int64?)] = []
    @State private var dnsFilterItems: [(String, Int64?)] = []
    @State private var geoSiteItems: [(String, Int64?)] = []
    @State private var geoIPItems: [(String, Int64?)] = []
    @State private var failureCensusRunning = false
     
     
    @State private var failureCensusGeneration: UInt64 = 0
     
     
     
     
     
    @State private var coreLog: [String] = []
    @State private var strippedNotices: [String] = []
     
     
    @State private var modulesListener: ModuleActivationRecord?
     
     
     
     
     
     
     
    @State private var geoNameCount: Int?
     
    @State private var geoNameCountGeneration: UInt64 = 0
     
     
     
     
     
     
     
    @State private var activationShownInFlight = false
     
     
    @State private var activationShownWait = 0
    private static let activationShownAfter: UInt64 = 350_000_000
     
     
     
     
    @StateObject private var startupOutcome = StartupOutcomeWatcher()

    @Environment(\.locale)
    private var locale
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.clashShellLayout) private var shellLayout

    @ObservedObject var vpn: VPNController
    @ObservedObject var command: ClashCommandClient
    @ObservedObject var nodes: NodesModel
    @ObservedObject var stats: StatsModel
    let profileRefreshToken: Int
     
     
    @Binding var pendingSessionPage: ClashClientUI.ClashRootDestination?
    @Binding var pendingOutboundMode: String?
     
     
     
    let presentationRecovery: LostPresentationRecovery
     
     
     
    let openThroughDoor: (_ door: String, _ open: @escaping @MainActor () -> Void) -> Void
     
    let openProfiles: () -> Void
    let openProxies: () -> Void
     
     
     
    let openProxiesToChooseInGlobal: () -> Void
    let openRules: () -> Void
    let openActiveRules: () -> Void
     
    let openOnDemand: () -> Void
     
     
    let openLogs: () -> Void
    let openDNSQuery: () -> Void
    let rebind: () -> Void

     
     
     
     
     
     
    @ObservedObject private var profiles: ProfilesViewModel


    @State private var favoriteCards =
        HomeFavoriteCardPreferences().load()
     
     
    @AppStorage(ClashHomeOutboundModeStyle.storageKey)
    private var homeLayout: ClashHomeOutboundModeStyle = .spacious
    @State private var trafficOnlyProxy =
        TrafficStatisticsSettings.onlyProxy()
    @State private var lanAddress: String?
    @State private var editorDestination: HomeProfileEditorDestination?
    @State private var runtimeConfigurationProfile: Profile?
    @State private var runtimeConfigurationPresentation:
        RuntimeConfigurationPresentation?
    @State private var runtimeConfigurationPreparationGeneration: UInt64 = 0
    @State private var presentedConnectionIssue: HomeConnectionIssue?
     
     
     
     
    @State private var presentedHomeSnapshot: AppleClientSnapshot?
    @State private var configTally: ProfileConfigTally?
    @State private var tallyGeneration: UInt64 = 0
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    @State private var resourceCounts: HomeResourceCounts?
    @State private var rulesOverview: RulesOverviewModel?
    @State private var configuredMode: Profile.OutboundMode = .rule
     
     
     
    @State private var modeRefusal: OutboundModeRefusal?
    @State private var pendingProxiesGroup: String?
     
     
     
    @State private var proxiesOpening: ProxyBrowsingVisibility.Opening = .browsing
     
     
     
     
    @State private var directGlobalQuestion: DirectGlobalQuestion?
     
     
     
    @Binding private var sessionPresentation:
        ClashClientUI.ClashRootDestination?
    @State private var proxiesPreparationGeneration: UInt64 = 0
     
    private struct ProxiesPreparationKey: Hashable {
        let generation: UInt64
        let overrides: ProxyNodeOverrideSpec?
    }
    @State private var preparedProxiesPresentation:
        PreparedProxiesPresentation?

    init(
        vpn: VPNController,
        command: ClashCommandClient,
        nodes: NodesModel,
        stats: StatsModel,
        profiles: ProfilesViewModel,
        profileRefreshToken: Int,
        pendingSessionPage:
            Binding<ClashClientUI.ClashRootDestination?> = .constant(nil),
        sessionPresentation:
            Binding<ClashClientUI.ClashRootDestination?> = .constant(nil),
        pendingOutboundMode: Binding<String?> = .constant(nil),
        presentationRecovery: LostPresentationRecovery,
        openThroughDoor: @escaping (_ door: String, _ open: @escaping @MainActor () -> Void) -> Void,
        openProfiles: @escaping () -> Void,
        openProxies: @escaping () -> Void,
        openProxiesToChooseInGlobal: @escaping () -> Void,
        openRules: @escaping () -> Void,
        openActiveRules: @escaping () -> Void,
        openOnDemand: @escaping () -> Void,
        openLogs: @escaping () -> Void,
        openDNSQuery: @escaping () -> Void,
        rebind: @escaping () -> Void
    ) {
        self.vpn = vpn
        self.command = command
        _trafficFeedOwner = StateObject(wrappedValue: HomeTrafficFeedOwner(traffic: Self.cardTraffic(command.traffic)))
        self.nodes = nodes
        self.stats = stats
        self.profileRefreshToken = profileRefreshToken
        _pendingSessionPage = pendingSessionPage
        _sessionPresentation = sessionPresentation
        _pendingOutboundMode = pendingOutboundMode
        self.presentationRecovery = presentationRecovery
        self.openThroughDoor = openThroughDoor
        self.openProfiles = openProfiles
        self.openProxies = openProxies
        self.openProxiesToChooseInGlobal = openProxiesToChooseInGlobal
        self.openRules = openRules
        self.openActiveRules = openActiveRules
        self.openOnDemand = openOnDemand
        self.openLogs = openLogs
        self.openDNSQuery = openDNSQuery
        self.rebind = rebind
        self.profiles = profiles
    }

    var body: some View {


        let homeSnapshot = presentedHomeSnapshot ?? sharedSnapshot
        ClashClientUI.ClashHomeView(
            snapshot: homeSnapshot,
            actions: sharedActions,
            presentationClass: shellLayout == .regularSidebar
                ? .regularTouch
                : .compactTouch,
            palette: ClashClientUI.ClashProductPalette.clashProduct,
            customizationPresentation: { content in
                AnyView(HomeCustomizationEditModePresenter(content: content))
            },
             
             
            clearedLostPresentation: { [presentationRecovery] in
                presentationRecovery.noteDroppedByTheDoor(["cardCustomization"])
            }
        ) { symbol in
            ClashSymbolImage(symbol: symbol)
        }
        .equatable()
        .environment(\.clashTrafficFeed, trafficFeedOwner.feed)
        .onReceive(command.$traffic) { traffic in
             
             
            guard presentedHomeSnapshot == nil else { return }
            trafficFeedOwner.update(Self.cardTraffic(traffic))
        }
         
         
        .environment(\.clashHomeIssueOpensAccount, true)


         
         
        .onAppear { presentationRecovery.register(home: homeClaims) }
        .task(id: profileRefreshToken) {
            profiles.load()
            recomputeConfiguredMode()
            recomputeTally()
            startupOutcome.refresh()
             
             
             
             
             
             
            if command.isConnected,
               nodes.runtimeProviderCatalog.proxyProviders.isEmpty {
                await nodes.refresh()
            }
        }
         
         
         
         
        .onChange(of: command.isConnected) { _ in
            recomputeTally()
            startupOutcome.refresh()
        }
        .onChange(of: homeLayout) { _ in
            command.applyTrafficStatisticsPreference()
        }
         
         
         
         
        .onChange(of: command.nodeSummary?.nodes) { _ in
            recomputeTally()
        }
        .onChange(of: profiles.savedConfigurationGeneration) { _ in
            recomputeTally()
            startupOutcome.refresh()
            if !command.isConnected { Task { await nodes.refresh() } }
        }
         
         
        .onAppear { activationShownInFlight = profiles.isAwaitedActivationInFlight }
        .onChange(of: profiles.isAwaitedActivationInFlight) { inFlight in
            activationShownWait += 1
            guard inFlight else {
                activationShownInFlight = false
                return
            }
            let wait = activationShownWait
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: Self.activationShownAfter)
                if activationShownWait == wait, profiles.isAwaitedActivationInFlight {
                    activationShownInFlight = true
                }
            }
        }
        .onChange(of: editorDestination?.id) { destination in
            if destination == nil {
                presentedHomeSnapshot = nil
                trafficFeedOwner.update(Self.cardTraffic(command.traffic))
                startupOutcome.refresh()
                recomputeTally()
                pendingProxiesGroup = nil
                proxiesOpening = .browsing
                proxiesPreparationGeneration &+= 1
                preparedProxiesPresentation = nil
            } else if presentedHomeSnapshot == nil {
                presentedHomeSnapshot = homeSnapshot
            }
            switch editorDestination {
            case .proxiesOverview: sessionPresentation = .proxies
            case .rulesOverview: sessionPresentation = .rules
            default: sessionPresentation = nil
            }
        }
         
         
         
         
         
         
         
         
         
         
         
         
         
        .task(id: pendingSessionPage) {
            guard let page = pendingSessionPage else { return }
            pendingSessionPage = nil
            switch page {
            case .proxies: presentProxiesSheet(.browsing, group: nil)
            case .rules: presentRulesOverview()
            default: break
            }
        }
         
         
         
         
         
        .task(id: pendingOutboundMode) {
            guard let raw = pendingOutboundMode else { return }
            setOutboundMode(raw)
            pendingOutboundMode = nil
        }
        .onChange(of: currentProfile?.id) { _ in
            recomputeConfiguredMode()
        }
        .onChange(of: command.mode) { mode in
             
             
             
            recomputeConfiguredMode()
             
             
            proxiesOpening = ProxyBrowsingVisibility.opening(
                proxiesOpening, after: .modeChanged(.init(coreValue: mode)))
            guard command.isConnected,
                  mode.caseInsensitiveCompare("global") == .orderedSame else {
                return
            }
            Task {
                await enforceConnectedGlobalMode()
            }
        }
        .clashProductModal(
            item: $editorDestination,
            role: .page
        ) { destination in
             
             
             
            ClashLazyView(defersOneTurn: true) {
                editorSheet(destination)
            }
                .clashPageSizedSheet()
                 
                 
                .onAppear { ClashPushClock.arrived() }
        }
        .clashSheet(
            item: $runtimeConfigurationProfile,
            onDismiss: {
                runtimeConfigurationPreparationGeneration &+= 1
                runtimeConfigurationPresentation = nil
            }
        ) { profile in
            if let presentation = runtimeConfigurationPresentation,
               presentation.profileID == profile.id {
                ProfileFinalConfigurationView(
                    title: "Runtime Configuration",
                    snapshot: presentation.snapshot,
                    sourceYAML: presentation.sourceYAML,
                    comparisonYAML: presentation.comparisonYAML,
                    baseYAML: presentation.baseYAML,
                    command: command,
                     
                     
                     
                     
                    blockedRuleSets: presentation.includesBlockedRuleSets
                        ? {
                            guard let container =
                                ClashAppIdentifiers.appGroupContainer else {
                                return []
                            }
                            let coreHome =
                                container.appendingPathComponent("working")
                            return ProviderCompileVerdicts
                                .load(coreHome: coreHome)
                                .blockedRuleProviders
                        }
                        : nil,
                     
                     
                    textFirst: true
                )
                .clashModalPresentation(.page)
            } else {
                HomePreparationPlaceholder(
                    title: "Runtime Configuration",
                    accessibilityIdentifier: "final.preparing"
                )
                .task(id: runtimeConfigurationPreparationGeneration) {
                    await prepareRuntimeConfiguration(
                        for: profile,
                        generation: runtimeConfigurationPreparationGeneration
                    )
                }
                .clashModalPresentation(.page)
            }
        }
        .task {
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
            guard Self.isStoppedStatus(vpn.status), vpn.lastStartFailed
            else { return }
            startupExplanation = command.readStartupExplanation()
            rebuildFailureCaptureIfNeeded()
        }
        .onChange(of: vpn.status) { status in
             
             
             
             
             
             
             
             
             
             
            if Self.startRetiresStartupExplanation(status) {
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                command.clearStartupExplanation()
                guard presentedConnectionIssue == nil else { return }
                startupExplanation = nil
                unreadableRuleSets = []
                geoNameCount = nil
                coreLog = []
            strippedNotices = []
            modulesListener = nil
                billLines = []
                ruleSetItems = []
                providerLoadRows = []
                clearFailureCensus()
                return
            }
            guard Self.isStoppedStatus(status) else { return }
             
             
             
             
             
             
             
            guard vpn.lastStartFailed else {
                command.clearStartupExplanation()
                startupExplanation = nil
                unreadableRuleSets = []
                geoNameCount = nil
                coreLog = []
                strippedNotices = []
                modulesListener = nil
                billLines = []
                ruleSetItems = []
                providerLoadRows = []
                clearFailureCensus()
                return
            }
            startupExplanation = command.readStartupExplanation()
            if vpn.consumeUserInitiatedStop() {
                 
                 
                 
                 
                command.clearStartupExplanation()
                startupExplanation = nil
                unreadableRuleSets = []
                geoNameCount = nil
                coreLog = []
                strippedNotices = []
                modulesListener = nil
                billLines = []
                ruleSetItems = []
                providerLoadRows = []
                clearFailureCensus()
                return
            }
            rebuildFailureCaptureIfNeeded()
        }
        .clashSheet(item: $presentedConnectionIssue) { issue in
             
             
             
            connectionIssueSheet(issue)
                .clashModalPresentation(.form)
        }
        .alert(
            LocalizedStringKey(modeRefusal?.title ?? ""),
            isPresented: Binding(
                get: { modeRefusal != nil },
                set: { if !$0 { modeRefusal = nil } }
            ),
            presenting: modeRefusal
        ) { refusal in
            if refusal.offersNodeChoice {
                Button("Choose Node") { openGlobalToChooseANode() }
            }
            Button("OK", role: .cancel) {}
        } message: { refusal in
            Text(clash: refusal.message)
        }
         
         
         
        .alert(
            "Switch to Global Mode?",
            isPresented: Binding(
                get: { directGlobalQuestion != nil },
                set: { if !$0 { directGlobalQuestion = nil } }
            ),
            presenting: directGlobalQuestion
        ) { question in
            Button("Choose Node") { openGlobalToChooseANode() }
            Button("Switch Anyway") { switchToGlobalOverDirect(question) }
            Button("Cancel", role: .cancel) {}
        } message: { question in
            Text(clash: .copy(ClashTunnelOutboundMode.questionKey(question.exit)))
        }
        .onChange(of: nodes.replaysEndedOnGlobalWithoutAProxy) { _ in
             
             
             
            guard command.isConnected else { return }
            Task { await enforceConnectedGlobalMode() }
        }
        .onChange(of: favoriteCards) { cards in
            HomeFavoriteCardPreferences().save(cards)
        }
    }

    @ViewBuilder
    private func editorSheet(
        _ destination: HomeProfileEditorDestination
    ) -> some View {
        switch destination {
        case .rulesOverview(let profile):
             
             
             
             
            let live = profiles.profiles.first { $0.id == profile.id } ?? profile
            RulesOverviewHost(
                command: command,
                canInspectActiveRules: command.isConnected,
                profiles: profiles,
                profile: live,
                openProxiesGroup: { group in
                    pendingProxiesGroup = group
                    proxiesOpening = .browsing
                    presentProxiesOverview(for: profile)
                }
            )
        case .proxiesOverview(let profile):
             
             
             
             
            let live = profiles.profiles.first { $0.id == profile.id } ?? profile
            Group {
                if let preparedProxiesPresentation,
                   preparedProxiesPresentation.profileID == live.id {
                    ProxiesOverviewHost(
                        vpn: vpn,
                        command: command,
                        nodes: nodes,
                        profiles: profiles,
                        isConnected: command.isConnected,
                        mode: command.mode,
                        profile: live,
                         
                         
                        sourceModel: preparedProxiesPresentation.sourceModel
                            .applying(selectedMap: live.selectedMap),
                         
                         
                         
                         
                         
                         
                        initiallyExpandedGroup: HomeProxiesEntryPolicy.homeEntry(
                            pending: pendingProxiesGroup,
                            lastOpened: nodes.currentGroupName,
                            groups: preparedProxiesPresentation.sourceModel.groups,
                            name: \.name,
                            isHidden: \.hidden,
                            coreMode: command.mode,
                             
                             
                            liveCatalog: command.isConnected && nodes.isRuntimeAvailable,
                            readerFoldedAll: nodes.readerFoldedAllGroups,
                            opening: proxiesOpening
                        ),
                        opening: proxiesOpening
                    )
                } else {
                    HomePreparationPlaceholder(
                        title: "Proxies",
                        accessibilityIdentifier: "proxies.preparing"
                    )
                }
            }
             
             
             
             
             
             
             
             
            .onReceive(NotificationCenter.default.publisher(for: ProviderDownloadActivity.didChangeNotification)) { _ in
                proxiesPreparationGeneration &+= 1
            }
            .task(id: ProxiesPreparationKey(
                generation: proxiesPreparationGeneration,
                overrides: live.proxyNodeOverrides
            )) {
                await prepareProxiesOverview(
                    for: live,
                    generation: proxiesPreparationGeneration
                )
            }
        case .onDemand:
            HomeOnDemandPage(vpn: vpn)
        }
    }

    private var currentProfile: Profile? {
        HomeProfileResolution.workingProfile(in: profiles)
    }

     
     
     
     
     
     
     
     
     
     
     
     
    private var namedRoute: HomeNamedRoute.Route {
        HomeNamedRoute.route(
            mode: configuredMode, groups: nodes.groups, delays: nodes.delays,
            terminals: nodes.resolvedNowByGroup, groupsAreTheCores: nodes.groupsAreTheCores,
            finalRuleTarget: HomeNamedRoute.finalRuleTarget(of: rulesOverview)
        )
    }

    @ViewBuilder
    private func connectionIssueSheet(
        _ issue: ClashHomeConnectionIssue
    ) -> some View {
        HomeConnectionIssueView(
            issue: issue,
            vpn: vpn,
            openLogs: openLogs,
            startupExplanation: startupExplanation,
            geoNameCount: geoNameCount,
            billLines: billLines,
            ruleSetItems: ruleSetItems,
            trimSpec: currentProfile?.memoryTrim ?? MemoryTrimSpec(),
            onSaveTrim: { spec in saveTrimAndRetry(spec) },
             
            dnsPolicyKeys: dnsPolicyItems,
            dnsFilterEntries: dnsFilterItems,
            geoSiteItems: geoSiteItems,
            geoIPItems: geoIPItems,
            providerLoadRows: providerLoadRows,
             
             
            coreLog: issue.kind == .runningPreviousRevision
                ? [startupOutcome.record?.message].compactMap { $0 }
                : coreLog,
             
             
            refusalReason: issue.kind == .runningPreviousRevision
                ? startupOutcome.record?.message.map(ConfigurationRefusalReason.reading)
                : nil,
            strippedNotices: strippedNotices,
            unreadableRuleSets: unreadableRuleSets,
            modulesListener: modulesListener,
             
             
            onDemandNote: vpn.onDemandNoteForTheReasonSheet(locale: locale),
            openOnDemand: { throughDoor("home.connection-issue.on-demand") { openOnDemandPage() } }
        )
        .onDisappear {
             
             
             
            guard issue.kind == .startupStopped else { return }
            command.clearStartupExplanation()
            startupExplanation = nil
            geoNameCount = nil
            coreLog = []
            strippedNotices = []
            modulesListener = nil
            billLines = []
            ruleSetItems = []
            providerLoadRows = []
            clearFailureCensus()
             
             
             
             
             
            unreadableRuleSets = []
        }
    }

    private func saveTrimAndRetry(_ spec: MemoryTrimSpec) {
        guard var profile = currentProfile else { return }
        profile.memoryTrim = spec.isEmpty ? nil : spec
        profiles.saveMemoryTrim(profile)
        Task {
            guard await profiles.selectAndWait(profile) else { return }
            await vpn.start(origin: .programmatic)
            rebind()
        }
    }

     
     
     
    static func memoryBill(
        ruleSetCensusCount: Int? = nil,
        ruleSetCensusBytes: Int64? = nil,
        dnsCensusCount: Int? = nil,
        providerCensusCount: Int? = nil,
        geoCensusCount: Int? = nil,
        geoCensusBytes: Int64? = nil
    ) -> [MemoryBillSection.Line] {
        guard let container = ClashAppIdentifiers.appGroupContainer,
              let text = try? String(
                  contentsOf: container.appendingPathComponent(
                      MemorySampleLog.startupPhaseFileName
                  ),
                  encoding: .utf8
              )
        else { return [] }
        let ledger = ClashMemoryLedger.lastRun(
            from: text.split(separator: "\n").map(String.init)
        )
        let lines = MemoryBillSection.lines(
            ledger: ledger,
            pressureFootprintBytes: CoreMemoryPressure.observed()?
                .footprintBytes,
            ruleSetCensusCount: ruleSetCensusCount,
            ruleSetCensusBytes: ruleSetCensusBytes,
            dnsCensusCount: dnsCensusCount,
            providerCensusCount: providerCensusCount,
            geoCensusCount: geoCensusCount,
            geoCensusBytes: geoCensusBytes
        )
        return lines
    }

     
     
    private func clearFailureCensus() {
        failureCensusGeneration &+= 1
        dnsPolicyItems = []
        dnsFilterItems = []
        geoSiteItems = []
        geoIPItems = []
    }

     
     
     
     
     
     
    private func rebuildFailureCaptureIfNeeded() {
        guard billLines.isEmpty, !failureCensusRunning else { return }
        unreadableRuleSets = Self.unreadableRuleSets()
        geoNameCount = nil
        refreshGeoNameCount(for: startupExplanation)
        coreLog = CoreLogExcerpt.recent()
        strippedNotices = CoreLogExcerpt.strippedThisRun()
         
        modulesListener = ModuleActivationRecord.load(
            locations: .production,
            publishedAs: startupOutcome.record?.requested.map {
                ActiveConfigurationPointer(profileID: $0.profileID, revision: $0.revision)
            })
         
         
         
         
        failureCensusRunning = true
        let generation = failureCensusGeneration
        let profile = currentProfile
        let groups = configTally?.groupNames ?? []
         
         
         
         
        var estimates: [String: Int64] = [:]
        for (name, rp) in nodes.runtimeProviderCatalog.ruleProviders
            where rp.behavior?.lowercased() == "domain" && rp.ruleCount > 0
        {
            estimates[name] = Int64(rp.ruleCount) * 84
        }
        Task { @MainActor in
            defer { failureCensusRunning = false }
            var source: String?
            if let profile { source = await profiles.loadSourceYAML(for: profile) }
            let reading = await Task.detached(priority: .userInitiated) { [source, estimates] in
                HomeFailureCensus.reading(source: source, trim: profile?.memoryTrim, groups: groups, estimates: estimates)
            }.value
            guard generation == failureCensusGeneration, billLines.isEmpty else { return }
            ruleSetItems = reading.ruleSetItems
            providerLoadRows = reading.providerRows
            dnsPolicyItems = reading.dnsPolicy
            dnsFilterItems = reading.dnsFilter
            geoSiteItems = reading.geoSite
            geoIPItems = reading.geoIP
            billLines = Self.memoryBill(
                ruleSetCensusCount: reading.ruleSetItems.count,
                ruleSetCensusBytes: reading.ruleSetItems
                    .compactMap(\.measuredBytes).reduce(0, +),
                dnsCensusCount: reading.dnsPolicy.count + reading.dnsFilter.count,
                providerCensusCount: reading.providerRows.count,
                geoCensusCount: reading.geoSite.count + reading.geoIP.count,
                geoCensusBytes: (reading.geoSite + reading.geoIP)
                    .compactMap(\.1).reduce(0, +)
            )
        }
    }

     
     
     
     
     
    static func unreadableRuleSets() -> [ProvidersModel.Row] {
        guard let container = ClashAppIdentifiers.appGroupContainer,
              let store = try? ConfigResourceStore(containerURL: container),
              let providers = try? store.activeProvidersDirectory()
        else { return [] }
        return ProvidersModel.unreadableRuleSets(providersDir: providers)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private func refreshGeoNameCount(for explanation: ClashStartupExplanation?) {
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        let resource = explanation?.resource ?? ""
        let isGeoSite = resource.hasPrefix("geosite:")
        geoNameCountGeneration &+= 1
        guard explanation != nil,
              resource.isEmpty || resource.hasPrefix("geoip:") || isGeoSite,
              let profile = currentProfile
        else { return }
         
         
         
         
        let generation = geoNameCountGeneration
        Task { @MainActor in
            guard let yaml = await profiles.previewTextOffTheMainActor(for: profile), !yaml.isEmpty else { return }
            let count = await Task.detached(priority: .utility) {
                Self.countGeoNames(in: yaml, geoSite: isGeoSite)
            }.value
            guard generation == geoNameCountGeneration, startupExplanation != nil else { return }
            geoNameCount = count
        }
    }

     
     
     
     
     
    nonisolated private static func countGeoNames(in yaml: String, geoSite: Bool) -> Int? {
        let lines = (geoSite ? AppCore.geoSiteCategoryLines(yaml) : AppCore.geoIPCountryLines(yaml))
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        ClashLogStore.shared.append(
            "geo count: \(lines.count) \(geoSite ? "categories" : "countries") named",
            stream: .app
        )
        return lines.isEmpty ? nil : lines.count
    }

     
     
    static func isStoppedStatus(_ status: String) -> Bool {
        ["disconnected", "invalid", "unknown"].contains(
            Self.normalizedStatus(status)
        )
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func startRetiresStartupExplanation(_ status: String) -> Bool {
        Self.normalizedStatus(status) == "connected"
    }

     
     
     
     
     
     
     
     
     
     
     
    static func stopMayBeExplained(
        status: String,
        lastStartFailed: Bool
    ) -> Bool {
        isStoppedStatus(status) && lastStartFailed
    }

    private static func normalizedStatus(_ status: String) -> String {
        status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

     
     
     
     
     
    private var connectionErrorMessage: String {
         
         
        let live = vpn.homeLastErrorRow
        guard let startupExplanation else { return live }
         
         
         
         
         
         
         
         
         
         
         
        guard live.isEmpty || VPNDisconnectErrorPresentation
            .isProviderStoppedUnexpectedly(live)
        else { return live }
        return ClashCopy.string(for: startupExplanation.summary, locale: locale)
    }

     
     
     
     
    static func errorSubject(for line: String, refusal: CoreStartRefusal?) -> String? {
        guard let refusal, line == refusal.message else { return nil }
        return refusal.words
    }

    private var presentation: HomeConnectionPresentation {
        let route = namedRoute
        let line = connectionErrorMessage
        return HomeConnectionPresenter.presentation(
            for: HomeConnectionFacts(
                activeProfileName: currentProfile.map { ProfileRowPresentation.label(for: $0, locale: .current) },
                vpnStatus: homeVPNStatus,
                errorMessage: line,
                vpnAuthorization: vpn.systemVPNAuthorization,
                errorIsStartupStopped: vpn.lastError.isEmpty
                    && startupExplanation != nil,
                errorIsProviderNotLaunched: VPNDisconnectErrorPresentation
                    .isProviderNotLaunched(vpn.homeLastErrorRow),
                 
                 
                 
                 
                errorOnDemandRuleNames: vpn.startRefusedByOnDemand?.isCertain == true
                    ? vpn.onDemandRuleNames(locale: locale) : nil,
                 
                errorSubject: Self.errorSubject(for: line, refusal: vpn.startRefusedByCore),
                allowsSystemVPNProfileReset:
                    vpn.systemVPNProfileResetAvailable,
                isSwitchingProxy: nodes.isSwitchingProxy,
                recoveryMode: .none,
                mode: configuredMode.rawValue,
                 
                selectedProxyName: configuredMode == .global ? route.node : nil,
                selectedProxyDelayMilliseconds:
                    configuredMode == .global ? route.delay : nil,
                runningPreviousRevision: startupOutcome.record?.homeShowsPreviousRevision(vpnStatus: vpn.status) ?? false,
                runningPreviousProfileName: startupOutcome.record?.runningProfileID(ifNot: currentProfile?.id)
                    .flatMap { id in profiles.profiles.first { $0.id == id }?.label },
                globalExitWithoutProxy: command.isConnected
                    && command.mode.caseInsensitiveCompare("global") == .orderedSame
                    ? Self.homeLine(for: nodes.globalExit) : nil,
                finalRuleRoute: configuredMode == .rule
                    ? route.node.map {
                        ClashHomeFinalRuleRoute(group: route.group, node: $0, delayMilliseconds: route.delay)
                    } : nil
            )
        )
    }

     
     
    private static func cardTraffic(_ traffic: ClashTrafficSnapshot) -> AppleClientTrafficSnapshot {
        guard !ClashClientUI.ClashPerfExperiment.freezesTrafficFigures else { return AppleClientTrafficSnapshot() }
        return AppleClientTrafficSnapshot(
            uploadBytesPerSecond: traffic.upload,
            downloadBytesPerSecond: traffic.download,
            uploadTotalBytes: traffic.uploadTotal,
            downloadTotalBytes: traffic.downloadTotal,
            uploadRatesBytesPerSecond: traffic.uploadHistory,
            downloadRatesBytesPerSecond: traffic.downloadHistory)
    }

    private var sharedSnapshot: AppleClientSnapshot {
         
         
         
         
        ClashPerf.measure("home.snapshot") { untimedSharedSnapshot }
    }

    private var untimedSharedSnapshot: AppleClientSnapshot {
         
         
         
        let timedProfile = ClashPerf.measure("home.s.profile") { currentProfile }
        let timedPresentation = ClashPerf.measure("home.s.presentation") {
            presentation
        }
        let timedProxyCount = ClashPerf.measure("home.s.proxyCount") {
            homeProxyCount
        }
        let timedProxyBreakdown = ClashPerf.measure("home.s.proxyBreakdown") {
            proxiesCardBreakdown
        }
        let timedRuleBreakdown = ClashPerf.measure("home.s.ruleBreakdown") {
            rulesCardBreakdown
        }
        let timedRuleTargets = ClashPerf.measure("home.s.ruleTargets") {
            rulesCardTargets
        }
        let timedEgress = ClashPerf.measure("home.s.egress") { egressSnapshot }
        let timedTally = ClashPerf.measure("home.s.tally") { configTally }
        return AppleClientSnapshot(
            revision: UInt64(truncatingIfNeeded: profileRefreshToken),
            selectedProfile: timedProfile.flatMap {
                guard let identifier = try? ClashClientKit.Profile.ID($0.id)
                else {
                    return nil
                }
                return AppleClientProfileSnapshot(
                    id: identifier,
                     
                     
                    label: ProfileRowPresentation.label(for: $0, locale: .current)
                )
            },
            connection: AppleClientConnectionSnapshot(
                phase: appleConnectionPhase
            ),
            home: AppleClientHomeSnapshot(
                routing: AppleClientRoutingSnapshot(
                    mode:
                        AppleClientOutboundMode(
                            rawValue: configuredMode.rawValue
                        ) ?? .rule
                ),
                 
                 
                traffic: AppleClientTrafficSnapshot(
                    coreStartedAtUnixSeconds: HomeConnectionClock.startedAtUnixSeconds(
                        coreReported: command.runtimeDiagnostics?.startTimeUnix,
                        connectedSince: vpn.connectedSince)
                ),
                proxyGroupCount: timedTally?.proxyGroups ?? 0,
                proxyCount: timedTally?.proxies ?? 0,
                ruleCount: timedTally?.rules ?? 0,
                connection: timedPresentation,
                initialSection: .common,
                favoriteCards: favoriteCards,
                trafficScope:
                    trafficOnlyProxy ? .proxiedOnly : .allTraffic,
                proxies: HomeProxiesCardPolicy.domainSnapshot(
                    mode: configuredMode,
                    standard: ClashHomeDomainSnapshot(
                        count: timedProxyCount.value,
                        countUnit: timedProxyCount.unit,
                        breakdown: timedProxyBreakdown,
                        names: timedTally?.groupNames ?? []
                    ),
                    globalNode: globalGroupNode
                ),
                rules: ClashHomeDomainSnapshot(
                    count: timedTally?.rules,
                    countUnit: "rules",
                    breakdown: timedRuleBreakdown,
                    names: timedRuleTargets
                ),
                egress: timedEgress,
                lanAddress: lanAddress,
                isProfileActionInFlight:
                    activationShownInFlight,
                 
                 
                selectedProfileIsSystemFallback: ProfileCenterPolicy.selectedProfileIsSystemFallback(
                    selectedID: timedProfile?.id,
                    profiles: profiles.profiles
                ),
                profilesLoaded: profiles.hasLoadedProfiles,
                profilesUnavailableReason: profiles.profiles.isEmpty ? profiles.lastFailure?.message : nil
            ),
            capabilities: AppleClientCapabilities([
                .home: .available,
                .outboundMode:
                    currentProfile == nil
                        ? .unavailable(.requiresProfile)
                        : .available,
            ])
        )
    }

    private var sharedActions: AppleClientActions {
        let home = AppleClientActions(capability: .home) { action in
            guard case .home(let command) = action else {
                return
            }
            perform(command)
        }
        let outbound = AppleClientActions(
            capability: .outboundMode
        ) { action in
            guard case .setOutboundMode(let mode) = action else {
                return
            }
            setOutboundMode(mode.rawValue)
        }
        return (
            try? AppleClientActions.composing([home, outbound])
        ) ?? .unavailable
    }

     
    private var homeVPNStatus: String { vpn.homeStatus }

    private var appleConnectionPhase: AppleClientConnectionPhase {
        switch homeVPNStatus.lowercased() {
        case "connected", "reasserting":
            .connected
        case "connecting":
            .preparing
        case "disconnecting":
            .disconnecting
        case "invalid", "unknown":
            .unavailable
        default:
            .disconnected
        }
    }

    private var egressSnapshot: ClashHomeEgressSnapshot {
         
         
         
         
        let connected = vpn.status == "connected"
        let address = stats.egressIP
        let hasResult =
            connected
            && !address.isEmpty
            && address != "—"
            && address != "checking…"
            && address != "VPN not connected"
            && !address.hasPrefix("error")
        let detail = [
            stats.egressCountryName,
            stats.egressISP,
        ]
        .filter { !$0.isEmpty && $0 != "—" }
        .joined(separator: " · ")
        return ClashHomeEgressSnapshot(
            address: hasResult ? address : nil,
            flag:
                hasResult
                    ? EgressLookupResult.flagEmoji(
                        countryCode: stats.egressCountryCode
                    )
                    : "",
            detail: hasResult ? detail : "",
            canRefresh: connected,
            isChecking: connected && address == "checking…"
        )
    }

    private func perform(_ command: ClashHomeCommand) {
        switch command {
        case .openProfiles:
            throughDoor("home.profiles", openProfiles)
        case .performPrimaryAction(let action):
            performPrimaryAction(action)
        case .showConnectionIssue:
            throughDoor("home.connection-issue") { presentConnectionIssue() }
        case .resetVPNProfile:
             
             
             
             
             
             
            Task { @MainActor in _ = await vpn.resetSystemVPNProfile() }
        case .openOnDemand:
             
             
            throughDoor("home.on-demand") { openOnDemandPage() }
         
         
         
        case .openProxies:
             
             
             
             
             
             
            let choosesInGlobal = presentation.issue?.kind == .globalOnDirect
            throughDoor("home.proxies") {
                if choosesInGlobal {
                    openGlobalToChooseANode()
                } else if shellLayout == .regularSidebar {
                    openProxies()
                } else {
                    presentProxiesSheet(.browsing, group: nil)
                }
            }
        case .openRules:
            throughDoor("home.rules") {
                if shellLayout == .regularSidebar {
                    openRules()
                } else {
                    presentRulesOverview()
                }
            }
        case .openRuntimeConfiguration:
            throughDoor("home.runtime-configuration") { presentRuntimeConfiguration() }
        case .setCards(let cards):
            favoriteCards = ClashHomeCatalog.normalized(cards)
        case .setTrafficScope(let scope):
            setTrafficOnlyProxy(scope == .proxiedOnly)
        case .refreshExternalIP:
            Task {
                await stats.checkEgressIP()
            }
        case .refreshLANIP:
            lanAddress = LANAddressInventory.current().first
        }
    }

     
     
     
     
    private func presentRuntimeConfiguration() {
        guard let profile = currentProfile else { return }
        presentationRecovery.supersede()
        runtimeConfigurationPreparationGeneration &+= 1
        runtimeConfigurationPresentation = nil
        runtimeConfigurationProfile = profile
    }

    private func prepareRuntimeConfiguration(
        for profile: Profile,
        generation requestedGeneration: UInt64
    ) async {
         
         
        await Task.yield()
        guard !Task.isCancelled,
              requestedGeneration == runtimeConfigurationPreparationGeneration
        else { return }
        let profileID = profile.id
         
         
         
         
         
         
        let sourceYAML: String?
        if profiles.hasLargeSource(profile), let url = profiles.sourceLocation(for: profile) {
            sourceYAML = await Task.detached(priority: .userInitiated) {
                LargeConfigurationDisplay.text(ofFileAt: url, containerPath: ClashAppIdentifiers.appGroupContainer?.path,
                                               telling: { LargeConfigurationDisplay.phrase($0) })
            }.value
        } else {
            sourceYAML = profiles.capturedSourceText(for: profile)
        }
        let effectiveYAML = await profiles.runtimeDisplayTextOffTheMainActor(for: profile)
        guard !Task.isCancelled,
              requestedGeneration == runtimeConfigurationPreparationGeneration
        else { return }
        let began = DispatchTime.now().uptimeNanoseconds
        let snapshot = await Task.detached(priority: .userInitiated) {
            ProfileFinalConfigurationSnapshot.textOnly(sourceYAML: sourceYAML, effectiveYAML: effectiveYAML)
        }.value
        guard !Task.isCancelled,
              requestedGeneration == runtimeConfigurationPreparationGeneration,
              runtimeConfigurationProfile?.id == profileID
        else { return }
        runtimeConfigurationPresentation = RuntimeConfigurationPresentation(
            profileID: profileID,
            snapshot: snapshot,
            sourceYAML: sourceYAML,
            comparisonYAML: nil,
            baseYAML: nil,
            includesBlockedRuleSets: false
        )
        ClashPerf.span(
            "final.prepare",
            milliseconds: Double(
                DispatchTime.now().uptimeNanoseconds - began
            ) / 1_000_000
        )
    }

    private func setTrafficOnlyProxy(_ enabled: Bool) {
        guard enabled != trafficOnlyProxy else {
            return
        }
        trafficOnlyProxy = enabled
        TrafficStatisticsSettings.setOnlyProxy(enabled)
        command.applyTrafficStatisticsPreference()
    }

     
     
     
     
     
     
     
     
     
     
    private var homeProxyCount: HomeProxiesCardPolicy.Count {
        let inline = configTally?.proxies
        let subscription = nodes.providerNodeTotal ?? 0
        return HomeProxiesCardPolicy.count(inline: inline, providerNodes: subscription,
                                           notDownloadedProviders: notDownloadedProxyProviders)
    }

     
     
    @State private var notDownloadedProxyProviders = 0

     
     
     
     
     
     
     
     
    @State private var subscriptionNodeTally: Int?

    private static func readSubscriptionNodeTally(
        store: ConfigResourceStore?
    ) -> Int? {
        guard let store,
              let directory = try? store.activeProvidersDirectory(),
              let catalog = ProviderCatalog.load(providersDir: directory)
        else { return nil }
        let total = catalog.entries
            .filter { $0.kind == "proxy" }
            .compactMap(\.count)
            .reduce(0, +)
        return total > 0 ? total : nil
    }

     
     
    private var globalGroupNode: String? {
        let name = ProxyBrowsingVisibility.kernelGlobalGroupName
        if let running = nodes.groups.first(where: { $0.name == name })?.now, !running.isEmpty {
            return running
        }
        return currentProfile?.selectedMap[name]
    }

    private var proxiesCardBreakdown: String? {
        guard let tally = configTally else {
            return nil
        }
        var parts: [String] = []
        if tally.proxyGroups > 0 {
            parts.append(
                Self.countedNoun(
                    tally.proxyGroups,
                    "%d group",
                    "%d groups",
                    locale: locale
                )
            )
        }
         
         
        if tally.proxyProviders > 0, homeProxyCount.unit == "proxies" {
            parts.append(
                Self.countedNoun(
                    tally.proxyProviders,
                    "%d source",
                    "%d sources",
                    locale: locale
                )
            )
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var rulesCardBreakdown: String? {
        guard let tally = configTally else {
            return nil
        }
        var parts: [String] = []
        if tally.ruleProviders > 0 {
            parts.append(
                Self.countedNoun(
                    tally.ruleProviders,
                    "%d set",
                    "%d sets",
                    locale: locale
                )
            )
        }
        if tally.subRules > 0 {
            parts.append(
                Self.countedNoun(
                    tally.subRules,
                    "%d sub-rule",
                    "%d sub-rules",
                    locale: locale
                )
            )
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var rulesCardTargets: [String] {
        (rulesOverview?.buckets.prefix(3) ?? []).map {
            "\($0.target) \($0.count)"
        }
    }

    private static func countedNoun(
        _ count: Int,
        _ singular: String,
        _ plural: String,
        locale: Locale
    ) -> String {
        ClashCopy.format(
            count == 1 ? singular : plural,
            locale: locale,
            count
        )
    }

    private func recomputeConfiguredMode() {
         
         
         
         
         
         
         
         
         
         
         
         
         
        if command.isConnected,
           let running = Profile.OutboundMode(rawValue: command.mode.lowercased()) {
            configuredMode = running
            return
        }
        guard let currentProfile else {
            configuredMode = .rule
            return
        }
        if let cached = profiles.cachedOutboundMode(for: currentProfile) {
            configuredMode = cached
        } else {
             
             
            if let last = profiles.lastKnownOutboundMode(for: currentProfile) { configuredMode = last }
            let asked = currentProfile.id
            Task { @MainActor in
                let stored = await profiles.outboundMode(for: currentProfile)
                guard self.currentProfile?.id == asked, !command.isConnected else { return }
                configuredMode = stored
            }
        }
    }

    private func setOutboundMode(_ rawValue: String) {
        guard let profile = currentProfile,
              let mode = Profile.OutboundMode(rawValue: rawValue)
        else {
            return
        }
         
        if mode != .global { GlobalOverDirectConsent.shared.revoke(profileID: nodes.activeProfileID ?? profile.id) }

         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        if let stored = profiles.cachedOutboundMode(for: profile),
           OutboundModeSelection.changesNothing(
            requested: mode,
            stored: stored,
            running: command.isConnected ? command.mode : nil
        ) {
             
             
             
             
             
            ModeIntentClock.next()
            configuredMode = mode
            return
        }

        if mode == .global, command.isConnected {
            let intent = ModeIntentClock.next()
            let previousMode = configuredMode
             
             
            configuredMode = mode
            Task {
                let check = await nodes.checkGlobalMode()
                 
                 
                 
                 
                 
                 
                guard ModeIntentClock.isCurrent(intent) else { return }
                switch GlobalModeConfirmation.switchStep(check: check, groups: nodes.groups) {
                case .switchNow:
                    await commitGlobalMode(profile: profile, intent: intent, previousMode: previousMode)
                case .ask(let exit):
                     
                     
                     
                    configuredMode = previousMode
                    directGlobalQuestion = DirectGlobalQuestion(profileID: profile.id, previousMode: previousMode, exit: exit)
                case .refuse(let sentence):
                     
                     
                     
                    configuredMode = previousMode
                    modeRefusal = OutboundModeRefusal(
                        title: "Global Mode Unavailable",
                        message: .copy(sentence),
                        offersNodeChoice: true
                    )
                case .notKnown:
                     
                    configuredMode = previousMode
                    modeRefusal = OutboundModeRefusal(
                        title: "Global Mode Unavailable",
                        message: .copy(GlobalModeConfirmation.switchNotConfirmed)
                    )
                }
            }
            return
        }

        do {
            let intent = ModeIntentClock.next()
            try profiles.updateOutboundMode(
                profileID: profile.id,
                mode: mode,
                kernelCarriesTheChange: command.isConnected
            )
            configuredMode = mode
             
             
             
             
             
             
             
            if command.isConnected {
                Task {
                    guard await command.setMode(mode.rawValue) else {
                        repairAfterFailedModePatch(
                            profile: profile,
                            intent: intent
                        )
                        return
                    }
                }
            }
        } catch {
            recomputeConfiguredMode()
            modeRefusal = .saveFailed(mode: mode, error: error)
        }
    }

     
     
     
     
     
     
     
     
     
    private func repairAfterFailedModePatch(
        profile: Profile,
        intent: UInt64
    ) {
        guard ModeIntentClock.isCurrent(intent) else { return }
        let kernelMode = Profile.OutboundMode(
            rawValue: command.mode.lowercased()
        )
        do {
            if let kernelMode {
                try profiles.updateOutboundMode(
                    profileID: profile.id,
                    mode: kernelMode,
                    kernelCarriesTheChange: true
                )
            }
            recomputeConfiguredMode()
            modeRefusal = OutboundModeRefusal(
                title: "Mode Not Applied",
                message: "The running tunnel did not take the change, so nothing was changed."
            )
        } catch {
            recomputeConfiguredMode()
            modeRefusal = .saveFailed(mode: kernelMode ?? .rule, error: error)
        }
    }

     
    private func commitGlobalMode(
        profile: Profile,
        intent: UInt64,
        previousMode: Profile.OutboundMode
    ) async {
        guard ModeIntentClock.isCurrent(intent) else { return }
        do {
            try profiles.updateOutboundMode(
                profileID: profile.id,
                mode: .global,
                kernelCarriesTheChange: command.isConnected
            )
            guard await command.setMode(Profile.OutboundMode.global.rawValue) else {
                repairAfterFailedModePatch(
                    profile: profile,
                    intent: intent
                )
                return
            }
        } catch {
            configuredMode = previousMode
            recomputeConfiguredMode()
            modeRefusal = .saveFailed(mode: .global, error: error)
        }
    }

     
     
     
    private func switchToGlobalOverDirect(_ question: DirectGlobalQuestion) {
        guard let profile = currentProfile, profile.id == question.profileID else { return }
        GlobalOverDirectConsent.shared.grant(profileID: nodes.activeProfileID ?? profile.id)
        let intent = ModeIntentClock.next()
        configuredMode = .global
        Task { await commitGlobalMode(profile: profile, intent: intent, previousMode: question.previousMode) }
    }

     
    private static func homeLine(for exit: ClashTunnelOutboundMode.GlobalExit?) -> ClashHomeGlobalExit? {
        switch exit {
        case .direct: return .direct
        case .reject: return .reject
        case .other: return .other
        case .proxy, nil: return nil
        }
    }

     
     
     
     
     
     
     
     
     
     
    private func openGlobalToChooseANode() {
        if shellLayout == .regularSidebar {
            openProxiesToChooseInGlobal()
        } else {
            presentProxiesSheet(.choosingInGlobal, group: GlobalProxySelectionPolicy.groupName)
        }
    }

     
     
     
     
     
    private func presentProxiesSheet(_ opening: ProxyBrowsingVisibility.Opening, group: String?) {
        guard let currentProfile else { return }
        pendingProxiesGroup = group
        proxiesOpening = opening
        presentProxiesOverview(for: currentProfile)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private func enforceConnectedGlobalMode() async {
        await ConnectedGlobalModeEnforcer.shared.enforce(.init(
            isConnected: { command.isConnected },
            isConnectedUnderGlobal: {
                command.isConnected && command.mode.caseInsensitiveCompare("global") == .orderedSame
            },
            runningMode: { command.mode.lowercased() },
             
             
             
            check: { await nodes.checkGlobalMode() },
            inventory: {
                (nodes.groups.count, nodes.groups.contains { $0.name == GlobalProxySelectionPolicy.groupName })
            },
            consentHolds: {
                GlobalOverDirectConsent.shared.holds(profileID: nodes.activeProfileID ?? currentProfile?.id)
            },
            refusal: { GlobalProxySelectionPolicy.refusal(groups: nodes.groups) },
            intentSequence: { ModeIntentClock.sequence },
            intentIsCurrent: { ModeIntentClock.isCurrent($0) },
             
             
             
             
             
             
            runByRules: { await command.setMode(Profile.OutboundMode.rule.rawValue, closesConnections: false) },
            storedModeIsGlobal: {
                currentProfile.flatMap { profiles.cachedOutboundMode(for: $0) }.map { $0 == .global } ?? true
            },
            modeChosenSince: { ClashWidgetFactsPublisher.modeChosen(after: $0) },
            runGlobal: { await command.setMode(Profile.OutboundMode.global.rawValue) },
            putBackToRule: { sentence in await putGlobalBackToRule(saying: sentence) },
            say: { sentence in
                modeRefusal = OutboundModeRefusal(title: "Global Mode Unavailable", message: .copy(sentence), offersNodeChoice: true)
            },
            pause: { try? await Task.sleep(nanoseconds: 1_500_000_000) }
        ))
    }

     
     
    private func putGlobalBackToRule(saying sentence: String) async {
        if let profile = currentProfile {
            try? profiles.updateOutboundMode(
                profileID: profile.id,
                mode: .rule,
                kernelCarriesTheChange: command.isConnected
            )
        }
        configuredMode = .rule
        await command.setMode(Profile.OutboundMode.rule.rawValue)
        modeRefusal = OutboundModeRefusal(
            title: "Global Mode Unavailable",
            message: .copy(sentence),
            offersNodeChoice: true
        )
    }

    private func performPrimaryAction(
        _ action: HomePrimaryAction
    ) {
        switch action {
        case .openProfiles:
            throughDoor("home.primary-action", openProfiles)
        case .connect, .retry:
            connectCurrentProfile()
        case .cancel:
            Task {
                 
                 
                 
                await vpn.stop(alongside: {
                    if profiles.busyProfileID != nil {
                        profiles.cancelActivation()
                    }
                })
            }
        case .disconnect:
            Task {
                await vpn.stop()
            }
        case .retryProxy:
            Task {
                await vpn.forceRestart()
                rebind()
            }
        case .none:
            break
        }
    }

    private func presentProxiesOverview(for profile: Profile) {
         
         
         
        presentationRecovery.supersede()
        sessionPresentation = .proxies
        proxiesPreparationGeneration &+= 1
        preparedProxiesPresentation = nil
        editorDestination = .proxiesOverview(profile)
    }

    private func prepareProxiesOverview(
        for profile: Profile,
        generation requestedGeneration: UInt64
    ) async {
        let sourceYAML = await profiles.loadPagesYAML(for: profile)
        let selectedMap = profile.selectedMap
        let profileID = profile.id
         
         
         
        let isActive = profiles.activeProfileID == profileID
         
         
         
        let asksKernel = !command.isConnected && !command.tunnelIsUp
        let preparedModel = await Task.detached(
            priority: .userInitiated
        ) {
            var providerNodes:
                [String: [ProxiesOverviewModel.Proxy]] = [:]
            var catalog: ProviderCatalog?
            var notes: [String: ProviderNote] = [:]
            if isActive,
               let container = ClashAppIdentifiers.appGroupContainer,
               let store = try? ConfigResourceStore(
                   containerURL: container
               ),
               let directory =
                   try? store.activeProvidersDirectory()
            {
                providerNodes = ProviderNodesLoader.load(
                    providersDir: directory
                )
                catalog = ProviderCatalog.load(providersDir: directory)
                 
                notes = catalog?.proxyProviderNotes(
                    state: ProviderRefreshState.read(workingDirectory: container.appendingPathComponent("working")),
                    written: ProviderCatalog.writtenAt(providersDir: directory)) ?? [:]
            }
             
             
             
             
             
             
            let projected = ProxiesOverviewModel.make(
                sourceYAML: sourceYAML,
                selectedMap: selectedMap,
                providerNodes: providerNodes,
                notes: notes
            )
            return (asksKernel ? projected.resolvedWithKernelCatalog(profileID: profileID) : projected)
                .explainingEmptyProviders(sourceYAML: sourceYAML, catalog: catalog)
        }.value
        guard !Task.isCancelled,
              requestedGeneration == proxiesPreparationGeneration,
              editorDestination?.id == "\(profile.id)|proxies-overview"
        else {
            return
        }
        preparedProxiesPresentation = PreparedProxiesPresentation(
            profileID: profile.id,
            sourceModel: preparedModel
        )
    }

    private func presentRulesOverview() {
        guard let currentProfile else {
            return
        }
        presentationRecovery.supersede()
        sessionPresentation = .rules
        editorDestination = .rulesOverview(currentProfile)
    }

    private func recomputeTally() {
        tallyGeneration &+= 1
        let generation = tallyGeneration
        let tunnelRunning = command.isConnected
         
         
         
        let runningNodes = command.nodeSummary?.nodes
         
         
         
         
         
         
         
         
        let projectionProfile = currentProfile
        let projectedCached = currentProfile.flatMap {
            profiles.cachedUIProjectedYAML(for: $0)
        }
        let projectionInputs = projectedCached == nil
            ? currentProfile.map { profiles.uiProjectionInputs(for: $0) }
            : nil
        let store = profiles.resourceStoreForHomeTally
        let workingDirectory = profiles.workingDir
         
         
         
        let profileForResources = currentProfile
         
         
         
         
        let largeSource = currentProfile.map { profiles.hasLargeSource($0) } ?? false
        let resourceURL = largeSource ? currentProfile.flatMap { profiles.sourceLocation(for: $0) } : nil
        let resourceYAML = largeSource ? nil : currentProfile.flatMap {
            profiles.sourceYAML(for: $0)
        }
         
         
         
        let cacheKey = currentProfile.map {
            HomeTallyCache.Key(profileID: $0.id, refreshToken: profileRefreshToken &+ Int(truncatingIfNeeded: profiles.savedConfigurationGeneration))
        }
        if let cacheKey, let cached = HomeTallyCache.shared.entry(for: cacheKey) {
            configTally = cached.tally
            rulesOverview = cached.rulesOverview
            subscriptionNodeTally = cached.subscriptionNodeTally
            notDownloadedProxyProviders = cached.notDownloadedProxyProviders
            resourceCounts = cached.resourceCounts
        }
        Task.detached(priority: .userInitiated) {
             
             
             
             
             
             
             
             
             
             
            if projectedCached == nil, let projectionInputs, let projectionProfile,
               (projectionInputs.sourceYAML?.utf8.count ?? 0) <= NodesInventoryProjection.wholeReadBytes {
                let value = CustomNodesGroupMaterializer.projectForUI(
                    sourceYAML: projectionInputs.sourceYAML,
                    profile: projectionProfile
                )
                await MainActor.run {
                    profiles.rememberUIProjectedYAML(
                        value, key: projectionInputs.key, for: projectionProfile
                    )
                }
            }
            let effective: String?
             
             
            var libraryNodes: Int?
             
             
            var awaitingRunningCount = false
             
             
            var publication: ActiveConfigurationPointer?
            if tunnelRunning {
                if let profile = projectionProfile {
                    effective = await profiles.loadEffectiveYAML(for: profile)
                    publication = profile.activeRevision.map { ActiveConfigurationPointer(profileID: profile.id, revision: $0) }
                } else {
                    effective = nil
                }
                if let effective, ConfigTransforms.nodeLibraryPath(in: effective) != nil {
                     
                     
                     
                    libraryNodes = ModuleRouteHiding.nodeCount(runningNodes, of: publication)
                        ?? resourceYAML.flatMap { ConfigurationSections.entryCount(ofSection: "proxies", in: $0) }
                        ?? resourceURL.flatMap { ConfigurationSections.entryCount(ofSection: "proxies", inFileAt: $0) }
                    awaitingRunningCount = libraryNodes == nil
                }
            } else if let source = resourceYAML, let profile = projectionProfile {
                 
                 
                 
                 
                if let published = PublishedPresentation.textForPages(
                    source: source, profile: profile, store: store, workingDirectory: workingDirectory) {
                    effective = published
                    publication = try? store?.activeIdentity()
                     
                     
                     
                     
                     
                     
                     
                     
                    libraryNodes = ModuleRouteHiding.publishedNodeCount(profileID: profile.id, store: store)
                        ?? ConfigurationSections.entryCount(ofSection: "proxies", in: source)
                } else {
                    effective = (try? ProfileRuntimeConfigBuilder.buildProduction(raw: source, profile: profile, scripts: .silent)) ?? source
                }
            } else if let url = resourceURL, let profile = projectionProfile {
                 
                 
                if let published = PublishedPresentation.textForPages(
                    sourceAt: url, profile: profile, store: store, workingDirectory: workingDirectory) {
                    effective = published
                    publication = try? store?.activeIdentity()
                    libraryNodes = ModuleRouteHiding.publishedNodeCount(profileID: profile.id, store: store)
                        ?? ConfigurationSections.entryCount(ofSection: "proxies", inFileAt: url)
                } else if let leaving = ProfilesViewModel.presentedDocumentLeavingRules(sourceAt: url, profile: profile) {
                     
                     
                    effective = leaving
                } else if let source = try? String(contentsOf: url, encoding: .utf8) {
                     
                    effective = (try? ProfileRuntimeConfigBuilder.buildProduction(raw: source, profile: profile, scripts: .silent)) ?? source
                } else {
                    effective = nil
                }
            } else { effective = nil }
             
             
             
            let overview = RulesOverviewModel.make(sourceYAML: effective)
            let rulesElsewhere = effective.map {
                ConfigTransforms.ruleIndexPath(in: $0) != nil || PagesRuleSource.url(in: $0) != nil
            } == true
            var tally = ProfileConfigTally.make(sourceYAML: effective, tunnelRunning: tunnelRunning,
                                                rulesCounted: rulesElsewhere ? overview.inlineCount : nil)
             
             
            if let counted = tally, let effective, ConfigTransforms.nodeLibraryPath(in: effective) == nil {
                tally = counted.leavingOutTheEngine(of: publication)
            }
            if let libraryNodes, let counted = tally {
                tally = counted.counting(proxies: libraryNodes)
            }
            let subscription = Self.readSubscriptionNodeTally(store: store)
            let notDownloaded = HomeProxiesCardPolicy.notDownloadedProxyProviders(
                in: (try? store?.activeProvidersDirectory()).flatMap { ProviderCatalog.load(providersDir: $0) },
                state: ClashAppIdentifiers.appGroupContainer.flatMap {
                    ProviderRefreshState.read(workingDirectory: $0.appendingPathComponent("working"))
                })
             
             
            let counts = HomeResourceCounts.make(
                profile: profileForResources,
                sourceYAML: resourceYAML ?? (largeSource ? effective : nil)
            )
            await MainActor.run {
                guard generation == tallyGeneration, command.isConnected == tunnelRunning,
                      currentProfile?.id == projectionProfile?.id else { return }
                let shown = awaitingRunningCount
                    ? tally.map { $0.awaitingRunningCount(shownBefore: configTally) }
                    : tally
                 
                 
                 
                if configTally != shown { configTally = shown }
                if rulesOverview?.fingerprint != overview.fingerprint {
                    rulesOverview = overview
                }
                if subscriptionNodeTally != subscription {
                    subscriptionNodeTally = subscription
                }
                if notDownloadedProxyProviders != notDownloaded {
                    notDownloadedProxyProviders = notDownloaded
                }
                if resourceCounts != counts { resourceCounts = counts }
                if let cacheKey, !awaitingRunningCount {
                    HomeTallyCache.shared.store(
                        HomeTallyCache.Entry(
                            tally: tally,
                            rulesOverview: overview,
                            subscriptionNodeTally: subscription,
                            notDownloadedProxyProviders: notDownloaded,
                            resourceCounts: counts
                        ),
                        for: cacheKey
                    )
                }
            }
        }
    }

     
     
     
     
     
     
     
     
     
    private func throughDoor(_ door: String, _ open: @escaping @MainActor () -> Void) {
        presentationRecovery.register(home: homeClaims)
        openThroughDoor(door, open)
    }

     
     
     
     
     
    private var homeClaims: LostPresentationRecovery.Claims {
        let editor = $editorDestination
        let runtimeConfiguration = $runtimeConfigurationProfile
        let connectionIssue = $presentedConnectionIssue
        let refusal = $modeRefusal
        return LostPresentationRecovery.Claims(
            kinds: {
                var kinds: [String] = []
                switch editor.wrappedValue {
                case .proxiesOverview: kinds.append("proxiesOverview")
                case .rulesOverview: kinds.append("rulesOverview")
                case .onDemand: kinds.append("onDemand")
                case nil: break
                }
                if runtimeConfiguration.wrappedValue != nil { kinds.append("runtimeConfiguration") }
                if connectionIssue.wrappedValue != nil { kinds.append("connectionIssue") }
                if refusal.wrappedValue != nil { kinds.append("modeRefusal") }
                return kinds
            },
            clear: {
                editor.wrappedValue = nil
                runtimeConfiguration.wrappedValue = nil
                connectionIssue.wrappedValue = nil
                refusal.wrappedValue = nil
            }
        )
    }

    private func presentConnectionIssue() {
        presentationRecovery.supersede()
        presentedConnectionIssue = presentation.issue
    }

    private func presentOnDemand() {
        presentationRecovery.supersede()
        editorDestination = .onDemand
    }

    private func openOnDemandPage() {
        Self.routeToOnDemand(layout: shellLayout, rail: openOnDemand, sheet: { presentOnDemand() })
    }

     
     
     
    static func routeToOnDemand(layout: AppShellLayout, rail: () -> Void, sheet: () -> Void) {
        if layout == .regularSidebar {
            rail()
        } else {
            sheet()
        }
    }

    private func connectCurrentProfile() {
        guard let profile = currentProfile else {
            throughDoor("home.connect", openProfiles)
            return
        }
        Task {
            await profiles.connectFromHome(profile)
            rebind()
        }
    }
}

private enum HomeProfileEditorDestination: Identifiable {
    case rulesOverview(Profile)
    case proxiesOverview(Profile)
     
     
    case onDemand

    var id: String {
        switch self {
        case .rulesOverview(let profile):
            "\(profile.id)|rules-overview"
        case .proxiesOverview(let profile):
            "\(profile.id)|proxies-overview"
        case .onDemand:
            "on-demand"
        }
    }
}

 
 
 
private struct HomeOnDemandPage: View {
     
     
    @StateObject private var dismiss = ClashDismissHandle()
    @ObservedObject var vpn: VPNController

    var body: some View {
        ClashFeatureNavigationContainer {
            OnDemandConfigView(vpn: vpn, usesRegularDetailLayout: false)
                .clashToolbarUnlessInPanel {
                    ToolbarItem(placement: .cancellationAction) {
                        ClashSheetCloseButton { dismiss.closeModalOrDismiss() }
                    }
                }
                .clashSheetPresentation()
        }
        .clashCapturesDismiss(dismiss)
    }
}

private struct HomePreparationPlaceholder: View {
     
     
     
     
     
     
    @StateObject private var dismiss = ClashDismissHandle()
    let title: String
    let accessibilityIdentifier: String

    var body: some View {
        ClashSingleColumnNavigationContainer {
            ClashPageLoadingPlaceholder(title: .copy("Loading"))
                .accessibilityIdentifier(accessibilityIdentifier)
                .clashPageTitle(.copy(title))
                .clashToolbarUnlessInPanel {
                    ToolbarItem(placement: .cancellationAction) {
                        ClashSheetCloseButton { dismiss() }
                    }
                }
        }
        .clashCapturesDismiss(dismiss)
    }
}



 
 
 
 
 
 
enum HomeFailureCensus {
     
     
     
     
     
     
     
    static let priceMemoryKey = "memory.trim.measured-prices"
     
     
     
    static let peakPriceMemoryKey = "memory.trim.measured-peaks"

    static func ruleSetItems(source: String?, trim: MemoryTrimSpec?,
                                        estimates domainEstimates: [String: Int64]) -> [MemoryTrimManageView.Item] {
         
         
         
         
         
         
         
        var censusNote = ""
        defer {
            ClashLogStore.shared.append(censusNote, stream: .app, level: .info)
        }
         
         
         
        let defaults = GlobalConfig.appGroupDefaults
        var prices = (defaults.dictionary(
            forKey: Self.priceMemoryKey
        ) as? [String: Int64]) ?? [:]
         
         
         
         
         
         
        var peakPrices = (defaults.dictionary(
            forKey: Self.peakPriceMemoryKey
        ) as? [String: Int64]) ?? [:]
        var runPrices: [String: Int64] = [:]
        if let container = ClashAppIdentifiers.appGroupContainer,
           let text = try? String(
               contentsOf: container.appendingPathComponent(
                   MemorySampleLog.startupPhaseFileName
               ),
               encoding: .utf8
           )
        {
            for row in ClashMemoryLedger.lastRun(
                from: text.split(separator: "\n").map(String.init)
            ).rows where row.name.hasPrefix("apply:rule-provider:") {
                 
                 
                 
                 
                 
                let name = String(
                    row.name.dropFirst("apply:rule-provider:".count)
                )
                guard !name.isEmpty else { continue }
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                let measured = row.peakSpendBytes
                guard measured > 0 else { continue }
                runPrices[name] = measured
                if row.peakBytes == nil {
                     
                     
                    prices[name] = min(prices[name] ?? .max, measured)
                } else {
                     
                     
                    peakPrices[name] = max(peakPrices[name] ?? 0, measured)
                }
            }
            defaults.set(prices, forKey: Self.priceMemoryKey)
            defaults.set(peakPrices, forKey: Self.peakPriceMemoryKey)
        }
         
         
         
         
        var estimates = domainEstimates
         
         
         
         
        for (name, size) in MemoryTrimCensus.stagedFileSizes(
            kind: "rule-providers",
            container: ClashAppIdentifiers.appGroupContainer
        ) where estimates[name] == nil {
            estimates[name] = size
        }
        let items = MemoryTrimCensus.ruleProviders(
            sourceYAML: source,
             
             
             
             
             
             
            effectiveYAML: MemoryTrimCensus.effectiveYAML(
                container: ClashAppIdentifiers.appGroupContainer
            ),
            dropped: trim?.droppedRuleProviders ?? [],
            prices: prices.merging(peakPrices) { _, peak in peak },
            runPrices: runPrices,
            estimates: estimates
        )
        censusNote = "ruleset-census total=\(items.count)"
            + " fromOverride=\(items.filter { $0.origin == .override }.count)"
        ClashLogStore.shared.append(
            "ruleset-items total=\(items.count) priced=\(items.filter { $0.measuredBytes != nil }.count) zero=\(items.filter { $0.measuredBytes == 0 }.count) run=\(runPrices.count) store=\(prices.count)",
            stream: .app, level: .info)
        return items
    }

     
    static func geoItems(kind: String, source yaml: String?, trim: MemoryTrimSpec?) -> [(String, Int64?)] {
        let dropped = kind == "GEOIP"
            ? trim?.droppedGeoIPRules ?? []
            : trim?.droppedGeoSiteRules ?? []
        let container = ClashAppIdentifiers.appGroupContainer
        return MemoryTrimCensus.geoRuleNames(
            sourceYAML: yaml, kind: kind, dropped: dropped
        ).map {
            ($0, MemoryTrimCensus.geoArtifactBytes(
                kind: kind, name: $0, container: container))
        }
    }

     
    static func pricedDNS(_ entries: [String]) -> [(String, Int64?)] {
        let store = (GlobalConfig.appGroupDefaults.dictionary(
            forKey: Self.priceMemoryKey
        ) as? [String: Int64]) ?? [:]
        let container = ClashAppIdentifiers.appGroupContainer
        return entries.map {
            ($0, MemoryTrimCensus.dnsEntryBytes(
                $0, container: container, rulePrices: store
            ))
        }
    }

     
    static func dnsPolicyKeys(source yaml: String?, trim: MemoryTrimSpec?) -> [String] {
         
         
        let effective = MemoryTrimCensus.effectiveYAML(
            container: ClashAppIdentifiers.appGroupContainer
        )
        return MemoryTrimCensus.dnsPolicyKeys(
            sourceYAML: yaml,
            effectiveYAML: effective,
            dropped: trim?.droppedDNSPolicyKeys ?? []
        )
    }

     
    static func fakeIPFilterEntries(source yaml: String?, trim: MemoryTrimSpec?) -> [String] {
        MemoryTrimCensus.fakeIPFilterEntries(
            sourceYAML: yaml,
            dropped: trim?.droppedFakeIPFilterEntries ?? []
        )
    }

     
     
    static func providerLoad(source yaml: String?, groups: [String]) -> [ProviderLoadDetailView.Row] {
         
         
         
         
        let subscriptions = MemoryTrimCensus.proxyProviderNames(
            sourceYAML: yaml
        )
        var measured: [String: Int64] = [:]
        for row in Self.providerLoadRows() { measured[row.name] = row.bytes }
        let disk = MemoryTrimCensus.stagedFileSizes(
            kind: "proxy-providers",
            container: ClashAppIdentifiers.appGroupContainer
        )
        let subsSet = Set(subscriptions)
        return (subscriptions.sorted() + groups.sorted()).map { name in
            if let real = measured[name] {
                return ProviderLoadDetailView.Row(
                    name: name, bytes: real,
                    isSubscription: subsSet.contains(name)
                )
            }
             
            return ProviderLoadDetailView.Row(
                name: name, bytes: disk[name], isEstimate: disk[name] != nil,
                isSubscription: subsSet.contains(name)
            )
        }
    }

    static func providerLoadRows() -> [ProviderLoadDetailView.Row] {
        guard let container = ClashAppIdentifiers.appGroupContainer,
              let text = try? String(
                  contentsOf: container.appendingPathComponent(
                      MemorySampleLog.startupPhaseFileName
                  ),
                  encoding: .utf8
              )
        else { return [] }
        return ClashMemoryLedger.lastRun(
            from: text.split(separator: "\n").map(String.init)
        ).rows.compactMap { row in
            guard row.name.hasPrefix("apply:proxy-provider:") else {
                return nil
            }
             
             
             
             
            return ProviderLoadDetailView.Row(
                name: String(
                    row.name.dropFirst("apply:proxy-provider:".count)
                ),
                bytes: row.deltaBytes > 0 ? row.deltaBytes : nil
            )
        }
    }

     
    struct Reading {
        var ruleSetItems: [MemoryTrimManageView.Item]
        var providerRows: [ProviderLoadDetailView.Row]
        var dnsPolicy: [(String, Int64?)]
        var dnsFilter: [(String, Int64?)]
        var geoSite: [(String, Int64?)]
        var geoIP: [(String, Int64?)]
    }

     
    static func reading(source: String?, trim: MemoryTrimSpec?, groups: [String],
                                    estimates: [String: Int64]) -> Reading {
        defer { MemoryTrimCensus.forgetReadings() }
        return Reading(
            ruleSetItems: ruleSetItems(source: source, trim: trim, estimates: estimates),
            providerRows: providerLoad(source: source, groups: groups),
            dnsPolicy: pricedDNS(dnsPolicyKeys(source: source, trim: trim)),
            dnsFilter: pricedDNS(fakeIPFilterEntries(source: source, trim: trim)),
            geoSite: geoItems(kind: "GEOSITE", source: source, trim: trim),
            geoIP: geoItems(kind: "GEOIP", source: source, trim: trim))
    }
}

 
 
 
@MainActor
final class HomeTrafficFeedOwner: ObservableObject {
    let feed: ClashClientUI.ClashTrafficFeed

    init(traffic: AppleClientTrafficSnapshot) {
        feed = ClashClientUI.ClashTrafficFeed(traffic: traffic)
    }

     
    func update(_ traffic: AppleClientTrafficSnapshot) {
        if feed.traffic != traffic { feed.traffic = traffic }
    }
}
