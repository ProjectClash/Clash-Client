import Foundation

 
 
 
 
enum AdBlockLineSyntax {
     
     
    static let defaultScriptUpdateInterval = 86_400

     

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

     
     
    static func rejectAction(_ word: String) -> AdBlockRewriteAction? {
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

     
     
     
     
     
    static func rewriteAnswer(_ word: String) -> AdBlockRewriteAction? {
        if let reject = rejectAction(word) { return reject }
        guard word.lowercased().replacingOccurrences(of: "_", with: "-") == "reject-video" else { return nil }
        return .localAnswer(AdBlockLocalAnswer(status: 200, headers: [AdBlockHeaderField(name: "Content-Type", value: "video/mp4")],
                                               body: .emptyVideo))
    }

     

    private static func isAbsoluteWebAddress(_ text: String) -> Bool {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host?.isEmpty == false
    }

     
     
     
     
     
     
     
    static func urlRewrite(_ line: String, origin: AdBlockLineOrigin) -> Result<AdBlockRewriteRule, AdBlockIgnoredReason> {
        guard AdBlockYAMLText.isOneLine(line) else { return .failure(.unreadableLine) }
        if let words = tokens(line), words.count >= 3, words[1] == "url", !words[0].isEmpty {
            guard let reject = rewriteAnswer(words[2]) else { return .failure(.unsupportedRewriteType(words[2])) }
            guard words.count == 3 else { return .failure(.unreadableLine) }
            guard isValidPattern(words[0]) else { return .failure(.invalidPattern) }
            return .success(AdBlockRewriteRule(pattern: words[0], action: reject, origin: origin))
        }
        guard let words = tokens(line), words.count == 2 || words.count == 3, !words[0].isEmpty else {
            return .failure(.unreadableLine)
        }
         
         
         
        if words.count == 3, ["302", "307", "header"].contains(words[1].lowercased()), isAbsoluteWebAddress(words[2]) {
            return loonRewrites(line, origin: origin).flatMap { rules in rules.first.map { .success($0) } ?? .failure(.unreadableLine) }
        }
        let action: AdBlockRewriteAction
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
        return .success(AdBlockRewriteRule(pattern: words[0], action: action, origin: origin))
    }

     
     
     
    struct Reading: Equatable {
        var rules: [AdBlockRewriteRule]
        var files: [AdBlockAnswerFileReference] = []
    }

     
     
     
     
    static func loonRewriteReading(_ line: String, origin: AdBlockLineOrigin, moduleURL: String?) -> Result<Reading, AdBlockIgnoredReason> {
        if let json = loonBodyJSON(line, origin: origin, moduleURL: moduleURL) { return json }
        return loonRewrites(line, origin: origin).map { Reading(rules: $0) }
    }

     
     
     
     
     
    private static func loonBodyJSON(_ line: String, origin: AdBlockLineOrigin, moduleURL: String?) -> Result<Reading, AdBlockIgnoredReason>? {
        guard let words = tokens(line), words.count >= 2 else { return nil }
        let keyword = words[1].lowercased()
        let isJQ = keyword == "request-body-json-jq" || keyword == "response-body-json-jq"
        guard isJQ || (keyword.contains("-body-json-") && AdBlockJSONRewriteSyntax.Verb.spelled(keyword) != nil) else { return nil }
        guard AdBlockYAMLText.isOneLine(line), let split = splitHead(line, count: 2) else { return .failure(.unreadableLine) }
        return jsonBodyRewrite(pattern: split.head[0], keyword: split.head[1], rest: split.rest, origin: origin, moduleURL: moduleURL,
                               resolvesAgainstTheModule: true)
    }

     
    static func loonRewrite(_ line: String, origin: AdBlockLineOrigin) -> Result<AdBlockRewriteRule, AdBlockIgnoredReason> {
        loonRewrites(line, origin: origin).flatMap { rules in rules.first.map { .success($0) } ?? .failure(.unreadableLine) }
    }

     
     
     
     
     
     
     
     
     
     
     
    static func loonRewrites(_ line: String, origin: AdBlockLineOrigin) -> Result<[AdBlockRewriteRule], AdBlockIgnoredReason> {
        guard AdBlockYAMLText.isOneLine(line) else { return .failure(.unreadableLine) }
         
         
        if let words = tokens(line), words.count == 3, !words[0].isEmpty {
            let action: AdBlockRewriteAction?
            switch words[1].lowercased() {
            case "302": action = .redirect302(words[2])
            case "307": action = .redirect307(words[2])
            case "header", "transparent": action = .transparent(words[2])
            default: action = nil
            }
            if let action {
                guard isValidPattern(words[0]) else { return .failure(.invalidPattern) }
                return .success([AdBlockRewriteRule(pattern: words[0], action: action, origin: origin)])
            }
        }
         
         
         
         
        if let words = tokens(line), words.count == 2, !words[0].isEmpty, words[1].lowercased() == "reject" {
            guard isValidPattern(words[0]) else { return .failure(.invalidPattern) }
            return .success([AdBlockRewriteRule(pattern: words[0], action: .rejectDrop, origin: origin)])
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
            || (second.contains("-body-json-") && AdBlockJSONRewriteSyntax.Verb.spelled(second) != nil)
    }

     
     
     
     
    static func headerRewrite(_ line: String, origin: AdBlockLineOrigin) -> Result<AdBlockRewriteRule, AdBlockIgnoredReason> {
        headerRewrites(line, origin: origin, severalHeaders: false).map { $0[0] }
    }

     
     
     
    static func headerRewrites(_ line: String, origin: AdBlockLineOrigin,
                               severalHeaders: Bool) -> Result<[AdBlockRewriteRule], AdBlockIgnoredReason> {
        guard AdBlockYAMLText.isOneLine(line) else { return .failure(.unreadableLine) }
        guard var words = tokens(line), !words.isEmpty else { return .failure(.unreadableLine) }
        var phase = AdBlockRewritePhase.request
        switch words[0].lowercased() {
        case "http-request": words.removeFirst()
        case "http-response": phase = .response; words.removeFirst()
        default: break
        }
        guard words.count >= 3 else { return .failure(.unreadableLine) }
        let pattern = words[0]
        var operation = words[1].lowercased()
        for (prefix, side) in [("request-", AdBlockRewritePhase.request), ("response-", .response)] where operation.hasPrefix(prefix) {
            phase = side
            operation = String(operation.dropFirst(prefix.count))
            if !operation.hasPrefix("header-") { operation = "header-" + operation }
        }
        let kind: AdBlockHeaderOperation
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
        var rules: [AdBlockRewriteRule] = []
        var index = 0
        while index < given.count {
            let arguments = Array(given[(index + 1)..<(index + group)])
            guard kind != .replaceRegex || isValidPattern(arguments[0]) else { return .failure(.invalidPattern) }
            rules.append(AdBlockRewriteRule(
                pattern: pattern, action: .header(phase: phase, operation: kind, name: given[index], arguments: arguments),
                origin: origin))
            index += group
        }
        return .success(rules)
    }

     
     
     
    static func bodyRewrite(_ line: String, origin: AdBlockLineOrigin) -> Result<AdBlockRewriteRule, AdBlockIgnoredReason> {
        bodyRewriteReading(line, origin: origin, moduleURL: nil).flatMap { reading in
            guard reading.files.isEmpty, let rule = reading.rules.first else {
                let head = splitHead(line, count: 2)?.head ?? []
                return .failure(.unsupportedRewriteType(head.first.map { $0.lowercased().hasPrefix("http-") ? $0 : head.last ?? $0 } ?? line))
            }
            return .success(rule)
        }
    }

     
     
     
     
     
     
     
     
     
    static func bodyRewriteReading(_ line: String, origin: AdBlockLineOrigin, moduleURL: String?) -> Result<Reading, AdBlockIgnoredReason> {
        guard AdBlockYAMLText.isOneLine(line) else { return .failure(.unreadableLine) }
        guard let split = splitHead(line, count: 2) else { return .failure(.unreadableLine) }
        let (head, rest) = split
        let phase: AdBlockRewritePhase
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
        var pairs: [AdBlockReplacementPair] = []
        var index = 0
        while index < words.count {
            guard isValidPattern(words[index]) else { return .failure(.invalidPattern) }
            pairs.append(AdBlockReplacementPair(search: words[index], replacement: words[index + 1]))
            index += 2
        }
        return .success(Reading(rules: [AdBlockRewriteRule(pattern: pattern, action: .bodyReplace(phase: phase, pairs: pairs), origin: origin)]))
    }

     
     
     
     
     
     
    private static func jsonBodyRewrite(pattern: String, keyword: String, rest: String, origin: AdBlockLineOrigin, moduleURL: String?,
                                        resolvesAgainstTheModule: Bool) -> Result<Reading, AdBlockIgnoredReason> {
        let word = keyword.lowercased()
        let jqPhase: AdBlockRewritePhase?
        switch word {
        case "http-request-jq", "request-jq", "request-body-json-jq": jqPhase = .request
        case "http-response-jq", "response-jq", "response-body-json-jq": jqPhase = .response
        default: jqPhase = nil
        }
        let operation = AdBlockJSONRewriteSyntax.Verb.spelled(word)
        guard jqPhase != nil || operation != nil else { return .failure(.unsupportedRewriteType(keyword)) }
        guard isValidPattern(pattern) else { return .failure(.invalidPattern) }
        if let phase = jqPhase {
            let written = rest.trimmingCharacters(in: .whitespaces)
            guard !written.isEmpty else { return .failure(.unreadableLine) }
            func rule(_ expression: String) -> AdBlockRewriteRule {
                AdBlockRewriteRule(pattern: pattern, action: .bodyJQ(phase: phase, expression: expression), origin: origin)
            }
            switch AdBlockJSONRewriteSyntax.jqSource(AdBlockJSONRewriteSyntax.unquoted(written) ?? written) {
            case .expression(let expression):
                return AdBlockJSONRewriteSyntax.jq(expression).map { Reading(rules: [rule($0)]) }
            case .file(let name):
                 
                return AdBlockLocalAnswerSyntax.fileAddress(name, moduleURL: moduleURL, resolvesAgainstTheModule: resolvesAgainstTheModule)
                    .map { Reading(rules: [rule("")], files: [AdBlockAnswerFileReference(url: $0, sha256: nil, origin: origin)]) }
            }
        }
        guard let (phase, verb) = operation, let words = AdBlockJSONRewriteSyntax.words(rest) else { return .failure(.unreadableLine) }
         
        let paths: [String]
        let values: [String]?
        if verb.takesValue {
            guard words.count >= 2, words.count % 2 == 0 else { return .failure(.unreadableLine) }
            paths = stride(from: 0, to: words.count, by: 2).map { AdBlockJSONRewriteSyntax.unquoted(words[$0]) ?? words[$0] }
            values = stride(from: 1, to: words.count, by: 2).map { words[$0] }
        } else {
            paths = words.map { AdBlockJSONRewriteSyntax.unquoted($0) ?? $0 }
            values = nil
        }
        return AdBlockJSONRewriteSyntax.operations(verb, paths: paths, values: values).map {
            Reading(rules: [AdBlockRewriteRule(pattern: pattern, action: .json(phase: phase, operations: $0), origin: origin)])
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

     
     
     
     
     
    static func script(name: String, parameters: [(key: String, value: String)],
                       origin: AdBlockLineOrigin) -> Result<AdBlockScript, AdBlockIgnoredReason> {
         
         
        guard AdBlockYAMLText.isOneLine(name), parameters.allSatisfy({ AdBlockYAMLText.isOneLine($0.value) }) else {
            return .failure(.unreadableLine)
        }
        var values: [String: String] = [:]
        for parameter in parameters where values[parameter.key] == nil { values[parameter.key] = parameter.value }
        let type = (values["type"] ?? "").lowercased()
        let phase: AdBlockRewritePhase
        switch type {
        case "http-request": phase = .request
        case "http-response": phase = .response
         
         
        case "cron": phase = .cron
        case "generic", "network-changed", "dns": phase = .generic
        default: return .failure(.unsupportedScriptType(type))
        }
        if ["0", "false", "no"].contains((values["enable"] ?? "").lowercased()) {
            return .failure(.scriptTurnedOff)
        }
        if values["jq-path"] != nil { return .failure(.unsupportedRewriteType("jq-path")) }
        // A cron declaration has no URL: Surge writes its schedule as
        // `cronexp`, and the schedule is what plays the part `pattern` plays
        // for a request or response script. Requiring a pattern here rejected
        // every cron module Surge and Loon publish.
        let schedule = phase == .cron ? (values["cronexp"] ?? values["cron"] ?? values["pattern"]) : nil
        let pattern: String
        if let schedule, !schedule.isEmpty {
            pattern = schedule
        } else if let declared = values["pattern"], !declared.isEmpty {
            pattern = declared
        } else {
            return .failure(.unreadableLine)
        }
        let path = values["script-path"] ?? ""
        if path.lowercased().contains("boxjs") || pattern.lowercased().contains("boxjs") {
            return .failure(.boxJSNotSupported)
        }
        guard let url = URL(string: path), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host?.isEmpty == false else {
            return .failure(.scriptWithoutAddress)
        }
         
         
         
        guard path.utf8.count <= AdBlockModuleParser.maximumShownBytes else { return .failure(.unreadableLine) }
         
         
         
        guard scheme == "https" else { return .failure(.scriptAddressNotSecure) }
        // A cron schedule is not a URL pattern; the other phases' patterns are.
        if phase != .cron {
            guard isValidPattern(pattern) else { return .failure(.invalidPattern) }
        }
        func flag(_ keys: String...) -> Bool {
            keys.contains { ["1", "true", "yes"].contains((values[$0] ?? "").lowercased()) }
        }
        func number(_ key: String) -> Int? {
            values[key].flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        }
        let interval = number("script-update-interval").flatMap { $0 > 0 ? $0 : nil } ?? defaultScriptUpdateInterval
        return .success(AdBlockScript(
            name: name, phase: phase, pattern: pattern, scriptURL: path,
            requiresBody: flag("requires-body", "require-body"),
            binaryBodyMode: flag("binary-body-mode", "binary-mode"),
            maxSize: number("max-size"), timeout: number("timeout") ?? number("time-out"),
            argument: values["argument"].flatMap { $0.isEmpty ? nil : $0 },
            updateInterval: interval, bodySHA256: nil, origin: origin,
            cronFields: schedule.map { [$0] }))
    }

     
    static func surgeScript(_ line: String, origin: AdBlockLineOrigin) -> Result<AdBlockScript, AdBlockIgnoredReason> {
        guard let equals = line.firstIndex(of: "=") else { return .failure(.unreadableLine) }
        let name = line[..<equals].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return .failure(.unreadableLine) }
        return script(name: name, parameters: parameters(String(line[line.index(after: equals)...])), origin: origin)
    }

     
    static func loonScript(_ line: String, origin: AdBlockLineOrigin) -> Result<AdBlockScript, AdBlockIgnoredReason> {
        guard let split = splitHead(line, count: 2) else { return .failure(.unreadableLine) }
        var declared = parameters(split.rest)
        declared.insert((key: "pattern", value: split.head[1]), at: 0)
        declared.insert((key: "type", value: split.head[0].lowercased()), at: 0)
         
         
        let tag = declared.first { $0.key == "tag" }?.value ?? ""
        let file = declared.first { $0.key == "script-path" }.flatMap { URL(string: $0.value)?.lastPathComponent } ?? ""
        return script(name: !tag.isEmpty ? tag : !file.isEmpty && file != "/" ? file : split.head[1], parameters: declared, origin: origin)
    }

     
     
     
    static func isNewerLoonSyntax(_ line: String) -> Bool {
        let words = line.split(separator: " ", maxSplits: 2).map { $0.lowercased() }
        guard words.count >= 2 else { return false }
        return (["request", "response"].contains(words[0]) && words[1] == "if")
            || (words[0] == "cron" && line.range(of: #" then "#, options: .caseInsensitive) != nil)
    }

     
     
    static func isLoonScriptLine(_ line: String) -> Bool {
        let first = line.split(separator: " ", maxSplits: 1).first.map { $0.lowercased() } ?? ""
        return ["http-request", "http-response", "cron", "generic", "network-changed", "dns"].contains(first)
    }
}
