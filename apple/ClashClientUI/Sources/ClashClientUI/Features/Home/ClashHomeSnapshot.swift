import Foundation

public enum ClashHomeTrafficScope: String, Codable, Equatable, Sendable {
    case proxiedOnly
    case allTraffic
}

public struct ClashHomeDomainSnapshot: Codable, Equatable, Sendable {
    public let count: Int?
     
     
     
    public let countUnit: String?
    public let breakdown: String?
    public let names: [String]

    public init(
        count: Int? = nil,
        countUnit: String? = nil,
        breakdown: String? = nil,
        names: [String] = []
    ) {
        self.count = count.map { max(0, $0) }
        self.countUnit = countUnit.map { String($0.prefix(64)) }
        self.breakdown = breakdown.map { String($0.prefix(256)) }
        self.names = names.prefix(12).map { String($0.prefix(128)) }
    }

    public static let empty = ClashHomeDomainSnapshot()
}

public struct ClashHomeEgressSnapshot: Codable, Equatable, Sendable {
    public let address: String?
    public let flag: String
    public let detail: String
    public let canRefresh: Bool
    public let isChecking: Bool

    public init(
        address: String? = nil,
        flag: String = "",
        detail: String = "",
        canRefresh: Bool = false,
        isChecking: Bool = false
    ) {
        self.address = address.map { String($0.prefix(128)) }
        self.flag = String(flag.prefix(16))
        self.detail = String(detail.prefix(256))
        self.canRefresh = canRefresh
        self.isChecking = isChecking
    }

    public static let unavailable = ClashHomeEgressSnapshot()
}

public enum ClashHomeRecoveryMode: String, Codable, Equatable, Sendable {
    case none
    case direct
}

public enum ClashHomeConnectionPhase:
    String,
    CaseIterable,
    Codable,
    Equatable,
    Sendable
{
    case noProfile
    case ready
    case connecting
    case connected
    case switching
    case recoverableError
    case directRecovery
}

public enum ClashHomePrimaryAction: String, Codable, Equatable, Sendable {
    case openProfiles
    case connect
    case cancel
    case disconnect
    case retry
    case retryProxy
    case none
}

public struct ClashHomeConnectionIssue:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
     
     
     
     
     
     
     
     
    public enum Kind: String, Codable, Equatable, Sendable {
        case connectionFailure
         
         
        case startupStopped
         
         
         
         
         
         
        case providerNotLaunched
         
         
         
         
         
         
         
         
         
         
        case configurationNotFound
         
         
         
         
         
        case runningPreviousRevision
         
         
         
         
         
         
        case stoppedByOnDemandRule
         
         
         
         
        case globalOnDirect

         
         
        public var lineTapResetsVPNProfile: Bool {
            self == .providerNotLaunched || self == .configurationNotFound
        }

         
         
         
        public var lineTapCommand: ClashHomeCommand {
            if lineTapResetsVPNProfile { return .resetVPNProfile }
            if self == .stoppedByOnDemandRule { return .openOnDemand }
            if self == .globalOnDirect { return .openProxies }
            return .showConnectionIssue
        }
    }

    public let message: String
    public let kind: Kind
    public let allowsSystemVPNProfileReset: Bool
     
     
     
    public let subject: String?

    public init(
        message: String,
        kind: Kind = .connectionFailure,
        allowsSystemVPNProfileReset: Bool = false,
        subject: String? = nil
    ) {
        self.message = String(
            message
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(512)
        )
        self.kind = kind
        self.allowsSystemVPNProfileReset = allowsSystemVPNProfileReset
        self.subject = subject
    }

    public var id: String {
        "\(kind.rawValue)|\(allowsSystemVPNProfileReset)|\(message)|\(subject ?? "")"
    }

     
    public var text: ClashDisplayText {
        subject.map { .format(message, [$0]) } ?? .copy(message)
    }
}

public enum ClashVPNAuthorizationState: String, Codable, Equatable, Sendable {
    case required
    case waiting
    case notCompleted
}

 
 
 
public enum ClashHomeGlobalExit: String, Codable, Equatable, Sendable {
     
    case direct
     
    case reject
     
    case other
}

public extension ClashHomeGlobalExit {
     
     
    init?(_ exit: ClashTunnelOutboundMode.GlobalExit?) {
        switch exit {
        case .direct: self = .direct
        case .reject: self = .reject
        case .other: self = .other
        case .proxy, nil: return nil
        }
    }
}

public struct ClashHomeConnectionFacts: Codable, Equatable, Sendable {
    public var activeProfileName: String?
    public var vpnStatus: String
    public var errorMessage: String
    public var vpnAuthorization: ClashVPNAuthorizationState?
     
     
     
    public var errorIsStartupStopped: Bool
     
     
     
    public var errorIsProviderNotLaunched: Bool
     
     
     
     
    public var errorIsConfigurationNotFound: Bool
     
     
     
     
     
    public var errorOnDemandRuleNames: String?
     
     
     
    public var errorSubject: String?
    public var allowsSystemVPNProfileReset: Bool
    public var isSwitchingProxy: Bool
    public var recoveryMode: ClashHomeRecoveryMode
    public var mode: String
    public var selectedProxyName: String?
    public var selectedProxyDelayMilliseconds: Int?
     
     
    public var runningPreviousRevision: Bool
     
     
    public var runningPreviousProfileName: String?
     
     
     
    public var globalExitWithoutProxy: ClashHomeGlobalExit?
     
     
     
     
    public var finalRuleRoute: ClashHomeFinalRuleRoute?

    public init(
        activeProfileName: String?,
        vpnStatus: String,
        errorMessage: String = "",
        vpnAuthorization: ClashVPNAuthorizationState? = nil,
        errorIsStartupStopped: Bool = false,
        errorIsProviderNotLaunched: Bool = false,
        errorIsConfigurationNotFound: Bool = false,
        errorOnDemandRuleNames: String? = nil,
        errorSubject: String? = nil,
        allowsSystemVPNProfileReset: Bool = false,
        isSwitchingProxy: Bool = false,
        recoveryMode: ClashHomeRecoveryMode = .none,
        mode: String = "rule",
        selectedProxyName: String? = nil,
        selectedProxyDelayMilliseconds: Int? = nil,
        runningPreviousRevision: Bool = false,
        runningPreviousProfileName: String? = nil,
        globalExitWithoutProxy: ClashHomeGlobalExit? = nil,
        finalRuleRoute: ClashHomeFinalRuleRoute? = nil
    ) {
        self.activeProfileName = activeProfileName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.vpnStatus = vpnStatus
        self.errorMessage = errorMessage
        self.vpnAuthorization = vpnAuthorization
        self.errorIsStartupStopped = errorIsStartupStopped
        self.errorIsProviderNotLaunched = errorIsProviderNotLaunched
        self.errorIsConfigurationNotFound = errorIsConfigurationNotFound
        self.errorOnDemandRuleNames = errorOnDemandRuleNames
        self.errorSubject = errorSubject
        self.allowsSystemVPNProfileReset = allowsSystemVPNProfileReset
        self.isSwitchingProxy = isSwitchingProxy
        self.recoveryMode = recoveryMode
        self.mode = mode
        self.selectedProxyName = selectedProxyName
        self.selectedProxyDelayMilliseconds = selectedProxyDelayMilliseconds
        self.runningPreviousRevision = runningPreviousRevision
        self.runningPreviousProfileName = runningPreviousProfileName
        self.globalExitWithoutProxy = globalExitWithoutProxy
        self.finalRuleRoute = finalRuleRoute
    }
}

 
 
public struct ClashHomeFinalRuleRoute: Codable, Equatable, Sendable {
    public var group: String?
    public var node: String
    public var delayMilliseconds: Int?

    public init(group: String?, node: String, delayMilliseconds: Int?) {
        self.group = group
        self.node = node
        self.delayMilliseconds = delayMilliseconds
    }
}

public struct ClashHomeConnectionPresentation:
    Codable,
    Equatable,
    Sendable
{
    public let phase: ClashHomeConnectionPhase
    public let title: String
     
     
     
     
    public let subtitle: ClashDisplayText
    public let primaryAction: ClashHomePrimaryAction
    public let primaryActionTitle: String?
    public let issue: ClashHomeConnectionIssue?

    public init(
        phase: ClashHomeConnectionPhase,
        title: String,
        subtitle: ClashDisplayText,
        primaryAction: ClashHomePrimaryAction,
        primaryActionTitle: String?,
        issue: ClashHomeConnectionIssue? = nil
    ) {
        self.phase = phase
        self.title = String(title.prefix(160))
        self.subtitle = subtitle
        self.primaryAction = primaryAction
        self.primaryActionTitle = primaryActionTitle.map {
            String($0.prefix(64))
        }
        self.issue = issue
    }

    public var primaryActionEnabled: Bool {
        primaryAction != .none
    }

    public static let unavailable = ClashHomeConnectionPresentation(
        phase: .noProfile,
        title: "Profile Unavailable",
        subtitle: "The local Direct profile could not be prepared",
        primaryAction: .openProfiles,
        primaryActionTitle: "Open Profiles"
    )

     
     
     
    public static let loadingProfiles = ClashHomeConnectionPresentation(
        phase: .noProfile,
        title: "Loading",
        subtitle: "",
        primaryAction: .none,
        primaryActionTitle: nil
    )
}

public enum ClashHomeConnectionPresenter {
     
     
     
    public static func globalLine(_ exit: ClashHomeGlobalExit) -> String {
        switch exit {
        case .direct: return "In Global mode, GLOBAL is set to DIRECT, so no traffic goes through a proxy"
        case .reject: return "In Global mode, GLOBAL is set to REJECT, so all traffic is rejected"
        case .other: return "In Global mode, GLOBAL has no proxy chosen"
        }
    }

     
     
     
     
     
     
     
    public static func homeStatus(
        status: String, isPreparingStart: Bool, systemHasNotAnswered: Bool = false
    ) -> String {
        guard isPreparingStart || systemHasNotAnswered,
              !["connected", "connecting", "reasserting", "disconnecting"].contains(status.lowercased())
        else { return status }
        return "connecting"
    }

    public static func presentation(
        for facts: ClashHomeConnectionFacts
    ) -> ClashHomeConnectionPresentation {
        if facts.recoveryMode == .direct {
            return .init(
                phase: .directRecovery,
                title: "Direct Recovery Mode",
                subtitle: "Proxy is not in use",
                primaryAction: .retryProxy,
                primaryActionTitle: "Retry Proxy"
            )
        }

        let status = facts.vpnStatus
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let hasProfile = facts.activeProfileName?.isEmpty == false
        let boundedError = facts.errorMessage
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let kind: ClashHomeConnectionIssue.Kind
        if facts.errorIsProviderNotLaunched {
            kind = .providerNotLaunched
        } else if facts.errorIsConfigurationNotFound {
            kind = .configurationNotFound
        } else if facts.errorOnDemandRuleNames != nil {
            kind = .stoppedByOnDemandRule
        } else if facts.errorIsStartupStopped {
            kind = .startupStopped
        } else {
            kind = .connectionFailure
        }
        let issue = boundedError.isEmpty ? nil : ClashHomeConnectionIssue(
            message: boundedError,
            kind: kind,
             
             
             
             
             
            allowsSystemVPNProfileReset: kind.lineTapResetsVPNProfile
                || (kind != .startupStopped && facts.allowsSystemVPNProfileReset),
             
             
            subject: kind == .stoppedByOnDemandRule ? facts.errorOnDemandRuleNames
                : kind == .connectionFailure ? facts.errorSubject : nil
        )

        if !hasProfile {
            return .unavailable
        }
        if let authorization = facts.vpnAuthorization, issue == nil,
           !["connected", "connecting", "reasserting", "disconnecting"].contains(status) {
            let waiting = authorization == .waiting
            return .init(
                phase: waiting ? .connecting : .ready,
                title: "VPN Authorization",
                subtitle: waiting
                    ? "Allow VPN setup to connect."
                    : authorization == .notCompleted
                        ? "Tap Retry, then allow VPN setup."
                        : "Tap START, then allow VPN setup.",
                primaryAction: waiting ? .cancel : .connect,
                primaryActionTitle: waiting ? nil : authorization == .notCompleted ? "Retry" : "START"
            )
        }
        if facts.isSwitchingProxy
            && ["connected", "reasserting"].contains(status)
        {
            return .init(
                phase: .switching,
                title: "Switching Route",
                 
                 
                subtitle: "Switching Route",
                 
                 
                 
                 
                 
                 
                 
                 
                primaryAction: .cancel,
                primaryActionTitle: "STOP"
            )
        }
        if ["connecting", "disconnecting"].contains(status) {
            let closing = status == "disconnecting"
            return .init(
                phase: .connecting,
                 
                 
                 
                 
                 
                 
                 
                 
                title: closing ? "STOPPING" : "STARTING",
                subtitle: closing ? "STOPPING" : "STARTING",
                 
                 
                 
                 
                 
                 
                 
                primaryAction: closing ? .none : .cancel,
                primaryActionTitle: nil
            )
        }
        if ["connected", "reasserting"].contains(status) {
            return .init(
                phase: .connected,
                title: "Connected",
                subtitle: .verbatim(connectedSubtitle(facts)),
                primaryAction: .disconnect,
                primaryActionTitle: "STOP",
                 
                 
                issue: facts.runningPreviousRevision
                    ? ClashHomeConnectionIssue(
                        message: facts.runningPreviousProfileName == nil
                            ? "Still running the previous version" : "Still running %@",
                        kind: .runningPreviousRevision,
                        subject: facts.runningPreviousProfileName
                    )
                     
                     
                    : facts.mode.lowercased() == "global"
                        ? facts.globalExitWithoutProxy.map {
                            ClashHomeConnectionIssue(message: Self.globalLine($0), kind: .globalOnDirect)
                        }
                        : nil
            )
        }
        if issue != nil || ["invalid", "unknown"].contains(status) {
            return .init(
                phase: .recoverableError,
                title: "Connection Not Completed",
                subtitle: "Not Connected",
                primaryAction: .retry,
                primaryActionTitle: "Retry",
                issue: issue
            )
        }

        return .init(
            phase: .ready,
            title: facts.activeProfileName ?? "Profile",
            subtitle: "Not Connected",
            primaryAction: .connect,
             
             
             
             
             
             
             
            primaryActionTitle: "START"
        )
    }

    public static func semanticMode(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        {
        case "global":
            "Global"
        case "direct":
            "Direct"
        default:
            "Rule"
        }
    }

    private static func connectedSubtitle(
        _ facts: ClashHomeConnectionFacts
    ) -> String {
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        let mode = semanticMode(facts.mode)
        if mode == "Rule" { return finalRuleLine(facts.finalRuleRoute) }
        guard mode == "Global" else { return "" }
        var parts: [String] = []
        if let selected = facts.selectedProxyName?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !selected.isEmpty {
            parts.append(selected)
        }
        if let delay = facts.selectedProxyDelayMilliseconds, delay >= 0 {
            parts.append("\(delay) ms")
        }
        return parts.joined(separator: " · ")
    }

     
     
     
    private static func finalRuleLine(_ route: ClashHomeFinalRuleRoute?) -> String {
        guard let route else { return "" }
        let node = route.node.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !node.isEmpty else { return "" }
        var parts: [String] = []
        if let group = route.group?.trimmingCharacters(in: .whitespacesAndNewlines), !group.isEmpty {
            parts.append(group)
        }
        parts.append(node)
        if let delay = route.delayMilliseconds, delay >= 0 {
            parts.append("\(delay) ms")
        }
        return parts.joined(separator: " · ")
    }
}

public enum ClashHomeCommand: Codable, Equatable, Sendable {
    case openProfiles
    case performPrimaryAction(ClashHomePrimaryAction)
    case showConnectionIssue
     
     
     
    case resetVPNProfile
     
     
     
    case openOnDemand
    case openProxies
    case openRules
    case openRuntimeConfiguration
    case setCards([ClashHomeCard])
    case setTrafficScope(ClashHomeTrafficScope)
    case refreshExternalIP
    case refreshLANIP
}
