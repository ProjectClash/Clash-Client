import Foundation
import ClashClientKit
import ClashClientUI

typealias HomeSection = ClashClientUI.ClashHomeSection
typealias HomeFavoriteCard = ClashClientUI.ClashHomeCard

typealias ClashCopy = ClashClientUI.ClashCopy

 
 
 
 
enum ConfigurationProductSurface: String, Equatable, Sendable {
    case homeGeneral
    case homeOverride
    case proxies
    case utilities
    case more
    case homeFinalConfiguration
}

enum ConfigurationCapabilityID: String, CaseIterable, Sendable {
    case mode
    case dnsAndHosts
    case routingRules
    case proxiesAndGroups
    case proxySources
    case ruleSets
    case tunnelAndAddressing
    case trafficRecognition
    case timeSynchronization
    case advancedRuntime
    case advancedTrust
    case geoData
    case automaticRuntimeAdaptations
    case localProxyListeners
    case externalController
    case unsupportedInboundServers
    case unsupportedPlatformServices
}

struct ConfigurationCapabilityPlacement: Equatable, Sendable {
    let id: ConfigurationCapabilityID
    let title: String
    let sourceKeys: [String]
    let surface: ConfigurationProductSurface
    let rationale: String
}

enum ConfigurationSurfaceCatalog {
     
     
     
     
     
    static let configCapabilities: [ConfigurationCapabilityPlacement] = [
        .init(
            id: .mode,
            title: "Mode & Route",
            sourceKeys: ["mode"],
            surface: .homeGeneral,
            rationale: "A frequent app-wide runtime decision."
        ),
        .init(
            id: .dnsAndHosts,
            title: "DNS & Local Mapping",
            sourceKeys: ["dns", "hosts"],
             
            surface: .homeOverride,
            rationale: "A configuration's own DNS and hosts, edited in its editor."
        ),
        .init(
            id: .routingRules,
            title: "Rules",
            sourceKeys: ["rules", "sub-rules"],
            surface: .homeOverride,
            rationale: "These fields change how the current profile routes traffic."
        ),
        .init(
            id: .proxiesAndGroups,
            title: "Proxies",
            sourceKeys: ["proxies", "proxy-groups"],
            surface: .proxies,
            rationale: "Configured policy groups and nodes are always browsable; connection adds live runtime state."
        ),
        .init(
            id: .proxySources,
            title: "Proxy Sources",
            sourceKeys: ["proxy-providers"],
            surface: .homeOverride,
            rationale: "The source belongs to this profile; its live health remains read-only in Utilities."
        ),
        .init(
            id: .ruleSets,
            title: "Rule Sets",
            sourceKeys: ["rule-providers"],
            surface: .homeOverride,
            rationale: "Rule-set materialization and update policy are profile configuration."
        ),
        .init(
            id: .tunnelAndAddressing,
            title: "Tunnel & Routes",
            sourceKeys: ["tun"],
             
             
            surface: .homeOverride,
            rationale: "A configuration's own TUN settings, edited in its editor."
        ),
        .init(
            id: .trafficRecognition,
            title: "Traffic Recognition",
            sourceKeys: ["sniffer"],
            surface: .homeOverride,
            rationale: "Sniffing changes rule matching and therefore belongs beside profile networking."
        ),
        .init(
            id: .timeSynchronization,
            title: "Time Synchronization",
            sourceKeys: ["ntp"],
            surface: .homeOverride,
            rationale: "Core network-time offsets are profile networking; changing the Apple system clock remains unavailable."
        ),
        .init(
            id: .advancedRuntime,
            title: "Core Behavior",
            sourceKeys: [
                "ipv6", "unified-delay", "log-level",
                "geosite-matcher", "tcp-concurrent",
                "global-ua", "keep-alive-idle", "keep-alive-interval",
                "disable-keep-alive",
            ],
             
             
            surface: .homeOverride,
            rationale: "A configuration's own core behavior, edited in its editor."
        ),
        .init(
            id: .advancedTrust,
            title: "Trust & Experimental",
            sourceKeys: ["tls", "experimental"],
            surface: .homeOverride,
             
             
            rationale: "A configuration's own TLS and experimental settings, edited in its editor."
        ),
        .init(
            id: .geoData,
            title: "Geo Data",
            sourceKeys: [
                "geox-url", "geo-auto-update", "geo-update-interval",
            ],
            surface: .more,
            rationale: "GeoIP, GeoSite, ASN, and MMDB assets are shared across profiles."
        ),
        .init(
            id: .automaticRuntimeAdaptations,
            title: "Client-managed Runtime",
            sourceKeys: [
                "geodata-loader", "geodata-mode", "etag-support",
                "profile",
            ],
            surface: .homeFinalConfiguration,
            rationale: "iOS fixes the memory-safe Geo loader, pins the GeoIP data mode, and performs conditional HTTP updates in the Client instead of exposing ineffective Core toggles."
        ),
        .init(
            id: .localProxyListeners,
            title: "Local Proxy & Inbound Servers",
            sourceKeys: [
                "port", "socks-port", "mixed-port", "inbound-tfo", "inbound-mptcp",
                "allow-lan", "bind-address", "authentication",
                "skip-auth-prefixes", "lan-allowed-ips", "lan-disallowed-ips",
                 
                 
                 
                 
                "ss-config", "vmess-config", "tuic-server", "listeners", "tunnels",
            ],
            surface: .utilities,
            rationale: "The core opens the listener the profile asks for. Only allow-lan needs a decision from the reader, because only it moves the listener off 127.0.0.1, so LAN Proxy Share carries the switch and the other ten arrive unconditionally."
        ),
        .init(
            id: .externalController,
            title: "External Controller",
            sourceKeys: [
                "external-controller", "external-controller-tls",
                "external-controller-cors", "external-controller-unix",
                "secret", "external-doh-server",
                 
                 
                "external-ui", "external-ui-name", "external-ui-url",
            ],
            surface: .homeFinalConfiguration,
            rationale: "Runs as written. This entry called the family inert while that was true, and it stopped being true the night the core wired the address to route.ReCreateServer — a sentence describing behaviour a build no longer has is the defect this surface exists to prevent."
        ),
        .init(
            id: .unsupportedInboundServers,
            title: "Redirection Ports",
            sourceKeys: ["redir-port", "tproxy-port"],
            surface: .homeFinalConfiguration,
            rationale: "The two upstream itself refuses here: redirection reads /dev/pf, which the sandbox does not have, and transparent proxying returns \"not supported\" off Linux. The inbound servers that used to sit beside them — ss-config, vmess-config, tuic-server, listeners, tunnels — are the reader\'s to configure: upstream runs them and the platform allows them, and this app deciding otherwise was answering a question about somebody else\'s device."
        ),
        .init(
            id: .unsupportedPlatformServices,
            title: "Platform-only Services",
            sourceKeys: [
                "find-process-mode",
                "external-controller-pipe", "external-controller-routing-mark",
                "interface-name", "routing-mark",
                "global-client-fingerprint", "iptables", "clash-for-android",
            ],
            surface: .homeFinalConfiguration,
            rationale: "Desktop/router services are disclosed in iOS Changes and never presented as working controls."
        ),
    ]

    static func placement(
        for id: ConfigurationCapabilityID
    ) -> ConfigurationCapabilityPlacement? {
        configCapabilities.first { $0.id == id }
    }
}

struct ProfileFinalConfigurationDisclosure: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
     
     
     
     
    var strippedKeys: [String] = []
     
     
     
    var lines: [String] = []
}

 
 
 
 
struct ProfileFinalConfigurationSnapshot: Equatable, Sendable {
    let sourceText: String?
    let effectiveText: String?
    let fixedItems: [ProfileFinalConfigurationDisclosure]
    let unsupportedItems: [ProfileFinalConfigurationDisclosure]
    let adaptedItems: [ProfileFinalConfigurationDisclosure]
     
     
     
     
     
    let sourceFingerprint: Int
    let effectiveFingerprint: Int

    init(
        sourceText: String?,
        effectiveText: String?,
        fixedItems: [ProfileFinalConfigurationDisclosure],
        unsupportedItems: [ProfileFinalConfigurationDisclosure],
        adaptedItems: [ProfileFinalConfigurationDisclosure]
    ) {
        self.sourceText = sourceText
        self.effectiveText = effectiveText
        self.fixedItems = fixedItems
        self.unsupportedItems = unsupportedItems
        self.adaptedItems = adaptedItems
        sourceFingerprint = sourceText?.hashValue ?? 0
        effectiveFingerprint = effectiveText?.hashValue ?? 0
    }

     
     
    static func textOnly(sourceYAML: String?, effectiveYAML: String?) -> ProfileFinalConfigurationSnapshot {
        ProfileFinalConfigurationSnapshot(
            sourceText: presentedText(sourceYAML),
            effectiveText: presentedText(effectiveYAML),
            fixedItems: [],
            unsupportedItems: [],
            adaptedItems: []
        )
    }

     
     
     
     
     
     
     
     
     
     
     
    static func make(
        sourceYAML: String?,
        effectiveYAML: String?,
        omittedRules: [String] = [],
        omittedPersonalRules: [String] = []
    ) -> ProfileFinalConfigurationSnapshot {
        let sourceText = presentedText(sourceYAML)
        let effectiveText = presentedText(effectiveYAML)
        let source = object(sourceText)
        let effective = object(effectiveText)

        var adapted = adaptedDisclosures(source: source, effective: effective)
        if !omittedRules.isEmpty {
            adapted.append(.init(
                id: "omitted-rules",
                title: "Rules Not in Effect as Written",
                detail: "Each of these rules names a node that none of this configuration's node sources includes. A rule is left out and its traffic follows the rules below it; a final MATCH rule sends traffic directly instead. Add that node's source to this configuration, or route the rule to a policy group.",
                lines: omittedRules
            ))
        }
        if !omittedPersonalRules.isEmpty {
            adapted.append(.init(
                id: "omitted-personal-rules",
                title: "Custom Rules Not in Effect",
                detail: "Each of these rules uses a policy, rule set or sub-rule this configuration does not have, so it is left out and its traffic follows the rules below it. Change the rule to use one this configuration has.",
                lines: omittedPersonalRules
            ))
        }
        return ProfileFinalConfigurationSnapshot(
            sourceText: sourceText,
            effectiveText: effectiveText,
            fixedItems: fixedDisclosures,
            unsupportedItems: unsupportedDisclosures(in: source),
            adaptedItems: adapted
        )
    }

#if os(macOS)
     
     
     
     
    private static let fixedDisclosures: [ProfileFinalConfigurationDisclosure] = [
        .init(
            id: "network-extension",
            title: "Packet Tunnel",
            detail: "The connection is started and stopped by the macOS Network Extension."
        ),
         
         
         
         
         
         
         
         
         
         
        .init(
            id: "dns-interception",
            title: "DNS Interception",
            detail: "DNS interception runs inside the packet tunnel. A profile that sets dns.listen gets that listener too, opened exactly as written; only its Linux routing mark is zeroed."
        ),
         
         
         
         
        .init(
            id: "tunnel-stack",
            title: "Tunnel Stack",
            detail: "The tunnel runs the sing-box (Go) packet stack, whatever stack a profile writes: on the Mac the tunnel reads its own network interface, and that stack is the one built to drive it."
        ),
        .init(
            id: "geodata-loader",
            title: "Geo Data Loader",
            detail: "Clash reads Geo data with the standard filesystem loader on macOS; the memory-conservative mode is an iOS memory-budget measure."
        ),
        .init(
            id: "client-resource-updates",
            title: "Resource Updates",
            detail: "Clash downloads profile URLs, providers and Geo data in the Client with conditional HTTP and last-known-good recovery; the packet-tunnel Core does not perform background downloads."
        ),
         
         
         
         
         
         
         
         
         
         
        .init(
            id: "external-controller",
            title: "External Controller",
            detail: "The API listens at the configured address, TLS included, with the profile's secret and CORS rules applied. A profile that sets external-ui gets its web dashboard, as upstream serves it. Configuration writes stay with the app: the API serves reads, proxy selection and connection close."
        ),
    ]
#else
    private static let fixedDisclosures: [ProfileFinalConfigurationDisclosure] = [
        .init(
            id: "network-extension",
            title: "Packet Tunnel",
            detail: "The connection is started and stopped by iOS Network Extension."
        ),
        .init(
            id: "dns-interception",
            title: "DNS Interception",
             
             
             
             
             
            detail: "DNS interception runs inside the packet tunnel. A profile that sets dns.listen gets that listener too, opened exactly as written; only its Linux routing mark is zeroed."
        ),
        .init(
            id: "tunnel-stack",
            title: "Tunnel Stack",
             
             
             
             
             
             
             
            detail: "The tunnel runs the sing-box (Go) packet stack, whatever stack a profile writes: on iPhone and iPad the tunnel reads its own network interface, and that stack is the one built to drive it."
        ),
        .init(
            id: "geodata-loader",
            title: "Geo Data Loader",
            detail: "Clash always uses the memory-conservative, memory-mapped loader on iOS so large GeoIP and GeoSite databases stay off the app heap."
        ),
        .init(
            id: "client-resource-updates",
            title: "Resource Updates",
            detail: "Clash downloads profile URLs, providers and Geo data in the Client with conditional HTTP and last-known-good recovery; the packet-tunnel Core does not perform background downloads."
        ),
        .init(
            id: "external-controller",
            title: "External Controller",
             
             
             
             
             
             
             
             
             
             
            detail: "The API listens at the configured address, TLS included, with the profile's secret and CORS rules applied. A profile that sets external-ui gets its web dashboard, as upstream serves it. Configuration writes stay with the app: the API serves reads, proxy selection and connection close."
        ),
    ]
#endif

     
     
     
     
     
     
     
     
    private static var inboundKeys: Set<String> {
        ConfigTransforms.iosUnsupportedTopLevelKeys.intersection([
            "port", "socks-port", "redir-port", "tproxy-port", "mixed-port",
            "ss-config", "vmess-config", "inbound-tfo", "inbound-mptcp",
            "tuic-server", "allow-lan", "bind-address", "authentication",
            "skip-auth-prefixes", "lan-allowed-ips", "lan-disallowed-ips",
            "listeners", "tunnels",
        ])
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private static let deadControllerSpellings: Set<String> = [
        "external-controller-pipe", "external-controller-routing-mark",
    ]

    private static let platformRoutingKeys: Set<String> = [
        "interface-name", "routing-mark",
    ]

    private static let platformServiceKeys: Set<String> = [
        "iptables", "clash-for-android",
    ]

    private static func unsupportedDisclosures(
        in source: [String: Any]
    ) -> [ProfileFinalConfigurationDisclosure] {
        var result: [ProfileFinalConfigurationDisclosure] = []
        let keys = Set(source.keys)

        if !keys.isDisjoint(with: inboundKeys) {
            result.append(.init(
                id: "inbound-servers",
                title: "Redirection Ports",
                detail: "Redirection ports are removed from the runtime config, because Clash itself refuses them here too: the redirect listener needs a system facility an app on Apple is not allowed to open. Every other inbound field runs — listeners, tunnels and the protocol servers included — and LAN Proxy Share carries the allow-lan switch.",
                strippedKeys: keys.intersection(inboundKeys).sorted()
            ))
        }
#if !os(macOS)
         
         
         
         
        if keys.contains("find-process-mode") {
            result.append(.init(
                id: "process-lookup",
                title: "Process Lookup",
                detail: "A packet tunnel cannot attribute traffic to ordinary app processes. Process matching is disabled."
            ))
        }
#endif
        if !keys.isDisjoint(with: deadControllerSpellings) {
            result.append(.init(
                id: "external-control",
                title: "External Controller Spellings",
                detail: "Two spellings do not apply on this platform: the Windows named pipe is removed, and the routing mark is a Linux-only socket option that stays in the file and does nothing.",
                 
                 
                strippedKeys: keys.intersection(deadControllerSpellings)
                    .intersection(ConfigTransforms.iosUnsupportedTopLevelKeys).sorted()
            ))
        }
        if !keys.isDisjoint(with: platformRoutingKeys) {
            result.append(.init(
                id: "platform-routing",
                title: "Platform Routing Fields",
                detail: "Top-level interface names and Linux routing marks are not applied. Apple selects physical egress through Network Extension and its current network path.",
                strippedKeys: keys.intersection(platformRoutingKeys).sorted()
            ))
        }
        if keys.contains("global-client-fingerprint") {
            result.append(.init(
                id: "obsolete-global-fingerprint",
                title: "Global Client Fingerprint Is Obsolete",
                 
                 
                 
                 
                 
                 
                 
                detail: "Clash dropped this field upstream: the core logs an error and ignores it, on every platform, and your file is left as written. Set client-fingerprint on an individual proxy when that protocol supports it."
            ))
        }
        if !keys.isDisjoint(with: platformServiceKeys) {
            result.append(.init(
                id: "platform-services",
                title: "Router & Android Services",
                detail: "Fields meant for a Linux firewall or for Clash on Android stay in your file and do nothing here.",
                strippedKeys: keys.intersection(platformServiceKeys).sorted()
            ))
        }
        return result
    }

    private static func adaptedDisclosures(
        source: [String: Any],
        effective: [String: Any]
    ) -> [ProfileFinalConfigurationDisclosure] {
        var result: [ProfileFinalConfigurationDisclosure] = []

        if differs(path: ["dns", "enable"], source: source, effective: effective) {
            result.append(.init(
                id: "dns-service",
                title: "DNS Service Enabled",
                detail: "Clash enables the DNS engine required by the packet tunnel."
            ))
        }
        if value(path: ["dns", "listen-routing-mark"], in: source) != nil {
             
             
             
             
             
            result.append(.init(
                id: "dns-listener",
                title: "DNS Listener Mark Removed",
                detail: "The DNS listener opens as written; only its Linux socket mark is dropped, because socket marks are a Linux facility that Apple does not have."
            ))
        }
        if differs(path: ["tun", "enable"], source: source, effective: effective)
            || differs(path: ["tun", "stack"], source: source, effective: effective) {
            result.append(.init(
                id: "packet-tunnel",
                title: "Packet Tunnel Normalized",
                 
                 
                 
                detail: "Tunnel ownership is normalized for Apple's packet-flow contract."
            ))
        }
        if differs(path: ["profile", "store-fake-ip"], source: source, effective: effective) {
            result.append(.init(
                id: "fake-ip-persistence",
                title: "Fake-IP Storage Enabled",
                detail: "Clash keeps Fake-IP mappings stable across reloads and restarts."
            ))
        }
        if containsHTTPProvider(source) && !containsHTTPProvider(effective) {
            result.append(.init(
                id: "provider-materialization",
                title: "Remote Providers Materialized",
                detail: "The client downloaded remote provider data into the immutable profile revision before Core started."
            ))
        }
        return result
    }

    private static func presentedText(_ yaml: String?) -> String? {
        guard let yaml, !yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
         
         
        return yaml
    }

    private static func object(_ yaml: String?) -> [String: Any] {
        guard let yaml,
              let json = try? ConfigTransforms.yamlToJSON(yaml),
              let value = try? JSONSerialization.jsonObject(with: Data(json.utf8)),
              let root = value as? [String: Any] else {
            return [:]
        }
        return root
    }

    private static func value(path: [String], in root: [String: Any]) -> Any? {
        var current: Any = root
        for component in path {
            guard let dictionary = current as? [String: Any],
                  let next = dictionary[component] else {
                return nil
            }
            current = next
        }
        return current
    }

    private static func differs(
        path: [String],
        source: [String: Any],
        effective: [String: Any]
    ) -> Bool {
        canonical(value(path: path, in: source)) != canonical(value(path: path, in: effective))
    }

    private static func canonical(_ value: Any?) -> Data? {
        guard let value, JSONSerialization.isValidJSONObject(["value": value]) else { return nil }
        return try? JSONSerialization.data(withJSONObject: ["value": value], options: [.sortedKeys])
    }

    private static func containsHTTPProvider(_ root: [String: Any]) -> Bool {
        guard let providers = root["proxy-providers"] as? [String: Any] else { return false }
        return providers.values.contains { value in
            guard let provider = value as? [String: Any] else { return false }
            return (provider["type"] as? String)?.lowercased() == "http"
        }
    }
}

struct HomeFavoriteCardPreferences {
    static let key = "home.favorite.cards.v3"
     
    static let legacyKeyV2 = "home.favorite.cards.v2"
     
     
    static let legacyKey = "home.favorite.cards.v1"
     
     
    static let defaultCards = ClashClientUI.ClashHomeCatalog.defaultCards
     
     
    static let requiredCards = ClashClientUI.ClashHomeCatalog.requiredCards
    static let optionalCards = ClashClientUI.ClashHomeCatalog.optionalCards

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [HomeFavoriteCard] {
        if let raw = defaults.array(forKey: Self.key) as? [String] {
            let cards = Self.normalized(Self.decode(raw))
            if cards.map(\.rawValue) != raw {
                save(cards)
            }
            return cards
        }
        if let raw = defaults.array(forKey: Self.legacyKeyV2) as? [String] {
             
             
            var cards = Self.decode(raw)
            if !cards.contains(.traffic) { cards.append(.traffic) }
            cards = Self.normalized(cards)
            save(cards)
            return cards
        }
        if let legacyRaw = defaults.array(forKey: Self.legacyKey) as? [String] {
            var cards = Self.decode(legacyRaw)
             
             
             
            if let anchor = cards.firstIndex(of: .routing) {
                cards.insert(contentsOf: [.proxies, .rules], at: anchor + 1)
                if !cards.contains(.traffic) { cards.append(.traffic) }
            }
            cards = Self.normalized(cards)
            save(cards)
            return cards
        }
        return Self.defaultCards
    }

    private static func decode(_ raw: [String]) -> [HomeFavoriteCard] {
        var seen = Set<HomeFavoriteCard>()
        return raw.compactMap(HomeFavoriteCard.init(rawValue:)).filter {
            seen.insert($0).inserted
        }
    }

    private static func normalized(
        _ cards: [HomeFavoriteCard]
    ) -> [HomeFavoriteCard] {
        ClashClientUI.ClashHomeCatalog.normalized(cards)
    }

    func save(_ cards: [HomeFavoriteCard]) {
        let values = Self.normalized(cards).map(\.rawValue)
        defaults.set(values, forKey: Self.key)
    }
}

typealias HomeRecoveryMode = ClashClientUI.ClashHomeRecoveryMode
typealias HomeConnectionPhase =
    ClashClientUI.ClashHomeConnectionPhase
typealias HomePrimaryAction = ClashClientUI.ClashHomePrimaryAction
typealias HomeConnectionIssue = ClashClientUI.ClashHomeConnectionIssue
typealias HomeConnectionFacts = ClashClientUI.ClashHomeConnectionFacts
typealias HomeConnectionPresentation =
    ClashClientUI.ClashHomeConnectionPresentation
typealias HomeConnectionPresenter =
    ClashClientUI.ClashHomeConnectionPresenter

 
 
 
 
enum HomeProxiesEntryPolicy {
     
     
     
     
     
     
     
    static func groupToOpen(
        pending: String?,
        lastOpened: String?,
        groups: [String],
        readerFoldedAll: Bool = false,
        mode: ProxyBrowsingVisibility.Mode = .rule,
        liveCatalog: Bool = false
    ) -> String? {
        if let pending { return pending }
        if let global = globalToOpen(mode: mode, liveCatalog: liveCatalog, candidates: groups,
                                     readerFoldedAll: readerFoldedAll) { return global }
        if readerFoldedAll { return nil }
        if let lastOpened, groups.contains(lastOpened) { return lastOpened }
         
         
         
        return groups.first { $0 != ProxyBrowsingVisibility.kernelGlobalGroupName }
    }

     
     
     
     
     
     
     
     
     
     
    static func globalToOpen(mode: ProxyBrowsingVisibility.Mode, liveCatalog: Bool, candidates: [String],
                             readerFoldedAll: Bool) -> String? {
        let global = ProxyBrowsingVisibility.kernelGlobalGroupName
        return mode == .global && liveCatalog && !readerFoldedAll && candidates.contains(global) ? global : nil
    }

     
    private static func listed<Group>(_ groups: [Group], name: (Group) -> String, isHidden: (Group) -> Bool,
                                      coreMode: String, opening: ProxyBrowsingVisibility.Opening)
        -> (mode: ProxyBrowsingVisibility.Mode, names: [String]) {
        let mode = ProxyBrowsingVisibility.Mode(coreValue: coreMode)
        return (mode, candidates(groups, mode: mode, opening: opening, name: name, isHidden: isHidden))
    }

     
     
     
    private static func chooseNodeEntry(_ opening: ProxyBrowsingVisibility.Opening, candidates: [String]) -> String? {
        let global = ProxyBrowsingVisibility.kernelGlobalGroupName
        return opening == .choosingInGlobal && candidates.contains(global) ? global : nil
    }

     
     
    static func homeEntry<Group>(pending: String?, lastOpened: String?, groups: [Group], name: (Group) -> String,
                                 isHidden: (Group) -> Bool, coreMode: String, liveCatalog: Bool,
                                 readerFoldedAll: Bool, opening: ProxyBrowsingVisibility.Opening = .browsing) -> String? {
        let listed = listed(groups, name: name, isHidden: isHidden, coreMode: coreMode, opening: opening)
        if let global = chooseNodeEntry(opening, candidates: listed.names) { return global }
        return groupToOpen(pending: pending, lastOpened: lastOpened, groups: listed.names,
                           readerFoldedAll: readerFoldedAll, mode: listed.mode, liveCatalog: liveCatalog)
    }

     
     
     
     
     
     
     
    static func railEntry<Group>(openedGroup: String?, groups: [Group], name: (Group) -> String,
                                 isHidden: (Group) -> Bool, coreMode: String, liveCatalog: Bool,
                                 readerFoldedAll: Bool, opening: ProxyBrowsingVisibility.Opening = .browsing) -> String? {
        if opening == .browsing, let openedGroup { return openedGroup }
        let listed = listed(groups, name: name, isHidden: isHidden, coreMode: coreMode, opening: opening)
        if let global = chooseNodeEntry(opening, candidates: listed.names) { return global }
        if let openedGroup { return openedGroup }
        return globalToOpen(mode: listed.mode, liveCatalog: liveCatalog, candidates: listed.names,
                            readerFoldedAll: readerFoldedAll)
    }

     
     
     
     
     
     
     
     
     
    static func candidates<Group>(
        _ groups: [Group],
        mode: ProxyBrowsingVisibility.Mode,
        opening: ProxyBrowsingVisibility.Opening = .browsing,
        name: (Group) -> String,
        isHidden: (Group) -> Bool
    ) -> [String] {
        ProxyBrowsingVisibility.groups(groups, mode: mode, opening: opening, name: name, isHidden: isHidden).map(name)
    }
}

 
 
 
 
enum HomeProxiesCardPolicy {
     
    struct Count: Equatable {
        let value: Int?
        let unit: String
    }

     
     
     
     
     
    static func notDownloadedProxyProviders(in catalog: ProviderCatalog?,
                                            state: ProviderRefreshState? = nil) -> Int {
        guard let catalog else { return 0 }
        let coreFetched = catalog.coreFetchedProviders ?? []
        return catalog.entries.filter { entry in
            entry.kind == "proxy" && entry.lastUpdatedAt == nil && (entry.count ?? 0) == 0
                && !coreFetched.contains(entry.name)
                && state?.entry(kind: entry.kind, name: entry.name, url: entry.url)?.checkedAt == nil
        }.count
    }

     
     
     
     
     
    static func count(inline: Int?, providerNodes: Int, notDownloadedProviders: Int) -> Count {
        if providerNodes > 0 { return Count(value: (inline ?? 0) + providerNodes, unit: "proxies") }
        if (inline ?? 0) == 0, notDownloadedProviders > 0 {
            return Count(value: notDownloadedProviders,
                         unit: notDownloadedProviders == 1 ? "source (not downloaded yet)" : "sources (not downloaded yet)")
        }
        return Count(value: inline, unit: "proxies")
    }

    static func domainSnapshot(
        mode: Profile.OutboundMode,
        standard: ClashHomeDomainSnapshot,
        globalNode: String?
    ) -> ClashHomeDomainSnapshot {
        guard mode == .global else { return standard }
        return ClashHomeDomainSnapshot(
            count: standard.count,
            countUnit: standard.countUnit,
            breakdown: ProxyBrowsingVisibility.kernelGlobalGroupName,
            names: globalNode.map { [$0] } ?? []
        )
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum HomeNamedRoute {
    struct Route: Equatable {
         
         
         
        var group: String?
        var node: String?
        var delay: Int?

        static let none = Route(group: nil, node: nil, delay: nil)
    }

     
     
     
     
     
     
     
    static func route(mode: Profile.OutboundMode, groups: [ProxyGroup], delays: [String: Int],
                      terminals: [String: String] = [:], groupsAreTheCores: Bool = true,
                      finalRuleTarget: String? = nil) -> Route {
        switch mode {
        case .global:
             
             
            guard let group = groups.first(where: { $0.name == GlobalProxySelectionPolicy.groupName }) else { return .none }
            let end = group.resolvedNow.isEmpty ? group.now : group.resolvedNow
            guard !end.isEmpty else { return .none }
             
             
             
            return Route(group: nil, node: end, delay: NodeInventory.routeDelay(from: group.name, groups: groups, delays: delays))
        case .rule:
            guard groupsAreTheCores,
                  let target = finalRuleTarget?.trimmingCharacters(in: .whitespacesAndNewlines), !target.isEmpty else {
                return .none
            }
            let builtins = ConfigurationLibraryPicks.builtinNames
            if groups.contains(where: { $0.name == target }) {
                 
                 
                guard let end = terminals[target], !groups.contains(where: { $0.name == end }) else { return .none }
                 
                 
                return Route(group: target, node: end,
                             delay: builtins.contains(end) ? nil : NodeInventory.routeDelay(from: target, groups: groups, delays: delays))
            }
             
             
             
            guard !groups.isEmpty, !builtins.contains(target) else { return .none }
            return Route(group: nil, node: target, delay: NodeInventory.memberDelay(target, delays: delays))
        case .direct:
            return .none
        }
    }

     
     
     
     
     
    static func finalRuleTarget(of overview: RulesOverviewModel?) -> String? {
        guard let target = overview?.fallback.first?.target.trimmingCharacters(in: .whitespacesAndNewlines),
              !target.isEmpty else { return nil }
        return target
    }
}

 
 
 
 
 
enum ProxiesPresentedDocument {
    static func make(
        source: String?,
        profile: Profile,
        fallback: String?,
        build: (String, Profile) throws -> String = { try ProfileRuntimeConfigBuilder.buildProduction(raw: $0, profile: $1, scripts: .silent) }
    ) -> String? {
        guard let source else { return fallback }
        return (try? build(source, profile)) ?? fallback
    }

     
     
     
    static func key(projectionKey: String, profile: Profile, scriptBody: String?) -> String {
        var parts = [projectionKey, String(describing: profile.overwriteMode), profile.selectedScriptID ?? "-", String(scriptBody?.hashValue ?? 0)]
         
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        if let encoded = try? encoder.encode(profile) { parts.append(String(encoded.hashValue)) }
        if let runtime = try? encoder.encode(FlClashRuntimeConfig.load()) { parts.append(String(runtime.hashValue)) }
        return parts.joined(separator: "|")
    }
}
