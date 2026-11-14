import Combine
import ClashClientKit
import ClashClientUI
import SwiftUI

struct ProxiesRuntimeFacts {
    var delays: [String: Int] = [:]
    var defaultDelayTestURL: String = DelayTestSettings.effectiveURL()
     
     
     
     
    var failureReasons: [String: String] = [:]
     
     
     
    var coreFailureReasons: [String: String] = [:]
    var nowByGroup: [String: String] = [:]
    var resolvedNowByGroup: [String: String] = [:]
     
    var fixedByGroup: [String: String] = [:]
     
     
     
     
     
     
    var groupsAreTheCores = false
     
     
     
    var catalog: [ProxyGroup] = []
     
    var runtimeNodes: [ProxiesOverviewModel.Proxy] = []
     
    var providerCatalog = ProviderRuntimeCatalog.empty
     
     
     
    var isAuthoritative = false

    static let none = ProxiesRuntimeFacts()

     
     
    var shownFailureReasons: [String: String] {
        if failureReasons.isEmpty { return coreFailureReasons }
        if coreFailureReasons.isEmpty { return failureReasons }
        return coreFailureReasons.merging(failureReasons) { _, own in own }
    }


}

typealias ProxiesDisplayPreferences =
    ClashProxiesDisplayPreferences

extension ClashProxiesDisplayPreferences {
    static let key = "proxies.display.v1"

    static func load(
        defaults: UserDefaults = .standard
    ) -> ClashProxiesDisplayPreferences {
        guard let raw =
                defaults.dictionary(forKey: key)
                    as? [String: String] else {
            return ClashProxiesDisplayPreferences()
        }
        return ClashProxiesDisplayPreferences(
            style: raw["style"].flatMap(Style.init(rawValue:))
                ?? .list,
            sort: raw["sort"].flatMap(Sort.init(rawValue:))
                ?? .standard,
            layout: raw["layout"].flatMap(Layout.init(rawValue:))
                ?? .loose,
            size: raw["size"].flatMap(Size.init(rawValue:))
                ?? .standard,
             
             
            groupIconImages: raw["groupIconImages"] == "true"
        )
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(
            [
                "style": style.rawValue,
                "sort": sort.rawValue,
                "layout": layout.rawValue,
                "size": size.rawValue,
                "groupIconImages": groupIconImages ? "true" : "false",
            ],
            forKey: Self.key
        )
    }

    static func uiTestOverride()
        -> ClashProxiesDisplayPreferences?
    {

        return nil

    }
}

 
 
 
 
 
struct ProxiesOverviewAdapter: View {
    @Environment(\.horizontalSizeClass)
    private var horizontalSizeClass

    @ObservedObject private var networkPath =
        NetworkPathObserver.shared

    private let sourceModel: ProxiesOverviewModel
    private let runtime: ProxiesRuntimeFacts
     
     
     
     
     
     
    private let outboundMode: ProxyBrowsingVisibility.Mode
     
     
    private let opening: ProxyBrowsingVisibility.Opening
    private let isConnected: Bool
    private let testingNames: Set<String>
    private let isTestingLatency: Bool
     
    private let sweepEvents: AnyPublisher<LatencySweepBatch, Never>?
    private let latencyCompletedCount: Int
    private let latencyTotalCount: Int
    private let testAll: (() -> Void)?
    private let testGroup: ((String) -> Void)?
     
    private let testShown: (([ClashProxiesShownMembers]) -> Void)?
     
    private let loadMembers: ((String) -> Void)?
     
    private let loadProviderNodes: ((String) -> Void)?
     
    private let searchMembers: ((String) -> Void)?
    private let switchSelection: ((String, String) -> Void)?
    private let setVisibleGroup: ((String?) -> Void)?
    private let updateProvider: ((String) -> Void)?
     
     
    private let setGroupExpanded: ((String, Bool) -> Void)?
    private let setGroupsExpanded: (([String], Bool) -> Void)?
    private let cancelLatency: (() -> Void)?
     
     
     
     
    private let refreshCatalog: (() -> Void)?
     
    private let unpinGroup: ((String) -> Void)?
     
    private let actionRefusals: [String: ClashGroupActionRefusal]
     
    private let testMember: ((String, String?) -> Void)?
     
    private let editMember: ((String) -> Void)?
    private let inspectMember: ((String) -> Void)?
     
     
    private let nodeScripts: [ClashProxyNodeScript]
    private let runNodeScript: ((String, String) -> Void)?
    private let initiallyExpandedGroup: String?
     
     
     
    private let rememberedExpandedGroups: Set<String>
    private let rememberedOpenGroup: String?
    private let readerFoldedAll: Bool

    @State private var preferences:
        ClashProxiesDisplayPreferences
    @State private var testAllDecision:
        NetworkPathPolicyDecision?
     
    @State private var pendingShown: [ClashProxiesShownMembers]?
     
     
     
     
     
     
    @State private var frozenSweep: FrozenSweep?
    @StateObject private var pulseHub = LatencyPulseHub()
     
     
     
     
    @State private var projections = ProxiesProjectionMemo()

     
     
     
     
    @Environment(\.clashLatencyPulseGate) private var latencyPulseGate
     
    @Environment(\.locale) private var locale

     
     
     
     
    private var isActiveRoot: Bool {
        latencyPulseGate?.isOpen ?? true
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    @State private var hiddenHold = SnapshotHold()
     
     
     
     
    @State private var shownAgain = 0

    final class SnapshotHold {
        var value: AppleClientSnapshot?
         
         
        var key: ProxiesSweepSnapshotHold.Key?
    }

    struct FrozenSweep: Equatable {
        let latency: [String: ClashProxyLatencyState]
         
         
         
        let failureCategories: [String: String]
        let completed: Int
        let total: Int
    }

     
     
     
     
     
     
     
     
     
    @MainActor
    final class LatencyPulseHub: ObservableObject {
        private let subject: CurrentValueSubject<ClashLatencyPulse, Never>
        private var accumulatedResults: [String: ClashProxyLatencyState] = [:]
        private var accumulatedGroupTerminals: [String: String] = [:]
         
        private var runLanded: Set<String> = []
        private var wasTesting = false
         
         
        let publisher: AnyPublisher<ClashLatencyPulse, Never>

         
         
         
         
         
         
         
         
        var current: ClashLatencyPulse { subject.value }

        init() {
            let initial = ClashLatencyPulse(
                results: [:],
                testing: [],
                completed: 0,
                total: 0,
                isTesting: false
            )
            subject = CurrentValueSubject(initial)
            publisher = subject.eraseToAnyPublisher()
        }

         
         
        var isRunning: Bool { wasTesting }

         
         
         
         
         
         
         
         
         
         
         
         
         
        func send(_ pulse: ClashLatencyPulse, landed: Set<String> = []) {
            if pulse.isTesting, !wasTesting {
                accumulatedResults.merge(pulse.results) { _, fresh in fresh }
                accumulatedGroupTerminals = pulse.groupTerminals
                runLanded = landed
            } else {
                 
                 
                 
                if pulse.isTesting, pulse.completed == 0 { runLanded = [] }
                runLanded.formUnion(landed)
                accumulatedResults.merge(pulse.results) { _, fresh in fresh }
                accumulatedGroupTerminals.merge(pulse.groupTerminals) {
                    _, fresh in fresh
                }
            }
            wasTesting = pulse.isTesting
            let replay = ClashLatencyPulse(
                results: accumulatedResults,
                testing: pulse.testing,
                groupTerminals: accumulatedGroupTerminals,
                 
                 
                 
                groupTerminalKeys: pulse.groupTerminalKeys,
                completed: pulse.completed,
                total: pulse.total,
                isTesting: pulse.isTesting,
                 
                 
                landed: runLanded
            )
            if !pulse.isTesting { runLanded = [] }
            subject.send(replay)
        }

         
         
         
         
         
         
        func replaceIdle(_ pulse: ClashLatencyPulse) {
            precondition(!pulse.isTesting)
            wasTesting = false
            runLanded = []
            accumulatedResults = pulse.results
            accumulatedGroupTerminals = pulse.groupTerminals
            subject.send(pulse)
        }

         
         
         
         
         
         
         
        func replay() {
            subject.send(subject.value)
        }
    }

    init(
        sourceModel: ProxiesOverviewModel,
        outboundMode: ProxyBrowsingVisibility.Mode,
        opening: ProxyBrowsingVisibility.Opening = .browsing,
        runtime: ProxiesRuntimeFacts = .none,
        isConnected: Bool = false,
        testingNames: Set<String> = [],
        isTestingLatency: Bool = false,
        sweepEvents: AnyPublisher<LatencySweepBatch, Never>? = nil,
        latencyCompletedCount: Int = 0,
        latencyTotalCount: Int = 0,
        testAll: (() -> Void)? = nil,
        testGroup: ((String) -> Void)? = nil,
        testShown: (([ClashProxiesShownMembers]) -> Void)? = nil,
        loadMembers: ((String) -> Void)? = nil,
        loadProviderNodes: ((String) -> Void)? = nil,
        searchMembers: ((String) -> Void)? = nil,
        switchSelection: ((String, String) -> Void)? = nil,
        setVisibleGroup: ((String?) -> Void)? = nil,
        updateProvider: ((String) -> Void)? = nil,
        setGroupExpanded: ((String, Bool) -> Void)? = nil,
        setGroupsExpanded: (([String], Bool) -> Void)? = nil,
        cancelLatency: (() -> Void)? = nil,
        refreshCatalog: (() -> Void)? = nil,
        unpinGroup: ((String) -> Void)? = nil,
        actionRefusals: [String: ClashGroupActionRefusal] = [:],
        testMember: ((String, String?) -> Void)? = nil,
        editMember: ((String) -> Void)? = nil,
        inspectMember: ((String) -> Void)? = nil,
        nodeScripts: [ClashProxyNodeScript] = [],
        runNodeScript: ((String, String) -> Void)? = nil,
        initiallyExpandedGroup: String? = nil,
        rememberedExpandedGroups: Set<String> = [],
        rememberedOpenGroup: String? = nil,
        readerFoldedAll: Bool = false,
        ownsNavigationContainer: Bool = true
    ) {
        self.ownsNavigationContainer = ownsNavigationContainer
        self.sourceModel = sourceModel
        self.runtime = runtime
        self.outboundMode = outboundMode
        self.opening = opening
        self.isConnected = isConnected
        self.testingNames = testingNames
        self.isTestingLatency = isTestingLatency
        self.sweepEvents = sweepEvents
        self.latencyCompletedCount = latencyCompletedCount
        self.latencyTotalCount = latencyTotalCount
        self.testAll = testAll
        self.testGroup = testGroup
        self.testShown = testShown
        self.loadMembers = loadMembers
        self.loadProviderNodes = loadProviderNodes
        self.searchMembers = searchMembers
        self.switchSelection = switchSelection
        self.setVisibleGroup = setVisibleGroup
        self.updateProvider = updateProvider
        self.setGroupExpanded = setGroupExpanded
        self.setGroupsExpanded = setGroupsExpanded
        self.cancelLatency = cancelLatency
        self.refreshCatalog = refreshCatalog
        self.unpinGroup = unpinGroup
        self.actionRefusals = actionRefusals
        self.testMember = testMember
        self.editMember = editMember
        self.inspectMember = inspectMember
        self.nodeScripts = nodeScripts
        self.runNodeScript = runNodeScript
        self.initiallyExpandedGroup = initiallyExpandedGroup
        self.rememberedExpandedGroups = rememberedExpandedGroups
        self.rememberedOpenGroup = rememberedOpenGroup
        self.readerFoldedAll = readerFoldedAll
        _preferences = State(
            initialValue:
                ClashProxiesDisplayPreferences.uiTestOverride()
                ?? ClashProxiesDisplayPreferences.load()
        )
    }

     
     
     
     
     
    private let ownsNavigationContainer: Bool

    var body: some View {
         
         
         
         
         
        ClashFeatureNavigationContainer(
            ownsNavigationContainer: ownsNavigationContainer
        ) {
            page
        }
         
         
         
         
         
        .alert(
            LocalizedStringKey(testAllDecision?.title ?? ""),
            isPresented: Binding(
                get: { testAllDecision != nil },
                set: { if !$0 { testAllDecision = nil } }
            ),
            presenting: testAllDecision
        ) { decision in
            if decision.action == .confirm {
                Button("Test All", role: .destructive) {
                    if let shown = pendingShown { testShown?(shown) } else { testAll?() }
                }
                Button("Cancel", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { decision in
            Text(clash: .copy(decision.message))
        }
    }

    @ViewBuilder
    private var page: some View {
        let browser = ClashClientUI.ClashProxiesView(
            snapshot: sharedSnapshot,
            actions: sharedActions,
            presentationClass:
                horizontalSizeClass == .regular
                    ? .regularTouch
                    : .compactTouch,
            palette: ClashClientUI.ClashProductPalette.clashProduct,
            showsDismissControl: ownsNavigationContainer,
            latencyPulse: pulseHub.publisher,
            latencyPulseSnapshot: { pulseHub.current }
        ) { symbol in
            ClashSymbolImage(symbol: symbol)
        }
         
         
         
         
         
         
         
         
         
        let live = browser
            .equatable()
            .onAppear { reseedLatencyPulseForEntry() }
            .onChange(of: isTestingLatency) { testing in
                if testing {
                    frozenSweep = FrozenSweep(
                        latency: latencyStates,
                        failureCategories: effectiveRuntime.shownFailureReasons,
                        completed: latencyCompletedCount,
                        total: latencyTotalCount
                    )
                     
                     
                     
                     
                    if !pulseHub.isRunning {
                        pulseHub.send(currentPulse(isTesting: true))
                    }
                } else {
                    frozenSweep = nil
                     
                     
                     
                     
                     
                     
                     
                     
                     
                    if sweepEvents == nil {
                        pulseHub.replaceIdle(currentPulse(isTesting: false))
                    }
                }
            }
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
            .onChange(of: idlePulseFacts) { facts in
                guard !isTestingLatency || !facts.isConnected else { return }
                pulseHub.replaceIdle(pulse(facts, isTesting: false))
            }
            .onReceive(
                latencyPulseGate?.opened.eraseToAnyPublisher()
                    ?? Empty<Void, Never>(completeImmediately: false).eraseToAnyPublisher()
            ) {
                 
                 
                 
                pulseHub.replay()
                 
                 
                guard hiddenHold.value != nil else { return }
                hiddenHold.value = nil
                hiddenHold.key = nil
                shownAgain &+= 1
            }
            .onReceive(
                sweepEvents
                    ?? Empty<LatencySweepBatch, Never>().eraseToAnyPublisher()
            ) { batch in
                 
                 
                pulseHub.send(ClashLatencyPulse(
                    results: batch.results.reduce(into: [:]) { states, entry in
                         
                         
                        let name = entry.key.split(separator: "\u{1F}", maxSplits: 1).last.map(String.init) ?? entry.key
                        states[entry.key] = ProxiesLatencyMapping.state(
                            delay: entry.value,
                            category: effectiveRuntime.failureReasons[name] ?? ""
                        )
                    },
                    testing: batch.testing,
                    groupTerminals: batch.groupTerminals,
                    groupTerminalKeys: batch.groupTerminalKeys,
                    completed: batch.completed,
                    total: batch.total,
                    isTesting: !batch.finished
                ), landed: Set(batch.results.keys))
            }
        if ownsNavigationContainer {
            live.clashSheetPresentation()
        } else {
            live
        }
    }

     
     
     
     
     
     
     
    private func reseedLatencyPulseForEntry() {
        ClashPerf.emit(
            "proxies latency reseed results=\(latencyStates.count) testing=\(isTestingLatency)"
        )
        let pulse = currentPulse(isTesting: isTestingLatency)
        if isTestingLatency {
            if frozenSweep == nil {
                frozenSweep = FrozenSweep(
                    latency: latencyStates,
                    failureCategories: effectiveRuntime.shownFailureReasons,
                    completed: latencyCompletedCount,
                    total: latencyTotalCount
                )
            }
            pulseHub.send(pulse)
        } else {
            frozenSweep = nil
            pulseHub.replaceIdle(pulse)
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
    struct IdlePulseFacts: Equatable {
        let results: [String: ClashProxyLatencyState]
        let groupTerminals: [String: String]
        let groupTerminalKeys: [String: String]
        let isConnected: Bool
    }

    private var idlePulseFacts: IdlePulseFacts {
        Self.idlePulseFacts(results: latencyStates, runtime: effectiveRuntime, isConnected: isConnected)
    }

    static func idlePulseFacts(
        results: [String: ClashProxyLatencyState],
        runtime: ProxiesRuntimeFacts,
        isConnected: Bool
    ) -> IdlePulseFacts {
        IdlePulseFacts(
            results: results,
             
             
             
             
             
             
            groupTerminals: isConnected ? runtime.resolvedNowByGroup : [:],
             
             
             
            groupTerminalKeys: isConnected
                ? NodeInventory.groupTerminalKeys(
                    groups: runtime.catalog, defaultURL: runtime.defaultDelayTestURL)
                : [:],
            isConnected: isConnected
        )
    }

    private func pulse(_ facts: IdlePulseFacts, isTesting: Bool) -> ClashLatencyPulse {
        ClashLatencyPulse(
            results: facts.results,
            testing: testingNames,
            groupTerminals: facts.groupTerminals,
            groupTerminalKeys: facts.groupTerminalKeys,
            completed: latencyCompletedCount,
            total: latencyTotalCount,
            isTesting: isTesting
        )
    }

    private func currentPulse(isTesting: Bool) -> ClashLatencyPulse {
        pulse(idlePulseFacts, isTesting: isTesting)
    }

    private var effectiveRuntime: ProxiesRuntimeFacts {


        return runtime
    }

     
     
     
     
     
     
     
     
     
     
    private var sharedSnapshot: AppleClientSnapshot {
         
         
         
         
         
         
         
         
         
         
         
         
        _ = shownAgain
        if !isActiveRoot, let held = hiddenHold.value {
            ClashPerf.count("proxies.snapshot.skipped-hidden")
            return held
        }
        let holdKey = sweepHoldKey
        if let held = hiddenHold.value,
           ProxiesSweepSnapshotHold.servesHeld(
               isSweeping: frozenSweep != nil,
               held: hiddenHold.key,
               current: holdKey
           ) {
            ClashPerf.count("proxies.snapshot.skipped-sweep")
            return held
        }
        let began = DispatchTime.now().uptimeNanoseconds
        let snapshot = builtSharedSnapshot
        let elapsed =
            Double(DispatchTime.now().uptimeNanoseconds - began) / 1_000_000
        ClashPerf.span(
            "proxies.snapshot",
            milliseconds: elapsed,
            detail: "groups=\(snapshot.proxies.groups.count)"
        )
        hiddenHold.value = snapshot
        hiddenHold.key = holdKey
        return snapshot
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func pinnedSelection(
        projected: String?,
        kernelFixed: String?,
        isConnected: Bool,
        groupsAreTheCores: Bool
    ) -> String? {
        guard isConnected else { return projected }
        if groupsAreTheCores { return kernelFixed }
        return projected ?? kernelFixed
    }

     
     
     
    static func groupSnapshot(
        _ group: ProxiesOverviewModel.Group,
        members: [ClashProxyMemberSnapshot],
        runtime: ProxiesRuntimeFacts,
        isConnected: Bool
    ) -> ClashProxyGroupSnapshot {
        var snapshot = ClashProxyGroupSnapshot(
            name: group.name,
            type: group.type,
            members: members,
            configuredSelection: pinnedSelection(
                projected: group.configuredSelection,
                kernelFixed: runtime.fixedByGroup[group.name],
                isConnected: isConnected,
                 
                 
                 
                groupsAreTheCores: runtime.groupsAreTheCores
                    && ProxyGroupControlKind(rawType: group.type).canBeUnpinned
            ),
            runtimeSelection: isConnected ? runtime.nowByGroup[group.name] : nil,
            resolvedRuntimeRoute: isConnected ? runtime.resolvedNowByGroup[group.name] : nil,
            icon: group.icon,
            emptyFallback: group.emptyFallback,
            memberTotal: group.memberTotal
        )
        snapshot.carriedSelection = group.carriedSelection
        return snapshot
    }

     
     
     
     
    static func memberLatencyEndpoints(_ catalog: [ProxyGroup]) -> [String: String?] {
        Dictionary(catalog.map { ($0.name, NodeInventory.readingURL(of: $0)) }, uniquingKeysWith: { first, _ in first })
    }

     
     
     
     
    private var sweepHoldKey: ProxiesSweepSnapshotHold.Key {
        ProxiesSweepSnapshotHold.Key(
            preferences: preferences,
            outboundModeToken: "\(outboundMode) \(opening)",
            isConnected: isConnected,
            nowByGroup: effectiveRuntime.nowByGroup,
            resolvedNowByGroup: effectiveRuntime.resolvedNowByGroup,
            groupCount: sourceModel.groups.count
                + effectiveRuntime.catalog.count,
            ungroupedCount: sourceModel.ungrouped.count
                + effectiveRuntime.runtimeNodes.count
        )
    }

     
     
     
     
     
     
     
     
     
     
    private var builtSharedSnapshot: AppleClientSnapshot {
        let groupsKey = ProxiesProjectionMemo.GroupsKey(
            outboundMode: outboundMode,
            source: sourceModel.groups,
            runtimeCatalog: effectiveRuntime.catalog,
            nowByGroup: effectiveRuntime.nowByGroup,
            resolvedNowByGroup: effectiveRuntime.resolvedNowByGroup,
             
             
            groupsAreTheCores: effectiveRuntime.groupsAreTheCores,
            isConnected: isConnected,
            opening: opening
        )
         
         
         
         
         
         
         
         
        let facts = effectiveRuntime
        let projection = ClashPerf.measure("proxies.snapshot.groups") {
            projections.groups(groupsKey) {
                let all = ClashPerf.measure("proxies.compose.groups") {
                    ProxiesRuntimeCatalogComposer.groups(
                        source: sourceModel.groups,
                        runtime: effectiveRuntime.catalog,
                        isConnected: isConnected
                    )
                }
                let urlByGroup = Self.memberLatencyEndpoints(effectiveRuntime.catalog)
                let defaultURL = effectiveRuntime.defaultDelayTestURL
                func snapshot(_ group: ProxiesOverviewModel.Group) -> ClashProxyGroupSnapshot {
                    Self.groupSnapshot(
                        group,
                        members: ProxyBrowsingVisibility.members(
                            projections.members(of: group, latencyEndpoint: urlByGroup[group.name] ?? nil,
                                                defaultURL: defaultURL),
                            of: group.name,
                            mode: outboundMode,
                            opening: opening,
                            name: \.name
                        ),
                        runtime: facts,
                        isConnected: isConnected
                    )
                }
                let listed = ProxyBrowsingVisibility.groups(all, mode: outboundMode, opening: opening,
                                                            name: \.name, isHidden: \.hidden)
                 
                 
                let shown = Set(listed.map(\.name))
                return ProxiesProjectionMemo.GroupProjection(
                    listed: listed.map(snapshot),
                    hidden: all.filter { $0.hidden && !shown.contains($0.name) }.map(snapshot)
                )
            }
        }
        let groups = projection.listed
        let searchable = ClashPerf.measure("proxies.snapshot.searchable") {
            ProxiesRuntimeCatalogComposer.searchableProxies(
                source: sourceModel.proxies,
                runtime: effectiveRuntime.runtimeNodes,
                isConnected: isConnected,
                runtimeIsAuthoritative: effectiveRuntime.isAuthoritative
            ).map {
                ClashProxySnapshot(
                    name: $0.name,
                    type: $0.type
                )
            }
        }
         
         
         
         
        let editableMembers: Set<String> = editMember == nil
            ? []
            : Set(sourceModel.proxies.map(\.name))
         
         
        let providerNote = { (note: ProviderNote) -> String in
            ClashCopy.string(for: note.displayText(locale: locale), locale: locale)
        }
        let composedProviders = ProxiesRuntimeCatalogComposer.providers(
            source: sourceModel.providers,
            runtime: effectiveRuntime.providerCatalog,
            isConnected: isConnected
        )
        let providers = ClashPerf.measure("proxies.snapshot.providers") {
            composedProviders.map { provider in
                ClashProxyProviderSnapshot(
                    name: provider.name,
                    displayName: ConfigurationComposer.displayName(forComposedProviderName: provider.name),
                    type: provider.type,
                    nodeCount: provider.nodeCount,
                     
                     
                     
                    nodes: effectiveRuntime.providerCatalog
                        .proxyProviders[provider.name]
                        .flatMap { $0.proxies.isEmpty && $0.nodeCount > 0 ? nil : $0.proxies }?
                        .map {
                            ClashProxyMemberSnapshot(
                                name: $0.name,
                                type: $0.type ?? ""
                            )
                        },
                     
                     
                     
                    loadFailure: provider.note.flatMap { $0.isFailure ? providerNote($0) : nil },
                    note: provider.note.flatMap { $0.isFailure || !$0.isShown ? nil : providerNote($0) }
                )
            }
        }
         
         
         
        let drawsFrom = Dictionary(sourceModel.groups.map { ($0.name, $0.drawsFromProviders) },
                                   uniquingKeysWith: { first, _ in first })
        func noting(_ group: ClashProxyGroupSnapshot) -> ClashProxyGroupSnapshot {
            guard group.isEmpty, let names = drawsFrom[group.name], !names.isEmpty,
                  let note = ProxiesOverviewModel.emptyGroupNote(drawsFrom: names, providers: composedProviders)
            else { return group }
            var noted = group
            noted.emptyNote = providerNote(note)
            return noted
        }
        let explainsEmptyGroups = composedProviders.contains { $0.note != nil }
        let notedGroups = explainsEmptyGroups ? groups.map(noting) : groups
        let notedHiddenGroups = explainsEmptyGroups ? projection.hidden.map(noting) : projection.hidden
        let ungroupedKey = ProxiesProjectionMemo.UngroupedKey(
            outboundMode: outboundMode,
            source: sourceModel.ungrouped,
            runtimeNodes: effectiveRuntime.runtimeNodes,
            runtimeGroups: effectiveRuntime.catalog,
            isConnected: isConnected,
            runtimeIsAuthoritative: effectiveRuntime.isAuthoritative,
            opening: opening
        )
        let ungrouped = ClashPerf.measure("proxies.snapshot.ungrouped") {
            projections.ungrouped(ungroupedKey) {
                ProxyBrowsingVisibility.standaloneNodes(
                    ProxiesRuntimeCatalogComposer.ungrouped(
                        source: sourceModel.ungrouped,
                        runtimeNodes: effectiveRuntime.runtimeNodes,
                        runtimeGroups: effectiveRuntime.catalog,
                        isConnected: isConnected,
                        runtimeIsAuthoritative: effectiveRuntime.isAuthoritative
                    ).map {
                        ClashProxySnapshot(
                            name: $0.name,
                            type: $0.type
                        )
                    },
                    mode: outboundMode,
                    opening: opening
                )
            }
        }
        return AppleClientSnapshot(
            revision: 0,
            connection: AppleClientConnectionSnapshot(
                phase: isConnected
                    ? .connected
                    : .disconnected
            ),
            proxies: ClashProxiesSnapshot(
                groups: notedGroups,
                hiddenGroups: notedHiddenGroups,
                searchableProxies: searchable,
                providers: providers,
                ungrouped: ungrouped,
                 
                 
                 
                browsingSuppressedByDirectMode:
                    ProxyBrowsingVisibility.browsingMode(outboundMode, opening: opening) == .direct,
                latencyByName: frozenSweep?.latency ?? latencyStates,
                 
                 
                 
                 
                failureCategories: frozenSweep?.failureCategories
                    ?? effectiveRuntime.shownFailureReasons,
                isConnected: isConnected,
                isTestingLatency: frozenSweep != nil || isTestingLatency,
                latencyCompletedCount: frozenSweep?.completed ?? latencyCompletedCount,
                latencyTotalCount: frozenSweep?.total ?? latencyTotalCount,
                initiallyExpandedGroup:
                    initiallyExpandedGroup,
                rememberedExpandedGroups: rememberedExpandedGroups,
                displayPreferences: preferences,
                 
                 
                 
                catalogState: isConnected
                    ? nil
                    : sourceModel.catalogRefusal.map {
                        .failed(message: ClashCopy.format(
                            "The core cannot read this configuration: %@. Connecting will get the same answer.",
                            locale: locale, $0))
                    }
                    ?? (sourceModel.catalogUnavailable
                        ? .failed(message: ClashCopy.string(
                            "The groups cannot be read right now; they appear once you connect.",
                            locale: locale))
                        : nil),
                canRefreshCatalog: refreshCatalog != nil,
                 
                 
                 
                 
                canUnpinGroups: unpinGroup != nil,
                actionRefusals: actionRefusals,
                editableMembers: editableMembers,
                rememberedOpenGroup: rememberedOpenGroup,
                readerFoldedAll: readerFoldedAll,
                 
                liveCatalog: isConnected && effectiveRuntime.isAuthoritative,
                 
                nodeScripts: runNodeScript == nil ? [] : nodeScripts
            ),
            capabilities: AppleClientCapabilities([
                .proxies: .available,
            ])
        )
    }

    private var latencyStates:
        [String: ClashProxyLatencyState]
    {
        var values: [String: ClashProxyLatencyState] = [:]
         
         
         
        let reasons = effectiveRuntime.shownFailureReasons
        for (name, value) in effectiveRuntime.delays {
            values[name] = ProxiesLatencyMapping.state(
                delay: value,
                category: reasons[name] ?? ""
            )
        }
        for name in testingNames {
            values[name] = .testing
        }
        return values
    }

    private var sharedActions: AppleClientActions {
        AppleClientActions(capability: .proxies) { action in
            guard case .proxies(let command) = action else {
                return
            }
             
             
            ClashLogStore.shared.append(
                "proxies command  \(String(describing: command))",
                stream: .app
            )
            switch command {
            case .refresh:
                refreshCatalog?()
            case .testAll:
                requestTestAll()
            case .testShown(let shown):
                requestTestAll(shown: shown)
            case .testGroup(let name):
                testGroup?(name)
            case .loadMembers(let group):
                loadMembers?(group)
            case .loadProviderNodes(let provider):
                loadProviderNodes?(provider)
            case .searchMembers(let query):
                searchMembers?(query)
            case .testMember(let name, let group):
                testMember?(name, group)
            case .editMember(let name):
                editMember?(name)
            case .inspectMember(let name):
                inspectMember?(name)
            case .runNodeScript(let id, let node):
                runNodeScript?(id, node)
            case .unpin(let group):
                unpinGroup?(group)
            case .select(let group, let member):
                switchSelection?(group, member)
            case .setDisplayPreferences(let updated):
                preferences = updated
                updated.save()
            case .setVisibleGroup(let name):
                setVisibleGroup?(name)
            case .updateProvider(let name):
                updateProvider?(name)
            case .setGroupExpanded(let name, let isExpanded):
                setGroupExpanded?(name, isExpanded)
            case .setGroupsExpanded(let names, let isExpanded):
                if let setGroupsExpanded {
                    setGroupsExpanded(names, isExpanded)
                } else {
                     
                     
                    for name in names {
                        setGroupExpanded?(name, isExpanded)
                    }
                }
            case .cancelLatency:
                cancelLatency?()
            }
        }
    }

    private func requestTestAll(shown: [ClashProxiesShownMembers]? = nil) {
        let decision = NetworkPathPolicy.fullTransfer(
            snapshot: networkPath.snapshot
        )
        switch decision.action {
        case .allow:
            if let shown { testShown?(shown) } else { testAll?() }
        case .confirm, .block:
            pendingShown = shown
            testAllDecision = decision
        case .deferOperation:
            break
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
enum ProxiesLatencyMapping {
    static func state(delay: Int, category: String) -> ClashProxyLatencyState {
        if delay > 0 { return .measured(milliseconds: delay) }
        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "timeout" ? .timedOut : .failed
    }
}
