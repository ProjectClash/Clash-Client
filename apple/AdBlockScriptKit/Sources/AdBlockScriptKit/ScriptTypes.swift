import Foundation

/// An ordered header list that keeps the case a script wrote and looks names up
/// case-insensitively.
///
/// Scripts copy `$request.headers` and change one field; several of them pick
/// the field by lowercased name and write it back in that case. Rebuilding the
/// list from a dictionary would lose the original casing and make such scripts
/// produce two `content-type` fields, so the list is kept and mutated in place.
public struct ScriptHeaders: Equatable, Sendable {
    public private(set) var fields: [(name: String, value: String)]

    public static func == (lhs: ScriptHeaders, rhs: ScriptHeaders) -> Bool {
        guard lhs.fields.count == rhs.fields.count else { return false }
        for (left, right) in zip(lhs.fields, rhs.fields) where left.name != right.name || left.value != right.value {
            return false
        }
        return true
    }

    public init(_ fields: [(name: String, value: String)] = []) {
        self.fields = fields
    }

    public init(_ dictionary: [String: String]) {
        self.fields = dictionary.map { (name: $0.key, value: $0.value) }
    }

    public var isEmpty: Bool { fields.isEmpty }

    /// The first value for `name`, matched without regard to case.
    public func first(_ name: String) -> String? {
        fields.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    public func contains(_ name: String) -> Bool { first(name) != nil }

    /// Replaces every field called `name` with one field, keeping the name's
    /// original casing when there was one.
    public mutating func set(_ name: String, _ value: String) {
        if let index = fields.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            let kept = fields[index].name
            fields.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            fields.insert((name: kept, value: value), at: index)
        } else {
            fields.append((name: name, value: value))
        }
    }

    public mutating func add(_ name: String, _ value: String) {
        fields.append((name: name, value: value))
    }

    public mutating func remove(_ name: String) {
        fields.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// A plain object for JavaScript, in the order the fields are held.
    public var dictionary: [String: String] {
        var out: [String: String] = [:]
        for field in fields where out[field.name] == nil { out[field.name] = field.value }
        return out
    }
}

/// A request as a script sees it. `body` is present only when the script's
/// declaration asked for the body (`requires-body`).
public struct ScriptRequest: Equatable, Sendable {
    public var id: String
    public var method: String
    public var url: String
    public var headers: ScriptHeaders
    public var body: Data?

    public init(id: String = "", method: String, url: String, headers: ScriptHeaders, body: Data? = nil) {
        self.id = id
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

/// A response as a script sees it.
public struct ScriptResponse: Equatable, Sendable {
    public var status: Int
    public var headers: ScriptHeaders
    public var body: Data?

    public init(status: Int, headers: ScriptHeaders, body: Data? = nil) {
        self.status = status
        self.headers = headers
        self.body = body
    }
}

/// What a run produced, normalized across platforms.
///
/// The four script platforms disagree about how to say the same thing, and the
/// differences are all in `$done`'s argument: a status is a number here and a
/// status line there, a body is a string here and bytes there, a mock response
/// is a top-level object here and nested under `response` there. This is the one
/// shape the tunnel acts on.
public enum ScriptOutcome: Equatable, Sendable {
    /// The script said nothing, or said `{}`: let the traffic through.
    case unchanged
    /// The request phase produced a changed request.
    case request(ScriptRequest)
    /// The request phase produced a response of its own (a mock), or the
    /// response phase produced a changed response.
    case response(ScriptResponse)
    /// The script asked for the connection to end.
    case drop(String)
    /// The script aborted with `{abort: true}` or a fatal error.
    case aborted(String)
    /// No answer arrived inside the script's budget.
    case timedOut
    /// The run could not start at all.
    case unavailable(String)
    /// What a `cron` or `generic` script handed back for its entry point to
    /// show. Loon calls this "一个结果对象，供调用入口展示或消费"; the hub's node checks
    /// exist only to produce it (a node's country, its unlock status), so an
    /// outcome that dropped it would have run them for nothing.
    case result(ScriptResult)
}
