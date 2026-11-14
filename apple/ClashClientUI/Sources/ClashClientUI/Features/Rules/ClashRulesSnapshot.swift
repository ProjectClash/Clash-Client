import Foundation

public struct ClashRuleLineSnapshot:
    Codable,
    Equatable,
    Hashable,
    Identifiable,
    Sendable
{
    public let raw: String
    public let type: String
    public let payload: String
    public let target: String
     
     
     
    public let entryCount: Int?

    public var id: String { raw }

    public init(
        raw: String,
        type: String,
        payload: String,
        target: String,
        entryCount: Int? = nil
    ) {
        self.raw = String(raw.prefix(8_192))
        self.type = String(type.prefix(128))
        self.payload = String(payload.prefix(4_096))
        self.target = String(target.prefix(256))
        self.entryCount = entryCount
    }
}

public struct ClashRuleBucketSnapshot:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    public let target: String
    public let rules: [ClashRuleLineSnapshot]
    public let canOpenProxiesGroup: Bool
     
     
     
    public let ruleCount: Int

    public var id: String { target }

     
     
    public static let pageRowCap = 200

    public init(
        target: String,
        rules: [ClashRuleLineSnapshot],
        canOpenProxiesGroup: Bool = false,
        ruleCount: Int? = nil
    ) {
        self.target = String(target.prefix(256))
        self.rules = rules
        self.canOpenProxiesGroup = canOpenProxiesGroup
        self.ruleCount = max(ruleCount ?? rules.count, rules.count)
    }

    private enum CodingKeys: String, CodingKey { case target, rules, canOpenProxiesGroup, ruleCount }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(target: try container.decode(String.self, forKey: .target),
                  rules: try container.decode([ClashRuleLineSnapshot].self, forKey: .rules),
                  canOpenProxiesGroup: try container.decode(Bool.self, forKey: .canOpenProxiesGroup),
                  ruleCount: try container.decodeIfPresent(Int.self, forKey: .ruleCount))
    }
}

public struct ClashRuleSetSnapshot:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    public let name: String
    public let detail: String
     
     
     
     
    public let blockedReason: String?
     
     
     
     
    public let entryCount: Int?

    public var id: String { name }

    public init(name: String, detail: String, blockedReason: String? = nil, entryCount: Int? = nil) {
        self.entryCount = entryCount
         
         
         
        self.name = name
        self.detail = String(detail.prefix(512))
        self.blockedReason = blockedReason.map { String($0.prefix(512)) }
    }
}

public struct ClashRulesOverviewSnapshot:
    Codable,
    Equatable,
    Sendable
{
    public let inlineCount: Int
    public let inapplicableCount: Int
     
     
     
     
     
     
     
     
    public let platformTitle: String
    public let buckets: [ClashRuleBucketSnapshot]
    public let ruleSets: [ClashRuleSetSnapshot]
    public let fallback: [ClashRuleLineSnapshot]
    public let searchableRules: [ClashRuleLineSnapshot]
    public let jumpableTargets: Set<String>
     
     
     
     
    public let rulesAreCounted: Bool

    public init(
        inlineCount: Int = 0,
        inapplicableCount: Int = 0,
        platformTitle: String = "",
        buckets: [ClashRuleBucketSnapshot] = [],
        ruleSets: [ClashRuleSetSnapshot] = [],
        fallback: [ClashRuleLineSnapshot] = [],
        searchableRules: [ClashRuleLineSnapshot]? = nil,
        jumpableTargets: Set<String> = [],
        rulesAreCounted: Bool = false
    ) {
        self.inlineCount = max(0, inlineCount)
        self.inapplicableCount = max(0, inapplicableCount)
        self.platformTitle = platformTitle
        self.buckets = buckets
        self.ruleSets = ruleSets
        self.fallback = fallback
        self.rulesAreCounted = rulesAreCounted
        self.searchableRules = rulesAreCounted
            ? [] : searchableRules ?? buckets.flatMap(\.rules) + fallback
        self.jumpableTargets = jumpableTargets
    }

    private enum CodingKeys: String, CodingKey {
        case inlineCount, inapplicableCount, platformTitle, buckets, ruleSets, fallback, searchableRules,
             jumpableTargets, rulesAreCounted
    }

     
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            inlineCount: try container.decode(Int.self, forKey: .inlineCount),
            inapplicableCount: try container.decode(Int.self, forKey: .inapplicableCount),
            platformTitle: try container.decode(String.self, forKey: .platformTitle),
            buckets: try container.decode([ClashRuleBucketSnapshot].self, forKey: .buckets),
            ruleSets: try container.decode([ClashRuleSetSnapshot].self, forKey: .ruleSets),
            fallback: try container.decode([ClashRuleLineSnapshot].self, forKey: .fallback),
            searchableRules: try container.decode([ClashRuleLineSnapshot].self, forKey: .searchableRules),
            jumpableTargets: try container.decode(Set<String>.self, forKey: .jumpableTargets),
            rulesAreCounted: try container.decodeIfPresent(Bool.self, forKey: .rulesAreCounted) ?? false
        )
    }

    public static let empty = ClashRulesOverviewSnapshot()

    public func search(_ query: String) -> [ClashRuleLineSnapshot] {
        let normalized = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalized.isEmpty else { return [] }
        return searchableRules.filter {
            $0.raw.localizedCaseInsensitiveContains(normalized)
        }
    }
}

public enum ClashRuleTargetVerdict:
    String,
    Codable,
    Equatable,
    Sendable
{
    case builtin
    case followsFallback
    case known
    case unknown
}

public struct ClashRulePolicySnapshot:
    Codable,
    Equatable,
    Hashable,
    Identifiable,
    Sendable
{
    public let name: String
    public let type: String
     
     
     
     
    public var isHidden: Bool = false

    public var id: String { name }

    public init(name: String, type: String, isHidden: Bool = false) {
         
         
         
        self.name = name
        self.type = String(type.prefix(128))
        self.isHidden = isHidden
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case type
    }
}

public struct ClashRulePolicyOptions:
    Codable,
    Equatable,
    Sendable
{
    public let groups: [ClashRulePolicySnapshot]
    public let proxies: [ClashRulePolicySnapshot]
    public let ruleSets: [String]
     
     
     
    public let subRuleNames: [String]?
     
     
     
     
    public let ruleSetsAreKnown: Bool

    private enum CodingKeys: String, CodingKey { case groups, proxies, ruleSets, subRuleNames, ruleSetsAreKnown }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        groups = try container.decode([ClashRulePolicySnapshot].self, forKey: .groups)
        proxies = try container.decode([ClashRulePolicySnapshot].self, forKey: .proxies)
        ruleSets = try container.decode([String].self, forKey: .ruleSets)
        subRuleNames = try container.decodeIfPresent([String].self, forKey: .subRuleNames)
        ruleSetsAreKnown = try container.decodeIfPresent(Bool.self, forKey: .ruleSetsAreKnown) ?? false
    }

     
    public var pickableGroups: [ClashRulePolicySnapshot] {
        groups.filter { !$0.isHidden }
    }

     
     
     
     
     
     
     
     
     
    public var unofferedKinds: Set<ClashStructuredRule.Action> {
        ruleSetsAreKnown && ruleSets.isEmpty ? [.ruleSet] : []
    }

    public init(
        groups: [ClashRulePolicySnapshot] = [],
        proxies: [ClashRulePolicySnapshot] = [],
        ruleSets: [String] = [],
        subRuleNames: [String]? = nil,
         
         
        ruleSetsAreKnown: Bool = false
    ) {
        self.groups = groups
        self.proxies = proxies
        self.ruleSetsAreKnown = ruleSetsAreKnown
        self.ruleSets = ruleSets.map { String($0.prefix(256)) }
        self.subRuleNames = subRuleNames.map { names in
            names.map { String($0.prefix(256)) }
        }
    }

    public static let empty = ClashRulePolicyOptions()

    public static let builtinPolicies: Set<String> = [
        "DIRECT", "REJECT", "REJECT-DROP", "PASS", "PASS-RULE",
        "COMPATIBLE", "GLOBAL",
    ]

    public func verdict(forTarget target: String) -> ClashRuleTargetVerdict {
        if Self.builtinPolicies.contains(target) {
            return .builtin
        }
        if target == "MATCH" {
            return .followsFallback
        }
        if groups.contains(where: { $0.name == target })
            || proxies.contains(where: { $0.name == target })
        {
            return .known
        }
        return .unknown
    }

     
     
     
     
     
     
     
    public func flagsUnknownTarget(of rule: ClashStructuredRule) -> Bool {
        guard rule.action != .subRule else {
            guard let subRuleNames else { return false }
            return !subRuleNames.contains(rule.target)
        }
        return verdict(forTarget: rule.target) == .unknown
    }

     
     
     
     
     
    public static func value(_ content: String, from old: ClashStructuredRule.Action, to new: ClashStructuredRule.Action,
                             ruleSets: [String]?) -> String {
        guard let ruleSets, old != new else { return content }
        if new == .ruleSet { return ruleSets.contains(content) ? content : "" }
        return old == .ruleSet ? "" : content
    }

     
     
     
    public func ruleSetNotInEffect(_ raw: String) -> ClashDisplayText? {
        guard ruleSetsAreKnown else { return nil }
        return ClashRuleNames(policies: nil, ruleSets: Set(ruleSets), subRules: nil).notInEffect(raw)
    }
}

public struct ClashPersonalRuleSnapshot:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    public let raw: String
    public let isEnabled: Bool
    public let comment: String?

    public var id: String { raw }

    public init(
        raw: String,
        isEnabled: Bool = true,
        comment: String? = nil
    ) {
        self.raw = String(raw.prefix(8_192))
        self.isEnabled = isEnabled
        self.comment = comment.map { String($0.prefix(1_024)) }
    }
}

public struct ClashProfileRulesSnapshot:
    Codable,
    Equatable,
    Sendable
{
    public let profileName: String
    public let rules: [ClashPersonalRuleSnapshot]
    public let prependRules: Bool
    public let policyOptions: ClashRulePolicyOptions
    public let initialRuleBuilderRaw: String?
    public let initialRuleBuilderRoute: ClashRuleBuilderRoute?

     
     
     
     
     
    public static let prependsByDefault = true

    public init(
        profileName: String,
        rules: [ClashPersonalRuleSnapshot] = [],
        prependRules: Bool = ClashProfileRulesSnapshot.prependsByDefault,
        policyOptions: ClashRulePolicyOptions = .empty,
        initialRuleBuilderRaw: String? = nil,
        initialRuleBuilderRoute: ClashRuleBuilderRoute? = nil
    ) {
        self.profileName = String(profileName.prefix(256))
        self.rules = rules
        self.prependRules = prependRules
        self.policyOptions = policyOptions
        self.initialRuleBuilderRaw = initialRuleBuilderRaw.map {
            String($0.prefix(8_192))
        }
        self.initialRuleBuilderRoute = initialRuleBuilderRoute
    }
}

public enum ClashRuleBuilderRoute:
    String,
    Codable,
    Equatable,
    Sendable
{
    case country
    case policy
    case category
}

public enum ClashRuleGeoResource:
    String,
    Codable,
    Equatable,
    Sendable
{
    case geoIP
    case geoSite
}

public struct ClashProfileRulesDraft:
    Codable,
    Equatable,
    Sendable
{
    public var rules: [ClashPersonalRuleSnapshot]
    public var prependRules: Bool

    public init(
        rules: [ClashPersonalRuleSnapshot],
        prependRules: Bool
    ) {
        self.rules = rules
        self.prependRules = prependRules
    }
}

public struct ClashRulesSnapshot:
    Codable,
    Equatable,
    Sendable
{
    public let overview: ClashRulesOverviewSnapshot
    public let editor: ClashProfileRulesSnapshot?
    public let canInspectActiveRules: Bool

    public init(
        overview: ClashRulesOverviewSnapshot = .empty,
        editor: ClashProfileRulesSnapshot? = nil,
        canInspectActiveRules: Bool = false
    ) {
        self.overview = overview
        self.editor = editor
        self.canInspectActiveRules = canInspectActiveRules
    }

    public static let empty = ClashRulesSnapshot()
}

public struct ClashLogicCondition:
    Codable,
    Equatable,
    Sendable
{
    public var action: ClashStructuredRule.Action
    public var content: String
    public var noResolve: Bool
    public var src: Bool

    public init(
        action: ClashStructuredRule.Action,
        content: String,
        noResolve: Bool = false,
        src: Bool = false
    ) {
        self.action = action
        self.content = content
        self.noResolve = noResolve
        self.src = src
    }

    public var raw: String {
        var fields = [action.rawValue, content]
        if action.supportsSrc, src {
            fields.append("src")
        }
        if action.supportsNoResolve, noResolve {
            fields.append("no-resolve")
        }
        return fields.joined(separator: ",")
    }
}

public enum ClashLogicExpressionCodec {
    public static func serialize(
        action: ClashStructuredRule.Action,
        conditions: [ClashLogicCondition]
    ) -> String {
        let inner = conditions.map { "(\($0.raw))" }
            .joined(separator: ",")
        return action == .subRule
            ? "(\(conditions.first?.raw ?? ""))"
            : "(\(inner))"
    }

    public static func parse(
        action: ClashStructuredRule.Action,
        content: String
    ) -> [ClashLogicCondition]? {
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("("), trimmed.hasSuffix(")") else {
            return nil
        }
        let subPayloads: [String]
        if action == .subRule {
            subPayloads = [String(trimmed.dropFirst().dropLast())]
        } else {
            let inner = String(trimmed.dropFirst().dropLast())
            guard let groups = topLevelGroups(inner) else {
                return nil
            }
            subPayloads = groups
        }
        guard !subPayloads.isEmpty else { return nil }
        var conditions: [ClashLogicCondition] = []
        for payload in subPayloads {
            guard let condition = parseCondition(payload) else {
                return nil
            }
            conditions.append(condition)
        }
        if action == .not || action == .subRule,
            conditions.count != 1
        {
            return nil
        }
        return conditions
    }

    public static func summary(
        action: ClashStructuredRule.Action,
        content: String
    ) -> String? {
        parse(action: action, content: content)?
            .map(\.content)
            .joined(separator: " · ")
    }

    private static func topLevelGroups(
        _ inner: String
    ) -> [String]? {
        var groups: [String] = []
        var depth = 0
        var current = ""
        for character in inner {
            switch character {
            case "(":
                depth += 1
                if depth > 1 {
                    current.append(character)
                }
            case ")":
                depth -= 1
                if depth < 0 {
                    return nil
                }
                if depth == 0 {
                    groups.append(current)
                    current = ""
                } else {
                    current.append(character)
                }
            case ",":
                if depth != 0 {
                    current.append(character)
                }
            default:
                if depth == 0 {
                    guard character.isWhitespace else {
                        return nil
                    }
                } else {
                    current.append(character)
                }
            }
        }
        return depth == 0 && !groups.isEmpty ? groups : nil
    }

    private static func parseCondition(
        _ payload: String
    ) -> ClashLogicCondition? {
        let fields = payload.split(
            separator: ",",
            omittingEmptySubsequences: false
        )
        .map { $0.trimmingCharacters(in: .whitespaces) }
        guard fields.count >= 2,
            let head = fields.first,
            let action = ClashStructuredRule.Action(
                rawValue: head.uppercased()
            )
        else {
            return nil
        }
        switch action {
        case .and, .or, .not, .subRule, .match:
            return nil
        case .domainRegex:
            return ClashLogicCondition(
                action: action,
                content: fields.dropFirst().joined(separator: ",")
            )
        default:
            let value = fields[1]
            guard !value.isEmpty else { return nil }
            var noResolve = false
            var src = false
            for parameter in fields.dropFirst(2) {
                switch parameter.lowercased() {
                case "no-resolve":
                    noResolve = true
                case "src":
                    src = true
                default:
                    return nil
                }
            }
            return ClashLogicCondition(
                action: action,
                content: value,
                noResolve: noResolve,
                src: src
            )
        }
    }
}

 
 
 
public enum ClashAppleRuntimeProfile:
    String,
    CaseIterable,
    Codable,
    Equatable,
    Sendable
{
    case iosPacketTunnel
    case macosPacketTunnel
     
     
     
     
     
     
    case tvosPacketTunnel

     
     
     
     
     
     
     
     

     
    public var removedRuleActionNames: Set<String> {
        switch self {
        case .macosPacketTunnel: []
        case .iosPacketTunnel, .tvosPacketTunnel: ["UID"]
        }
    }

     
     
    public var keptNeverMatchRuleActionNames: Set<String> {
        let needInboundOrAuditToken: Set<String> = [
            "IN-USER",
            "SOURCE-APP-SIGNING-ID",
            "SOURCE-APP-TEAM-ID",
        ]
        switch self {
        case .macosPacketTunnel:
            return needInboundOrAuditToken
        case .iosPacketTunnel, .tvosPacketTunnel:
            return needInboundOrAuditToken.union([
                "PROCESS-NAME",
                "PROCESS-PATH",
                "PROCESS-NAME-REGEX",
                "PROCESS-PATH-REGEX",
                "PROCESS-NAME-WILDCARD",
                "PROCESS-PATH-WILDCARD",
            ])
        }
    }

     
     
     
     
    public var unavailableRuleActionNames: Set<String> {
        removedRuleActionNames.union(keptNeverMatchRuleActionNames)
    }

    public var platformTitle: String {
        switch self {
        case .iosPacketTunnel: "iOS"
        case .macosPacketTunnel: "macOS"
        case .tvosPacketTunnel: "tvOS"
        }
    }

    public var unavailableMetadataExplanation: String {
        switch self {
        case .macosPacketTunnel:
            "IN-USER and SOURCE-APP-* rules need inbound authentication or flow audit-token metadata the macOS packet tunnel cannot resolve. PROCESS-* and UID rules are available."
        case .tvosPacketTunnel:
            "On tvOS these rules are kept but match nothing: the owner metadata they test cannot be resolved, so the next rule decides. UID is the exception — it is removed, because a UID rule cannot be built on this platform and keeping it would stop the whole configuration from loading. Use domain, IP, GEOSITE or GEOIP conditions instead."
        case .iosPacketTunnel:
             
             
             
             
             
             
             
             
            "On iOS these rules are kept but match nothing: the owner metadata they test cannot be resolved, so the next rule decides. UID is the exception — it is removed, because a UID rule cannot be built on this platform and keeping it would stop the whole configuration from loading. Use domain, IP, GEOSITE or GEOIP conditions instead."
        }
    }

    public var inlineRuleEditorNotice: String {
        switch self {
        case .macosPacketTunnel:
            "PROCESS-* and UID rules run on macOS. IN-USER and SOURCE-APP-* rules are stripped at activation with a per-rule notice."
        case .tvosPacketTunnel:
            "On tvOS, process-, inbound-user- and source-app-based rules run but match nothing, because the owner metadata they test cannot be resolved; UID rules are removed at activation. The editor lets you write them and marks them, so the same profile can carry them for a Mac."
        case .iosPacketTunnel:
            "On iOS, process-, inbound-user- and source-app-based rules run but match nothing, because the owner metadata they test cannot be resolved; UID rules are removed at activation. The editor lets you write them and marks them, so the same profile can carry them for a Mac."
        }
    }
}

public struct ClashStructuredRule:
    Codable,
    Equatable,
    Sendable
{
    public enum Category:
        String,
        CaseIterable,
        Codable,
        Identifiable,
        Sendable
    {
        case domain
        case address
        case connection
        case resources
        case logic
        case advanced

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .domain: "Domain"
            case .address: "Address"
            case .connection: "Connection"
            case .resources: "Resources"
            case .logic: "Logic"
            case .advanced: "Advanced metadata"
            }
        }
    }

    public enum Action:
        String,
        CaseIterable,
        Codable,
        Identifiable,
        Sendable
    {
        case domain = "DOMAIN"
        case domainSuffix = "DOMAIN-SUFFIX"
        case domainKeyword = "DOMAIN-KEYWORD"
        case domainRegex = "DOMAIN-REGEX"
        case domainWildcard = "DOMAIN-WILDCARD"
        case geosite = "GEOSITE"
        case geoip = "GEOIP"
        case srcGeoIP = "SRC-GEOIP"
        case ipASN = "IP-ASN"
        case srcIPASN = "SRC-IP-ASN"
        case ipCIDR = "IP-CIDR"
        case ipCIDR6 = "IP-CIDR6"
        case srcIPCIDR = "SRC-IP-CIDR"
        case ipSuffix = "IP-SUFFIX"
        case srcIPSuffix = "SRC-IP-SUFFIX"
        case srcPort = "SRC-PORT"
        case dstPort = "DST-PORT"
        case inPort = "IN-PORT"
        case dscp = "DSCP"
        case processName = "PROCESS-NAME"
        case processPath = "PROCESS-PATH"
        case processNameRegex = "PROCESS-NAME-REGEX"
        case processPathRegex = "PROCESS-PATH-REGEX"
        case processNameWildcard = "PROCESS-NAME-WILDCARD"
        case processPathWildcard = "PROCESS-PATH-WILDCARD"
        case uid = "UID"
        case sourceAppSigningID = "SOURCE-APP-SIGNING-ID"
        case sourceAppTeamID = "SOURCE-APP-TEAM-ID"
        case network = "NETWORK"
         
         
        case trafficProtocol = "PROTOCOL"
         
        case subnet = "SUBNET"
         
        case cellularRadio = "CELLULAR-RADIO"
        case inType = "IN-TYPE"
        case inName = "IN-NAME"
        case inUser = "IN-USER"
        case rematchName = "REMATCH-NAME"
        case subRule = "SUB-RULE"
        case and = "AND"
        case or = "OR"
        case not = "NOT"
        case ruleSet = "RULE-SET"
        case match = "MATCH"

        public var id: String { rawValue }

        public var category: Category {
            switch self {
            case .domain, .domainSuffix, .domainKeyword,
                .domainRegex, .domainWildcard, .geosite:
                .domain
            case .geoip, .srcGeoIP, .ipASN, .srcIPASN,
                .ipCIDR, .ipCIDR6, .srcIPCIDR, .ipSuffix,
                .srcIPSuffix:
                .address
            case .srcPort, .dstPort, .inPort, .dscp, .network,
                .trafficProtocol, .subnet, .cellularRadio:
                .connection
            case .ruleSet:
                .resources
            case .subRule, .and, .or, .not, .match:
                .logic
            case .processName, .processPath, .processNameRegex,
                .processPathRegex, .processNameWildcard,
                .processPathWildcard, .uid, .sourceAppSigningID,
                .sourceAppTeamID, .inType, .inName, .inUser,
                .rematchName:
                .advanced
            }
        }

        public var title: String {
            switch self {
            case .domain: "Exact domain"
            case .domainSuffix: "Domain suffix"
            case .domainKeyword: "Domain keyword"
            case .domainRegex: "Domain regular expression"
            case .domainWildcard: "Domain wildcard"
            case .geosite: "GeoSite category"
            case .geoip: "Destination country or region"
            case .srcGeoIP: "Source country or region"
            case .ipASN: "Destination network ASN"
            case .srcIPASN: "Source network ASN"
            case .ipCIDR: "Destination IPv4 network"
            case .ipCIDR6: "Destination IPv6 network"
            case .srcIPCIDR: "Source IP network"
            case .ipSuffix: "Destination IP suffix"
            case .srcIPSuffix: "Source IP suffix"
            case .srcPort: "Source port"
            case .dstPort: "Destination port"
            case .inPort: "Inbound port"
            case .dscp: "DSCP value"
            case .processName: "Process name"
            case .processPath: "Process path"
            case .processNameRegex: "Process name regular expression"
            case .processPathRegex: "Process path regular expression"
            case .processNameWildcard: "Process name wildcard"
            case .processPathWildcard: "Process path wildcard"
            case .uid: "Process user ID"
            case .sourceAppSigningID: "Source app signing ID"
            case .sourceAppTeamID: "Source app team ID"
            case .network: "Transport protocol"
            case .trafficProtocol: "Traffic type"
            case .subnet: "Current network"
            case .cellularRadio: "Cellular network type"
            case .inType: "Inbound type"
            case .inName: "Inbound name"
            case .inUser: "Inbound user"
            case .rematchName: "Rematch name"
            case .subRule: "Sub-rule branch"
            case .and: "All conditions"
            case .or: "Any condition"
            case .not: "Not condition"
            case .ruleSet: "Rule-set provider"
            case .match: "All remaining traffic"
            }
        }

        public var summary: String {
            switch self {
            case .domain:
                "Matches when the request domain equals this value exactly."
            case .domainSuffix:
                "Matches the domain itself and any of its subdomains."
            case .domainKeyword:
                "Matches when the request domain contains this text."
            case .domainRegex:
                "Matches the request domain against a regular expression."
            case .domainWildcard:
                "Matches the request domain against a wildcard pattern (* and ?)."
            case .geosite:
                "Matches domains listed in this built-in GeoSite category."
            case .geoip:
                "Matches the destination address's GeoIP country or region."
            case .srcGeoIP:
                "Matches the source address's GeoIP country or region."
            case .ipASN:
                "Matches the destination address's autonomous system number."
            case .srcIPASN:
                "Matches the source address's autonomous system number."
            case .ipCIDR:
                "Matches destination IPv4 addresses inside this network."
            case .ipCIDR6:
                "Matches destination IPv6 addresses inside this network."
            case .srcIPCIDR:
                "Matches source addresses inside this network."
            case .ipSuffix:
                "Matches the trailing bits of the destination address."
            case .srcIPSuffix:
                "Matches the trailing bits of the source address."
            case .srcPort:
                "Matches the connection's source port."
            case .dstPort:
                "Matches the connection's destination port."
            case .inPort:
                "Matches the listener port that accepted the connection."
            case .dscp:
                "Matches the packet's DSCP marking."
            case .processName:
                "Matches the executable name the core resolves from the socket owner."
            case .processPath:
                "Matches the executable path the core resolves from the socket owner."
            case .processNameRegex:
                "Matches the resolved executable name against a regular expression."
            case .processPathRegex:
                "Matches the resolved executable path against a regular expression."
            case .processNameWildcard:
                "Matches the resolved executable name against a wildcard pattern."
            case .processPathWildcard:
                "Matches the resolved executable path against a wildcard pattern."
            case .uid:
                "Matches the numeric user ID the core resolves from the socket owner."
            case .sourceAppSigningID:
                "Matches the code-signing identifier of the app that opened the connection."
            case .sourceAppTeamID:
                "Matches the developer team ID of the app that opened the connection."
            case .network:
                "Matches the transport protocol, tcp or udp."
            case .trafficProtocol:
                "Matches the kind of traffic the connection carries, such as HTTP, HTTPS, QUIC or STUN."
            case .subnet:
                "Matches the network the device is on, by its type or its router's address."
            case .cellularRadio:
                "Matches the cellular network type the device is on, such as LTE or NR."
            case .inType:
                "Matches the inbound type that accepted the connection."
            case .inName:
                "Matches the inbound name that accepted the connection."
            case .inUser:
                "Matches the user name the inbound authenticated for this connection."
            case .rematchName:
                "Matches the rematch lane this connection was re-evaluated under."
            case .subRule:
                "Branches into the named sub-rule list when the condition matches."
            case .and:
                "Matches only when every listed condition matches."
            case .or:
                "Matches when any one of the listed conditions matches."
            case .not:
                "Matches when the wrapped condition does not match."
            case .ruleSet:
                "Matches entries supplied by the named rule provider."
            case .match:
                "Matches every request not matched by the rules above."
            }
        }

        public var iOSInertNote: String? {
            self == .dscp
                ? "Unreliable on iOS — the packet tunnel never sets DSCP, so every flow reads as 0: DSCP,0 matches all traffic and any other value never matches."
                : nil
        }

        public var needsContent: Bool { self != .match }

        public var payloadConsumesRemainingFields: Bool {
            switch self {
            case .domainRegex, .processNameRegex, .processPathRegex,
                .subRule, .and, .or, .not:
                true
            default:
                false
            }
        }

        public var supportsNoResolve: Bool {
            switch self {
            case .geoip, .ipCIDR, .ipCIDR6, .ipASN,
                .ipSuffix, .ruleSet:
                true
            default:
                false
            }
        }

        public var supportsSrc: Bool {
            switch self {
            case .geoip, .ipCIDR, .ipCIDR6, .ipASN,
                .ipSuffix, .ruleSet:
                true
            default:
                false
            }
        }

        public var contentLabel: String {
            switch self {
            case .ruleSet: "Rule-set name"
            case .subRule, .and, .or, .not: "Condition expression"
            case .network: "Protocol"
            case .inType: "Inbound kind"
            case .inName: "Inbound name"
            case .inUser: "Inbound user"
            case .rematchName: "Rematch name"
            default: "Match value"
            }
        }

        public var contentPlaceholder: String {
            switch self {
            case .geoip, .srcGeoIP: "CN"
            case .geosite: "gfw"
            case .ipCIDR, .srcIPCIDR: "10.0.0.0/8"
            case .ipCIDR6: "2620:0:2d0::/48"
            case .ipASN, .srcIPASN: "13335"
            case .ipSuffix, .srcIPSuffix: "1.1"
            case .dstPort, .srcPort, .inPort: "443 or 8000-9000"
            case .dscp: "0-63"
            case .processName: "curl"
            case .processPath: "/usr/bin/curl"
            case .processNameRegex: "^curl$"
            case .processPathRegex: "^/usr/bin/.*"
            case .processNameWildcard: "curl*"
            case .processPathWildcard: "/usr/bin/*"
            case .uid: "501"
            case .sourceAppSigningID: "com.example.app"
            case .sourceAppTeamID: "ABCDE12345"
            case .network: "TCP or UDP"
            case .trafficProtocol: "HTTPS"
            case .subnet: "TYPE:WIFI"
            case .cellularRadio: "LTE"
            case .ruleSet: "provider name"
            case .subRule: "(OR,((NETWORK,TCP),(NETWORK,UDP)))"
            case .and: "((DOMAIN,a.example),(NETWORK,TCP))"
            case .or: "((DOMAIN,a.example),(DOMAIN,b.example))"
            case .not: "(DOMAIN,blocked.example)"
            case .domainRegex: "^api[0-9]+\\.example\\.com$"
            case .domainWildcard: "test.*.example.com"
            case .inType: "TUN"
            case .inName: "clash-tun"
            case .inUser: "alice"
            case .rematchName: "lane-a/lane-b"
            default: "example.com"
            }
        }

        public var targetLabel: String {
            self == .subRule ? "Sub-rule list" : "Route"
        }

        public var hasLimitedIOSMeaning: Bool {
            switch self {
            case .inType, .inName, .rematchName:
                true
            default:
                false
            }
        }
    }

    public static let allCoreActionNames: Set<String> = [
        "DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "DOMAIN-REGEX",
        "DOMAIN-WILDCARD", "GEOSITE", "GEOIP", "SRC-GEOIP",
        "IP-ASN", "SRC-IP-ASN", "IP-CIDR", "IP-CIDR6",
        "SRC-IP-CIDR", "IP-SUFFIX", "SRC-IP-SUFFIX", "SRC-PORT",
        "DST-PORT", "IN-PORT", "DSCP", "PROCESS-NAME",
        "PROCESS-PATH", "PROCESS-NAME-REGEX", "PROCESS-PATH-REGEX",
        "PROCESS-NAME-WILDCARD", "PROCESS-PATH-WILDCARD",
        "NETWORK", "PROTOCOL", "SUBNET", "CELLULAR-RADIO",
        "UID", "IN-TYPE", "IN-USER", "IN-NAME",
        "REMATCH-NAME", "SUB-RULE", "AND", "OR", "NOT", "RULE-SET",
        "MATCH", "SOURCE-APP-SIGNING-ID", "SOURCE-APP-TEAM-ID",
    ]

    @available(*, deprecated)
    public static let unavailableOnIOSActionNames =
        ClashAppleRuntimeProfile.iosPacketTunnel
            .unavailableRuleActionNames

     
     
     
     
     
     
     
     
     
     
    public static func availableActions(
        for runtimeProfile: ClashAppleRuntimeProfile
    ) -> [Action] {
        Action.allCases.filter { !notOfferedActions.contains($0) }
    }

     
     
     
     
     
     
     
    public static let notOfferedActions: Set<Action> = [.cellularRadio]

     
     
     
     
    public static func platformNote(
        for actionName: String,
        runtimeProfile: ClashAppleRuntimeProfile
    ) -> ClashDisplayText? {
        let name = actionName.uppercased()
        if runtimeProfile.removedRuleActionNames.contains(name) {
            return .format("%@ rules cannot be built in Clash's %@ packet tunnel and are removed at activation; the rule stays in the profile for other platforms.", [name, runtimeProfile.platformTitle])
        }
        if runtimeProfile.keptNeverMatchRuleActionNames.contains(name) {
            return .format("%@ rules are kept but never match in Clash's %@ packet tunnel: the owner metadata they test cannot be resolved here, so the next rule decides.", [name, runtimeProfile.platformTitle])
        }
        return nil
    }

     
     
    public static func platformNote(
        _ rule: String,
        runtimeProfile: ClashAppleRuntimeProfile
    ) -> ClashDisplayText? {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        if let head = trimmed.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           let note = platformNote(for: head, runtimeProfile: runtimeProfile) {
            return note
        }
        let pattern = runtimeProfile.unavailableRuleActionNames
            .map(NSRegularExpression.escapedPattern).sorted().joined(separator: "|")
        guard !pattern.isEmpty,
              let range = trimmed.range(
                  of: #"(?:^|\()\s*("# + pattern + #")\s*,"#,
                  options: [.regularExpression, .caseInsensitive]
              )
        else { return nil }
        let nested = String(trimmed[range]).trimmingCharacters(in: CharacterSet(charactersIn: "(, \t"))
        return platformNote(for: nested, runtimeProfile: runtimeProfile)
    }

    public var action: Action
    public var content: String
    public var target: String
    public var noResolve: Bool
    public var src: Bool
    public var additionalParams: [String]

    public init(
        action: Action,
        content: String,
        target: String,
        noResolve: Bool = false,
        src: Bool = false,
        additionalParams: [String] = []
    ) {
        self.action = action
        self.content = content
        self.target = target
        self.noResolve = noResolve
        self.src = src
        self.additionalParams = additionalParams
    }

    public var rawValue: String {
        var fields = [action.rawValue]
        if action.needsContent {
            fields.append(content)
        }
        fields.append(target)
        if action.supportsSrc, src {
            fields.append("src")
        }
        if action.supportsNoResolve, noResolve {
            fields.append("no-resolve")
        }
        fields.append(contentsOf: additionalParams)
        return fields.joined(separator: ",")
    }

     
     
     
     
     
     
     
     
     
     
     
    public static func builderWritesBack(_ raw: String, hasTarget: Bool = true) -> Bool {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = hasTarget ? parse(line) : parsePayload(line), parsed.additionalParams.isEmpty else { return false }
        if !hasTarget, refusedInARuleSet.contains(parsed.action) { return false }
        var content = parsed.content
        if [.and, .or, .not, .subRule].contains(parsed.action) {
            guard let conditions = ClashLogicExpressionCodec.parse(action: parsed.action, content: parsed.content),
                  !conditions.isEmpty else { return false }
            content = ClashLogicExpressionCodec.serialize(action: parsed.action, conditions: conditions)
        }
        let rebuilt = ClashStructuredRule(action: parsed.action, content: content, target: parsed.target,
                                         noResolve: parsed.noResolve, src: parsed.src,
                                         additionalParams: parsed.additionalParams)
        return (hasTarget ? rebuilt.rawValue : rebuilt.payloadValue) == line
    }

     
     
     
     
     
     
    public static func parsePayload(_ raw: String) -> ClashStructuredRule? {
        let fields = raw.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let head = fields.first, let action = Action(rawValue: head.uppercased()), action != .match,
              fields.count >= 2, !fields[1].isEmpty else { return nil }
        if action.payloadConsumesRemainingFields {
            return ClashStructuredRule(action: action, content: fields.dropFirst().joined(separator: ","), target: "")
        }
        let options = readOptions(Array(fields.dropFirst(2)).filter { !$0.isEmpty }, for: action)
        return ClashStructuredRule(action: action, content: fields[1], target: "", noResolve: options.noResolve,
                                  src: options.src, additionalParams: options.rest)
    }

     
     
     
     
     
     
    static func readOptions(_ parameters: [String], for action: Action) -> (src: Bool, noResolve: Bool, rest: [String]) {
        let src = action.supportsSrc && parameters.contains(srcOption)
        let noResolve = action.supportsNoResolve && parameters.contains(noResolveOption)
        let rest = parameters.filter {
            !(action.supportsSrc && $0 == srcOption) && !(action.supportsNoResolve && $0 == noResolveOption)
        }
        return (src, noResolve, rest)
    }

     
     
     
     
    public static let headsWhosePayloadConsumesRemainingFields: Set<String> = Set(
        Action.allCases.filter(\.payloadConsumesRemainingFields).map(\.rawValue)
    )

     
     
     
     
     
     
     
     
     
    public static func coreTargetIndex(head: String, fieldCount: Int) -> Int? {
        let kind = head.trimmingCharacters(in: .whitespaces).uppercased()
        if kind == Action.match.rawValue { return fieldCount > 1 ? 1 : nil }
        if headsWhosePayloadConsumesRemainingFields.contains(kind) { return fieldCount > 1 ? fieldCount - 1 : nil }
        return fieldCount > 2 ? 2 : nil
    }

     
    public static let srcOption = "src"
    public static let noResolveOption = "no-resolve"

     
     
     
    public static let refusedInARuleSet: Set<Action> = [.match, .ruleSet, .subRule]

     
     
    public var payloadValue: String {
        var fields = [action.rawValue]
        if action.needsContent { fields.append(content) }
        if action.supportsSrc, src { fields.append("src") }
        if action.supportsNoResolve, noResolve { fields.append("no-resolve") }
        fields.append(contentsOf: additionalParams)
        return fields.joined(separator: ",")
    }

    public static func parse(_ raw: String) -> ClashStructuredRule? {
        let fields = raw.split(
            separator: ",",
            omittingEmptySubsequences: false
        )
        .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let head = fields.first,
            let action = Action(rawValue: head.uppercased())
        else {
            return nil
        }

        if action == .match {
             
             
             
             
             
             
            guard fields.count >= 2, !fields[1].isEmpty else {
                return nil
            }
            return ClashStructuredRule(
                action: action,
                content: "",
                target: fields[1],
                additionalParams: Array(fields.dropFirst(2))
            )
        }

        if action.payloadConsumesRemainingFields {
            guard fields.count >= 3,
                let target = fields.last,
                !target.isEmpty
            else {
                return nil
            }
            let content = fields[1..<(fields.count - 1)]
                .joined(separator: ",")
            guard !content.isEmpty else { return nil }
            return ClashStructuredRule(
                action: action,
                content: content,
                target: target
            )
        }

        guard fields.count >= 3,
            !fields[1].isEmpty,
            !fields[2].isEmpty
        else {
            return nil
        }
         
         
        let options = readOptions(
            Array(fields.dropFirst(3)).filter { !$0.isEmpty },
            for: action
        )
        return ClashStructuredRule(
            action: action,
            content: fields[1],
            target: fields[2],
            noResolve: options.noResolve,
            src: options.src,
            additionalParams: options.rest
        )
    }

     
     
     
     
     
    public static func ruleSetNames(in raw: String) -> [String] {
        guard let parsed = parse(raw) else { return [] }
        if parsed.action == .ruleSet { return [parsed.content] }
        guard [.and, .or, .not, .subRule].contains(parsed.action) else { return [] }
        let content = parsed.content as NSString
        return nestedRuleSet.matches(in: parsed.content, range: NSRange(location: 0, length: content.length)).map {
            content.substring(with: $0.range(at: 1)).trimmingCharacters(in: .whitespaces)
        }
    }

     
     
     
    private static let nestedRuleSet = try! NSRegularExpression(
        pattern: #"\(\s*RULE-SET\s*,\s*([^,()]+)"#, options: [.caseInsensitive])

    public static func disallowReason(
        _ rule: String,
        runtimeProfile: ClashAppleRuntimeProfile
    ) -> String? {
        let trimmed = rule.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else {
            return "The rule is empty."
        }
         
         
        guard let parsed = parse(trimmed) else {
            return "This is not a rule head Clash recognizes."
        }
        if let reason = payloadDisallowReason(
            action: parsed.action,
            content: parsed.content
        ) {
            return reason
        }
        return nil
    }

     
     
     
     
    public static func rawDisallowReason(
        _ rule: String,
        runtimeProfile: ClashAppleRuntimeProfile
    ) -> String? {
        let trimmed = rule.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else {
            return "The rule is empty."
        }
        guard let parsed = parse(trimmed) else {
            return nil
        }
        return payloadDisallowReason(
            action: parsed.action,
            content: parsed.content
        )
    }

    private static func payloadDisallowReason(
        action: Action,
        content: String
    ) -> String? {
        switch action {
        case .srcPort, .dstPort, .inPort:
            return unsignedRangeDisallowReason(
                content,
                actionName: action.rawValue,
                maximum: UInt64(UInt16.max),
                permitsWildcard: false
            )
        case .dscp:
            return unsignedRangeDisallowReason(
                content,
                actionName: action.rawValue,
                maximum: 63,
                permitsWildcard: true
            )
        case .uid:
            return unsignedRangeDisallowReason(
                content,
                actionName: action.rawValue,
                maximum: UInt64(UInt32.max),
                permitsWildcard: false
            )
        case .and, .or, .not, .subRule:
            guard let conditions = ClashLogicExpressionCodec.parse(
                action: action,
                content: content
            ) else {
                return nil
            }
            for condition in conditions {
                if let reason = payloadDisallowReason(
                    action: condition.action,
                    content: condition.content
                ) {
                    return reason
                }
            }
            return nil
        default:
            return nil
        }
    }

     
     
     
     
     
    private static func unsignedRangeDisallowReason(
        _ content: String,
        actionName: String,
        maximum: UInt64,
        permitsWildcard: Bool
    ) -> String? {
        let trimmed = content.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if permitsWildcard, trimmed == "*" {
            return nil
        }
        guard !trimmed.isEmpty, trimmed != "*" else {
            return rangeExplanation(
                actionName: actionName,
                maximum: maximum
            )
        }

        let terms = trimmed
            .replacingOccurrences(of: ",", with: "/")
            .split(separator: "/", omittingEmptySubsequences: false)
        guard terms.count <= 28 else {
            return "\(actionName) supports at most 28 values or ranges."
        }

        var foundValue = false
        for term in terms {
            if term.isEmpty {
                continue
            }
            foundValue = true
            let bounds = term.split(
                separator: "-",
                omittingEmptySubsequences: false
            )
            guard bounds.count == 1 || bounds.count == 2 else {
                return rangeExplanation(
                    actionName: actionName,
                    maximum: maximum
                )
            }
            for bound in bounds {
                let valueText = bound.trimmingCharacters(
                    in: CharacterSet(charactersIn: "[] ")
                )
                guard !valueText.isEmpty,
                    let value = UInt64(valueText),
                    value <= maximum
                else {
                    return rangeExplanation(
                        actionName: actionName,
                        maximum: maximum
                    )
                }
            }
        }
        return foundValue
            ? nil
            : rangeExplanation(
                actionName: actionName,
                maximum: maximum
            )
    }

    private static func rangeExplanation(
        actionName: String,
        maximum: UInt64
    ) -> String {
        "\(actionName) must use values from 0 through \(maximum), with ranges such as 8000-9000."
    }
}

 
 
 
 
public enum ClashModuleRuleSetNames {
    public static let lan = "module-builtin-lan"
    public static let system = "module-builtin-system"

    public static func isReserved(_ name: String) -> Bool {
        if name == lan || name == system { return true }
        let parts = name.split(separator: "-", omittingEmptySubsequences: false)
        return parts.count == 3 && parts[0] == "module" && parts[2].count == 8 && parts[2].allSatisfy(\.isHexDigit)
            && (parts[1] == "ruleset" || parts[1] == "engine"
                || (parts[1].count == 8 && parts[1].allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }))
    }
}

 
 
 
 
 
 
 
public struct ClashRuleNames: Equatable, Sendable {
     
    public enum Missing: Equatable, Sendable {
        case policy(String), ruleSet(String), subRule(String)
    }

     
     
    public var policies: Set<String>?
    public var ruleSets: Set<String>?
    public var subRules: Set<String>?

    public init(policies: Set<String>?, ruleSets: Set<String>?, subRules: Set<String>?) {
        self.policies = policies
        self.ruleSets = ruleSets
        self.subRules = subRules
    }

     
     
     
     
     
    public func missing(in rule: String) -> Missing? {
        guard let parsed = ClashStructuredRule.parse(rule) else { return nil }
        if let name = missingRuleSets(in: rule).first { return .ruleSet(name) }
        let target = parsed.target
        if !target.isEmpty, policies?.contains(target) != true {
            if parsed.action != .subRule {
                if policies != nil { return .policy(target) }
            } else if let subRules, !subRules.contains(target) {
                 
                 
                if policies != nil { return .subRule(target) }
            }
        }
        return nil
    }

    public func leavesOut(_ rule: String) -> Bool { missing(in: rule) != nil }

     
     
     
    public func missingRuleSets(in rule: String) -> [String] {
        guard let ruleSets else { return [] }
        return ClashStructuredRule.ruleSetNames(in: rule).filter {
            !ruleSets.contains($0) && !ClashModuleRuleSetNames.isReserved($0)
        }
    }

     
     
     
    public func notInEffect(_ rule: String) -> ClashDisplayText? {
        guard case .ruleSet(let name)? = missing(in: rule) else { return nil }
        return .format("Not in effect: this configuration has no rule set named %@.", [name])
    }
}

 
 
 
 
 
 
 
 
 
public enum ClashRuleSetSniff {
    public struct Found: Equatable, Sendable {
         
        public let format: String
         
         
         
        public let behavior: String?

        public init(format: String, behavior: String?) {
            self.format = format
            self.behavior = behavior
        }

         
        public var fileSuffix: String { format == "text" ? "txt" : format }
    }

     
     
    static let readsAtMost = 4 * 1_048_576

     
     
    public static func name(typed label: String, fileName: String) -> String {
        let typed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? (fileName as NSString).deletingPathExtension : typed
    }

     
     
     
    public static func fileName(_ fileName: String, found: Found) -> String {
        fileName.isEmpty ? "rule-set-" + UUID().uuidString.prefix(8).lowercased() + "." + found.fileSuffix : fileName
    }

     
    public static func linkStem(_ link: String) -> String {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)) else { return "" }
        let stem = url.deletingPathExtension().lastPathComponent
        return stem == "/" ? "" : stem
    }

    public static func ruleSet(in data: Data) -> Found? {
         
        if data.starts(with: [0x28, 0xB5, 0x2F, 0xFD]) { return Found(format: "mrs", behavior: nil) }
        var text = String(decoding: data.prefix(readsAtMost), as: UTF8.self)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
         
        let lines = Lines(text: text[...], dropsLast: data.count > readsAtMost)
        switch yamlPayload(lines) {
        case .notYAML:
            return textBehavior(lines).map { Found(format: "text", behavior: $0) }
        case .otherKeys:
            return nil
        case .entries(let entries):
             
             
             
             
            guard !entries.isEmpty else { return nil }
             
            if entries.contains(where: carriesAPolicy) { return nil }
            if entries.contains(where: isClassical) { return Found(format: "yaml", behavior: "classical") }
            return Found(format: "yaml", behavior: entries.allSatisfy(isAddressRange) ? "ipcidr" : "domain")
        }
    }

    private enum YAMLReading { case notYAML, otherKeys, entries([String]) }

     
     
    private struct Lines: Sequence, IteratorProtocol {
        let text: Substring
        var index: Substring.Index
        let dropsLast: Bool

        init(text: Substring, dropsLast: Bool) {
            self.text = text
            self.index = text.startIndex
            self.dropsLast = dropsLast
        }

        mutating func next() -> Substring? {
            while index < text.endIndex {
                let end = text[index...].firstIndex(where: \.isNewline) ?? text.endIndex
                if end == text.endIndex, dropsLast { index = end; return nil }
                let line = text[index..<end]
                index = end == text.endIndex ? end : text.index(after: end)
                if !line.isEmpty { return line }
            }
            return nil
        }
    }

     
     
     
    private static func yamlPayload(_ lines: Lines) -> YAMLReading {
        var sawPayload = false
        var entries: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed == "---" { continue }
            if let first = line.first, first != " ", first != "\t", first != "-" {
                 
                 
                 
                guard let key = yamlKey(line) else { return sawPayload ? .otherKeys : .notYAML }
                guard key == "payload", !sawPayload else { return .otherKeys }
                sawPayload = true
                 
                if let open = line.firstIndex(of: "["), let close = line.lastIndex(of: "]"), open < close {
                    entries += flowItems(line[line.index(after: open)..<close])
                }
                continue
            }
            guard sawPayload, trimmed.hasPrefix("-") else { continue }
            let entry = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
            entries.append(entry.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")))
        }
        return sawPayload ? .entries(entries) : .notYAML
    }

     
     
     
     
     
    static func flowItems(_ list: Substring) -> [String] {
        var items: [String] = []
        var current = ""
        var quote: Character?
        var characters = list.makeIterator()
        var pending: Character? = nil
        while let character = pending ?? characters.next() {
            pending = nil
            if let open = quote {
                if open == "\"", character == "\\", let escaped = characters.next() {
                    current.append(escaped)
                    continue
                }
                guard character == open else { current.append(character); continue }
                if open == "'", let next = characters.next() {
                    if next == "'" { current.append("'"); continue }
                    pending = next
                }
                quote = nil
            } else if (character == "'" || character == "\""),
                      current.allSatisfy(\.isWhitespace) {
                current = ""
                quote = character
            } else if character == "," {
                items.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        items.append(current)
        return items.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static let keyLine = try! NSRegularExpression(pattern: #"^["']?([A-Za-z_][A-Za-z0-9_-]*)["']?\s*:(\s|$)"#)

    private static func yamlKey(_ line: Substring) -> String? {
        let text = String(line)
        guard let match = keyLine.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

     
     
     
    private static func textBehavior(_ lines: Lines) -> String? {
        var kind: String?
         
         
        var dotted = false
        for line in lines {
            let entry = line.trimmingCharacters(in: .whitespaces)
            if entry.isEmpty || entry.hasPrefix("#") || entry.hasPrefix("//") { continue }
            let this: String
            if isClassical(entry) { this = "classical" }
            else if isAddressRange(entry) { this = "ipcidr" }
            else if isTextDomain(entry) { this = "domain"; dotted = dotted || entry.contains(".") }
            else { return nil }
            if kind == nil { kind = this } else if kind != this { return nil }
        }
        return kind == "domain" && !dotted ? nil : kind
    }

     
     
     
     
     
    private static func isClassical(_ entry: String) -> Bool {
        guard let parsed = ClashStructuredRule.parsePayload(entry) else { return isUnknownRuleLine(entry) }
        if [.and, .or, .not, .subRule].contains(parsed.action) { return parsed.content.hasSuffix(")") }
        return parsed.additionalParams.isEmpty
    }

     
     
    private static func isUnknownRuleLine(_ entry: String) -> Bool {
        unknownRuleLine.firstMatch(in: entry, range: NSRange(entry.startIndex..., in: entry)) != nil
    }

    private static let unknownRuleLine = try! NSRegularExpression(pattern: #"^[A-Z][A-Z0-9]*(-[A-Z0-9]+)*,[^,]+$"#)

     
     
    private static func carriesAPolicy(_ entry: String) -> Bool {
        ClashStructuredRule.parsePayload(entry) != nil && !isClassical(entry)
    }

    private static let addressRange = try! NSRegularExpression(
        pattern: #"^(\d{1,3}(\.\d{1,3}){3}|[0-9A-Fa-f]*:[0-9A-Fa-f:.]+)(/\d{1,3})?$"#)
     
     
     
    private static let textDomain = try! NSRegularExpression(
        pattern: #"^(\+\.|\*\.|\.)?[^\s.,:/]+(\.[^\s.,:/]+)*\.?$"#)

    private static func isAddressRange(_ entry: String) -> Bool {
        addressRange.firstMatch(in: entry, range: NSRange(entry.startIndex..., in: entry)) != nil
    }

    private static func isTextDomain(_ entry: String) -> Bool {
        textDomain.firstMatch(in: entry, range: NSRange(entry.startIndex..., in: entry)) != nil
    }
}

extension ClashRulesOverviewSnapshot {
     
     
     
     
     
     
     
     
     
     
     
    var hasRulesGroup: Bool {
        !buckets.isEmpty || inlineCount > fallback.count
    }
}
