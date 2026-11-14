@preconcurrency import NetworkExtension
import Combine
import Foundation
import Clash
import ClashClientUI

enum NETimeoutError: LocalizedError, Equatable {
    case nePreferencesTimeout
    case extensionMessageTimeout

    var errorDescription: String? {
        "The system VPN service isn’t responding. Please try again in a moment, or restart your Mac."
    }
}

private final class ClashMacNETimeoutGate<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: T) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(throwing: error)
    }
}

private final class ClashMacManagerLoadResult: @unchecked Sendable {
    let managers: [NETunnelProviderManager]
    let error: Error?

    init(_ managers: [NETunnelProviderManager]?, _ error: Error?) {
        self.managers = managers ?? []
        self.error = error
    }
}

@MainActor
final class VPNController: ObservableObject {
    static let vpnProfileTitle = "Clash"
    static let vpnProfileDescription = "Clash"
    private static let packetTunnelExtensionBundleID =
        ClashAppIdentifiers.base + ".packet-tunnel"

    enum OnDemandSaveOutcome: Equatable {
        case applied
        case refused(String)
        case indeterminate(String)
    }

     
     
     
    static func armOnDemand(
        _ manager: NETunnelProviderManager,
        configuration: OnDemandConfiguration
    ) throws {
        try OnDemandSettings.apply(configuration, to: manager)
    }

     
     
     
     
    static func disarmOnDemandForUserStop(
        _ manager: NETunnelProviderManager
    ) -> Bool {
        manager.disarmOnDemandForUserStop()
    }

     
     
     
     
     
    @Published var legacySettingsMigration: LegacyClientSettingsMigrationResult?
    @Published private(set) var status = "idle"
    @Published private(set) var lastError = "" {
        didSet {
            installationReadError = nil
            lastErrorOffersVPNProfileReset = false
            if startRefusedByCore != nil { startRefusedByCore = nil }
        }
    }
     
     
     
     
    @Published private(set) var startRefusedByCore: CoreStartRefusal?

     
     
    var lastErrorText: ClashDisplayText {
        startRefusedByCore.map { .format($0.message, [$0.words]) } ?? text(of: lastError)
    }

     
     
    func text(of sentence: String) -> ClashDisplayText {
        if sentence == lastError, let refusal = startRefusedByCore { return .format(refusal.message, [refusal.words]) }
        return .copy(CoreStartRefusal.isLead(sentence) ? MacVPNDisconnectErrorPresentation.genericStartFailureMessage : sentence)
    }

     
     
     
     
    var lastErrorReason: String {
        if let refusal = startRefusedByCore {
            return ClashCopy.string(for: .format(refusal.message, [refusal.words]), locale: Locale.current)
        }
        return CoreStartRefusal.isLead(lastError) ? MacVPNDisconnectErrorPresentation.genericStartFailureMessage : lastError
    }
     
     
     
     
     
    @Published private(set) var lastErrorOffersVPNProfileReset = false
     
     
     
     
     
     
     
    @Published private(set) var lastReloadNotice: ReloadNotice?

     
     
     
     
     
     
    static let userInitiatedStartOption = ClashTunnelStart.userInitiatedStartOption

     
     
     
    var nextStartIsUserInitiated = false

    struct ReloadNotice: Equatable {
        let errorClass: ReloadErrorClass
         
        let message: String
    }
     
     
     
     
     
    private var awaitingStartTransition = false
    private var systemVPNProfileResetInFlight = false
    @Published private(set) var vpnAuthorization: ClashVPNAuthorizationState?
    private var installationReadError: String?
    private var installationReadGeneration: UInt64 = 0
    private var systemVPNInstallationKnown = false
    private let startRequests = TunnelRequestCoalescer()
    var isStarting: Bool { startRequestsInFlight > 0 }
     
     
     
     
     
     
     
    var compilationBarrier: @MainActor () async -> Bool = {
        await ProfileActivationCoordinator.drainDeferredCompilation()
    }
     
     
     
    var compilationGeneration: () -> UInt64 = { ProfileActivationCoordinator.scheduledCompiles }
     
     
     
     
     
    var libraryGoneHandler: (@MainActor (StartupOutcomeRecord, _ stillWanted: @escaping @MainActor () -> Bool) async -> Void)?
     
     
     
     
    @TaskLocal static var recoveryStopEpoch: UInt?
     
     
     
     
     
    var intentDirectory: () -> URL? = {
        ClashMacAppGroupAccess.isWithheldFromThisProcess ? nil : ReaderTunnelIntent.appGroupDirectory
    }
     
     
     
     
     
     
    var unrequestedStops: VPNUnrequestedStopLog?
     
    var writeUnrequestedStopLine: (String) -> Void = {
        ClashLogStore.shared.append($0, stream: .app, level: .warning)
    }
     
     
     
    var unrequestedStopError: ((NEVPNConnection) async -> NSError?)?
     
     
    var stopsTunnel: (NEVPNConnection) -> Void = { $0.stopVPNTunnel() }
     
     
     
    var startupRecord: () -> StartupOutcomeRecord? = {
        StartupOutcomeRecord.read(from: ClashMacAppGroupAccess.readableContainer())
    }

     
     
     
     
     
     
     
    @discardableResult
    func recordReaderWord(_ intent: ReaderTunnelIntent) -> UInt64? {
        let word = intent.rawValue
         
         
         
        guard let directory = intentDirectory() else { return nil }
        do {
            switch try ReaderTunnelIntent.record(intent, gesture: UUID().uuidString, in: directory) {
            case .accepted(let written): return written.generation
            case .superseded(let newer): return newer.generation
            }
        } catch {
            ClashLogStore.shared.append({ "vpn \(word): reader's word not written  \(error)" }(), stream: .app, level: .warning)
            return nil
        }
    }

     
     
     
     
    struct StandingWord: Equatable, Sendable {
        let generation: UInt64
        let required: Bool
    }

     
     
     
    @TaskLocal static var standingOnWord: StandingWord?

     
     
     
     
     
    func readerWordStands(_ word: StandingWord) -> Bool {
        do {
            guard let last = try ReaderTunnelIntent.last(in: intentDirectory()) else { return true }
            return last.generation == word.generation || last.intent != .stop
        } catch {
            return !word.required
        }
    }

     
     
     
    struct ReaderStoppedSince: Error, VPNStartAbandonment {}
     
     
     
    private var lastStartIssuedAt: Date?
    private var lastStartStopEpoch: UInt = 0
     
    private var foreignStartSeen: (at: Date, stopEpoch: UInt)?
     
     
     
     
     
    @Published private(set) var preparingStarts: Set<UInt64> = []
    var isPreparingStart: Bool { !preparingStarts.isEmpty }
    private var preparingStartSerial: UInt64 = 0

     
     
     
     
     
    func preparingToStart<T>(_ body: @MainActor () async -> T) async -> T {
        preparingStartSerial &+= 1
        let token = preparingStartSerial
        preparingStarts.insert(token)
        defer { preparingStarts.remove(token) }
        return await body()
    }

     
     
     
     
     
     
     
     
     
     
    @Published private(set) var startAwaitingSystem = false
    private var startAnswerDeadline: Task<Void, Never>?
    static let startAnswerWindowMilliseconds: UInt64 = 1_000

    private func systemTookStart() {
        startAnswerDeadline?.cancel()
        startAwaitingSystem = true
        startAnswerDeadline = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.startAnswerWindowMilliseconds * 1_000_000)
            guard !Task.isCancelled else { return }
            self?.startNoLongerAwaited()
        }
    }

     
    private func systemSaid(_ status: NEVPNStatus) {
        guard status == .connecting || status == .connected || status == .reasserting else { return }
        startNoLongerAwaited()
    }

    private func startNoLongerAwaited() {
        startAnswerDeadline?.cancel()
        startAnswerDeadline = nil
        if startAwaitingSystem { startAwaitingSystem = false }
    }

     
    var connectedSince: Date? {
        guard ["connected", "reasserting"].contains(status) else { return nil }
        return manager?.connection.connectedDate
    }
    var systemVPNAuthorization: ClashVPNAuthorizationState? {
        vpnAuthorization ?? (systemVPNInstallationKnown && manager == nil ? .required : nil)
    }
     
     
     
    @Published private(set) var tunnelSettings = VPNTunnelSettings()

    private let preferences: UserDefaults
    private let preferencesReadTimeout: Double
    private let systemVPNManagers: @MainActor () async throws -> [NETunnelProviderManager]
    private var manager: NETunnelProviderManager?
     
     
     
     
     
    private var appliedConfigIntent: PlatformConfigIntent?
    private var statusObserver: NSObjectProtocol?
     
     
     
     
    private var reachedConnectedSinceStart = false
     
     
     
    private var disconnectNoticeTracker = VPNDisconnectNotice.Tracker()
     
     
    private var managerReloadInFlight = false
    private var managerReloadCooldownUntil = ContinuousClock.now
    private let managerReloadCooldown: Duration
     
     
    private let connectionStatus: (NEVPNConnection) -> NEVPNStatus

    private var userStopInFlight = false

    var clientPreferences: UserDefaults { preferences }

    private let profileWriter = IPStackProfileWriter()
    private var profileWriteIntentGeneration: UInt64 = 0
    private var startRequestsInFlight = 0

    var session: NETunnelProviderSession? {
        manager?.connection as? NETunnelProviderSession
    }
    var reportableLastError: String { lastError }
    var systemVPNProfileResetAvailable: Bool { manager != nil }

    init(
        preferences: UserDefaults? = UserDefaults(
            suiteName: ClashAppIdentifiers.defaultsSuite
        ),
        systemVPNManagers: (@MainActor () async throws -> [NETunnelProviderManager])? = nil,
        preferencesReadTimeout: Double = 15,
        managerReloadCooldown: Duration = .seconds(2),
        connectionStatus: @escaping (NEVPNConnection) -> NEVPNStatus = { $0.status }
    ) {
        self.connectionStatus = connectionStatus
        self.preferences = preferences ?? .standard
        self.preferencesReadTimeout = preferencesReadTimeout
        self.managerReloadCooldown = managerReloadCooldown
        self.systemVPNManagers = systemVPNManagers ?? { try await Self.loadSystemManagers() }
        tunnelSettings = VPNTunnelSettings.load(from: self.preferences)
        unrequestedStops = ClashMacAppGroupAccess.isWithheldFromThisProcess
            ? nil : VPNUnrequestedStopLog(defaults: self.preferences)
         
         
         
         
        self.preferences.removeObject(forKey: IPStackSettings.defaultsKey)
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let connection = notification.object as? NEVPNConnection else {
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if connection !== manager?.connection {
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                    guard !isStarting, !profileWriter.isBusy, !managerReloadInFlight else { return }
                    let now = ContinuousClock.now
                    if now >= managerReloadCooldownUntil {
                        managerReloadInFlight = true
                        await refreshSystemVPNInstallation()
                        managerReloadInFlight = false
                        managerReloadCooldownUntil =
                            ContinuousClock.now.advanced(by: managerReloadCooldown)
                    }
                     
                     
                     
                    guard manager != nil else { return }
                }
                let status = connectionStatus(manager?.connection ?? connection)
                updateStatus(status)
                noteTunnelState(status, on: manager?.connection ?? connection)
                 
                 
                 
                 
                 
                 
                if status == .connecting, !awaitingStartTransition, foreignStartSeen == nil {
                    foreignStartSeen = (Date(), stopGeneration)
                } else if status == .connected || status == .reasserting {
                    foreignStartSeen = nil
                } else if status == .disconnected || status == .invalid, let seen = foreignStartSeen {
                    foreignStartSeen = nil
                    answerLibraryGone(issuedAt: seen.at.addingTimeInterval(-2), sinceStop: seen.stopEpoch)
                }
                if status == .connected || status == .reasserting {
                    awaitingStartTransition = false
                } else if awaitingStartTransition,
                          status == .disconnected || status == .invalid,
                          let failed = manager?.connection {
                     
                     
                     
                     
                    awaitingStartTransition = false
                    Task { @MainActor [weak self] in
                        await self?.resolveLastDisconnectError(on: failed)
                    }
                    answerLibraryGone(issuedAt: lastStartIssuedAt, sinceStop: lastStartStopEpoch)
                }
                if status == .connected {
                    if !reachedConnectedSinceStart {
                         
                         
                         
                         
                         
                         
                        ProviderFirstLoadRetry.kick(trigger: .connected)
                    }
                    reachedConnectedSinceStart = true
                } else if status == .disconnected || status == .invalid {
                    reachedConnectedSinceStart = false
                }
                if disconnectNoticeTracker.observe(
                    status,
                    userInitiated: userStopInFlight,
                    enabled: OnDemandSettings.configuration()
                        .showDisconnectMessage
                ) {
                    VPNDisconnectNotice.post()
                }
                if status == .connecting || status == .connected {
                    userStopInFlight = false
                }
            }
        }
    }

    deinit {
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver)
        }
    }

     
     
    func refreshSystemVPNInstallation() async {
        guard !isStarting, !profileWriter.isBusy else { return }
        let intent = profileWriteIntentGeneration
        let revision = profileWriter.revision
        installationReadGeneration &+= 1
        let read = installationReadGeneration
        func isCurrent() -> Bool {
            !Task.isCancelled && intent == profileWriteIntentGeneration
                && revision == profileWriter.revision && read == installationReadGeneration
                && !isStarting && !profileWriter.isBusy
        }
        do {
            let installed = try await loadManager()
            guard isCurrent() else { return }
            adoptInstalledManager(installed)
            if installationReadError != nil { lastError = "" }
             
             
             
            if let installed {
                noteTunnelState(connectionStatus(installed.connection), on: installed.connection)
            }
        } catch {
            guard isCurrent() else { return }
             
             
             
             
            systemVPNInstallationKnown = false
            vpnAuthorization = nil
            lastError = "The VPN configuration could not be read or saved."
            installationReadError = lastError
        }
    }

    private func adoptInstalledManager(_ installed: NETunnelProviderManager?) {
        let wasInstalled = manager != nil
        manager = installed
        systemVPNInstallationKnown = true
        if installed != nil || wasInstalled { vpnAuthorization = nil }
        updateStatus(installed.map { connectionStatus($0.connection) } ?? .invalid)
    }

    func refresh() async {
        await refreshSystemVPNInstallation()
    }

     

     
     
     
     
    var routingPolicy: VPNRoutingPolicy {
         
         
        VPNRoutingPolicy(tunnel: tunnelSettings.overlaid(by: ModuleDeviceSettingOverlay.load()))
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    @discardableResult
    func updateTunnelSettings(_ settings: VPNTunnelSettings) async -> Bool {
        guard waitForTunnelSettingsSave(settings) else { return true }
        return await saveWaitingTunnelSettings()
    }

     
    func flipTunnelSettings(to settings: VPNTunnelSettings) {
        guard waitForTunnelSettingsSave(settings) else { return }
        Task { await saveWaitingTunnelSettings() }
    }

     
     
     
     
    private func waitForTunnelSettingsSave(_ settings: VPNTunnelSettings) -> Bool {
        waitingTunnelSettings = settings == tunnelSettings ? nil : settings
        guard !tunnelSettingsRunning, waitingTunnelSettings != nil else { return false }
        tunnelSettingsRunning = true
        return true
    }

     
    @discardableResult
    private func saveWaitingTunnelSettings() async -> Bool {
        defer { tunnelSettingsRunning = false }
        var applied = true
        while let next = waitingTunnelSettings {
            let previous = tunnelSettings
             
            tunnelSettings = next
            waitingTunnelSettings = nil
            guard next != previous else { continue }
            next.save(to: preferences)
            if await installForTunnelSettings() {
                tunnelSettingsRefusal = ""
            } else {
                previous.save(to: preferences)
                tunnelSettings = previous
                applied = false
                tunnelSettingsRefusal = lastError
                waitingTunnelSettings = nil
            }
        }
        return applied
    }

     
    private var tunnelSettingsRunning = false
     
     
    @Published private(set) var waitingTunnelSettings: VPNTunnelSettings?
     
    @Published private(set) var tunnelSettingsRefusal = ""



    private func installForTunnelSettings() async -> Bool {


        return await installRoutingPolicy(reconnectIfNeeded: true)
    }

     
     
     
     
     
    private func installRoutingPolicy(reconnectIfNeeded: Bool) async -> Bool {
        do {
            let manager = try await currentOrNewManager()
            guard let tunnelProtocol = manager.protocolConfiguration
                as? NETunnelProviderProtocol
            else {
                fail(NETimeoutError.nePreferencesTimeout)
                return false
            }
            let wanted = routingPolicy
            if self.manager == nil || VPNRoutingPolicy.installed(from: tunnelProtocol) != wanted {
                wanted.apply(to: tunnelProtocol)
                manager.protocolConfiguration = tunnelProtocol
                try await saveToPreferences(manager)
                try await loadFromPreferences(manager)
                self.manager = manager
            }
            lastError = ""
        } catch {
            fail(error)
            return false
        }
        guard reconnectIfNeeded, tunnelIsUp else { return true }
        return await forceRestart()
    }

    @discardableResult
    func start() async -> Bool {
        await start(sinceStop: Self.recoveryStopEpoch ?? stopGeneration, standingOn: Self.standingOnWord)
    }

     
     
     
     
     
     
     
    func start(sinceStop epoch: UInt, standingOn word: StandingWord? = nil) async -> Bool {
        do { try profileWriter.requireStartReady() }
        catch { lastError = error.localizedDescription; return false }
        let cancellation = VPNStartCancellation()
        return await withTaskCancellationHandler {
            await startRequests.run(origin: .programmatic) { [weak self] in
                guard let self, !cancellation.isCancelled else { return false }
                guard self.stopGeneration == epoch else {
                    {
                        let what = "stop"
                        ClashLogStore.shared.append(
                            "start abandoned, a \(what) arrived while it waited its turn",
                            stream: .app, level: .warning)
                    }()
                    return false
                }
                return await self.performStart(cancellation: cancellation, standingOn: word)
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    private func performStart(cancellation: VPNStartCancellation, standingOn word: StandingWord? = nil) async -> Bool {
         
         
        lastReloadNotice = nil
        let userInitiated = nextStartIsUserInitiated
        nextStartIsUserInitiated = false
        profileWriteIntentGeneration &+= 1
        let intent = profileWriteIntentGeneration
        startRequestsInFlight += 1
        var phase = "prepare"
        var needsAuthorization = false
        lastError = ""
        vpnAuthorization = nil
        defer {
            startRequestsInFlight -= 1
            if vpnAuthorization == .waiting { vpnAuthorization = nil }
        }
        func isCurrent() -> Bool {
            intent == profileWriteIntentGeneration && !cancellation.isCancelled
        }
        func checkIntent() throws {
            try Task.checkCancellation()
            guard isCurrent() else { throw CancellationError() }
        }
        do {
            try checkIntent()
            var compileStillRunning = false
            if userInitiated {
                 
                 
                 
                preparingStartSerial &+= 1
                let token = preparingStartSerial
                preparingStarts.insert(token)
                 
                 
                 
                 
                 
                 
                let compileWait = Date()
                var rounds = 0
                repeat {
                    let scheduled = compilationGeneration()
                    guard await compilationBarrier() else { compileStillRunning = true; break }
                    rounds += 1
                    if compilationGeneration() == scheduled { break }
                } while rounds < 3 && isCurrent()
                preparingStarts.remove(token)
                let waited = Int(Date().timeIntervalSince(compileWait) * 1_000)
                if compileStillRunning {
                    ClashLogStore.shared.append(
                        "vpn start went ahead with the rule-set compile still running  waited=+\(waited)ms",
                        stream: .app, level: .warning)
                } else if waited >= 100 {
                    ClashLogStore.shared.append("vpn start waited for the rule-set compile  +\(waited)ms", stream: .app)
                }
                try checkIntent()
            }
            let ipStack = IPStackSettings()
            if let container = ClashMacAppGroupAccess.readableContainer() {
                try await Self.ensureCoreSetupOffMain(container: container, settings: ipStack)
                let scheduled = compilationGeneration()
                try await ProviderFirstLoadRetry.recoverCoreOwnedRoutesBeforeStart(container: container)
                 
                 
                if userInitiated, !compileStillRunning, compilationGeneration() != scheduled {
                    let stageWait = Date()
                    if !(await compilationBarrier()) {
                        let waited = Int(Date().timeIntervalSince(stageWait) * 1_000)
                        ClashLogStore.shared.append(
                            "vpn start went ahead with the rule-set compile still running  waited=+\(waited)ms",
                            stream: .app, level: .warning)
                    }
                    try checkIntent()
                }
            }
            try checkIntent()
            let manager = try await currentOrNewManager()
            try checkIntent()
            needsAuthorization = self.manager == nil
            if needsAuthorization { vpnAuthorization = .waiting }
            let proto = (manager.protocolConfiguration?.copy() as? NETunnelProviderProtocol)
                ?? NETunnelProviderProtocol()
            proto.providerBundleIdentifier = Self.packetTunnelExtensionBundleID
            proto.serverAddress = Self.vpnProfileDescription
            proto.providerConfiguration = try ipStack.applying(to: proto.providerConfiguration)
            routingPolicy.apply(to: proto)
            let policy = routingPolicy
             
             
             
             
            ClashLogStore.shared.append(
                "routing policy: enforceRoutes=\(policy.enforceRoutes) "
                    + "excludeLocalNetworks=\(policy.excludeLocalNetworks) "
                    + "includeAllNetworks=\(policy.includeAllNetworks) "
                    + "excludeAPNs=\(policy.excludeAPNs)",
                stream: .app
            )
            manager.protocolConfiguration = proto
            manager.localizedDescription = Self.vpnProfileDescription
            manager.isEnabled = true
            try Self.armOnDemand(manager, configuration: OnDemandSettings.configuration())
            let frozen = IPStackSystemProfileSnapshot(manager)
            try await VPNStartAuthorization.perform(
                save: { [self] in
                    phase = "save"
                    try await profileWriter.run { [self] in
                        try checkIntent()
                        frozen.apply(to: manager)
                        try await rawSaveToPreferences(manager)
                    }
                },
                reload: { [self] in
                    phase = "reload"
                    try await loadFromPreferences(manager)
                },
                start: { [self] in
                    phase = "start"
                     
                     
                     
                    if let word, !readerWordStands(word) { throw ReaderStoppedSince() }
                    lastStartIssuedAt = Date()
                    lastStartStopEpoch = stopGeneration
                    try manager.connection.startVPNTunnel(
                        options: userInitiated
                            ? [Self.userInitiatedStartOption: NSNumber(value: true)]
                            : nil)
                    awaitingStartTransition = true
                    systemTookStart()
                    adoptInstalledManager(manager)
                    lastError = ""
                },
                abort: { [self] in
                    awaitingStartTransition = false
                    startNoLongerAwaited()
                     
                     
                    await Task { @MainActor in
                        do {
                            try await self.profileWriter.run {
                                if manager.isOnDemandEnabled {
                                    try await self.rawSaveToPreferences(manager, disarmOnly: true)
                                }
                            }
                        } catch {
                            ClashLogStore.shared.append("vpn cancelled-start disarm failed: \(error)",
                                stream: .app, level: .warning)
                        }
                        self.stopTunnel(manager.connection)
                        self.adoptInstalledManager(manager)
                    }.value
                },
                isCurrent: isCurrent,
                onWaiting: { [weak self] in
                    guard isCurrent() else { return }
                    if needsAuthorization { self?.vpnAuthorization = .waiting }
                })
            return true
        } catch is ReaderStoppedSince {
             
            ClashLogStore.shared.append({ let place = "before-system-start"; return "vpn start dropped  at=\(place) reason=readerStopped" }(),
                                        stream: .app, level: .warning)
            return false
        } catch is CancellationError {
            return false
        } catch {
            guard isCurrent(), !Task.isCancelled else { return false }
            presentSystemVPNStartFailure(error, phase: phase, needsAuthorization: needsAuthorization)
            return false
        }
    }

    func presentSystemVPNStartFailure(_ error: Error, phase: String, needsAuthorization: Bool) {
        if needsAuthorization, phase == "save", VPNStartAuthorization.isPermissionDenial(error as NSError) {
            vpnAuthorization = .notCompleted
            lastError = ""
        } else {
            vpnAuthorization = nil
            fail(error)
        }
    }

    func stop() async {
         
         
         
        requestedStops &+= 1
        await stopTheTunnel()
    }

     
    private var requestedStops: UInt = 0

    private func stopTheTunnel() async {
         
         
         
         
         
        lastReloadNotice = nil
        profileWriteIntentGeneration &+= 1
        let writeIntent = profileWriteIntentGeneration
        stopGeneration &+= 1
        preparingStarts = []
        vpnAuthorization = nil
        userStopInFlight = true
        awaitingStartTransition = false
        startNoLongerAwaited()
        if let manager, Self.disarmOnDemandForUserStop(manager) {
             
             
            try? await saveToPreferences(manager, whileIntent: writeIntent, disarmOnly: true)
        }
         
         
         
        if profileWriteIntentGeneration == writeIntent, let manager { stopTunnel(manager.connection) }
        if let status = manager?.connection.status {
            updateStatus(status)
        } else {
            self.status = "disconnected"
        }
    }

     
     
     
    private var stopGeneration: UInt = 0

    @discardableResult
    func forceRestart() async -> Bool {
        let beforeOwnStop = stopGeneration
        await stopTheTunnel()
        let restartGeneration = stopGeneration
         
         
         
        guard restartGeneration == beforeOwnStop &+ 1 else {
            {
                let what = "stop"
                ClashLogStore.shared.append(
                    "restart abandoned, a \(what) arrived while the restart's own stop ran",
                    stream: .app, level: .warning)
            }()
            return false
        }
         
         
         
         
         
         
        var confirmedDown = manager == nil
        for _ in 0..<150 where !confirmedDown {
            guard let connectionStatus = manager?.connection.status else {
                confirmedDown = true
                break
            }
            if connectionStatus == .disconnected
                || connectionStatus == .invalid
            {
                confirmedDown = true
                break
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard confirmedDown else {
            lastError = NETimeoutError.nePreferencesTimeout
                .errorDescription ?? "The tunnel did not finish stopping."
            return false
        }
         
         
         
         
        guard stopGeneration == restartGeneration else {
            {
                let verb = "wound"
                ClashLogStore.shared.append(
                    "restart abandoned, a stop arrived while the tunnel \(verb) down",
                    stream: .app, level: .warning)
            }()
            return false
        }
         
         
        return await start(sinceStop: restartGeneration)
    }

    @discardableResult
     
     
     
     
     
     
     
     
    func resetSystemVPNProfile() async -> Bool {
        guard !systemVPNProfileResetInFlight else { return false }
        systemVPNProfileResetInFlight = true
        defer { systemVPNProfileResetInFlight = false }
        awaitingStartTransition = false
        startNoLongerAwaited()
        do {
            if let manager {
                 
                 
                switch connectionStatus(manager.connection) {
                case .disconnected, .invalid: break
                default: unrequestedStops?.appWillStop(connectedSince: manager.connection.connectedDate)
                }
                try await removeFromPreferences(manager)
                self.manager = nil
            }
            let fresh = try await currentOrNewManager()
            try await saveToPreferences(fresh)
            try await loadFromPreferences(fresh)
            adoptInstalledManager(fresh)
            lastError = ""
            return true
        } catch {
            fail(error)
            return false
        }
    }

     
     
     
     
    private func answerLibraryGone(issuedAt: Date?, sinceStop epoch: UInt) {
        guard let issuedAt, let libraryGoneHandler, stopGeneration == epoch,
              let record = StartupOutcomeRecord.read(from: ClashMacAppGroupAccess.readableContainer()),
              record.answersStart(issuedAt: issuedAt),
              LibraryGoneRepublish.owes(record, answered: nil)
        else { return }
        Task { @MainActor [weak self] in
            await Self.$recoveryStopEpoch.withValue(epoch) {
                await libraryGoneHandler(record) { self?.stopGeneration == epoch }
            }
        }
    }

     
     
     
     
     
     
    private func resolveLastDisconnectError(on connection: NEVPNConnection) async {
        let intent = profileWriteIntentGeneration
        await VPNStartAuthorization.resolveFailure(
            fetch: { [self] in await fetchLastDisconnectError(on: connection) },
            isCurrent: { [self] in
                manager?.connection === connection
                    && profileWriteIntentGeneration == intent
                    && (connection.status == .disconnected || connection.status == .invalid)
            },
            publish: { [self] error in
                if let error {
                     
                     
                     
                    let domain = error.domain
                    let code = error.code
                    ClashLogStore.shared.append(
                        "vpn disconnect error  domain=\(domain) code=\(code)",
                        stream: .app, level: .warning)
                }
                 
                 
                 
                 
                let record = error?.domain == ClashTunnelStart.startErrorDomain ? startupRecord() : nil
                let verdict = MacVPNDisconnectErrorPresentation.verdict(
                    for: error, status: connection.status, record: record, issuedAt: lastStartIssuedAt)
                lastError = verdict.message
                lastErrorOffersVPNProfileReset = verdict.offersVPNProfileReset
                startRefusedByCore = verdict.refusal
            })
    }

     
     
     
     
    private func stopTunnel(_ connection: NEVPNConnection) {
        unrequestedStops?.appWillStop(connectedSince: connection.connectedDate)
        stopsTunnel(connection)
    }

     
     
     
     
     
    func sessionIsEnding() {
        guard let manager else { return }
        unrequestedStops?.appWillStop(connectedSince: manager.connection.connectedDate)
    }

     
     
     
     
     
     
     
    private func noteTunnelState(_ status: NEVPNStatus, on connection: NEVPNConnection) {
        guard let unrequestedStops else { return }
        switch status {
        case .connected, .reasserting:
            let generation: UInt64?
            do {
                generation = try ReaderTunnelIntent.last(in: intentDirectory())?.generation ?? 0
            } catch {
                generation = nil
            }
            unrequestedStops.tunnelIsUp(
                connectedSince: connection.connectedDate, readerWordGeneration: generation)
        case .disconnected, .invalid:
             
             
            let word = unrequestedStops.armed == nil
                ? nil : (try? ReaderTunnelIntent.last(in: intentDirectory())) ?? nil
            guard let ended = unrequestedStops.tunnelIsDown(lastReaderWord: word) else { return }
            let label = status == .invalid ? "invalid" : "disconnected"
            Task { @MainActor [weak self] in
                guard let self else { return }
                let error: NSError?
                if let answer = self.unrequestedStopError {
                    error = await answer(connection)
                } else {
                    error = await self.fetchLastDisconnectError(on: connection)
                }
                self.writeUnrequestedStopLine(VPNUnrequestedStopLog.line(for: ended, status: label, error: error))
            }
        default:
            break
        }
    }

    private func fetchLastDisconnectError(on connection: NEVPNConnection) async -> NSError? {
        await withCheckedContinuation { continuation in
            let gate = MacVPNDisconnectErrorFetchGate(continuation)
            connection.fetchLastDisconnectError { error in
                gate.resolve(error as NSError?)
            }
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                gate.resolve(nil)
            }
        }
    }

     
     
     
     
     
     
    func activationCoordinator(
        store: ConfigResourceStore,
        container: URL,
        compileRuleSetsNow: Bool = false,
        fetchBudget: ProviderFetchBudget = .activation
    ) throws -> ProfileActivationCoordinator {
         
         
         
         
        let working = container.appendingPathComponent(
            "working",
            isDirectory: true
        )
        return ProfileActivationCoordinator(
            store: store,
            profileStore: ProfileStore(
                fileURL: working.appendingPathComponent("store/profiles.json")
            ),
            credentials: CredentialStore(),
            downloader: ResourceDownloader(),
            coreHomeDir: working,
             
             
             
             
             
             
             
             
            compileRuleSets: true,
             
             
             
             
             
             
            deferRuleSetCompilation: !compileRuleSetsNow,
            activationFetchBudget: fetchBudget,
            runtimeOverride: { [preferences] in
                FlClashRuntimeConfig.load(from: preferences)
            },
             
             
             
             
            logDefaults: preferences,
            activator: { _ in },
             
             
             
             
            intentContainer: container,
            prepareCore: { try AppCoreSetup.ensure(container: container) }
        )
    }

     
     
     
     
    func migrateLegacyGlobalSettingsIfNeeded()
        -> LegacyClientSettingsMigrationResult
    {
         
         
         
         
         
         
        guard let container = ClashMacAppGroupAccess.readableContainer() else {
            return .init(
                globalConfig: .blocked(.storageUnavailable),
                globalScript: nil
            )
        }
        do { try Self.ensureCoreSetup(container: container) }
        catch {
            lastError = error.localizedDescription
            return .init(globalConfig: .blocked(.coreSetupFailed(error.localizedDescription)), globalScript: nil)
        }
        let working = container.appendingPathComponent(
            "working",
            isDirectory: true
        )
        let globalConfig = LegacyGlobalConfigMigrationCoordinator.run(
            workingDirectory: working,
            defaults: preferences
        )
        guard globalConfig.userMessage.isEmpty else {
            return .init(globalConfig: globalConfig, globalScript: nil)
        }
        return .init(
            globalConfig: globalConfig,
            globalScript: LegacyGlobalScriptMigrationCoordinator.run(
                workingDirectory: working,
                defaults: preferences
            )
        )
    }

     
     
     
     
     
    var intentStampDefaults: UserDefaults = GlobalConfig.appGroupDefaults

     
     
     
     
     
     
     
     
     
     
     
     
     
    @discardableResult
    func applyActiveConfiguration(
        nextIntent intent: PlatformConfigIntent,
        startsWhenDown: Bool = true,
        publishedAs expected: ActiveConfigurationPointer? = nil
    ) async -> TunnelApplyOutcome {
         
         
         
        let stops = requestedStops
        let outcome = await handOver((intent, expected), forProfile: expected?.profileID,
                              startsWhenDown: startsWhenDown, stopsWhenAsked: stops) ?? .savedForNext
        Self.announceIfRunning(outcome)
        return outcome
    }

     
     
     
     
     
     
     
     
     
    private func handOver(_ first: (intent: PlatformConfigIntent, expected: ActiveConfigurationPointer?)?,
                          forProfile profileID: String?, startsWhenDown: Bool, stopsWhenAsked: UInt) async -> TunnelApplyOutcome? {
        var next = first, profileID = profileID
        while true {
            await applications.acquire()
            defer { applications.release() }
            guard requestedStops == stopsWhenAsked else { return .savedForNext }
            if next == nil {
                guard let published = await HandoverRevision.publishedNow(container: ClashMacAppGroupAccess.readableContainer()),
                      PublishedRuntimeHandover.hands(published.pointer, forProfile: profileID) else { return nil }
                next = (published.intent, published.pointer)
            }
            guard let (intent, expected) = next else { return nil }
            if let outcome = await applyFollowingPublications(intent, publishedAs: expected,
                                                              startsWhenDown: startsWhenDown, stopsWhenAsked: stopsWhenAsked) {
                return outcome
            }
            next = nil
            profileID = expected?.profileID
        }
    }

     
    private let applications = TunnelApplicationGate()



     
     
     
     
     
     
    @discardableResult
    func applyPublished(forProfile profileID: String?, startsWhenDown: Bool) async -> TunnelApplyOutcome? {
        let stops = requestedStops
        let outcome = await handOver(nil, forProfile: profileID, startsWhenDown: startsWhenDown, stopsWhenAsked: stops)
        Self.announceIfRunning(outcome)
        return outcome
    }

     
     
     
     
     
     
    private static func announceIfRunning(_ outcome: TunnelApplyOutcome?) {
        guard outcome?.tunnelRunsTheNewConfiguration == true else { return }
        NotificationCenter.default.post(name: .clashProviderContentChanged, object: nil)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private func applyFollowingPublications(
        _ intent: PlatformConfigIntent, publishedAs expected: ActiveConfigurationPointer?,
        startsWhenDown: Bool, stopsWhenAsked: UInt
    ) async -> TunnelApplyOutcome? {
        var intent = intent, expected = expected
        for _ in 0..<3 {
            if let outcome = await applyActiveConfigurationHoldingTheGate(
                nextIntent: intent, startsWhenDown: startsWhenDown, stopsWhenAsked: stopsWhenAsked,
                expected: expected) {
                return outcome
            }
            guard let before = expected,
                  let published = await HandoverRevision.publishedNow(container: ClashMacAppGroupAccess.readableContainer()),
                  published.pointer.profileID == before.profileID else { return .savedForNext }
            intent = published.intent
            expected = published.pointer
        }
        return nil
    }

     
     
     
     
     
     
    private func applyActiveConfigurationHoldingTheGate(
        nextIntent intent: PlatformConfigIntent,
        startsWhenDown: Bool,
        stopsWhenAsked: UInt,
        expected: ActiveConfigurationPointer?
    ) async -> TunnelApplyOutcome? {
        let container = ClashMacAppGroupAccess.readableContainer()
        func overtaken() -> Bool { HandoverRevision.superseded(expected, container: container) }
        if overtaken() { return nil }
        let tunnelUp: Bool
        switch manager?.connection.status {
        case .connected, .connecting, .reasserting: tunnelUp = true
        default: tunnelUp = false
        }
        if appliedConfigIntent == nil, tunnelUp,
           let stampJSON = TunnelIntentStamp.readJSON(
               from: intentStampDefaults
           ),
           let recovered = try? JSONDecoder().decode(
               PlatformConfigIntent.self, from: Data(stampJSON.utf8)
           ) {
            appliedConfigIntent = recovered
        }
        let decision = ActivationDecision.decide(
            current: appliedConfigIntent, next: intent, tunnelUp: tunnelUp
        )
         
         
         
        if decision == .start, !startsWhenDown { return .savedForNext }
         
         
        guard requestedStops == stopsWhenAsked else { return .savedForNext }
         
         
         
         
        let applyEpoch = stopGeneration
         
         
        defer { NotificationCenter.default.post(name: .clashTunnelOutcomeRecorded, object: nil) }
        let outcome: TunnelApplyOutcome
         
         
        var settledByTheExtension = false
        switch decision {
        case .start:
            let issued = Date()
             
             
            let stopAtStart = stopGeneration
            if await start(sinceStop: stopAtStart) {
                outcome = await settleStart(issuedAt: issued, since: stopAtStart, success: .applied(warning: nil))
                settledByTheExtension = true
            } else {
                 
                outcome = stopGeneration == stopAtStart ? .failed(lastErrorReason) : .savedForNext
            }
        case .reload:
             
             
             
             
             
             
             
            await awaitConnectedBeforeReload()
             
             
             
             
             
             
            guard tunnelIsUp else {
                {
                    let verb = "waited"
                    ClashLogStore.shared.append(
                        "reload skipped, tunnel went down while it \(verb)",
                        stream: .app, level: .warning)
                }()
                outcome = .savedForNext
                break
            }
            if overtaken() { return nil }
             
             
             
             
             
            if session?.status == .connected, let record = HandoverRevision.running(expected, container: container),
               !ModuleEngineReadinessSource.takesOwedReload(of: expected, container: container) {
                lastError = ""
                appliedConfigIntent = intent
                return .applied(warning: record.warningForRunning)
            }
            var reply = await sendReloadMessage()
             
             
             
             
             
             
            var attemptsLeft = 3
            while attemptsLeft > 0, reloadIsWorthRetrying(reply) {
                attemptsLeft -= 1
                ClashLogStore.shared.append(
                    "reload raced activation, retrying  reason=\(reply.reason)",
                    stream: .app, level: .warning)
                 
                 
                 
                 
                 
                await awaitConnectedBeforeReload(ticks: 50)
                try? await Task.sleep(nanoseconds: 400_000_000)
                if overtaken() { return nil }
                reply = await sendReloadMessage()
            }
            switch reply {
            case .reloaded(let warning):
                lastError = ""
                noteReloadLanded(warning: warning)
                outcome = .applied(warning: warning)
            case .notSent(let why):
                 
                 
                 
                 
                 
                switch manager?.connection.status {
                case .connected:
                     
                     
                     
                     
                    if overtaken() { return nil }
                    switch await sendReloadMessage() {
                    case .reloaded(let warning):
                        lastError = ""
                        noteReloadLanded(warning: warning)
                        outcome = .applied(warning: warning)
                    case .refused(let answered, .committed):
                        lastError = ""
                        noteReloadLanded(warning: answered)
                        outcome = .applied(warning: answered)
                    case .refused(let answered, .config):
                        keepRunning(refusedBecause: answered, .config)
                        outcome = .keptRunning(answered)
                    case .refused(let answered, _):
                         
                         
                        guard session?.status == .connected else {
                            ClashLogStore.shared.append(
                                "reload skipped, tunnel went down after refusing  reason=\(answered)",
                                stream: .app, level: .warning)
                            outcome = .savedForNext
                            break
                        }
                        if overtaken() { return nil }
                        ClashLogStore.shared.append(
                            "reload refused after reconnect, restarting  reason=\(answered)",
                            stream: .app, level: .warning)
                        outcome = await restartOutcome(since: applyEpoch)
                        settledByTheExtension = true
                    case .notSent(let again):
                        ClashLogStore.shared.append(
                            "reload skipped, session flapping  reason=\(again)",
                            stream: .app, level: .warning)
                         
                         
                        outcome = .savedForNext
                    }
                case .connecting, .reasserting:
                     
                     
                     
                     
                    if overtaken() { return nil }
                    ClashLogStore.shared.append(
                        "reload not delivered, tunnel stuck in transition, restarting  reason=\(why)",
                        stream: .app, level: .warning)
                    outcome = await restartOutcome(since: applyEpoch)
                    settledByTheExtension = true
                default:
                     
                     
                     
                     
                    ClashLogStore.shared.append(
                        "reload skipped, tunnel went down  reason=\(why)",
                        stream: .app, level: .warning)
                    outcome = .savedForNext
                }
            case .refused(let why, .committed):
                 
                 
                lastError = ""
                noteReloadLanded(warning: why)
                outcome = .applied(warning: why)
            case .refused(let why, .config):
                 
                 
                 
                 
                keepRunning(refusedBecause: why, .config)
                outcome = .keptRunning(why)
            case .refused(let why, _):
                 
                 
                 
                guard session?.status == .connected else {
                    ClashLogStore.shared.append(
                        "reload skipped, tunnel went down after refusing  reason=\(why)",
                        stream: .app, level: .warning)
                    outcome = .savedForNext
                    break
                }
                 
                 
                 
                if overtaken() { return nil }
                ClashLogStore.shared.append(
                    "reload refused, restarting  reason=\(why)",
                    stream: .app, level: .warning)
                outcome = await restartOutcome(since: applyEpoch)
                settledByTheExtension = true
            }
        case .restart:
             
             
             
             
             
             
             
             
             
             
             
             
            let stopAtEntry = stopGeneration
            await awaitConnectedBeforeReload()
            if overtaken() { return nil }
            let answer: ReloadReply? = session?.status == .connected ? await sendReloadMessage() : nil
            let stillUp: Bool
            switch manager?.connection.status {
            case .connected, .connecting, .reasserting: stillUp = true
            default: stillUp = false
            }
            if case .refused(let why, .config)? = answer {
                keepRunning(refusedBecause: why, .config)
                outcome = .keptRunning(why)
            } else if stopGeneration != stopAtEntry || !stillUp {
                {
                    let what = "settings"
                    ClashLogStore.shared.append(
                        "restart skipped, the tunnel was stopped while the new \(what) were asked about",
                        stream: .app, level: .warning)
                }()
                outcome = .savedForNext
            } else if overtaken() {
                 
                 
                 
                 
                return nil
            } else {
                outcome = await restartOutcome(since: applyEpoch)
                settledByTheExtension = true
            }
        }
        if !settledByTheExtension, outcome.tunnelRunsTheNewConfiguration {
             
             
             
            appliedConfigIntent = HandoverRevision.acknowledged(expected, container: container) ? intent : nil
        }
        return outcome
    }

    private func restartOutcome(since epoch: UInt) async -> TunnelApplyOutcome {
        let issued = Date()
        guard stopGeneration == epoch else {
            {
                let what = "reload"
                ClashLogStore.shared.append(
                    "restart skipped, the tunnel was stopped while the \(what) was asked",
                    stream: .app, level: .warning)
            }()
            return .savedForNext
        }
        guard await forceRestart() else {
             
             
            return stopGeneration == epoch &+ 1 ? .failed(lastErrorReason) : .savedForNext
        }
         
         
        return await settleStart(issuedAt: issued, since: epoch &+ 1, success: .restarted)
    }

     
     
     
     
     
     
     
    private func settleStart(issuedAt: Date, since stopEpoch: UInt,
                             success: TunnelApplyOutcome) async -> TunnelApplyOutcome {
         
         
        var ticks = 0
        while ticks < 300 {
            let status = manager?.connection.status
            let settling = status == .connecting || status == .reasserting
                || (ticks < 20 && (status == .disconnected || status == nil))
            guard settling, !Task.isCancelled, stopGeneration == stopEpoch else { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
            ticks += 1
        }
         
        guard stopGeneration == stopEpoch else {
            appliedConfigIntent = nil
            return .savedForNext
        }
        let status = manager?.connection.status
        if status == .connecting || status == .reasserting || Task.isCancelled {
             
             
             
             
            appliedConfigIntent = nil
            return .pending
        }
        let connected = status == .connected
        appliedConfigIntent = connected
            ? TunnelIntentStamp.readJSON(from: intentStampDefaults).flatMap {
                try? JSONDecoder().decode(PlatformConfigIntent.self, from: Data($0.utf8))
            }
            : nil
        if !connected { answerLibraryGone(issuedAt: issuedAt, sinceStop: stopEpoch) }
        guard let settled = StartupOutcomeRecord.settlement(
            of: StartupOutcomeRecord.read(from: ClashMacAppGroupAccess.readableContainer()),
            issuedAt: issuedAt, connected: connected, fallbackReason: lastErrorReason) else {
            return success
        }
        if case .keptRunning(let reason) = settled {
            ClashLogStore.shared.append(
                "start fell back to the last configuration that ran  reason=\(reason)",
                stream: .app, level: .warning)
        }
        return settled
    }

    private func keepRunning(refusedBecause why: String, _ errorClass: ReloadErrorClass) {
        ClashLogStore.shared.append(
            "reload refused, running configuration kept  class=\(errorClass.rawValue) reason=\(why)",
            stream: .app, level: .warning)
        lastReloadNotice = ReloadNotice(errorClass: errorClass, message: why)
    }

    private func noteReloadLanded(warning: String?) {
        guard let warning else {
            lastReloadNotice = nil
            return
        }
        ClashLogStore.shared.append(
            "reload applied with a warning  reason=\(warning)",
            stream: .app, level: .warning)
        lastReloadNotice = ReloadNotice(errorClass: .committed, message: warning)
    }

     
     
     
    private func awaitConnectedBeforeReload(ticks: Int = 100) async {
        for _ in 0..<ticks {
            switch manager?.connection.status {
            case .connecting, .reasserting:
                try? await Task.sleep(nanoseconds: 100_000_000)
            default:
                return
            }
        }
    }

     
     
     
    private var tunnelIsUp: Bool {
        switch manager?.connection.status {
        case .connected, .connecting, .reasserting: return true
        default: return false
        }
    }

     
     
     
     
     
     
     
     
     
     
    private func reloadIsWorthRetrying(_ reply: ReloadReply) -> Bool {
        switch reply {
        case .reloaded:
            return false
        case .notSent:
            switch manager?.connection.status {
            case .connecting, .reasserting: return true
            default: return false
            }
        case .refused(let why, _):
            return manager?.connection.status == .connected
                && ReloadRefusal.isRaceWithActivation(why)
        }
    }

     
     
     
     
     
    private enum ReloadReply: Equatable {
         
         
        case reloaded(warning: String?)
         
         
         
        case notSent(String)
         
         
         
         
         
         
         
        case refused(String, ReloadErrorClass)

        var reason: String {
            switch self {
            case .reloaded: return "reloaded"
            case .notSent(let why), .refused(let why, _): return why
            }
        }
    }

     
     
     
     
     
     
     
     
     
     
    private func sendReloadMessage() async -> ReloadReply {
        guard let session, session.status == .connected else {
             
             
             
             
            return .notSent({ let what = "not connected"; return "session \(what)" }())
        }
        guard let payload = try? JSONSerialization.data(
            withJSONObject: ["cmd": "reload"]
        ) else {
            return .notSent({ let verb = "encoded"; return "reload payload could not be \(verb)" }())
        }
        do {
            return try await Self.withNETimeout(
                seconds: 20, .extensionMessageTimeout
            ) {
                try await withCheckedThrowingContinuation { continuation in
                    do {
                        try session.sendProviderMessage(payload) { reply in
                            guard let reply,
                                  let json = try? JSONSerialization
                                      .jsonObject(with: reply)
                                      as? [String: Any]
                            else {
                                 
                                 
                                 
                                continuation.resume(
                                    returning: .refused({ let why = "silent"; return "the extension replied \(why)" }(), .unknown)
                                )
                                return
                            }
                            if let error = json["error"] as? String {
                                 
                                 
                                 
                                 
                                 
                                continuation.resume(returning: .refused(
                                    error, ReloadErrorClass.of(reply: json) ?? .unknown))
                                return
                            }
                            continuation.resume(returning: .reloaded(
                                warning: ReloadErrorClass.of(reply: json) == .committed
                                    ? (json["warning"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                                    : nil))
                        }
                    } catch {
                         
                         
                         
                         
                        continuation.resume(
                            returning: .notSent(error.localizedDescription)
                        )
                    }
                }
            }
        } catch {
             
             
            return .refused({ let why = "unanswered"; return "the extension went \(why) for 20s" }(), .unknown)
        }
    }

    func applyOnDemandSettingsReportingOutcome() async
        -> OnDemandSaveOutcome
    {
        do {
            let manager = try await currentOrNewManager()
            try Self.armOnDemand(
                manager,
                configuration: OnDemandSettings.configuration()
            )
            try await saveToPreferences(manager)
            self.manager = manager
            lastError = ""
            return .applied
        } catch let error as OnDemandValidationError {
             
            fail(error)
            return .refused(lastError)
        } catch {
             
             
             
             
            fail(error)
            return .indeterminate(lastError)
        }
    }

    nonisolated static func withNETimeout<T: Sendable>(
        seconds: Double,
        _ timeoutError: NETimeoutError,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<T, Error>) in
            let gate = ClashMacNETimeoutGate(continuation)
            let timeout = Task {
                try? await Task.sleep(for: .seconds(seconds))
                gate.resume(throwing: timeoutError)
            }
            Task {
                defer { timeout.cancel() }
                do {
                    gate.resume(returning: try await operation())
                } catch {
                    gate.resume(throwing: error)
                }
            }
        }
    }

    func currentOrNewManager() async throws
        -> NETunnelProviderManager
    {
        let intent = profileWriteIntentGeneration
        let saved: NETunnelProviderManager?
        do { saved = try await loadManager() }
        catch {
            guard intent == profileWriteIntentGeneration, !Task.isCancelled else { throw CancellationError() }
            systemVPNInstallationKnown = false
            throw error
        }
        try Task.checkCancellation()
        guard intent == profileWriteIntentGeneration else { throw CancellationError() }
        adoptInstalledManager(saved)
        if let saved { return saved }

        let created = NETunnelProviderManager()
        let tunnelProtocol = NETunnelProviderProtocol()
        tunnelProtocol.providerBundleIdentifier =
            Self.packetTunnelExtensionBundleID
        tunnelProtocol.serverAddress = Self.vpnProfileDescription
        routingPolicy.apply(to: tunnelProtocol)
         
         
         
        tunnelProtocol.disconnectOnSleep =
            OnDemandSettings.configuration().disconnectOnSleep
        tunnelProtocol.providerConfiguration = try IPStackSettings()
            .applying(to: tunnelProtocol.providerConfiguration)
        created.protocolConfiguration = tunnelProtocol
        created.localizedDescription = Self.vpnProfileDescription
        created.isEnabled = true
        return created
    }

    private static func loadSystemManagers() async throws -> [NETunnelProviderManager] {
        let result = await withCheckedContinuation {
            (continuation:
                CheckedContinuation<ClashMacManagerLoadResult, Never>) in
            NETunnelProviderManager.loadAllFromPreferences {
                managers,
                error in
                continuation.resume(
                    returning: ClashMacManagerLoadResult(managers, error)
                )
            }
        }
        if let error = result.error { throw error }
        return result.managers
    }

    private func loadManager() async throws -> NETunnelProviderManager? {
        let managers = try await Self.withNETimeout(seconds: preferencesReadTimeout, .nePreferencesTimeout) { [self] in
            try await systemVPNManagers()
        }
        return managers.first {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?
                .providerBundleIdentifier
                == Self.packetTunnelExtensionBundleID
        }
    }

    private func saveToPreferences(_ manager: NETunnelProviderManager, whileIntent intent: UInt64? = nil, disarmOnly: Bool = false) async throws {
        let frozen = IPStackSystemProfileSnapshot(manager)
        try await profileWriter.run { [self] in
            if let intent, intent != profileWriteIntentGeneration { throw CancellationError() }
            frozen.apply(to: manager)
            try await rawSaveToPreferences(manager, disarmOnly: disarmOnly)
        }
    }

    private func rawSaveToPreferences(
        _ manager: NETunnelProviderManager, disarmOnly: Bool = false
    ) async throws {
        let frozen = IPStackSystemProfileSnapshot(manager)
        try await profileWriter.saveConfirmed(frozen, to: manager, disarmOnly: disarmOnly) {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                manager.saveToPreferences { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }

    private func loadFromPreferences(_ manager: NETunnelProviderManager) async throws {
        try await Self.withNETimeout(seconds: preferencesReadTimeout, .nePreferencesTimeout) {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                manager.loadFromPreferences { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            }
        }
    }

    private func removeFromPreferences(
        _ manager: NETunnelProviderManager
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            manager.removeFromPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }



    private func updateStatus(_ status: NEVPNStatus) {
         
        systemSaid(status)
        switch status {
        case .invalid, .disconnected: self.status = "disconnected"
        case .connecting: self.status = "connecting"
         
         
         
         
         
        case .reasserting: self.status = "reasserting"
        case .connected: self.status = "connected"
        case .disconnecting: self.status = "disconnecting"
        @unknown default: self.status = "unavailable"
        }
    }

    private func fail(_: Error) {
        status = "unavailable"
        lastError = "The VPN configuration could not be read or saved."
    }

    func prepareCoreForUIReview(container: URL) {
        do { try Self.ensureCoreSetup(container: container) }
        catch { lastError = error.localizedDescription }
    }

    static func ensureCoreSetup(container: URL, settings: IPStackSettings? = nil) throws {
        try AppCoreSetup.ensure(container: container, settings: settings)
    }

     
     
     
     
     
    nonisolated static func ensureCoreSetupOffMain(
        container: URL, settings: IPStackSettings? = nil
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            try AppCoreSetup.ensure(container: container, settings: settings)
        }.value
    }
}
