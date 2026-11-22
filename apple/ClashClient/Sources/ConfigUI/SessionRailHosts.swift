import Combine
import ClashClientKit
import ClashClientUI
import SwiftUI
#if canImport(AppKit) && !canImport(UIKit)
import AppKit
import ClashMacClient
#endif

 
 
 
 
 
 
 
 
 
 
 
 
struct ProxiesMacGroupPages {
    var group: (_ profileID: String, _ name: String) -> AnyView
    var list: (_ profileID: String) -> AnyView
    var newGroup: (_ profileID: String, _ close: @escaping () -> Void) -> AnyView
    var delete: (_ profileID: String, _ name: String) -> Void
     
     
     
    var attach: (_ reorderGroups: (() -> Void)?, _ updateNodeSources: (() -> Void)?,
                 _ openNodeSources: (() -> Void)?) -> Void = { _, _, _ in }
     
     
    var openNodeSource: ((String) -> Void)? = nil
    var originalNode: ((String, String, @escaping () -> Void, @escaping () -> Void) -> AnyView)? = nil
     
     
     
    var offerUndo: (@MainActor (_ title: ClashDisplayText, _ actionName: ClashDisplayText, _ label: String, _ operation: String,
                                _ restore: @escaping @MainActor () async throws -> Void) -> Void)? = nil
}

struct ProxiesOverviewHost: View {
    @ObservedObject var vpn: VPNController
     
     
     
     
     
     
     
     
    let command: ClashCommandClient
    @ObservedObject var nodes: NodesModel
    @ObservedObject var profiles: ProfilesViewModel
    let isConnected: Bool
    let mode: String
    let profile: Profile
    let sourceModel: ProxiesOverviewModel
    let initiallyExpandedGroup: String?
    var ownsNavigationContainer = true
     
     
     
    var opening: ProxyBrowsingVisibility.Opening = .browsing
     
     
     
     
     
    var reprepare: (() -> Void)? = nil
     
     
     
    var macNodeSourcesPage: ((String) -> AnyView)? = nil
     
    var macGroupPages: ProxiesMacGroupPages? = nil
     
     
     
     
    var isConfigurationsPage = false
    @Environment(\.locale) private var locale
#if !os(iOS)
     
    @Environment(\.clashPushRoute) private var pushRoute
     
    @State private var addingGroup = false
     
     
    @State private var macSelfBuiltNodes: [String] = []
     
     
    @State private var macRemovableNodes: [String] = []
#endif
    @State private var providerUpdateFailure: ClashDisplayText?
     
     
    @State private var providerUpdateDeferred: ClashDisplayText?
     
    @State private var inspectingNode: ProxyNodeInspection?
     
     
     
     
     
     
    @State private var offersNodeEditing = false
    @Environment(\.clashFeedback) private var feedback
     
     
     
    @State private var scriptRun: ClashNodeScriptResult?
     
    @State private var scriptTask: Task<Void, Never>?
     
     
     
     
    @State private var pageConfiguration: ProxiesPageConfiguration?
#if os(iOS)
     
    @ObservedObject private var appScripts = ModuleAppScriptRunner.shared
     
    @State private var addingNodes = false
     
     
    @State private var policyGroupSheet: ConfigurationPolicyGroupSheet.Opening?
#endif
     
     
     
    @State private var ownRefusals: [String: ClashGroupActionRefusal] = [:]

    var body: some View {
        ClashPerf.measure("proxies.host.body") {
            hosted
                .clashProductModal(item: $inspectingNode, role: .form) { inspection in
                    nodeDetailSheet(for: inspection)
                }
                .clashProductModal(item: $scriptRun, role: .form) { run in
                    scriptResultSheet(run)
                }
                 
                 
                .onChange(of: scriptRun == nil) { closed in
                    if closed { scriptTask?.cancel() }
                }
#if !os(iOS)
                 
                 
                .clashSheet(isPresented: $addingGroup) {
                    if let macGroupPages {
                        macGroupPages.newGroup(profile.id) { addingGroup = false }
                            .clashModalPresentation(.fitted)
                            .environment(\.clashPresentsPanelsAsNativeSheets, true)
                    }
                }
                .onAppear { macGroupPages?.attach(shownReorderGroups, shownNodeSourcesUpdate, shownOpenNodeSources) }
                .onChange(of: pageConfiguration) { _ in macGroupPages?.attach(shownReorderGroups, shownNodeSourcesUpdate, shownOpenNodeSources) }
                .task(id: pageConfiguration) { await readSelfBuiltNodes() }
                 
                .onChange(of: profiles.libraryContentEpoch) { _ in Task { await readSelfBuiltNodes() } }
#endif
#if os(iOS)
                .clashProductModal(isPresented: $addingNodes, role: .page) {
                    if shownConfiguration.isComposed {
                        ProxiesAddNodesSheet(model: profiles, profileID: profile.id, configurationName: shownName,
                                             added: { addingNodes = false; reprepare?() },
                                             close: { addingNodes = false })
                    } else {
                         
                         
                        OriginalAddNodesSheet(model: profiles, profileID: profile.id, configurationName: shownName,
                                              close: { addingNodes = false; reprepare?() })
                    }
                }
                .clashProductModal(item: $policyGroupSheet, role: .page) { opening in
                    ConfigurationPolicyGroupSheet(model: profiles, profileID: profile.id, opening: opening,
                                                  changed: { _ in }, close: { policyGroupSheet = nil })
                }
                 
                 
                .onChange(of: policyGroupSheet == nil) { closed in
                    if closed { reprepare?() }
                }
#endif
        }
        .task(id: profile.id) {
            offersNodeEditing = ProxyNodeEditPolicy.isEditable(
                hasStoredSource: profiles.sourceYAML(for: profile) != nil
            )
        }
         
         
        .task(id: "\(profile.id)|\(profile.activeRevision ?? "")|\(profiles.libraryContentEpoch)|\(isCurrent)") {
            await readPageConfiguration()
        }
#if os(iOS)
         
         
         
         
         
         
         
         
         
         
         
         
        .task(id: isCurrent) {
            guard isCurrent else { return }
            await nodes.followHealthChecksWhileVisible()
        }
#else
         
         
         
         
         
         
         
         
         
         
         
         
        .task(id: isCurrent) {
            guard isCurrent else { return }
            await nodes.followHealthChecksWhileVisible()
        }
#endif




    }



     
     
     
     
     
     
     
     
    @ViewBuilder
    private var hosted: some View {
        let current = isCurrent
        let wiring = liveWiring
        ProxiesOverviewAdapter(
             
             
             
             
            sourceModel: command.tunnelIsUp && current ? sourceModel.withoutCatalogRefusal : sourceModel,
             
             
             
             
             
             
             
             
             
             
             
            outboundMode: ProxyBrowsingVisibility.Mode(
                coreValue: {
                     
                     
                     
                     
                     
                    guard current else {
                        return (profiles.appWideOutboundMode() ?? .rule).rawValue
                    }
                    let tunnelUp = ["connected", "reasserting"]
                        .contains(vpn.status)
                    if tunnelUp, mode != "—" {
                        return mode
                    }
                     
                     
                     
                     
                    let saved = profiles.cachedOutboundMode(for: profile)
                        ?? profiles.lastKnownOutboundMode(for: profile)
                        ?? .direct
                    return saved.rawValue
                }()
            ),
            opening: opening,
             
             
             
            runtime: current ? Self.runtimeFacts(of: nodes, isConnected: isConnected, profileID: profile.id) : .none,
            isConnected: current && isConnected,
            testingNames: current ? nodes.testingNames : [],
            isTestingLatency: current && nodes.isTestingLatency,
            sweepEvents: current ? nodes.latencySweepConduit.eraseToAnyPublisher() : nil,
            latencyCompletedCount: current ? nodes.latencyCompletedCount : 0,
            latencyTotalCount: current ? nodes.latencyTotalCount : 0,
            testAll: wiring.testAll,
            testGroup: wiring.testGroup,
            testShown: wiring.testShown,
             
             
            loadMembers: wiring.loadMembers,
            loadProviderNodes: wiring.loadProviderNodes,
            searchMembers: wiring.searchMembers,
            switchSelection: { group, member in
                 
                 
                ClashLogStore.shared.append(
                    "proxy pick group=\(group) member=\(member) connected=\(command.isConnected)",
                    stream: .app,
                    level: .info
                )
                let route = Self.pickRoute(isCurrent: current, isConnected: command.isConnected)
                let refusal = Self.pick(group: group, member: member, route: route, profileID: profile.id,
                                        catalog: sourceModel, profiles: profiles, nodes: nodes)
                if route == .thisConfigurationsRecord {
                    ownRefusals[group] = refusal.map {
                        ClashGroupActionRefusal(verb: .select, coreSentence: $0, appSentence: nil)
                    }
                }
            },
             
             
            setVisibleGroup: wiring.setVisibleGroup,
            updateProvider: wiring.updateProvider,
            setGroupExpanded: wiring.setGroupExpanded,
            setGroupsExpanded: wiring.setGroupsExpanded,
            cancelLatency: wiring.cancelLatency,
             
            refreshCatalog: wiring.refreshCatalog,
             
             
            unpinGroup: wiring.unpinGroup,
             
            actionRefusals: current ? nodes.actionRefusals : shownOwnRefusals,
            testMember: wiring.testMember,
             
             
             
             
             
            editMember: offersNodeEditing
                ? { name in inspectingNode = ProxyNodeInspection(name: name) }
                : nil,
            inspectMember: { name in inspectingNode = ProxyNodeInspection(name: name) },
             
            nodeScripts: current ? offeredNodeScripts : [],
            runNodeScript: current ? nodeScriptRunner : nil,
            initiallyExpandedGroup: initiallyExpandedGroup,
            rememberedExpandedGroups: current ? nodes.unfoldedGroups : [],
             
             
            rememberedOpenGroup: current ? nodes.currentGroupName : nil,
            readerFoldedAll: current && nodes.readerFoldedAllGroups,
            ownsNavigationContainer: ownsNavigationContainer,
            configurationPage: shownConfigurationPage,
            nodeSourcesPage: shownNodeSourcesPage,
            addNodes: shownAddNodes,
            updateNodeSources: shownNodeSourcesUpdate,
            inspectGroup: shownInspectGroup,
            newGroup: shownNewGroup,
            reorderGroups: shownReorderGroups,
            deleteGroup: shownDeleteGroup,
            nodeActions: shownNodeActions
        )
        .alert(
            "Provider update failed",
            isPresented: Binding(
                get: { providerUpdateFailure != nil },
                set: { if !$0 { providerUpdateFailure = nil } }
            )
        ) {
            Button("OK", role: .cancel) { providerUpdateFailure = nil }
        } message: {
            Text(clash: providerUpdateFailure ?? .verbatim(""))
        }
        .alert(
            "Update applies at the next activation",
            isPresented: Binding(
                get: { providerUpdateDeferred != nil },
                set: { if !$0 { providerUpdateDeferred = nil } }
            )
        ) {
            Button("OK", role: .cancel) { providerUpdateDeferred = nil }
        } message: {
             
            Text(clash: providerUpdateDeferred ?? .verbatim(""))
        }
    }

     
     
     
     
     
     
    @MainActor
    private func updateProvider(_ name: String) async {
        guard let container = ClashAppIdentifiers.appGroupContainer,
              let store = try? ConfigResourceStore(containerURL: container) else { return }
        let operation = "proxies.provider.update.\(name)"
        let running = feedback?.show(
            .loading(title: ClashFeedbackCopy.updating, accessibilityIdentifier: "feedback.provider.update"),
            operation: operation)
        let profileID = profile.id
        let report = await ProviderUpdater.update([name], in: .live(
            profile: profile, store: store, container: container, vpn: vpn, scripts: .surfaced,
            stillInUse: { store.activeIdentityOrNil()?.profileID == profileID }))
        let outcome = report.outcomes[name] ?? .skipped
        let line = ProvidersModel.statusLine(outcome, for: name, locale: locale)
        switch outcome {
        case .updated, .unchanged:
            feedback?.answer(running, with: .success(title: line.text, accessibilityIdentifier: "feedback.provider.update"),
                             operation: operation)
        case .failed(let reason):
            if let feedback {
                feedback.answer(running, with: .error(
                    title: ClashFeedbackCopy.couldNotUpdate(name), message: reason.displayText, action: .retry,
                    accessibilityIdentifier: "feedback.provider.update"),
                    operation: operation, perform: { Task { await updateProvider(name) } })
            } else {
                providerUpdateFailure = reason.displayText
            }
        case .skipped:
             
             
            if let running { feedback?.dismiss(running) }
        case .notUpdatable(.unusableAddress):
             
             
            if let feedback {
                feedback.answer(running, with: .error(
                    title: ClashFeedbackCopy.couldNotUpdate(name), message: line.text,
                    accessibilityIdentifier: "feedback.provider.update"), operation: operation)
            } else {
                providerUpdateFailure = line.text
            }
        case .heldByTunnel, .awaitingConnection, .notConfirmed, .notUpdatable:
             
             
            let title = line.text
            let message: ClashDisplayText? = nil
            if let feedback {
                feedback.answer(running, with: .information(
                    title: title, message: message,
                    accessibilityIdentifier: "feedback.provider.update"), operation: operation)
            } else {
                providerUpdateDeferred = line.text
            }
        }
        await nodes.refresh()
    }
}

struct RulesOverviewHost: View {
     
     
     
     
     
     
     
     
    let command: ClashCommandClient?
    let canInspectActiveRules: Bool
    @ObservedObject var profiles: ProfilesViewModel
    let profile: Profile
     
     
    let openProxiesGroup: ((String) -> Void)?
    var ownsNavigationContainer = true
     
     
     
     
     
     
    var profileID: String? = nil
#if os(iOS)
     
     
     
    var pageSession: ConfigurationEditorSession? = nil
#endif
     
     
     
    var libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)? = nil
     
     
     
     
     
    var macPage: ((Profile) -> RulesOverviewPageParts)? = nil
     
     
     
    @State private var compileVerdicts = ProviderCompileVerdicts()
     
     
     
     
     
     
     
    @State private var presentedYAML: String?
     
     
     
     
    @State private var providerContentGeneration = 0
     
     
    @State private var pagesReadFor: String?
     
     
     
     
    @State private var editingInPlace = false

     
     
     
     
     
    private var isConfigurationsPage: Bool {
        profileID != nil
    }

     
     
    private var current: Profile {
        profileID.flatMap { id in profiles.profiles.first { $0.id == id } } ?? profile
    }

     
     
     
     
    private var pagesTaskID: String {
        let published = isConfigurationsPage ? "#\(profiles.publishedGeneration(of: current.id))" : ""
        return "\(current.id)#\(current.activeRevision ?? "")#\(current.selectedScriptID ?? "")\(published)#presented"
    }

    var body: some View {
        Group {
             
             
             
             
            if presentedYAML == nil, profiles.hasLargeSource(current) {
                if pagesReadFor == pagesTaskID {
                    VStack(spacing: ClashTheme.Spacing.row) {
                        ClashEmptyState(
                            title: "Rules Unavailable",
                            message: "Clash couldn’t read this configuration’s rules.",
                            symbol: .exclamationmarkTriangle
                        )
                        .accessibilityIdentifier("rules.overview.unavailable")
                        ClashOpeningCancelButton()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ClashOpeningProgress()
                }
            } else {
                 
                 
                 
                 
                let sourceYAML = presentedYAML ?? profiles.uiProjectedYAML(for: current)
#if os(iOS)
                 
                 
                 
                ConfigurationRulesPageContextHost(model: profiles, profile: current, session: pageSession,
                                                  selections: command, editsRules: editsRulesInLibrary,
                                                  drawsSections: isConfigurationsPage,
                                                  libraryChanged: libraryChanged,
                                                  editingInPlace: $editingInPlace) { parts in
                    adapter(sourceYAML: sourceYAML, page: parts)
                }
                 
                 
                 
                .id(current.id)
#else
                adapter(sourceYAML: sourceYAML, page: macPage?(current) ?? RulesOverviewPageParts())
#endif
            }
        }
         
         
         
         
         
         
         
        .task(id: "\(pagesTaskID)#\(editingInPlace)") {
            guard !editingInPlace else { return }
            let id = pagesTaskID
            presentedYAML = await profiles.loadPagesYAML(for: current)
            if !Task.isCancelled { pagesReadFor = id }
        }
        .onReceive(NotificationCenter.default.publisher(for: .clashProviderContentChanged)) { note in
             
             
             
             
             
            guard note.userInfo?["profileID"] == nil else { return }
            providerContentGeneration &+= 1
        }
        .task(id: "\(current.id)#\(current.activeRevision ?? "")#\(canInspectActiveRules)#\(providerContentGeneration)#\(editingInPlace)") {
            guard !editingInPlace else { return }
             
             
             
             
             
             
             
             
            let isActive = profiles.activeProfileID == current.id
            let profileID = current.id
            let coreHome = ClashAppIdentifiers.appGroupContainer?.appendingPathComponent("working")
            compileVerdicts = await Task.detached(priority: .utility) {
                var verdicts = isActive
                    ? coreHome.map { ProviderCompileVerdicts.load(coreHome: $0) } ?? ProviderCompileVerdicts()
                    : ProviderCompileVerdicts()
                verdicts.entryCounts = OfflineProxyCatalogLoader.input(preferredProfileID: profileID)
                    .map(OfflineProxyCatalogLoader.ruleSetCounts) ?? [:]
                return verdicts
            }.value
        }
        .task(id: "\(current.id)#\(current.activeRevision ?? "")#edits#\(editingInPlace)") {
            guard !editingInPlace else { return }
             
            guard let store = profiles.configurationLibraryStore else {
                editsRulesInLibrary = false
                return
            }
            let profileID = current.id
            editsRulesInLibrary = await Task.detached(priority: .utility) {
                (try? store.snapshot()).map { Self.editsRules(of: profileID, in: $0) } ?? false
            }.value
        }
    }

     
     
     
     
    @State private var editsRulesInLibrary: Bool?

    nonisolated static func editsRules(of profileID: String, in library: ConfigurationLibrarySnapshot) -> Bool {
        guard library.recipes.contains(where: { $0.id == profileID }) else { return false }
         
         
        return !keepsRulesInFile(of: profileID, in: library)
    }

     
     
     
    nonisolated static func keepsRulesInFile(of profileID: String, in library: ConfigurationLibrarySnapshot) -> Bool {
        guard let recipe = library.recipes.first(where: { $0.id == profileID }) else { return false }
        return library.sources.first { $0.id == recipe.ruleSource.id }?.rulesWrittenInOriginal == true
    }

     
     
     
     
    private func adapter(sourceYAML: String?, page: RulesOverviewPageParts) -> some View {
        RulesOverviewAdapter(
            sourceYAML: sourceYAML,
            canInspectActiveRules: canInspectActiveRules,
            compileVerdicts: compileVerdicts,
            openProxiesGroup: openProxiesGroup,
            ownsNavigationContainer: ownsNavigationContainer,
            page: page,
            activeRules: { [command] in
                 
                 
                 
                if let command {
                    ActiveRulesView(command: command)
                }
            }
        )
    }
}

 
 
 
struct SessionProxiesRailRoot: View {
    @ObservedObject var vpn: VPNController
    @ObservedObject var command: ClashCommandClient
    @ObservedObject var nodes: NodesModel
    @ObservedObject var profiles: ProfilesViewModel
    let profileRefreshToken: Int
     
     
     
    let avoidsLiveProviderStore: Bool
    @Binding var stagedGroup: String?
     
     
    @Binding var stagedOpening: ProxyBrowsingVisibility.Opening
     
    var macNodeSourcesPage: ((String) -> AnyView)? = nil
     
    var macGroupPages: ProxiesMacGroupPages? = nil

    @State private var preparedModel: ProxiesOverviewModel?
    @State private var preparedProfileID: Profile.ID?
     
     
     
     
    @State private var railStamp = UUID()
     
     
     
     
     
     
     
     
    @State private var openedGroup: String?
     
     
     
     
    @State private var opening: ProxyBrowsingVisibility.Opening
     
     
     
    @Environment(\.clashRegularRootOpenGroup) private var openRequest
     
     
    @Environment(\.clashRegularRootIsActive) private var isShown

    @MainActor
    init(
        vpn: VPNController,
        command: ClashCommandClient,
        nodes: NodesModel,
        profiles: ProfilesViewModel,
        profileRefreshToken: Int,
        avoidsLiveProviderStore: Bool,
        stagedGroup: Binding<String?>,
        stagedOpening: Binding<ProxyBrowsingVisibility.Opening> = .constant(.browsing),
        macNodeSourcesPage: ((String) -> AnyView)? = nil,
        macGroupPages: ProxiesMacGroupPages? = nil
    ) {
        self.macNodeSourcesPage = macNodeSourcesPage
        self.macGroupPages = macGroupPages
        self.vpn = vpn
        self.command = command
        self.nodes = nodes
        self.profiles = profiles
        self.profileRefreshToken = profileRefreshToken
        self.avoidsLiveProviderStore = avoidsLiveProviderStore
        self._stagedGroup = stagedGroup
         
         
         
         
         
         
         
         
         
        _openedGroup = State(initialValue: stagedGroup.wrappedValue)
        self._stagedOpening = stagedOpening
        _opening = State(initialValue: stagedOpening.wrappedValue)
         
         
         
         
         
         
         
         
         
         
         
         
         
        let restored: (model: ProxiesOverviewModel, profileID: Profile.ID)? =
            ClashPerf.measure("proxies.host.init.cache") {
                guard let profile = HomeProfileResolution.workingProfile(
                    in: profiles
                ),
                      let cached = ProxiesRailPreparationCache.shared.value(
                          for: profile.id
                      )
                else { return nil }
                 
                 
                 
                 
                 
                 
                return (cached.model, cached.profileID)
            }
        if let restored {
            _preparedModel = State(initialValue: restored.model)
            _preparedProfileID = State(initialValue: restored.profileID)
        }
         
         
         
        ClashPerf.count("proxies.rail.init")
    }

    var body: some View {
        Group {
            if let profile = HomeProfileResolution.workingProfile(
                in: profiles
            ) {
                if let preparedModel, preparedProfileID == profile.id {
                    ProxiesOverviewHost(
                        vpn: vpn,
                        command: command,
                        nodes: nodes,
                        profiles: profiles,
                        isConnected: command.isConnected,
                        mode: command.mode,
                        profile: profile,
                         
                         
                         
                         
                         
                         
                        sourceModel: preparedModel.applying(
                            selectedMap: profile.selectedMap
                        ),
                         
                         
                         
                         
                         
                         
                         
                        initiallyExpandedGroup: HomeProxiesEntryPolicy.railEntry(
                            openedGroup: openedGroup,
                            groups: preparedModel.groups,
                            name: \.name,
                            isHidden: \.hidden,
                            coreMode: command.mode,
                             
                             
                            liveCatalog: command.isConnected && nodes.isRuntimeAvailable,
                            readerFoldedAll: nodes.readerFoldedAllGroups,
                            opening: opening
                        ),
                        ownsNavigationContainer: false,
                        opening: opening,
                        macNodeSourcesPage: macNodeSourcesPage,
                        macGroupPages: macGroupPages
                    )
                } else {
                    ProgressView()
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity
                        )
                }
            } else {
                ClashEmptyState(
                    title: "No Profile",
                    message:
                        "Add a profile before browsing its proxies.",
                    symbol: .exclamationmarkTriangle
                )
            }
        }
        .task(
            id: Self.preparationKey(in: profiles, refreshToken: profileRefreshToken)
        ) {
             
             
             
             
             
            ClashPerf.markProxiesRailTaskFires(
                stamp: String(railStamp.uuidString.prefix(5))
            )
            await prepare()
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
            await nodes.refresh()
             
             
             
        }
        .onAppear {
            guard let staged = stagedGroup else { return }
            ClashPerf.markProxiesRailConsumesStagedGroup()
             
             
            if openedGroup != staged {
                openedGroup = staged
            }
            if opening != stagedOpening {
                opening = stagedOpening
            }
             
             
             
             
             
            Task { @MainActor in
                stagedGroup = nil
                stagedOpening = .browsing
            }
        }
         
         
         
        .onChange(of: openRequest) { request in take(request) }
         
         
         
        .onChange(of: command.mode) { mode in settleOpening(.modeChanged(.init(coreValue: mode))) }
        .onChange(of: isShown) { shown in settleOpening(.shownChanged(shown)) }
    }

     
     
     
     
     
     
     
    private func take(_ request: ClashRootOpenGroupSignal) {
        openedGroup = request.group
        opening = ProxyBrowsingVisibility.opening(opening, after: .request(.init(request.opening)))
        Task { @MainActor in
            stagedGroup = nil
            stagedOpening = .browsing
        }
    }

     
     
    private func settleOpening(_ event: ProxyBrowsingVisibility.OpeningEvent) {
        let settled = ProxyBrowsingVisibility.opening(opening, after: event)
        if settled != opening { opening = settled }
    }

     
     
     
    @MainActor
    static func preparationKey(in profiles: ProfilesViewModel, refreshToken: Int) -> PreparationKey {
        let profile = HomeProfileResolution.workingProfile(in: profiles)
#if os(macOS)
        return PreparationKey(profileID: profile?.id, refreshToken: refreshToken,
                              scriptID: profile?.selectedScriptID, overrides: profile?.proxyNodeOverrides,
                              published: profile.map { profiles.publishedGeneration(of: $0.id) } ?? 0)
#else
        return PreparationKey(profileID: profile?.id, refreshToken: refreshToken,
                              scriptID: profile?.selectedScriptID, overrides: profile?.proxyNodeOverrides)
#endif
    }

    struct PreparationKey: Hashable {
        let profileID: Profile.ID?
        let refreshToken: Int
         
         
        let scriptID: String?
         
         
         
         
         
         
         
         
        let overrides: ProxyNodeOverrideSpec?
#if os(macOS)
         
         
         
         
         
         
         
         
         
        let published: UInt64
#endif
    }

    @MainActor
    private func prepare() async {
        guard let profile = HomeProfileResolution.workingProfile(
            in: profiles
        ) else {
            preparedModel = nil
            preparedProfileID = nil
            return
        }
         
         
         
         
         
         
         
         
         
         
        let presentedSource = await profiles.loadPagesYAML(for: profile)
        let selectedMap = profile.selectedMap
         
         
         
         
         
        let cached = ProxiesRailPreparationCache.shared.value(
            for: profile.id
        )
        let began = DispatchTime.now().uptimeNanoseconds
        let avoidsStore = avoidsLiveProviderStore
         
         
         
        let asksKernel = !avoidsStore && !command.isConnected && !command.tunnelIsUp
        let drawnProfileID = profile.id
         
         
         
         
        let comparison = cached.map {
            (
                sourceYAML: $0.sourceYAML,
                fingerprint: $0.fingerprint
            )
        }
        let handle = Task.detached(
            priority: .userInitiated
        ) { () -> (ProxiesRailPreparation, String?)? in
            let sourceYAML: String? = presentedSource
            var providersDir: URL?
            if !avoidsStore,
               let container = ClashAppIdentifiers.appGroupContainer,
               let store = try? ConfigResourceStore(
                   containerURL: container
               ),
                
                
                
                
               let identity = try? store.activeIdentity() {
                providersDir = store.providersDirectory(
                    profileID: identity.profileID,
                    revision: identity.revision
                )
            }
            if Task.isCancelled { return nil }
             
             
             
            let catalog = providersDir.flatMap {
                ProviderCatalog.load(providersDir: $0)
            }
             
             
            let catalogInput = asksKernel
                ? OfflineProxyCatalogLoader.input(preferredProfileID: drawnProfileID)
                : nil
             
             
             
            let refreshState = providersDir == nil ? nil : ClashAppIdentifiers.appGroupContainer
                .flatMap { ProviderRefreshState.read(workingDirectory: $0.appendingPathComponent("working")) }
            let fingerprint = ProxiesProviderFingerprint.of(
                directory: providersDir,
                catalog: catalog
            ) + "|" + (catalogInput?.fingerprint ?? "-")
                 
                 
                + "|" + ProviderDownloadActivity.fingerprint
                + "|" + String(refreshState?.writtenAt ?? 0)
            if let comparison,
               comparison.sourceYAML == sourceYAML,
               comparison.fingerprint == fingerprint {
                return (.unchanged, sourceYAML)
            }
            if Task.isCancelled { return nil }
            var providerNodes:
                [String: [ProxiesOverviewModel.Proxy]] = [:]
            if let providersDir, let catalog {
                providerNodes = ProviderNodesLoader.load(
                    catalog: catalog,
                    providersDir: providersDir
                )
            }
            if Task.isCancelled { return nil }
            return (.built(
                model: ProxiesOverviewModel.make(
                    sourceYAML: sourceYAML,
                    selectedMap: selectedMap,
                    providerNodes: providerNodes,
                     
                     
                     
                     
                    notes: catalog?.proxyProviderNotes(
                        state: refreshState,
                        written: providersDir.flatMap { ProviderCatalog.writtenAt(providersDir: $0) }) ?? [:]
                 
                ).resolvedWithKernelCatalog(input: catalogInput)
                    .explainingEmptyProviders(sourceYAML: sourceYAML, catalog: catalog),
                fingerprint: fingerprint
            ), sourceYAML)
        }
         
         
         
        let result = await withTaskCancellationHandler {
            await handle.value
        } onCancel: {
            handle.cancel()
        }
        guard !Task.isCancelled, let (outcome, sourceYAML) = result else {
            return
        }
        switch outcome {
        case .unchanged:
             
             
             
             
             
             
            if let cached,
               preparedModel == nil
                   || preparedProfileID != cached.profileID {
                preparedModel = cached.model
                preparedProfileID = cached.profileID
            }
        case .built(let model, let fingerprint):
            preparedModel = model
            preparedProfileID = profile.id
            ProxiesRailPreparationCache.shared.store(
                (
                    model: model,
                    profileID: profile.id,
                    sourceYAML: sourceYAML,
                    fingerprint: fingerprint
                ),
                for: profile.id
            )
             
             
            ClashPerf.span(
                "proxies.prepare",
                milliseconds: Double(
                    DispatchTime.now().uptimeNanoseconds - began
                ) / 1_000_000,
                detail: "groups=\(model.groups.count)"
            )
        }
    }
}

 
private enum ProxiesRailPreparation: Sendable {
    case unchanged
    case built(model: ProxiesOverviewModel, fingerprint: String)
}

 
 
 
 
 
 
 
 
 
 
 
enum ProxiesProviderFingerprint {
    static func of(directory: URL?, catalog: ProviderCatalog?) -> String {
        guard let directory else { return "none" }
        let manager = FileManager.default
        func stamp(_ url: URL) -> String {
            let attributes = try? manager.attributesOfItem(atPath: url.path)
            let size = (attributes?[.size] as? NSNumber)?.intValue ?? -1
            let modified = (attributes?[.modificationDate] as? Date)?
                .timeIntervalSince1970 ?? -1
            return "\(url.lastPathComponent)|\(size)|\(modified)"
        }
        guard let catalog else {
             
             
             
            return "nocatalog"
        }
        var parts: [String] = []
        for entry in catalog.entries where entry.kind == "proxy" {
            parts.append(
                "\(entry.name)|"
                    + stamp(directory.appendingPathComponent(entry.path))
            )
        }
        return parts.sorted().joined(separator: ";")
    }
}

 
 
@MainActor
private enum ProxiesRailPreparationCache {
    static let shared = ClashLastPreparation<
        Profile.ID,
        (
            model: ProxiesOverviewModel,
            profileID: Profile.ID,
            sourceYAML: String?,
            fingerprint: String
        )
    >()
}

 
struct SessionRulesRailRoot: View {
     
     
    let command: ClashCommandClient
    let canInspectActiveRules: Bool
    @ObservedObject var profiles: ProfilesViewModel
    let openProxiesGroup: (String) -> Void
     
    var macPage: ((Profile) -> RulesOverviewPageParts)? = nil

    var body: some View {
        if let profile = HomeProfileResolution.workingProfile(
            in: profiles
        ) {
            RulesOverviewHost(
                command: command,
                canInspectActiveRules: canInspectActiveRules,
                profiles: profiles,
                profile: profile,
                openProxiesGroup: openProxiesGroup,
                ownsNavigationContainer: false,
                macPage: macPage
            )
        } else {
            ClashEmptyState(
                title: "No Profile",
                message:
                    "Add a profile before browsing its rules.",
                symbol: .exclamationmarkTriangle
            )
        }
    }
}

 
 
enum HomeProfileResolution {
    @MainActor
    static func workingProfile(
        in profiles: ProfilesViewModel
    ) -> Profile? {
        if let active = profiles.activeProfileID,
           let profile = profiles.profiles.first(
               where: { $0.id == active }
           ) {
            return profile
        }
        if let id = ProfileCenterPolicy.automaticSelectionID(
            profiles: profiles.profiles,
            activeProfileID: nil
        ) {
            return profiles.profiles.first { $0.id == id }
        }
        return nil
    }
}



 
 
 
 
 
extension ProxiesOverviewHost: @MainActor Equatable {
    static func == (a: Self, b: Self) -> Bool {
        let equal = a.isConnected == b.isConnected
            && a.mode == b.mode
            && a.profile.id == b.profile.id
            && a.profile.activeRevision == b.profile.activeRevision
             
             
             
             
             
             
            && a.sourceModel == b.sourceModel
            && a.initiallyExpandedGroup == b.initiallyExpandedGroup
            && a.ownsNavigationContainer == b.ownsNavigationContainer
            && a.opening == b.opening
        ClashPerf.count(equal ? "proxies.host.eq.hit" : "proxies.host.eq.miss")
        return equal
    }
}

extension ProxiesOverviewHost {
     
     
    @MainActor
    static func runtimeFacts(of nodes: NodesModel, isConnected: Bool, profileID: String) -> ProxiesRuntimeFacts {
        ProxiesRuntimeFacts(
            delays: nodes.delays,
            defaultDelayTestURL: nodes.defaultDelayTestURL,
            failureReasons: nodes.failureReasons,
            coreFailureReasons: nodes.coreFailureReasons,
             
             
            nowByGroup: nodes.nowByGroup,
            resolvedNowByGroup: nodes.resolvedNowByGroup,
            fixedByGroup: nodes.fixedByGroup,
             
             
             
            groupsAreTheCores: nodes.groupsAreTheCores,
             
             
             
            catalog: isConnected || nodes.offlineGroupsProfileID == profileID ? nodes.groups : [],
            runtimeNodes: nodes.runtimeProxies,
            providerCatalog: nodes.runtimeProviderCatalog,
            isAuthoritative: nodes.isRuntimeAvailable
        )
    }

     
     
    fileprivate var offeredNodeScripts: [ClashProxyNodeScript] {
#if os(iOS)
        ModuleNodeScriptPresentation.menu(appScripts.entries(.generic))
#else
        []
#endif
    }

    fileprivate var nodeScriptRunner: ((String, String) -> Void)? {
#if os(iOS)
        { id, node in runNodeScript(id: id, node: node) }
#else
        nil
#endif
    }

#if os(iOS)
     
     
     
     
     
    fileprivate func runNodeScript(id: String, node: String) {
        guard let entry = appScripts.entry(id: id) else { return }
        let started = ClashNodeScriptResult(scriptName: entry.name, node: node, state: .running)
        scriptTask?.cancel()
        scriptRun = started
        let command = command
        scriptTask = Task { @MainActor in
            let info = await command.nodeInformation(named: node)
            guard !Task.isCancelled else { return }
            let result = await ModuleAppScriptRunner.shared.run(entry, trigger: .generic(node: node, nodeInfo: info))
             
            let state = await Task.detached(priority: .userInitiated) { ModuleNodeScriptPresentation.state(result) }.value
            guard scriptRun?.id == started.id else { return }
            scriptRun?.state = state
        }
    }
#endif

     
    fileprivate func scriptResultSheet(_ run: ClashNodeScriptResult) -> some View {
        ClashFeatureNavigationContainer {
            ClashNodeScriptResultView(result: run)
                .clashPageTitle(.verbatim(run.pageTitle), watchAs: "proxies.script.result")
                .clashToolbarUnlessInPanel {
                    ToolbarItem(placement: .cancellationAction) {
                        ClashSheetCloseButton { scriptRun = nil }
                    }
                }
        }
    }

     
     
     
     
     
    fileprivate func nodeDetailSheet(for inspection: ProxyNodeInspection) -> some View {
         
         
         
         
        let inputs = profiles.uiProjectionInputs(for: profile)
        let cached = profiles.cachedUIProjectedYAML(for: profile)
        var providersDir: URL?
         
         
        if isCurrent,
           let container = ClashAppIdentifiers.appGroupContainer,
           let store = try? ConfigResourceStore(containerURL: container),
           let identity = try? store.activeIdentity() {
            providersDir = store.providersDirectory(
                profileID: identity.profileID,
                revision: identity.revision
            )
        }
        let made = ProxyNodeEditorSheet(
            nodeName: inspection.name,
            sourceYAML: inputs.sourceYAML,
            cachedProjection: cached,
            profile: profile,
            providersDir: providersDir,
            failureCategory: isCurrent ? nodes.coreFailureReasons[inspection.name] : nil,
            failureMessage: isCurrent ? nodes.coreFailureMessages[inspection.name] : nil,
            profiles: profiles
        )
         
         
         
        let again = reprepare
        var sheet = made
#if os(iOS)
        sheet.library = ProxyNodeLibraryContext(configurationName: shownName, reprepare: { again?() })
#else
         
         
        if macGroupPages != nil {
            sheet.library = ProxyNodeLibraryContext(configurationName: shownName, reprepare: { again?() },
                                                    openSource: macGroupPages?.openNodeSource, originalEditor: macGroupPages?.originalNode,
                                                    offerUndo: macGroupPages?.offerUndo)
        }
#endif
        return sheet
    }
}

 
 
 
 
 
extension ProxiesOverviewHost {
     
     
    @MainActor
    static func isCurrent(profileID: String, in profiles: ProfilesViewModel) -> Bool {
        HomeProfileResolution.workingProfile(in: profiles)?.id == profileID
    }

     
    var isCurrent: Bool {
#if os(iOS)
        Self.isCurrent(profileID: profile.id, in: profiles)
#else
        Self.pageIsCurrent(isConfigurationsPage: isConfigurationsPage, profileID: profile.id,
                           workingProfileID: HomeProfileResolution.workingProfile(in: profiles)?.id)
#endif
    }

     
     
     
     
    static func pageIsCurrent(isConfigurationsPage: Bool, profileID: String, workingProfileID: String?) -> Bool {
        !isConfigurationsPage || workingProfileID == profileID
    }

     
    enum PickRoute: Equatable {
         
        case running
         
        case currentRecord
         
         
        case thisConfigurationsRecord
    }

    static func pickRoute(isCurrent: Bool, isConnected: Bool) -> PickRoute {
        guard isCurrent else { return .thisConfigurationsRecord }
        return isConnected ? .running : .currentRecord
    }

     
     
     
    @MainActor
    @discardableResult
    static func pick(group: String, member: String, route: PickRoute, profileID: String,
                     catalog: ProxiesOverviewModel?, profiles: ProfilesViewModel, nodes: NodesModel) -> String? {
        switch route {
        case .running:
             
             
            nodes.pickFromPage(group: group, member: member)
            return nil
        case .currentRecord, .thisConfigurationsRecord:
            do {
                try profiles.updateProxySelection(profileID: profileID, group: group, member: member, catalog: catalog)
                if route == .currentRecord { nodes.noteOfflinePick(group: group, refusal: nil) }
                return nil
            } catch {
                 
                 
                ClashLogStore.shared.append(
                    "proxy selection refused offline group=\(group) member=\(member): \(error)",
                    stream: .app,
                    level: .warning
                )
                if route == .currentRecord {
                    nodes.noteOfflinePick(group: group, refusal: error.localizedDescription)
                }
                return error.localizedDescription
            }
        }
    }

     
     
     
     
    fileprivate struct LiveWiring {
        var testAll: (() -> Void)?
        var testGroup: ((String) -> Void)?
        var testShown: (([ClashProxiesShownMembers]) -> Void)?
        var loadMembers: ((String) -> Void)?
        var loadProviderNodes: ((String) -> Void)?
        var searchMembers: ((String) -> Void)?
        var setVisibleGroup: ((String?) -> Void)?
        var updateProvider: ((String) -> Void)?
        var setGroupExpanded: ((String, Bool) -> Void)?
        var setGroupsExpanded: (([String], Bool) -> Void)?
        var cancelLatency: (() -> Void)?
        var refreshCatalog: (() -> Void)?
        var unpinGroup: ((String) -> Void)?
        var testMember: ((String, String?) -> Void)?
    }

    fileprivate var liveWiring: LiveWiring {
        guard isCurrent else { return LiveWiring(refreshCatalog: reprepare) }
        let command = command
        let nodes = nodes
        var wiring = LiveWiring()
        wiring.testAll = {
            guard command.isConnected else { return }
            Task { await nodes.testAll() }
        }
        wiring.testGroup = { groupName in
            guard command.isConnected,
                  let group = nodes.groups.first(where: { $0.name == groupName })
            else { return }
            Task { await nodes.test(group: group) }
        }
        wiring.testShown = { shown in
            guard command.isConnected else { return }
            Task { await nodes.test(shown: shown) }
        }
        wiring.loadMembers = { groupName in Task { await nodes.loadRemainingMembers(of: groupName) } }
        wiring.loadProviderNodes = { providerName in Task { await nodes.loadProviderNodes(named: providerName) } }
        wiring.searchMembers = { query in Task { await nodes.searchMembers(matching: query) } }
        wiring.setVisibleGroup = { group in
            if let group { nodes.setCurrentGroup(group) }
        }
        wiring.updateProvider = { name in Task { await updateProvider(name) } }
        wiring.setGroupExpanded = { group, isExpanded in nodes.setExpanded(isExpanded, group: group) }
        wiring.setGroupsExpanded = { groups, isExpanded in nodes.setExpanded(isExpanded, groups: groups) }
        wiring.cancelLatency = { Task { await nodes.cancelLatencyTests(reason: .requested) } }
        wiring.refreshCatalog = { Task { await nodes.refresh() } }
        wiring.unpinGroup = { group in Task { await nodes.unfix(group: group) } }
        wiring.testMember = { name, group in Task { await nodes.test(name, inGroup: group) } }
        return wiring
    }

     
    fileprivate var shownOwnRefusals: [String: ClashGroupActionRefusal] {
        ownRefusals
    }

     
    fileprivate var shownName: String {
        ProfileRowPresentation.label(for: profile, locale: locale)
    }

     
     
    fileprivate var shownConfiguration: ProxiesPageConfiguration {
        if let pageConfiguration, pageConfiguration.profileID == profile.id, pageConfiguration.isCurrent == isCurrent {
            return pageConfiguration
        }
        return ProxiesPageConfiguration(profileID: profile.id, name: shownName, isCurrent: isCurrent,
                                        isComposed: false, sourceNames: nil)
    }

     
    fileprivate func readPageConfiguration() async {
        let id = profile.id
        let name = shownName
        let working = isCurrent ? id : nil
        let locale = locale
        guard let store = profiles.configurationLibraryStore else { return }
        let library = try? await Task.detached(priority: .userInitiated) { try store.snapshot() }.value
        guard !Task.isCancelled else { return }
        pageConfiguration = ProxiesPageConfiguration.make(profileID: id, name: name, workingProfileID: working,
                                                          library: library, locale: locale)
    }

     
    fileprivate var shownNodeSourcesUpdate: (() -> Void)? {
        let ids = shownConfiguration.updatableSourceIDs
        guard !ids.isEmpty else { return nil }
        return { Task { await updateNodeSources(ids) } }
    }

     
     
     
     
    fileprivate func updateNodeSources(_ ids: [String]) async {
        guard let store = profiles.configurationLibraryStore,
              let library = try? await Task.detached(priority: .userInitiated, operation: { try store.snapshot() }).value
        else { return }
        let feedback = feedback
        let locale = locale
        let operation = #"proxies.node-sources.update"#
        for id in ids {
            guard let source = library.sources.first(where: { $0.id == id }) else { continue }
            let label = source.displayLabel(locale: locale)
            let running = feedback?.show(.loading(title: ClashFeedbackCopy.updating, message: .verbatim(label),
                                                  accessibilityIdentifier: ConfigurationSourceUpdate.resultIdentifier),
                                         operation: operation)
            guard let run = profiles.updateConfigurationSource(source, replacingRules: false, locale: locale,
                                                               changed: { _ in }, status: { _ in })
            else {
                 
                if let running { feedback?.dismiss(running) }
                continue
            }
            do {
                let outcome = try await run.value
                feedback?.answer(running, with: ConfigurationSourceUpdate.result(outcome, label: label,
                    putBack: profiles.wasPutBack(source.id)), operation: operation)
            } catch {
                feedback?.answer(running, with: ConfigurationSourceUpdate.failure(error, label: label, locale: locale),
                                 operation: operation)
            }
        }
        reprepare?()
    }
#if os(iOS)
    fileprivate var shownConfigurationPage: ClashProxiesConfigurationPage? { shownConfiguration.page() }

     
     
    fileprivate var shownNodeSourcesPage: (() -> AnyView)? {
        guard shownConfiguration.sourceNames != nil else { return nil }
        let profiles = profiles
        let id = profile.id
        return { AnyView(Self.nodeSourcesPage(model: profiles, profileID: id)) }
    }

     
     
    fileprivate var shownAddNodes: (() -> Void)? {
        guard shownConfiguration.sourceNames != nil else { return nil }
        return { addingNodes = true }
    }

     
     
     
    fileprivate var shownGroupPage: ((ConfigurationPolicyGroupSheet.Opening) -> Void)? {
        guard shownConfiguration.sourceNames != nil else { return nil }
        return { policyGroupSheet = $0 }
    }
    fileprivate var shownInspectGroup: ((String) -> Void)? { shownGroupPage.map { open in { open(.group($0)) } } }
    fileprivate var shownNewGroup: (() -> Void)? { shownGroupPage.map { open in { open(.adding) } } }
    fileprivate var shownReorderGroups: (() -> Void)? { shownGroupPage.map { open in { open(.reordering) } } }
     
    fileprivate var shownDeleteGroup: ((String) -> Void)? { nil }
     
    fileprivate var shownNodeActions: ProxiesNodeActions? { nil }


     
    @MainActor
    static func nodeSourcesPage(model: ProfilesViewModel, profileID: String) -> ConfigurationNodeSourcesPage {
        ConfigurationNodeSourcesPage(model: model, profileID: profileID, section: .proxies)
    }

#else
     
     
    fileprivate var shownConfigurationPage: ClashProxiesConfigurationPage? {
        ClashMacProxiesRail.page(shownConfiguration, selfBuiltNodes: macSelfBuiltNodes, removableNodes: macRemovableNodes,
                                 quotesConfigurationName: isConfigurationsPage)
    }

     
    fileprivate func readSelfBuiltNodes() async {
         
        guard shownConfiguration.sourceNames != nil, let store = profiles.configurationLibraryStore
        else { macSelfBuiltNodes = []; macRemovableNodes = []; return }
        let id = profile.id
        let read = await Task.detached(priority: .userInitiated) { () -> (selfBuilt: [String], removable: [String]) in
            guard let snapshot = try? store.snapshot() else { return ([], []) }
            let selfBuilt = ClashMacProxiesRail.selfBuiltNodes(profileID: id, in: snapshot) { record in
                try OrderedJSON.parse(store.payload(ConfigurationSourceVersion(record)).documentJSON)
            }
            return (selfBuilt, ClashMacProxiesRail.removableNodes(profileID: id, in: snapshot, store: store))
        }.value
        guard !Task.isCancelled else { return }
        macSelfBuiltNodes = read.selfBuilt
        macRemovableNodes = read.removable
    }

     
     
     
    fileprivate var shownNodeActions: ProxiesNodeActions? {
        guard shownConfiguration.sourceNames != nil else { return nil }
        return ProxiesNodeActions(
            copyYAML: { name in Task { await copyNodeYAML(name) } },
            remove: { name in Task { await libraryActions(for: name) { actions in
                await actions.remove(feedback: feedback, locale: locale)
                 
                 
                if let refusal = actions.removalRefusal { feedback?.say(.error(title: .verbatim(refusal), accessibilityIdentifier: "feedback.node.remove.refused"),
                                                                        operation: "configuration.node.remove") }
            } } },
            delete: { name in Task { await libraryActions(for: name) { actions in
                await actions.delete(feedback: feedback, locale: locale)
                if let refusal = actions.deletionRefusal {
                    feedback?.say(.error(title: ClashFeedbackCopy.couldNotDelete(name), message: .verbatim(refusal),
                                         accessibilityIdentifier: "feedback.node.delete.refused"),
                                  operation: "library.delete")
                }
            } } }
        )
    }

     
    fileprivate func libraryActions(for name: String, _ run: (ProxyNodeLibraryActions) async -> Void) async {
        let actions = ProxyNodeLibraryActions()
        let again = reprepare
        actions.attach(node: name, profileID: profile.id, model: profiles,
                       context: ProxyNodeLibraryContext(configurationName: shownName, reprepare: { again?() },
                                                        offerUndo: macGroupPages?.offerUndo),
                       locale: locale, close: {})
        await actions.read()
        await run(actions)
    }

     
    fileprivate func copyNodeYAML(_ name: String) async {
        let yaml = profiles.cachedUIProjectedYAML(for: profile) ?? profiles.uiProjectionInputs(for: profile).sourceYAML
        let text = await Task.detached(priority: .userInitiated) { () -> String? in
            guard let yaml, let details = ProxyNodeDetailLookup.details(named: name, yaml: yaml, providersDir: nil) else { return nil }
            return ProxyNodeDetailLookup.yaml(for: details)
        }.value
        guard let text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
     
     
    fileprivate var shownNodeSourcesPage: (() -> AnyView)? {
        guard shownConfiguration.sourceNames != nil, let macNodeSourcesPage else { return nil }
        let id = profile.id
        return { macNodeSourcesPage(id) }
    }
    fileprivate var shownAddNodes: (() -> Void)? { nil }
     
     
    fileprivate var shownInspectGroup: ((String) -> Void)? { macGroupPages.map { pages in { name in push(pages.group(profile.id, name)) } } }
    fileprivate var shownNewGroup: (() -> Void)? { macGroupPages.map { _ in { addingGroup = true } } }
     
     
    fileprivate var shownReorderGroups: (() -> Void)? {
        guard shownConfiguration.sourceNames != nil, let pages = macGroupPages else { return nil }
        return { push(pages.list(profile.id)) }
    }
    fileprivate var shownDeleteGroup: ((String) -> Void)? { macGroupPages.map { pages in { name in pages.delete(profile.id, name) } } }

     
     
     
    fileprivate var shownOpenNodeSources: (() -> Void)? {
        guard shownConfiguration.sourceNames != nil, let macNodeSourcesPage else { return nil }
        let id = profile.id
        return { push(macNodeSourcesPage(id)) }
    }

    private func push(_ page: AnyView) {
        guard let pushRoute else { return }
        let token = UUID()
        ClashViewRouteRegistry.set(token, ownership: .oneShot, onReturn: {}) { page }
        pushRoute(ClashViewRoute(id: token))
    }
#endif
}

extension ProxyBrowsingVisibility.Opening {
     
     
    init(_ requested: ClashRootOpenGroupSignal.Opening) {
        switch requested {
        case .browsing: self = .browsing
        case .choosingInGlobal: self = .choosingInGlobal
        }
    }
}
