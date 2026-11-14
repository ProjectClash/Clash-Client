import Foundation

 
 
 
 
enum ModuleLineSyntax {
     
     
    static let defaultScriptUpdateInterval = 86_400

     
     
     
     
     
    static func scriptUpdateInterval(_ values: [String: String]) -> Int {
        number(values, "script-update-interval").flatMap { $0 >= 0 ? $0 : nil } ?? defaultScriptUpdateInterval
    }

     
     
     
     
     
    static let everyScanMinimumInterval = 3600

     
     
    static func scriptCheckInterval(_ interval: Int) -> TimeInterval {
        TimeInterval(interval > 0 ? interval : everyScanMinimumInterval)
    }

     

    private static func isBlank(_ character: Character) -> Bool { character == " " || character == "\t" }

    private enum QuotedRun {
        case notQuoted
        case unclosed
         
         
        case closed(String, next: Int)
    }

     
     
     
    private static func quotedRun(_ characters: [Character], at start: Int) -> QuotedRun {
        let open = characters[start]
        guard open == "\"" || open == "'" else { return .notQuoted }
        var text = ""
        var index = start + 1
        while index < characters.count {
            let character = characters[index]
            if character == "\\", index + 1 < characters.count, characters[index + 1] == open {
                text.append(open)
                index += 2
            } else if character == open {
                return .closed(text, next: index + 1)
            } else {
                text.append(character)
                index += 1
            }
        }
        return .unclosed
    }

     
     
     
     
     
     
    private static func nextToken(_ characters: [Character], at index: Int) -> (text: String, next: Int)? {
        switch quotedRun(characters, at: index) {
        case .unclosed:
            return nil
        case .closed(let text, let next) where next == characters.count || isBlank(characters[next]):
            return (text, next)
        case .closed, .notQuoted:
            var end = index
            while end < characters.count, !isBlank(characters[end]) { end += 1 }
            return (String(characters[index..<end]), end)
        }
    }

     
     
    static func tokens(_ line: String) -> [String]? {
        let characters = Array(line)
        var out: [String] = []
        var index = 0
        while index < characters.count {
            if isBlank(characters[index]) { index += 1; continue }
            guard let token = nextToken(characters, at: index) else { return nil }
            out.append(token.text)
            index = token.next
        }
        return out
    }

     
     
    static func splitHead(_ line: String, count: Int) -> (head: [String], rest: String)? {
        let characters = Array(line)
        var head: [String] = []
        var index = 0
        while head.count < count {
            while index < characters.count, isBlank(characters[index]) { index += 1 }
            guard index < characters.count, let token = nextToken(characters, at: index) else { return nil }
            head.append(token.text)
            index = token.next
        }
        return (head, String(characters[index...]).trimmingCharacters(in: .whitespaces))
    }

     
     
    static func isValidPattern(_ pattern: String) -> Bool {
        !pattern.isEmpty && (try? NSRegularExpression(pattern: pattern)) != nil
    }

     
     
    static func rejectAction(_ word: String) -> ModuleRewriteAction? {
        switch word.lowercased().replacingOccurrences(of: "_", with: "-") {
        case "reject": return .reject
        case "reject-200": return .reject200
        case "reject-img": return .rejectImg
        case "reject-tinygif": return .rejectTinyGif
        case "reject-dict": return .rejectDict
        case "reject-array": return .rejectArray
        case "reject-drop": return .rejectDrop
        case "reject-no-drop": return .rejectNoDrop
        default: return nil
        }
    }

     
     
     
     
     
    static func rewriteAnswer(_ word: String) -> ModuleRewriteAction? {
        if let reject = rejectAction(word) { return reject }
        guard word.lowercased().replacingOccurrences(of: "_", with: "-") == "reject-video" else { return nil }
        return .localAnswer(ModuleLocalAnswer(status: 200, headers: [ModuleHeaderField(name: "Content-Type", value: "video/mp4")],
                                               body: .emptyVideo))
    }

     

    private static func isAbsoluteWebAddress(_ text: String) -> Bool {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host?.isEmpty == false
    }

     
     
     
     
     
     
     
    static func urlRewrite(_ line: String, origin: ModuleLineOrigin) -> Result<ModuleRewriteRule, ModuleIgnoredReason> {
        guard ModuleYAMLText.isOneLine(line) else { return .failure(.unreadableLine) }
        if let words = tokens(line), words.count >= 3, words[1] == "url", !words[0].isEmpty {
            guard let reject = rewriteAnswer(words[2]) else { return .failure(.unsupportedRewriteType(words[2])) }
            guard words.count == 3 else { return .failure(.unreadableLine) }
            guard isValidPattern(words[0]) else { return .failure(.invalidPattern) }
            return .success(ModuleRewriteRule(pattern: words[0], action: reject, origin: origin))
        }
        guard let words = tokens(line), words.count == 2 || words.count == 3, !words[0].isEmpty else {
            return .failure(.unreadableLine)
        }
         
         
         
        if words.count == 3, ["302", "307", "header"].contains(words[1].lowercased()), isAbsoluteWebAddress(words[2]) {
            return loonRewrites(line, origin: origin).flatMap { rules in rules.first.map { .success($0) } ?? .failure(.unreadableLine) }
        }
        let action: ModuleRewriteAction
        if words.count == 2 {
            if let reject = rewriteAnswer(words[1]) {
                action = reject
            } else if isAbsoluteWebAddress(words[1]) {
                action = .transparent(words[1])
            } else {
                return .failure(.unsupportedRewriteType(words[1]))
            }
        } else if let reject = rewriteAnswer(words[2]) {
            action = reject
        } else {
            switch words[2].lowercased() {
            case "302": action = .redirect302(words[1])
            case "307": action = .redirect307(words[1])
            case "header", "transparent": action = .transparent(words[1])
            default: return .failure(.unsupportedRewriteType(words[2]))
            }
        }
        guard isValidPattern(words[0]) else { return .failure(.invalidPattern) }
        return .success(ModuleRewriteRule(pattern: words[0], action: action, origin: origin))
    }

     
     
     
    struct Reading: Equatable {
        var rules: [ModuleRewriteRule]
        var files: [ModuleAnswerFileReference] = []
    }

     
     
     
     
    static func loonRewriteReading(_ line: String, origin: ModuleLineOrigin, moduleURL: String?) -> Result<Reading, ModuleIgnoredReason> {
        if let json = loonBodyJSON(line, origin: origin, moduleURL: moduleURL) { return json }
        return loonRewrites(line, origin: origin).map { Reading(rules: $0) }
    }

     
     
     
     
     
    private static func loonBodyJSON(_ line: String, origin: ModuleLineOrigin, moduleURL: String?) -> Result<Reading, ModuleIgnoredReason>? {
        guard let words = tokens(line), words.count >= 2 else { return nil }
        let keyword = words[1].lowercased()
        let isJQ = keyword == "request-body-json-jq" || keyword == "response-body-json-jq"
        guard isJQ || (keyword.contains("-body-json-") && ModuleJSONRewriteSyntax.Verb.spelled(keyword) != nil) else { return nil }
        guard ModuleYAMLText.isOneLine(line), let split = splitHead(line, count: 2) else { return .failure(.unreadableLine) }
        return jsonBodyRewrite(pattern: split.head[0], keyword: split.head[1], rest: split.rest, origin: origin, moduleURL: moduleURL,
                               resolvesAgainstTheModule: true)
    }

     
    static func loonRewrite(_ line: String, origin: ModuleLineOrigin) -> Result<ModuleRewriteRule, ModuleIgnoredReason> {
        loonRewrites(line, origin: origin).flatMap { rules in rules.first.map { .success($0) } ?? .failure(.unreadableLine) }
    }

     
     
     
     
     
     
     
     
     
     
     
    static func loonRewrites(_ line: String, origin: ModuleLineOrigin) -> Result<[ModuleRewriteRule], ModuleIgnoredReason> {
        guard ModuleYAMLText.isOneLine(line) else { return .failure(.unreadableLine) }
         
         
        if let words = tokens(line), words.count == 3, !words[0].isEmpty {
            let action: ModuleRewriteAction?
            switch words[1].lowercased() {
            case "302": action = .redirect302(words[2])
            case "307": action = .redirect307(words[2])
            case "header", "transparent": action = .transparent(words[2])
            default: action = nil
            }
            if let action {
                guard isValidPattern(words[0]) else { return .failure(.invalidPattern) }
                return .success([ModuleRewriteRule(pattern: words[0], action: action, origin: origin)])
            }
        }
         
         
         
         
        if let words = tokens(line), words.count == 2, !words[0].isEmpty, words[1].lowercased() == "reject" {
            guard isValidPattern(words[0]) else { return .failure(.invalidPattern) }
            return .success([ModuleRewriteRule(pattern: words[0], action: .rejectDrop, origin: origin)])
        }
        if let words = tokens(line), words.count >= 2, words[1] != "url" {
            let second = words[1].lowercased()
            if second.hasPrefix("header-") || second.hasPrefix("request-header-") || second.hasPrefix("response-header-") {
                return headerRewrites(line, origin: origin, severalHeaders: true)
            }
            if second == "request-body-replace-regex" || second == "response-body-replace-regex" {
                return bodyRewrite(line, origin: origin).map { [$0] }
            }
            if let json = loonBodyJSON(line, origin: origin, moduleURL: nil) {
                return json.flatMap { $0.files.isEmpty ? .success($0.rules) : .failure(.unsupportedRewriteType(words[1])) }
            }
            if second.hasPrefix("request-") || second.hasPrefix("response-") || second.hasPrefix("mock-") {
                return .failure(.unsupportedRewriteType(words[1]))
            }
             
            if words.count > 3, rejectAction(words[1]) == nil, !isAbsoluteWebAddress(words[1]), words[1] != "-", words[1] != "_" {
                return .failure(.unsupportedRewriteType(words[1]))
            }
        }
        return urlRewrite(line, origin: origin).map { [$0] }
    }

     
     
     
     
    static func isLoonOperationLine(_ line: String) -> Bool {
        guard let words = tokens(line), words.count >= 3 else { return false }
        let second = words[1].lowercased()
        return second.hasPrefix("header-") || second.hasPrefix("request-header-") || second.hasPrefix("response-header-")
            || second == "request-body-replace-regex" || second == "response-body-replace-regex"
            || second == "request-body-json-jq" || second == "response-body-json-jq"
            || (second.contains("-body-json-") && ModuleJSONRewriteSyntax.Verb.spelled(second) != nil)
    }

     
     
     
     
    static func headerRewrite(_ line: String, origin: ModuleLineOrigin) -> Result<ModuleRewriteRule, ModuleIgnoredReason> {
        headerRewrites(line, origin: origin, severalHeaders: false).map { $0[0] }
    }

     
     
     
    static func headerRewrites(_ line: String, origin: ModuleLineOrigin,
                               severalHeaders: Bool) -> Result<[ModuleRewriteRule], ModuleIgnoredReason> {
        guard ModuleYAMLText.isOneLine(line) else { return .failure(.unreadableLine) }
        guard var words = tokens(line), !words.isEmpty else { return .failure(.unreadableLine) }
        var phase = ModuleRewritePhase.request
        switch words[0].lowercased() {
        case "http-request": words.removeFirst()
        case "http-response": phase = .response; words.removeFirst()
        default: break
        }
        guard words.count >= 3 else { return .failure(.unreadableLine) }
        let pattern = words[0]
        var operation = words[1].lowercased()
        for (prefix, side) in [("request-", ModuleRewritePhase.request), ("response-", .response)] where operation.hasPrefix(prefix) {
            phase = side
            operation = String(operation.dropFirst(prefix.count))
            if !operation.hasPrefix("header-") { operation = "header-" + operation }
        }
        let kind: ModuleHeaderOperation
        let arity: Int
        switch operation {
        case "header-add": kind = .add; arity = 1
        case "header-del": kind = .delete; arity = 0
        case "header-replace": kind = .replace; arity = 1
        case "header-replace-regex": kind = .replaceRegex; arity = 2
        default: return .failure(.unsupportedRewriteType(words[1]))
        }
        let given = Array(words.dropFirst(2))
        let group = 1 + arity
        guard given.count == group || (severalHeaders && given.count > group && given.count % group == 0) else {
            return .failure(.unreadableLine)
        }
        guard isValidPattern(pattern) else { return .failure(.invalidPattern) }
        var rules: [ModuleRewriteRule] = []
        var index = 0
        while index < given.count {
            let arguments = Array(given[(index + 1)..<(index + group)])
            guard kind != .replaceRegex || isValidPattern(arguments[0]) else { return .failure(.invalidPattern) }
            rules.append(ModuleRewriteRule(
                pattern: pattern, action: .header(phase: phase, operation: kind, name: given[index], arguments: arguments),
                origin: origin))
            index += group
        }
        return .success(rules)
    }

     
     
     
    static func bodyRewrite(_ line: String, origin: ModuleLineOrigin) -> Result<ModuleRewriteRule, ModuleIgnoredReason> {
        bodyRewriteReading(line, origin: origin, moduleURL: nil).flatMap { reading in
            guard reading.files.isEmpty, let rule = reading.rules.first else {
                let head = splitHead(line, count: 2)?.head ?? []
                return .failure(.unsupportedRewriteType(head.first.map { $0.lowercased().hasPrefix("http-") ? $0 : head.last ?? $0 } ?? line))
            }
            return .success(rule)
        }
    }

     
     
     
     
     
     
     
     
     
    static func bodyRewriteReading(_ line: String, origin: ModuleLineOrigin, moduleURL: String?) -> Result<Reading, ModuleIgnoredReason> {
        guard ModuleYAMLText.isOneLine(line) else { return .failure(.unreadableLine) }
        guard let split = splitHead(line, count: 2) else { return .failure(.unreadableLine) }
        let (head, rest) = split
        let phase: ModuleRewritePhase
        let pattern: String
        switch head[0].lowercased() {
        case "http-request": phase = .request; pattern = head[1]
        case "http-response": phase = .response; pattern = head[1]
        case "http-request-jq", "http-response-jq":
            return jsonBodyRewrite(pattern: head[1], keyword: head[0], rest: rest, origin: origin, moduleURL: moduleURL,
                                   resolvesAgainstTheModule: false)
        default:
            pattern = head[0]
            switch head[1].lowercased() {
            case "request-replace-regex", "request-body-replace-regex": phase = .request
            case "response-replace-regex", "response-body-replace-regex": phase = .response
            default:
                return jsonBodyRewrite(pattern: pattern, keyword: head[1], rest: rest, origin: origin, moduleURL: moduleURL,
                                       resolvesAgainstTheModule: false)
            }
        }
        guard isValidPattern(pattern) else { return .failure(.invalidPattern) }
        guard let words = tokens(rest), !words.isEmpty, words.count % 2 == 0 else { return .failure(.unreadableLine) }
        var pairs: [ModuleReplacementPair] = []
        var index = 0
        while index < words.count {
            guard isValidPattern(words[index]) else { return .failure(.invalidPattern) }
            pairs.append(ModuleReplacementPair(search: words[index], replacement: words[index + 1]))
            index += 2
        }
        return .success(Reading(rules: [ModuleRewriteRule(pattern: pattern, action: .bodyReplace(phase: phase, pairs: pairs), origin: origin)]))
    }

     
     
     
     
     
     
    static func jsonBodyRewrite(pattern: String, keyword: String, rest: String, origin: ModuleLineOrigin, moduleURL: String?,
                                        resolvesAgainstTheModule: Bool) -> Result<Reading, ModuleIgnoredReason> {
        let word = keyword.lowercased()
        let jqPhase: ModuleRewritePhase?
        switch word {
        case "http-request-jq", "request-jq", "request-body-json-jq": jqPhase = .request
        case "http-response-jq", "response-jq", "response-body-json-jq": jqPhase = .response
        default: jqPhase = nil
        }
        let operation = ModuleJSONRewriteSyntax.Verb.spelled(word)
        guard jqPhase != nil || operation != nil else { return .failure(.unsupportedRewriteType(keyword)) }
        guard isValidPattern(pattern) else { return .failure(.invalidPattern) }
        if let phase = jqPhase {
            let written = rest.trimmingCharacters(in: .whitespaces)
            guard !written.isEmpty else { return .failure(.unreadableLine) }
            func rule(_ expression: String) -> ModuleRewriteRule {
                ModuleRewriteRule(pattern: pattern, action: .bodyJQ(phase: phase, expression: expression), origin: origin)
            }
            switch ModuleJSONRewriteSyntax.jqSource(ModuleJSONRewriteSyntax.unquoted(written) ?? written) {
            case .expression(let expression):
                return ModuleJSONRewriteSyntax.jq(expression).map { Reading(rules: [rule($0)]) }
            case .file(let name):
                 
                return ModuleLocalAnswerSyntax.fileAddress(name, moduleURL: moduleURL, resolvesAgainstTheModule: resolvesAgainstTheModule)
                    .map { Reading(rules: [rule("")], files: [ModuleAnswerFileReference(url: $0, sha256: nil, origin: origin)]) }
            }
        }
        guard let (phase, verb) = operation, let words = ModuleJSONRewriteSyntax.words(rest) else { return .failure(.unreadableLine) }
         
        let paths: [String]
        let values: [String]?
        if verb.takesValue {
            guard words.count >= 2, words.count % 2 == 0 else { return .failure(.unreadableLine) }
            paths = stride(from: 0, to: words.count, by: 2).map { ModuleJSONRewriteSyntax.unquoted(words[$0]) ?? words[$0] }
            values = stride(from: 1, to: words.count, by: 2).map { words[$0] }
        } else {
            paths = words.map { ModuleJSONRewriteSyntax.unquoted($0) ?? $0 }
            values = nil
        }
        return ModuleJSONRewriteSyntax.operations(verb, paths: paths, values: values).map {
            Reading(rules: [ModuleRewriteRule(pattern: pattern, action: .json(phase: phase, operations: $0), origin: origin)])
        }
    }

     

     
     
     
     
     
     
     
     
     
     
    static func mapLocalParameters(_ text: String) -> [(key: String, value: String)]? {
        quotedParameters(text)?.map { (key: $0.key, value: $0.value) }
    }

     
     
    static func quotedParameters(_ text: String) -> [(key: String, value: String, bareQuote: Bool)]? {
        let characters = Array(text)
        var out: [(key: String, value: String, bareQuote: Bool)] = []
        var index = 0
        while index < characters.count {
            if isBlank(characters[index]) { index += 1; continue }
            let keyStart = index
            while index < characters.count, characters[index] != "=", !isBlank(characters[index]) { index += 1 }
            guard index < characters.count, characters[index] == "=", index > keyStart else { return nil }
            let key = String(characters[keyStart..<index]).lowercased()
            index += 1
            var value = ""
            var bareQuote = false
            if index < characters.count, characters[index] == "\"" || characters[index] == "'" {
                let quote = characters[index]
                index += 1
                var closed = false
                while index < characters.count {
                    let character = characters[index]
                    if character == "\\", index + 1 < characters.count, characters[index + 1] == quote || characters[index + 1] == "\\" {
                        value.append(characters[index + 1])
                        index += 2
                    } else if character == quote, index + 1 == characters.count || isBlank(characters[index + 1]) {
                        index += 1
                        closed = true
                        break
                    } else {
                        if character == quote { bareQuote = true }
                        value.append(character)
                        index += 1
                    }
                }
                guard closed else { return nil }
            } else {
                while index < characters.count, !isBlank(characters[index]) { value.append(characters[index]); index += 1 }
            }
            out.append((key: key, value: value, bareQuote: bareQuote))
        }
        return out
    }

     

     
     
     
     
     
     
     
    static func parameters(_ text: String) -> [(key: String, value: String)] {
        let characters = Array(text)
        var out: [(key: String, value: String)] = []
        func isKeyCharacter(_ character: Character) -> Bool {
            character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_")
        }
        func startsPair(at start: Int) -> Bool {
            var index = start
            while index < characters.count, characters[index] == " " { index += 1 }
            let keyStart = index
            while index < characters.count, isKeyCharacter(characters[index]) { index += 1 }
            let keyEnd = index
            while index < characters.count, characters[index] == " " { index += 1 }
            return keyEnd > keyStart && index < characters.count && characters[index] == "="
        }
        var index = 0
        while index < characters.count {
            while index < characters.count, characters[index] == " " || characters[index] == "," { index += 1 }
            let keyStart = index
            while index < characters.count, characters[index] != "=" { index += 1 }
            guard index < characters.count else { break }
            let key = String(characters[keyStart..<index]).trimmingCharacters(in: .whitespaces).lowercased()
            index += 1
            var value = ""
            while index < characters.count, characters[index] == " " { index += 1 }
            var quotedValue: String?
            if index < characters.count, characters[index] == "\"" {
                 
                var scan = index + 1
                while scan < characters.count {
                    if characters[scan] == "\\", scan + 1 < characters.count, characters[scan + 1] == "\"" {
                        scan += 2
                        continue
                    }
                    if characters[scan] == "\"" {
                        var after = scan + 1
                        while after < characters.count, characters[after] == " " { after += 1 }
                        let ends = after == characters.count
                            || (characters[after] == "," && (startsPair(at: after + 1)
                                || characters[(after + 1)...].allSatisfy { $0 == " " }))
                        if ends {
                            quotedValue = String(characters[(index + 1)..<scan]).replacingOccurrences(of: "\\\"", with: "\"")
                            index = after
                            break
                        }
                    }
                    scan += 1
                }
            }
            if let quotedValue {
                value = quotedValue
            } else {
                while index < characters.count {
                    if characters[index] == ",", startsPair(at: index + 1) { break }
                    value.append(characters[index])
                    index += 1
                }
                value = value.trimmingCharacters(in: .whitespaces)
            }
            if !key.isEmpty { out.append((key: key, value: value)) }
        }
        return out
    }

     
     
    enum DeclaredScript: Equatable {
        case http(ModuleScript)
        case app(ModuleAppScript)

        var http: ModuleScript? {
            if case .http(let script) = self { return script } else { return nil }
        }

        var app: ModuleAppScript? {
            if case .app(let script) = self { return script } else { return nil }
        }
    }

     
     
    static let surgeEvents: Set<String> = ["network-changed", "notification", "engine-started", "profile-reloaded"]

     
     
     
     
     
     
     
     
    static func script(name: String, parameters: [(key: String, value: String)],
                       origin: ModuleLineOrigin) -> Result<DeclaredScript, ModuleIgnoredReason> {
         
         
        guard ModuleYAMLText.isOneLine(name), parameters.allSatisfy({ ModuleYAMLText.isOneLine($0.value) }) else {
            return .failure(.unreadableLine)
        }
        var values: [String: String] = [:]
        for parameter in parameters where values[parameter.key] == nil { values[parameter.key] = parameter.value }
         
         
        let type = (values["type"] ?? "").prefix { $0 != "," }.trimmingCharacters(in: .whitespaces).lowercased()
        let kind: ModuleAppScriptKind
        switch type {
        case "http-request", "http-response":
            return httpScript(name: name, phase: type == "http-request" ? .request : .response, values: values, origin: origin)
        case "cron": kind = .cron
        case "event": kind = .event
        case "generic", "": kind = .generic
        case "dns": return .failure(.platformCannot(.dnsScripts))
        case "rule": return .failure(.platformCannot(.ruleScripts))
        default: return .failure(.unsupportedScriptType(type))
        }
        return appScript(name: name, kind: kind, values: values, origin: origin)
    }

    private static func flag(_ values: [String: String], _ keys: String...) -> Bool {
        keys.contains { ["1", "true", "yes"].contains((values[$0] ?? "").lowercased()) }
    }

    private static func number(_ values: [String: String], _ key: String) -> Int? {
        values[key].flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

     
     
     
     
     
     
     
    private static func maxSize(_ values: [String: String]) -> Int? {
        values["max-size"].map { Int(NSString(string: $0).intValue) }
    }

     
    private static func isTurnedOff(_ values: [String: String]) -> Bool {
        ["enable", "enabled"].contains { ["0", "false", "no"].contains((values[$0] ?? "").lowercased()) }
    }

     
     
     
     
     
    private static func scriptAddress(_ path: String) -> Result<String, ModuleIgnoredReason> {
        guard let url = URL(string: path), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host?.isEmpty == false else {
            return .failure(.scriptWithoutAddress)
        }
         
         
         
        guard path.utf8.count <= ModuleParser.maximumShownBytes else { return .failure(.unreadableLine) }
        return .success(path)
    }

    private static func httpScript(name: String, phase: ModuleRewritePhase, values: [String: String],
                                   origin: ModuleLineOrigin) -> Result<DeclaredScript, ModuleIgnoredReason> {
        if isTurnedOff(values) { return .failure(.scriptTurnedOff) }
        if values["jq-path"] != nil { return .failure(.unsupportedRewriteType("jq-path")) }
        guard let pattern = values["pattern"], !pattern.isEmpty else { return .failure(.unreadableLine) }
        let path: String
        switch scriptAddress(values["script-path"] ?? "") {
        case .success(let address): path = address
        case .failure(let reason): return .failure(reason)
        }
        guard isValidPattern(pattern) else { return .failure(.invalidPattern) }
        let interval = scriptUpdateInterval(values)
        return .success(.http(ModuleScript(
            name: name, phase: phase, pattern: pattern, scriptURL: path,
            requiresBody: flag(values, "requires-body", "require-body"),
            binaryBodyMode: flag(values, "binary-body-mode", "binary-mode"),
            maxSize: maxSize(values), timeout: number(values, "timeout") ?? number(values, "time-out"),
            argument: values["argument"].flatMap { $0.isEmpty ? nil : $0 },
            updateInterval: interval, bodySHA256: nil, origin: origin)))
    }

     
     
     
     
     
     
    private static func appScript(name: String, kind: ModuleAppScriptKind, values: [String: String],
                                  origin: ModuleLineOrigin) -> Result<DeclaredScript, ModuleIgnoredReason> {
        if isTurnedOff(values) { return .failure(.scriptTurnedOff) }
        var made = ModuleAppScript(name: name, kind: kind, scriptURL: "", origin: origin)
        switch kind {
        case .cron:
            guard let written = values["cronexp"] ?? values["cronexpr"], let schedule = cronExpression(written) else {
                return .failure(.unreadableLine)
            }
            made.cronExpression = schedule
        case .event:
            let event = (values["event-name"] ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            guard surgeEvents.contains(event) else { return .failure(.noEffectInItsOwnApp(.noEffectThereEither)) }
            if event == "network-changed" { made.kind = .networkChanged } else { made.eventName = event }
        case .networkChanged, .generic:
            break
        }
        switch scriptAddress(values["script-path"] ?? "") {
        case .success(let address): made.scriptURL = address
        case .failure(let reason): return .failure(reason)
        }
        made.timeout = number(values, "timeout") ?? number(values, "time-out")
        made.argument = values["argument"].flatMap { $0.isEmpty ? nil : $0 }
        made.updateInterval = scriptUpdateInterval(values)
        made.wakeSystem = flag(values, "wake-system")
        made.engine = values["engine"].flatMap { $0.isEmpty ? nil : $0 }
        return .success(.app(made))
    }

     
    private static let cronWords: Set<String> = ["@yearly", "@annually", "@monthly", "@weekly", "@daily", "@midnight", "@hourly"]

     
     
     
     
     
     
     
     
     
    static func cronExpression(_ written: String) -> String? {
        var text = written.trimmingCharacters(in: .whitespaces)
        if text.count >= 2, let quote = text.first, quote == "\"" || quote == "'", text.last == quote {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        if text.hasPrefix("@") { return cronWords.contains(text.lowercased()) ? text : nil }
        let fields = text.split(whereSeparator: isBlank)
        guard (5...7).contains(fields.count) else { return nil }
        let marks = Set("*/,-?")
        let shaped = fields.allSatisfy { field in
            field.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || marks.contains($0)) }
                && field.split(whereSeparator: { !$0.isLetter }).allSatisfy { $0.count == 3 }
        }
        return shaped ? text : nil
    }

     
     
     
     
     
    static func panel(_ line: String, origin: ModuleLineOrigin) -> Result<ModulePanel, ModuleIgnoredReason> {
        guard let equals = line.firstIndex(of: "=") else { return .failure(.unreadableLine) }
        let name = line[..<equals].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return .failure(.unreadableLine) }
        var panel = ModulePanel(name: name, origin: origin)
        for (key, written) in parameters(String(line[line.index(after: equals)...])) {
            let value = written.isEmpty ? nil : written
            switch key {
            case "title": panel.title = value
            case "content": panel.content = value
            case "style": panel.style = value?.lowercased()
            case "icon": panel.icon = value
            case "icon-color": panel.iconColor = value
            case "script-name": panel.scriptName = value
            case "update-interval": panel.updateInterval = value.flatMap { Int($0) }.flatMap { $0 > 0 ? $0 : nil }
            default: break
            }
        }
        guard panel.title != nil || panel.content != nil || panel.scriptName != nil else { return .failure(.unreadableLine) }
        return .success(panel)
    }

    static func surgeScript(_ line: String, origin: ModuleLineOrigin) -> Result<DeclaredScript, ModuleIgnoredReason> {
        guard let equals = line.firstIndex(of: "=") else { return .failure(.unreadableLine) }
        let name = line[..<equals].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return .failure(.unreadableLine) }
        return script(name: name, parameters: parameters(String(line[line.index(after: equals)...])), origin: origin)
    }

     
     
     
     
     
    static func loonScriptParts(_ line: String) -> (type: String, head: String?, options: [(key: String, value: String)])? {
        let text = line.trimmingCharacters(in: .whitespaces)
        guard let typeEnd = text.firstIndex(where: isBlank) else { return nil }
        let type = text[..<typeEnd].lowercased()
        let rest = text[typeEnd...].trimmingCharacters(in: .whitespaces)
        switch type {
        case "cron":
            if let first = rest.first, first == "\"" || first == "'" {
                guard let split = splitHead(rest, count: 1), !split.head[0].isEmpty else { return nil }
                return (type, split.head[0], parameters(split.rest))
            }
            var words: [Substring] = []
            var remaining = Substring(rest)
            while let start = remaining.firstIndex(where: { !isBlank($0) }) {
                let word = remaining[start...].prefix { !isBlank($0) }
                 
                 
                let after = remaining[word.endIndex...].drop(while: isBlank)
                if word.contains("=") || after.hasPrefix("=") {
                    remaining = remaining[start...]
                    break
                }
                words.append(word)
                remaining = remaining[word.endIndex...]
            }
            guard !words.isEmpty else { return nil }
            return (type, words.joined(separator: " "), parameters(String(remaining)))
        case "network-changed", "generic", "dns":
            return (type, nil, parameters(rest))
        default:
            guard let split = splitHead(text, count: 2) else { return nil }
            return (type, split.head[1], parameters(split.rest))
        }
    }

     
     
     
    static func loonScript(_ line: String, origin: ModuleLineOrigin) -> Result<DeclaredScript, ModuleIgnoredReason> {
        guard let parts = loonScriptParts(line) else { return .failure(.unreadableLine) }
        var declared = parts.options
        switch parts.type {
        case "cron":
            declared.insert((key: "cronexp", value: parts.head ?? ""), at: 0)
            declared.insert((key: "type", value: "cron"), at: 0)
        case "network-changed":
            declared.insert((key: "event-name", value: "network-changed"), at: 0)
            declared.insert((key: "type", value: "event"), at: 0)
        case "generic", "dns":
            declared.insert((key: "type", value: parts.type), at: 0)
        default:
            declared.insert((key: "pattern", value: parts.head ?? ""), at: 0)
            declared.insert((key: "type", value: parts.type), at: 0)
        }
         
         
         
        let tag = declared.first { $0.key == "tag" }?.value ?? ""
        let file = declared.first { $0.key == "script-path" }.flatMap { URL(string: $0.value)?.lastPathComponent } ?? ""
        let fallback = parts.type.hasPrefix("http-") ? parts.head ?? parts.type : parts.type
        return script(name: !tag.isEmpty ? tag : !file.isEmpty && file != "/" ? file : fallback, parameters: declared, origin: origin)
    }

     
     
     
    static func isNewerLoonSyntax(_ line: String) -> Bool {
        let words = line.split(separator: " ", maxSplits: 2).map { $0.lowercased() }
        guard words.count >= 2 else { return false }
        return (["request", "response"].contains(words[0]) && words[1] == "if")
            || (words[0] == "cron" && line.range(of: #" then "#, options: .caseInsensitive) != nil)
            || (["network-changed", "generic"].contains(words[0]) && words[1] == "then")
    }

     
     
    static func isLoonScriptLine(_ line: String) -> Bool {
        let first = line.split(separator: " ", maxSplits: 1).first.map { $0.lowercased() } ?? ""
        return ["http-request", "http-response", "cron", "generic", "network-changed", "dns"].contains(first)
    }

     
     
     
     
     
     
    static func scriptAddress(ofLine line: String, moduleURL: String?) -> String? {
        let text = line.trimmingCharacters(in: .whitespaces)
        if isNewerLoonSyntax(text) || ModuleLoonRewriteSyntax.isRule(text) {
             
            guard let call = text.range(of: #"\sthen\s+script\s*\("#, options: [.regularExpression, .caseInsensitive]) else { return nil }
            let rest = text[call.upperBound...].drop(while: isBlank)
            guard let quote = rest.first, quote == "\"" || quote == "'" else { return nil }
            let body = rest.dropFirst()
            guard let end = body.firstIndex(of: quote) else { return nil }
            guard case .success(let address) = ModuleLocalAnswerSyntax.fileAddress(
                String(body[..<end]), moduleURL: moduleURL, resolvesAgainstTheModule: true) else { return nil }
            return address
        }
        let options: [(key: String, value: String)]
        if isLoonScriptLine(text) {
            options = loonScriptParts(text)?.options ?? []
        } else if let equals = text.firstIndex(of: "=") {
            options = parameters(String(text[text.index(after: equals)...]))
        } else {
            options = []
        }
        guard let path = options.first(where: { $0.key == "script-path" })?.value, !path.isEmpty else { return nil }
        return path
    }
}
