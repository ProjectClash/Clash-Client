import Foundation

/// What a `cron` or `generic` script hands back for its entry point to show.
///
/// Loon's manual names `title` and `content`; the scripts in the hub also send
/// `htmlMessage`, which is what a client with an HTML view renders instead of
/// the plain text. All three are kept as written rather than flattened, because
/// the caller decides how much of it it can show.
public struct ScriptResult: Equatable, Sendable {
    public var title: String?
    public var content: String?
    public var htmlMessage: String?

    public init(title: String? = nil, content: String? = nil, htmlMessage: String? = nil) {
        self.title = title
        self.content = content
        self.htmlMessage = htmlMessage
    }

    /// True when the script supplied none of the fields, which is the same as
    /// it having said nothing.
    public var isEmpty: Bool { title == nil && content == nil && htmlMessage == nil }

    /// The text a client without an HTML view can show.
    ///
    /// Every result in the hub's corpus arrives as `htmlMessage` and none of
    /// them as `content`: `NodeLinkCheck.js` answers with a centred `<p>` full
    /// of `<br>` and `<span style=…>`, `NetworkEntryAndExitQueries.js` with a
    /// `<div>` of labelled IPs. Rendering that markup is a UI decision, so this
    /// reduces it to the text a plain label can carry — line breaks preserved
    /// from `<br>` and block ends, tags dropped, entities decoded — rather than
    /// showing raw markup or showing nothing.
    public var plainText: String {
        if let content { return [title, content].compactMap { $0 }.joined(separator: "\n") }
        guard let html = htmlMessage else { return title ?? "" }
        return [title, ScriptResult.plain(html)].compactMap { $0 }
            .filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// Markup to text, without a web view.
    static func plain(_ html: String) -> String {
        var text = html
        // Only block elements end a line. `</span>` must not: the hub wraps its
        // labels in spans, so treating it as a break splits "节点: HK-01 IEPL"
        // into two lines — a rendering bug the tests caught.
        for tag in ["<br/>", "<br />", "<br>", "</div>", "</p>", "</tr>", "<tr>"] {
            text = text.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
        }
        // Drop everything else between angle brackets, inline tags included.
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        // Collapse the runs of blank lines the tags leave behind.
        var lines: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty, lines.last?.isEmpty != false { continue }
            lines.append(trimmed)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A `$done` payload, already read out of JavaScript.
///
/// Deliberately not a `Codable` mirror of any one platform's object: the reader
/// accepts every spelling it has seen in the wild (`status` or `statusCode`,
/// `body` or `bodyBytes`, `headers` as an object or as `{field, value}` pairs)
/// and the parser below turns the same value into the right meaning for the
/// phase it was called in.
public struct ScriptDonePayload: Equatable, Sendable {
    /// The status as the script wrote it: `200`, `"200"` or `"HTTP/1.1 200 OK"`.
    public var status: String?
    public var statusCode: String?
    public var url: String?
    public var headers: ScriptHeaders?
    /// Text body, when the script supplied one as a string.
    public var text: String?
    /// Binary body, when the script supplied bytes.
    public var bytes: Data?
    /// Whether the script supplied a body at all — `null` means "no change",
    /// an empty string means "make it empty".
    public var hasBody: Bool
    public var abort: Bool
    public var policy: String?
    /// A nested response, which is how the request phase returns a mock on
    /// Loon; Surge and Stash spell it as top-level fields.
    public var nestedResponse: ScriptResponse?
    /// What a `cron`/`generic` script hands back for its entry point to show.
    ///
    /// Loon's manual, §11.1: "Generic 脚本可以返回一个结果对象，供调用入口展示或消费：
    /// `$done({ title: "查询完成", content: "当前任务已经执行完成" })`". The hub's node
    /// checks all use it — `LocationDetection.js` answers with
    /// `{title: "  地理位置查询", htmlMessage: message}` — so a run that drops it
    /// has run the script for nothing.
    public var result: ScriptResult?

    public init(status: String? = nil, statusCode: String? = nil, url: String? = nil,
                headers: ScriptHeaders? = nil, text: String? = nil, bytes: Data? = nil,
                hasBody: Bool = false, abort: Bool = false, policy: String? = nil,
                nestedResponse: ScriptResponse? = nil, result: ScriptResult? = nil) {
        self.status = status
        self.statusCode = statusCode
        self.url = url
        self.headers = headers
        self.text = text
        self.bytes = bytes
        self.hasBody = hasBody
        self.abort = abort
        self.policy = policy
        self.nestedResponse = nestedResponse
        self.result = result
    }

    /// True when the script asked for nothing at all.
    public var isSilent: Bool {
        status == nil && statusCode == nil && url == nil && headers == nil && !hasBody
            && !abort && policy == nil && nestedResponse == nil && result == nil
    }

    /// The body as bytes, from whichever field carried it.
    public var body: Data? {
        if let bytes { return bytes }
        if let text { return Data(text.utf8) }
        return nil
    }
}

/// Turns a payload into an outcome, in the phase it was produced.
public enum ScriptDoneParsing {
    /// The status code from `status`/`statusCode`, in any of the spellings the
    /// platforms accept. `"HTTP/1.1 200 OK"`, `"HTTP/1.1 200"` and `"200"` all
    /// mean 200; anything else is `nil` and the response keeps its status.
    public static func statusCode(_ payload: ScriptDonePayload) -> Int? {
        if let code = payload.statusCode.flatMap(parseStatus) { return code }
        if let raw = payload.status { return parseStatus(raw) }
        return nil
    }

    static func parseStatus(_ raw: String) -> Int? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        // A status line: "HTTP/1.1 200 OK". The version token may be absent.
        let words = text.split(separator: " ", omittingEmptySubsequences: true)
        if let first = words.first, first.uppercased().hasPrefix("HTTP/") {
            guard words.count >= 2, let code = Int(words[1]), (100...599).contains(code) else { return nil }
            return code
        }
        if words.count == 1, let code = Int(text), (100...599).contains(code) { return code }
        return nil
    }

    /// The outcome of a `$done` in the request phase.
    ///
    /// A status, headers or body at the top level is a changed request. A
    /// nested `response` — or, on Surge and Stash, a top-level status with no
    /// request fields — is a mock: the tunnel answers without going upstream.
    public static func requestOutcome(_ payload: ScriptDonePayload, base: ScriptRequest) -> ScriptOutcome {
        if payload.abort { return .aborted("the script aborted the request") }
        if let mock = payload.nestedResponse { return .response(mock) }
        // A `cron`/`generic` script's answer is the result object itself. It
        // comes before the change checks, because a result carries no request
        // fields and would otherwise read as "no change".
        if let result = payload.result { return .result(result) }
        if payload.isSilent { return .unchanged }

        // Surge documents a request script answering with a status as a mock,
        // and Quantumult X has no other way to say it. A status therefore means
        // "answer with this"; only a URL or a method means "change the request".
        if statusCode(payload) != nil, payload.url == nil {
            return .response(response(from: payload, base: nil))
        }
        // A `policy` (or `node`) on its own asks the host for routing this
        // tunnel does not expose to scripts; it is not a change to the request.
        guard payload.url != nil || payload.headers != nil || payload.hasBody else { return .unchanged }

        var next = base
        if let url = payload.url, !url.isEmpty { next.url = url }
        if let headers = payload.headers { next.headers = headers }
        if payload.hasBody { next.body = payload.body }
        return .request(next)
    }

    /// The outcome of a `$done` in the response phase.
    public static func responseOutcome(_ payload: ScriptDonePayload, base: ScriptResponse) -> ScriptOutcome {
        if payload.abort { return .aborted("the script aborted the response") }
        if payload.isSilent { return .unchanged }
        return .response(response(from: payload, base: base))
    }

    /// Reads a response out of a payload. With a `base`, unmentioned fields keep
    /// their original value; without one, absent fields take HTTP defaults.
    public static func response(from payload: ScriptDonePayload, base: ScriptResponse?) -> ScriptResponse {
        var out = base ?? ScriptResponse(status: 200, headers: ScriptHeaders())
        if let code = statusCode(payload) { out.status = code }
        if let headers = payload.headers { out.headers = headers }
        if payload.hasBody { out.body = payload.body }
        return out
    }
}
