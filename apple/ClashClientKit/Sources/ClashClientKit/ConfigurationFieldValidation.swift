import Foundation

 
 
 
 
 
public enum ConfigurationFieldProblem: Equatable, Sendable {
    case notANumber
     
    case wholeNumber
     
    case belowMinimum(String)
    case aboveMaximum(String)
     
    case missingPort
    case portOutOfRange
     
    case unbracketedIPv6
     
     
    case bracketedIPv6Host
     
    case hostNotAnIP
     
    case hostWithPort
     
    case address
    case ipAddress
    case addressRange
    case domain
    case webAddress
    case portList
    case dnsServer
    case pattern
    case base64
     
    case standardBase64
    case hexadecimal
    case fingerprint
    case shortID
    case uuid
    case duration
     
    case spaces
     
     
    case hostsValue
}

 
 
 
 
 
public enum ConfigurationFieldValidation {
     
     
    public static func problem(_ text: String, field: ConfigurationField) -> ConfigurationFieldProblem? {
         
        if field.kind == .number { return problem(number: text, min: field.min, max: field.max, whole: true) }
        return problem(text, format: field.format, path: field.path, allowed: field.values ?? [])
    }

     
     
     
    static let trieDomainPaths: Set<String> = [
        "sniffer.skip-domain", "sniffer.force-domain", "dns.fake-ip-filter", "dns.fallback-filter.domain",
        "mitm.skip-domain",
    ]

     
    static let ipMatcherPaths: Set<String> = ["sniffer.skip-src-address", "sniffer.skip-dst-address", "mitm.skip-dst-address"]

     
     
    static let hostsEntryPath = "hosts.*"

     
     
     
    public static func readsSiblings(path: String) -> Bool { path == hostsEntryPath }

     
     
     
     
     
     
    private static func hostsProblem(_ value: String, siblings: [String]) -> ConfigurationFieldProblem? {
        let others = siblings.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if isIP(value) { return others.allSatisfy(isIP) ? nil : .hostsValue }
        guard others.isEmpty else { return .hostsValue }
        if value == "lan" { return nil }
        let labels = value.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .split(separator: ".", omittingEmptySubsequences: false)
        return labels.count >= 2 ? nil : .hostsValue
    }

     
     
     
    static func readsAsDNSServers(path: String) -> Bool {
        path.hasPrefix("proxies[") && leaf(of: path) == "dns"
    }

     
    static func namesAnIPMatcher(_ value: String) -> Bool {
        let lower = value.lowercased()
        for prefix in ["geoip:", "rule-set:"] where lower.hasPrefix(prefix) {
            return !value.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces).isEmpty
        }
        return false
    }

     
     
     
    public static func problem(_ text: String, format: ConfigurationFieldFormat?, path: String = "",
                               allowed: [String] = [], siblings: [String] = []) -> ConfigurationFieldProblem? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, var format, !allowed.contains(value) else { return nil }
        let leaf = Self.leaf(of: path)
        if readsAsDNSServers(path: path) { format = .dnsServer }
        switch format {
        case .text, .password, .path, .filter, .unrecognised: return nil
         
         
        case .regex: return patternProblem(value)
        case .portRange: return portListProblem(value)
        case .uuid: return uuidProblem(value, path: path)
         
         
        case .dnsServer: return dnsServerProblem(value)
        case .domain where trieDomainPaths.contains(path): return value.contains("/") ? .domain : nil
        case .cidr where ipMatcherPaths.contains(path) && namesAnIPMatcher(value): return nil
         
        case .ip where path == hostsEntryPath: return hostsProblem(value, siblings: siblings)
        default: break
        }
        if value.contains(where: \.isWhitespace) { return .spaces }
        switch format {
        case .ipPort: return leaf == "dns-hijack" ? dnsHijackProblem(value) : hostPortProblem(value)
        case .host: return hostProblem(value, leaf: leaf)
        case .domain: return value.contains("/") ? .domain : nil
        case .ip: return ipProblem(value, leaf: leaf)
        case .cidr: return cidrProblem(value, leaf: leaf)
        case .url: return urlProblem(value, path: path)
        case .base64: return base64Problem(value, path: path)
        case .hex: return hexProblem(value, leaf: leaf)
        case .duration: return durationProblem(value)
        case .text, .password, .path, .filter, .unrecognised, .regex, .portRange, .uuid, .dnsServer: return nil
        }
    }

     
     
    public static func problem(number text: String, min: Double?, max: Double?) -> ConfigurationFieldProblem? {
        problem(number: text, min: min, max: max, whole: false)
    }

     
     
     
     
    public static func problem(number text: String, min: Double?, max: Double?, whole: Bool) -> ConfigurationFieldProblem? {
        let value = text.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        guard ConfigurationFieldDraft.isNumber(value), let number = Double(value) else { return .notANumber }
        if whole, value.contains(where: { ".eE".contains($0) }) { return .wholeNumber }
        if let min, number < min { return .belowMinimum(plain(min)) }
        if let max, number > max { return .aboveMaximum(plain(max)) }
        return nil
    }

     

     
     
    public static func splitHostPort(_ text: String) -> (host: String, port: String)? {
        if text.hasPrefix("[") {
            guard let close = text.firstIndex(of: "]") else { return nil }
            let host = text[text.index(after: text.startIndex)..<close]
            let rest = text[text.index(after: close)...]
            guard rest.hasPrefix(":"), !host.contains("["), !rest.dropFirst().contains(":") else { return nil }
            return (String(host), String(rest.dropFirst()))
        }
        guard let colon = text.lastIndex(of: ":") else { return nil }
        let host = text[..<colon]
        guard !host.contains(":"), !host.contains("["), !host.contains("]") else { return nil }
        return (String(host), String(text[text.index(after: colon)...]))
    }

     
     
    public static func joinHostPort(host: String, port: String) -> String {
        var name = host
        if name.hasPrefix("["), name.hasSuffix("]") { name = String(name.dropFirst().dropLast()) }
        return name.contains(":") ? "[" + name + "]:" + port : name + ":" + port
    }

     
    private static func hostPortProblem(_ value: String) -> ConfigurationFieldProblem? {
        if value.contains("://") || value.contains("/") { return .address }
        if value.hasPrefix("["), !value.contains("]") { return .address }
        guard value.contains(":") else { return .missingPort }
        guard let (host, port) = splitHostPort(value) else {
            if value.hasPrefix("[") { return value.hasSuffix("]") ? .missingPort : .address }
            return .unbracketedIPv6
        }
        if isIP(value.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))) { return .missingPort }
        guard isPort(port, serviceNames: true) else { return .portOutOfRange }
        if host.contains(where: { "@?#".contains($0) }) { return .address }
        return nil
    }

     
     
    private static func dnsHijackProblem(_ value: String) -> ConfigurationFieldProblem? {
        var address = value
        if let scheme = address.range(of: "://") { address = String(address[scheme.upperBound...]) }
        if let any = address.range(of: "any") { address.replaceSubrange(any, with: "0.0.0.0") }
        guard address.contains(":") else { return .missingPort }
        guard let (host, port) = splitHostPort(address) else {
            return isIP(address) ? .missingPort : (address.hasPrefix("[") ? .address : .unbracketedIPv6)
        }
        guard isPort(port, serviceNames: false) else { return .portOutOfRange }
        return isIP(host) ? nil : .hostNotAnIP
    }

     
    private static func isPort(_ text: String, serviceNames: Bool) -> Bool {
        if !text.isEmpty, text.allSatisfy(\.isASCIIDigit) { return (Int(text) ?? 65536) <= 65535 }
        return serviceNames && goServices.contains(text.lowercased())
    }

     
     
    private static let goServices: Set<String> = [
        "ftp", "ftps", "gopher", "http", "https", "imap2", "imap3", "imaps", "pop3", "pop3s", "smtp",
        "submissions", "ssh", "telnet", "domain",
    ]

     

     
     
    private static func hostProblem(_ value: String, leaf: String) -> ConfigurationFieldProblem? {
        if value.contains("://") || value.contains("/") { return .address }
        if leaf == "server", value.contains(":"), !isIP(value) { return .hostWithPort }
        return nil
    }

     
     
    private static func ipProblem(_ value: String, leaf: String) -> ConfigurationFieldProblem? {
        if leaf == "bind-address" { return bindAddressProblem(value) }
        if isIP(value) { return nil }
        if leaf == "listen", value.allSatisfy({ $0.isLetter || $0.isNumber || "-._".contains($0) }) { return nil }
        return .ipAddress
    }

     
     
     
    private static func bindAddressProblem(_ value: String) -> ConfigurationFieldProblem? {
        if value == "*" { return nil }
        if value.hasPrefix("["), value.hasSuffix("]") {
            let inside = String(value.dropFirst().dropLast())
            return inside.contains(":") && isIP(inside) ? nil : .ipAddress
        }
        guard isIP(value) else { return .ipAddress }
        return value.contains(":") ? .bracketedIPv6Host : nil
    }

     
     
    private static func cidrProblem(_ value: String, leaf: String) -> ConfigurationFieldProblem? {
        guard let slash = value.firstIndex(of: "/") else {
            return ["ip", "ipv4", "ipv6"].contains(leaf) && isIP(value) ? nil : .addressRange
        }
        let address = String(value[..<slash])
        let bits = value[value.index(after: slash)...]
        guard !bits.isEmpty, bits.allSatisfy(\.isASCIIDigit), let count = Int(bits) else { return .addressRange }
        var v4 = in_addr(), v6 = in6_addr()
        if inet_pton(AF_INET, address, &v4) == 1 { return count <= 32 ? nil : .addressRange }
        if inet_pton(AF_INET6, address, &v6) == 1 { return count <= 128 ? nil : .addressRange }
        return .addressRange
    }

     
     
    private static func urlProblem(_ value: String, path: String) -> ConfigurationFieldProblem? {
        if value == "*", path.hasSuffix("allow-origins") { return nil }
        let pattern = #"^[A-Za-z][A-Za-z0-9+.\-]*:.+"#
        return value.range(of: pattern, options: .regularExpression) == nil ? .webAddress : nil
    }

     
     
     
    private static func dnsServerProblem(_ value: String) -> ConfigurationFieldProblem? {
        if value == "system" || isIP(value) { return nil }
        let server = value.contains("://") ? value : "udp://" + value
        guard let separator = server.range(of: "://") else { return .dnsServer }
        let scheme = server[..<separator.lowerBound].lowercased()
        let rest = String(server[separator.upperBound...])
        let beforeFragment = rest.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        var host = beforeFragment.split(whereSeparator: { $0 == "/" || $0 == "?" }).first.map(String.init) ?? ""
         
        if let at = host.lastIndex(of: "@") { host = String(host[host.index(after: at)...]) }
         
        if scheme.contains(where: \.isWhitespace) || host.contains(where: \.isWhitespace) { return .spaces }
        switch scheme {
        case "udp", "tcp", "tls", "http", "https", "quic":
            guard !host.isEmpty else { return .dnsServer }
             
             
             
             
             
            if host.hasPrefix("[") {
                guard let close = host.firstIndex(of: "]") else { return .dnsServer }
                let inside = String(host[host.index(after: host.startIndex)..<close])
                guard inside.contains(":"), isIP(inside) else { return .dnsServer }
                let after = host[host.index(after: close)...]
                if after.isEmpty { return nil }
                guard after.hasPrefix(":"), isPort(String(after.dropFirst()), serviceNames: false) else { return .dnsServer }
                return nil
            }
            guard host.contains(":") else { return nil }
            guard let (_, port) = splitHostPort(host), isPort(port, serviceNames: false) else { return .dnsServer }
            return nil
        case "system":
            return nil
        case "ts", "tailscale", "et", "easytier":
            return host.isEmpty ? .dnsServer : nil
        case "dhcp":
            return rest.isEmpty ? .dnsServer : nil
        case "rcode":
            let codes: Set<String> = ["success", "format_error", "server_failure", "name_error", "not_implemented", "refused"]
            return codes.contains(host) ? nil : .dnsServer
        default:
            return .dnsServer
        }
    }

     

     
     
     
    private static func portListProblem(_ value: String) -> ConfigurationFieldProblem? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed == "*" { return nil }
        let pieces = trimmed.replacingOccurrences(of: ",", with: "/").split(separator: "/", omittingEmptySubsequences: false)
        guard pieces.count <= 28 else { return .portList }
        for piece in pieces {
            let range = piece.trimmingCharacters(in: .whitespaces)
            if range.isEmpty { continue }
            let ends = range.split(separator: "-", omittingEmptySubsequences: false)
            guard ends.count == 1 || ends.count == 2 else { return .portList }
            for end in ends {
                let number = end.trimmingCharacters(in: CharacterSet(charactersIn: "[ ]"))
                guard !number.isEmpty, number.allSatisfy(\.isASCIIDigit), (Int(number) ?? 65536) <= 65535 else { return .portList }
            }
        }
        return nil
    }

     
     
     
     
    private static func base64Problem(_ value: String, path: String) -> ConfigurationFieldProblem? {
        if path.contains("[wireguard]") {
            let body = value.reversed().drop(while: { $0 == "=" })
            let standard = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
            guard value.count - body.count <= 2, !body.isEmpty, value.count % 4 == 0,
                  body.allSatisfy(standard.contains) else { return .standardBase64 }
            return nil
        }
        let body = value.reversed().drop(while: { $0 == "=" })
        guard value.count - body.count <= 2, !body.isEmpty else { return .base64 }
        let alphabet = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/-_")
        return body.allSatisfy(alphabet.contains) ? nil : .base64
    }

     
     
    private static func hexProblem(_ value: String, leaf: String) -> ConfigurationFieldProblem? {
        switch leaf {
        case "fingerprint":
            let digits = value.replacingOccurrences(of: ":", with: "")
            return digits.count == 64 && digits.allSatisfy(\.isASCIIHexDigit) ? nil : .fingerprint
        case "short-id":
            return value.count % 2 == 0 && value.count <= 16 && value.allSatisfy(\.isASCIIHexDigit) ? nil : .shortID
        default:
            return value.count % 2 == 0 && value.allSatisfy(\.isASCIIHexDigit) ? nil : .hexadecimal
        }
    }

     
     
     
    private static func uuidProblem(_ value: String, path: String) -> ConfigurationFieldProblem? {
        guard path.contains("[tuic]") else { return nil }
        var id = value
        if id.lowercased().hasPrefix("urn:uuid:") { id = String(id.dropFirst("urn:uuid:".count)) }
        if id.hasPrefix("{"), id.hasSuffix("}") { id = String(id.dropFirst().dropLast()) }
        if id.count == 32, id.allSatisfy(\.isASCIIHexDigit) { return nil }
        return UUID(uuidString: id) == nil ? .uuid : nil
    }

     
     
     
    private static func patternProblem(_ value: String) -> ConfigurationFieldProblem? {
        let icu = value.replacingOccurrences(of: "(?P<", with: "(?<")
        if (try? NSRegularExpression(pattern: icu)) != nil { return nil }
        return bracketsClose(value) ? nil : .pattern
    }

    private static func bracketsClose(_ pattern: String) -> Bool {
        var depth = 0, inClass = false, escaped = false
        for character in pattern {
            if escaped { escaped = false; continue }
            switch character {
            case "\\": escaped = true
            case "[" where !inClass: inClass = true
            case "]" where inClass: inClass = false
            case "(" where !inClass: depth += 1
            case ")" where !inClass:
                depth -= 1
                if depth < 0 { return false }
            default: break
            }
        }
        return depth == 0 && !inClass && !escaped
    }

     
    private static func durationProblem(_ value: String) -> ConfigurationFieldProblem? {
        if ConfigurationFieldDraft.isNumber(value) { return nil }
        let pattern = #"^[-+]?((\d+(\.\d*)?|\.\d+)(ns|us|µs|μs|ms|s|m|h))+$"#
        return value.range(of: pattern, options: .regularExpression) == nil ? .duration : nil
    }

     

     
     
    public static func generatedPassword(length: Int = 24) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        var generator = SystemRandomNumberGenerator()
        return String((0..<max(length, 0)).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &generator)] })
    }

     
    public static func generatedUUID() -> String { UUID().uuidString.lowercased() }

     

     
    static func leaf(of path: String) -> String {
        path.split(separator: ".").last.map(String.init) ?? path
    }

     
    static func isIP(_ text: String) -> Bool {
        var v4 = in_addr(), v6 = in6_addr()
        if inet_pton(AF_INET, text, &v4) == 1 { return true }
        let address = text.split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false)
        guard let head = address.first, address.count == 1 || !(address.last ?? "").isEmpty else { return false }
        return inet_pton(AF_INET6, String(head), &v6) == 1
    }

     
    public static func plain(_ number: Double) -> String {
        number == number.rounded() && abs(number) < 1e15 ? String(Int(number)) : String(number)
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
    var isASCIIHexDigit: Bool { isASCIIDigit || ("a"..."f").contains(self) || ("A"..."F").contains(self) }
}

 

 
 
 
 
public struct ConfigurationHostPortEntry: Equatable, Sendable {
    public enum HostChoice: String, CaseIterable, Sendable { case thisDevice, allNetworks, custom }

    public static let thisDeviceHost = "127.0.0.1"
    public static let allNetworksHost = "0.0.0.0"

    public var hostChoice: HostChoice
     
     
    public var customHost: String
    public var port: String

     
     
     
    public init(_ value: String?) {
        let text = value?.trimmingCharacters(in: .whitespaces) ?? ""
        if let (host, port) = ConfigurationFieldValidation.splitHostPort(text) {
            self.port = port
            switch host {
            case Self.thisDeviceHost: hostChoice = .thisDevice; customHost = ""
            case Self.allNetworksHost: hostChoice = .allNetworks; customHost = ""
            default: hostChoice = .custom; customHost = host
            }
        } else if text.isEmpty {
            hostChoice = .thisDevice; customHost = ""; port = ""
        } else {
             
            hostChoice = .custom; customHost = text; port = ""
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
    public init(_ value: String?, listens: Bool) {
        self.init(value)
        if listens {
            let text = value?.trimmingCharacters(in: .whitespaces) ?? ""
            if !text.isEmpty, text.allSatisfy({ ("0"..."9").contains($0) }),
               let number = Int(text), (1...65535).contains(number) {
                hostChoice = .thisDevice
                customHost = ""
                port = text
            }
            return
        }
        guard hostChoice != .custom else { return }
        let written = !(value?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
        customHost = written ? host : ""
        hostChoice = .custom
    }

    public var host: String {
        switch hostChoice {
        case .thisDevice: return Self.thisDeviceHost
        case .allNetworks: return Self.allNetworksHost
        case .custom: return customHost.trimmingCharacters(in: .whitespaces)
        }
    }

     
     
    public var composed: String? {
        problem(path: "") == nil ? candidate : nil
    }

     
    public func problem(path: String) -> ConfigurationFieldProblem? {
        let typedPort = port.trimmingCharacters(in: .whitespaces)
        guard !typedPort.isEmpty else { return .missingPort }
        if host.contains(where: \.isWhitespace) || typedPort.contains(where: \.isWhitespace) { return .spaces }
        return ConfigurationFieldValidation.problem(candidate, format: .ipPort, path: path)
    }

    private var candidate: String {
        ConfigurationFieldValidation.joinHostPort(host: host, port: port.trimmingCharacters(in: .whitespaces))
    }
}

 

 
 
 
public struct ConfigurationDurationEntry: Equatable, Sendable {
    public enum Unit: String, CaseIterable, Sendable {
        case milliseconds = "ms", seconds = "s", minutes = "min", hours = "h"

        var inMilliseconds: Decimal {
            switch self {
            case .milliseconds: return 1
            case .seconds: return 1000
            case .minutes: return 60_000
            case .hours: return 3_600_000
            }
        }
    }

    public var amount: String
    public var unit: Unit
     
    public let units: [Unit]
    private let base: Unit

     
    public init?(stored: String, fieldUnit: String?) {
        guard let base = Unit(rawValue: fieldUnit ?? ""), let units = Self.units(for: base), units.count > 1 else { return nil }
        self.base = base
        self.units = units
        if let whole = Self.largestWhole(stored: stored, fieldUnit: fieldUnit) {
            amount = whole.amount
            unit = whole.unit
        } else {
            amount = stored.trimmingCharacters(in: .whitespaces)
            unit = base
        }
    }

     
    public var stored: String? {
        let typed = amount.trimmingCharacters(in: .whitespaces)
        guard ConfigurationFieldDraft.isNumber(typed), let value = Self.decimal(typed) else { return nil }
        return Self.plain(value * unit.inMilliseconds / base.inMilliseconds)
    }

     
     
    public static func largestWhole(stored: String, fieldUnit: String?) -> (amount: String, unit: Unit)? {
        guard let base = Unit(rawValue: fieldUnit ?? ""), let units = units(for: base) else { return nil }
        let typed = stored.trimmingCharacters(in: .whitespaces)
        guard ConfigurationFieldDraft.isNumber(typed), let value = decimal(typed) else { return nil }
        guard value != 0 else { return ("0", base) }
        let milliseconds = value * base.inMilliseconds
        for unit in units.reversed() {
            let amount = milliseconds / unit.inMilliseconds
            if amount >= 1, isWhole(amount) { return (plain(amount), unit) }
        }
        return (plain(value), base)
    }

    private static func units(for base: Unit) -> [Unit]? {
        switch base {
         
         
        case .milliseconds: return [.milliseconds, .seconds, .minutes, .hours]
        case .seconds: return [.seconds, .minutes, .hours]
        case .minutes: return [.minutes, .hours]
        case .hours: return [.hours]
        }
    }

    private static func decimal(_ text: String) -> Decimal? {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func isWhole(_ value: Decimal) -> Bool {
        var rounded = Decimal()
        var copy = value
        NSDecimalRound(&rounded, &copy, 0, .plain)
        return rounded == value
    }

    private static func plain(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}
