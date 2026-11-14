import ClashClientKit
import ClashClientUI
import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum ModuleRuleSetSyntax {
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    #if os(macOS)
    static let maximumHeldWeight = Int.max
    #else
    static let maximumHeldWeight = 40_000
    #endif
     
     
    static let regexWeight = 20
     
     
     
     
     
     
     
     
    static let maximumListRuleBytes = Int.max
     
     
    static let maximumModuleKeptBytes = Int.max
     
     
    static let maximumListBytes = 16 << 20
     
    static let minimumListInterval = 3_600

     
     
    static let keywordLimit = 20_000
    static let regexLimit = 1_000
    static let othersLimit = 20_000

     
    static let lanProviderName = ClashModuleRuleSetNames.lan
    static let systemProviderName = ClashModuleRuleSetNames.system
     
     
    static let engineProviderPrefix = "module-engine-"

     

     
     
     
     
     
     
     
    static func line(_ fields: ModuleRuleMapping.Fields, family: ModuleFormat,
                     origin: ModuleLineOrigin) -> Result<ModuleRuleSet, ModuleIgnoredReason> {
        let value = fields.payload.joined(separator: ",").trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, ModuleYAMLText.isOneLine(value), !value.contains(",") else { return .failure(.unreadableLine) }
        let policy = ModuleRuleMapping.policy(fields.policy, family: family)
        var params: [String] = []
        var interval: Int?
        for option in fields.options {
            let lowered = option.lowercased()
            if ModuleRuleMapping.kernelOptions.contains(lowered) {
                if !params.contains(lowered) { params.append(lowered) }
            } else if lowered.hasPrefix("update-interval=") {
                 
                 
                interval = Int(lowered.dropFirst("update-interval=".count).trimmingCharacters(in: .whitespaces))
            }
        }
        func set(url: String?, kind: ModuleRuleSetKind, name: String? = nil) -> ModuleRuleSet {
            ModuleRuleSet(url: url, inline: nil, kind: kind, policy: policy, params: params, interval: interval, origin: origin, name: name)
        }
        switch fields.type {
        case "DOMAIN-SET":
            guard family != .stash else { return .failure(.unsupportedRuleType("DOMAIN-SET")) }
            if isAddress(value) { return .success(set(url: value, kind: .domainSet)) }
             
            return .failure(.platformCannot(.remoteRelativeFile))
        case "RULE-SET":
             
            if family == .stash { return .success(set(url: nil, kind: .classical, name: value)) }
            if isAddress(value) { return .success(set(url: value, kind: .classical)) }
            switch value.uppercased() {
            case "LAN": return .success(set(url: nil, kind: .builtInLAN))
            case "SYSTEM": return .success(set(url: nil, kind: .builtInSystem))
            default: break
            }
             
            if value.contains("/") || value.contains("\\") || [".list", ".txt", ".conf", ".yaml"].contains(where: value.lowercased().hasSuffix) {
                return .failure(.platformCannot(.remoteRelativeFile))
            }
            return .success(set(url: nil, kind: .classical, name: value))
        default:
            return .failure(.unreadableLine)
        }
    }

     
    static func isAddress(_ value: String) -> Bool {
        let lowered = value.lowercased()
        guard lowered.hasPrefix("https://") || lowered.hasPrefix("http://"),
              let url = URL(string: value), let host = url.host, !host.isEmpty else { return false }
        return !value.contains(" ")
    }

     
     
     
    static func add(_ set: ModuleRuleSet, to sets: inout [ModuleRuleSet]) {
        guard let index = sets.firstIndex(where: { $0.reference == set.reference }) else {
            sets.append(set)
            return
        }
        guard let lines = set.inline else { return }
        var merged = sets[index].inline ?? []
        for line in lines where !merged.contains(line) { merged.append(line) }
        sets[index].inline = merged
    }

     
     
     
     
     
     
     
     
     
    static func takeSection(_ name: String, lines: [(text: String, origin: ModuleLineOrigin)], family: ModuleFormat,
                            platform: ModulePlatform, check: ModuleRuleMapping.Check = ModuleRuleMapping.kernelCheck,
                            into ir: inout ModuleIR) {
        guard let first = lines.first else { return }
        let policy = ir.routingRules.first { $0.head == "RULE-SET," + name }?.policy ?? .builtIn("DIRECT")
        let target = policy.writtenName ?? "PROXY"
        var kernel: [String] = []
        for (text, origin) in lines {
            func ignore(_ reason: ModuleIgnoredReason) { ir.ignored.append(ModuleIgnoredEntry(text: text, reason: reason, origin: origin)) }
            let mapped: ModuleRuleMapping.Mapped
            do {
                mapped = try ModuleRuleMapping.map(text + "," + target, family: family, platform: platform, origin: origin, check: check)
            } catch {
                ignore(.unreadableLine)
                continue
            }
            switch mapped.outcome {
            case .kernel(let rule):
                let line = ([rule.head] + rule.params).joined(separator: ",")
                if !kernel.contains(line) { kernel.append(line) }
            case .engine(let rule):
                ir.engineRules.append(rule)
            case .rewrite(let pattern, let action, let written):
                ir.rewriteRules.append(ModuleRewriteRule(pattern: pattern, actions: [action], origin: origin, policy: written))
            case .ruleSet:
                 
                ignore(.unsupportedRuleType(text.prefix { $0 != "," }.uppercased()))
            case .ignored(let reason):
                ignore(reason)
            }
            for reason in mapped.setAside { ignore(reason) }
        }
        guard !kernel.isEmpty else { return }
        add(ModuleRuleSet(url: nil, inline: kernel, kind: .classical, policy: .builtIn("DIRECT"), params: [], interval: nil,
                           origin: first.origin, name: name), to: &ir.ruleSets)
    }

     

     
     
     
     
     
     
    static func stashProvider(_ name: String, _ value: OrderedJSON, origin: ModuleLineOrigin) -> Result<ModuleRuleSet, ModuleIgnoredReason> {
        guard case .object(let fields) = value, !name.isEmpty, ModuleYAMLText.isOneLine(name) else { return .failure(.unreadableLine) }
        func field(_ key: String) -> OrderedJSON? { fields.first { $0.key.lowercased() == key }?.value }
        func text(_ key: String) -> String? { ModuleStashParser.scalar(field(key))?.trimmingCharacters(in: .whitespaces) }
        let type = text("type")?.lowercased() ?? "http"
        let behavior = text("behavior")?.lowercased() ?? ""
        let format = text("format")?.lowercased() ?? "yaml"
        guard ["domain", "ipcidr", "classical"].contains(behavior), ["yaml", "text", "mrs"].contains(format) else {
            return .failure(.unreadableLine)
        }
         
         
        if format == "mrs", behavior == "classical" { return .failure(.unreadableLine) }
        var interval: Int?
        if let written = text("interval") { interval = Int(written) }
        var headers: [String: [String]]?
        if case .object(let pairs)? = field("headers") ?? field("header") {
            var made: [String: [String]] = [:]
            for (key, value) in pairs where ModuleYAMLText.isOneLine(key) {
                switch value {
                case .array(let items): made[key] = items.compactMap(ModuleStashParser.scalar).filter(ModuleYAMLText.isOneLine)
                default: if let one = ModuleStashParser.scalar(value), ModuleYAMLText.isOneLine(one) { made[key] = [one] }
                }
            }
            headers = made.isEmpty ? nil : made
        }
        let kind = ModuleRuleSetKind.provider(behavior: behavior, format: format)
        switch type {
        case "http":
            guard let url = text("url"), isAddress(url) else { return .failure(.unreadableLine) }
            return .success(ModuleRuleSet(url: url, inline: nil, kind: kind, policy: .builtIn("DIRECT"), params: [], interval: interval,
                                           origin: origin, name: name, headers: headers))
        case "inline":
            guard case .array(let items)? = field("payload") else { return .failure(.unreadableLine) }
            let payload = items.compactMap(ModuleStashParser.scalar).map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && ModuleYAMLText.isOneLine($0) }
            guard !payload.isEmpty else { return .failure(.unreadableLine) }
            return .success(ModuleRuleSet(url: nil, inline: payload, kind: .provider(behavior: behavior, format: "inline"), policy: .builtIn("DIRECT"),
                                           params: [], interval: nil, origin: origin, name: name))
        case "file":
            return .failure(.platformCannot(.remoteRelativeFile))
        default:
            return .failure(.unreadableLine)
        }
    }

     

     
     
     
     
     
    static func providerName(moduleID: String, url: String) -> String {
        let id = String(moduleID.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(8))
        let padded = id + String(repeating: "0", count: max(0, 8 - id.count))
        return "module-" + padded + "-" + String(ModuleJSON.sha256(Data(url.utf8)).prefix(8))
    }

     
    static func providerName(inline name: String) -> String {
        "module-ruleset-" + String(ModuleJSON.sha256(Data(name.utf8)).prefix(8))
    }

     
     
     
     
    static func readersOwn(_ providers: [String: Any]) -> [String: Any] {
        providers.filter { name, definition in
            !isModuleProviderName(name) && ((definition as? [String: Any])?["x-clash-module"] as? Bool) != true
        }
    }

     
     
    static func isModuleNotice(_ notice: String) -> Bool {
        guard notice.hasPrefix("rule-providers.") else { return false }
        let rest = notice.dropFirst("rule-providers.".count)
        let name = rest.prefix { $0 != ":" && $0 != "." }
        return isModuleProviderName(String(name))
    }

     
     
    static func isModuleProviderName(_ name: String) -> Bool {
        ClashModuleRuleSetNames.isReserved(name)
    }

     

     
    struct Converted: Equatable {
         
         
        var kernelLines: [String] = []
         
         
         
        var rewriteRules: [ModuleRewriteRule] = []
         
        var rewriteBytes = 0
         
         
         
         
        var skipped = 0
         
         
         
        var heapLines = 0
         
        var tooHeavy = false
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func convert(_ text: String, kind: ModuleRuleSetKind, policy: ModuleRulePolicy, origin: ModuleLineOrigin,
                        family: ModuleFormat = .surge, platform: ModulePlatform = .current) -> Converted {
        var out = Converted()
        switch kind {
        case .domainSet:
            for raw in listLines(text) {
                if let name = domainSetName(raw) { out.kernelLines.append(name) } else { out.skipped += 1 }
            }
        case .provider(let behavior, let format):
            guard behavior == "classical" else {
                out.kernelLines = format == "yaml" ? yamlPayload(text) ?? [] : listLines(text).map(String.init)
                return out
            }
            let lines = format == "yaml" ? yamlPayload(text) ?? [] : listLines(text).map(String.init)
            var counter = HeavyCounter()
            for line in lines {
                 
                let type = line.prefix { $0 != "," }.trimmingCharacters(in: .whitespaces).uppercased()
                if ["USER-AGENT", "URL-REGEX"].contains(type) || (ModuleRoutingRule.logicTypes.contains(type)
                    && (line.uppercased().contains("(USER-AGENT,") || line.uppercased().contains("(URL-REGEX,"))) {
                    take(line + "," + (policy.writtenName ?? "PROXY"), family: .stash, platform: platform, origin: origin, into: &out)
                    continue
                }
                out.kernelLines.append(line)
                counter.count(line)
            }
            out.heapLines = counter.heap
            out.tooHeavy = counter.tooHeavy
        case .classical, .builtInLAN, .builtInSystem:
            var counter = HeavyCounter()
            let target = policy.writtenName ?? "PROXY"
            for raw in listLines(text) {
                let line = ModuleParser.strippingComment(String(raw)).trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty else { continue }
                if let fast = plainKernelLine(line) {
                    out.kernelLines.append(fast)
                    counter.count(fast)
                    continue
                }
                let before = out.kernelLines.count
                take(line + "," + target, family: family, platform: platform, origin: origin, into: &out)
                for added in out.kernelLines[before...] { counter.count(added) }
            }
            out.heapLines = counter.heap
            out.tooHeavy = counter.tooHeavy
        }
        return out
    }

     
    private static func take(_ line: String, family: ModuleFormat, platform: ModulePlatform, origin: ModuleLineOrigin,
                             into out: inout Converted) {
         
         
         
        let mapped: ModuleRuleMapping.Mapped
        do {
            mapped = try ModuleRuleMapping.map(line, family: family, platform: platform, origin: origin, check: { _ in nil })
        } catch {
            out.skipped += 1
            return
        }
        switch mapped.outcome {
        case .kernel(let rule):
            out.kernelLines.append(([rule.head] + rule.params).joined(separator: ","))
        case .rewrite(let pattern, let action, let written):
             
             
             
             
             
            guard out.rewriteBytes + pattern.utf8.count <= maximumListRuleBytes else {
                out.skipped += 1
                return
            }
            let rule = ModuleRewriteRule(pattern: pattern, actions: [action], origin: origin, policy: written)
            let bytes = encodedBytes(rule)
            guard out.rewriteBytes + bytes <= maximumListRuleBytes else {
                out.skipped += 1
                return
            }
            out.rewriteRules.append(rule)
            out.rewriteBytes += bytes
        case .engine, .ruleSet, .ignored:
             
             
             
            out.skipped += 1
        }
    }

     
     
    static func listLines(_ text: String) -> [Substring] {
         
         
         
        var out: [Substring] = []
        let bytes = text.utf8
        func blank(_ byte: UInt8) -> Bool { byte == 0x20 || byte == 0x09 || byte == 0x0D }
        for slice in bytes.split(omittingEmptySubsequences: true, whereSeparator: { $0 == 0x0A || $0 == 0x0D }) {
            var start = slice.startIndex, end = slice.endIndex
             
            if bytes[start...].starts(with: [0xEF, 0xBB, 0xBF]) { start = bytes.index(start, offsetBy: 3) }
            while start < end, blank(bytes[start]) { start = bytes.index(after: start) }
            while end > start, blank(bytes[bytes.index(before: end)]) { end = bytes.index(before: end) }
            guard start < end else { continue }
            let first = bytes[start]
            if first == UInt8(ascii: "#") || first == UInt8(ascii: ";") { continue }
            if first == UInt8(ascii: "/"), bytes.index(after: start) < end, bytes[bytes.index(after: start)] == UInt8(ascii: "/") { continue }
            out.append(text[start..<end])
        }
        return out
    }

     
     
    static func yamlPayload(_ text: String) -> [String]? {
        guard let json = try? ConfigTransforms.yamlToJSON(text, omitting: []),
              case .object(let root)? = try? OrderedJSON.parse(json),
              case .array(let items)? = root.first(where: { $0.key == "payload" })?.value else { return nil }
        return items.compactMap(ModuleStashParser.scalar).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

     
     
    static func domainSetName(_ line: Substring) -> String? {
        var name = line.lowercased()
        var suffix = false
        if name.hasPrefix(".") {
            suffix = true
            name.removeFirst()
        }
        guard !name.isEmpty, name.utf8.count <= 253, !name.hasPrefix("."), !name.hasSuffix("."), !name.contains("..") else { return nil }
        for byte in name.utf8 {
            switch byte {
            case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "-"), UInt8(ascii: "_"), UInt8(ascii: "."):
                continue
            case 0x80...0xFF:
                continue
            default:
                return nil
            }
        }
        return suffix ? "+." + name : name
    }

     
     
     
     
     
    static func plainKernelLine(_ line: String) -> String? {
        let fields = line.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard fields.count == 2 || fields.count == 3, !fields[1].isEmpty,
              !fields[1].contains("\""), !fields[1].contains("'"), !fields[1].contains(" ") else { return nil }
        let type = fields[0].uppercased()
        switch type {
        case "DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD":
            guard fields.count == 2 else { return nil }
            return type + "," + (type == "DOMAIN-SUFFIX" ? ModuleRuleMapping.withoutLeadingDot(fields[1]) : fields[1])
        case "IP-CIDR", "IP-CIDR6":
            if fields.count == 3 {
                guard fields[2].lowercased() == "no-resolve" else { return nil }
                return type + "," + ModuleRuleMapping.withPrefixLength(fields[1]) + ",no-resolve"
            }
            return type + "," + ModuleRuleMapping.withPrefixLength(fields[1])
        default:
            return nil
        }
    }

     
     
     
     
    static func heapWeight(_ line: String) -> Int {
        var counter = HeavyCounter()
        counter.count(line)
        return counter.heap
    }

     
     
    private struct HeavyCounter {
        var keywords = 0, regexes = 0, others = 0, children = 0
         
        var weight = 0

         
        static let logicChild = try! NSRegularExpression(pattern: #"\(\s*([^,()\s]+)\s*,"#)

        mutating func count(_ line: String) {
            let type = line.prefix { $0 != "," }.trimmingCharacters(in: .whitespaces).uppercased()
            switch type {
            case "DOMAIN", "DOMAIN-SUFFIX", "IP-CIDR", "IP-CIDR6":
                return
            case "AND", "OR", "NOT":
                others += 1
                 
                 
                 
                let range = NSRange(line.startIndex..., in: line)
                for match in Self.logicChild.matches(in: line, range: range) {
                    children += 1
                    guard let typeRange = Range(match.range(at: 1), in: line) else { continue }
                    switch line[typeRange].uppercased() {
                    case "DOMAIN-KEYWORD": keywords += 1
                    case "DOMAIN-REGEX", "PROCESS-NAME-REGEX", "PROCESS-PATH-REGEX":
                        regexes += 1
                        weight += ModuleRuleSetSyntax.regexWeight - 1
                    default: break
                    }
                }
            case "DOMAIN-KEYWORD":
                keywords += 1
                others += 1
            case "DOMAIN-REGEX", "PROCESS-NAME-REGEX", "PROCESS-PATH-REGEX":
                regexes += 1
                others += 1
                weight += ModuleRuleSetSyntax.regexWeight - 1
            default:
                others += 1
            }
        }

         
         
        var heap: Int { others + children + weight }
        var tooHeavy: Bool {
            keywords > ModuleRuleSetSyntax.keywordLimit || regexes > ModuleRuleSetSyntax.regexLimit
                || others + children > ModuleRuleSetSyntax.othersLimit
        }
    }

     

     
     
     
     
    static func builtInLines(_ kind: ModuleRuleSetKind, platform: ModulePlatform = .current, bundle: Bundle = .main) -> [String]? {
        let resource: String
        switch kind {
        case .builtInLAN: resource = "surge-builtin-lan"
        case .builtInSystem: resource = "surge-builtin-system"
        default: return nil
        }
        guard let url = bundle.url(forResource: resource, withExtension: "list"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let origin = ModuleLineOrigin(section: "Rule", line: 0)
        return convert(text, kind: kind, policy: .builtIn("DIRECT"), origin: origin, platform: platform).kernelLines
    }

     

     
     
     
     
     
     
     
    static func definition(of set: ModuleRuleSet, payload: [String]? = nil) -> OrderedJSON {
        let behavior: String
        let format: String
        switch set.kind {
        case .domainSet: (behavior, format) = ("domain", "text")
        case .classical, .builtInLAN, .builtInSystem: (behavior, format) = ("classical", "text")
        case .provider(let written, let writtenFormat): (behavior, format) = (written, writtenFormat)
        }
        if let lines = payload ?? set.inline, set.url == nil, set.kind != .builtInLAN, set.kind != .builtInSystem {
            return .object([("type", .string("inline")), ("behavior", .string(behavior)), ("payload", .array(lines.map(OrderedJSON.string)))])
        }
        return .object([("type", .string("file")), ("behavior", .string(behavior)), ("format", .string(format))])
    }

     
     
    static func heldWeight(ofInline set: ModuleRuleSet) -> Int {
        guard let lines = set.inline else { return 0 }
        switch set.kind {
        case .provider(let behavior, _) where behavior != "classical": return 0
        default: return lines.reduce(0) { $0 + heapWeight($1) }
        }
    }

     
    static func encodedBytes(_ rule: ModuleRewriteRule) -> Int {
        (try? ModuleJSON.encoder().encode(rule).count) ?? (rule.pattern.utf8.count + 96)
    }

     
     
     
     
    static func keptBytes(of ir: ModuleIR) -> Int {
        var kept = ir
        kept.mitmHostLines = []
        kept.forceHTTPEngineHostLines = []
        kept.routingRules = []
        kept.ignored = []
        return (try? ModuleJSON.encoder().encode(kept).count) ?? .max
    }

     
     
    static func downloadHeaders(of set: ModuleRuleSet) -> [String: String] {
        var out = ["User-Agent": ClientUserAgent.Preset.clash.value]
        for (key, values) in set.headers ?? [:] where key.lowercased() != "user-agent" && !values.isEmpty {
            out[key] = values.joined(separator: ", ")
        }
        return out
    }
}

 

extension ModuleRuleSetSyntax {
     
     
    struct Publication: Equatable {
        var rules: [ModuleGlobalManifest.Rule] = []
        var settings: [ModuleGlobalManifest.ModuleSettings]?
        var providers: [ModuleGlobalManifest.RuleProvider]?
         
         
         
        var leftOutOrigins: [String: [ModuleLineOrigin]] = [:]
    }

     
     
     
     
     
     
     
     
     
    static func publication(_ modules: [(moduleID: String, ir: ModuleIR, choice: String?)],
                            builtInCopy: (ModuleRuleSetKind) -> String? = { _ in nil }) -> Publication {
         
        var inline: [String: ModuleRuleSet] = [:]
        for module in modules {
            for set in module.ir.ruleSets where set.isSurgeSection {
                guard let name = set.name else { continue }
                if var known = inline[name] {
                    var merged = known.inline ?? []
                    for line in set.inline ?? [] where !merged.contains(line) { merged.append(line) }
                    known.inline = merged
                    inline[name] = known
                } else {
                    inline[name] = set
                }
            }
        }
        var out = Publication()
        var providers: [ModuleGlobalManifest.RuleProvider] = []
        var named = Set<String>()
        var seen = Set<ModuleGlobalManifest.Rule>()
        var settings: [(moduleID: String, ir: ModuleIR)] = []
         
         
         
        var heldSoFar = 0
        func provide(_ name: String, _ set: ModuleRuleSet, moduleID: String) {
            guard named.insert(name).inserted else { return }
            let copy: String?
            let held: Int
            switch set.kind {
            case .builtInLAN, .builtInSystem:
                copy = builtInCopy(set.kind)
                held = (builtInLines(set.kind) ?? []).reduce(0) { $0 + heapWeight($1) }
            default:
                copy = set.url == nil ? nil : set.copy?.sha256
                held = set.url == nil ? heldWeight(ofInline: set) : set.copy?.held ?? 0
            }
            let overBudget = heldSoFar + held > maximumHeldWeight
            if overBudget {
                if set.url != nil { out.leftOutOrigins[moduleID, default: []].append(set.origin) }
            } else {
                heldSoFar += held
            }
            providers.append(ModuleGlobalManifest.RuleProvider(name: name, definition: definition(of: set).serialized(), copy: copy,
                                                                held: held, reference: set.reference, overBudget: overBudget))
        }
        for module in modules {
            let local = Dictionary(module.ir.ruleSets.filter { !$0.isSurgeSection }.map { ($0.reference, $0) }, uniquingKeysWith: { first, _ in first })
             
             
            let missing = Set(local.values.filter { $0.url != nil && $0.copy == nil }.map(\.reference))
             
            func resolve(_ reference: String) -> String? {
                if missing.contains(reference) { return nil }
                if let set = local[reference] {
                    let name: String
                    switch set.kind {
                    case .builtInLAN: name = lanProviderName
                    case .builtInSystem: name = systemProviderName
                    default: name = providerName(moduleID: module.moduleID, url: reference)
                    }
                    provide(name, set, moduleID: module.moduleID)
                    return name
                }
                guard module.ir.manifest.format != .stash, reference.hasPrefix("RULE-SET,"),
                      let set = inline[String(reference.dropFirst("RULE-SET,".count))], let name = set.name else { return nil }
                let provider = providerName(inline: name)
                provide(provider, set, moduleID: module.moduleID)
                return provider
            }
            for routing in module.ir.routingRules {
                var rule = ModuleGlobalManifest.Rule(routing, choice: module.choice)
                if rule.head.hasPrefix("RULE-SET,") || rule.head.hasPrefix("DOMAIN-SET,") {
                    if let name = resolve(rule.head) {
                        rule.head = "RULE-SET," + name
                    } else if rule.head.hasPrefix("DOMAIN-SET,") || missing.contains(rule.head) {
                        continue
                    }
                }
                if seen.insert(rule).inserted { out.rules.append(rule) }
            }
             
            var ir = module.ir
            ir.hosts = ir.hosts.compactMap { mapping in
                guard mapping.pattern.hasPrefix("rule-set:") else { return mapping }
                guard let name = resolve(String(mapping.pattern.dropFirst("rule-set:".count))) else { return nil }
                var rendered = mapping
                rendered.pattern = "rule-set:" + name
                return rendered
            }
            ir.edits = ir.edits.compactMap { edit in
                guard edit.path.first == "dns", edit.valueJSON.contains("rule-set:RULE-SET,"),
                      let value = try? OrderedJSON.parse(edit.valueJSON) else { return edit }
                 
                guard let kept = renderingSets(value, resolve), !kept.isEmptyContainer else { return nil }
                var rendered = edit
                rendered.valueJSON = kept.serialized()
                return rendered
            }
            settings.append((module.moduleID, ir))
        }
        out.settings = ModuleGlobalManifest.settings(settings)
        out.providers = providers.isEmpty ? nil : providers
        return out
    }

     
     
     
     
     
    static func renderingSets(_ value: OrderedJSON, _ resolve: (String) -> String?) -> OrderedJSON? {
        func rendered(_ text: String) -> String? {
            guard text.hasPrefix("rule-set:RULE-SET,") else { return text }
            return resolve(String(text.dropFirst("rule-set:".count))).map { "rule-set:" + $0 }
        }
        switch value {
        case .object(let pairs):
            var out: [(key: String, value: OrderedJSON)] = []
            for pair in pairs {
                 
                 
                if case .string(let text) = pair.value, rendered(text) == nil { return nil }
                guard let key = rendered(pair.key), let kept = renderingSets(pair.value, resolve) else { continue }
                out.append((key, kept))
            }
            return .object(out)
        case .array(let items):
            return .array(items.compactMap { renderingSets($0, resolve) })
        case .string(let text):
            return rendered(text).map(OrderedJSON.string)
        case .scalar:
            return value
        }
    }
}

extension ModuleRuleSetSyntax {
     
     
     
     
     
    static func strippingModuleSets(_ value: OrderedJSON, keeping handed: Set<String>) -> OrderedJSON? {
        func missing(_ text: String) -> Bool {
            guard text.hasPrefix("rule-set:") else { return false }
            let names = text.dropFirst("rule-set:".count).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            return names.contains { isModuleProviderName($0) && !handed.contains($0) }
        }
        switch value {
        case .object(let pairs):
            var out: [(key: String, value: OrderedJSON)] = []
            for pair in pairs where !missing(pair.key) {
                 
                 
                 
                if case .string(let text) = pair.value, missing(text) { return nil }
                guard let kept = strippingModuleSets(pair.value, keeping: handed) else { continue }
                out.append((pair.key, kept))
            }
            return .object(out)
        case .array(let items):
            return .array(items.compactMap { strippingModuleSets($0, keeping: handed) })
        case .string(let text):
            return missing(text) ? nil : value
        case .scalar:
            return value
        }
    }
}

extension OrderedJSON {
     
    var isEmptyContainer: Bool {
        switch self {
        case .object(let pairs): return pairs.isEmpty
        case .array(let items): return items.isEmpty
        default: return false
        }
    }
}

extension ModuleRuleSet {
     
     
    var isSurgeSection: Bool { kind == .classical && url == nil && inline != nil && name != nil }

     
     
     
     
    var reference: String {
        switch kind {
        case .domainSet: return "DOMAIN-SET," + (name ?? url ?? "")
        case .builtInLAN: return "RULE-SET,LAN"
        case .builtInSystem: return "RULE-SET,SYSTEM"
         
        default: return "RULE-SET," + (name ?? url ?? "")
        }
    }

     
     
    var isDefinition: Bool {
        url != nil || inline != nil || kind == .builtInLAN || kind == .builtInSystem
    }
}
