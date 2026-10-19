import Darwin
import Foundation
import os

 
 
 
 
 
 
struct AdBlockRequirementEnvironment: Equatable, Sendable {
    var coreVersion: Int
     
     
    var systemVersion: String
     
     
    var systemVersionDescription: String
     
    var deviceModel: String
     
    var language: String

     
     
     
     
     
    static var current: AdBlockRequirementEnvironment {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return AdBlockRequirementEnvironment(coreVersion: AdBlockModuleParser.declaredCoreVersion,
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

 
 
 
 
 
 
 
enum AdBlockModuleParser {
     
     
     
    static let maximumBytes = 2 << 20

    static func parse(_ data: Data, sourceURL: String?, fetchedAt: Date?,
                      platform: AdBlockPlatform = .current,
                      environment: AdBlockRequirementEnvironment = .current,
                      check: AdBlockRuleMapping.Check = AdBlockRuleMapping.kernelCheck) throws -> Result<AdBlockModuleIR, AdBlockModuleRefusal> {
        guard data.count <= maximumBytes else { return .failure(.tooLarge(data.count)) }
        guard var text = String(data: data, encoding: .utf8) else { return .failure(.notText) }
         
         
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let manifest = AdBlockModuleManifest(
            name: nil, desc: nil, author: nil, icon: nil, system: [], arguments: [], format: .surge,
            sourceURL: sourceURL, fetchedAt: fetchedAt, contentSHA256: AdBlockJSON.sha256(data))
        if isQuantumultX(text, sourceURL: sourceURL) {
            // The reader reports a file it cannot read as an ignored module the
            // user can see, rather than throwing; only a line inside it is
            // reported per-line.
            return try AdBlockQuantumultXParser.parse(text, manifest: manifest, sourceURL: sourceURL,
                                                       platform: platform,
                                                       check: check).map(bounded)
        }
        if isStash(text, sourceURL: sourceURL) {
            return try AdBlockStashParser.parse(text, manifest: manifest, platform: platform, check: check).map(bounded)
        }
        return try parseSections(text, manifest: manifest, sourceURL: sourceURL, platform: platform, environment: environment,
                                 check: check).map(bounded)
    }

     
     
     
     
     
    static let maximumShownBytes = 1024
    static let maximumSourceURLBytes = 4096

     
     
    static func bounded(_ ir: AdBlockModuleIR) -> AdBlockModuleIR {
        var out = ir
        func cut(_ text: String) -> String { prefix(text, bytes: maximumShownBytes) }
        out.manifest.sourceURL = ir.manifest.sourceURL.map { prefix($0, bytes: maximumSourceURLBytes) }
        for index in out.ignored.indices {
            out.ignored[index].text = cut(out.ignored[index].text)
            let reason: AdBlockIgnoredReason
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
        let actions: Set<String> = [
            "reject", "reject-200", "reject-img", "reject-dict", "reject-array", "302", "307",
            "request-header", "request-body", "response-header", "response-body", "echo-response",
            "script-request-header", "script-request-body", "script-response-header", "script-response-body",
            "script-echo-response", "script-analyze-echo-response",
        ]
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
            let words = line.split(separator: " ")
            if words.count >= 3, words[1] == "url", actions.contains(words[2].lowercased()) { sawLine = true }
        }
        if sawQuantumultXSection { return !sawFamilySection }
        let address = path(of: sourceURL)
        return !sawSection && (sawLine || address.hasSuffix(".conf") || address.hasSuffix(".snippet"))
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
        if AdBlockLineSyntax.isNewerLoonSyntax(line.trimmingCharacters(in: .whitespaces)) {
            return AdBlockLoonRewriteSyntax.strippingComment(line)
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

     

     
     
     
     
    static func arguments(_ value: String) -> [AdBlockModuleArgument] {
        cappedArguments(value).kept
    }

     
     
     
     
     
     
     
     
     
    static let maximumArguments = 256
    static let maximumArgumentBytes = 1024
     
    static let maximumSystems = 64
     
     
     
    static let maximumDescriptionBytes = 4096
     
     
     
     
     
    static let maximumArgumentsDescriptionBytes = 32 * 1024

     
     
     
     
    static func cappedArguments(_ value: String) -> (kept: [AdBlockModuleArgument], dropped: Int, droppedNames: [String]) {
        var kept: [AdBlockModuleArgument] = []
        var droppedNames: [String] = []
        var dropped = 0
        for item in commaSplit(value) {
            let part = item.trimmingCharacters(in: .whitespaces)
            guard !part.isEmpty else { continue }
            let argument: AdBlockModuleArgument
            if let colon = part.firstIndex(of: ":") {
                argument = AdBlockModuleArgument(name: unquoted(part[..<colon].trimmingCharacters(in: .whitespaces)),
                                                 defaultValue: unquoted(part[part.index(after: colon)...].trimmingCharacters(in: .whitespaces)))
            } else {
                argument = AdBlockModuleArgument(name: unquoted(part), defaultValue: nil)
            }
            guard kept.count < maximumArguments, isWithinLimit(argument) else {
                dropped += 1
                droppedNames.append(argument.name)
                continue
            }
            kept.append(argument)
        }
        return (kept, dropped, droppedNames)
    }

     
     
    static func isWithinLimit(_ argument: AdBlockModuleArgument) -> Bool {
        argument.name.utf8.count + 1 + (argument.defaultValue?.utf8.count ?? 0) <= maximumArgumentBytes
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
            let name = String(line[nameRange])
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
        if AdBlockLineSyntax.isLoonScriptLine(line) {
            guard let split = AdBlockLineSyntax.splitHead(line, count: 2) else { return false }
            parameters = AdBlockLineSyntax.parameters(split.rest)
            if split.head.contains(where: { $0.contains("{{{") }) { return false }
        } else {
            guard let equals = line.firstIndex(of: "=") else { return false }
            if line[..<equals].contains("{{{") { return false }
            parameters = AdBlockLineSyntax.parameters(String(line[line.index(after: equals)...]))
        }
        func count(_ text: String) -> Int { text.components(separatedBy: "{{{").count - 1 }
        let inArgument = parameters.filter { $0.key == "argument" }.reduce(0) { $0 + count($1.value) }
        return inArgument > 0 && inArgument == count(line)
    }

     
     
     
    static let converterKeys: Set<String> = ["raw-url", "tg-channel", "basedon", "surge_version", "bundleid", "update-url",
                                             "total", "mitm", "reject", "redirect", "updatetime", "edit", "manual"]
     
     
    static let loonConverterKeys: Set<String> = ["category", "version"]
     
     
     
    private static let keysReadElsewhere: Set<String> = ["requirement", "select", "input"]
     
     
     
    static let maximumOtherKeys = 64

     
     
     
     
     
     
     
     
     
     
    private static func readMetadata(_ line: String, loon: Bool, into manifest: inout AdBlockModuleManifest) -> AdBlockIgnoredReason? {
        guard line.hasPrefix("#!"), let equals = line.firstIndex(of: "=") else { return nil }
        let written = line[line.index(line.startIndex, offsetBy: 2)..<equals].trimmingCharacters(in: .whitespaces)
         
        guard !written.isEmpty, written.allSatisfy({ $0.isLetter || $0.isNumber || "_-.".contains($0) }) else { return nil }
        let key = written.lowercased()
        if converterKeys.contains(key) || (loon && loonConverterKeys.contains(key)) || keysReadElsewhere.contains(key) { return nil }
        let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        let limit = key == "desc" ? maximumDescriptionBytes : key == "arguments-desc" ? maximumArgumentsDescriptionBytes : maximumArgumentBytes
        let cut = prefix(value, bytes: limit)
        switch key {
        case "name": manifest.name = cut
        case "desc": manifest.desc = cut
        case "author": manifest.author = cut
        case "icon": manifest.icon = cut
        case "homepage": manifest.homepage = cut
        case "category": manifest.category = cut
        case "openurl": manifest.openURL = cut
        case "date": manifest.date = cut
        case "tag": manifest.tag = cut
        case "version": manifest.version = cut
        case "arguments-desc": manifest.argumentsDescription = cut
        case "system":
            let capped = cappedSystems(value)
            manifest.system = capped.kept
            return capped.dropped > 0 ? .headerOverLimit : nil
        case "arguments":
            manifest.arguments = arguments(value)
            return nil
        case "type":
            return value.lowercased() == "parser" ? .unsupportedScriptType("parser") : nil
        default:
            guard manifest.otherKeys.count < maximumOtherKeys, written.utf8.count <= maximumArgumentBytes else { return .headerOverLimit }
            manifest.otherKeys.append(AdBlockManifestKey(key: written, value: cut))
        }
        return cut.utf8.count < value.utf8.count ? .headerOverLimit : nil
    }

     
     
     
    static func systems(_ value: String) -> [String] { cappedSystems(value).kept }

     
     
     
    static func cappedSystems(_ value: String) -> (kept: [String], dropped: Int) {
        var out: [String] = []
        var dropped = 0
        for word in value.lowercased().split(separator: ",") {
            let name = word.trimmingCharacters(in: .whitespaces)
            let platform: String
            switch name {
            case "": continue
            case "ios", "ipados", "iphoneos": platform = "ios"
            case "mac", "macos", "osx": platform = "mac"
            default: platform = name
            }
            guard !out.contains(platform) else { continue }
            guard out.count < maximumSystems, platform.utf8.count <= maximumArgumentBytes else {
                dropped += 1
                continue
            }
            out.append(platform)
        }
        return (out, dropped)
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

     
     
     
     
     
     
     
     
    static func platforms(meeting requirement: String, environment: AdBlockRequirementEnvironment? = nil,
                          deadline: TimeInterval = requirementRegexDeadline) -> [String] {
        let systems = [("ios", ["ios", "ipados"]), ("mac", ["macos"]), ("tvos", ["tvos"])]
        let expression = Requirement(requirement)
        var timedOut = false
        var clock = AdBlockRegexDeadline(deadline)
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

         
         
         
        func holds(system: [String], environment: AdBlockRequirementEnvironment?, clock: inout AdBlockRegexDeadline,
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
                        if let have = AdBlockRequirementEnvironment.version(environment.systemVersion),
                           let wanted = AdBlockRequirementEnvironment.version(value), !Self.stringOperators.contains(op) {
                            return .some(Self.compare(AdBlockRequirementEnvironment.order(have, wanted), op))
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

         
         
         
         
        static func matches(_ have: String, _ op: String, _ wanted: String, clock: inout AdBlockRegexDeadline,
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

         
         
         
         
        private static func wholeMatch(_ text: String, _ pattern: String, clock: inout AdBlockRegexDeadline,
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

     

     
     
     
     
    static func loonArgument(_ line: String) -> AdBlockModuleArgument? {
        guard let equals = line.firstIndex(of: "=") else { return nil }
        let name = line[..<equals].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name.allSatisfy({ !$0.isWhitespace && !"${},\"'".contains($0) }) else { return nil }
        var parts = commaSplit(String(line[line.index(after: equals)...]))
        guard !parts.isEmpty else { return nil }
        let control = parts.removeFirst().trimmingCharacters(in: .whitespaces).lowercased()
        var values: [String] = []
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            let lowered = trimmed.lowercased()
            if ["type", "tag", "desc"].contains(where: { lowered.hasPrefix($0 + "=") || lowered.hasPrefix($0 + " =") }) { break }
            values.append(unquoted(trimmed))
        }
        var value = values.first
        if control == "switch", let written = value?.lowercased(), written != "true", written != "false" { value = nil }
        if control == "switch" { value = value?.lowercased() }
        if control != "input", control != "select", control != "switch" { value = nil }
        return AdBlockModuleArgument(name: name, defaultValue: value)
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

     
     
     
     
     
    static func substitutingLoon(_ line: String, arguments: [String: String?]) -> Result<String, AdBlockIgnoredReason> {
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

     

    private static func parseSections(_ text: String, manifest base: AdBlockModuleManifest, sourceURL: String?,
                                      platform: AdBlockPlatform, environment: AdBlockRequirementEnvironment,
                                      check: AdBlockRuleMapping.Check) throws -> Result<AdBlockModuleIR, AdBlockModuleRefusal> {
        let lines = text.components(separatedBy: "\n")
        var manifest = base
         
        let loonSections = lines.contains { raw in
            let written = strippingComment(raw.trimmingCharacters(in: .whitespaces))
            guard written.hasPrefix("["), written.hasSuffix("]") else { return false }
            return ["rewrite", "argument"].contains(key(of: String(written.dropFirst().dropLast())))
        }
         
         
        let newerLoonLines = lines.contains { AdBlockLoonRewriteSyntax.isRule($0.trimmingCharacters(in: .whitespaces)) }
        let address = path(of: sourceURL)
        var loon = address.hasSuffix(".plugin") || address.hasSuffix(".lpx") || loonSections || newerLoonLines
        var headerNotes: [AdBlockIgnoredEntry] = []
        for (index, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let reason = readMetadata(line, loon: loon, into: &manifest) else { continue }
             
            let shown = reason == .headerOverLimit
                ? line.firstIndex(of: "=").map { String(line[..<$0]).trimmingCharacters(in: .whitespaces) } ?? "#!" : line
            headerNotes.append(AdBlockIgnoredEntry(text: prefix(shown, bytes: maximumArgumentBytes), reason: reason,
                                                   origin: AdBlockLineOrigin(section: "", line: index + 1)))
        }
        if !manifest.system.isEmpty, !manifest.system.contains(platform.rawValue) {
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
         
        var loonTypes: [String: AdBlockLoonRewriteSyntax.SettingType] = [:]
         
         
        var overLimit = Set<Int>()
        var droppedNames = Set<String>()
        var scanning: String?
        for (index, raw) in lines.enumerated() {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("//") || trimmed.hasPrefix(";") { continue }
            let written = strippingComment(trimmed)
            if written.hasPrefix("["), written.hasSuffix("]") {
                scanning = key(of: String(written.dropFirst().dropLast()))
                if ["rewrite", "argument"].contains(scanning!) { loon = true }
            } else if scanning == "argument", let argument = loonArgument(written) {
                let known = manifest.arguments.contains { $0.name == argument.name }
                guard isWithinLimit(argument), known || manifest.arguments.count < maximumArguments else {
                    overLimit.insert(index)
                     
                     
                    droppedNames.insert(argument.name)
                    continue
                }
                loonArguments[argument.name] = .some(argument.defaultValue)
                loonTypes[argument.name] = AdBlockLoonRewriteSyntax.declaredType(ofArgument: written)
                if !known { manifest.arguments.append(argument) }
            }
        }
         
         
         
        var argumentsLine: (index: Int, value: String)?
        for (index, raw) in lines.enumerated() {
            if let value = metadataValue(raw, "arguments") { argumentsLine = (index, value) }
        }
        var argumentsOverLimit: AdBlockIgnoredEntry?
        if let argumentsLine {
            let capped = cappedArguments(argumentsLine.value)
            if capped.dropped > 0 {
                argumentsOverLimit = AdBlockIgnoredEntry(text: "#!arguments", reason: .argumentsOverLimit,
                                                         origin: AdBlockLineOrigin(section: "", line: argumentsLine.index + 1))
            }
            droppedNames.formUnion(capped.droppedNames.filter { name in !manifest.arguments.contains { $0.name == name } })
        }
        manifest.arguments.removeAll { droppedNames.contains($0.name) }
        for name in droppedNames { loonArguments.removeValue(forKey: name) }
         
         
         
        var newerLoonArguments = loonArguments
        for name in droppedNames { newerLoonArguments[name] = .some(nil) }
         
         
        let declaredNames = Set(manifest.arguments.map(\.name)).union(loonArguments.keys).union(droppedNames)
        func holdsPlaceholder(_ text: String) -> Bool {
            text.contains("{{{") || text.contains("${args.") || loonReferences(in: text).contains(where: declaredNames.contains)
        }
        manifest.arguments = manifest.arguments.map { argument in
            argument.defaultValue.map(holdsPlaceholder) == true ? AdBlockModuleArgument(name: argument.name, defaultValue: nil) : argument
        }
        for (name, value) in loonArguments where (value ?? nil).map(holdsPlaceholder) == true { loonArguments[name] = .some(nil) }
        var defaults: [String: String] = [:]
        for argument in manifest.arguments where defaults[argument.name] == nil { defaults[argument.name] = argument.defaultValue }
        var ir = AdBlockModuleIR.empty(manifest)
        ir.ignored += headerNotes
        if let argumentsOverLimit { ir.ignored.append(argumentsOverLimit) }
         
        for name in droppedNames where loonArguments[name] == nil { loonArguments[name] = .some(nil) }
        var section: String?
         
        var rulesets: [(name: String, lines: [(text: String, origin: AdBlockLineOrigin)])] = []
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
            let origin = AdBlockLineOrigin(section: section ?? "", line: index + 1)
            guard let current = section else {
                ir.ignored.append(AdBlockIgnoredEntry(text: written, reason: .unreadableLine, origin: origin))
                continue
            }
            if overLimit.contains(index) {
                ir.ignored.append(AdBlockIgnoredEntry(text: prefix(written, bytes: maximumArgumentBytes), reason: .argumentsOverLimit,
                                                      origin: origin))
                continue
            }
             
             
             
            if loon, ["rewrite", "urlrewrite"].contains(key(of: current)), AdBlockLoonRewriteSyntax.isRule(trimmed) {
                 
                switch AdBlockLoonRewriteSyntax.reading(trimmed, origin: origin, arguments: newerLoonArguments, types: loonTypes,
                                                        moduleURL: sourceURL) {
                case .success(let read):
                    ir.rewriteRules.append(read.rule)
                    ir.answerFiles += read.files
                case .failure(let reason): ir.ignored.append(AdBlockIgnoredEntry(text: written, reason: reason, origin: origin))
                }
                continue
            }
             
             
            if loon, key(of: current) == "script", AdBlockLoonRewriteSyntax.isRule(trimmed) {
                switch AdBlockLoonRewriteSyntax.scriptRule(trimmed, origin: origin, arguments: newerLoonArguments, types: loonTypes,
                                                           moduleURL: sourceURL) {
                case .success(let script): ir.scripts.append(script)
                case .failure(let reason): ir.ignored.append(AdBlockIgnoredEntry(text: written, reason: reason, origin: origin))
                }
                continue
            }
            let surge = substituting(written, defaults: defaults)
            var filled: Result<String, AdBlockIgnoredReason> = .success(surge.text)
            if loon, key(of: current) != "argument" {
                filled = substitutingLoon(surge.text, arguments: loonArguments)
            }
            if case .success(let line) = filled, let name = surge.unresolved.first,
               key(of: current) != "script" || !placeholdersOnlyInArgument(line)
                || surge.unresolved.contains(where: droppedNames.contains) {
                 
                 
                filled = .failure(.missingArgument(surge.unresolved.first(where: droppedNames.contains) ?? name))
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
                try take(line, written: written, section: current, origin: origin, loon: loon, platform: platform, check: check, into: &ir)
            case .failure(let reason):
                ir.ignored.append(AdBlockIgnoredEntry(text: written, reason: reason, origin: origin))
            }
        }
        guard section != nil else { return .failure(.notAModule) }
        for ruleset in rulesets {
            AdBlockRuleSetSyntax.takeSection(ruleset.name, lines: ruleset.lines, family: loon ? .loon : .surge, platform: platform,
                                              check: check, into: &ir)
        }
        if loon { loonIPRewriteHoldsWhole(&ir) }
        settingsSectionsHoldWhole(&ir)
        if loon { manifest.format = .loon }
        ir.manifest = manifest
        // A script carries the defaults of the arguments it asked for, so the
        // tunnel can build `$argument` without re-reading the module. The
        // declared kind is what decides whether a value is a boolean, a number
        // or text, so the whole declaration is kept, not just its default.
        let declared = Dictionary(manifest.arguments.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        for index in ir.scripts.indices {
            guard let names = ir.scripts[index].argumentNames, !names.isEmpty else { continue }
            ir.scripts[index].argumentDefaults = names.map { name in
                AdBlockScriptArgument(name: name, kind: declared[name]?.declaredKind,
                                      defaultValue: declared[name]?.defaultValue)
            }
        }
        return .success(ir)
    }

     
     
    static func directive(_ value: String) -> (AdBlockHostListDirective?, String) {
        let text = value.trimmingCharacters(in: .whitespaces)
        for (word, directive) in [("%APPEND%", AdBlockHostListDirective.append), ("%INSERT%", .insert)]
        where text.uppercased().hasPrefix(word) {
            return (directive, String(text.dropFirst(word.count)).trimmingCharacters(in: .whitespaces))
        }
        return (nil, text)
    }

     
     
     
    private static func loonIPRewriteHoldsWhole(_ ir: inout AdBlockModuleIR) {
        func inSection(_ origin: AdBlockLineOrigin) -> Bool { key(of: origin.section) == "iprewrite" }
        func written(_ edit: AdBlockConfigurationEdit) -> String {
            ((try? JSONSerialization.jsonObject(with: Data(edit.valueJSON.utf8))) as? [String])?.first ?? edit.valueJSON
        }
        let lines = ir.edits.filter { $0.path == ["x-clash-ip-rewrite"] && inSection($0.origin) }
        guard !lines.isEmpty else { return }
        let addresses = lines.map { written($0).split(separator: "=").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? "" }
        guard ir.ignored.contains(where: { inSection($0.origin) }) || Set(addresses).count != addresses.count else { return }
        ir.edits.removeAll { $0.path == ["x-clash-ip-rewrite"] && inSection($0.origin) }
        for edit in lines {
            ir.ignored.append(AdBlockIgnoredEntry(text: written(edit), reason: .noEffectInItsOwnApp(.noEffectThereEither), origin: edit.origin))
        }
    }

     
     
     
     
     
     
     
     
     
     
     
    private static func settingsSectionsHoldWhole(_ ir: inout AdBlockModuleIR) {
        func isListener(_ edit: AdBlockConfigurationEdit, _ name: String) -> Bool { edit.path == ["listeners", name] }
        func fields(_ edit: AdBlockConfigurationEdit) -> [(key: String, value: OrderedJSON)] {
            if case .object(let pairs)? = try? OrderedJSON.parse(edit.valueJSON) { return pairs }
            return []
        }
        func leaveOut(_ origins: Set<AdBlockLineOrigin>, because reason: AdBlockIgnoredReason = .notApplicable(.partCannotBeUsed)) {
            let taken = ir.edits.filter { origins.contains($0.origin) }
            ir.edits.removeAll { origins.contains($0.origin) }
            ir.changes.removeAll { origins.contains($0.origin) }
            for edit in taken where !ir.ignored.contains(where: { $0.origin == edit.origin }) {
                ir.ignored.append(AdBlockIgnoredEntry(text: edit.path.joined(separator: "."), reason: reason, origin: edit.origin))
            }
        }
         
        let wireGuard = Dictionary(grouping: ir.edits.filter { $0.path.first == "proxies" }, by: \.origin.section)
        for (section, edits) in wireGuard where ir.ignored.contains(where: { entry in
            entry.origin.section == section && [.unreadableLine].contains(entry.reason)
        }) {
            leaveOut(Set(edits.map(\.origin)))
        }
         
        for name in [AdBlockSettingsMapping.snellListener, AdBlockSettingsMapping.mtprotoListener] {
            let edits = ir.edits.filter { isListener($0, name) }
            guard let first = edits.first else { continue }
            let keys = Set(edits.flatMap { fields($0).map(\.key) })
            var added: [(key: String, value: OrderedJSON)] = []
             
             
             
            if name == AdBlockSettingsMapping.mtprotoListener, !keys.isSuperset(of: ["secret", "port"]) {
                leaveOut(Set(edits.map(\.origin)))
                continue
            }
            if name == AdBlockSettingsMapping.snellListener {
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
            if !keys.contains("listen") { added.append(("listen", .string(AdBlockSettingsMapping.listenerDefaultAddress))) }
            guard !added.isEmpty, let index = ir.edits.firstIndex(of: first) else { continue }
            ir.edits[index].valueJSON = OrderedJSON.object(fields(first) + added).serialized()
        }
    }
     
     
    private static func scriptOptions(_ line: String, loonStyle: Bool) -> [(key: String, value: String)] {
        if loonStyle { return AdBlockLineSyntax.splitHead(line, count: 2).map { AdBlockLineSyntax.parameters($0.rest) } ?? [] }
        guard let equals = line.firstIndex(of: "=") else { return [] }
        return AdBlockLineSyntax.parameters(String(line[line.index(after: equals)...]))
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

    private static func take(_ line: String, written: String, section: String, origin: AdBlockLineOrigin, loon: Bool,
                             platform: AdBlockPlatform, check: AdBlockRuleMapping.Check, into ir: inout AdBlockModuleIR) throws {
        func ignore(_ reason: AdBlockIgnoredReason) {
            ir.ignored.append(AdBlockIgnoredEntry(text: written, reason: reason, origin: origin))
        }
        func keep(_ result: Result<AdBlockRewriteRule, AdBlockIgnoredReason>) {
            switch result {
            case .success(let rule): ir.rewriteRules.append(rule)
            case .failure(let reason): ignore(reason)
            }
        }
         
         
         
        func answer(_ result: Result<AdBlockLocalAnswerSyntax.Reading, AdBlockIgnoredReason>) {
            switch result {
            case .success(let read):
                ir.rewriteRules.append(read.rule)
                ir.answerFiles += read.files
                for note in read.notes { ignore(note) }
            case .failure(let reason): ignore(reason)
            }
        }
         
         
        func surgeSectionInLoon(_ result: Result<AdBlockRewriteRule, AdBlockIgnoredReason>) {
            keep(result)
            if loon, case .success = result { ignore(.noEffectInItsOwnApp(.anotherAppsFormatWorksHere)) }
        }
         
         
        func read(_ result: Result<AdBlockLineSyntax.Reading, AdBlockIgnoredReason>) {
            switch result {
            case .success(let reading):
                ir.rewriteRules += reading.rules
                ir.answerFiles += reading.files
            case .failure(let reason): ignore(reason)
            }
        }
        let sectionKey = key(of: section)
        if ["rewrite", "script"].contains(sectionKey), AdBlockLineSyntax.isNewerLoonSyntax(line) {
            return ignore(.newerSyntaxNotSupported)
        }
        switch sectionKey {
        case "general", "mitm":
            guard let equals = line.firstIndex(of: "=") else { return ignore(.unreadableLine) }
            let name = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: equals)...])
            if (sectionKey == "general" && name == "force-http-engine-hosts") || (sectionKey == "mitm" && name == "hostname") {
                var parsed = AdBlockHostList.line(value, origin: origin)
                 
                 
                if loon { parsed.line.directive = .merge }
                if sectionKey == "mitm" { ir.mitmHostLines.append(parsed.line) } else { ir.forceHTTPEngineHostLines.append(parsed.line) }
                ir.ignored += parsed.ignored
            } else if sectionKey == "mitm" {
                 
                 
                ignore(["ca-p12", "ca-passphrase", "ca-keystore-name"].contains(name) ? .notApplicable(.modulesCannotChangeCertificate)
                                                                                    : .settingNotSupported(name))
            } else {
                let (directive, rest) = Self.directive(value)
                let mapped = AdBlockSettingsMapping.general(name, directive: directive, value: rest, family: loon ? .loon : .surge,
                                                            origin: origin, platform: platform)
                AdBlockSettingsMapping.take(mapped, written: written, origin: origin, key: name, into: &ir)
            }
        case "host":
             
             
            if let made = AdBlockHostMappingSyntax.setLine(line, origin: origin) {
                switch made {
                case .success(let taken):
                    ir.hosts.append(taken.mapping)
                    AdBlockRuleSetSyntax.add(taken.set, to: &ir.ruleSets)
                case .failure(let reason):
                    ignore(reason)
                }
                return
            }
            switch AdBlockHostMappingSyntax.line(line, origin: origin) {
             
            case .success(let mapping) where mapping.value == .ipMode("dual"):
                ir.inEffect.append(AdBlockSettingInEffect(key: "ip-mode", origin: origin))
            case .success(let mapping): ir.hosts.append(mapping)
            case .failure(let reason): ignore(reason)
            }
        case "iprewrite":
            let mapped = AdBlockSettingsMapping.ipRewrite(line, family: loon ? .loon : .surge, origin: origin)
            let kept = ir.edits.filter { $0.path == ["x-clash-ip-rewrite"] }.count
            if kept >= AdBlockSettingsMapping.maximumIPRewriteLines, mapped.contains(where: { if case .edits = $0 { return true } else { return false } }) {
                return ignore(.argumentsOverLimit)
            }
            AdBlockSettingsMapping.take(mapped, written: written, origin: origin, key: "ip-rewrite", into: &ir)
        case "mtproto":
            AdBlockSettingsMapping.take(AdBlockSettingsMapping.mtproto(line, origin: origin, platform: platform), written: written, origin: origin,
                                        key: "mtproto", into: &ir)
        case "snellserver":
            AdBlockSettingsMapping.take(AdBlockSettingsMapping.snellServer(line, origin: origin), written: written, origin: origin,
                                        key: "snell-server", into: &ir)
         
         
        case let other where other.hasPrefix("wireguard") && other.count > "wireguard".count:
            let node = section.trimmingCharacters(in: .whitespaces).dropFirst("WireGuard".count).trimmingCharacters(in: .whitespaces)
            AdBlockSettingsMapping.take(AdBlockSettingsMapping.wireGuard(line, node: node, origin: origin), written: written,
                                        origin: origin, key: "wireguard", into: &ir)
        case "rule":
            let mapped = try AdBlockRuleMapping.map(line, family: loon ? .loon : .surge, platform: platform, origin: origin, check: check)
            AdBlockRuleMapping.take(mapped, written: written, origin: origin, into: &ir)
         
         
         
        case "urlrewrite" where loon || AdBlockLineSyntax.isLoonOperationLine(line), "rewrite":
             
            if AdBlockLocalAnswerSyntax.isLoonClassicMock(line) {
                return answer(AdBlockLocalAnswerSyntax.loonClassicMock(line, origin: origin, moduleURL: ir.manifest.sourceURL))
            }
            read(AdBlockLineSyntax.loonRewriteReading(line, origin: origin, moduleURL: ir.manifest.sourceURL))
        case "urlrewrite": keep(AdBlockLineSyntax.urlRewrite(line, origin: origin))
        case "headerrewrite": surgeSectionInLoon(AdBlockLineSyntax.headerRewrite(line, origin: origin))
        case "bodyrewrite":
            let reading = AdBlockLineSyntax.bodyRewriteReading(line, origin: origin, moduleURL: ir.manifest.sourceURL)
            read(reading)
            if loon, case .success = reading { ignore(.noEffectInItsOwnApp(.anotherAppsFormatWorksHere)) }
        case "script":
            let loonStyle = AdBlockLineSyntax.isLoonScriptLine(line)
            let parsed = loonStyle ? AdBlockLineSyntax.loonScript(line, origin: origin) : AdBlockLineSyntax.surgeScript(line, origin: origin)
            switch parsed {
            case .success(var script):
                let options = scriptOptions(line, loonStyle: loonStyle)
                let ownOptions = loon && loonStyle ? loonScriptOptions : surgeScriptOptions
                if loon, loonStyle {
                     
                     
                    script.pattern = AdBlockLoonRewriteSyntax.ignoringCase(script.pattern)
                    script.imageURL = options.first { $0.key == "img-url" }.flatMap { $0.value.isEmpty ? nil : $0.value }
                }
                ir.scripts.append(script)
                 
                 
                if options.contains(where: { !ownOptions.contains($0.key) }) {
                    ignore(.noEffectInItsOwnApp(.optionsWithNoEffect))
                }
            case .failure(let reason): ignore(reason)
            }
        case "maplocal":
            let note = AdBlockIgnoredReason.noEffectInItsOwnApp(.anotherAppsFormatWorksHere)
            let read = AdBlockLocalAnswerSyntax.mapLocal(line, origin: origin, moduleURL: ir.manifest.sourceURL)
            answer(read)
            if loon, case .success(let taken) = read, !taken.notes.contains(note) { ignore(note) }
        case "argument":
             
             
            if loonArgument(line) == nil { ignore(.unreadableLine) }
         
         
        case "proxy", "proxygroup": ignore(.notApplicable(.modulesCannotAddProxies))
        case "replica", "plugin": ignore(.notApplicable(.noEffect))
        case let other where quantumultXSections.contains(other): ignore(.notApplicable(.writtenForAnotherApp))
        default: ignore(.sectionNotSupported(section))
        }
    }
}
