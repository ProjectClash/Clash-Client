import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum AdBlockLoonRewriteSyntax {
    enum Token: Equatable {
         
        case word(String)
         
         
        case string(String)
         
        case raw(String)
         
        case regex(String, flags: String)
        case number(Double)
        case bool(Bool)
         
        case reference(String)
        case symbol(String)
    }

     
    static let maximumLineBytes = 64 * 1024
     
     
    static let maximumDepth = 16
     
     
    static let maximumJQBytes = AdBlockJSONRewriteSyntax.maximumJQBytes

     
     
    static let mockContentTypes: [String: String] = [
        "json": "application/json", "text": "text/plain", "text/event-stream": "text/event-stream", "css": "text/css",
        "html": "text/html", "javascript": "application/javascript", "plain": "text/plain", "png": "image/png",
        "gif": "image/gif", "jpeg": "image/jpeg", "tiff": "image/tiff", "svg": "image/svg+xml", "mp4": "video/mp4",
        "form-data": "multipart/form-data",
    ]

     
    static func isRule(_ line: String) -> Bool {
        let words = line.split(maxSplits: 2, whereSeparator: { $0 == " " || $0 == "\t" })
        guard words.count >= 2 else { return false }
        let phase = words[0].lowercased()
        if ["request", "response"].contains(phase) { return words[1].lowercased() == "if" }
        // A scheduled or menu script has no condition to test, so the word that
        // follows the phase is `then` rather than `if`: Loon writes
        // `cron ${TaskCron} then script(…)` and `generic then script(…)`. They
        // are rules of the same shape and have to reach the same reader — while
        // they were excluded here they fell through to the Surge reader, which
        // has no `script-path` to find on such a line and set every one of them
        // aside as `scriptWithoutAddress`.
        //
        // The `then script(` pair is required, not just the phase word: Surge
        // writes its scripts as `generic = type=generic, script-path=…`, and
        // that line has to keep reaching the Surge reader.
        guard ["cron", "generic", "network-changed"].contains(phase) else { return false }
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard let then = parts.firstIndex(where: { $0.lowercased() == "then" }),
              parts.count > then + 1 else { return false }
        return parts[then + 1].lowercased().hasPrefix("script(")
    }

     

    private static func isBlank(_ character: Character) -> Bool { character == " " || character == "\t" }
    private static func isWordStart(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character == "_")
    }
    private static func isWordCharacter(_ character: Character) -> Bool {
        // `-` is a word character because a phase word is spelled with one:
        // `network-changed then script(…)` is a rule of its own, and splitting
        // it made the line start with a word no phase matches.
        character.isASCII && (character.isLetter || character.isNumber || character == "_" || character == "."
                              || character == "-")
    }
    private static func isDigit(_ character: Character) -> Bool { character.isASCII && character.isNumber }

     
     
     
     
     
    static func tokens(_ line: String) -> [Token]? {
        let c = Array(line)
        var out: [Token] = []
        var i = 0
        while i < c.count {
            let ch = c[i]
            if isBlank(ch) {
                i += 1
                continue
            }
            if i > 0, isBlank(c[i - 1]), ch == "#" || ch == ";" || (ch == "/" && i + 1 < c.count && c[i + 1] == "/") { break }
            switch ch {
            case "\"":
                var j = i + 1
                var closed = false
                while j < c.count {
                    if c[j] == "\\" {
                        j += 2
                        continue
                    }
                    if c[j] == "\"" {
                        closed = true
                        break
                    }
                    j += 1
                }
                guard closed else { return nil }
                out.append(.string(String(c[(i + 1)..<j])))
                i = j + 1
            case "`":
                var text = ""
                var j = i + 1
                var closed = false
                while j < c.count {
                    if c[j] == "`" {
                        if j + 1 < c.count, c[j + 1] == "`" {
                            text.append("`")
                            j += 2
                            continue
                        }
                        closed = true
                        break
                    }
                    text.append(c[j])
                    j += 1
                }
                guard closed else { return nil }
                out.append(.raw(text))
                i = j + 1
            case "/":
                var j = i + 1
                var inClass = false
                var closed = false
                while j < c.count {
                    let x = c[j]
                    if x == "\\" {
                        j += 2
                        continue
                    }
                    if inClass {
                        if x == "]" { inClass = false }
                    } else if x == "[" {
                        inClass = true
                    } else if x == "/" {
                        closed = true
                        break
                    }
                    j += 1
                }
                guard closed, j > i + 1 else { return nil }
                var k = j + 1
                var flags = ""
                while k < c.count, isWordCharacter(c[k]) {
                    guard "ims".contains(c[k]) else { return nil }
                    flags.append(c[k])
                    k += 1
                }
                out.append(.regex(String(c[(i + 1)..<j]), flags: flags))
                i = k
            case "$" where i + 1 < c.count && c[i + 1] == "{":
                guard let end = referenceEnd(c, from: i + 2), end > i + 2 else { return nil }
                out.append(.reference(String(c[(i + 2)..<end])))
                i = end + 1
            default:
                if isDigit(ch) || (ch == "-" && i + 1 < c.count && isDigit(c[i + 1])) {
                    var j = i + 1
                    while j < c.count, isDigit(c[j]) || c[j] == "." || c[j] == "e" || c[j] == "E"
                            || ((c[j] == "+" || c[j] == "-") && (c[j - 1] == "e" || c[j - 1] == "E")) {
                        j += 1
                    }
                    guard let value = Double(String(c[i..<j])), value.isFinite else { return nil }
                    if j < c.count, isWordCharacter(c[j]) { return nil }
                    out.append(.number(value))
                    i = j
                } else if isWordStart(ch) {
                    var j = i + 1
                    while j < c.count, isWordCharacter(c[j]) { j += 1 }
                    let word = String(c[i..<j])
                    switch word {
                    case "true": out.append(.bool(true))
                    case "false": out.append(.bool(false))
                    default: out.append(.word(word))
                    }
                    i = j
                } else {
                    let two = i + 1 < c.count ? String(c[i...(i + 1)]) : ""
                    if ["~=", "==", "&&", "||", "!=", "!~"].contains(two) {
                        out.append(.symbol(two))
                        i += 2
                    } else if "|()[]{},!=<>".contains(ch) {
                        out.append(.symbol(String(ch)))
                        i += 1
                    } else {
                        return nil
                    }
                }
            }
        }
        return out
    }

     
     
     
     
     
    static func strippingComment(_ line: String) -> String {
        let c = Array(line)
        let whole = line.trimmingCharacters(in: .whitespaces)
        var i = 0
        while i < c.count {
            let ch = c[i]
            if isBlank(ch) {
                i += 1
                continue
            }
            if i > 0, isBlank(c[i - 1]), ch == "#" || ch == ";" || (ch == "/" && i + 1 < c.count && c[i + 1] == "/") {
                return String(c[..<i]).trimmingCharacters(in: .whitespaces)
            }
            var j = i + 1
            switch ch {
            case "\"":
                while j < c.count, c[j] != "\"" { j += c[j] == "\\" ? 2 : 1 }
            case "`":
                while j < c.count, c[j] != "`" || (j + 1 < c.count && c[j + 1] == "`") { j += c[j] == "`" ? 2 : 1 }
            case "/":
                var inClass = false
                while j < c.count {
                    if c[j] == "\\" {
                        j += 2
                        continue
                    }
                    if inClass {
                        if c[j] == "]" { inClass = false }
                    } else if c[j] == "[" {
                        inClass = true
                    } else if c[j] == "/" {
                        break
                    }
                    j += 1
                }
            case "$" where j < c.count && c[j] == "{":
                guard let end = referenceEnd(c, from: j + 1) else { return whole }
                j = end
            default:
                i += 1
                continue
            }
            guard j < c.count else { return whole }
            i = j + 1
        }
        return whole
    }

     
     
    private static func referenceEnd(_ c: [Character], from start: Int) -> Int? {
        var quote: Character?
        var j = start
        while j < c.count {
            let x = c[j]
            if let open = quote {
                if x == open { quote = nil }
            } else if x == "'" || x == "\"" {
                quote = x
            } else if x == "}" {
                return j
            }
            j += 1
        }
        return nil
    }

     

     
     
     
     
    enum SettingType: Equatable, Sendable {
        case text
        case number
        case boolean
    }

     
     
     
    static func declaredType(ofArgument line: String) -> SettingType {
        guard let equals = line.firstIndex(of: "=") else { return .text }
        var parts: [String] = []
        var current = ""
        var quoted = false
        for character in line[line.index(after: equals)...] {
            if character == "\"" { quoted.toggle() }
            if character == ",", !quoted {
                parts.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        parts.append(current)
        let trimmed = parts.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        if trimmed.first == "switch" { return .boolean }
        let declared = trimmed.dropFirst().first { $0.hasPrefix("type") && $0.dropFirst(4).trimmingCharacters(in: .whitespaces).hasPrefix("=") }
        if let declared, declared.split(separator: "=", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) == "number" { return .number }
        return .text
    }

     
     
     
     
     
    static func rule(_ line: String, origin: AdBlockLineOrigin, arguments: [String: String?],
                     types: [String: SettingType] = [:]) -> Result<AdBlockRewriteRule, AdBlockIgnoredReason> {
        reading(line, origin: origin, arguments: arguments, types: types).map(\.rule)
    }

     
     
     
     
     
     
    static func reading(_ line: String, origin: AdBlockLineOrigin, arguments: [String: String?], types: [String: SettingType] = [:],
                        moduleURL: String? = nil) -> Result<(rule: AdBlockRewriteRule, files: [AdBlockAnswerFileReference]), AdBlockIgnoredReason> {
        guard line.utf8.count <= maximumLineBytes else { return .failure(.lineTooLong(maximumLineBytes)) }
        guard isPrintable(line), let tokens = tokens(line) else { return .failure(.unreadableLine) }
        do {
            var reader = Reader(tokens: tokens, arguments: arguments, types: types, moduleURL: moduleURL)
            let rule = try reader.rule(origin: origin)
            return .success((rule: rule, files: reader.files))
        } catch let reason as AdBlockIgnoredReason {
            return .failure(reason)
        } catch {
            return .failure(.unreadableLine)
        }
    }

     
     
     
     
     
     
     
     
     
     
    static func scriptRule(_ line: String, origin: AdBlockLineOrigin, arguments: [String: String?],
                           types: [String: SettingType] = [:], moduleURL: String? = nil) -> Result<AdBlockScript, AdBlockIgnoredReason> {
        guard line.utf8.count <= maximumLineBytes else { return .failure(.lineTooLong(maximumLineBytes)) }
        guard isPrintable(line), let tokens = tokens(line) else { return .failure(.unreadableLine) }
        do {
            var reader = Reader(tokens: tokens, arguments: arguments, types: types, moduleURL: moduleURL)
            return .success(try reader.script(origin: origin))
        } catch let reason as AdBlockIgnoredReason {
            return .failure(reason)
        } catch {
            return .failure(.unreadableLine)
        }
    }

     
     
    static func unescapingSlashes(_ pattern: String) -> String {
        let c = Array(pattern)
        var out = ""
        var i = 0
        while i < c.count {
            if c[i] == "\\", i + 1 < c.count {
                if c[i + 1] != "/" { out.append(c[i]) }
                out.append(c[i + 1])
                i += 2
                continue
            }
            out.append(c[i])
            i += 1
        }
        return out
    }

     
     
     
     
     
    static func ignoringCase(_ pattern: String) -> String {
        pattern.hasPrefix("(?i)") ? pattern : "(?i)" + pattern
    }

     
     
     
     
     
     
    static func gatePattern(of condition: AdBlockCondition) -> String {
        let atoms: [AdBlockCondition]
        switch condition {
        case .match: atoms = [condition]
        case .all(let conditions): atoms = conditions
        case .any: atoms = []
        }
        for atom in atoms {
            if case .match(.url, .regexSearch, .regex(let pattern), _) = atom { return pattern }
        }
        for atom in atoms {
            if case .match(.url, .equals, .string(let whole), _) = atom {
                return "^" + NSRegularExpression.escapedPattern(for: whole) + "$"
            }
        }
        return ""
    }

     
    private static func isPrintable(_ line: String) -> Bool {
        line.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x09: return true
            case 0x00...0x1F, 0x7F...0x9F, 0x2028, 0x2029, 0xFEFF: return false
            default: return true
            }
        }
    }

     

    fileprivate indirect enum Expression {
        case and([Expression])
        case or([Expression])
        case compare(Operand, AdBlockConditionOperator, Operand, capture: String?)
    }

    fileprivate enum Operand {
        case reference(String)
        case string(String)
        case raw(String)
        case regex(String, flags: String)
        case number(Double)
        case bool(Bool)
        case null
    }

    fileprivate enum Argument {
        case one(Operand)
        case many([Operand])
    }

    fileprivate struct Call {
        let name: String
        let arguments: [Argument]
         
         
        var bare = false
    }

     
    fileprivate enum Typed: Equatable {
        case text(String)
        case number(Double)
        case boolean(Bool)
    }

     
    fileprivate enum Reference {
        case variable(AdBlockConditionVariable)
        case capture(name: String, index: Int)
        case setting(String)
    }

     
    fileprivate struct Capture {
        let groups: Int
         
         
        let onEveryPath: Bool
        let regex: String
    }

     
     
    fileprivate enum Piece {
        case text(String, written: Bool)
        case capture(name: String, index: Int, written: String)
        case variable(String)
    }

    fileprivate struct Reader {
        let tokens: [Token]
        let arguments: [String: String?]
        let types: [String: SettingType]
        var index = 0
        var depth = 0
        var phase: AdBlockRewritePhase = .request
        var captures: [String: Capture] = [:]
         
        var gateCapture: String?
        var deferred: AdBlockIgnoredReason?
         
        let moduleURL: String?
        var origin = AdBlockLineOrigin(section: "", line: 0)
         
         
        var files: [AdBlockAnswerFileReference] = []
        var namesABody = false

        init(tokens: [Token], arguments: [String: String?], types: [String: SettingType], moduleURL: String?) {
            self.tokens = tokens
            self.arguments = arguments
            self.types = types
            self.moduleURL = moduleURL
        }

        private func peek(_ offset: Int = 0) -> Token? {
            index + offset < tokens.count ? tokens[index + offset] : nil
        }

        private mutating func next() -> Token? {
            defer { index += 1 }
            return peek()
        }

        private mutating func expect(_ symbol: String) throws {
            guard next() == .symbol(symbol) else { throw AdBlockIgnoredReason.unreadableLine }
        }

        private mutating func defer_(_ reason: AdBlockIgnoredReason) {
            if deferred == nil { deferred = reason }
        }

         

        mutating func rule(origin: AdBlockLineOrigin) throws -> AdBlockRewriteRule {
            self.origin = origin
            guard case .word(let phaseWord)? = next(), case .word(let ifWord)? = next(), ifWord.lowercased() == "if" else {
                throw AdBlockIgnoredReason.unreadableLine
            }
            switch phaseWord.lowercased() {
            case "request": phase = .request
            case "response": phase = .response
            case "cron": phase = .cron
            case "generic": phase = .generic
            default: throw AdBlockIgnoredReason.unreadableLine
            }
            let expression = try or()
            // Loon's v2 rules read `then script(...)`, but the same line shape
            // with `then script(...)` is what a cron or generic rule also uses;
            // the phase is the only difference.
            guard case .word(let thenWord)? = next(), thenWord.lowercased() == "then" else { throw AdBlockIgnoredReason.unreadableLine }
            var calls: [Call] = [try call()]
            while index < tokens.count {
                try expect("|")
                calls.append(try call())
            }
             
            try collectCaptures(expression, onEveryPath: true)
            let condition = Self.root(try lower(expression))
            if case .match(.url, .regexSearch, .regex(let gate), let capture) = Self.gateAtom(condition) {
                gateCapture = capture.flatMap { captures[$0]?.regex == gate ? $0 : nil }
            }
            let actions = try self.actions(calls, expression: expression)
            if let deferred { throw deferred }
            return AdBlockRewriteRule(pattern: AdBlockLoonRewriteSyntax.gatePattern(of: condition), phase: phase, condition: condition, actions: actions,
                                      origin: origin)
        }

         

        private mutating func or() throws -> Expression {
            var parts = [try and()]
            while peek() == .symbol("||") {
                index += 1
                parts.append(try and())
            }
            return parts.count == 1 ? parts[0] : .or(parts)
        }

        private mutating func and() throws -> Expression {
            var parts = [try atom()]
            while peek() == .symbol("&&") {
                index += 1
                parts.append(try atom())
            }
            return parts.count == 1 ? parts[0] : .and(parts)
        }

        private mutating func atom() throws -> Expression {
            if peek() == .symbol("(") {
                index += 1
                depth += 1
                guard depth <= AdBlockLoonRewriteSyntax.maximumDepth else { throw AdBlockIgnoredReason.unreadableLine }
                let inner = try or()
                try expect(")")
                depth -= 1
                return inner
            }
            let left = try operand()
            let op: AdBlockConditionOperator
            switch next() {
            case .symbol("~=")?: op = .regexSearch
            case .symbol("==")?: op = .equals
             
            default: throw AdBlockIgnoredReason.unreadableLine
            }
            let right = try operand()
            var capture: String?
            if peek() == .word("as") {
                index += 1
                guard op == .regexSearch, case .word(let name)? = next(), !name.contains(".") else {
                    throw AdBlockIgnoredReason.unreadableLine
                }
                capture = name
            }
            return .compare(left, op, right, capture: capture)
        }

        private mutating func operand() throws -> Operand {
            switch next() {
            case .reference(let text)?: return .reference(text)
            case .string(let text)?: return .string(text)
            case .raw(let text)?: return .raw(text)
            case .regex(let body, let flags)?: return .regex(body, flags: flags)
            case .number(let value)?: return .number(value)
            case .bool(let value)?: return .bool(value)
            case .word("null")?: return .null
            default: throw AdBlockIgnoredReason.unreadableLine
            }
        }

         

        private mutating func call() throws -> Call {
            guard case .word(let name)? = next() else { throw AdBlockIgnoredReason.unreadableLine }
             
             
            if name == "reject", peek() == nil || peek() == .symbol("|") {
                return Call(name: name, arguments: [], bare: true)
            }
            try expect("(")
            var arguments: [Argument] = []
            if peek() == .symbol(")") {
                index += 1
                return Call(name: name, arguments: arguments)
            }
            while true {
                if peek() == .symbol("[") {
                    index += 1
                    var values: [Operand] = []
                    if peek() != .symbol("]") {
                        values.append(try operand())
                        while peek() == .symbol(",") {
                            index += 1
                            values.append(try operand())
                        }
                    }
                    try expect("]")
                    arguments.append(.many(values))
                } else {
                     
                    arguments.append(.one(try operand()))
                }
                switch next() {
                case .symbol(",")?: continue
                case .symbol(")")?: return Call(name: name, arguments: arguments)
                default: throw AdBlockIgnoredReason.unreadableLine
                }
            }
        }

         

        private mutating func collectCaptures(_ expression: Expression, onEveryPath: Bool) throws {
            switch expression {
            case .and(let parts):
                for part in parts { try collectCaptures(part, onEveryPath: onEveryPath) }
            case .or(let parts):
                for part in parts { try collectCaptures(part, onEveryPath: false) }
            case .compare(_, _, let right, let capture?):
                 
                guard captures[capture] == nil, arguments[capture] == nil else { throw AdBlockIgnoredReason.unreadableLine }
                let regex = try conditionRegex(right)
                guard let compiled = try? NSRegularExpression(pattern: regex) else { throw AdBlockIgnoredReason.invalidPattern }
                captures[capture] = Capture(groups: compiled.numberOfCaptureGroups, onEveryPath: onEveryPath, regex: regex)
            case .compare:
                break
            }
        }

         
        private func reference(_ text: String) throws -> Reference {
            switch text {
            case "url": return .variable(.url)
            case "request.method": return .variable(.requestMethod)
            case "response.status": return .variable(.responseStatus)
            default: break
            }
            for (prefix, request) in [("request.header[", true), ("response.header[", false)] where text.hasPrefix(prefix) {
                let rest = Array(text.dropFirst(prefix.count))
                guard rest.count >= 4, let quote = rest.first, quote == "'" || quote == "\"", rest[rest.count - 2] == quote,
                      rest[rest.count - 1] == "]" else { throw AdBlockIgnoredReason.unreadableLine }
                let name = String(rest[1..<(rest.count - 2)])
                guard !name.isEmpty, !name.contains(quote), AdBlockLoonRewriteSyntax.isHeaderName(name) else {
                    throw AdBlockIgnoredReason.unreadableLine
                }
                return .variable(request ? .requestHeader(name) : .responseHeader(name))
            }
             
            if text.hasPrefix("request.") || text.hasPrefix("response.") { throw AdBlockIgnoredReason.unreadableLine }
            if arguments[text] != nil { return .setting(text) }
            if let dot = text.lastIndex(of: "."), let number = Int(text[text.index(after: dot)...]), number >= 0,
               text[text.index(after: dot)...].allSatisfy({ $0.isASCII && $0.isNumber }) {
                return .capture(name: String(text[..<dot]), index: number)
            }
             
            throw AdBlockIgnoredReason.unreadableLine
        }

         
        private func setting(_ name: String) throws -> String {
            guard let declared = arguments[name] else { throw AdBlockIgnoredReason.unreadableLine }
            guard let value = declared else { throw AdBlockIgnoredReason.missingArgument(name) }
            return value
        }

         
         
         
        private func typedSetting(_ name: String) throws -> Typed {
            let value = try setting(name)
            switch types[name] ?? .text {
            case .text: return .text(value)
            case .number:
                guard let number = Double(value.trimmingCharacters(in: .whitespaces)), number.isFinite else {
                    throw AdBlockIgnoredReason.unreadableLine
                }
                return .number(number)
            case .boolean:
                switch value.lowercased() {
                case "true": return .boolean(true)
                case "false": return .boolean(false)
                default: throw AdBlockIgnoredReason.unreadableLine
                }
            }
        }

         
        private func textSetting(_ name: String) throws -> String {
            guard case .text(let value) = try typedSetting(name) else { throw AdBlockIgnoredReason.unreadableLine }
            return value
        }

         
         
        private func checkCapture(_ name: String, _ index: Int) throws {
            guard let capture = captures[name], capture.onEveryPath, index <= capture.groups else {
                throw AdBlockIgnoredReason.unreadableLine
            }
        }

         
        private func checkVariable(_ variable: AdBlockConditionVariable) throws {
            switch variable {
            case .responseStatus, .responseHeader:
                guard phase == .response else { throw AdBlockIgnoredReason.unreadableLine }
            case .url, .requestMethod, .requestHeader:
                break
            }
        }

         

         
         
         
         
         
         
        private func pieces(_ operand: Operand) throws -> [Piece] {
            switch operand {
            case .raw(let text):
                return [.text(text, written: true)]
            case .reference(let text):
                if case .setting(let name) = try reference(text) { return [.text(try textSetting(name), written: false)] }
                return [try piece(reference: text)]
            case .string(let written):
                let c = Array(written)
                var out: [Piece] = []
                var text = ""
                func flush() {
                    if !text.isEmpty { out.append(.text(text, written: true)) }
                    text = ""
                }
                var i = 0
                while i < c.count {
                    let x = c[i]
                    if x == "\\", i + 1 < c.count {
                        let escaped = c[i + 1]
                        switch escaped {
                        case "\"": text.append("\"")
                        case "\\": text.append("\\")
                        case "n": text.append("\n")
                        case "r": text.append("\r")
                        case "t": text.append("\t")
                        case "$":
                             
                            flush()
                            out.append(.text("$", written: false))
                        default:
                            text.append(x)
                            text.append(escaped)
                        }
                        i += 2
                        continue
                    }
                    if x == "$", i + 1 < c.count, c[i + 1] == "{" {
                        guard let end = AdBlockLoonRewriteSyntax.referenceEnd(c, from: i + 2), end > i + 2 else {
                            throw AdBlockIgnoredReason.unreadableLine
                        }
                        flush()
                        out.append(try piece(reference: String(c[(i + 2)..<end])))
                        i = end + 1
                        continue
                    }
                    text.append(x)
                    i += 1
                }
                flush()
                return out
            default:
                throw AdBlockIgnoredReason.unreadableLine
            }
        }

        private func piece(reference text: String) throws -> Piece {
            switch try reference(text) {
            case .setting(let name):
                 
                _ = try typedSetting(name)
                return .text(try setting(name), written: false)
            case .capture(let name, let index):
                try checkCapture(name, index)
                return .capture(name: name, index: index, written: "${" + text + "}")
            case .variable(let variable):
                try checkVariable(variable)
                return .variable("${" + text + "}")
            }
        }

         
         
         
         
        private func refusePlaceholders(_ text: String) throws {
            let c = Array(text)
            var i = 0
            while i < c.count {
                if c[i] == "{", let end = c[(i + 1)...].firstIndex(where: { $0 == "}" || $0 == "{" }), c[end] == "}",
                   end > i + 1, arguments[String(c[(i + 1)..<end])] != nil {
                    throw AdBlockIgnoredReason.unreadableLine
                }
                i += 1
            }
        }

         
         
        private mutating func plainText(_ operand: Operand) throws -> String {
            var out = ""
            for piece in try pieces(operand) {
                switch piece {
                case .text(let text, let written):
                    if written { try refusePlaceholders(text) }
                    out += text
                case .capture(_, _, let written), .variable(let written):
                    defer_(.unsupportedRewriteType(written))
                }
            }
            return out
        }

         
         
         
         
        private mutating func template(_ operand: Operand, refusingWrittenDollars: Bool) throws -> String {
            var out = ""
            for piece in try pieces(operand) {
                switch piece {
                case .text(let text, let written):
                    if written { try refusePlaceholders(text) }
                    if written, refusingWrittenDollars, AdBlockLoonRewriteSyntax.holdsDollarNumber(text) {
                        defer_(.noEffectInItsOwnApp(.redirectAddressCannotUseDollarNumbers))
                    }
                    out += AdBlockLoonRewriteSyntax.escapedForTemplate(text)
                case .capture(let name, let index, let written):
                    if name == gateCapture { out += "$\(index)" } else { defer_(.unsupportedRewriteType(written)) }
                case .variable(let written):
                    defer_(.unsupportedRewriteType(written))
                }
            }
            return out
        }

         
         
        private mutating func replacement(_ operand: Operand) throws -> String {
            var out = ""
            for piece in try pieces(operand) {
                switch piece {
                case .text(let text, let written):
                    if written {
                        try refusePlaceholders(text)
                        let c = Array(text)
                        for (i, x) in c.enumerated() {
                            switch x {
                            case "\\": out += "\\\\"
                            case "$" where i + 1 < c.count && c[i + 1].isASCII && c[i + 1].isNumber: out.append(x)
                            case "$": out += "\\$"
                            default: out.append(x)
                            }
                        }
                    } else {
                        out += AdBlockLoonRewriteSyntax.escapedForTemplate(text)
                    }
                case .capture(_, _, let written), .variable(let written):
                     
                    defer_(.unsupportedRewriteType(written))
                }
            }
            return out
        }

         
        private func regex(_ operand: Operand) throws -> String {
            guard case .regex(let body, let flags) = operand else { throw AdBlockIgnoredReason.unreadableLine }
            let pattern = AdBlockLoonRewriteSyntax.icu(body, flags: flags)
            guard AdBlockLineSyntax.isValidPattern(pattern) else { throw AdBlockIgnoredReason.invalidPattern }
            return pattern
        }

         
         
        private func conditionRegex(_ operand: Operand) throws -> String {
            if case .reference(let text) = operand, case .setting(let name) = try reference(text) {
                let pattern = try textSetting(name)
                guard AdBlockLineSyntax.isValidPattern(pattern) else { throw AdBlockIgnoredReason.invalidPattern }
                return pattern
            }
            return try regex(operand)
        }

         
         
        private func status(_ operand: Operand) throws -> Int {
            let value: Double
            switch operand {
            case .number(let number): value = number
            case .reference(let text):
                guard case .setting(let name) = try reference(text), case .number(let number) = try typedSetting(name) else {
                    throw AdBlockIgnoredReason.unreadableLine
                }
                value = number
            default: throw AdBlockIgnoredReason.unreadableLine
            }
            guard value.isFinite, value.rounded() == value, (100...599).contains(value) else { throw AdBlockIgnoredReason.unreadableLine }
            return Int(value)
        }

        private func flag(_ operand: Operand) throws -> Bool {
            switch operand {
            case .bool(let value): return value
            case .reference(let text):
                guard case .setting(let name) = try reference(text), case .boolean(let value) = try typedSetting(name) else {
                    throw AdBlockIgnoredReason.unreadableLine
                }
                return value
            default: throw AdBlockIgnoredReason.unreadableLine
            }
        }

         
         
         
         
         
         
         
         
         
        private mutating func jsonValue(_ operand: Operand) throws -> String {
            switch operand {
            case .number(let value): return AdBlockLoonRewriteSyntax.jsonNumber(value)
            case .bool(let value): return value ? "true" : "false"
            case .null: return "null"
            case .reference(let text):
                if case .setting(let name) = try reference(text) {
                    switch try typedSetting(name) {
                    case .number(let value): return AdBlockLoonRewriteSyntax.jsonNumber(value)
                    case .boolean(let value): return value ? "true" : "false"
                    case .text(let value): return AdBlockJSONRewriteSyntax.string(value)
                    }
                }
                return AdBlockJSONRewriteSyntax.string(try plainText(operand))
            case .string, .raw:
                let asWritten = try pieces(operand).allSatisfy { piece in
                    if case .text(_, written: true) = piece { return true } else { return false }
                }
                let text = try plainText(operand)
                return asWritten ? AdBlockJSONRewriteSyntax.value(ofString: text) : AdBlockJSONRewriteSyntax.string(text)
            case .regex: throw AdBlockIgnoredReason.unreadableLine
            }
        }

         

        fileprivate enum Lowered {
            case condition(AdBlockCondition)
            case constant(Bool)
        }

         
         
         
        private func lower(_ expression: Expression) throws -> Lowered {
            switch expression {
            case .and(let parts):
                 
                var out = Self.Distinct()
                for part in parts {
                    switch try lower(part) {
                    case .constant(true): continue
                    case .constant(false): out.add(.any([]))
                    case .condition(.all(let inner)): inner.forEach { out.add($0) }
                    case .condition(let condition): out.add(condition)
                    }
                }
                if out.items.isEmpty { return .constant(true) }
                return .condition(out.items.count == 1 ? out.items[0] : .all(out.items))
            case .or(let parts):
                var out = Self.Distinct()
                for part in parts {
                    switch try lower(part) {
                    case .constant(true): return .constant(true)
                    case .constant(false): continue
                    case .condition(.any(let inner)): inner.forEach { out.add($0) }
                    case .condition(let condition): out.add(condition)
                    }
                }
                if out.items.isEmpty { return .constant(false) }
                return .condition(out.items.count == 1 ? out.items[0] : .any(out.items))
            case .compare(let left, let op, let right, let capture):
                return try compare(left, op, right, capture: capture)
            }
        }

         
        private struct Distinct {
            var items: [AdBlockCondition] = []
            var seen: Set<AdBlockCondition> = []

            mutating func add(_ condition: AdBlockCondition) {
                if seen.insert(condition).inserted { items.append(condition) }
            }
        }

         
        private static func root(_ lowered: Lowered) -> AdBlockCondition {
            switch lowered {
            case .condition(let condition): return condition
            case .constant(let value): return value ? .all([]) : .any([])
            }
        }

        private static func gateAtom(_ condition: AdBlockCondition) -> AdBlockCondition? {
            let atoms: [AdBlockCondition]
            switch condition {
            case .match: atoms = [condition]
            case .all(let conditions): atoms = conditions
            case .any: atoms = []
            }
            return atoms.first { if case .match(.url, .regexSearch, .regex, _) = $0 { return true } else { return false } }
        }

        private func compare(_ left: Operand, _ op: AdBlockConditionOperator, _ right: Operand, capture: String?) throws -> Lowered {
             
            if op == .equals, case .reference(let text) = right, case .variable = try reference(text) {
                if case .reference(let other) = left, case .variable = try reference(other) { throw AdBlockIgnoredReason.unreadableLine }
                return try compare(right, op, left, capture: capture)
            }
            guard case .reference(let text) = left else { throw AdBlockIgnoredReason.unreadableLine }
            switch try reference(text) {
            case .capture: throw AdBlockIgnoredReason.unreadableLine
            case .variable(let variable):
                try checkVariable(variable)
                return .condition(.match(variable, op, try value(for: variable, op, right), capture: capture))
            case .setting(let name):
                guard capture == nil else { throw AdBlockIgnoredReason.unreadableLine }
                 
                 
                 
                if op == .regexSearch {
                    _ = try conditionRegex(right)
                    throw AdBlockIgnoredReason.unsupportedRewriteType("${" + text + "}")
                }
                return .constant(try decide(try typedSetting(name), right))
            }
        }

         
         
        private func value(for variable: AdBlockConditionVariable, _ op: AdBlockConditionOperator,
                           _ right: Operand) throws -> AdBlockConditionValue {
            if op == .regexSearch {
                guard variable != .responseStatus else { throw AdBlockIgnoredReason.unreadableLine }
                return .regex(try conditionRegex(right))
            }
            switch variable {
            case .responseStatus:
                switch right {
                case .number(let number): return .number(number)
                case .reference(let text):
                    guard case .setting(let name) = try reference(text), case .number(let number) = try typedSetting(name) else {
                        throw AdBlockIgnoredReason.unreadableLine
                    }
                    return .number(number)
                default: throw AdBlockIgnoredReason.unreadableLine
                }
            case .url, .requestMethod, .requestHeader, .responseHeader:
                switch right {
                case .null:
                    switch variable {
                    case .requestHeader, .responseHeader: return .null
                    default: throw AdBlockIgnoredReason.unreadableLine
                    }
                case .string, .raw, .reference:
                    return .string(try conditionText(right))
                default:
                    throw AdBlockIgnoredReason.unreadableLine
                }
            }
        }

         
         
        private func conditionText(_ operand: Operand) throws -> String {
            var out = ""
            for piece in try pieces(operand) {
                switch piece {
                case .text(let text, _): out += text
                case .capture(_, _, let written), .variable(let written):
                    throw AdBlockIgnoredReason.unsupportedRewriteType(written)
                }
            }
            return out
        }

         
         
         
         
        private func decide(_ value: Typed, _ right: Operand) throws -> Bool {
            switch (value, right) {
            case (.boolean(let have), .bool(let flag)): return have == flag
            case (.number(let have), .number(let number)): return have == number
            case (.text(let have), .string), (.text(let have), .raw): return have == (try conditionText(right))
            case (_, .reference(let text)):
                guard case .setting(let name) = try reference(text) else { throw AdBlockIgnoredReason.unreadableLine }
                let other = try typedSetting(name)
                switch (value, other) {
                case (.text, .text), (.number, .number), (.boolean, .boolean): return value == other
                default: throw AdBlockIgnoredReason.unreadableLine
                }
            default:
                throw AdBlockIgnoredReason.unreadableLine
            }
        }

         

         
         
        private static let requestActions: Set<String> = [
            "url.replace", "redirect", "reject", "reject_img", "reject_dict", "reject_array", "reject_video",
            "request.header.add", "request.header.set", "request.header.del", "request.header.replace",
            "request.body.replace", "request.json.add", "request.json.delete", "request.json.replace", "request.json.jq",
            "request.json.jq_file", "request.body.mock", "request.body.mock_file",
        ]
        private static let responseActions: Set<String> = [
            "response.header.add", "response.header.set", "response.header.del", "response.header.replace",
            "response.body.replace", "response.json.add", "response.json.delete", "response.json.replace", "response.json.jq",
            "response.json.jq_file", "response.body.mock", "response.body.mock_file",
        ]
        private static let mocks: Set<String> = ["response.body.mock", "response.body.mock_file"]

        private mutating func actions(_ calls: [Call], expression: Expression) throws -> [AdBlockRewriteAction] {
             
            if calls.contains(where: { $0.name == "script" }) {
                guard calls.count == 1 else { throw AdBlockIgnoredReason.unreadableLine }
                defer_(.newerSyntaxNotSupported)
                return []
            }
            let allowed = phase == .request ? Self.requestActions : Self.responseActions
            guard calls.allSatisfy({ allowed.contains($0.name) }) else { throw AdBlockIgnoredReason.unreadableLine }
            if calls.contains(where: { $0.name == "url.replace" || $0.name == "redirect" }) {
                 
                guard try Self.requiredURLRegexes(expression, reader: self) == 1 else { throw AdBlockIgnoredReason.unreadableLine }
            }
            let mocks = calls.filter { Self.mocks.contains($0.name) }
            if !mocks.isEmpty {
                 
                 
                 
                guard mocks.count == 1, calls.allSatisfy({ Self.mocks.contains($0.name) || $0.name.hasPrefix("response.header.") }),
                      try !Self.namesResponse(expression, reader: self) else { throw AdBlockIgnoredReason.unreadableLine }
                return try mockAnswer(calls)
            }
            var out: [AdBlockRewriteAction] = []
            for call in calls { out += try action(call) }
            return out
        }

         
        private static func requiredURLRegexes(_ expression: Expression, reader: Reader) throws -> Int {
            switch expression {
            case .and(let parts): return try parts.reduce(0) { $0 + (try requiredURLRegexes($1, reader: reader)) }
            case .or: return 0
            case .compare(let left, .regexSearch, _, _):
                if case .reference(let text) = left, case .variable(.url) = try reader.reference(text) { return 1 }
                return 0
            case .compare: return 0
            }
        }

        private static func namesResponse(_ expression: Expression, reader: Reader) throws -> Bool {
            switch expression {
            case .and(let parts), .or(let parts): return try parts.contains { try namesResponse($0, reader: reader) }
            case .compare(let left, _, let right, _):
                for operand in [left, right] {
                    guard case .reference(let text) = operand else { continue }
                    switch try reader.reference(text) {
                    case .variable(.responseStatus), .variable(.responseHeader): return true
                    default: continue
                    }
                }
                return false
            }
        }

         
         
         
         
        private func rows(_ call: Call, arity: Int, batch: Bool) throws -> [[Operand]] {
            guard call.arguments.count == arity else { throw AdBlockIgnoredReason.unreadableLine }
            var singles: [Operand] = []
            var columns: [[Operand]] = []
            for argument in call.arguments {
                switch argument {
                case .one(let operand): singles.append(operand)
                case .many(let operands): columns.append(operands)
                }
            }
            if columns.isEmpty { return [singles] }
            guard batch, singles.isEmpty, let count = columns.first?.count, count > 0, columns.allSatisfy({ $0.count == count }) else {
                throw AdBlockIgnoredReason.unreadableLine
            }
            return (0..<count).map { row in columns.map { $0[row] } }
        }

         
        private func singles(_ call: Call, _ arities: ClosedRange<Int>) throws -> [Operand] {
            guard arities.contains(call.arguments.count) else { throw AdBlockIgnoredReason.unreadableLine }
            return try call.arguments.map { argument in
                guard case .one(let operand) = argument else { throw AdBlockIgnoredReason.unreadableLine }
                return operand
            }
        }

        private mutating func headerName(_ operand: Operand) throws -> String {
            let name = try plainText(operand)
            guard AdBlockLoonRewriteSyntax.isHeaderName(name) else { throw AdBlockIgnoredReason.unreadableLine }
            return name
        }

        private mutating func action(_ call: Call) throws -> [AdBlockRewriteAction] {
            let name = call.name
            let side: AdBlockRewritePhase = name.hasPrefix("response.") ? .response : .request
            func answer(_ status: Int, _ contentType: String?, _ body: AdBlockAnswerBody) -> AdBlockRewriteAction {
                .localAnswer(AdBlockLocalAnswer(status: status, headers: contentType.map { [AdBlockHeaderField(name: "Content-Type", value: $0)] } ?? [],
                                                body: body))
            }
            switch name {
            case "url.replace":
                let target = try template(try singles(call, 1...1)[0], refusingWrittenDollars: true)
                return [.transparent(target)]
            case "redirect":
                let given = try singles(call, 2...2)
                let code = try status(given[0])
                let target = try template(given[1], refusingWrittenDollars: true)
                switch code {
                case 302: return [.redirect302(target)]
                case 307: return [.redirect307(target)]
                default: throw AdBlockIgnoredReason.unreadableLine
                }
            case "reject" where call.bare:
                 
                 
                 
                return [.rejectDrop]
            case "reject":
                let given = try singles(call, 1...2)
                let code = try status(given[0])
                let body = given.count == 2 ? try plainText(given[1]) : ""
                if body.isEmpty {
                     
                    return [code == 404 ? .reject : code == 200 ? .reject200 : answer(code, nil, .empty)]
                }
                 
                return [answer(code, "text/plain", .text(body))]
            case "reject_img":
                let code = try status(try singles(call, 1...1)[0])
                return [code == 200 ? .rejectImg : answer(code, "image/gif", .tinyGIF)]
            case "reject_dict":
                let code = try status(try singles(call, 1...1)[0])
                return [code == 200 ? .rejectDict : answer(code, "application/json", .emptyJSONObject)]
            case "reject_array":
                let code = try status(try singles(call, 1...1)[0])
                return [code == 200 ? .rejectArray : answer(code, "application/json", .emptyJSONArray)]
            case "reject_video":
                let code = try status(try singles(call, 1...1)[0])
                return [answer(code, "video/mp4", .emptyVideo)]
            case "request.header.add", "request.header.set", "response.header.add", "response.header.set":
                let operation: AdBlockHeaderOperation = name.hasSuffix(".add") ? .add : .set
                return try rows(call, arity: 2, batch: true).map { row -> AdBlockRewriteAction in
                    let value = try template(row[1], refusingWrittenDollars: false)
                    guard AdBlockYAMLText.isOneLine(value) else { throw AdBlockIgnoredReason.unreadableLine }
                    return .header(phase: side, operation: operation, name: try headerName(row[0]), arguments: [value])
                }
            case "request.header.del", "response.header.del":
                return try rows(call, arity: 1, batch: true).map { row -> AdBlockRewriteAction in
                    .header(phase: side, operation: .delete, name: try headerName(row[0]), arguments: [])
                }
            case "request.header.replace", "response.header.replace":
                return try rows(call, arity: 3, batch: true).map { row -> AdBlockRewriteAction in
                    let replacement = try self.replacement(row[2])
                    guard AdBlockYAMLText.isOneLine(replacement) else { throw AdBlockIgnoredReason.unreadableLine }
                    return .header(phase: side, operation: .replaceRegex, name: try headerName(row[0]),
                                   arguments: [try regex(row[1]), replacement])
                }
            case "request.body.replace", "response.body.replace":
                let pairs = try rows(call, arity: 2, batch: true).map { row -> AdBlockReplacementPair in
                    AdBlockReplacementPair(search: try regex(row[0]), replacement: try replacement(row[1]))
                }
                return [.bodyReplace(phase: side, pairs: pairs)]
             
             
            case "request.json.add", "request.json.replace", "response.json.add", "response.json.replace":
                let given = try rows(call, arity: 2, batch: true)
                let paths = try given.map { try plainText($0[0]) }
                let values = try given.map { try jsonValue($0[1]) }
                return [.json(phase: side, operations: try AdBlockJSONRewriteSyntax.operations(name.hasSuffix(".add") ? .add : .replace,
                                                                                             paths: paths, values: values).get())]
            case "request.json.delete", "response.json.delete":
                let paths = try rows(call, arity: 1, batch: true).map { try plainText($0[0]) }
                return [.json(phase: side, operations: try AdBlockJSONRewriteSyntax.operations(.delete, paths: paths, values: nil).get())]
            case "request.json.jq", "response.json.jq":
                let written = try plainText(try singles(call, 1...1)[0])
                switch AdBlockJSONRewriteSyntax.jqSource(written) {
                case .expression(let expression):
                    return [.bodyJQ(phase: side, expression: try AdBlockJSONRewriteSyntax.jq(expression).get())]
                case .file(let name):
                     
                    try addJQFile(name)
                    return [.bodyJQ(phase: side, expression: "")]
                }
            case "request.json.jq_file", "response.json.jq_file":
                 
                try addJQFile(try plainText(try singles(call, 1...1)[0]))
                return [.bodyJQ(phase: side, expression: "")]
            case "request.body.mock_file":
                 
                let given = try singles(call, 2...3)
                let contentType = try mockType(given[0])
                try addFile(given[1], base64: given.count == 3 ? try flag(given[2]) : false)
                return [.requestBody(AdBlockLocalAnswerSyntax.pendingFile, contentType: contentType)]
            case "request.body.mock":
                let given = try singles(call, 2...3)
                let made = try mock(given[0], given[1], status: nil, base64: given.count == 3 ? try flag(given[2]) : false)
                return [.requestBody(made.body, contentType: made.headers.first?.value)]
            default:
                throw AdBlockIgnoredReason.unreadableLine
            }
        }

        private mutating func mockType(_ operand: Operand) throws -> String {
            guard let contentType = AdBlockLoonRewriteSyntax.mockContentTypes[try plainText(operand)] else {
                throw AdBlockIgnoredReason.unreadableLine
            }
            return contentType
        }

         
         
        private mutating func mock(_ type: Operand, _ body: Operand, status: Int?, base64: Bool) throws -> AdBlockLocalAnswer {
            switch AdBlockLocalAnswerSyntax.loonMock(type: try plainText(type), body: try plainText(body), status: status, base64: base64) {
            case .success(let answer): return answer
            case .failure(let reason): throw reason
            }
        }

         
         
        private mutating func addFile(_ operand: Operand, base64: Bool) throws {
            guard !namesABody else { throw AdBlockIgnoredReason.unreadableLine }
            namesABody = true
            switch AdBlockLocalAnswerSyntax.fileAddress(try plainText(operand), moduleURL: moduleURL, resolvesAgainstTheModule: true) {
            case .success(let address):
                files.append(AdBlockAnswerFileReference(url: address, sha256: nil, origin: origin, base64: base64 ? true : nil))
            case .failure(let reason):
                throw reason
            }
        }

         
         
         
         
        private static let typesWithNoEffect: Set<String> = ["base64", "file"]

         
         
         
         
        private mutating func mockAnswer(_ calls: [Call]) throws -> [AdBlockRewriteAction] {
            var answer = AdBlockLocalAnswer(status: 200, headers: [], body: .empty)
            for call in calls where Self.mocks.contains(call.name) {
                let given = try singles(call, 2...4)
                if call.name == "response.body.mock", Self.typesWithNoEffect.contains(try plainText(given[0])) {
                    defer_(.noEffectInItsOwnApp(.noEffect))
                    return [.localAnswer(answer)]
                }
                let code = given.count >= 3 ? try status(given[2]) : 200
                let base64 = given.count == 4 ? try flag(given[3]) : false
                if call.name == "response.body.mock_file" {
                     
                    let contentType = try mockType(given[0])
                    try addFile(given[1], base64: base64)
                    answer = AdBlockLocalAnswer(status: code, headers: [AdBlockHeaderField(name: "Content-Type", value: contentType)],
                                                body: AdBlockLocalAnswerSyntax.pendingFile)
                } else {
                    answer = try mock(given[0], given[1], status: code, base64: base64)
                }
            }
            func framing(_ name: String) -> Bool { ["content-length", "transfer-encoding"].contains(name.lowercased()) }
            func same(_ field: AdBlockHeaderField, _ name: String) -> Bool { field.name.caseInsensitiveCompare(name) == .orderedSame }
             
             
             
            var after: [AdBlockRewriteAction] = []
            for call in calls where !Self.mocks.contains(call.name) {
                if !after.isEmpty || call.name == "response.header.replace" {
                    after += try action(call)
                    continue
                }
                switch call.name {
                case "response.header.add", "response.header.set":
                    for row in try rows(call, arity: 2, batch: true) {
                        let name = try headerName(row[0])
                        let value = try plainText(row[1])
                        guard AdBlockYAMLText.isOneLine(value) else { throw AdBlockIgnoredReason.unreadableLine }
                        guard !framing(name) else { continue }
                        if call.name.hasSuffix(".set"), let first = answer.headers.firstIndex(where: { same($0, name) }) {
                            answer.headers[first].value = value
                            answer.headers = answer.headers.enumerated().filter { $0.offset <= first || !same($0.element, name) }.map(\.element)
                        } else {
                            answer.headers.append(AdBlockHeaderField(name: name, value: value))
                        }
                    }
                case "response.header.del":
                    for row in try rows(call, arity: 1, batch: true) {
                        let name = try headerName(row[0])
                        answer.headers.removeAll { same($0, name) }
                    }
                default:
                    throw AdBlockIgnoredReason.unreadableLine
                }
            }
            return [.localAnswer(answer)] + after
        }

         
         
         
        private mutating func addJQFile(_ written: String) throws {
            switch AdBlockLocalAnswerSyntax.fileAddress(written, moduleURL: moduleURL, resolvesAgainstTheModule: true) {
            case .success(let address): files.append(AdBlockAnswerFileReference(url: address, sha256: nil, origin: origin))
            case .failure(let reason): throw reason
            }
        }
    }

     

     
    static func isHeaderName(_ name: String) -> Bool {
        !name.isEmpty && name.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || "!#$%&'*+-.^_`|~".unicodeScalars.contains(scalar))
        }
    }

     
    static func icu(_ body: String, flags: String) -> String {
        ["i", "m", "s"].filter { flags.contains($0) }.map { "(?\($0))" }.joined() + body
    }

     
    static func holdsDollarNumber(_ text: String) -> Bool {
        let c = Array(text)
        return c.indices.contains { c[$0] == "$" && $0 + 1 < c.count && c[$0 + 1].isASCII && c[$0 + 1].isNumber }
    }

     
    static func escapedForTemplate(_ text: String) -> String {
        var out = ""
        for character in text {
            if character == "\\" || character == "$" { out.append("\\") }
            out.append(character)
        }
        return out
    }

    static func jsonNumber(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 1e15 { return String(Int64(value)) }
        return "\(value)"
    }
}

 

private extension AdBlockLoonRewriteSyntax.Reader {
    typealias Token = AdBlockLoonRewriteSyntax.Token

     
     
    static let scriptOptions: Set<String> = ["enable", "tag", "img_url", "timeout", "debug", "requires_body", "binary_body_mode"]

     
    mutating func script(origin: AdBlockLineOrigin) throws -> AdBlockScript {
        self.origin = origin
        guard case .word(let phaseWord)? = next() else { throw AdBlockIgnoredReason.unreadableLine }
        switch phaseWord.lowercased() {
        case "request": phase = .request
        case "response": phase = .response
        case "cron": phase = .cron
        // A network-changed script is a menu script the app may run when the
        // network changes; Loon's own docs give it the same shape as `generic`,
        // and the Surge reader already maps it the same way.
        case "generic", "network-changed": phase = .generic
        default: throw AdBlockIgnoredReason.unreadableLine
        }
        // `request if <condition> then script(…)` is the HTTP shape. A
        // scheduled script has no condition to test — Loon writes
        // `cron ${TaskCron} then script(…)`, with the schedule where the
        // condition would be — so the `if` is optional for those phases and
        // what follows is read as the schedule itself. `generic then script(…)`
        // carries neither a condition nor a schedule: `then` comes straight
        // after the phase word.
        enum Lead { case condition, schedule(AdBlockLoonRewriteSyntax.Operand), none }
        var scheduleOperand: AdBlockLoonRewriteSyntax.Operand?
        let lead: Lead
        if case .word(let ifWord)? = peek(), ifWord.lowercased() == "if" {
            _ = next()
            lead = .condition
        } else if phase == .cron || phase == .generic {
            if case .word(let word)? = peek(), word.lowercased() == "then" {
                lead = .none
            } else {
                lead = .schedule(try operand())
            }
        } else {
            throw AdBlockIgnoredReason.unreadableLine
        }
        let expression: AdBlockLoonRewriteSyntax.Expression
        switch lead {
        case .condition: expression = try or()
        case .none: expression = .and([])
        case .schedule(let operand): scheduleOperand = operand; expression = .and([])
        }
        guard case .word(let thenWord)? = next(), thenWord.lowercased() == "then", next() == .word("script") else {
            throw AdBlockIgnoredReason.unreadableLine
        }
         
        guard !Self.captures(expression) else { throw AdBlockIgnoredReason.unreadableLine }
         
         
         
        if phase == .response, try !Self.guarded(expression, reader: self) {
            throw AdBlockIgnoredReason.unreadableLine
        }
        try expect("(")
        let path = try fixedText(try operand())
        guard !path.isEmpty else { throw AdBlockIgnoredReason.unreadableLine }
        var argument: String?
        var argumentNames: [String]?
        if peek() == .symbol(",") {
            index += 1
            if peek() == .symbol("{") {
                argumentNames = try objectArgument()
            } else {
                argument = try argumentText(try operand())
            }
        }
        try expect(")")
        var options: [String: Token] = [:]
        if peek() == .word("with") {
            index += 1
            while true {
                guard case .word(let name)? = next(), Self.scriptOptions.contains(name), options[name] == nil else {
                    throw AdBlockIgnoredReason.unreadableLine
                }
                try expect("=")
                guard let value = next() else { throw AdBlockIgnoredReason.unreadableLine }
                options[name] = value
                guard peek() == .symbol(",") else { break }
                index += 1
            }
        }
         
        guard index == tokens.count else { throw AdBlockIgnoredReason.unreadableLine }

        // A cron or generic rule has no URL gate: it runs on a schedule or from
        // the app's own menu. An empty gate is what a phase-only script reads.
        let condition = Self.root(try lower(expression))
        let gate = phase == .cron || phase == .generic ? "" : Self.scriptGate(of: condition)
         
         
        // A cron rule's expression is its schedule, and the schedule is what
        // the scheduler needs; a generic rule's expression is its trigger. The
        // pattern an HTTP rule carries is not meaningful for either.
        // A schedule written without an `if` may be a `${Argument}` whose value
        // is the crontab line, so it goes through the reader's own substitution
        // rather than being taken literally.
        var schedule: String?
        if phase == .cron {
            if let scheduleOperand {
                // A schedule is fixed text: a placeholder that has a declared
                // value is substituted, and one that does not is the reader's
                // `.missingArgument`.
                schedule = try fixedText(scheduleOperand)
            } else {
                schedule = Self.cronText(of: condition)
            }
        }
        let pattern = gate.isEmpty ? (schedule ?? "^") : AdBlockLoonRewriteSyntax.unescapingSlashes(gate)
        // An HTTP rule's pattern has to be a URL; a schedule does not, so it is
        // not held to that check.
        if phase != .cron && phase != .generic {
            guard AdBlockLineSyntax.isValidPattern(pattern) else { throw AdBlockIgnoredReason.invalidPattern }
        }
        let requiresBody = try flag(options["requires_body"], settings: false, otherwise: false)
        let binaryBodyMode = try flag(options["binary_body_mode"], settings: false, otherwise: false)
        _ = try flag(options["debug"], settings: true, otherwise: false)
        let timeout = try seconds(options["timeout"])
        let tag = try options["tag"].map { try fixedText(Self.operand(of: $0)) }
        let imageURL = try options["img_url"].map { try fixedText(Self.operand(of: $0)) }
         
        guard try flag(options["enable"], settings: true, otherwise: true) else { throw AdBlockIgnoredReason.scriptTurnedOff }
         
         
         
        if Self.neverHolds(condition) { throw AdBlockIgnoredReason.scriptTurnedOff }

         
         
         
        let address: String
        switch AdBlockLocalAnswerSyntax.fileAddress(path, moduleURL: moduleURL, resolvesAgainstTheModule: true) {
        case .success(let resolved): address = resolved
        case .failure(let reason): throw reason
        }
         
        if address.lowercased().contains("boxjs") || pattern.lowercased().contains("boxjs") {
            throw AdBlockIgnoredReason.boxJSNotSupported
        }
        guard let url = URL(string: address), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else { throw AdBlockIgnoredReason.scriptWithoutAddress }
        guard address.utf8.count <= AdBlockModuleParser.maximumShownBytes else { throw AdBlockIgnoredReason.unreadableLine }
        guard scheme == "https" else { throw AdBlockIgnoredReason.scriptAddressNotSecure }

         
        let file = URL(string: path)?.lastPathComponent ?? ""
        let name = tag.flatMap { $0.isEmpty ? nil : $0 } ?? (!file.isEmpty && file != "/" ? file : pattern)
        var asked: AdBlockCondition? = condition
        switch condition {
        case .match(.url, .regexSearch, .regex(let only), nil) where only == gate: asked = nil
        case .all(let parts) where parts.isEmpty: asked = nil
        default: break
        }
        return AdBlockScript(name: name, phase: phase, pattern: pattern, scriptURL: address, requiresBody: requiresBody,
                             binaryBodyMode: binaryBodyMode, maxSize: nil, timeout: timeout, argument: argument,
                             updateInterval: AdBlockLineSyntax.defaultScriptUpdateInterval, bodySHA256: nil, origin: origin,
                             condition: asked, argumentNames: argumentNames, imageURL: imageURL.flatMap { $0.isEmpty ? nil : $0 },
                             cronFields: schedule.map { [$0] })
    }

    /// The text of a `cron "0 10 * * *"` condition. Loon writes the schedule as
    /// a string operand, so the expression is walked for the first string or
    /// raw operand, which is the schedule itself.
    static func cronText(of condition: AdBlockCondition) -> String? {
        func operandText(_ operand: AdBlockLoonRewriteSyntax.Operand) -> String? {
            switch operand {
            case .string(let text), .raw(let text): return text
            case .number(let value): return value == value.rounded() ? String(Int(value)) : String(value)
            default: return nil
            }
        }
        func walk(_ condition: AdBlockCondition) -> String? {
            switch condition {
            case .all(let parts), .any(let parts):
                for part in parts { if let found = walk(part) { return found } }
                return nil
            case .match(_, _, let value, _):
                switch value {
                case .string(let text), .regex(let text): return text
                case .number(let value): return value == value.rounded() ? String(Int(value)) : String(value)
                case .null: return nil
                }
            }
        }
        return walk(condition)
    }

    static func captures(_ expression: AdBlockLoonRewriteSyntax.Expression) -> Bool {
        switch expression {
        case .and(let parts), .or(let parts): return parts.contains(where: captures)
        case .compare(_, _, _, let capture): return capture != nil
        }
    }

    static func operand(of token: Token) throws -> AdBlockLoonRewriteSyntax.Operand {
        switch token {
        case .string(let text): return .string(text)
        case .raw(let text): return .raw(text)
        default: throw AdBlockIgnoredReason.unreadableLine
        }
    }

     
     
     
    func fixedText(_ operand: AdBlockLoonRewriteSyntax.Operand) throws -> String {
        switch operand {
        case .string, .raw: break
        default: throw AdBlockIgnoredReason.unreadableLine
        }
        var out = ""
        for piece in try pieces(operand) {
            guard case .text(let text, written: true) = piece else { throw AdBlockIgnoredReason.unreadableLine }
            out += text
        }
        return out
    }

     
     
     
    func argumentText(_ operand: AdBlockLoonRewriteSyntax.Operand) throws -> String {
        switch operand {
        case .string, .raw, .reference: break
        default: throw AdBlockIgnoredReason.unreadableLine
        }
        var out = ""
        for piece in try pieces(operand) {
            switch piece {
            case .text(let text, let written):
                if written { try refusePlaceholders(text) }
                out += text
            case .capture, .variable:
                throw AdBlockIgnoredReason.unreadableLine
            }
        }
        return out
    }

     
     
     
     
    mutating func objectArgument() throws -> [String] {
        try expect("{")
        var names: [String] = []
        while true {
            guard case .reference(let text)? = next(), case .setting(let name) = try reference(text), !names.contains(name) else {
                throw AdBlockIgnoredReason.unreadableLine
            }
            if case .some(.some) = arguments[name] { _ = try typedSetting(name) }
            names.append(name)
            guard peek() == .symbol(",") else { break }
            index += 1
        }
        try expect("}")
        return names
    }

     
     
    func flag(_ token: Token?, settings: Bool, otherwise: Bool) throws -> Bool {
        switch token {
        case nil: return otherwise
        case .bool(let value)?: return value
        case .reference(let text)? where settings:
            guard case .setting(let name) = try reference(text) else { throw AdBlockIgnoredReason.unreadableLine }
            guard case .some(.some) = arguments[name] else { return otherwise }
            guard case .boolean(let value) = try typedSetting(name) else { throw AdBlockIgnoredReason.unreadableLine }
            return value
        default: throw AdBlockIgnoredReason.unreadableLine
        }
    }

     
     
     
     
    func seconds(_ token: Token?) throws -> Int? {
        let value: Double
        switch token {
        case nil: return nil
        case .number(let number)?: value = number
        case .reference(let text)?:
            guard case .setting(let name) = try reference(text) else { throw AdBlockIgnoredReason.unreadableLine }
            guard case .some(.some) = arguments[name] else { return nil }
            switch try typedSetting(name) {
            case .number(let number): value = number
            case .text(let written):
                guard let number = Double(written) else { throw AdBlockIgnoredReason.unreadableLine }
                value = number
            case .boolean: throw AdBlockIgnoredReason.unreadableLine
            }
        default: throw AdBlockIgnoredReason.unreadableLine
        }
        guard value.isFinite, value > 0, value <= Double(Int32.max) else { throw AdBlockIgnoredReason.unreadableLine }
        return Int(value.rounded(.up))
    }

     
     
     
    static func guarded(_ expression: AdBlockLoonRewriteSyntax.Expression, reader: Self) throws -> Bool {
        func isURL(_ operand: AdBlockLoonRewriteSyntax.Operand) throws -> Bool {
            guard case .reference(let text) = operand, case .variable(.url) = try reader.reference(text) else { return false }
            return true
        }
        switch expression {
        case .and(let parts): return try parts.contains { try guarded($0, reader: reader) }
        case .or(let parts): return try parts.allSatisfy { try guarded($0, reader: reader) }
        case .compare(let left, .regexSearch, _, _): return try isURL(left)
        case .compare(let left, .equals, let right, _): return try isURL(left) || isURL(right)
        case .compare: return false
        }
    }

     
     
     
     
    static func scriptGate(of condition: AdBlockCondition) -> String {
        let gate = AdBlockLoonRewriteSyntax.gatePattern(of: condition)
        guard gate.isEmpty else { return gate }
        let parts: [AdBlockCondition]
        switch condition {
        case .all(let all): parts = all
        default: parts = [condition]
        }
        for part in parts {
            guard case .any(let options) = part, !options.isEmpty else { continue }
            let gates = options.map { scriptGate(of: $0) }
            if !gates.contains("") { return gates.map { "(?:" + $0 + ")" }.joined(separator: "|") }
        }
        return ""
    }

     
     
     
    static func neverHolds(_ condition: AdBlockCondition) -> Bool {
        switch condition {
        case .any(let options): return options.allSatisfy(neverHolds)
        case .all(let parts): return parts.contains(where: neverHolds)
        case .match: return false
        }
    }
}
