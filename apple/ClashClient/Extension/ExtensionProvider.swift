@preconcurrency import Clash
import Network
import NetworkExtension
import os.log

let appGroupID = ClashAppIdentifiers.appGroup

 
 
 
 
enum TunnelGlobalReading {
    static func exit() -> ClashTunnelOutboundMode.GlobalExit? {
        ClashTunnelOutboundMode.readGlobalExit(
            summary: { ClashProxiesSummaryJSON() },
            members: { ClashGroupMembersJSON($0, 0, Int32(ClashTunnelOutboundMode.membersRead)) }
        )
    }
}



enum ExtensionError: LocalizedError {
    case appGroupUnavailable
    case configurationUnavailable
    case physicalPathUnavailable
    case serviceUnavailable(String)
     
    case coreRefused(errorClass: String, message: String)
     
    case backedOff(until: Date, lastMessage: String)

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "App Group container \(appGroupID) unavailable — check entitlements"
        case .configurationUnavailable:
            return "No client-staged config.yaml is available in the App Group"
        case .physicalPathUnavailable:
            return "No satisfied physical Wi-Fi, cellular, or wired path is available"
        case let .serviceUnavailable(reason):
            return "Clash service unavailable: \(reason)"
        case let .coreRefused(_, message):
            return message
        case let .backedOff(until, lastMessage):
            return String(format: "Not retrying before %@ after repeated failures on this network; last: %@",
                          ISO8601DateFormatter().string(from: until), lastMessage)
        }
    }

     
     
     
     
     
    static func startFailureLine(_ error: Error) -> String {
        if case let .coreRefused(errorClass, message)? = error as? ExtensionError {
            let oneLine = message.replacingOccurrences(of: "\r\n", with: "\\n")
                .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\n")
            return "tunnel start refused (\(errorClass)): \(oneLine)"
        }
        return "tunnel start failed: \(String(describing: error))"
    }
}

 
 
 
extension ExtensionError: CustomNSError {
    static var errorDomain: String { ClashTunnelStart.startErrorDomain }

    var errorCode: Int {
        let code: ClashTunnelStart.StartErrorCode
        switch self {
        case .serviceUnavailable: code = .serviceUnavailable
        case .coreRefused: code = .coreRefused
        case .backedOff: code = .backedOff
        case .appGroupUnavailable: code = .appGroupUnavailable
        case .configurationUnavailable: code = .configurationUnavailable
        case .physicalPathUnavailable: code = .physicalPathUnavailable
        }
        return code.rawValue
    }
}

private struct PhysicalPathEvent {
    let sequence: UInt64
    let unixTimeMilliseconds: Int64
    let interfaceName: String
    let interfaceType: String
    let interfaceIndex: UInt32
    let satisfied: Bool
    let expensive: Bool
    let constrained: Bool
    let supportsIPv4: Bool
    let supportsIPv6: Bool

    var jsonObject: [String: Any] {
        [
            "sequence": sequence,
            "unixTimeMilliseconds": unixTimeMilliseconds,
            "interfaceName": interfaceName,
            "interfaceType": interfaceType,
            "interfaceIndex": interfaceIndex,
            "satisfied": satisfied,
            "expensive": expensive,
            "constrained": constrained,
            "supportsIPv4": supportsIPv4,
            "supportsIPv6": supportsIPv6,
        ]
    }
}

final class ExtensionProvider: NSObject {
    private let tunnelProvider: NEPacketTunnelProvider
     
     
     
    private let packetFlowReads: SharedPacketFlowReads
    private let startupMemorySampler: StartupMemorySampler
#if os(iOS) || os(macOS)
     
     
     
     
    var modulesHooks: ModuleTunnelHooks?
#endif
#if os(iOS) || os(macOS)
     
     
     
    lazy var widgetMailbox = WidgetMailboxService(
        provider: self,
        store: ClashWidgetMailboxStore(
            root: ClashAppIdentifiers.appGroupContainer ?? FileManager.default.temporaryDirectory
        )
    )
#endif
    private var service: ClashBoxService?
     
    private var runningConfiguration: ClashStartupOutcomeRecord.Revision?
     
     
    private var startRecorded = false
     
    private let reloadRecordLock = NSLock()
     
     
     
    private var startSettling = false
     
     
    private var startPathGeneration: PhysicalPathStartupGate.Generation?
     
     
     
    private var startAttempt: ClashStartupOutcomeRecord.Revision?
     
     
    private var startPublishedName: ClashStartupOutcomeRecord.Revision?
     
     
     
    private var startRequested: ClashStartupOutcomeRecord.Revision?
     
     
    private var tunnelStopped = false
    private var startupSamplingToken: StartupMemorySampler.Token?
    private var networkSettings: NEPacketTunnelNetworkSettings?
     
     
     
    private let settingsWriter = TunnelNetworkSettingsWriter()
    private var settingsGeneration: TunnelNetworkSettingsWriter.Generation?
    private var ipStackSettings = PacketTunnelIPStackSettings.default
    private var offeredNetworkSettings: NEPacketTunnelNetworkSettings?
    private var offeredTunnelSession: ProviderTunnelSessionLease.Session?
    private var offeredSettingsRevision: UInt64 = 0
    private var appliedSettingsRevision: UInt64?
    private var desiredPathHasIPv6 = false
     
     
     
     
     
    private var pathReapplyOwed = false
    private var pathRecoveredSinceApply = false
    private var appliedInterfaceName: String?
    private var pathReapplyTask: Task<Void, Never>?
#if os(macOS)
     
     
    private var appliedExclusionsLeftToOthers: String = ""
     
     
    private var exclusionsClaimed: Set<String> = []
    private var exclusionsReleasedAt: [String: UInt64] = [:]
    private var exclusionGraceTask: Task<Void, Never>?
     
     
    private var appliedExclusionsLeftOnScoped: Set<String> = []
    private var exclusionsScopedStay: Set<String> = []
    private var routeTableWatch: MacRouteTableWatch?
#endif
    private var tunStrictRouteRequested = false
     
     
     
     
     
     
    private var preappliedTunnel: Task<Int32, Error>?
    private var preappliedDescriptor: PreappliedTunnelDescriptor?
    private var preappliedTunIntent = ""
    private var packetFlowBridge: PacketFlowBridge?
    private var packetFlowConfiguration: PacketFlowBridgeConfiguration = .default
    private let lifecycle = ProviderLifecycle()
    private let operationGate = ProviderOperationGate()
     
     
     
    private let tunnelSessionLease = ProviderTunnelSessionLease()
    private let reloadEnvelope = ProviderReloadEnvelope()
#if os(tvOS)
     
     
    private let urlTestSweep = ClashURLTestSweep { name, url in ClashURLTest(name, url) }
#endif


    private let log = Logger(subsystem: "org.example.clash.demo.extension", category: "core")

     
     
     
     
    private let physicalPathMonitorFactory: () -> any PhysicalPathMonitoring
    private let physicalPathMonitorSession = PhysicalPathMonitorSession()
    private let pathQueueKey = DispatchSpecificKey<Void>()
    private lazy var pathQueue: DispatchQueue = {
        let queue = DispatchQueue(label: "org.example.clash.pathmonitor")
        queue.setSpecific(key: pathQueueKey, value: ())
        return queue
    }()
    private let pathLock = NSLock()
     
     
     
     
    private let stateLock = NSLock()
    private func withStateLock<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }
    private var currentService: ClashBoxService? { withStateLock { service } }

     
     
    func scriptRoutingMode() -> String? { currentService?.mode() }

     
     
     
    func setScriptRoutingMode(_ mode: String) -> Bool {
        guard let service = currentService else { return false }
        do {
            try service.setMode(mode)
            return true
        } catch {
            return false
        }
    }
    private var currentPacketFlowBridge: PacketFlowBridge? { withStateLock { packetFlowBridge } }
    private var defaultInterfaceIndex: UInt32 = 0
    private var defaultInterfaceName = ""
    private var defaultInterfaceType = ""
    private var defaultPathIsSatisfied = false
    private var defaultPathIsExpensive = false
    private var defaultPathIsConstrained = false
    private var defaultPathSupportsIPv4 = false
    private var defaultPathSupportsIPv6 = false
    private var physicalPathAvailableInterfaces: [PhysicalInterfaceInventory.PathInterface] = []
     
     
    private var handedNetworkIdentity: NetworkIdentity?
    private var physicalInterfaceIdentity = PhysicalInterfaceIdentity()
    private var physicalPathUpdateCount: UInt64 = 0
    private var physicalPathHistory: [PhysicalPathEvent] = []
    private var providerSleepCount: UInt64 = 0
    private var providerWakeCount: UInt64 = 0
     
    private var interfaceListener: (any ClashInterfaceUpdateListenerProtocol)?

    init(
        tunnelProvider: NEPacketTunnelProvider,
        startupMemorySampler: StartupMemorySampler = .shared,
        physicalPathMonitorFactory: @escaping () -> any PhysicalPathMonitoring =
            ExtensionProvider.makeDefaultPhysicalPathMonitor
    ) {
        self.tunnelProvider = tunnelProvider
        self.packetFlowReads = SharedPacketFlowReads(tunnelProvider.packetFlow)
        self.startupMemorySampler = startupMemorySampler
        self.physicalPathMonitorFactory = physicalPathMonitorFactory
        super.init()
    }

    static func makeDefaultPhysicalPathMonitor() -> any PhysicalPathMonitoring {

        ApplePhysicalPathMonitor(logHandler: { ClashLogStore.shared.append($0, stream: .app) })

    }

    private func startPathMonitor(
        settingsGeneration: TunnelNetworkSettingsWriter.Generation,
        ipStack: PacketTunnelIPStackSettings
    ) -> PhysicalPathStartupGate.Generation {
        let monitor = physicalPathMonitorFactory()
        pathLock.lock()
        defaultInterfaceIndex = 0
        defaultInterfaceName = ""
        defaultInterfaceType = ""
        defaultPathIsSatisfied = false
        defaultPathSupportsIPv4 = false
        defaultPathSupportsIPv6 = false
        defaultPathIsExpensive = false
        defaultPathIsConstrained = false
        physicalPathUpdateCount = 0
        physicalInterfaceIdentity = PhysicalInterfaceIdentity()
        handedNetworkIdentity = nil
        physicalPathHistory.removeAll(keepingCapacity: true)
        providerSleepCount = 0
        providerWakeCount = 0
        pathLock.unlock()


        return physicalPathMonitorSession.start(
            monitor: monitor,
            queue: pathQueue
        ) { [weak self] snapshot in
            guard let self else { return }
            pathLock.lock()
            let correction = notePhysicalPathForTunnelSettings(
                ready: snapshot.isReady, name: snapshot.interfaceName, supportsIPv6: snapshot.supportsIPv6
            )
            defaultInterfaceIndex = snapshot.interfaceIndex
            defaultInterfaceType = snapshot.interfaceType
            defaultPathIsExpensive = snapshot.expensive
            defaultPathIsConstrained = snapshot.constrained
            defaultPathSupportsIPv4 = snapshot.supportsIPv4
            physicalPathAvailableInterfaces = snapshot.availableInterfaces
            physicalPathUpdateCount &+= 1
            physicalPathHistory.append(PhysicalPathEvent(
                sequence: physicalPathUpdateCount,
                unixTimeMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000),
                interfaceName: snapshot.interfaceName,
                interfaceType: snapshot.interfaceType,
                interfaceIndex: snapshot.interfaceIndex,
                satisfied: snapshot.isReady,
                expensive: snapshot.expensive,
                constrained: snapshot.constrained,
                supportsIPv4: snapshot.supportsIPv4,
                supportsIPv6: snapshot.supportsIPv6
            ))
            if physicalPathHistory.count > 32 {
                physicalPathHistory.removeFirst(physicalPathHistory.count - 32)
            }
            let listener = interfaceListener
            let identity = NetworkIdentity(snapshot)
            let identityChanged = identity != handedNetworkIdentity
            handedNetworkIdentity = identity
            pathLock.unlock()
             
             
            if identityChanged { ClashSetNetworkIdentity(identity.kind, identity.routers, "", "", "") }
            followPhysicalPath(
                correction, followsPath: ipStack.tunIPv6Mode.followsPath, generation: settingsGeneration
            )
#if os(iOS) || os(macOS)
             
            widgetMailbox.pathChanged(interfaceType: snapshot.interfaceType)
#endif
            log.info("path update: default egress \(snapshot.interfaceName.isEmpty ? "none" : snapshot.interfaceName, privacy: .private) index=\(snapshot.interfaceIndex, privacy: .private)")
             
             
            listener?.updateDefaultInterface(
                snapshot.interfaceName,
                interfaceIndex: Int32(bitPattern: snapshot.interfaceIndex),
                isExpensive: snapshot.expensive,
                isConstrained: snapshot.constrained,
                supportsIPv4: snapshot.supportsIPv4,
                supportsIPv6: snapshot.supportsIPv6
            )
        }
    }

     
     
     
     
     
    struct PhysicalInterfaceIdentity {
        enum Change: Equatable { case none, renamed, recovered }
        private var lastName: String?

        mutating func observe(ready: Bool, name: String) -> Change {
            guard ready, !name.isEmpty else {
                if lastName != nil { lastName = "" }
                return .none
            }
            defer { lastName = name }
            switch lastName {
            case nil, name?: return .none
            case ""?: return .recovered
            default: return .renamed
            }
        }
    }

     
     
     
     
     
     
    static func pathSchedulesCorrection(
        pathReady: Bool, interfaceChange: PhysicalInterfaceIdentity.Change, ipv6SupportChanged: Bool, followsPath: Bool
    ) -> Bool {
        pathReady && (interfaceChange != .none || (ipv6SupportChanged && followsPath))
    }

    struct PathCorrection {
        let pathReady: Bool
        let interfaceChange: PhysicalInterfaceIdentity.Change
        let ipv6SupportChanged: Bool
        let hasIPv6: Bool
    }

     
     
    private func notePhysicalPathForTunnelSettings(
        ready: Bool, name: String, supportsIPv6: Bool
    ) -> PathCorrection {
        let ipv6SupportChanged = (defaultPathIsSatisfied && defaultPathSupportsIPv6) != (ready && supportsIPv6)
        let interfaceChange = physicalInterfaceIdentity.observe(ready: ready, name: name)
        defaultInterfaceName = name
        defaultPathIsSatisfied = ready
        defaultPathSupportsIPv6 = supportsIPv6
        return PathCorrection(
            pathReady: ready, interfaceChange: interfaceChange, ipv6SupportChanged: ipv6SupportChanged,
            hasIPv6: ready && supportsIPv6
        )
    }

     
    private func followPhysicalPath(
        _ correction: PathCorrection, followsPath: Bool, generation: TunnelNetworkSettingsWriter.Generation
    ) {
        guard Self.pathSchedulesCorrection(
            pathReady: correction.pathReady, interfaceChange: correction.interfaceChange,
            ipv6SupportChanged: correction.ipv6SupportChanged, followsPath: followsPath
        ) else {
             
             
            if !correction.pathReady { withStateLock { pathReapplyTask?.cancel() } }
            return
        }
        scheduleTunnelSettingsFollowingPath(
            hasIPv6: correction.hasIPv6, interfaceChange: correction.interfaceChange, generation: generation
        )
    }

     
     
    private var readyPhysicalInterfaceName: String? {
        pathLock.lock(); defer { pathLock.unlock() }
        return defaultPathIsSatisfied ? defaultInterfaceName : nil
    }

     
     
     
     
     
    private func scheduleTunnelSettingsFollowingPath(
        hasIPv6: Bool, interfaceChange: PhysicalInterfaceIdentity.Change,
        generation: TunnelNetworkSettingsWriter.Generation
    ) {
        settingsWriter.updateDesired(in: generation) {
            withStateLock {
                desiredPathHasIPv6 = hasIPv6
                if interfaceChange != .none { pathReapplyOwed = true }
                if interfaceChange == .recovered { pathRecoveredSinceApply = true }
                pathReapplyTask?.cancel()
                pathReapplyTask = Task { [weak self] in
                    do {
                        try await Task.sleep(nanoseconds: 250_000_000)
                        guard let self else { return }
                        try await self.reconcileTunnelSettings(in: generation)
                    } catch is CancellationError {
                         
                    } catch {
                        guard let self, self.settingsWriter.isCurrent(generation) else { return }
                        ClashLogStore.shared.append(
                            "tun: path re-apply failed: \(error.localizedDescription)", stream: .app
                        )
                    }
                }
            }
        }
    }

    private struct SettingsPlan {
        let settings: NEPacketTunnelNetworkSettings
        let revision: UInt64
        let session: ProviderTunnelSessionLease.Session?
        let interfaceName: String?
        let followsInterfaceChange: Bool
        var exclusionsLeftToOthers = ""
        var exclusionsLeftOnScoped: Set<String> = []
    }

     
     
    private var desiredIPv6Declaration: Bool {
        ipStackSettings.tunIPv6Mode.declaresIPv6(
            coreOffersIPv6: offeredNetworkSettings?.ipv6Settings != nil,
            pathReady: desiredPathHasIPv6, supportsIPv6: desiredPathHasIPv6
        )
    }

    private func offerTunnelSettings(
        _ settings: NEPacketTunnelNetworkSettings, strictRoute: Bool,
        in generation: TunnelNetworkSettingsWriter.Generation,
        session: ProviderTunnelSessionLease.Session? = nil
    ) throws {
        guard settingsWriter.updateDesired(in: generation, when: { self.isTunnelSessionCurrent(session) }, {
            withStateLock {
                offeredNetworkSettings = settings
                offeredTunnelSession = session
                offeredSettingsRevision &+= 1
                tunStrictRouteRequested = strictRoute
            }
        }) else { throw CancellationError() }
    }

     
     
     
    private func reconcileTunnelSettings(in generation: TunnelNetworkSettingsWriter.Generation) async throws {
        while true {
            try Task.checkCancellation()
            var appliedIPv6: Bool?
            var appliedAfterInterfaceChange = false
            let outcome = try await settingsWriter.perform(in: generation, prepare: { dirty -> SettingsPlan? in
                let session = self.withStateLock { self.offeredTunnelSession }
                guard self.isTunnelSessionCurrent(session) else { return nil }
                let interfaceName = self.readyPhysicalInterfaceName
#if os(macOS)
                 
                let otherRoutes = ClashTunnelRouteShaping.currentOtherInterfaceRoutes(
                    ownInterfaces: ClashTunnelRouteShaping.interfaces(carrying: Set(self.withStateLock {
                        (self.offeredNetworkSettings?.ipv4Settings?.addresses ?? [])
                            + (self.offeredNetworkSettings?.ipv6Settings?.addresses ?? [])
                    }))
                )
#endif
                return self.withStateLock {
                    guard let offered = self.offeredNetworkSettings else { return nil }
                     
                     
                     
                    let declares = interfaceName == nil
                        ? self.networkSettings.map { $0.ipv6Settings != nil } ?? self.desiredIPv6Declaration
                        : self.desiredIPv6Declaration
                     
                     
                    let reapplyDue = self.pathReapplyOwed && interfaceName.map {
                        self.pathRecoveredSinceApply || $0 != self.appliedInterfaceName
                    } ?? false
#if os(macOS)
                     
                     
                    let settings = offered.copy() as! NEPacketTunnelNetworkSettings
                    if !declares { settings.ipv6Settings = nil }
                    let (leftToOthers, leftOnScoped) = self.leaveExclusionsToOtherVPNs(
                        settings, otherRoutes: otherRoutes, generation: generation
                    )
                    let exclusionsMatch = leftToOthers == self.appliedExclusionsLeftToOthers
#else
                    let (leftToOthers, leftOnScoped, exclusionsMatch) = ("", Set<String>(), true)
#endif
                    if !dirty, !reapplyDue, exclusionsMatch, self.appliedSettingsRevision == self.offeredSettingsRevision,
                       let current = self.networkSettings,
                       (current.ipv6Settings != nil) == declares { return nil }
#if !os(macOS)
                    let settings = offered.copy() as! NEPacketTunnelNetworkSettings
                    if !declares { settings.ipv6Settings = nil }
#endif
                    return SettingsPlan(settings: settings, revision: self.offeredSettingsRevision, session: session,
                                        interfaceName: interfaceName, followsInterfaceChange: reapplyDue,
                                        exclusionsLeftToOthers: leftToOthers, exclusionsLeftOnScoped: leftOnScoped)
                }
            }, apply: { plan in
                try await self.tunnelProvider.setTunnelNetworkSettings(plan.settings)
            }, accept: { plan in
                self.isTunnelSessionCurrent(plan.session)
            }, publish: { plan in
                self.withStateLock {
                    self.networkSettings = plan.settings
                    self.appliedSettingsRevision = plan.revision
                     
                     
                    self.appliedInterfaceName = plan.interfaceName
                    self.pathReapplyOwed = false
                    self.pathRecoveredSinceApply = false
                    appliedIPv6 = plan.settings.ipv6Settings != nil
                    appliedAfterInterfaceChange = plan.followsInterfaceChange
#if os(macOS)
                    if plan.exclusionsLeftToOthers != self.appliedExclusionsLeftToOthers {
                        let left = plan.exclusionsLeftToOthers.isEmpty ? "none" : plan.exclusionsLeftToOthers
                        ClashLogStore.shared.append("tun: route-exclude left to another VPN's route: \(left)", stream: .app)
                    }
                    self.appliedExclusionsLeftToOthers = plan.exclusionsLeftToOthers
                    self.appliedExclusionsLeftOnScoped = plan.exclusionsLeftOnScoped
#endif
                }
            })
            guard settingsWriter.isCurrent(generation) else { throw CancellationError() }
            if let appliedIPv6 {
                let reason = appliedAfterInterfaceChange ? " after interface change" : ""
                ClashLogStore.shared.append("tun: IPv6 declaration applied=\(appliedIPv6)\(reason)", stream: .app)
            }
            if outcome != .superseded { return }
        }
    }

#if os(macOS)
     
     
     
     
     
     
     
     
     
     
    private func leaveExclusionsToOtherVPNs(
        _ settings: NEPacketTunnelNetworkSettings,
        otherRoutes: [ClashTunnelRouteShaping.OtherInterfaceRoute],
        generation: TunnelNetworkSettingsWriter.Generation
    ) -> (signature: String, leftOnScoped: Set<String>) {
        typealias Shaping = ClashTunnelRouteShaping
        let now = DispatchTime.now().uptimeNanoseconds
        exclusionsReleasedAt = exclusionsReleasedAt.filter { now &- $0.value < Self.exclusionRegraceNanoseconds }
        let recentlyLeft = exclusionsClaimed.union(exclusionsReleasedAt.keys)
        let v4 = settings.ipv4Settings, v6 = settings.ipv6Settings
        let excluded4 = (v4?.excludedRoutes ?? []).map { Shaping.V4(address: $0.destinationAddress, mask: $0.destinationSubnetMask) }
        let included4 = (v4?.includedRoutes ?? []).map { Shaping.V4(address: $0.destinationAddress, mask: $0.destinationSubnetMask) }
        let excluded6 = (v6?.excludedRoutes ?? []).map {
            Shaping.V6(address: $0.destinationAddress, prefix: $0.destinationNetworkPrefixLength.intValue)
        }
        let included6 = (v6?.includedRoutes ?? []).map {
            Shaping.V6(address: $0.destinationAddress, prefix: $0.destinationNetworkPrefixLength.intValue)
        }
        func splits() -> (Shaping.ExclusionSplit<Shaping.V4>, Shaping.ExclusionSplit<Shaping.V6>) {
            (Shaping.macDeclaredExclusions(excluded4, included: included4, otherRoutes: otherRoutes,
                                           recentlyLeft: recentlyLeft, scopedStays: exclusionsScopedStay),
             Shaping.macDeclaredExclusions(excluded6, included: included6, otherRoutes: otherRoutes,
                                           recentlyLeft: recentlyLeft, scopedStays: exclusionsScopedStay))
        }
        var (split4, split6) = splits()
         
         
        let stayed = Set(split4.leftOnScoped.map(Shaping.exclusionKey) + split6.leftOnScoped.map(Shaping.exclusionKey))
            .intersection(appliedExclusionsLeftOnScoped)
        if !stayed.isEmpty {
            exclusionsScopedStay.formUnion(stayed)
            (split4, split6) = splits()
        }
        if !split4.leftToOthers.isEmpty || !split4.held.isEmpty {
            v4?.excludedRoutes = split4.declared.map { NEIPv4Route(destinationAddress: $0.address, subnetMask: $0.mask) }
        }
        if !split6.leftToOthers.isEmpty || !split6.held.isEmpty {
            v6?.excludedRoutes = split6.declared.map {
                NEIPv6Route(destinationAddress: $0.address, networkPrefixLength: NSNumber(value: $0.prefix))
            }
        }
        let claimed = Set(split4.leftToOthers.map(Shaping.exclusionKey) + split6.leftToOthers.map(Shaping.exclusionKey))
        let heldKeys = split4.held.map(Shaping.exclusionKey) + split6.held.map(Shaping.exclusionKey)
        for key in heldKeys where exclusionsReleasedAt[key] == nil { exclusionsReleasedAt[key] = now }
        for key in claimed { exclusionsReleasedAt[key] = nil }
        exclusionsClaimed = claimed
         
        if !heldKeys.isEmpty, exclusionGraceTask == nil {
            exclusionGraceTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: Self.exclusionRegraceNanoseconds + 200_000_000)
                guard let self else { return }
                self.withStateLock { self.exclusionGraceTask = nil }
                guard self.settingsWriter.isCurrent(generation) else { return }
                try? await self.reconcileTunnelSettings(in: generation)
            }
        }
        let signature = (split4.leftToOthers.map(Shaping.exclusionKey) + split6.leftToOthers.map(Shaping.exclusionKey)
            + heldKeys.map { $0 + "(held)" }).joined(separator: ",")
        return (signature, Set(split4.leftOnScoped.map(Shaping.exclusionKey) + split6.leftOnScoped.map(Shaping.exclusionKey)))
    }

     
    static let exclusionRegraceNanoseconds: UInt64 = 10_000_000_000

     
     
     
    private func startRouteTableWatch(generation: TunnelNetworkSettingsWriter.Generation) {
        let watch = MacRouteTableWatch { [weak self] in
            guard let self, self.settingsWriter.isCurrent(generation) else { return }
            Task { [weak self] in
                do { try await self?.reconcileTunnelSettings(in: generation) } catch {}
            }
        }
        let previous = withStateLock { () -> MacRouteTableWatch? in
            let previous = routeTableWatch
            routeTableWatch = watch
            appliedExclusionsLeftToOthers = ""
            exclusionsClaimed = []
            exclusionsReleasedAt = [:]
            appliedExclusionsLeftOnScoped = []
            exclusionsScopedStay = []
            exclusionGraceTask?.cancel()
            exclusionGraceTask = nil
            return previous
        }
        previous?.cancel()
        watch.start()
    }

    private func stopRouteTableWatch() {
        withStateLock { () -> MacRouteTableWatch? in
            defer { routeTableWatch = nil }
            exclusionGraceTask?.cancel()
            exclusionGraceTask = nil
            return routeTableWatch
        }?.cancel()
    }
#endif

    private func clearTunnelSettings(in generation: TunnelNetworkSettingsWriter.Generation) async throws {
         
         
        let cleanup = Task {
            try await self.settingsWriter.perform(in: generation, prepare: { _ -> Bool? in true }, apply: { _ in
                try await self.tunnelProvider.setTunnelNetworkSettings(nil)
            }, publish: { _ in
                self.withStateLock {
                    self.networkSettings = nil
                    self.appliedSettingsRevision = nil
                }
            })
        }
        _ = try await cleanup.value
    }

    private func stopPathMonitor() {
        physicalPathMonitorSession.stop()
         
         
         
        if DispatchQueue.getSpecific(key: pathQueueKey) == nil {
            pathQueue.sync {}
        }
        pathLock.lock()
        interfaceListener = nil
        defaultInterfaceIndex = 0
        defaultInterfaceName = ""
        defaultInterfaceType = ""
        defaultPathSupportsIPv4 = false
        defaultPathSupportsIPv6 = false
        defaultPathIsSatisfied = false
        defaultPathIsExpensive = false
        defaultPathIsConstrained = false
        pathLock.unlock()
    }

    private func currentInterfaceIndex() -> UInt32 {
        pathLock.lock(); defer { pathLock.unlock() }
        return defaultInterfaceIndex
    }

    private func waitForPhysicalPath(
        _ generation: PhysicalPathStartupGate.Generation,
        timeoutSeconds: Double = 10
    ) async throws {
        do {
            try await physicalPathMonitorSession.wait(
                for: generation,
                timeoutNanoseconds: UInt64(max(0, timeoutSeconds) * 1_000_000_000)
            )
        } catch PhysicalPathStartupGateError.timedOut {
            throw ExtensionError.physicalPathUnavailable
        } catch PhysicalPathStartupGateError.superseded {
            throw CancellationError()
        }
    }

    func start(userInitiated: Bool = false) async throws {
        await operationGate.enter()
        var samplingToken: StartupMemorySampler.Token?
         
         
        withStateLock {
            startRecorded = false; runningConfiguration = nil; startPathGeneration = nil; startAttempt = nil; startPublishedName = nil; startRequested = nil
            tunnelStopped = false
        }
        do {
            try lifecycle.beginStart()
            try await start0(samplingToken: &samplingToken, userInitiated: userInitiated)
            try lifecycle.didStart()
            startupMemorySampler.mark("tunnel-up", token: samplingToken)
            await operationGate.leave()
        } catch {
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
            let reason = String(describing: error)
            settleStart { withStateLock { runningConfiguration = nil } }
            await recordStartFailedBeforeCore(error, userInitiated: userInitiated)
            finishStartupSampling(token: samplingToken, reason: .failed(reason))
            let line = ExtensionError.startFailureLine(error)
            log.error("\(line, privacy: .public)")
            ClashLogStore.shared.append(
                line,
                stream: .app,
                level: .error
            )
            await teardownResources(policy: .failedStart)
            lifecycle.didFailStart()
            await operationGate.leave()
            throw error
        }
    }

    private func start0(
        samplingToken outputSamplingToken: inout StartupMemorySampler.Token?,
        userInitiated: Bool
    ) async throws {
        let ipStack = try PacketTunnelIPStackSettings.decode(providerConfiguration:
            (tunnelProvider.protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration
        )
        let settingsGeneration = settingsWriter.advanceGeneration()
        settingsWriter.commitIfCurrent(settingsGeneration) {
            withStateLock {
                self.settingsGeneration = settingsGeneration
                ipStackSettings = ipStack
                desiredPathHasIPv6 = false
                pathReapplyOwed = false
                pathRecoveredSinceApply = false
                appliedInterfaceName = nil
            }
        }
         
         
         
         
         
        guard let container = ClashAppIdentifiers.appGroupContainer
        else {
            throw ExtensionError.appGroupUnavailable
        }

         
         
        let startupMemorySampler = self.startupMemorySampler
        let samplingToken = StartupMemorySampler.samplesStartup
            ? startupMemorySampler.begin(container: container) : nil
        outputSamplingToken = samplingToken
        withStateLock { startupSamplingToken = samplingToken }
        ClashLogStore.shared.append(
            "IP Stack: queryMode=\(ipStack.queryMode.rawValue) tunIPv6Mode=\(ipStack.tunIPv6Mode.rawValue)",
            stream: .app
        )

         
         
         
         
         
         
        let gateStartedAt = DispatchTime.now().uptimeNanoseconds
        let pathGeneration = startPathMonitor(settingsGeneration: settingsGeneration, ipStack: ipStack)
#if os(macOS)
        startRouteTableWatch(generation: settingsGeneration)
#endif
         
         
         
         
         
         
        let attempt: ClashStartupOutcomeRecord.Revision?
        do {
            attempt = try ConfigResourceStore(containerURL: container).publishedName()
                .map { .init(profileID: $0.profileID, revision: $0.revision) }
        } catch {
            attempt = .storeUnreadable
        }
        withStateLock {
            startPathGeneration = pathGeneration
            startAttempt = attempt
            startPublishedName = attempt == .storeUnreadable ? nil : attempt
            startRequested = startPublishedName
        }
        startupMemorySampler.mark("path-monitor-started", token: samplingToken)
         
         
         
        try await failIfBackedOffBeforeSetup(container: container, pathGeneration: pathGeneration,
                                             userInitiated: userInitiated)

         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        let systemResolverLines = ClashSystemResolverLines()
        ClashLogStore.shared.append(
            "system resolvers before the tunnel: \(systemResolverLines.isEmpty ? "none" : systemResolverLines.split(separator: "\n").joined(separator: " "))",
            stream: .app
        )
        preapplyTunnelSettingsIfKnown(
            container: container, samplingToken: samplingToken, generation: settingsGeneration,
            pathGeneration: pathGeneration, ipStack: ipStack
        )

        let options = ClashSetupOptions()
        options.ipQueryMode = ipStack.queryMode.rawValue
        options.tunIPv6Mode = ipStack.tunIPv6Mode.rawValue
        startupMemorySampler.mark("options-allocated", token: samplingToken)
        options.basePath = container.path
        options.workingPath = container.appendingPathComponent("working").path
        options.tempPath = container.appendingPathComponent("temp").path
         
         
         
         
         
         
        options.startupPhaseLogPath = container.appendingPathComponent(
            MemorySampleLog.startupPhaseFileName
        ).path
         
         
         
         
         
         
         
         
        #if os(iOS)
        options.persistentCacheDirectory = NSHomeDirectory() + "/Library/Application Support"
        #elseif os(tvOS)
        options.persistentCacheDirectory = NSHomeDirectory() + "/Library/Caches"
        #endif
        options.timeZone = TimeZone.current.identifier  
        options.logMaxLines = 1000
         
         
         
        ApplePacketTunnelRuntimePolicy.current.apply(to: options)
         
         
         
         
         
         
         
         
        if let store = CertificateStorePolicy.setupValue(
            forStored: UserDefaults(suiteName: appGroupID)?
                .string(forKey: CertificateStorePolicy.defaultsKey)
        ) {
            options.certificateStore = store
        }
         
         
         
         
         
         
         
         
         
        let allowLanPermitted = LocalNetworkPermission.isPermitted(
            UserDefaults(suiteName: appGroupID)
        )
        ClashSetAllowLanPermitted(allowLanPermitted)
         
         
        applyRemoteControlSetting()
         
         
         
         
         
         
         
         
         
        ClashLogStore.shared.append(
            "allow-lan permitted=\(allowLanPermitted)",
            stream: .app,
            level: .warning
        )
         
         
         
         
        startupMemorySampler.mark("cert-store-read", token: samplingToken)
        packetFlowConfiguration = .default



         
         
         
         
         
         
         
         
         
         
         
         
         
         
#if os(tvOS)
         
         
        let includeAllNetworks = false
#else
        let includeAllNetworks = (tunnelProvider.protocolConfiguration
            as? NETunnelProviderProtocol)?.includeAllNetworks ?? false
#endif
        options.includeAllNetworks = includeAllNetworks
        log.info("include all networks=\(includeAllNetworks)")
        options.systemDNSServerLines = systemResolverLines
        startupMemorySampler.mark("options-built", token: samplingToken)
         
         
        ExtensionLogBatchWriter.shared.attach(self)
        var error: NSError?
        ClashSetup(options, &error)
        if let error { throw error }
#if os(macOS)
         
         
        ClashConnectionOwnerBridge.install()
#endif
        startupMemorySampler.mark("setup-done", token: samplingToken)
         
         
        startupMemorySampler.note(ClashLogStore.shared.composition(), token: samplingToken)

         
         
         
         
         
         
         
         
         
         
         
         
         
         
        let collectionOptions = ClashRuntimeSetupOptions()
        collectionOptions.gcPercent = 10
        var collectionError: NSError?
        ClashReloadSetupOptions(collectionOptions, &collectionError)
        if let collectionError {
             
             
             
            ClashLogStore.shared.append(
                "gc percent not applied: " + collectionError.localizedDescription,
                stream: .app,
                level: .warning
            )
        }



        guard let service = ClashNewService(StartupPlatformInterface(
            provider: self, samplingToken: samplingToken, settingsGeneration: settingsGeneration
        ), &error) else {
            throw error ?? ExtensionError.serviceUnavailable("NewService returned nil")
        }
        startupMemorySampler.mark("service-created", token: samplingToken)
        reloadRecordLock.lock()
        startSettling = true
        withStateLock { self.service = service }
        reloadRecordLock.unlock()
         
         
        defer { settleStart() }
         
         
         
         
        var storedConfiguration: StoredConfiguration?
        do {
            storedConfiguration = try stagedConfig()
        } catch ConfigResourceStoreError.noValidConfiguration {
            storedConfiguration = nil
        }
        withStateLock {
            startAttempt = storedConfiguration.map { .init(profileID: $0.profileID, revision: $0.revision) }
            startRequested = storedConfiguration.map { stored in
                let read = ClashStartupOutcomeRecord.Revision(profileID: stored.profileID, revision: stored.revision)
                return stored.recoveredFromLastKnownGood ? (startPublishedName ?? read) : read
            }
        }
        var yaml: String
        if let storedConfiguration,
           let storedText = storedConfiguration.text {
            yaml = storedText
        } else {

            throw ExtensionError.configurationUnavailable

        }
         
         
         
         
        startupMemorySampler.note(
            "config bytes=\(yaml.utf8.count) revision=\(storedConfiguration?.revision ?? "none")",
            token: samplingToken
        )
        startupMemorySampler.mark("config-read", token: samplingToken)
        try await waitForPhysicalPath(pathGeneration)
        let gateElapsedMilliseconds =
            (DispatchTime.now().uptimeNanoseconds - gateStartedAt) / 1_000_000
        log.info("physical path gate ready after \(gateElapsedMilliseconds, privacy: .public) ms; Core start permitted")
        startupMemorySampler.mark("path-gate-ready", token: samplingToken)
#if os(iOS) || os(macOS)
         
         
        modulesHooks?.willRun(storedConfiguration.map { ModuleRunningRevision(profileID: $0.profileID, revision: $0.revision) })
#endif
         
         
         
         
        startupMemorySampler.mark("pre-core-start", token: samplingToken)
         
         
        (storedConfiguration, yaml) = try startCoreRecovering(
            service, container: container, stored: storedConfiguration, yaml: yaml,
            userInitiated: userInitiated
        )
        startupMemorySampler.mark("core-started", token: samplingToken)
         
         
         
         
         
        var intentError: NSError?
        if let box = ClashPlatformConfigIntentJSON(yaml, &intentError),
           let groupDefaults = UserDefaults(suiteName: appGroupID) {
            TunnelIntentStamp.write(box.value, to: groupDefaults)
        }
        if let storedConfiguration,
           storedConfiguration.revision != "legacy-unversioned" {
             
             
             
             
             
            let container = container
            Task.detached(priority: .utility) { [log] in
                do {
                    let store = try ConfigResourceStore(containerURL: container)
                    if storedConfiguration.recoveredFromLastKnownGood {
                         
                         
                         
                         
                         
                        log.info("configuration store started last-known-good fallback")
                    } else {
                        try store.markLastKnownGood(
                            profileID: storedConfiguration.profileID,
                            revision: storedConfiguration.revision
                        )
                    }
                } catch {
                     
                     
                     
                    log.error("configuration store could not mark startup success: \(error.localizedDescription, privacy: .private)")
                }
                startupMemorySampler.mark("lkg-marked", token: samplingToken)
            }
        }
        log.info("clash core \(ClashVersion(), privacy: .public) status=\(service.status(), privacy: .public) tz=\(ClashTZProbe(), privacy: .private)")
        ClashLogStore.shared.append(
            "tunnel started  core=\(ClashVersion()) status=\(service.status())",
            stream: .app
        )
    }

     
     
     
     
     
    private func startCoreRecovering(
        _ service: ClashBoxService,
        container: URL,
        stored: StoredConfiguration?,
        yaml: String,
        userInitiated: Bool
    ) throws -> (StoredConfiguration?, String) {
        let now = Date()
        let pathSignature = currentPathSignature()
        var state = ClashStartRecoveryState.read(in: container)
         
        let requested = withStateLock { startRequested }
        func record(_ outcome: ClashStartupOutcomeRecord.Outcome, errorClass: String? = nil, message: String? = nil,
                    running: StoredConfiguration? = nil, quarantined: ClashStartupOutcomeRecord.Quarantine? = nil,
                    backoffUntil: Date? = nil) {
            writeStartupRecord(ClashStartupOutcomeRecord(
                at: Date(), operation: "start", outcome: outcome, errorClass: errorClass, message: message,
                requested: requested,
                running: running.map { .init(profileID: $0.profileID, revision: $0.revision) },
                quarantined: quarantined, userInitiated: userInitiated, backoffUntil: backoffUntil
            ), in: container)
        }

        if stored?.recoveredFromLastKnownGood == true {
             
             
             
            withStateLock { preappliedTunIntent = "" }
        }
        let published = stored.flatMap { stored in
            stored.text.map {
                ClashStartRecovery.Candidate(profileID: stored.profileID, revision: stored.revision, yaml: $0,
                                            recovered: stored.recoveredFromLastKnownGood)
            }
        }
        let result = ClashStartRecovery.run(
            state: &state, now: now, core: Self.coreIdentity, pathSignature: pathSignature,
            userInitiated: userInitiated, published: published, fallbackYAML: published == nil ? yaml : nil,
            lastKnownGood: { current in
                guard let store = try? ConfigResourceStore(containerURL: container),
                      let pointer = try? store.lastKnownGoodPointer(),
                      pointer.profileID != current?.profileID || pointer.revision != current?.revision,
                      let loaded = try? store.loadConfiguration(profileID: pointer.profileID, revision: pointer.revision),
                      let text = loaded.text
                else { return nil }
                 
                 
                 
                self.withStateLock { self.preappliedTunIntent = "" }
#if os(iOS) || os(macOS)
                 
                self.modulesHooks?.willRun(ModuleRunningRevision(profileID: loaded.profileID, revision: loaded.revision))
#endif
                return .init(profileID: loaded.profileID, revision: loaded.revision, yaml: text, recovered: true)
            },
            start: { yaml in
                 
                 
                 
                 
                let yaml = ClashTunnelOutboundMode.applyingChoice(in: UserDefaults(suiteName: appGroupID),
                                                                  cardsAt: ClashAppIdentifiers.appGroupContainer, to: yaml)
                let outcome = service.startClassified(yaml)
                return .init(errorClass: outcome?.errorClass ?? "unknown",
                             message: outcome?.message ?? "clash: StartClassified returned nothing")
            }
        )
        try? state.write(in: container)
        func quarantine(_ q: ClashStartRecoveryState.Quarantined?) -> ClashStartupOutcomeRecord.Quarantine? {
            q.map { .init(profileID: $0.profileID, revision: $0.revision, message: $0.message, at: $0.at) }
        }
        switch result {
        case let .backedOff(until):
            withStateLock { startRecorded = true }
            let last = ClashStartupOutcomeRecord.read(in: container)?.message ?? "unknown"
            settleStart { record(.backedOff, errorClass: "unknown", message: last, backoffUntil: until) }
            ClashLogStore.shared.append(
                "start backed off until \(ISO8601DateFormatter().string(from: until)) after \(state.consecutiveFailures) failure(s) on \(pathSignature)",
                stream: .app, level: .warning)
            throw ExtensionError.backedOff(until: until, lastMessage: last)
        case let .started(running, recovered, newlyQuarantined, warning):
            let runningStored = running.map {
                StoredConfiguration(profileID: $0.profileID, revision: $0.revision, data: Data($0.yaml.utf8),
                                    recoveredFromLastKnownGood: recovered)
            } ?? stored
            if recovered, let running {
                 
                let ranName = ClashStartupOutcomeRecord.Revision(profileID: running.profileID, revision: running.revision)
                let instead = requested.map { $0 == ranName ? "no readable published pointer" : $0.revision } ?? "none"
                ClashLogStore.shared.append(
                    "started last-known-good \(running.revision) instead of \(instead)"
                        + (newlyQuarantined.map { ", which the core refused (config): \($0.message)" } ?? ""),
                    stream: .app, level: .error)
            }
             
             
            settleStart {
                withStateLock {
                    runningConfiguration = runningStored.map { .init(profileID: $0.profileID, revision: $0.revision) }
                }
                record(recovered ? .recoveredFromLastKnownGood : .started,
                       errorClass: warning == nil ? nil : ClashCoreOutcomeCommitted, message: warning,
                       running: runningStored, quarantined: quarantine(newlyQuarantined))
#if os(iOS) || os(macOS)
                 
                 
                 
                modulesHooks?.didRun(runningStored.map { ModuleRunningRevision(profileID: $0.profileID, revision: $0.revision) })
#endif
            }
            return (runningStored, running?.yaml ?? yaml)
        case let .refused(errorClass, message, newlyQuarantined):
            withStateLock { startRecorded = true }
            settleStart { record(.refused, errorClass: errorClass, message: message, quarantined: quarantine(newlyQuarantined)) }
            throw ExtensionError.coreRefused(errorClass: errorClass, message: message)
        }
    }

     
    private static let coreIdentity: String = {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(ClashVersion()) build \(build)"
    }()

    private func writeStartupRecord(_ record: ClashStartupOutcomeRecord, in container: URL) {
        do { try record.write(in: container) } catch {
            log.error("startup record not written: \(String(describing: error), privacy: .public)")
        }
    }

     
     
    private func settleStart(_ body: () -> Void = {}) {
        reloadRecordLock.lock()
        defer { reloadRecordLock.unlock() }
        body()
        startSettling = false
    }

     
     
     
    private func failIfBackedOffBeforeSetup(
        container: URL, pathGeneration: PhysicalPathStartupGate.Generation, userInitiated: Bool
    ) async throws {
        guard !userInitiated else { return }
        let state = ClashStartRecoveryState.read(in: container)
        guard let open = state.backoffUntil, Date() < open else { return }
        try? await waitForPhysicalPath(pathGeneration, timeoutSeconds: 1)
         
         
         
         
        var stored: StoredConfiguration?
        var storedKnown = true
        do {
            stored = try stagedConfig()
        } catch ConfigResourceStoreError.noValidConfiguration {
            stored = nil
        } catch {
            storedKnown = false
        }
         
         
        let attempt = withStateLock { startAttempt }
        let path = currentPathSignature()
        func held(_ name: ClashStartupOutcomeRecord.Revision?) -> Date? {
            state.backoff(now: Date(), pathSignature: path, userInitiated: false,
                          profileID: name?.profileID, revision: name?.revision)
        }
        let storedName = stored.map { ClashStartupOutcomeRecord.Revision(profileID: $0.profileID, revision: $0.revision) }
        let publishedKey: ClashStartupOutcomeRecord.Revision?? = .some(attempt)
        let heldByStore = storedKnown ? held(storedName) : nil
        guard let until = heldByStore ?? publishedKey.flatMap({ held($0) })
        else { return }
        withStateLock { startRecorded = true }
        let last = ClashStartupOutcomeRecord.read(in: container)?.message ?? "unknown"
         
         
         
         
        let name = withStateLock { startPublishedName }
        let requested = stored.map { stored in
            let read = ClashStartupOutcomeRecord.Revision(profileID: stored.profileID, revision: stored.revision)
            return stored.recoveredFromLastKnownGood ? (name ?? read) : read
        } ?? (heldByStore != nil ? nil : name)
        writeStartupRecord(ClashStartupOutcomeRecord(
            at: Date(), operation: "start", outcome: .backedOff, errorClass: "unknown", message: last,
            requested: requested,
            userInitiated: false, backoffUntil: until
        ), in: container)
        ClashLogStore.shared.append(
            "start backed off before Setup until \(ISO8601DateFormatter().string(from: until)) after \(state.consecutiveFailures) failure(s)",
            stream: .app, level: .warning)
        throw ExtensionError.backedOff(until: until, lastMessage: last)
    }

     
     
     
    private func recordStartFailedBeforeCore(_ error: Error, userInitiated: Bool) async {
         
         
        if error is CancellationError { return }
        if let lifecycleError = error as? ProviderLifecycleError, case .invalidTransition = lifecycleError { return }
        guard !withStateLock({ startRecorded }), let container = ClashAppIdentifiers.appGroupContainer else { return }
         
         
        if let generation = withStateLock({ startPathGeneration }) {
            try? await waitForPhysicalPath(generation, timeoutSeconds: 1)
        }
        let message = String(describing: error)
         
         
         
        if !(error is PacketTunnelIPStackSettings.InvalidSnapshot) {
            var state = ClashStartRecoveryState.read(in: container)
            let attempt = withStateLock { startAttempt }
            state.noteFailure(endedAt: Date(), pathSignature: currentPathSignature(),
                              profileID: attempt?.profileID, revision: attempt?.revision)
            try? state.write(in: container)
        }
        writeStartupRecord(ClashStartupOutcomeRecord(
            at: Date(), operation: "start", outcome: .refused, errorClass: "unknown", message: message,
            requested: withStateLock { startRequested }, userInitiated: userInitiated
        ), in: container)
    }

     
    private func currentPathSignature() -> String {
        pathLock.lock(); defer { pathLock.unlock() }
        guard let last = physicalPathHistory.last else { return "none" }
        return "\(last.interfaceType):\(last.interfaceName)"
    }

    private func stagedConfig() throws -> StoredConfiguration {
        guard let container = ClashAppIdentifiers.appGroupContainer
        else { throw ExtensionError.appGroupUnavailable }
        return try ConfigResourceStore(containerURL: container).loadCurrent()
    }

    func stop(reason: NEProviderStopReason) async {
         
         
         
         
         
        let stopBegan = DispatchTime.now()
        await operationGate.enter()
        let gateWaitMs = Self.milliseconds(since: stopBegan)
        guard lifecycle.beginStop() else {
            await operationGate.leave()
            return
        }
#if os(tvOS)
         
         
        urlTestSweep.close()
#endif
        markStopped()
         
         
         
         
         
         
         
         
         
         
         
         
        let summary = clashStopReasonSummary(reason)
        finishStartupSampling(
            token: withStateLock { startupSamplingToken }, reason: .stopped(summary)
        )
        log.info("stopping packet tunnel, \(summary, privacy: .public)")
        ClashLogStore.shared.append(
            "tunnel stopping  \(summary)",
            stream: .app,
            level: .warning
        )
        Self.clearOutlivedPressureEvidence()
        ClashLogStore.shared.flush()
        let steps = await teardownResources(policy: .systemStop)
        ClashLogStore.shared.append(
            "tunnel stopped  gate=\(gateWaitMs)ms \(steps) total=\(Self.milliseconds(since: stopBegan))ms",
            stream: .app
        )
        ClashLogStore.shared.flush()
        lifecycle.didStop()
        await operationGate.leave()
    }

     
     
     
     
     
     
     
    private static func clearOutlivedPressureEvidence() {
        var error: NSError?
        guard let evidence = ClashConsumeOOMEvidence(&error) else { return }
        ClashLogStore.shared.append(#"memory pressure this run outlived, cleared at a clean stop: "# + evidence.value,
                                    stream: .app, level: .warning)
    }

    private static func milliseconds(since start: DispatchTime) -> Int {
        Int((DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds) / 1_000_000)
    }

    private func finishStartupSampling(
        token: StartupMemorySampler.Token?, reason: StartupMemorySampler.FinishReason
    ) {
        withStateLock {
            if startupSamplingToken == token { startupSamplingToken = nil }
        }
         
         
        startupMemorySampler.finish(token: token, reason: reason)
    }

     
     
    @discardableResult
    private func teardownResources(policy: ProviderTeardownPolicy) async -> String {
        let closeBegan = DispatchTime.now()
        var closeMs = 0, bridgeMs = 0, settingsMs = 0
        let cleanupGeneration = settingsWriter.advanceGeneration()
         
         
         
         
        stopPathMonitor()
#if os(macOS)
        stopRouteTableWatch()
#endif
         
         
         
        tunnelSessionLease.invalidate()
         
         
         
        let (svc, bridge) = withStateLock {
            () -> (ClashBoxService?, PacketFlowBridge?) in
            let s = service
            let b = packetFlowBridge
            pathReapplyTask?.cancel()
            pathReapplyTask = nil
            preappliedTunnel?.cancel()
            preappliedTunnel = nil
            preappliedDescriptor = nil
            preappliedTunIntent = ""
            settingsGeneration = nil
            offeredNetworkSettings = nil
            offeredTunnelSession = nil
            appliedSettingsRevision = nil
            desiredPathHasIPv6 = false
            pathReapplyOwed = false
            pathRecoveredSinceApply = false
            appliedInterfaceName = nil
            service = nil
            packetFlowBridge = nil
            networkSettings = nil
            tunStrictRouteRequested = false
            return (s, b)
        }
        if let svc {
            let began = DispatchTime.now()
            defer { closeMs = Self.milliseconds(since: began) }
            do {
                try svc.close()
            } catch {
                log.error("service close failed: \(error.localizedDescription, privacy: .private)")
                ClashLogStore.shared.append(
                    "service close failed  \(error.localizedDescription)",
                    stream: .app,
                    level: .error
                )
            }
        }
        let bridgeBegan = DispatchTime.now()
        bridge?.stop()
        bridgeMs = Self.milliseconds(since: bridgeBegan)
        if policy.clearsNetworkSettings, settingsWriter.hasSubmittedSettings {
            let began = DispatchTime.now()
            do {
                try await clearTunnelSettings(in: cleanupGeneration)
            } catch {
                log.error("clear tunnel settings failed: \(error.localizedDescription, privacy: .private)")
            }
            settingsMs = Self.milliseconds(since: began)
        }
        return "detach=\(Self.milliseconds(since: closeBegan) - closeMs - bridgeMs - settingsMs)ms close=\(closeMs)ms bridge=\(bridgeMs)ms settings=\(settingsMs)ms"
    }

    func sleep() {
        pathLock.lock()
        providerSleepCount &+= 1
        let count = providerSleepCount
        pathLock.unlock()
        currentService?.pause()
         
         
        ClashLogStore.shared.append("provider sleep  n=\(count)", stream: .app)
        ClashLogStore.shared.flush()
    }

    func wake() {
        pathLock.lock()
        providerWakeCount &+= 1
        let count = providerWakeCount
        pathLock.unlock()
        currentService?.wake()
        ClashLogStore.shared.append("provider wake  n=\(count)", stream: .app)
    }

     
     
    static let remoteControlKey = "core.remote-control"

     
     
     
    private func applyRemoteControlSetting() {
        guard let settings = UserDefaults(suiteName: appGroupID)?.string(forKey: Self.remoteControlKey) else { return }
        _ = ClashApplyRemoteControl(settings)
    }

     
     
     
    private final class MessageFollowUp {
        var run: (() -> Void)?
    }

     
     
     
     
     
     
     
     
    func handleMessage(_ data: Data) async -> (reply: Data, afterReply: (() -> Void)?) {
        let followUp = MessageFollowUp()
        let reply = await respond(to: data, followUp: followUp)
        return (reply, followUp.run)
    }

    private func respond(to data: Data, followUp: MessageFollowUp) async -> Data {
        guard let req = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cmd = req["cmd"] as? String
        else {
            return refusedRequest("bad request")
        }
        switch cmd {
        case "hello":
            return jsonObject([
                "schemaVersion": ClashCommandSchemaVersion,
                "minSchemaVersion": ClashCommandSchemaMinVersion,
                "coreVersion": ClashVersion(),
                "capabilities": ["stun-v1", ProviderReloadEnvelope.capability]
            ])
        case "remoteControl":
             
             
             
             
             
            guard let settings = UserDefaults(suiteName: appGroupID)?.string(forKey: Self.remoteControlKey) else {
                return appError("There is no External Controller setting.", english: "no External Controller setting")
            }
            let status = await Task.detached { ClashApplyRemoteControl(settings) }.value
            return Data(status.utf8)
        case "runtimeDiagnostics":
            guard let service = currentService else { return appError("Not connected", english: "service not running") }
            return runtimeDiagnosticsData(service)
        case "consumeGoCrashReport":
             
             
             
             
            var crashError: NSError?
            guard let report = ClashConsumeGoCrashReport(&crashError) else {
                return jsonError(
                    crashError?.localizedDescription ?? "no Go crash report"
                )
            }
            return Data(report.value.utf8)
        case "consumeOOMEvidence":
            var consumeError: NSError?
            guard let evidence = ClashConsumeOOMEvidence(&consumeError) else {
                return jsonError(consumeError?.localizedDescription ?? "OOM evidence unavailable")
            }
            return Data(evidence.value.utf8)
        case "reload":
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
            guard let service = currentService else { return reloadRefused("service not running", errorClass: ClashCoreOutcomeRestart) }
            do {
                let stored = try stagedConfig()
                guard let yaml = stored.text else {
                    return reloadRefused("staged config is not UTF-8", errorClass: ClashCoreOutcomeConfig)
                }
                let reply = reloadEnvelope.replyClassified(to: req, apply: reloadThroughCore(service, stored: stored, yaml: yaml))
                followUp.run = reply.start
                return jsonObject(reply.object)
            } catch {
                return reloadRefused(error.localizedDescription, errorClass: ClashCoreOutcomeConfig)
            }
        case "reloadStatus":
             
             
             
             
             
            return jsonObject(reloadEnvelope.statusReply(to: req))


        case "status": return Data(ClashStatusJSON().utf8)
        case "traffic": return Data(ClashTrafficJSON().utf8)
        case "connections": return Data(ClashConnectionsJSON().utf8)
        case "proxies": return Data(ClashProxiesJSON().utf8)
#if os(tvOS)
         
         
         
         
         
         
         
        case "proxiesSummary": return Data(ClashProxiesSummaryJSON().utf8)
         
         
         
        case "urltestSweep":
            guard currentService != nil else { return appError("Not connected", english: "service not running") }
            guard let probes = ClashURLTestSweep.probes(from: req) else { return refusedRequest("missing probes") }
            let width = (req["width"] as? NSNumber)?.intValue ?? 1
            let floor = ((req["failureFloorMilliseconds"] as? NSNumber)?.doubleValue ?? 0) / 1000
            guard let id = urlTestSweep.start(probes, width: width, failureFloor: floor) else {
                return appError("Not connected", english: "service not running")
            }
            return jsonObject(ClashURLTestSweep.startReply(sweep: id, count: probes.count))
        case "urltestSweepRead":
            guard let id = (req["sweep"] as? NSNumber)?.uint64Value, let reading = urlTestSweep.read(id) else {
                return refusedRequest("no such sweep")
            }
            return jsonObject(reading.reply)
        case "urltestSweepStop":
            urlTestSweep.stop((req["sweep"] as? NSNumber)?.uint64Value)
            return okJSON()
        case "groupMembers":
            guard let group = req["group"] as? String else { return refusedRequest("missing group") }
            return Data(ClashGroupMembersJSON(group, Self.pageOffset(req), Self.pageLimit(req)).utf8)
        case "providerNodes":
            guard let provider = req["provider"] as? String else { return refusedRequest("missing provider") }
            return Data(ClashProviderNodesJSON(provider, Self.pageOffset(req), Self.pageLimit(req)).utf8)
        case "proxiesPage":
            return Data(ClashProxiesPageJSON(req["after"] as? String ?? "", Self.pageLimit(req)).utf8)
         
         
         
         
        case "proxyDelaysPage":
            let since = (req["since"] as? NSNumber)?.int64Value ?? 0
            return Data(ClashProxyDelaysPageJSON(since, req["after"] as? String ?? "", Self.pageLimit(req)).utf8)
         
         
         
         
         
         
        case "rulesPage":
            return Data(ClashRulesPageJSON(Self.pageOffset(req), Self.pageLimit(req), Self.ruleTypesJSON(req)).utf8)
        case "ruleHits":
            return Data(ClashRuleHitsJSON(Self.pageOffset(req), Self.pageLimit(req)).utf8)
         
         
         
         
         
         
         
         
        case "seedProviderFile":
            guard let kind = req["kind"] as? String, let name = req["name"] as? String,
                  let path = req["payloadPath"] as? String, let seed = req["seed"] as? String,
                  let expected = req["expectedConfigSHA256"] as? String else {
                return refusedRequest("missing kind/name/payloadPath/seed/expectedConfigSHA256")
            }
            let timeout = Int32(clamping: (req["timeoutMilliseconds"] as? Int) ?? 20_000)
            let answer = await Task.detached { ClashSeedProviderFileJSON(kind, name, path, seed, expected, timeout) }.value
            return Data(answer.utf8)
         
         
         
         
        case "updateProvider":
            guard let kind = req["kind"] as? String, let name = req["name"] as? String else {
                return refusedRequest("missing kind/name")
            }
            let timeout = Int32(clamping: (req["timeoutMilliseconds"] as? Int) ?? 20_000)
            let answer = await Task.detached { ClashUpdateProviderJSON(kind, name, timeout) }.value
            return Data(answer.utf8)
#endif
        case "ruleProviders":
            guard currentService != nil else { return appError("Not connected", english: "service not running") }
            return Data(ClashRuleProvidersJSON().utf8)
        case "logs": return Data(ClashRecentLogsJSON().utf8)
        case "setMode":
            guard let mode = req["mode"] as? String else { return refusedRequest("missing mode") }
            do {
                let service = currentService
                let before = service?.mode()
                try service?.setMode(mode)
#if !os(tvOS)
                 
                 
                 
                 
                if service != nil, (req["closes"] as? Bool) ?? true,
                   let defaults = UserDefaults(suiteName: appGroupID),
                   ClashConnectionsOnSwitch.closesAfterModeSwitch(
                       from: before, to: mode, settingIsOn: ClashConnectionsOnSwitch.isOn(in: defaults)) {
                    ClashCloseAllConnections()
                }
#endif
                return okJSON()
            } catch { return jsonError(error.localizedDescription) }
        case "select":
            guard let group = req["group"] as? String, let name = req["name"] as? String
            else { return refusedRequest("missing group/name") }
            var selectErr: NSError?
            ClashSelectProxy(group, name, &selectErr)
            if let selectErr { return jsonError(selectErr.localizedDescription) }
            return okJSON()
         
         
         
        case "unfix":
            guard let group = req["group"] as? String else { return refusedRequest("missing group") }
            var unfixErr: NSError?
            ClashUnfixProxy(group, &unfixErr)
            if let unfixErr { return jsonError(unfixErr.localizedDescription) }
            return okJSON()
        case "urltest":
            guard let name = req["name"] as? String else { return refusedRequest("missing name") }
            let delay = ClashURLTest(name, req["url"] as? String ?? "")
            return Data("{\"delay\":\(delay)}".utf8)
         
         
         
        case "dnsQuery":
            guard currentService != nil else { return appError("Not connected", english: "service not running") }
            guard let name = req["name"] as? String else { return refusedRequest("missing name") }
            return Data(ClashDNSQueryJSON(name, req["type"] as? String ?? "A").utf8)
        case "close":
            guard let id = req["id"] as? String else { return refusedRequest("missing id") }
            return Data("{\"closed\":\(ClashCloseConnection(id))}".utf8)
        case "closeAll":
            ClashCloseAllConnections(); return okJSON()
         
         
         
         
         
         
         
         
         
        case "proxyShareStart":
            guard let service = currentService else { return appError("Not connected", english: "service not running") }
            guard let requested = req["port"] as? NSNumber else { return refusedRequest("missing port") }
             
             
             
             
             
            guard let port = Int32(exactly: requested.doubleValue) else { return appError("The port must be a whole number.", english: "port must be a whole number") }
            do {
                try service.startProxyShare(port, username: req["username"] as? String ?? "", password: req["password"] as? String ?? "")
                return proxyShareStatusReply(service)
            } catch {
                return jsonError(error.localizedDescription)
            }
        case "proxyShareStop":
            guard let service = currentService else { return appError("Not connected", english: "service not running") }
            do {
                try service.stopProxyShare()
                return proxyShareStatusReply(service)
            } catch {
                return jsonError(error.localizedDescription)
            }
        case "proxyShareStatus":
            guard let service = currentService else { return appError("Not connected", english: "service not running") }
            return proxyShareStatusReply(service)
        default:
            return refusedRequest("unknown cmd \(cmd)")
        }
    }

#if os(tvOS)
     
     
     
     
    static let largestNodePage: Int32 = 2_000

    private static func pageLimit(_ req: [String: Any]) -> Int32 {
        let asked = Int32(clamping: (req["limit"] as? NSNumber)?.intValue ?? 0)
        return asked > 0 ? min(asked, largestNodePage) : largestNodePage
    }

    private static func pageOffset(_ req: [String: Any]) -> Int32 {
        max(0, Int32(clamping: (req["offset"] as? NSNumber)?.intValue ?? 0))
    }

     
     
     
    private static func ruleTypesJSON(_ req: [String: Any]) -> String {
        if let text = req["types"] as? String { return text }
        guard let list = req["types"] as? [String],
              let data = try? JSONSerialization.data(withJSONObject: list) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
#endif

    private func okJSON() -> Data { Data("{\"ok\":true}".utf8) }
    private func jsonObject(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? refusedRequest("encode response")
    }
     
     
     
     
     
     
     
     
     
     
     
    private func refusedRequest(_ detail: String) -> Data {
        ClashLogStore.shared.append("ipc: request refused: \(detail)", stream: .app)
        return appError("Clash couldn't do that", english: detail)
    }

    private func appError(_ key: String, _ arguments: String..., english: String) -> Data {
        Data((try? JSONSerialization.data(withJSONObject: ["error": english, "errorKey": key, "errorArguments": arguments]))
            ?? Data("{\"error\":\"?\"}".utf8))
    }

    private func jsonError(_ msg: String) -> Data {
        Data((try? JSONSerialization.data(withJSONObject: ["error": msg])) ?? Data("{\"error\":\"?\"}".utf8))
    }

    private func jsonError(_ msg: String, errorClass: String) -> Data {
        Data((try? JSONSerialization.data(withJSONObject: ["error": msg, "errorClass": errorClass]))
            ?? Data("{\"error\":\"?\"}".utf8))
    }

     
     
     
    private func reloadThroughCore(
        _ service: ClashBoxService, stored: StoredConfiguration, yaml published: String
    ) -> () -> ProviderReloadEnvelope.Verdict {
        { [weak self] in
            guard let self else {
                return .init(errorClass: ClashCoreOutcomeRestart, message: "extension is gone")
            }
            self.reloadRecordLock.lock()
            defer { self.reloadRecordLock.unlock() }
            let requested = ClashStartupOutcomeRecord.Revision(profileID: stored.profileID, revision: stored.revision)
            if self.startSettling {
                 
                let verdict = ProviderReloadEnvelope.Verdict(
                    errorClass: ClashCoreOutcomeRestart, message: "service not running: the tunnel is still starting")
                self.recordReload(verdict, requested: requested)
                return verdict
            }
#if os(tvOS)
             
             
             
            self.urlTestSweep.stop()
#endif
#if os(iOS) || os(macOS)
             
             
            self.modulesHooks?.willRun(ModuleRunningRevision(profileID: stored.profileID, revision: stored.revision))
#endif
             
             
             
            let defaults = UserDefaults(suiteName: appGroupID)
             
             
            ClashSetAllowLanPermitted(LocalNetworkPermission.isPermitted(UserDefaults(suiteName: appGroupID)))
            self.applyRemoteControlSetting()
            let yaml = ClashTunnelOutboundMode.applyingChoice(in: defaults, cardsAt: ClashAppIdentifiers.appGroupContainer, to: published)
            let outcome = service.reloadClassified(yaml)
            let verdict = ProviderReloadEnvelope.Verdict(
                errorClass: outcome?.errorClass ?? "unknown",
                message: outcome?.message ?? "clash: ReloadClassified returned nothing"
            )
            self.recordReload(verdict, requested: requested)
#if os(iOS) || os(macOS)
             
            self.modulesHooks?.didRun(self.withStateLock { self.runningConfiguration }
                .map { ModuleRunningRevision(profileID: $0.profileID, revision: $0.revision) })
#endif
            return verdict
        }
    }

     
    private func reloadRefused(_ message: String, errorClass: String) -> Data {
        let requested = (try? stagedConfig()).map {
            ClashStartupOutcomeRecord.Revision(profileID: $0.profileID, revision: $0.revision)
        }
        reloadRecordLock.lock()
        recordReload(.init(errorClass: errorClass, message: message), requested: requested)
        reloadRecordLock.unlock()
        return jsonError(message, errorClass: errorClass)
    }

     
     
     
    private func markStopped() {
        reloadRecordLock.lock()
        defer { reloadRecordLock.unlock() }
        withStateLock { runningConfiguration = nil; tunnelStopped = true }
    }

     
     
     
    private func recordReload(_ verdict: ProviderReloadEnvelope.Verdict, requested: ClashStartupOutcomeRecord.Revision?) {
        guard let container = ClashAppIdentifiers.appGroupContainer else { return }
         
        guard !withStateLock({ tunnelStopped }) else { return }
        let outcome: ClashStartupOutcomeRecord.Outcome
        let running: ClashStartupOutcomeRecord.Revision?
        switch verdict.errorClass {
        case "", ClashCoreOutcomeCommitted:
            outcome = .reloaded
            running = requested
            withStateLock { runningConfiguration = requested }
             
            var state = ClashStartRecoveryState.read(in: container)
            state.noteSuccess(profileID: requested?.profileID, revision: requested?.revision)
            try? state.write(in: container)
        case ClashCoreOutcomeConfig, ClashCoreOutcomeMemory, ClashCoreOutcomeRestart:
            outcome = .refusedKeptRunning
            running = withStateLock { runningConfiguration }
        default:
            outcome = .refused
            running = nil
            withStateLock { runningConfiguration = nil }
        }
        writeStartupRecord(ClashStartupOutcomeRecord(
            at: Date(), operation: "reload", outcome: outcome,
            errorClass: verdict.errorClass.isEmpty ? nil : verdict.errorClass,
            message: verdict.message.isEmpty ? nil : verdict.message,
            requested: requested, running: running
        ), in: container)
    }

     
     
     
     
    private func proxyShareStatusReply(_ service: ClashBoxService) -> Data {
        guard let data = service.proxyShareStatusJSON().data(using: .utf8),
              let status = try? JSONSerialization.jsonObject(with: data)
        else { return refusedRequest("proxy share status is not JSON") }
        return jsonObject(["ok": true, "status": status])
    }

    private func runtimeDiagnosticsData(_ service: ClashBoxService) -> Data {
        guard let data = service.runtimeDiagnosticsJSON().data(using: .utf8),
              var diagnostics = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return refusedRequest("invalid core diagnostics") }
        let (strictRoute, settingsSnapshot) = withStateLock { (tunStrictRouteRequested, networkSettings) }
         
         
         
         
         
        diagnostics["extensionMemoryFootprintBytes"] = ClashMemoryFootprint()
        diagnostics["lowMemoryBuild"] = ClashLowMemoryBuild()
        diagnostics["tunStrictRouteRequested"] = strictRoute
        diagnostics["appleIPv4IncludedRouteCount"] = settingsSnapshot?.ipv4Settings?.includedRoutes?.count ?? 0
        diagnostics["appleIPv4ExcludedRouteCount"] = settingsSnapshot?.ipv4Settings?.excludedRoutes?.count ?? 0
        diagnostics["appleIPv6IncludedRouteCount"] = settingsSnapshot?.ipv6Settings?.includedRoutes?.count ?? 0
        diagnostics["appleIPv6ExcludedRouteCount"] = settingsSnapshot?.ipv6Settings?.excludedRoutes?.count ?? 0
        diagnostics["appleMTU"] = settingsSnapshot?.mtu?.intValue ?? 0
        let droppedLogBatchCount = ExtensionLogBatchWriter.shared.droppedBatchCount
        pathLock.lock()
        diagnostics["applePhysicalInterfaceName"] = defaultInterfaceName
        diagnostics["applePhysicalInterfaceType"] = defaultInterfaceType
        diagnostics["applePhysicalInterfaceIndex"] = defaultInterfaceIndex
        diagnostics["applePhysicalPathSatisfied"] = defaultPathIsSatisfied
        diagnostics["applePhysicalPathExpensive"] = defaultPathIsExpensive
        diagnostics["applePhysicalPathConstrained"] = defaultPathIsConstrained
        diagnostics["applePhysicalPathSupportsIPv4"] = defaultPathSupportsIPv4
        diagnostics["applePhysicalPathSupportsIPv6"] = defaultPathSupportsIPv6
        diagnostics["applePhysicalPathUpdateCount"] = physicalPathUpdateCount
        diagnostics["applePhysicalPathHistory"] = physicalPathHistory.map(\.jsonObject)
        diagnostics["appleProviderSleepCount"] = providerSleepCount
        diagnostics["appleProviderWakeCount"] = providerWakeCount
        diagnostics["extensionLogBatchesDropped"] = droppedLogBatchCount
        pathLock.unlock()
        if let bridge = currentPacketFlowBridge?.snapshot() {
            diagnostics["packetFlowReadCallbackBatches"] = bridge.readCallbackBatches
            diagnostics["packetFlowPacketsFromSystem"] = bridge.packetsFromSystem
            diagnostics["packetFlowBytesFromSystem"] = bridge.bytesFromSystem
            diagnostics["packetFlowPacketsToCore"] = bridge.packetsToCore
            diagnostics["packetFlowBytesToCore"] = bridge.bytesToCore
            diagnostics["packetFlowSendSyscallCount"] = bridge.sendSyscallCount
            diagnostics["packetFlowSendWouldBlockCount"] = bridge.sendWouldBlockCount
            diagnostics["packetFlowSendENOBUFSCount"] = bridge.sendENOBUFSCount
            diagnostics["packetFlowSendENOMEMCount"] = bridge.sendENOMEMCount
            diagnostics["packetFlowReceiveWouldBlockCount"] = bridge.receiveWouldBlockCount
            diagnostics["packetFlowReceiveENOBUFSCount"] = bridge.receiveENOBUFSCount
            diagnostics["packetFlowReceiveENOMEMCount"] = bridge.receiveENOMEMCount
            diagnostics["packetFlowSendBackoffCount"] = bridge.sendBackoffCount
            diagnostics["packetFlowSendAccumulatedBackoffNanoseconds"] = bridge.sendAccumulatedBackoffNanoseconds
            diagnostics["packetFlowReceiveBackoffCount"] = bridge.receiveBackoffCount
            diagnostics["packetFlowReceiveAccumulatedBackoffNanoseconds"] = bridge.receiveAccumulatedBackoffNanoseconds
            diagnostics["packetFlowPacketsToSystem"] = bridge.packetsToSystem
            diagnostics["packetFlowDroppedToCore"] = bridge.droppedToCore
            diagnostics["packetFlowDroppedToSystem"] = bridge.droppedToSystem
            diagnostics["packetFlowPendingPackets"] = bridge.pendingPackets
            diagnostics["packetFlowPendingBytes"] = bridge.pendingBytes
            diagnostics["packetFlowPeakPendingPackets"] = bridge.peakPendingPackets
            diagnostics["packetFlowPeakPendingBytes"] = bridge.peakPendingBytes
            diagnostics["packetFlowQueueLatencySamples"] = bridge.queueLatencySamples
            diagnostics["packetFlowAverageQueueLatencyNanoseconds"] = bridge.averageQueueLatencyNanoseconds
            diagnostics["packetFlowMaxQueueLatencyNanoseconds"] = bridge.maxQueueLatencyNanoseconds
            diagnostics["packetFlowSystemWriteCalls"] = bridge.systemWriteCalls
            diagnostics["packetFlowMaxSystemWriteBatch"] = bridge.maxSystemWriteBatch
            diagnostics["packetFlowConfiguredMaxDrainBatch"] = bridge.configuredMaxDrainBatch
            diagnostics["packetFlowCoreToSystemFlushNanoseconds"] = bridge.coreToSystemFlushNanoseconds
            diagnostics["packetFlowSocketBufferRequestedBytes"] = bridge.socketBufferRequestedBytes
            diagnostics["packetFlowFlowEndpointSendBufferBytes"] = bridge.flowEndpointSendBufferBytes
            diagnostics["packetFlowFlowEndpointReceiveBufferBytes"] = bridge.flowEndpointReceiveBufferBytes
            diagnostics["packetFlowCoreEndpointSendBufferBytes"] = bridge.coreEndpointSendBufferBytes
            diagnostics["packetFlowCoreEndpointReceiveBufferBytes"] = bridge.coreEndpointReceiveBufferBytes
            diagnostics["packetFlowFlowEndpointSendBufferSetErrno"] = bridge.flowEndpointSendBufferSetErrno
            diagnostics["packetFlowFlowEndpointReceiveBufferSetErrno"] = bridge.flowEndpointReceiveBufferSetErrno
            diagnostics["packetFlowCoreEndpointSendBufferSetErrno"] = bridge.coreEndpointSendBufferSetErrno
            diagnostics["packetFlowCoreEndpointReceiveBufferSetErrno"] = bridge.coreEndpointReceiveBufferSetErrno
            diagnostics["packetFlowFlowEndpointSendBufferGetErrno"] = bridge.flowEndpointSendBufferGetErrno
            diagnostics["packetFlowFlowEndpointReceiveBufferGetErrno"] = bridge.flowEndpointReceiveBufferGetErrno
            diagnostics["packetFlowCoreEndpointSendBufferGetErrno"] = bridge.coreEndpointSendBufferGetErrno
            diagnostics["packetFlowCoreEndpointReceiveBufferGetErrno"] = bridge.coreEndpointReceiveBufferGetErrno
        }
        return jsonObject(diagnostics)
    }

    private func writeRestartEvidence(
        requested: Int,
        completed: Int,
        processIdentifiers: [Int32],
        goroutineCounts: [Int],
        error: String
    ) {
        guard let container = ClashAppIdentifiers.appGroupContainer,
              let data = try? JSONSerialization.data(withJSONObject: [
                "requested": requested,
                "completed": completed,
                "processIdentifiers": processIdentifiers,
                "goroutineCounts": goroutineCounts,
                "error": error
              ], options: [.sortedKeys])
        else { return }
        try? data.write(
            to: container.appendingPathComponent("provider-restart-evidence.json"),
            options: .atomic
        )
    }


}

 
 
 
 
 
 
 
 
 
 
final class ExtensionLogBatchWriter: NSObject, ClashLogBatchWriterProtocol, @unchecked Sendable {
    static let shared = ExtensionLogBatchWriter()

    private let lock = NSLock()
    private weak var provider: ExtensionProvider?
    private var registered = false
     
     
     
    private var droppedBatches: UInt64 = 0

    var droppedBatchCount: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return droppedBatches
    }

    func attach(_ provider: ExtensionProvider) {
        lock.lock()
        self.provider = provider
        let first = !registered
        registered = true
        lock.unlock()
        if first { ClashSetLogBatchWriter(self) }
    }

    func writeLogBatch(_ linesJSON: String?) {
        guard let linesJSON,
              let lines = (try? JSONSerialization.jsonObject(with: Data(linesJSON.utf8))) as? [String]
        else {
            lock.lock()
            droppedBatches &+= 1
            lock.unlock()
            return
        }
        lock.lock()
        let provider = self.provider
        lock.unlock()
        guard let provider else { return }
        for line in lines { provider.writeLog(line) }
    }
}

 
 
extension ExtensionProvider: ClashPlatformInterfaceProtocol {
     
     
     
     
    func tunFailed(_ reason: String?) {
        guard let generation = withStateLock({ settingsGeneration }) else { return }
        tunFailed(reason, generation: generation)
    }

     
     
     
    fileprivate func tunFailed(_ reason: String?, generation: TunnelNetworkSettingsWriter.Generation) {
        let reason = reason ?? "no reason given"
        guard withStateLock({ settingsGeneration }) == generation else {
            ClashLogStore.shared.append("tunnel descriptor failed under a service that was replaced; the tunnel stays  \(reason)",
                                        stream: .app, level: .warning)
            return
        }
        log.error("tunnel descriptor failed: \(reason, privacy: .public)")
        ClashLogStore.shared.append("tunnel descriptor failed, ending the tunnel  \(reason)", stream: .app, level: .error)
        tunnelProvider.cancelTunnelWithError(ExtensionError.serviceUnavailable("the tunnel's descriptor failed: \(reason)"))
    }

    func writeLog(_ message: String?) {
        guard let message else { return }
        log.info("[core] \(message, privacy: .private)")
         
         
         
        ClashLogStore.shared.append(message, stream: .core)
    }

     
     
     
    func openTun(_ options: (any ClashTunOptionsProtocol)?, ret0_: UnsafeMutablePointer<Int32>?) throws {
         
         
        guard let generation = withStateLock({ settingsGeneration }) else { throw CancellationError() }
        try openTun(options, ret0_: ret0_, samplingToken: nil, generation: generation)
    }

    fileprivate func openTun(
        _ options: (any ClashTunOptionsProtocol)?, ret0_: UnsafeMutablePointer<Int32>?,
        samplingToken: StartupMemorySampler.Token?, generation: TunnelNetworkSettingsWriter.Generation
    ) throws {
        guard let options else {
            throw ExtensionError.serviceUnavailable("OpenTun: nil options")
        }
        guard let ret0_ else {
            throw ExtensionError.serviceUnavailable("OpenTun: nil return pointer")
        }
         
         
         
        let session = try beginTunnelSession(in: generation)
        let fd: Int32
        do {
            fd = try runBlocking { [self] in
                try await openTun0(options, session: session, samplingToken: samplingToken, generation: generation)
            }
        } catch {
            abandonTunnelSession(session, generation: generation)
            throw error
        }
        ret0_.pointee = fd
    }

    private func openTun0(
        _ options: any ClashTunOptionsProtocol,
        session: ProviderTunnelSessionLease.Session,
        samplingToken: StartupMemorySampler.Token?, generation: TunnelNetworkSettingsWriter.Generation
    ) async throws -> Int32 {
        var capturedIPStack: PacketTunnelIPStackSettings?
        guard commitSettingsContext(generation: generation, session: session, {
            capturedIPStack = withStateLock { ipStackSettings }
        }), let ipStack = capturedIPStack else { throw CancellationError() }
        guard options.getIPv6Mode() == ipStack.tunIPv6Mode.rawValue else {
            throw ExtensionError.serviceUnavailable(
                "OpenTun: Core IPv6 mode does not match the saved VPN IP Stack settings"
            )
        }
        startupMemorySampler.note("tun: open-entered", token: samplingToken)
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        let effectiveMTU = options.getMTU()
        guard (1_280...9_000).contains(Int(effectiveMTU)) else {
            throw ExtensionError.serviceUnavailable(
                "OpenTun: Core returned invalid MTU \(effectiveMTU); expected 1280...9000"
            )
        }
         
         
         
         
         
        settings.mtu = NSNumber(value: effectiveMTU)
        settings.tunnelOverheadBytes = nil

         
         
         
         
        let dnsBox = try options.getDNSServerAddress()
        guard !dnsBox.value.isEmpty else {
            throw ExtensionError.serviceUnavailable("OpenTun: DNS takeover address unavailable")
        }
        settings.dnsSettings = Self.dnsTakeoverSettings(server: dnsBox.value)

         
        var v4Addr: [String] = [], v4Mask: [String] = []
        guard let v4It = options.getInet4Address() else {
            throw ExtensionError.serviceUnavailable("OpenTun: nil Inet4Address iterator")
        }
        while v4It.hasNext() {
            guard let p = v4It.next() else { break }
            v4Addr.append(p.address()); v4Mask.append(p.mask())
        }
         
         
         
         
        let routeSwitches = ClashTunnelRouteShaping.Switches.read(
            from: UserDefaults(suiteName: appGroupID),
            moduleOverlay: ClashAppIdentifiers.appGroupContainer?
                .appendingPathComponent(ClashTunnelRouteShaping.moduleDeviceSettingsPath)
        )
         
        let enforceRoutes = tunnelProvider.protocolConfiguration.enforceRoutes
         
         
         
        #if os(iOS)
        let routeShapeSwitches = routeSwitches
        #else
        var routeShapeSwitches = routeSwitches
        routeShapeSwitches.hideVPNIcon = false
        #endif
         
         
         
         
         
         
        let loopback4 = options.getInet4LoopbackAddress().map(collectV4Routes) ?? []
        let loopback6 = options.getInet6LoopbackAddress().map(collectV6Routes) ?? []
        #if os(iOS)
        let loopbackConfigured = !v4Addr.isEmpty && !loopback4.isEmpty
        #else
        let loopbackConfigured = false
        #endif
        let splitTable = ClashTunnelRouteShaping.usesSplitTable(
            strictRoute: options.getStrictRoute(), enforceRoutes: enforceRoutes,
            loopbackConfigured: loopbackConfigured, switches: routeShapeSwitches
        )
         
         
        let wholeAsDefault = ClashTunnelRouteShaping.takesWholeAsDefault(
            splitTable: splitTable, hideVPNIcon: routeShapeSwitches.hideVPNIcon
        )
         
         
         
         
         
         
         
         
         
        let besideLoopback = loopbackConfigured && !splitTable
        ClashLogStore.shared.append(
            "route shaping: hideVPNIcon=\(routeSwitches.hideVPNIcon) homeKitCompatibility=\(routeSwitches.homeKitCompatibility) excludeAPNsRoute=\(routeSwitches.excludeAPNsRoute) enforceRoutes=\(enforceRoutes) splitTable=\(splitTable) loopback=\(loopback4.count + loopback6.count) besideLoopback=\(besideLoopback)",
            stream: .app
        )
        var v4DeclaredMask = v4Mask
        if !v4Addr.isEmpty {
            guard let includedIt = options.getInet4RouteAddress(),
                  let excludedIt = options.getInet4RouteExcludeAddress() else {
                throw ExtensionError.serviceUnavailable("OpenTun: nil Inet4 route iterator")
            }
            let included = collectV4Routes(includedIt)
            let effective = included.isEmpty ? defaultV4Routes(strict: splitTable) : included
            let routes4 = effective.map { ClashTunnelRouteShaping.V4(address: $0.destinationAddress, mask: $0.destinationSubnetMask) }
            let loopbackRoutes4 = loopback4.map { ClashTunnelRouteShaping.V4(address: $0.destinationAddress, mask: $0.destinationSubnetMask) }
            let leftOut4 = besideLoopback ? ClashTunnelRouteShaping.v4LeftOutBesideLoopback(
                routes4, keeping: zip(v4Addr, v4Mask).map { ClashTunnelRouteShaping.V4(address: $0, mask: $1) } + loopbackRoutes4
            ) : nil
            let configured4 = collectV4Routes(excludedIt).map {
                ClashTunnelRouteShaping.V4(address: $0.destinationAddress, mask: $0.destinationSubnetMask)
            }
            let excluded4 = ClashTunnelRouteShaping.v4Excluded(
                configured4 + (leftOut4 ?? []).filter { !configured4.contains($0) },
                includedIsEmpty: effective.isEmpty,
                switches: routeSwitches
            )
            if ClashTunnelRouteShaping.v4DeclaresHostAddress(leftOut: leftOut4, excluded: excluded4, dnsServer: dnsBox.value) {
                v4DeclaredMask = v4Mask.map { _ in ClashTunnelRouteShaping.v4HostMask }
            }
            let v4 = NEIPv4Settings(addresses: v4Addr, subnetMasks: v4DeclaredMask)
             
             
             
             
            v4.includedRoutes = ClashTunnelRouteShaping.v4Included(
                routes4,
                loopback: loopbackRoutes4,
                wholeAsDefault: wholeAsDefault, besideLoopback: besideLoopback
            ).map { NEIPv4Route(destinationAddress: $0.address, subnetMask: $0.mask) }
            v4.excludedRoutes = excluded4.map { NEIPv4Route(destinationAddress: $0.address, subnetMask: $0.mask) }
            settings.ipv4Settings = v4
        }

         
        var v6Addr: [String] = [], v6Prefix: [NSNumber] = []
        guard let v6It = options.getInet6Address() else {
            throw ExtensionError.serviceUnavailable("OpenTun: nil Inet6Address iterator")
        }
        while v6It.hasNext() {
            guard let p = v6It.next() else { break }
            v6Addr.append(p.address()); v6Prefix.append(NSNumber(value: p.prefix()))
        }
         
         
         
         
         
         
         
        if !v6Addr.isEmpty, !besideLoopback {
            guard let includedIt = options.getInet6RouteAddress(),
                  let excludedIt = options.getInet6RouteExcludeAddress() else {
                throw ExtensionError.serviceUnavailable("OpenTun: nil Inet6 route iterator")
            }
            let v6 = NEIPv6Settings(addresses: v6Addr, networkPrefixLengths: v6Prefix)
            let included = collectV6Routes(includedIt)
            let effective = included.isEmpty ? defaultV6Routes(strict: splitTable) : included
             
             
            v6.includedRoutes = ClashTunnelRouteShaping.v6Included(
                effective.map { .init(address: $0.destinationAddress, prefix: $0.destinationNetworkPrefixLength.intValue) },
                loopback: loopback6.map { .init(address: $0.destinationAddress, prefix: $0.destinationNetworkPrefixLength.intValue) },
                wholeAsDefault: wholeAsDefault
            ).map { NEIPv6Route(destinationAddress: $0.address, networkPrefixLength: NSNumber(value: $0.prefix)) }
            v6.excludedRoutes = ClashTunnelRouteShaping.v6Excluded(
                collectV6Routes(excludedIt).map { .init(address: $0.destinationAddress, prefix: $0.destinationNetworkPrefixLength.intValue) },
                includedIsEmpty: effective.isEmpty,
                switches: routeSwitches
            ).map { NEIPv6Route(destinationAddress: $0.address, networkPrefixLength: NSNumber(value: $0.prefix)) }
             
             
            settings.ipv6Settings = v6
        }

        let strictRoute = options.getStrictRoute()
         
         
        let requested = PreappliedTunnelDescriptor(
            mtu: Int(effectiveMTU),
            dnsServerAddress: dnsBox.value,
            inet4Addresses: zip(v4Addr, v4DeclaredMask).map { "\($0)/\($1)" },
             
             
            inet6Addresses: settings.ipv6Settings == nil ? [] : zip(v6Addr, v6Prefix).map { "\($0)/\($1.intValue)" },
            inet4IncludedRoutes: (settings.ipv4Settings?.includedRoutes ?? [])
                .map { "\($0.destinationAddress)/\($0.destinationSubnetMask)" },
            inet4ExcludedRoutes: (settings.ipv4Settings?.excludedRoutes ?? [])
                .map { "\($0.destinationAddress)/\($0.destinationSubnetMask)" },
            inet6IncludedRoutes: (settings.ipv6Settings?.includedRoutes ?? [])
                .map { "\($0.destinationAddress)/\($0.destinationNetworkPrefixLength)" },
            inet6ExcludedRoutes: (settings.ipv6Settings?.excludedRoutes ?? [])
                .map { "\($0.destinationAddress)/\($0.destinationNetworkPrefixLength)" },
            strictRoute: strictRoute,
            queryMode: ipStack.queryMode.rawValue,
            ipv6Mode: ipStack.tunIPv6Mode.rawValue
        )
         
         
         
        if let claimed = try await claimPreappliedTunnel(
            matching: requested, samplingToken: samplingToken, generation: generation, session: session
        ) {
            startupMemorySampler.note("tun: pre-applied claimed", token: samplingToken)
            let published = commitTunnelSession(session, generation: generation) {
                ClashLogStore.shared.markTunnelEstablished()
            }
            guard published else {
                throw ExtensionError.serviceUnavailable(
                    "the tunnel session was superseded before it was established"
                )
            }
             
             
             
             
            ClashLogStore.shared.append(
                "tunnel opened from pre-applied settings  fd=\(claimed) bridge=none",
                stream: .app
            )
            return claimed
        }
        try offerTunnelSettings(settings, strictRoute: strictRoute, in: generation, session: session)
         
         
         
        startupMemorySampler.note("tun: settings-built", token: samplingToken)
        try await reconcileTunnelSettings(in: generation)
        startupMemorySampler.note("tun: settings-applied", token: samplingToken)


        try detachPacketFlowBridge(in: generation, session: session)?.stop()
        let provider = tunnelProvider
         
         
        let bridge: PacketFlowBridge?
        let bridgeFD: Int32
        if let direct = Self.systemTunnelDescriptor() {
            bridge = nil
            bridgeFD = direct
        } else {
            let made = PacketFlowBridge(
                packetFlow: packetFlowReads,
                configuration: packetFlowConfiguration,
            logLine: { ClashLogStore.shared.append($0, stream: .app, level: .warning) }
            ) { [weak provider] error in
                provider?.cancelTunnelWithError(error)
            }
            bridgeFD = try made.start()
            bridge = made
        }
         
         
         
         
         
         
         
         
         
         
        var rememberedKey = ""
        let published = commitTunnelSession(session, generation: generation) {
            ClashLogStore.shared.markTunnelEstablished()
            withStateLock { packetFlowBridge = bridge }
            rememberedKey = rememberPreapplied(requested)
        }
        guard published else {
             
             
             
             
            bridge?.stop()
             
             
             
            ClashLogStore.shared.append(
                bridge == nil
                    ? "tunnel descriptor not handed over  fd=\(bridgeFD) reason=session-superseded preapplied=not-remembered"
                    : "packet bridge stopped  fd=\(bridgeFD) reason=session-superseded preapplied=not-remembered",
                stream: .app
            )
             
             
            throw ExtensionError.serviceUnavailable(
                "the tunnel session was superseded before it was established"
            )
        }
         
         
         
         
         
        let remembered = rememberedKey.isEmpty
            ? "preapplied=not-remembered(no-tun-intent)"
            : "preapplied-remembered-key=\(rememberedKey.prefix(12))"
        ClashLogStore.shared.append(
            bridge == nil
                ? "tunnel descriptor handed to the core  fd=\(bridgeFD) \(remembered)"
                : "packet bridge started  fd=\(bridgeFD) \(remembered)",
            stream: .app
        )
        startupMemorySampler.note("tun: bridge-up", token: samplingToken)
        return bridgeFD
    }

    private func commitTunnelSession(
        _ session: ProviderTunnelSessionLease.Session,
        generation: TunnelNetworkSettingsWriter.Generation,
        _ commit: () -> Void
    ) -> Bool {
        commitSettingsContext(generation: generation, session: session, commit)
    }

    private func beginTunnelSession(in generation: TunnelNetworkSettingsWriter.Generation) throws -> ProviderTunnelSessionLease.Session {
        var session: ProviderTunnelSessionLease.Session?
        guard settingsWriter.commitIfCurrent(generation, {
            session = tunnelSessionLease.begin()
        }), let session else { throw CancellationError() }
        return session
    }

    private func abandonTunnelSession(
        _ session: ProviderTunnelSessionLease.Session, generation: TunnelNetworkSettingsWriter.Generation
    ) {
        settingsWriter.commitIfCurrent(generation) {
            tunnelSessionLease.invalidate(ifCurrent: session)
        }
    }

    private func isTunnelSessionCurrent(_ session: ProviderTunnelSessionLease.Session?) -> Bool {
        guard let session else { return true }
        return tunnelSessionLease.commitIfCurrent(session, {})
    }

     
     
     
    @discardableResult
    private func commitSettingsContext(
        generation: TunnelNetworkSettingsWriter.Generation,
        session: ProviderTunnelSessionLease.Session?, requiringReconciled: Bool = false,
        _ commit: () -> Void
    ) -> Bool {
        var accepted = false
        settingsWriter.commitIfCurrent(generation, requiringReconciled: requiringReconciled) {
            if let session {
                accepted = tunnelSessionLease.commitIfCurrent(session, commit)
            } else {
                commit()
                accepted = true
            }
        }
        return accepted
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static let readsTheTunnelDirectly = true

    static func systemTunnelDescriptor() -> Int32? {
        guard readsTheTunnelDirectly else { return nil }
         
         
        let controlProtocol: Int32 = 2
        let interfaceNameOption: Int32 = 2
        var name = [CChar](repeating: 0, count: Int(IFNAMSIZ))
        for descriptor: Int32 in 0..<1024 {
            var length = socklen_t(name.count)
            guard getsockopt(descriptor, controlProtocol, interfaceNameOption, &name, &length) == 0 else { continue }
            if String(cString: name).hasPrefix("utun") { return descriptor }
        }
        return nil
    }

    private func detachPacketFlowBridge(
        in generation: TunnelNetworkSettingsWriter.Generation,
        session: ProviderTunnelSessionLease.Session? = nil
    ) throws -> PacketFlowBridge? {
        var bridge: PacketFlowBridge?
        guard commitSettingsContext(generation: generation, session: session, {
            withStateLock {
                bridge = packetFlowBridge
                packetFlowBridge = nil
            }
        }) else { throw CancellationError() }
        return bridge
    }

     
     
     
     
     
     
    private func preapplyTunnelSettingsIfKnown(
        container: URL, samplingToken: StartupMemorySampler.Token?,
        generation: TunnelNetworkSettingsWriter.Generation,
        pathGeneration: PhysicalPathStartupGate.Generation, ipStack: PacketTunnelIPStackSettings
    ) {


        guard (try? ConfigResourceStore(containerURL: container).loadCurrent()) != nil
        else { return }
         
         
         
         
         
         
        let defaults = UserDefaults(suiteName: appGroupID)
        let fingerprint = PublishedTunIntent.current(defaults: defaults)
        guard !fingerprint.isEmpty else { return }
         
         
         
        withStateLock { preappliedTunIntent = fingerprint }
        let known = PreappliedTunnelStore(defaults: defaults)
            .descriptor(forTunIntent: fingerprint, queryMode: ipStack.queryMode.rawValue,
                        ipv6Mode: ipStack.tunIPv6Mode.rawValue)
         
         
         
         
        startupMemorySampler.note(
            "tun: preapply key=\(fingerprint.prefix(12)) cached=\(known != nil)",
            token: samplingToken
        )
        guard let known else { return }
        let provider = tunnelProvider
        let settings = Self.networkSettings(from: known)
        let task = Task<Int32, Error> { [weak self] in
            guard let self else { throw ExtensionError.serviceUnavailable("provider went away") }
            try await self.waitForPhysicalPath(pathGeneration)
            try Task.checkCancellation()
            try self.offerTunnelSettings(settings, strictRoute: known.strictRoute, in: generation)
            try await self.reconcileTunnelSettings(in: generation)


            try self.detachPacketFlowBridge(in: generation)?.stop()
             
            if let direct = Self.systemTunnelDescriptor() {
                guard !Task.isCancelled, self.settingsWriter.commitIfCurrent(generation, {}) else {
                    throw CancellationError()
                }
                return direct
            }
            let bridge = PacketFlowBridge(
                packetFlow: self.packetFlowReads,
                configuration: self.packetFlowConfiguration,
                logLine: { ClashLogStore.shared.append($0, stream: .app, level: .warning) }
            ) { [weak provider = provider] error in
                provider?.cancelTunnelWithError(error)
            }
            let fd = try bridge.start()
            guard !Task.isCancelled, self.settingsWriter.commitIfCurrent(generation, {
                self.withStateLock { self.packetFlowBridge = bridge }
            }) else {
                bridge.stop()
                throw CancellationError()
            }
            return fd
        }
        withStateLock {
            preappliedTunnel = task
            preappliedDescriptor = known
        }
        startupMemorySampler.mark("tun-preapply-dispatched", token: samplingToken)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func dnsTakeoverSettings(server: String) -> NEDNSSettings {
        let dns = NEDNSSettings(servers: [server])
        dns.matchDomains = [""]
        dns.matchDomainsNoSearch = true
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, *) {
            dns.allowFailover = false
        }
        return dns
    }

     
     
     
    private static func networkSettings(
        from descriptor: PreappliedTunnelDescriptor
    ) -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        settings.mtu = NSNumber(value: descriptor.mtu)
        settings.tunnelOverheadBytes = nil
        settings.dnsSettings = Self.dnsTakeoverSettings(server: descriptor.dnsServerAddress)

        let v4 = descriptor.inet4Addresses.compactMap(Self.splitPrefix)
        if !v4.isEmpty {
            let ipv4 = NEIPv4Settings(addresses: v4.map(\.0), subnetMasks: v4.map(\.1))
             
             
            ipv4.includedRoutes = ClashTunnelRouteShaping.v4Included(
                descriptor.inet4IncludedRoutes.compactMap(Self.splitPrefix).map { .init(address: $0.0, mask: $0.1) },
                loopback: []
            ).map { NEIPv4Route(destinationAddress: $0.address, subnetMask: $0.mask) }
            ipv4.excludedRoutes = descriptor.inet4ExcludedRoutes
                .compactMap(Self.splitPrefix)
                .map { NEIPv4Route(destinationAddress: $0.0, subnetMask: $0.1) }
            settings.ipv4Settings = ipv4
        }
        let v6 = descriptor.inet6Addresses.compactMap(Self.splitPrefix)
        if !v6.isEmpty {
            let ipv6 = NEIPv6Settings(
                addresses: v6.map(\.0),
                networkPrefixLengths: v6.map { NSNumber(value: Int($0.1) ?? 128) }
            )
            ipv6.includedRoutes = ClashTunnelRouteShaping.v6Included(
                descriptor.inet6IncludedRoutes.compactMap(Self.splitPrefix).map { .init(address: $0.0, prefix: Int($0.1) ?? 128) },
                loopback: []
            ).map { NEIPv6Route(destinationAddress: $0.address, networkPrefixLength: NSNumber(value: $0.prefix)) }
            ipv6.excludedRoutes = descriptor.inet6ExcludedRoutes
                .compactMap(Self.splitPrefix)
                .map {
                    NEIPv6Route(
                        destinationAddress: $0.0,
                        networkPrefixLength: NSNumber(value: Int($0.1) ?? 128)
                    )
                }
            settings.ipv6Settings = ipv6
        }
        return settings
    }

    private static func splitPrefix(_ value: String) -> (String, String)? {
        guard let slash = value.lastIndex(of: "/") else { return nil }
        return (String(value[value.startIndex..<slash]),
                String(value[value.index(after: slash)...]))
    }

     
     
     
     
    private func claimPreappliedTunnel(
        matching requested: PreappliedTunnelDescriptor,
        samplingToken: StartupMemorySampler.Token?, generation: TunnelNetworkSettingsWriter.Generation,
        session: ProviderTunnelSessionLease.Session? = nil
    ) async throws -> Int32? {
        var taken: (Task<Int32, Error>?, PreappliedTunnelDescriptor?) = (nil, nil)
        guard commitSettingsContext(generation: generation, session: session, {
            withStateLock {
                taken = (preappliedTunnel, preappliedDescriptor)
                preappliedTunnel = nil
                preappliedDescriptor = nil
            }
        }) else { throw CancellationError() }
        guard let task = taken.0 else { return nil }
        let applied = taken.1
        guard applied == requested else {
             
             
             
             
            _ = try? await task.value
            try detachPacketFlowBridge(in: generation, session: session)?.stop()
            startupMemorySampler.note("tun: pre-applied discarded (settings changed)", token: samplingToken)
            return nil
        }
        do {
            let fd = try await task.value
             
             
             
            while true {
                try await reconcileTunnelSettings(in: generation)
                var matches = false
                commitSettingsContext(generation: generation, session: session, requiringReconciled: true) {
                    matches = withStateLock {
                        let matches = appliedSettingsRevision == offeredSettingsRevision
                            && networkSettings != nil
                            && (networkSettings?.ipv6Settings != nil) == desiredIPv6Declaration
                        if matches { offeredTunnelSession = session }
                        return matches
                    }
                }
                guard settingsWriter.isCurrent(generation), isTunnelSessionCurrent(session) else { throw CancellationError() }
                if matches { return fd }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
             
             
            startupMemorySampler.note("tun: pre-applied failed, applying normally", token: samplingToken)
            return nil
        }
    }

     
     
     
     
    @discardableResult
    private func rememberPreapplied(_ descriptor: PreappliedTunnelDescriptor) -> String {
        let fingerprint = withStateLock { preappliedTunIntent }
         
        guard !fingerprint.isEmpty else { return fingerprint }
        PreappliedTunnelStore(defaults: UserDefaults(suiteName: appGroupID))
            .remember(descriptor, forTunIntent: fingerprint, queryMode: descriptor.queryMode,
                      ipv6Mode: descriptor.ipv6Mode)
        return fingerprint
    }

     
     
     
    private func collectV4Routes(_ it: any ClashRoutePrefixIteratorProtocol) -> [NEIPv4Route] {
        var routes: [NEIPv4Route] = []
        while it.hasNext() {
            guard let p = it.next() else { break }
            routes.append(NEIPv4Route(destinationAddress: p.address(), subnetMask: p.mask()))
        }
        return routes
    }

    private func collectV6Routes(_ it: any ClashRoutePrefixIteratorProtocol) -> [NEIPv6Route] {
        var routes: [NEIPv6Route] = []
        while it.hasNext() {
            guard let p = it.next() else { break }
            routes.append(NEIPv6Route(destinationAddress: p.address(), networkPrefixLength: NSNumber(value: p.prefix())))
        }
        return routes
    }

     
     
     
     
     
     
     
     
     
    private func defaultV4Routes(strict: Bool) -> [NEIPv4Route] {
        ClashTunnelRouteShaping.v4Default(splitTable: strict).map {
            NEIPv4Route(destinationAddress: $0.address, subnetMask: $0.mask)
        }
    }

    private func defaultV6Routes(strict: Bool) -> [NEIPv6Route] {
        ClashTunnelRouteShaping.v6Default(splitTable: strict).map {
            NEIPv6Route(destinationAddress: $0.address, networkPrefixLength: NSNumber(value: $0.prefix))
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    private final class BlockingResultBox<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Result<T, Error>?
        private var abandoned = false

         
        func deliver(_ result: Result<T, Error>) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !abandoned else { return false }
            value = result
            return true
        }

        func abandon() {
            lock.lock()
            abandoned = true
            lock.unlock()
        }

        func take() -> Result<T, Error>? {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    private static var blockingOperationLimit: DispatchTime { .now() + .seconds(20) }

    private func runBlocking<T>(_ operation: @escaping () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let box = BlockingResultBox<T>()
        Task {
            let outcome: Result<T, Error>
            do { outcome = .success(try await operation()) }
            catch { outcome = .failure(error) }
            if box.deliver(outcome) { semaphore.signal() }
        }
        guard semaphore.wait(timeout: Self.blockingOperationLimit) == .success else {
            box.abandon()
            throw ExtensionError.serviceUnavailable(
                "the system did not finish applying the tunnel settings"
            )
        }
        guard let result = box.take() else {
            throw ExtensionError.serviceUnavailable(
                "the tunnel settings finished without a result"
            )
        }
        return try result.get()
    }

    func usePlatformAutoDetectControl() -> Bool { Self.bindsOutboundToPhysicalInterface }

     
     
    static var bindsOutboundToPhysicalInterface: Bool {
         
         
         
         
         
         
         
         
         
         
        false
    }

     
     
     
     
     
     
    func autoDetectControl(_ fd: Int32) throws {
        do {
            try PhysicalEgressBinding.apply(.decision(interfaceIndex: currentInterfaceIndex()), to: fd)
        } catch let failure as PhysicalEgressBinding.Failure {
            throw ExtensionError.serviceUnavailable(failure.description)
        }
    }

     
     
     
     
    func startDefaultInterfaceMonitor(_ listener: (any ClashInterfaceUpdateListenerProtocol)?) throws {
        guard let listener else { return }
        let publishInitialPath = { [self] in
            pathLock.lock()
            guard defaultPathIsSatisfied,
                  defaultInterfaceIndex != 0,
                  !defaultInterfaceName.isEmpty
            else {
                interfaceListener = nil
                pathLock.unlock()
                throw ExtensionError.physicalPathUnavailable
            }
            interfaceListener = listener
            let idx = defaultInterfaceIndex
            let name = defaultInterfaceName
            let isExpensive = defaultPathIsExpensive
            let isConstrained = defaultPathIsConstrained
            let supportsIPv4 = defaultPathSupportsIPv4
            let supportsIPv6 = defaultPathSupportsIPv6
            pathLock.unlock()
            listener.updateDefaultInterface(
                name,
                interfaceIndex: Int32(bitPattern: idx),
                isExpensive: isExpensive,
                isConstrained: isConstrained,
                supportsIPv4: supportsIPv4,
                supportsIPv6: supportsIPv6
            )
        }
        if DispatchQueue.getSpecific(key: pathQueueKey) != nil {
            try publishInitialPath()
        } else {
            try pathQueue.sync(execute: publishInitialPath)
        }
    }

    func closeDefaultInterfaceMonitor(_: (any ClashInterfaceUpdateListenerProtocol)?) throws {
        let detach = { [self] in
            pathLock.lock()
            interfaceListener = nil
            pathLock.unlock()
        }
        if DispatchQueue.getSpecific(key: pathQueueKey) != nil {
            detach()
        } else {
             
             
            pathQueue.sync(execute: detach)
        }
    }

     
     
     
     
     
     
    func getInterfaces() throws -> any ClashNetworkInterfaceIteratorProtocol {
        pathLock.lock()
        let available = physicalPathAvailableInterfaces
        let expensive = defaultPathIsExpensive
        let defaultIndex = defaultInterfaceIndex
        pathLock.unlock()
        let settings = withStateLock { networkSettings }
        let ownAddresses = Set(
            (settings?.ipv4Settings?.addresses ?? []) + (settings?.ipv6Settings?.addresses ?? [])
        )
        return PhysicalInterfaceInventory.Iterator(
            PhysicalInterfaceInventory.build(
                raw: PhysicalInterfaceInventory.enumerate(),
                available: available,
                pathIsExpensive: expensive,
                defaultInterfaceIndex: defaultIndex,
                ownTunnelAddresses: ownAddresses
            )
        )
    }

    func underNetworkExtension() -> Bool {
        true
    }
}

 
 
 
private final class StartupPlatformInterface: NSObject, ClashPlatformInterfaceProtocol {
    private weak var provider: ExtensionProvider?
    private let samplingToken: StartupMemorySampler.Token?
    private let settingsGeneration: TunnelNetworkSettingsWriter.Generation

    init(provider: ExtensionProvider, samplingToken: StartupMemorySampler.Token?,
         settingsGeneration: TunnelNetworkSettingsWriter.Generation) {
        self.provider = provider
        self.samplingToken = samplingToken
        self.settingsGeneration = settingsGeneration
    }

    private func owner() throws -> ExtensionProvider {
        guard let provider else { throw ExtensionError.serviceUnavailable("provider released") }
        return provider
    }

    func writeLog(_ message: String?) { provider?.writeLog(message) }
    func tunFailed(_ reason: String?) { provider?.tunFailed(reason, generation: settingsGeneration) }
    func openTun(_ options: (any ClashTunOptionsProtocol)?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        try owner().openTun(options, ret0_: ret0_, samplingToken: samplingToken, generation: settingsGeneration)
    }
     
    func usePlatformAutoDetectControl() -> Bool { ExtensionProvider.bindsOutboundToPhysicalInterface }
    func autoDetectControl(_ fd: Int32) throws { try owner().autoDetectControl(fd) }
    func startDefaultInterfaceMonitor(_ listener: (any ClashInterfaceUpdateListenerProtocol)?) throws {
        try owner().startDefaultInterfaceMonitor(listener)
    }
    func closeDefaultInterfaceMonitor(_ listener: (any ClashInterfaceUpdateListenerProtocol)?) throws {
        try owner().closeDefaultInterfaceMonitor(listener)
    }
    func getInterfaces() throws -> any ClashNetworkInterfaceIteratorProtocol { try owner().getInterfaces() }
    func underNetworkExtension() -> Bool { true }
}

#if os(macOS)
 
 
 
 
final class ClashConnectionOwnerBridge: NSObject, ClashConnectionOwnerResolverProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var installed: ClashConnectionOwnerBridge?

    private let client: ClashConnectionOwnerClient
    private let tally = NSLock()
    private var asked = 0
    private var named = 0
    private static let log = Logger(subsystem: "org.example.clash.demo.extension", category: "process-owner")

    private init(client: ClashConnectionOwnerClient) {
        self.client = client
    }

    static func install() {
        lock.lock()
        defer { lock.unlock() }
        guard installed == nil,
              let container = ClashAppIdentifiers.appGroupContainer,
              let client = ClashConnectionOwnerClient(container: container)
        else { return }
        let bridge = ClashConnectionOwnerBridge(client: client)
        installed = bridge
        ClashSetConnectionOwnerResolver(bridge)
    }

    func findConnectionOwner(
        _ ipProtocol: Int32, sourceAddress: String?, sourcePort: Int32,
        destinationAddress: String?, destinationPort: Int32
    ) throws -> ClashConnectionOwner {
        let owner = sourceAddress.flatMap { source in
            destinationAddress.flatMap { destination in
                client.owner(
                    ipProtocol: ipProtocol, sourceAddress: source, sourcePort: sourcePort,
                    destinationAddress: destination, destinationPort: destinationPort
                )
            }
        }
        tally.lock()
        asked += 1
        if owner != nil { named += 1 }
        let (n, hits) = (asked, named)
        tally.unlock()
        if n <= 20 || n % 500 == 0 {
            Self.log.info("owner.ask n=\(n, privacy: .public) named=\(hits, privacy: .public) proto=\(ipProtocol, privacy: .public) src=\(sourceAddress ?? "", privacy: .public):\(sourcePort, privacy: .public) owner=\(owner?.processPath ?? "-", privacy: .public)")
        }
        guard let owner else {
            throw NSError(domain: "ClashConnectionOwner", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "the app did not name this connection's owner",
            ])
        }
        let result = ClashConnectionOwner()
        result.userId = owner.userID
        result.userName = owner.userName
        result.processPath = owner.processPath
        return result
    }
}
#endif

#if os(macOS)
 
 
 
final class MacRouteTableWatch {
    private let queue = DispatchQueue(label: "clash.route-table-watch")
    private let changed: () -> Void
    private var source: DispatchSourceRead?
    private var pending: DispatchWorkItem?

    init(changed: @escaping () -> Void) { self.changed = changed }

    func start() {
        let fd = socket(PF_ROUTE, SOCK_RAW, 0)
        guard fd >= 0 else { return }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 2048)
            while read(fd, &buffer, buffer.count) > 0 {}
             
             
             
            guard let self, self.pending == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                self?.pending = nil
                self?.changed()
            }
            self.pending = work
            self.queue.asyncAfter(deadline: .now() + 1, execute: work)
        }
        source.setCancelHandler { close(fd) }
        queue.sync { self.source = source }
        source.resume()
    }

    func cancel() {
        queue.sync {
            pending?.cancel()
            pending = nil
            source?.cancel()
            source = nil
        }
    }
}
#endif
