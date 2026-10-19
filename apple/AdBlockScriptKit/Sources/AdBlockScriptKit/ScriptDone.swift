import Foundation

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

    public init(status: String? = nil, statusCode: String? = nil, url: String? = nil,
                headers: ScriptHeaders? = nil, text: String? = nil, bytes: Data? = nil,
                hasBody: Bool = false, abort: Bool = false, policy: String? = nil,
                nestedResponse: ScriptResponse? = nil) {
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
    }

    /// True when the script asked for nothing at all.
    public var isSilent: Bool {
        status == nil && statusCode == nil && url == nil && headers == nil && !hasBody
            && !abort && policy == nil && nestedResponse == nil
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
