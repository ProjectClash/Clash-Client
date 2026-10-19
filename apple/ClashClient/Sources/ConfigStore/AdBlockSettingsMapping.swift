import ClashClientKit
import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum AdBlockSettingsMapping {
    enum Mapped: Equatable {
        case edits([AdBlockConfigurationEdit])
        case rules([AdBlockRoutingRule])
        case mitmExclusions([AdBlockHostEntry])
        case plainExclusions([AdBlockHostEntry])
        case hosts([AdBlockHostMapping])
        case device([AdBlockDeviceSetting])
        case alreadyInEffect
         
        case ignored(AdBlockIgnoredReason)
         
        case itemLeftOut(String, AdBlockIgnoredReason)
         
         
        case changes([AdBlockModuleChange])
         
        case note(AdBlockSentence)
         
        case ruleSets([AdBlockRuleSet])
    }

     

     
    enum Value {
         
        case names
         
        case routes
         
        case servers(ServerKind)
        case bool
        case text
         
        case url
         
        case number
         
         
        case ipv4, ipv6
         
        case choice([String])
    }

    enum ServerKind {
         
         
        case any
         
        case encrypted
         
        case doh, doq, doh3
    }

    enum Kind {
         
        case list([String], Value, condition: AdBlockEditCondition? = nil)
         
        case scalar([String], Value)
         
        case device(AdBlockDeviceSettingKey, Value)
         
        case inEffect
         
         
         
        case holds(when: Bool, otherwise: AdBlockIgnoredReason)
         
        case notApplicable(AdBlockSentence)
         
        case skipped(AdBlockIgnoredReason)
         
        case special((Input) -> [Mapped])
    }

    struct Row {
        let families: Set<AdBlockModuleFormat>
        let kind: Kind
    }

     
    struct Input {
        let key: String
         
        let directive: AdBlockHostListDirective?
        let value: String
        let family: AdBlockModuleFormat
        let origin: AdBlockLineOrigin
         
         
         
        var platform: AdBlockPlatform = .current

         
        var listOperation: AdBlockEditOperation {
            guard family != .loon else { return .append }
            switch directive {
            case .append?: return .append
            case .insert?: return .prepend
            default: return .replace
            }
        }

        var items: [String] {
            value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }

        func edit(_ path: [String], _ operation: AdBlockEditOperation, _ value: OrderedJSON,
                  condition: AdBlockEditCondition? = nil) -> AdBlockConfigurationEdit {
            AdBlockConfigurationEdit(path: path, operation: operation, valueJSON: value.serialized(), origin: origin, condition: condition)
        }
    }

    private static let surge: Set<AdBlockModuleFormat> = [.surge]
    private static let loon: Set<AdBlockModuleFormat> = [.loon]
    /// The rows both Surge and Loon share, and that Quantumult X spells the
    /// same way as Surge. A Quantumult X module gets these settings too.
    private static let both: Set<AdBlockModuleFormat> = [.surge, .loon, .quantumultX]

     
     
     
     
    static let rows: [String: Row] = [
         
        "skip-proxy": Row(families: both, kind: .special(skipProxy)),

        "always-real-ip": Row(families: surge, kind: .special(realIP)),
        "real-ip": Row(families: loon, kind: .special(realIP)),
        "tun-excluded-routes": Row(families: surge, kind: .list(["tun", "route-exclude-address"], .routes)),
        "bypass-tun": Row(families: loon, kind: .special(bypassTun)),
        "tun-included-routes": Row(families: surge, kind: .list(["tun", "route-address"], .routes, condition: .whereWritten)),
        "include-tun": Row(families: loon, kind: .list(["tun", "route-address"], .routes, condition: .whereWritten)),
        "dns-server": Row(families: both, kind: .special(dnsServer)),
        "encrypted-dns-server": Row(families: surge, kind: .list(["dns", "nameserver"], .servers(.encrypted))),
        "doh-server": Row(families: loon, kind: .list(["dns", "nameserver"], .servers(.doh))),
        "doq-server": Row(families: loon, kind: .list(["dns", "nameserver"], .servers(.doq))),
        "doh3-server": Row(families: loon, kind: .list(["dns", "nameserver"], .servers(.doh3))),
         
        "direct-dns-server": Row(families: surge, kind: .list(["dns", "direct-nameserver"], .servers(.any))),
        "fallback-dns-server": Row(families: surge, kind: .special(fallbackDNSServer)),
        "proxy-dns-server": Row(families: surge, kind: .list(["dns", "proxy-server-nameserver"], .servers(.any))),
        "dns-direct-system": Row(families: surge, kind: .special(dnsDirectSystem)),
        "encrypted-dns-follow-outbound-mode": Row(families: surge, kind: .special(followOutboundMode)),
        "encrypted-dns-skip-cert-verification": Row(families: surge, kind: .special(skipCertVerification)),
        "hijack-dns": Row(families: surge, kind: .special(hijackDNS)),
        "ipv6": Row(families: surge, kind: .special(ipv6)),
        "ipv6-vif": Row(families: both, kind: .special(ipv6VIF)),
        "always-raw-tcp-hosts": Row(families: surge, kind: .special(rawTCPHosts)),
        "always-raw-tcp-keywords": Row(families: surge, kind: .special(rawTCPKeywords)),
        "exclude-simple-hostnames": Row(families: surge, kind: .special(simpleHostnames)),
        "block-quic": Row(families: surge, kind: .special(blockQUIC)),
        "geoip-maxmind-url": Row(families: surge, kind: .scalar(["geox-url", "mmdb"], .url)),
         
         
        "disable-geoip-db-auto-update": Row(families: surge,
                                            kind: .holds(when: false, otherwise: .setInClashSettings("disable-geoip-db-auto-update"))),
         
         
        "read-etc-hosts": Row(families: surge, kind: .inEffect),
         
         
         
         
        "udp-priority": Row(families: surge, kind: .holds(when: false, otherwise: .notApplicable(.clashCannotDoThis))),
        "prefer-ipv6": Row(families: surge, kind: .holds(when: false, otherwise: .notApplicable(.clashCannotDoThis))),
        "private-ip-answer": Row(families: surge, kind: .holds(when: true, otherwise: .notApplicable(.clashCannotDoThis))),
        "dns-direct-fallback-proxy": Row(families: surge, kind: .holds(when: false, otherwise: .notApplicable(.clashCannotDoThis))),
        "always-ip-address": Row(families: surge, kind: .holds(when: false, otherwise: .notApplicable(.clashCannotDoThis))),
         
        "icmp-auto-reply": Row(families: surge, kind: .special(icmpAutoReply)),
         
        "close-if-proxy-chain-missing": Row(families: surge, kind: .holds(when: true, otherwise: .notApplicable(.clashCannotDoThis))),
        "ipv6-only-if-no-ipv4-dns": Row(families: surge, kind: .inEffect),
         
         
        "use-local-host-item-for-proxy": Row(families: surge, kind: .inEffect),
         
        "udp-policy-not-supported-behaviour": Row(families: surge, kind: .special(udpUnsupported)),
        "stun-response-ip": Row(families: surge, kind: .scalar(["x-clash-stun-response-ip"], .ipv4)),
        "stun-response-ipv6": Row(families: surge, kind: .scalar(["x-clash-stun-response-ipv6"], .ipv6)),
        "allow-dns-svcb": Row(families: surge, kind: .scalar(["dns", "x-clash-answer-svcb"], .bool)),
        "allow-dns-all": Row(families: surge, kind: .special(allowDNSAll)),
        "show-error-page-for-reject": Row(families: surge, kind: .special(errorPageForReject)),
        "always-reject-url-rewrite": Row(families: surge, kind: .special(alwaysRejectURLRewrite)),
         
        "hide-vpn-icon": Row(families: surge, kind: .device(.hideVPNIcon, .bool)),
        "include-all-networks": Row(families: surge, kind: .device(.includeAllNetworks, .bool)),
        "include-local-networks": Row(families: surge, kind: .device(.includeLocalNetworks, .bool)),
        "include-apns": Row(families: surge, kind: .device(.includeAPNs, .bool)),
         
        "include-cellular-services": Row(families: surge, kind: .special(includeCellularServices)),
        "compatibility-mode": Row(families: surge, kind: .special(compatibilityMode)),
        "proxy-test-url": Row(families: surge, kind: .device(.testURL, .url)),
         
         
        "internet-test-url": Row(families: surge, kind: .notApplicable(.noEffect)),
         
         
         
        "test-timeout": Row(families: surge, kind: .skipped(.platformCannot(.noSuchSetting))),
        "proxy-test-udp": Row(families: surge, kind: .skipped(.platformCannot(.noSuchSetting))),
        "wifi-assist": Row(families: surge, kind: .skipped(.platformCannot(.networkSwitching))),
        "all-hybrid": Row(families: surge, kind: .skipped(.platformCannot(.networkSwitching))),
        "loglevel": Row(families: surge, kind: .special(logLevel)),
         
        "allow-wifi-access": Row(families: surge, kind: .scalar(["allow-lan"], .bool)),
        "allow-hotspot-access": Row(families: surge, kind: .scalar(["allow-lan"], .bool)),
        "wifi-access-http-port": Row(families: surge, kind: .scalar(["port"], .number)),
        "wifi-access-socks5-port": Row(families: surge, kind: .scalar(["socks-port"], .number)),
        "http-api": Row(families: surge, kind: .special(httpAPI)),
        "external-controller-access": Row(families: surge, kind: .special(externalControllerAccess)),
        "http-api-tls": Row(families: surge, kind: .special(httpAPITLS)),
         
        "http-api-web-dashboard": Row(families: surge, kind: .holds(when: false, otherwise: .notApplicable(.clashCannotDoThis))),
        "http-listen": Row(families: surge, kind: .special({ listen($0, port: "port") })),
        "socks5-listen": Row(families: surge, kind: .special({ listen($0, port: "socks-port") })),
         
        "include": Row(families: surge, kind: .notApplicable(.noEffect)),
        "bypass-system": Row(families: surge, kind: .notApplicable(.noEffect)),
        "tls-provider": Row(families: surge, kind: .notApplicable(.noEffect)),
        "vif-mode": Row(families: surge, kind: .notApplicable(.noEffect)),
        "network-framework": Row(families: surge, kind: .notApplicable(.noEffect)),
        "debug-cpu-usage": Row(families: surge, kind: .notApplicable(.noEffect)),
    ]

     

     
     
     
     
     
     
    static let waitingForTheKernel: Set<String> = []

     
     
    static let changeKeys: [String: AdBlockModuleChange.Key] = [
        "loglevel": .logLevel,
        "allow-wifi-access": .lanSharing, "allow-hotspot-access": .lanSharing,
        "wifi-access-http-port": .httpPort, "wifi-access-socks5-port": .socksPort,
        "http-listen": .httpPort, "socks5-listen": .socksPort,
        "http-api": .controller, "external-controller-access": .controller,
        "compatibility-mode": .homeKitCompatibility,
    ]

     
    static let stashChangeKeys: [String: AdBlockModuleChange.Key] = [
        "log-level": .logLevel, "mode": .mode, "allow-lan": .lanSharing, "bind-address": .bindAddress,
        "port": .httpPort, "socks-port": .socksPort, "mixed-port": .mixedPort,
        "external-controller": .controller, "secret": .secret,
    ]

     
    static func waitsForTheKernel(_ edit: AdBlockConfigurationEdit) -> String? {
        let key = edit.path.prefix(2).joined(separator: ".")
        if waitingForTheKernel.contains(key) { return key }
        return edit.path.first.flatMap { waitingForTheKernel.contains($0) ? $0 : nil }
    }

     

     
     
     
     
     
    static func general(_ key: String, directive: AdBlockHostListDirective?, value: String, family: AdBlockModuleFormat,
                        origin: AdBlockLineOrigin, platform: AdBlockPlatform = .current) -> [Mapped] {
        let input = Input(key: key, directive: directive, value: value.trimmingCharacters(in: .whitespaces), family: family,
                          origin: origin, platform: platform)
        guard let row = rows[key] else {
            return [.ignored(family == .loon ? .noEffectInItsOwnApp(.noEffectThereEither) : .settingNotSupported(key))]
        }
        guard row.families.contains(family) else {
            return [.ignored(family == .loon ? .noEffectInItsOwnApp(.noEffectThereEither) : .settingNotSupported(key))]
        }
        let mapped: [Mapped]
        switch row.kind {
        case .list(let path, let kind, let condition):
            mapped = list(input, path, kind, condition: condition)
        case .scalar(let path, let kind):
            guard let written = scalar(input.value, kind) else { return [.ignored(.unreadableLine)] }
            mapped = [.edits([input.edit(path, .replace, written)])]
        case .device(let key, let kind):
            guard let written = scalar(input.value, kind) else { return [.ignored(.unreadableLine)] }
            mapped = [.device([AdBlockDeviceSetting(key: key, value: deviceValue(written), origin: origin)]),
                      .changes([AdBlockModuleChange(key: .init(key), value: input.value, origin: origin)])]
        case .inEffect:
            mapped = [.alreadyInEffect]
        case .holds(let when, let otherwise):
            guard let on = boolean(input.value) else { return [.ignored(.unreadableLine)] }
            mapped = [on == when ? .alreadyInEffect : .ignored(otherwise)]
        case .notApplicable(let why):
            mapped = [.ignored(.notApplicable(why))]
        case .skipped(let why):
            mapped = [.ignored(why)]
        case .special(let map):
            mapped = map(input)
        }
         
        guard let change = changeKeys[key], mapped.contains(where: { result in
            switch result {
            case .edits, .device: return true
            default: return false
            }
        }) else { return mapped }
        return mapped + [.changes([AdBlockModuleChange(key: change, value: input.value, origin: origin)])]
    }

     
    private static func list(_ input: Input, _ path: [String], _ kind: Value, condition: AdBlockEditCondition?) -> [Mapped] {
        var out: [Mapped] = []
        var values: [OrderedJSON] = []
        for item in input.items {
            if let written = listItem(item, kind) {
                if !values.contains(.string(written)) { values.append(.string(written)) }
            } else {
                out.append(.itemLeftOut(item, .invalidHost(item)))
            }
        }
        guard !values.isEmpty else { return out.isEmpty ? [.ignored(.unreadableLine)] : out }
        return [.edits([input.edit(path, input.listOperation, .array(values), condition: condition)])] + out
    }

    private static func listItem(_ item: String, _ kind: Value) -> String? {
        switch kind {
        case .names: return fakeIPFilterItem(surge: item) == nil ? nil : item.lowercased()
        case .routes: return route(item)
        case .servers(let server): return dnsServer(item, kind: server)
        default: return scalar(item, kind).flatMap { if case .string(let text) = $0 { return text } else { return nil } }
        }
    }

     
    static func scalar(_ value: String, _ kind: Value) -> OrderedJSON? {
        let text = unquoted(value)
        switch kind {
        case .bool: return boolean(text).map { .scalar($0 ? "true" : "false") }
        case .number:
            guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(text), number <= 65_535 else { return nil }
            return .scalar(String(number))
        case .url:
            guard let components = URLComponents(string: text), ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
                  !(components.host ?? "").isEmpty, AdBlockYAMLText.isOneLine(text) else { return nil }
            return .string(text)
        case .text:
            guard !text.isEmpty, AdBlockYAMLText.isOneLine(text) else { return nil }
            return .string(text)
        case .ipv4, .ipv6:
            var wantsIPv6 = false
            if case .ipv6 = kind { wantsIPv6 = true }
            guard let address = AdBlockIPLiteral(text), address.isIPv6 == wantsIPv6 else { return nil }
            return .string(address.canonical)
        case .choice(let words):
            guard words.contains(text.lowercased()) else { return nil }
            return .string(text.lowercased())
        case .names, .routes, .servers:
            return listItem(text, kind).map(OrderedJSON.string)
        }
    }

     
     
    private static func deviceValue(_ json: OrderedJSON) -> String {
        switch json {
        case .string(let text): return text
        case .scalar(let token): return token
        default: return json.serialized()
        }
    }

    static func boolean(_ text: String) -> Bool? {
        switch text.lowercased() {
        case "true", "yes", "on", "1": return true
        case "false", "no", "off", "0": return false
        default: return nil
        }
    }

    private static func unquoted(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2, let first = trimmed.first, first == "\"" || first == "'", trimmed.last == first else { return trimmed }
        return String(trimmed.dropFirst().dropLast())
    }

     

    private static let nameCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-_*?+")

     
     
     
     
     
     
    static func trieHolds(_ pattern: String) -> Bool {
        guard let first = pattern.first, let last = pattern.last, !first.isWhitespace, !last.isWhitespace,
              last != "." else { return false }
        let labels = pattern.split(separator: ".", omittingEmptySubsequences: false)
        if labels.count == 1 { guard !labels[0].isEmpty else { return false } }
        else if labels.dropFirst().contains(where: \.isEmpty) { return false }
        for (index, label) in labels.enumerated() {
            if label.contains("+"), label != "+" || index != 0 || labels.count == 1 { return false }
            if label.contains("*"), label != "*" { return false }
        }
        return true
    }

     
    private static func isPlainName(_ name: Substring) -> Bool {
        !name.isEmpty && !name.contains("*") && !name.contains("?") && !name.contains("+") && !name.hasPrefix(".") && trieHolds(String(name))
    }

     
    private static func filterItem(_ written: String, name: String?, rule: String?) -> OrderedJSON {
        var pairs: [(key: String, value: OrderedJSON)] = [("item", .string(written))]
        if let name { pairs.append(("name", .string(name))) }
        if let rule { pairs.append(("rule", .string(rule))) }
        return .object(pairs)
    }

     
     
     
     
     
     
     
     
    static func fakeIPFilterItem(surge item: String) -> OrderedJSON? {
        let name = item.lowercased()
        guard !name.isEmpty, !name.hasPrefix("-"), !name.hasPrefix("."), !name.hasSuffix("."), !name.contains(".."),
              !name.contains("+"), name.unicodeScalars.allSatisfy(nameCharacters.contains) else { return nil }
        if name.hasPrefix("*."), isPlainName(name.dropFirst(2)) {
            return filterItem(item, name: "+." + name.dropFirst(2), rule: "DOMAIN-SUFFIX," + name.dropFirst(2))
        }
        if isPlainName(Substring(name)) { return filterItem(item, name: name, rule: "DOMAIN," + name) }
        return filterItem(item, name: !name.contains("?") && trieHolds(name) ? name : nil, rule: "DOMAIN-WILDCARD," + name)
    }

     
     
     
     
    static func fakeIPFilterItem(kernel item: String) -> OrderedJSON? {
        let name = item.trimmingCharacters(in: .whitespaces).lowercased()
        guard AdBlockYAMLText.isOneLine(name) else { return nil }
        if name.hasPrefix("geosite:") {
            let category = name.dropFirst("geosite:".count)
            guard !category.isEmpty, !category.contains(","), !category.contains(" ") else { return nil }
            return filterItem(item, name: name, rule: "GEOSITE," + category)
        }
        guard name.unicodeScalars.allSatisfy(nameCharacters.contains), !name.contains("?"), trieHolds(name) else { return nil }
        if name.hasPrefix("+."), isPlainName(name.dropFirst(2)) { return filterItem(item, name: name, rule: "DOMAIN-SUFFIX," + name.dropFirst(2)) }
        if name.hasPrefix("."), isPlainName(name.dropFirst()) { return filterItem(item, name: name, rule: "DOMAIN-WILDCARD,*" + name) }
        if isPlainName(Substring(name)) { return filterItem(item, name: name, rule: "DOMAIN," + name) }
         
        var labels = name.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        var head = "^"
        if labels.first == "+" { head = "^(?:.+\\.)?"; labels.removeFirst() }
        else if labels.first == "" { head = "^.+\\."; labels.removeFirst() }
        let body = labels.map { $0 == "*" ? "[^.]+" : NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "\\.")
        return filterItem(item, name: name, rule: "DOMAIN-REGEX," + head + body + "$")
    }

     
     
     
    static func realIP(_ input: Input) -> [Mapped] {
        var items: [OrderedJSON] = []
        var out: [Mapped] = []
         
         
         
        var wildcards: [String] = []
        for item in input.items {
            guard let made = fakeIPFilterItem(surge: item) else {
                out.append(.itemLeftOut(item, .invalidHost(item)))
                continue
            }
            var kept = made
            if case .object(let pairs) = made, !pairs.contains(where: { $0.key == "name" }),
               case .string(let rule)? = pairs.first(where: { $0.key == "rule" })?.value {
                wildcards.append(rule)
                 
                kept = .object(pairs + [("set", .scalar("true"))])
            }
            if !items.contains(kept) { items.append(kept) }
        }
        guard !items.isEmpty else { return out.isEmpty ? [.ignored(.unreadableLine)] : out }
        if !wildcards.isEmpty {
            let set = AdBlockRuleSet(url: nil, inline: wildcards, kind: .provider(behavior: "classical", format: "inline"),
                                     policy: .builtIn("DIRECT"), params: [], interval: nil, origin: input.origin, name: realIPSetName)
            items.append(.object([("item", .string("rule-set")), ("name", .string("rule-set:" + set.reference))]))
            out.append(.ruleSets([set]))
        }
        return [.edits([input.edit(["dns", "fake-ip-filter"], input.listOperation, .array(items), condition: .fakeIPFilter)])] + out
    }

     
    static let realIPSetName = "real-ip"

     
     
    static func route(_ item: String) -> String? {
        let parts = item.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count <= 2, let address = AdBlockIPLiteral(String(parts[0])) else { return nil }
        let most = address.isIPv6 ? 128 : 32
        guard parts.count == 2 else { return address.canonical + "/\(most)" }
        guard let prefix = Int(parts[1]), (0...most).contains(prefix), parts[1].allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return address.canonical + "/\(prefix)"
    }

     
     
     
     
     
     
     
     
     
    static func dnsServer(_ item: String, kind: ServerKind) -> String? {
        var text = unquoted(item)
        if let hash = text.firstIndex(of: "#") { text = String(text[..<hash]) }
        text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, AdBlockYAMLText.isOneLine(text), !text.contains(" ") else { return nil }
        let lowered = text.lowercased()
        if ["system", "syslib", "force-syslib"].contains(lowered) { return kind == .any ? "system" : nil }
        var h3 = kind == .doh3
        if lowered.hasPrefix("h3://") {
            text = "https://" + text.dropFirst(5)
            h3 = true
        } else if !lowered.contains("://") {
            switch kind {
            case .doh, .doh3: text = "https://" + text
            case .doq: text = "quic://" + text
            case .any, .encrypted:
                if kind == .encrypted { return nil }
                return plainServer(text)
            }
        }
        guard let components = URLComponents(string: text), let scheme = components.scheme?.lowercased(),
              ["udp", "tcp", "tls", "https", "quic"].contains(scheme), !(components.host ?? "").isEmpty else { return nil }
        if kind == .encrypted, !["tls", "https", "quic"].contains(scheme) { return nil }
        return h3 && scheme == "https" ? text + "#h3=true" : text
    }

     
    private static func plainServer(_ text: String) -> String? {
        if AdBlockIPLiteral(text) != nil { return text }
        if text.hasPrefix("["), let close = text.firstIndex(of: "]"), AdBlockIPLiteral(String(text[text.index(after: text.startIndex)..<close]))?.isIPv6 == true {
            let rest = text[text.index(after: close)...]
            guard rest.isEmpty || (rest.hasPrefix(":") && Int(rest.dropFirst()).map { (1...65_535).contains($0) } == true) else { return nil }
            return text
        }
        if let colon = text.lastIndex(of: ":"), text.filter({ $0 == ":" }).count == 1, AdBlockIPLiteral(String(text[..<colon])) != nil,
           Int(text[text.index(after: colon)...]).map({ (1...65_535).contains($0) }) == true {
            return text
        }
        return nil
    }

    static func isEncrypted(_ server: String) -> Bool {
        let lowered = server.lowercased()
        return lowered.hasPrefix("https://") || lowered.hasPrefix("tls://") || lowered.hasPrefix("quic://")
    }

     

     
     
     
     
     
     
    static func skipProxy(_ input: Input) -> [Mapped] {
        directAndUntouched(input, items: input.items)
    }

     
     
    static func bypassTun(_ input: Input) -> [Mapped] {
        var routes: [OrderedJSON] = []
        var names: [String] = []
        for item in input.items {
            if let written = route(item) { routes.append(.string(written)) } else { names.append(item) }
        }
        var out: [Mapped] = []
        if !routes.isEmpty { out.append(.edits([input.edit(["tun", "route-exclude-address"], .append, .array(routes))])) }
        if !names.isEmpty { out += directAndUntouched(input, items: names) }
        return out.isEmpty ? [.ignored(.unreadableLine)] : out
    }

    private static func directAndUntouched(_ input: Input, items: [String]) -> [Mapped] {
        var rules: [AdBlockRoutingRule] = []
        var exclusions: [AdBlockHostEntry] = []
        var out: [Mapped] = []
        let direct = AdBlockRulePolicy.builtIn("DIRECT")
        for item in items {
            if let range = route(item) {
                let type = range.contains(":") ? "IP-CIDR6" : "IP-CIDR"
                rules.append(AdBlockRoutingRule(head: "\(type),\(range)", policy: direct, params: ["no-resolve"], origin: input.origin))
                continue
            }
            let name = item.lowercased()
            guard let entry = AdBlockHostList.entry(name), !entry.excluded, case .name(let pattern) = entry.pattern,
                  entry.port == .standard, AdBlockHostList.isHostName(pattern) else {
                out.append(.itemLeftOut(item, .invalidHost(item)))
                continue
            }
            if pattern.hasPrefix("*."), !pattern.dropFirst(2).contains("*"), !pattern.contains("?"), pattern.count > 2 {
                rules.append(AdBlockRoutingRule(head: "DOMAIN-SUFFIX," + pattern.dropFirst(2), policy: direct, origin: input.origin))
            } else if pattern.contains("*") || pattern.contains("?") {
                rules.append(AdBlockRoutingRule(head: "DOMAIN-WILDCARD," + pattern, policy: direct, origin: input.origin))
            } else {
                rules.append(AdBlockRoutingRule(head: "DOMAIN," + pattern, policy: direct, origin: input.origin))
            }
            exclusions.append(AdBlockHostEntry(excluded: true, pattern: .name(pattern), port: .all))
        }
        var mapped: [Mapped] = []
        if !rules.isEmpty { mapped.append(.rules(rules)) }
        if !exclusions.isEmpty { mapped.append(.mitmExclusions(exclusions)) }
        return mapped.isEmpty && out.isEmpty ? [.ignored(.unreadableLine)] : mapped + out
    }

     
     
     
     
     
     
    static func dnsServer(_ input: Input) -> [Mapped] {
        var plain: [OrderedJSON] = []
        var encrypted: [OrderedJSON] = []
        var out: [Mapped] = []
        for item in input.items {
            guard let server = dnsServer(item, kind: .any) else {
                out.append(.itemLeftOut(item, .invalidHost(item)))
                continue
            }
            if isEncrypted(server) {
                if !encrypted.contains(.string(server)) { encrypted.append(.string(server)) }
            } else if !plain.contains(.string(server)) {
                plain.append(.string(server))
            }
        }
        var edits: [AdBlockConfigurationEdit] = []
        if !encrypted.isEmpty { edits.append(input.edit(["dns", "nameserver"], input.listOperation, .array(encrypted))) }
        if !plain.isEmpty {
            edits.append(input.edit(["dns", "nameserver"], input.listOperation, .array(plain), condition: .plainNameserver))
        }
        return edits.isEmpty ? (out.isEmpty ? [.ignored(.unreadableLine)] : out) : [.edits(edits)] + out
    }

     
     
     
     
    static func fallbackDNSServer(_ input: Input) -> [Mapped] {
        let items = input.items.isEmpty ? ["system"] : input.items
        var servers: [OrderedJSON] = []
        var out: [Mapped] = []
        for item in items {
            if let server = dnsServer(item, kind: .any) { servers.append(.string(server)) } else { out.append(.itemLeftOut(item, .invalidHost(item))) }
        }
        guard !servers.isEmpty else { return out.isEmpty ? [.ignored(.unreadableLine)] : out }
        return [.edits([input.edit(["dns", "nameserver"], .append, .array(servers))])] + out
    }

     
     
    static func dnsDirectSystem(_ input: Input) -> [Mapped] {
        guard let on = boolean(input.value) else { return [.ignored(.unreadableLine)] }
        guard on else { return [.alreadyInEffect] }
        return [.edits([input.edit(["dns", "direct-nameserver"], .replace, .array([.string("system")]))])]
    }

     
     
     
     
     
     
     
    static func followOutboundMode(_ input: Input) -> [Mapped] {
        guard let on = boolean(input.value) else { return [.ignored(.unreadableLine)] }
        guard on else { return [.alreadyInEffect] }
        let source = OrderedJSON.array([.string("dns"), .string("nameserver")])
        return [.edits([input.edit(["dns", "respect-rules"], .replace, .scalar("true")),
                        input.edit(["dns", "proxy-server-nameserver"], .copyIfAbsent, source)])]
    }

     
     
    static func skipCertVerification(_ input: Input) -> [Mapped] {
        guard let on = boolean(input.value) else { return [.ignored(.unreadableLine)] }
        guard on else { return [.alreadyInEffect] }
        return [.edits([input.edit(["dns", "nameserver"], .serverParameter, .string("skip-cert-verify=true"))])]
    }

     
     
    static func hijackDNS(_ input: Input) -> [Mapped] {
        var values: [OrderedJSON] = []
        var out: [Mapped] = []
        for item in input.items {
            var host = item
            var port = "53"
            if let colon = item.lastIndex(of: ":"), item.filter({ $0 == ":" }).count == 1 {
                host = String(item[..<colon])
                port = String(item[item.index(after: colon)...])
            }
            guard let number = Int(port), (1...65_535).contains(number), host == "*" || AdBlockIPLiteral(host) != nil else {
                out.append(.itemLeftOut(item, .invalidHost(item)))
                continue
            }
            values.append(.string((host == "*" ? "any" : host) + ":\(number)"))
        }
        guard !values.isEmpty else { return out.isEmpty ? [.ignored(.unreadableLine)] : out }
        return [.edits([input.edit(["tun", "dns-hijack"], input.directive == .insert ? .prepend : .append, .array(values))])] + out
    }

     
     
     
    static func ipv6(_ input: Input) -> [Mapped] {
        guard let on = boolean(input.value) else { return [.ignored(.unreadableLine)] }
        if on { return [.edits([input.edit(["ipv6"], .replace, .scalar("true"))])] }
        return [.edits([input.edit(["ipv6"], .replace, .scalar("false")), input.edit(["dns", "ipv6"], .replace, .scalar("false"))])]
    }

     
     
     
     
     
     
    static func ipv6VIF(_ input: Input) -> [Mapped] {
        let value = input.value.lowercased()
        if input.family == .loon {
            guard ["off", "auto", "always", "on", "true", "false"].contains(value) else { return [.ignored(.unreadableLine)] }
            guard value == "off" || value == "false" else { return [.alreadyInEffect] }
            return [.edits([input.edit(["ipv6"], .replace, .scalar("false")), input.edit(["dns", "ipv6"], .replace, .scalar("false"))])]
        }
        switch value {
        case "disabled", "off", "false": return [.edits([input.edit(["tun", "inet6-address"], .replace, .array([]))])]
        case "auto", "always", "on", "true": return [.alreadyInEffect]
        default: return [.ignored(.unreadableLine)]
        }
    }

     
     
    static func rawTCPHosts(_ input: Input) -> [Mapped] {
        var exclusions: [AdBlockHostEntry] = []
        var out: [Mapped] = []
        for item in input.items {
            guard let entry = AdBlockHostList.entry(item) else {
                out.append(.itemLeftOut(item, .invalidHost(item)))
                continue
            }
             
            guard !entry.excluded else { continue }
            exclusions.append(AdBlockHostEntry(excluded: true, pattern: entry.pattern, port: entry.port == .standard ? .all : entry.port))
        }
        guard !exclusions.isEmpty else { return out.isEmpty ? [.ignored(.unreadableLine)] : out }
        return [.mitmExclusions(exclusions), .plainExclusions(exclusions)] + out
    }

     
    static func rawTCPKeywords(_ input: Input) -> [Mapped] {
        var exclusions: [AdBlockHostEntry] = []
        var out: [Mapped] = []
        for item in input.items {
            guard let entry = AdBlockHostList.entry("*" + item.lowercased() + "*"), case .name = entry.pattern else {
                out.append(.itemLeftOut(item, .invalidHost(item)))
                continue
            }
            exclusions.append(AdBlockHostEntry(excluded: true, pattern: entry.pattern, port: .all))
        }
        guard !exclusions.isEmpty else { return out.isEmpty ? [.ignored(.unreadableLine)] : out }
        return [.mitmExclusions(exclusions), .plainExclusions(exclusions)] + out
    }

     
    static func simpleHostnames(_ input: Input) -> [Mapped] {
        guard let on = boolean(input.value) else { return [.ignored(.unreadableLine)] }
        guard on else { return [.alreadyInEffect] }
        return [.rules([AdBlockRoutingRule(head: "DOMAIN-REGEX,^[^.]+$", policy: .builtIn("DIRECT"), origin: input.origin)])]
    }

     
     
     
     
     
     
     
    static func blockQUIC(_ input: Input) -> [Mapped] {
        switch input.value.lowercased() {
        case "all-proxy":
            return [.edits([input.edit(["x-clash-block-quic"], .replace, .string("all-proxy"))])]
        case "all", "true":
            return [.edits([input.edit(["x-clash-block-quic"], .replace, .string("all"))])]
        case "per-policy", "always-allow", "false":
            return [.alreadyInEffect]
        default:
            return [.ignored(.unreadableLine)]
        }
    }

     
     
     
    static func icmpAutoReply(_ input: Input) -> [Mapped] {
        guard let on = boolean(input.value) else { return [.ignored(.unreadableLine)] }
        return on ? [.alreadyInEffect] : [.ignored(.platformCannot(.pingForwarding))]
    }

     
    static func udpUnsupported(_ input: Input) -> [Mapped] {
        let value = input.value.uppercased()
        guard ["REJECT", "DIRECT"].contains(value) else { return [.ignored(.unreadableLine)] }
        return [.edits([input.edit(["x-clash-udp-unsupported"], .replace, .string(value))])]
    }

     
     
    static func allowDNSAll(_ input: Input) -> [Mapped] {
        guard let on = boolean(input.value) else { return [.ignored(.unreadableLine)] }
        return on ? [.alreadyInEffect] : [.edits([input.edit(["dns", "x-clash-answer-other-types"], .replace, .scalar("false"))])]
    }

     
    static func errorPageForReject(_ input: Input) -> [Mapped] {
        guard let on = boolean(input.value) else { return [.ignored(.unreadableLine)] }
        return on ? [.edits([input.edit(["x-clash-show-error-page-for-reject"], .replace, .scalar("true"))])] : [.alreadyInEffect]
    }

     
     
     
    static func alwaysRejectURLRewrite(_ input: Input) -> [Mapped] {
        guard let on = boolean(input.value) else { return [.ignored(.unreadableLine)] }
        return on ? [.edits([input.edit(["x-clash-every-mode-rules"], .engineRoute, .scalar("true"))])] : [.alreadyInEffect]
    }

     
     
    static func includeCellularServices(_ input: Input) -> [Mapped] {
        guard input.platform != .mac else { return [.ignored(.platformCannot(.cellularServices))] }
        guard let on = boolean(input.value) else { return [.ignored(.unreadableLine)] }
        return [.device([AdBlockDeviceSetting(key: .includeCellularServices, value: on ? "true" : "false", origin: input.origin)]),
                .changes([AdBlockModuleChange(key: .includeCellularServices, value: input.value, origin: input.origin)])]
    }

     
     
     
     
     
    static func compatibilityMode(_ input: Input) -> [Mapped] {
        switch input.value {
        case "0": return [.alreadyInEffect]
        case "3", "5":
            return [.device([AdBlockDeviceSetting(key: .homeKitCompatibility, value: input.value == "5" ? "true" : "false",
                                                  origin: input.origin)])]
        case "1", "2", "4": return [.ignored(.platformCannot(.systemProxy))]
        default: return [.ignored(.unreadableLine)]
        }
    }

     
     
    static func logLevel(_ input: Input) -> [Mapped] {
        let level: String
        switch input.value.lowercased() {
        case "verbose": level = "debug"
        case "info", "notify": level = "info"
        case "warning": level = "warning"
        default: return [.ignored(.unreadableLine)]
        }
        return [.edits([input.edit(["log-level"], .replace, .string(level))])]
    }

     
    private static func controller(_ value: String) -> (secret: String?, address: String)? {
        var text = unquoted(value)
        var secret: String?
        if let at = text.lastIndex(of: "@") {
            secret = String(text[..<at])
            text = String(text[text.index(after: at)...])
        }
        guard let colon = text.lastIndex(of: ":"), let port = Int(text[text.index(after: colon)...]), (1...65_535).contains(port),
              AdBlockYAMLText.isOneLine(text), !text.contains(" ") else { return nil }
        let host = String(text[..<colon])
         
         
        guard host.isEmpty || AdBlockIPLiteral(host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))) != nil
                || (AdBlockHostList.isHostName(host.lowercased()) && !host.contains("*") && !host.contains("?") && trieHolds(host))
        else { return nil }
        if let secret, !AdBlockYAMLText.isOneLine(secret) { return nil }
        return (secret, text)
    }

     
     
     
    static func httpAPI(_ input: Input) -> [Mapped] {
        guard let written = controller(input.value) else { return [.ignored(.unreadableLine)] }
        var edits = [input.edit(["external-controller"], .replace, .string(written.address))]
        if let secret = written.secret { edits.append(input.edit(["secret"], .replace, .string(secret))) }
        return [.edits(edits)]
    }

     
     
     
    static func externalControllerAccess(_ input: Input) -> [Mapped] {
        httpAPI(input)
    }

     
     
    static func httpAPITLS(_ input: Input) -> [Mapped] {
        guard let on = boolean(input.value) else { return [.ignored(.unreadableLine)] }
        return on ? [.ignored(.notApplicable(.clashCannotDoThis))] : [.alreadyInEffect]
    }

     
     
     
     
     
    static func listen(_ input: Input, port key: String) -> [Mapped] {
        var text = unquoted(input.value)
        if let at = text.lastIndex(of: "@") { text = String(text[text.index(after: at)...]) }
        var host = text
        var port = key == "port" ? 6152 : 6153
        if let colon = text.lastIndex(of: ":"), !text.hasSuffix("]") {
            guard let written = Int(text[text.index(after: colon)...]), (1...65_535).contains(written) else { return [.ignored(.unreadableLine)] }
            port = written
            host = String(text[..<colon])
        }
        host = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        var edits = [input.edit([key], .replace, .scalar(String(port)))]
        switch host {
        case "", "127.0.0.1", "::1", "localhost":
            break
        case "0.0.0.0", "::", "*":
            edits.append(input.edit(["allow-lan"], .replace, .scalar("true")))
        default:
            guard AdBlockIPLiteral(host) != nil else { return [.ignored(.unreadableLine)] }
            edits.append(input.edit(["allow-lan"], .replace, .scalar("true")))
        }
        return [.edits(edits)]
    }

     

     
     
     
    static func ipRewrite(_ line: String, family: AdBlockModuleFormat, origin: AdBlockLineOrigin) -> [Mapped] {
        guard let equals = line.firstIndex(of: "=") else { return [.ignored(.unreadableLine)] }
        let target = line[..<equals].trimmingCharacters(in: .whitespaces)
        let action = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces).lowercased()
        guard ["reflect", "reject", "drop"].contains(action) else { return [.ignored(.unreadableLine)] }
        if family == .loon {
            guard let address = AdBlockIPLiteral(target), !address.isIPv6 else { return [.ignored(.unreadableLine)] }
        } else {
            guard route(target) != nil else { return [.ignored(.unreadableLine)] }
        }
        let input = Input(key: "ip-rewrite", directive: nil, value: "", family: family, origin: origin)
        return [.edits([input.edit(["x-clash-ip-rewrite"], .append, .array([.string("\(target) = \(action)")]))])]
    }

     
    static let maximumIPRewriteLines = 256

     
     
     
     
     
     
     
     
     
    static func wireGuard(_ line: String, node: String, origin: AdBlockLineOrigin) -> [Mapped] {
        guard let equals = line.firstIndex(of: "=") else { return [.ignored(.unreadableLine)] }
        let key = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
        let value = unquoted(String(line[line.index(after: equals)...]))
        var fields: [(key: String, value: OrderedJSON)] = []
        switch key {
        case "private-key":
            guard isWireGuardKey(value) else { return [.ignored(.unreadableLine)] }
            fields = [("private-key", .string(value))]
        case "self-ip":
            guard let address = AdBlockIPLiteral(value), !address.isIPv6 else { return [.ignored(.unreadableLine)] }
            fields = [("ip", .string(address.canonical))]
        case "self-ip-v6":
            guard let address = AdBlockIPLiteral(value), address.isIPv6 else { return [.ignored(.unreadableLine)] }
            fields = [("ipv6", .string(address.canonical))]
        case "dns-server":
            let servers = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard !servers.isEmpty, servers.allSatisfy({ AdBlockIPLiteral($0) != nil }) else { return [.ignored(.unreadableLine)] }
            fields = [("dns", .array(servers.map(OrderedJSON.string))), ("remote-dns-resolve", .scalar("true"))]
        case "mtu":
            guard let mtu = scalar(value, .number) else { return [.ignored(.unreadableLine)] }
            fields = [("mtu", mtu)]
        case "peer":
            guard let peer = wireGuardPeer(value) else { return [.ignored(.unreadableLine)] }
            fields = peer
        default:
            return [.ignored(.settingNotSupported(key))]
        }
        guard !node.isEmpty, fields.allSatisfy({ AdBlockYAMLText.isOneLine($0.value.serialized()) }) else { return [.ignored(.unreadableLine)] }
        let input = Input(key: key, directive: nil, value: value, family: .surge, origin: origin)
        return [.edits([input.edit(["proxies", node], .merge, .object(fields))])]
    }

     
    static func isWireGuardKey(_ text: String) -> Bool {
        guard text.utf8.count == 44, let data = Data(base64Encoded: text) else { return false }
        return data.count == 32
    }

     
     
    static func wireGuardPeer(_ value: String) -> [(key: String, value: OrderedJSON)]? {
        var text = value.trimmingCharacters(in: .whitespaces)
        guard text.hasPrefix("("), text.hasSuffix(")") else { return nil }
        text = String(text.dropFirst().dropLast())
        var parts: [String] = []
        var current = ""
        var quoted = false
        for character in text {
            if character == "\"" { quoted.toggle(); continue }
            if character == ",", !quoted { parts.append(current); current = ""; continue }
            current.append(character)
        }
        parts.append(current)
        var out: [(key: String, value: OrderedJSON)] = []
        for part in parts {
            guard let equals = part.firstIndex(of: "=") else { continue }
            let key = part[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            let value = part[part.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            switch key {
            case "public-key":
                guard isWireGuardKey(value) else { return nil }
                out.append(("public-key", .string(value)))
            case "preshared-key":
                guard isWireGuardKey(value) else { return nil }
                out.append(("pre-shared-key", .string(value)))
            case "allowed-ips":
                let ranges = value.split(separator: ",").map { route($0.trimmingCharacters(in: .whitespaces)) }
                guard !ranges.isEmpty, !ranges.contains(nil) else { return nil }
                out.append(("allowed-ips", .array(ranges.compactMap { $0.map(OrderedJSON.string) })))
            case "endpoint":
                guard let colon = value.lastIndex(of: ":"), let port = Int(value[value.index(after: colon)...]), (1...65_535).contains(port) else { return nil }
                let host = String(value[..<colon]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                guard AdBlockIPLiteral(host) != nil || (AdBlockHostList.isHostName(host.lowercased()) && trieHolds(host)) else { return nil }
                out.append(("server", .string(host)))
                out.append(("port", .scalar(String(port))))
            case "keepalive":
                guard let seconds = Int(value), (0...65_535).contains(seconds) else { return nil }
                out.append(("persistent-keepalive", .scalar(String(seconds))))
            case "client-id":
                let bytes = value.split(separator: "/").compactMap { Int($0) }
                guard bytes.count == 3, bytes.allSatisfy({ (0...255).contains($0) }) else { return nil }
                out.append(("reserved", .array(bytes.map { .scalar(String($0)) })))
            default:
                continue
            }
        }
        return out.isEmpty ? nil : out
    }

     
    static let mtprotoListener = "module-mtproto"
    static let snellListener = "module-snell"

     
     
     
    static let listenerDefaultAddress = "127.0.0.1"

     
     
     
     
     
    static func mtproto(_ line: String, origin: AdBlockLineOrigin, platform: AdBlockPlatform = .current) -> [Mapped] {
        guard let equals = line.firstIndex(of: "=") else { return [.ignored(.unreadableLine)] }
        let key = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
        let value = unquoted(String(line[line.index(after: equals)...]))
        var fields: [(key: String, value: OrderedJSON)] = [("type", .string("mtproto"))]
        var change: AdBlockModuleChange?
        switch key {
        case "port":
            guard let port = scalar(value, .number) else { return [.ignored(.unreadableLine)] }
            fields.append(("port", port))
            change = AdBlockModuleChange(key: .listener, value: value, origin: origin)
        case "secret":
            let hex = value.lowercased()
            let body = hex.hasPrefix("dd") && hex.count == 34 ? String(hex.dropFirst(2)) : hex
            guard body.count == 32, body.allSatisfy({ $0.isHexDigit && $0.isASCII }) else { return [.ignored(.unreadableLine)] }
            fields.append(("secret", .string(hex)))
        case "ipv6":
            guard let on = boolean(value) else { return [.ignored(.unreadableLine)] }
            fields.append(("ipv6", .scalar(on ? "true" : "false")))
        case "interface":
             
            guard platform == .mac else { return [.alreadyInEffect] }
            guard let address = listenAddress(value) else { return [.ignored(.unreadableLine)] }
            fields.append(("listen", .string(address)))
            change = AdBlockModuleChange(key: .listener, value: value, origin: origin)
        case "dc-config-url":
             
            return [.alreadyInEffect]
        default:
            return [.ignored(.settingNotSupported(key))]
        }
        let input = Input(key: key, directive: nil, value: value, family: .surge, origin: origin)
        return [.edits([input.edit(["listeners", mtprotoListener], .merge, .object(fields))])] + (change.map { [.changes([$0])] } ?? [])
    }

     
     
     
     
     
     
     
     
     
    static func snellServer(_ line: String, origin: AdBlockLineOrigin) -> [Mapped] {
        guard let equals = line.firstIndex(of: "=") else { return [.ignored(.unreadableLine)] }
        let key = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
        let value = unquoted(String(line[line.index(after: equals)...]))
        var fields: [(key: String, value: OrderedJSON)] = [("type", .string("snell"))]
        var change: AdBlockModuleChange?
        switch key {
        case "port":
            guard let port = scalar(value, .number) else { return [.ignored(.unreadableLine)] }
            fields.append(("port", port))
            change = AdBlockModuleChange(key: .listener, value: value, origin: origin)
        case "psk":
            guard !value.isEmpty, AdBlockYAMLText.isOneLine(value) else { return [.ignored(.unreadableLine)] }
            fields.append(("psk", .string(value)))
        case "version":
            switch value {
            case "1": fields.append(("version", .scalar("1")))
            case "6": fields += [("version", .scalar("6")), ("udp", .scalar("true"))]
            default: return [.ignored(.unreadableLine)]
            }
        case "interface":
            guard let address = listenAddress(value) else { return [.ignored(.unreadableLine)] }
            fields.append(("listen", .string(address)))
            change = AdBlockModuleChange(key: .listener, value: value, origin: origin)
        case "listen":
             
            var host = value
            if let colon = value.lastIndex(of: ":"), value.filter({ $0 == ":" }).count == 1 || value.hasPrefix("[") {
                guard let port = scalar(String(value[value.index(after: colon)...]), .number) else { return [.ignored(.unreadableLine)] }
                fields.append(("port", port))
                host = String(value[..<colon])
            }
            guard let address = listenAddress(host) else { return [.ignored(.unreadableLine)] }
            fields.append(("listen", .string(address)))
            change = AdBlockModuleChange(key: .listener, value: value, origin: origin)
        default:
            return [.ignored(.settingNotSupported(key))]
        }
        let input = Input(key: key, directive: nil, value: value, family: .surge, origin: origin)
        return [.edits([input.edit(["listeners", snellListener], .merge, .object(fields))])] + (change.map { [.changes([$0])] } ?? [])
    }

     
    private static func listenAddress(_ text: String) -> String? {
        let host = text.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
        if host == "*" { return "0.0.0.0" }
        return AdBlockIPLiteral(host)?.canonical
    }

     
    static func opensToOtherDevices(_ address: String) -> Bool {
        !["127.0.0.1", "::1", "localhost", ""].contains(address)
    }

     

     
     
     
    static let stashKeys: Set<String> = ["dns", "hosts", "proxy-hosts", "ipv6", "proxy-groups", "mode", "log-level",
                                         "external-controller", "secret", "allow-lan", "bind-address", "port", "socks-port",
                                         "mixed-port"]
     
     
    static let stashMisplacedKeys: Set<String> = ["mitm", "url-rewrite", "rewrite", "header-rewrite", "body-rewrite", "script",
                                                  "scripts", "force-http-engine"]
     
    static let stashTunnelDNSKeys: Set<String> = ["enhanced-mode", "listen"]

     
     
     
     
     
    static let stashScalars: [String: Value] = [
        "mode": .choice(["rule", "global", "direct"]), "log-level": .choice(["silent", "error", "warning", "info", "debug"]),
        "ipv6": .bool, "allow-lan": .bool, "port": .number, "socks-port": .number, "mixed-port": .number, "secret": .text,
    ]

     
     
    static func stashScalar(_ key: String, _ value: OrderedJSON) -> OrderedJSON? {
        switch key {
        case "external-controller":
            guard case .string(let text) = value, !text.contains("@"), let written = controller(text) else { return nil }
            return .string(written.address)
        case "bind-address":
            guard case .string(let text) = value, text == "*" || AdBlockIPLiteral(text) != nil else { return nil }
            return .string(text)
        default:
            break
        }
        guard let kind = stashScalars[key] else { return nil }
        switch (kind, value) {
        case (.bool, .scalar(let token)) where token == "true" || token == "false": return value
        case (.number, .scalar(let token)): return scalar(token, .number)
        case (.choice, .string(let text)), (.choice, .scalar(let text)): return scalar(text, kind)
         
        case (.text, .string(let text)), (.text, .scalar(let text)) where text != "null": return scalar(text, .text)
        default: return nil
        }
    }

     
    static func writtenText(_ value: OrderedJSON) -> String {
        switch value {
        case .string(let text), .scalar(let text): return text
        default: return value.serialized()
        }
    }

     
    private static let stashDNSBools: Set<String> = ["enable", "ipv6", "prefer-h3", "use-hosts", "use-system-hosts", "respect-rules",
                                                     "direct-nameserver-follow-policy"]
    private static let stashDNSServerLists: Set<String> = ["nameserver", "fallback", "default-nameserver", "proxy-server-nameserver",
                                                           "direct-nameserver"]

     
     
     
    static func isKernelServer(_ text: String) -> Bool {
        var base = text.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty, AdBlockYAMLText.isOneLine(base) else { return false }
        if let hash = base.firstIndex(of: "#") { base = String(base[..<hash]) }
        let lowered = base.lowercased()
        if lowered == "system" || lowered == "system://" { return true }
        if let range = lowered.range(of: "://") {
            guard ["udp", "tcp", "tls", "https", "quic", "dhcp", "rcode"].contains(String(lowered[..<range.lowerBound])) else { return false }
            return !lowered[range.upperBound...].isEmpty && !lowered.contains(" ")
        }
        return plainServer(base) != nil
    }

     
     
     
    static func policyKeyHolds(_ key: String) -> Bool {
        let names = key.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        return !names.isEmpty && names.allSatisfy { name in
            if name.hasPrefix("geosite:") { return name.count > "geosite:".count }
            return !name.hasPrefix("rule-set:") && !name.contains("?") && AdBlockYAMLText.isOneLine(name) && trieHolds(name)
        }
    }

     
     
     
     
    private static func stashDNSChild(_ child: String, _ value: OrderedJSON, siblings: [(key: String, value: OrderedJSON)],
                                      ruleProviders: Set<String> = [], origin: AdBlockLineOrigin) -> (kept: OrderedJSON?, out: [Mapped]) {
        func servers(_ value: OrderedJSON) -> Bool {
            switch value {
            case .string(let text): return isKernelServer(text)
            case .array(let items):
                return !items.isEmpty && items.allSatisfy { if case .string(let text) = $0 { return isKernelServer(text) } else { return false } }
            default: return false
            }
        }
        let whole: [Mapped] = [.itemLeftOut("dns." + child, .unreadableLine)]
        switch child {
        case _ where stashDNSBools.contains(child):
            guard case .scalar(let token) = value, token == "true" || token == "false" else { return (nil, whole) }
            return (value, [])
        case _ where stashDNSServerLists.contains(child):
            guard case .array = value, servers(value) else { return (nil, whole) }
            return (value, [])
        case "fake-ip-filter-mode":
            guard let mode = scalar(writtenText(value), .choice(["blacklist", "whitelist", "rule"])) else { return (nil, whole) }
            return (mode, [])
        case "fake-ip-filter":
             
            guard case .array(let items) = value else { return (nil, whole) }
            let rules = siblings.first { $0.key == "fake-ip-filter-mode" }.map { writtenText($0.value).lowercased() == "rule" } ?? false
            var kept: [OrderedJSON] = []
            var out: [Mapped] = []
            for item in items {
                let text = writtenText(item)
                let holds: Bool
                if case .string = item {
                    holds = rules ? isFakeIPRuleLine(text) : fakeIPFilterItem(kernel: text) != nil
                } else {
                    holds = false
                }
                if holds { kept.append(item) } else { out.append(.itemLeftOut(text, .invalidHost(text))) }
            }
            return (kept.isEmpty ? nil : .array(kept), out)
        case "nameserver-policy":
            guard case .object(let entries) = value else { return (nil, whole) }
            var kept: [(key: String, value: OrderedJSON)] = []
            var out: [Mapped] = []
            var sets: [AdBlockRuleSet] = []
            for entry in entries {
                let lowered = entry.key.lowercased()
                if lowered.hasPrefix("rule-set:") {
                     
                     
                     
                    let names = entry.key.dropFirst("rule-set:".count).split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                    guard servers(entry.value), !names.isEmpty, names.allSatisfy(ruleProviders.contains) else {
                        out.append(.itemLeftOut(entry.key, .notApplicable(.doesNotApply)))
                        continue
                    }
                    for name in names { kept.append(("rule-set:RULE-SET," + name, entry.value)) }
                } else if policyKeyHolds(entry.key), servers(entry.value) {
                    kept.append(entry)
                } else if servers(entry.value), !lowered.contains(","), !lowered.hasPrefix("geosite:"),
                          let rule = AdBlockHostMappingSyntax.stashGlobRule(entry.key) {
                     
                     
                    let name = AdBlockHostMappingSyntax.globSetName([entry.value.serialized()])
                    let set = AdBlockRuleSet(url: nil, inline: [rule], kind: .provider(behavior: "classical", format: "inline"),
                                             policy: .builtIn("DIRECT"), params: [], interval: nil, origin: origin, name: name)
                    AdBlockRuleSetSyntax.add(set, to: &sets)
                    let key = "rule-set:" + set.reference
                    if !kept.contains(where: { $0.key == key }) { kept.append((key, entry.value)) }
                } else {
                    out.append(.itemLeftOut(entry.key, .invalidHost(entry.key)))
                }
            }
            if !sets.isEmpty { out.append(.ruleSets(sets)) }
            return (kept.isEmpty ? nil : .object(kept), out)
        case "fake-ip-range", "fake-ip-range6":
            guard case .string(let text) = value, text.contains("/"), route(text) != nil else { return (nil, whole) }
            return (value, [])
        default:
             
            return (value, [])
        }
    }

     
    private static func isFakeIPRuleLine(_ text: String) -> Bool {
        let fields = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        return fields.count >= 2 && ["real-ip", "fake-ip"].contains(fields.last!) && AdBlockYAMLText.isOneLine(text)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    static func stash(_ key: String, value: OrderedJSON, directives: [[String]: AdBlockEditOperation],
                      origin: AdBlockLineOrigin, ruleProviders: Set<String> = []) -> [Mapped] {
        let input = Input(key: key, directive: nil, value: "", family: .stash, origin: origin)
        if stashMisplacedKeys.contains(key) { return [.ignored(.noEffectInItsOwnApp(.noEffectThereEither))] }
        switch key {
        case "hosts":
            guard case .object(let pairs) = value else { return [.ignored(.unreadableLine)] }
            var out: [Mapped] = []
             
            if directives[[key]] == .replace { out.append(.edits([input.edit(["hosts"], .replace, .object([]))])) }
            var mappings: [AdBlockHostMapping] = []
            for (name, target) in pairs {
                switch AdBlockHostMappingSyntax.stash(name, target, origin: origin) {
                case .success(let mapping): mappings.append(mapping)
                case .failure(let reason): out.append(.itemLeftOut(name, reason))
                }
            }
            return (mappings.isEmpty ? [] : [.hosts(mappings)]) + out
        case "proxy-hosts":
            guard case .object(let pairs) = value else { return [.ignored(.unreadableLine)] }
            var kept: [(key: String, value: OrderedJSON)] = []
            var out: [Mapped] = []
            for (name, target) in pairs {
                switch AdBlockHostMappingSyntax.stash(name, target, origin: origin) {
                case .success(let mapping):
                    switch mapping.value {
                    case .addresses(let addresses):
                        kept.append((mapping.pattern, addresses.count == 1 ? .string(addresses[0]) : .array(addresses.map(OrderedJSON.string))))
                    case .name(let alias): kept.append((mapping.pattern, .string(alias)))
                    default: out.append(.itemLeftOut(name, .unreadableLine))
                    }
                case .failure(let reason): out.append(.itemLeftOut(name, reason))
                }
            }
            let replace = directives[[key]] == .replace
            guard !kept.isEmpty || replace else { return out.isEmpty ? [.ignored(.unreadableLine)] : out }
            return [.edits([input.edit(["x-clash-proxy-hosts"], replace ? .replace : .merge, .object(kept))])] + out
        case "proxy-groups":
            guard case .array(let groups) = value else { return [.ignored(.unreadableLine)] }
             
             
            if directives[["proxy-groups"]] == .replace { return [.ignored(.notApplicable(.clashCannotDoThis))] }
            return [.edits([input.edit(["proxy-groups"], directives[["proxy-groups"]] ?? .prepend, .array(groups))])]
        case "dns":
            guard case .object(let pairs) = value else { return [.ignored(.unreadableLine)] }
             
            let whole = directives[["dns"]] == .replace
            var kept: [(key: String, value: OrderedJSON)] = []
            var edits: [AdBlockConfigurationEdit] = []
            var out: [Mapped] = []
            for (child, childValue) in pairs {
                if stashTunnelDNSKeys.contains(child) {
                    out.append(.itemLeftOut("dns." + child, .setInClashSettings("dns." + child)))
                    continue
                }
                if child == "fake-ip-filter", !whole {
                     
                    guard case .array(let items) = childValue else {
                        out.append(.itemLeftOut("dns." + child, .unreadableLine))
                        continue
                    }
                    var made: [OrderedJSON] = []
                    for item in items {
                        let text = writtenText(item)
                        if case .string = item, let one = fakeIPFilterItem(kernel: text) { made.append(one) } else { out.append(.itemLeftOut(text, .invalidHost(text))) }
                    }
                    if !made.isEmpty {
                        let path = ["dns", "fake-ip-filter"]
                        edits.append(input.edit(path, directives[path] ?? .prepend, .array(made), condition: .fakeIPFilter))
                    }
                    continue
                }
                let checked = stashDNSChild(child, childValue, siblings: pairs, ruleProviders: ruleProviders, origin: origin)
                out += checked.out
                guard let childKept = checked.kept else { continue }
                if whole { kept.append((child, childKept)) } else { edits.append(stashEdit(input, ["dns", child], childKept, directives: directives)) }
            }
            if whole { edits = [input.edit(["dns"], .replace, .object(kept))] }
            return (edits.isEmpty ? [] : [.edits(edits)]) + out
        default:
            guard stashKeys.contains(key) else { return [.ignored(.sectionNotSupported(key))] }
             
            guard let checked = stashScalar(key, value) else { return [.ignored(.unreadableLine)] }
            var mapped: [Mapped] = [.edits([input.edit([key], .replace, checked)])]
            if let change = stashChangeKeys[key] {
                mapped.append(.changes([AdBlockModuleChange(key: change, value: writtenText(value), origin: origin)]))
            }
            return mapped
        }
    }

    private static func stashEdit(_ input: Input, _ path: [String], _ value: OrderedJSON,
                                  directives: [[String]: AdBlockEditOperation]) -> AdBlockConfigurationEdit {
        switch value {
        case .array: return input.edit(path, directives[path] ?? .prepend, value)
        case .object: return input.edit(path, directives[path] == .replace ? .replace : .merge, value)
        default: return input.edit(path, .replace, value)
        }
    }

     

     
     
    static func take(_ results: [Mapped], written: String, origin: AdBlockLineOrigin, key: String, into ir: inout AdBlockModuleIR) {
        for result in results {
            switch result {
            case .edits(let edits): ir.edits += edits
            case .rules(let rules): ir.routingRules += rules
             
            case .mitmExclusions(let entries):
                ir.mitmHostLines.append(AdBlockHostListLine(directive: .setting, entries: entries, origin: origin))
            case .plainExclusions(let entries):
                ir.forceHTTPEngineHostLines.append(AdBlockHostListLine(directive: .setting, entries: entries, origin: origin))
            case .hosts(let mappings): ir.hosts += mappings
            case .device(let settings): ir.deviceSettings += settings
            case .alreadyInEffect: ir.inEffect.append(AdBlockSettingInEffect(key: key, origin: origin))
            case .ignored(let reason): ir.ignored.append(AdBlockIgnoredEntry(text: written, reason: reason, origin: origin))
            case .itemLeftOut(let item, let reason): ir.ignored.append(AdBlockIgnoredEntry(text: item, reason: reason, origin: origin))
            case .changes(let changes): ir.changes += changes
            case .note(let sentence): ir.notes.append(AdBlockLineNote(sentence: sentence, origin: origin))
            case .ruleSets(let sets): for set in sets { AdBlockRuleSetSyntax.add(set, to: &ir.ruleSets) }
            }
        }
    }
}
