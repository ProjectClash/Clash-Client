import ClashClientKit
import Foundation

 
 
struct ModuleInjectionPlan {
     
    let enginePort: UInt16
     
    let reinjectPort: UInt16
    let reinjectListenerName: String
    let engineProxyName: String
     
     
    let certEntryIP: String?
     
     
    let mitmHosts: ModuleHostList
     
     
     
    let forceHTTPEngineHosts: ModuleHostList
     
    let moduleRules: [String]
     
     
    let engineReady: Bool
     
     
     
    var decryptsTLS: Bool = true
     
     
     
     
     
     
    var fakeIPRanges: [String] = []
     
     
     
     
     
    var reinjectCredentials = ModuleReinjectCredentials.random()
     
     
     
     
    var engineProxyCredentials = ModuleEngineProxyCredentials.random()
     
     
     
    var moduleRulePolicies: Set<String> = []
     
     
    var platform: ModulePlatform = .current
     
     
     
    var moduleRuleSets: Set<String> = []
}

 
 
 
 
 
 
 
 
enum ModuleInjectionError: Error, Equatable, Sendable {
    case unsupportedSectionLayout(String)
     
    case unreadableLayout
     
     
    case unusableCredentials
     
     
    case unusableOwnValue
     
     
     
     
    case engineNameTaken

     
     
    var authoredText: AuthoredText {
        switch self {
        case .unsupportedSectionLayout(let key):
             
            return .app(ModuleStoredSentence.sectionLayout, arguments: [key])
        case .unreadableLayout:
             
            return .app("This configuration is written in an unusual way, so modules cannot take effect.")
        case .unusableCredentials, .unusableOwnValue:
             
             
             
            return ModuleDegradeReason.engineUnavailable.authoredText
        case .engineNameTaken:
            return ModuleDegradeReason.engineNameTaken.authoredText
        }
    }
}

 
 
 
 
 
 
 
 
 
 
enum ModuleYAMLText {
     
     
    static func isOneLine(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x00...0x1F, 0x7F...0x9F, 0x2028, 0x2029, 0xFEFF: return false
            default: return true
            }
        }
    }

     
     
     
    static func scalar(_ text: String) -> String {
        isPlain(text) ? text : doubleQuoted(text)
    }

     
     
     
    static func isPlain(_ text: String) -> Bool {
        guard let first = text.unicodeScalars.first, first.isASCII, first.properties.isAlphabetic else { return false }
        guard text.unicodeScalars.allSatisfy({ (0x20...0x7E).contains($0.value) }) else { return false }
        if text.contains(": ") || text.contains(" #") || text.hasSuffix(":") || text.hasSuffix(" ") { return false }
        return !["y", "n", "yes", "no", "on", "off", "true", "false", "null"].contains(text.lowercased())
    }

     
     
     
    static func doubleQuoted(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\\": out += #"\\"#
            case "\"": out += #"\""#
            default:
                switch scalar.properties.generalCategory {
                case .control, .format, .lineSeparator, .paragraphSeparator, .privateUse, .unassigned, .surrogate:
                    out += scalar.value <= 0xFFFF ? String(format: #"\u%04X"#, scalar.value) : String(format: #"\U%08X"#, scalar.value)
                default:
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

     
     
    static func isPlainName(_ text: String) -> Bool {
        guard let first = text.unicodeScalars.first, first.isASCII, first.properties.isAlphabetic else { return false }
        return text.unicodeScalars.allSatisfy {
            $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0) || $0 == "-" || $0 == "_")
        }
    }

     
    static func isIPv4Literal(_ text: String) -> Bool {
        guard let literal = ModuleIPLiteral(text) else { return false }
        return !literal.isIPv6 && literal.canonical == text
    }
}

 
 
indirect enum ModuleClause: Equatable {
    case atom(String)
    case and([ModuleClause])
    case or([ModuleClause])
    case not(ModuleClause)

     
     
    var simplified: ModuleClause {
        switch self {
        case .atom:
            return self
        case .not(let inner):
            return .not(inner.simplified)
        case .or(let members):
            let flat = members.map(\.simplified).flatMap { member -> [ModuleClause] in
                if case .or(let inner) = member { return inner }
                return [member]
            }
            return flat.count == 1 ? flat[0] : .or(flat)
        case .and(let members):
            let flat = members.map(\.simplified).flatMap { member -> [ModuleClause] in
                switch member {
                case .and(let inner): return inner
                case .not(.or(let inner)): return inner.map { .not($0) }
                default: return [member]
                }
            }
            return flat.count == 1 ? flat[0] : .and(flat)
        }
    }

     
    var rendered: String {
        switch self {
        case .atom(let text): return "(" + text + ")"
        case .and(let members): return "(AND,(" + members.map(\.rendered).joined(separator: ",") + "))"
        case .or(let members): return "(OR,(" + members.map(\.rendered).joined(separator: ",") + "))"
        case .not(let inner): return "(NOT,(" + inner.rendered + "))"
        }
    }

     
    var conjuncts: [ModuleClause] {
        if case .and(let members) = simplified { return members }
        return [simplified]
    }
}

 
 
 
enum ModuleHostListEncoding {
     
     
     
     
     
     
     
     
     
     
    static func clause(for list: ModuleHostList, onlyPort: UInt16? = nil) -> ModuleClause? {
        func port(of entry: ModuleHostEntry) -> UInt16? {
            switch entry.port {
            case .standard: return list.standardPort
            case .port(let value): return value
            case .all: return nil
            }
        }
        let entries = list.items.map(\.entry).filter { entry in
            guard let onlyPort, let fixed = port(of: entry) else { return true }
            return fixed == onlyPort
        }
         
        var blocks: [(exclusions: [ModuleHostEntry], run: [ModuleHostEntry])] = []
        var index = 0
        while index < entries.count {
            var block: (exclusions: [ModuleHostEntry], run: [ModuleHostEntry]) = ([], [])
            while index < entries.count, entries[index].excluded { block.exclusions.append(entries[index]); index += 1 }
            while index < entries.count, !entries[index].excluded { block.run.append(entries[index]); index += 1 }
            blocks.append(block)
        }
        func group(_ entry: ModuleHostEntry) -> UInt16? { onlyPort ?? port(of: entry) }
        func disjuncts(of run: [ModuleHostEntry]) -> [ModuleClause] {
            var groups: [UInt16?] = []
            for entry in run where !groups.contains(group(entry)) { groups.append(group(entry)) }
            return groups.map { groupPort in
                let hosts = ModuleClause.or(run.filter { group($0) == groupPort }.map { hostClause($0.pattern) })
                guard onlyPort == nil, let groupPort else { return hosts }
                return .and([.atom("DST-PORT,\(groupPort)"), hosts])
            }
        }
         
         
         
        func notMatching(_ exclusion: ModuleHostEntry, tailPorts: Set<UInt16?>) -> ModuleClause? {
            guard onlyPort == nil, let excludedPort = port(of: exclusion) else { return .not(hostClause(exclusion.pattern)) }
            if tailPorts == [excludedPort] { return .not(hostClause(exclusion.pattern)) }
            if !tailPorts.contains(excludedPort), !tailPorts.contains(nil) { return nil }
            return .not(.and([.atom("DST-PORT,\(excludedPort)"), hostClause(exclusion.pattern)]))
        }
        var tail: ModuleClause?
        var tailPorts = Set<UInt16?>()
        for block in blocks.reversed() {
            let members = disjuncts(of: block.run) + (tail.map { [$0] } ?? [])
            guard !members.isEmpty else { tail = nil; continue }
            block.run.forEach { tailPorts.insert(onlyPort == nil ? port(of: $0) : onlyPort) }
            let inner = ModuleClause.or(members)
            let nots = block.exclusions.compactMap { notMatching($0, tailPorts: tailPorts) }
            if nots.isEmpty {
                tail = inner
            } else if case .and(let required) = inner.simplified, case .atom(let first)? = required.first, first.hasPrefix("DST-PORT,") {
                 
                tail = .and([required[0]] + nots + required.dropFirst())
            } else {
                tail = .and(nots + [inner])
            }
        }
        return tail?.simplified
    }

    static func hostClause(_ pattern: ModuleHostPattern) -> ModuleClause {
        switch pattern {
        case .name(let name):
             
             
            if name == "*" { return .atom("DOMAIN-WILDCARD,?*") }
            if name.contains("*") || name.contains("?") { return .atom("DOMAIN-WILDCARD,\(name)") }
             
             
             
             
             
             
            if let literal = ModuleIPLiteral(name) {
                return .and([.not(.atom("DOMAIN-WILDCARD,?*")),
                             .atom(literal.isIPv6 ? "IP-CIDR6,\(literal.canonical)/128,no-resolve" : "IP-CIDR,\(literal.canonical)/32,no-resolve")])
            }
            return .atom("DOMAIN,\(name)")
        case .ipAddress:
            return .not(.atom("DOMAIN-WILDCARD,?*"))
        case .ipv4Address:
            return .and([.not(.atom("DOMAIN-WILDCARD,?*")), .atom("IP-CIDR,0.0.0.0/0,no-resolve")])
        case .ipv6Address:
            return .and([.not(.atom("DOMAIN-WILDCARD,?*")), .atom("IP-CIDR6,::/0,no-resolve")])
        case .simpleHostname:
            return .atom(#"DOMAIN-REGEX,^[^.]+$"#)
        }
    }
}

 
 
 
 
 
 
 
 
struct ModuleEngineHostSet: Equatable, Sendable {
     
    let lines: [String]
     
    let sha256: String

    init<S: Sequence>(_ lines: S) where S.Element == String {
        let sorted = Array(Set(lines)).sorted()
        self.lines = sorted
        sha256 = ModuleJSON.sha256(Data((sorted.joined(separator: "\n") + "\n").utf8))
    }

     
    var data: Data { Data((lines.joined(separator: "\n") + "\n").utf8) }

     
     
    var name: String { ModuleRuleSetSyntax.engineProviderPrefix + String(sha256.prefix(8)) }

     
     
    func definition(path: String?) -> OrderedJSON {
        guard let path else {
            return .object([("type", .string("inline")), ("behavior", .string("domain")),
                            ("payload", .array(lines.map(OrderedJSON.string)))])
        }
        return .object([("type", .string("file")), ("behavior", .string("domain")), ("format", .string("text")),
                        ("path", .string(path))])
    }

     
     
     
     
     
     
     
    func keep(in copies: URL) -> URL? {
        let url = copies.appendingPathComponent(sha256)
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
            return url
        }
        do {
            try FileManager.default.createDirectory(at: copies, withIntermediateDirectories: true)
            try data.write(to: url, options: ProviderPayloadStore.writeOptions)
            return url
        } catch {
            return nil
        }
    }

     
     
     
     
    static func definitions(_ sets: [ModuleEngineHostSet], copies: URL?) -> [String: OrderedJSON] {
        var out: [String: OrderedJSON] = [:]
        for set in sets where out[set.name] == nil {
            out[set.name] = set.definition(path: copies.flatMap { set.keep(in: $0) }?.path)
        }
        return out
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum ModuleEngineRoute {
    struct Built: Equatable {
        var rules: [String] = []
        var sets: [ModuleEngineHostSet] = []
    }

     
    static let quicPort: UInt16 = 443

     
     
     
     
     
    static func quic(mitm: ModuleHostList) -> Built {
        let part = setPart(of: mitm, port: quicPort)
        let head: [ModuleClause] = [.atom("IN-TYPE,TUN"), .atom("NETWORK,UDP"), .atom("DST-PORT,\(quicPort)")]
        let rules = part.rules.map { conjuncts in
            "AND,(" + ModuleClause.and(head + conjuncts).conjuncts.map(\.rendered).joined(separator: ",") + "),REJECT"
        }
        return Built(rules: rules, sets: part.sets)
    }

    static func build(mitm: ModuleHostList?, forceHTTP: ModuleHostList, engine name: String) -> Built {
        var out = Built()
        let head: [ModuleClause] = [.atom("IN-TYPE,TUN"), .atom("NETWORK,TCP")]
        func rule(_ conjuncts: [ModuleClause]) -> String {
            "AND,(" + ModuleClause.and(head + conjuncts).conjuncts.map(\.rendered).joined(separator: ",") + ")," + name
        }
        if let mitm {
            let port = mitm.standardPort
            let part = setPart(of: mitm, port: port)
            for one in part.rules { out.rules.append(rule([.atom("DST-PORT,\(port)")] + one)) }
            out.sets += part.sets
             
             
             
            let others = mitm.items.filter { !decidesOnly(port, $0.entry, standardPort: mitm.standardPort) }
            if let clause = ModuleHostListEncoding.clause(for: ModuleHostList(items: others, standardPort: mitm.standardPort)) {
                let everyPort = others.contains { $0.entry.port == .all }
                out.rules.append(rule((everyPort ? [.not(.atom("DST-PORT,\(port)"))] : []) + [clause]))
            }
        }
        if let clause = ModuleHostListEncoding.clause(for: forceHTTP) {
            out.rules.append(rule([clause]))
        }
        return out
    }

     
     
    static func hostSets(for mitm: ModuleHostList) -> [ModuleEngineHostSet] {
        setPart(of: mitm, port: mitm.standardPort).sets
    }

     
    static func applies(_ entry: ModuleHostEntry, to port: UInt16, standardPort: UInt16) -> Bool {
        switch entry.port {
        case .standard: return standardPort == port
        case .port(let value): return value == port
        case .all: return true
        }
    }

     
    private static func decidesOnly(_ port: UInt16, _ entry: ModuleHostEntry, standardPort: UInt16) -> Bool {
        switch entry.port {
        case .standard: return standardPort == port
        case .port(let value): return value == port
        case .all: return false
        }
    }

     
    private static func setPart(of list: ModuleHostList, port: UInt16) -> (rules: [[ModuleClause]], sets: [ModuleEngineHostSet]) {
         
        let entries = list.items.map(\.entry).filter { applies($0, to: port, standardPort: list.standardPort) }
            .map { (entry: $0, shape: shape($0.pattern)) }
         
         
        var front: [(entry: ModuleHostEntry, shape: Shape)] = []
        var rest: [(entry: ModuleHostEntry, shape: Shape)] = []
        var includes: [Shape] = []
        for item in entries {
            if !item.entry.excluded {
                includes.append(item.shape)
                rest.append(item)
            } else if includes.contains(where: { overlap($0, item.shape) }) {
                rest.append(item)
            } else {
                front.append(item)
            }
        }
        var ordered: [ModuleHostEntry] = []
        let all = front + rest
        for (index, item) in all.enumerated() {
            if item.entry.excluded, !all[(index + 1)...].contains(where: { !$0.entry.excluded && overlap($0.shape, item.shape) }) {
                continue
            }
            ordered.append(item.entry)
        }
        var rules: [[ModuleClause]] = []
        var sets: [ModuleEngineHostSet] = []
        var guards: [ModuleClause] = []
        var index = 0
        while index < ordered.count {
            var exclusions: [ModuleHostEntry] = []
            while index < ordered.count, ordered[index].excluded { exclusions.append(ordered[index]); index += 1 }
            var run: [ModuleHostEntry] = []
            while index < ordered.count, !ordered[index].excluded { run.append(ordered[index]); index += 1 }
            let excludedLines = exclusions.compactMap { setLine($0.pattern) }
            if !excludedLines.isEmpty {
                let set = ModuleEngineHostSet(excludedLines)
                sets.append(set)
                guards.append(.not(.atom("RULE-SET," + set.name)))
            }
            guards += exclusions.filter { setLine($0.pattern) == nil }.map { .not(ModuleHostListEncoding.hostClause($0.pattern)) }
            guard !run.isEmpty else { continue }
            let lines = run.compactMap { setLine($0.pattern) }
            if !lines.isEmpty {
                let set = ModuleEngineHostSet(lines)
                sets.append(set)
                 
                 
                rules.append([.atom("RULE-SET," + set.name)] + guards)
            }
            let others = run.filter { setLine($0.pattern) == nil }.map { ModuleHostListEncoding.hostClause($0.pattern) }
            if !others.isEmpty { rules.append([.or(others)] + guards) }
        }
        return (rules, sets)
    }

     
     
     
     
    static func setLine(_ pattern: ModuleHostPattern) -> String? {
        guard case .name(let name) = pattern else { return nil }
        if name.hasPrefix("*.") {
            let rest = name.dropFirst(2)
            return isExactName(rest) ? "." + rest : nil
        }
        return isExactName(name[...]) ? name : nil
    }

     
     
    private static func isExactName(_ name: Substring) -> Bool {
        guard !name.isEmpty, !name.hasPrefix("."), !name.hasSuffix("."), !name.contains(".."),
              !ModuleIPLiteral.mightBe(String(name)) else { return false }
        return name.unicodeScalars.allSatisfy { scalar in
            ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "." || scalar == "-" || scalar == "_"
        }
    }

     
    private enum Shape {
        case exact(String)
         
        case under(String)
        case wildcard(String)
        case simpleHostname
        case address(ModuleIPLiteral)
        case anyAddress
        case anyIPv4
        case anyIPv6

        var needsName: Bool {
            switch self {
            case .exact, .under, .wildcard, .simpleHostname: return true
            case .address, .anyAddress, .anyIPv4, .anyIPv6: return false
            }
        }
    }

    private static func shape(_ pattern: ModuleHostPattern) -> Shape {
        switch pattern {
        case .name(let name):
            if ModuleIPLiteral.mightBe(name), let literal = ModuleIPLiteral(name) { return .address(literal) }
            guard name.contains("*") || name.contains("?") else { return .exact(name) }
            let rest = name.dropFirst(2)
            if name.hasPrefix("*."), !rest.contains("*"), !rest.contains("?") { return .under("." + rest) }
            return .wildcard(name)
        case .ipAddress: return .anyAddress
        case .ipv4Address: return .anyIPv4
        case .ipv6Address: return .anyIPv6
        case .simpleHostname: return .simpleHostname
        }
    }

     
     
     
     
    static func mayOverlap(_ a: ModuleHostPattern, _ b: ModuleHostPattern) -> Bool {
        overlap(shape(a), shape(b))
    }

    private static func overlap(_ x: Shape, _ y: Shape) -> Bool {
        guard x.needsName == y.needsName else { return false }
        switch (x, y) {
        case (.exact(let one), .exact(let other)): return one == other
        case (.exact(let name), .under(let suffix)), (.under(let suffix), .exact(let name)):
            return ModuleWildcard.matches("*" + suffix, name)
        case (.exact(let name), .wildcard(let pattern)), (.wildcard(let pattern), .exact(let name)):
            return ModuleWildcard.matches(pattern, name)
        case (.exact(let name), .simpleHostname), (.simpleHostname, .exact(let name)):
            return !name.contains(".")
        case (.under(let one), .under(let other)):
            return one.hasSuffix(other) || other.hasSuffix(one)
        case (.under, .simpleHostname), (.simpleHostname, .under):
            return false
        case (.address(let one), .address(let other)):
            return one.canonical == other.canonical
        case (.address(let literal), .anyIPv4), (.anyIPv4, .address(let literal)):
            return !literal.isIPv6
        case (.address(let literal), .anyIPv6), (.anyIPv6, .address(let literal)):
            return literal.isIPv6
        case (.anyIPv4, .anyIPv6), (.anyIPv6, .anyIPv4):
            return false
        default:
            return true
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum ModuleInjection {
    struct Result: Equatable {
         
         
        let text: String
         
        let engineProxyName: String?
        let reinjectListenerName: String?
         
        let reinjectCredentials: ModuleReinjectCredentials?
         
         
        var engineProxyCredentials: ModuleEngineProxyCredentials? = nil
         
         
        let snifferInjected: Bool
         
         
        var snifferAdded: [String] = []
         
         
         
        var snifferWrittenOff: [String] = []
         
         
         
        var snifferNotCompleted = false
         
         
         
        var rules: [String] = []
         
         
        var leftOut: [String] = []
         
         
         
        var hostSets: [ModuleEngineHostSet] = []
    }

     
     
    static let certEntryHostName = "cert.clash"

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func snifferValue(skippingFakeIPRanges ranges: [String] = []) -> String {
         
         
         
        let safe = ranges.filter { !$0.isEmpty && $0.allSatisfy { ($0.isASCII && $0.isHexDigit) || $0 == ":" || $0 == "." || $0 == "/" } }
         
         
         
         
         
        let skip = safe.isEmpty ? "" : #", skip-dst-address: ["# + safe.map(ModuleYAMLText.doubleQuoted).joined(separator: ", ") + "]"
        return #"{ enable: true, override-destination: false, force-dns-mapping: true, parse-pure-ip: true"# + skip
            + #", sniff: { TLS: { ports: [443] }, HTTP: { ports: [80] }, QUIC: { ports: [443] } } }"#
    }

     
     
     
     
     
     
     
     
     
     
     
     
    static func reinjectListenerEntry(name: String, port: UInt16, credentials: ModuleReinjectCredentials) throws -> String {
        guard credentials.isWellFormed else { throw ModuleInjectionError.unusableCredentials }
        return "{ name: \(name), type: mixed, listen: 127.0.0.1, port: \(port), users: [{ username: \(credentials.username), password: \(credentials.password) }]"
            + #", x-clash-outbound-header: true }"#
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func engineProxyEntry(name: String, port: UInt16, credentials: ModuleEngineProxyCredentials,
                                 listener: ModuleReinjectCredentials) throws -> String {
        guard credentials.isWellFormed, credentials != listener else { throw ModuleInjectionError.unusableCredentials }
        return "{ name: \(name), type: http, server: 127.0.0.1, port: \(port), username: \(credentials.username), password: \(credentials.password), x-clash-internal: true, x-clash-connect-sniffed-host: true }"
    }

     
     
     
     
    static let composition = 2

     
     
     
     
     
    static func rulesBlock(_ plan: ModuleInjectionPlan) -> [String] {
        rulesAndSets(plan).rules
    }

     
    static func rulesAndSets(_ plan: ModuleInjectionPlan) -> (rules: [String], sets: [ModuleEngineHostSet]) {
        func rule(_ conjuncts: [ModuleClause], _ target: String) -> String {
            "AND,(" + ModuleClause.and(conjuncts).conjuncts.map(\.rendered).joined(separator: ",") + ")," + target
        }
        var out: [String] = []
        if plan.engineReady, let address = plan.certEntryIP {
             
            out.append(rule([.atom("IN-TYPE,TUN"), .atom("IP-CIDR,\(address)/32,no-resolve")], plan.engineProxyName))
        }
         
        let quic = ModuleEngineRoute.quic(mitm: plan.mitmHosts)
        out.append(contentsOf: quic.rules)
        guard plan.engineReady else { return (out + plan.moduleRules, quic.sets) }
         
         
         
         
         
         
         
         
        let refusals = plan.moduleRules.prefix(while: refuses)
        out.append(contentsOf: refusals)
         
         
        let route = ModuleEngineRoute.build(mitm: plan.decryptsTLS ? plan.mitmHosts : nil, forceHTTP: plan.forceHTTPEngineHosts,
                                             engine: plan.engineProxyName)
         
        var named = Set<String>()
        return (out + route.rules + plan.moduleRules.dropFirst(refusals.count),
                (quic.sets + route.sets).filter { named.insert($0.name).inserted })
    }

     
     
    static func refuses(_ rule: String) -> Bool {
        ModuleRuleMapping.split(rule, family: .surge)?.policy.map(ModuleRuleMapping.isReject) ?? false
    }

     
     
    static func hostsForTheDocument(_ list: ModuleHostList) -> (list: ModuleHostList, leftOut: [String]) {
        var leftOut: [String] = []
        var checked = list
        checked.items = list.items.filter { item in
            guard case .name(let name) = item.entry.pattern, !ModuleHostList.isHostName(name) else { return true }
            leftOut.append(item.entry.spelling)
            return false
        }
        return (checked, leftOut)
    }

    static func inject(into mergedYAML: String, plan: ModuleInjectionPlan) throws -> String {
        try injectReporting(into: mergedYAML, plan: plan).text
    }

    static func injectReporting(into mergedYAML: String, plan: ModuleInjectionPlan) throws -> Result {
         
         
         
         
         
         
         
        var leftOut: [String] = []
        let moduleRules = plan.moduleRules.filter { rule in
            let usable = !rule.isEmpty && ModuleYAMLText.isOneLine(rule)
                && ModuleRuleMapping.isModuleRule(rule, policies: plan.moduleRulePolicies, ruleSets: plan.moduleRuleSets,
                                                   platform: plan.platform)
            if !usable { leftOut.append(rule) }
            return usable
        }
        func hosts(_ list: ModuleHostList) -> ModuleHostList {
            let checked = hostsForTheDocument(list)
            leftOut += checked.leftOut
            return checked.list
        }
        let mitmHosts = hosts(plan.mitmHosts)
        let forceHTTPEngineHosts = hosts(plan.forceHTTPEngineHosts)
        guard plan.engineReady else {
             
             
            let checked = ModuleInjectionPlan(
                enginePort: plan.enginePort, reinjectPort: plan.reinjectPort, reinjectListenerName: plan.reinjectListenerName,
                engineProxyName: plan.engineProxyName, certEntryIP: plan.certEntryIP, mitmHosts: mitmHosts,
                forceHTTPEngineHosts: forceHTTPEngineHosts, moduleRules: moduleRules, engineReady: false,
                decryptsTLS: plan.decryptsTLS, fakeIPRanges: plan.fakeIPRanges, reinjectCredentials: plan.reinjectCredentials,
                engineProxyCredentials: plan.engineProxyCredentials, moduleRulePolicies: plan.moduleRulePolicies,
                moduleRuleSets: plan.moduleRuleSets)
            let block = rulesAndSets(checked)
            return Result(text: mergedYAML, engineProxyName: nil, reinjectListenerName: nil, reinjectCredentials: nil,
                          snifferInjected: false, rules: block.rules, leftOut: leftOut, hostSets: block.sets)
        }
        guard ModuleYAMLText.isPlainName(plan.engineProxyName), ModuleYAMLText.isPlainName(plan.reinjectListenerName),
              plan.certEntryIP.map(ModuleYAMLText.isIPv4Literal) ?? true else {
            throw ModuleInjectionError.unusableOwnValue
        }
         
        let mark = "\u{FEFF}"
        let hasMark = mergedYAML.hasPrefix(mark)
        let body = hasMark ? String(mergedYAML.dropFirst()) : mergedYAML
         
         
        guard !hasLoneCarriageReturn(body), let keys = TopLevelYAMLSections.keyLines(of: body) else {
            throw ModuleInjectionError.unreadableLayout
        }
        let bytes = Array(body.utf8)
        let newline = usesCRLF(bytes) ? "\r\n" : "\n"
         
         
         
         
        if namesAnEntry(ModuleActivationStep.engineProxyName, in: bytes) { throw ModuleInjectionError.engineNameTaken }

         
         
         
        let plan = ModuleInjectionPlan(
            enginePort: plan.enginePort, reinjectPort: plan.reinjectPort,
            reinjectListenerName: uniqueName(plan.reinjectListenerName, in: bytes),
            engineProxyName: plan.engineProxyName,
            certEntryIP: plan.certEntryIP, mitmHosts: mitmHosts,
            forceHTTPEngineHosts: forceHTTPEngineHosts, moduleRules: moduleRules, engineReady: true,
            decryptsTLS: plan.decryptsTLS, fakeIPRanges: plan.fakeIPRanges, reinjectCredentials: plan.reinjectCredentials,
            engineProxyCredentials: plan.engineProxyCredentials, moduleRulePolicies: plan.moduleRulePolicies,
            platform: plan.platform, moduleRuleSets: plan.moduleRuleSets)
        var edits: [Edit] = []
        var snifferInjected = false
        edits.append(try edit(key: "proxies", keys: keys, bytes: bytes, newline: newline, entries: [
            try engineProxyEntry(name: plan.engineProxyName, port: plan.enginePort, credentials: plan.engineProxyCredentials,
                                 listener: plan.reinjectCredentials),
        ]))
        edits.append(try edit(key: "listeners", keys: keys, bytes: bytes, newline: newline, entries: [
            try reinjectListenerEntry(name: plan.reinjectListenerName, port: plan.reinjectPort, credentials: plan.reinjectCredentials),
        ]))
         
        var snifferAdded: [String] = []
        var snifferWrittenOff: [String] = []
        var snifferNotCompleted = false
        var snifferReplacement: Edit?
        if let line = keys.first(where: { $0.key == "sniffer" }) {
             
             
            let end = keys.map(\.offset).filter { $0 > line.offset }.min() ?? bytes.count
            let section = String(decoding: bytes[line.offset..<end], as: UTF8.self)
             
             
             
            let anchored = bytes[line.offset..<end].withUnsafeBufferPointer { TopLevelYAMLSections.mentionsAnchorOrAlias(inBytes: $0) }
                || section.range(of: #"<<[ \t]*:"#, options: .regularExpression) != nil
            if let json = try? ConfigTransforms.yamlToJSON(section, omitting: []),
               let root = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any],
               let own = root["sniffer"] as? [String: Any] {
                let done = completedSniffer(own, fakeIPRanges: plan.fakeIPRanges)
                snifferWrittenOff = done.writtenOff
                if !done.added.isEmpty, anchored {
                    snifferNotCompleted = true
                } else if !done.added.isEmpty,
                   let text = try? JSONSerialization.data(withJSONObject: done.value, options: [.sortedKeys, .withoutEscapingSlashes]) {
                     
                     
                    snifferReplacement = Edit(start: line.offset, end: end,
                                              replacement: Array((#"sniffer: "# + String(decoding: text, as: UTF8.self) + newline).utf8))
                    snifferAdded = done.added
                }
            } else {
                 
                 
                snifferNotCompleted = true
            }
        } else {
            let at = keys.first?.offset ?? bytes.count
            edits.append(Edit(start: at, end: at, replacement: Array((#"sniffer: "# + snifferValue(skippingFakeIPRanges: plan.fakeIPRanges) + newline).utf8)))
            snifferInjected = true
        }
        if let address = plan.certEntryIP, !contains(certEntryHostName, in: bytes),
           let alias = hostsEdit(keys: keys, bytes: bytes, newline: newline, entry: certEntryHostName + ": " + address) {
            edits.append(alias)
        }
         
         
        if let snifferReplacement { edits.append(snifferReplacement) }
         
        let block = rulesAndSets(plan)
        return Result(text: (hasMark ? mark : "") + apply(edits, to: bytes),
                      engineProxyName: plan.engineProxyName, reinjectListenerName: plan.reinjectListenerName,
                      reinjectCredentials: plan.reinjectCredentials, engineProxyCredentials: plan.engineProxyCredentials,
                      snifferInjected: snifferInjected, snifferAdded: snifferAdded, snifferWrittenOff: snifferWrittenOff,
                      snifferNotCompleted: snifferNotCompleted,
                      rules: block.rules, leftOut: leftOut, hostSets: block.sets)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func completedSniffer(_ sniffer: [String: Any], fakeIPRanges: [String])
        -> (value: [String: Any], added: [String], writtenOff: [String]) {
        var writtenOff: [String] = []
        for key in ["enable", "parse-pure-ip", "force-dns-mapping"] where (sniffer[key] as? Bool) == false {
            writtenOff.append(key)
        }
         
        if (sniffer["enable"] as? Bool) == false { return (sniffer, [], writtenOff) }
        var value = sniffer
        var added: [String] = []
        if sniffer["enable"] == nil {
            value["enable"] = true
            added.append("enable")
        }
        var sniff = sniffer["sniff"] as? [String: Any] ?? [:]
        if sniff.isEmpty, let older = sniffer["sniffing"] as? [Any], !older.isEmpty {
            let whitelist = sniffer["port-whitelist"] as? [Any] ?? []
            for case let name as String in older {
                sniff[name.uppercased()] = whitelist.isEmpty ? [String: Any]() : ["ports": whitelist]
            }
            added.append(#"sniff (rewritten from sniffing)"#)
        }
        for (name, port) in [("TLS", 443), ("HTTP", 80), ("QUIC", 443)] {
            guard let key = sniff.keys.first(where: { $0.uppercased() == name }) else {
                sniff[name] = ["ports": [port], "override-destination": false] as [String: Any]
                added.append("\(name) on \(port)")
                continue
            }
            var entry = sniff[key] as? [String: Any] ?? [:]
            let list = entry["ports"] as? [Any] ?? []
            guard !list.isEmpty, !holds(list, port) else { continue }
            entry["ports"] = list + [port]
            sniff[key] = entry
            added.append("\(name) on \(port)")
        }
        if !added.isEmpty || sniffer["sniff"] != nil { value["sniff"] = sniff }
        let skip = fakeIPRanges.filter { !$0.isEmpty && $0.allSatisfy { ($0.isASCII && $0.isHexDigit) || $0 == ":" || $0 == "." || $0 == "/" } }
        if sniffer["skip-dst-address"] == nil, !skip.isEmpty {
            value["skip-dst-address"] = skip
            added.append("skip-dst-address")
        }
        return (value, added, writtenOff)
    }

     
     
    private static func holds(_ list: [Any], _ port: Int) -> Bool {
        list.contains { item in
            if let number = item as? NSNumber { return number.intValue == port }
            guard let text = item as? String else { return false }
            let bounds = text.split(separator: "-", maxSplits: 1).map { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard let low = bounds.first ?? nil else { return false }
            let high = bounds.count == 2 ? (bounds[1] ?? low) : low
            return (low...max(low, high)).contains(port)
        }
    }

     

    private struct Edit {
         
        let start: Int
        let end: Int
        let replacement: [UInt8]
    }

     
     
    private static func hasLoneCarriageReturn(_ text: String) -> Bool {
        var text = text
        return text.withUTF8 { bytes in
            guard let base = bytes.baseAddress else { return false }
            var from = 0
            while from < bytes.count, let hit = memchr(base + from, Int32(UInt8(ascii: "\r")), bytes.count - from) {
                let at = UnsafeRawPointer(base).distance(to: UnsafeRawPointer(hit))
                if at + 1 >= bytes.count || bytes[at + 1] != UInt8(ascii: "\n") { return true }
                from = at + 2
            }
            return false
        }
    }

     
    private static func isEmptySequence(_ value: String) -> Bool {
        ["[]", "~", "null", "Null", "NULL"].contains(value)
    }

    private static func usesCRLF(_ bytes: [UInt8]) -> Bool {
        guard let newline = bytes.firstIndex(of: UInt8(ascii: "\n")) else { return false }
        return newline > 0 && bytes[newline - 1] == UInt8(ascii: "\r")
    }

     
     
     
     
    private static func uniqueName(_ base: String, in bytes: [UInt8]) -> String {
        var candidate = base
        var next = 2
        while contains(candidate, in: bytes) {
            candidate = "\(base)-\(next)"
            next += 1
        }
        return candidate
    }

     
     
     
     
    static func namesAnEntry(_ name: String, in bytes: [UInt8]) -> Bool {
        let needle = Array(name.utf8)
        guard !needle.isEmpty, needle.count <= bytes.count else { return false }
        func isBlank(_ byte: UInt8) -> Bool { byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") }
        func isQuote(_ byte: UInt8) -> Bool { byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") }
        var from = 0
        while from + needle.count <= bytes.count {
            let found: Int? = bytes.withUnsafeBytes { text in
                needle.withUnsafeBytes { pattern in
                    guard let hit = memmem(text.baseAddress! + from, text.count - from, pattern.baseAddress, pattern.count) else { return nil }
                    return text.baseAddress!.distance(to: UnsafeRawPointer(hit))
                }
            }
            guard let at = found else { return false }
            from = at + 1
             
            var lineStart = at
            while lineStart > 0, bytes[lineStart - 1] != UInt8(ascii: "\n") { lineStart -= 1 }
            if (lineStart..<at).contains(where: { bytes[$0] == UInt8(ascii: "#") && ($0 == lineStart || isBlank(bytes[$0 - 1])) }) {
                continue
            }
             
            var end = at + needle.count
            var start = at
            if start > 0, isQuote(bytes[start - 1]) {
                guard end < bytes.count, bytes[end] == bytes[start - 1] else { continue }
                start -= 1
                end += 1
            }
            guard end == bytes.count || [UInt8(ascii: ","), UInt8(ascii: "}"), UInt8(ascii: "\n"), UInt8(ascii: "\r"),
                                          UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "#")].contains(bytes[end]) else { continue }
             
            var i = start
            while i > 0, isBlank(bytes[i - 1]) { i -= 1 }
            guard i > 0, bytes[i - 1] == UInt8(ascii: ":") else { continue }
            i -= 1
            while i > 0, isBlank(bytes[i - 1]) { i -= 1 }
            var quote: UInt8?
            if i > 0, isQuote(bytes[i - 1]) {
                quote = bytes[i - 1]
                i -= 1
            }
            let key = Array("name".utf8)
            guard i >= key.count, Array(bytes[(i - key.count)..<i]) == key else { continue }
            i -= key.count
            if let quote {
                guard i > 0, bytes[i - 1] == quote else { continue }
                i -= 1
            }
            if i == 0 || [UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "{"), UInt8(ascii: ","), UInt8(ascii: "-"),
                          UInt8(ascii: "\n")].contains(bytes[i - 1]) {
                return true
            }
        }
        return false
    }

    private static func contains(_ needle: String, in haystack: [UInt8]) -> Bool {
        let pattern = Array(needle.utf8)
        guard !pattern.isEmpty, pattern.count <= haystack.count else { return false }
        return haystack.withUnsafeBytes { text in
            pattern.withUnsafeBytes { memmem(text.baseAddress, text.count, $0.baseAddress, $0.count) != nil }
        }
    }

     
    private struct SectionHead {
        let lineEnd: Int
        let contentEnd: Int
        let valueStart: Int
        let value: String
    }

    private static func sectionHead(of line: TopLevelYAMLSections.KeyLine, in bytes: [UInt8]) -> SectionHead {
        var lineEnd = line.offset
        while lineEnd < bytes.count, bytes[lineEnd] != UInt8(ascii: "\n") { lineEnd += 1 }
        var contentEnd = lineEnd
        if contentEnd > line.offset, bytes[contentEnd - 1] == UInt8(ascii: "\r") { contentEnd -= 1 }
        let valueStart = line.offset + line.key.utf8.count + 1
        let value = String(decoding: bytes[valueStart..<contentEnd], as: UTF8.self).trimmingCharacters(in: .whitespaces)
        return SectionHead(lineEnd: lineEnd, contentEnd: contentEnd, valueStart: valueStart, value: value)
    }

     
     
     
     
     
     
     
    private static func edit(key: String, keys: [TopLevelYAMLSections.KeyLine], bytes: [UInt8],
                             newline: String, entries: [String]) throws -> Edit {
        guard let line = keys.first(where: { $0.key == key }) else {
            let at = keys.first?.offset ?? bytes.count
            let text = key + ":" + newline + entries.map { "  - " + $0 + newline }.joined()
            return Edit(start: at, end: at, replacement: Array(text.utf8))
        }
        let head = sectionHead(of: line, in: bytes)
        var start = head.contentEnd
         
        if isEmptySequence(head.value) {
            start = head.valueStart
        } else if !head.value.isEmpty, !head.value.hasPrefix("#") {
            throw ModuleInjectionError.unsupportedSectionLayout(key)
        }
        let first = firstContentLine(after: head.lineEnd, in: bytes)
        let indent = first.map { $0.isListItem ? String(repeating: " ", count: $0.indent) : "  " } ?? "  "
        let text = entries.map { newline + indent + "- " + $0 }.joined()
        return Edit(start: start, end: head.contentEnd, replacement: Array(text.utf8))
    }

     
     
     
     
    private static func hostsEdit(keys: [TopLevelYAMLSections.KeyLine], bytes: [UInt8], newline: String,
                                  entry: String) -> Edit? {
        guard let line = keys.first(where: { $0.key == "hosts" }) else {
            let at = keys.first?.offset ?? bytes.count
            return Edit(start: at, end: at, replacement: Array(("hosts:" + newline + "  " + entry + newline).utf8))
        }
        let head = sectionHead(of: line, in: bytes)
        var start = head.contentEnd
        if ["{}", "~", "null", "Null", "NULL"].contains(head.value) {
            start = head.valueStart
        } else if !head.value.isEmpty, !head.value.hasPrefix("#") {
            return nil
        }
        var indent = "  "
        if let first = firstContentLine(after: head.lineEnd, in: bytes), first.indent > 0 {
            indent = String(repeating: " ", count: first.indent)
        }
        return Edit(start: start, end: head.contentEnd, replacement: Array((newline + indent + entry).utf8))
    }

     
     
    private static func firstContentLine(after lineEnd: Int, in bytes: [UInt8]) -> (indent: Int, isListItem: Bool)? {
        var start = lineEnd + 1
        while start < bytes.count {
            var end = start
            while end < bytes.count, bytes[end] != UInt8(ascii: "\n") { end += 1 }
            var first = start
            while first < end, bytes[first] == UInt8(ascii: " ") { first += 1 }
            let blank = first == end || (first == end - 1 && bytes[first] == UInt8(ascii: "\r"))
            if !blank, bytes[first] != UInt8(ascii: "#") {
                let next = first + 1 < end ? bytes[first + 1] : UInt8(ascii: "\n")
                let isItem = bytes[first] == UInt8(ascii: "-")
                    && [UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\r"), UInt8(ascii: "\n")].contains(next)
                return (first - start, isItem)
            }
            start = end + 1
        }
        return nil
    }

     
     
    private static func apply(_ edits: [Edit], to bytes: [UInt8]) -> String {
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count + edits.reduce(0) { $0 + $1.replacement.count })
        var cursor = 0
        for edit in edits.enumerated().sorted(by: { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }).map(\.element) {
            out.append(contentsOf: bytes[cursor..<edit.start])
            out.append(contentsOf: edit.replacement)
            cursor = edit.end
        }
        out.append(contentsOf: bytes[cursor...])
        return String(decoding: out, as: UTF8.self)
    }
}

 

 
 
 
 
 
 
 
extension ModuleInjection {
     
     
    struct SettingsResult: Equatable {
        var text: String
        var skipped: [ModuleIgnoredEntry] = []
         
         
        var inEffect: [ModuleSettingInEffect] = []
         
         
        var logNotes: [String] = []
    }

     
     
     
     
     
     
     
     
    static func edits(of hosts: [ModuleHostMapping]) -> [ModuleConfigurationEdit] {
        var out: [ModuleConfigurationEdit] = []
        func one(_ values: [String]) -> OrderedJSON { values.count == 1 ? .string(values[0]) : .array(values.map(OrderedJSON.string)) }
        for mapping in hosts where mapping.pattern != certEntryHostName {
            let origin = mapping.origin
            func merge(_ path: [String], _ key: String, _ value: OrderedJSON) {
                out.append(ModuleConfigurationEdit(path: path, operation: .merge, valueJSON: OrderedJSON.object([(key, value)]).serialized(),
                                                    origin: origin))
            }
            if mapping.pattern.hasPrefix("ssid:") {
                guard case .dnsServers(let servers) = mapping.value else { continue }
                merge(["dns", "x-clash-ssid-nameservers"], String(mapping.pattern.dropFirst(5)), .array(servers.map(OrderedJSON.string)))
                continue
            }
            switch mapping.value {
            case .addresses(let addresses): merge(["hosts"], mapping.pattern, one(addresses))
            case .name(let name): merge(["hosts"], mapping.pattern, .string(name))
            case .dnsServers(let servers): merge(["dns", "nameserver-policy"], mapping.pattern, one(servers))
            case .systemDNS: merge(["dns", "nameserver-policy"], mapping.pattern, .string("system"))
            case .ipMode(let mode):
                let parameter: String
                switch mode {
                case "ipv4-only": parameter = "disable-ipv6=true"
                case "ipv6-only": parameter = "disable-ipv4=true"
                 
                default: continue
                }
                out.append(ModuleConfigurationEdit(path: ["dns", "nameserver-policy", mapping.pattern], operation: .nameserversWithParameter,
                                                    valueJSON: OrderedJSON.string(parameter).serialized(), origin: origin))
            }
        }
        return out
    }

     
     
     
    static func applyEdits(_ edits: [ModuleConfigurationEdit], hosts: [ModuleHostMapping], to text: String) -> SettingsResult {
        let all = edits + Self.edits(of: hosts)
        guard !all.isEmpty else { return SettingsResult(text: text) }
        var logNotes: [String] = []
        var inEffect: [ModuleSettingInEffect] = []
         
         
        func skip(_ edits: [ModuleConfigurationEdit], _ why: String) -> [ModuleIgnoredEntry] {
            edits.map { edit in
                let place = edit.path.joined(separator: ".")
                logNotes.append(#"\#(place.debugDescription): \#(why)"#)
                return ModuleIgnoredEntry(text: place, reason: .notApplicable(.doesNotApply), origin: edit.origin, moduleID: edit.moduleID)
            }
        }
        let mark = "\u{FEFF}"
        let hasMark = text.hasPrefix(mark)
        let body = hasMark ? String(text.dropFirst()) : text
        guard let keys = TopLevelYAMLSections.keyLines(of: body) else {
            let skipped = skip(all, #"the configuration is not written as one plain mapping"#)
            return SettingsResult(text: text, skipped: skipped, logNotes: logNotes)
        }
         
        var order: [String] = []
        var byKey: [String: [ModuleConfigurationEdit]] = [:]
        for edit in all where !edit.path.isEmpty {
            if byKey[edit.path[0]] == nil { order.append(edit.path[0]) }
            byKey[edit.path[0], default: []].append(edit)
        }
        var bytes = body
        var skipped: [ModuleIgnoredEntry] = []
        var replacements: [(range: Range<Int>, text: String)] = []
         
         
        let newline = bytes.withUTF8 { buffer -> String in
            guard let end = buffer.firstIndex(of: UInt8(ascii: "\n")), end > 0, buffer[end - 1] == UInt8(ascii: "\r") else { return "\n" }
            return "\r\n"
        }
        let firstKey = keys.first?.offset ?? body.utf8.count
        bytes.withUTF8 { buffer in
            for key in order {
                guard let edits = byKey[key] else { continue }
                let index = keys.firstIndex { $0.key == key }
                let range = index.map { keys[$0].offset..<($0 + 1 < keys.count ? keys[$0 + 1].offset : buffer.count) }
                let section = range.map { String(decoding: UnsafeBufferPointer(rebasing: buffer[$0]), as: UTF8.self) }
                 
                 
                 
                if key == "proxy-groups", edits.allSatisfy({ $0.path.count == 1 && [.append, .prepend].contains($0.operation) }),
                   let inserted = insertItems(edits, section: section, range: range, at: firstKey, newline: newline) {
                    replacements += inserted
                    continue
                }
                var tree: OrderedJSON?
                if let section {
                    if TopLevelYAMLSections.mentionsAnchorOrAlias(inBytes: UnsafeBufferPointer(rebasing: buffer[range!])) {
                        skipped += skip(edits, "the configuration's \(key) uses YAML anchors")
                        continue
                    }
                    do {
                        let json = try ConfigTransforms.yamlToJSON(section, omitting: [])
                        guard case .object(let pairs) = try OrderedJSON.parse(json) else { throw CocoaError(.propertyListReadCorrupt) }
                        tree = pairs.first { $0.key == key }?.value
                        if tree == .scalar("null") { tree = nil }
                    } catch {
                        skipped += skip(edits, AuthoredText.of(error).englishText)
                        continue
                    }
                }
                 
                if tree == nil, key == "listeners" { tree = .array([]) }
                let original = tree
                var changed = false
                 
                 
                var ruleFront = 0
                for edit in sequenced(edits) {
                     
                     
                    if key == "proxies" {
                        let node = edit.path.dropFirst().first ?? ""
                        guard case .array(let items)? = tree, items.contains(where: {
                            named($0) == node && value(at: ["type"], in: $0) == .string("wireguard")
                        }) else {
                            skipped.append(ModuleIgnoredEntry(text: edit.path.joined(separator: "."), reason: .policyNotFound(node),
                                                               origin: edit.origin, moduleID: edit.moduleID))
                            continue
                        }
                    }
                     
                    if edit.condition == .fakeIPFilter {
                        switch fakeIPFilter(edit, on: &tree, ruleFront: &ruleFront) {
                        case .written(let leftOut):
                            changed = true
                            skipped += leftOut
                        case .inEffect: inEffect.append(ModuleSettingInEffect(key: "dns.fake-ip-filter", origin: edit.origin))
                        case .leftOut(let leftOut): skipped += leftOut
                        }
                        continue
                    }
                    switch apply(edit, at: edit.path.dropFirst(), to: &tree) {
                    case .applied: changed = true
                    case .notNeeded: break
                    case .refused(let why): skipped += skip([edit], why)
                    }
                }
                guard changed else { continue }
                 
                 
                if key == "dns" { logNotes += reconcileFakeIPFilterMode(original: original, in: &tree) }
                 
                 
                keepTheAppsEntries(key, original: original, in: &tree)
                guard let tree else { continue }
                let written = key + ":" + block(tree, indent: 0, newline: newline) + newline
                if let range {
                    replacements.append((range, written))
                } else {
                    replacements.append((firstKey..<firstKey, written))
                }
            }
        }
        guard !replacements.isEmpty else { return SettingsResult(text: text, skipped: skipped, inEffect: inEffect, logNotes: logNotes) }
        var out = [UInt8]()
        out.reserveCapacity(body.utf8.count + replacements.reduce(0) { $0 + $1.text.utf8.count })
        bytes.withUTF8 { buffer in
            var cursor = 0
             
             
            let ordered = replacements.enumerated().sorted { a, b in
                (a.element.range.lowerBound, a.element.range.isEmpty ? 0 : 1, a.offset)
                    < (b.element.range.lowerBound, b.element.range.isEmpty ? 0 : 1, b.offset)
            }.map(\.element)
            for replacement in ordered {
                out.append(contentsOf: UnsafeBufferPointer(rebasing: buffer[cursor..<replacement.range.lowerBound]))
                out.append(contentsOf: Array(replacement.text.utf8))
                cursor = replacement.range.upperBound
            }
            out.append(contentsOf: UnsafeBufferPointer(rebasing: buffer[cursor..<buffer.count]))
        }
        if hasMark { out.insert(contentsOf: Array(mark.utf8), at: 0) }
        return SettingsResult(text: String(decoding: out, as: UTF8.self), skipped: skipped, inEffect: inEffect, logNotes: logNotes)
    }

    private enum FakeIPFilterWrite {
         
        case written([ModuleIgnoredEntry])
         
        case inEffect
         
        case leftOut([ModuleIgnoredEntry])
    }

     
     
     
     
     
     
     
     
    private static func fakeIPFilter(_ edit: ModuleConfigurationEdit, on tree: inout OrderedJSON?, ruleFront: inout Int) -> FakeIPFilterWrite {
        guard case .array(let items)? = try? OrderedJSON.parse(edit.valueJSON) else { return .leftOut([]) }
        var mode = "blacklist"
        if case .string(let declared)? = value(at: ["fake-ip-filter-mode"], in: tree) { mode = declared.lowercased() }
        if mode == "whitelist" { return .inEffect }
        func field(_ item: OrderedJSON, _ name: String) -> String? {
            guard case .object(let pairs) = item, case .string(let text)? = pairs.first(where: { $0.key == name })?.value else { return nil }
            return text
        }
        var existing: [OrderedJSON] = []
        switch value(at: ["fake-ip-filter"], in: tree) {
        case .array(let list)?: existing = list
        case nil where mode != "rule": existing = ConfigTransforms.kernelDefaultFakeIPFilter.map(OrderedJSON.string)
        default: break
        }
        var leftOut: [ModuleIgnoredEntry] = []
        var list: [OrderedJSON]
        if mode == "rule" {
            let rules = items.compactMap { field($0, "rule").map { OrderedJSON.string($0 + ",real-ip") } }
            guard !rules.isEmpty else { return .leftOut([]) }
            switch edit.operation {
            case .replace:
                list = rules
                ruleFront = rules.count
            case .prepend:
                list = rules + existing.filter { !rules.contains($0) }
                ruleFront += rules.count
            default:
                let added = rules.filter { !existing.contains($0) }
                list = existing
                list.insert(contentsOf: added, at: min(ruleFront, list.count))
                ruleFront += added.count
            }
        } else {
            var names: [OrderedJSON] = []
            for item in items {
                if let name = field(item, "name") {
                    names.append(.string(name))
                } else if case .object(let pairs) = item, pairs.contains(where: { $0.key == "set" }) {
                     
                    continue
                } else {
                    let written = field(item, "item") ?? item.serialized()
                    leftOut.append(ModuleIgnoredEntry(text: written, reason: .invalidHost(written), origin: edit.origin,
                                                       moduleID: edit.moduleID))
                }
            }
            guard !names.isEmpty else { return .leftOut(leftOut) }
            switch edit.operation {
            case .replace: list = names
            case .prepend: list = names + existing.filter { !names.contains($0) }
            default: list = existing + names.filter { !existing.contains($0) }
            }
        }
        guard modify(&tree, at: ["fake-ip-filter"], creating: true, { $0 = .array(list) }) else { return .leftOut(leftOut) }
        return .written(leftOut)
    }

     
     
     
     
     
     
     
     
     
    private static func reconcileFakeIPFilterMode(original: OrderedJSON?, in tree: inout OrderedJSON?) -> [String] {
        func mode(_ root: OrderedJSON?) -> String {
            if case .string(let declared)? = value(at: ["fake-ip-filter-mode"], in: root) { return declared.lowercased() }
            if case .scalar(let declared)? = value(at: ["fake-ip-filter-mode"], in: root) { return declared.lowercased() }
            return "blacklist"
        }
        let before = mode(original), after = mode(tree)
        guard before != after, case .array(let items)? = value(at: ["fake-ip-filter"], in: tree) else { return [] }
        var out: [OrderedJSON] = []
        var leftOut: [String] = []
        for item in items {
            let text: String
            switch item {
            case .string(let written), .scalar(let written): text = written
            default:
                leftOut.append(item.serialized())
                continue
            }
            let fields = text.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
             
             
             
             
            let action = StructuredRule.coreTargetIndex(head: fields[0], fieldCount: fields.count).map { fields[$0] }
            let isRule = action != nil
            if after == "rule" {
                if isRule {
                    out.append(item)
                } else if text.lowercased().hasPrefix("rule-set:") {
                    let made = OrderedJSON.string("RULE-SET," + text.dropFirst("rule-set:".count) + (before == "whitelist" ? ",fake-ip" : ",real-ip"))
                    if !out.contains(made) { out.append(made) }
                } else if case .object(let made)? = ModuleSettingsMapping.fakeIPFilterItem(kernel: text),
                          case .string(let rule)? = made.first(where: { $0.key == "rule" })?.value {
                    let made = OrderedJSON.string(rule + (before == "whitelist" ? ",fake-ip" : ",real-ip"))
                    if !out.contains(made) { out.append(made) }
                } else {
                    leftOut.append(text)
                }
                continue
            }
            guard isRule else {
                out.append(item)
                continue
            }
             
            let wanted = after == "whitelist" ? "fake-ip" : "real-ip"
            let name: String?
            if action?.lowercased() == wanted {
                switch fields[0].uppercased() {
                case "DOMAIN": name = fields[1].lowercased()
                case "DOMAIN-SUFFIX": name = "+." + fields[1].lowercased()
                case "GEOSITE": name = "geosite:" + fields[1]
                case "RULE-SET": name = "rule-set:" + fields[1]
                default: name = nil
                }
            } else {
                name = nil
            }
            if let name, ModuleYAMLText.isOneLine(name) {
                if !out.contains(.string(name)) { out.append(.string(name)) }
            } else {
                leftOut.append(text)
            }
        }
        _ = modify(&tree, at: ["fake-ip-filter"], creating: true) { $0 = .array(out) }
        guard !leftOut.isEmpty else { return [] }
        return [#"dns.fake-ip-filter: a module set fake-ip-filter-mode "# + after + #"; left out what that mode cannot say: "#
                + leftOut.map(\.debugDescription).joined(separator: ", ")]
    }

     
     
     
     
     
     
     
     
     
    private static func keepTheAppsEntries(_ key: String, original: OrderedJSON?, in tree: inout OrderedJSON?) {
        func list(_ path: ArraySlice<String>, _ root: OrderedJSON?) -> [OrderedJSON] {
            if case .array(let items)? = value(at: path, in: root) { return items }
            return []
        }
        func holds(_ items: [OrderedJSON], _ text: String) -> Bool { items.contains(.string(text)) || items.contains(.scalar(text)) }
        switch key {
        case "dns":
            let entry = ConfigTransforms.apnsFakeIPFilterEntry
            let rule = ConfigTransforms.apnsFakeIPFilterRule
            let had = list(["fake-ip-filter"], original)
            if holds(had, entry) || holds(had, rule) {
                var mode = "blacklist"
                if case .string(let declared)? = value(at: ["fake-ip-filter-mode"], in: tree) { mode = declared.lowercased() }
                var now = list(["fake-ip-filter"], tree)
                if mode == "rule", !holds(now, rule) {
                    now.insert(.string(rule), at: 0)
                    _ = modify(&tree, at: ["fake-ip-filter"], creating: true) { $0 = .array(now) }
                } else if mode == "blacklist", !holds(now, entry) {
                    if value(at: ["fake-ip-filter"], in: tree) == nil { now = ConfigTransforms.kernelDefaultFakeIPFilter.map(OrderedJSON.string) }
                    now.append(.string(entry))
                    _ = modify(&tree, at: ["fake-ip-filter"], creating: true) { $0 = .array(now) }
                }
            }
            for name in ["default-nameserver", "proxy-server-nameserver"] {
                let before = list([name], original)
                var now = list([name], tree)
                let missing = ConfigTransforms.dnsBootstrapFallbacks.filter { holds(before, $0) && !holds(now, $0) }
                guard !missing.isEmpty else { continue }
                now += missing.map(OrderedJSON.string)
                _ = modify(&tree, at: [name], creating: true) { $0 = .array(now) }
            }
        case "hosts":
            let name = certEntryHostName
            guard let entry = value(at: [name], in: original), value(at: [name], in: tree) == nil,
                  case .object(var pairs) = tree ?? .object([]) else { return }
            pairs.insert((name, entry), at: 0)
            tree = .object(pairs)
        default:
            return
        }
    }

     
     
     
    private static func sequenced(_ edits: [ModuleConfigurationEdit]) -> [ModuleConfigurationEdit] {
        func rank(_ edit: ModuleConfigurationEdit) -> Int {
            if edit.condition == .plainNameserver { return 1 }
            switch edit.operation {
            case .copyIfAbsent: return 2
            case .serverParameter: return 3
            case .nameserversWithParameter: return 4
            default: return 0
            }
        }
        return edits.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }

    private enum Applied: Equatable {
        case applied
        case notNeeded
        case refused(String)
    }

     
    private static func apply(_ edit: ModuleConfigurationEdit, at path: ArraySlice<String>, to root: inout OrderedJSON?) -> Applied {
        guard let given = try? OrderedJSON.parse(edit.valueJSON) else { return .refused(#"the value is not JSON"#) }
        var path = path
        if edit.condition == .plainNameserver, path.last == "nameserver",
           case .array(let servers)? = value(at: ["nameserver"], in: root),
           servers.contains(where: { if case .string(let server) = $0 { return ModuleSettingsMapping.isEncrypted(server) } else { return false } }) {
            path = ["default-nameserver"]
        }
        if edit.condition == .whereWritten, value(at: path, in: root) == nil { return .notNeeded }
        var result = Applied.applied
         
        let before = root
        let reached = modify(&root, at: path, creating: edit.operation != .serverParameter) { current in
            switch edit.operation {
            case .replace:
                current = given
            case .replaceIfAbsent:
                if current == nil { current = given } else { result = .notNeeded }
            case .append, .prepend:
                guard case .array(let items) = given else { result = .refused(#"the value is not a list"#); return }
                var existing: [OrderedJSON] = []
                switch current {
                case .array(let list)?: existing = list
                case nil: existing = []
                case let one?: existing = [one]
                }
                current = .array(edit.operation == .append
                                 ? existing + items.filter { !existing.contains($0) }
                                 : items + existing.filter { !items.contains($0) })
            case .merge:
                current = merged(given, over: current)
            case .copyIfAbsent:
                guard current == nil else { result = .notNeeded; return }
                guard case .array(let steps) = given else { result = .refused(#"the source is not a path"#); return }
                let source = steps.dropFirst().compactMap { step -> String? in if case .string(let text) = step { return text } else { return nil } }
                 
                 
                current = value(at: ArraySlice(source), in: before)
                    ?? (source == ["nameserver"] ? .array(kernelDefaultNameservers.map(OrderedJSON.string)) : nil)
                if current == nil { result = .notNeeded }
            case .serverParameter:
                guard case .string(let parameter) = given, case .array(let servers)? = current else { result = .notNeeded; return }
                current = .array(servers.map { server in
                    guard case .string(let text) = server, ModuleSettingsMapping.isEncrypted(text) else { return server }
                    return .string(adding(parameter, to: text))
                })
            case .nameserversWithParameter:
                guard case .string(let parameter) = given else { result = .refused(#"the value is not a parameter"#); return }
                var servers: [String] = []
                if case .array(let written)? = value(at: ["nameserver"], in: before) {
                    servers = written.compactMap { if case .string(let text) = $0 { return text } else { return nil } }
                }
                 
                if servers.isEmpty { servers = kernelDefaultNameservers }
                current = .array(servers.map { .string(adding(parameter, to: $0 == "system" ? "system://" : $0)) })
            case .engineRoute:
                 
                result = .notNeeded
            }
        }
        if !reached { return edit.operation == .serverParameter ? .notNeeded : .refused(#"the place it goes is not a mapping"#) }
        if edit.operation == .nameserversWithParameter, case .applied = result, path.count >= 2 {
             
            let name = path[path.endIndex - 1]
            let parent = Array(path.dropLast())
            if case .object(var pairs)? = value(at: ArraySlice(parent), in: root), let index = pairs.firstIndex(where: { $0.key == name }) {
                let pair = pairs.remove(at: index)
                pairs.insert(pair, at: 0)
                _ = modify(&root, at: ArraySlice(parent), creating: false) { $0 = .object(pairs) }
            }
        }
        return result
    }

     
     
    static let kernelDefaultNameservers = ["https://doh.pub/dns-query", "tls://223.5.5.5:853"]

     
    private static func adding(_ parameter: String, to server: String) -> String {
        let name = parameter.split(separator: "=").first.map(String.init) ?? parameter
        guard let hash = server.firstIndex(of: "#") else { return server + "#" + parameter }
        let fragment = server[server.index(after: hash)...]
        if fragment.split(separator: "&").contains(where: { $0.split(separator: "=").first.map(String.init) == name }) { return server }
        return server + (fragment.isEmpty ? "" : "&") + parameter
    }

     
     
     
    private static func merged(_ module: OrderedJSON, over reader: OrderedJSON?) -> OrderedJSON {
        guard case .object(let mine) = module, case .object(let theirs)? = reader else { return module }
        var out: [(key: String, value: OrderedJSON)] = []
        for pair in mine {
            out.append((pair.key, merged(pair.value, over: theirs.first { $0.key == pair.key }?.value)))
        }
        for pair in theirs where !mine.contains(where: { $0.key == pair.key }) { out.append(pair) }
        return .object(out)
    }

     
     
    private static func value(at path: ArraySlice<String>, in root: OrderedJSON?) -> OrderedJSON? {
        guard let step = path.first else { return root }
        switch root {
        case .object(let pairs)?: return value(at: path.dropFirst(), in: pairs.first { $0.key == step }?.value)
        case .array(let items)?: return value(at: path.dropFirst(), in: items.first { named($0) == step })
        default: return nil
        }
    }

    private static func named(_ item: OrderedJSON) -> String? {
        guard case .object(let pairs) = item, case .string(let name)? = pairs.first(where: { $0.key == "name" })?.value else { return nil }
        return name
    }

     
     
     
    private static func modify(_ root: inout OrderedJSON?, at path: ArraySlice<String>, creating: Bool,
                               _ body: (inout OrderedJSON?) -> Void) -> Bool {
        guard let step = path.first else {
            body(&root)
            return true
        }
        switch root {
        case nil:
            guard creating else { return false }
            var child: OrderedJSON?
            guard modify(&child, at: path.dropFirst(), creating: creating, body) else { return false }
            if let child { root = .object([(step, child)]) }
            return true
        case .object(var pairs)?:
            let index = pairs.firstIndex { $0.key == step }
            var child = index.map { pairs[$0].value }
            if child == .scalar("null") { child = nil }
            guard modify(&child, at: path.dropFirst(), creating: creating, body) else { return false }
            if let index {
                if let child { pairs[index].value = child }
            } else if let child {
                pairs.append((step, child))
            }
            root = .object(pairs)
            return true
        case .array(var items)?:
             
            let index = items.firstIndex { named($0) == step }
            var child = index.map { items[$0] }
            if child == nil {
                guard creating else { return false }
                child = .object([("name", .string(step))])
            }
            guard modify(&child, at: path.dropFirst(), creating: creating, body), let child else { return false }
            if let index { items[index] = child } else { items.append(child) }
            root = .array(items)
            return true
        default:
            return false
        }
    }

     
     
     
     
    private static func insertItems(_ edits: [ModuleConfigurationEdit], section: String?, range: Range<Int>?, at firstKey: Int,
                                    newline: String) -> [(range: Range<Int>, text: String)]? {
        var front: [OrderedJSON] = []
        var back: [OrderedJSON] = []
        for edit in edits {
            guard case .array(let items)? = try? OrderedJSON.parse(edit.valueJSON) else { return nil }
            if edit.operation == .prepend { front.insert(contentsOf: items, at: 0) } else { back += items }
        }
        let key = edits[0].path[0]
        func lines(_ items: [OrderedJSON], _ indent: String) -> String {
            items.map { newline + indent + "- " + $0.serialized() }.joined()
        }
        guard let section, let range else {
            return [(firstKey..<firstKey, key + ":" + lines(front + back, "  ") + newline)]
        }
        let all = section.components(separatedBy: "\n")
        let head = all[0].replacingOccurrences(of: "\r", with: "")
        let value = head.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
        if ["[]", "~", "null", "Null", "NULL"].contains(value) {
            return [(range, key + ":" + lines(front + back, "  ") + newline)]
        }
        guard value.isEmpty || value.hasPrefix("#") else { return nil }
         
        var indent: String?
        var lastContentEnd = range.lowerBound + all[0].utf8.count
        var offset = range.lowerBound + all[0].utf8.count + 1
        for line in all.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\r", with: "")
            if !trimmed.isEmpty, !trimmed.hasPrefix("#") {
                if indent == nil {
                    guard trimmed.hasPrefix("-") else { return nil }
                    indent = String(line.prefix { $0 == " " })
                }
                lastContentEnd = offset + line.replacingOccurrences(of: "\r", with: "").utf8.count
            }
            offset += line.utf8.count + 1
        }
        let at = indent ?? "  "
        let headEnd = range.lowerBound + head.utf8.count
        var out: [(range: Range<Int>, text: String)] = []
        if !front.isEmpty { out.append((headEnd..<headEnd, lines(front, at))) }
        if !back.isEmpty { out.append((lastContentEnd..<lastContentEnd, lines(back, at))) }
        return out
    }

     
     
     
     
     
     
    private static func block(_ value: OrderedJSON, indent: Int, newline: String) -> String {
        let pad = String(repeating: " ", count: indent + 2)
        switch value {
        case .object(let pairs):
            guard !pairs.isEmpty else { return " {}" }
            return pairs.map { pair in
                let key = OrderedJSON.string(pair.key).serialized()
                if key.utf8.count > 1000 {
                    return newline + pad + "? " + key + newline + pad + ":" + block(pair.value, indent: indent + 2, newline: newline)
                }
                return newline + pad + key + ":" + block(pair.value, indent: indent + 2, newline: newline)
            }.joined()
        case .array(let items):
            guard !items.isEmpty else { return " []" }
            return items.map { newline + pad + "- " + $0.serialized() }.joined()
        case .string, .scalar:
            return " " + value.serialized()
        }
    }
}
