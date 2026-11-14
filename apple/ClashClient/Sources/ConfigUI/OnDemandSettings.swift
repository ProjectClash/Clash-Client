import ClashClientUI
import Foundation
import Network
import NetworkExtension

enum OnDemandRuleAction: String, Codable, CaseIterable, Identifiable {
    case connect
    case disconnect
    case ignore
    case evaluate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .connect: return "Connect"
        case .disconnect: return "Disconnect"
        case .ignore: return "Ignore"
        case .evaluate: return "Evaluate Connection"
        }
    }
}

enum OnDemandInterface: String, Codable, CaseIterable, Identifiable {
    case any
    case wifi
    case cellular

    var id: String { rawValue }

    static var platformCases: [Self] {
#if os(macOS)
        [.any, .wifi]
#else
        allCases
#endif
    }

    var title: String {
        switch self {
         
         
        case .any: return "Any network"
        case .wifi: return "Wi-Fi"
        case .cellular: return "Cellular"
        }
    }

    var nativeValue: NEOnDemandRuleInterfaceType {
        switch self {
        case .any: return .any
        case .wifi: return .wiFi
        case .cellular:
#if os(macOS)
             
             
            return .any
#else
            return .cellular
#endif
        }
    }
}

enum OnDemandEvaluateAction: String, Codable, CaseIterable, Identifiable {
    case connectIfNeeded
    case neverConnect

    var id: String { rawValue }

    var title: String {
        switch self {
        case .connectIfNeeded: return "Connect If Needed"
        case .neverConnect: return "Never Connect"
        }
    }

    var nativeValue: NEEvaluateConnectionRuleAction {
        switch self {
        case .connectIfNeeded: return .connectIfNeeded
        case .neverConnect: return .neverConnect
        }
    }
}

struct OnDemandEvaluateRuleSpec: Codable, Equatable, Identifiable {
    var id: UUID
    var action: OnDemandEvaluateAction
    var matchDomains: [String]
    var dnsServers: [String]
    var probeURL: String

    init(
        id: UUID = UUID(),
        action: OnDemandEvaluateAction,
        matchDomains: [String] = [],
        dnsServers: [String] = [],
        probeURL: String = ""
    ) {
        self.id = id
        self.action = action
        self.matchDomains = matchDomains
        self.dnsServers = dnsServers
        self.probeURL = probeURL
    }

    func normalized() -> Self {
        var copy = self
        copy.matchDomains = Self.cleaned(matchDomains)
        copy.dnsServers = Self.cleaned(dnsServers)
        copy.probeURL = probeURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }

    private static func cleaned(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap {
            let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return !value.isEmpty && seen.insert(value).inserted ? value : nil
        }
    }
}

struct OnDemandRuleSpec: Codable, Equatable, Identifiable {
    var id: UUID
    var action: OnDemandRuleAction
    var interface: OnDemandInterface
    var ssids: [String]
    var dnsSearchDomains: [String]
    var dnsServerAddresses: [String]
    var probeURL: String
    var connectionRules: [OnDemandEvaluateRuleSpec]

    init(
        id: UUID = UUID(),
        action: OnDemandRuleAction,
        interface: OnDemandInterface = .any,
        ssids: [String] = [],
        dnsSearchDomains: [String] = [],
        dnsServerAddresses: [String] = [],
        probeURL: String = "",
        connectionRules: [OnDemandEvaluateRuleSpec] = []
    ) {
        self.id = id
        self.action = action
        self.interface = interface
        self.ssids = ssids
        self.dnsSearchDomains = dnsSearchDomains
        self.dnsServerAddresses = dnsServerAddresses
        self.probeURL = probeURL
        self.connectionRules = connectionRules
    }

    func normalized() -> Self {
        var copy = self
        copy.ssids = Self.cleaned(ssids)
        copy.dnsSearchDomains = Self.cleaned(dnsSearchDomains)
        copy.dnsServerAddresses = Self.cleaned(dnsServerAddresses)
        copy.probeURL = probeURL.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.connectionRules = connectionRules.map { $0.normalized() }
        return copy
    }

    private static func cleaned(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap {
            let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return !value.isEmpty && seen.insert(value).inserted ? value : nil
        }
    }
}

extension OnDemandRuleSpec {
     
     
     
    func takingPending(ssid: String = "", dnsSearchDomain: String = "", dnsServerAddress: String = "") -> Self {
        var copy = self
        OnDemandPendingEntry.take(ssid, into: &copy.ssids)
        OnDemandPendingEntry.take(dnsSearchDomain, into: &copy.dnsSearchDomains)
        OnDemandPendingEntry.take(dnsServerAddress, into: &copy.dnsServerAddresses)
        return copy
    }
}

extension OnDemandEvaluateRuleSpec {
     
    func takingPending(matchDomain: String = "", dnsServer: String = "") -> Self {
        var copy = self
        OnDemandPendingEntry.take(matchDomain, into: &copy.matchDomains)
        OnDemandPendingEntry.take(dnsServer, into: &copy.dnsServers)
        return copy
    }
}

private enum OnDemandPendingEntry {
    static func take(_ text: String, into list: inout [String]) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty, !list.contains(value) { list.append(value) }
    }
}

 
 
enum OnDemandRulePreset: String, CaseIterable, Identifiable {
    case connectOnWiFi, connectOnCellular, disconnectOnWiFi, connectAnywhere

    var id: String { rawValue }

    var title: String {
        switch self {
        case .connectOnWiFi: return "Connect on Wi-Fi"
        case .connectOnCellular: return "Connect on Cellular"
        case .disconnectOnWiFi: return "Disconnect on Wi-Fi"
        case .connectAnywhere: return "Connect on Any Network"
        }
    }

     
    var rule: OnDemandRuleSpec {
        switch self {
        case .connectOnWiFi: return OnDemandRuleSpec(action: .connect, interface: .wifi)
        case .connectOnCellular: return OnDemandRuleSpec(action: .connect, interface: .cellular)
        case .disconnectOnWiFi: return OnDemandRuleSpec(action: .disconnect, interface: .wifi)
        case .connectAnywhere: return OnDemandRuleSpec(action: .connect)
        }
    }

     
    static var platformCases: [Self] {
        allCases.filter { OnDemandInterface.platformCases.contains($0.rule.interface) }
    }
}

struct OnDemandConfiguration: Codable, Equatable {
    var enabled: Bool
    var rules: [OnDemandRuleSpec]
     
     
     
     
    var alwaysOn = false
     
    var disconnectOnSleep = false
     
     
    var showDisconnectMessage = false

    init(
        enabled: Bool,
        rules: [OnDemandRuleSpec],
        alwaysOn: Bool = false,
        disconnectOnSleep: Bool = false,
        showDisconnectMessage: Bool = false
    ) {
        self.enabled = enabled
        self.rules = rules
        self.alwaysOn = alwaysOn
        self.disconnectOnSleep = disconnectOnSleep
        self.showDisconnectMessage = showDisconnectMessage
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, rules, alwaysOn, disconnectOnSleep, showDisconnectMessage
    }

     
     
     
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        rules = try container.decode([OnDemandRuleSpec].self, forKey: .rules)
        alwaysOn = try container.decodeIfPresent(Bool.self, forKey: .alwaysOn) ?? false
        disconnectOnSleep = try container.decodeIfPresent(Bool.self, forKey: .disconnectOnSleep) ?? false
        showDisconnectMessage = try container.decodeIfPresent(Bool.self, forKey: .showDisconnectMessage) ?? false
    }

    static let disabled = OnDemandConfiguration(
        enabled: false,
        rules: [OnDemandRuleSpec(action: .connect)]
    )

    func normalized() -> Self {
        var copy = self
        copy.rules = rules.map { $0.normalized() }
        return copy
    }

     
     
     
     
     
     
     
     
    func withOnDemandOffWhenItHasNoRules() -> Self {
        guard enabled, rules.isEmpty else { return self }
        var copy = self
        copy.enabled = false
        return copy
    }
}

enum OnDemandValidationError: Error, Equatable, LocalizedError {
    case missingRules
    case invalidDNSServer(String)
    case invalidProbeURL(String)
    case missingEvaluateRules
    case missingMatchDomains

    var errorDescription: String? {
        switch self {
        case .missingRules:
            return "Add at least one on-demand rule."
        case .invalidDNSServer:
            return "DNS server conditions must use an IPv4 or IPv6 address."
        case .invalidProbeURL:
            return "Probe URLs must be credential-free http or https URLs with a host."
        case .missingEvaluateRules:
            return "Evaluate Connection needs at least one connection rule."
        case .missingMatchDomains:
            return "Every connection rule needs at least one match domain."
        }
    }
}

 
 
enum OnDemandSettings {
    static let configurationKey = "onDemand.configuration.v2"
    static let enabledKey = "onDemand.enabled"
    static let ssidsKey = "onDemand.ssids"

    static var appGroupDefaults: UserDefaults {
        UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite) ?? .standard
    }

    static func configuration(
        from defaults: UserDefaults = appGroupDefaults
    ) -> OnDemandConfiguration {
        if let data = defaults.data(forKey: configurationKey),
           let decoded = try? JSONDecoder().decode(OnDemandConfiguration.self, from: data) {
            return decoded.normalized().withOnDemandOffWhenItHasNoRules()
        }

        let enabled = defaults.bool(forKey: enabledKey)
        let ssids = legacySSIDs(from: defaults)
        guard enabled else { return .disabled }
        guard !ssids.isEmpty else {
            return OnDemandConfiguration(enabled: true, rules: [OnDemandRuleSpec(action: .connect)])
        }
        return OnDemandConfiguration(enabled: true, rules: [
            OnDemandRuleSpec(action: .connect, interface: .wifi, ssids: ssids),
            OnDemandRuleSpec(action: .disconnect)
        ])
    }

    static func save(
        _ configuration: OnDemandConfiguration,
        in defaults: UserDefaults = appGroupDefaults
    ) throws {
        let configuration = configuration.normalized()
         
         
         
         
         
         
         
        var withoutAlwaysOn = configuration
        withoutAlwaysOn.alwaysOn = false
        _ = try rules(configuration: withoutAlwaysOn)
        let data = try JSONEncoder().encode(configuration)
        defaults.set(data, forKey: configurationKey)
        defaults.set(configuration.enabled, forKey: enabledKey)
        let firstConnectSSIDs = configuration.rules.first(where: { $0.action == .connect })?.ssids ?? []
        defaults.set(firstConnectSSIDs, forKey: ssidsKey)
    }

     
    static func enabled(from defaults: UserDefaults = appGroupDefaults) -> Bool {
        configuration(from: defaults).enabled
    }

    static func ssids(from defaults: UserDefaults = appGroupDefaults) -> [String] {
        if defaults.data(forKey: configurationKey) != nil {
            return configuration(from: defaults).rules.first(where: { $0.action == .connect })?.ssids ?? []
        }
        return legacySSIDs(from: defaults)
    }

    static func save(
        enabled: Bool,
        ssids: [String],
        in defaults: UserDefaults = appGroupDefaults
    ) {
        defaults.removeObject(forKey: configurationKey)
        defaults.set(enabled, forKey: enabledKey)
        defaults.set(cleaned(ssids), forKey: ssidsKey)
    }

     
    static func rules(enabled: Bool, ssids: [String]) -> [NEOnDemandRule]? {
        guard enabled else { return nil }
        let cleanedSSIDs = cleaned(ssids)
        let configuration: OnDemandConfiguration
        if cleanedSSIDs.isEmpty {
            configuration = OnDemandConfiguration(
                enabled: true,
                rules: [OnDemandRuleSpec(action: .connect)]
            )
        } else {
            configuration = OnDemandConfiguration(enabled: true, rules: [
                OnDemandRuleSpec(action: .connect, interface: .wifi, ssids: cleanedSSIDs),
                OnDemandRuleSpec(action: .disconnect)
            ])
        }
        return try? rules(configuration: configuration)
    }

     
     
     
    static func apply(_ configuration: OnDemandConfiguration, to manager: NETunnelProviderManager) throws {
        let rules = try rules(configuration: configuration)
        manager.onDemandRules = rules
        manager.isOnDemandEnabled = rules != nil
        manager.protocolConfiguration?.disconnectOnSleep = configuration.disconnectOnSleep
    }

     
     
     
    static func rules(configuration: OnDemandConfiguration) throws -> [NEOnDemandRule]? {
        if configuration.alwaysOn { return [NEOnDemandRuleConnect()] }
        guard configuration.enabled else { return nil }
        let configuration = configuration.normalized()
        guard !configuration.rules.isEmpty else { throw OnDemandValidationError.missingRules }
        return try configuration.rules.map(makeNativeRule)
    }

    private static func makeNativeRule(from spec: OnDemandRuleSpec) throws -> NEOnDemandRule {
        try validateDNSServers(spec.dnsServerAddresses)
        let probeURL = try validatedProbeURL(spec.probeURL)

        let rule: NEOnDemandRule
        switch spec.action {
        case .connect:
            rule = NEOnDemandRuleConnect()
        case .disconnect:
            rule = NEOnDemandRuleDisconnect()
        case .ignore:
            rule = NEOnDemandRuleIgnore()
        case .evaluate:
            guard !spec.connectionRules.isEmpty else {
                throw OnDemandValidationError.missingEvaluateRules
            }
            let evaluate = NEOnDemandRuleEvaluateConnection()
            evaluate.connectionRules = try spec.connectionRules.map(makeEvaluateRule)
            rule = evaluate
        }

        rule.interfaceTypeMatch = spec.interface.nativeValue
        rule.ssidMatch = spec.ssids.isEmpty ? nil : spec.ssids
        rule.dnsSearchDomainMatch = spec.dnsSearchDomains.isEmpty ? nil : spec.dnsSearchDomains
        rule.dnsServerAddressMatch = spec.dnsServerAddresses.isEmpty ? nil : spec.dnsServerAddresses
        rule.probeURL = probeURL
        return rule
    }

    private static func makeEvaluateRule(
        from spec: OnDemandEvaluateRuleSpec
    ) throws -> NEEvaluateConnectionRule {
        guard !spec.matchDomains.isEmpty else {
            throw OnDemandValidationError.missingMatchDomains
        }
        try validateDNSServers(spec.dnsServers)
        let rule = NEEvaluateConnectionRule(
            matchDomains: spec.matchDomains,
            andAction: spec.action.nativeValue
        )
        rule.useDNSServers = spec.dnsServers.isEmpty ? nil : spec.dnsServers
        rule.probeURL = try validatedProbeURL(spec.probeURL)
        return rule
    }

    private static func validateDNSServers(_ servers: [String]) throws {
        for server in servers where IPv4Address(server) == nil && IPv6Address(server) == nil {
            throw OnDemandValidationError.invalidDNSServer(server)
        }
    }

    private static func validatedProbeURL(_ raw: String) throws -> URL? {
        guard !raw.isEmpty else { return nil }
         
        guard let components = URLComponents(string: raw),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              components.host != nil,
              components.user == nil,
              components.password == nil,
              let url = components.url
        else {
            throw OnDemandValidationError.invalidProbeURL(raw)
        }
        return url
    }

    private static func legacySSIDs(from defaults: UserDefaults) -> [String] {
        cleaned(defaults.stringArray(forKey: ssidsKey) ?? [])
    }

    private static func cleaned(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap {
            let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return !value.isEmpty && seen.insert(value).inserted ? value : nil
        }
    }
}


 

extension OnDemandRuleSpec {
     
     
     
     
     
    func title(locale: Locale) -> String {
        [action.title, interface.title]
            .map { ClashCopy.string($0, locale: locale) }
            .joined(separator: " · ")
    }

     
     
     
     
     
    func conditions(locale: Locale) -> String? {
        func words(_ items: [String]) -> String { ConfigurationValueWords.listJoined(items, locale: locale) }
        var parts: [ClashDisplayText] = []
        if !ssids.isEmpty {
            parts.append(.format("SSID %@", [words(ssids)]))
        }
        if !dnsSearchDomains.isEmpty {
            parts.append(.format("DNS search domain %@", [words(dnsSearchDomains)]))
        }
        if !dnsServerAddresses.isEmpty {
            parts.append(.format("DNS server %@", [words(dnsServerAddresses)]))
        }
        if !probeURL.isEmpty {
            parts.append(.format("Probe URL %@", [probeURL]))
        }
        var line = parts.map { ClashCopy.string(for: $0, locale: locale) }
        if action == .evaluate {
            line.append(connectionRules.count == 1
                ? ClashCopy.string("1 connection rule", locale: locale)
                : ClashCopy.format("%d connection rules", locale: locale, connectionRules.count))
        }
        return line.isEmpty ? nil : line.joined(separator: " · ")
    }

     
     
     
    var hasConditions: Bool {
        !ssids.isEmpty || !dnsSearchDomains.isEmpty || !dnsServerAddresses.isEmpty || !probeURL.isEmpty
    }

     
     
     
     
     
     
    init(native rule: NEOnDemandRule, position: Int) {
        let action: OnDemandRuleAction
        var connectionRules: [OnDemandEvaluateRuleSpec] = []
        switch rule {
        case is NEOnDemandRuleConnect:
            action = .connect
        case is NEOnDemandRuleDisconnect:
            action = .disconnect
        case let evaluate as NEOnDemandRuleEvaluateConnection:
            action = .evaluate
            connectionRules = (evaluate.connectionRules ?? []).enumerated().map { index, native in
                OnDemandEvaluateRuleSpec(
                    id: OnDemandRuleSpec.positionalID(position, index + 1),
                    action: native.action == .neverConnect ? .neverConnect : .connectIfNeeded,
                    matchDomains: native.matchDomains,
                    dnsServers: native.useDNSServers ?? [],
                    probeURL: native.probeURL?.absoluteString ?? ""
                )
            }
        default:
             
             
            action = .ignore
        }
        self.init(
            id: OnDemandRuleSpec.positionalID(position, 0),
            action: action,
             
             
             
            interface: OnDemandRuleSpec.interface(of: rule.interfaceTypeMatch) ?? .any,
            ssids: rule.ssidMatch ?? [],
            dnsSearchDomains: rule.dnsSearchDomainMatch ?? [],
            dnsServerAddresses: rule.dnsServerAddressMatch ?? [],
            probeURL: rule.probeURL?.absoluteString ?? "",
            connectionRules: connectionRules
        )
    }

     
     
    static func interface(of type: NEOnDemandRuleInterfaceType) -> OnDemandInterface? {
        if type == OnDemandInterface.any.nativeValue { return .any }
        if type == OnDemandInterface.wifi.nativeValue { return .wifi }
        if type == OnDemandInterface.cellular.nativeValue { return .cellular }
        return nil
    }

     
     
    private static func positionalID(_ position: Int, _ inner: Int) -> UUID {
        let place = UInt32(clamping: max(0, position))
        let within = UInt32(clamping: max(0, inner))
        return UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0,
                           UInt8(within >> 24 & 0xFF), UInt8(within >> 16 & 0xFF),
                           UInt8(within >> 8 & 0xFF), UInt8(within & 0xFF),
                           UInt8(place >> 24 & 0xFF), UInt8(place >> 16 & 0xFF),
                           UInt8(place >> 8 & 0xFF), UInt8(place & 0xFF)))
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct OnDemandStartRefusal: Equatable {
     
     
    let rules: [OnDemandRuleSpec]
     
     
    let isCertain: Bool
     
     
    let interface: NetworkPathInterfaceKind

     
     
    static let certainMessage =
        "On Demand rule %@ stopped the connection on this network. Tap to change."
     
     
     
     
    static let certainStatement =
        "On Demand rule %@ stopped the connection on this network."
     
    static let possibleMessage =
        "On Demand rule %@ may have stopped the connection on this network."

     
     
     
    func ruleNames(locale: Locale) -> String {
        var seen = Set<String>()
        let quoted = rules
            .map { $0.title(locale: locale) }
            .filter { seen.insert($0).inserted }
            .map { ClashCopy.string(for: .format("“%@”", [$0]), locale: locale) }
        return ConfigurationValueWords.listJoined(quoted, locale: locale)
    }

     
    enum StartNetwork: Equatable {
        case wifi
        case cellular
         
        case neither
         
         
        case unknown

        init(_ interface: NetworkPathInterfaceKind) {
            switch interface {
            case .wifi: self = .wifi
            case .cellular: self = .cellular
            case .wiredEthernet: self = .neither
            case .loopback, .other, .unknown: self = .unknown
            }
        }
    }

    private enum Match { case no, maybe, yes }

     
     
     
    static func isWeighable(_ interface: NetworkPathInterfaceKind) -> Bool {
        StartNetwork(interface) != .unknown
    }

     
     
     
    private enum RuleNetwork: Equatable {
         
        case offered
         
         
         
        case ethernet
         
        case unrecognized

        init(_ type: NEOnDemandRuleInterfaceType) {
            if OnDemandRuleSpec.interface(of: type) != nil {
                self = .offered
            } else if type.rawValue == 1 {
                self = .ethernet
            } else {
                self = .unrecognized
            }
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func find(on manager: NEVPNManager, interface: NetworkPathInterfaceKind) -> Self? {
        guard manager.isOnDemandEnabled else { return nil }
        let network = StartNetwork(interface)
        var named: [OnDemandRuleSpec] = []
        var somethingMightMatchFirst = false
        for (position, native) in (manager.onDemandRules ?? []).enumerated() {
            let rule = OnDemandRuleSpec(native: native, position: position).normalized()
            let kind = RuleNetwork(native.interfaceTypeMatch)
            let verdict = match(rule, kind: kind, on: network)
            if verdict == .no { continue }
            let isNamed = kind == .offered
                && rule.action == .disconnect
                && (network != .unknown || rule.interface.nativeValue == .any)
            if isNamed { named.append(rule) }
            if verdict == .yes {
                if isNamed, !somethingMightMatchFirst {
                    return Self(rules: [rule], isCertain: true, interface: interface)
                }
                break
            }
            somethingMightMatchFirst = true
        }
        guard !named.isEmpty else { return nil }
        return Self(rules: named, isCertain: false, interface: interface)
    }

     
     
     
     
    static func canStopAStart(on manager: NEVPNManager) -> Bool {
        manager.isOnDemandEnabled
            && manager.onDemandRules?.contains(where: { $0 is NEOnDemandRuleDisconnect }) == true
    }

    private static func match(_ rule: OnDemandRuleSpec, kind: RuleNetwork, on network: StartNetwork) -> Match {
        let byInterface: Match
        switch kind {
        case .ethernet:
             
            byInterface = network == .neither ? .yes : network == .unknown ? .maybe : .no
        case .unrecognized:
            byInterface = .maybe
        case .offered:
             
             
            switch rule.interface.nativeValue {
            case .any:
                byInterface = .yes
            case .wiFi:
                byInterface = network == .wifi ? .yes : network == .unknown ? .maybe : .no
            default:
                byInterface = network == .cellular ? .yes : network == .unknown ? .maybe : .no
            }
        }
        guard byInterface != .no else { return .no }
         
        if !rule.ssids.isEmpty, network == .cellular || network == .neither { return .no }
        return rule.hasConditions ? .maybe : byInterface
    }
}

 
 
 
 
 
enum OnDemandRuleSurgery {
     
     
    static func move(
        _ rules: inout [OnDemandRuleSpec], id: UUID, offset: Int
    ) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else {
            return
        }
        let target = index + offset
        guard rules.indices.contains(target) else { return }
        rules.swapAt(index, target)
    }

    static func remove(_ rules: inout [OnDemandRuleSpec], id: UUID) {
        rules.removeAll { $0.id == id }
    }
}
