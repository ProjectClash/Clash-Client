import Foundation
import XCTest
@testable import AdBlockScriptKit

/// A host that answers from a dictionary and records what was asked.
final class FakeServices: ScriptHostServices, ScriptSynchronousServices, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String] = [:]
    var httpAnswer: ScriptHostAnswer = .json(["status": 200, "headers": [:], "body": "ok"])
    private(set) var logged: [String] = []
    private(set) var notified: [ScriptNotification] = []
    private(set) var calls: [String] = []
    /// Answers `utils.gzip`/`utils.ungzip`. `nil` means "this fake cannot do
    /// it", which is the honest answer for the real host's compressed path.
    var compressionHandler: ((Data, Bool) -> Data?)?

    func perform(_ call: ScriptHostCall, completion: @escaping @Sendable (ScriptHostAnswer) -> Void) {
        lock.lock(); calls.append(call.name); lock.unlock()
        switch call.name {
        case "http":
            completion(httpAnswer)
        default:
            completion(.failure("unknown call \(call.name)"))
        }
    }

    func log(_ line: String, level: String) {
        lock.lock(); logged.append(line); lock.unlock()
    }

    func notify(_ notification: ScriptNotification) {
        lock.lock(); notified.append(notification); lock.unlock()
    }

    func synchronousAnswer(name: String, payload: Data) -> String {
        let object = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] ?? [:]
        lock.lock(); calls.append(name); lock.unlock()
        switch name {
        case "store.read":
            let key = object["key"] as? String ?? ""
            lock.lock(); let value = storage[key]; lock.unlock()
            return value.map { jsonString($0) } ?? "null"
        case "store.write":
            let key = object["key"] as? String ?? ""
            lock.lock()
            if let value = object["value"] as? String { storage[key] = value }
            else { storage.removeValue(forKey: key) }
            lock.unlock()
            return "true"
        case "config.getConfig":
            return jsonString("{}")
        case "utils.gzip", "utils.ungzip":
            // The prelude sends `{ "data": { "$clashBytes": base64 } }` and
            // expects the same shape back. Answering `null` here is what made
            // the earlier gzip measurement meaningless.
            guard let handler = compressionHandler,
                  let encoded = object["data"] as? [String: Any],
                  let text = encoded["$clashBytes"] as? String,
                  let data = Data(base64Encoded: text),
                  let out = handler(data, name == "utils.gzip") else { return "null" }
            return "{\"$clashBytes\":\"\(out.base64EncodedString())\"}"
        default:
            return "null"
        }
    }

    private func jsonString(_ text: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [text])
        return String(decoding: data.dropFirst().dropLast(), as: UTF8.self)
    }
}

/// An engine that runs nothing but reports what it was asked to evaluate. Used
/// to test the runner's bookkeeping without JavaScript.
final class StubEngine: JSEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var hooks: JSEngineHooks?
    private(set) var evaluated: [String] = []
    var onEvaluate: (@Sendable (String) -> Void)?

    func install(_ hooks: JSEngineHooks) throws { self.hooks = hooks }
    func evaluate(_ script: String, sourceURL: String?) throws {
        lock.lock(); evaluated.append(script); lock.unlock()
        onEvaluate?(script)
    }
    func resolve(callbackID: Int, answer: ScriptHostAnswer) {}
    func fireTimer(_ id: Int) {}
    func isUsable() -> Bool { true }
}

func makeRequest(body: Data? = nil) -> ScriptRequest {
    ScriptRequest(method: "GET", url: "https://example.com/a",
                  headers: ScriptHeaders([(name: "Accept", value: "*/*")]), body: body)
}

func makeResponse(body: Data? = nil) -> ScriptResponse {
    ScriptResponse(status: 200, headers: ScriptHeaders([(name: "Content-Type", value: "application/json")]), body: body)
}
