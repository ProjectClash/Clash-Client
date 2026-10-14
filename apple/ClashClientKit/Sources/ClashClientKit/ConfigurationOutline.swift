import Foundation

 
 
 
 
 
 
public enum ConfigurationOutlineSection: String, CaseIterable, Sendable {
    case general, dns, sniffer, mitm, inbound, proxies, proxyProviders, proxyGroups, rules, ruleProviders, subRules
    case tunnels, ntp, experimental, unknown
     
     
     
     
    case customRules, overrideScript

     
     
     
    public var isConfigurationsOwn: Bool { self == .customRules || self == .overrideScript }
}

 
 
 
 
public enum ConfigurationOutlineForm: Sendable { case original, composed }

public struct ConfigurationOutlineRow: Equatable, Sendable {
    public let section: ConfigurationOutlineSection
     
     
     
     
    public let count: Int
     
    public var hidden: Int? = nil
     
     
    public var downloadable: Int? = nil
     
    public var lines: Int? = nil
     
    public var enabled: Bool? = nil
     
     
     
    public var written: Bool = false
}

public enum ConfigurationOutline {
     
     
     
     
    public static let knownTopLevelKeys: [String] = sectionOfKey.map(\.key)

     
     
     
     
     
     
    private static let sectionOfKey: [(key: String, section: ConfigurationOutlineSection)] = [
         
        ("allow-lan", .general), ("bind-address", .general), ("authentication", .general),
        ("skip-auth-prefixes", .general), ("lan-allowed-ips", .general), ("lan-disallowed-ips", .general),
        ("mode", .general), ("log-level", .general), ("ipv6", .general), ("keep-alive-idle", .general),
        ("keep-alive-interval", .general), ("disable-keep-alive", .general), ("find-process-mode", .general),
        ("external-controller", .general), ("external-controller-tls", .general),
        ("external-controller-unix", .general), ("external-controller-pipe", .general),
        ("external-controller-cors", .general), ("external-controller-routing-mark", .general),
        ("secret", .general), ("external-doh-server", .general), ("external-ui", .general),
        ("external-ui-name", .general), ("external-ui-url", .general), ("profile", .general),
        ("unified-delay", .general), ("tcp-concurrent", .general), ("interface-name", .general),
        ("routing-mark", .general), ("tls", .general), ("global-client-fingerprint", .general),
        ("geodata-mode", .general), ("geodata-loader", .general), ("geo-auto-update", .general),
        ("geo-update-interval", .general), ("geox-url", .general), ("global-ua", .general),
        ("etag-support", .general),
        ("network-strategy", .general), ("network-type", .general), ("fallback-network-type", .general),
         
         
        ("geosite-matcher", .general),
        ("clash-for-android", .general),
         
        ("dns", .dns), ("hosts", .dns),
         
        ("sniffer", .sniffer),

        ("mitm", .mitm),

        ("port", .inbound), ("socks-port", .inbound), ("mixed-port", .inbound), ("redir-port", .inbound),
        ("tproxy-port", .inbound), ("inbound-tfo", .inbound), ("inbound-mptcp", .inbound), ("tun", .inbound),
        ("listeners", .inbound), ("ss-config", .inbound), ("vmess-config", .inbound), ("tuic-server", .inbound),
        ("iptables", .inbound),
         
        ("proxies", .proxies),
        ("proxy-providers", .proxyProviders),
        ("proxy-groups", .proxyGroups),
        ("rules", .rules),
        ("rule-providers", .ruleProviders),
        ("sub-rules", .subRules),
         
        ("tunnels", .tunnels),
        ("ntp", .ntp),
        ("experimental", .experimental),
    ]

    private static let sectionIndex: [String: ConfigurationOutlineSection] =
        Dictionary(uniqueKeysWithValues: sectionOfKey.map { ($0.key, $0.section) })

    public static func section(forTopLevelKey key: String) -> ConfigurationOutlineSection {
        sectionIndex[key] ?? .unknown
    }

     
     
     
     
     
    public static func sections(for form: ConfigurationOutlineForm) -> [ConfigurationOutlineSection] {
        [.general, .dns, .sniffer, .mitm, .inbound, .proxies, .proxyProviders, .proxyGroups, .rules,
         .ruleProviders, .subRules, .tunnels, .ntp, .experimental, .unknown, .customRules, .overrideScript]
    }

     
     
     
    public static func showsDefaults(_ section: ConfigurationOutlineSection) -> Bool {
        [.general, .dns, .sniffer, .mitm, .inbound, .ntp, .experimental].contains(section)
    }

     
     
     
     
    public static func composedDocument(page: OrderedJSON, rules: OrderedJSON) -> OrderedJSON {
        var entries: [(key: String, value: OrderedJSON)] = []
        if case let .object(items) = ConfigurationSettingsDocument.project(page) { entries += items }
        if case let .object(items) = ConfigurationRuleDocument.project(rules) { entries += items }
        return .object(entries)
    }

     
     
    public static func rows(for document: OrderedJSON, form: ConfigurationOutlineForm,
                            customRules: Int = 0) -> [ConfigurationOutlineRow] {
        let pairs: [(key: String, value: OrderedJSON)]
        if case let .object(items) = document { pairs = items } else { pairs = [] }
        func value(_ key: String) -> OrderedJSON? { pairs.last(where: { $0.key == key })?.value }
        func size(_ node: OrderedJSON?) -> Int {
            switch node {
            case let .array(items)?: return items.count
            case let .object(items)?: return items.count
            default: return 0
            }
        }
        func written(_ section: ConfigurationOutlineSection) -> Int {
            Set(pairs.map(\.key).filter { self.section(forTopLevelKey: $0) == section }).count
        }
        func field(_ node: OrderedJSON?, _ name: String) -> OrderedJSON? {
            guard case let .object(items)? = node else { return nil }
            return items.last(where: { $0.key.lowercased() == name })?.value
        }
        func isTrue(_ node: OrderedJSON?) -> Bool? {
            switch node {
            case let .scalar(token)?: return token == "true" ? true : (token == "false" ? false : nil)
            case let .string(text)?: return text == "true" ? true : (text == "false" ? false : nil)
            default: return nil
            }
        }
        func downloadable(_ node: OrderedJSON?) -> Int {
            guard case let .object(items)? = node else { return 0 }
            return items.filter {
                if case let .string(type)? = field($0.value, "type") { return type.lowercased() == "http" }
                return false
            }.count
        }

        func writes(_ section: ConfigurationOutlineSection) -> Bool {
            switch section {
            case .customRules: return customRules > 0
            case .overrideScript: return false
            case .unknown: return pairs.contains { sectionIndex[$0.key] == nil }
            default: return pairs.contains { self.section(forTopLevelKey: $0.key) == section }
            }
        }
        return sections(for: form).map { section -> ConfigurationOutlineRow in
            var row = row(section)
            row.written = writes(section)
            return row
        }

        func row(_ section: ConfigurationOutlineSection) -> ConfigurationOutlineRow {
            switch section {
            case .customRules:
                return .init(section: section, count: customRules)
            case .overrideScript:
                return .init(section: section, count: 0)
            case .general, .inbound:
                return .init(section: section, count: written(section))
            case .dns, .proxies, .rules, .tunnels, .ntp, .experimental:
                let key = ["dns": "dns", "proxies": "proxies", "rules": "rules", "tunnels": "tunnels",
                           "ntp": "ntp", "experimental": "experimental"][section.rawValue]!
                return .init(section: section, count: size(value(key)))
            case .proxyGroups:
                let groups = value("proxy-groups")
                var hidden = 0
                if case let .array(items)? = groups { hidden = items.filter { isTrue(field($0, "hidden")) == true }.count }
                return .init(section: section, count: size(groups), hidden: hidden)
            case .proxyProviders:
                let providers = value("proxy-providers")
                return .init(section: section, count: size(providers), downloadable: downloadable(providers))
            case .ruleProviders:
                let providers = value("rule-providers")
                return .init(section: section, count: size(providers), downloadable: downloadable(providers))
            case .subRules:
                let groups = value("sub-rules")
                var lines = 0
                if case let .object(items)? = groups { lines = items.reduce(0) { $0 + size($1.value) } }
                return .init(section: section, count: size(groups), lines: lines)
            case .sniffer:
                let sniffer = value("sniffer")
                let protocols = field(sniffer, "sniff") ?? field(sniffer, "sniffing")
                return .init(section: section, count: size(protocols), enabled: isTrue(field(sniffer, "enable")))
            case .mitm:
                let mitm = value("mitm")
                let policies = field(mitm, "rewrite")
                return .init(section: section, count: size(policies), enabled: isTrue(field(mitm, "enable")))
            case .unknown:
                return .init(section: section, count: Set(pairs.map(\.key).filter { sectionIndex[$0] == nil }).count)
            }
        }
    }
}
