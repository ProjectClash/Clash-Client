import SwiftUI
import ClashClientKit

 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashTVProductState {
    var observations = ClashTVControlObservations()
     
     
     
    enum Stage { case disconnected, connecting, connected, disconnecting }

     
     
     
     
    enum Fixture { case prototype, manyGroups, manyGroupsTenNodes, longNames }

    var stage: Stage = .disconnected
     
     
     
    var autoConnect: Bool = false
     
     
    var autoConnectIssue: String?
     
    var iCloudRestoreLine: String?
     
     
    var issue: String?
    var vpnAuthorization: ClashVPNAuthorizationState?
     
     
    var pipelinePhase: ClashTVConfigPipeline.Phase?
     
     
     
     
    var refresh: Refresh?

    enum Refresh: Equatable {
        case updating(ClashTVSubscription.ID, ClashTVConfigPipeline.Phase)
        case failed(ClashTVSubscription.ID, String)
    }
     
     
     
     
    var feedback = ClashFeedbackCenterState()
     
     
     
    var feedbackPlace: ClashTVFeedback.Screen?
    var profileName: String = "Home profile"
    var profileAge: String = "Updated 2 hours ago"
     
     
     
    var profileUpdatedAt: Date?
    var nodeName: String = "Hong Kong 04"
    var nodeGroup: String = "Node selection"
    var outboundMode: ClashTVOutboundMode = .rule
    var nodeCount: Int = 37
    var groupCount: Int = 12
    var ruleCount: Int = 1284
     
    var connectedSince: Date? = Date(timeIntervalSinceNow: -(72 * 60 + 5))
     
    var downloadBytesPerSecond: Int64 = 6_025_000
    var uploadBytesPerSecond: Int64 = 387_500
    var sessionBytes: Int64 = 2_576_980_378
    var connectionCount: Int = 46

     
     
    var proxyGroups: [ClashProxyGroupSnapshot]
     
     
     
     
     
    var hiddenProxyGroups: [ClashProxyGroupSnapshot] = []
     
     
     
    var latency: [String: ClashProxyLatencyState]
     
     
    var groupReadingURLs: [String: String] = [:]
     
     
    var failureReasons: [String: String] = [:]
     
     
     
    var easyTierNodeNames: Set<String> = []
     
     
    var rules: [ClashRuleLineSnapshot]
     
     
     
    var indexedRules: ClashTVIndexedRules? = nil
     
     
     
    var indexedRulesRead: ClashTVIndexedRulesRead? = nil
     
     
     
    var connections: [ClashActivityConnectionSnapshot]

     
     
    var memoryBytes: Int64 = 29_779_558
    var geodataSource: String = "Bundled"
    var ruleProvidersLoaded: Int = 4
    var ruleProvidersTotal: Int = 4
     
     
     
    var providerRefresh: ProviderRefreshState? = ClashTVProviderCatalog.Entry.prototypeRecord
     
     
     
     
     
    var pendingCompileFailures: [String: String] = [:]
     
     
     
     
     
     
    var providers: [ClashTVProviderCatalog.Entry] = ClashTVProviderCatalog.Entry.prototype
     
     
     
     
     
     
     
     
     
     
     
    var lastProblem: Problem? = Problem(
        sentence: String(localized: "The profile URL could not be fetched: the request timed out."),
        at: Date().addingTimeInterval(-22 * 60),
        aboutProfile: true
    )

    struct Problem: Equatable {
        let sentence: String
        let at: Date
         
         
        var aboutProfile = false
    }

    mutating func note(problem: String, at moment: Date = Date(), aboutProfile: Bool = false) {
        lastProblem = Problem(sentence: problem, at: moment, aboutProfile: aboutProfile)
    }

     
     
    var remoteControlProblemNoted: String?
     
     
    var remoteControlPendingGeneration: Int?

     
     
    var dnsEnhancedMode: String = "fake-ip"
    var dnsNameservers: [String] = ["https://doh.pub/dns-query", "https://dns.alidns.com/dns-query"]
    var dnsFallback: [String] = ["https://1.1.1.1/dns-query", "tls://8.8.4.4"]
    var dnsDefaultNameservers: [String] = ["223.5.5.5", "119.29.29.29"]

    var isConnected: Bool { stage == .connected }

     
     
     
    static var empty: ClashTVProductState {
        var state = ClashTVProductState(fixture: .prototype)
        state.observations = .init()
        state.stage = .disconnected
        state.profileName = ""
        state.profileAge = ""
        state.nodeName = ""
        state.nodeGroup = ""
        state.nodeCount = 0
        state.groupCount = 0
        state.ruleCount = 0
        state.connectedSince = nil
        state.downloadBytesPerSecond = 0
        state.uploadBytesPerSecond = 0
        state.sessionBytes = 0
        state.connectionCount = 0
        state.proxyGroups = []
        state.hiddenProxyGroups = []
        state.latency = [:]
        state.groupReadingURLs = [:]
        state.rules = []
        state.connections = []
         
         
         
         
         
        state.providers = []
        state.providerRefresh = nil
        state.lastProblem = nil
        state.memoryBytes = 0
        state.ruleProvidersLoaded = 0
        state.ruleProvidersTotal = 0
        state.dnsEnhancedMode = ""
        state.dnsNameservers = []
        state.dnsFallback = []
        state.dnsDefaultNameservers = []
        return state
    }

    init(fixture: Fixture = .prototype) {
        let built = Self.buildProxyFixture(fixture)
        proxyGroups = built.groups
        latency = built.latency
        rules = Self.buildRulesFixture()
        ruleCount = rules.count
        connections = Self.buildConnectionsFixture()
        connectionCount = connections.count
        observations = .fixture()
    }

     
     
     
     
     
    mutating func pin(member: String, in groupName: String) {
        guard let index = proxyGroups.firstIndex(where: { $0.name == groupName }) else { return }
        let group = proxyGroups[index]
         
         
         
        guard group.allowsMemberChoice,
              group.membership(of: member) == .member
        else { return }
        proxyGroups[index] = ClashProxyGroupSnapshot(
            name: group.name,
            type: group.type,
            members: group.members,
            configuredSelection: group.configuredSelection,
            runtimeSelection: member,
            resolvedRuntimeRoute: group.resolvedRuntimeRoute,
            icon: group.icon,
            emptyFallback: group.emptyFallback,
            memberTotal: group.memberTotal
        )
    }

     
     
     
    mutating func unpin(group groupName: String) {
        guard let index = proxyGroups.firstIndex(where: { $0.name == groupName }) else { return }
        let group = proxyGroups[index]
        proxyGroups[index] = ClashProxyGroupSnapshot(
            name: group.name,
            type: group.type,
            members: group.members,
            configuredSelection: nil,
            runtimeSelection: group.runtimeSelection,
            resolvedRuntimeRoute: group.resolvedRuntimeRoute,
            icon: group.icon,
            emptyFallback: group.emptyFallback,
            memberTotal: group.memberTotal
        )
    }

     

    private static func buildProxyFixture(
        _ fixture: Fixture
    ) -> (groups: [ClashProxyGroupSnapshot], latency: [String: ClashProxyLatencyState]) {
         
         
         
        let protocols = ["shadowsocks", "shadowsocks", "shadowsocks", "trojan", "vmess", "hysteria2"]
        let delays = [94, 117, 112, 151, 197, 166, 180, 129, 148, 103, 88, 210, 176, 134, 121, 99, 158, 143]
         
         
         
         
        let longTails = ["IEPL 专线 1.5x [Premium]", "BGP · 家宽 · 0.8x", "Netflix / Disney+ 解锁 · 2x", "IPLC 中转 · 低延迟", "Standard 1x", "游戏加速 · UDP · 3x"]
        let hongKong = (1...18).map { index in
            ClashProxyMemberSnapshot(
                name: fixture == .longNames
                    ? String(format: "🇭🇰 Hong Kong %02d · %@", index, longTails[(index - 1) % longTails.count])
                    : String(format: "Hong Kong %02d", index),
                type: protocols[(index - 1) % protocols.count]
            )
        }
        var latency: [String: ClashProxyLatencyState] = [:]
        for (member, delay) in zip(hongKong, delays) {
            latency[member.name] = .measured(milliseconds: delay)
        }
         
        latency[hongKong[4].name] = .failed
         
         
         
         
        latency[hongKong[5].name] = .testing
        latency[hongKong[6].name] = .testing
        latency[hongKong[7].name] = .timedOut
        let singapore = (1...6).map { index in
            ClashProxyMemberSnapshot(name: String(format: "Singapore %02d", index), type: "trojan")
        }
        for (index, member) in singapore.enumerated() {
            latency[member.name] = .measured(milliseconds: 60 + index * 9)
        }
        let regions = [
            ClashProxyMemberSnapshot(name: "Hong Kong", type: "URLTest", isGroup: true),
            ClashProxyMemberSnapshot(name: "Streaming", type: "Selector", isGroup: true),
            ClashProxyMemberSnapshot(name: "DIRECT", type: "Direct"),
        ]
        var groups = [
            ClashProxyGroupSnapshot(
                name: "Node selection",
                type: "select",
                members: regions,
                configuredSelection: "Hong Kong"
            ),
            ClashProxyGroupSnapshot(
                name: "Hong Kong",
                type: "url-test",
                members: hongKong,
                runtimeSelection: hongKong[3].name
            ),
            ClashProxyGroupSnapshot(
                name: "Streaming",
                type: "select",
                members: singapore,
                configuredSelection: "Singapore 02"
            ),
            ClashProxyGroupSnapshot(
                name: "Fallback",
                type: "fallback",
                members: Array(hongKong.prefix(4)) + Array(singapore.prefix(2)),
                runtimeSelection: "Hong Kong 01"
            ),
            ClashProxyGroupSnapshot(
                name: "Final",
                type: "select",
                members: [
                    ClashProxyMemberSnapshot(name: "Node selection", type: "Selector", isGroup: true),
                    ClashProxyMemberSnapshot(name: "DIRECT", type: "Direct"),
                ]
            ),
        ]
        if fixture == .longNames {
             
             
            groups.swapAt(0, 1)
        }
        if fixture == .manyGroups || fixture == .manyGroupsTenNodes {
             
             
            let extra = ["Japan", "Taiwan", "Korea", "United States", "United Kingdom", "Germany",
                         "France", "Netherlands", "Canada", "Australia", "India", "Brazil",
                         "Turkey", "Russia", "Argentina", "South Africa"]
            for (regionIndex, region) in extra.enumerated() {
                let perGroup = fixture == .manyGroupsTenNodes ? 10 : 4
                let members = (1...perGroup).map { index in
                    ClashProxyMemberSnapshot(
                        name: String(format: "%@ %02d", region, index),
                        type: protocols[(index + regionIndex) % protocols.count]
                    )
                }
                for (index, member) in members.enumerated() {
                    latency[member.name] = .measured(milliseconds: 120 + regionIndex * 7 + index * 11)
                }
                groups.append(
                    ClashProxyGroupSnapshot(
                        name: region,
                        type: regionIndex % 3 == 0 ? "url-test" : "select",
                        members: members,
                        runtimeSelection: members.first?.name
                    )
                )
            }
        }
        return (groups, latency)
    }

     
     
     
     
     
     
    private static func buildRulesFixture() -> [ClashRuleLineSnapshot] {
        func line(_ type: String, _ payload: String, _ target: String) -> ClashRuleLineSnapshot {
            ClashRuleLineSnapshot(
                raw: [type, payload, target].filter { !$0.isEmpty }.joined(separator: ","),
                type: type,
                payload: payload,
                target: target
            )
        }
        var rules: [ClashRuleLineSnapshot] = [
            line("DST-PORT", "443", "Node selection"),
            line("NETWORK", "udp", "DIRECT"),
            line("PROCESS-NAME", "com.apple.Music", "DIRECT"),
            line("PROCESS-PATH", "/Applications/Safari.app", "Node selection"),
            line("IP-CIDR", "192.168.0.0/16", "DIRECT"),
            line("SOURCE-APP-TEAM-ID", "EXAMPLETEAM", "DIRECT"),
            line("IP-ASN", "13335", "Node selection"),
            line("RULE-SET", "streaming", "Streaming"),
            line("AND", "((DOMAIN-SUFFIX,cdn.example),(NETWORK,tcp))", "Node selection"),
        ]
        let words = ["cdn", "static", "img", "api", "edge", "media", "video", "login", "auth", "sync"]
        let tlds = ["com", "net", "org", "io", "tv", "app"]
        let targets = ["Node selection", "Streaming", "DIRECT", "Hong Kong"]
        for index in 0..<1_240 {
            let word = words[index % words.count]
            let tld = tlds[(index / words.count) % tlds.count]
            let target = targets[index % targets.count]
            switch index % 9 {
            case 0, 1, 2, 3, 4:
                rules.append(line("DOMAIN-SUFFIX", "\(word)\(index).example.\(tld)", target))
            case 5:
                rules.append(line("DOMAIN-KEYWORD", "\(word)\(index)", target))
            case 6:
                rules.append(line("GEOIP", ["cn", "us", "jp", "hk"][index % 4], target))
            case 7:
                rules.append(line("IP-CIDR", "10.\(index % 255).0.0/16", "DIRECT"))
            default:
                rules.append(line("DST-PORT", "\(8_000 + index % 1_000)", target))
            }
            if index % 40 == 39 {
                rules.append(line("RULE-SET", "provider-\(index / 40)", target))
            }
            if index % 400 == 399 {
                rules.append(line("PROCESS-NAME-REGEX", "^com\\.example\\.\(word)", "DIRECT"))
                rules.append(line("IN-USER", "guest", "DIRECT"))
            }
        }
        rules.append(line("GEOSITE", "cn", "DIRECT"))
        rules.append(line("GEOIP", "cn", "DIRECT"))
        rules.append(line("MATCH", "", "Final"))
        return rules
    }

     
     
     
     
     
     
    private static func buildConnectionsFixture() -> [ClashActivityConnectionSnapshot] {
        struct Seed {
            let destination: String
            let rule: String
            let payload: String
            let chains: [String]
            let bytes: Int64
        }
        let seeds: [Seed] = [
            Seed(destination: "occ-0-2774-2773.1.nflxso.net:443", rule: "GeoSite", payload: "netflix", chains: ["Hong Kong 04", "Hong Kong", "Streaming"], bytes: 13_002_342),
            Seed(destination: "ipv4-c002-hkg001-ix.1.oca.nflxvideo.net:443", rule: "GeoSite", payload: "netflix", chains: ["Hong Kong 04", "Hong Kong", "Streaming"], bytes: 421_527_040),
            Seed(destination: "time.apple.com:123", rule: "Domain", payload: "time.apple.com", chains: ["DIRECT"], bytes: 1_229),
            Seed(destination: "gateway.icloud.com:443", rule: "RuleSet", payload: "apple", chains: ["DIRECT"], bytes: 90_112),
            Seed(destination: "ads.example-tracker.net:443", rule: "GeoSite", payload: "category-ads-all", chains: ["REJECT", "Ads"], bytes: 0),
            Seed(destination: "api.github.com:443", rule: "DomainSuffix", payload: "github.com", chains: ["Hong Kong 04", "Hong Kong", "Node selection"], bytes: 34_816),
            Seed(destination: "unknown-host.example.org:443", rule: "Match", payload: "", chains: ["Hong Kong 04", "Hong Kong", "Final"], bytes: 2_048),
        ]
        var rows: [ClashActivityConnectionSnapshot] = []
         
         
         
         
         
        let base = Date().addingTimeInterval(-90)
        func append(_ seed: Seed, index: Int) {
            rows.append(
                ClashActivityConnectionSnapshot(
                    id: "fixture-\(index)",
                    destination: seed.destination,
                    source: "192.168.1.20:\(51_000 + index)",
                    network: index % 5 == 0 ? "UDP" : "TCP",
                    route: seed.chains.joined(separator: " → "),
                    rule: seed.rule,
                    upload: seed.bytes / 12,
                    download: seed.bytes - seed.bytes / 12,
                    start: base.addingTimeInterval(TimeInterval(-index * 7)),
                    chains: seed.chains,
                    rulePayload: seed.payload
                )
            )
        }
        for (index, seed) in seeds.enumerated() {
            append(seed, index: index)
        }
         
        let proxiedHosts = ["cdn.example.tv", "static.example.app", "img.example.io", "video.example.net", "edge.example.com"]
        let directHosts = ["push.apple.com", "mesu.apple.com", "ocsp.apple.com", "configuration.ls.apple.com"]
        var index = seeds.count
        var proxied = seeds.filter { $0.chains.first != "DIRECT" && $0.chains.first != "REJECT" }.count
        var direct = seeds.filter { $0.chains.first == "DIRECT" }.count
        while proxied < 31 {
            append(Seed(destination: "\(proxiedHosts[index % proxiedHosts.count]):443", rule: "DomainSuffix",
                        payload: proxiedHosts[index % proxiedHosts.count],
                        chains: ["Hong Kong 04", "Hong Kong", index % 2 == 0 ? "Node selection" : "Streaming"],
                        bytes: Int64(20_000 + index * 3_331)), index: index)
            index += 1; proxied += 1
        }
        while direct < 14 {
            append(Seed(destination: "\(directHosts[index % directHosts.count]):443", rule: "GeoSite",
                        payload: "apple", chains: ["DIRECT"], bytes: Int64(3_000 + index * 517)), index: index)
            index += 1; direct += 1
        }
        return rows
    }
}

 
 
 
 
 
 
 
 
 
 
 
enum ClashTVOutboundMode: String, CaseIterable, Equatable, Sendable {
    case global
    case rule
    case direct

     
    var title: String {
        switch self {
        case .global: String(localized: "Global")
        case .rule: String(localized: "Rule")
        case .direct: String(localized: "Direct")
        }
    }

     
     
    var kernelToken: String { rawValue }

     
     
     
    var explanation: String {
        switch self {
        case .global: String(localized: "Send all traffic through the selected proxy")
        case .rule: String(localized: "Route traffic by the profile rules")
        case .direct: String(localized: "Connect directly, without a proxy")
        }
    }
}


 
struct ClashTVControlObservations: Equatable {
    var generation: UInt64 = 0
    var lastEndedGeneration: UInt64?
    var traffic = ClashTVObservation()
    var totals = ClashTVObservation()
    var memory = ClashTVObservation()
    var proxies = ClashTVObservation()
     
     
     
    var latency = ClashTVObservation()
    var connections = ClashTVObservation()
    var mode = ClashTVObservation()

    private static let fields: [WritableKeyPath<Self, ClashTVObservation>] = [
        \.traffic, \.totals, \.memory, \.proxies, \.latency, \.connections, \.mode
    ]

    mutating func beginGeneration() {
        generation &+= 1
        for field in Self.fields { self[keyPath: field].forgetRuntime() }
    }

    mutating func waitForUpdate() {
        for field in Self.fields { self[keyPath: field].waitForUpdate() }
    }

    static func fixture(at date: Date = Date()) -> Self {
        var result = Self()
        for field in Self.fields { result[keyPath: field].accept(.init(date: date)) }
        return result
    }
}

struct ClashTVObservation: Equatable {
    enum Source { case unknown, configuration, selection, operation, runtime }
    enum FailureKind { case notSent, resultUnknown, invalidReply, readFailed }
    struct Failure: Equatable {
        let kind: FailureKind
        let message: String
    }
    struct Moment: Equatable {
        var date: Date
        var instant: ContinuousClock.Instant = .now
    }

    private(set) var source: Source = .unknown
    private(set) var lastSuccess: Date?
    private(set) var lastSuccessInstant: ContinuousClock.Instant?
    private(set) var version: UInt64 = 0
    private(set) var failure: Failure?
    private(set) var waitingForUpdate = false
    private(set) var operationConfirmedAt: Date?

    var hasRuntimeSample: Bool { source == .runtime && lastSuccess != nil }
    var hasValue: Bool { source != .unknown }
    var confirmsCurrentValue: Bool {
        (hasRuntimeSample || source == .operation) && failure == nil && !waitingForUpdate
    }

    mutating func accept(_ moment: Moment) {
        source = .runtime
        lastSuccess = moment.date
        lastSuccessInstant = moment.instant
        version &+= 1
        failure = nil
        waitingForUpdate = false
        operationConfirmedAt = nil
    }

    mutating func fail(_ failure: Failure) {
        self.failure = failure
        waitingForUpdate = false
    }

    mutating func waitForUpdate() {
        if source == .runtime || source == .operation { waitingForUpdate = true }
    }

    mutating func useConfiguration() {
        forgetRuntime()
        source = .configuration
    }

    mutating func selectLocally() {
        forgetRuntime()
        source = .selection
    }

    mutating func acknowledgeOperation(at date: Date) {
        source = .operation
        operationConfirmedAt = date
        waitingForUpdate = false
        failure = nil
         
    }

    mutating func forgetRuntime() {
        if source != .configuration && source != .selection { source = .unknown }
        lastSuccess = nil
        lastSuccessInstant = nil
        operationConfirmedAt = nil
        failure = nil
        waitingForUpdate = false
    }

    func value(_ knownValue: String, unknown: String = "—") -> String {
        hasValue ? knownValue : unknown
    }

     
    static func failureMessages(_ observations: [Self]) -> [String] {
        var seen = Set<String>()
        return observations.compactMap { $0.failure?.message }.filter { seen.insert($0).inserted }
    }

    var summary: String {
        if let lastSuccess, hasRuntimeSample {
            let when = Self.timestamp(lastSuccess)
            if failure != nil { return String(localized: "Update unsuccessful · Last read \(when)") }
            if waitingForUpdate { return String(localized: "Waiting for update · Last read \(when)") }
            return String(localized: "Last read \(when)")
        }
        switch source {
        case .configuration:
            return failure == nil ? String(localized: "From configuration") : String(localized: "From configuration · Update unsuccessful")
        case .selection:
            return String(localized: "Selected locally · Runtime not confirmed")
        case .operation:
            guard let operationConfirmedAt else { return String(localized: "Not yet confirmed") }
            let when = Self.timestamp(operationConfirmedAt)
            if failure != nil { return String(localized: "Update unsuccessful · Choice confirmed \(when)") }
            if waitingForUpdate { return String(localized: "Waiting for runtime confirmation") }
            return String(localized: "Choice confirmed \(when)")
        case .unknown, .runtime:
            return failure == nil ? String(localized: "Not yet confirmed") : String(localized: "Update unsuccessful · Not yet confirmed")
        }
    }

    private static func timestamp(_ date: Date) -> String {
         
        date.formatted(date: .numeric, time: .standard)
    }
}

 
struct ClashTVObservationNote: View {
    let observations: [ClashTVObservation]

    init(observation: ClashTVObservation) { observations = [observation] }
    init(observations: [ClashTVObservation]) { self.observations = observations }

    var body: some View {
        let messages = ClashTVObservation.failureMessages(observations)
        if !messages.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(messages, id: \.self) { Text(verbatim: $0) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        }
    }
}

 
 
enum ClashTVIndexedRulesRead: Equatable {
    case reading
    case unavailable
}
