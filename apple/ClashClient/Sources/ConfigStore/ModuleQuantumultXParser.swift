import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum ModuleQuantumultXParser {
     
     
    private enum Section: String {
        case rewrite = "rewrite_local"
        case mitm
        case filter = "filter_local"
        case task = "task_local"
    }

     
     
    private static let proxySections: Set<String> = ["server_local", "server_remote", "policy"]

     
     
     
    static func parse(_ text: String, manifest base: ModuleManifest, sourceURL: String?, platform: ModulePlatform,
                      check: ModuleRuleMapping.Check, commented: Bool = false) throws -> Result<ModuleIR, ModuleRefusal> {
        let lines = text.components(separatedBy: "\n")
        var manifest = base
        manifest.format = .quantumultX
        var notes: [ModuleIgnoredEntry] = []
        for (index, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let origin = ModuleLineOrigin(section: "", line: index + 1)
             
            if let key = headerKey(line), key == "arguments" || key == "arguments-desc" {
                notes.append(ModuleIgnoredEntry(text: ModuleParser.prefix(line, bytes: ModuleParser.maximumShownBytes),
                                                reason: .argumentsNotSupported, origin: origin))
                continue
            }
            guard let reason = ModuleParser.readMetadata(line, loon: false, into: &manifest) else { continue }
            notes.append(ModuleIgnoredEntry(text: ModuleParser.prefix(line, bytes: ModuleParser.maximumShownBytes), reason: reason,
                                            origin: origin))
        }
        if !manifest.system.isEmpty, !manifest.system.contains(platform.rawValue) {
            return .failure(.otherPlatform(manifest.system))
        }
        var ir = ModuleIR.empty(manifest)
        ir.ignored += notes
        var section: String?
        var sawLine = false
         
         
        var anotherApps = false
        for (index, raw) in lines.enumerated() {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(";") || trimmed.hasPrefix("//") { continue }
            let written = ModuleParser.strippingComment(trimmed)
            if written.isEmpty { continue }
            if written.hasPrefix("["), written.hasSuffix("]") {
                let name = String(written.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                section = name
                if ModuleParser.quantumultXSections.contains(key(of: name)) {
                    anotherApps = false
                } else if otherAppsSections.contains(key(of: name)) {
                    anotherApps = true
                }
                continue
            }
            if commented, anotherApps || !isResourceLine(written, section: section.map(key(of:))) { continue }
            sawLine = true
             
             
            let named = section ?? inferredSection(written)?.rawValue ?? ""
            let origin = ModuleLineOrigin(section: named, line: index + 1)
            try take(written, section: key(of: named), origin: origin, platform: platform, check: check, into: &ir)
        }
        guard section != nil || sawLine else { return .failure(.notAModule) }
        return .success(ir)
    }

     
    private static func key(of section: String) -> String {
        section.lowercased().filter { !$0.isWhitespace }
    }

     
    private static func headerKey(_ line: String) -> String? {
        guard line.hasPrefix("#!"), let equals = line.firstIndex(of: "=") else { return nil }
        return line[line.index(line.startIndex, offsetBy: 2)..<equals].trimmingCharacters(in: .whitespaces).lowercased()
    }

     
    private static func hostnameLine(_ line: String) -> (key: String, value: String)? {
        guard let equals = line.firstIndex(of: "=") else { return nil }
        let key = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
        guard key == "hostname" || key == "hostname-disabled" else { return nil }
        return (key, String(line[line.index(after: equals)...]))
    }

     
     
     
     
     
    private static func inferredSection(_ line: String) -> Section? {
        if hostnameLine(line) != nil { return .mitm }
        if let words = ModuleLineSyntax.tokens(line), words.count >= 3,
           words[1].lowercased() == "url" || words.dropFirst(2).contains(where: { $0.lowercased() == "url-and-header" }) {
            return .rewrite
        }
        if filterType(line) != nil { return .filter }
        return nil
    }

    private static func take(_ line: String, section: String, origin: ModuleLineOrigin, platform: ModulePlatform,
                             check: ModuleRuleMapping.Check, into ir: inout ModuleIR) throws {
        func ignore(_ reason: ModuleIgnoredReason) {
            ir.ignored.append(ModuleIgnoredEntry(text: line, reason: reason, origin: origin))
        }
         
        if section != Section.filter.rawValue, section != Section.task.rawValue, let host = hostnameLine(line) {
            return takeHostname(host, line: line, origin: origin, into: &ir)
        }
        switch section {
        case Section.rewrite.rawValue:
            switch rewrite(line, origin: origin, moduleURL: ir.manifest.sourceURL) {
            case .success(let read):
                ir.rewriteRules += read.rules
                ir.answerFiles += read.files
                if let script = read.script { ir.scripts.append(script) }
                for note in read.notes { ignore(note) }
            case .failure(let reason):
                ignore(reason)
            }
        case Section.mitm.rawValue:
            guard let equals = line.firstIndex(of: "=") else { return ignore(.unreadableLine) }
            let name = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
             
            ignore(["passphrase", "p12"].contains(name) ? .notApplicable(.modulesCannotChangeCertificate) : .settingNotSupported(name))
        case Section.filter.rawValue:
            try takeFilter(line, origin: origin, platform: platform, check: check, into: &ir)
        case Section.task.rawValue:
            switch task(line, origin: origin) {
            case .success(let script): ir.appScripts.append(script)
            case .failure(let reason): ignore(reason)
            }
        case let other where proxySections.contains(other):
            ignore(.notApplicable(.modulesCannotAddProxies))
        case "":
            ignore(.unreadableLine)
        default:
             
            ignore(.sectionNotSupported(origin.section))
        }
    }

     

     
     
     
    private static let otherAppsSections: Set<String> = [
        "general", "script", "rewrite", "urlrewrite", "headerrewrite", "bodyrewrite", "maplocal", "rule", "host", "plugin",
        "argument", "panel",
    ]

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func commentedResource(_ text: String, sourceURL: String?) -> String? {
        let address = sourceURL.flatMap { URL(string: $0)?.path.lowercased() } ?? ""
        guard !otherAppsModuleExtensions.contains((address as NSString).pathExtension) else { return nil }
        let lines = text.components(separatedBy: "\n")
        var words: [String] = []
        words.reserveCapacity(lines.count)
        var inComment = false
        var outside = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if inComment || trimmed.hasPrefix("/*") {
                let body = inComment ? Substring(trimmed) : trimmed.dropFirst(2)
                if let close = body.range(of: "*/") {
                    words.append(commentWords(body[..<close.lowerBound]))
                    inComment = false
                } else {
                    words.append(commentWords(body))
                    inComment = true
                }
                continue
            }
            words.append("")
            if trimmed.hasPrefix("["), isOtherAppsSection(ModuleParser.strippingComment(trimmed)) { return nil }
            if !outside, isOwnLine(ModuleParser.strippingComment(trimmed)) { outside = true }
        }
        guard words.contains(where: isOwnLine) else { return nil }
        guard !outside || address.hasSuffix(".js") else { return nil }
        return words.joined(separator: "\n")
    }

     
     
    private static let otherAppsModuleExtensions: Set<String> = ["sgmodule", "module", "plugin", "lpx", "stoverride",
                                                                 "yaml", "yml"]

     
     
    private static func isOtherAppsSection(_ line: String) -> Bool {
        guard line.hasPrefix("["), line.hasSuffix("]") else { return false }
        let name = key(of: String(line.dropFirst().dropLast()))
        return otherAppsSections.contains(name) || name == Section.mitm.rawValue
    }

     
     
     
    private static func commentWords(_ line: Substring) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        let stars = text.prefix { $0 == "*" }
        if !stars.isEmpty, text.dropFirst(stars.count).first.map({ $0 == " " || $0 == "\t" }) ?? true {
            text = text.dropFirst(stars.count).trimmingCharacters(in: .whitespaces)
        }
        return text.allSatisfy({ "*=-_~#/".contains($0) }) ? "" : text
    }

     
    private static func isOwnLine(_ line: String) -> Bool {
        if line.hasPrefix("["), line.hasSuffix("]"),
           ModuleParser.quantumultXSections.contains(key(of: String(line.dropFirst().dropLast()))) {
            return true
        }
        return ModuleParser.isQuantumultXRewriteLine(line)
    }

     
     
     
     
     
    private static func isResourceLine(_ line: String, section: String?) -> Bool {
        if hostnameLine(line) != nil { return true }
        switch section {
        case nil: return inferredSection(line) != nil
        case Section.rewrite.rawValue: return inferredSection(line) == .rewrite
        case Section.mitm.rawValue:
            guard let equals = line.firstIndex(of: "=") else { return false }
            let name = line[..<equals].trimmingCharacters(in: .whitespaces)
            return !name.isEmpty && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        case Section.filter.rawValue: return filterType(line) != nil
        case Section.task.rawValue:
             
            if line.lowercased().hasPrefix("event-") { return true }
            let words = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            let fields = words.prefix { word in word.allSatisfy { $0.isASCII && ($0.isNumber || "*/,-?".contains($0)) } }.count
            return fields >= 5 && words.count > fields
        default: return false
        }
    }

     

     
     
     
     
     
    private static func takeHostname(_ host: (key: String, value: String), line: String, origin: ModuleLineOrigin,
                                     into ir: inout ModuleIR) {
        guard host.key == "hostname" else {
            ir.ignored.append(ModuleIgnoredEntry(text: line, reason: .noEffectInItsOwnApp(.noEffectThereEither), origin: origin))
            return
        }
        var parsed = ModuleHostList.line(host.value, origin: origin)
        parsed.line.directive = .merge
        ir.mitmHostLines.append(parsed.line)
        ir.ignored += parsed.ignored
    }

     

     
     
    struct Read: Equatable {
        var rules: [ModuleRewriteRule] = []
        var files: [ModuleAnswerFileReference] = []
        var script: ModuleScript?
        var notes: [ModuleIgnoredReason] = []
    }

     
     
     
    private static let scriptTypes: [String: (phase: ModuleRewritePhase, requiresBody: Bool)] = [
        "script-request-header": (.request, false),
        "script-request-body": (.request, true),
        "script-response-header": (.response, false),
        "script-response-body": (.response, true),
        "script-echo-response": (.request, false),
        "script-analyze-echo-response": (.request, true),
    ]

     
     
     
    private static let scriptOptions: Set<String> = ["tag", "enabled", "img-url", "timeout", "argument"]

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func rewrite(_ line: String, origin: ModuleLineOrigin, moduleURL: String?) -> Result<Read, ModuleIgnoredReason> {
        guard ModuleYAMLText.isOneLine(line) else { return .failure(.unreadableLine) }
         
         
         
         
         
        if let gated = urlAndHeader(line) {
            guard !gated.head.isEmpty else { return .failure(.unreadableLine) }
            guard ModuleLineSyntax.isValidPattern(gated.head) else { return .failure(.invalidPattern) }
            let condition = ModuleCondition.match(.requestHead, .regexSearch, .regex(gated.head), capture: nil)
            return rewrite(gated.pattern + #" url "# + gated.rest, origin: origin, moduleURL: moduleURL).map { read in
                var held = read
                for index in held.rules.indices { held.rules[index].condition = condition }
                held.script?.condition = condition
                return held
            }
        }
        guard let split = ModuleLineSyntax.splitHead(line, count: 3), split.head[1].lowercased() == "url" else {
            return .failure(.unreadableLine)
        }
        let pattern = split.head[0], type = split.head[2].lowercased(), rest = split.rest
        func rule(_ action: ModuleRewriteAction) -> Result<Read, ModuleIgnoredReason> {
            guard ModuleLineSyntax.isValidPattern(pattern) else { return .failure(.invalidPattern) }
            return .success(Read(rules: [ModuleRewriteRule(pattern: pattern, action: action, origin: origin)]))
        }
        if let reject = ModuleLineSyntax.rewriteAnswer(type) {
            guard rest.isEmpty else { return .failure(.unreadableLine) }
            return rule(reject)
        }
        if let script = scriptTypes[type] {
            return scriptLine(pattern: pattern, type: type, phase: script.phase, requiresBody: script.requiresBody, rest: rest,
                              origin: origin)
        }
        switch type {
        case "302", "307":
            guard let target = ModuleLineSyntax.tokens(rest), target.count == 1, !target[0].isEmpty else {
                return .failure(.unreadableLine)
            }
            return rule(type == "302" ? .redirect302(target[0]) : .redirect307(target[0]))
        case "request-body", "response-body":
            guard let (search, replacement) = pair(rest, keyword: type) else { return .failure(.unreadableLine) }
            guard ModuleLineSyntax.isValidPattern(search) else { return .failure(.invalidPattern) }
            return rule(.bodyReplace(phase: type == "request-body" ? .request : .response,
                                     pairs: [ModuleReplacementPair(search: search, replacement: replacement)]))
        case "jsonjq-request-body", "jsonjq-response-body":
            let keyword = type == "jsonjq-request-body" ? "http-request-jq" : "http-response-jq"
            return ModuleLineSyntax.jsonBodyRewrite(pattern: pattern, keyword: keyword, rest: rest, origin: origin, moduleURL: moduleURL,
                                                    resolvesAgainstTheModule: false)
                .map { Read(rules: $0.rules, files: $0.files) }
        case "echo-response":
            return echoResponse(pattern: pattern, rest: rest, origin: origin, moduleURL: moduleURL)
        case "request-header":
            guard let (search, replacement) = pair(rest, keyword: type) else { return .failure(.unreadableLine) }
            guard ModuleLineSyntax.isValidPattern(search) else { return .failure(.invalidPattern) }
            return rule(.header(phase: .request, operation: .replaceHead, name: "", arguments: [search, replacement]))
        case "simple-response":
            guard let encoded = ModuleLineSyntax.tokens(rest), encoded.count == 1 else { return .failure(.unreadableLine) }
            return ModuleLocalAnswerSyntax.rawResponse(encoded[0]).flatMap { rule(.localAnswer($0)) }
        default:
             
            if ModuleJSONRewriteSyntax.Verb.spelled(type) != nil {
                return ModuleLineSyntax.loonRewriteReading(pattern + " " + type + " " + rest, origin: origin, moduleURL: moduleURL)
                    .map { Read(rules: $0.rules, files: $0.files) }
            }
            return .failure(.unsupportedRewriteType(split.head[2]))
        }
    }

     
     
     
    private static func urlAndHeader(_ line: String) -> (pattern: String, head: String, rest: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let blank = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" }),
              let keyword = trimmed.range(of: #" url-and-header "#, options: .caseInsensitive, range: blank..<trimmed.endIndex)
                ?? trimmed.range(of: "\t" + #"url-and-header "#, options: .caseInsensitive, range: blank..<trimmed.endIndex) else {
            return nil
        }
        let head = trimmed[blank..<keyword.lowerBound].trimmingCharacters(in: .whitespaces)
        return (String(trimmed[..<blank]), head, String(trimmed[keyword.upperBound...]))
    }

     
     
     
    private static func pair(_ rest: String, keyword: String) -> (String, String)? {
        let separator = " " + keyword
        var from = rest.startIndex
        while let found = rest.range(of: separator, options: .caseInsensitive, range: from..<rest.endIndex) {
            let after = found.upperBound
            if after == rest.endIndex || rest[after] == " " {
                let search = String(rest[..<found.lowerBound]).trimmingCharacters(in: .whitespaces)
                let replacement = after == rest.endIndex ? "" : String(rest[rest.index(after: after)...])
                return search.isEmpty ? nil : (search, replacement)
            }
            from = after
        }
        return nil
    }

     
     
     
    private static func echoResponse(pattern: String, rest: String, origin: ModuleLineOrigin,
                                     moduleURL: String?) -> Result<Read, ModuleIgnoredReason> {
        guard let (head, file) = pair(rest, keyword: "echo-response"),
              let name = ModuleLineSyntax.tokens(file), name.count == 1 else { return .failure(.unreadableLine) }
        let parts = head.components(separatedBy: #"\r\n"#)
        let contentType = parts[0].trimmingCharacters(in: .whitespaces)
        guard !contentType.isEmpty else { return .failure(.unreadableLine) }
        var headers: [ModuleHeaderField] = []
        for part in parts.dropFirst() where !part.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let colon = part.firstIndex(of: ":") else { return .failure(.unreadableLine) }
            headers.append(ModuleHeaderField(name: part[..<colon].trimmingCharacters(in: .whitespaces),
                                             value: part[part.index(after: colon)...].trimmingCharacters(in: .whitespaces)))
        }
        let address: String
        switch ModuleLocalAnswerSyntax.fileAddress(name[0], moduleURL: moduleURL, resolvesAgainstTheModule: false) {
        case .success(let found): address = found
        case .failure(let reason): return .failure(reason)
        }
        guard ModuleLineSyntax.isValidPattern(pattern) else { return .failure(.invalidPattern) }
        let answer = ModuleLocalAnswer(status: 200, headers: ModuleLocalAnswerSyntax.withContentType(contentType, headers),
                                       body: ModuleLocalAnswerSyntax.pendingFile)
        return .success(Read(rules: [ModuleRewriteRule(pattern: pattern, action: .localAnswer(answer), origin: origin)],
                             files: [ModuleAnswerFileReference(url: address, sha256: nil, origin: origin)]))
    }

     
     
     
    private static func scriptLine(pattern: String, type: String, phase: ModuleRewritePhase, requiresBody: Bool, rest: String,
                                   origin: ModuleLineOrigin) -> Result<Read, ModuleIgnoredReason> {
        guard let (path, options) = addressAndOptions(rest) else { return .failure(.unreadableLine) }
        if options.contains(where: { $0.key == "require-devices" }) { return .failure(.noEffectInItsOwnApp(.noEffectThereEither)) }
        var parameters: [(key: String, value: String)] = [
            (key: "type", value: phase == .request ? "http-request" : "http-response"),
            (key: "pattern", value: pattern),
            (key: "script-path", value: path),
            (key: "requires-body", value: requiresBody ? "true" : "false"),
        ]
        parameters += options.filter { scriptOptions.contains($0.key) && $0.key != "tag" && $0.key != "img-url" }
        let name = scriptName(options: options, path: path)
        switch ModuleLineSyntax.script(name: name, parameters: parameters, origin: origin) {
        case .success(.http(var script)):
            script.imageURL = options.first { $0.key == "img-url" }.flatMap { $0.value.isEmpty ? nil : $0.value }
            var read = Read(script: script)
            if options.contains(where: { !scriptOptions.contains($0.key) }) { read.notes.append(.noEffectInItsOwnApp(.optionsWithNoEffect)) }
            return .success(read)
        case .success(.app):
            return .failure(.unreadableLine)
        case .failure(let reason):
            return .failure(reason)
        }
    }

     
     
    static func addressAndOptions(_ text: String) -> (path: String, options: [(key: String, value: String)])? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let end = trimmed.firstIndex { $0 == "," || $0 == " " || $0 == "\t" } ?? trimmed.endIndex
        let path = String(trimmed[..<end])
        guard !path.isEmpty else { return nil }
        var after = trimmed[end...].drop { $0 == " " || $0 == "\t" }
        if after.first == "," { after = after.dropFirst() }
        guard after.isEmpty || after.contains("=") else { return nil }
        return (path, ModuleLineSyntax.parameters(String(after)))
    }

     
    static func scriptName(options: [(key: String, value: String)], path: String) -> String {
        if let tag = options.first(where: { $0.key == "tag" })?.value.trimmingCharacters(in: .whitespaces), !tag.isEmpty { return tag }
        let file = URL(string: path)?.lastPathComponent ?? ""
        return !file.isEmpty && file != "/" ? file : path
    }

     

     
     
     
     
     
     
     
     
     
    static func task(_ line: String, origin: ModuleLineOrigin) -> Result<ModuleAppScript, ModuleIgnoredReason> {
        guard ModuleYAMLText.isOneLine(line) else { return .failure(.unreadableLine) }
        var words: [Substring] = []
        var rest = Substring(line.trimmingCharacters(in: .whitespaces))
        func takeWord() -> Substring? {
            let word = rest.prefix { $0 != " " && $0 != "\t" }
            guard !word.isEmpty else { return nil }
            rest = rest[word.endIndex...].drop { $0 == " " || $0 == "\t" }
            return word
        }
        var parameters: [(key: String, value: String)]
        switch rest.prefix(while: { $0 != " " && $0 != "\t" }).lowercased() {
        case "event-network":
            _ = takeWord()
            parameters = [(key: "type", value: "event"), (key: "event-name", value: "network-changed")]
        case "event-interaction":
            _ = takeWord()
            parameters = [(key: "type", value: "generic")]
        default:
             
            while words.count < 6, let next = rest.split(separator: " ", maxSplits: 1).first,
                  next.allSatisfy({ $0.isASCII && ($0.isNumber || $0.isLetter || "*/,-?".contains($0)) }),
                  !next.contains(where: { $0.isLetter }) || next.count == 3, let word = takeWord() {
                words.append(word)
            }
            guard words.count >= 5 else { return .failure(.unreadableLine) }
            parameters = [(key: "type", value: "cron"), (key: "cronexp", value: words.joined(separator: " "))]
        }
        guard let (path, options) = addressAndOptions(String(rest)) else { return .failure(.unreadableLine) }
        if options.contains(where: { $0.key == "require-devices" }) { return .failure(.noEffectInItsOwnApp(.noEffectThereEither)) }
        parameters.append((key: "script-path", value: path))
        parameters += options.filter { ["enabled", "timeout", "argument"].contains($0.key) }
        switch ModuleLineSyntax.script(name: scriptName(options: options, path: path), parameters: parameters, origin: origin) {
        case .success(.app(var script)):
            script.imageURL = options.first { $0.key == "img-url" }.flatMap { $0.value.isEmpty ? nil : $0.value }
            return .success(script)
        case .success(.http):
            return .failure(.unreadableLine)
        case .failure(let reason):
            return .failure(reason)
        }
    }

     

     
     
     
     
     
    private static let filterTypes: [String: String] = [
        "host": "DOMAIN", "host-suffix": "DOMAIN-SUFFIX", "host-keyword": "DOMAIN-KEYWORD", "host-wildcard": "DOMAIN-WILDCARD",
        "ip-cidr": "IP-CIDR", "ip6-cidr": "IP-CIDR6", "geoip": "GEOIP", "ip-asn": "IP-ASN", "user-agent": "USER-AGENT",
        "final": "FINAL",
        "domain": "DOMAIN", "domain-suffix": "DOMAIN-SUFFIX", "domain-keyword": "DOMAIN-KEYWORD", "ip-cidr6": "IP-CIDR6",
    ]

     
     
    private static let interfaceOptions: Set<String> = ["force-cellular", "multi-interface", "multi-interface-balance", "via-interface"]

     
    private static func filterType(_ line: String) -> String? {
        guard let comma = line.firstIndex(of: ",") else { return nil }
        return filterTypes[line[..<comma].trimmingCharacters(in: .whitespaces).lowercased()]
    }

     
     
     
     
     
    private static func takeFilter(_ line: String, origin: ModuleLineOrigin, platform: ModulePlatform, check: ModuleRuleMapping.Check,
                                   into ir: inout ModuleIR) throws {
        var fields = line.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard fields.count >= 2 else {
            return ir.ignored.append(ModuleIgnoredEntry(text: line, reason: .unreadableLine, origin: origin))
        }
        let written = fields[0].lowercased()
        fields[0] = filterTypes[written] ?? fields[0].uppercased()
        var passedOver: [String] = []
        fields = fields.enumerated().filter { index, field in
            guard index >= 3, interfaceOptions.contains(field.split(separator: "=").first.map { $0.lowercased() } ?? "") else { return true }
            passedOver.append(field)
            return false
        }.map(\.element)
        if fields.count >= 3 {
            let policy = fields[2]
            switch policy.lowercased() {
            case "proxy": fields[2] = "PROXY"
            case "direct": fields[2] = "DIRECT"
            case let lowered where ModuleRuleMapping.isReject(lowered): fields[2] = policy.uppercased()
            default: break
            }
        }
        let mapped = try ModuleRuleMapping.map(fields.joined(separator: ","), family: .quantumultX, platform: platform, origin: origin,
                                               check: check)
        ModuleRuleMapping.take(mapped, written: line, origin: origin, into: &ir)
        if case .ignored = mapped.outcome { return }
        if !passedOver.isEmpty {
            ir.ignored.append(ModuleIgnoredEntry(text: line, reason: .settingNotSupported(passedOver.joined(separator: ", ")), origin: origin))
        }
    }
}
