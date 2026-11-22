import Foundation
import Clash
import OSLog

enum ProxyImportContext: String {
    case singleNode
    case nodeBundle
    case subscriptionBody
    case configuration
}

struct ProxyImportIssue: Equatable {
    let index: Int
    let scheme: String
    let code: String
    let message: String

     
     
     
     
     
     
    var alsoNotHonoured: [String] = []

     
     
     
     
     
     
    var line: Int?

     
     
     
     
     
     
     
     
    var proxy: String = ""
}

 
 
 
 
struct ProxyPayloadShape: Equatable {
    let isConfiguration: Bool
    let hasInlineProxies: Bool
    let hasProxyProviders: Bool
    let recognizedKeys: [String]
    let unrecognizedKeys: [String]

     
     
    var carriesRouting: Bool {
        recognizedKeys.contains { ["proxy-groups", "rules", "proxy-providers", "rule-providers"].contains($0) }
    }
}

struct ProxyImportResult {
    let format: String
    let context: ProxyImportContext
    let proxies: [[String: Any]]

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    let skipped: [ProxyImportIssue]

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    let notHonoured: [ProxyImportIssue]

     
     
     
     
     
     
     
     
     
     
     
     
    let identities: [String]
    let shape: ProxyPayloadShape?

    var issues: [ProxyImportIssue] {
        skipped
    }

     
     
     
     
     
    func duplicateNodeOffsets() -> [Int] {
        guard !identities.isEmpty, identities.count == proxies.count else { return [] }
        var seen = Set<String>()
        return identities.enumerated().compactMap {
            seen.insert($0.element).inserted ? nil : $0.offset
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func explanation(for issue: ProxyImportIssue) -> String {
        guard !issue.alsoNotHonoured.isEmpty else { return issue.message }
        return issue.message + "; " + issue.alsoNotHonoured.joined(separator: "; ")
    }

     
     
     
     
     
    var sentence: String {
        let folded = duplicateNodeOffsets().count
        var clauses: [String] = []
        if !skipped.isEmpty {
            clauses.append(String(format: String(localized: "%d not imported"), skipped.count))
        }
        if folded > 0 {
            clauses.append(String(format: String(localized: "%d duplicate"), folded))
        }
        clauses.append(String(
            format: String(localized: "%d imported"), proxies.count - folded
        ))
        return clauses.joined(separator: " · ")
    }

    func fieldsLeftBehind() -> [String: [ProxyImportIssue]] {
        Dictionary(grouping: notHonoured.filter { !$0.proxy.isEmpty }, by: \.proxy)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    func summarySentence(renamed: [(from: String, to: String)] = [],
                         duplicatesFolded: Int = 0) -> String {
        var parts: [String] = []
        parts.append("\(proxies.count) imported")
        if !issues.isEmpty { parts.append("\(issues.count) skipped") }
        if duplicatesFolded > 0 { parts.append("\(duplicatesFolded) duplicates not imported") }
        if !renamed.isEmpty {
            let shown = renamed.prefix(3)
                .map { "\($0.from) → \($0.to)" }
                .joined(separator: ", ")
            let more = renamed.count > 3 ? " and \(renamed.count - 3) more" : ""
            parts.append("renamed \(shown)\(more)")
        }
        if !notHonoured.isEmpty { parts.append("\(notHonoured.count) fields did not carry over") }
        return parts.joined(separator: " · ")
    }
}

enum ProxyImportBridgeError: LocalizedError {
    case bridgeReturnedNil(String)
    case invalidResult
    case rejected([ProxyImportIssue])
     
     
     
     
    case refusedConfiguration(reason: String, nodes: Int)
     
     
     
    case overrideScript

     
     
     
     
     
     
    static let overrideScriptMessage = "This is an override script. Add it under the configuration’s Override Script."

    var errorDescription: String? {
        switch self {
        case .bridgeReturnedNil(let message):
            return message
        case .invalidResult:
            return "The share link could not be read."
        case .overrideScript:
            return Self.overrideScriptMessage
        case .refusedConfiguration(let reason, _):
            return reason
        case .rejected(let issues):
             
             
             
             
             
             
            guard let first = issues.first else {
                return "That text does not contain a node share link."
            }
            return first.message
        }
    }
}

 
 
 
 
 
 
 
 
enum OverrideScriptSniff {
    private static let opening = try! NSRegularExpression(
        pattern: #"\A\x{FEFF}?\s*(?:/\*|//|(?:async\s+)?function\b|(?:const|let|var)\s|main\s*=|["']use strict["'])"#)
    private static let definesMain = try! NSRegularExpression(
        pattern: #"^\x{FEFF}?[ \t]*(?:(?:async[ \t]+)?function[ \t]*main[ \t]*\(|(?:(?:const|let|var)[ \t]+)?main[ \t]*=[^=])"#,
        options: [.anchorsMatchLines])
     
     
    private static let openingLength = 4096

    static func isOverrideScript(_ text: String) -> Bool {
        let start = String(text.prefix(openingLength))
        guard opening.firstMatch(in: start, range: NSRange(start.startIndex..., in: start)) != nil else { return false }
        return definesMain.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}

 
 
 
struct ProxyImportSummary: Equatable {
    let format: String
    let count: Int
    let skippedCount: Int
    let notHonouredCount: Int
    var shape: ProxyPayloadShape? = nil
}

 
 
 
enum ProxyImportBridge {
     
     
     
     
     
    static func read(_ data: Data, context: ProxyImportContext) throws -> ProxyImportResult {
        try decode(data, context: context) { AppCore.readProxyPayload(data, context.rawValue, $0) }
    }

    static func inspect(_ data: Data, context: ProxyImportContext) throws -> ProxyImportResult {
        try decode(data, context: context) { AppCore.inspectProxyPayload(data, context.rawValue, $0) }
    }

     
     
     
    static func inspectSummary(_ data: Data, context: ProxyImportContext) throws -> ProxyImportSummary {
        try summary { AppCore.inspectProxyPayloadSummary(data, context.rawValue, $0) }
    }

     
    static func readSummary(_ data: Data, context: ProxyImportContext) throws -> ProxyImportSummary {
        try summary { AppCore.readProxyPayloadSummary(data, context.rawValue, $0) }
    }

    private static func summary(_ call: (NSErrorPointer) -> ClashStringBox?) throws -> ProxyImportSummary {
        var error: NSError?
        guard let box = call(&error) else {
            throw error.map { ProxyImportBridgeError.bridgeReturnedNil($0.localizedDescription) }
                ?? ProxyImportBridgeError.bridgeReturnedNil("The share link could not be read.")
        }
        guard let root = try JSONSerialization.jsonObject(with: Data(box.value.utf8)) as? [String: Any],
              let format = root["format"] as? String,
              let count = (root["count"] as? NSNumber)?.intValue else {
            throw ProxyImportBridgeError.invalidResult
        }
        return ProxyImportSummary(format: format, count: count,
                                  skippedCount: (root["skippedCount"] as? NSNumber)?.intValue ?? 0,
                                  notHonouredCount: (root["notHonouredCount"] as? NSNumber)?.intValue ?? 0,
                                  shape: shape(root["payloadShape"]))
    }

    private static func decode(_ data: Data, context: ProxyImportContext,
                               _ call: (NSErrorPointer) -> ClashStringBox?) throws -> ProxyImportResult {
        var error: NSError?
        guard let box = call(&error) else {
            throw error.map { ProxyImportBridgeError.bridgeReturnedNil($0.localizedDescription) }
                ?? ProxyImportBridgeError.bridgeReturnedNil("The share link could not be read.")
        }
        guard let root = try JSONSerialization.jsonObject(with: Data(box.value.utf8))
                as? [String: Any],
              let format = root["format"] as? String,
              let rawContext = root["context"] as? String,
              let decodedContext = ProxyImportContext(rawValue: rawContext),
              let proxies = root["proxies"] as? [[String: Any]] else {
            throw ProxyImportBridgeError.invalidResult
        }
        return ProxyImportResult(
            format: format,
            context: decodedContext,
            proxies: proxies,
             
             
             
             
             
            skipped: issues(root["skipped"])
                + issues(root["rejectedRecords"])
                + issues(root["recognizedUnsupported"]),
            notHonoured: issues(root["notHonoured"]),
            identities: root["identities"] as? [String] ?? [],
            shape: shape(root["payloadShape"])
        )
    }

     
     
     
     
     
     

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func derivedSubscriptionYAML(from source: Data, nodesOnly: Bool = false) throws -> String {
        try derivedSubscription(from: source, nodesOnly: nodesOnly).yaml
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func bareNodesDocument(_ text: String) -> String? {
         
        guard text.utf8.count <= 16 * 1024,
              let json = try? ConfigTransforms.yamlToJSON(text),
              let node = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              node["name"] is String, node["type"] is String, node["server"] != nil,
              Self.containerKeys.allSatisfy({ node[$0] == nil }),
              !Self.routesOrListens(node),
              let wrapped = try? JSONSerialization.data(withJSONObject: ["proxies": [node]]),
              let yaml = try? ConfigTransforms.jsonToYAML(String(decoding: wrapped, as: UTF8.self)),
              let read = try? inspect(Data(yaml.utf8), context: .subscriptionBody),
              read.proxies.count == 1, read.issues.isEmpty else { return nil }
        return yaml
    }

     
     
    private static let containerKeys = [
        "proxies", "servers", "outbounds", "proxy-providers", "proxy-groups", "rules", "rule-providers", "sub-rules",
        "tun",
    ]

     
     
     
     
    private static func routesOrListens(_ top: [String: Any]) -> Bool {
        if top["dns"] is [String: Any] { return true }
        if let mode = top["mode"] as? String, ["rule", "global", "direct"].contains(mode.lowercased()) { return true }
        if let listeners = top["listeners"] as? [Any], listeners.contains(where: { $0 is [String: Any] }) { return true }
        return false
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func derivedSubscription(
        from original: Data, nodesOnly: Bool = false
    ) throws -> (yaml: String, kept: Int, skipped: [ProxyImportIssue]) {
        guard let pasted = String(data: original, encoding: .utf8) else {
            throw SubscriptionError.notUTF8
        }
        let text = bareNodesDocument(pasted) ?? pasted
        let source = text == pasted ? original : Data(text.utf8)
        var sourceValidationError: Error?
        var validated = false
        do {
            try ConfigTransforms.validateSource(text)
            validated = true
        } catch {
            sourceValidationError = error
        }
        AppCore.returnFreeMemoryNow(after: text)
         
         
         
         
         
         
         
         
#if !os(tvOS)
        if let refusal = sourceValidationError as? ConfigTransformsError,
           case .invalidConfiguration(let reason) = refusal,
           OverrideScriptSniff.isOverrideScript(pasted) {
            capabilityLog.notice(
                "proxy import: an override script, refused as configuration -- \(reason, privacy: .public)"
            )
            throw ProxyImportBridgeError.overrideScript
        }
#endif
         
         
         
         
         
        if validated, text.utf8.count >= ConfigTransforms.ruleSectionCutFromBytes,
           TopLevelYAMLSections.keyLines(of: text)?.contains(where: { $0.key == "rules" }) == true {
            return (text, 0, [])
        }
         
         
         
         
         
        let summarized = Result { try readSummary(source, context: .subscriptionBody) }

        if validated {
             
             
             
             
             
             
             
             
            if let shape = try? summarized.get().shape, shape.isConfiguration {
                return (text, 0, [])
            }
        }

        if !nodesOnly, case ConfigTransformsError.invalidConfiguration(let reason)? = sourceValidationError,
           let shape = try? summarized.get().shape, shape.carriesRouting {
             
             
             
             
             
            let nodes = (try? inspectSummary(source, context: .subscriptionBody).count) ?? 0
            throw ProxyImportBridgeError.refusedConfiguration(reason: reason, nodes: nodes)
        }

        let result: ProxyImportResult
        do {
            result = try inspect(source, context: .subscriptionBody)
        } catch {
             
             
             
             
             
             
            throw validated ? error : (sourceValidationError ?? error)
        }
        guard !result.proxies.isEmpty else {
            throw result.issues.isEmpty
                ? (sourceValidationError ?? ProxyImportBridgeError.invalidResult)
                : ProxyImportBridgeError.rejected(result.issues)
        }
        log(skipped: result.issues, keeping: result.proxies.count)
        log(notHonoured: result.notHonoured)
        let data = try JSONSerialization.data(withJSONObject: ["proxies": result.proxies])
        let yaml = try ConfigTransforms.jsonToYAML(String(decoding: data, as: UTF8.self))
        return (yaml, result.proxies.count, result.issues)
    }

     
     
     
    private static func log(skipped issues: [ProxyImportIssue], keeping kept: Int) {
        guard !issues.isEmpty else { return }
        for issue in issues {
            let line = "record \(issue.index) (\(issue.scheme)): \(issue.code) -- \(issue.message)"
            capabilityLog.error(
                """
                proxy import: subscription kept \(kept) node(s) and skipped \
                \(issues.count) -- \(line, privacy: .public)
                """
            )
        }
    }

     
     
    static func log(notHonoured: [ProxyImportIssue]) {
        for issue in notHonoured {
            capabilityLog.notice(
                "proxy import: field left behind -- \(issue.message, privacy: .public)"
            )
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static let profilePasteNodeSchemes: Set<String> = {
        do {
            guard let schemes = try capabilityDocument()["schemes"] as? [[String: Any]] else {
                throw ProxyImportBridgeError.invalidResult
            }
            return Set(schemes.compactMap { item in
                guard item["pasteRole"] as? String == "node" else { return nil }
                return item["scheme"] as? String
            })
        } catch {
            let reason = error.localizedDescription
            capabilityLog.error(
                """
                proxy import: the Core capability registry is unreadable, so no \
                pasted scheme routes as a node -- \(reason, privacy: .public)
                """
            )
            return []
        }
    }()

    private static let capabilityLog = Logger(
        subsystem: "org.example.clash", category: "proxyimport")

    private static func capabilityDocument() throws -> [String: Any] {
        guard let box = ClashProxyImportCapabilitiesForIOS() else {
            throw ProxyImportBridgeError.bridgeReturnedNil(
                "The share link could not be read."
            )
        }
        guard let root = try JSONSerialization.jsonObject(with: Data(box.value.utf8))
                as? [String: Any] else {
            throw ProxyImportBridgeError.invalidResult
        }
        return root
    }

     
     
     
    private static func shape(_ raw: Any?) -> ProxyPayloadShape? {
        guard let d = raw as? [String: Any],
              let isConfiguration = d["isConfiguration"] as? Bool else { return nil }
        return ProxyPayloadShape(
            isConfiguration: isConfiguration,
            hasInlineProxies: d["hasInlineProxies"] as? Bool ?? false,
            hasProxyProviders: d["hasProxyProviders"] as? Bool ?? false,
            recognizedKeys: d["recognizedKeys"] as? [String] ?? [],
            unrecognizedKeys: d["unrecognizedKeys"] as? [String] ?? []
        )
    }

    static func issues(_ raw: Any?) -> [ProxyImportIssue] {
        guard let items = raw as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let index = item["index"] as? Int,
                  let scheme = item["scheme"] as? String,
                  let code = item["code"] as? String,
                  let message = item["message"] as? String else { return nil }
            return ProxyImportIssue(
                index: index, scheme: scheme, code: code, message: message,
                alsoNotHonoured: item["alsoNotHonoured"] as? [String] ?? [],
                line: item["line"] as? Int,
                 
                 
                 
                 
                 
                proxy: item["proxy"] as? String ?? ""
            )
        }
    }
}


 
 
 
final class ProxyPayloadPages: @unchecked Sendable {
    private let lock = NSLock()
    private var payload: ClashProxyPayload?
    let key: String

    private init(_ payload: ClashProxyPayload, key: String) {
        self.payload = payload
        self.key = key
    }

    private static let heldLock = NSLock()
    private static var held: ProxyPayloadPages?

     
    static func open(_ data: Data, context: ProxyImportContext, key: String) throws -> ProxyPayloadPages {
        heldLock.lock()
        if let held, held.key == key { heldLock.unlock(); return held }
        heldLock.unlock()
        var error: NSError?
        guard let opened = AppCore.openProxyPayload(data, context.rawValue, &error) else {
            throw error.map { ProxyImportBridgeError.bridgeReturnedNil($0.localizedDescription) } ?? ProxyImportBridgeError.invalidResult
        }
        let pages = ProxyPayloadPages(opened, key: key)
        heldLock.lock()
        let previous = held
        held = pages
        heldLock.unlock()
        previous?.close()
        return pages
    }

     
    func summary() throws -> (count: Int, issues: [ProxyImportIssue]) {
        let root = try object { $0.summaryJSON() }
        let count = root["count"] as? Int ?? 0
        return (count, ProxyImportBridge.issues(root["skipped"]) + ProxyImportBridge.issues(root["notHonoured"]))
    }

     
    func page(offset: Int, limit: Int) throws -> [[String: Any]] {
        let root = try object { $0.pageJSON(Int32(clamping: offset), limit: Int32(clamping: limit)) }
        return root["proxies"] as? [[String: Any]] ?? []
    }

    func close() {
        lock.lock()
        let payload = self.payload
        self.payload = nil
        lock.unlock()
        payload?.close()
    }

    deinit { payload?.close() }

    private func object(_ body: (ClashProxyPayload) -> String) throws -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        guard let payload else { throw ProxyImportBridgeError.invalidResult }
        let data = Data(body(payload).utf8)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProxyImportBridgeError.invalidResult
        }
        if let message = root["error"] as? String { throw ProxyImportBridgeError.bridgeReturnedNil(message) }
        return root
    }
}
