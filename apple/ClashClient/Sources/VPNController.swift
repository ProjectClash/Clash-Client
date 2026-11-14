import Combine
import Foundation
import Clash
import ClashClientUI
import NetworkExtension

 
 
 
 
 
 
enum NETimeoutError: LocalizedError, Equatable {
     
    case nePreferencesTimeout
     
    case extensionMessageTimeout

    var errorDescription: String? {
        switch self {
        case .nePreferencesTimeout, .extensionMessageTimeout:
            return "The system VPN service isn’t responding. Please try again in a moment, or restart your device."
        }
    }
}

enum VPNDisconnectErrorPresentation {
    static let noNetworkMessage =
        "No network is available. Restore Wi-Fi or cellular data and try again."
    static let genericStartFailureMessage =
        "The VPN could not start. Check the configuration and try again."
    static let genericDisconnectMessage =
        "The VPN disconnected because the system reported an error."
    static let providerDisconnectMessage =
        "The VPN disconnected because the tunnel provider reported an error."
    static let genericReportMessage =
        "The VPN operation failed. Review the app and system status for details."
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static let providerNotLaunchedMessage =
        "Connection failed. Tap to reinstall VPN profile."

     
    static func isProviderNotLaunched(_ reportMessage: String) -> Bool {
        reportMessage == providerNotLaunchedMessage
    }

    private static let connectionMessages: [Int: String] = [
        1: "The VPN disconnected after the device slept for an extended period.",
        2: noNetworkMessage,
        3: "The VPN disconnected after an unrecoverable network change.",
        4: "The VPN could not connect because its configuration is invalid.",
        5: "The VPN server address could not be resolved.",
        6: "The VPN server did not respond.",
        7: "The VPN server is unavailable.",
        8: "VPN authentication failed.",
        9: "The VPN client certificate is invalid.",
        10: "The VPN client certificate is not valid yet.",
        11: "The VPN client certificate has expired.",
        12: "The VPN tunnel provider stopped unexpectedly.",
        13: "The VPN configuration could not be found.",
        14: "The VPN tunnel provider is unavailable or needs an update.",
        15: "VPN protocol negotiation failed.",
        16: "The VPN server disconnected.",
        17: "The VPN server certificate is invalid.",
        18: "The VPN server certificate is not valid yet.",
        19: "The VPN server certificate has expired.",
    ]

    private static let configurationMessages: [Int: String] = [
        1: "The VPN configuration is invalid.",
        2: "The VPN configuration is disabled.",
        3: "The VPN connection failed.",
        4: "The VPN configuration is stale. Reload it and try again.",
        5: "The VPN configuration could not be read or saved.",
        6: "The VPN configuration failed for an unknown reason.",
    ]

    private static let safeReportMessages: Set<String> = Set(
        Array(connectionMessages.values)
            + Array(configurationMessages.values)
            + [
                genericStartFailureMessage,
                genericDisconnectMessage,
                providerDisconnectMessage,
                genericReportMessage,
                providerNotLaunchedMessage,
            ]
            + [OnDemandStartRefusal.certainMessage]
    )

    static func message(for error: NSError) -> String {
        message(for: error, providerLooksUnlaunched: false)
    }

     
     
     
    static func message(for error: NSError, providerLooksUnlaunched: Bool) -> String {
        if #available(iOS 16.0, *), error.domain == NEVPNConnectionErrorDomain {
            if error.code == 12, providerLooksUnlaunched { return providerNotLaunchedMessage }
            return connectionMessages[error.code] ?? genericDisconnectMessage
        }
        if error.domain == NEVPNErrorDomain {
            return configurationMessages[error.code] ?? genericDisconnectMessage
        }
        return providerDisconnectMessage
    }

    static func startMessage(for error: NSError) -> String {
        if error.domain == NEVPNErrorDomain {
            return configurationMessages[error.code] ?? genericStartFailureMessage
        }
        return genericStartFailureMessage
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func reportMessage(_ message: String) -> String {
        guard !message.isEmpty else { return "" }
        if safeReportMessages.contains(message) { return message }
        return String(message.prefix(512))
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func isProviderStoppedUnexpectedly(_ reportMessage: String) -> Bool {
        reportMessage == connectionMessages[12]
    }

    static func allowsSystemVPNProfileReset(for error: NSError) -> Bool {
        if #available(iOS 16.0, *), error.domain == NEVPNConnectionErrorDomain {
            return error.code == 4 || error.code == 13
        }
        if error.domain == NEVPNErrorDomain {
            return [1, 2, 4, 5, 6].contains(error.code)
        }
        return false
    }

    static func allowsSystemVPNProfileReset(forReportMessage message: String) -> Bool {
        let resettableMessages = Set(
            [connectionMessages[4], connectionMessages[13], providerNotLaunchedMessage]
                .compactMap { $0 }
                + [1, 2, 4, 5, 6].compactMap { configurationMessages[$0] }
        )
        return resettableMessages.contains(message)
    }
}

private final class VPNDisconnectErrorFetchGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<NSError?, Never>?

    init(_ continuation: CheckedContinuation<NSError?, Never>) {
        self.continuation = continuation
    }

    func resolve(_ error: NSError?) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: error)
    }
}

 
 
 
 
private final class NETimeoutGate<T>: @unchecked Sendable {
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

 
 
 
 
 
 
 
struct VPNTunnelSettings: Equatable {
    var enforceRoutes = false
    var includeAllNetworks = false
    var includeLocalNetworks = false
    var includeAPNs = false
    var includeCellularServices = false
     
     
     
     
     
     
     
    var hideVPNIcon = false
    var homeKitCompatibility = false
     
     
     
     
    var excludeAPNsRoute = false

    enum Key {
        static let enforceRoutes = "vpn.tunnel.enforceRoutes"
        static let includeAllNetworks = "vpn.tunnel.includeAllNetworks"
        static let includeLocalNetworks = "vpn.tunnel.includeLocalNetworks"
        static let includeAPNs = "vpn.tunnel.includeAPNs"
        static let includeCellularServices = "vpn.tunnel.includeCellularServices"
        static let hideVPNIcon = "vpn.tunnel.hideVPNIcon"
        static let homeKitCompatibility = "vpn.tunnel.homeKitCompatibility"
        static let excludeAPNsRoute = "vpn.tunnel.excludeAPNsRoute"
    }

    static func load(from defaults: UserDefaults) -> Self {
        VPNTunnelSettings(
            enforceRoutes: defaults.bool(forKey: Key.enforceRoutes),
            includeAllNetworks: defaults.bool(forKey: Key.includeAllNetworks),
            includeLocalNetworks: defaults.bool(forKey: Key.includeLocalNetworks),
            includeAPNs: defaults.bool(forKey: Key.includeAPNs),
            includeCellularServices: defaults.bool(forKey: Key.includeCellularServices),
            hideVPNIcon: defaults.bool(forKey: Key.hideVPNIcon),
            homeKitCompatibility: defaults.bool(forKey: Key.homeKitCompatibility),
            excludeAPNsRoute: defaults.bool(forKey: Key.excludeAPNsRoute)
        )
    }

    func save(to defaults: UserDefaults) {
        defaults.set(enforceRoutes, forKey: Key.enforceRoutes)
        defaults.set(includeAllNetworks, forKey: Key.includeAllNetworks)
        defaults.set(includeLocalNetworks, forKey: Key.includeLocalNetworks)
        defaults.set(includeAPNs, forKey: Key.includeAPNs)
        defaults.set(includeCellularServices, forKey: Key.includeCellularServices)
        defaults.set(hideVPNIcon, forKey: Key.hideVPNIcon)
        defaults.set(homeKitCompatibility, forKey: Key.homeKitCompatibility)
        defaults.set(excludeAPNsRoute, forKey: Key.excludeAPNsRoute)
    }
}

 
 
 
 
struct VPNRoutingPolicy: Equatable {
    let includeAllNetworks: Bool
    let excludeLocalNetworks: Bool
    let enforceRoutes: Bool
    let excludeCellularServices: Bool
    let excludeAPNs: Bool
    let excludeDeviceCommunication: Bool

    init(
        tunnel: VPNTunnelSettings = VPNTunnelSettings(),
        preserveDevelopmentDeviceCommunication: Bool = Self.defaultDevelopmentDeviceCommunication
    ) {
        includeAllNetworks = tunnel.includeAllNetworks
        excludeLocalNetworks = !tunnel.includeLocalNetworks
         
         
         
         
         
        enforceRoutes = tunnel.enforceRoutes
        excludeCellularServices = !tunnel.includeCellularServices
        excludeAPNs = !tunnel.includeAPNs
         
         
         
         
         
        excludeDeviceCommunication = includeAllNetworks
            || (enforceRoutes && preserveDevelopmentDeviceCommunication)
    }

    private init(
        includeAllNetworks: Bool,
        excludeLocalNetworks: Bool,
        enforceRoutes: Bool,
        excludeCellularServices: Bool,
        excludeAPNs: Bool,
        excludeDeviceCommunication: Bool
    ) {
        self.includeAllNetworks = includeAllNetworks
        self.excludeLocalNetworks = excludeLocalNetworks
        self.enforceRoutes = enforceRoutes
        self.excludeCellularServices = excludeCellularServices
        self.excludeAPNs = excludeAPNs
        self.excludeDeviceCommunication = excludeDeviceCommunication
    }

    private static let defaultDevelopmentDeviceCommunication = false


    func apply(to tunnelProtocol: NETunnelProviderProtocol) {
        tunnelProtocol.includeAllNetworks = includeAllNetworks
         
         
         
        tunnelProtocol.excludeLocalNetworks = excludeLocalNetworks
        tunnelProtocol.enforceRoutes = enforceRoutes
        if #available(iOS 16.4, *) {
            tunnelProtocol.excludeCellularServices = excludeCellularServices
            tunnelProtocol.excludeAPNs = excludeAPNs
        }
        if #available(iOS 17.4, *) {
            tunnelProtocol.excludeDeviceCommunication = excludeDeviceCommunication
        }
    }

    static func installed(from tunnelProtocol: NETunnelProviderProtocol) -> Self {
        var excludeCellularServices = false
        var excludeAPNs = false
        var excludeDeviceCommunication = false
        if #available(iOS 16.4, *) {
            excludeCellularServices = tunnelProtocol.excludeCellularServices
            excludeAPNs = tunnelProtocol.excludeAPNs
        }
        if #available(iOS 17.4, *) {
            excludeDeviceCommunication = tunnelProtocol.excludeDeviceCommunication
        }
        return Self(
            includeAllNetworks: tunnelProtocol.includeAllNetworks,
            excludeLocalNetworks: tunnelProtocol.excludeLocalNetworks,
            enforceRoutes: tunnelProtocol.enforceRoutes,
            excludeCellularServices: excludeCellularServices,
            excludeAPNs: excludeAPNs,
            excludeDeviceCommunication: excludeDeviceCommunication
        )
    }
}

 
 

enum AppConfigurationPreflight {
    static func inspectRoutingIntent(
        _ configContent: String, container: URL? = nil, settings: IPStackSettings? = nil
    ) throws -> PlatformConfigIntent {
        guard let container = container ?? AppCoreSetup.applicationContainer else {
            throw NSError(domain: "ClashClient.Configuration", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "App Group container unavailable"])
        }
        return try AppCoreSetup.withConfiguration(container: container, settings: settings) {
            var error: NSError?
            guard let box = AppCore.platformConfigIntentJSON(configContent, &error) else {
                throw error ?? NSError(domain: "ClashClient.Configuration", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Unable to inspect configuration routing intent"])
            }
            return try JSONDecoder().decode(PlatformConfigIntent.self, from: Data(box.value.utf8))
        }
    }

}

 
 
 
@MainActor
 
 
 
enum VPNStopSite: String {
    case userButton = "user-stop-button"
    case intentRestart = "intent-restart"
    case forceRestart = "force-restart"
    case reloadFallback = "reload-fallback"
    case selfTest = "self-test"
}

@MainActor
final class VPNController: ObservableObject {
     
     
    private(set) lazy var tunnelSettingsApplying = TunnelSettingsApplying(vpn: self)
     
     
     
     
     
     
     
     
    static let vpnProfileTitle = "Clash"

     
     
    static let vpnProfileDescription = "Clash"

    @Published var status: String = "idle"
     
     
     
     
     
     
    @Published private(set) var hasLoadedStatus = false
    @Published var lastError: String = "" {
        didSet {
            installationReadError = nil
             
             
             
             
            if startRefusedByOnDemand != nil { startRefusedByOnDemand = nil }
            if startRefusedByCore != nil { startRefusedByCore = nil }
        }
    }
     
     
     
     
     
     
     
     
     
     
     
    @Published private(set) var startRefusedByOnDemand: OnDemandStartRefusal?
     
     
     
     
    @Published private(set) var startRefusedByCore: CoreStartRefusal?
     
    private var installationReadError: String?
    @Published private(set) var configurationNotice: String = ""
     
     
    var publicationBarrier: (@MainActor () async -> Void)?
     
     
     
     
     
     
    var compilationBarrier: @MainActor () async -> Bool = {
        await ProfileActivationCoordinator.drainDeferredCompilation()
    }
     
     
     
    var compilationGeneration: () -> UInt64 = { ProfileActivationCoordinator.scheduledCompiles }
     
     
     
     
     
    var libraryGoneHandler: (@MainActor (StartupOutcomeRecord, _ stillWanted: @escaping @MainActor () -> Bool) async -> Void)?
     
     
     
     
     
     
    @Published private(set) var preparingStarts: Set<UInt64> = []
    private var lastPreparingStart: UInt64 = 0
    var isPreparingStart: Bool { !preparingStarts.isEmpty }

     
     
    var homeStatus: String {
        ClashHomeConnectionPresenter.homeStatus(status: status, isPreparingStart: isPreparingStart,
                                                systemHasNotAnswered: startAwaitingSystem)
    }

     
    var connectedSince: Date? {
        guard ["connected", "reasserting"].contains(status.lowercased()) else { return nil }
        return manager?.connection.connectedDate
    }

     
     
     
     
     
     
     
     
    @Published private(set) var startAwaitingSystem = false
    private var startAnswerDeadline: Task<Void, Never>?
    static var startAnswerDeadlineNanoseconds: UInt64 = 1_000_000_000

    func systemTookStart() {
        startAnswerDeadline?.cancel()
        if !startAwaitingSystem { startAwaitingSystem = true }
        startAnswerDeadline = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.startAnswerDeadlineNanoseconds)
            guard !Task.isCancelled else { return }
            self?.stopAwaitingTheSystem()
        }
    }

     
    func systemSaid(_ status: NEVPNStatus) {
        if [.connecting, .connected, .reasserting].contains(status) { stopAwaitingTheSystem() }
    }

    private func stopAwaitingTheSystem() {
        startAnswerDeadline?.cancel()
        startAnswerDeadline = nil
        if startAwaitingSystem { startAwaitingSystem = false }
    }

     
     
     
     
    func preparingToStart<T>(_ body: @MainActor () async -> T) async -> T {
        lastPreparingStart &+= 1
        let preparing = lastPreparingStart
        preparingStarts.insert(preparing)
        defer { preparingStarts.remove(preparing) }
        return await body()
    }
    @Published private(set) var vpnAuthorization: ClashVPNAuthorizationState?

    var systemVPNAuthorization: ClashVPNAuthorizationState? {
        vpnAuthorization ?? (hasLoadedStatus && systemVPNInstallationKnown && manager == nil ? .required : nil)
    }
     
     
     
     
    @Published var legacySettingsMigration: LegacyClientSettingsMigrationResult?
    @Published private(set) var configuredIncludedRouteCount = 0
    @Published private(set) var configuredExcludedRouteCount = 0
    @Published private(set) var routingPolicyNeedsApply = false
    @Published private(set) var installedRoutingPolicy = VPNRoutingPolicy()
     
     
    @Published private(set) var tunnelSettings = VPNTunnelSettings()

    private var manager: NETunnelProviderManager?
    private var systemVPNInstallationKnown = false
    private var installationReadGeneration: UInt64 = 0
    private var observer: NSObjectProtocol?
     
     
     
     
    private var disconnectNoticeTracker = VPNDisconnectNotice.Tracker()
    private var userStopInFlight = false
     
     
     
    private let unrequestedStops: VPNUnrequestedStopLog
    private var startFailureTracker = VPNStartFailureTracker()
     
     
     
    private var startNetwork: Task<NetworkPathInterfaceKind, Never>?
    private var systemVPNProfileResetInFlight = false
    private var startOutcomeWatchdog: Task<Void, Never>?
     
     
    private var statusLoad: Task<Void, Never>?
    private var connectionStatusGeneration: UInt64 = 0

    private let extensionBundleID = ClashAppIdentifiers.packetTunnelExtensionBundleID
    private let preferences: UserDefaults
    private let usesUITestFixtures: Bool
    private let systemVPNManagers: @MainActor () async throws -> [NETunnelProviderManager]
     
     
     
    private let lastDisconnectErrorReader: (@MainActor (NEVPNConnection) async -> NSError?)?
     
     
    private let networkReader: @MainActor () async -> NetworkPathInterfaceKind
     
     
    private let startupRecordReader: () -> StartupOutcomeRecord?

     
     
     
     
     
     
     
     
     
     
     
    private lazy var connectionRequests: TunnelRequestCoalescer = {
        let fixtures = usesUITestFixtures
        return TunnelRequestCoalescer(
            gestureWindow: {
                fixtures ? 0 : TunnelRequestCoalescer.defaultGestureWindow
            },
            isSettling: { [weak self] in
                guard let self, !fixtures else { return false }
                return Self.transitionalStates.contains(self.status)
            },
            settlingWindow: fixtures ? 0 : TunnelRequestCoalescer.defaultSettlingWindow
        )
    }()

     
     
    private static let transitionalStates: Set<String> = [
        "connecting", "disconnecting", "reasserting",
    ]

     
     
     
    var clientPreferences: UserDefaults { preferences }

    private let profileWriter: IPStackProfileWriter
    private var profileWriteIntentGeneration: UInt64 = 0

     
     
     
     
     
     
    private enum LegacyKillSwitchPreferenceKey {
        static let killSwitch = "vpn.routing.killSwitch"
        static let allowLocalNetwork = "vpn.routing.allowLocalNetwork"
        static let deviceTestRoutingBackup = "vpn.routing.deviceTestBackup"
    }

    init(
        preferences: UserDefaults? = UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite),
        usesUITestFixtures: Bool = false,
        systemVPNManagers: (@MainActor () async throws -> [NETunnelProviderManager])? = nil,
        profileWriter: IPStackProfileWriter? = nil,
        lastDisconnectError: (@MainActor (NEVPNConnection) async -> NSError?)? = nil,
        networkInterface: (@MainActor () async -> NetworkPathInterfaceKind)? = nil,
        startupRecord: (() -> StartupOutcomeRecord?)? = nil
    ) {
        let preferences = preferences ?? .standard
        self.preferences = preferences
        self.unrequestedStops = VPNUnrequestedStopLog(defaults: preferences)
        self.usesUITestFixtures = usesUITestFixtures
        self.systemVPNManagers = systemVPNManagers ?? { try await Self.boundedLoadAll() }
        self.lastDisconnectErrorReader = lastDisconnectError
        self.networkReader = networkInterface ?? { await NetworkPathProbe.startInterface(timeout: 1) }
        self.startupRecordReader = startupRecord ?? {
            StartupOutcomeRecord.read(from: ClashAppIdentifiers.appGroupContainer)
        }
        self.profileWriter = profileWriter ?? IPStackProfileWriter()
        clearLegacyKillSwitchPreferences()
        tunnelSettings = VPNTunnelSettings.load(from: preferences)
         
         
         
         
        preferences.removeObject(forKey: IPStackSettings.defaultsKey)
    }

     
    var session: NETunnelProviderSession? {
        manager?.connection as? NETunnelProviderSession
    }

     
     
     
     
     
     
    var reportableLastError: String {
        guard lastError == OnDemandStartRefusal.certainMessage || CoreStartRefusal.isLead(lastError) else {
            return VPNDisconnectErrorPresentation.reportMessage(lastError)
        }
        return lastErrorSentence(locale: AppPreferences.language().locale)
    }

     
     
     
     
    var recordedLastError: String {
        lastErrorSentence(locale: Locale(identifier: "en"))
    }

     
     
     
    var handoverFailureReason: String {
        reportableLastError
    }

     
     
     
     
     
    var homeLastErrorRow: String {
         
         
         
        if CoreStartRefusal.isLead(lastError) {
            return startRefusedByCore == nil ? VPNDisconnectErrorPresentation.providerDisconnectMessage : lastError
        }
        guard lastError == OnDemandStartRefusal.certainMessage else {
            return VPNDisconnectErrorPresentation.reportMessage(lastError)
        }
        guard startRefusedByOnDemand?.isCertain == true else {
            return VPNDisconnectErrorPresentation.genericStartFailureMessage
        }
        return lastError
    }

     
     
     
     
    func lastErrorSentence(locale: Locale) -> String {
        if CoreStartRefusal.isLead(lastError) {
            guard let refusal = startRefusedByCore else { return VPNDisconnectErrorPresentation.providerDisconnectMessage }
            return ClashCopy.string(for: .format(refusal.message, [refusal.words]), locale: locale)
        }
        guard lastError == OnDemandStartRefusal.certainMessage else {
            return VPNDisconnectErrorPresentation.reportMessage(lastError)
        }
        guard startRefusedByOnDemand?.isCertain == true, let names = onDemandRuleNames(locale: locale) else {
            return VPNDisconnectErrorPresentation.genericStartFailureMessage
        }
        return ClashCopy.string(for: .format(OnDemandStartRefusal.certainStatement, [names]), locale: locale)
    }

     
     
     
    func onDemandRuleNames(locale: Locale) -> String? {
        startRefusedByOnDemand?.ruleNames(locale: locale)
    }

     
     
     
    func onDemandNoteForTheReasonSheet(locale: Locale) -> String? {
        guard startRefusedByOnDemand?.isCertain == false, let names = onDemandRuleNames(locale: locale) else {
            return nil
        }
        return ClashCopy.string(for: .format(OnDemandStartRefusal.possibleMessage, [names]), locale: locale)
    }

     
     
     
     
     
    func sampleTheStartsNetwork() {
        guard let manager, OnDemandStartRefusal.canStopAStart(on: manager) else {
            startNetwork = nil
            return
        }
        let read = networkReader
        startNetwork = Task { @MainActor in await read() }
    }

     
     
     
    private func publishOnDemandRefusal(_ refusal: OnDemandStartRefusal?) {
        lastError = refusal?.isCertain == true
            ? OnDemandStartRefusal.certainMessage
            : VPNDisconnectErrorPresentation.genericStartFailureMessage
        startRefusedByOnDemand = refusal
    }

     
     
     
     
     
    private func retireTheOnDemandRefusal() {
        guard let refusal = startRefusedByOnDemand else { return }
        if refusal.isCertain, lastError == OnDemandStartRefusal.certainMessage {
            lastError = ""
        }
        if startRefusedByOnDemand != nil { startRefusedByOnDemand = nil }
    }

     
     
    func statusMoved(to status: NEVPNStatus) {
        if status != .disconnected, status != .invalid { retireTheOnDemandRefusal() }
    }

     
     
    private(set) var onDemandNetworkRecheck: Task<Void, Never>?

     
     
     
     
     
     
     
    private func recheckTheOnDemandRefusalsNetwork() {
        guard let refusal = startRefusedByOnDemand, OnDemandStartRefusal.isWeighable(refusal.interface) else { return }
        let read = networkReader
        onDemandNetworkRecheck = Task { @MainActor [weak self] in
            let now = await read()
            guard let self, OnDemandStartRefusal.isWeighable(now), now != refusal.interface,
                  self.startRefusedByOnDemand == refusal
            else { return }
            self.reweighTheOnDemandRefusal(on: now)
        }
    }

     
     
     
     
     
    private func reweighTheOnDemandRefusal(on interface: NetworkPathInterfaceKind) {
        guard let refusal = startRefusedByOnDemand else { return }
        let answer = manager.flatMap { OnDemandStartRefusal.find(on: $0, interface: interface) }
        guard let now = answer, now.rules == refusal.rules, now.isCertain == refusal.isCertain else {
            retireTheOnDemandRefusal()
            return
        }
        if now != refusal { startRefusedByOnDemand = now }
    }

    var systemVPNProfileResetAvailable: Bool {
         
        VPNDisconnectErrorPresentation.allowsSystemVPNProfileReset(
            forReportMessage: homeLastErrorRow
        )
    }

     
     
     
     
     
     
     
    func ensureStatusLoaded() async {
        if hasLoadedStatus { return }
        if let statusLoad { return await statusLoad.value }
        let load = Task { await self.loadInstalledManager() }
        statusLoad = load
        await load.value
        statusLoad = nil
    }

     
     
     
     
     
    private func loadInstalledManager() async {
        await refreshSystemVPNInstallation()
    }

     
     
     
    func refreshSystemVPNInstallation() async {
        _ = await refreshInstalledManagerIfIdle()
        recheckTheOnDemandRefusalsNetwork()
    }

    private func refreshInstalledManagerIfIdle() async -> Bool {
        guard !connectionRequests.isBusy, !profileWriter.isBusy else { return false }
        let intent = profileWriteIntentGeneration
        let writerRevision = profileWriter.revision
        installationReadGeneration &+= 1
        let readGeneration = installationReadGeneration
        func isCurrent() -> Bool {
            !Task.isCancelled && intent == profileWriteIntentGeneration
                && writerRevision == profileWriter.revision
                && readGeneration == installationReadGeneration
                && !connectionRequests.isBusy && !profileWriter.isBusy
        }
        do {
            let installed = try await systemVPNManagers().first {
                Self.isOwnedSystemVPNProfile($0, providerBundleIdentifier: extensionBundleID)
            }
            guard isCurrent() else { return false }
            let wasInstalled = manager != nil
            adoptManager(installed)
            if let installed {
                updateInstalledRoutingPolicy(from: installed)
                vpnAuthorization = nil
            } else if wasInstalled {
                vpnAuthorization = nil
            }
            if installationReadError != nil { lastError = "" }
            hasLoadedStatus = true
            updateStatus()
             
             
            if let installed { noteTunnelState(installed.connection) }
            return true
        } catch {
            guard isCurrent() else { return false }
             
            systemVPNInstallationKnown = false
            vpnAuthorization = nil
            let message = VPNDisconnectErrorPresentation.startMessage(for: error as NSError)
            lastError = message
            installationReadError = message
            return false
        }
    }

    func refresh() async {
        do {

            let recoveredInterruptedFixture = false
            let recoveredInterruptedPacketFlowProfile = false
            let recoveredInterruptedResourceProfile = false

            try await refreshConfigurationRoutingIntent()
            guard await refreshInstalledManagerIfIdle() else { return }
            let needsRecoveryApply = recoveredInterruptedFixture
                || recoveredInterruptedPacketFlowProfile
                || recoveredInterruptedResourceProfile
            if needsRecoveryApply {
                guard await applyRoutingPolicy(reconnectIfNeeded: true) else { return }


            }
            lastError = ""
        } catch {
            lastError = VPNDisconnectErrorPresentation.startMessage(
                for: error as NSError
            )
        }
    }

     
     
     
     
     
     
    @discardableResult
    func resetSystemVPNProfile() async -> Bool {
         
         
         
         
        guard !systemVPNProfileResetInFlight else { return false }
        systemVPNProfileResetInFlight = true
        defer { systemVPNProfileResetInFlight = false }
        startFailureTracker.cancelStart()

        do {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }

            let installedManagers = try await Self.boundedLoadAll()
            let clashManagers = installedManagers.filter { installed in
                Self.isOwnedSystemVPNProfile(
                    installed,
                    providerBundleIdentifier: extensionBundleID
                )
            }

            for installed in clashManagers {
                if Self.isActive(installed.connection.status) {
                    ClashLogStore.shared.append(
                        { let site = "replace-managers"; return "vpn stop requested  site=\(site)" }(),
                        stream: .app, level: .warning)
                    userStopInFlight = true
                    stopTunnel(installed.connection)
                    try await waitUntilDisconnected(installed.connection)
                }
                try await boundedRemove(installed)
            }

            manager = nil
            let fresh = NETunnelProviderManager()
            let tunnel = try configuredProtocol(from: fresh)
            routingPolicy.apply(to: tunnel)
            fresh.protocolConfiguration = tunnel
            fresh.localizedDescription = Self.vpnProfileTitle
            fresh.isEnabled = true
            try applyOnDemand(to: fresh)
            try await boundedSave(fresh)
            try await boundedLoad(fresh)

            adoptManager(fresh)
            updateInstalledRoutingPolicy(from: fresh)
            routingPolicyNeedsApply = false
            updateStatus()
            lastError = ""
            configurationNotice = ""
             
             
            startFailureTracker.forgetInstantFailures()
            return true
        } catch {
            lastError = VPNDisconnectErrorPresentation.startMessage(
                for: error as NSError
            )
            updateStatus()
            return false
        }
    }

     
     
     
    static func isOwnedSystemVPNProfile(
        _ manager: NETunnelProviderManager,
        providerBundleIdentifier: String
    ) -> Bool {
        guard let tunnel = manager.protocolConfiguration
            as? NETunnelProviderProtocol else { return false }
        return tunnel.providerBundleIdentifier == providerBundleIdentifier
    }

     
     
     
     
    static func readTunnelIsConnected() async -> Bool {
        guard let managers = try? await boundedLoadAll() else { return false }
        let ours = managers.first {
            isOwnedSystemVPNProfile($0, providerBundleIdentifier: ClashAppIdentifiers.packetTunnelExtensionBundleID)
        }
        return ours?.connection.status == .connected
    }

    var routingPolicy: VPNRoutingPolicy {
         
         
        VPNRoutingPolicy(tunnel: tunnelSettings.overlaid(by: ModuleDeviceSettingOverlay.load()))
    }

     
     
     
     
     
    @discardableResult
    func updateTunnelSettings(_ settings: VPNTunnelSettings) async -> Bool {
        let previous = tunnelSettings
        guard settings != previous else { return true }
        settings.save(to: preferences)
        tunnelSettings = settings
        guard await applyRoutingPolicy(reconnectIfNeeded: true) else {
            previous.save(to: preferences)
            tunnelSettings = previous
            routingPolicyNeedsApply = installedRoutingPolicy != routingPolicy
            return false
        }
        return true
    }

    @discardableResult
    func applyRoutingPolicy(reconnectIfNeeded: Bool) async -> Bool {
        do {
            try await refreshConfigurationRoutingIntent()
            let mgr = try await currentOrNewManager()
            let wasActive = Self.isActive(mgr.connection.status)
            if wasActive && reconnectIfNeeded {
                ClashLogStore.shared.append(
                    { let site = "reconnect-for-config"; return "vpn stop requested  site=\(site)" }(),
                    stream: .app, level: .warning)
                userStopInFlight = true
                stopTunnel(mgr.connection)
                try await waitUntilDisconnected(mgr.connection)
            }

            let tunnelProtocol = try configuredProtocol(from: mgr)
            routingPolicy.apply(to: tunnelProtocol)
            mgr.protocolConfiguration = tunnelProtocol
            mgr.localizedDescription = Self.vpnProfileTitle
            mgr.isEnabled = true
            try applyOnDemand(to: mgr)
            try await boundedSave(mgr)
            try await boundedLoad(mgr)
            adoptManager(mgr)
            updateInstalledRoutingPolicy(from: mgr)
            routingPolicyNeedsApply = false

            if wasActive && reconnectIfNeeded {
                try mgr.connection.startVPNTunnel()
                try await waitUntilConnected(mgr.connection)
            }
            updateStatus()
            lastError = ""
            return true
        } catch {
            lastError = "routing policy: \(error.localizedDescription)"
            return false
        }
    }

     
     
     
     
     
     
    private func stageConfig(settings: IPStackSettings) async throws -> String? {
        guard let container = ClashAppIdentifiers.appGroupContainer
        else {
            throw NSError(
                domain: "ClashClient.Configuration",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "App Group container unavailable"]
            )
        }
        let working = container.appendingPathComponent("working")
        try? FileManager.default.createDirectory(at: working, withIntermediateDirectories: true)
        let stageBegan = Date()
        func stageMark(_ name: String) {
            ClashLogStore.shared.append("stage phase  \(name)  +\(Int(Date().timeIntervalSince(stageBegan) * 1_000))ms", stream: .app, level: .info)
        }
        try BundledGeodataProvisioner.seedAllMissing(into: working)
         
         
        try await Task.detached(priority: .userInitiated) {
            try AppCoreSetup.ensure(container: container, settings: settings)
        }.value
        stageMark("core-setup")

        let store = try ConfigResourceStore(containerURL: container)
        let profileStore = ProfileStore(
            fileURL: working.appendingPathComponent("store/profiles.json")
        )
        try LocalDefaultProfileProvisioner.provisionIfNeeded(
            store: profileStore,
            workingDirectory: working
        )
        try BundledProfileProvisioner.provisionExistingProfileIfNeeded(
            container: container
        )
        stageMark("provisioned")
         
         
         
        let hasConfiguration = try await Task.detached(priority: .userInitiated) {
            let store = try ConfigResourceStore(containerURL: container)
            return try store.activePointer() != nil || store.lastKnownGoodPointer() != nil
        }.value
        if !hasConfiguration {
             
             
             
            let profiles = profileStore.load()
            let profile = profiles.first {
                $0.id == LocalDefaultProfileProvisioner.profileID
            } ?? profiles.first {
                BundledProfileProvisioner.bundledSequence(for: $0.source) == 1
            }
            guard let profile else {
                throw NSError(
                    domain: "ClashClient.Configuration",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey:
                        "No local profile is available to start Clash"]
                )
            }
            let sidecar = working
                .appendingPathComponent("store/\(profile.id)", isDirectory: true)
                .appendingPathComponent("source.yaml")
             
             
            let handed: HandedSource
            if FileManager.default.fileExists(atPath: sidecar.path) {
                handed = HandedSource(try String(contentsOf: sidecar, encoding: .utf8))
            } else if BundledProfileProvisioner.bundledSequence(for: profile.source) == 1,
                      let configURL = Bundle.main.url(
                          forResource: "config",
                          withExtension: "yaml"
                      ) {
                handed = HandedSource(try String(contentsOf: configURL, encoding: .utf8))
            } else {
                throw NSError(
                    domain: "ClashClient.Configuration",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey:
                        "The local profile source is unavailable"]
                )
            }
            try await activationCoordinator(store: store, container: container, settings: settings)
                .activate(profile: profile, handedSource: handed)
        }
        #if !os(tvOS)
        try await ProviderFirstLoadRetry.recoverCoreOwnedRoutesBeforeStart(container: container)
        #endif
        stageMark("core-routes-recovered")
        let preparation = try await ActiveRevisionMigrator(
            store: store,
            preflight: { PreflightService.intent(finalYAML: $0, container: container, settings: settings) },
            rebuild: { [weak self] pointer in
                guard let self else {
                    throw PipelineError.sourceUnavailable(
                        "The client runtime compiler is unavailable."
                    )
                }
                return try await self.regenerateRuntime(
                    replacing: pointer,
                    store: store,
                    container: container,
                    settings: settings
                )
            }
        ).prepareForStart()
        stageMark("prepared-for-start")
        guard let activeYAML = preparation.configuration.text else {
            throw ConfigResourceStoreError.configurationIsNotUTF8
        }
         
         
         
        let routingIntent = try await Task.detached(priority: .userInitiated) {
            try AppConfigurationPreflight.inspectRoutingIntent(activeYAML, container: container, settings: settings)
        }.value
        applyConfigurationRoutingIntent(routingIntent)
        stageMark("routing-intent")

        return preparation.userNotice
    }

     
     
     
    private func regenerateRuntime(
        replacing pointer: ActiveConfigurationPointer,
        store: ConfigResourceStore,
        container: URL,
        settings: IPStackSettings
    ) async throws -> ActiveConfigurationPointer {
        let working = container.appendingPathComponent("working", isDirectory: true)
        let profileStore = ProfileStore(
            fileURL: working.appendingPathComponent("store/profiles.json")
        )
        let profiles = profileStore.load()
        let profile = profiles.first { $0.id == pointer.profileID }
            ?? profiles.first { $0.activeRevision == pointer.revision }
            ?? {
                guard pointer.profileID == ConfigResourceStore.defaultProfileID else {
                    return nil
                }
                return profiles.first {
                    BundledProfileProvisioner.bundledSequence(for: $0.source) == 1
                }
            }()
        guard let profile else {
            throw PipelineError.sourceUnavailable(
                "The saved runtime has no matching source profile."
            )
        }

        let sidecar = working
            .appendingPathComponent("store/\(profile.id)", isDirectory: true)
            .appendingPathComponent("source.yaml")
        let coordinator = try activationCoordinator(store: store, container: container, settings: settings)
        if let source = try? String(contentsOf: sidecar, encoding: .utf8),
           !source.isEmpty {
            return try await coordinator.regenerateRuntime(
                profile: profile,
                storedSourceYAML: source,
                replacing: pointer
            )
        }

         
         
         
        if case .url = profile.source {
            let fetched = try await SubscriptionManager(
                downloader: ResourceDownloader(),
                credentials: CredentialStore()
            ).fetch(profile: profile, useConditionalValidators: false)
            guard let fetched else {
                throw PipelineError.sourceUnavailable(
                    "The profile URL did not provide a profile."
                )
            }
            return try await coordinator.regenerateRuntime(
                profile: profile,
                storedSourceYAML: fetched.yaml,
                sourceIsStoredSidecar: false,
                replacing: pointer
            )
        }

        if BundledProfileProvisioner.bundledSequence(for: profile.source) == 1,
           let configURL = Bundle.main.url(
               forResource: "config",
               withExtension: "yaml"
           ) {
            return try await coordinator.regenerateRuntime(
                profile: profile,
                storedSourceYAML: try String(contentsOf: configURL, encoding: .utf8),
                sourceIsStoredSidecar: false,
                replacing: pointer
            )
        }

        throw PipelineError.sourceUnavailable(
            "The local source file for this profile is unavailable."
        )
    }

     
     
     
     
     
     
     
     
     
     
    func activationCoordinator(store: ConfigResourceStore, container: URL, settings: IPStackSettings? = nil,
                               compileRuleSetsNow: Bool = false,
                               fetchBudget: ProviderFetchBudget = .activation) throws -> ProfileActivationCoordinator {
         
         
         
         
         
        let working = container.appendingPathComponent("working")
        return ProfileActivationCoordinator(
            store: store,
            profileStore: ProfileStore(fileURL: working.appendingPathComponent("store/profiles.json")),
            credentials: CredentialStore(),
            downloader: ResourceDownloader(),
            coreHomeDir: working,
             
             
             
             
             
             
            compileRuleSets: true,
            deferRuleSetCompilation: !compileRuleSetsNow,
            activationFetchBudget: fetchBudget,
            runtimeOverride: { [preferences = self.preferences] in
                FlClashRuntimeConfig.load(from: preferences)
            },
             
             
             
             
            logDefaults: preferences,
            activator: { _ in },
             
             
             
            intentContainer: container,
            intentSettings: settings,
            prepareCore: { try AppCoreSetup.ensure(container: container, settings: settings) })
    }

     
     
     
     
    func migrateLegacyGlobalSettingsIfNeeded() async -> LegacyClientSettingsMigrationResult {
        guard let container = ClashAppIdentifiers.appGroupContainer else {
            return .init(
                globalConfig: .blocked(.storageUnavailable),
                globalScript: nil
            )
        }
         
         
         
        let preferences = self.preferences
        let outcome: Result<LegacyClientSettingsMigrationResult, Error> = await Task.detached(priority: .userInitiated) {
            do { try AppCoreSetup.ensure(container: container) } catch { return .failure(error) }
            let working = container.appendingPathComponent("working")
            let globalConfig = LegacyGlobalConfigMigrationCoordinator.run(
                workingDirectory: working,
                defaults: preferences
            )
            guard globalConfig.userMessage.isEmpty else {
                return .success(.init(globalConfig: globalConfig, globalScript: nil))
            }
            return .success(.init(
                globalConfig: globalConfig,
                globalScript: LegacyGlobalScriptMigrationCoordinator.run(
                    workingDirectory: working,
                    defaults: preferences
                )
            ))
        }.value
        switch outcome {
        case .success(let result):
            return result
        case .failure(let error):
            lastError = error.localizedDescription
            return .init(globalConfig: .blocked(.coreSetupFailed(error.localizedDescription)), globalScript: nil)
        }
    }

     
     
    private static func ensureCoreSetup(container: URL, settings: IPStackSettings? = nil) throws {
        try AppCoreSetup.ensure(container: container, settings: settings)
    }

     

    private var appliedConfigIntent: PlatformConfigIntent?

     
     
     
     
     
     
    @discardableResult
    func applyActiveConfiguration(
        nextIntent intent: PlatformConfigIntent,
        startsWhenDown: Bool = true,
        publishedAs expected: ActiveConfigurationPointer? = nil
    ) async -> TunnelApplyOutcome {
         
         
         
        let stopEpoch = userStopEpoch
        let outcome = await handOver((intent, expected), forProfile: expected?.profileID,
                              startsWhenDown: startsWhenDown, stopEpoch: stopEpoch) ?? .savedForNext
        Self.announceIfRunning(outcome)
        return outcome
    }

     
     
     
     
     
     
     
     
    private func handOver(_ first: (intent: PlatformConfigIntent, expected: ActiveConfigurationPointer?)?,
                          forProfile profileID: String?, startsWhenDown: Bool, stopEpoch: UInt64) async -> TunnelApplyOutcome? {
        var next = first, profileID = profileID
        while true {
            await applications.acquire()
            defer { applications.release() }
            guard userStopEpoch == stopEpoch else { return .savedForNext }
            if next == nil {
                guard let published = await HandoverRevision.publishedNow(container: handoverContainer),
                      PublishedRuntimeHandover.hands(published.pointer, forProfile: profileID) else { return nil }
                next = (published.intent, published.pointer)
            }
            guard let (intent, expected) = next else { return nil }
            if let outcome = await applyFollowingPublications(intent, publishedAs: expected,
                                                              startsWhenDown: startsWhenDown, stopEpoch: stopEpoch) {
                return outcome
            }
            next = nil
            profileID = expected?.profileID
        }
    }

     
    private let applications = TunnelApplicationGate()



     
     
     
     
     
     
    @discardableResult
    func applyPublished(forProfile profileID: String?, startsWhenDown: Bool) async -> TunnelApplyOutcome? {
        let stopEpoch = userStopEpoch
        let outcome = await handOver(nil, forProfile: profileID, startsWhenDown: startsWhenDown, stopEpoch: stopEpoch)
        Self.announceIfRunning(outcome)
        return outcome
    }

     
     
     
     
     
     
    private static func announceIfRunning(_ outcome: TunnelApplyOutcome?) {
        guard outcome?.tunnelRunsTheNewConfiguration == true else { return }
        NotificationCenter.default.post(name: .clashProviderContentChanged, object: nil)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private func applyFollowingPublications(
        _ intent: PlatformConfigIntent, publishedAs expected: ActiveConfigurationPointer?,
        startsWhenDown: Bool, stopEpoch: UInt64
    ) async -> TunnelApplyOutcome? {
        var intent = intent, expected = expected
        for _ in 0..<3 {
            if let outcome = await applyActiveConfigurationHoldingTheGate(
                nextIntent: intent, startsWhenDown: startsWhenDown, stopEpoch: stopEpoch, expected: expected) {
                return outcome
            }
            guard let before = expected,
                  let published = await HandoverRevision.publishedNow(container: handoverContainer),
                  published.pointer.profileID == before.profileID else { return .savedForNext }
            intent = published.intent
            expected = published.pointer
        }
        return nil
    }



     
     
    private var handoverContainer: URL? {


        return ClashAppIdentifiers.appGroupContainer
    }

    private var handoverTunnelStatus: NEVPNStatus? {


        return manager?.connection.status
    }

    private var handoverSessionStatus: NEVPNStatus? {


        return session?.status
    }

    private func awaitConnectedForHandover() async {


        await awaitConnectedBeforeReload()
    }

    private func reloadForHandover() async -> ReloadAnswer {


        return await sendReloadMessage()
    }

    private func startForHandover(stopEpoch: UInt64) async -> TunnelApplyOutcome {


        let issuedAt = Date()
        return await start(origin: .programmatic)
            ? await settleStart(issuedAt: issuedAt, since: stopEpoch, success: .applied(warning: nil))
            : .failed(handoverFailureReason)
    }

    private func restartForHandover(forNewSettings: Bool, stopEpoch: UInt64) async -> TunnelApplyOutcome {


        let issuedAt = Date()
        return await restartTunnel(site: forNewSettings ? .intentRestart : .reloadFallback, since: stopEpoch)
            ? await settleStart(issuedAt: issuedAt, since: stopEpoch, success: .restarted)
            : .failed(handoverFailureReason)
    }

     
     
     
     
     
    private func applyActiveConfigurationHoldingTheGate(
        nextIntent intent: PlatformConfigIntent,
        startsWhenDown: Bool,
        stopEpoch: UInt64,
        expected: ActiveConfigurationPointer?
    ) async -> TunnelApplyOutcome? {
        let container = handoverContainer
        func overtaken() -> Bool { HandoverRevision.superseded(expected, container: container) }
        if overtaken() { return nil }
        let tunnelUp: Bool
        switch handoverTunnelStatus {
        case .connected, .connecting, .reasserting: tunnelUp = true
        default: tunnelUp = false
        }
         
         
         
         
        if appliedConfigIntent == nil, tunnelUp,
           let stampJSON = TunnelIntentStamp.readJSON(from: preferences),
           let recovered = try? JSONDecoder().decode(
               PlatformConfigIntent.self, from: Data(stampJSON.utf8)
           ) {
            appliedConfigIntent = recovered
        }
        let decision = ActivationDecision.decide(current: appliedConfigIntent, next: intent, tunnelUp: tunnelUp)
         
         
         
        if decision == .start, !startsWhenDown { return .savedForNext }
         
         
        guard userStopEpoch == stopEpoch else { return .savedForNext }
        let outcome: TunnelApplyOutcome
        switch decision {
        case .start:
            outcome = await startForHandover(stopEpoch: stopEpoch)
        case .reload, .restart:
             
             
             
             
             
             
             
             
             
             
             
             
            await awaitConnectedForHandover()
            guard !Task.isCancelled else { return .savedForNext }
            if overtaken() { return nil }
             
             
             
             
             
            if decision == .reload, handoverSessionStatus == .connected,
               let record = HandoverRevision.running(expected, container: container),
               !ModuleEngineReadinessSource.takesOwedReload(of: expected, container: container) {
                lastError = ""
                appliedConfigIntent = intent
                configurationNotice = ""
                return .applied(warning: record.warningForRunning)
            }
            var answer = await reloadForHandover()
             
             
             
             
             
             
            var attemptsLeft = 3
            while !answer.reloaded,
                  ReloadRefusal.isRaceWithActivation(answer.refusal),
                   
                   
                   
                  handoverSessionStatus == .connected,
                  attemptsLeft > 0 {
                attemptsLeft -= 1
                {
                    let why = answer.refusal ?? "unknown"
                    ClashLogStore.shared.append(
                        "reload raced activation, retrying  reason=\(why)",
                        stream: .app, level: .warning)
                }()
                try? await Task.sleep(nanoseconds: 400_000_000)
                if Task.isCancelled { return .savedForNext }
                if overtaken() { return nil }
                answer = await reloadForHandover()
            }
            let sessionStatus = handoverSessionStatus
            let followUp = ReloadFollowUp.after(
                decision, reloaded: answer.reloaded, verdict: answer.verdict,
                sessionUp: sessionStatus == .connected || sessionStatus == .connecting || sessionStatus == .reasserting,
                readerStopped: userStopEpoch != stopEpoch, cancelled: Task.isCancelled)
             
             
            NotificationCenter.default.post(name: .clashTunnelOutcomeRecorded, object: nil)
            switch followUp {
            case .applied(let warning):
                lastError = ""
                 
                 
                 
                appliedConfigIntent = HandoverRevision.acknowledged(expected, container: container) ? intent : nil
                configurationNotice = ""
                outcome = .applied(warning: warning)
            case .keep(let reason):
                 
                 
                 
                 
                { ClashLogStore.shared.append(
                    "reload refused, keeping the running configuration  reason=\(reason)",
                    stream: .app, level: .warning) }()
                return .keptRunning(reason)
            case .leaveDown:
                 
                 
                 
                 
                 
                 
                {
                    let why = answer.refusal ?? "none"
                    ClashLogStore.shared.append(
                        "reload unanswered and the tunnel was stopped or went down; not restarted  reason=\(why)",
                        stream: .app, level: .warning)
                }()
                return .savedForNext
            case .restart(let forNewSettings):
                 
                 
                 
                 
                if overtaken() { return nil }
                do {
                    let why = forNewSettings ? { let what = "routing"; return "new \(what) settings" }() : (answer.refusal ?? "unknown")
                    ClashLogStore.shared.append(
                        "reload answered, restarting  reason=\(why)",
                        stream: .app, level: .warning)
                }
                outcome = await restartForHandover(forNewSettings: forNewSettings, stopEpoch: stopEpoch)
            }
        }
        return outcome
    }

     
     
     
     
     
     
     
    private func settleStart(issuedAt: Date, since stopEpoch: UInt64,
                             success: TunnelApplyOutcome) async -> TunnelApplyOutcome {
        defer { NotificationCenter.default.post(name: .clashTunnelOutcomeRecorded, object: nil) }
         
         
        var ticks = 0
        while ticks < 300 {
            let status = manager?.connection.status
            let settling = status == .connecting || status == .reasserting
                || (ticks < 20 && (status == .disconnected || status == nil))
            guard settling, !Task.isCancelled, userStopEpoch == stopEpoch else { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
            ticks += 1
        }
         
        guard userStopEpoch == stopEpoch else {
            appliedConfigIntent = nil
            return .savedForNext
        }
        let status = manager?.connection.status
        if status == .connecting || status == .reasserting || Task.isCancelled {
             
             
             
             
            appliedConfigIntent = nil
            return .pending
        }
        let connected = status == .connected
         
         
        if !connected, lastError.isEmpty { await refreshLastDisconnectErrorAfterFailedStart() }
        appliedConfigIntent = connected
            ? TunnelIntentStamp.readJSON(from: preferences).flatMap {
                try? JSONDecoder().decode(PlatformConfigIntent.self, from: Data($0.utf8))
            }
            : nil
        let record = StartupOutcomeRecord.read(from: ClashAppIdentifiers.appGroupContainer)
        if !connected, let record, record.answersStart(issuedAt: issuedAt),
           LibraryGoneRepublish.owes(record, answered: nil), let libraryGoneHandler,
           userStopEpoch == stopEpoch {
             
             
             
             
             
            let stillWanted: @MainActor () -> Bool = { [weak self] in self?.userStopEpoch == stopEpoch }
            Task { @MainActor in await libraryGoneHandler(record, stillWanted) }
        }
        guard let settled = StartupOutcomeRecord.settlement(
            of: record,
             
            issuedAt: issuedAt, connected: connected, fallbackReason: connected ? "" : handoverFailureReason) else {
            configurationNotice = ""
            return success
        }
        if case .keptRunning(let reason) = settled {
            { ClashLogStore.shared.append(
                "start fell back to the last configuration that ran  reason=\(reason)",
                stream: .app, level: .warning) }()
        }
        return settled
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    nonisolated static func withNETimeout<T: Sendable>(
        seconds: Double,
        _ timeoutError: NETimeoutError,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let gate = NETimeoutGate(continuation)
            let timeout = Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
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

     
    private func rawSaveToPreferences(_ manager: NETunnelProviderManager, disarmOnly: Bool = false) async throws {
        let frozen = IPStackSystemProfileSnapshot(manager)
        try await profileWriter.saveConfirmed(frozen, to: manager, disarmOnly: disarmOnly) {
            try await manager.saveToPreferences()
        }
    }

    private func boundedSave(_ manager: NETunnelProviderManager, whileIntent intent: UInt64? = nil, disarmOnly: Bool = false) async throws {
        let frozen = IPStackSystemProfileSnapshot(manager)
        try await Self.withNETimeout(seconds: 15, .nePreferencesTimeout) { [self] in
            try await profileWriter.run { [self] in
                if let intent, intent != profileWriteIntentGeneration { throw CancellationError() }
                frozen.apply(to: manager)
                try await rawSaveToPreferences(manager, disarmOnly: disarmOnly)
            }
        }
    }

     
    private func boundedLoad(_ manager: NETunnelProviderManager) async throws {
        try await Self.withNETimeout(seconds: 15, .nePreferencesTimeout) {
            try await manager.loadFromPreferences()
        }
    }

     
    private func boundedRemove(_ manager: NETunnelProviderManager) async throws {
        try await Self.withNETimeout(seconds: 15, .nePreferencesTimeout) {
            try await manager.removeFromPreferences()
        }
    }

     
    private static func boundedLoadAll() async throws -> [NETunnelProviderManager] {
        try await withNETimeout(seconds: 15, .nePreferencesTimeout) {
            try await NETunnelProviderManager.loadAllFromPreferences()
        }
    }

     
     
     
     
     
     
    struct ReloadAnswer: Sendable {
        var reloaded = false
        var verdict: ReloadVerdict?
         
        var refusal: String?
    }

     
     
     
    private func sendReloadMessage() async -> ReloadAnswer {
        guard let session, session.status == .connected else { return ReloadAnswer() }
        guard let payload = try? JSONSerialization.data(withJSONObject: ["cmd": "reload"]) else {
            return ReloadAnswer()
        }
        do {
            return try await Self.withNETimeout(seconds: 20, .extensionMessageTimeout) {
                try await withCheckedThrowingContinuation { continuation in
                    do {
                        try session.sendProviderMessage(payload) { reply in
                            guard let reply,
                                  let json = try? JSONSerialization.jsonObject(with: reply) as? [String: Any]
                            else {
                                continuation.resume(returning: ReloadAnswer(
                                    refusal: { let why = "silent"; return "the extension replied \(why)" }()))
                                return
                            }
                            if let error = json["error"] as? String {
                                 
                                 
                                 
                                 
                                 
                                 
                                 
                                 
                                 
                                 
                                continuation.resume(returning: ReloadAnswer(
                                    verdict: ReloadVerdict.of(reply: json), refusal: error))
                                return
                            }
                            continuation.resume(returning: ReloadAnswer(reloaded: true, verdict: ReloadVerdict.of(reply: json)))
                        }
                    } catch {
                        continuation.resume(returning: ReloadAnswer(refusal: error.localizedDescription))
                    }
                }
            }
        } catch {
             
             
            return ReloadAnswer(refusal: { let why = "unanswered"; return "the extension went \(why) for 20s" }())
        }
    }

    private func applyOnDemand(to manager: NETunnelProviderManager) throws {
        try OnDemandSettings.apply(OnDemandSettings.configuration(), to: manager)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    enum OnDemandSaveOutcome: Equatable {
        case applied
        case refused(String)
        case indeterminate(String)
    }

    func applyOnDemandSettingsReportingOutcome() async -> OnDemandSaveOutcome {
        do {
            let mgr = try await currentOrNewManager()
            try applyOnDemand(to: mgr)
            try await boundedSave(mgr)
            adoptManager(mgr)
            lastError = ""
            return .applied
        } catch let error as NETimeoutError {
            let message = "on-demand: \(error.localizedDescription)"
            lastError = message
            return .indeterminate(message)
        } catch {
            let message = "on-demand: \(error.localizedDescription)"
            lastError = message
            return .refused(message)
        }
    }

    @discardableResult
    func applyOnDemandSettings() async -> Bool {
        do {
            let mgr = try await currentOrNewManager()
            try applyOnDemand(to: mgr)
            try await boundedSave(mgr)
            adoptManager(mgr)
            lastError = ""
            return true
        } catch {
            lastError = "on-demand: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
     
     
     
     
     
     
     
    private func awaitConnectedBeforeReload() async {
        for _ in 0..<100 {
             
             
             
             
             
            if Task.isCancelled { return }
            switch manager?.connection.status {
            case .connecting, .reasserting:
                try? await Task.sleep(nanoseconds: 100_000_000)
            default:
                return
            }
        }
    }

     
     
     
    private func restartTunnel(site: VPNStopSite, since epoch: UInt64? = nil) async -> Bool {
         
         
         
         
         
         
         
        guard !Task.isCancelled else { return false }
        let epochAtEntry = epoch ?? userStopEpoch
        guard epochAtEntry == userStopEpoch else { return false }
        await stop(site: site)
        for _ in 0..<50 {  
            if Task.isCancelled { return false }
            let status = manager?.connection.status
            if status == .disconnected || status == .invalid || status == nil { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard !Task.isCancelled else { return false }
         
         
         
        guard epochAtEntry == userStopEpoch else { return false }
        let started = await start(origin: .programmatic)
         
         
         
         
         
         
         
        if started, Task.isCancelled || epochAtEntry != userStopEpoch {
            await stop(site: site)
            return false
        }
        return started
    }

     
     
     
    func forceRestart() async {
        lastError = ""
        _ = await restartTunnel(site: .forceRestart)
    }

    private func stage(_ src: URL, to dst: URL) throws {
        try? FileManager.default.removeItem(at: dst)
        try FileManager.default.copyItem(at: src, to: dst)
    }

    @discardableResult
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func start(
        origin: TunnelRequestCoalescer.Origin = .gesture,
        waitsForPublication: Bool? = nil,
        userInitiated: Bool? = nil,
        ticket: StartTicket? = nil
    ) async -> Bool {
        let person = userInitiated ?? (origin == .gesture)
         
         
         
        let ticket = ticket ?? startTicket(asReader: person)
        do { try profileWriter.requireStartReady() }
        catch { lastError = error.localizedDescription; return false }
         
         
         
         
        let stopEpoch = userStopEpoch
        lastPreparingStart &+= 1
        let preparing = lastPreparingStart
        preparingStarts.insert(preparing)
        defer { preparingStarts.remove(preparing) }
        var compilesWaitedFor: UInt64?
        if waitsForPublication ?? (origin == .gesture) {
             
             
             
            let compileWait = Date()
            var rounds = 0
            var drained = true
            repeat {
                let scheduled = compilationGeneration()
                if let publicationBarrier { await publicationBarrier() }
                drained = await compilationBarrier()
                rounds += 1
                if !drained || compilationGeneration() == scheduled { break }
            } while rounds < 3 && userStopEpoch == stopEpoch && !Task.isCancelled
             
             
             
             
            compilesWaitedFor = drained ? compilationGeneration() : nil
            let waited = Int(Date().timeIntervalSince(compileWait) * 1_000)
            if !drained {
                ClashLogStore.shared.append(
                    "vpn start went ahead with the rule-set compile still running  waited=+\(waited)ms",
                    stream: .app, level: .warning)
            } else if waited >= 100 {
                ClashLogStore.shared.append("vpn start waited for the rule-set compile  +\(waited)ms", stream: .app)
            }
            guard userStopEpoch == stopEpoch, !Task.isCancelled else {
                ClashLogStore.shared.append(
                    { let why = Task.isCancelled ? "cancelled" : "stopped"; return "vpn start dropped after the publication wait  reason=\(why)" }(),
                    stream: .app, level: .warning)
                return false
            }
            if abandonsStale(ticket, at: .afterPublicationWait) != nil { return false }
        }
        let cancellation = VPNStartCancellation()
        return await withTaskCancellationHandler {
            await connectionRequests.run(origin: origin) { [weak self] in
                guard let self, !cancellation.isCancelled else { return false }
                 
                 
                guard self.userStopEpoch == stopEpoch else {
                    { let what = "stop"
                      ClashLogStore.shared.append("vpn start yielded to a \(what) made while it waited its turn",
                                                 stream: .app, level: .warning) }()
                    return false
                }
                self.profileWriteIntentGeneration &+= 1
                return await self.performStart(
                    writeIntent: self.profileWriteIntentGeneration, cancellation: cancellation,
                    userInitiated: person, compilesWaitedFor: compilesWaitedFor, ticket: ticket)
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

     
     
     
     
     
     
    static let userInitiatedStartOption = ClashTunnelStart.userInitiatedStartOption

    private func performStart(writeIntent: UInt64, cancellation: VPNStartCancellation,
                              userInitiated: Bool = false,
                              compilesWaitedFor: UInt64? = nil,
                              ticket: StartTicket? = nil) async -> Bool {
         
        if let ticket, abandonsStale(ticket, at: .atItsTurn) != nil { return false }
        let waitingMessage = String(localized: "Waiting for VPN authorization. Complete the system confirmation in Settings to continue.")
        let began = Date()
        var phase = "prepare"
        func mark(_ name: String) {
            ClashLogStore.shared.append("start phase  \(name)  +\(Int(Date().timeIntervalSince(began) * 1_000))ms", stream: .app, level: .info)
        }
        mark("prepare-begin")
        var needsAuthorization = false
        lastError = ""
        vpnAuthorization = nil
        func checkStartIntent() throws {
            try Task.checkCancellation()
            guard writeIntent == profileWriteIntentGeneration, !cancellation.isCancelled
            else { throw CancellationError() }
        }
        defer {
            if self.configurationNotice == waitingMessage { self.configurationNotice = "" }
            if vpnAuthorization == .waiting { vpnAuthorization = nil }
        }
        do {
            try checkStartIntent()
            let ipStack = IPStackSettings()
            let configurationNotice = try await stageConfig(settings: ipStack)
            mark("stage-config-done")
             
             
             
            if let compilesWaitedFor, compilationGeneration() != compilesWaitedFor {
                let stageWait = Date()
                if await compilationBarrier() {
                    mark("stage-compile-done")
                } else {
                    let waited = Int(Date().timeIntervalSince(stageWait) * 1_000)
                    ClashLogStore.shared.append(
                        "vpn start went ahead with the rule-set compile still running  waited=+\(waited)ms",
                        stream: .app, level: .warning)
                }
            }
            try checkStartIntent()
            let installed = try await loadSystemVPNStartProfile(isCurrent: {
                writeIntent == self.profileWriteIntentGeneration && !cancellation.isCancelled
            })
            mark("system-profile-loaded")
            try checkStartIntent()
            let mgr = installed.manager
            needsAuthorization = installed.needsAuthorization
            if needsAuthorization { vpnAuthorization = .waiting }
            let proto = try configuredProtocol(from: mgr, ipStack: ipStack)
            routingPolicy.apply(to: proto)
            mgr.protocolConfiguration = proto
            mgr.localizedDescription = Self.vpnProfileTitle
            mgr.isEnabled = true
            try applyOnDemand(to: mgr)
            let frozen = IPStackSystemProfileSnapshot(mgr)
            try await VPNStartAuthorization.perform(
                save: { [self] in
                    phase = "save"
                    try await profileWriter.run { [self] in
                        guard writeIntent == profileWriteIntentGeneration, !cancellation.isCancelled
                        else { throw CancellationError() }
                        frozen.apply(to: mgr)
                        ClashLogStore.shared.append("vpn authorization save began", stream: .app, level: .warning)
                        try await rawSaveToPreferences(mgr)
                        ClashLogStore.shared.append("vpn authorization save confirmed", stream: .app, level: .warning)
                        mark("preferences-saved")
                    }
                },
                reload: { [self] in
                    phase = "reload"
                    vpnAuthorization = nil
                    try await boundedLoad(mgr)
                    mark("preferences-reloaded")
                },
                start: { [self] in
                    phase = "start"
                     
                     
                     
                     
                     
                     
                    if let ticket, let stale = abandonsStale(ticket, at: .beforeSystemStart) { throw stale }
                    adoptManager(mgr)
                    updateInstalledRoutingPolicy(from: mgr)
                    routingPolicyNeedsApply = false
                    sampleTheStartsNetwork()
                    startFailureTracker.beginStart()
                    let before = connectionStatusLabel(mgr.connection.status)
                    try mgr.connection.startVPNTunnel(
                        options: userInitiated ? [Self.userInitiatedStartOption: NSNumber(value: true)] : nil)
                    systemTookStart()
                    updateStatus()
                    mark("start-vpn-tunnel-returned")
                    let after = connectionStatusLabel(mgr.connection.status)
                    ClashLogStore.shared.append(
                        "vpn start requested  before=\(before) after=\(after)",
                        stream: .app, level: .warning)
                    lastError = ""
                    self.configurationNotice = configurationNotice ?? ""
                    scheduleStartOutcomeWatchdog()
                },
                abort: { [self] in
                     
                     
                    await Task { @MainActor in
                        do {
                            try await profileWriter.run { [self] in
                                if mgr.isOnDemandEnabled {
                                    try await rawSaveToPreferences(mgr, disarmOnly: true)
                                }
                            }
                        } catch {
                            ClashLogStore.shared.append(
                                "vpn cancelled-start disarm failed: \(error)", stream: .app, level: .warning)
                        }
                        stopTunnel(mgr.connection)
                    }.value
                },
                isCurrent: { [self] in
                    writeIntent == profileWriteIntentGeneration && !cancellation.isCancelled
                },
                onWaiting: { [weak self] in
                    guard let self, writeIntent == self.profileWriteIntentGeneration,
                          !cancellation.isCancelled else { return }
                    self.configurationNotice = waitingMessage
                    if needsAuthorization { self.vpnAuthorization = .waiting }
                    ClashLogStore.shared.append("vpn authorization still waiting", stream: .app, level: .warning)
                })
            return true
        } catch is CancellationError {
            startFailureTracker.cancelStart()
            ClashLogStore.shared.append("vpn start cancelled before request", stream: .app, level: .warning)
            return false
        } catch is StaleStart {
             
            startFailureTracker.cancelStart()
            return false
        } catch {
            startFailureTracker.cancelStart()
            guard writeIntent == profileWriteIntentGeneration,
                  !cancellation.isCancelled, !Task.isCancelled else {
                ClashLogStore.shared.append("vpn start cancelled during preparation", stream: .app, level: .warning)
                return false
            }
            let failure = error as NSError
            let elapsed = Int(Date().timeIntervalSince(began) * 1_000)
            ClashLogStore.shared.append(
                "vpn start refused  phase=\(phase) domain=\(failure.domain) code=\(failure.code) elapsedMs=\(elapsed) error=\(failure.localizedDescription) details=\(failure)",
                stream: .app, level: .warning)
            presentSystemVPNStartFailure(error, phase: phase, needsAuthorization: needsAuthorization)
            return false
        }
    }

    func presentSystemVPNStartFailure(_ error: Error, phase: String, needsAuthorization: Bool) {
        if needsAuthorization, phase == "save",
           VPNStartAuthorization.isPermissionDenial(error as NSError) {
            vpnAuthorization = .notCompleted
            lastError = ""
            return
        }
        vpnAuthorization = nil
        lastError = error is NETimeoutError ? error.localizedDescription
            : VPNDisconnectErrorPresentation.startMessage(for: error as NSError)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private static let startOutcomeDeadlineMilliseconds: UInt64 = 250

    private func scheduleStartOutcomeWatchdog() {
         
         
         
         
         
         
        guard startOutcomeWatchdog == nil else { return }
        startOutcomeWatchdog = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: Self.startOutcomeDeadlineMilliseconds * 1_000_000
            )
            guard !Task.isCancelled else { return }
            await self?.reportStartThatNeverMoved()
        }
    }

    private func reportStartThatNeverMoved() async {
        startOutcomeWatchdog = nil
        guard startFailureTracker.isAwaitingResult else { return }
        ClashLogStore.shared.append(
            {
                let window = Self.startOutcomeDeadlineMilliseconds
                return "vpn start never moved  window=\(window)ms"
            }(),
            stream: .app, level: .warning)
         
         
         
        await refreshLastDisconnectErrorAfterFailedStart()
    }

     
     
    nonisolated private func connectionStatusLabel(_ status: NEVPNStatus) -> String {
        switch status {
        case .invalid: return "invalid"
        case .disconnected: return "disconnected"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .reasserting: return "reasserting"
        case .disconnecting: return "disconnecting"
        @unknown default: return "unknown"
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func stop(
        site: VPNStopSite = .userButton,
        origin: TunnelRequestCoalescer.Origin? = nil,
        alongside: (@MainActor () -> Void)? = nil
    ) async {
        profileWriteIntentGeneration &+= 1
        let writeIntent = profileWriteIntentGeneration
        let origin = origin ?? (site == .userButton ? .gesture : .programmatic)
         
         
         
         
         
        if site == .userButton {
            userStopEpoch &+= 1
            preparingStarts.removeAll()
            stopAwaitingTheSystem()
             
             
             
            do {
                try ReaderTunnelIntent.record(.stop, at: startClock(), gesture: UUID().uuidString, in: intentDirectory())
            } catch {
                 
                ClashLogStore.shared.append({ "vpn stop: reader's word not written  \(error)" }(), stream: .app, level: .warning)
            }
        }
        await connectionRequests.run(origin: origin) { [weak self] in
            alongside?()
            await self?.performStop(site: site, writeIntent: writeIntent)
            return false
        }
    }

    private func performStop(site: VPNStopSite, writeIntent: UInt64) async {
        startFailureTracker.cancelStart()
        guard let manager else { return }
        if Self.disarmOnDemandForUserStop(manager) {
            do {
                try await boundedSave(manager, whileIntent: writeIntent, disarmOnly: true)
            } catch {
                 
                 
                 
            }
        }
        ClashLogStore.shared.append(
            { let label = site.rawValue; return "vpn stop requested  site=\(label)" }(),
            stream: .app, level: .warning)
         
         
         
         
         
         
         
        lastStopUserInitiated = true
        userStopInFlight = true
        if profileWriteIntentGeneration == writeIntent { stopTunnel(manager.connection) }
    }

     
     
    private var userStopEpoch: UInt64 = 0

     
     
     
     
     
     
     
     
     
     
    private var stay: UInt64 = 0
    private var latestLongStay: UInt64 = 0
     
     
    private var backgroundEnteredAt: TimeInterval?
     
     
     
    static let startSurvivesBackgroundFor: TimeInterval = 120
     
     
    var startClock: () -> Date = { Date() }
     
     
    var monotonicSeconds: () -> TimeInterval = {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
    }
     
     
    var intentDirectory: () -> URL? = { ReaderTunnelIntent.appGroupDirectory }

     
     
    struct StartTicket: Equatable {
         
         
        let stay: UInt64
         
         
         
         
        let intentGeneration: UInt64?
         
         
        let requiresIntent: Bool
         
         
        let supersededByStop: Bool
        let askedAt: Date
    }

     
     
     
     
    func startTicket(asReader: Bool) -> StartTicket {
        let askedAt = startClock()
        let directory = intentDirectory()
        var generation: UInt64?
        var superseded = false
        do {
            let seen = try ReaderTunnelIntent.last(in: directory)?.generation ?? 0
            if asReader {
                switch try ReaderTunnelIntent.record(
                    .connect, at: askedAt, gesture: UUID().uuidString, basedOn: seen, in: directory) {
                case .accepted(let written):
                    generation = written.generation
                case .superseded(let newer):
                     
                     
                    generation = newer.generation
                    superseded = newer.intent == .stop
                }
            } else {
                generation = seen
            }
        } catch {
            ClashLogStore.shared.append({ "vpn start: reader's word unavailable  \(error)" }(), stream: .app, level: .warning)
        }
        return StartTicket(stay: stay, intentGeneration: generation, requiresIntent: false,
                           supersededByStop: superseded, askedAt: askedAt)
    }

     
     
     
    func startTicket(continuing verified: ReaderTunnelIntent.Record) -> StartTicket {
        StartTicket(stay: stay, intentGeneration: verified.generation, requiresIntent: true,
                    supersededByStop: false, askedAt: startClock())
    }

    func applicationEnteredBackground() {
        guard backgroundEnteredAt == nil else { return }
        stay &+= 1
        backgroundEnteredAt = monotonicSeconds()
    }

    func applicationBecameActive() {
        guard let entered = backgroundEnteredAt else { return }
        backgroundEnteredAt = nil
        if monotonicSeconds() - entered > Self.startSurvivesBackgroundFor { latestLongStay = stay }
    }

    enum StaleStart: Error, Equatable, VPNStartAbandonment {
         
        case background
         
         
        case readerStopped
         
        case intentUnreadable
    }

     
    private func staleness(of ticket: StartTicket) -> StaleStart? {
        if latestLongStay > ticket.stay { return .background }
         
         
        if let entered = backgroundEnteredAt, stay > ticket.stay,
           monotonicSeconds() - entered > Self.startSurvivesBackgroundFor {
            return .background
        }
        if ticket.supersededByStop { return .readerStopped }
        guard let generation = ticket.intentGeneration else {
            return ticket.requiresIntent ? .intentUnreadable : nil
        }
        do {
            if let last = try ReaderTunnelIntent.last(in: intentDirectory()),
               last.generation != generation, last.intent == .stop {
                return .readerStopped
            }
        } catch {
            if ticket.requiresIntent { return .intentUnreadable }
        }
        return nil
    }

     
     
     
    private func abandonsStale(_ ticket: StartTicket, at checkpoint: StartCheckpoint) -> StaleStart? {
        guard let stale = staleness(of: ticket) else { return nil }
        let why: String
        switch stale {
        case .background: why = "backgrounded"
        case .readerStopped: why = "readerStopped"
        case .intentUnreadable: why = "intentUnreadable"
        }
        let place = checkpoint.rawValue
        ClashLogStore.shared.append({ "vpn start dropped  at=\(place) reason=\(why)" }(), stream: .app, level: .warning)
        if stale == .background {
            lastError = String(localized: "The connection was canceled after a long time in the background. Connect again.")
        }
        return stale
    }

     
    enum StartCheckpoint: String {
        case afterPublicationWait = "after-publication-wait"
        case atItsTurn = "at-its-turn"
        case beforeSystemStart = "before-system-start"
    }

    private var lastStopUserInitiated = false
     
    func consumeUserInitiatedStop() -> Bool {
        defer { lastStopUserInitiated = false }
        return lastStopUserInitiated
    }

     
     
     
     
     
     
     
     
     
     
     
     
    private(set) var reachedConnectedSinceStart = false

     
     
     
     
     
     
     
     
     
     
     
    private(set) var sawStartAttempt = false

     
     
    var lastStartFailed: Bool { sawStartAttempt && !reachedConnectedSinceStart }

     
     
     
    @discardableResult
    nonisolated static func disarmOnDemandForUserStop(
        _ manager: NETunnelProviderManager
    ) -> Bool {
        manager.disarmOnDemandForUserStop()
    }

    private func configuredProtocol(from manager: NETunnelProviderManager, ipStack: IPStackSettings? = nil) throws -> NETunnelProviderProtocol {
        let tunnelProtocol = (manager.protocolConfiguration?.copy() as? NETunnelProviderProtocol)
            ?? NETunnelProviderProtocol()
        let snapshot = ipStack ?? IPStackSettings()
        tunnelProtocol.providerConfiguration = try snapshot.applying(to: tunnelProtocol.providerConfiguration)
        tunnelProtocol.providerBundleIdentifier = extensionBundleID
        tunnelProtocol.serverAddress = Self.vpnProfileDescription
         
         
        tunnelProtocol.disconnectOnSleep = OnDemandSettings.configuration().disconnectOnSleep
        return tunnelProtocol
    }

    struct SystemVPNStartProfile {
        let manager: NETunnelProviderManager
        let needsAuthorization: Bool
    }

    func loadSystemVPNStartProfile(isCurrent: () -> Bool) async throws -> SystemVPNStartProfile {
        let intent = profileWriteIntentGeneration
        try Task.checkCancellation()
        guard isCurrent(), intent == profileWriteIntentGeneration else { throw CancellationError() }
        let installed: NETunnelProviderManager?
        do {
            installed = try await systemVPNManagers().first {
                Self.isOwnedSystemVPNProfile($0, providerBundleIdentifier: extensionBundleID)
            }
        } catch {
            try Task.checkCancellation()
            guard isCurrent(), intent == profileWriteIntentGeneration else { throw CancellationError() }
            systemVPNInstallationKnown = false
            throw error
        }
        try Task.checkCancellation()
        guard isCurrent(), intent == profileWriteIntentGeneration else { throw CancellationError() }
         
         
        adoptManager(installed)
        hasLoadedStatus = true
        updateStatus()
        return SystemVPNStartProfile(
            manager: installed ?? NETunnelProviderManager(),
            needsAuthorization: installed == nil)
    }

    private func currentOrNewManager() async throws -> NETunnelProviderManager {
        if let manager { return manager }
        let managers = try await systemVPNManagers()
        if let installed = managers.first {
            return installed
        }
        return NETunnelProviderManager()
    }

     
     
     
     
    private func clearLegacyKillSwitchPreferences() {
        preferences.removeObject(forKey: LegacyKillSwitchPreferenceKey.killSwitch)
        preferences.removeObject(forKey: LegacyKillSwitchPreferenceKey.allowLocalNetwork)
        preferences.removeObject(forKey: LegacyKillSwitchPreferenceKey.deviceTestRoutingBackup)
    }

    private func updateInstalledRoutingPolicy(from manager: NETunnelProviderManager) {
        guard let tunnelProtocol = manager.protocolConfiguration as? NETunnelProviderProtocol else { return }
        let installed = VPNRoutingPolicy.installed(from: tunnelProtocol)
        let changed = installed != installedRoutingPolicy
        installedRoutingPolicy = installed
        routingPolicyNeedsApply = installedRoutingPolicy != routingPolicy
         
         
         
         
        if changed {
            ClashLogStore.shared.append(
                "vpn profile installed  includeAllNetworks=\(installed.includeAllNetworks) "
                    + "excludeLocalNetworks=\(installed.excludeLocalNetworks) "
                    + "enforceRoutes=\(installed.enforceRoutes) "
                    + "excludeAPNs=\(installed.excludeAPNs) "
                    + "excludeCellularServices=\(installed.excludeCellularServices) "
                    + "excludeDeviceCommunication=\(installed.excludeDeviceCommunication) "
                    + "disconnectOnSleep=\(tunnelProtocol.disconnectOnSleep) "
                    + "onDemand=\(manager.isOnDemandEnabled)",
                stream: .app, level: .warning)
        }
    }

    private func refreshConfigurationRoutingIntent() async throws {
        let ipStack = IPStackSettings()
        if let container = ClashAppIdentifiers.appGroupContainer {
            do {
                let intent = try await Task.detached {
                    let stored = try ConfigResourceStore(containerURL: container).loadCurrent()
                    guard let content = stored.text else {
                        throw ConfigResourceStoreError.configurationIsNotUTF8
                    }
                    return try AppConfigurationPreflight.inspectRoutingIntent(content, settings: ipStack)
                }.value
                applyConfigurationRoutingIntent(intent)
                return
            } catch ConfigResourceStoreError.noValidConfiguration {
                 
                 
            }
        }
        guard let bundled = Bundle.main.url(forResource: "config", withExtension: "yaml") else { return }
        let content = try String(contentsOf: bundled, encoding: .utf8)
        let intent = try await Task.detached {
            try AppConfigurationPreflight.inspectRoutingIntent(content, settings: ipStack)
        }.value
        applyConfigurationRoutingIntent(intent)
    }

    private func applyConfigurationRoutingIntent(_ configContent: String) throws {
        applyConfigurationRoutingIntent(
            try AppConfigurationPreflight.inspectRoutingIntent(configContent)
        )
    }

    private func applyConfigurationRoutingIntent(_ intent: PlatformConfigIntent) {
         
         
        configuredIncludedRouteCount = intent.includedRouteCount
        configuredExcludedRouteCount = intent.excludedRouteCount
    }



    private static func isActive(_ status: NEVPNStatus) -> Bool {
        switch status {
        case .connecting, .connected, .reasserting:
            return true
        default:
            return false
        }
    }

    private func waitUntilDisconnected(_ connection: NEVPNConnection) async throws {
        for _ in 0..<100 {
            if connection.status == .disconnected || connection.status == .invalid { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw NSError(
            domain: "ClashClient.VPNRoutingPolicy",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "timed out waiting for VPN disconnect"]
        )
    }

    private func waitUntilConnected(_ connection: NEVPNConnection) async throws {
        for _ in 0..<450 {
            if connection.status == .connected || connection.status == .reasserting { return }
             
             
            if connection.status == .invalid {
                throw NSError(
                    domain: "ClashClient.VPNRoutingPolicy",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "VPN profile became invalid while applying routing policy"]
                )
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw NSError(
            domain: "ClashClient.VPNRoutingPolicy",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "timed out waiting for VPN reconnect"]
        )
    }

     
     
     
     
     
     
     
     
     
     
     
    private func adoptManager(_ mgr: NETunnelProviderManager?) {
        manager = mgr
        systemVPNInstallationKnown = true
        observeStatus()
        retireTheOnDemandRefusalTheProfileNoLongerMakes()
    }

     
     
     
     
    private func retireTheOnDemandRefusalTheProfileNoLongerMakes() {
        guard let refusal = startRefusedByOnDemand else { return }
        reweighTheOnDemandRefusal(on: refusal.interface)
    }

    private func observeStatus() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        guard let connection = manager?.connection else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: connection, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.handleStatusChange() }
        }
    }

    private func handleStatusChange() async {
        connectionStatusGeneration &+= 1
        guard let connection = manager?.connection else {
            updateStatus()
            return
        }
        updateStatus()
        statusMoved(to: connection.status)
        if disconnectNoticeTracker.observe(
            connection.status,
            userInitiated: userStopInFlight,
            enabled: OnDemandSettings.configuration().showDisconnectMessage
        ) {
            VPNDisconnectNotice.post()
        }
        if connection.status == .connecting || connection.status == .connected {
            userStopInFlight = false
        }
         
         
         
         
         
         
         
        ClashLogStore.shared.append(
            {
                let label = connectionStatusLabel(connection.status)
                return "vpn status changed  to=\(label)"
            }(),
            stream: .app, level: .warning)
        noteTunnelState(connection)
        if connection.status == .connected || connection.status == .disconnected || connection.status == .invalid {
            ClashWidgetFactsPublisher.tunnelChanged()
        }
         
         
         
        startOutcomeWatchdog?.cancel()
        startOutcomeWatchdog = nil
        systemSaid(connection.status)
        if connection.status == .connected || connection.status == .reasserting
            || connection.status == .connecting
        {
             
             
             
             
            lastError = ""
        }
        if connection.status == .connected || connection.status == .reasserting {
             
             
             
             
            #if !os(tvOS)
            if !reachedConnectedSinceStart, connection.status == .connected {
                 
                 
                 
                 
                 
                ProviderFirstLoadRetry.kick(trigger: .connected)
            }
            #endif
            reachedConnectedSinceStart = true
        }
        if connection.status == .connecting {
            reachedConnectedSinceStart = false
             
             
             
             
            sawStartAttempt = true
        }
        if startFailureTracker.statusDidChange(to: connection.status) {
            await resolveLastDisconnectError(on: connection)
        }
    }

    func refreshLastDisconnectErrorAfterFailedStart() async {
         
         
        guard startFailureTracker.isAwaitingResult,
              lastError.isEmpty,
              let connection = manager?.connection,
              connection.status == .disconnected || connection.status == .invalid
        else { return }
        startFailureTracker.cancelStart()
        await resolveLastDisconnectError(on: connection)
    }

    func resolveLastDisconnectError(on connection: NEVPNConnection) async {
        let intent = profileWriteIntentGeneration
        let statusGeneration = connectionStatusGeneration
         
         
         
        var onDemandRefusal: OnDemandStartRefusal?
        await VPNStartAuthorization.resolveFailure(
            fetch: { [self] in
                let error: NSError?
                if let read = lastDisconnectErrorReader {
                    error = await read(connection)
                } else {
                    error = await fetchLastDisconnectError(on: connection)
                }
                if error == nil { onDemandRefusal = await onDemandRefusalOfTheStoppedStart() }
                return error
            },
            isCurrent: { [self] in
                manager?.connection === connection
                    && profileWriteIntentGeneration == intent
                    && connectionStatusGeneration == statusGeneration
                    && (connection.status == .disconnected || connection.status == .invalid)
            },
            publish: { [self] error in
                if let error {
                     
                     
                     
                     
                     
                     
                     
                     
                    ClashLogStore.shared.append(
                        {
                            let domain = error.domain
                            let code = error.code
                            return "vpn disconnect error  domain=\(domain) code=\(code)"
                        }(),
                        stream: .app, level: .warning)
                     
                     
                     
                     
                    let record = error.domain == ClashTunnelStart.startErrorDomain ? startupRecordReader() : nil
                    if let refusal = CoreStartRefusal.from(error: error, record: record) {
                        lastError = refusal.message
                        startRefusedByCore = refusal
                    } else {
                        lastError = VPNDisconnectErrorPresentation.message(
                            for: error,
                            providerLooksUnlaunched: startFailureTracker.providerLooksUnlaunched
                        )
                    }
                } else {
                    if let onDemandRefusal {
                        ClashLogStore.shared.append(
                            #"vpn start stopped with no reason  on-demand disconnect rules=\#(onDemandRefusal.rules.count) certain=\#(onDemandRefusal.isCertain) network=\#(onDemandRefusal.interface.rawValue)"#,
                            stream: .app, level: .warning)
                    }
                     
                     
                     
                    publishOnDemandRefusal(onDemandRefusal)
                }
            })
    }

     
     
     
     
     
    private func onDemandRefusalOfTheStoppedStart() async -> OnDemandStartRefusal? {
         
        guard let manager, OnDemandStartRefusal.canStopAStart(on: manager) else { return nil }
        let interface = await startNetwork?.value ?? .unknown
        return OnDemandStartRefusal.find(on: manager, interface: interface)
    }

     
     
     
    private func stopTunnel(_ connection: NEVPNConnection) {
        unrequestedStops.appWillStop(connectedSince: connection.connectedDate)
        connection.stopVPNTunnel()
    }

     
     
     
     
     
    private func noteTunnelState(_ connection: NEVPNConnection) {
        switch connection.status {
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
            let status = connectionStatusLabel(connection.status)
            Task { [weak self] in
                guard let self else { return }
                let error = await self.fetchLastDisconnectError(on: connection)
                ClashLogStore.shared.append(
                    VPNUnrequestedStopLog.line(for: ended, status: status, error: error),
                    stream: .app, level: .warning)
            }
        default:
            break
        }
    }

    private func fetchLastDisconnectError(on connection: NEVPNConnection) async -> NSError? {
        guard #available(iOS 16.0, *) else { return nil }
        return await withCheckedContinuation { continuation in
            let gate = VPNDisconnectErrorFetchGate(continuation)
            connection.fetchLastDisconnectError { error in
                gate.resolve(error as NSError?)
            }
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                gate.resolve(nil)
            }
        }
    }

    private func updateStatus() {
        guard let connection = manager?.connection else { status = "not installed"; return }
        switch connection.status {
        case .invalid: status = "invalid"
        case .disconnected: status = "disconnected"
        case .connecting: status = "connecting"
        case .connected: status = "connected"
        case .reasserting: status = "reasserting"
        case .disconnecting: status = "disconnecting"
        @unknown default: status = "unknown"
        }
    }
}
