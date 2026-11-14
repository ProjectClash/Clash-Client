import Combine
import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
 
 
 
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
    @Environment(\.locale) private var locale
    @State private var providerUpdateFailure: ClashDisplayText?
     
     
    @State private var providerUpdateDeferred: ClashDisplayText?
     
    @State private var inspectingNode: ProxyNodeInspection?
     
     
     
     
     
     
    @State private var offersNodeEditing = false
    @Environment(\.clashFeedback) private var feedback
     
     
     
    @State private var scriptRun: ClashNodeScriptResult?
     
    @State private var scriptTask: Task<Void, Never>?
#if os(iOS)
     
    @ObservedObject private var appScripts = ModuleAppScriptRunner.shared
#endif

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
        }
        .task(id: profile.id) {
            offersNodeEditing = ProxyNodeEditPolicy.isEditable(
                hasStoredSource: profiles.sourceYAML(for: profile) != nil
            )
        }
#if os(iOS)
         
         
         
         
         
         
         
         
         
         
         
        .task { await nodes.followHealthChecksWhileVisible() }
#else
         
         
         
         
         
         
         
         
         
        .task { await nodes.followHealthChecksWhileVisible() }
#endif




    }



     
     
     
     
     
     
     
     
    @ViewBuilder
    private var hosted: some View {
        ProxiesOverviewAdapter(
             
             
             
            sourceModel: command.tunnelIsUp ? sourceModel.withoutCatalogRefusal : sourceModel,
             
             
             
             
             
             
             
             
             
             
             
            outboundMode: ProxyBrowsingVisibility.Mode(
                coreValue: {
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
            runtime: Self.runtimeFacts(of: nodes, isConnected: isConnected, profileID: profile.id),
            isConnected: isConnected,
            testingNames: nodes.testingNames,
            isTestingLatency: nodes.isTestingLatency,
            sweepEvents: nodes.latencySweepConduit.eraseToAnyPublisher(),
            latencyCompletedCount: nodes.latencyCompletedCount,
            latencyTotalCount: nodes.latencyTotalCount,
            testAll: {
                guard command.isConnected else {
                    return
                }
                Task {
                    await nodes.testAll()
                }
            },
            testGroup: { groupName in
                guard command.isConnected,
                      let group = nodes.groups.first(
                          where: { $0.name == groupName }
                      )
                else {
                    return
                }
                Task {
                    await nodes.test(group: group)
                }
            },
            testShown: { shown in
                guard command.isConnected else { return }
                Task { await nodes.test(shown: shown) }
            },
            loadMembers: { groupName in
                Task { await nodes.loadRemainingMembers(of: groupName) }
            },
            loadProviderNodes: { providerName in
                Task { await nodes.loadProviderNodes(named: providerName) }
            },
            searchMembers: { query in
                Task { await nodes.searchMembers(matching: query) }
            },
            switchSelection: { group, member in
                 
                 
                ClashLogStore.shared.append(
                    "proxy pick group=\(group) member=\(member) connected=\(command.isConnected)",
                    stream: .app,
                    level: .info
                )
                if command.isConnected {
                     
                     
                    nodes.pickFromPage(group: group, member: member)
                } else {
                    do {
                        try profiles.updateProxySelection(
                            profileID: profile.id,
                            group: group,
                            member: member,
                            catalog: sourceModel
                        )
                        nodes.noteOfflinePick(group: group, refusal: nil)
                    } catch {
                         
                         
                        ClashLogStore.shared.append(
                            "proxy selection refused offline group=\(group) member=\(member): \(error)",
                            stream: .app,
                            level: .warning
                        )
                        nodes.noteOfflinePick(group: group, refusal: error.localizedDescription)
                    }
                }
            },
            setVisibleGroup: { group in
                if let group {
                    nodes.setCurrentGroup(group)
                }
            },
            updateProvider: { name in Task { await updateProvider(name) } },
            setGroupExpanded: { group, isExpanded in
                nodes.setExpanded(isExpanded, group: group)
            },
            setGroupsExpanded: { groups, isExpanded in
                nodes.setExpanded(isExpanded, groups: groups)
            },
            cancelLatency: {
                Task {
                    await nodes.cancelLatencyTests(
                        reason: .requested
                    )
                }
            },
            refreshCatalog: { Task { await nodes.refresh() } },
             
             
            unpinGroup: { group in
                Task { await nodes.unfix(group: group) }
            },
             
            actionRefusals: nodes.actionRefusals,
            testMember: { name, group in Task { await nodes.test(name, inGroup: group) } },
             
             
             
             
             
            editMember: offersNodeEditing
                ? { name in inspectingNode = ProxyNodeInspection(name: name) }
                : nil,
            inspectMember: { name in inspectingNode = ProxyNodeInspection(name: name) },
            nodeScripts: offeredNodeScripts,
            runNodeScript: nodeScriptRunner,
            initiallyExpandedGroup: initiallyExpandedGroup,
            rememberedExpandedGroups: nodes.unfoldedGroups,
             
             
            rememberedOpenGroup: nodes.currentGroupName,
            readerFoldedAll: nodes.readerFoldedAllGroups,
            ownsNavigationContainer: ownsNavigationContainer
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
     
     
     
     
     
     
    let command: ClashCommandClient
    let canInspectActiveRules: Bool
    @ObservedObject var profiles: ProfilesViewModel
    let profile: Profile
    let openProxiesGroup: (String) -> Void
    var ownsNavigationContainer = true
     
     
     
    @State private var compileVerdicts = ProviderCompileVerdicts()
     
     
     
     
     
     
     
    @State private var presentedYAML: String?
     
     
     
     
    @State private var providerContentGeneration = 0
     
     
    @State private var pagesReadFor: String?

    private var pagesTaskID: String {
        "\(profile.id)#\(profile.activeRevision ?? "")#\(profile.selectedScriptID ?? "")#presented"
    }

    var body: some View {
        Group {
             
             
             
             
            if presentedYAML == nil, profiles.hasLargeSource(profile) {
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
                 
                 
                 
                 
                RulesOverviewAdapter(
                    sourceYAML: presentedYAML ?? profiles.uiProjectedYAML(for: profile),
                    canInspectActiveRules: canInspectActiveRules,
                    compileVerdicts: compileVerdicts,
                    openProxiesGroup: openProxiesGroup,
                    ownsNavigationContainer: ownsNavigationContainer,
                    editRules: editRulesPage,
                    activeRules: {
                         
                         
                         
                        ActiveRulesView(command: command)
                    }
                )
            }
        }
         
         
         
         
         
         
         
        .task(id: pagesTaskID) {
            let id = pagesTaskID
            presentedYAML = await profiles.loadPagesYAML(for: profile)
            if !Task.isCancelled { pagesReadFor = id }
        }
        .onReceive(NotificationCenter.default.publisher(for: .clashProviderContentChanged)) { note in
             
             
             
             
             
            guard note.userInfo?["profileID"] == nil else { return }
            providerContentGeneration &+= 1
        }
        .task(id: "\(profile.id)#\(profile.activeRevision ?? "")#\(canInspectActiveRules)#\(providerContentGeneration)") {
             
             
             
             
             
             
             
             
            let isActive = profiles.activeProfileID == profile.id
            let profileID = profile.id
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
        .task(id: "\(profile.id)#\(profile.activeRevision ?? "")#edits") {
             
            guard let store = profiles.configurationLibraryStore else {
                editsRulesInLibrary = false
                return
            }
            let profileID = profile.id
            editsRulesInLibrary = await Task.detached(priority: .utility) {
                (try? store.snapshot()).map { Self.editsRules(of: profileID, in: $0) } ?? false
            }.value
        }
    }

     
     
     
    @State private var editsRulesInLibrary = false

    nonisolated static func editsRules(of profileID: String, in library: ConfigurationLibrarySnapshot) -> Bool {
        guard let recipe = library.recipes.first(where: { $0.id == profileID }) else { return false }
         
         
        return library.sources.first { $0.id == recipe.ruleSource.id }?.rulesWrittenInOriginal != true
    }

     
     
     
    private var editRulesPage: (() -> AnyView)? {
#if os(iOS)
        guard editsRulesInLibrary else { return nil }
        return { [profiles, profile] in AnyView(ConfigurationRulesChapterHost(model: profiles, profileID: profile.id)) }
#else
        nil
#endif
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
        stagedOpening: Binding<ProxyBrowsingVisibility.Opening> = .constant(.browsing)
    ) {
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
                        opening: opening
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
            id: PreparationKey(
                profileID: HomeProfileResolution.workingProfile(
                    in: profiles
                )?.id,
                refreshToken: profileRefreshToken,
                scriptID: HomeProfileResolution.workingProfile(
                    in: profiles
                )?.selectedScriptID,
                overrides: HomeProfileResolution.workingProfile(
                    in: profiles
                )?.proxyNodeOverrides
            )
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

    fileprivate struct PreparationKey: Hashable {
        let profileID: Profile.ID?
        let refreshToken: Int
         
         
        let scriptID: String?
         
         
         
         
         
         
         
         
        let overrides: ProxyNodeOverrideSpec?
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
                ownsNavigationContainer: false
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
        if let container = ClashAppIdentifiers.appGroupContainer,
           let store = try? ConfigResourceStore(containerURL: container),
           let identity = try? store.activeIdentity() {
            providersDir = store.providersDirectory(
                profileID: identity.profileID,
                revision: identity.revision
            )
        }
        return ProxyNodeEditorSheet(
            nodeName: inspection.name,
            sourceYAML: inputs.sourceYAML,
            cachedProjection: cached,
            profile: profile,
            providersDir: providersDir,
            failureCategory: nodes.coreFailureReasons[inspection.name],
            failureMessage: nodes.coreFailureMessages[inspection.name],
            profiles: profiles
        )
    }
}

extension ProxyBrowsingVisibility.Opening {
     
     
    init(_ requested: ClashRootOpenGroupSignal.Opening) {
        switch requested {
        case .browsing: self = .browsing
        case .choosingInGlobal: self = .choosingInGlobal
        }
    }
}
