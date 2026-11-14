import Foundation
import ClashClientKit
import ClashClientUI

public typealias ClashMacDestination = ClashClientUI.ClashRootDestination
public typealias ClashHomeSection = ClashClientUI.ClashHomeSection

public enum ClashConnectionPhase: String, Equatable, Sendable {
    case disconnected
    case preparing
    case connected
    case disconnecting
    case unavailable

    public var isActive: Bool {
        switch self {
        case .preparing, .connected, .disconnecting:
            true
        case .disconnected, .unavailable:
            false
        }
    }
}

public enum ClashConnectionAction: String, Equatable, Sendable {
    case activateSystemExtension
    case updateSystemExtension
    case installConfiguration
    case connect
    case disconnect
    case busy
    case unavailable
}

public struct ClashConnectionSnapshot: Equatable, Sendable {
    public var phase: ClashConnectionPhase
    public var action: ClashConnectionAction
    public var selectedRouteName: String?
    public var selectedRouteDelayMilliseconds: Int?
    public var issueDescription: String?

    public init(
        phase: ClashConnectionPhase,
        action: ClashConnectionAction? = nil,
        selectedRouteName: String? = nil,
        selectedRouteDelayMilliseconds: Int? = nil,
        issueDescription: String? = nil
    ) {
        self.phase = phase
        self.action = action ?? Self.defaultAction(for: phase)
        self.selectedRouteName = selectedRouteName
        self.selectedRouteDelayMilliseconds = selectedRouteDelayMilliseconds
        self.issueDescription = issueDescription
    }

    private static func defaultAction(for phase: ClashConnectionPhase) -> ClashConnectionAction {
        switch phase {
        case .connected: .disconnect
        case .preparing, .disconnecting: .busy
        case .disconnected: .connect
        case .unavailable: .unavailable
        }
    }
}

public enum ClashOutboundMode: String, CaseIterable, Identifiable, Sendable {
    case global = "Global"
    case rule = "Rule"
    case direct = "Direct"

    public var id: String { rawValue }
}

public struct ClashOverviewSnapshot: Equatable, Sendable {
    public var outboundMode: ClashOutboundMode
    public var selectedProxyName: String?
    public var proxyGroupCount: Int
    public var proxyCount: Int
    public var ruleCount: Int
    public var proxyNames: [String]
    public var ruleTargets: [String]

    public init(
        outboundMode: ClashOutboundMode,
        selectedProxyName: String? = nil,
        proxyGroupCount: Int = 0,
        proxyCount: Int = 0,
        ruleCount: Int = 0,
        proxyNames: [String] = [],
        ruleTargets: [String] = []
    ) {
        self.outboundMode = outboundMode
        self.selectedProxyName = selectedProxyName
        self.proxyGroupCount = max(0, proxyGroupCount)
        self.proxyCount = max(0, proxyCount)
        self.ruleCount = max(0, ruleCount)
        self.proxyNames = proxyNames
        self.ruleTargets = ruleTargets
    }
}

public typealias ClashMacProxyCatalogPhase =
    ClashClientUI.ClashProxyRuntimeCatalogPhase
public typealias ClashMacProxyNodeSnapshot =
    ClashClientUI.ClashProxyRuntimeNodeSnapshot
public typealias ClashMacProxyGroupSnapshot =
    ClashClientUI.ClashProxyRuntimeGroupSnapshot
public typealias ClashMacProxiesSnapshot =
    ClashClientUI.ClashProxiesRuntimeSnapshot
public typealias ClashMacLatencySweepSnapshot =
    ClashClientUI.ClashProxyLatencySweepSnapshot
public typealias ClashMacLatencyProbePlan =
    ClashClientUI.ClashProxyLatencyProbePlan
public typealias ClashMacProxyLatencyResult =
    ClashClientUI.ClashProxyLatencyResult
public typealias ClashMacLatencySweepController =
    ClashClientUI.ClashProxyLatencySweepController

@MainActor
public struct ClashMacProxiesActions {
    public var refresh: @MainActor () -> Void
    public var select: @MainActor (_ group: String, _ member: String) -> Void
    public var testAll: @MainActor (_ visibleGroupNames: [String]) -> Void
    public var cancelLatencyTests: @MainActor () -> Void

    public init(
        refresh: @escaping @MainActor () -> Void,
        select: @escaping @MainActor (_ group: String, _ member: String) -> Void,
        testAll: @escaping @MainActor (_ visibleGroupNames: [String]) -> Void = { _ in },
        cancelLatencyTests: @escaping @MainActor () -> Void = {}
    ) {
        self.refresh = refresh
        self.select = select
        self.testAll = testAll
        self.cancelLatencyTests = cancelLatencyTests
    }

    public static let none = Self(refresh: {}, select: { _, _ in })
}

public enum ClashMacActivityPhase: Equatable, Sendable {
    case disconnected
    case loading
    case ready
    case failed
}

 
 
public struct ClashMacActivitySnapshot: Equatable, Sendable {
    public var phase: ClashMacActivityPhase
    public var activeConnectionCount: Int
    public var recentLogCount: Int
    public var uploadBytesPerSecond: Int64
    public var downloadBytesPerSecond: Int64
    public var uploadTotalBytes: Int64
    public var downloadTotalBytes: Int64
    public var errorDescription: String?

    public init(
        phase: ClashMacActivityPhase,
        activeConnectionCount: Int = 0,
        recentLogCount: Int = 0,
        uploadBytesPerSecond: Int64 = 0,
        downloadBytesPerSecond: Int64 = 0,
        uploadTotalBytes: Int64 = 0,
        downloadTotalBytes: Int64 = 0,
        errorDescription: String? = nil
    ) {
        self.phase = phase
        self.activeConnectionCount = max(0, activeConnectionCount)
        self.recentLogCount = max(0, recentLogCount)
        self.uploadBytesPerSecond = max(0, uploadBytesPerSecond)
        self.downloadBytesPerSecond = max(0, downloadBytesPerSecond)
        self.uploadTotalBytes = max(0, uploadTotalBytes)
        self.downloadTotalBytes = max(0, downloadTotalBytes)
        self.errorDescription = errorDescription
    }

    public static let disconnected = Self(phase: .disconnected)
    public static let loading = Self(phase: .loading)
    public static let readyEmpty = Self(phase: .ready)

    public static func failed(_ message: String) -> Self {
        Self(phase: .failed, errorDescription: message)
    }
}

@MainActor
public struct ClashMacActivityActions {
    public var refresh: @MainActor () -> Void

    public init(refresh: @escaping @MainActor () -> Void) {
        self.refresh = refresh
    }

    public static let none = Self(refresh: {})
}

public struct ClashUtilitiesSnapshot: Equatable, Sendable {
    public var activeConnectionCount: Int
    public var requestCount: Int
    public var logCount: Int
    public var uploadBytesPerSecond: Int64
    public var downloadBytesPerSecond: Int64
    public var providerCount: Int?

    public init(
        activeConnectionCount: Int = 0,
        requestCount: Int = 0,
        logCount: Int = 0,
        uploadBytesPerSecond: Int64 = 0,
        downloadBytesPerSecond: Int64 = 0,
        providerCount: Int? = nil
    ) {
        self.activeConnectionCount = max(0, activeConnectionCount)
        self.requestCount = max(0, requestCount)
        self.logCount = max(0, logCount)
        self.uploadBytesPerSecond = max(0, uploadBytesPerSecond)
        self.downloadBytesPerSecond = max(0, downloadBytesPerSecond)
        self.providerCount = providerCount.map { max(0, $0) }
    }
}

public struct ClashMoreSnapshot: Equatable, Sendable {
    public var onDemandEnabled: Bool
    public var onDemandRuleCount: Int
    public var proxyShareStatus: String
    public var systemIntegrationStatus: String

    public init(
        onDemandEnabled: Bool = false,
        onDemandRuleCount: Int = 0,
        proxyShareStatus: String = "Off",
        systemIntegrationStatus: String = "Ready"
    ) {
        self.onDemandEnabled = onDemandEnabled
        self.onDemandRuleCount = max(0, onDemandRuleCount)
        self.proxyShareStatus = proxyShareStatus
        self.systemIntegrationStatus = systemIntegrationStatus
    }
}

 
 
 
@available(
    *,
    deprecated,
    renamed: "AppleClientSnapshot",
    message: "Construct AppleClientSnapshot directly in the macOS Adapter."
)
public typealias ClashMacClientSnapshot = AppleClientSnapshot

public extension AppleClientSnapshot {
    init(
        profile: Profile?,
        connection: ClashConnectionSnapshot,
        overview: ClashOverviewSnapshot,
        rules: ClashRulesSnapshot = .empty,
        dns: ClashDNSSnapshot = .empty,
        utilities: ClashUtilitiesSnapshot = ClashUtilitiesSnapshot(),
        more: ClashMoreSnapshot = ClashMoreSnapshot(),
        isPreview: Bool = false
    ) {
        let selectedProfile = profile.map {
            AppleClientProfileSnapshot(id: $0.id, label: $0.label)
        }
        let sharedMode = overview.outboundMode.appleClientMode
        let connectionPresentation =
            ClashHomeConnectionPresenter.presentation(
                for: ClashHomeConnectionFacts(
                    activeProfileName: profile?.label,
                    vpnStatus: connection.phase.rawValue,
                    errorMessage: connection.issueDescription ?? "",
                    mode: sharedMode.rawValue,
                    selectedProxyName:
                        connection.selectedRouteName
                        ?? overview.selectedProxyName,
                    selectedProxyDelayMilliseconds:
                        connection.selectedRouteDelayMilliseconds
                )
            )

        self.init(
            revision: 0,
            selectedProfile: selectedProfile,
            connection: AppleClientConnectionSnapshot(
                phase: connection.phase.appleClientPhase,
                primaryIntent: connection.action.appleClientIntent,
                selectedRouteName:
                    connection.selectedRouteName
                    ?? overview.selectedProxyName,
                selectedRouteDelayMilliseconds:
                    connection.selectedRouteDelayMilliseconds,
                issue: connection.issueDescription.map {
                    AppleClientFailure(
                        code: .connection,
                        title: "Connection",
                        message: $0
                    )
                }
            ),
            home: AppleClientHomeSnapshot(
                routing: AppleClientRoutingSnapshot(mode: sharedMode),
                traffic: AppleClientTrafficSnapshot(
                    uploadBytesPerSecond:
                        utilities.uploadBytesPerSecond,
                    downloadBytesPerSecond:
                        utilities.downloadBytesPerSecond
                ),
                proxyGroupCount: overview.proxyGroupCount,
                proxyCount: overview.proxyCount,
                ruleCount: overview.ruleCount,
                connection: connectionPresentation,
                proxies: ClashHomeDomainSnapshot(
                    count: overview.proxyCount,
                    breakdown: Self.countedNoun(
                        overview.proxyGroupCount,
                        singular: "group"
                    ),
                    names: overview.proxyNames
                ),
                rules: ClashHomeDomainSnapshot(
                    count: overview.ruleCount,
                    names: overview.ruleTargets
                )
            ),
            rules: rules,
            dns: dns,
            utilities: ClashClientUI.ClashUtilitiesSnapshot(
                nativeAPIConnected: connection.phase == .connected,
                activeConnectionCount:
                    utilities.activeConnectionCount,
                requestCount: utilities.requestCount,
                logCount: utilities.logCount,
                providerCount: utilities.providerCount,
                proxyShareStatus: more.proxyShareStatus,
                proxyShareEnabled: more.proxyShareStatus != "Off"
            ),
            more: ClashClientUI.ClashMoreSnapshot(
                onDemandEnabled: more.onDemandEnabled,
                onDemandRuleCount: more.onDemandRuleCount,
                showsDeveloperDestination: isPreview
            ),
            capabilities: AppleClientCapabilities([
                .home: .available,
                .utilities: .available,
                .more: .available,
                .connection: .available,
                .systemIntegration: .available,
                .configuration: .available,
                .outboundMode: .available,
                .rules: .available,
                .dns: .available,
            ])
        )
    }

    private static func countedNoun(
        _ value: Int,
        singular: String
    ) -> String? {
        guard value > 0 else { return nil }
        return "\(value) \(value == 1 ? singular : singular + "s")"
    }
}

public typealias ClashUtilityDestination = ClashClientUI.ClashUtilitiesDestination

public extension ClashUtilityDestination {
     
     
    @available(
        *,
        deprecated,
        renamed: "connections",
        message: "Use the shared Connections destination."
    )
    static var liveTraffic: Self { .connections }
}

public typealias ClashMoreDestination = ClashClientUI.ClashMoreDestination

 
 
 
public enum ClashMacSecondaryDestination: Hashable, Sendable {
    case profiles
    case proxies
    case rules
    case activeRules
    case dnsQuery
    case runtimeConfiguration
    case configuration
    case utility(ClashUtilityDestination)
    case more(ClashMoreDestination)

    public static let all: [Self] = [
        .profiles,
        .proxies,
        .rules,
        .activeRules,
        .dnsQuery,
    ]
        + [
            .runtimeConfiguration,
            .configuration,
        ]
        + ClashClientUI.ClashUtilitiesCatalog.sections
            .flatMap(\.destinations)
            .map(Self.utility)
        + ClashClientUI.ClashMoreCatalog.sections
            .flatMap(\.destinations)
            .map(Self.more)

    public var title: String {
        switch self {
        case .profiles:
            "Profiles"
        case .proxies:
            "Proxies"
        case .rules:
            "Rules"
        case .activeRules:
            "Active Rules"
        case .dnsQuery:
            "DNS Query"
        case .runtimeConfiguration:
            "Runtime Configuration"
        case .configuration:
            "Configuration"
        case .utility(let destination):
            destination.title
        case .more(let destination):
            destination.title
        }
    }

    public init?(homeCommand: ClashHomeCommand) {
        switch homeCommand {
        case .openRuntimeConfiguration:
            self = .runtimeConfiguration
        case .openProfiles, .performPrimaryAction, .showConnectionIssue,
             .resetVPNProfile, .openOnDemand, .openProxies, .openRules, .setCards,
             .setTrafficScope, .refreshExternalIP, .refreshLANIP:
            return nil
        }
    }
}

 
 
 
@available(
    *,
    deprecated,
    renamed: "AppleClientActions",
    message: "Construct capability-scoped AppleClientActions in the macOS Adapter."
)
public typealias ClashMacClientActions = AppleClientActions

@MainActor
public extension AppleClientActions {
    init(
        selectProfile: @escaping @MainActor () -> Void,
        performPrimaryAction: @escaping @MainActor () -> Void,
        selectOutboundMode: @escaping @MainActor (ClashOutboundMode) -> Void,
        openProxies: @escaping @MainActor () -> Void,
        openRules: @escaping @MainActor () -> Void,
        openActiveRules: @escaping @MainActor () -> Void,
        openDNSQuery: @escaping @MainActor () -> Void,
        customizeHome: @escaping @MainActor () -> Void,
        openUtility: @escaping @MainActor (ClashUtilityDestination) -> Void,
        openMore: @escaping @MainActor (ClashMoreDestination) -> Void
    ) {
        self = try! AppleClientActions.composing([
            AppleClientActions(capability: .home) { action in
                guard case .home(let command) = action else { return }
                switch command {
                case .openProfiles:
                    selectProfile()
                case .performPrimaryAction:
                    performPrimaryAction()
                case .openProxies:
                    openProxies()
                case .openRules:
                    openRules()
                case .openRuntimeConfiguration:
                    customizeHome()
                case .showConnectionIssue,
                     .resetVPNProfile,
                     .openOnDemand,
                     .setCards,
                     .setTrafficScope,
                     .refreshExternalIP,
                     .refreshLANIP:
                    break
                }
            },
            AppleClientActions(capability: .connection) { action in
                guard case .connection = action else { return }
                performPrimaryAction()
            },
            AppleClientActions(capability: .systemIntegration) { action in
                guard case .connection = action else { return }
                performPrimaryAction()
            },
            AppleClientActions(capability: .configuration) { action in
                guard case .connection = action else { return }
                performPrimaryAction()
            },
            AppleClientActions(capability: .outboundMode) { action in
                guard case .setOutboundMode(let mode) = action else {
                    return
                }
                selectOutboundMode(mode.clashMacMode)
            },
            AppleClientActions(capability: .rules) { action in
                guard case .rules(let command) = action else { return }
                switch command {
                case .openActiveRules:
                    openActiveRules()
                case .openProxiesGroup:
                    openProxies()
                case .saveProfileRules:
                    throw AppleClientActionError.unavailable(
                        .rules,
                        .unsupportedPlatform
                    )
                }
            },
            AppleClientActions(capability: .dns) { action in
                guard case .dns(let command) = action else { return }
                switch command {
                case .openDNSQuery:
                    openDNSQuery()
                case .saveSettings, .saveLocalMappings:
                    throw AppleClientActionError.unavailable(
                        .dns,
                        .unsupportedPlatform
                    )
                }
            },
            AppleClientActions(capability: .utilities) { action in
                guard case .openUtility(let destination) = action else {
                    return
                }
                openUtility(destination)
            },
            AppleClientActions(capability: .more) { action in
                guard case .openMore(let destination) = action else {
                    return
                }
                openMore(destination)
            },
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
        ])
    }

    static var none: AppleClientActions {
        .unavailable
    }
}

private extension ClashConnectionPhase {
    var appleClientPhase: AppleClientConnectionPhase {
        switch self {
        case .disconnected: .disconnected
        case .preparing: .preparing
        case .connected: .connected
        case .disconnecting: .disconnecting
        case .unavailable: .unavailable
        }
    }
}

private extension ClashConnectionAction {
    var appleClientIntent: AppleClientConnectionIntent? {
        switch self {
        case .activateSystemExtension: .activateSystemExtension
        case .updateSystemExtension: .updateSystemExtension
        case .installConfiguration: .installConfiguration
        case .connect: .connect
        case .disconnect: .disconnect
        case .busy, .unavailable: nil
        }
    }
}

private extension ClashOutboundMode {
    var appleClientMode: AppleClientOutboundMode {
        switch self {
        case .global: .global
        case .rule: .rule
        case .direct: .direct
        }
    }
}

private extension AppleClientOutboundMode {
    var clashMacMode: ClashOutboundMode {
        switch self {
        case .global: .global
        case .rule: .rule
        case .direct: .direct
        }
    }
}
