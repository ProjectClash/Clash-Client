import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashTVBrandMark: View {
     
     
     
    static let width: CGFloat = 307
     
     
     
    static let aboutWidth: CGFloat = 200

    var width: CGFloat = ClashTVBrandMark.width

    var body: some View {
        Image("ClashBrandMark")
            .resizable()
            .scaledToFit()
            .frame(width: width)
            .accessibilityHidden(true)
    }
}

 

 
 
 
enum ClashTVTestAppearance: String, Equatable, Sendable {
    case light
    case dark

    var colorScheme: ColorScheme {
        switch self {
        case .light: .light
        case .dark: .dark
        }
    }
}

enum ClashTVTestContentSize: String, Equatable, Sendable {
    case accessibilityExtraLarge = "accessibility-extra-large"
}

 
 
enum ClashTVTestStage: String, Equatable, Sendable {
    case welcome
    case home
    case connected
     
    case outboundMode = "outbound-mode"
     
    case globalQuestion = "global-question"
     
     
    case chooseNodeGlobal = "choose-node-global"
     
     
    case nodes
     
     
    case nodesMany = "nodes-many"
     
     
    case nodesLongNames = "nodes-long-names"
     
     
    case nodesManyTen = "nodes-many-ten"
     
     
    case nodesDirect = "nodes-direct"
     
    case rules
     
    case connections
     
     
    case connectionsLive = "connections-live"
     
     
     
    case connectionDetail = "connection-detail"
     
     
    case subscriptions
     
    case proxyShare = "proxy-share"
     
     
    case subscriptionDetail = "subscription-detail"
     
     
    case editSubscription = "edit-subscription"
     
     
    case profileRules = "profile-rules"
     
     
    case addSubscription = "add-subscription"
     
    case more
    case diagnostics
     
    case logs
    case dns
     
     
     
    case userAgent = "user-agent"
     
    case providers

     
     
    var opensNodes: Bool {
        switch self {
        case .nodes, .nodesMany, .nodesManyTen, .nodesLongNames, .nodesDirect: true
        default: false
        }
    }

     
     
    var outboundModeOverride: ClashTVOutboundMode? {
        self == .nodesDirect ? .direct : nil
    }
}

struct ClashTVLaunchOverrides: Equatable, Sendable {
    let appearance: ClashTVTestAppearance?
    let contentSize: ClashTVTestContentSize?
    let stage: ClashTVTestStage?
     
     
     
     
    let connectsOnLaunch: Bool
     
     
     
    let updatesOnLaunch: Bool
     
     
    let disconnectsOnLaunch: Bool
     
     
     
    let useProfileURL: String?
     
     
    let scriptURL: String?
     
     
    let updatesScriptOnLaunch: Bool
     
     
     
     
    let rulesForCurrent: ClashTVProfileRules?
     
     
     
    let allowLAN: Bool?
     
     
     
     
    let proxyShare: ProxyShareConfiguration?
     
     
     
    let probeSpec: String?
     
     
    let switchWatch: String?
     
     
    let mdnsProbe: String?
     
    let dumpsDiagnostics: Bool
     
     
     
     
    let seedsProviderNotLaunched: Bool
     
     
     
    let opens: String?
     
     
     
     
    let feedbackSample: String?
     
     
     
     
     
    let externalControllerSample: String?



    init(environment: [String: String]) {
        appearance = environment["CLASH_TV_APPEARANCE"]
            .flatMap(ClashTVTestAppearance.init(rawValue:))
        contentSize = environment["CLASH_TV_CONTENT_SIZE"]
            .flatMap(ClashTVTestContentSize.init(rawValue:))
        stage = environment["CLASH_TV_STAGE"]
            .flatMap(ClashTVTestStage.init(rawValue:))
        connectsOnLaunch = environment["CLASH_TV_CONNECT_ON_LAUNCH"] == "1"
        updatesOnLaunch = environment["CLASH_TV_UPDATE_ON_LAUNCH"] == "1"
        disconnectsOnLaunch = environment["CLASH_TV_DISCONNECT_ON_LAUNCH"] == "1"
        useProfileURL = environment["CLASH_TV_USE_PROFILE_URL"]
        scriptURL = environment["CLASH_TV_SCRIPT_URL"]
        updatesScriptOnLaunch = environment["CLASH_TV_UPDATE_SCRIPT_ON_LAUNCH"] == "1"
        rulesForCurrent = environment["CLASH_TV_RULES"].flatMap(ClashTVProfileRules.init(rawValue:))
        allowLAN = environment["CLASH_TV_ALLOW_LAN"].flatMap { $0 == "1" ? true : ($0 == "0" ? false : nil) }
        proxyShare = Self.proxyShareOverride(environment["CLASH_TV_PROXY_SHARE"])
        probeSpec = environment["CLASH_TV_PROBE"]
        switchWatch = environment["CLASH_TV_SWITCH_WATCH"]
        mdnsProbe = environment["CLASH_TV_MDNS_PROBE"]
        dumpsDiagnostics = environment["CLASH_TV_DIAG"] == "1"
        seedsProviderNotLaunched = environment["CLASH_TV_SEED_PROVIDER_NOT_LAUNCHED"] == "1"
        opens = environment["CLASH_TV_OPEN"]
        feedbackSample = environment["CLASH_TV_FEEDBACK_SAMPLE"]
        externalControllerSample = environment["CLASH_TV_EXTERNAL_CONTROLLER"]


    }
}

extension ClashTVLaunchOverrides {
     
     
     
    static func proxyShareOverride(_ raw: String?) -> ProxyShareConfiguration? {
        guard let raw, !raw.isEmpty else { return nil }
        let parts = raw.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, let port = Int32(parts[0]) else { return nil }
        let username = String(parts[1]), password = String(parts[2])
        guard !username.isEmpty, !password.isEmpty else { return nil }
        return ProxyShareConfiguration(port: port, username: username, password: password)
    }
}
