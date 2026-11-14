import Combine
import Clash
import Foundation
import NetworkExtension
import ClashClientKit

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
final class ClashTVTunnelController: ObservableObject {
     
     
    @Published var state: ClashTVProductState = .empty

     
     
     
     
    @Published var lastActivation: Activation?
    @Published private(set) var isApplyingIPStack = false
    let ipStackDefaults: UserDefaults

    struct Activation: Equatable {
        let subscriptionID: ClashTVSubscription.ID
        let at: Date
         
        var panelName: String? = nil
    }

    static let vpnProfileTitle = "Clash"
    static let vpnProfileDescription = "Clash"
     
     
     
     
     
    static let providerNotLaunchedMessage = String(localized: "Connection failed. Select Reinstall VPN Profile.")

     
     
     
     
     
    nonisolated static var defaultContainer: URL? {
        if let group = ClashAppIdentifiers.appGroupContainer { return group }

        return nil

    }
    static let messageTimeout: TimeInterval = 8
     
    private static let reloadTimeout: TimeInterval = 30

    private let container: URL?
    private let session: URLSession
     
    private let autoConnect: ClashTVAutoConnect.Store
     
     
    typealias ProfileLoader = @MainActor () async throws -> [any ClashTVSystemProfile]
    typealias ProfileMaker = @MainActor () -> any ClashTVSystemProfile
     
     
     
     
    private let coordinator: ClashTVProfileCoordinator
     
     
    private var manager: (any ClashTVSystemProfile)? { coordinator.current }
    private var statusObserver: NSObjectProtocol?
    private var pollTask: Task<Void, Never>?
    typealias MessageReader = @MainActor (Data, UInt64, Bool) async throws -> Data
    private let messageReader: MessageReader?
     
    private let ipcChannel: ClashTVIPCChannel
     
     
     
    typealias PendingSeedPreparer = @Sendable (_ container: URL, _ publishedConfig: String) throws -> String
    private let preparePendingSeeds: PendingSeedPreparer
    private let pollSleep: @MainActor () async throws -> Void
    private var presentation = ClashTVPollingPresentation(page: .configuration, active: false)
    private var presentationEpoch: UInt64 = 0
    private let observationClock: @MainActor () -> ClashTVObservation.Moment

    func updatePresentation(_ presentation: ClashTVPollingPresentation) {
        guard self.presentation != presentation else { return }
         
         
        if presentation.active, !self.presentation.active {
            pendingCompileDue = clock()
            Task { @MainActor [weak self] in await self?.repairNodeLibrary() }
        }
        self.presentation = presentation
        presentationEpoch &+= 1
        state.observations.waitForUpdate()
        stopPolling()
        if presentation.active {
             
            statusChanged()
            startPolling()
        }
    }
    private var startRequested = false
     
     
     
     
    private var stopRequested = false
     
     
     
     
     
    private var stopEpoch = 0
     
     
     
     
     
    private var connectTask: Task<Void, Never>?
     
    private var refreshTask: Task<Void, Never>?
     
     
     
    private var reinstallInFlight = false
     
     
    private var startGeneration = 0
    private var groupOrder: [String] = []
    private var lastKnownStatus: NEVPNStatus = .invalid
     
    private var startFailureTracker = VPNStartFailureTracker()
    private let clock: @MainActor () -> Date
    private var ipcGeneration = ClashTVIPCGeneration(active: false)
    private var observedIPCProfile: ObjectIdentifier?
    private var observedIPCSession: ObjectIdentifier?
    private var controlRevision: UInt64 = 0
     
     
     
    private var modeRequestRevision: UInt64 = 0
     
     
     
    private var askedGlobal: (revision: UInt64, generation: ClashTVIPCGeneration, profile: ClashTVSubscription.ID?)?
     
     
    private var modeSendsInFlight = 0
    private var activeObservationGeneration: UInt64?
    private var ruleProbePointer: ActiveConfigurationPointer?
    private var ruleProbeGeneration: ClashTVIPCGeneration?
    private var nextRuleProbeAt = Date.distantPast
    private var ruleProbeBackoff: TimeInterval = 3
    private var ruleRecoveryPending = false

    private func replaceIPCGeneration(active: Bool) {
        ipcGeneration.invalidate()
        state.observations.beginGeneration()
        sweepingMembers = []
        documentMark = nil
        documentReadAt = nil
        state.pendingCompileFailures = [:]
        testedAt = [:]
        unappliedDelayNames = [:]
        delayBook = .init()
        delayCursor = .init()
        rebuildingDelays = false
        memberPages = [:]
        memberRevision = nil
        lastSummary = nil
        ipcGeneration = ClashTVIPCGeneration(active: active)
    }

    init(
        container: URL? = ClashTVTunnelController.defaultContainer,
        session: URLSession = ClashTVNetwork.session,
        autoConnect: ClashTVAutoConnect.Store = ClashTVAutoConnect.Store(),
        loadProfiles: @escaping ProfileLoader = { try await NETunnelProviderManager.loadAllFromPreferences() },
        makeProfile: @escaping ProfileMaker = { NETunnelProviderManager() },
        preferencesTimeout: TimeInterval = 15,
        ipStackDefaults: UserDefaults = UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite) ?? .standard,
        messageReader: MessageReader? = nil,
        observationClock: @escaping @MainActor () -> ClashTVObservation.Moment = { .init(date: Date()) },
        clock: @escaping @MainActor () -> Date = { Date() },
        pollSleep: @escaping @MainActor () async throws -> Void = { try await Task.sleep(for: .seconds(1)) },
        preparePendingSeeds: PendingSeedPreparer? = nil,
        ipcChannel: ClashTVIPCChannel = .shared
    ) {
        self.ipcChannel = ipcChannel
        self.ipStackDefaults = ipStackDefaults
        self.container = container
        self.messageReader = messageReader
        self.preparePendingSeeds = preparePendingSeeds ?? { container, published in
            try ClashTVPendingSeeds.prepare(container: container, publishedConfig: published)
        }
        self.observationClock = observationClock
        self.clock = clock
        self.pollSleep = pollSleep
        self.session = session
        self.autoConnect = autoConnect
        self.coordinator = ClashTVProfileCoordinator(
            intent: autoConnect.isEnabled,
            persistIntent: { autoConnect.set($0) },
            load: loadProfiles,
            make: makeProfile,
            timeout: preferencesTimeout,
            ownedBy: { ClashTVTunnelController.owns($0) }
        )
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, let connection = notification.object as? NEVPNConnection else { return }
            Task { @MainActor in
                guard let managed = self.manager?.vpnConnection, connection === managed else { return }
                self.statusChanged()
            }
        }
    }

    deinit {
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver)
        }
        pollTask?.cancel()
    }

     

     
     
     
     
     
     
    func prepare(subscription: ClashTVSubscription?) async {
        do {
            try await coordinator.find()
        } catch {
            report(issue: error.localizedDescription)
        }
        state.autoConnect = autoConnect.isEnabled
        showConfiguration(for: subscription)
        statusChanged()
        preparedSubscription = subscription
        await repairNodeLibrary()
    }

     
    private var preparedSubscription: ClashTVSubscription?
     
     
     
     
    private static let repairedRefusalKey = "clash.tv.nodeLibrary.repairedRefusal"
    private var repairedRefusal: String? {
        get { ipStackDefaults.string(forKey: Self.repairedRefusalKey) }
        set { ipStackDefaults.set(newValue, forKey: Self.repairedRefusalKey) }
    }

     
     
     
     
     
     
     
     
     
     
     
    func repairNodeLibrary() async {
        func idle() -> Bool { !state.isConnected && connectTask == nil && refreshTask == nil }
        guard let subscription = preparedSubscription ?? connectedSubscription, idle(),
              !needsActivation(for: subscription) else { return }
        var refusal: String?
        if let error = await manager?.lastDisconnectError(), Self.isNodeLibraryUnavailable(error) {
            refusal = (error as NSError).localizedDescription
        }
        let refusedAgain = refusal != nil && refusal != repairedRefusal
        let gone = refusedAgain ? false : await activeLibraryIsGone()
        guard refusedAgain || gone else { return }
        guard idle(), (preparedSubscription ?? connectedSubscription)?.id == subscription.id,
              !needsActivation(for: subscription) else { return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let ipStack = try IPStackSettings.load(from: self.ipStackDefaults)
                let activated = try await self.activate(subscription, settings: ipStack) { _ in }
                self.noteActivation(subscription, panelName: activated.panelName)
                if let refusal { self.repairedRefusal = refusal }
                 
                if let chosen = self.preparedSubscription, chosen.id != subscription.id {
                    self.showConfiguration(for: chosen)
                }
                ClashLogStore.shared.append("tv node library published again before the next start", stream: .app)
            } catch {
                ClashLogStore.shared.append("tv node library not published again  reason=\(error.localizedDescription)",
                                           stream: .app, level: .warning)
            }
        }
        refreshTask = task
        await task.value
        if refreshTask == task { refreshTask = nil }
    }

     
     
     
    func connect(subscription: ClashTVSubscription) async {
        await connect(subscription: subscription, republishing: false)
    }

     
     
     
    private func connect(subscription: ClashTVSubscription, republishing: Bool) async {
        guard connectTask == nil else { return }
        if !republishing { libraryRepublished = false }
        guard !isApplyingIPStack else {
             
             
             
             
             
             
            state.post(ClashTVFeedback.busy(.applying), for: .ipStack)
            return
        }
         
         
         
         
         
         
        stopRequested = false
         
         
         
        if let refreshTask {
            let epoch = stopEpoch
            await refreshTask.value
             
             
             
             
            guard connectTask == nil, !isApplyingIPStack, stopEpoch == epoch else { return }
            if let chosen = preparedSubscription, chosen.id != subscription.id { return }
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performConnect(subscription, republish: republishing)
        }
        connectTask = task
        await task.value
         
         
        if connectTask == task { connectTask = nil }
    }

    private func performConnect(_ subscription: ClashTVSubscription, republish: Bool = false) async {
        state.issue = nil
        state.vpnAuthorization = nil
        startGeneration += 1
        connectedSubscription = subscription
        do {
            let ipStack = try IPStackSettings.load(from: ipStackDefaults)
             
             
            let libraryGone = await activeLibraryIsGone()
             
             
             
            let setsLeft = await activeRevisionLeftRuleSetsToTheTunnel()
            if republish || needsActivation(for: subscription) || libraryGone {
                state.pipelinePhase = .downloading
                defer { state.pipelinePhase = nil }
                let activated = try await activate(subscription, settings: ipStack) { [weak self] phase in self?.state.pipelinePhase = phase }
                noteActivation(subscription, panelName: activated.panelName)
            } else if setsLeft, let container {
                 
                 
                 
                 
                 
                 
                 
                state.pipelinePhase = .downloading
                defer { state.pipelinePhase = nil }
                for _ in 0..<2 {
                    guard let expected = try? ConfigResourceStore(containerURL: container).activeIdentity() else { break }
                    do {
                        if try await ClashTVConfigPipeline(container: container, session: session, settings: ipStack)
                            .prepareLeftRuleSets(expected: expected) != nil {
                            loadActiveConfigurationFacts()
                        }
                    } catch {
                        if error is CancellationError || Task.isCancelled { throw CancellationError() }
                        ClashLogStore.shared.append("tv connect: rule sets left to the tunnel  reason=\(error.localizedDescription)",
                                                   stream: .app, level: .warning)
                    }
                    guard (try? ConfigResourceStore(containerURL: container).activeIdentity()) != expected,
                          await activeRevisionLeftRuleSetsToTheTunnel() else { break }
                }
            }
             
             
            if let container, let store = try? ConfigResourceStore(containerURL: container),
               let expected = try? store.activeIdentity() {
                do {
                    _ = try await ClashTVConfigPipeline(container: container, session: session, settings: ipStack).recoverRules(expected: expected)
                    loadActiveConfigurationFacts()
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                     
                     
                    ClashLogStore.shared.append("tv startup rule recovery: \(error.localizedDescription)", stream: .app, level: .warning)
                }
            }
            try Task.checkCancellation()
             
             
            try await start(settings: ipStack, userInitiated: true)
        } catch ClashTVProfileCoordinator.StartError.permissionNotGranted {
            state.pipelinePhase = nil
            state.issue = nil
            state.vpnAuthorization = .notCompleted
            startRequested = false
            statusChanged()
        } catch is CancellationError {
            state.vpnAuthorization = nil
             
             
            state.pipelinePhase = nil
            ClashLogStore.shared.append("tv connect cancelled", stream: .app)
            statusChanged()
        } catch {
            state.vpnAuthorization = nil
            state.pipelinePhase = nil
            report(issue: error.localizedDescription, aboutProfile: Self.isAboutProfile(error))
             
             
             
            state.post(ClashTVFeedback.couldNotConnect(reason: error.localizedDescription), for: .connect, remembers: false)
            ClashLogStore.shared.append("tv connect failed  reason=\(error.localizedDescription)", stream: .app, level: .warning)
            statusChanged()
        }
    }

     
     
     
     
     
     
     
     
     
     
     
    func refresh(subscription: ClashTVSubscription, announces: Bool = true) async {
        guard connectTask == nil, refreshTask == nil else {
             
             
             
            if announces {
                state.beginOperation()
                state.post(ClashTVFeedback.busy(connectTask != nil ? .connecting : .updating), for: .update(subscription.id))
            }
            return
        }
        if announces { state.beginOperation() }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performRefresh(subscription, announces: announces)
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

     
     
     
     
     
    func updateScript(subscription: ClashTVSubscription, isCurrent: Bool) async {
        guard connectTask == nil, refreshTask == nil else {
            state.beginOperation()
            state.post(ClashTVFeedback.busy(connectTask != nil ? .connecting : .updating), for: .script(subscription.id))
            return
        }
        state.beginOperation()
        guard let container else {
            let reason = ControllerError.appGroupUnavailable.localizedDescription
            state.refresh = .failed(subscription.id, reason)
            state.post(ClashTVFeedback.couldNotUpdateScript(subscription.title, reason: reason), for: .script(subscription.id))
            return
        }
        state.refresh = .updating(subscription.id, .downloading)
        do {
            _ = try await ClashTVConfigPipeline(container: container, session: session).updateScript(for: subscription)
            state.refresh = nil
        } catch {
            state.refresh = .failed(subscription.id, error.localizedDescription)
            state.post(ClashTVFeedback.couldNotUpdateScript(subscription.title, reason: error.localizedDescription), for: .script(subscription.id))
            ClashLogStore.shared.append("tv script update failed  reason=\(error.localizedDescription)", stream: .app, level: .warning)
            return
        }
         
         
         
        if isCurrent {
            await refresh(subscription: subscription)
        } else {
            state.post(ClashTVFeedback.scriptUpdated(subscription.title), for: .script(subscription.id))
        }
    }

    private func performRefresh(_ subscription: ClashTVSubscription, announces: Bool = true) async {
        let generation = ipcGeneration
         
         
         
         
        let running = state.isConnected ? activeConfigurationFacts() : nil
        state.refresh = .updating(subscription.id, .downloading)
        do {
            let activated = try await activate(subscription) { [weak self] phase in
                self?.state.refresh = .updating(subscription.id, phase)
            }
            state.refresh = nil
            var warning: String?
            var changed = activated.changed
            if state.isConnected {
                warning = try await reloadOrRestart(subscription, expectedGeneration: generation)
                 
                 
                 
                 
                 
                if generation === ipcGeneration, generation.isValid {
                    let checks = await checkProviders(expectedGeneration: generation)
                    warning = ([warning].compactMap { $0 } + checks.failed).joined(separator: "\n").nilIfEmpty
                    changed = changed || checks.changed
                } else {
                    checksAfterRestart = (subscription.title, startGeneration)
                     
                     
                    changed = true
                }
            } else {
                 
                 
                 
                 
                let failed = state.providers.compactMap { entry -> String? in
                    guard entry.url != nil else { return nil }
                    switch entry.note {
                    case .downloadFailed(let reason)?: return ClashTVProvidersScreen.failedLine(entry.name, .download, reason: reason.text)
                    case .unreadable(let reason)?: return ClashTVProvidersScreen.resultLine(entry.name, reason.text)
                    default: return nil
                    }
                }
                warning = failed.joined(separator: "\n").nilIfEmpty
            }
            noteActivation(subscription, panelName: activated.panelName)
             
             
             
            if announces {
                let said = warning.map { ClashTVFeedback.updatedWithWarning(subscription.title, warning: $0) }
                    ?? (changed ? ClashTVFeedback.updated(subscription.title) : ClashTVFeedback.upToDate(subscription.title))
                state.post(said, for: .update(subscription.id))
            } else if let warning {
                 
                 
                state.note(problem: ClashTVFeedback.spoken(ClashTVFeedback.updatedWithWarning(subscription.title, warning: warning)))
            }
        } catch is CancellationError {
            state.refresh = nil
        } catch ControllerError.kernelRefused(let reason) {
             
             
            if let running {
                apply(facts: running.facts, catalog: running.catalog, fallbackCount: running.fallbackCount,
                      ruleFacts: running.ruleFacts, publishedPath: running.publishedPath)
                await refreshStatus()
            }
            let sentence = ControllerError.kernelRefused(reason).localizedDescription
            state.refresh = .failed(subscription.id, sentence)
            updateFailed(subscription, reason: sentence, announces: announces)
            ClashLogStore.shared.append("tv update refused; the screens show the running configuration  reason=\(reason)", stream: .app, level: .warning)
        } catch {
             
             
            state.refresh = .failed(subscription.id, error.localizedDescription)
            updateFailed(subscription, reason: error.localizedDescription, announces: announces)
            ClashLogStore.shared.append("tv update failed  reason=\(error.localizedDescription)", stream: .app, level: .warning)
        }
    }

     
     
     
     
     
    func take(_ outcome: ClashTVAutoUpdate.BackgroundOutcome, row: ClashTVSubscription?,
              current: ClashTVSubscription?) async {
        let title = row?.title ?? outcome.subscriptionID.absoluteString
        if let failure = outcome.failure {
            state.note(problem: ClashTVFeedback.spoken(ClashTVFeedback.couldNotUpdate(title, reason: failure)), at: outcome.at, aboutProfile: true)
            return
        }
        guard let current, current.id == outcome.subscriptionID, state.isConnected,
              connectTask == nil, refreshTask == nil else { return }
        let generation = ipcGeneration
         
         
         
        let published = container.flatMap { try? ConfigResourceStore(containerURL: $0) }?.activeIdentityOrNil()
        do {
            let warning = try await reloadOrRestart(current, expectedGeneration: generation)
             
            loadActiveConfigurationFacts()
            var checks: (failed: [String], changed: Bool) = ([], false)
            if generation === ipcGeneration, generation.isValid {
                checks = await checkProviders(expectedGeneration: generation)
            } else {
                checksAfterRestart = (current.title, startGeneration)
            }
            if let said = ([warning].compactMap { $0 } + checks.failed).joined(separator: "\n").nilIfEmpty {
                state.note(problem: ClashTVFeedback.spoken(ClashTVFeedback.updatedWithWarning(current.title, warning: said)))
            }
        } catch {
             
             
             
             
             
            if case ControllerError.kernelRefused = error, let previous = outcome.previous,
               let running = configurationFacts(of: previous) {
                if let container, let store = try? ConfigResourceStore(containerURL: container),
                   let published, published != previous,
                   (try? store.activateIfCurrentMatches(published, replacement: previous)) == true {
                    apply(facts: running.facts, catalog: running.catalog, fallbackCount: running.fallbackCount,
                          ruleFacts: running.ruleFacts, publishedPath: running.publishedPath)
                } else {
                     
                    loadActiveConfigurationFacts()
                }
            }
            state.note(problem: ClashTVFeedback.spoken(ClashTVFeedback.couldNotUpdate(current.title, reason: error.localizedDescription)), aboutProfile: true)
        }
    }

     
     
     
     
     
     
    private func checkProviders(expectedGeneration generation: ClashTVIPCGeneration) async -> (failed: [String], changed: Bool) {
        var failed: [String] = []
        var changed = false
        for entry in state.providers {
            guard let url = entry.url, entry.note != .inline else { continue }
            let target = ProviderUpdateTarget(kind: entry.kind, name: entry.name, vehicle: "http", url: url,
                                              fetchedByCore: false)
            guard ProviderUpdateRoute.decide(target, tunnelRunning: true) == .tunnel, generation.isValid else { continue }
            do {
                let reply = try await send(["cmd": "updateProvider", "kind": entry.kind, "name": entry.name,
                                            "timeoutMilliseconds": Self.providerCheckMilliseconds],
                                           timeout: Self.providerCheckTimeout, expectedGeneration: generation)
                let object = (try? JSONSerialization.jsonObject(with: reply)) as? [String: Any]
                if let english = object?["error"] as? String, let refusal = object.flatMap(ClashTVKernelSnapshots.refusal(in:)) {
                     
                     
                    switch ProviderUpdateRefusal(english) {
                    case .busy?:
                        failed.append(ClashTVProvidersScreen.resultLine(entry.name, AuthoredText.app("Can't update right now — try again in a moment").text))
                    case .stillRunning?:
                        failed.append(ClashTVProvidersScreen.resultLine(entry.name, AuthoredText.app("Still updating").text))
                    case .unavailable?:
                        failed.append(ClashTVProvidersScreen.resultLine(entry.name, refusal.text))
                    case nil:
                        failed.append(ClashTVProvidersScreen.failedLine(entry.name, .update, reason: refusal.text))
                    }
                    continue
                }
                let answer = ProviderUpdateAnswer.decode(String(decoding: reply, as: UTF8.self))
                switch answer?.result {
                case .updated?: changed = true
                case .unchanged?: break
                case .failed?:
                    failed.append(ClashTVProvidersScreen.failedLine(entry.name, .update, reason: answer?.error))
                case .pendingApp?:
                    changed = true
                    let reason = answer?.pendingReason
                    let taker = ProviderRefreshState.pendingTaker(kind: entry.kind, reason: reason, variant: nil,
                                                                  appCanFetch: reason == "routes" || reason == "recompile")
                    if let line = answer?.displayLine(taker: taker) {
                        failed.append(ClashTVProvidersScreen.resultLine(entry.name, AuthoredText.app(line.key, arguments: line.arguments).text))
                    }
                case .scheduled?, nil:
                    failed.append(ClashTVProvidersScreen.resultLine(entry.name, AuthoredText.app("Still updating").text))
                }
            } catch {
                ClashLogStore.shared.append("tv provider check  name=\(entry.name) reason=\(error.localizedDescription)", stream: .app, level: .warning)
                failed.append(ClashTVProvidersScreen.resultLine(entry.name, error.localizedDescription))
            }
        }
        readProviderRefresh()
        state.ruleProvidersLoaded = ClashTVProvidersScreen.readyCount(state.providers, tunnel: state.providerRefresh,
                                                                        running: state.isConnected)
        return (failed, changed)
    }

     
     
     
     
     
     
    static let providerCheckMilliseconds = 4_000
    private static let providerCheckTimeout: TimeInterval = 7

     

     
     
     
     
     
     
    private var pendingCompileDue: Date?
    private var lastPendingCompile = Date.distantPast
    private var pendingCompileTask: Task<Void, Never>?
     
    var isCompilingPending: Bool { pendingCompileTask != nil }
    static let pendingCompileAfterConnect: TimeInterval = 3
     
     
     
    static let seedTimeout: TimeInterval = 15
    static let pendingCompileInterval: TimeInterval = 10

     
     
     
    private func pendingCompileIsDue(at now: Date) -> Bool {
        guard pendingCompileTask == nil else { return false }
        if let due = pendingCompileDue, now.timeIntervalSince(due) >= 0 { return true }
        guard now.timeIntervalSince(lastPendingCompile) >= Self.pendingCompileInterval else { return false }
        readProviderRefresh()
        if ClashTVPendingSeeds.waitsForTheApp(state.providerRefresh) { return true }
         
        lastPendingCompile = now
        return false
    }

     
     
    func compilePendingProviders() async {
        await startPendingCompile().value
    }

     
     
    @discardableResult
    private func startPendingCompile() -> Task<Void, Never> {
        if let running = pendingCompileTask { return running }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.handOverPendingProviders()
            self.pendingCompileTask = nil
        }
        pendingCompileTask = task
        return task
    }

    private func handOverPendingProviders() async {
        pendingCompileDue = nil
        lastPendingCompile = clock()
        guard state.isConnected, let container else { return }
         
         
        readProviderRefresh()
        guard let running = state.providerRefresh?.running?.configSHA256 else { return }
        guard let published = await Task.detached(operation: {
            ClashTVPendingSeeds.runningConfiguration(container: container, sha256: running)
        }).value else {
             
             
            ClashLogStore.shared.append("tv pending compile: the tunnel runs no configuration the store keeps  sha256=\(running)",
                                       stream: .app, level: .warning)
            return
        }
        let generation = ipcGeneration
        let prepare = preparePendingSeeds
        let entries: [ClashTVPendingSeeds.Entry]
        do {
            let answer = try await Task.detached { try prepare(container, published) }.value
            entries = try ClashTVPendingSeeds.decode(answer)
        } catch {
            ClashLogStore.shared.append("tv pending compile: \(error.localizedDescription)", stream: .app, level: .warning)
            return
        }
        guard !entries.isEmpty else { return }
        var handing = entries[...]
        while let entry = handing.popFirst() {
            let key = ProviderRefreshState.key(kind: entry.kind, name: entry.name)
            guard let handOver = entry.handOver else {
                 
                 
                state.pendingCompileFailures[key] = entry.error ?? ""
                ClashLogStore.shared.append("tv pending compile  name=\(key) reason=\(entry.error ?? "")",
                                           stream: .app, level: .warning)
                continue
            }
             
             
            defer { try? FileManager.default.removeItem(atPath: handOver.path) }
            do {
                let reply = try await send(["cmd": "seedProviderFile", "kind": entry.kind, "name": entry.name,
                                            "payloadPath": handOver.path, "seed": handOver.seed,
                                            "expectedConfigSHA256": handOver.expected,
                                            "timeoutMilliseconds": Self.providerCheckMilliseconds],
                                           timeout: Self.seedTimeout, expectedGeneration: generation)
                state.pendingCompileFailures[key] = Self.seedFailure(reply)
            } catch {
                 
                 
                ClashLogStore.shared.append("tv pending seed  name=\(key) reason=\(error.localizedDescription)",
                                           stream: .app, level: .warning)
                for rest in handing {
                    if let path = rest.handOver?.path { try? FileManager.default.removeItem(atPath: path) }
                }
                break
            }
        }
        readProviderRefresh()
        state.ruleProvidersLoaded = ClashTVProvidersScreen.readyCount(state.providers, tunnel: state.providerRefresh,
                                                                        running: state.isConnected)
    }

     
     
     
     
    static func seedFailure(_ reply: Data) -> String? {
        let object = (try? JSONSerialization.jsonObject(with: reply)) as? [String: Any]
        if let english = object?["error"] as? String {
             
             
             
            guard ProviderUpdateRefusal(english) == nil, !english.contains(ClashSideUpdateStalePrefix) else { return nil }
            return object.flatMap(ClashTVKernelSnapshots.refusal(in:))?.text ?? english
        }
        let answer = ProviderUpdateAnswer.decode(String(decoding: reply, as: UTF8.self))
        return answer?.result == .failed ? (answer?.error ?? "") : nil
    }
     
     
     
     
     
    private var checksAfterRestart: (title: String, start: Int)?

     
     
     
     
    private func updateFailed(_ subscription: ClashTVSubscription, reason: String, announces: Bool) {
        let result = ClashTVFeedback.couldNotUpdate(subscription.title, reason: reason)
        if announces {
            state.post(result, for: .update(subscription.id))
        } else {
            state.note(problem: ClashTVFeedback.spoken(result), aboutProfile: true)
        }
    }

     
     
     
     
     
     
     
     
     
     
     
    @discardableResult
    func reloadOrRestart(_ subscription: ClashTVSubscription, expectedGeneration: ClashTVIPCGeneration? = nil) async throws -> String? {
        let generation = expectedGeneration ?? ipcGeneration
        controlRevision &+= 1
        state.observations.waitForUpdate()
         
         
         
        let controllerChangeSent = state.remoteControlPendingGeneration
        let reply = try await send(["cmd": "reload"], timeout: Self.reloadTimeout, expectedGeneration: generation)
        guard generation === ipcGeneration, generation.isValid else { throw ControllerError.ipcReplySuperseded }
        if Self.isOK(reply) {
            let warning = Self.committedWarning(reply)
            if let warning {
                ClashLogStore.shared.append("tv reload applied with a warning  reason=\(warning)", stream: .app, level: .warning)
                 
                 
                state.note(problem: String(localized: "The profile was applied, with a warning: \(warning)"))
            } else {
                ClashLogStore.shared.append("tv reload applied", stream: .app)
            }
             
             
            if controllerChangeSent != nil, state.remoteControlPendingGeneration == controllerChangeSent {
                state.remoteControlPendingGeneration = nil
            }
            await refreshProxyDelays(forceDocument: true)
            await refreshStatus()
            return warning
        }
         
         
        guard case ControllerError.kernelRefused(let reason) = Self.replyError(reply) else { throw ControllerError.invalidResponse }
        if Self.errorClass(reply) == "config" {
            ClashLogStore.shared.append("tv reload refused; the running configuration stands  reason=\(reason)", stream: .app, level: .warning)
            await refreshStatus()
            throw ControllerError.kernelRefused(reason)
        }
        ClashLogStore.shared.append("tv reload refused; restarting the tunnel  reason=\(reason)", stream: .app, level: .warning)
         
         
        let epoch = stopEpoch + 1
        await disconnect()
        guard stopEpoch == epoch else { throw CancellationError() }
        try await waitUntilDown()
         
         
        guard stopEpoch == epoch else { throw CancellationError() }
         
         
         
        statusChanged()
         
         
        stopRequested = false
        do {
            try await start()
        } catch {
             
             
            if !(error is CancellationError) { report(issue: error.localizedDescription, aboutProfile: Self.isAboutProfile(error)) }
            throw error
        }
        return nil
    }

     
     
     
    func disconnect() async {
        replaceIPCGeneration(active: false)
        startRequested = false
        startFailureTracker.cancelStart()
        state.vpnAuthorization = nil
        startGeneration += 1
        stopRequested = true
        stopEpoch += 1
        let disarm = coordinator.requestStop { $0.stopVPNTunnel() }
        if let connectTask {
            connectTask.cancel()
            await connectTask.value
             
             
             
             
             
            if self.connectTask == connectTask { self.connectTask = nil }
        }
         
         
        await disarm.value
        statusChanged()
    }

     
     
     
     
     
    func reinstallVPNProfile() async {
        guard connectTask == nil, refreshTask == nil, !isApplyingIPStack, !reinstallInFlight,
              !state.isConnected, state.stage != .connecting else { return }
        reinstallInFlight = true
        defer { reinstallInFlight = false }
        startFailureTracker.cancelStart()
        state.issue = nil
        state.vpnAuthorization = nil
        let epoch = stopEpoch
        do {
            let ipStack = try IPStackSettings.load(from: ipStackDefaults)
            try await coordinator.commitStart(
                replacingInstalled: true,
                configure: { try Self.configure($0, ipStack: ipStack) },
                shouldAbort: { [weak self] in
                    guard let self else { return true }
                    return self.stopEpoch != epoch
                },
                onWaiting: { [weak self] in
                    guard let self, self.stopEpoch == epoch else { return }
                    self.state.vpnAuthorization = .waiting
                }
            )
            state.vpnAuthorization = nil
             
             
            startFailureTracker.forgetInstantFailures()
            ClashLogStore.shared.append("tv vpn profile reinstalled", stream: .app)
        } catch ClashTVProfileCoordinator.StartError.permissionNotGranted {
             
             
            state.vpnAuthorization = .notCompleted
        } catch is CancellationError {
            state.vpnAuthorization = nil
            ClashLogStore.shared.append("tv vpn profile reinstall cancelled", stream: .app)
        } catch {
            state.vpnAuthorization = nil
            report(issue: error.localizedDescription)
            state.post(ClashTVFeedback.couldNotReinstall(reason: error.localizedDescription), for: .reinstall, remembers: false)
            ClashLogStore.shared.append("tv vpn profile reinstall failed  reason=\(error.localizedDescription)", stream: .app, level: .warning)
        }
        statusChanged()
    }

     
     
     
    var isStarting: Bool { connectTask != nil || state.stage == .connecting }

     
     
    @discardableResult
    func applyIPStack(_ next: IPStackSettings) async throws -> Bool {
        guard !isApplyingIPStack, connectTask == nil, refreshTask == nil,
              state.stage != .connecting, state.stage != .disconnecting else {
            throw IPStackSettingsApplicationError.operationInProgress
        }
        guard try next != IPStackSettings.load(from: ipStackDefaults) else { return false }
        isApplyingIPStack = true
        defer { isApplyingIPStack = false }
        let epoch = stopEpoch
        try await coordinator.applyIPStack(next, defaults: ipStackDefaults)
        guard stopEpoch == epoch, manager?.status == .connected || manager?.status == .reasserting else { return false }
        do {
            state.issue = nil
            startRequested = false
            stopRequested = true
            replaceIPCGeneration(active: false)
            await coordinator.stop { $0.stopVPNTunnel() }
            try await waitUntilDown()
            guard stopEpoch == epoch else { throw CancellationError() }
             
            statusChanged()
            stopRequested = false
        } catch {
             
             
             
            if error is CancellationError || stopEpoch != epoch { throw CancellationError() }
            throw ControllerError.ipStackStopUnanswered(error.localizedDescription)
        }
        do {
            try await start(settings: next)
            return true
        } catch {
            if error is CancellationError || stopEpoch != epoch { throw CancellationError() }
             
             
            report(issue: error.localizedDescription)
            throw ControllerError.ipStackRestartFailed(error.localizedDescription)
        }
    }

     
     
     
     
     
     
     
    func setAutoConnect(_ wanted: Bool) async {
        state.beginOperation()
        await coordinator.setWanted(wanted) { [weak self] outcome, wish in
            guard let self else { return }
             
             
            switch outcome {
            case .saved, .noProfile:
                self.state.autoConnect = wish
                self.state.autoConnectIssue = nil
            case .indeterminate(let error):
                 
                 
                 
                self.state.autoConnect = wish
                self.state.autoConnectIssue = Self.saveIndeterminate(error)
                self.state.post(ClashTVFeedback.autoConnectUnconfirmed(reason: Self.saveIndeterminate(error)), for: .autoConnect)
            case .refused(let error):
                 
                self.state.autoConnect = self.autoConnect.isEnabled
                self.state.autoConnectIssue = Self.saveRefused(error)
                self.state.post(ClashTVFeedback.autoConnectNotSaved(reason: Self.saveRefused(error)), for: .autoConnect)
            case .loadFailed(let error):
                 
                self.state.autoConnect = self.autoConnect.isEnabled
                self.state.autoConnectIssue = Self.saveRefused(error)
                self.state.post(ClashTVFeedback.autoConnectNotSaved(reason: Self.saveRefused(error)), for: .autoConnect)
            case .superseded:
                 
                 
                break
            }
        }
    }

     
     
     
     
    func subscriptionChanged(to subscription: ClashTVSubscription) async {
        preparedSubscription = subscription
        let busy = connectTask != nil || state.isConnected || state.stage == .connecting
        guard busy else {
            showConfiguration(for: subscription)
            return
        }
        await disconnect()
        let epoch = stopEpoch
        do {
            try await waitUntilDown()
        } catch {
             
             
             
            state.post(ClashTVFeedback.couldNotSwitchProfile(to: subscription.title, reason: error.localizedDescription),
                       for: .use)
            return
        }
         
         
        guard stopEpoch == epoch else {
            showConfiguration(for: subscription)
            return
        }
        await connect(subscription: subscription)
    }



     

     
     
     
     
     
    func sendProxyShare(_ message: [String: Any]) async throws -> Data {
        try await send(message)
    }

     
     
     
     
     
    func remoteControlStatus() async -> ClashTVTunnelAnswer {
         
         
         
        var waited = 0
        while isStarting, waited < 60, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 500_000_000)
            waited += 1
        }
        guard state.isConnected else { return .notRunning }
        do {
            return .status(String(decoding: ClashTVKernelSnapshots.readerFacing(try await send(["cmd": "remoteControl"])),
                                  as: UTF8.self))
        } catch {
            return .unanswered(error.localizedDescription)
        }
    }

    func setMode(_ mode: ClashTVOutboundMode) async {
        state.beginOperation()
        guard state.isConnected else {
            state.outboundMode = mode
            state.observations.mode.selectLocally()
            return
        }
        let generation = ipcGeneration
        controlRevision &+= 1
        let revision = controlRevision
        do {
            state.observations.mode.waitForUpdate()
            modeSendsInFlight += 1
            defer { modeSendsInFlight -= 1 }
            let reply = try await send(["cmd": "setMode", "mode": mode.kernelToken], expectedGeneration: generation)
            guard generation.isValid, revision == controlRevision else { return }
            guard Self.isOK(reply) else { throw Self.replyError(reply) }
            state.outboundMode = mode
            if state.observations.proxies.hasRuntimeSample { showRoute() }
            state.observations.mode.acknowledgeOperation(at: observationClock().date)
        } catch {
            ClashLogStore.shared.append("tv setMode outcome  reason=\(error.localizedDescription)", stream: .app, level: .warning)
            guard generation.isValid, revision == controlRevision else { return }
             
             
             
             
             
             
             
            if case ControllerError.kernelRefused = error {
                state.post(ClashTVFeedback.modeRefused, for: .mode)
            } else {
                state.post(ClashTVFeedback.couldNotChangeMode(reason: error.localizedDescription), for: .mode)
            }
        }
    }

     
     
    enum ModeRequestOutcome: Equatable {
         
         
        case switched
         
         
        case ask(ClashTunnelOutboundMode.GlobalExit)
         
         
         
        case refused(String)
         
         
        case notConfirmed
         
         
        case superseded
         
         
        case unchanged
    }

     
     
     
     
     
    func requestMode(_ mode: ClashTVOutboundMode) async -> ModeRequestOutcome {
         
         
        modeRequestRevision &+= 1
        let revision = modeRequestRevision
        askedGlobal = nil
        guard mode == .global, state.isConnected else {
            await setMode(mode)
            return .switched
        }
         
         
         
        if state.outboundMode == .global, state.observations.mode.hasValue, modeSendsInFlight == 0 {
            state.settle(.mode)
            return .unchanged
        }
        state.beginOperation()
        let generation = ipcGeneration
        var step = ClashTunnelOutboundMode.GlobalSwitchStep.notKnown
        do {
            let reply = try await send(["cmd": "proxiesSummary"], expectedGeneration: generation)
             
             
             
             
             
            step = await ClashTunnelOutboundMode.readGlobalStep(
                summaryJSON: String(decoding: reply, as: UTF8.self),
                members: { [self] group in
                    (try? await send(["cmd": "groupMembers", "group": group, "offset": 0,
                                      "limit": ClashTunnelOutboundMode.membersRead],
                                     expectedGeneration: generation)).map { String(decoding: $0, as: UTF8.self) }
                },
                isCurrent: { [self] in generation.isValid && revision == modeRequestRevision }
            ) ?? .notKnown
        } catch {
            ClashLogStore.shared.append("tv setMode global  check=unread reason=\(error.localizedDescription)", stream: .app, level: .warning)
        }
         
        guard revision == modeRequestRevision else { return .superseded }
         
         
         
        guard generation.isValid else {
            ClashLogStore.shared.append("tv setMode global  check=unconfirmed reason=tunnel changed", stream: .app, level: .warning)
            state.post(ClashTVFeedback.globalNotConfirmed, for: .mode)
            return .notConfirmed
        }
        switch step {
        case .switchNow:
            await setMode(.global)
            return .switched
        case .ask(let exit):
            ClashLogStore.shared.append("tv setMode global  check=\(exit.rawValue) asked", stream: .app, level: .info)
            askedGlobal = (revision, generation, currentProfileID)
            return .ask(exit)
        case .refuse(let key):
            ClashLogStore.shared.append("tv setMode global  check=refused reason=\(key)", stream: .app, level: .info)
            state.post(ClashTVFeedback.globalRefused(key), for: .mode)
            return .refused(key)
        case .notKnown:
            ClashLogStore.shared.append("tv setMode global  check=unconfirmed", stream: .app, level: .warning)
            state.post(ClashTVFeedback.globalNotConfirmed, for: .mode)
            return .notConfirmed
        }
    }

     
     
    struct GlobalQuestionTicket {
        fileprivate let revision: UInt64
        fileprivate let generation: ClashTVIPCGeneration
        fileprivate let profile: ClashTVSubscription.ID?
    }

    func globalQuestionTicket() -> GlobalQuestionTicket? {
        askedGlobal.map { GlobalQuestionTicket(revision: $0.revision, generation: $0.generation, profile: $0.profile) }
    }

     
     
     
     
     
    @discardableResult
    func switchGlobalAnyway(_ ticket: GlobalQuestionTicket?) async -> Bool {
        askedGlobal = nil
        guard let asked = ticket else {
             
             
            ClashLogStore.shared.append("tv setMode global  anyway=no-question", stream: .app, level: .info)
            return false
        }
        guard asked.revision == modeRequestRevision, asked.generation.isValid,
              asked.generation === ipcGeneration, asked.profile == currentProfileID else {
            ClashLogStore.shared.append("tv setMode global  anyway=stale", stream: .app, level: .info)
            state.post(ClashTVFeedback.globalNotConfirmed, for: .mode)
            return false
        }
        await setMode(.global)
        return true
    }

     
     
    func dropGlobalQuestion() { askedGlobal = nil }

     
     
     
    @discardableResult
    func readGroupsUntilListed(_ name: String) async -> Bool {
         
         
         
         
        for attempt in 0..<Self.groupReadAttempts {
            if groupIsRead(name) { return true }
            if attempt > 0 { try? await Task.sleep(for: .seconds(1)) }
             
            guard !Task.isCancelled else { return false }
            if await refreshProxies() != nil, !groupIsRead(name) {
                 
                return false
            }
        }
        return groupIsRead(name)
    }

    private func groupIsRead(_ name: String) -> Bool {
        state.proxyGroups.contains { $0.name == name } || state.hiddenProxyGroups.contains { $0.name == name }
    }

    static let groupReadAttempts = 3

     
    private var currentProfileID: ClashTVSubscription.ID? {
        (preparedSubscription ?? connectedSubscription)?.id
    }


    func pin(member: String, group: String) async {
        state.beginOperation()
        guard state.isConnected else {
            state.pin(member: member, in: group)
            return
        }
        let generation = ipcGeneration
        controlRevision &+= 1
        let revision = controlRevision
        let epoch = presentationEpoch
        do {
            state.observations.proxies.waitForUpdate()
            let reply = try await send(["cmd": "select", "group": group, "name": member], expectedGeneration: generation)
            guard generation.isValid, revision == controlRevision else { return }
            guard Self.isOK(reply) else { throw Self.replyError(reply) }
             
            if presentation.active && presentationEpoch == epoch {
                await refreshProxyDelays(forceDocument: true)
            }
        } catch {
            ClashLogStore.shared.append("tv pin outcome  reason=\(error.localizedDescription)", stream: .app, level: .warning)
            guard generation.isValid, revision == controlRevision else { return }
             
             
            if await landedAfterLostReply(error, group: group, generation: generation, revision: revision, epoch: epoch,
                                          landed: { $0["now"] as? String == member || $0["fixed"] as? String == member }) {
                ClashLogStore.shared.append(#"tv pin outcome  reply lost, read-back shows the member in use"#, stream: .app)
                if presentation.active && presentationEpoch == epoch {
                    await refreshProxyDelays(forceDocument: true)
                }
                return
            }
            guard generation.isValid, revision == controlRevision else { return }
            state.post(ClashTVFeedback.couldNotUse(member, reason: error.localizedDescription), for: .pin)
        }
    }

     
     
     
     
    func unpin(group: String) async {
        state.beginOperation()
        guard state.isConnected else {
            state.unpin(group: group)
            return
        }
        let generation = ipcGeneration
        controlRevision &+= 1
        let revision = controlRevision
        let epoch = presentationEpoch
        do {
            state.observations.proxies.waitForUpdate()
            let reply = try await send(["cmd": "unfix", "group": group], expectedGeneration: generation)
            guard generation.isValid, revision == controlRevision else { return }
            guard Self.isOK(reply) else { throw Self.replyError(reply) }
            if presentation.active && presentationEpoch == epoch {
                await refreshProxyDelays(forceDocument: true)
            }
        } catch {
            ClashLogStore.shared.append("tv unpin outcome  reason=\(error.localizedDescription)", stream: .app, level: .warning)
            guard generation.isValid, revision == controlRevision else { return }
             
             
            if await landedAfterLostReply(error, group: group, generation: generation, revision: revision, epoch: epoch,
                                          landed: { $0["fixed"] as? String == "" }) {
                ClashLogStore.shared.append(#"tv unpin outcome  reply lost, read-back shows the pin released"#, stream: .app)
                if presentation.active && presentationEpoch == epoch {
                    await refreshProxyDelays(forceDocument: true)
                }
                return
            }
            guard generation.isValid, revision == controlRevision else { return }
            state.post(ClashTVFeedback.couldNotUnfix(group, reason: error.localizedDescription), for: .unpin)
        }
    }

     
     
     
     
     
     
     
    private func landedAfterLostReply(_ error: Error, group: String, generation: ClashTVIPCGeneration,
                                      revision: UInt64, epoch: UInt64,
                                      landed: ([String: Any]) -> Bool) async -> Bool {
        guard case ControllerError.ipcResultUnknown = error else { return false }
        let deadline = ContinuousClock.now + Self.lostReplyReadBackWindow
        while presentation.active, presentationEpoch == epoch, generation.isValid, revision == controlRevision,
              !Task.isCancelled {
            do {
                 
                 
                let reply = try await send(["cmd": "proxyDelaysPage", "since": Int64.max, "after": "", "limit": 1],
                                           expectedGeneration: generation)
                guard revision == controlRevision,
                      let root = try? JSONSerialization.jsonObject(with: reply) as? [String: Any],
                      let entry = (root["groups"] as? [String: Any])?[group] as? [String: Any] else { return false }
                return landed(entry)
            } catch ControllerError.ipcNotSent(.unresolved) where ContinuousClock.now < deadline {
                try? await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                return false
            }
        }
        return false
    }

     
    static let lostReplyReadBackWindow: Duration = .seconds(16)

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func testAll(group shown: ClashProxyGroupSnapshot) async {
        var group = shown
         
         
         
         
         
         
        ClashLogStore.shared.append(
            "url test sweep requested  group=\(group.name) members=\(group.members.count) "
                + "connected=\(state.isConnected) stage=\(state.stage) busy=\(!sweepingMembers.isEmpty)",
            stream: .app
        )
        guard state.isConnected else {
             
             
            state.beginOperation()
            state.post(isStarting ? ClashTVFeedback.busy(.connecting) : ClashTVFeedback.connectToTest, for: .test)
            return
        }
        state.beginOperation()
         
         
        guard sweepingMembers.isEmpty, !sweepReserved else { return }
        let generation = ipcGeneration
         
         
        sweepEnded = false
         
         
        if !group.hasEveryMember, let total = lastSummary?.groups[group.name]?.total {
             
             
             
            guard !sweepReserved else { return }
            sweepReserved = true
            defer { sweepReserved = false }
            while memberLoads.contains(group.name) {
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                guard generation.isValid else { return }
            }
            memberLoads.insert(group.name)
            defer { memberLoads.remove(group.name) }
            do {
                try await readMembers(of: group.name, upTo: total, cancellableRead: false)
            } catch {
                guard generation.isValid else { return }
                state.post(ClashTVFeedback.testStopped(reason: error.localizedDescription), for: .test)
                return
            }
            guard generation.isValid, sweepingMembers.isEmpty, !sweepEnded, let latest = lastSummary else { return }
            showNodes(latest)
            group = ClashTVNodesScreen.group(named: group.name, state: state) ?? group
            if !group.hasEveryMember {
                ClashLogStore.shared.append("url test sweep: the list moved while it was read  group=\(group.name) "
                    + "read=\(group.members.count) of \(group.memberCount)", stream: .app, level: .warning)
            }
        }
         
         
         
         
         
         
        let probes = ClashTVNodesScreen.sweepProbes(of: group, state: state)
        let keys = Set(probes.flatMap { [$0.name, $0.key] })
        let previousLatency = keys.reduce(into: [String: ClashProxyLatencyState]()) {
            $0[$1] = state.latency[$1]
        }
        sweepingMembers = keys
        defer {
            if generation === ipcGeneration {
                 
                 
                for key in keys where state.latency[key] == .testing {
                    state.latency[key] = previousLatency[key]
                        ?? (ClashTVKernelSnapshots.urlRecord(of: key) == nil ? .untested : nil)
                }
                sweepingMembers = []
            }
        }
        ClashTVNodesScreen.beginTesting(group, state: &state)
         
         
         
         
         
         
         
         
         
        var measured = 0
        var inHand: ClashTVNodesScreen.Probe?
        do {
            let width = LatencyProbePolicy.tvOS.concurrentProbeCount(for: probes.count)
            var rest = probes[...]
            while !rest.isEmpty {
                 
                try Task.checkCancellation()
                guard !sweepEnded else { return }
                let batch = Self.sweepBatch(of: rest)
                rest = rest.dropFirst(batch.count)
                switch try await sweepInTunnel(batch, width: width, generation: generation) {
                case .measured(let count):
                    measured += count
                case .ended:
                    return
                case .unknownToTunnel:
                     
                     
                     
                    ClashLogStore.shared.append("url test sweep: the tunnel predates the sweep; one node at a time",
                                                stream: .app)
                    for probe in batch + rest {
                        guard generation.isValid, !sweepEnded else { return }
                        try Task.checkCancellation()
                        inHand = probe
                        let reply = try await send(Self.urlTestRequest(probe), expectedGeneration: generation)
                        guard generation.isValid else { return }
                        inHand = nil
                        let delay = (try? ClashTVKernelSnapshots.urlTestDelay(from: reply)) ?? -1
                        if delay > 0 { measured += 1 }
                        ClashTVNodesScreen.record(delay: delay, for: probe, state: &state)
                        noteMeasured(probe)
                    }
                    rest = []
                }
            }
        } catch {
            ClashLogStore.shared.append("tv url test sweep ended  reason=\(error.localizedDescription)", stream: .app, level: .warning)
             
             
            if error is CancellationError { return }
            guard generation.isValid else { return }
            if let probe = inHand {
                state.latency[probe.name] = .failed
                state.latency[probe.key] = .failed
                noteMeasured(probe)
            }
            state.post(ClashTVFeedback.testStopped(reason: error.localizedDescription), for: .test)
            return
        }
        ClashLogStore.shared.append(
            "url test sweep done  group=\(group.name) measured=\(measured) of \(probes.count)",
            stream: .app
        )
    }

     
     
     
     
    static let sweepBatchProbes = 500
    static let sweepBatchBytes = 64 * 1024

     
    static func sweepBatch(of rest: ArraySlice<ClashTVNodesScreen.Probe>) -> [ClashTVNodesScreen.Probe] {
        var bytes = 0
        var batch: [ClashTVNodesScreen.Probe] = []
        for probe in rest.prefix(sweepBatchProbes) {
             
            let cost = 32 + 2 * (probe.name.utf8.count + (probe.url?.utf8.count ?? 0))
            if !batch.isEmpty, bytes + cost > sweepBatchBytes { break }
            bytes += cost
            batch.append(probe)
        }
        return batch
    }
     
    static let sweepReadInterval: Duration = .milliseconds(300)

    private enum TunnelSweep {
        case measured(Int)
         
        case ended
         
        case unknownToTunnel
    }

     
     
    private func sweepInTunnel(_ batch: [ClashTVNodesScreen.Probe], width: Int,
                               generation: ClashTVIPCGeneration) async throws -> TunnelSweep {
        let request: [String: Any] = [
            "cmd": "urltestSweep",
            "probes": batch.map { probe -> [String: Any] in
                var entry: [String: Any] = ["name": probe.name]
                if let url = probe.url { entry["url"] = url }
                return entry
            },
            "width": width,
            "failureFloorMilliseconds": LatencyProbePolicy.tvOS.probeFailureFloorNanoseconds / 1_000_000,
        ]
        let started = try await send(request, expectedGeneration: generation)
        guard generation.isValid else { return .ended }
        let root = try? JSONSerialization.jsonObject(with: started) as? [String: Any]
        guard let id = (root?["sweep"] as? NSNumber)?.uint64Value else {
            if (root?["error"] as? String)?.hasPrefix("unknown cmd") == true { return .unknownToTunnel }
            throw Self.replyError(started)
        }
        tunnelSweep = (id, generation)
         
         
         
         
         
        defer { if tunnelSweep?.id == id { tunnelSweep = nil } }
        do {
            let outcome = try await readTunnelSweep(id, batch, generation: generation)
            await stopTunnelSweep(id)
            return outcome
        } catch {
            await stopTunnelSweep(id)
            throw error
        }
    }

     
     
     
    private var tunnelSweep: (id: UInt64, generation: ClashTVIPCGeneration)?

     
     
     
     
     
     
     
     
    private func stopTunnelSweep(_ id: UInt64) async {
        guard let running = tunnelSweep, running.id == id, running.generation.isValid else { return }
        do {
            _ = try await send(["cmd": "urltestSweepStop", "sweep": id], expectedGeneration: running.generation)
            if tunnelSweep?.id == id { tunnelSweep = nil }
        } catch {
            ClashLogStore.shared.append("url test sweep: the stop did not go  reason=\(error.localizedDescription)",
                                        stream: .app, level: .warning)
        }
    }

     
     
     
    private func readTunnelSweep(_ id: UInt64, _ batch: [ClashTVNodesScreen.Probe],
                                 generation: ClashTVIPCGeneration) async throws -> TunnelSweep {
        var landed = Set<Int>()
        var measured = 0
        while true {
            if sweepEnded { return .ended }
            let reply: Data
            do {
                reply = try await readSweep(id, generation: generation)
            } catch _ where sweepEnded {
                 
                 
                return .ended
            }
            guard generation.isValid else { return .ended }
            let reading = try? JSONSerialization.jsonObject(with: reply) as? [String: Any]
            guard let delays = reading?["delays"] as? [Any], let done = reading?["done"] as? Bool else {
                throw Self.replyError(reply)
            }
            if done, tunnelSweep?.id == id { tunnelSweep = nil }
            for (index, value) in zip(batch.indices, delays) where !landed.contains(index) {
                guard let delay = (value as? NSNumber)?.intValue else { continue }
                landed.insert(index)
                if delay > 0 { measured += 1 }
                ClashTVNodesScreen.record(delay: delay, for: batch[index], state: &state)
                noteMeasured(batch[index])
            }
            if reading?["stopped"] as? Bool == true {
                 
                 
                 
                ClashLogStore.shared.append("url test sweep: the tunnel ended it  landed=\(landed.count) of \(batch.count)",
                                            stream: .app, level: .warning)
                return .ended
            }
            if done { return .measured(measured) }
            try await Task.sleep(for: Self.sweepReadInterval)
            guard generation.isValid else { return .ended }
        }
    }

     
     
     
     
    private func readSweep(_ id: UInt64, generation: ClashTVIPCGeneration) async throws -> Data {
        let deadline = ContinuousClock.now + Self.lostReplyReadBackWindow
        while true {
            do {
                return try await send(["cmd": "urltestSweepRead", "sweep": id], expectedGeneration: generation)
            } catch ControllerError.ipcNotSent(.unresolved) where ContinuousClock.now < deadline && !sweepEnded {
                try await Task.sleep(for: .milliseconds(250))
            }
        }
    }

     
     
     
     
     
     
    func endSweep() async {
        guard !sweepingMembers.isEmpty || sweepReserved else { return }
        sweepEnded = true
        if let running = tunnelSweep { await stopTunnelSweep(running.id) }
    }

     
    private var sweepEnded = false

     
     
     
     
     
    func testOne(member: ClashProxyMemberSnapshot, in group: ClashProxyGroupSnapshot? = nil) async {
         
         
         
        guard state.isConnected else {
            state.beginOperation()
            state.post(isStarting ? ClashTVFeedback.busy(.connecting) : ClashTVFeedback.connectToTest, for: .test)
            return
        }
        state.beginOperation()
        guard let probe = ClashTVNodesScreen.probe(for: member, in: group, state: state),
              !sweepingMembers.contains(probe.name), !sweepingMembers.contains(probe.key)
        else { return }
        let name = probe.name
        let generation = ipcGeneration
        let keys: Set<String> = [probe.name, probe.key]
        sweepingMembers.formUnion(keys)
        defer { if generation === ipcGeneration { sweepingMembers.subtract(keys) } }
        for key in keys { state.latency[key] = .testing }
        do {
            let reply = try await send(Self.urlTestRequest(probe), expectedGeneration: generation)
            guard generation.isValid else { return }
            let delay = (try? ClashTVKernelSnapshots.urlTestDelay(from: reply)) ?? -1
            ClashTVNodesScreen.record(delay: delay, for: probe, state: &state)
            noteMeasured(probe)
            ClashLogStore.shared.append("url test one  node=\(name) member=\(member.name) delay=\(delay)", stream: .app)
        } catch {
            ClashLogStore.shared.append("tv url test ended  reason=\(error.localizedDescription)", stream: .app, level: .warning)
            guard generation.isValid else { return }
            for key in keys { state.latency[key] = .failed }
            noteMeasured(probe)
            state.post(ClashTVFeedback.testStopped(reason: error.localizedDescription), for: .test)
        }
    }

     
     
     
     
     
     
    private var sweepingMembers: Set<String> = []

     

     
     
    var iCloudRestore: ClashTVICloudRestore? {
        get { injectedICloudRestore ?? container.map { ClashTVICloudRestore(container: $0) } }
        set { injectedICloudRestore = newValue }
    }
    private var injectedICloudRestore: ClashTVICloudRestore?

     
     
     
     
    func refreshRestoredProfilesIfNewer(store: ClashTVSubscriptionStore) async -> ClashTVSubscriptionStore? {
        guard let service = iCloudRestore, !store.followingAutoBackup.isEmpty else { return nil }
        var working = store
        let result: Result<ClashTVSubscriptionStore?, Error>
        do {
            let changed = try await service.refreshIfNewer(store: &working)
            result = .success(changed ? working : nil)
        } catch {
            result = .failure(error)
        }
        switch result {
        case .success(let refreshed):
            if refreshed != nil {
                ClashLogStore.shared.append("tv icloud refresh applied", stream: .app)
            }
            return refreshed
        case .failure(let error):
            ClashLogStore.shared.append("tv icloud refresh failed  reason=\(error.localizedDescription)", stream: .app, level: .warning)
            return nil
        }
    }

     
    func probeICloudForWelcome() async {
        guard let service = iCloudRestore else { return }
        let availability = await ClashTVICloudRestore.availability(locator: service.locator())
        state.iCloudRestoreLine = ClashTVICloudRestorePresentation.welcomeLine(availability)
    }

     
     
    func restoredDocumentIsNewerThanLastActivation(_ subscription: ClashTVSubscription) -> Bool {
        guard let at = subscription.restored?.exportedAt, let last = lastActivation,
              last.subscriptionID == subscription.id else { return false }
        return at > last.at
    }

     
    func noteActivated(_ subscription: ClashTVSubscription, at date: Date) {
        lastActivation = Activation(subscriptionID: subscription.id, at: date)
    }

     
     
     
     
    private func activeLibraryIsGone() async -> Bool {
        guard let container else { return false }
        return await Task.detached {
            guard let text = (try? ConfigResourceStore(containerURL: container).loadCurrent())?.text else { return false }
             
             
            let named = [ConfigTransforms.nodeLibraryPath(in: text), ConfigTransforms.ruleIndexPath(in: text)].compactMap { $0 }
            return named.contains { !FileManager.default.fileExists(atPath: $0) }
        }.value
    }

     
     
    private func activeRevisionLeftRuleSetsToTheTunnel() async -> Bool {
        guard let container else { return false }
        return await Task.detached {
            guard let store = try? ConfigResourceStore(containerURL: container),
                  let directory = try? store.activeProvidersDirectory() else { return false }
            return ClashTVProviderCatalog.read(from: directory)?.ruleSetsLeftToTheTunnel == true
        }.value
    }

     
     
     
     
     
    nonisolated static func isNodeLibraryUnavailable(_ error: Error) -> Bool {
        let error = error as NSError
        let words = [error.localizedDescription, error.localizedFailureReason ?? ""]
            + ((error.userInfo[NSUnderlyingErrorKey] as? NSError).map { [$0.localizedDescription] } ?? [])
        return words.contains { $0.contains(ClashNodeLibraryUnavailablePrefix) || $0.contains(ClashRuleIndexUnavailablePrefix) }
    }
     
    private var connectedSubscription: ClashTVSubscription?
     
    private var libraryRepublished = false

    private func needsActivation(for subscription: ClashTVSubscription) -> Bool {
        if restoredDocumentIsNewerThanLastActivation(subscription) { return true }
        guard let container, let store = try? ConfigResourceStore(containerURL: container),
              let pointer = try? store.activePointer()
        else { return true }
        return pointer.profileID != ClashTVConfigPipeline.profileID(for: subscription)
    }

     
     
     
    private func showConfiguration(for subscription: ClashTVSubscription?) {
        if let subscription, !needsActivation(for: subscription) {
            loadActiveConfigurationFacts()
        } else {
            clearConfigurationFacts()
        }
    }

    private func clearConfigurationFacts() {
        guard !state.isConnected else { return }
        controlRevision &+= 1
        state.observations.proxies = .init()
        state.observations.mode = .init()
        groupOrder = []
        state.rules = []
        forgetIndexedRules()
        state.ruleCount = 0
        state.dnsEnhancedMode = ""
        state.dnsNameservers = []
        state.dnsFallback = []
        state.dnsDefaultNameservers = []
        state.groupCount = 0
        state.ruleProvidersTotal = 0
        state.ruleProvidersLoaded = 0
        state.proxyGroups = []
        state.hiddenProxyGroups = []
        state.nodeCount = 0
        state.nodeGroup = ""
        state.nodeName = ""
    }

     
     
     
     
     
     
     
    @discardableResult
    private func activate(_ subscription: ClashTVSubscription, settings: IPStackSettings? = nil, report: @escaping @MainActor (ClashTVConfigPipeline.Phase) -> Void) async throws -> (panelName: String?, changed: Bool) {
        guard let container else { throw ControllerError.appGroupUnavailable }
        let pipeline = ClashTVConfigPipeline(container: container, session: session, settings: settings)
        let activation = try await pipeline.activate(subscription: subscription, tunnelRunning: state.isConnected) { phase in
            Task { @MainActor in report(phase) }
        }
        for warning in activation.warnings {
            ClashLogStore.shared.append("provider warning  \(warning)", stream: .app, level: .warning)
        }
        apply(facts: try ClashTVConfigFacts(yaml: activation.finalYAML), catalog: activation.catalog,
              ruleFacts: activation.ruleFacts, publishedPath: activation.publishedPath)
        return (activation.panelName, activation.changed)
    }

    private func noteActivation(_ subscription: ClashTVSubscription, panelName: String?) {
        lastActivation = Activation(subscriptionID: subscription.id, at: Date(), panelName: panelName)
    }

     
     
     
     
    private func loadActiveConfigurationFacts() {
        guard let active = activeConfigurationFacts() else { return }
        apply(facts: active.facts, catalog: active.catalog, fallbackCount: active.fallbackCount,
              ruleFacts: active.ruleFacts, publishedPath: active.publishedPath)
    }

     
    private func configurationFacts(of pointer: ActiveConfigurationPointer) -> (facts: ClashTVConfigFacts, catalog: ClashTVProviderCatalog, fallbackCount: Int, ruleFacts: ClashTVRuleFacts?, publishedPath: String?)? {
        guard let container, let store = try? ConfigResourceStore(containerURL: container),
              let stored = try? store.loadConfiguration(profileID: pointer.profileID, revision: pointer.revision),
              let yaml = stored.text, let facts = try? ClashTVConfigFacts(yaml: yaml) else { return nil }
        let directory = store.providersDirectory(profileID: pointer.profileID, revision: pointer.revision)
        let catalog = directory.flatMap { ClashTVProviderCatalog.read(from: $0) } ?? ClashTVProviderCatalog(entries: [])
        let files = directory.flatMap { try? FileManager.default.subpathsOfDirectory(atPath: $0.path) } ?? []
        return (facts, catalog, ClashTVProviderCatalog.providerFileCount(in: files), directory.flatMap { ClashTVRuleFacts.read(from: $0) },
                directory.map { ClashTVRuleFacts.publishedPath(providersDirectory: $0) })
    }

     
     
    private func activeConfigurationFacts() -> (facts: ClashTVConfigFacts, catalog: ClashTVProviderCatalog, fallbackCount: Int, ruleFacts: ClashTVRuleFacts?, publishedPath: String?)? {
        guard let container, let store = try? ConfigResourceStore(containerURL: container),
              let current = try? store.loadCurrent(), let yaml = current.text,
              let facts = try? ClashTVConfigFacts(yaml: yaml)
        else { return nil }
         
         
         
         
         
         
        let directory = try? store.activeProvidersDirectory()
        let catalog = directory.flatMap { ClashTVProviderCatalog.read(from: $0) }
        let files = directory
            .flatMap { try? FileManager.default.subpathsOfDirectory(atPath: $0.path) } ?? []
        return (facts, catalog ?? ClashTVProviderCatalog(entries: []), ClashTVProviderCatalog.providerFileCount(in: files),
                directory.flatMap { ClashTVRuleFacts.read(from: $0) },
                directory.map { ClashTVRuleFacts.publishedPath(providersDirectory: $0) })
    }

     
     
     
     
     
     
    private func report(issue: String, aboutProfile: Bool = false) {
        state.issue = issue
        state.note(problem: issue, aboutProfile: aboutProfile)
    }

     
     
    nonisolated static func isAboutProfile(_ error: Error) -> Bool {
        error is ClashTVSubscriptionFetcher.FetchError
    }

    private func apply(facts: ClashTVConfigFacts, catalog: ClashTVProviderCatalog, fallbackCount: Int? = nil,
                       ruleFacts: ClashTVRuleFacts? = nil, publishedPath: String? = nil) {
        controlRevision &+= 1
        state.observations.waitForUpdate()
        state.observations.mode.useConfiguration()
        groupOrder = facts.proxyGroupNames
        state.rules = facts.rules
         
         
         
         
        state.ruleCount = ruleFacts?.count ?? facts.ruleCount
        if facts.namesRuleIndex, let publishedPath {
            loadIndexedRules(publishedPath: publishedPath, counts: ruleFacts == nil)
        } else {
            forgetIndexedRules()
            closeRuleReader()
        }
        state.dnsEnhancedMode = facts.dnsEnhancedMode
        state.dnsNameservers = facts.dnsNameservers
        state.dnsFallback = facts.dnsFallback
        state.dnsDefaultNameservers = facts.dnsDefaultNameservers
        state.groupCount = facts.proxyGroupNames.count
        state.easyTierNodeNames = facts.easyTierNodeNames
        state.outboundMode = ClashTVOutboundMode(rawValue: facts.mode) ?? .rule
        state.geodataSource = "Bundled"
        state.providers = catalog.entries
        readProviderRefresh()
        let total = catalog.entries.isEmpty ? (fallbackCount ?? 0) : catalog.entries.count
        state.ruleProvidersTotal = total
        state.ruleProvidersLoaded = catalog.entries.isEmpty ? total
            : ClashTVProvidersScreen.readyCount(catalog.entries, tunnel: state.providerRefresh, running: state.isConnected)
         
         
         
         
         
        if !state.isConnected {
            state.observations.proxies.useConfiguration()
            state.proxyGroups = facts.proxyGroups
             
             
            state.hiddenProxyGroups = []
            state.nodeCount = facts.nodeCount
            if let first = facts.proxyGroups.first {
                state.nodeGroup = first.name
                state.nodeName = first.members.first?.name ?? ""
            }
             
             
             
             
            loadOfflineNodes()
        }
    }

     
     
     
     
    private func loadOfflineNodes() {
        guard let container else { return }
        let applied = controlRevision
        let wanted = Self.wholeGroupMembers
        offlineNodesTask?.cancel()
        offlineReads += 1
        offlineNodesTask = Task { @MainActor [weak self] in
            defer { self?.offlineReads -= 1 }
            let read = await Task.detached { () -> (String, OfflineNodes)? in
                 
                guard let published = (try? ConfigResourceStore(containerURL: container).loadCurrent())?.text else { return nil }
                do {
                    return (published, try Self.readCatalog(container: container, published: published,
                                                            wanted: { _, total in min(total, wanted) }))
                } catch {
                    ClashLogStore.shared.append("tv node catalog: \(error.localizedDescription)", stream: .app, level: .warning)
                    return nil
                }
            }.value
            guard let self, let (published, read) = read, !Task.isCancelled, !self.state.isConnected,
                  self.controlRevision == applied else { return }
            self.offlinePublished = published
            self.lastSummary = read.summary
            self.memberPages = read.members
            self.memberRevision = nil
            self.showNodes(read.summary, fromTunnel: false)
        }
    }
    private var offlineNodesTask: Task<Void, Never>?
    private var offlineReads = 0

     

     
     
    private let ruleReader = ClashTVPublishedRuleReader()
     
    private var indexedRulesPath: String?
     
    private var readingRulesPath: String?
    private var readingRules: Task<Void, Never>?
    private var rulesGeneration = 0
    private var ruleReads = 0
     
     
    private struct RuleLoad: Hashable {
        let generation: Int
        let category: ClashStructuredRule.Category
    }
    private var ruleLoads: Set<RuleLoad> = []
     
    var isReadingIndexedRules: Bool { ruleReads > 0 }
     
    static let firstRulePage = 100
    static let rulePageSize = 200

     
     
     
     
     
    private func loadIndexedRules(publishedPath path: String, counts: Bool) {
         
         
         
         
        if readingRulesPath == path { return }
        if indexedRulesPath == path, let rules = state.indexedRules {
            if counts { state.ruleCount = rules.total }
            return
        }
         
         
        forgetIndexedRules()
        let generation = rulesGeneration
        readingRulesPath = path
        state.indexedRulesRead = .reading
        ruleReads += 1
        readingRules = Task { @MainActor [weak self] in
            defer {
                if let self {
                    self.ruleReads -= 1
                    if self.rulesGeneration == generation { self.readingRulesPath = nil }
                }
            }
            guard let self else { return }
            do {
                let summary = try await self.ruleReader.summary(publishedPath: path)
                var rules = ClashTVIndexedRules(total: summary.total, byType: summary.byType)
                for category in ClashStructuredRule.Category.allCases where rules.count(in: category) > 0 {
                    try Task.checkCancellation()
                    rules.loaded[category] = try await self.ruleReader.page(
                        publishedPath: path, types: rules.types(in: category), offset: 0, limit: Self.firstRulePage)
                }
                guard self.rulesGeneration == generation else { return }
                self.indexedRulesPath = path
                self.state.indexedRules = rules
                self.state.indexedRulesRead = nil
                 
                 
                if counts { self.state.ruleCount = rules.total }
            } catch is CancellationError {
            } catch {
                ClashLogStore.shared.append("tv rule catalog: \(error.localizedDescription)", stream: .app, level: .warning)
                 
                guard self.rulesGeneration == generation else { return }
                self.state.indexedRulesRead = .unavailable
            }
        }
    }

     
     
    private func forgetIndexedRules() {
        readingRules?.cancel()
        readingRules = nil
        readingRulesPath = nil
        rulesGeneration &+= 1
        state.indexedRules = nil
        state.indexedRulesRead = nil
        indexedRulesPath = nil
    }

     
     
     
    private func closeRuleReader() {
        let generation = rulesGeneration
        Task { @MainActor [weak self] in
            guard let self, self.rulesGeneration == generation else { return }
            await self.ruleReader.close()
        }
    }

     
     
    func loadMoreRules(in category: ClashStructuredRule.Category) async {
        let generation = rulesGeneration
        let load = RuleLoad(generation: generation, category: category)
        guard ruleLoads.insert(load).inserted else { return }
        defer { ruleLoads.remove(load) }
        guard let path = indexedRulesPath, let rules = state.indexedRules, rules.hasMore(in: category) else { return }
        let offset = rules.loaded[category]?.count ?? 0
        do {
            let page = try await ruleReader.page(publishedPath: path, types: rules.types(in: category),
                                                 offset: offset, limit: Self.rulePageSize)
            guard rulesGeneration == generation, indexedRulesPath == path,
                  state.indexedRules?.loaded[category]?.count ?? 0 == offset else { return }
            state.indexedRules?.loaded[category, default: []] += page
        } catch {
            ClashLogStore.shared.append("tv rule catalog: \(error.localizedDescription)", stream: .app, level: .warning)
        }
    }
     
    var isReadingOfflineNodes: Bool { offlineReads > 0 }
     
     
    private var offlinePublished: String?

    private struct OfflineNodes: Sendable {
        let summary: ClashTVKernelSnapshots.Summary
        let members: [String: MemberPages]
    }

     
     
    nonisolated private static func readCatalog(container: URL, published: String,
                                                have: [String: MemberPages] = [:],
                                                wanted: (String, Int) -> Int) throws -> OfflineNodes {
        let catalog = try ClashTVNodeCatalog.open(container: container, publishedConfig: published)
        defer { catalog.close() }
        let summary = try ClashTVKernelSnapshots.summary(from: catalog.summary())
        var members = have
        for (name, group) in summary.groups {
            var pages = members[name] ?? MemberPages(total: group.total, members: [])
            let target = wanted(name, group.total)
            while pages.members.count < target {
                let page = try ClashTVKernelSnapshots.membersPage(from: catalog.members(
                    of: name, offset: pages.members.count, limit: min(memberPageSize, target - pages.members.count)))
                pages.total = page.total
                pages.members += page.members
                if page.members.isEmpty || pages.members.count >= page.total { break }
            }
            members[name] = pages
        }
        return OfflineNodes(summary: summary, members: members)
    }

     

    private func start(settings: IPStackSettings? = nil, userInitiated: Bool = false) async throws {
         
         
         
         
         
         
        let epoch = stopEpoch
        let ipStackSnapshot = try settings ?? IPStackSettings.load(from: ipStackDefaults)
        if let container {
            try AppCoreSetup.ensure(container: container, settings: ipStackSnapshot)
        }
        try await coordinator.commitStart(
            configure: { try Self.configure($0, ipStack: ipStackSnapshot) },
            shouldAbort: { [weak self] in
                guard let self else { return true }
                return self.stopEpoch != epoch
            },
            onWaiting: { [weak self] in
                guard let self, self.stopEpoch == epoch else { return }
                self.state.vpnAuthorization = .waiting
            }
        )
         
         
         
        if stopEpoch != epoch || Task.isCancelled { throw CancellationError() }
        guard let profile = coordinator.current else { throw ControllerError.tunnelDidNotStart }
        replaceIPCGeneration(active: false)
        state.vpnAuthorization = nil
        startRequested = true
        startGeneration += 1
         
         
        startFailureTracker.beginStart(at: clock())
        do {
            try profile.startVPNTunnel(userInitiated: userInitiated)
        } catch {
            startFailureTracker.cancelStart()
            throw error
        }
        ClashLogStore.shared.append("tv vpn start requested", stream: .app)
         
         
         
         
        state.stage = .connecting
    }

     
     
     
     
    private static func configure(_ profile: any ClashTVSystemProfile, ipStack: IPStackSettings) throws {
        let tunnelProtocol = (profile.protocolConfiguration?.copy() as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
        tunnelProtocol.providerBundleIdentifier = ClashAppIdentifiers.tvPacketTunnelExtensionBundleID
        tunnelProtocol.serverAddress = Self.vpnProfileDescription
        tunnelProtocol.providerConfiguration = try ipStack.applying(
            to: tunnelProtocol.providerConfiguration
        )
        profile.protocolConfiguration = tunnelProtocol
        profile.localizedDescription = Self.vpnProfileTitle
        profile.isEnabled = true
    }

    private static func owns(_ manager: any ClashTVSystemProfile) -> Bool {
        (manager.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier
            == ClashAppIdentifiers.tvPacketTunnelExtensionBundleID
    }

     
     
     
     
     
    static func dropMessage(for error: NSError, providerLooksUnlaunched: Bool) -> String {
        if error.domain == NEVPNConnectionErrorDomain, error.code == 12, providerLooksUnlaunched {
            return providerNotLaunchedMessage
        }
        return error.localizedDescription
    }


     
     
    static func saveRefused(_ error: Error) -> String {
        String(localized: "The system did not take the change — the switch is back where it was.") + " " + error.localizedDescription
    }

     
     
    static func saveIndeterminate(_ error: Error) -> String {
        String(localized: "The system has not answered yet — the change may still take. The switch shows what you asked for; the next Connect applies it again.") + " " + error.localizedDescription
    }

     
     
     
    private func waitUntilDown() async throws {
         
        for _ in 0..<100 where (manager?.status ?? .disconnected) != .disconnected {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard (manager?.status ?? .disconnected) == .disconnected else {
            throw ControllerError.systemTimedOut
        }
    }

     
     
     
    func statusChanged() {
        let status = manager?.status ?? .invalid
        if status == .disconnected || status == .invalid || status == .connecting {
             
             
            let ended = ContinuousClock.now
            Task { [ipcChannel] in await ipcChannel.tunnelEnded(at: ended) }
        }
         
         
        _ = startFailureTracker.statusDidChange(to: status, at: clock())
        let previous = lastKnownStatus
        let active = status == .connected || status == .reasserting
        let previouslyActive = previous == .connected || previous == .reasserting
        let profileID = manager.map { ObjectIdentifier($0) }
        let sessionID = manager?.vpnConnection.map { ObjectIdentifier($0) }
        let runtimeIdentityChanged = profileID != observedIPCProfile || sessionID != observedIPCSession
        if active != previouslyActive || runtimeIdentityChanged {
            replaceIPCGeneration(active: active)
            observedIPCProfile = profileID
            observedIPCSession = sessionID
        }
        if active {
             
            if activeObservationGeneration == nil || runtimeIdentityChanged {
                activeObservationGeneration = state.observations.generation
            }
        } else if status == .disconnected || status == .invalid, let ended = activeObservationGeneration {
            state.observations.lastEndedGeneration = ended
            activeObservationGeneration = nil
        }
        lastKnownStatus = status
        switch status {
        case .connected, .reasserting:
            if state.stage != .connected {
                state.stage = .connected
                 
                 
                 
                 
                let now = clock()
                state.connectedSince = min(manager?.connectedDate ?? now, now)
                state.issue = nil
                 
                 
                state.settle(.connect)
                startRequested = false
                 
                 
                repairedRefusal = nil
                pendingCompileDue = clock().addingTimeInterval(Self.pendingCompileAfterConnect)
                startPolling()
                if let pending = checksAfterRestart {
                    checksAfterRestart = nil
                    let title = pending.title
                    let generation = ipcGeneration
                     
                    guard pending.start == startGeneration else { break }
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let checks = await self.checkProviders(expectedGeneration: generation)
                        if let said = checks.failed.joined(separator: "\n").nilIfEmpty {
                            self.state.note(problem: ClashTVFeedback.spoken(ClashTVFeedback.updatedWithWarning(title, warning: said)))
                        }
                    }
                }
            }
        case .connecting:
            stopPolling()
            state.stage = .connecting
        case .disconnecting:
            stopPolling()
            state.stage = .disconnecting
             
             
            state.remoteControlPendingGeneration = nil
        case .disconnected, .invalid:
            let wasUp = state.stage == .connected || state.stage == .disconnecting
            state.stage = .disconnected
            state.remoteControlPendingGeneration = nil
            stopPolling()
            state.connectedSince = nil
            state.downloadBytesPerSecond = 0
            state.uploadBytesPerSecond = 0
            state.connections = []
            state.connectionCount = 0
             
             
            if wasUp { loadOfflineNodes() }
             
             
             
             
            let startNeverCameUp = startRequested && !wasUp
                && (previous == .connecting || previous == .disconnected || previous == .invalid)
            let droppedWhileUp = wasUp && !stopRequested
            if startNeverCameUp || droppedWhileUp {
                startRequested = false
                explainDrop(unexpectedWhileUp: droppedWhileUp)
            }
            stopRequested = false
        @unknown default:
            state.stage = .disconnected
        }
    }

    private func explainDrop(unexpectedWhileUp: Bool) {
        let fallback = unexpectedWhileUp
            ? ControllerError.tunnelStopped.localizedDescription
            : ControllerError.tunnelDidNotStart.localizedDescription
        guard let profile = manager else {
            sayDrop(fallback, unexpectedWhileUp: unexpectedWhileUp)
            return
        }
        let generation = startGeneration
         
         
        let providerLooksUnlaunched = startFailureTracker.providerLooksUnlaunched
        Task { @MainActor [weak self] in
            let error = await profile.lastDisconnectError()
            guard let self else { return }
             
             
            guard self.startGeneration == generation, self.state.stage == .disconnected,
                  self.state.issue == nil, self.state.vpnAuthorization == nil else { return }
             
             
             
            if let error, Self.isNodeLibraryUnavailable(error), !self.libraryRepublished,
               let subscription = self.connectedSubscription {
                self.libraryRepublished = true
                ClashLogStore.shared.append("tv start: node library unavailable, publishing again  reason=\(error.localizedDescription)",
                                           stream: .app, level: .warning)
                await self.connect(subscription: subscription, republishing: true)
                return
            }
            if let error {
                self.sayDrop(Self.dropMessage(for: error as NSError, providerLooksUnlaunched: providerLooksUnlaunched),
                             unexpectedWhileUp: unexpectedWhileUp)
            } else {
                self.sayDrop(fallback, unexpectedWhileUp: unexpectedWhileUp)
            }
        }
    }

     
     
     
     
    private func sayDrop(_ sentence: String, unexpectedWhileUp: Bool) {
        report(issue: sentence)
        state.post(unexpectedWhileUp ? ClashTVFeedback.disconnected(reason: sentence)
                                     : ClashTVFeedback.couldNotConnect(reason: sentence),
                   for: .connect, remembers: false)
    }

     

    private func startPolling() {
        guard pollTask == nil, presentation.active, state.isConnected else { return }
        let page = presentation.page
        pollTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                guard let self, self.state.isConnected else { return }
                for command in page.commands(tick: tick) {
                    guard !Task.isCancelled else { return }
                    switch command {
                    case .traffic: await self.refreshTraffic()
                    case .proxyDelays: await self.refreshProxyDelays(cancellableRead: true)
                    case .connections: await self.refreshConnections()
                    case .status: await self.refreshStatus(cancellableRead: true)
                    }
                }
                if self.pendingCompileIsDue(at: self.clock()) { self.startPendingCompile() }
                tick = (tick + 1) % 3
                do { try await self.pollSleep() } catch { return }
            }
        }
    }

     
     
    private var acceptsKernelReplies: Bool {
        state.isConnected && !Task.isCancelled
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }


     
    private struct ReadContext {
        let generation: ClashTVIPCGeneration
        let presentationEpoch: UInt64
        let controlRevision: UInt64
    }

    private func readContext() -> ReadContext {
        .init(generation: ipcGeneration, presentationEpoch: presentationEpoch, controlRevision: controlRevision)
    }

    private func accepts(_ context: ReadContext) -> Bool {
        acceptsKernelReplies && context.generation === ipcGeneration && context.generation.isValid
            && context.presentationEpoch == presentationEpoch && context.controlRevision == controlRevision
    }

    private func readFailed(_ error: Error, context: ReadContext,
                            fields: [WritableKeyPath<ClashTVControlObservations, ClashTVObservation>]) {
        guard accepts(context), !(error is CancellationError) else { return }
        let kind: ClashTVObservation.FailureKind
        if let error = error as? ControllerError {
            switch error {
            case .ipcReplySuperseded: return
            case .ipcNotSent: kind = .notSent
            case .ipcResultUnknown: kind = .resultUnknown
            case .invalidResponse: kind = .invalidReply
            default: kind = .readFailed
            }
        } else {
            if let decoding = error as? ClashTVKernelSnapshots.DecodingError {
                switch decoding {
                case .kernelError: kind = .readFailed
                case .notAnObject: kind = .invalidReply
                }
            } else { kind = .readFailed }
        }
        let failure = ClashTVObservation.Failure(kind: kind, message: error.localizedDescription)
        for field in fields { state.observations[keyPath: field].fail(failure) }
    }

    private func refreshTraffic() async {
        let context = readContext()
        do {
            let reply = try await send(["cmd": "traffic"], timeout: 2, cancellableRead: true)
            let traffic = try ClashTVKernelSnapshots.traffic(from: reply)
            guard accepts(context) else { return }
            let moment = observationClock()
            if traffic.hasRates {
                state.downloadBytesPerSecond = traffic.down
                state.uploadBytesPerSecond = traffic.up
                state.observations.traffic.accept(moment)
            } else {
                state.observations.traffic.fail(.init(kind: .invalidReply, message: String(localized: "Couldn't read traffic speed")))
            }
            if traffic.hasTotals {
                state.sessionBytes = traffic.downTotal + traffic.upTotal
                state.observations.totals.accept(moment)
            } else {
                state.observations.totals.fail(.init(kind: .invalidReply, message: String(localized: "Couldn't read traffic totals")))
            }
            if traffic.memory > 0 {
                state.memoryBytes = traffic.memory
                state.observations.memory.accept(moment)
            } else {
                state.observations.memory.fail(.init(kind: .invalidReply, message: String(localized: "Couldn't read memory use")))
            }
        } catch {
            readFailed(error, context: context, fields: [\.traffic, \.totals, \.memory])
        }
    }

     
     
     
     
     
     
     
     
     
    @discardableResult
    func refreshProxies(cancellableRead: Bool = false) async -> [String: ClashTVKernelSnapshots.GroupSelection]? {
        let context = readContext()
        do {
            let reply = try await send(["cmd": "proxiesSummary"], cancellableRead: cancellableRead)
            let summary = try ClashTVKernelSnapshots.summary(from: reply)
            guard accepts(context) else { return nil }
             
             
            var read = memberPages.mapValues(\.members.count)
            if summary.revision != memberRevision || summary.revision == nil {
                 
                memberPages = [:]
                memberRevision = summary.revision
            } else {
                read = [:]
            }
            for (name, group) in summary.groups.sorted(by: { $0.key < $1.key }) {
                let had = max(read[name] ?? 0, memberPages[name]?.members.count ?? 0)
                let wanted = min(group.total, max(Self.wholeGroupMembers, had))
                guard (memberPages[name]?.members.count ?? 0) < wanted else { continue }
                try await readMembers(of: name, upTo: wanted, cancellableRead: cancellableRead)
                guard accepts(context) else { return nil }
            }
            lastSummary = summary
            return showNodes(summary)
        } catch {
            readFailed(error, context: context, fields: [\.proxies])
            return nil
        }
    }

     
     
    @discardableResult
    private func showNodes(_ summary: ClashTVKernelSnapshots.Summary,
                           fromTunnel: Bool = true) -> [String: ClashTVKernelSnapshots.GroupSelection] {
        let decoded = ClashTVKernelSnapshots.proxies(summary: summary, members: memberPages.mapValues(\.members),
                                                     groupOrder: groupOrder)
        state.proxyGroups = decoded.groups
        state.hiddenProxyGroups = decoded.hiddenGroups
        state.nodeCount = decoded.nodeCount
         
         
        if !decoded.easyTierPlaceholders.isEmpty { state.easyTierNodeNames.formUnion(decoded.easyTierPlaceholders) }
         
         
        state.groupCount = decoded.groups.filter { $0.name != "GLOBAL" }.count
         
         
         
         
         
         
        state.groupReadingURLs = decoded.readingURLs
        let urls = Set(decoded.readingURLs.values)
        if !urls.isSubset(of: delayBook.readingURLs) { delaysLackURLRecords = true }
        let moved = delayBook.name(configured: decoded.configuredNodes).union(delayBook.follow(urls: urls))
        for name in moved where !sweepingMembers.contains(name) && testedAt[name] == nil {
            state.latency[name] = delayBook.latency[name]
        }
        showRoute()
        if fromTunnel {
            state.observations.proxies.accept(observationClock())
        } else {
            state.observations.proxies.useConfiguration()
        }
        return decoded.selections
    }

     
     
     
    static let wholeGroupMembers = 500
     
    static let memberPageSize = 500

     
     
    private struct MemberPages {
        var total: Int
        var members: [ClashTVKernelSnapshots.Member]
    }
    private var memberPages: [String: MemberPages] = [:]
    private var memberRevision: String?
    private var lastSummary: ClashTVKernelSnapshots.Summary?

    private func readMembers(of group: String, upTo wanted: Int, cancellableRead: Bool) async throws {
        let revision = memberRevision
        let started = memberPages[group]?.members.count ?? 0
        var pages = memberPages[group] ?? MemberPages(total: wanted, members: [])
        defer {
             
             
             
            if memberRevision == revision, (memberPages[group]?.members.count ?? 0) == started {
                memberPages[group] = pages
            }
        }
        while pages.members.count < wanted {
            let reply = try await send(["cmd": "groupMembers", "group": group, "offset": pages.members.count,
                                        "limit": min(Self.memberPageSize, wanted - pages.members.count)],
                                       cancellableRead: cancellableRead)
            let page = try ClashTVKernelSnapshots.membersPage(from: reply)
             
             
            if let read = page.revision, let summary = revision, read != summary { return }
            pages.total = page.total
            pages.members += page.members
             
             
            if page.members.isEmpty || pages.members.count >= page.total { break }
        }
    }

     
     
    func loadMoreMembers(of group: String) async {
        guard memberLoads.insert(group).inserted else { return }
        defer { memberLoads.remove(group) }
        guard let summary = lastSummary, let total = summary.groups[group]?.total else { return }
        let read = memberPages[group]?.members.count ?? 0
        guard read < total else { return }
        if !state.isConnected {
             
             
            guard let container, let published = offlinePublished else { return }
            let applied = controlRevision
            let have = memberPages
            let target = min(total, read + Self.memberPageSize)
            let more = await Task.detached {
                try? Self.readCatalog(container: container, published: published, have: have,
                                      wanted: { name, total in name == group ? target : min(have[name]?.members.count ?? 0, total) })
            }.value
            guard let more, !state.isConnected, controlRevision == applied else { return }
            memberPages = more.members
            showNodes(summary, fromTunnel: false)
            return
        }
        let context = readContext()
        do {
            try await readMembers(of: group, upTo: min(total, read + Self.memberPageSize), cancellableRead: true)
             
            guard accepts(context), let latest = lastSummary else { return }
            showNodes(latest)
        } catch {
            readFailed(error, context: context, fields: [\.proxies])
        }
    }
    private var memberLoads: Set<String> = []
     
    private var sweepReserved = false

     
     
     
     
    private func showRoute() {
        let groups = state.proxyGroups
        let root = state.outboundMode == .global
            ? groups.first { $0.name == "GLOBAL" }
            : groups.first { $0.name != "GLOBAL" }
        if let root {
            state.nodeGroup = root.name
            state.nodeName = Self.leaf(of: root, in: groups) ?? root.currentSelection ?? ""
        } else {
            state.nodeName = ""
            state.nodeGroup = ""
        }
    }

     
     
     
    private var documentMark: ClashTVKernelSnapshots.DocumentMark?

     
     
     
    private var delayBook = ClashTVKernelSnapshots.DelayBook()
     
     
    private var delaysLackURLRecords = false
    private struct DelayCursor {
        var since: Int64 = 0
        var after = ""
         
        var sweepNow: Int64?
    }
    private var delayCursor = DelayCursor()
     
    private var rebuildingDelays = false
    private var delayReading = false
    private var delayReaders: [CheckedContinuation<Void, Never>] = []

    private func acquireDelayRead() async {
        guard delayReading else { delayReading = true; return }
        await withCheckedContinuation { delayReaders.append($0) }
    }

     
    private func releaseDelayRead() {
        if delayReaders.isEmpty { delayReading = false } else { delayReaders.removeFirst().resume() }
    }
     
     
    static let delayPagesPerPoll = 8
    static let delayPageSize = 2_000

     
     
     
     
     
     
     
     
     
     
    func refreshProxyDelays(cancellableRead: Bool = false, forceDocument: Bool = false) async {
         
         
        await acquireDelayRead()
        defer { releaseDelayRead() }
        let context = readContext()
         
         
        let began = measurementClock
         
         
         
         
         
         
         
         
        var carried = unappliedDelayNames
        unappliedDelayNames = [:]
        var touched = Set<String>()
        func keep() {
             
            guard context.generation === ipcGeneration else { return }
            for (name, read) in carried { unappliedDelayNames[name] = min(read, unappliedDelayNames[name] ?? .max) }
            for name in touched where unappliedDelayNames[name] == nil { unappliedDelayNames[name] = began }
        }
        var sweepEnded = false
        if delaysLackURLRecords {
            delaysLackURLRecords = false
            delayCursor = .init()
            rebuildingDelays = true
        }
        if delayBook.revision == nil { rebuildingDelays = true }
        do {
            var pages = 0
            while pages < Self.delayPagesPerPoll {
                let reply = try await send(["cmd": "proxyDelaysPage", "since": delayCursor.since,
                                            "after": delayCursor.after, "limit": Self.delayPageSize],
                                           cancellableRead: cancellableRead)
                let page = try ClashTVKernelSnapshots.proxyDelaysPage(from: reply)
                guard accepts(context) else { keep(); return }
                pages += 1
                if page.revision != delayBook.revision, delayCursor.since != 0 || !delayCursor.after.isEmpty {
                     
                     
                    delayBook.reset(revision: page.revision)
                    delayCursor = .init()
                    rebuildingDelays = true
                     
                    touched = []
                    carried = [:]
                    testedAt = [:]
                    continue
                }
                if page.revision != delayBook.revision, delayBook.revision != nil {
                    rebuildingDelays = true
                    touched = []
                    carried = [:]
                    testedAt = [:]
                }
                if page.revision != delayBook.revision { rebuildingDelays = true }
                touched.formUnion(delayBook.absorb(page))
                if delayCursor.sweepNow == nil { delayCursor.sweepNow = page.now }
                if let next = page.next {
                    delayCursor.after = next
                } else {
                    delayCursor = .init(since: delayCursor.sweepNow ?? delayCursor.since)
                    sweepEnded = true
                    break
                }
            }
        } catch {
             
             
            keep()
            readFailed(error, context: context, fields: [\.latency])
             
             
             
             
             
             
             
             
            let now = observationClock().instant
            let due = documentMark == nil || documentReadAt.map { now - $0 >= Self.fallbackDocumentInterval } ?? true
            if accepts(context), forceDocument || due,
               let shown = await refreshProxies(cancellableRead: cancellableRead) {
                documentMark = .init(revision: nil, selections: [:], shown: shown, rechecked: true)
                documentReadAt = now
            }
            return
        }
        guard accepts(context) else { keep(); return }
        let delays = delayBook.delays
         
        var readAt = carried
        for name in touched { readAt[name] = began }
        if rebuildingDelays, sweepEnded {
            rebuildingDelays = false
            apply(delays, readAt: readAt, whole: true)
        } else {
            apply(delays, readAt: readAt)
        }
        guard forceDocument || delays.needsDocument(since: documentMark),
              let shown = await refreshProxies(cancellableRead: cancellableRead), accepts(context) else { return }
        documentMark = delays.mark(shown: shown, after: documentMark)
        documentReadAt = observationClock().instant
    }

     
     
     
     
    private func apply(_ delays: ClashTVKernelSnapshots.ProxyDelays, readAt: [String: UInt64] = [:], whole: Bool = false) {
         
         
         
        let touched = Set(readAt.keys)
        let newer = Set(testedAt.filter { name, at in at > (readAt[name] ?? .max) }.keys)
        let held = sweepingMembers.union(newer)
        if whole {
            state.latency = ClashTVNodesScreen.merge(polled: delays.latency, over: state.latency,
                                                     sweeping: held.union(testedAt.keys.filter { !touched.contains($0) }))
        } else {
            for name in touched where !held.contains(name) { state.latency[name] = delays.latency[name] }
        }
        for name in touched where !held.contains(name) { testedAt[name] = nil }
        state.observations.latency.accept(observationClock())
    }

     
     
     
     
     
    private var testedAt: [String: UInt64] = [:]
    private var measurementClock: UInt64 = 0
     
     
    private var unappliedDelayNames: [String: UInt64] = [:]

    private func noteMeasured(_ name: String) {
        measurementClock &+= 1
        testedAt[name] = measurementClock
    }

     
    private func noteMeasured(_ probe: ClashTVNodesScreen.Probe) {
        noteMeasured(probe.name)
        testedAt[probe.key] = measurementClock
    }

     
     
     
    static func urlTestRequest(_ probe: ClashTVNodesScreen.Probe) -> [String: Any] {
        var request: [String: Any] = ["cmd": "urltest", "name": probe.name]
        if let url = probe.url { request["url"] = url }
        return request
    }
     
    private var documentReadAt: ContinuousClock.Instant?
    static let fallbackDocumentInterval: Duration = .seconds(30)

    private static func leaf(of group: ClashProxyGroupSnapshot, in groups: [ClashProxyGroupSnapshot], depth: Int = 0) -> String? {
        guard depth < 8, let selection = group.currentSelection else { return nil }
        if let next = groups.first(where: { $0.name == selection }) {
            return leaf(of: next, in: groups, depth: depth + 1) ?? selection
        }
        return selection
    }

    private func refreshConnections() async {
        let context = readContext()
        do {
            let reply = try await send(["cmd": "connections"], cancellableRead: true)
            let read = try ClashTVKernelSnapshots.connectionRead(from: reply)
            guard accepts(context) else { return }
            guard read.isComplete else {
                state.observations.connections.fail(.init(kind: .invalidReply, message: String(localized: "The connection list was incomplete.")))
                return
            }
            state.connections = read.rows
            state.connectionCount = read.rows.count
            state.observations.connections.accept(observationClock())
        } catch {
            readFailed(error, context: context, fields: [\.connections])
        }
    }

    private func refreshStatus(cancellableRead: Bool = false) async {
        let context = readContext()
        do {
            let reply = try await send(["cmd": "status"], cancellableRead: cancellableRead)
            let status = try ClashTVKernelSnapshots.status(from: reply)
            guard let mode = ClashTVOutboundMode(rawValue: status.mode.lowercased()) else {
                throw ClashTVKernelSnapshots.DecodingError.notAnObject("mode")
            }
            guard accepts(context) else { return }
            if state.outboundMode != mode {
                state.outboundMode = mode
                if state.observations.proxies.hasRuntimeSample { showRoute() }
            }
            state.observations.mode.accept(observationClock())
            await refreshRuleProviders(force: false)
        } catch {
            readFailed(error, context: context, fields: [\.mode])
        }
    }

     
    private func readProviderRefresh() {
        guard let container else { state.providerRefresh = nil; return }
        let working = container.appendingPathComponent("working", isDirectory: true)
        let read = ProviderRefreshState.read(workingDirectory: working)
        if read != state.providerRefresh { state.providerRefresh = read }
    }

     
    func refreshRuleProviders(force: Bool = true, now: Date = Date()) async {
        let context = readContext()
        guard accepts(context), let container,
              let store = try? ConfigResourceStore(containerURL: container),
              let expected = try? store.activeIdentity() else { return }
         
         
        readProviderRefresh()
         
         
        if !state.providers.isEmpty {
            state.ruleProvidersLoaded = ClashTVProvidersScreen.readyCount(state.providers, tunnel: state.providerRefresh,
                                                                            running: state.isConnected)
        }
        let newIdentity = ruleProbePointer != expected || ruleProbeGeneration !== ipcGeneration
        let pending = ruleRecoveryPending || state.providers.contains { $0.kind == "rule" && $0.pending }
        let visible = presentation.active && presentation.page == .providers
        guard force || newIdentity || ((pending || visible) && now.timeIntervalSince(nextRuleProbeAt) >= 0) else { return }
        if newIdentity { ruleProbeBackoff = 3 }
        ruleProbePointer = expected
        ruleProbeGeneration = ipcGeneration
        nextRuleProbeAt = now.addingTimeInterval(visible ? 10 : ruleProbeBackoff)
        ruleProbeBackoff = min(60, ruleProbeBackoff * 2)
        let directory = store.providersDirectory(profileID: expected.profileID, revision: expected.revision)
        let record = directory.flatMap { ClashTVRuleRecovery.read(from: $0) }
        ruleRecoveryPending = record?.hasUnexpandedRoutes ?? false
         
        readProviderRefresh()
         
         
        guard state.providers.contains(where: { $0.kind == "rule" }) else { return }
        do {
            let reply = try await send(["cmd": "ruleProviders"], cancellableRead: true)
            let providers = try ClashTVKernelSnapshots.ruleProviders(from: reply)
            guard accepts(context), try store.activeIdentity() == expected else { return }
             
             
            state.providers = state.providers.map { entry in
                guard entry.kind == "rule", let provider = providers[entry.name], provider.loaded,
                      entry.note != .inline else { return entry }
                var loaded = entry
                loaded.note = nil
                loaded.updatedAt = provider.updatedAt ?? entry.updatedAt
                return loaded
            }
            readProviderRefresh()
            state.ruleProvidersLoaded = ClashTVProvidersScreen.readyCount(
                state.providers, tunnel: state.providerRefresh, running: state.isConnected)
            guard record != nil else { return }
             
             
            let tunnelHashes = ClashTVRuleRecovery.tunnelContent(container: container)
            let pipeline = ClashTVConfigPipeline(container: container, session: session)
            let recovered = try await pipeline.recoverRules(expected: expected, tunnelHashes: tunnelHashes) { [weak self] hashes in
                guard let self, self.accepts(context), try store.activeIdentity() == expected else { return false }
                let second = ClashTVRuleRecovery.tunnelContent(container: container)
                return hashes.allSatisfy { key, hash in
                    second[String(key.dropFirst("rule:".count))]?.contains(hash) == true
                }
            }
            if let recovered, accepts(context) {
                ruleProbePointer = .init(profileID: recovered.profileID, revision: recovered.revision)
                if let directory = store.providersDirectory(profileID: recovered.profileID, revision: recovered.revision) {
                    ruleRecoveryPending = ClashTVRuleRecovery.read(from: directory)?.hasUnexpandedRoutes ?? false
                }
            }
        } catch {
             
             
            guard !(error is CancellationError), accepts(context),
                  (try? store.activeIdentity()) == expected else { return }
            ClashLogStore.shared.append("tv rule recovery: \(error.localizedDescription)", stream: .app, level: .warning)
        }
    }


     

    private func send(_ object: [String: Any], timeout: TimeInterval = messageTimeout, cancellableRead: Bool = false, expectedGeneration: ClashTVIPCGeneration? = nil) async throws -> Data {
        let generation = expectedGeneration ?? ipcGeneration
        guard generation === ipcGeneration, generation.isValid else { throw ControllerError.ipcNotSent(.connectionChanged) }
        let payload = try JSONSerialization.data(withJSONObject: object)
        let reply: Data
        if let messageReader {
            reply = try await messageReader(payload, UInt64(timeout * 1_000_000_000), cancellableRead)
        } else {
            guard let session = manager?.vpnConnection as? NETunnelProviderSession else {
                throw ControllerError.ipcNotSent(.connectionChanged)
            }
            reply = try await ipcChannel.send(session: session, data: payload,
                timeoutNanoseconds: UInt64(timeout * 1_000_000_000),
                cancellableRead: cancellableRead, generation: generation)
        }
        guard generation === ipcGeneration, generation.isValid else { throw ControllerError.ipcReplySuperseded }
        return reply
    }

    private static func isOK(_ reply: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: reply) as? [String: Any])?["ok"] as? Bool == true
    }

     
    private static func errorClass(_ reply: Data) -> String? {
        (try? JSONSerialization.jsonObject(with: reply) as? [String: Any])?["errorClass"] as? String
    }

     
    private static func committedWarning(_ reply: Data) -> String? {
        guard errorClass(reply) == "committed" else { return nil }
        let warning = (try? JSONSerialization.jsonObject(with: reply) as? [String: Any])?["warning"] as? String
        return warning?.isEmpty == false ? warning : nil
    }

    private static func replyError(_ reply: Data) -> Error {
        guard let root = try? JSONSerialization.jsonObject(with: reply) as? [String: Any],
              let refusal = ClashTVKernelSnapshots.refusal(in: root) else {
            return ControllerError.invalidResponse
        }
        return ControllerError.kernelRefused(refusal.text)
    }

     

     
     
     
     
     
     
     
     
     
     
     
    static func bounded<T: Sendable>(
        _ seconds: TimeInterval,
        late: (@Sendable (Result<T, Error>) -> Void)? = nil,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let once = ClashTVResumeOnce()
            let work = Task {
                do {
                    let value = try await operation()
                    if once.claim() { continuation.resume(returning: value) } else { late?(.success(value)) }
                } catch {
                    if once.claim() { continuation.resume(throwing: error) } else { late?(.failure(error)) }
                }
            }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                if once.claim() {
                     
                     
                    if late == nil { work.cancel() }
                    continuation.resume(throwing: ControllerError.systemTimedOut)
                }
            }
        }
    }

     
     
     
     
    enum ControllerError: LocalizedError {
        case appGroupUnavailable
        case extensionUnavailable
        case systemTimedOut
        case tunnelTimedOut
        case invalidResponse
        case ipcNotSent(IPCNotSentReason)
        case ipcResultUnknown
        case ipcReplySuperseded

        enum IPCNotSentReason {
            case capacity, deadline, connectionChanged, unresolved, invalidRequest, unsupportedAsyncReload
            case transport(String)
        }
        case tunnelDidNotStart
        case tunnelStopped
        case kernelRefused(String)
        case ipStackRestartFailed(String)
         
         
        case ipStackStopUnanswered(String)

        var errorDescription: String? {
            switch self {
            case .ipStackRestartFailed(let reason):
                return String(localized: "IP Stack settings were saved, but Clash didn't reconnect. Connect again to apply them.") + "\n" + reason
            case .ipStackStopUnanswered(let reason):
                return String(localized: "IP Stack settings were saved, but Clash didn't reconnect. Connect again to apply them.") + "\n" + reason
            case .appGroupUnavailable:
                return String(localized: "Clash couldn't read its saved data")
            case .extensionUnavailable:
                return String(localized: "Clash isn't available")
            case .systemTimedOut:
                return String(localized: "Apple TV didn't respond in time — try again")
            case .tunnelTimedOut:
                return String(localized: "Clash didn't respond in time")
            case .ipcNotSent(let reason):
                let detail: String
                switch reason {
                case .capacity: detail = String(localized: "Too many changes at once — try again in a moment")
                case .deadline: detail = String(localized: "Timed out — try again")
                case .connectionChanged: detail = String(localized: "Clash reconnected meanwhile — try again")
                case .unresolved: detail = String(localized: "The last change hasn't finished — try again in a moment")
                case .invalidRequest: detail = String(localized: "Clash couldn't do that")
                case .unsupportedAsyncReload: detail = String(localized: "Clash couldn't do that")
                case .transport(let message): detail = message
                }
                return detail
            case .ipcResultUnknown:
                return String(localized: "Clash didn't confirm the change. Check whether it took effect.")
            case .ipcReplySuperseded:
                return String(localized: "Clash reconnected meanwhile — try again")
            case .invalidResponse:
                return String(localized: "Clash gave an unexpected answer")
            case .tunnelDidNotStart:
                return String(localized: "Clash couldn't connect. Try again.")
            case .tunnelStopped:
                return String(localized: "Clash disconnected. Connect again to continue.")
            case .kernelRefused(let reason):
                 
                 
                 
                return reason
            }
        }
    }
}

 
 
 
 
 
actor ClashTVIPCChannel {
    static let shared = ClashTVIPCChannel()
    typealias Delivery = @Sendable (Data, @escaping @Sendable (Data?) -> Void) throws -> Void
    typealias Failure = ClashTVTunnelController.ControllerError

    struct Limits: Sendable {
        var queuedCount = 32
        var payloadBytes = 256 * 1024
        var timeoutNanoseconds: UInt64 = 30_000_000_000
        var unansweredHoldNanoseconds: UInt64 = 15_000_000_000
    }
    private struct Pending {
        let id: UUID
        let command: String
        let deliver: Delivery
        let data: Data
        let ticket: ClashTVReadAdmission?
        let generation: ClashTVIPCGeneration?
        let deadline: ContinuousClock.Instant
        let continuation: CheckedContinuation<Data, Error>
    }
     
     
    private struct Unresolved {
        let id: UUID
        let command: String
        let generation: ClashTVIPCGeneration?
        let deadline: ContinuousClock.Instant
         
        let sentAt: ContinuousClock.Instant
        var continuation: CheckedContinuation<Data, Error>?
    }

    private let limits: Limits
    private var queue: [Pending] = []
    private var current: Unresolved?
    private var deadlines: [UUID: Task<Void, Never>] = [:]
    private(set) var queuedBytes = 0
    var queuedCount: Int { queue.count }
    var unresolvedCount: Int { current == nil ? 0 : 1 }
    var quarantined: Bool { current != nil && current?.continuation == nil }

    init(limits: Limits = Limits()) { self.limits = limits }

    func send(session: NETunnelProviderSession, data: Data, timeoutNanoseconds: UInt64,
              cancellableRead: Bool = false, generation: ClashTVIPCGeneration? = nil) async throws -> Data {
        try await send(data: data, timeoutNanoseconds: timeoutNanoseconds,
                       cancellableRead: cancellableRead, generation: generation) { data, reply in
            try session.sendProviderMessage(data, responseHandler: reply)
        }
    }

    func send(data: Data, timeoutNanoseconds: UInt64, cancellableRead: Bool = false,
              generation: ClashTVIPCGeneration? = nil, deliver: @escaping Delivery) async throws -> Data {
        let deadline = ContinuousClock.now.advanced(by: .nanoseconds(Int64(clamping:
            min(timeoutNanoseconds, limits.timeoutNanoseconds))))
        guard data.count <= limits.payloadBytes else { throw Failure.ipcNotSent(.capacity) }
        guard let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let command = request["cmd"] as? String, !command.isEmpty, command.utf8.count <= 64 else {
            throw Failure.ipcNotSent(.invalidRequest)
        }
         
         
        if command == "reload", request["async"] as? Bool == true {
            throw Failure.ipcNotSent(.unsupportedAsyncReload)
        }
        let id = UUID()
        let ticket = cancellableRead && Self.readCommands.contains(command) ? ClashTVReadAdmission() : nil
        return try await withTaskCancellationHandler {
            if ticket != nil { try Task.checkCancellation() }
            guard generation?.isValid != false else { throw Failure.ipcNotSent(.connectionChanged) }
            guard deadline > .now else { throw Failure.ipcNotSent(.deadline) }
            guard !quarantined else { throw Failure.ipcNotSent(.unresolved) }
            guard queue.count < limits.queuedCount,
                  data.count <= limits.payloadBytes - queuedBytes else { throw Failure.ipcNotSent(.capacity) }
            return try await withCheckedThrowingContinuation { continuation in
                queue.append(Pending(id: id, command: command, deliver: deliver, data: data,
                    ticket: ticket, generation: generation, deadline: deadline, continuation: continuation))
                queuedBytes += data.count
                deadlines[id] = Task { [weak self] in
                    do { try await ContinuousClock().sleep(until: deadline) } catch { return }
                    await self?.expire(id: id)
                }
                startNextIfNeeded()
            }
        } onCancel: {
            guard let ticket else { return }
            ticket.cancel()
            Task { await self.removeQueued(id: id, error: CancellationError()) }
        }
    }

    private static let readCommands: Set<String> = [
        "hello", "runtimeDiagnostics", "reloadStatus", "status", "traffic",
        "connections", "proxies", "ruleProviders", "logs", "proxyShareStatus",
        "proxiesSummary", "groupMembers", "providerNodes", "proxiesPage", "proxyDelaysPage"
    ]

    private func removeQueued(id: UUID, error: Error) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        let pending = queue.remove(at: index)
        queuedBytes -= pending.data.count
        deadlines.removeValue(forKey: id)?.cancel()
        pending.continuation.resume(throwing: error)
    }

    private func startNextIfNeeded() {
        guard current == nil else { return }
        while !queue.isEmpty {
            let pending = queue.removeFirst()
            queuedBytes -= pending.data.count
            let failure: Error?
            if pending.generation?.isValid == false { failure = Failure.ipcNotSent(.connectionChanged) }
            else if pending.deadline <= .now { failure = Failure.ipcNotSent(.deadline) }
            else if let ticket = pending.ticket, !ticket.admit() { failure = CancellationError() }
            else { failure = nil }
            if let failure {
                deadlines.removeValue(forKey: pending.id)?.cancel()
                pending.continuation.resume(throwing: failure)
                continue
            }
            let id = pending.id
            current = Unresolved(id: id, command: pending.command, generation: pending.generation,
                                 deadline: pending.deadline, sentAt: .now, continuation: pending.continuation)
            do {
                try pending.deliver(pending.data) { [weak self] response in
                    Task { await self?.receive(id: id, response: response) }
                }
                return
            } catch {
                 
                deadlines.removeValue(forKey: id)?.cancel()
                current = nil
                pending.continuation.resume(throwing: Failure.ipcNotSent(.transport(error.localizedDescription)))
                 
            }
        }
    }

    private func expire(id: UUID) {
        deadlines.removeValue(forKey: id)?.cancel()
        if current?.id == id { makeUnknown(id: id) }
        else { removeQueued(id: id, error: Failure.ipcNotSent(.deadline)) }
    }

    private func makeUnknown(id: UUID) {
        guard current?.id == id else { return }
        deadlines.removeValue(forKey: id)?.cancel()
        let continuation = current?.continuation
        current?.continuation = nil
        continuation?.resume(throwing: Failure.ipcResultUnknown)
         
         
         
         
        let hold = limits.unansweredHoldNanoseconds
        deadlines[id] = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: hold) } catch { return }
            await self?.release(id: id)
        }
    }

     
     
     
     
     
    func tunnelEnded(at instant: ContinuousClock.Instant) {
        guard let unresolved = current, unresolved.sentAt <= instant else { return }
        deadlines.removeValue(forKey: unresolved.id)?.cancel()
        current = nil
        unresolved.continuation?.resume(throwing: Failure.ipcResultUnknown)
        ClashLogStore.shared.append(#"tv ipc: "\#(unresolved.command)" unanswered when the tunnel ended; later requests go out again"#,
                                    stream: .app, level: .warning)
        startNextIfNeeded()
    }

    private func release(id: UUID) {
        guard let unresolved = current, unresolved.id == id, unresolved.continuation == nil else { return }
        deadlines.removeValue(forKey: id)
        current = nil
        ClashLogStore.shared.append(#"tv ipc: "\#(unresolved.command)" went unanswered; later requests go out again"#,
                                    stream: .app, level: .warning)
        startNextIfNeeded()
    }

    private func receive(id: UUID, response: Data?) {
        guard let unresolved = current, unresolved.id == id else { return }
        guard let response, Self.isCompletion(response, command: unresolved.command) else {
            makeUnknown(id: id)
            return
        }
        deadlines.removeValue(forKey: id)?.cancel()
        current = nil
        if unresolved.deadline <= .now {
            unresolved.continuation?.resume(throwing: Failure.ipcResultUnknown)
        } else if unresolved.generation?.isValid == false {
            unresolved.continuation?.resume(throwing: Failure.ipcReplySuperseded)
        } else {
            unresolved.continuation?.resume(returning: response)
        }
        startNextIfNeeded()
    }

    private static func isCompletion(_ data: Data, command: String) -> Bool {
         
         
        if command == "consumeGoCrashReport" { return String(data: data, encoding: .utf8) != nil }
        guard let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return false }
        if command == "logs", value is [String] || value is NSNull { return true }
        guard let object = value as? [String: Any] else { return false }
        if object["error"] is String { return true }
        if object["accepted"] as? Bool == true { return false }
        switch command {
        case "reload", "setMode", "select", "unfix", "closeAll", "recordMemoryPressureEvidence", "urltestSweepStop":
            return object["ok"] as? Bool == true
        case "hello":
            return object["schemaVersion"] is NSNumber && object["coreVersion"] is String
        case "status":
            return object["status"] is String && object["mode"] is String
        case "traffic":
            return ["up", "down", "upTotal", "downTotal"].allSatisfy { object[$0] is NSNumber }
        case "connections":
            return object["connections"] is [Any] || object["connections"] is NSNull
        case "proxies": return object["proxies"] is [String: Any]
         
         
        case "proxiesSummary": return object["groups"] is [String: Any] && object["providers"] is [String: Any]
        case "groupMembers": return object["members"] is [Any] && object["total"] is NSNumber
        case "providerNodes": return object["proxies"] is [Any] && object["total"] is NSNumber
        case "proxiesPage": return object["proxies"] is [String: Any]
        case "proxyDelaysPage":
            return object["proxies"] is [String: Any] && object["providers"] is [String: Any] && object["now"] is NSNumber
         
         
         
        case "rulesPage": return object["rules"] is [Any] && object["total"] is NSNumber && object["offset"] is NSNumber
        case "ruleHits":
            return object["rules"] is [Any] && object["total"] is NSNumber && object["offset"] is NSNumber
                && object["noted"] is NSNumber
         
         
         
        case "updateProvider", "seedProviderFile": return object["result"] is String
         
         
         
        case "ruleProviders": return object["providers"] is [String: Any]
        case "urltest": return object["delay"] is NSNumber
         
        case "urltestSweep": return object["sweep"] is NSNumber && object["count"] is NSNumber
        case "urltestSweepRead": return object["delays"] is [Any] && object["done"] as? Bool != nil
        case "dnsQuery": return object["Status"] is NSNumber
        case "close": return object["closed"] is NSNumber
        case "proxyShareStart", "proxyShareStop", "proxyShareStatus":
            return object["ok"] as? Bool == true && object["status"] is [String: Any]
        case "runtimeDiagnostics", "reloadRuntimeSetupOptions", "exerciseSleepWake":
            return object["goroutines"] is NSNumber
        case "consumeOOMEvidence":
            return object["schemaVersion"] is NSNumber && object["pressureLevel"] is String
                && object["possibleSystemKill"] as? Bool == true
        case "reloadStatus":
            return object["session"] is String && object["state"] is String
         
         
         
        case "remoteControl":
            return object["generation"] is NSNumber && object["mode"] is String
        default:
             
             
            return false
        }
    }
}

 
 
final class ClashTVIPCGeneration: @unchecked Sendable {
    private let lock = NSLock()
    private var valid: Bool
    init(active: Bool = true) { valid = active }
    var isValid: Bool { lock.lock(); defer { lock.unlock() }; return valid }
    func invalidate() { lock.lock(); valid = false; lock.unlock() }
}

 
 
private final class ClashTVReadAdmission: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var admitted = false
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        if !admitted { cancelled = true }
    }
    func admit() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { return false }
        admitted = true
        return true
    }
}

 
final class ClashTVResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}


enum ClashTVPollingPage: Equatable, Sendable {
    case home, nodes, outboundMode, connections, connectionDetail, diagnostics, configuration, providers

     
     
     
     
     
     
     
     

    func commands(tick: Int) -> [ClashTVPollingCommand] {
        var result: [ClashTVPollingCommand] = []
        if self == .home || self == .diagnostics { result.append(.traffic) }
        if tick % 3 == 0 {
            if self == .home || self == .nodes { result.append(.proxyDelays) }
            if self == .home || self == .connections || self == .connectionDetail { result.append(.connections) }
            result.append(.status)
        }
        return result
    }
}

enum ClashTVPollingCommand: String, Equatable, Sendable {
    case traffic, proxyDelays, connections, status
}

struct ClashTVPollingPresentation: Equatable, Sendable {
    let page: ClashTVPollingPage
    let active: Bool
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
