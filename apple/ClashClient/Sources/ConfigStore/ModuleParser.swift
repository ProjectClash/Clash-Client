import Darwin
import Foundation
import os

 
 
 
 
 
 
struct ModuleRequirementEnvironment: Equatable, Sendable {
    var coreVersion: Int
     
     
    var systemVersion: String
     
     
    var systemVersionDescription: String
     
    var deviceModel: String
     
    var language: String

     
     
     
     
     
    static var current: ModuleRequirementEnvironment {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return ModuleRequirementEnvironment(coreVersion: ModuleParser.declaredCoreVersion,
                                             systemVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
                                             systemVersionDescription: "System \(ProcessInfo.processInfo.operatingSystemVersionString)",
                                             deviceModel: model(), language: Locale.preferredLanguages.first ?? "en")
    }

    private static func model() -> String {
#if os(macOS)
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return "" }
        return String(cString: bytes)
#else
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"], !simulated.isEmpty { return simulated }
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
#endif
    }

     
    static func version(_ text: String) -> [Int]? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var out: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(part) else { return nil }
            out.append(number)
        }
        return out
    }

     
    static func order(_ a: [Int], _ b: [Int]) -> Int {
        for index in 0..<max(a.count, b.count) {
            let left = index < a.count ? a[index] : 0, right = index < b.count ? b[index] : 0
            if left != right { return left < right ? -1 : 1 }
        }
        return 0
    }
}

 
 
 
 
 
 
 
 
enum ModuleParser {
     
     
     
     
     
    static func parse(_ data: Data, sourceURL: String?, fetchedAt: Date?,
                      platform: ModulePlatform = .current,
                      environment: ModuleRequirementEnvironment = .current,
                      argumentValues: [String: String] = [:],
                      check: ModuleRuleMapping.Check = ModuleRuleMapping.kernelCheck) throws -> Result<ModuleIR, ModuleRefusal> {
        guard var text = String(data: data, encoding: .utf8) else { return .failure(.notText) }
         
         
        let argumentValues = argumentValues.mapValues { value in
            String(String.UnicodeScalarView(value.unicodeScalars.filter { $0 != "\r" && $0 != "\n" }))
        }
         
         
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let manifest = ModuleManifest(
            name: nil, desc: nil, author: nil, icon: nil, system: [], arguments: [], format: .surge,
            sourceURL: sourceURL, fetchedAt: fetchedAt, contentSHA256: ModuleJSON.sha256(data))
         
        if let commented = ModuleQuantumultXParser.commentedResource(text, sourceURL: sourceURL) {
            return try ModuleQuantumultXParser.parse(commented, manifest: manifest, sourceURL: sourceURL, platform: platform,
                                                     check: check, commented: true).map(bounded)
        }
        if isQuantumultX(text, sourceURL: sourceURL) {
            return try ModuleQuantumultXParser.parse(text, manifest: manifest, sourceURL: sourceURL, platform: platform, check: check)
                .map(bounded)
        }
        if isStash(text, sourceURL: sourceURL) {
            return try ModuleStashParser.parse(text, manifest: manifest, platform: platform, argumentValues: argumentValues,
                                               check: check).map { bounded(ModuleRuleMapping.listingPlainHTTPHosts($0)) }
        }
        return try parseSections(text, manifest: manifest, sourceURL: sourceURL, platform: platform, environment: environment,
                                 argumentValues: argumentValues, check: check).map { bounded(ModuleRuleMapping.listingPlainHTTPHosts($0)) }
    }

     
     
     
     
     
    static let maximumShownBytes = 1024
    static let maximumSourceURLBytes = 4096

     
     
    static func bounded(_ ir: ModuleIR) -> ModuleIR {
        var out = ir
        func cut(_ text: String) -> String { prefix(text, bytes: maximumShownBytes) }
        out.manifest.sourceURL = ir.manifest.sourceURL.map { prefix($0, bytes: maximumSourceURLBytes) }
        for index in out.ignored.indices {
            out.ignored[index].text = cut(out.ignored[index].text)
            let reason: ModuleIgnoredReason
            switch out.ignored[index].reason {
            case .sectionNotSupported(let text): reason = .sectionNotSupported(cut(text))
            case .settingNotSupported(let text): reason = .settingNotSupported(cut(text))
            case .invalidHost(let text): reason = .invalidHost(cut(text))
            case .unsupportedRewriteType(let text): reason = .unsupportedRewriteType(cut(text))
            case .unsupportedRuleType(let text): reason = .unsupportedRuleType(cut(text))
            case .customPolicy(let text): reason = .customPolicy(cut(text))
            case .ruleRefused(let text): reason = .ruleRefused(cut(text))
            case .unsupportedScriptType(let text): reason = .unsupportedScriptType(cut(text))
            case .missingArgument(let text): reason = .missingArgument(cut(text))
            case .waitingForKernel(let text): reason = .waitingForKernel(cut(text))
            case .setInClashSettings(let text): reason = .setInClashSettings(cut(text))
            case .jqExpressionInvalid(let text): reason = .jqExpressionInvalid(cut(text))
            case .policyNotFound(let text): reason = .policyNotFound(cut(text))
            case let other: reason = other
            }
            out.ignored[index].reason = reason
        }
        return out
    }

     

    private static func path(of sourceURL: String?) -> String {
        sourceURL.flatMap { URL(string: $0)?.path.lowercased() } ?? ""
    }

     
    static let quantumultXSections: Set<String> = ["rewrite_local", "rewrite_remote", "filter_local", "filter_remote",
                                                   "task_local", "server_local", "server_remote", "http_backend"]
     
    private static let sharedWithQuantumultX: Set<String> = ["general", "mitm", "dns", "policy"]

     
     
     
     
     
     
     
     
     
     
     
     
    static func isQuantumultX(_ text: String, sourceURL: String?) -> Bool {
        let sections = quantumultXSections
        var sawSection = false
        var sawQuantumultXSection = false
        var sawFamilySection = false
        var sawLine = false
        for raw in text.split(separator: "\n") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
             
            if trimmed.hasPrefix("#") || trimmed.hasPrefix(";") || trimmed.hasPrefix("//") { continue }
             
            let line = strippingComment(trimmed)
            if line.hasPrefix("["), line.hasSuffix("]") {
                let name = String(line.dropFirst().dropLast()).lowercased()
                if sections.contains(name) {
                    sawQuantumultXSection = true
                } else {
                    sawSection = true
                    if !sharedWithQuantumultX.contains(name) { sawFamilySection = true }
                }
                continue
            }
            if isQuantumultXRewriteLine(line) { sawLine = true }
        }
        if sawQuantumultXSection || sawLine { return !sawFamilySection }
        let address = path(of: sourceURL)
        return !sawFamilySection && (address.hasSuffix(".conf") || address.hasSuffix(".snippet"))
    }

     
    static let quantumultXActions: Set<String> = [
        "reject", "reject-200", "reject-img", "reject-dict", "reject-array", "302", "307",
        "request-header", "request-body", "response-header", "response-body", "echo-response",
        "jsonjq-request-body", "jsonjq-response-body", "simple-response",
        "script-request-header", "script-request-body", "script-response-header", "script-response-body",
        "script-echo-response", "script-analyze-echo-response",
    ]

     
     
    static func isQuantumultXRewriteLine(_ line: String) -> Bool {
        let words = line.split(separator: " ")
        if words.count >= 3, words[1] == "url", quantumultXActions.contains(words[2].lowercased()) { return true }
        return words.count >= 4 && words.dropFirst(2).contains(where: { $0.lowercased() == "url-and-header" })
    }

     
     
    static func isStash(_ text: String, sourceURL: String?) -> Bool {
        if path(of: sourceURL).hasSuffix(".stoverride") { return true }
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") || line.hasPrefix("//") { continue }
             
            if line == "---" || line.hasPrefix("--- ") { continue }
            guard raw.first.map({ !$0.isWhitespace }) == true, !line.hasPrefix("[") else { return false }
            return line.range(of: #"^[A-Za-z][A-Za-z0-9_-]*:(\s|$)"#, options: .regularExpression) != nil
        }
        return false
    }

     

     
     
     
     
     
     
     
     
     
     
     
     
    static func strippingComment(_ line: String) -> String {
        if ModuleLineSyntax.isNewerLoonSyntax(line.trimmingCharacters(in: .whitespaces)) {
            return ModuleLoonRewriteSyntax.strippingComment(line)
        }
        let characters = Array(line)
        var quote: Character?
        var inClass = false
        var index = 0
        while index < characters.count {
            let character = characters[index]
            let previous: Character? = index > 0 ? characters[index - 1] : nil
            if character == "\\" {
                index += 2
                continue
            }
            if let open = quote {
                if character == open { quote = nil }
            } else if inClass {
                if character == "]" { inClass = false }
            } else if (character == "\"" || character == "'"),
                      previous == nil || previous == " " || previous == "\t" || previous == "=" || previous == "," {
                quote = character
            } else if character == "[" {
                inClass = true
            } else if previous == " " || previous == "\t" {
                let startsComment = character == "#" || character == ";"
                    || (character == "/" && index + 1 < characters.count && characters[index + 1] == "/")
                if startsComment { return String(characters[..<index]).trimmingCharacters(in: .whitespaces) }
            }
            index += 1
        }
        return line.trimmingCharacters(in: .whitespaces)
    }

     

     
     
     
     
     
     
     
     
    static func arguments(_ value: String) -> [ModuleArgument] {
        var kept: [ModuleArgument] = []
        for item in commaSplit(value) {
            let part = item.trimmingCharacters(in: .whitespaces)
            guard !part.isEmpty else { continue }
            if let colon = part.firstIndex(of: ":") {
                kept.append(ModuleArgument(name: unquoted(part[..<colon].trimmingCharacters(in: .whitespaces)),
                                           defaultValue: unquoted(part[part.index(after: colon)...].trimmingCharacters(in: .whitespaces))))
            } else {
                kept.append(ModuleArgument(name: unquoted(part), defaultValue: nil))
            }
        }
        return kept
    }

     
     
    static func prefix(_ text: String, bytes: Int) -> String {
        var out = String.UnicodeScalarView()
        var used = 0
        for scalar in text.unicodeScalars {
            let size = String(scalar).utf8.count
            guard used + size <= bytes else { break }
            out.append(scalar)
            used += size
        }
        return String(out)
    }

     
     
     
    private static let placeholder = try! NSRegularExpression(pattern: #"\{\{\{([^{}]+)\}\}\}"#)

     
     
     
     
    static func substituting(_ line: String, defaults: [String: String]) -> (text: String, unresolved: [String]) {
        guard line.contains("{{{") else { return (line, []) }
        var out = line
        var unresolved: [String] = []
        let whole = NSRange(line.startIndex..., in: line)
        for match in placeholder.matches(in: line, range: whole).reversed() {
            guard let nameRange = Range(match.range(at: 1), in: line), let range = Range(match.range, in: out) else { continue }
             
            let name = line[nameRange].trimmingCharacters(in: .whitespaces)
            guard let value = defaults[name] else {
                unresolved.insert(name, at: 0)
                continue
            }
            out.replaceSubrange(range, with: value)
        }
        return (out, unresolved)
    }

     
     
     
     
     
    static func placeholdersOnlyInArgument(_ line: String) -> Bool {
        let parameters: [(key: String, value: String)]
        if ModuleLineSyntax.isLoonScriptLine(line) {
            guard let split = ModuleLineSyntax.splitHead(line, count: 2) else { return false }
            parameters = ModuleLineSyntax.parameters(split.rest)
            if split.head.contains(where: { $0.contains("{{{") }) { return false }
        } else {
            guard let equals = line.firstIndex(of: "=") else { return false }
            if line[..<equals].contains("{{{") { return false }
            parameters = ModuleLineSyntax.parameters(String(line[line.index(after: equals)...]))
        }
        func count(_ text: String) -> Int { text.components(separatedBy: "{{{").count - 1 }
        let inArgument = parameters.filter { $0.key == "argument" }.reduce(0) { $0 + count($1.value) }
        return inArgument > 0 && inArgument == count(line)
    }

     
     
     
    static let converterKeys: Set<String> = ["raw-url", "tg-channel", "basedon", "surge_version", "bundleid", "update-url",
                                             "total", "mitm", "reject", "redirect", "updatetime", "edit", "manual"]
     
     
    static let loonConverterKeys: Set<String> = ["category", "version"]
     
     
     
    private static let keysReadElsewhere: Set<String> = ["requirement", "select", "input"]

     
     
     
     
     
     
     
     
    static func readMetadata(_ line: String, loon: Bool, into manifest: inout ModuleManifest) -> ModuleIgnoredReason? {
        guard line.hasPrefix("#!"), let equals = line.firstIndex(of: "=") else { return nil }
        let written = line[line.index(line.startIndex, offsetBy: 2)..<equals].trimmingCharacters(in: .whitespaces)
         
        guard !written.isEmpty, written.allSatisfy({ $0.isLetter || $0.isNumber || "_-.".contains($0) }) else { return nil }
        let key = written.lowercased()
        if converterKeys.contains(key) || (loon && loonConverterKeys.contains(key)) || keysReadElsewhere.contains(key) { return nil }
        let value = String(line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces))
        switch key {
        case "name": manifest.name = value
        case "desc": manifest.desc = value
        case "author": manifest.author = value
        case "icon": manifest.icon = value
        case "homepage": manifest.homepage = value
        case "category": manifest.category = value
        case "openurl": manifest.openURL = value
        case "date": manifest.date = value
        case "tag": manifest.tag = value
        case "version": manifest.version = value
        case "arguments-desc": manifest.argumentsDescription = value
        case "system":
            manifest.system = systems(value)
        case "arguments":
            manifest.arguments = arguments(value)
            return nil
        case "type":
            return value.lowercased() == "parser" ? .unsupportedScriptType("parser") : nil
        default:
            manifest.otherKeys.append(ModuleManifestKey(key: written, value: value))
        }
        return nil
    }

     
     
     
     
    static func systems(_ value: String) -> [String] {
        var out: [String] = []
         
        for word in value.lowercased().split(whereSeparator: { $0 == "," || $0.isWhitespace }) {
            let name = word.trimmingCharacters(in: .whitespaces)
            let platform: String
            switch name {
            case "": continue
            case "ios", "ipados", "iphoneos": platform = "ios"
            case "mac", "macos", "osx": platform = "mac"
            default: platform = name
            }
            if !out.contains(platform) { out.append(platform) }
        }
        return out
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func loonSystemAllows(_ value: String, on platform: ModulePlatform) -> Bool {
        let written = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !written.isEmpty else { return true }
        let name: String
        switch platform {
        case .ios: name = "ios"
        case .mac: name = "macos"
        case .tvos: name = "tvos"
        }
        if written.contains(name) { return true }
        for both in ["mac", "tv", "ipad"] where written.contains(both) && name.contains(both) { return true }
        if written.contains("all") { return true }
        if written.contains("ios") { return false }
        return written.contains("ipad") && written.contains("tv") && written.contains("mac")
    }

     

    private static func requirementValue(_ raw: String) -> String? { metadataValue(raw, "requirement") }

     
    private static func metadataValue(_ raw: String, _ wanted: String) -> String? {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard line.hasPrefix("#!"), let equals = line.firstIndex(of: "=") else { return nil }
        let key = line[line.index(line.startIndex, offsetBy: 2)..<equals].trimmingCharacters(in: .whitespaces).lowercased()
        guard key == wanted else { return nil }
        return line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
    }

     
     
     
     
     
     
     
     
     
     
    static let declaredCoreVersion = 22

     
     
     
     
     
     
    static let requirementRegexDeadline: TimeInterval = 0.020

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Clash", category: "modules")

     
     
     
     
     
     
     
     
    static func platforms(meeting requirement: String, environment: ModuleRequirementEnvironment? = nil,
                          deadline: TimeInterval = requirementRegexDeadline) -> [String] {
        let systems = [("ios", ["ios", "ipados"]), ("mac", ["macos"]), ("tvos", ["tvos"])]
        let expression = Requirement(requirement)
        var timedOut = false
        var clock = ModuleRegexDeadline(deadline)
        let meeting = systems.filter { _, names in
            expression.holds(system: names, environment: environment, clock: &clock, timedOut: &timedOut) != false
        }
        guard !timedOut else {
            log.notice("A #!requirement's MATCHES or LIKE ran past \(requirementRegexDeadline * 1_000, privacy: .public) ms; the requirement is not read, so the module applies: \(requirement, privacy: .public)")
            return systems.map(\.0)
        }
        return meeting.map(\.0)
    }

     
     
     
     
     
    private struct Requirement {
        enum Token: Equatable { case word(String), text(String), op(String), open, close, not, and, or }
        let tokens: [Token]?

        static let stringOperators: Set<String> = ["BEGINSWITH", "CONTAINS", "ENDSWITH", "LIKE", "MATCHES"]

        init(_ written: String) {
            var text = written
            if text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") { text = String(text.dropFirst().dropLast()) }
            var out: [Token] = []
            let characters = Array(text)
            var index = 0
            var readable = true
            while index < characters.count, readable {
                let character = characters[index]
                if character == " " || character == "\t" { index += 1; continue }
                let two = index + 1 < characters.count ? String(characters[index...(index + 1)]) : String(character)
                switch two {
                case "&&": out.append(.and); index += 2; continue
                case "||": out.append(.or); index += 2; continue
                case "==", "!=", ">=", "<=": out.append(.op(two)); index += 2; continue
                case "=>": out.append(.op(">=")); index += 2; continue
                case "=<": out.append(.op("<=")); index += 2; continue
                case "<>": out.append(.op("!=")); index += 2; continue
                default: break
                }
                switch character {
                case "(": out.append(.open); index += 1
                case ")": out.append(.close); index += 1
                case "!": out.append(.not); index += 1
                case "=", ">", "<": out.append(.op(character == "=" ? "==" : String(character))); index += 1
                case "'", "\"":
                    guard let close = characters[(index + 1)...].firstIndex(of: character) else { readable = false; break }
                    out.append(.text(String(characters[(index + 1)..<close])))
                    index = close + 1
                default:
                    var end = index
                    while end < characters.count, characters[end].isLetter || characters[end].isNumber || "_.".contains(characters[end]) { end += 1 }
                    guard end > index else { readable = false; break }
                    let word = String(characters[index..<end])
                    switch word.uppercased() {
                    case "AND": out.append(.and)
                    case "OR": out.append(.or)
                    case "NOT": out.append(.not)
                    case let upper where Self.stringOperators.contains(upper): out.append(.op(upper))
                    default: out.append(.word(word))
                    }
                    index = end
                }
            }
            tokens = readable ? out : nil
        }

         
         
         
        func holds(system: [String], environment: ModuleRequirementEnvironment?, clock: inout ModuleRegexDeadline,
                   timedOut: inout Bool) -> Bool? {
            guard let tokens else { return nil }
             
            var stopped = timedOut
            var regexClock = clock
            defer {
                if stopped { timedOut = true }
                clock = regexClock
            }
            var index = 0
            func or() -> Bool?? {
                guard var left = and() else { return nil }
                while index < tokens.count, tokens[index] == .or {
                    index += 1
                    guard let right = and() else { return nil }
                    left = left == true || right == true ? true : (left == false && right == false ? false : nil)
                }
                return left
            }
            func and() -> Bool?? {
                guard var left = unary() else { return nil }
                while index < tokens.count, tokens[index] == .and {
                    index += 1
                    guard let right = unary() else { return nil }
                    left = left == false || right == false ? false : (left == true && right == true ? true : nil)
                }
                return left
            }
            func unary() -> Bool?? {
                guard index < tokens.count else { return nil }
                switch tokens[index] {
                case .not:
                    index += 1
                    guard let inner = unary() else { return nil }
                    return inner.map { !$0 }
                case .open:
                    index += 1
                    guard let inner = or(), index < tokens.count, tokens[index] == .close else { return nil }
                    index += 1
                    return inner
                case .word(let name):
                    guard index + 2 < tokens.count, case .op(let op) = tokens[index + 1] else { return nil }
                    let value: String
                    switch tokens[index + 2] {
                    case .text(let text), .word(let text): value = text
                    default: return nil
                    }
                    index += 3
                    switch name.uppercased() {
                    case "SYSTEM":
                        guard op == "==" || op == "!=" else { return .some(nil) }
                        let equal = system.contains(value.lowercased())
                        return .some(op == "==" ? equal : !equal)
                    case "CORE_VERSION":
                        guard let environment, let wanted = Double(value) else { return .some(nil) }
                        return .some(Self.compare(Double(environment.coreVersion) < wanted ? -1 : (Double(environment.coreVersion) > wanted ? 1 : 0), op))
                    case "SYSTEM_VERSION":
                        guard let environment else { return .some(nil) }
                        if let have = ModuleRequirementEnvironment.version(environment.systemVersion),
                           let wanted = ModuleRequirementEnvironment.version(value), !Self.stringOperators.contains(op) {
                            return .some(Self.compare(ModuleRequirementEnvironment.order(have, wanted), op))
                        }
                        return .some(Self.matches(environment.systemVersionDescription, op, value, clock: &regexClock, timedOut: &stopped))
                    case "DEVICE_MODEL":
                        return .some(environment.flatMap { Self.matches($0.deviceModel, op, value, clock: &regexClock, timedOut: &stopped) })
                    case "LANGUAGE":
                        return .some(environment.flatMap { Self.matches($0.language, op, value, clock: &regexClock, timedOut: &stopped) })
                    default:
                         
                        return .some(nil)
                    }
                default:
                    return nil
                }
            }
            guard let result = or(), index == tokens.count else { return nil }
            return result
        }

         
         
        static func compare(_ order: Int, _ op: String) -> Bool? {
            switch op {
            case "==": return order == 0
            case "!=": return order != 0
            case ">=": return order >= 0
            case "<=": return order <= 0
            case ">": return order > 0
            case "<": return order < 0
            default: return nil
            }
        }

         
         
         
         
        static func matches(_ have: String, _ op: String, _ wanted: String, clock: inout ModuleRegexDeadline,
                            timedOut: inout Bool) -> Bool? {
            switch op {
            case "==": return have == wanted
            case "!=": return have != wanted
            case "BEGINSWITH": return have.hasPrefix(wanted)
            case "CONTAINS": return have.contains(wanted)
            case "ENDSWITH": return have.hasSuffix(wanted)
            case "LIKE":
                let pattern = NSRegularExpression.escapedPattern(for: wanted)
                    .replacingOccurrences(of: "\\*", with: ".*").replacingOccurrences(of: "\\?", with: ".")
                return wholeMatch(have, pattern, clock: &clock, timedOut: &timedOut)
            case "MATCHES": return wholeMatch(have, wanted, clock: &clock, timedOut: &timedOut)
            default: return nil
            }
        }

         
         
         
         
        private static func wholeMatch(_ text: String, _ pattern: String, clock: inout ModuleRegexDeadline,
                                       timedOut: inout Bool) -> Bool? {
            guard !timedOut, let regex = try? NSRegularExpression(pattern: "^(?:" + pattern + ")$") else { return nil }
            var running = clock
            defer { clock = running }
             
            if running.isPast() {
                timedOut = true
                return nil
            }
            var found = false
            var stopped = false
            regex.enumerateMatches(in: text, options: [.reportProgress], range: NSRange(text.startIndex..., in: text)) { result, _, stop in
                if result != nil {
                    found = true
                    stop.pointee = true
                } else if running.isPast() {
                    stopped = true
                    stop.pointee = true
                }
            }
            if stopped { timedOut = true; return nil }
            return found
        }
    }

     

     
     
     
     
    static func loonArgument(_ line: String) -> ModuleArgument? {
        guard let name = loonArgumentName(line), let equals = line.firstIndex(of: "=") else { return nil }
        var parts = commaSplit(String(line[line.index(after: equals)...]))
        guard !parts.isEmpty else { return nil }
        let control = parts.removeFirst().trimmingCharacters(in: .whitespaces).lowercased()
         
        guard ["input", "select", "switch"].contains(control) else { return nil }
        var values: [String] = []
        var options: [String: String] = [:]
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if let equals = trimmed.firstIndex(of: "="),
               case let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces).lowercased(), ["type", "tag", "desc"].contains(key) {
                options[key] = options[key] ?? unquoted(trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces))
                continue
            }
             
            if options.isEmpty { values.append(unquoted(trimmed)) }
        }
        let valueType = options["type"]?.lowercased()
         
         
         
         
        if valueType == "number", values.contains(where: { Double($0.trimmingCharacters(in: .whitespaces)) == nil }) {
            return nil
        }
        var value = values.first
        let kind: ModuleArgumentKind
        switch control {
        case "switch":
            if let written = value?.lowercased(), written != "true", written != "false" { value = nil }
            value = value?.lowercased()
            kind = .toggle
        case "select": kind = .choice(values)
        default: kind = .input
        }
        return ModuleArgument(name: name, defaultValue: value, kind: kind, valueType: options["type"], tag: options["tag"],
                              desc: options["desc"])
    }

     
    static func loonArgumentName(_ line: String) -> String? {
        guard let equals = line.firstIndex(of: "=") else { return nil }
        let name = line[..<equals].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name.allSatisfy({ !$0.isWhitespace && !"${},\"'".contains($0) }) else { return nil }
        return name
    }

     
     
     
    static func storedSettings(_ lines: [String], besides declared: [ModuleArgument]) -> [ModuleArgument] {
        var out: [ModuleArgument] = []
        var names = Set(declared.map(\.name))
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let select = metadataValue(line, "select"), input = metadataValue(line, "input")
            guard let value = select ?? input else { continue }
            let parts = commaSplit(value).map { unquoted($0.trimmingCharacters(in: .whitespaces)) }.filter { !$0.isEmpty }
            guard let name = parts.first, !names.contains(name) else { continue }
            let options = Array(parts.dropFirst())
            let setting = select != nil
                ? ModuleArgument(name: name, defaultValue: options.first, kind: .storedChoice(options))
                : ModuleArgument(name: name, defaultValue: nil, kind: .storedInput)
            names.insert(name)
            out.append(setting)
        }
        return out
    }

     
    static func isComment(_ line: String) -> Bool {
        let head = line.trimmingCharacters(in: .whitespaces)
        return head.hasPrefix("#") || head.hasPrefix("//") || head.hasPrefix(";")
    }

     
     
     
    static func loonObjectArgumentNames(_ line: String, declared: [String: String?]) -> [String]? {
        guard ModuleLineSyntax.isLoonScriptLine(line), let split = ModuleLineSyntax.splitHead(line, count: 2),
              let written = ModuleLineSyntax.parameters(split.rest).last(where: { $0.key == "argument" })?.value else { return nil }
        let value = unquoted(written.trimmingCharacters(in: .whitespaces))
        guard value.hasPrefix("["), value.hasSuffix("]"), value.count > 2 else { return nil }
        var names: [String] = []
        for item in value.dropFirst().dropLast().split(separator: ",", omittingEmptySubsequences: false) {
            var reference = item.trimmingCharacters(in: .whitespaces)
            if reference.hasPrefix("$") { reference.removeFirst() }
            guard reference.hasPrefix("{"), reference.hasSuffix("}") else { return nil }
            let name = String(reference.dropFirst().dropLast())
            guard declared[name] != nil, !names.contains(name) else { return nil }
            names.append(name)
        }
        return names
    }

     
     
    static func typedLoonValue(_ value: String?, type: ModuleLoonRewriteSyntax.SettingType) -> ModuleScriptTypedArgument.Value {
        guard let value else { return .null }
        switch type {
        case .text: return .string(value)
        case .boolean:
            switch value.lowercased() {
            case "true": return .bool(true)
            case "false": return .bool(false)
            default: return .string(value)
            }
        case .number:
            guard let number = Double(value.trimmingCharacters(in: .whitespaces)), number.isFinite else { return .string(value) }
            return .number(number)
        }
    }

     
    private static func commaSplit(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        var quoted = false
        var previous: Character?
        for character in text {
            if character == "\"", previous != "\\" {
                quoted.toggle()
                current.append(character)
            } else if character == ",", !quoted {
                out.append(current)
                current = ""
            } else {
                current.append(character)
            }
            previous = character
        }
        out.append(current)
        return out
    }

    private static func unquoted(_ text: String) -> String {
        guard text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") else { return text }
        return String(text.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"")
    }

    private static let loonReference = try! NSRegularExpression(pattern: #"\$?\{([^{}\s]+)\}"#)

     
    static func loonReferences(in text: String) -> [String] {
        guard text.contains("{") else { return [] }
        let whole = NSRange(text.startIndex..., in: text)
        return loonReference.matches(in: text, range: whole).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

     
     
     
     
     
    static func substitutingLoon(_ line: String, arguments: [String: String?]) -> Result<String, ModuleIgnoredReason> {
        guard !arguments.isEmpty, line.contains("{") else { return .success(line) }
        var out = line
        let whole = NSRange(line.startIndex..., in: line)
        for match in loonReference.matches(in: line, range: whole).reversed() {
            guard let nameRange = Range(match.range(at: 1), in: line), let range = Range(match.range, in: out) else {
                return .failure(.unreadableLine)
            }
            let name = String(line[nameRange])
            guard let declared = arguments[name] else { continue }
            guard let value = declared else { return .failure(.missingArgument(name)) }
            out.replaceSubrange(range, with: value)
        }
        return .success(out)
    }

     
     
    private static func rulesetName(_ section: String) -> String? {
        let trimmed = section.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > 8, trimmed.prefix(8).lowercased() == #"ruleset "# else { return nil }
        let name = trimmed.dropFirst(8).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

     
     
    private static func key(of section: String) -> String {
        section.lowercased().filter { !$0.isWhitespace }
    }

     

    private static func parseSections(_ text: String, manifest base: ModuleManifest, sourceURL: String?,
                                      platform: ModulePlatform, environment: ModuleRequirementEnvironment,
                                      argumentValues: [String: String],
                                      check: ModuleRuleMapping.Check) throws -> Result<ModuleIR, ModuleRefusal> {
        let lines = text.components(separatedBy: "\n")
        var manifest = base
         
        let loonSections = lines.contains { raw in
            let written = strippingComment(raw.trimmingCharacters(in: .whitespaces))
            guard written.hasPrefix("["), written.hasSuffix("]") else { return false }
            return ["rewrite", "argument"].contains(key(of: String(written.dropFirst().dropLast())))
        }
         
         
        let newerLoonLines = lines.contains { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            return ModuleLoonRewriteSyntax.isRule(line) || ModuleLoonRewriteSyntax.isAppScriptRule(line)
        }
         
         
         
         
         
         
         
         
         
         
         
         
         
        let address = path(of: sourceURL)
        let addressNamesAFamily = [".sgmodule", ".module", ".srmodule", ".stoverride", ".yaml", ".yml"]
            .contains { address.hasSuffix($0) }
        var inScript = false
        let olderLoonScriptLines = !addressNamesAFamily && lines.contains { raw in
            let line = strippingComment(raw.trimmingCharacters(in: .whitespaces)).replacingOccurrences(of: "\t", with: " ")
            if line.hasPrefix("["), line.hasSuffix("]") {
                inScript = key(of: String(line.dropFirst().dropLast())) == "script"
                return false
            }
            guard inScript, ModuleLineSyntax.isLoonScriptLine(line), line.contains("script-path=") else { return false }
            let name = line.prefix { $0 != "=" }
            guard name.contains("://") || name.contains(#":\/\/"#)
                    || line.range(of: #"^[^=]*=\s*type\s*=\s*(http-request|http-response|cron|event|dns|rule|generic)\s*(,|$)"#,
                                  options: [.regularExpression, .caseInsensitive]) == nil else { return false }
            let rest = line.drop { $0 != " " }.drop { $0 == " " }
            return !rest.isEmpty && !rest.hasPrefix("=")
        }
        var loon = address.hasSuffix(".plugin") || address.hasSuffix(".lpx") || loonSections || newerLoonLines
            || olderLoonScriptLines
        var headerNotes: [ModuleIgnoredEntry] = []
        for (index, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let reason = readMetadata(line, loon: loon, into: &manifest) else { continue }
            headerNotes.append(ModuleIgnoredEntry(text: prefix(line, bytes: maximumShownBytes), reason: reason,
                                                   origin: ModuleLineOrigin(section: "", line: index + 1)))
        }
         
         
        if loon {
            if let written = lines.compactMap({ metadataValue($0, "system") }).last,
               !loonSystemAllows(written, on: platform) {
                return .failure(.otherPlatform(manifest.system))
            }
        } else if !manifest.system.isEmpty, !manifest.system.contains(platform.rawValue) {
            return .failure(.otherPlatform(manifest.system))
        }
         
         
         
         
        if let requirement = lines.lazy.compactMap(requirementValue).first {
            let platforms = Self.platforms(meeting: requirement)
            if !platforms.contains(platform.rawValue) { return .failure(.otherPlatform(platforms)) }
            if !Self.platforms(meeting: requirement, environment: environment).contains(platform.rawValue) {
                return .failure(.requirementNotMet)
            }
        }
         
         
        var loonArguments: [String: String?] = [:]
         
        var loonTypes: [String: ModuleLoonRewriteSyntax.SettingType] = [:]
         
         
        var invalidNames = Set<String>()
        var scanning: String?
        for raw in lines {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("//") || trimmed.hasPrefix(";") { continue }
            let written = strippingComment(trimmed)
            if written.hasPrefix("["), written.hasSuffix("]") {
                scanning = key(of: String(written.dropFirst().dropLast()))
                if ["rewrite", "argument"].contains(scanning!) { loon = true }
            } else if scanning == "argument", loonArgument(written) == nil, let name = loonArgumentName(written) {
                invalidNames.insert(name)
            } else if scanning == "argument", let argument = loonArgument(written) {
                let known = manifest.arguments.contains { $0.name == argument.name }
                loonArguments[argument.name] = .some(argument.defaultValue)
                loonTypes[argument.name] = ModuleLoonRewriteSyntax.declaredType(ofArgument: written)
                if !known { manifest.arguments.append(argument) }
            }
        }
         
         
         
        var bareNames = Set<String>()
        if let value = lines.compactMap({ metadataValue($0, "arguments") }).last {
            bareNames = Set(arguments(value).filter { $0.defaultValue == nil }.map(\.name))
        }
         
         
         
        var newerLoonArguments = loonArguments
         
         
        let declaredNames = Set(manifest.arguments.map(\.name)).union(loonArguments.keys)
        func holdsPlaceholder(_ text: String) -> Bool {
            text.contains("{{{") || text.contains("${args.") || loonReferences(in: text).contains(where: declaredNames.contains)
        }
        manifest.arguments = manifest.arguments.map { argument in
            argument.defaultValue.map(holdsPlaceholder) == true ? ModuleArgument(name: argument.name, defaultValue: nil) : argument
        }
        for (name, value) in loonArguments where (value ?? nil).map(holdsPlaceholder) == true { loonArguments[name] = .some(nil) }
        var defaults: [String: String] = [:]
        for argument in manifest.arguments where defaults[argument.name] == nil {
            defaults[argument.name] = argument.defaultValue ?? (bareNames.contains(argument.name) ? "" : nil)
        }
        for name in invalidNames where loonArguments[name] == nil {
            loonArguments[name] = .some(nil)
            newerLoonArguments[name] = .some(nil)
        }
         
         
         
         
         
        for (name, value) in argumentValues where declaredNames.contains(name) && !invalidNames.contains(name) {
            defaults[name] = value
            if loonArguments[name] != nil {
                loonArguments[name] = .some(value)
                newerLoonArguments[name] = .some(value)
            }
        }
         
         
         
        manifest.arguments += storedSettings(lines, besides: manifest.arguments)
        var ir = ModuleIR.empty(manifest)
        ir.ignored += headerNotes
        var section: String?
         
        var rulesets: [(name: String, lines: [(text: String, origin: ModuleLineOrigin)])] = []
        for (index, raw) in lines.enumerated() {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("//") || trimmed.hasPrefix(";") { continue }
            let written = strippingComment(trimmed)
            if written.isEmpty { continue }
            if written.hasPrefix("["), written.hasSuffix("]") {
                let name = String(written.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                section = name
                continue
            }
            let origin = ModuleLineOrigin(section: section ?? "", line: index + 1)
            guard let current = section else {
                ir.ignored.append(ModuleIgnoredEntry(text: written, reason: .unreadableLine, origin: origin))
                continue
            }
             
             
             
            if loon, ["rewrite", "urlrewrite"].contains(key(of: current)), ModuleLoonRewriteSyntax.isRule(trimmed) {
                 
                switch ModuleLoonRewriteSyntax.reading(trimmed, origin: origin, arguments: newerLoonArguments, types: loonTypes,
                                                        moduleURL: sourceURL) {
                case .success(let read):
                    ir.rewriteRules.append(read.rule)
                    ir.answerFiles += read.files
                case .failure(let reason): ir.ignored.append(ModuleIgnoredEntry(text: written, reason: reason, origin: origin))
                }
                continue
            }
             
             
             
             
            if loon, key(of: current) == "script", ModuleLoonRewriteSyntax.isAppScriptRule(trimmed) {
                switch ModuleLoonRewriteSyntax.appScriptRule(trimmed, origin: origin, arguments: newerLoonArguments, types: loonTypes,
                                                              moduleURL: sourceURL) {
                case .success(let script): ir.appScripts.append(script)
                case .failure(let reason): ir.ignored.append(ModuleIgnoredEntry(text: written, reason: reason, origin: origin))
                }
                continue
            }
            if loon, key(of: current) == "script", ModuleLoonRewriteSyntax.isRule(trimmed) {
                switch ModuleLoonRewriteSyntax.scriptRule(trimmed, origin: origin, arguments: newerLoonArguments, types: loonTypes,
                                                           moduleURL: sourceURL) {
                case .success(let script): ir.scripts.append(script)
                case .failure(let reason): ir.ignored.append(ModuleIgnoredEntry(text: written, reason: reason, origin: origin))
                }
                continue
            }
             
             
            let objectNames = loon && key(of: current) == "script" ? loonObjectArgumentNames(written, declared: loonArguments) : nil
            let surge = substituting(written, defaults: defaults)
            var filled: Result<String, ModuleIgnoredReason> = .success(surge.text)
            if loon, key(of: current) != "argument" {
                var given = loonArguments
                for name in objectNames ?? [] where given[name] == .some(nil) { given[name] = .some("") }
                filled = substitutingLoon(surge.text, arguments: given)
            }
             
             
            if case .success(let line) = filled, line != written, isComment(line) { continue }
            if case .success(let line) = filled, let name = surge.unresolved.first,
               key(of: current) != "script" || !placeholdersOnlyInArgument(line) {
                filled = .failure(.missingArgument(name))
            }
             
             
             
             
             
            if case .success(let line) = filled, line.contains("{{{") {
                let left = substituting(line, defaults: [:]).unresolved
                let handedOver = key(of: current) == "script" && placeholdersOnlyInArgument(line) && !left.isEmpty
                    && !left.contains(where: declaredNames.contains)
                if !handedOver {
                    filled = .failure(left.first(where: declaredNames.contains).map { .missingArgument($0) }
                                        ?? left.first.map { .missingArgument($0) } ?? .unreadableLine)
                }
            }
            if loon, key(of: current) != "argument", case .success(let line) = filled,
               let name = loonReferences(in: line).first(where: declaredNames.contains) {
                filled = .failure(.missingArgument(name))
            }
             
            if case .success(let line) = filled, let reference = line.range(of: "${args.") {
                let name = line[reference.upperBound...].prefix { !"}| ".contains($0) }
                filled = .failure(.missingArgument(String(name)))
            }
            switch filled {
            case .success(let line) where rulesetName(current) != nil:
                 
                let name = rulesetName(current)!
                if let index = rulesets.firstIndex(where: { $0.name == name }) {
                    rulesets[index].lines.append((line, origin))
                } else {
                    rulesets.append((name, [(line, origin)]))
                }
            case .success(let line):
                let scripts = ir.scripts.count
                try take(line, written: written, section: current, origin: origin, loon: loon, platform: platform, check: check, into: &ir)
                if let objectNames, ir.scripts.count == scripts + 1 {
                    ir.scripts[scripts].argumentNames = objectNames
                    ir.scripts[scripts].typedArguments = objectNames.map {
                        ModuleScriptTypedArgument(name: $0, value: typedLoonValue(loonArguments[$0] ?? nil, type: loonTypes[$0] ?? .text))
                    }
                }
            case .failure(let reason):
                ir.ignored.append(ModuleIgnoredEntry(text: written, reason: reason, origin: origin))
            }
        }
        guard section != nil else { return .failure(.notAModule) }
        for ruleset in rulesets {
            ModuleRuleSetSyntax.takeSection(ruleset.name, lines: ruleset.lines, family: loon ? .loon : .surge, platform: platform,
                                              check: check, into: &ir)
        }
        if loon { loonIPRewriteHoldsWhole(&ir) }
        if loon { loonClassicNetworkChangedRunsOnce(&ir, lines: lines) }
        settingsSectionsHoldWhole(&ir)
        if loon { manifest.format = .loon }
        ir.manifest = manifest
        return .success(ir)
    }

     
     
    static func directive(_ value: String) -> (ModuleHostListDirective?, String) {
        let text = value.trimmingCharacters(in: .whitespaces)
        for (word, directive) in [("%APPEND%", ModuleHostListDirective.append), ("%INSERT%", .insert)]
        where text.uppercased().hasPrefix(word) {
            return (directive, String(text.dropFirst(word.count)).trimmingCharacters(in: .whitespaces))
        }
        return (nil, text)
    }

     
     
     
     
     
     
    private static func loonClassicNetworkChangedRunsOnce(_ ir: inout ModuleIR, lines: [String]) {
        func isClassic(_ script: ModuleAppScript) -> Bool {
            guard script.kind == .networkChanged, lines.indices.contains(script.origin.line - 1) else { return false }
            let line = lines[script.origin.line - 1].trimmingCharacters(in: .whitespaces)
            return ModuleLineSyntax.isLoonScriptLine(line) && !ModuleLoonRewriteSyntax.isAppScriptRule(line)
        }
        guard let first = ir.appScripts.firstIndex(where: isClassic) else { return }
        let later = ir.appScripts.indices.filter { $0 > first && isClassic(ir.appScripts[$0]) }
        for index in later {
            let script = ir.appScripts[index]
            let written = strippingComment(lines[script.origin.line - 1].trimmingCharacters(in: .whitespaces))
            ir.ignored.append(ModuleIgnoredEntry(text: written, reason: .noEffectInItsOwnApp(.noEffectThereEither), origin: script.origin))
        }
        ir.appScripts = ir.appScripts.indices.filter { !later.contains($0) }.map { ir.appScripts[$0] }
    }

     
     
     
    private static func loonIPRewriteHoldsWhole(_ ir: inout ModuleIR) {
        func inSection(_ origin: ModuleLineOrigin) -> Bool { key(of: origin.section) == "iprewrite" }
        func written(_ edit: ModuleConfigurationEdit) -> String {
            ((try? JSONSerialization.jsonObject(with: Data(edit.valueJSON.utf8))) as? [String])?.first ?? edit.valueJSON
        }
        let lines = ir.edits.filter { $0.path == ["x-clash-ip-rewrite"] && inSection($0.origin) }
        guard !lines.isEmpty else { return }
        let addresses = lines.map { written($0).split(separator: "=").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? "" }
        guard ir.ignored.contains(where: { inSection($0.origin) }) || Set(addresses).count != addresses.count else { return }
        ir.edits.removeAll { $0.path == ["x-clash-ip-rewrite"] && inSection($0.origin) }
        for edit in lines {
            ir.ignored.append(ModuleIgnoredEntry(text: written(edit), reason: .noEffectInItsOwnApp(.noEffectThereEither), origin: edit.origin))
        }
    }

     
     
     
     
     
     
     
     
     
     
     
    private static func settingsSectionsHoldWhole(_ ir: inout ModuleIR) {
        func isListener(_ edit: ModuleConfigurationEdit, _ name: String) -> Bool { edit.path == ["listeners", name] }
        func fields(_ edit: ModuleConfigurationEdit) -> [(key: String, value: OrderedJSON)] {
            if case .object(let pairs)? = try? OrderedJSON.parse(edit.valueJSON) { return pairs }
            return []
        }
        func leaveOut(_ origins: Set<ModuleLineOrigin>, because reason: ModuleIgnoredReason = .notApplicable(.partCannotBeUsed)) {
            let taken = ir.edits.filter { origins.contains($0.origin) }
            ir.edits.removeAll { origins.contains($0.origin) }
            ir.changes.removeAll { origins.contains($0.origin) }
            for edit in taken where !ir.ignored.contains(where: { $0.origin == edit.origin }) {
                ir.ignored.append(ModuleIgnoredEntry(text: edit.path.joined(separator: "."), reason: reason, origin: edit.origin))
            }
        }
         
        let wireGuard = Dictionary(grouping: ir.edits.filter { $0.path.first == "proxies" }, by: \.origin.section)
        for (section, edits) in wireGuard where ir.ignored.contains(where: { entry in
            entry.origin.section == section && [.unreadableLine].contains(entry.reason)
        }) {
            leaveOut(Set(edits.map(\.origin)))
        }
         
        for name in [ModuleSettingsMapping.snellListener, ModuleSettingsMapping.mtprotoListener] {
            let edits = ir.edits.filter { isListener($0, name) }
            guard let first = edits.first else { continue }
            let keys = Set(edits.flatMap { fields($0).map(\.key) })
            var added: [(key: String, value: OrderedJSON)] = []
             
             
             
            if name == ModuleSettingsMapping.mtprotoListener, !keys.isSuperset(of: ["secret", "port"]) {
                leaveOut(Set(edits.map(\.origin)))
                continue
            }
            if name == ModuleSettingsMapping.snellListener {
                if !keys.isSuperset(of: ["psk", "port"]) {
                    leaveOut(Set(edits.map(\.origin)))
                    continue
                }
                 
                 
                let pairs = edits.flatMap { fields($0) }
                if pairs.last(where: { $0.key == "version" })?.value.serialized() == "6",
                   case .string(let psk)? = pairs.last(where: { $0.key == "psk" })?.value, !(12...255).contains(psk.utf8.count) {
                    leaveOut(Set(edits.map(\.origin)))
                    continue
                }
                 
                 
                if !keys.contains("version") { added.append(("version", .scalar("1"))) }
            }
            if !keys.contains("listen") { added.append(("listen", .string(ModuleSettingsMapping.listenerDefaultAddress))) }
            guard !added.isEmpty, let index = ir.edits.firstIndex(of: first) else { continue }
            ir.edits[index].valueJSON = OrderedJSON.object(fields(first) + added).serialized()
        }
    }
     
     
    private static func scriptOptions(_ line: String, loonStyle: Bool) -> [(key: String, value: String)] {
        if loonStyle { return ModuleLineSyntax.loonScriptParts(line)?.options ?? [] }
        guard let equals = line.firstIndex(of: "=") else { return [] }
        return ModuleLineSyntax.parameters(String(line[line.index(after: equals)...]))
    }

     
     
     
     
     
     
     
    private static let loonScriptOptions: Set<String> = [
        "script-path", "requires-body", "require-body", "binary-body-mode", "binary-mode", "timeout", "time-out", "tag",
        "img-url", "enable", "enabled", "argument", "max-size", "script-update-interval",
    ]

     
     
     
    private static let surgeScriptOptions: Set<String> = [
        "type", "pattern", "script-path", "requires-body", "require-body", "binary-body-mode", "binary-mode", "max-size",
        "timeout", "time-out", "argument", "script-update-interval", "engine", "debug", "enable", "ability", "wake-system",
        "cronexp", "cronexpr", "event-name", "full-header-mode", "tag",
    ]

    private static func take(_ line: String, written: String, section: String, origin: ModuleLineOrigin, loon: Bool,
                             platform: ModulePlatform, check: ModuleRuleMapping.Check, into ir: inout ModuleIR) throws {
        func ignore(_ reason: ModuleIgnoredReason) {
            ir.ignored.append(ModuleIgnoredEntry(text: written, reason: reason, origin: origin))
        }
        func keep(_ result: Result<ModuleRewriteRule, ModuleIgnoredReason>) {
            switch result {
            case .success(let rule): ir.rewriteRules.append(rule)
            case .failure(let reason): ignore(reason)
            }
        }
         
         
         
        func answer(_ result: Result<ModuleLocalAnswerSyntax.Reading, ModuleIgnoredReason>) {
            switch result {
            case .success(let read):
                ir.rewriteRules.append(read.rule)
                ir.answerFiles += read.files
                for note in read.notes { ignore(note) }
            case .failure(let reason): ignore(reason)
            }
        }
         
         
        func surgeSectionInLoon(_ result: Result<ModuleRewriteRule, ModuleIgnoredReason>) {
            keep(result)
            if loon, case .success = result { ignore(.noEffectInItsOwnApp(.anotherAppsFormatWorksHere)) }
        }
         
         
        func read(_ result: Result<ModuleLineSyntax.Reading, ModuleIgnoredReason>) {
            switch result {
            case .success(let reading):
                ir.rewriteRules += reading.rules
                ir.answerFiles += reading.files
            case .failure(let reason): ignore(reason)
            }
        }
        let sectionKey = key(of: section)
        if ["rewrite", "script"].contains(sectionKey), ModuleLineSyntax.isNewerLoonSyntax(line) {
            return ignore(.newerSyntaxNotSupported)
        }
        switch sectionKey {
        case "general", "mitm":
            guard let equals = line.firstIndex(of: "=") else { return ignore(.unreadableLine) }
            let name = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: equals)...])
            if (sectionKey == "general" && name == "force-http-engine-hosts") || (sectionKey == "mitm" && name == "hostname") {
                var parsed = ModuleHostList.line(value, origin: origin)
                 
                 
                if loon { parsed.line.directive = .merge }
                if sectionKey == "mitm" { ir.mitmHostLines.append(parsed.line) } else { ir.forceHTTPEngineHostLines.append(parsed.line) }
                ir.ignored += parsed.ignored
            } else if sectionKey == "mitm", name == "h2" {
                 
                 
                switch value.trimmingCharacters(in: .whitespaces).lowercased() {
                case "true": ir.mitmHTTP2 = true
                case "false": ir.mitmHTTP2 = false
                default: return ignore(.unreadableLine)
                }
                ir.inEffect.append(ModuleSettingInEffect(key: "h2", origin: origin))
            } else if sectionKey == "mitm" {
                 
                 
                ignore(["ca-p12", "ca-passphrase", "ca-keystore-name"].contains(name) ? .notApplicable(.modulesCannotChangeCertificate)
                                                                                    : .settingNotSupported(name))
            } else {
                let (directive, rest) = Self.directive(value)
                let mapped = ModuleSettingsMapping.general(name, directive: directive, value: rest, family: loon ? .loon : .surge,
                                                            origin: origin, platform: platform)
                ModuleSettingsMapping.take(mapped, written: written, origin: origin, key: name, into: &ir)
            }
        case "host":
             
             
            if let made = ModuleHostMappingSyntax.setLine(line, origin: origin) {
                switch made {
                case .success(let taken):
                    ir.hosts.append(taken.mapping)
                    ModuleRuleSetSyntax.add(taken.set, to: &ir.ruleSets)
                case .failure(let reason):
                    ignore(reason)
                }
                return
            }
            switch ModuleHostMappingSyntax.line(line, origin: origin) {
             
            case .success(let mapping) where mapping.value == .ipMode("dual"):
                ir.inEffect.append(ModuleSettingInEffect(key: "ip-mode", origin: origin))
            case .success(let mapping): ir.hosts.append(mapping)
            case .failure(let reason): ignore(reason)
            }
        case "iprewrite":
            let mapped = ModuleSettingsMapping.ipRewrite(line, family: loon ? .loon : .surge, origin: origin)
            let kept = ir.edits.filter { $0.path == ["x-clash-ip-rewrite"] }.count
            if kept >= ModuleSettingsMapping.maximumIPRewriteLines, mapped.contains(where: { if case .edits = $0 { return true } else { return false } }) {
                return ignore(.argumentsOverLimit)
            }
            ModuleSettingsMapping.take(mapped, written: written, origin: origin, key: "ip-rewrite", into: &ir)
        case "mtproto":
            ModuleSettingsMapping.take(ModuleSettingsMapping.mtproto(line, origin: origin, platform: platform), written: written, origin: origin,
                                        key: "mtproto", into: &ir)
        case "snellserver":
            ModuleSettingsMapping.take(ModuleSettingsMapping.snellServer(line, origin: origin), written: written, origin: origin,
                                        key: "snell-server", into: &ir)
         
         
        case let other where other.hasPrefix("wireguard") && other.count > "wireguard".count:
            let node = section.trimmingCharacters(in: .whitespaces).dropFirst("WireGuard".count).trimmingCharacters(in: .whitespaces)
            ModuleSettingsMapping.take(ModuleSettingsMapping.wireGuard(line, node: node, origin: origin), written: written,
                                        origin: origin, key: "wireguard", into: &ir)
        case "rule":
            let mapped = try ModuleRuleMapping.map(line, family: loon ? .loon : .surge, platform: platform, origin: origin, check: check)
            ModuleRuleMapping.take(mapped, written: written, origin: origin, into: &ir)
         
         
         
        case "urlrewrite" where loon || ModuleLineSyntax.isLoonOperationLine(line), "rewrite":
             
            if ModuleLocalAnswerSyntax.isLoonClassicMock(line) {
                return answer(ModuleLocalAnswerSyntax.loonClassicMock(line, origin: origin, moduleURL: ir.manifest.sourceURL))
            }
            read(ModuleLineSyntax.loonRewriteReading(line, origin: origin, moduleURL: ir.manifest.sourceURL))
        case "urlrewrite": keep(ModuleLineSyntax.urlRewrite(line, origin: origin))
        case "headerrewrite": surgeSectionInLoon(ModuleLineSyntax.headerRewrite(line, origin: origin))
        case "bodyrewrite":
            let reading = ModuleLineSyntax.bodyRewriteReading(line, origin: origin, moduleURL: ir.manifest.sourceURL)
            read(reading)
            if loon, case .success = reading { ignore(.noEffectInItsOwnApp(.anotherAppsFormatWorksHere)) }
        case "script":
            let loonStyle = ModuleLineSyntax.isLoonScriptLine(line)
            let parsed = loonStyle ? ModuleLineSyntax.loonScript(line, origin: origin) : ModuleLineSyntax.surgeScript(line, origin: origin)
            switch parsed {
            case .success(let declared):
                let options = scriptOptions(line, loonStyle: loonStyle)
                let ownOptions = loon && loonStyle ? loonScriptOptions : surgeScriptOptions
                 
                let icon = loon && loonStyle ? options.first { $0.key == "img-url" }.flatMap { $0.value.isEmpty ? nil : $0.value } : nil
                switch declared {
                case .http(var script):
                     
                    if loon, loonStyle {
                        script.pattern = ModuleLoonRewriteSyntax.ignoringCase(script.pattern)
                        script.imageURL = icon
                    }
                    ir.scripts.append(script)
                case .app(var script):
                    if loon, loonStyle { script.imageURL = icon }
                    ir.appScripts.append(script)
                }
                 
                 
                if options.contains(where: { !ownOptions.contains($0.key) }) {
                    ignore(.noEffectInItsOwnApp(.optionsWithNoEffect))
                }
            case .failure(let reason): ignore(reason)
            }
        case "maplocal":
            let note = ModuleIgnoredReason.noEffectInItsOwnApp(.anotherAppsFormatWorksHere)
            let read = ModuleLocalAnswerSyntax.mapLocal(line, origin: origin, moduleURL: ir.manifest.sourceURL)
            answer(read)
            if loon, case .success(let taken) = read, !taken.notes.contains(note) { ignore(note) }
        case "panel":
            switch ModuleLineSyntax.panel(line, origin: origin) {
            case .success(let panel): ir.panels.append(panel)
            case .failure(let reason): ignore(reason)
            }
        case "argument":
             
             
            if loonArgument(line) == nil { ignore(.unreadableLine) }
         
         
        case "proxy", "proxygroup": ignore(.notApplicable(.modulesCannotAddProxies))
        case "replica", "plugin": ignore(.notApplicable(.noEffect))
        case let other where quantumultXSections.contains(other): ignore(.notApplicable(.writtenForAnotherApp))
        default: ignore(.sectionNotSupported(section))
        }
    }
}
