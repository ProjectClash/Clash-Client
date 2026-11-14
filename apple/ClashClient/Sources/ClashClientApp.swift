import Combine
import ClashClientUI
import SwiftUI
import UIKit
import UserNotifications
import WidgetKit

@main
struct ClashClientApp: App {
    init() {
         
         
        ConfigStoreSuspensionShield.install()
         
         
        ClashNotificationCenterDelegate.install()
         
         
         
        ClashPerfBootstrap.install()
         
         
        ClashClientUI.ClashSymbol.platformName = { $0.name }
         
         
         
         
         
        MainActor.assumeIsolated {
            DirectFetchFallback.perform = { request, maxBytes, timeout, redirectPolicy in
                try await AppGroupDirectFetch.perform(request, maxBytes: maxBytes, timeout: timeout,
                                                      redirectPolicy: redirectPolicy)
            }
            DirectFetchFallback.isUsable = { await AppGroupDirectFetch.isUsable() }
             
             
            ModuleTextPlatform.install()
#if os(iOS)
             
             
            ClashUIKitTextFieldAlert.install()
#endif
        }

            Self.repairPersonalRulePlacement()
            MetricKitCollector.shared.start()
             
            BackgroundRefresh.register {
                 
                 
                async let scripts: Void = ModuleAppScriptDriver.shared.runMissedInBackground()
                let outcome = await BackgroundRefresh.refreshDueProfiles()
                await scripts
                return outcome
            }
            BackgroundRefresh.schedule(earliest: BackgroundRefresh.nextEligibility())
             
            Task { await BackgroundRefresh.scanOnForegroundIfDue() }
             
             
            AppGoCrashReportStore.shared.consumeOnce()
             
            ModuleCertificateStore.followTheLanguage()
             
             
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
                MainActor.assumeIsolated {
                    Task { await ModuleScriptNotificationPermission.shared.start() }
                }
                ModuleScriptNotificationPoster.askFirst = { done in
                    Task { @MainActor in done(await ModuleScriptNotificationPermission.shared.mayShowNotification()) }
                }
            }

         
         
        MainActor.assumeIsolated { ModuleAppScriptDriver.shared.start() }
    }

     
     
    private static func repairPersonalRulePlacement() {
        guard let container = ClashAppIdentifiers.appGroupContainer, let defaults = UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite)
        else { return }
        let working = container.appendingPathComponent("working", isDirectory: true)
        PersonalRulePlacementMigration.runIfNeeded(
            store: ProfileStore(
                fileURL: working.appendingPathComponent("store/profiles.json")
            ),
            defaults: defaults
        )
    }

    var body: some Scene {
        WindowGroup {

            AppShellView()

        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
struct DisclaimerView: View {

    var body: some View {
         
         
         
         
         
        List {
            Section {
                 
                 
                 
                 
                 
                VStack(
                    alignment: .leading,
                    spacing: ClashTheme.Spacing.row
                ) {
                    Text(clash: .copy(Self.responsibility))
                    Text(clash: .copy(Self.noService))
                }
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, ClashTheme.Spacing.tight)
            }
        }
        .listStyle(.insetGrouped)
        .clashPageTitle("Disclaimer")
        .clashDetailPageInsets()
        .accessibilityIdentifier("about.disclaimer")
    }

    static let responsibility =
        "Clash is a network tool. You are responsible for making sure the way you use it complies with the laws that apply to you and with the terms of any service you connect through."
    static let noService =
        "Clash does not provide any proxy service and is not responsible for the third-party services you configure it with."
}

struct AppShellView: View {
    @Environment(\.scenePhase) private var scenePhase
     
     
     
     
     
     
     
     
    @State private var scenePhaseWitness = ScenePhaseWitness()
     
     
     
     
    @State private var pendingCompileWatcher = ProviderRefreshStateWatcher()
     
     
     
     
     
    @State private var throughputUnit = ClashThroughputUnit.stored(in: GlobalConfig.appGroupDefaults)

     
     
     
     
     
     
    private func noteTheReturnFromBackground() {
        vpn.applicationBecameActive()
    }


    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var preferences = AppPreferencesModel()
    @StateObject private var vpn: VPNController
     
     
     
     
     
    @StateObject private var profiles: ProfilesViewModel
    @StateObject private var command = ClashCommandClient()
    @StateObject private var stats = StatsModel()
     
     
    @StateObject private var nodes = NodesModel(
        automaticPinsDefaults: UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite)
    )
    @StateObject private var networkQuality = NetworkQualityModel()
    @StateObject private var stun = STUNTestModel()
     
     
     
     
     
     
     
    @StateObject private var connectionsOwner = ConnectionsModelOwner()
    private var connections: ConnectionsModel { connectionsOwner.model }
    @StateObject private var proxyShare = ProxyShareModel()
    @StateObject private var profileImports = ProfileImportRouter()
    @State private var navigationState = ClashClientUI.AppleClientNavigationState()
     
     
     
    @State private var activityLens: ClashActivityLens = .connections

    init() {
        let vpn = VPNController()
        _vpn = StateObject(wrappedValue: vpn)
        _profiles = StateObject(wrappedValue: ProfilesViewModel(vpn: vpn, downloader: Self.downloader()))
    }

     
     
     
     
     
    private static func downloader() -> HTTPFetching {


        return ResourceDownloader()
    }

     
     
     
    @State private var lastRouteNotedVPNStatus = ""
     
     
    @State private var egressRecheck = EgressRecheckDebt()
     
     
     
    @State private var profileSheets = ProfileSheetState()
    private var profileCenterDestination: AppNavigationDestination? {
        get { profileSheets.centre }
        nonmutating set { profileSheets.centre = newValue }
    }
     
     
    @State private var handoffCentre = HandoffCentreDebt()
    @State private var handoffAnswers = 0
     
     
    @State private var handoffChecksInFlight = 0
     
     
     
     
     
    @State private var pendingSessionPage:
        ClashClientUI.ClashRootDestination?
     
     
    @State private var compactSessionPage:
        ClashClientUI.ClashRootDestination?
     
     
    @State private var railProxiesGroup: String?
     
     
    @State private var railProxiesOpening: ProxyBrowsingVisibility.Opening = .browsing
     
     
     
     
    @State private var railProxiesRequest = ClashClientUI.ClashRootOpenGroupSignal()
    @State private var profileRefreshToken = 0
     
     
    @State private var nodeListRereads = NodeListRereads()
     
    private var isPickingProfile: Bool {
        get { profileSheets.isPicking }
        nonmutating set { profileSheets.isPicking = newValue }
    }
     
     
     
    @State private var presentationRecovery = LostPresentationRecovery(
        presented: ShellPresentationProbe.describe,
        isPresenting: { ShellPresentationProbe.presentsMoreThanAnAlert }
    )
     
     
    @State private var deferredRoutePage: DeferredPage?
     
     
     
     
    @State private var deferredCentrePage: DeferredPage?
    @State private var pendingOutboundMode: String?
     
     
    @State private var pickerSwitchFailure: ProfileSwitchAlertFailure?


    private let systemHandoff = ClashSystemHandoff()

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private func probeSingleNodeIfRequested() async {


    }

     
     
     
    private func loseTheProfileSheetIfRequested() async {


    }

     
     
     
     
     
    private func openDocumentsFileIfRequested() async {


    }

     
     
     
     
    private func openLinkIfRequested() async {


    }

     
     
     
     
    private func tapScriptNotificationIfRequested() async {


    }

     
     
     
     
     
    private func compiledGeoIfRequested() async {


    }

     
     
     
     
     
     
    private func backupTraceIfRequested() async {


    }

     
     
     
     
    private func deleteProfilesIfRequested() async {


    }

    private func logFootprintIfRequested() async {


    }

    private func applySoftMemoryLimitIfRequested() async {


    }

     
     
     
     
     
    private func collectResidentProfilesIfRequested() async {




    }

    var body: some View {
        debugGateShell
            .task { await collectResidentProfilesIfRequested() }
            .task { await applySoftMemoryLimitIfRequested() }
            .task { await logFootprintIfRequested() }
            .task { await probeSingleNodeIfRequested() }
            .task { await loseTheProfileSheetIfRequested() }
            .task { await openDocumentsFileIfRequested() }
            .task { await openLinkIfRequested() }
            .task { await deleteProfilesIfRequested() }
            .task { await compiledGeoIfRequested() }
            .task { await backupTraceIfRequested() }
            .task { await tapScriptNotificationIfRequested() }
         
         
         
         
         
         
         
         
         
         
         
         
         
        .clashSheet(item: shellSheet, onDismiss: activeRuntimeDidChange) {
            shellSheetContent(for: $0)
                .clashModalPresentation(.page)
        }
         
         
         
         
        .background(secondPresenter)
         
         
         
        .background(ScriptNotificationPagePresenter(pages: .shared))
         
         
        .onDisappear { presentationRecovery.supersede() }
         
         
         
         
         
         
         
         
         
        .transformEnvironment(\.locale) { locale in
            if let override = preferences.language.localeOverride { locale = override }
        }
        .preferredColorScheme(preferences.themeMode.colorScheme)
        .tint(preferences.accent.color)
         
        .clashRuleRunFeedbackRelay(profiles, locale: preferences.language.localeOverride)
         
         
        .clashFeedbackSceneHost(locale: preferences.language.localeOverride,
                                colorScheme: preferences.themeMode.colorScheme,
                                tint: preferences.accent.color)
        .background(ClashTheme.canvas(pureBlack: preferences.pureBlack).ignoresSafeArea())
        .task {
             
             
             
            if !scenePhaseWitness.heardAChange { scenePhaseWitness.phase = scenePhase }
            ModuleScriptNotificationPages.shared.sceneBecame(active: scenePhase == .active)
            command.syncConnectionObservationScene(isActive: scenePhase == .active, isBackground: scenePhase == .background)




             
             
            await restoreTunnelControlSession()
            proxyShare.bind(command: command)
             
             
            LocalNetworkPermission.clearPublicationMirror(in: UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite))
             
             
             
            proxyShare.bind(
                profileYAML: { [profiles] in
                    guard let active = profiles.profiles.first(where: { $0.id == profiles.activeProfileID })
                    else { return nil }
                    return profiles.effectiveYAMLIfReady(for: active)
                },
                lanListenerPermitted: {
                    LocalNetworkPermission.isPermitted(UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite))
                }
            )
             
             
             
            proxyShare.bind(kernelShare: profiles.kernelLANShareBinding())
            stun.bind(command: command)
            vpn.legacySettingsMigration = await vpn.migrateLegacyGlobalSettingsIfNeeded()
            await vpn.refresh()
            rebind()
            syncConnectionsForSelectedTab()
            proxyShare.updateAPIAvailability(command.isConnected)
            if command.isConnected {
                await proxyShare.refresh()
            }
            checkSharedImports()
            handlePendingSystemAction()


        }
         
         
        .onReceive(profiles.$activeProfileID.removeDuplicates().dropFirst()) { _ in
            connections.clearRequestHistory()
        }
        .onReceive(vpn.$status.removeDuplicates()) { status in
            handleVPNStatusTransition(status)
        }
         
         
         
        .onChange(of: vpn.hasLoadedStatus) { _ in
            publishVPNControlSnapshot(status: vpn.status)
        }
         
         
         
         
         
         
         
         
         
         
         
         
         
        .onChange(of: command.selectionAnnouncements) { _ in
            guard command.isConnected else { return }
            Task { await nodes.refresh() }
        }
         
         
         
        .onChange(of: command.tunnelIsUp) { up in
            syncConnectionsForSelectedTab(tunnelIsUp: up)
        }
        .onChange(of: command.channelAttachFailed) { failed in
            syncConnectionsForSelectedTab(channelFailed: failed)
        }
         
         
         
         
        .onChange(of: command.coreSession) { core in
            guard core != nil else { return }
            Task { await nodes.restoreAutomaticPins() }
        }
        .onChange(of: command.isConnected) { connected in
            syncConnectionsForSelectedTab(isConnected: connected)
            proxyShare.updateAPIAvailability(connected)
             
             
             
             
             
             
            if egressRecheck.channelChanged(up: connected) {
                Task { _ = await stats.checkEgressIP() }
            }
             
             
             
             
             
             
             
             
            if !command.isReopeningControlSession {
                Task { await nodes.refresh() }
            }
            if connected {
                Task { await proxyShare.refresh() }
                 
                 
                 
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    guard command.isConnected, scenePhaseWitness.phase == .active,
                          let container = ClashAppIdentifiers.appGroupContainer else { return }
                    command.startPendingCompiles(container: container)
                    profiles.publishWhatOnlyAPublicationTakes(container: container)
                }
            } else {
                command.stopPendingCompiles()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.didReceiveMemoryWarningNotification
            )
        ) { _ in
            Task { await nodes.cancelLatencyTests(reason: .memoryPressure) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .clashSystemActionQueued)) { _ in
            handlePendingSystemAction()
        }
         
         
         
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
             
             
             
             
            checkSharedImports()
            openDeferredPage()
        }
         
         
         
         
         
        .onReceive(NotificationCenter.default.publisher(for: ClashLogSettings.levelDirectiveDidChange)) { _ in
            command.refreshLogDisplayLevel()
            profiles.restageActiveRuntime()
        }
        .onChange(of: navigationState.selectedRoot) { _ in
            syncConnectionsForSelectedTab()
        }
        .onChange(of: handoffAnswers) { _ in
            raiseCentreForHandoffAfterThisTurn()
        }
         
        .onChange(of: profileImports.centreAppearances) { _ in
            handoffCentre.centreAppeared()
        }
         
         
         
         
         
         
        .modifier(InstallLinkConfirmationAlert(router: profileImports,
            asksHere: profileImports.centresOnScreen.isEmpty,
            added: {
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                presentationRecovery.afterDismissal(
                    "install-link.add",
                    shell: shellClaims,
                    lost: !ShellPresentationProbe.presentsMoreThanAnAlert,
                     
                     
                    afterRaise: { confirmTheSheetCameUp() }
                ) {
                    navigate(to: .profiles)
                }
            },
            declined: {
                 
                 
                 
                raiseCentreForHandoffOnceSettled()
            }
        ))
        .onChange(of: nodes.routeGeneration) { _ in
             
             
             
             
             
             
            guard egressRecheck.routeMoved(channelUp: command.isConnected) else { return }
            Task { _ = await stats.checkEgressIP() }
        }
         
         
         
        .task {


        }
        .task {
             
             
            ICloudAutoBackup.shared.start()
             
             
            ModuleScriptNotificationRelay.shared.start()
            ModuleScriptNotificationTaps.register()
            watchForPendingCompiles(scenePhase == .active)
        }
        .onChange(of: scenePhase) { phase in
            scenePhaseWitness.phase = phase
            scenePhaseWitness.heardAChange = true
            command.syncConnectionObservationScene(isActive: phase == .active, isBackground: phase == .background)
             
             
            ICloudAutoBackup.shared.setForeground(phase == .active)
            watchForPendingCompiles(phase == .active)
             
             
            if case .active = phase { ModuleScriptNotificationRelay.shared.drain() }
             
            ModuleScriptNotificationPages.shared.sceneBecame(active: phase == .active)
            if phase == .active {
                Task {
                    await restoreTunnelControlSession()
                     
                     
                     
                     
                     
                     
                     
                     
                    syncConnectionsForSelectedTab(isForeground: scenePhaseWitness.phase == .active)
                }
                noteTheReturnFromBackground()
                 
                 
                 
                Task { await profiles.republishIfLibraryGone() }
                if let container = ClashAppIdentifiers.appGroupContainer, command.isConnected {
                    command.startPendingCompiles(container: container)
                    profiles.publishWhatOnlyAPublicationTakes(container: container)
                }
                 
                 
                if pendingOutboundMode == nil, let raw = ClashWidgetFactsPublisher.takeModeChosenOnACard() {
                    pendingOutboundMode = raw
                }


                proxyShare.refreshAddresses()
                nodes.applicationBecameActive()
                if command.isConnected {
                    Task { await proxyShare.refresh() }
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                    Task {
                        if await !nodes.readOnForeground() { await command.refreshMetadata() }
                    }
                }
                checkSharedImports()
                 
                 
                raiseCentreForHandoffAfterThisTurn()
                openDeferredPage()
                handlePendingSystemAction()

                    Task { await BackgroundRefresh.scanOnForegroundIfDue() }

            } else if phase == .background, !false {
                command.stopPendingCompiles()
                 
                 
                 
                 
                syncConnectionsForSelectedTab(isForeground: false)
                 
                 
                vpn.applicationEnteredBackground()
                Task { await nodes.cancelLatencyTests(reason: .backgrounded) }
                 
                 
                BackgroundRefresh.schedule(
                    earliest: BackgroundRefresh.nextEligibility()
                )
            }
        }
        .task {
             
             
             
            command.takesWhatTheCompileCouldNotTake = { [weak profiles] held in
                guard let container = ClashAppIdentifiers.appGroupContainer else { return }
                profiles?.publishWhatOnlyAPublicationTakes(container: container, handedOn: held)
            }
             
            await profiles.republishIfLibraryGone()
             
             
            ProviderTunnelUpdate.perform = { [weak command] target, stillInUse in
                guard let command else { return .noSession }
                return await command.updateProviderInTunnel(kind: target.kind, name: target.name,
                                                            url: target.url ?? "", stillInUse: stillInUse)
            }
             
             
             
             
             
            AppGroupDirectFetch.session = command
             
             
            ProviderFirstLoadRetry.loadedRuleProvidersInCore = { [weak command] in
                await MainActor.run {
                    guard let command, command.isConnected else { return nil as ClashCommandClient? }
                    return command
                }.map { client in
                    Task { @MainActor in
                        let catalog = try? await client.providerRuntimeCatalog()
                        return Set(catalog?.ruleProviders.compactMap { name, provider in
                            provider.updatedAt == nil ? nil : name
                        } ?? [])
                    }
                }?.value ?? []
            }
             
             
            ProviderFirstLoadRetry.loadedProxyProvidersInCore = { [weak command] in
                await MainActor.run {
                    guard let command, command.isConnected else { return nil as ClashCommandClient? }
                    return command
                }.map { client in
                    Task { @MainActor in
                        let catalog = try? await client.providerRuntimeCatalog()
                        return Set(catalog?.proxyProviders.compactMap { name, provider in
                             
                             
                            provider.nodeCount > 0 || (provider.updatedAt?.timeIntervalSince1970 ?? 0) > 0
                                ? name : nil
                        } ?? [])
                    }
                }?.value ?? []
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ProviderFirstLoadRetry.didRefreshNotification)) { _ in
             
             
             
             
             
            let updates = ProviderFirstLoadRetry.takeRuntimeUpdates()
            guard let published = updates.compactMap(\.publishedIn).last else { return }
            Task { await PublishedRuntimeHandover.apply(vpn: vpn, profileID: published.profileID) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .clashProviderContentChanged)) { note in
             
             
             
             
             
             
            guard PublishedRuntimeHandover.readsNodesAgain(after: note, isConnected: command.isConnected) else { return }
            nodeListRereads.ask { await nodes.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: ProviderDownloadActivity.didChangeNotification)) { _ in
             
             
             
             
            profileRefreshToken &+= 1
            if !command.isConnected { Task { await nodes.refresh() } }
        }
        .onChange(of: profiles.isActivating) { activating in
             
             
             
             
             
             
             
            guard !activating else { return }
            profileRefreshToken &+= 1
            if !command.isConnected { Task { await nodes.refresh() } }
        }
        .onOpenURL { url in


            if let route = ClashSystemRoute(url: url) {
                handleSystemRoute(route)
            } else if let module = ModuleInstallLink.moduleLink(from: url) {
                openAddModule(with: module)
            } else {
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                answerHandoff(profileImports.open(url))
            }
        }
         
         
         
        .environment(\.proxyShareAppModel, proxyShare)
        .environment(\.proxyShareProfiles, profiles)
         
        .environment(\.externalControllerCore, ExternalControllerCore.live(vpn: vpn, profiles: profiles))
        .environment(\.clashThroughputUnit, throughputUnit)
         
         
         
        .onReceive(NotificationCenter.default.publisher(for: .clashModeChosenElsewhere).receive(on: RunLoop.main)) { _ in
            guard scenePhaseWitness.phase == .active, pendingOutboundMode == nil,
                  let raw = ClashWidgetFactsPublisher.takeModeChosenOnACard() else { return }
            pendingOutboundMode = raw
        }
        .onReceive(NotificationCenter.default.publisher(for: ClashThroughputUnit.didChangeNotification)) { _ in
            throughputUnit = ClashThroughputUnit.stored(in: GlobalConfig.appGroupDefaults)
             
            WidgetCenter.shared.reloadAllTimelines()
        }
         
         
         
         
         
         
         
        .environment(\.configurationLinkedPage, ConfigurationLinkedPages(from: [proxyShare, profiles, command]) {
            [proxyShare, profiles, command] page in
            switch page {
            case .owner(.lanSharing):
                return AnyView(ProxyShareView(model: proxyShare))
            case .owner(.clientSettings):
                return AnyView(ConfigurationClientSettingsPage(profiles: profiles, command: command))
            case .owner:
                return nil
            }
        })
    }

     
     
     
    @ViewBuilder
    private func shellSheetContent(for sheet: ShellSheet) -> some View {
            switch sheet.kind {
            case .profileCenter:
                ShellProfileCenter(
                    profiles: profiles,
                    importRouter: profileImports,
                    initialDestination: profileCenterDestination ?? .profiles,
                    ownsNavigationContainer: true,
                    onActiveRuntimeChanged: activeRuntimeDidChange,
                    selections: command
                )
                .equatable()
                .clashPageSizedSheet()
                .onAppear { presentationRecovery.noteAppeared() }
            case .profilePicker:
                profilePickerSheet
            case .runtimeInspector:
                runtimeInspectorSheet
            }
    }

     
    private var runtimeInspectorSheet: some View {
        ClashFeatureNavigationContainer {
            compactRuntimeInspectorContent
                .clashToolbarUnlessInPanel {
                    ToolbarItem(placement: .cancellationAction) {
                         
                         
                        ClashSheetCloseButton {
                            navigationState.navigate(to: .home)
                        }
                        .accessibilityIdentifier(
                            "compact.runtime-inspector.done"
                        )
                    }
                }
        }
    }

     
    private var profilePickerSheet: some View {
        ClashFeatureNavigationContainer {
            ClashProfilePickerCard(
                items: profiles.profiles.map {
                    ClashClientUI.ClashProfilePickerItem(
                        id: $0.id,
                        label: $0.label,
                        isCurrent: $0.id == profiles.activeProfileID,
                        isSwitching: $0.id == profiles.busyProfileID
                    )
                },
                onPick: { pickProfile($0) },
                onClose: { closeProfilePicker() }
            )
             
             
             
            .clashSheetPresentation()
        }
        .alert(
            isPresented: Binding(
                get: { pickerSwitchFailure != nil },
                set: { if !$0 { pickerSwitchFailure = nil } }
            ),
            error: pickerSwitchFailure
        ) { _ in
            Button("OK", role: .cancel) { pickerSwitchFailure = nil }
        } message: { failure in
            Text(verbatim: failure.messageText)
        }
        .onAppear { presentationRecovery.noteAppeared() }
    }

     
    private func closeProfilePicker() {
        isPickingProfile = false
    }

    private var debugGateShell: some View {
        goldenFlowShell
    }


    private var goldenFlowShell: some View {
        Group {
            switch shellLayout {
            case .compactTabs:
                compactTabShell
            case .regularSidebar:
                regularSidebarShell
            }
        }
         
         
        .environment(\.clashShellLayout, shellLayout)

         
         
         
        .onChange(of: shellLayout) { layout in
            switch layout {
            case .compactTabs:
                guard let handoff = AppShellLayoutSelector.compactHandoff(
                    for: navigationState.selectedRoot
                ) else { return }
                switch handoff {
                case .proxiesSheet: pendingSessionPage = .proxies
                case .rulesSheet: pendingSessionPage = .rules
                case .profileCenter:
                    profileSheets.narrow(into: handoff)
                    profileCentreTakesTheSheet()
                    presentationRecovery.noteRaised()
                }
            case .regularSidebar:
                 
                 
                 
                 
                guard let root = profileSheets.widen(sessionPage: compactSessionPage)
                else { return }
                compactSessionPage = nil
                navigationState.selectRoot(root)
            }
        }
         
         
        .onChange(of: profileCenterDestination) { destination in
            if destination != nil { profileCentreTakesTheSheet() }
        }
    }

    private var shellLayout: AppShellLayout {
        AppShellLayoutSelector.layout(
            isPad: UIDevice.current.userInterfaceIdiom == .pad,
            hasRegularHorizontalSize: horizontalSizeClass == .regular
        )
    }

    private var compactTabShell: some View {
        TabView(selection: appTabSelection) {
            homeRoot
            .tabItem {
                 
                 
                Label {
                    Text("Home")
                } icon: {
                    ClashSymbolImage(symbol: .catCircleFill)
                }
            }
            .tag(AppTab.home)

            utilitiesRoot(ownsNavigationContainer: true)
                .tabItem { Label("Utilities", systemImage: ClashSymbol.briefcaseCircleFill.name) }
                .tag(AppTab.utilities)

            moreRoot(ownsNavigationContainer: true)
            .tabItem { Label("More", systemImage: ClashSymbol.ellipsisCircleFill.name) }
            .tag(AppTab.more)
        }
        .accessibilityIdentifier("app.compact-tabs")
    }

    @ViewBuilder
    private var regularSidebarShell: some View {
        ClashClientUI.ClashRegularClientShell(
            navigationState: sharedRegularNavigationBinding,
            sidebarBehavior: .locked,
            background: ClashTheme.canvas,
            sidebarBackground: ClashTheme.surface
        ) { destination in
            ClashSymbolImage(
                symbol: destination.symbol,
                resizesToFit: true
            )
        } rootContent: { destination in
            regularRoot(for: destination)
        } destinationContent: { destination in
            regularDestination(for: destination)
        }
        .modifier(RegularSidebarTitleStyle())
    }

     
     
     
     
     
     
    private func openRailProxies(_ group: String?, _ opening: ProxyBrowsingVisibility.Opening) {
        railProxiesGroup = group
        railProxiesOpening = opening
        railProxiesRequest = ClashClientUI.ClashRootOpenGroupSignal(
            token: railProxiesRequest.token &+ 1, group: group,
            opening: opening == .choosingInGlobal ? .choosingInGlobal : .browsing)
        navigate(to: .proxies)
    }

     
     
    private var sharedRegularNavigationBinding:
        Binding<ClashClientUI.AppleClientNavigationState>
    {
        Binding(
            get: { navigationState },
            set: { next, transaction in
                if next.selectedRoot != navigationState.selectedRoot {
                    presentationRecovery.supersede()
                }
                withTransaction(transaction) { navigationState = next }
            }
        )
    }

    @ViewBuilder
    private func regularRoot(
        for destination: ClashClientUI.ClashRootDestination
    ) -> some View {
        switch destination {
        case .home:
            homeRoot
         
         
         
        case .profiles:
            ShellProfileCenter(
                profiles: profiles,
                importRouter: profileImports,
                initialDestination: .profiles,
                ownsNavigationContainer: false,
                onActiveRuntimeChanged: activeRuntimeDidChange,
                selections: command
            )
            .equatable()
         
         
         
        case .proxies:
            SessionProxiesRailRoot(
                vpn: vpn,
                command: command,
                nodes: nodes,
                profiles: profiles,
                profileRefreshToken: profileRefreshToken,
                avoidsLiveProviderStore: false,
                stagedGroup: $railProxiesGroup,
                stagedOpening: $railProxiesOpening
            )
            .environment(\.clashRegularRootOpenGroup, railProxiesRequest)
        case .rules:
            SessionRulesRailRoot(
                command: command,
                canInspectActiveRules: command.isConnected,
                profiles: profiles,
                openProxiesGroup: { group in
                    openRailProxies(group, .browsing)
                }
            )
         
         
        case .activity:
            regularDestination(for: .utilities(.activity))
         
         
         
         
        case .utilities:
            utilitiesRoot(ownsNavigationContainer: false)
        case .more:
            moreRoot(ownsNavigationContainer: false)
        case .about:
            regularDestination(for: .more(.about))
        }
    }

    @ViewBuilder
    private func regularDestination(
        for destination: ClashClientUI.AppleClientDestination
    ) -> some View {
        switch destination {
        case .activeRules:
            ActiveRulesView(command: command)
        case .dnsQuery:
            DNSQueryView(command: command)
        case .utilities(let item):
             
             
            GoldenFlowUtilitiesDestinationAdapter(
                vpn: vpn,
                command: command,
                connections: connections,
                networkQuality: networkQuality,
                stun: stun,
                proxyShare: proxyShare,
                destination: item,
                activityLens: $activityLens,
                usesRegularDetailLayout: true
            )
            .equatable()
        case .more(let item):
            GoldenFlowMoreDestinationAdapter(
                vpn: vpn,
                command: command,
                preferences: preferences,
                destination: item,
                usesRegularDetailLayout: true
            )
        default:
             
             
             
             
            homeRoot
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private var secondPresenter: some View {
        WindowSheetPresenter(
            item: profileSheets.item(on: .second, inspector: compactRuntimeInspectorPresentation.wrappedValue),
            dropClaim: { secondPresenterItem.wrappedValue = nil },
            onDismiss: activeRuntimeDidChange
        ) { sheet in
            Group {
                switch sheet {
                case .centre(let destination):
                    ShellProfileCenter(
                        profiles: profiles,
                        importRouter: profileImports,
                        initialDestination: destination,
                        ownsNavigationContainer: true,
                        onActiveRuntimeChanged: activeRuntimeDidChange,
                        selections: command
                    )
                    .equatable()
                    .clashPageSizedSheet()
                    .onAppear { presentationRecovery.noteAppeared() }
                case .picker:
                    profilePickerSheet
                case .inspector:
                    runtimeInspectorSheet
                }
            }
        }
    }

     
     
    private var secondPresenterItem: Binding<ProfileSheetState.Sheet?> {
        Binding(
            get: {
                profileSheets.item(on: .second, inspector: compactRuntimeInspectorPresentation.wrappedValue)
            },
            set: { presented in
                guard presented == nil, profileSheets.presenter == .second else { return }
                profileSheets.drop()
                if compactRuntimeInspectorPresentation.wrappedValue {
                    navigationState.navigate(to: .home)
                }
            }
        )
    }

    private var homeRoot: some View {
        GoldenFlowHomeAdapter(
            vpn: vpn,
            command: command,
            nodes: nodes,
            stats: stats,
            profiles: profiles,
            profileRefreshToken: profileRefreshToken,
            pendingSessionPage: $pendingSessionPage,
            sessionPresentation: $compactSessionPage,
            pendingOutboundMode: $pendingOutboundMode,
            presentationRecovery: presentationRecovery,
             
             
            openThroughDoor: { door, open in openThroughDoor(door, open) },
            openProfiles: {
                 
                 
                 
                 
                 
                 
                 
                 
                 
                if shellLayout == .regularSidebar, ProfileCenterPolicy.hasUserProfile(profiles.profiles) {
                    isPickingProfile = true
                } else {
                    navigate(to: .profiles)
                }
            },
             
             
            openProxies: { openRailProxies(nil, .browsing) },
             
            openProxiesToChooseInGlobal: {
                openRailProxies(GlobalProxySelectionPolicy.groupName, .choosingInGlobal)
            },
            openRules: { navigate(to: .rules) },
            openActiveRules: { navigate(to: .activeRules) },
            openOnDemand: { navigate(to: .more(.onDemand)) },
            openLogs: {
                 
                 
                 
                 
                activityLens = .logs
                navigate(to: .utilities(.activity))
            },
            openDNSQuery: { navigate(to: .dnsQuery) },
            rebind: rebind
        )
    }

    private func utilitiesRoot(ownsNavigationContainer: Bool) -> some View {
        GoldenFlowUtilitiesAdapter(
            vpn: vpn,
            command: command,
            connections: connections,
            networkQuality: networkQuality,
            stun: stun,
            proxyShare: proxyShare,
            destination: utilitiesDestinationSelection,
            activityLens: $activityLens,
            ownsNavigationContainer: ownsNavigationContainer
        )
    }

    private func moreRoot(ownsNavigationContainer: Bool) -> some View {
        GoldenFlowMoreAdapter(
            vpn: vpn,
            command: command,
            preferences: preferences,
            destination: moreDestinationSelection,
            ownsNavigationContainer: ownsNavigationContainer,
             
             
             
            navigate: { destination in
                openThroughDoor("more.attention") { navigate(to: destination) }
            }
        )
    }

    private var appTabSelection: Binding<AppTab> {
        Binding(
            get: { Self.compactTab(for: navigationState.selectedRoot) },
            set: { tab in
                 
                ReaderSelection.select(Self.tabRoot(for: tab), in: &navigationState, recovery: presentationRecovery)
            }
        )
    }

     
     
     
     
     
     
    private static func compactTab(
        for root: ClashClientUI.ClashRootDestination
    ) -> AppTab {
        switch root {
        case .home, .proxies, .rules, .profiles: .home
        case .activity, .utilities: .utilities
        case .more, .about: .more
        }
    }

    private static func tabRoot(
        for tab: AppTab
    ) -> ClashClientUI.ClashRootDestination {
        switch tab {
        case .home: .home
        case .utilities: .utilities
        case .more: .more
        }
    }

    private var utilitiesDestinationSelection: Binding<AppNavigationDestination.UtilitiesDestination> {
        Binding(
            get: {
                guard case .utilities(let destination) = navigationState.destination else {
                    return .root
                }
                return destination
            },
            set: { destination in
                navigationState.navigate(
                    to: .utilities(destination)
                )
            }
        )
    }

    private var moreDestinationSelection: Binding<AppNavigationDestination.MoreDestination> {
        Binding(
            get: {
                guard case .more(let destination) = navigationState.destination else {
                    return .root
                }
                return destination
            },
            set: { destination in
                navigationState.navigate(to: .more(destination))
            }
        )
    }

     
     
     
     
     
     
     
    private enum ShellSheetKind {
        case profileCenter
        case profilePicker
        case runtimeInspector
    }

     
    private struct ShellSheet: Identifiable {
        let kind: ShellSheetKind
        var id: Int {
            switch kind {
            case .profileCenter: return 0
            case .profilePicker: return 1
            case .runtimeInspector: return 2
            }
        }
    }

    private var shellSheetKind: ShellSheetKind? {
        switch profileSheets.item(on: .shell, inspector: compactRuntimeInspectorPresentation.wrappedValue) {
        case .centre: return .profileCenter
        case .picker: return .profilePicker
        case .inspector: return .runtimeInspector
        case nil: return nil
        }
    }

     
     
     
     
     
     
     
     
     
     
    private var shellSheet: Binding<ShellSheet?> {
        Binding(
            get: { shellSheetKind.map(ShellSheet.init(kind:)) },
            set: { presented in
                guard presented == nil else { return }
                 
                 
                guard profileSheets.presenter == .shell else { return }
                profileSheets.drop()
                if compactRuntimeInspectorPresentation.wrappedValue {
                    navigationState.navigate(to: .home)
                }
            }
        )
    }

    private var profileCenterPresentation: Binding<Bool> {
        Binding(
            get: { profileCenterDestination != nil },
            set: { isPresented in
                guard !isPresented else { return }
                profileCenterDestination = nil
            }
        )
    }

    private var compactRuntimeInspectorPresentation: Binding<Bool> {
        Binding(
            get: {
                guard shellLayout == .compactTabs else {
                    return false
                }
                switch navigationState.destination {
                case .activeRules, .dnsQuery:
                    return true
                default:
                    return false
                }
            },
            set: { isPresented in
                guard !isPresented else {
                    return
                }
                navigationState.navigate(to: .home)
            }
        )
    }

    @ViewBuilder
    private var compactRuntimeInspectorContent: some View {
        switch navigationState.destination {
        case .activeRules:
            ActiveRulesView(command: command)
        case .dnsQuery:
            DNSQueryView(command: command)
        default:
            EmptyView()
        }
    }

    private func restoreTunnelControlSession() async {
        await vpn.refreshSystemVPNInstallation()
         
         
        rebind()
    }

    private func rebind() {
        ClashPerf.measure("shell.rebind") {
             
             
             
            command.bind(sessionProvider: { [weak vpn] in vpn?.session })
            command.bind(session: vpn.session)
            command.sync(vpnStatus: vpn.status)
            stats.bind(session: vpn.session, command: command)
            ClashPerf.measure("shell.rebind.nodes") {
                nodes.bind(command: command)
            }
        }
    }

    private func activeRuntimeDidChange() {
        profileRefreshToken &+= 1
         
         
        nodes.noteRouteChanged()
         
         
        nodeListRereads.ask { await nodes.refresh() }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private func watchForPendingCompiles(_ inFront: Bool) {
        guard inFront else {
            pendingCompileWatcher.stop()
            return
        }
        pendingCompileWatcher.start(directory: ProviderRefreshStateWatcher.stateDirectory) {
             
             
            guard command.isConnected, scenePhaseWitness.phase == .active,
                  let container = ClashAppIdentifiers.appGroupContainer
            else { return }
            command.startPendingCompiles(container: container)
            profiles.publishWhatOnlyAPublicationTakes(container: container)
        }
    }

    private func syncConnectionsForSelectedTab(
        isForeground: Bool? = nil,
        isConnected: Bool? = nil,
        tunnelIsUp: Bool? = nil,
        channelFailed: Bool? = nil
    ) {
        connections.syncScene(
            isConnected: isConnected ?? command.isConnected,
            tunnelIsUp: tunnelIsUp ?? command.tunnelIsUp,
            channelFailed: channelFailed ?? command.channelAttachFailed,
            isActive: isForeground ?? (scenePhase == .active),
            isBackground: isForeground == nil ? scenePhase == .background : isForeground == false
        )
    }

    private func checkSharedImports() {
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        answerHandoff(profileImports.importSharedFiles())
    }

     
     
    private func answerHandoff(_ check: Task<ProfileImportOutcome, Never>?) {
        guard let check else { return }
        handoffChecksInFlight += 1
        Task { @MainActor in
            let outcome = await check.value
            handoffChecksInFlight -= 1
            guard !outcome.isEmpty else { return }
            handoffCentre.note(outcome, centreOnScreen: !profileImports.centresOnScreen.isEmpty)
            handoffAnswers &+= 1
        }
    }

     
     
     
     
    private func raiseCentreForHandoffOnceSettled() {
        guard handoffCentre.owed else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(LostPresentationRecovery.settle * 1_000_000_000))
            handoffAnswers &+= 1
        }
    }

     
     
     
     
     
     
    private func raiseCentreForHandoffAfterThisTurn() {
        DispatchQueue.main.async {
            raiseCentreForHandoff(sceneIsActive: scenePhaseWitness.phase == .active)
        }
    }

     
    private func raiseCentreForHandoff(sceneIsActive: Bool) {
        guard handoffCentre.raiseIsDue(
            sceneIsActive: sceneIsActive,
            confirmationPending: profileImports.pendingConfirmation != nil,
            routerHoldsSomething: profileImports.pendingImport != nil
                || !profileImports.untoldRefusals.isEmpty
        ) else { return }
         
        navigate(to: .profiles)
    }

    private func handlePendingSystemAction() {
        guard let route = systemHandoff.consume() else { return }
        ClashLogStore.shared.append("system handoff consumed -> \(String(describing: route))", stream: .app, level: .warning)
        handleSystemRoute(route)
    }

    private func handleSystemRoute(_ route: ClashSystemRoute) {
        openSystemRoutePage(route)
        switch route {
        case .open:
            break
        case .vpn(let action):
            Task {
                 
                 
                 
                 
                 
                await vpn.ensureStatusLoaded()
                switch ClashSystemVPNPolicy.command(
                    for: action,
                    isActive: ClashSystemVPNPolicy.isActive(vpn.status)
                ) {
                case .start:
                     
                     
                     
                    let started = await vpn.start(
                        origin: .programmatic, waitsForPublication: true, userInitiated: true)
                    if !started {
                         
                         
                         
                         
                         
                        await vpn.refreshLastDisconnectErrorAfterFailedStart()
                    }
                case .stop:
                    await vpn.stop(origin: .programmatic)
                case .unchanged:
                    break
                }
            }
        case .mode(let mode):
             
             
             
             
             
             
             
            let intent = ModeIntentClock.next()
             
             
             
             
             
             
             
             
             
             
             
            if mode != .global { pendingOutboundMode = mode.rawValue }
            Task {
                 
                 
                 
                await vpn.ensureStatusLoaded()
                 
                 
                 
                if !ClashSystemVPNPolicy.isActive(vpn.status) {
                    await vpn.start(origin: .programmatic, waitsForPublication: true, userInitiated: true)
                }
                rebind()
                for _ in 0..<100 where !command.isConnected {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                guard ModeIntentClock.isCurrent(intent) else { return }
                if mode == .global {
                    pendingOutboundMode = mode.rawValue
                    return
                }
                await command.setMode(mode.rawValue)
            }
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
    private func openSystemRoutePage(_ route: ClashSystemRoute) {
         
         
         
        let page = DeferredPage(
            destination: route.navigationDestination,
            opensTheLogs: route == .open(.logs),
            at: Date()
        )
        guard UIApplication.shared.applicationState == .active else {
            deferredRoutePage = page
            return
        }
        open(page)
    }

     
     
     
     
    private func openAddModule(with link: String) {
        let request = ModulePageModel.shared.addRequest
        request.request(link: link)
        guard !request.isPageOnScreen else { return }
        navigate(to: .modules)
    }

     
     
     
    private func openDeferredPage() {
        let fresh = { (page: DeferredPage?) in
            page.flatMap {
                abs(Date().timeIntervalSince($0.at)) <= ClashSystemHandoff.pendingRouteLifetime ? $0 : nil
            }
        }
        let route = fresh(deferredRoutePage)
        let centre = fresh(deferredCentrePage)
        deferredRoutePage = nil
        deferredCentrePage = nil
        let held = AppShellNavigationRouter.heldPagesToOpen(
            route: route, centre: centre, handoffCentrePending: handoffCentreIsPendingOrShowing
        )
        if let dropped = held.dropped {
            ClashLogStore.shared.append(
                "held route dropped for the import centre  route=\(dropped.destination)",
                stream: .app, level: .warning
            )
        }
        for page in held.open { open(page) }
    }

     
     
    private var handoffCentreIsPendingOrShowing: Bool {
        deferredCentrePage != nil
            || handoffCentre.owed
            || handoffChecksInFlight > 0
            || (!profileImports.centresOnScreen.isEmpty
                && (profileImports.pendingImport != nil || !profileImports.untoldRefusals.isEmpty))
    }

    private func open(_ page: DeferredPage) {
        navigate(to: page.destination)
        if page.opensTheLogs { activityLens = .logs }
         
         
        if page.confirmsAppearance { confirmTheSheetCameUp() }
    }

     
     
     
     
     
    private func pickProfile(_ id: String) {
        guard id != profiles.activeProfileID else {
            closeProfilePicker()
            return
        }
        guard let profile = profiles.profiles.first(where: { $0.id == id })
        else { return }
        Task {
            if await profiles.selectAndWait(profile) {
                activeRuntimeDidChange()
#if canImport(UIKit)
                UINotificationFeedbackGenerator()
                    .notificationOccurred(.success)
#endif
                closeProfilePicker()
            } else if let failure = profiles.lastFailure {
                 
                 
                pickerSwitchFailure = ProfileSwitchAlertFailure(failure)
            }
        }
    }

     
     
     
     
    private func openThroughDoor(_ door: String, _ open: @escaping @MainActor () -> Void) {
        presentationRecovery.door(
            door,
            shell: shellClaims,
            afterHealing: { confirmTheSheetCameUp() },
             
             
             
             
             
            healedAgain: {
                profileSheets.presenter = .second
                PresentationEvidence.record(.healedAgain, door: door)
            },
            open
        )
    }

     
     
     
     
     
     
     
     
    private func confirmTheSheetCameUp() {
        guard profileSheets.presenter == .shell else { return }
        guard let claim = profileSheets.claim else {
             
             
            deferredCentrePage?.confirmsAppearance = true
            return
        }
        let root = navigationState.selectedRoot
         
         
         
         
        let stillAsked = {
            profileSheets.claim == claim
                && navigationState.selectedRoot == root
                && UIApplication.shared.applicationState == .active
        }
        presentationRecovery.confirmAppearance(stillAsked: stillAsked) {
            ClashLogStore.shared.append(
                "lost presentation recovered via second presenter  sheet=\(claim)"
                    + "  presented=\(ShellPresentationProbe.describe() ?? "-")"
                    + "  " + PresentationEvidence.windows(),
                stream: .app, level: .warning
            )
            PresentationEvidence.captureSystemLog(reason: .secondPresenterTakesOver)
             
             
             
            _ = profileSheets.fallBack()
            presentationRecovery.raise(
                afterClearing: true,
                unless: {
                    profileSheets.claim != nil
                        || navigationState.selectedRoot != root
                        || UIApplication.shared.applicationState != .active
                }
            ) {
                profileSheets.raise(claim)
            }
        }
    }

     
    private var shellClaims: LostPresentationRecovery.Claims {
        LostPresentationRecovery.Claims(
            kinds: { shellClaimKinds },
            clear: { dropShellClaims() },
            place: { AnyHashable(navigationState.selectedRoot) }
        )
    }

     
    private var shellClaimKinds: [String] {
        var kinds: [String] = []
        let presenter = profileSheets.presenter == .second ? "@second" : ""
        if let profileCenterDestination {
            kinds.append("profileCenter(\(profileCenterDestination))\(presenter)")
        }
        if isPickingProfile { kinds.append("profilePicker\(presenter)") }
        if compactRuntimeInspectorPresentation.wrappedValue {
            kinds.append("runtimeInspector(\(navigationState.destination))\(presenter)")
        }
        return kinds
    }

     
    private func dropShellClaims() {
        profileSheets.drop()
        if compactRuntimeInspectorPresentation.wrappedValue {
            navigationState.navigate(to: .home)
        }
    }

     
     
     
     
     
     
    private func profileCentreTakesTheSheet() {
        if isPickingProfile { isPickingProfile = false }
        if compactRuntimeInspectorPresentation.wrappedValue {
            navigationState.navigate(to: .home)
        }
    }

    private func navigate(
        to destination: ClashClientUI.AppleClientDestination
    ) {
         
         
         
         
        if UIApplication.shared.applicationState != .active,
           AppShellNavigationRouter.raisesTheProfileCentre(destination, layout: shellLayout) {
            deferredCentrePage = DeferredPage(destination: destination, opensTheLogs: false, at: Date())
            return
        }
         
         
         
        presentationRecovery.supersede()
         
         
        profileSheets.route(to: destination, layout: shellLayout, navigationState: &navigationState)
        if profileCenterDestination != nil { profileCentreTakesTheSheet() }
        if !shellClaimKinds.isEmpty { presentationRecovery.noteRaised() }
         
         
         
         
         
         
         
         
        if destination == .proxies, shellLayout == .compactTabs {
            pendingSessionPage = .proxies
        }
    }

     
     
     
     
     
     
     
    private func handleVPNStatusTransition(_ status: String) {
         
         
         
        command.bind(session: vpn.session)
         
         
         
         
        stats.bind(session: vpn.session, command: command)
        stats.tunnelStatusChanged(status)
        command.sync(vpnStatus: status)
        publishVPNControlSnapshot(status: status)
         
        ModuleAppScriptDriver.shared.tunnelStatusChanged(status)
         
         
         
         
         
         
         
         
         
         
         
         
         
        guard status == "connected" || status == "disconnected",
              status != lastRouteNotedVPNStatus else { return }
        lastRouteNotedVPNStatus = status
        nodes.noteRouteChanged()
    }

    private func publishVPNControlSnapshot(status: String) {
        guard let active = ClashSystemVPNPolicy.controlSnapshot(
            status: status,
            isLoaded: vpn.hasLoadedStatus
        ) else { return }
        systemHandoff.setVPNSnapshot(active: active)
         
         
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 18.0, *) {
            ControlCenter.shared.reloadControls(
                ofKind: ClashSystemHandoff.controlKind
            )
        }
    }
}

 
 
 
 
 
 
private struct RegularSidebarTitleStyle: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.toolbarTitleDisplayMode(.large)
        } else {
            content.navigationBarTitleDisplayMode(.large)
        }
    }
}

 
 
 
 
 
 
 
 
 
struct ShellProfileCenter: View, Equatable {
    let profiles: ProfilesViewModel
    let importRouter: ProfileImportRouter
    let initialDestination: AppNavigationDestination
    let ownsNavigationContainer: Bool
     
     
    let onActiveRuntimeChanged: () -> Void
     
     
    let selections: ClashCommandClient

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.profiles === rhs.profiles
            && lhs.importRouter === rhs.importRouter
            && lhs.initialDestination == rhs.initialDestination
            && lhs.ownsNavigationContainer == rhs.ownsNavigationContainer
            && lhs.selections === rhs.selections
    }

    var body: some View {
        ProfileCenterView(
            profiles: profiles,
            importRouter: importRouter,
            initialDestination: initialDestination,
            ownsNavigationContainer: ownsNavigationContainer,
            onActiveRuntimeChanged: onActiveRuntimeChanged,
            selections: selections
        )
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
private struct WindowSheetPresenter<Item: Identifiable, Content: View>: UIViewControllerRepresentable {
    let item: Item?
     
    let dropClaim: () -> Void
    let onDismiss: () -> Void
    @ViewBuilder let content: (Item) -> Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIViewController {
        let anchor = UIViewController()
        anchor.view.backgroundColor = .clear
        anchor.view.isUserInteractionEnabled = false
        return anchor
    }

    func updateUIViewController(_ anchor: UIViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.dropClaim = dropClaim
        coordinator.onDismiss = onDismiss
        let shown = item
        let root = AnyView(
            Color.clear
                .clashSheet(
                    item: Binding(
                        get: { shown },
                        set: { [weak coordinator] in if $0 == nil { coordinator?.sheetDroppedItsClaim() } }
                    ),
                    onDismiss: { [weak coordinator] in coordinator?.sheetDismissed() }
                ) { sheet in
                     
                     
                    content(sheet)
                        .clashModalPresentation(.page)
                }
                .environment(\.self, context.environment)
        )
        coordinator.update(item: item, root: root, scene: anchor.view.window?.windowScene)
    }

    static func dismantleUIViewController(_ anchor: UIViewController, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    @MainActor
    final class Coordinator {
        var dropClaim: () -> Void = {}
        var onDismiss: () -> Void = {}
        private var window: UIWindow?
        private var host: UIHostingController<AnyView>?
        private(set) var item: Item?
         
         
        private var claimDropped = false
        private weak var keyBefore: UIWindow?
         
         
        private var generation = 0

        func update(item: Item?, root: AnyView, scene: UIWindowScene?) {
            let raised = self.item == nil && item != nil
            let dropped = self.item != nil && item == nil
             
             
            let switched = self.item != nil && item != nil && self.item?.id != item?.id
            if raised || dropped || switched { generation &+= 1 }
            self.item = item
            if item != nil { claimDropped = false }
            if let host {
                 
                 
                 
                host.rootView = root
                if raised || switched { confirmPresented() }
                if dropped {
                     
                     
                    if host.presentedViewController == nil {
                        tearDown()
                    } else {
                        confirmGone()
                    }
                }
                return
            }
            guard let item else { return }
            guard let scene else {
                ClashLogStore.shared.append("lost presentation: second presenter has no scene  sheet=\(item)",
                                            stream: .app, level: .warning)
                return
            }
             
             
             
            let shell = scene.keyWindow.flatMap { $0 is PassthroughWindow ? nil : $0 }
                ?? scene.windows.first { window in
                    !(window is PassthroughWindow)
                        && window.rootViewController.map { String(describing: type(of: $0)).contains("HostingController") } == true
                }
            let window = PassthroughWindow(windowScene: scene)
             
            window.windowLevel = .normal + 1
            window.backgroundColor = .clear
             
             
             
             
            window.overrideUserInterfaceStyle = shell?.overrideUserInterfaceStyle ?? .unspecified
            if let tint = shell?.tintColor { window.tintColor = tint }
            let host = UIHostingController(rootView: root)
            host.view.backgroundColor = .clear
            window.rootViewController = host
            keyBefore = shell
            window.makeKeyAndVisible()
            self.window = window
            self.host = host
            confirmPresented()
        }

         
         
         
         
        private func confirmPresented() {
            let raise = generation
             
             
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, raise == self.generation, let host = self.host, self.item != nil,
                      host.presentedViewController == nil else { return }
                ClashLogStore.shared.append(
                    "lost presentation: second presenter's window did not present  sheet=\(String(describing: self.item))  "
                        + PresentationEvidence.windows(),
                    stream: .app, level: .warning
                )
                PresentationEvidence.captureSystemLog(reason: .windowDidNotPresent)
                self.dropClaim()
                self.tearDown()
            }
        }

         
         
        private func confirmGone() {
            let drop = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, drop == self.generation, self.item == nil, self.window != nil else { return }
                self.tearDown()
            }
        }

        func sheetDroppedItsClaim() {
            claimDropped = true
            dropClaim()
        }

         
         
        func sheetDismissed() {
            guard item == nil || claimDropped else { return }
            tearDown()
        }

        func tearDown() {
            guard let window else { return }
            generation &+= 1
            self.window = nil
            host = nil
            item = nil
            claimDropped = false
            let restore = keyBefore
             
             
            let heldTheKey = window.isKeyWindow
            window.isHidden = true
            window.rootViewController = nil
            if heldTheKey, let restore, restore.windowScene != nil, !restore.isHidden {
                restore.makeKey()
            }
             
            let onDismiss = onDismiss
            DispatchQueue.main.async { onDismiss() }
        }
    }
}

 
 
 
private struct ScriptNotificationPagePresenter: View {
    @ObservedObject var pages: ModuleScriptNotificationPages

    var body: some View {
        WindowSheetPresenter(item: pages.shown, dropClaim: { pages.close() }, onDismiss: {}) { text in
            ModuleScriptNotificationPage(text: text) { pages.close() }
        }
    }
}

 
private final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
         
         
         
        if let root = rootViewController?.view, hit.isDescendant(of: root) { return nil }
        return hit
    }
}

 
private struct DeferredPage {
    let destination: AppNavigationDestination
    let opensTheLogs: Bool
    let at: Date
     
     
    var confirmsAppearance = false
}

 
 
 
 
private struct ConfigurationClientSettingsPage: View {
    @ObservedObject var profiles: ProfilesViewModel
    let command: ClashCommandClient

    var body: some View {
        let active = profiles.profiles.first { $0.id == profiles.activeProfileID }
        ClientSettingsView(
            command: command,
            activeProfileUDPFallback: active?.udpFallbackPolicy,
            activeProfileUDPFallbackGuardInput: { [profiles] in
                guard let active = profiles.profiles.first(where: { $0.id == profiles.activeProfileID }) else { return nil }
                return await profiles.udpFallbackGuardInput(for: active)
            }
        ) {
            profiles.restageForClientRuntimeSetting()
        }
    }
}

 
private final class ScenePhaseWitness {
    var phase: ScenePhase = .inactive
     
     
    var heardAChange = false
}



 
 
 
@MainActor
final class ConnectionsModelOwner: ObservableObject {
    let model = ConnectionsModel()
}
