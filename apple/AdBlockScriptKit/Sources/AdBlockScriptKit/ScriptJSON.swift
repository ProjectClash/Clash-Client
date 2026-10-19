import Foundation

/// A value of a module argument, as `$argument` carries it.
///
/// Loon's `[Argument]` section declares types (`select "true" "false"`,
/// `input`, `switch`), and scripts read `$argument.flag` expecting a boolean
/// there and a string elsewhere. The declared type is therefore kept rather
/// than flattening everything to text.
public enum ScriptArgumentValue: Equatable, Sendable {
    case text(String)
    case number(Double)
    case boolean(Bool)
    case empty

    /// Reads the usual spellings of a declared default.
    public init(_ raw: String, kind: String? = nil) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        switch (kind ?? "").lowercased() {
        case "switch", "bool", "boolean", "toggle":
            self = .boolean(["1", "true", "yes", "on"].contains(trimmed.lowercased()))
        case "number", "int", "integer", "float", "double":
            if let value = Double(trimmed) { self = .number(value) } else { self = .text(raw) }
        default:
            // Untyped defaults stay text; a script comparing with `=== 'true'`
            // must not be handed a boolean.
            self = .text(raw)
        }
    }

    public var jsonObject: Any {
        switch self {
        case .text(let value): return value
        case .number(let value): return value
        case .boolean(let value): return value
        case .empty: return NSNull()
        }
    }
}

/// Decodes the base64 marker the prelude uses for binary values.
///
/// The wire format between prelude and runner is JSON, which has no bytes; only
/// bodies and explicitly binary values pay the base64 cost, and only when a
/// script actually touches them.
public enum ScriptJSON {
    public static let bytesMarker = "$clashBytes"

    public static func decode(_ data: Data) -> Any? {
        guard !data.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    /// The bytes behind a `{"$clashBytes": "..."}` object.
    public static func bytes(_ value: Any?) -> Data? {
        guard let object = value as? [String: Any], let encoded = object[bytesMarker] as? String else { return nil }
        return Data(base64Encoded: encoded, options: [.ignoreUnknownCharacters])
    }

    public static func string(_ value: Any?) -> String? {
        switch value {
        case let text as String: return text
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }

    public static func flag(_ value: Any?) -> Bool {
        switch value {
        case let flag as Bool: return flag
        case let number as NSNumber: return number.boolValue
        case let text as String: return ["1", "true", "yes"].contains(text.lowercased())
        default: return false
        }
    }

    /// Headers as either a plain object (the common case) or Surge's
    /// `[{field, value}]` list, which preserves duplicate fields.
    public static func headers(_ value: Any?) -> ScriptHeaders? {
        if let list = value as? [[String: Any]] {
            var out = ScriptHeaders()
            for entry in list {
                guard let name = string(entry["field"]) ?? string(entry["name"]),
                      let value = string(entry["value"]) else { continue }
                out.add(name, value)
            }
            return out
        }
        if let object = value as? [String: Any] {
            var out = ScriptHeaders()
            for (name, value) in object {
                if let text = string(value) { out.add(name, text) }
            }
            return out
        }
        return nil
    }

    /// A payload from a `$done` argument.
    public static func payload(_ value: Any?) -> ScriptDonePayload {
        guard let object = value as? [String: Any] else { return ScriptDonePayload() }
        var payload = ScriptDonePayload()
        payload.status = string(object["status"])
        payload.statusCode = string(object["statusCode"])
        payload.url = string(object["url"])
        payload.headers = headers(object["headers"])
        payload.policy = string(object["policy"]) ?? string(object["node"])
        payload.abort = flag(object["abort"])
        if let text = object["body"] as? String {
            payload.text = text
            payload.hasBody = true
        } else if object["body"] != nil, !(object["body"] is NSNull) {
            if let bytes = bytes(object["body"]) {
                payload.bytes = bytes
                payload.hasBody = true
            }
        }
        if let bytes = bytes(object["bodyBytes"]) {
            payload.bytes = bytes
            payload.hasBody = true
        }
        if let nested = object["response"] as? [String: Any] {
            let inner = Self.payload(nested)
            payload.nestedResponse = ScriptDoneParsing.response(from: inner, base: nil)
        }
        return payload
    }
}
