#if os(iOS) || os(macOS)
import AdBlockScriptKit
import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif
import zlib

/// The host services a script run receives in the tunnel.
///
/// Three jobs, and each is somewhere a shortcut would show up as a bug:
///
/// * **HTTP** goes through `AdBlockUpstreamOpening` — the same connector the
///   intercepted traffic uses — so a script's request follows the app's policy
///   and cannot reach around the proxy. Responses are read whole and bounded.
/// * **Storage** is one JSON file in the App Group, read and written under a
///   lock. The platforms keep one store for all scripts, so this does too; keys
///   are whatever the script used, including the `@boxjs.key.path` convention.
/// * **Notifications** go through `UNUserNotificationCenter`, which is the only
///   notification surface an extension may post to.
final class AdBlockScriptHost: ScriptHostServices, ScriptSynchronousServices, @unchecked Sendable {
    private let queue: DispatchQueue
    private let log: AdBlockEngineLog
    private let upstreams: AdBlockUpstreamOpening
    private let storage: ScriptStore
    private let notifier: ScriptNotifier
    private let geo: ScriptGeoLookup?

    init(queue: DispatchQueue, log: AdBlockEngineLog, upstreams: AdBlockUpstreamOpening,
         storageURL: URL?, notifier: ScriptNotifier = ScriptNotifier(), geo: ScriptGeoLookup? = nil) {
        self.queue = queue
        self.log = log
        self.upstreams = upstreams
        self.storage = ScriptStore(url: storageURL)
        self.notifier = notifier
        self.geo = geo
    }

    // MARK: - Calls

    func perform(_ call: ScriptHostCall, completion: @escaping @Sendable (ScriptHostAnswer) -> Void) {
        switch call.name {
        case "http":
            http(call.payload, completion: completion)
        case "utils.geoip", "utils.ipasn", "utils.ipaso":
            let object = (try? JSONSerialization.jsonObject(with: call.payload)) as? [String: Any] ?? [:]
            let ip = object["ip"] as? String ?? ""
            let answer = geo?.answer(name: call.name, ip: ip)
            completion(answer.map { .json($0) } ?? .json([:]))
        case "utils.gzip":
            compression(call.payload, compress: true, completion: completion)
        case "utils.ungzip":
            compression(call.payload, compress: false, completion: completion)
        default:
            completion(.failure("this host has no \(call.name)"))
        }
    }

    /// The answers a script may need before it returns: storage and the few
    /// configuration questions the platforms answer synchronously.
    func synchronousAnswer(name: String, payload: Data) -> String {
        let object = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] ?? [:]
        switch name {
        case "store.read":
            return storage.read(object["key"] as? String).map(Self.jsonString) ?? "null"
        case "store.write":
            if object["all"] as? Bool == true {
                storage.removeAll()
                return "true"
            }
            storage.write(object["value"] as? String, for: object["key"] as? String)
            return "true"
        default:
            // The configuration questions need the engine's policy state, which
            // this host cannot reach. `null` makes a script fall back to its own
            // defaults, which is what the platforms do when a group is missing.
            return "null"
        }
    }

    // MARK: - HTTP

    private func http(_ payload: Data, completion: @escaping @Sendable (ScriptHostAnswer) -> Void) {
        guard let object = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any],
              let urlText = object["url"] as? String, let url = URL(string: urlText),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else {
            return completion(.failure("the script asked for an address that is not http or https"))
        }
        let method = (object["method"] as? String ?? "GET").uppercased()
        let requested = object["timeout"] as? Double ?? 5000
        let binary = object["binaryMode"] as? Bool == true
        var headers: [(String, String)] = []
        if let raw = object["headers"] as? [String: Any] {
            for (name, value) in raw {
                if let text = value as? String { headers.append((name, text)) }
            }
        }
        var body: Data?
        if let encoded = object["body"] as? [String: Any], let text = encoded["$clashBytes"] as? String {
            body = Data(base64Encoded: text)
        } else if let text = object["body"] as? String {
            body = Data(text.utf8)
        }

        let port = UInt16(url.port ?? (scheme == "https" ? 443 : 80))
        let deadline = Date().addingTimeInterval(min(30, max(1, requested / 1000)))
        upstreams.open(authority: "\(host):\(port)", serverName: host, tls: scheme == "https") { [weak self] result in
            guard let self else { return completion(.failure("the tunnel stopped")) }
            switch result {
            case .failure(let failure):
                completion(.failure("the script's request failed: \(failure)"))
            case .success(let stream):
                self.exchange(stream: stream, url: url, method: method, headers: headers, body: body,
                              binary: binary, deadline: deadline, completion: completion)
            }
        }
    }

    /// Writes a request and reads its answer whole.
    ///
    /// Deliberately the small HTTP/1.1 client a script needs and no more: no
    /// redirects (the platforms leave that to the script), no connection reuse,
    /// and a hard size cap so one script cannot pull a gigabyte into the
    /// extension.
    private func exchange(stream: AdBlockStream, url: URL, method: String, headers: [(String, String)],
                          body: Data?, binary: Bool, deadline: Date,
                          completion: @escaping @Sendable (ScriptHostAnswer) -> Void) {
        let path = url.path.isEmpty ? "/" : url.path
        let target = url.query.map { "\(path)?\($0)" } ?? path
        var head = "\(method) \(target) HTTP/1.1\r\nHost: \(url.host ?? "")\r\n"
        var written = Set<String>(["host"])
        for (name, value) in headers where !written.contains(name.lowercased()) {
            head += "\(name): \(value)\r\n"
            written.insert(name.lowercased())
        }
        if !written.contains("connection") { head += "Connection: close\r\n" }
        if let body, !written.contains("content-length") { head += "Content-Length: \(body.count)\r\n" }
        head += "Accept-Encoding: identity\r\n\r\n"
        var payload = Data(head.utf8)
        if let body { payload.append(body) }

        let state = StreamExchange(stream: stream, deadline: deadline, binary: binary, completion: completion)
        stream.send(payload, isFinal: body == nil) { error in
            if let error { return state.fail("the script's request could not be sent: \(error)") }
            state.read()
        }
    }

    // MARK: - Compression

    private func compression(_ payload: Data, compress: Bool,
                             completion: @escaping @Sendable (ScriptHostAnswer) -> Void) {
        guard let object = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any],
              let encoded = object["data"] as? [String: Any],
              let text = encoded["$clashBytes"] as? String,
              let data = Data(base64Encoded: text) else {
            return completion(.failure("compression needs bytes"))
        }
        let result: Result<Data, AdBlockBodyDecoderError> = compress
            ? ScriptGzip.deflate(data).mapError { AdBlockBodyDecoderError.corrupt("\($0)") }
            : AdBlockBodyDecoder.decode(data, coding: .gzip, maximumOutputLength: 64 << 20).map(\.data)
        switch result {
        case .success(let out):
            completion(.json([ScriptJSON.bytesMarker: out.base64EncodedString()]))
        case .failure(let why):
            completion(.failure("compression failed: \(why.reason)"))
        }
    }

    /// The host a runner has before the tunnel gives it one: every call is
    /// answered "unavailable", which is what the exchange already reports for a
    /// build without scripts.
    static func placeholder(queue: DispatchQueue, log: AdBlockEngineLog) -> AdBlockScriptHost {
        AdBlockScriptHost(queue: queue, log: log, upstreams: NoUpstreams(), storageURL: nil)
    }

    private static func jsonString(_ text: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [text]) else { return "null" }
        return String(decoding: data.dropFirst().dropLast(), as: UTF8.self)
    }
}

private final class NoUpstreams: AdBlockUpstreamOpening {
    func open(authority: String, serverName: String, tls: Bool,
              completion: @escaping (Result<AdBlockStream, AdBlockUpstreamFailure>) -> Void) {
        completion(.failure(.unreachable("the tunnel has not started its engine yet")))
    }
}

/// GeoIP for the `$utils` lookups scripts use to decide which region's content
/// they are looking at. Optional: a build without a database answers empty,
/// which the platforms also do for an unknown address.
protocol ScriptGeoLookup: AnyObject, Sendable {
    /// `utils.geoip` → `{"value": "US"}`; `utils.ipasn` → `{"value": "13335"}`;
    /// `utils.ipaso` → `{"value": "Cloudflare"}`.
    func answer(name: String, ip: String) -> [String: Any]?
}

/// Reads a response off a stream until the connection closes.
private final class StreamExchange: @unchecked Sendable {
    private let stream: AdBlockStream
    private let deadline: Date
    private let binary: Bool
    private let completion: @Sendable (ScriptHostAnswer) -> Void
    private var buffer = Data()
    private var finished = false

    private static let maximumBytes = 16 << 20

    init(stream: AdBlockStream, deadline: Date, binary: Bool,
         completion: @escaping @Sendable (ScriptHostAnswer) -> Void) {
        self.stream = stream
        self.deadline = deadline
        self.binary = binary
        self.completion = completion
    }

    func read() {
        guard !finished else { return }
        if Date() > deadline { return fail("the script's request ran out of time") }
        stream.receive(maximumLength: 64 << 10) { [weak self] data, complete, error in
            guard let self, !self.finished else { return }
            if let data { self.buffer.append(data) }
            if self.buffer.count > Self.maximumBytes { return self.fail("the answer is larger than 16 MiB") }
            if let error { return self.fail("the answer could not be read: \(error)") }
            if complete { return self.finish() }
            self.read()
        }
    }

    func fail(_ why: String) {
        guard !finished else { return }
        finished = true
        stream.cancel()
        completion(.failure(why))
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        stream.cancel()
        guard case .head(let head, let consumed)? = try? AdBlockHTTPParser.response(buffer) else {
            return completion(.failure("the answer had no HTTP head"))
        }
        var body = Data(buffer[buffer.startIndex + consumed...])
        let chunked = head.headers.tokens("Transfer-Encoding").contains { $0.caseInsensitiveCompare("chunked") == .orderedSame }
        if chunked { body = (try? ChunkedBody.decode(body)) ?? body }
        // One coding at a time, as the tunnel's own body path does: a body with
        // two codings is left encoded for the script to deal with.
        let codings = AdBlockContentCoding.parse(head.headers.first("Content-Encoding"))
        if codings.count == 1, let coding = codings.first,
           let decoded = try? AdBlockBodyDecoder.decode(body, coding: coding, maximumOutputLength: 64 << 20) {
            body = decoded.data
        }
        var answer: [String: Any] = [
            "status": head.status,
            "headers": Dictionary(head.headers.fields.map { ($0.name, $0.value) }, uniquingKeysWith: { first, _ in first })
        ]
        if !binary, let text = String(data: body, encoding: .utf8) {
            answer["body"] = text
        } else {
            answer["bodyBytes"] = [ScriptJSON.bytesMarker: body.base64EncodedString()]
        }
        completion(.json(answer))
    }
}

/// Decodes a chunked body into its payload.
enum ChunkedBody {
    static func decode(_ data: Data) throws -> Data {
        var out = Data()
        var index = data.startIndex
        while index < data.endIndex {
            guard let lineEnd = data[index...].firstIndex(of: 0x0A) else { break }
            var line = data[index..<lineEnd]
            if line.last == 0x0D { line = line.dropLast() }
            let sizeText = String(decoding: line, as: UTF8.self).split(separator: ";").first ?? ""
            guard let size = Int(sizeText.trimmingCharacters(in: .whitespaces), radix: 16) else { break }
            index = data.index(after: lineEnd)
            guard size > 0 else { break }
            let end = data.index(index, offsetBy: size, limitedBy: data.endIndex) ?? data.endIndex
            out.append(data[index..<end])
            index = data.index(end, offsetBy: 2, limitedBy: data.endIndex) ?? data.endIndex
        }
        return out
    }
}

/// gzip for `$utils.gzip`, which some scripts use before storing a large value.
enum ScriptGzip {
    static func deflate(_ data: Data) -> Result<Data, String> {
        var stream = z_stream()
        guard deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 15 + 16, 8,
                            Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            return .failure("zlib could not start")
        }
        defer { deflateEnd(&stream) }
        var output = Data()
        let chunk = 32 * 1024
        let buffer = UnsafeMutablePointer<Bytef>.allocate(capacity: chunk)
        defer { buffer.deallocate() }
        let status: Int32 = data.withUnsafeBytes { raw in
            stream.next_in = UnsafeMutablePointer(mutating: raw.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(raw.count)
            var status: Int32 = Z_OK
            repeat {
                stream.next_out = buffer
                stream.avail_out = uInt(chunk)
                status = zlib.deflate(&stream, Z_FINISH)
                output.append(buffer, count: chunk - Int(stream.avail_out))
            } while status == Z_OK
            return status
        }
        guard status == Z_STREAM_END else { return .failure("zlib status \(status)") }
        return .success(output)
    }
}

/// Persistent storage shared by every script.
///
/// One JSON object in the App Group, as the platforms have one store per host.
/// A write rewrites the file; scripts write rarely and read often, and the cache
/// makes the reads free after the first.
/// Posts a script's notification.
///
/// An extension may only schedule notifications; it cannot present them, and
/// the system decides whether they show. That is the same contract the phone
/// platforms give a script, so a script that gets no banner still got what it
/// asked for.
final class ScriptNotifier: @unchecked Sendable {
    func post(_ notification: ScriptNotification) {
#if canImport(UserNotifications)
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.subtitle = notification.subtitle
        content.body = notification.body
        if let url = notification.openURL { content.userInfo["openUrl"] = url }
        if let clipboard = notification.clipboard { content.userInfo["clipboard"] = clipboard }
        if notification.sound == true { content.sound = .default }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
#endif
    }
}
#endif
