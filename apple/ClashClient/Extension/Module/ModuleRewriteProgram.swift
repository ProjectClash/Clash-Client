#if os(iOS) || os(macOS)
import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 

 
struct ModuleRuleOrigin: Equatable, Sendable {
    let moduleName: String
    let section: String
    let line: Int

    var description: String { "\(moduleName) \(section) line \(line)" }
}

 
 
 
 
struct ModuleRequestURLs: Equatable, Sendable {
    let primary: String
    let alternates: [String]

    var all: [String] { [primary] + alternates }

    static func make(scheme: String, connectionHost: String, port: UInt16, head: ModuleHTTPRequestHead) -> ModuleRequestURLs {
        if let absolute = absoluteForm(head.target) { return ModuleRequestURLs(primary: absolute, alternates: []) }
        let path = head.target.hasPrefix("/") ? head.target : "/"
        let defaultPort: UInt16 = scheme == "https" ? 443 : 80
        let byConnection = scheme + "://" + authority(connectionHost.lowercased(), port, defaultPort: defaultPort) + path
        guard let field = head.headers.first("Host")?.trimmingCharacters(in: .whitespaces).lowercased(), !field.isEmpty,
              let named = ModuleConnectTarget.parse(field, defaultPort: defaultPort) else {
            return ModuleRequestURLs(primary: byConnection, alternates: [])
        }
        let byHeader = scheme + "://" + authority(named.host, named.port, defaultPort: defaultPort) + path
        return ModuleRequestURLs(primary: byHeader, alternates: byHeader == byConnection ? [] : [byConnection])
    }

     
     
     
     
     
    static func sent(_ url: String) -> ModuleRequestURLs {
        ModuleRequestURLs(primary: absoluteForm(url) ?? url, alternates: [])
    }

     
    private static func authority(_ host: String, _ port: UInt16, defaultPort: UInt16) -> String {
        let shown = host.contains(":") ? "[\(host)]" : host
        return port == defaultPort ? shown : "\(shown):\(port)"
    }

     
     
     
     
    private static func absoluteForm(_ target: String) -> String? {
        guard let separator = target.range(of: "://") else { return nil }
        let scheme = target[..<separator.lowerBound].lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }
        let rest = target[separator.upperBound...]
        let end = rest.firstIndex { "/?#".contains($0) } ?? rest.endIndex
        let written = rest[..<end].lowercased()
        let defaultPort: UInt16 = scheme == "https" ? 443 : 80
        let shown = ModuleConnectTarget.parse(written, defaultPort: defaultPort)
            .map { authority($0.host, $0.port, defaultPort: defaultPort) } ?? written
        let tail = rest[end...]
        return scheme + "://" + shown + (tail.hasPrefix("/") ? "" : "/") + tail
    }
}

 
struct ModuleLocalResponse: Equatable, Sendable {
    let status: Int
    let reason: String
     
     
     
    let headers: [ModuleHeaderField]
    let body: Data
    let location: String?

     
    var contentType: String? {
        headers.first { $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value
    }

    init(status: Int, reason: String, headers: [ModuleHeaderField], body: Data, location: String?) {
        self.status = status
        self.reason = reason
        self.headers = headers
        self.body = body
        self.location = location
    }

     
    init(status: Int, reason: String, contentType: String?, body: Data, location: String?) {
        self.init(status: status, reason: reason, headers: contentType.map { [ModuleHeaderField(name: "Content-Type", value: $0)] } ?? [],
                  body: body, location: location)
    }

     
     
     
    static let hopByHop: Set<String> = [
        "content-length", "transfer-encoding", "connection", "upgrade", "keep-alive", "proxy-connection", "te", "trailer",
    ]

     
     
     
     
     
     
     
     
    init?(answer: ModuleLocalAnswer) {
        guard Self.answers(answer) else { return nil }
        let body: Data
        switch answer.body {
        case .empty: body = Data()
        case .text(let text): body = Data(text.utf8)
        case .bytes(let bytes): body = bytes
        case .tinyGIF: body = Data(ModuleRejectResponses.tinyGIF)
        case .emptyJSONObject: body = Data("{}".utf8)
        case .emptyJSONArray: body = Data("[]".utf8)
        case .emptyVideo: body = Data(ModuleRejectResponses.emptyVideo)
        case .file: return nil
        }
        self.init(status: answer.status, reason: Self.reasonPhrase(answer.status),
                  headers: answer.headers.filter { !Self.hopByHop.contains($0.name.lowercased()) }, body: body, location: nil)
    }

     
     
    static func answers(_ answer: ModuleLocalAnswer) -> Bool {
         
         
        guard (200...999).contains(answer.status) else { return false }
        switch answer.body {
        case .empty, .text, .bytes, .tinyGIF, .emptyJSONObject, .emptyJSONArray, .emptyVideo: return true
        case .file: return false
        }
    }

     
     
    static func reasonPhrase(_ status: Int) -> String {
        switch status {
        case 100: return "Continue"
        case 101: return "Switching Protocols"
        case 200: return "OK"
        case 201: return "Created"
        case 202: return "Accepted"
        case 203: return "Non-Authoritative Information"
        case 204: return "No Content"
        case 205: return "Reset Content"
        case 206: return "Partial Content"
        case 300: return "Multiple Choices"
        case 301: return "Moved Permanently"
        case 302: return "Found"
        case 303: return "See Other"
        case 304: return "Not Modified"
        case 305: return "Use Proxy"
        case 307: return "Temporary Redirect"
        case 308: return "Permanent Redirect"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 402: return "Payment Required"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 406: return "Not Acceptable"
        case 407: return "Proxy Authentication Required"
        case 408: return "Request Timeout"
        case 409: return "Conflict"
        case 410: return "Gone"
        case 411: return "Length Required"
        case 412: return "Precondition Failed"
        case 413: return "Content Too Large"
        case 414: return "URI Too Long"
        case 415: return "Unsupported Media Type"
        case 416: return "Range Not Satisfiable"
        case 417: return "Expectation Failed"
        case 421: return "Misdirected Request"
        case 422: return "Unprocessable Content"
        case 426: return "Upgrade Required"
        case 429: return "Too Many Requests"
        case 500: return "Internal Server Error"
        case 501: return "Not Implemented"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        case 504: return "Gateway Timeout"
        case 505: return "HTTP Version Not Supported"
        default: return ""
        }
    }

     
     
    static func hasNoContent(_ status: Int) -> Bool {
        (100...199).contains(status) || status == 204 || status == 205 || status == 304
    }

     
     
     
    static let unwritable = Data("HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)

     
    struct Wire: Equatable, Sendable {
        let data: Data
         
         
         
         
        let isFallback: Bool
    }

    func bytes(method: String, keepAlive: Bool) -> Wire {
        var headers = ModuleHTTPHeaders()
        for field in self.headers { headers.add(field.name, field.value) }
        if let location { headers.add("Location", location) }
        let noContent = Self.hasNoContent(status)
        if !noContent { headers.add("Content-Length", String(body.count)) }
        headers.add("Connection", keepAlive ? "keep-alive" : "close")
        let head = ModuleHTTPResponseHead(version: .http11, status: status, reason: reason, headers: headers)
        guard let written = try? ModuleHTTPSerializer.head(head) else { return Wire(data: Self.unwritable, isFallback: true) }
        return Wire(data: written + (method == "HEAD" || noContent ? Data() : body), isFallback: false)
    }
}

 
enum ModuleRejectResponses {
     
     
    static let tinyGIF: [UInt8] = [
        0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00, 0xFF, 0xFF, 0xFF,
        0xFF, 0xFF, 0xFF, 0x21, 0xF9, 0x04, 0x01, 0x0A, 0x00, 0x01, 0x00, 0x2C, 0x00, 0x00, 0x00, 0x00,
        0x01, 0x00, 0x01, 0x00, 0x00, 0x02, 0x02, 0x4C, 0x01, 0x00, 0x3B,
    ]

     
     
     
     
    static let emptyVideo: [UInt8] = {
        func word(_ value: UInt32) -> [UInt8] { [UInt8(value >> 24), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)] }
        func box(_ kind: String, _ body: [UInt8]) -> [UInt8] { word(UInt32(8 + body.count)) + Array(kind.utf8) + body }
        let ftyp = box("ftyp", Array("isom".utf8) + word(0x200) + Array("isom".utf8) + Array("mp41".utf8))
        var mvhd = word(0)  
        mvhd += word(0) + word(0) + word(1_000) + word(0)  
        mvhd += word(0x0001_0000) + [0x01, 0x00, 0x00, 0x00] + word(0) + word(0)  
        mvhd += word(0x0001_0000) + word(0) + word(0) + word(0) + word(0x0001_0000) + word(0) + word(0) + word(0) + word(0x4000_0000)
        mvhd += Array(repeating: 0, count: 24) + word(1)  
        return ftyp + box("moov", box("mvhd", mvhd))
    }()

    private static let html = "text/html; charset=UTF-8"
    private static let json = "application/json; charset=UTF-8"

    static func response(for action: ModuleRewriteAction, location: String?) -> ModuleLocalResponse? {
        switch action {
        case .reject, .rejectNoDrop:
            return ModuleLocalResponse(status: 404, reason: "Not Found", contentType: html, body: Data(), location: nil)
        case .reject200:
            return ModuleLocalResponse(status: 200, reason: "OK", contentType: html, body: Data(), location: nil)
        case .rejectImg, .rejectTinyGif:
            return ModuleLocalResponse(status: 200, reason: "OK", contentType: "image/gif", body: Data(tinyGIF), location: nil)
        case .rejectDict:
            return ModuleLocalResponse(status: 200, reason: "OK", contentType: json, body: Data("{}".utf8), location: nil)
        case .rejectArray:
            return ModuleLocalResponse(status: 200, reason: "OK", contentType: json, body: Data("[]".utf8), location: nil)
        case .redirect302:
            return ModuleLocalResponse(status: 302, reason: "Found", contentType: nil, body: Data(), location: location)
        case .redirect307:
            return ModuleLocalResponse(status: 307, reason: "Temporary Redirect", contentType: nil, body: Data(), location: location)
         
         
        case .rejectDrop, .transparent, .header, .bodyReplace, .bodyJQ, .localAnswer, .requestBody, .json:
            return nil
        }
    }
}

 
 
 
struct ModuleRejectUpgrade {
    static let limit = 50
    static let window: TimeInterval = 30
     
     
    static let hostLimit = 256
    private static let upgraded: Set<String> = ["reject", "reject-img", "reject-tinygif"]
    private var hits: [String: [TimeInterval]] = [:]

     
     
     
    static func now() -> TimeInterval {
        Double(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
    }

     
    var hostsHeld: Int { hits.count }

     
     
    mutating func becomesDrop(kind: String, host: String, at: TimeInterval) -> Bool {
        guard Self.upgraded.contains(kind) else { return false }
        var recent = (hits[host] ?? []).filter { at - $0 < Self.window }
        recent.append(at)
        if hits[host] == nil, hits.count >= Self.hostLimit {
            hits = hits.filter { $0.value.contains { at - $0 < Self.window } }
            if hits.count >= Self.hostLimit,
               let stalest = hits.min(by: { ($0.value.last ?? -.infinity) < ($1.value.last ?? -.infinity) })?.key {
                hits[stalest] = nil
            }
        }
        hits[host] = Array(recent.suffix(Self.limit + 1))
        return recent.count > Self.limit
    }
}

enum ModuleRequestDecision: Equatable {
    case pass
     
    case respond(ModuleLocalResponse, ModuleRuleOrigin, kind: String)
     
    case drop(ModuleRuleOrigin, kind: String)
     
    case rewrite(to: String, ModuleRuleOrigin)
}

 
 
 
 
 
 
 
fileprivate final class ModuleCarriedRegexes {
    enum Carrier: Hashable {
         
        case rule(Int)
         
         
        case script(Int)
    }

     
    enum Stop {
        case timedOut
        case grewTooLarge
         
         
         
         
        case limit
    }

     
    struct Carried {
        let pattern: String
        let template: String
        var options: NSRegularExpression.Options = []
    }

    let budget: Int
     
     
    private let table: ModuleRegexTable
    private(set) var leftOut: [Carrier: String] = [:]
     
     
    private(set) var leftOutAtLoad = 0
     
    private(set) var overBudget = 0
     
    var held: Int { table.carriedCount }
    private(set) var regexTimeouts = 0
    private(set) var outputTooLarge = 0
    private var stops: [Carrier: Int] = [:]

    init(budget: Int, table: ModuleRegexTable = ModuleRegexTable()) {
        self.budget = budget
        self.table = table
    }

     
    static let forMemoryReason = "left out for memory: what was left as the rules were built holds no more regexes "
        + "for header and body rewrites"

    func runs(_ carrier: Carrier) -> Bool { leftOut[carrier] == nil }

     
     
    func leaveOutAtLoad(_ carrier: Carrier, because reason: String) {
        guard leftOut[carrier] == nil else { return }
        leftOutAtLoad += 1
        leftOut[carrier] = reason
    }

     
     
    func leaveOutOverBudget(_ carrier: Carrier, because reason: String) {
        guard leftOut[carrier] == nil else { return }
        overBudget += 1
        leftOut[carrier] = reason
    }

     
     
     
    func compile(_ pairs: [Carried], for carrier: Carrier) -> [(regex: NSRegularExpression, template: String)]? {
        if pairs.contains(where: { ModuleGateLiteral.usesBackReference($0.pattern) }) {
            leftOutAtLoad += 1
            leftOut[carrier] = ModuleGateLiteral.backReferenceReason
            return nil
        }
        if pairs.contains(where: { $0.template.utf8.count > ModuleRegexReplacement.maximumTemplateBytes }) {
            leftOutAtLoad += 1
            leftOut[carrier] = "a replacement it carries is longer than \(ModuleRegexReplacement.maximumTemplateBytes) bytes"
            return nil
        }
        let keys = pairs.map { ModuleRegexTable.CarriedKey(pattern: $0.pattern, options: $0.options.rawValue) }
         
         
        let fresh = Set(keys.filter { !table.carries($0) }).count
         
         
        let compiled = Set(keys.filter { !table.carries($0) && !table.holdsPinned($0) }).count
        guard held + fresh <= budget, table.room.take(Int64(compiled) * ModuleEngineBudget.chargedPerCompiledRegex) else {
            overBudget += 1
            leftOut[carrier] = Self.forMemoryReason
            return nil
        }
        switch table.carry(keys) {
        case .success(let regexes):
            return zip(regexes, pairs).map { ($0, $1.template) }
        case .failure(let error):
            table.room.give(Int64(compiled) * ModuleEngineBudget.chargedPerCompiledRegex)
            leftOutAtLoad += 1
            leftOut[carrier] = "a regex it carries does not compile: \(error.localizedDescription)"
            return nil
        }
    }

     
     
     
     
     
    func stopped(_ carrier: Carrier, _ why: Stop) {
        switch why {
        case .timedOut: regexTimeouts += 1
        case .grewTooLarge: outputTooLarge += 1
        case .limit: break
        }
        stops[carrier, default: 0] += 1
        guard stops[carrier, default: 0] >= ModuleGatedMatcher.timeoutsBeforeLeftOut, leftOut[carrier] == nil else { return }
        let reason: String
        switch why {
        case .timedOut, .grewTooLarge:
            reason = "a regex it carries ran past its deadline or grew the text past its cap "
                + "\(ModuleGatedMatcher.timeoutsBeforeLeftOut) times: left out for the rest of the run"
        case .limit:
            reason = "it stopped on a limit of its own \(ModuleGatedMatcher.timeoutsBeforeLeftOut) times: left out for the rest of the run"
        }
        leaveOutForTheRun(carrier, because: reason)
         
        if why == .grewTooLarge { leftOutForGrowth.insert(carrier) }
    }

     
    private(set) var leftOutForGrowth: Set<Carrier> = []

     
     
    private(set) var leftOutDuringRun: Set<Carrier> = []

    func leaveOutForTheRun(_ carrier: Carrier, because reason: String) {
        leftOut[carrier] = reason
        leftOutDuringRun.insert(carrier)
    }
}

struct ModuleBodyRule {
    let pairs: [(regex: NSRegularExpression, template: String)]
    let origin: ModuleRuleOrigin
     
    let index: Int
     
    fileprivate let carried: ModuleCarriedRegexes
}

 
 
 
 
 
 
 
 
struct ModuleRegexTemplate {
     
    let literalLength: Int
     
    let literalUTF8Length: Int
     
     
    private let named: [(group: Int, times: Int)]

    init(_ template: String, groupCount: Int) {
        let units = Array(template.utf16)
        var literal = 0
        var literalUTF8 = 0
        var times: [Int: Int] = [:]
        var i = 0
        let digits = String(max(0, groupCount)).count
        func digit(_ unit: UInt16) -> Int? { (0x30...0x39).contains(unit) ? Int(unit - 0x30) : nil }
        while i < units.count {
            if units[i] == 0x5C {
                if i + 1 < units.count {
                    literal += 1
                    literalUTF8 += ModuleRegexReplacement.Unit.utf8Length(of: units[i + 1])
                }
                i += 2
            } else if units[i] == 0x24, i + 1 < units.count, digit(units[i + 1]) != nil {
                i += 1
                var group = 0
                var taken = 0
                while i < units.count, taken < digits, let next = digit(units[i]) {
                    group = group * 10 + next
                    taken += 1
                    i += 1
                }
                times[group, default: 0] += 1
            } else {
                literal += 1
                literalUTF8 += ModuleRegexReplacement.Unit.utf8Length(of: units[i])
                i += 1
            }
        }
        literalLength = literal
        literalUTF8Length = literalUTF8
        named = times.sorted { $0.key < $1.key }.map { (group: $0.key, times: $0.value) }
    }

     
    func length(for match: NSTextCheckingResult) -> Int {
        named.reduce(literalLength) { total, entry in
            guard entry.group < match.numberOfRanges else { return total }
            let range = match.range(at: entry.group)
            return range.location == NSNotFound ? total : total + entry.times * range.length
        }
    }

     
    func length(for match: NSTextCheckingResult, in text: String, _ unit: ModuleRegexReplacement.Unit) -> Int {
        named.reduce(unit == .utf8 ? literalUTF8Length : literalLength) { total, entry in
            guard entry.group < match.numberOfRanges else { return total }
            let range = match.range(at: entry.group)
            return range.location == NSNotFound ? total : total + entry.times * unit.length(of: text, range)
        }
    }
}

 
 
 
 
 
 
enum ModuleRegexReplacement {
     
     
    static let maximumTemplateBytes = 4_096

     
     
     
     
    enum Unit: Equatable, Sendable {
        case utf8
        case utf16

         
         
         
        func length(of text: String, _ range: NSRange) -> Int {
            guard self == .utf8 else { return range.length }
            let start = String.Index(utf16Offset: range.location, in: text)
            let end = String.Index(utf16Offset: NSMaxRange(range), in: text)
            return text.utf8.distance(from: start, to: end)
        }

        func length(of text: String) -> Int {
            self == .utf8 ? text.utf8.count : text.utf16.count
        }

         
         
        static func utf8Length(of unit: unichar) -> Int {
            switch unit {
            case 0..<0x80: return 1
            case 0x80..<0x800: return 2
            case 0xD800...0xDFFF: return 2
            default: return 3
            }
        }
    }

    enum Result: Equatable {
         
        case replaced(String)
         
        case unchanged
         
        case timedOut
         
        case grewTooLarge
    }

    static func replace(_ regex: NSRegularExpression, in text: String, template: String, deadline: TimeInterval,
                        maximumLength: Int, unit: Unit) -> Result {
        let source = text as NSString
        let out = NSMutableString()
        let measure = ModuleRegexTemplate(template, groupCount: regex.numberOfCaptureGroups)
         
        var built = 0
        var copied = 0
        var changed = false
        var clock = ModuleRegexDeadline(deadline)
        var stoppedFor: Result?
        regex.enumerateMatches(in: text, options: [.reportProgress], range: NSRange(location: 0, length: source.length)) { match, _, stop in
            if let match {
                let gap = NSRange(location: copied, length: match.range.location - copied)
                let gapLength = unit.length(of: text, gap)
                guard built + gapLength + measure.length(for: match, in: text, unit) <= maximumLength else {
                    stoppedFor = .grewTooLarge
                    stop.pointee = true
                    return
                }
                out.append(source.substring(with: gap))
                let replacement = regex.replacementString(for: match, in: text, offset: 0, template: template)
                if !changed { changed = replacement != source.substring(with: match.range) }
                out.append(replacement)
                built += gapLength + unit.length(of: replacement)
                copied = NSMaxRange(match.range)
            }
            if clock.isPast() {
                stoppedFor = .timedOut
                stop.pointee = true
            }
        }
        if let stoppedFor { return stoppedFor }
        guard changed else { return .unchanged }
        let tail = NSRange(location: copied, length: source.length - copied)
        guard built + unit.length(of: text, tail) <= maximumLength else { return .grewTooLarge }
        out.append(source.substring(with: tail))
        return .replaced(out as String)
    }
}

 
enum ModuleBodyRewriteOutcome: Equatable {
     
    case rewritten(Data)
     
     
     
    case unchanged
     
    case notText
}

enum ModuleBodyRewrite {
     
     
     
     
     
     
    static func deadline(forUTF8Length length: Int) -> TimeInterval {
        ModuleGatedMatcher.evaluationDeadline + Double(length) / 4_096 * 0.001
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func apply(_ rules: [ModuleBodyRule], to body: Data, budget: inout ModuleRequestBudget) -> ModuleBodyRewriteOutcome {
         
        let reading = ModuleRequestBudget.threadNanoseconds()
        let decoded = String(data: body, encoding: .utf8)
        budget.charge(ModuleRequestBudget.threadNanoseconds() &- reading)
        guard var text = decoded else { return .notText }
        let maximumLength = max(body.count, ModuleBodyLimits.current.defaultBytes)
        var changed = false
        for rule in rules {
            for pair in rule.pairs where rule.carried.runs(.rule(rule.index)) {
                guard !budget.isSpent else {
                    budget.noteStop()
                    continue
                }
                let own = deadline(forUTF8Length: text.utf8.count)
                let allowed = min(own, budget.remainingSeconds)
                let started = ModuleRequestBudget.threadNanoseconds()
                let result = ModuleRegexReplacement.replace(pair.regex, in: text, template: pair.template, deadline: allowed,
                                                             maximumLength: maximumLength, unit: .utf8)
                budget.charge(ModuleRequestBudget.threadNanoseconds() &- started)
                switch result {
                case .replaced(let replaced):
                    text = replaced
                    changed = true
                case .unchanged:
                    break
                case .timedOut where allowed < own:
                    budget.noteStop()
                case .timedOut:
                    rule.carried.stopped(.rule(rule.index), .timedOut)
                case .grewTooLarge:
                    rule.carried.stopped(.rule(rule.index), .grewTooLarge)
                }
            }
        }
        guard changed else { return .unchanged }
        let writing = ModuleRequestBudget.threadNanoseconds()
        let written = Data(text.utf8)
        budget.charge(ModuleRequestBudget.threadNanoseconds() &- writing)
        return .rewritten(written)
    }

     
     
     
    static func apply(_ rules: [ModuleBodyRule], to body: Data) -> ModuleBodyRewriteOutcome {
        var budget = ModuleRequestBudget.unlimited
        return apply(rules, to: body, budget: &budget)
    }
}

 
 
struct ModuleHeaderRewrite: Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        case applied
         
         
        case timedOut
         
         
        case grewTooLarge
         
        case skipped(String)
         
         
         
        case budgetSpent
    }

    let origin: ModuleRuleOrigin
     
    let what: String
    let outcome: Outcome
}

extension ModuleRewriteAction {
     
    var spelling: String {
        switch self {
        case .reject: return "reject"
        case .reject200: return "reject-200"
        case .rejectImg: return "reject-img"
        case .rejectTinyGif: return "reject-tinygif"
        case .rejectDict: return "reject-dict"
        case .rejectArray: return "reject-array"
        case .rejectDrop: return "reject-drop"
        case .rejectNoDrop: return "reject-no-drop"
        case .redirect302: return "302"
        case .redirect307: return "307"
        case .transparent: return "header"
        case .header(let phase, let operation, _, _): return "\(phase.rawValue) header-\(operation.rawValue)"
        case .bodyReplace(let phase, _): return "\(phase.rawValue) body"
        case .bodyJQ(let phase, _, _): return "\(phase.rawValue) jq"
        case .localAnswer: return "mock"
        case .requestBody: return "request mock"
        case .json(let phase, _): return "\(phase.rawValue) json"
        }
    }
}

 
 
 
 
 
struct ModuleHeaderStep {
    let operation: ModuleHeaderOperation
    let name: String
     
    let value: String?
    let origin: ModuleRuleOrigin
    let family: ModuleFormat
     
     
    let unwritable: String?
     
    fileprivate let rule: Int
    fileprivate let regex: NSRegularExpression?

     
    var what: String { operation == .replaceHead ? "request-header" : "\(operation.rawValue) \(name)" }
}

 
 
 
struct ModuleBodyStep {
    enum Work {
         
        case replace(ModuleBodyRule)
         
        case json(ModuleJSONRewrite.Compiled)
         
        case jq(ModuleJQ.Program)
         
        case body(Data, contentType: String?)
         
         
         
         
         
         
        case nothing
    }

    let work: Work
    let origin: ModuleRuleOrigin
     
     
    let family: ModuleFormat
     
     
    let writtenFor: ModuleScriptFamily
     
    fileprivate let rule: Int
    fileprivate let carried: ModuleCarriedRegexes

     
    var what: String {
        switch work {
        case .replace: return "body"
        case .json: return "json"
        case .jq: return "jq"
        case .body: return "mock"
        case .nothing: return "nothing"
        }
    }

     
    var runs: Bool { carried.runs(.rule(rule)) }

     
     
    func stoppedOnItsOwnLimit() { carried.stopped(.rule(rule), .limit) }
#if false || MODULES_ENGINE_TESTS

     
    static func running(_ work: Work, origin: ModuleRuleOrigin, family: ModuleFormat,
                        writtenFor: ModuleScriptFamily? = nil) -> ModuleBodyStep {
        ModuleBodyStep(work: work, origin: origin, family: family, writtenFor: writtenFor ?? ModuleScriptFamily(format: family),
                       rule: 0, carried: ModuleCarriedRegexes(budget: 0))
    }
#endif


}

 
 
 
 
 
 
 
struct ModuleRequestPlan {
    var headerSteps: [ModuleHeaderStep] = []
    var headerRewrites: [ModuleHeaderRewrite] = []
    var requestHeaders: ModuleHTTPHeaders?
     
    var requestLine: (method: String, target: String)?
    var ending: ModuleRequestDecision?
    var bodySteps: [ModuleBodyStep] = []
}

 
 
 
struct ModuleResponsePlan {
    var headerSteps: [ModuleHeaderStep] = []
    var headerRewrites: [ModuleHeaderRewrite] = []
    var responseHeaders: ModuleHTTPHeaders?
    var bodySteps: [ModuleBodyStep] = []
}

 
 
 
struct ModuleResponseCandidates {
     
     
     
    fileprivate struct Hit {
        let rule: Int
        let gate: ModuleConditionEvaluation.GateMatch?
    }

    fileprivate var headers: [Hit] = []
    fileprivate var bodies: [Hit] = []
     
    private(set) var readsRequestHeaders = false

    static let none = ModuleResponseCandidates()

    fileprivate init(headers: [Hit] = [], bodies: [Hit] = [], readsRequestHeaders: Bool = false) {
        self.headers = headers
        self.bodies = bodies
        self.readsRequestHeaders = readsRequestHeaders
    }

     
    var readsBody: Bool { !bodies.isEmpty }

     
    var isEmpty: Bool { headers.isEmpty && bodies.isEmpty }

     
    var bodyRuleCount: Int { bodies.count }

     
    func withoutBodies() -> ModuleResponseCandidates {
        ModuleResponseCandidates(headers: headers, bodies: [], readsRequestHeaders: readsRequestHeaders)
    }
}

final class ModuleRewriteProgram {
     
     
     
     
     
     
    struct RunLeftOut: Hashable, Sendable {
        enum Kind: String, Sendable {
            case url, header, body, script
        }

        let moduleID: String
        let kind: Kind
        let section: String
        let line: Int
        let pattern: String
    }

     
     
     
    struct Input {
        let module: ModuleGlobalManifest.Module
        let format: ModuleFormat
        let rewriteRules: [ModuleRewriteRule]
        let scripts: [ModuleScript]
         
        var writtenFor: ModuleScriptFamily

        init(module: ModuleGlobalManifest.Module, format: ModuleFormat, rewriteRules: [ModuleRewriteRule], scripts: [ModuleScript],
             writtenFor: ModuleScriptFamily? = nil) {
            self.module = module
            self.format = format
            self.rewriteRules = rewriteRules
            self.scripts = scripts
            self.writtenFor = writtenFor ?? ModuleScriptFamily(format: format)
        }
    }

     
     
     
    private enum Stage: Int {
        case header, url, body
    }

    private struct HeaderAction {
        let phase: ModuleRewritePhase
        let operation: ModuleHeaderOperation
        let name: String
        let arguments: [String]
        var regex: NSRegularExpression?

         
         
        var runsARegex: Bool { operation == .replaceRegex || operation == .replaceHead }
    }

    private enum Ending {
         
        case action(ModuleRewriteAction)
        case answer(ModuleLocalAnswer)
    }

    private enum BodyDraft {
        case replace([ModuleReplacementPair])
         
        case jq(expression: String, sha256: String?)
        case ready(ModuleBodyStep.Work)
    }

    private struct BodyAction {
        let phase: ModuleRewritePhase
        var draft: BodyDraft
    }

     
     
     
    private struct Extras {
        var condition: ModuleConditionEvaluation.Compiled?
        var headers: [HeaderAction] = []
         
         
        var answerHeaders: [HeaderAction] = []
        var bodies: [BodyAction] = []
    }

     
     
     
    private struct Rule {
        var module: Int32
        var section: Int32
        var line: Int32
        var extras: Int32 = -1
        var headerEntry: Int32 = -1
        var urlEntry: Int32 = -1
        var bodyEntry: Int32 = -1
        var flags: Flags = []

        struct Flags: OptionSet {
            let rawValue: UInt16
             
            static let phased = Flags(rawValue: 1 << 0)
             
            static let conditioned = Flags(rawValue: 1 << 1)
            static let readsRequestHeaders = Flags(rawValue: 1 << 2)
            static let requestHeaders = Flags(rawValue: 1 << 3)
            static let responseHeaders = Flags(rawValue: 1 << 4)
            static let ending = Flags(rawValue: 1 << 5)
            static let requestBodies = Flags(rawValue: 1 << 6)
            static let responseBodies = Flags(rawValue: 1 << 7)
        }

        var stage: Stage {
            flags.contains(.requestHeaders) || flags.contains(.responseHeaders) ? .header : flags.contains(.ending) ? .url : .body
        }

        var kind: RunLeftOut.Kind {
            switch stage {
            case .header: return .header
            case .url: return .url
            case .body: return .body
            }
        }

        func hasHeaders(_ phase: ModuleRewritePhase) -> Bool { flags.contains(phase == .request ? .requestHeaders : .responseHeaders) }
        func hasBodies(_ phase: ModuleRewritePhase) -> Bool { flags.contains(phase == .request ? .requestBodies : .responseBodies) }
    }

     
     
     
    private static let endingActions: [ModuleRewriteAction] = [
        .reject, .reject200, .rejectImg, .rejectTinyGif, .rejectDict, .rejectArray, .rejectDrop, .rejectNoDrop,
    ]
    private static let payloadCode = UInt8(endingActions.count)

    private struct ScriptRule {
        let script: ModuleScript
        let moduleID: String
        let format: ModuleFormat
        let writtenFor: ModuleScriptFamily
        let bodyFile: URL?
        let origin: ModuleRuleOrigin
         
         
        var condition: ModuleConditionEvaluation.Compiled?
    }

     
     
     
     
     
     
     
     
     
    static let maximumCarriedRegexes = Int.max

     
     
     
     
     
     
    static let maximumReadValueBytes = 64 << 10

     
     
     
    private static let protectedHeaders: Set<String> = [
        "content-length", "transfer-encoding", "connection", "upgrade", "keep-alive", "proxy-connection", "te", "trailer",
    ]

     
     
    private static let framingHeaders: Set<String> = ["content-length", "transfer-encoding"]

     
    static let empty = ModuleRewriteProgram(inputs: [], scriptFile: { _, _ in nil })

    private let rules: [Rule]
    private let extras: [Extras]
     
    private let endingCodes: [UInt8]
    private let endingPayloads: [Int32: Ending]
    private let modules: [(id: String, name: String, family: ModuleFormat, writtenFor: ModuleScriptFamily)]
    private let sections: [String]
    private let headerEntries: [Int32]
    private let urlEntries: [Int32]
    private let bodyEntries: [Int32]
    private let scripts: [ScriptRule]
    private let headerMatcher: ModuleGatedMatcher
    private let urlMatcher: ModuleGatedMatcher
    private let bodyMatcher: ModuleGatedMatcher
    private let scriptMatcher: ModuleGatedMatcher
    private let carried: ModuleCarriedRegexes
     
     
    private let table: ModuleRegexTable
     
     
     
    let heldValueBytes: Int
     
     
     
     
    let unsupported: [ModuleRuleOrigin]
     
     
    private let handedGrowth: Set<RunLeftOut>

     
     
     
    convenience init(modules: [(module: ModuleGlobalManifest.Module, ir: ModuleIR)], leavingOut runLeftOut: Set<RunLeftOut> = [],
                     grownTooLarge: Set<RunLeftOut> = [], room: Int64? = nil,
                     scriptFile: (String, String) -> URL?, moduleFile: (String, String) -> URL? = { _, _ in nil }) {
        self.init(inputs: modules.map { Input(module: $0.module, format: $0.ir.manifest.format, rewriteRules: $0.ir.rewriteRules,
                                                scripts: $0.ir.scripts,
                                                writtenFor: ModuleScriptFamily(format: $0.ir.manifest.format, sourceURL: $0.ir.manifest.sourceURL)) },
                  leavingOut: runLeftOut, grownTooLarge: grownTooLarge, scriptFile: scriptFile, moduleFile: moduleFile, room: room)
    }

     
     
     
    convenience init(published: [ModulePublishedModule], leavingOut runLeftOut: Set<RunLeftOut> = [],
                     grownTooLarge: Set<RunLeftOut> = [],
                     scriptFile: (String, String) -> URL?, moduleFile: (String, String) -> URL? = { _, _ in nil },
                     room: Int64? = nil) {
        self.init(inputs: published.map { Input(module: $0.module, format: $0.ir.format, rewriteRules: $0.ir.rewriteRules,
                                                  scripts: $0.ir.scripts, writtenFor: $0.ir.writtenFor) },
                  leavingOut: runLeftOut, grownTooLarge: grownTooLarge, scriptFile: scriptFile, moduleFile: moduleFile,
                  room: room)
    }

     
    private struct Draft {
        var pattern: String
        var written: ModuleCondition?
        var extras = Extras()
        var ending: Ending?
        var builtLeftOut: String?
    }

     
     
     
     
    private struct Drafts {
        static let noEnding: UInt8 = 0xFF
        private(set) var patterns: [String] = []
        private var endingCodes: [UInt8] = []
        private var rest: [Int: Draft] = [:]

        init(capacity: Int) {
            patterns.reserveCapacity(capacity)
            endingCodes.reserveCapacity(capacity)
        }

        mutating func append(_ draft: Draft) {
            patterns.append(draft.pattern)
            endingCodes.append(Self.noEnding)
            self[patterns.count - 1] = draft
        }

        subscript(index: Int) -> Draft {
            get {
                var draft = rest[index] ?? Draft(pattern: "", written: nil)
                draft.pattern = patterns[index]
                let code = endingCodes[index]
                if code != Self.noEnding, code != ModuleRewriteProgram.payloadCode {
                    draft.ending = .action(ModuleRewriteProgram.endingActions[Int(code)])
                }
                return draft
            }
            set {
                patterns[index] = newValue.pattern
                var more = newValue
                more.pattern = ""
                if case .action(let action)? = newValue.ending, let code = ModuleRewriteProgram.endingActions.firstIndex(of: action) {
                    endingCodes[index] = UInt8(code)
                    more.ending = nil
                } else {
                    endingCodes[index] = newValue.ending == nil ? Self.noEnding : ModuleRewriteProgram.payloadCode
                }
                let extras = more.extras
                let plain = more.written == nil && more.ending == nil && more.builtLeftOut == nil && extras.condition == nil
                    && extras.headers.isEmpty && extras.answerHeaders.isEmpty && extras.bodies.isEmpty
                rest[index] = plain ? nil : more
            }
        }
    }

     
     
     
    init(inputs: [Input], leavingOut runLeftOut: Set<RunLeftOut> = [], grownTooLarge: Set<RunLeftOut> = [],
         scriptFile: (String, String) -> URL?, moduleFile: (String, String) -> URL? = { _, _ in nil },
         room roomBytes: Int64? = nil) {
         
         
         
        #if os(iOS)
        let room = ModuleProgramRoom(roomBytes, probe: { ModuleEngineBudget.onADevice ? ModuleEngineBudget.headroomForShare() : nil })
        #else
        let room = ModuleProgramRoom(roomBytes)
        #endif
        var rules: [Rule] = []
        var drafts = Drafts(capacity: inputs.reduce(0) { $0 + $1.rewriteRules.count })
        var modules: [(id: String, name: String, family: ModuleFormat, writtenFor: ModuleScriptFamily)] = []
        var sections: [String] = []
        var sectionIndex: [String: Int32] = [:]
        var scriptRules: [(String, ScriptRule)] = []
        var unsupported: [ModuleRuleOrigin] = []
        var held = Held()
        rules.reserveCapacity(inputs.reduce(0) { $0 + $1.rewriteRules.count })
        for input in inputs {
            let module = Int32(modules.count)
            modules.append((input.module.id, input.module.name, input.format, input.writtenFor))
            for rewrite in input.rewriteRules {
                let section: Int32
                if let known = sectionIndex[rewrite.origin.section] {
                    section = known
                } else {
                    section = Int32(sections.count)
                    sections.append(rewrite.origin.section)
                    sectionIndex[rewrite.origin.section] = section
                }
                var rule = Rule(module: module, section: section, line: Int32(clamping: rewrite.origin.line))
                var draft = Draft(pattern: rewrite.pattern, written: rewrite.condition)
                if rewrite.phase != nil { rule.flags.insert(.phased) }
                if rewrite.condition != nil { rule.flags.insert(.conditioned) }
                guard Self.read(rewrite, into: &rule, &draft, moduleID: input.module.id, moduleFile: moduleFile, held: &held) else {
                    unsupported.append(ModuleRuleOrigin(moduleName: input.module.name, section: rewrite.origin.section,
                                                         line: rewrite.origin.line))
                    continue
                }
                rules.append(rule)
                drafts.append(draft)
            }
            for script in input.scripts {
                let origin = ModuleRuleOrigin(moduleName: input.module.name, section: script.origin.section, line: script.origin.line)
                scriptRules.append((script.pattern, ScriptRule(script: script, moduleID: input.module.id, format: input.format,
                                                               writtenFor: input.writtenFor,
                                                               bodyFile: script.bodySHA256.flatMap { scriptFile(input.module.id, $0) },
                                                               origin: origin)))
            }
        }
         
         
         
         
         
        let table = ModuleRegexTable(maximumPinned: ModuleGatedMatcher.maximumPinned, room: room)
        func matcher(_ patterns: [String]) -> ModuleGatedMatcher {
            ModuleGatedMatcher(patterns: patterns, table: table)
        }
        let headerEntries = rules.indices.filter { rules[$0].stage == .header }.map(Int32.init)
        for (entry, index) in headerEntries.enumerated() { rules[Int(index)].headerEntry = Int32(entry) }
        let headerMatcher = matcher(headerEntries.map { Self.matched(drafts[Int($0)].pattern) })
        func outOfHeaders(_ index: Int) -> Bool { rules[index].headerEntry >= 0 && headerMatcher.leftOut[Int(rules[index].headerEntry)] != nil }
        let urlEntries = rules.indices.filter { rules[$0].flags.contains(.ending) && !outOfHeaders($0) }.map(Int32.init)
        for (entry, index) in urlEntries.enumerated() { rules[Int(index)].urlEntry = Int32(entry) }
        let urlMatcher = matcher(urlEntries.map { Self.matched(drafts[Int($0)].pattern) })
        func outOfURLs(_ index: Int) -> Bool { rules[index].urlEntry >= 0 && urlMatcher.leftOut[Int(rules[index].urlEntry)] != nil }
        let bodyEntries = rules.indices.filter { index in
            (rules[index].hasBodies(.request) || rules[index].hasBodies(.response)) && !outOfHeaders(index) && !outOfURLs(index)
        }.map(Int32.init)
        for (entry, index) in bodyEntries.enumerated() { rules[Int(index)].bodyEntry = Int32(entry) }
        let bodyMatcher = matcher(bodyEntries.map { Self.matched(drafts[Int($0)].pattern) })
        let scriptMatcher = matcher(scriptRules.map(\.0))
        func entries(_ rule: Rule) -> [(matcher: ModuleGatedMatcher, entry: Int)] {
            [(headerMatcher, rule.headerEntry), (urlMatcher, rule.urlEntry), (bodyMatcher, rule.bodyEntry)].compactMap { pair in
                pair.1 >= 0 ? (pair.0, Int(pair.1)) : nil
            }
        }
        func inMatchers(_ index: Int) -> Bool { entries(rules[index]).allSatisfy { $0.matcher.leftOut[$0.entry] == nil } }
        let carried = ModuleCarriedRegexes(budget: Self.maximumCarriedRegexes, table: table)
         
        var handedGrowth = Set<RunLeftOut>()
        if !runLeftOut.isEmpty {
            let reason = "it stopped \(ModuleGatedMatcher.timeoutsBeforeLeftOut) times earlier in this run: left out for the rest of it"
            for index in rules.indices {
                let rule = rules[index]
                let key = RunLeftOut(moduleID: modules[Int(rule.module)].id, kind: rule.kind, section: sections[Int(rule.section)],
                                     line: Int(rule.line), pattern: drafts[index].pattern)
                guard runLeftOut.contains(key) else { continue }
                for place in entries(rule) { place.matcher.leaveOutForTheRun(place.entry, because: reason) }
                carried.leaveOutForTheRun(.rule(index), because: reason)
                if grownTooLarge.contains(key) { handedGrowth.insert(key) }
            }
            for index in scriptRules.indices where runLeftOut.contains(
                RunLeftOut(moduleID: scriptRules[index].1.moduleID, kind: .script, section: scriptRules[index].1.origin.section,
                           line: scriptRules[index].1.origin.line, pattern: scriptRules[index].0)) {
                scriptMatcher.leaveOutForTheRun(index, because: reason)
            }
        }
         
         
        for index in rules.indices {
            if let written = drafts[index].written {
                do {
                    _ = try ModuleConditionEvaluation.compile(written, gate: Self.gate(drafts[index].pattern)) { _ in Self.placeholder }
                } catch let refusal as ModuleConditionEvaluation.Refusal {
                    drafts[index].builtLeftOut = drafts[index].builtLeftOut ?? "its condition cannot be read here: \(refusal.reason)"
                } catch {
                    drafts[index].builtLeftOut = drafts[index].builtLeftOut ?? "its condition cannot be read here"
                }
            }
            if let why = drafts[index].builtLeftOut { carried.leaveOutAtLoad(.rule(index), because: why) }
        }
         
         
         
        let order = rules.indices.sorted { (rules[$0].stage.rawValue, $0) < (rules[$1].stage.rawValue, $1) }
        for index in order {
            guard inMatchers(index), carried.runs(.rule(index)) else { continue }
            let pattern = drafts[index].pattern
            var pairs: [ModuleCarriedRegexes.Carried] = []
            if let written = drafts[index].written {
                _ = try? ModuleConditionEvaluation.compile(written, gate: Self.gate(pattern)) { regex in
                    pairs.append(.init(pattern: regex, template: ""))
                    return Self.placeholder
                }
            }
            let extras = drafts[index].extras
            for action in extras.headers + extras.answerHeaders where action.runsARegex && action.arguments.count >= 2 {
                pairs.append(.init(pattern: action.arguments[0], template: action.arguments[1]))
            }
             
            let options: NSRegularExpression.Options = modules[Int(rules[index].module)].family == .surge ? [.anchorsMatchLines] : []
            for action in extras.bodies {
                if case .replace(let written) = action.draft {
                    pairs += written.map { .init(pattern: $0.search, template: $0.replacement, options: options) }
                }
            }
            if pairs.isEmpty {
                drafts[index].extras.condition = drafts[index].written.flatMap {
                    try? ModuleConditionEvaluation.compile($0, gate: Self.gate(pattern)) { _ in Self.placeholder }
                }
                continue
            }
            guard let compiled = carried.compile(pairs, for: .rule(index)) else { continue }
            var next = compiled.makeIterator()
            if let written = drafts[index].written {
                drafts[index].extras.condition = try? ModuleConditionEvaluation.compile(written, gate: Self.gate(pattern)) { _ in
                    guard let regex = next.next()?.regex else { throw ModuleConditionEvaluation.Refusal(reason: "a regex is missing") }
                    return regex
                }
            }
            func take(_ actions: inout [HeaderAction]) {
                for position in actions.indices where actions[position].runsARegex && actions[position].arguments.count >= 2 {
                    actions[position].regex = next.next()?.regex
                }
            }
            take(&drafts[index].extras.headers)
            take(&drafts[index].extras.answerHeaders)
            for position in drafts[index].extras.bodies.indices {
                guard case .replace(let written) = drafts[index].extras.bodies[position].draft else { continue }
                let made = written.compactMap { _ in next.next() }
                drafts[index].extras.bodies[position].draft = .ready(.replace(ModuleBodyRule(
                    pairs: made, origin: Self.origin(rules[index], modules, sections), index: index, carried: carried)))
            }
        }
         
         
         
         
         
         
        for index in scriptRules.indices {
            guard let written = scriptRules[index].1.script.condition, scriptMatcher.leftOut[index] == nil else { continue }
            let pattern = scriptRules[index].0
            let condition = Self.guarded(written, by: pattern)
            do {
                _ = try ModuleConditionEvaluation.compile(condition, gate: Self.gate(pattern)) { _ in Self.placeholder }
            } catch {
                let why = (error as? ModuleConditionEvaluation.Refusal).map { #": \#($0.reason)"# } ?? ""
                carried.leaveOutAtLoad(.script(index), because: #"its condition cannot be read here"# + why)
                continue
            }
            var pairs: [ModuleCarriedRegexes.Carried] = []
            _ = try? ModuleConditionEvaluation.compile(condition, gate: Self.gate(pattern)) { regex in
                pairs.append(.init(pattern: regex, template: ""))
                return Self.placeholder
            }
            var regexes: [NSRegularExpression] = []
            if !pairs.isEmpty {
                guard let compiled = carried.compile(pairs, for: .script(index)) else { continue }
                regexes = compiled.map(\.regex)
            }
            var next = regexes.makeIterator()
            guard let compiled = try? ModuleConditionEvaluation.compile(condition, gate: Self.gate(pattern), compile: { _ in
                guard let regex = next.next() else { throw ModuleConditionEvaluation.Refusal(reason: #"a regex is missing"#) }
                return regex
            }) else {
                carried.leaveOutAtLoad(.script(index), because: #"its condition cannot be read here"#)
                continue
            }
             
            if case .gate = compiled { continue }
            scriptRules[index].1.condition = compiled
        }
         
         
         
        var jq = JQBuild(room: room)
        for index in rules.indices {
            var draft = drafts[index]
            let steps = draft.extras.bodies.compactMap { action -> (expression: String, sha256: String?)? in
                if case .jq(let expression, let sha256) = action.draft { return (expression, sha256) }
                return nil
            }
            guard !steps.isEmpty else { continue }
            var made: [ModuleJQ.Program] = []
            if inMatchers(index), carried.runs(.rule(index)), draft.written == nil || draft.extras.condition != nil {
                switch jq.programs(steps, moduleID: modules[Int(rules[index].module)].id, moduleFile: moduleFile) {
                case .success(let programs):
                    made = programs
                case .failure(let refusal):
                    if refusal.overBudget {
                        carried.leaveOutOverBudget(.rule(index), because: refusal.reason)
                    } else {
                        carried.leaveOutAtLoad(.rule(index), because: refusal.reason)
                    }
                }
            }
            var next = made.makeIterator()
            for position in draft.extras.bodies.indices {
                guard case .jq = draft.extras.bodies[position].draft else { continue }
                draft.extras.bodies[position].draft = next.next().map { .ready(.jq($0)) } ?? .ready(Self.leftOutWork)
            }
            drafts[index] = draft
        }
        held.bytes += jq.bytes
         
        var extrasTable: [Extras] = []
        var endingCodes = [UInt8](repeating: 0, count: urlEntries.count)
        var endingPayloads: [Int32: Ending] = [:]
        for index in rules.indices {
            var draft = drafts[index]
            if draft.written != nil {
                 
                if draft.extras.condition == nil, carried.runs(.rule(index)), inMatchers(index) {
                    carried.leaveOutAtLoad(.rule(index), because: "its condition cannot be read here")
                }
                 
                if case .gate? = draft.extras.condition {
                    draft.extras.condition = nil
                    rules[index].flags.remove(.conditioned)
                }
            }
            if let condition = draft.extras.condition, ModuleConditionEvaluation.readsRequestHeaders(condition) {
                rules[index].flags.insert(.readsRequestHeaders)
            }
             
            for position in draft.extras.bodies.indices {
                if case .replace = draft.extras.bodies[position].draft {
                    draft.extras.bodies[position].draft = .ready(.replace(ModuleBodyRule(
                        pairs: [], origin: Self.origin(rules[index], modules, sections), index: index, carried: carried)))
                }
            }
            let extras = draft.extras
            if extras.condition != nil || !extras.headers.isEmpty || !extras.answerHeaders.isEmpty || !extras.bodies.isEmpty {
                rules[index].extras = Int32(extrasTable.count)
                extrasTable.append(extras)
            }
            if let ending = draft.ending, rules[index].urlEntry >= 0 {
                let entry = Int(rules[index].urlEntry)
                if case .action(let action) = ending, let code = Self.endingActions.firstIndex(of: action) {
                    endingCodes[entry] = UInt8(code)
                } else {
                    endingCodes[entry] = Self.payloadCode
                    endingPayloads[Int32(entry)] = ending
                }
            }
        }
        drafts = Drafts(capacity: 0)
        table.settle()
        self.table = table
        self.rules = rules
        self.extras = extrasTable
        self.endingCodes = endingCodes
        self.endingPayloads = endingPayloads
        self.modules = modules
        self.sections = sections
        self.headerEntries = headerEntries
        self.urlEntries = urlEntries
        self.bodyEntries = bodyEntries
        self.scripts = scriptRules.map(\.1)
        self.headerMatcher = headerMatcher
        self.urlMatcher = urlMatcher
        self.bodyMatcher = bodyMatcher
        self.scriptMatcher = scriptMatcher
        self.carried = carried
        self.heldValueBytes = held.bytes
        self.handedGrowth = handedGrowth
        self.unsupported = unsupported
    }

     
     
     
    private struct Held {
        var bytes = 0
        var valueText = 0
    }

     
     
    private struct JQRefusal: Error {
        let reason: String
        var overBudget = false
    }

     
     
     
     
     
     
     
     
     
     
    static let maximumHeldJQBytes = Int.max

     
    static var carriedForMemoryReason: String { ModuleCarriedRegexes.forMemoryReason }

     
    static let jqOverBudgetReason = "left out for memory: what was left as the rules were built holds no more jq programs"

     
     
     
     
     
     
     
     
     
     
     
     
     
    private struct JQBuild {
        private var byFile: [String: ModuleJQ.Program] = [:]
        private var byText: [String: ModuleJQ.Program] = [:]
        private var missing: [String: String] = [:]
        private var unreadable: [String: String] = [:]
        private var charged = Set<String>()
        private(set) var bytes = 0
         
        let room: ModuleProgramRoom

        private enum Found {
            case program(ModuleJQ.Program)
            case source(String)
        }

         
         
        mutating func programs(_ steps: [(expression: String, sha256: String?)], moduleID: String,
                               moduleFile: (String, String) -> URL?) -> Result<[ModuleJQ.Program], JQRefusal> {
            var found: [(key: String, found: Found)] = []
            for step in steps {
                let key: String
                if let sha256 = step.sha256?.lowercased() {
                    key = "file " + sha256
                    if let program = byFile[sha256] {
                        found.append((key, .program(program)))
                        continue
                    }
                    if let why = unreadable[sha256] ?? missing[moduleID + " " + sha256] { return .failure(JQRefusal(reason: why)) }
                    guard let text = ModuleRewriteProgram.jqExpression(fileSHA256: sha256, at: moduleFile(moduleID, sha256)) else {
                        let why = "its jq file \(sha256) is not there, or holds other bytes than its name says"
                        missing[moduleID + " " + sha256] = why
                        return .failure(JQRefusal(reason: why))
                    }
                    found.append((key, .source(text)))
                } else {
                    key = "text " + step.expression
                    if let program = byText[step.expression] {
                        found.append((key, .program(program)))
                        continue
                    }
                    if let why = unreadable[key] { return .failure(JQRefusal(reason: why)) }
                    found.append((key, .source(step.expression)))
                }
            }
             
            var fresh = Set<String>()
            var cost = 0
            for (key, item) in found where !charged.contains(key) && fresh.insert(key).inserted {
                switch item {
                case .program(let program): cost += ModuleRewriteProgram.heldBytes(ofJQ: program.source)
                case .source(let text): cost += ModuleRewriteProgram.heldBytes(ofJQ: text)
                }
            }
            guard bytes + cost <= ModuleRewriteProgram.maximumHeldJQBytes, room.take(Int64(cost)) else {
                return .failure(JQRefusal(reason: ModuleRewriteProgram.jqOverBudgetReason, overBudget: true))
            }
            var programs: [ModuleJQ.Program] = []
            for (key, item) in found {
                switch item {
                case .program(let program):
                    programs.append(program)
                case .source(let text):
                    let sha256 = key.hasPrefix("file ") ? String(key.dropFirst(5)) : nil
                    if let program = sha256.flatMap({ byFile[$0] }) ?? (sha256 == nil ? byText[text] : nil) {
                        programs.append(program)
                        continue
                    }
                    do {
                        let program = try ModuleJQ.parseOnLargeStack(text)
                        if let sha256 { byFile[sha256] = program } else { byText[text] = program }
                        programs.append(program)
                    } catch {
                        let why = sha256.map { "its jq file \($0) does not read: \(error)" } ?? "its jq expression does not read: \(error)"
                        unreadable[sha256 ?? key] = why
                         
                        room.give(Int64(cost))
                        return .failure(JQRefusal(reason: why))
                    }
                }
            }
            charged.formUnion(fresh)
            bytes += cost
            return .success(programs)
        }
    }

     
    private static func gate(_ pattern: String) -> String? { pattern.isEmpty ? nil : pattern }

     
     
     
     
     
    private static func guarded(_ condition: ModuleCondition, by pattern: String) -> ModuleCondition {
        switch condition {
        case .all(let parts):
            return .all(parts.map { guarded($0, by: pattern) })
        case .any(let parts):
            return .any(parts.map { guarded($0, by: pattern) })
        case .match(.url, .regexSearch, .regex(let written), let capture) where withoutEscapedSlashes(written) == pattern:
            return .match(.url, .regexSearch, .regex(pattern), capture: capture)
        case .match:
            return condition
        }
    }

     
     
    private static func withoutEscapedSlashes(_ pattern: String) -> String {
        var out = ""
        var escaped = false
        for character in pattern {
            if escaped {
                if character != "/" { out.append("\\") }
                out.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                out.append(character)
            }
        }
        if escaped { out.append("\\") }
        return out
    }

     
     
     
    private static func matched(_ pattern: String) -> String { pattern.isEmpty ? "^" : pattern }

    private static func origin(_ rule: Rule, _ modules: [(id: String, name: String, family: ModuleFormat, writtenFor: ModuleScriptFamily)],
                               _ sections: [String]) -> ModuleRuleOrigin {
        ModuleRuleOrigin(moduleName: modules[Int(rule.module)].name, section: sections[Int(rule.section)], line: Int(rule.line))
    }

    private func origin(_ index: Int) -> ModuleRuleOrigin { Self.origin(rules[index], modules, sections) }

    private func family(_ index: Int) -> ModuleFormat { modules[Int(rules[index].module)].family }

    private func writtenFor(_ index: Int) -> ModuleScriptFamily { modules[Int(rules[index].module)].writtenFor }

    private func extras(_ index: Int) -> Extras? {
        let at = rules[index].extras
        return at >= 0 ? extras[Int(at)] : nil
    }

     
     
    static let leftOutWork: ModuleBodyStep.Work = .nothing

     
     
    private static let noMatch: NSTextCheckingResult = {
        var range = NSRange(location: 0, length: 0)
        return NSTextCheckingResult.regularExpressionCheckingResult(ranges: &range, count: 1, regularExpression: placeholder)
    }()

     
    private static let placeholder: NSRegularExpression = {
         
        guard let regex = try? NSRegularExpression(pattern: "a") else { preconditionFailure("a regex that compiles") }
        return regex
    }()

     
     
     
     
     
     
     
    private static func read(_ rewrite: ModuleRewriteRule, into rule: inout Rule, _ draft: inout Draft, moduleID: String,
                             moduleFile: (String, String) -> URL?, held: inout Held) -> Bool {
        for action in rewrite.actions {
            switch action {
            case .reject, .reject200, .rejectImg, .rejectTinyGif, .rejectDict, .rejectArray, .rejectDrop, .rejectNoDrop,
                 .redirect302, .redirect307, .transparent:
                 
                guard rewrite.phase != .response else { return false }
                if draft.ending == nil { draft.ending = .action(action) }
                rule.flags.insert(.ending)
            case .localAnswer(let answer):
                 
                guard ModuleLocalResponse.answers(answer) else { return false }
                if draft.ending == nil { draft.ending = .answer(answer) }
                rule.flags.insert(.ending)
            case .header(let phase, let operation, let name, let arguments):
                let header = HeaderAction(phase: phase, operation: operation, name: name, arguments: arguments, regex: nil)
                 
                if case .answer? = draft.ending, phase == .response {
                    draft.extras.answerHeaders.append(header)
                } else {
                    draft.extras.headers.append(header)
                    rule.flags.insert(phase == .request ? .requestHeaders : .responseHeaders)
                }
            case .bodyReplace(let phase, let pairs):
                draft.extras.bodies.append(BodyAction(phase: phase, draft: .replace(pairs)))
                rule.flags.insert(phase == .request ? .requestBodies : .responseBodies)
            case .json(let phase, let operations):
                let text = operations.reduce(0) { total, operation in
                    switch operation {
                    case .add(_, let value), .replace(_, let value), .replaceIfTruthy(_, let value), .addIfMissingOrNull(_, let value):
                        return total + value.utf8.count
                    case .delete, .deleteIfTruthy: return total
                    }
                }
                let reads = held.valueText + text <= maximumReadValueBytes
                switch ModuleJSONRewrite.compile(operations, readingValues: reads) {
                case .success(let compiled):
                    if reads { held.valueText += text }
                    held.bytes += compiled.heldBytes
                    draft.extras.bodies.append(BodyAction(phase: phase, draft: .ready(.json(compiled))))
                case .failure(let why):
                    draft.builtLeftOut = draft.builtLeftOut ?? why.reason
                    draft.extras.bodies.append(BodyAction(phase: phase, draft: .ready(Self.leftOutWork)))
                }
                rule.flags.insert(phase == .request ? .requestBodies : .responseBodies)
            case .bodyJQ(let phase, let expression, let sha256):
                if sha256 == nil, expression.isEmpty {
                     
                    draft.builtLeftOut = draft.builtLeftOut ?? "its jq file has not been downloaded yet"
                    draft.extras.bodies.append(BodyAction(phase: phase, draft: .ready(Self.leftOutWork)))
                } else {
                     
                    draft.extras.bodies.append(BodyAction(phase: phase, draft: .jq(expression: expression, sha256: sha256)))
                }
                rule.flags.insert(phase == .request ? .requestBodies : .responseBodies)
            case .requestBody(let body, let contentType):
                guard let data = Self.inline(body) else { return false }
                held.bytes += data.count
                draft.extras.bodies.append(BodyAction(phase: .request, draft: .ready(.body(data, contentType: contentType))))
                rule.flags.insert(.requestBodies)
            }
        }
        return true
    }

     
    private static func inline(_ body: ModuleAnswerBody) -> Data? {
        switch body {
        case .empty: return Data()
        case .text(let text): return Data(text.utf8)
        case .bytes(let bytes): return bytes
        case .tinyGIF: return Data(ModuleRejectResponses.tinyGIF)
        case .emptyJSONObject: return Data("{}".utf8)
        case .emptyJSONArray: return Data("[]".utf8)
        case .emptyVideo: return Data(ModuleRejectResponses.emptyVideo)
        case .file: return nil
        }
    }

     
     
     
     
     
     
     
    static func jqExpression(fileSHA256 sha256: String, at url: URL?) -> String? {
        guard let url, let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.readToEnd(), ModuleJSON.sha256(data) == sha256.lowercased() else { return nil }
        return String(data: data, encoding: .utf8)
    }

     
     
     
     
     
    static func heldBytes(ofJQ expression: String) -> Int { 1_024 + expression.utf8.count * 16 }

     

     
    private func runs(_ index: Int) -> Bool {
        let rule = rules[index]
        if rule.headerEntry >= 0, headerMatcher.leftOut[Int(rule.headerEntry)] != nil { return false }
        if rule.urlEntry >= 0, urlMatcher.leftOut[Int(rule.urlEntry)] != nil { return false }
        if rule.bodyEntry >= 0, bodyMatcher.leftOut[Int(rule.bodyEntry)] != nil { return false }
        return carried.runs(.rule(index))
    }

     
    private func pattern(_ index: Int) -> String {
        let rule = rules[index]
        if rule.headerEntry >= 0 { return headerMatcher.pattern(Int(rule.headerEntry)) ?? "" }
        if rule.urlEntry >= 0 { return urlMatcher.pattern(Int(rule.urlEntry)) ?? "" }
        if rule.bodyEntry >= 0 { return bodyMatcher.pattern(Int(rule.bodyEntry)) ?? "" }
        return ""
    }

     
    private func patternBytes(_ index: Int) -> Int {
        let rule = rules[index]
        if rule.headerEntry >= 0 { return headerMatcher.patternBytes(Int(rule.headerEntry)) }
        if rule.urlEntry >= 0 { return urlMatcher.patternBytes(Int(rule.urlEntry)) }
        if rule.bodyEntry >= 0 { return bodyMatcher.patternBytes(Int(rule.bodyEntry)) }
        return 0
    }

     
     
    var leftOutDuringRun: Set<RunLeftOut> {
        var indices = Set<Int>()
        for index in headerMatcher.leftOutDuringRun { indices.insert(Int(headerEntries[index])) }
        for index in urlMatcher.leftOutDuringRun { indices.insert(Int(urlEntries[index])) }
        for index in bodyMatcher.leftOutDuringRun { indices.insert(Int(bodyEntries[index])) }
        for carrier in carried.leftOutDuringRun {
            if case .rule(let index) = carrier { indices.insert(index) }
        }
        var out = Set<RunLeftOut>()
        for index in indices {
            let rule = rules[index]
            out.insert(RunLeftOut(moduleID: modules[Int(rule.module)].id, kind: rule.kind, section: sections[Int(rule.section)],
                                  line: Int(rule.line), pattern: pattern(index)))
        }
        for index in scriptsLeftOutDuringRun {
            let rule = scripts[index]
            out.insert(RunLeftOut(moduleID: rule.moduleID, kind: .script, section: rule.origin.section, line: rule.origin.line,
                                  pattern: scriptMatcher.pattern(index) ?? ""))
        }
        return out
    }

     
     
    private var scriptsLeftOutDuringRun: Set<Int> {
        var out = scriptMatcher.leftOutDuringRun
        for carrier in carried.leftOutDuringRun {
            if case .script(let index) = carrier { out.insert(index) }
        }
        return out
    }

     
     
     
    var grewTooLargeDuringRun: Set<RunLeftOut> {
        var out = handedGrowth
        for carrier in carried.leftOutForGrowth {
            guard case .rule(let index) = carrier else { continue }
            let rule = rules[index]
            out.insert(RunLeftOut(moduleID: modules[Int(rule.module)].id, kind: rule.kind, section: sections[Int(rule.section)],
                                  line: Int(rule.line), pattern: pattern(index)))
        }
        return out
    }

    private var reportedOutputTooLarge = 0
    private var reportedLeftOut = 0
    private var reportedLeftOutTooLarge = 0

     
     
     
     
     
    func takeNewStops() -> (outputTooLarge: Int, leftOutThisRun: Int, leftOutTooLarge: Int)? {
        let grew = carried.outputTooLarge
         
        var indices = Set<Int>()
        for index in headerMatcher.leftOutDuringRun { indices.insert(Int(headerEntries[index])) }
        for index in urlMatcher.leftOutDuringRun { indices.insert(Int(urlEntries[index])) }
        for index in bodyMatcher.leftOutDuringRun { indices.insert(Int(bodyEntries[index])) }
        for carrier in carried.leftOutDuringRun {
            if case .rule(let index) = carrier { indices.insert(index) }
        }
        let leftOut = indices.count + scriptsLeftOutDuringRun.count
         
        let tooLarge = handedGrowth.count + carried.leftOutForGrowth.count
        guard grew != reportedOutputTooLarge || leftOut != reportedLeftOut || tooLarge != reportedLeftOutTooLarge else { return nil }
        defer {
            reportedOutputTooLarge = grew
            reportedLeftOut = leftOut
            reportedLeftOutTooLarge = tooLarge
        }
        return (grew - reportedOutputTooLarge, leftOut, tooLarge)
    }

    private var reportedExecutions = 0
    private var reportedTimeouts = 0

     
     
     
     
     
     
    func takeNewRegexWork() -> (executions: Int, timeouts: Int) {
        let executions = regexExecutions, timeouts = regexTimeouts
        defer {
            reportedExecutions = executions
            reportedTimeouts = timeouts
        }
        return (executions - reportedExecutions, timeouts - reportedTimeouts)
    }

     
     
     
     
     
     
     
     
     
    var rewriteMetrics: ModuleGateMetrics {
        var total = ModuleGateMetrics()
        for part in [urlMatcher, headerMatcher, bodyMatcher].map(\.metrics) {
            total.patternBytes += part.patternBytes
            total.compileFailed += part.compileFailed
            total.gateLiterals += part.gateLiterals
            total.gateBytes += part.gateBytes
            total.regexTimeouts += part.regexTimeouts
            total.overBudget += part.overBudget
        }
        total.rules = rules.count
         
        total.ungated = urlMatcher.pinnedPatterns.union(headerMatcher.pinnedPatterns).union(bodyMatcher.pinnedPatterns).count
        total.patternBytes = rules.indices.reduce(0) { $0 + patternBytes($1) }
        total.compileFailed += carried.leftOutAtLoad
        total.overBudget += carried.overBudget
        total.regexTimeouts += carried.regexTimeouts
        total.outputTooLarge += carried.outputTooLarge
        return total
    }

     
    private var regexTimeouts: Int {
        urlMatcher.metrics.regexTimeouts + headerMatcher.metrics.regexTimeouts + bodyMatcher.metrics.regexTimeouts + carried.regexTimeouts
    }

    var scriptMetrics: ModuleGateMetrics { scriptMatcher.metrics }

     
    var regexExecutions: Int {
        urlMatcher.regexExecutions + headerMatcher.regexExecutions + bodyMatcher.regexExecutions + scriptMatcher.regexExecutions
    }

     
     
    var carriedRegexesHeld: Int { carried.held }

     
     
     
    var compiledRegexesAtMost: Int {
        carried.held + table.compiledAtMost
    }

     
     
    var roomTaken: Int64 { table.room.taken }

     
     
    var pinnedRegexes: Int { table.pinnedCount }

     
    var cachedRegexes: Int { table.cachedCount }

     
     
     
    func dropCachedRegexes() { table.dropCache() }

     
     
     
     
     
     
     
    var leftOut: [(origin: ModuleRuleOrigin, reason: String)] {
        var reasons: [Int: String] = [:]
        func note(_ matcher: ModuleGatedMatcher, _ entries: [Int32]) {
            for (entry, why) in matcher.leftOut where reasons[Int(entries[entry])] == nil { reasons[Int(entries[entry])] = why }
        }
        note(headerMatcher, headerEntries)
        note(urlMatcher, urlEntries)
        note(bodyMatcher, bodyEntries)
        for (carrier, why) in carried.leftOut {
            if case .rule(let index) = carrier, reasons[index] == nil { reasons[index] = why }
        }
        let ordered = reasons.keys.sorted { (rules[$0].stage.rawValue, $0) < (rules[$1].stage.rawValue, $1) }
        var scriptReasons = scriptMatcher.leftOut
        for (carrier, why) in carried.leftOut {
            if case .script(let index) = carrier, scriptReasons[index] == nil { scriptReasons[index] = why }
        }
        return ordered.map { (origin: origin($0), reason: reasons[$0] ?? "") }
            + scriptReasons.keys.sorted().map { (origin: scripts[$0].origin, reason: scriptReasons[$0] ?? "") }
    }

     

    private typealias Hit = (rule: Int, url: String, match: NSTextCheckingResult)

     
     
     
    private final class Seen {
        var gates: [Int: Hit?] = [:]
        var patterns: [Int32: Hit?] = [:]
        var conditions: [Int: ModuleConditionEvaluation.Outcome] = [:]
    }

     
     
    private func holds(_ index: Int, _ hit: Hit, _ view: ModuleMessageView, _ seen: Seen,
                       _ budget: inout ModuleRequestBudget) -> Bool {
        guard rules[index].flags.contains(.conditioned) else { return true }
        guard let condition = extras(index)?.condition else { return false }
        let outcome: ModuleConditionEvaluation.Outcome
        if let known = seen.conditions[index] {
            outcome = known
        } else {
            outcome = ModuleConditionEvaluation.evaluate(condition, in: view, gate: .init(url: hit.url, match: hit.match), budget: &budget)
            seen.conditions[index] = outcome
            if outcome == .timedOut { carried.stopped(.rule(index), .timedOut) }
        }
        if case .holds = outcome { return true }
        return false
    }

     
     
     
    private func each(_ matcher: ModuleGatedMatcher, _ entries: [Int32], _ urls: [String], _ seen: Seen,
                      _ budget: inout ModuleRequestBudget, where accept: (Int) -> Bool,
                      _ body: (Hit, inout ModuleRequestBudget) -> Bool) {
        matcher.forEachMatch(urls, budget: &budget, where: { accept(Int(entries[$0])) && self.runs(Int(entries[$0])) },
                             known: { entry -> ModuleGatedMatcher.Match?? in
                                 guard let known = seen.gates[Int(entries[entry])] ?? seen.patterns[matcher.patternID(entry)] else { return nil }
                                 guard let hit = known else { return .some(nil) }
                                 return .some((rule: entry, url: hit.url, match: hit.match))
                             },
                             { hit, budget in
                                 let found: Hit = (Int(entries[hit.rule]), hit.url, hit.match)
                                 seen.gates[found.rule] = .some(found)
                                 seen.patterns[matcher.patternID(hit.rule)] = .some(found)
                                 return body(found, &budget)
                             }, miss: { entry in
                                 seen.gates[Int(entries[entry])] = .some(nil)
                                 seen.patterns[matcher.patternID(entry)] = .some(nil)
                             })
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func mayAct(on urls: ModuleRequestURLs) -> Bool {
        let all = urls.all
        return [headerMatcher, urlMatcher, bodyMatcher, scriptMatcher].contains { !$0.candidates(all).isEmpty }
    }

    func requestPlan(_ view: ModuleMessageView, budget: inout ModuleRequestBudget) -> ModuleRequestPlan {
        var plan = ModuleRequestPlan()
        let seen = Seen()
        let urls = view.urls.all
        var working = view
        var turns: [(rule: Int32, stage: Stage, entry: Int32)] = []
        func gather(_ matcher: ModuleGatedMatcher, _ entries: [Int32], _ stage: Stage, _ accept: (Int) -> Bool) {
            matcher.candidates(urls).forEach { entry in
                if accept(Int(entries[entry])) { turns.append((entries[entry], stage, Int32(entry))) }
                return true
            }
        }
        gather(headerMatcher, headerEntries, .header) { self.rules[$0].hasHeaders(.request) }
        gather(urlMatcher, urlEntries, .url) { _ in true }
        gather(bodyMatcher, bodyEntries, .body) { self.rules[$0].hasBodies(.request) }
        turns.sort { ($0.rule, $0.stage.rawValue) < ($1.rule, $1.stage.rawValue) }
        var spent = false
        var found = false
        var decided: ModuleRequestDecision?
        var failing: ModuleHeaderStep?
        for turn in turns {
            let rule = Int(turn.rule)
             
            if found, turn.stage == .url { continue }
            if found, turn.stage == .body, decided.map(Self.endsTheRequest) == true { continue }
            guard runs(rule) else { continue }
            let matcher = turn.stage == .header ? headerMatcher : turn.stage == .url ? urlMatcher : bodyMatcher
            guard let hit = gate(matcher, Int(turn.entry), rule, urls, seen, &spent, &budget),
                  holds(rule, hit, working, seen, &budget) else { continue }
            switch turn.stage {
            case .header:
                let steps = headerSteps(rule, headerActions(rule, .request), hit)
                 
                if let step = steps.first(where: { framingStepFails($0, working.requestHeaders) }) {
                    failing = step
                    break
                }
                plan.headerSteps += steps
                for step in steps {
                    if step.operation == .replaceHead {
                        plan.headerRewrites.append(ModuleHeaderRewrite(origin: step.origin, what: step.what,
                                                                       outcome: applyHead(step, to: &working, line: &plan.requestLine,
                                                                                          budget: &budget)))
                    } else {
                        plan.headerRewrites += applyHeaderSteps([step], to: &working.requestHeaders, phase: .request, budget: &budget)
                    }
                }
            case .url:
                found = true
                decided = decision(rule, hit, &budget)
            case .body:
                plan.bodySteps += bodySteps(rule, .request)
            }
            if failing != nil { break }
        }
        plan.requestHeaders = working.requestHeaders
        if let step = failing {
            plan.ending = .drop(step.origin, kind: "header-\(step.operation.rawValue) \(step.name)")
            plan.bodySteps = []
            return plan
        }
        plan.ending = found ? (decided ?? .pass) : nil
        if let ending = plan.ending, Self.endsTheRequest(ending) { plan.bodySteps = [] }
        return plan
    }

     
    private static func endsTheRequest(_ decision: ModuleRequestDecision) -> Bool {
        switch decision {
        case .respond, .drop: return true
        case .pass, .rewrite: return false
        }
    }

     
     
     
    private func gate(_ matcher: ModuleGatedMatcher, _ entry: Int, _ rule: Int, _ urls: [String], _ seen: Seen,
                      _ spent: inout Bool, _ budget: inout ModuleRequestBudget) -> Hit? {
        let pattern = matcher.patternID(entry)
        if let known = seen.gates[rule] ?? seen.patterns[pattern] {
            guard let hit = known else { return nil }
            let found: Hit = (rule, hit.url, hit.match)
            seen.gates[rule] = .some(found)
            return found
        }
        guard !spent else {
            budget.noteStop()
            return nil
        }
        switch matcher.evaluated(entry, urls, budget: &budget) {
        case .match(let match):
            let found: Hit = (rule, match.url, match.match)
            seen.gates[rule] = .some(found)
            seen.patterns[pattern] = .some(found)
            return found
        case .none:
            seen.gates[rule] = .some(nil)
            seen.patterns[pattern] = .some(nil)
            return nil
        case .budgetSpent:
            spent = true
            return nil
        }
    }

     
     
    func requestPlan(_ view: ModuleMessageView) -> ModuleRequestPlan {
        var budget = ModuleRequestBudget.unlimited
        return requestPlan(view, budget: &budget)
    }

     
     
    func responseCandidates(_ urls: ModuleRequestURLs, budget: inout ModuleRequestBudget) -> ModuleResponseCandidates {
        var headers: [ModuleResponseCandidates.Hit] = []
        var bodies: [ModuleResponseCandidates.Hit] = []
        var readsRequestHeaders = false
        let seen = Seen()
        func gate(_ hit: Hit, filling: Bool) -> ModuleConditionEvaluation.GateMatch? {
            let flags = rules[hit.rule].flags
            return flags.contains(.conditioned) || (filling && flags.contains(.phased)) ? .init(url: hit.url, match: hit.match) : nil
        }
        each(headerMatcher, headerEntries, urls.all, seen, &budget, where: { self.rules[$0].hasHeaders(.response) }) { hit, _ in
            headers.append(.init(rule: hit.rule, gate: gate(hit, filling: true)))
            readsRequestHeaders = readsRequestHeaders || rules[hit.rule].flags.contains(.readsRequestHeaders)
            return true
        }
        each(bodyMatcher, bodyEntries, urls.all, seen, &budget, where: { self.rules[$0].hasBodies(.response) }) { hit, _ in
            bodies.append(.init(rule: hit.rule, gate: gate(hit, filling: false)))
            readsRequestHeaders = readsRequestHeaders || rules[hit.rule].flags.contains(.readsRequestHeaders)
            return true
        }
        return ModuleResponseCandidates(headers: headers, bodies: bodies, readsRequestHeaders: readsRequestHeaders)
    }

     
     
     
     
     
    func responsePlan(_ view: ModuleMessageView, candidates: ModuleResponseCandidates,
                      budget: inout ModuleRequestBudget) -> ModuleResponsePlan {
        var plan = ModuleResponsePlan()
        let seen = Seen()
        var working = view
         
        var headerAt = 0, bodyAt = 0
        while headerAt < candidates.headers.count || bodyAt < candidates.bodies.count {
            let takesHeader = bodyAt == candidates.bodies.count
                || (headerAt < candidates.headers.count && candidates.headers[headerAt].rule <= candidates.bodies[bodyAt].rule)
            let candidate = takesHeader ? candidates.headers[headerAt] : candidates.bodies[bodyAt]
            if takesHeader { headerAt += 1 } else { bodyAt += 1 }
            guard runs(candidate.rule) else { continue }
            let hit: Hit = (candidate.rule, candidate.gate?.url ?? "", candidate.gate?.match ?? Self.noMatch)
            guard holds(candidate.rule, hit, working, seen, &budget) else { continue }
            if takesHeader {
                let steps = headerSteps(candidate.rule, headerActions(candidate.rule, .response), hit)
                plan.headerSteps += steps
                var headers = working.responseHeaders ?? ModuleHTTPHeaders()
                plan.headerRewrites += applyHeaderSteps(steps, to: &headers, phase: .response, budget: &budget)
                working.responseHeaders = headers
            } else {
                plan.bodySteps += bodySteps(candidate.rule, .response)
            }
        }
        plan.responseHeaders = working.responseHeaders
        return plan
    }

     
    func responsePlan(_ view: ModuleMessageView) -> ModuleResponsePlan {
        var budget = ModuleRequestBudget.unlimited
        let candidates = responseCandidates(view.urls, budget: &budget)
        return responsePlan(view, candidates: candidates, budget: &budget)
    }

     
     
     
    static let maximumRewrittenURLLength = ModuleHTTPLimits.request.maximumStartLineBytes

     
     
     
     
    private func ending(_ view: ModuleMessageView, _ seen: Seen, _ budget: inout ModuleRequestBudget) -> ModuleRequestDecision? {
        var decided: ModuleRequestDecision?
        var found = false
        each(urlMatcher, urlEntries, view.urls.all, seen, &budget, where: { _ in true }) { hit, budget in
            guard holds(hit.rule, hit, view, seen, &budget) else { return true }
            found = true
            decided = decision(hit.rule, hit, &budget)
            return false
        }
        return found ? (decided ?? .pass) : nil
    }

     
    private func ending(_ index: Int) -> Ending? {
        let entry = rules[index].urlEntry
        guard entry >= 0 else { return nil }
        let code = endingCodes[Int(entry)]
        return code == Self.payloadCode ? endingPayloads[entry] : .action(Self.endingActions[Int(code)])
    }

    private func headerActions(_ index: Int, _ phase: ModuleRewritePhase) -> [HeaderAction] {
        extras(index)?.headers.filter { $0.phase == phase } ?? []
    }

     
     
    private func decision(_ index: Int, _ hit: Hit, _ budget: inout ModuleRequestBudget) -> ModuleRequestDecision? {
        let origin = origin(index)
        func expanded(_ template: String) -> String? {
             
             
            guard let regex = hit.match.regularExpression else { return template }
             
             
             
             
            let url = hit.url as NSString
            guard url.length - hit.match.range.length
                    + ModuleRegexTemplate(template, groupCount: regex.numberOfCaptureGroups).length(for: hit.match)
                    <= Self.maximumRewrittenURLLength else { return nil }
            return url.replacingCharacters(in: hit.match.range,
                                           with: regex.replacementString(for: hit.match, in: hit.url, offset: 0, template: template))
        }
        switch ending(index) {
        case nil:
            return nil
        case .answer(let answer)?:
            guard var response = ModuleLocalResponse(answer: answer) else { return nil }
            if let answerHeaders = extras(index)?.answerHeaders, !answerHeaders.isEmpty {
                 
                var headers = ModuleHTTPHeaders(response.headers.map { ModuleHTTPField(name: $0.name, value: $0.value) })
                _ = applyHeaderSteps(headerSteps(index, answerHeaders, hit), to: &headers, phase: .response, budget: &budget)
                response = ModuleLocalResponse(status: response.status, reason: response.reason,
                                                headers: headers.fields.filter { !ModuleLocalResponse.hopByHop.contains($0.name.lowercased()) }
                                                    .map { ModuleHeaderField(name: $0.name, value: $0.value) },
                                                body: response.body, location: nil)
            }
            return .respond(response, origin, kind: ModuleRewriteAction.localAnswer(answer).spelling)
        case .action(let action)?:
            switch action {
            case .rejectDrop:
                return .drop(origin, kind: action.spelling)
            case .redirect302(let template), .redirect307(let template):
                guard let location = expanded(template),
                      let response = ModuleRejectResponses.response(for: action, location: location) else { return nil }
                return .respond(response, origin, kind: action.spelling)
            case .transparent(let template):
                guard let to = expanded(template) else { return nil }
                return .rewrite(to: to, origin)
            default:
                guard let response = ModuleRejectResponses.response(for: action, location: nil) else { return nil }
                return .respond(response, origin, kind: action.spelling)
            }
        }
    }

     
     
     
    private func headerSteps(_ index: Int, _ actions: [HeaderAction], _ hit: Hit) -> [ModuleHeaderStep] {
        let phased = rules[index].flags.contains(.phased)
        let origin = origin(index), family = family(index)
        return actions.map { action in
            var value = action.arguments.first
            var unwritable: String?
            if action.runsARegex {
                value = action.arguments.count >= 2 ? action.arguments[1] : nil
            } else if phased, let template = value, action.operation == .add || action.operation == .set || action.operation == .replace {
                if let regex = hit.match.regularExpression, hit.match.numberOfRanges > 0 {
                    let cap = ModuleHTTPLimits.request.maximumHeadBytes
                    if ModuleRegexTemplate(template, groupCount: regex.numberOfCaptureGroups).length(for: hit.match) > cap {
                        value = nil
                        unwritable = "its value would be longer than a head may be (\(cap) bytes)"
                    } else {
                        value = regex.replacementString(for: hit.match, in: hit.url, offset: 0, template: template)
                    }
                } else {
                     
                    value = Self.unescaped(template)
                }
            }
            return ModuleHeaderStep(operation: action.operation, name: action.name, value: value, origin: origin, family: family,
                                     unwritable: unwritable, rule: index, regex: action.regex)
        }
    }

     
     
     
    static func unescaped(_ template: String) -> String {
        var out = ""
        let characters = Array(template)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\\" {
                if index + 1 < characters.count { out.append(characters[index + 1]) }
                index += 2
            } else if character == "$", index + 1 < characters.count, characters[index + 1].isASCII, characters[index + 1].isNumber {
                index += 1
                while index < characters.count, characters[index].isASCII, characters[index].isNumber { index += 1 }
            } else {
                out.append(character)
                index += 1
            }
        }
        return out
    }

    private func bodySteps(_ index: Int, _ phase: ModuleRewritePhase) -> [ModuleBodyStep] {
        let origin = origin(index), family = family(index), writtenFor = writtenFor(index)
        return (extras(index)?.bodies ?? []).compactMap { action in
            guard action.phase == phase, case .ready(let work) = action.draft else { return nil }
            return ModuleBodyStep(work: work, origin: origin, family: family, writtenFor: writtenFor, rule: index, carried: carried)
        }
    }

     
     
    private func framingStepFails(_ step: ModuleHeaderStep, _ headers: ModuleHTTPHeaders) -> Bool {
        guard step.family == .surge, Self.framingHeaders.contains(step.name.lowercased()) else { return false }
        switch step.operation {
        case .add, .set: return true
        case .delete, .replace, .replaceRegex: return headers.contains(step.name)
        case .replaceHead: return false
        }
    }

     

     
     
     
     
     
     
    func applyHeaderSteps(_ steps: [ModuleHeaderStep], to headers: inout ModuleHTTPHeaders, phase: ModuleRewritePhase,
                          budget: inout ModuleRequestBudget) -> [ModuleHeaderRewrite] {
        let headCap = (phase == .request ? ModuleHTTPLimits.request : ModuleHTTPLimits.response).maximumHeadBytes
        return steps.map { step in
            ModuleHeaderRewrite(origin: step.origin, what: step.what, outcome: apply(step, to: &headers, headCap: headCap, budget: &budget))
        }
    }

    private func apply(_ step: ModuleHeaderStep, to headers: inout ModuleHTTPHeaders,
                       headCap: Int, budget: inout ModuleRequestBudget) -> ModuleHeaderRewrite.Outcome {
        let name = step.name
        guard carried.runs(.rule(step.rule)) else { return .skipped("its rule was left out for the run") }
        guard !name.isEmpty, name.allSatisfy(ModuleHTTPParser.isTokenCharacter) else { return .skipped("its name is not a header name") }
        guard !Self.protectedHeaders.contains(name.lowercased()) else {
            return .skipped("the exchange keeps this header as it is: it frames the message or the connection")
        }
        if let why = step.unwritable { return .skipped(why) }
        switch step.operation {
        case .replaceHead:
            return .skipped("it rewrites the whole head, which the request's plan does")
        case .add:
            guard let value = step.value, ModuleHTTPParser.isValidFieldText(value) else { return .skipped("its value is not one line") }
            headers.add(name, value)
        case .delete:
            guard headers.contains(name) else { return .skipped("the header is not there") }
            headers.remove(name)
        case .replace:
             
            guard let value = step.value, ModuleHTTPParser.isValidFieldText(value) else { return .skipped("its value is not one line") }
            guard headers.contains(name) else { return .skipped("the header is not there") }
            headers.set(name, value)
        case .set:
             
            guard let value = step.value, ModuleHTTPParser.isValidFieldText(value) else { return .skipped("its value is not one line") }
            headers.set(name, value)
        case .replaceRegex:
            guard let template = step.value, let regex = step.regex else { return .skipped("it has no regex to run") }
            guard headers.contains(name) else { return .skipped("the header is not there") }
            var changed = false
            var unwritable = false
            for field in headers.fields.indices where headers.fields[field].name.caseInsensitiveCompare(name) == .orderedSame {
                let value = headers.fields[field].value
                 
                 
                let head = headers.fields.reduce(0) { $0 + $1.name.utf16.count + $1.value.utf16.count + 4 }
                let room = headCap - head + value.utf16.count
                guard !budget.isSpent else {
                    budget.noteStop()
                    return .budgetSpent
                }
                let allowed = min(ModuleGatedMatcher.evaluationDeadline, budget.remainingSeconds)
                let started = ModuleRequestBudget.threadNanoseconds()
                let result = ModuleRegexReplacement.replace(regex, in: value, template: template, deadline: allowed,
                                                             maximumLength: max(value.utf16.count, room), unit: .utf16)
                budget.charge(ModuleRequestBudget.threadNanoseconds() &- started)
                switch result {
                case .unchanged:
                    continue
                case .timedOut where allowed < ModuleGatedMatcher.evaluationDeadline:
                    budget.noteStop()
                    return .budgetSpent
                case .replaced(let replaced) where !ModuleHTTPParser.isValidFieldText(replaced):
                    unwritable = true
                case .replaced(let replaced):
                    headers.fields[field].value = replaced
                    changed = true
                case .timedOut:
                    carried.stopped(.rule(step.rule), .timedOut)
                    return .timedOut
                case .grewTooLarge:
                    carried.stopped(.rule(step.rule), .grewTooLarge)
                    return .grewTooLarge
                }
            }
            guard changed else { return .skipped(unwritable ? "what its regex makes is not one line" : "its regex changed nothing") }
        }
        return .applied
    }

     
     
     
     
     
    private func applyHead(_ step: ModuleHeaderStep, to view: inout ModuleMessageView, line: inout (method: String, target: String)?,
                           budget: inout ModuleRequestBudget) -> ModuleHeaderRewrite.Outcome {
        guard carried.runs(.rule(step.rule)) else { return .skipped("its rule was left out for the run") }
        guard let template = step.value, let regex = step.regex else { return .skipped("it has no regex to run") }
        let method = line?.method ?? view.method
        let target = line?.target ?? ModuleMessageView.target(of: view.urls.primary)
        let text = ModuleMessageView.head(method: method, target: target, headers: view.requestHeaders)
        guard !budget.isSpent else {
            budget.noteStop()
            return .budgetSpent
        }
        let allowed = min(ModuleGatedMatcher.evaluationDeadline, budget.remainingSeconds)
        let started = ModuleRequestBudget.threadNanoseconds()
        let result = ModuleRegexReplacement.replace(regex, in: text, template: template, deadline: allowed,
                                                     maximumLength: max(text.utf16.count, ModuleHTTPLimits.request.maximumHeadBytes),
                                                     unit: .utf16)
        budget.charge(ModuleRequestBudget.threadNanoseconds() &- started)
        switch result {
        case .unchanged:
            return .skipped("its regex changed nothing")
        case .timedOut where allowed < ModuleGatedMatcher.evaluationDeadline:
            budget.noteStop()
            return .budgetSpent
        case .timedOut:
            carried.stopped(.rule(step.rule), .timedOut)
            return .timedOut
        case .grewTooLarge:
            carried.stopped(.rule(step.rule), .grewTooLarge)
            return .grewTooLarge
        case .replaced(let replaced):
            guard let read = ModuleMessageView.readHead(replaced) else { return .skipped("what its regex makes is not a request's head") }
            let kept = view.requestHeaders.fields.filter { Self.protectedHeaders.contains($0.name.lowercased()) }
            view.requestHeaders = ModuleHTTPHeaders(read.fields.filter { !Self.protectedHeaders.contains($0.name.lowercased()) } + kept)
            if read.method != method || read.target != target {
                line = (read.method, read.target)
                view.method = read.method
            }
            return .applied
        }
    }

     

     
    private func view(_ urls: ModuleRequestURLs, _ headers: ModuleHTTPHeaders, _ phase: ModuleRewritePhase) -> ModuleMessageView {
        phase == .request ? ModuleMessageView(urls: urls, method: "", requestHeaders: headers)
            : ModuleMessageView(urls: urls, method: "", responseStatus: nil, responseHeaders: headers)
    }
#if false || MODULES_ENGINE_TESTS

     
     
     
     
     
     
     
    func applyHeaders(_ headers: inout ModuleHTTPHeaders, phase: ModuleRewritePhase,
                      urls: ModuleRequestURLs, budget: inout ModuleRequestBudget) -> [ModuleHeaderRewrite] {
        if phase == .request {
            var view = self.view(urls, headers, .request)
            var rewrites: [ModuleHeaderRewrite] = []
            let seen = Seen()
            each(headerMatcher, headerEntries, urls.all, seen, &budget, where: { self.rules[$0].hasHeaders(.request) }) { hit, budget in
                guard holds(hit.rule, hit, view, seen, &budget) else { return true }
                rewrites += applyHeaderSteps(headerSteps(hit.rule, headerActions(hit.rule, .request), hit), to: &view.requestHeaders,
                                             phase: .request, budget: &budget)
                return true
            }
            headers = view.requestHeaders
            return rewrites
        }
        let candidates = responseCandidates(urls, budget: &budget)
        let plan = responsePlan(view(urls, headers, .response), candidates: candidates.withoutBodies(), budget: &budget)
        headers = plan.responseHeaders ?? headers
        return plan.headerRewrites
    }

    func applyHeaders(_ headers: inout ModuleHTTPHeaders, phase: ModuleRewritePhase,
                      urls: ModuleRequestURLs) -> [ModuleHeaderRewrite] {
        var budget = ModuleRequestBudget.unlimited
        return applyHeaders(&headers, phase: phase, urls: urls, budget: &budget)
    }
#endif



     
    func requestDecision(_ urls: ModuleRequestURLs, budget: inout ModuleRequestBudget) -> ModuleRequestDecision {
        ending(view(urls, ModuleHTTPHeaders(), .request), Seen(), &budget) ?? .pass
    }

    func requestDecision(_ urls: ModuleRequestURLs) -> ModuleRequestDecision {
        var budget = ModuleRequestBudget.unlimited
        return requestDecision(urls, budget: &budget)
    }

     
     
    func bodyRules(phase: ModuleRewritePhase, urls: ModuleRequestURLs, budget: inout ModuleRequestBudget) -> [ModuleBodyRule] {
        let steps: [ModuleBodyStep]
        if phase == .request {
            let seen = Seen()
            var found: [ModuleBodyStep] = []
            let view = self.view(urls, ModuleHTTPHeaders(), .request)
            each(bodyMatcher, bodyEntries, urls.all, seen, &budget, where: { self.rules[$0].hasBodies(.request) }) { hit, budget in
                guard holds(hit.rule, hit, view, seen, &budget) else { return true }
                found += bodySteps(hit.rule, .request)
                return true
            }
            steps = found
        } else {
            let candidates = responseCandidates(urls, budget: &budget)
            steps = responsePlan(view(urls, ModuleHTTPHeaders(), .response), candidates: candidates, budget: &budget).bodySteps
        }
        return steps.compactMap { step in
            if case .replace(let rule) = step.work { return rule }
            return nil
        }
    }

    func bodyRules(phase: ModuleRewritePhase, urls: ModuleRequestURLs) -> [ModuleBodyRule] {
        var budget = ModuleRequestBudget.unlimited
        return bodyRules(phase: phase, urls: urls, budget: &budget)
    }

     

    private func match(_ index: Int, url: String) -> ModuleScriptMatch {
        let rule = scripts[index]
        return ModuleScriptMatch(script: rule.script, moduleID: rule.moduleID, format: rule.format, bodyFile: rule.bodyFile,
                                 origin: rule.origin, url: url, writtenFor: rule.writtenFor)
    }

     
     
     
    private func scriptHolds(_ index: Int, url: String, match: NSTextCheckingResult, _ view: ModuleMessageView,
                             _ budget: inout ModuleRequestBudget) -> Bool {
        guard let condition = scripts[index].condition else { return true }
        switch ModuleConditionEvaluation.evaluate(condition, in: view, gate: .init(url: url, match: match), budget: &budget) {
        case .holds:
            return true
        case .timedOut:
            carried.stopped(.script(index), .timedOut)
            return false
        case .fails, .budgetSpent:
            return false
        }
    }

     
    private func runs(script index: Int, _ phase: ModuleRewritePhase) -> Bool {
        scripts[index].script.phase == phase && carried.runs(.script(index))
    }

     
     
     
     
     
     
    func requestScript(_ view: ModuleMessageView, budget: inout ModuleRequestBudget) -> ModuleScriptMatch? {
        var found: ModuleScriptMatch?
        scriptMatcher.forEachMatch(view.urls.all, budget: &budget, where: { runs(script: $0, .request) }) { hit, budget in
            guard scriptHolds(hit.rule, url: hit.url, match: hit.match, view, &budget) else { return true }
            found = match(hit.rule, url: hit.url)
            return false
        }
        return found
    }

     
    func requestScript(_ view: ModuleMessageView) -> ModuleScriptMatch? {
        var budget = ModuleRequestBudget.unlimited
        return requestScript(view, budget: &budget)
    }

     
     
     
     
     
     
    func responseScripts(_ urls: ModuleRequestURLs, budget: inout ModuleRequestBudget) -> ModuleResponseScripts {
        var candidates: [ModuleResponseScripts.Candidate] = []
        scriptMatcher.forEachMatch(urls.all, budget: &budget, where: { runs(script: $0, .response) }) { hit, _ in
            let conditioned = scripts[hit.rule].condition != nil
            candidates.append(.init(rule: hit.rule, match: match(hit.rule, url: hit.url),
                                    gate: conditioned ? .init(url: hit.url, match: hit.match) : nil))
            return conditioned
        }
        return ModuleResponseScripts(candidates: candidates)
    }

    func responseScripts(_ urls: ModuleRequestURLs) -> ModuleResponseScripts {
        var budget = ModuleRequestBudget.unlimited
        return responseScripts(urls, budget: &budget)
    }

     
     
     
     
    func responseScript(_ found: ModuleResponseScripts, _ view: ModuleMessageView, budget: inout ModuleRequestBudget) -> ModuleScriptMatch? {
        for candidate in found.candidates {
            guard let gate = candidate.gate else { return candidate.match }
            guard carried.runs(.script(candidate.rule)),
                  scriptHolds(candidate.rule, url: gate.url, match: gate.match, view, &budget) else { continue }
            return candidate.match
        }
        return nil
    }

    func responseScript(_ found: ModuleResponseScripts, _ view: ModuleMessageView) -> ModuleScriptMatch? {
        var budget = ModuleRequestBudget.unlimited
        return responseScript(found, view, budget: &budget)
    }
}

 
 
struct ModuleResponseScripts {
    fileprivate struct Candidate {
         
        let rule: Int
        let match: ModuleScriptMatch
         
         
        let gate: ModuleConditionEvaluation.GateMatch?
    }

    fileprivate var candidates: [Candidate] = []

    static let none = ModuleResponseScripts()

    var isEmpty: Bool { candidates.isEmpty }
    var count: Int { candidates.count }

     
     
    var decided: ModuleScriptMatch? {
        guard let first = candidates.first, first.gate == nil else { return nil }
        return first.match
    }

     
    var first: ModuleScriptMatch? { candidates.first?.match }

     
    var mayReadBody: Bool { candidates.contains { $0.match.script.requiresBody } }
}

 
 
 
 
 
 
 
 
 
 
 
enum ModuleBodySteps {
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static let readAndWriteCharged = true

     
     
    static let readAndWriteNanosecondsPerByte: UInt64 = 20

     
     
     
     
     
     
    static let writeNanosecondsPerByte: UInt64 = 10

    struct Result {
         
        var body: Data?
         
        var contentType: String?
         
        var acted: [(origin: ModuleRuleOrigin, what: String)] = []
         
         
        var notes: [(origin: ModuleRuleOrigin, what: String, why: String)] = []
         
        var notText = false
    }

     
     
     
     
     
     
     
     
     
    static func apply(_ steps: [ModuleBodyStep], to body: Data, budget: inout ModuleRequestBudget, memoryLeft: Int? = nil) -> Result {
        var result = Result()
        let jsonCap = max(body.count, ModuleBodyLimits.current.defaultBytes)
        var text = body
        var changed = false
         
        var tree: ModuleJSONValue?
        var treeChanged = false
        var treeSteps: [(origin: ModuleRuleOrigin, what: String)] = []
         
        var reserved: UInt64 = 0
        func charge(since start: UInt64) {
            if readAndWriteCharged { budget.charge(ModuleRequestBudget.threadNanoseconds() &- start) }
        }
         
        func drop() {
            budget.release(reserved)
            reserved = 0
            tree = nil
            treeChanged = false
            treeSteps = []
        }
         
         
        func close() -> Bool {
            let current = treeChanged ? tree : nil
            let steps = treeSteps
            drop()
            guard let current else { return true }
            let payable = readAndWriteCharged ? Int(min(UInt64(jsonCap), budget.remainingNanoseconds / writeNanosecondsPerByte)) : jsonCap
            let start = ModuleRequestBudget.threadNanoseconds()
            let written = ModuleJSONText.serialize(current, limit: payable)
            charge(since: start)
            guard let written else {
                budget.noteStop()
                let why = payable < jsonCap
                    ? String(format: "the request's processing budget (%.1f ms left) cannot pay for writing what the JSON steps made; its change is dropped",
                             budget.remainingSeconds * 1_000)
                    : "what it made is larger than the \(jsonCap) bytes a body may be; its change is dropped"
                for step in steps { result.notes.append((step.origin, step.what, why)) }
                return false
            }
            text = written
            changed = true
            result.acted += steps
            return true
        }
         
        func open(_ step: ModuleBodyStep) -> ModuleJSONValue? {
            if let tree { return tree }
            let estimate = UInt64(text.count) &* readAndWriteNanosecondsPerByte
            guard !budget.isSpent, !readAndWriteCharged || budget.remainingNanoseconds >= estimate else {
                budget.noteStop()
                result.notes.append((step.origin, step.what, String(format: "the request's processing budget (%.1f ms left) cannot pay for reading and writing a body of %d bytes (about %.1f ms); it goes as it came",
                                                                    budget.remainingSeconds * 1_000, text.count, Double(estimate) / 1e6)))
                return nil
            }
            let start = ModuleRequestBudget.threadNanoseconds()
             
            let reading = ModuleJSONText.parse(text, maximumNodes: .max)
            charge(since: start)
            switch reading {
            case .value(let value):
                tree = value
                 
                if readAndWriteCharged { reserved = budget.hold(UInt64(text.count) &* writeNanosecondsPerByte) }
                return value
            case .notJSON, .tooManyNodes:
                result.notes.append((step.origin, step.what, "the body is not JSON; it goes as it came"))
            }
            return nil
        }
        for step in steps {
            guard step.runs else { continue }
            switch step.work {
            case .replace(let rule):
                _ = close()
                switch ModuleBodyRewrite.apply([rule], to: text, budget: &budget) {
                case .rewritten(let next):
                    text = next
                    changed = true
                    result.acted.append((step.origin, step.what))
                case .unchanged:
                    break
                case .notText:
                    result.notText = true
                }
            case .json(let compiled):
                guard var value = open(step) else { continue }
                switch ModuleJSONRewrite.apply(compiled, to: &value, maximumBodyBytes: jsonCap, bodyBytes: text.count, budget: &budget) {
                case .changed:
                    tree = value
                    treeChanged = true
                    treeSteps.append((step.origin, step.what))
                case .unchanged:
                    break
                case .stopped:
                     
                    if !budget.isSpent { step.stoppedOnItsOwnLimit() }
                    result.notes.append((step.origin, step.what, budget.isSpent
                        ? "the request's processing budget ran out; it changed nothing"
                        : "what it would write is past the \(jsonCap) bytes a body may be; it changed nothing"))
                }
            case .jq(let program):
                guard let value = open(step) else { continue }
                var limits = ModuleJQ.Limits.engine(bodyBytes: jsonCap, inputBytes: text.count)
                if let memoryLeft {
                    limits.memoryBytes = min(limits.memoryBytes, max(0, memoryLeft))
                    limits.backstopBytes = min(limits.backstopBytes, max(0, memoryLeft))
                }
                var lines: [String] = []
                let trace = ModuleJQ.trace(program, on: value, limits: limits, budget: &budget, maximumOutputs: 2, log: { lines.append($0) })
                 
                let settling = ModuleRequestBudget.threadNanoseconds()
                let outcome = ModuleJQ.outcome(of: trace, limits: limits, budget: &budget, log: { lines.append($0) })
                var differs = false
                if case .value(let next) = outcome { differs = next != value }
                budget.charge(ModuleRequestBudget.threadNanoseconds() &- settling)
                switch outcome {
                case .value(let next):
                    if differs {
                        tree = next
                        treeChanged = true
                        treeSteps.append((step.origin, step.what))
                    }
                case .noOutput:
                    result.notes.append((step.origin, step.what, "jq gave no output; the body goes as it came"))
                case .error(let words):
                    result.notes.append((step.origin, step.what, "jq raised \(words.debugDescription); the body goes as it came"))
                case .stopped:
                    if case .stopped(let why) = trace.ending {
                         
                        if !trace.stoppedByBackstop, !trace.stoppedByBudget { step.stoppedOnItsOwnLimit() }
                        result.notes.append((step.origin, step.what, "jq stopped: \(why); the body goes as it came"))
                    } else {
                        result.notes.append((step.origin, step.what, "jq's output is larger than \(jsonCap) bytes; the body goes as it came"))
                    }
                }
                for line in lines { result.notes.append((step.origin, step.what, line)) }
            case .body(let data, let contentType):
                 
                drop()
                text = data
                changed = true
                result.contentType = contentType
                result.acted.append((step.origin, step.what))
            case .nothing:
                 
                continue
            }
        }
        _ = close()
        result.body = changed && text != body ? text : (changed && result.contentType != nil ? text : nil)
        return result
    }
}
#endif
