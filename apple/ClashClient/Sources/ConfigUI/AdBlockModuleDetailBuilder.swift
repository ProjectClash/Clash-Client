#if os(iOS) || os(macOS)
import ClashClientKit
import ClashClientUI
import Foundation

 
 
 
 
 
 
 
 
 
 
enum AdBlockModuleDetailBuilder {
    typealias Item = ClashAdBlockModuleDetailSnapshot.Item
    typealias Section = ClashAdBlockModuleDetailSnapshot.Section

     
     
     
    enum Decryption: Equatable {
        case off
         
        case notReady(Why)
        case working

        enum Why: Equatable {
             
            case certificate
             
            case preparing
             
            case unavailable
        }

         
         
         
         
         
        var waiting: ClashDisplayText? {
            switch self {
            case .off: return "Needs HTTPS Decryption"
            case .notReady(.certificate): return "Certificate Needed"
            case .notReady(.preparing): return "Getting Ready"
            case .notReady(.unavailable): return "Not Available Yet"
            case .working: return nil
            }
        }
    }

     
     
     
    static func detail(record: AdBlockModuleRecord, facts: AdBlockPageFacts, source text: Data?, isUpdating: Bool,
                       locale: Locale) -> ClashAdBlockModuleDetailSnapshot {
        var out = detail(record: record, ir: facts.modules[record.id], source: text, decryption: AdBlockPageSnapshotBuilder.decryption(facts),
                         isUpdating: isUpdating, locale: locale, publication: facts.summary)
         
         
         
         
        if facts.isConnected, record.enabled,
           let omitted = facts.report?.omittedModules.first(where: { $0.id == record.id }) {
            out.failure = AdBlockEngineInsight.Copy.leftOut(omitted).displayText
            out.failureIsSentence = true
            if !omitted.detail.isEmpty {
                let item = Item(id: "left-out", text: omitted.detail)
                if let index = out.sections.firstIndex(where: { $0.id == "skipped" }) {
                    out.sections[index].items.insert(item, at: 0)
                } else {
                    out.sections.append(Section(id: "skipped", title: "Skipped", items: [item]))
                }
                out.ignoredCount += 1
            }
        }
        return out
    }

     
     
     
     
     
    static func detail(record: AdBlockModuleRecord, ir: AdBlockModuleIR?, source text: Data?, decryption: Decryption,
                       isUpdating: Bool, locale: Locale, publication: AdBlockPublicationSummary? = nil) -> ClashAdBlockModuleDetailSnapshot {
        let source: ClashAdBlockModuleSource
        let failure: ClashDisplayText?
        var failureIsSentence = false
        let lines = ir.flatMap { writtenLines(text, of: $0) }
        let ir = ir.map { published($0, record: record, publication: publication, written: lines) }
        let row = AdBlockPageSnapshotBuilder.row(record, ir: ir, locale: locale, decryption: decryption, written: lines)
         
        let unreadFailure: ClashDisplayText? = record.failureFromALaterBuild ? "Update failed" : nil
        switch record.origin {
        case .url(let link):
            source = .link(link)
             
             
            failure = record.lastFailure.map { AdBlockStoredSentence.failure($0, linked: true).displayText } ?? unreadFailure
             
            failureIsSentence = record.lastFailure != nil
        case .local:
            source = .local
             
             
             
             
            failure = record.lastFailure.map { AdBlockStoredSentence.failure($0, linked: false).displayText } ?? unreadFailure
            failureIsSentence = record.lastFailure != nil
        case .unknown:
             
            source = .unknown
            failure = row.failure.map { _ in "Update failed" }
        }
        let sections = ir.map { self.sections($0, written: lines, waiting: decryption.waiting) } ?? []
         
        let counts = ir.map { self.counts($0, decryption: decryption, written: lines) } ?? Counts(kept: 0, waiting: 0)
        return ClashAdBlockModuleDetailSnapshot(
            id: record.id, name: row.name, summary: written(ir?.manifest.desc), author: written(ir?.manifest.author),
            source: source, updatedAt: record.lastUpdatedAt, enabled: record.enabled, effectiveCount: counts.kept,
            ignoredCount: row.ignoredCount, failure: failure, isUpdating: isUpdating, sections: sections,
            needsDecryptionCount: counts.waiting, failureIsSentence: failureIsSentence)
    }

     

     
     
     
     
     
    struct Counts: Equatable {
        var kept: Int
        var waiting: Int

         
         
         
         
         
        func shown(enabled: Bool) -> Int { enabled ? max(0, kept - waiting) : kept }
    }

     
     
     
     
    static func counts(_ ir: AdBlockModuleIR, decryption: Decryption, written: [Substring]? = nil) -> Counts {
        let settingEntries = ir.hosts.count + ir.edits.count + ir.deviceSettings.count + ir.inEffect.count
        let kept = ir.effectiveCount - settingEntries + settingItems(ir, written: written).count
        let waiting = decryption.waiting == nil ? 0
            : (ir.mitmHostLines + ir.forceHTTPEngineHostLines).reduce(0) { $0 + $1.entries.count }
                + ir.rewriteRules.count + ir.engineRules.count + ir.scripts.count
        return Counts(kept: kept, waiting: waiting)
    }

     
     
     
     
     

     

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func published(_ ir: AdBlockModuleIR, record: AdBlockModuleRecord, publication: AdBlockPublicationSummary?,
                          written: [Substring]? = nil) -> AdBlockModuleIR {
        guard record.enabled, let publication else { return ir }
        let skipped = publication.skipped ?? []
        let withheld = (publication.changes ?? []).filter { !$0.applied }
        guard !skipped.isEmpty || !withheld.isEmpty else { return ir }
        var ir = ir
        let ruleOrigin = AdBlockActivationStep.moduleRuleOrigin
        let rules = Set(ir.routingRules.map(rendered))
        let sets = Set(ir.ruleSets.flatMap(ruleSetNames))
        let settings = Set(ir.edits.map(\.origin) + ir.hosts.map(\.origin) + ir.deviceSettings.map(\.origin)
                           + ir.inEffect.map(\.origin) + ir.changes.map(\.origin))
        var mine: [AdBlockIgnoredEntry] = []
        var leftOutRules = Set<String>()
        var leftOutLines = Set<AdBlockLineOrigin>()
        var refusal: AdBlockIgnoredReason?
        for entry in skipped {
            var said = entry
            if case .settingsRefused = entry.reason {
                 
                 
                guard (entry.moduleID ?? entry.text) == record.id else { continue }
                if refusal == nil { refusal = entry.reason }
                continue
            } else if entry.origin == ruleOrigin {
                guard rules.contains(entry.text) || sets.contains(entry.text) else { continue }
                leftOutRules.insert(entry.text)
            } else {
                guard entry.moduleID == record.id, settings.contains(entry.origin) else { continue }
                leftOutLines.insert(entry.origin)
                said.text = writtenLine(entry.origin, in: written) ?? entry.text
            }
            mine.append(said)
        }
        let refused = refusal != nil
        if let refusal {
             
            for origin in settingsLines(of: ir) {
                guard let text = writtenLine(origin, in: written) ?? writtenKey(origin, in: ir) else { continue }
                mine.append(AdBlockIgnoredEntry(text: text, reason: refusal, origin: origin, moduleID: record.id))
            }
        }
        ir.routingRules.removeAll { leftOutRules.contains(rendered($0)) }
        ir.ruleSets.removeAll { !leftOutRules.isDisjoint(with: ruleSetNames($0)) }
        if refused {
             
            ir.edits = []
            ir.hosts = []
            ir.deviceSettings = []
        } else {
            ir.edits.removeAll { leftOutLines.contains($0.origin) }
            ir.hosts.removeAll { leftOutLines.contains($0.origin) }
            ir.deviceSettings.removeAll { leftOutLines.contains($0.origin) }
            ir.inEffect.removeAll { leftOutLines.contains($0.origin) }
        }
        ir.changes = ir.changes.map { change in
            var change = change
            if refused || leftOutLines.contains(change.origin)
                || withheld.contains(where: { $0.key == change.key && $0.origin == change.origin && $0.value == change.value }) {
                change.applied = false
            }
            return change
        }
         
         
        var said = Set(ir.ignored.map { "\($0.text)\u{0}\($0.reason)" })
        ir.ignored += mine.filter { said.insert("\($0.text)\u{0}\($0.reason)").inserted }
        return ir
    }

     
    private static func ruleSetNames(_ set: AdBlockRuleSet) -> [String] {
         
        [set.url, ruleSetLine(set), set.reference].compactMap { $0 }
    }

     
     
     
     
    static func settingsLines(of ir: AdBlockModuleIR) -> [AdBlockLineOrigin] {
        var seen = Set<AdBlockLineOrigin>()
        let all = (ir.edits.map(\.origin) + ir.hosts.map(\.origin) + ir.deviceSettings.map(\.origin) + ir.changes.map(\.origin))
            .filter { seen.insert($0).inserted }
        guard ir.manifest.format != .stash else { return all }
        return all.enumerated().sorted { ($0.element.line, $0.offset) < ($1.element.line, $1.offset) }.map(\.element)
    }

     
     
     
     
     
     
    static func writtenKey(_ origin: AdBlockLineOrigin, in ir: AdBlockModuleIR) -> String? {
        if ir.manifest.format == .stash { return origin.section }
        if let kept = ir.inEffect.first(where: { $0.origin == origin }) { return kept.key }
        if let host = ir.hosts.first(where: { $0.origin == origin }) { return host.pattern }
        if let setting = ir.deviceSettings.first(where: { $0.origin == origin }) { return writtenKey(setting.key) }
        return ir.edits.first { $0.origin == origin && !isWorkedOut($0) }.map { $0.path.joined(separator: ".") }
    }

     
     
    static func writtenKey(_ key: AdBlockDeviceSettingKey) -> String {
        switch key {
        case .hideVPNIcon: return "hide-vpn-icon"
        case .includeAllNetworks: return "include-all-networks"
        case .includeLocalNetworks: return "include-local-networks"
        case .includeAPNs: return "include-apns"
        case .includeCellularServices: return "include-cellular-services"
        case .homeKitCompatibility: return "compatibility-mode"
        case .testURL: return "proxy-test-url"
        }
    }

     
     
     
    static func isWorkedOut(_ edit: AdBlockConfigurationEdit) -> Bool {
        switch edit.operation {
        case .copyIfAbsent, .serverParameter, .nameserversWithParameter, .engineRoute: return true
        case .replace, .append, .prepend, .merge, .replaceIfAbsent: return false
        }
    }

     
    private static func written(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

     
     
     
     
    static func sections(_ ir: AdBlockModuleIR, written: [Substring]?, waiting waits: ClashDisplayText?) -> [Section] {
        let numbered = ir.manifest.format != .stash
        let files = fileAddresses(ir)
        let all: [(id: String, title: ClashDisplayText, items: [Item], waits: ClashDisplayText?)] = [
            ("hosts", "Sites", siteItems(ir), waits),
            ("rules", "Rules", ruleItems(ir, written: written, waiting: waits), nil),
            ("rewrites", "Rewrites", ir.rewriteRules.enumerated().map {
                rewriteItem($0.element, index: $0.offset, files: files[$0.offset] ?? [])
            }, waits),
            ("settings", "Settings", settingItems(ir, written: written), nil),
             
            ("scripts", "Scripts", ir.scripts.enumerated().map {
                // A `generic` script is the one kind the app runs on request:
                // it has no URL to match and no schedule, so the row is also
                // the place it is started from. The others run on their own —
                // an HTTP script when its pattern matches, a cron one when its
                // schedule comes round — and offering a button for those would
                // mean running them outside the conditions they were written
                // for.
                let script = $0.element
                let runnable = script.phase == .generic ? script.bodySHA256 : nil
                // A generic script's row carries what it last answered, if it
                // has been run: these scripts exist to produce that panel, and
                // a row that shows only the script's name would hide the whole
                // point of pressing the button.
                let answered = script.bodySHA256.flatMap { facts.scriptResults[$0] }
                return Item(id: "script-\($0.offset)", text: script.name,
                            detail: answered.map { ClashDisplayText(verbatim: $0.plainText) },
                            secondary: script.pattern,
                            action: runnable.map { ClashAdBlockSnapshot.NoticeAction.runScriptAgain(sha256: $0) })
            }, waits),
            ("skipped", "Skipped", ir.ignored.enumerated().map {
                Item(id: "skipped-\($0.offset)", text: $0.element.text, detail: $0.element.reason.authoredText.displayText,
                     place: numbered ? place($0.element.origin) : nil)
            }, nil),
        ]
        return all.filter { !$0.items.isEmpty }.map {
            Section(id: $0.id, title: $0.title, items: $0.items, waiting: $0.waits)
        }
    }

     
     
     
     
    static func place(_ origin: AdBlockLineOrigin) -> ClashDisplayText? {
        origin.line > 0 ? .format("Line %@", [String(origin.line)]) : nil
    }

     
     
     
    static func writtenLines(_ text: Data?, of ir: AdBlockModuleIR) -> [Substring]? {
        guard let text, ir.manifest.format != .stash, AdBlockJSON.sha256(text) == ir.manifest.contentSHA256,
              var read = String(data: text, encoding: .utf8) else { return nil }
         
        if read.hasPrefix("\u{FEFF}") { read.removeFirst() }
        read = read.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return read.split(separator: "\n", omittingEmptySubsequences: false)
    }

     

     
     
    static func siteItems(_ ir: AdBlockModuleIR) -> [Item] {
        let decrypted = ir.mitmHostLines.flatMap(\.entries).map(\.spelling)
        let plain = ir.forceHTTPEngineHostLines.flatMap(\.entries).map(\.spelling)
        return decrypted.enumerated().map { Item(id: "site-\($0.offset)", text: $0.element) }
            + plain.enumerated().map { Item(id: "plain-\($0.offset)", text: $0.element, detail: .verbatim("HTTP")) }
    }

     

     
     
     
     
     
    static func ruleItems(_ ir: AdBlockModuleIR, written: [Substring]?, waiting: ClashDisplayText?) -> [Item] {
        let routing = ir.routingRules.enumerated().map { index, rule in
            Item(id: "rule-\(index)", text: writtenLine(rule.origin, in: written) ?? rendered(rule))
        }
        let engine = ir.engineRules.enumerated().map { index, rule in
            Item(id: "engine-\(index)", text: spelling(rule.condition) + "," + decision(rule.decision),
                 detail: waiting)
        }
        let sets = ir.ruleSets.enumerated().map { index, set in
            Item(id: "ruleset-\(index)", text: ruleSetLine(set), secondary: set.inline.map { $0.joined(separator: ", ") })
        }
        return routing + engine + sets
    }

     
     
    static func writtenLine(_ origin: AdBlockLineOrigin, in lines: [Substring]?) -> String? {
        guard let lines, origin.line > 0, origin.line <= lines.count else { return nil }
        let line = AdBlockModuleParser.strippingComment(lines[origin.line - 1].trimmingCharacters(in: .whitespaces))
        return line.isEmpty ? nil : line
    }

     
     
     
     
     
    static func rendered(_ rule: AdBlockRoutingRule) -> String {
        let name = rule.policy.kernelName ?? policy(rule.policy)
        return ([rule.head] + (name.isEmpty ? [] : [name]) + rule.params).joined(separator: ",")
    }

     
     
    static func policy(_ policy: AdBlockRulePolicy) -> String {
        switch policy {
        case .builtIn(let name), .named(let name): return name
        case .moduleChoice: return "PROXY"
        }
    }

    static func ruleSetLine(_ set: AdBlockRuleSet) -> String {
        let word: String
        let source: String?
        switch set.kind {
        case .classical, .provider: word = "RULE-SET"; source = set.url
        case .domainSet: word = "DOMAIN-SET"; source = set.url
        case .builtInLAN: word = "RULE-SET"; source = "LAN"
        case .builtInSystem: word = "RULE-SET"; source = "SYSTEM"
        }
         
        let from = source ?? (set.inline == nil ? nil : "inline")
        return ([word] + [from].compactMap { $0 } + [policy(set.policy)] + set.params).joined(separator: ",")
    }

     
     
    static func spelling(_ condition: AdBlockRuleCondition) -> String {
        func parts(_ conditions: [AdBlockRuleCondition]) -> String {
            "(" + conditions.map { "(" + spelling($0) + ")" }.joined(separator: ",") + ")"
        }
        switch condition {
        case .and(let conditions): return "AND," + parts(conditions)
        case .or(let conditions): return "OR," + parts(conditions)
        case .not(let condition): return "NOT," + parts([condition])
        case .urlRegex(let value): return "URL-REGEX," + value
        case .userAgent(let value): return "USER-AGENT," + value
        case .domain(let value): return "DOMAIN," + value
        case .domainSuffix(let value): return "DOMAIN-SUFFIX," + value
        case .domainKeyword(let value): return "DOMAIN-KEYWORD," + value
        case .domainWildcard(let value): return "DOMAIN-WILDCARD," + value
        case .domainRegex(let value): return "DOMAIN-REGEX," + value
        case .ipCIDR(let value): return (value.contains(":") ? "IP-CIDR6," : "IP-CIDR,") + value
        case .dstPort(let value): return "DST-PORT," + value
        case .network(let value): return "PROTOCOL," + value
        }
    }

     
     
    static func decision(_ decision: AdBlockEngineDecision) -> String {
        switch decision {
        case .pass: return "DIRECT"
        case .answer(let action):
            switch action {
            case .reject, .reject200, .rejectImg, .rejectTinyGif, .rejectDict, .rejectArray, .rejectDrop, .rejectNoDrop:
                return spelling(action).uppercased()
            case .redirect302, .redirect307, .transparent, .header, .bodyReplace, .bodyJQ, .localAnswer, .requestBody, .json:
                return spelling(action)
            }
        }
    }

     

     
     
     
    static func rewriteItem(_ rule: AdBlockRewriteRule, index: Int, files: [String] = []) -> Item {
        var files = files[...]
        let actions = rule.actions.map { action in
            spelling(action, file: waitsForAFile(action) ? files.popFirst() : nil)
        }.joined(separator: " | ")
        let condition = rule.condition.map(spelling)
        if !rule.pattern.isEmpty {
            return Item(id: "rewrite-\(index)", text: rule.pattern, detail: .verbatim(actions), secondary: condition)
        }
        if let condition {
            return Item(id: "rewrite-\(index)", text: condition, detail: .verbatim(actions))
        }
        return Item(id: "rewrite-\(index)", text: actions)
    }

     
     
     
    static func fileAddresses(_ ir: AdBlockModuleIR) -> [Int: [String]] {
        var left: [AdBlockLineOrigin: [String]] = [:]
        for reference in ir.answerFiles { left[reference.origin, default: []].append(reference.url) }
        var out: [Int: [String]] = [:]
        for (index, rule) in ir.rewriteRules.enumerated() {
            let wanted = rule.actions.filter(waitsForAFile).count
            guard wanted > 0, let queue = left[rule.origin], !queue.isEmpty else { continue }
            out[index] = Array(queue.prefix(wanted))
            left[rule.origin] = Array(queue.dropFirst(wanted))
        }
        return out
    }

     
    static func waitsForAFile(_ action: AdBlockRewriteAction) -> Bool {
        switch action {
        case .localAnswer(let answer):
            if case .file = answer.body { return true }
            return false
        case .requestBody(.file, _): return true
        case .bodyJQ(_, let expression, let sha256): return sha256 != nil || expression.isEmpty
        default: return false
        }
    }

     
     
     
    static func spelling(_ action: AdBlockRewriteAction, file: String? = nil) -> String {
        switch action {
        case .reject: return "reject"
        case .reject200: return "reject-200"
        case .rejectImg: return "reject-img"
        case .rejectTinyGif: return "reject-tinygif"
        case .rejectDict: return "reject-dict"
        case .rejectArray: return "reject-array"
        case .rejectDrop: return "reject-drop"
        case .rejectNoDrop: return "reject-no-drop"
        case .redirect302(let target): return "302 \(target)"
        case .redirect307(let target): return "307 \(target)"
        case .transparent(let target): return "transparent \(target)"
         
        case .header(_, let operation, let name, let arguments):
            return ([headerVerb(operation), name] + arguments).joined(separator: " ")
        case .bodyReplace(let phase, let pairs):
            let replaced = pairs.map { "\($0.search) → \($0.replacement)" }.joined(separator: ", ")
            return "\(bodyKeyword(phase)) \(replaced)"
        case .bodyJQ(let phase, let expression, let sha256):
             
            guard sha256 != nil || expression.isEmpty else { return "\(bodyKeyword(phase))-jq \(expression)" }
            return "\(bodyKeyword(phase))-jq jq-path" + (file.map { "=" + $0 } ?? "")
        case .localAnswer(let answer):
            var words = body(answer.body) + ["status-code=\(answer.status)"]
            if !answer.headers.isEmpty {
                words.append("header=\"\(answer.headers.map { "\($0.name):\($0.value)" }.joined(separator: "|"))\"")
            }
            return words.joined(separator: " ")
        case .requestBody(let requestBody, let contentType):
            return (["mock-request-body"] + body(requestBody) + [contentType.map { "content-type=\($0)" }].compactMap { $0 })
                .joined(separator: " ")
        case .json(let phase, let operations):
            return operations.map { json($0, phase: phase) }.joined(separator: " | ")
        }
    }

    static func headerVerb(_ operation: AdBlockHeaderOperation) -> String {
        switch operation {
        case .add: return "header-add"
        case .delete: return "header-del"
        case .replace: return "header-replace"
        case .replaceRegex: return "header-replace-regex"
        case .set: return "header-set"
        }
    }

    private static func bodyKeyword(_ phase: AdBlockRewritePhase) -> String {
        switch phase {
        case .request: return "http-request"
        case .response: return "http-response"
        }
    }

     
    static func body(_ body: AdBlockAnswerBody) -> [String] {
        switch body {
        case .empty: return ["data-type=text", #"data="""#]
        case .text(let text): return ["data-type=text", "data=\"\(text)\""]
        case .bytes(let data): return ["data-type=base64", "data=\"\(data.base64EncodedString())\""]
        case .file: return ["data-type=file"]
        case .tinyGIF: return ["data-type=tiny-gif"]
        case .emptyJSONObject: return ["data-type=text", #"data="{}""#]
        case .emptyJSONArray: return ["data-type=text", #"data="[]""#]
        case .emptyVideo: return ["reject-video"]
        }
    }

     
    static func json(_ operation: AdBlockJSONOperation, phase: AdBlockRewritePhase) -> String {
        let side: String
        switch phase {
        case .request: side = "request"
        case .response: side = "response"
        }
        switch operation {
        case .delete(let path): return "\(side)-body-json-del \(keyPath(path))"
        case .replace(let path, let value): return "\(side)-body-json-replace \(keyPath(path)) \(value)"
        case .add(let path, let value): return "\(side)-body-json-add \(keyPath(path)) \(value)"
         
        case .deleteIfTruthy(let path): return "\(side)-json-del \(keyPath(path))"
        case .replaceIfTruthy(let path, let value): return "\(side)-json-replace \(keyPath(path)) \(value)"
        case .addIfMissingOrNull(let path, let value): return "\(side)-json-add \(keyPath(path)) \(value)"
        }
    }

    static func keyPath(_ path: [AdBlockJSONPathComponent]) -> String {
        var out = ""
        for component in path {
            switch component {
            case .key(let key): out += out.isEmpty ? key : "." + key
            case .index(let index): out += "[\(index)]"
            case .every: out += "[*]"
            }
        }
        return out
    }

     
     
    static func spelling(_ condition: AdBlockCondition) -> String {
        func nested(_ condition: AdBlockCondition) -> String {
            if case .match = condition { return spelling(condition) }
            return "(" + spelling(condition) + ")"
        }
        switch condition {
        case .all(let conditions): return conditions.map(nested).joined(separator: " && ")
        case .any(let conditions): return conditions.map(nested).joined(separator: " || ")
        case .match(let variable, let comparison, let value, _):
            return [self.variable(variable), comparison.rawValue, self.value(value)].joined(separator: " ")
        }
    }

    private static func variable(_ variable: AdBlockConditionVariable) -> String {
        switch variable {
        case .url: return "${url}"
        case .requestMethod: return "${request.method}"
        case .requestHeader(let name): return "${request.header.\(name)}"
        case .responseStatus: return "${response.status}"
        case .responseHeader(let name): return "${response.header.\(name)}"
        }
    }

    private static func value(_ value: AdBlockConditionValue) -> String {
        switch value {
        case .regex(let pattern): return "/\(pattern)/"
        case .string(let text): return "\"\(text)\""
        case .number(let number):
            return number.rounded() == number && abs(number) < 1e15 ? String(Int64(number)) : String(number)
         
        case .null: return "null"
        }
    }

     

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func settingItems(_ ir: AdBlockModuleIR, written: [Substring]? = nil) -> [Item] {
        var items: [(line: Int, item: Item)] = []
        for (index, change) in ir.changes.enumerated() where change.applied {
            items.append((change.origin.line, Item(id: "change-\(index)", text: writtenLine(change.origin, in: written) ?? change.value,
                                                   detail: change.key.label.displayText)))
        }
         
         
        let changed = Set(ir.changes.map(\.origin))
        var listed = Set<AdBlockLineOrigin>()
        func line(_ origin: AdBlockLineOrigin, _ fallback: @autoclosure () -> Item?) {
            guard !changed.contains(origin) else { return }
            if let text = writtenLine(origin, in: written) {
                guard listed.insert(origin).inserted else { return }
                items.append((origin.line, Item(id: "line-\(origin.line)", text: text)))
            } else if let item = fallback() {
                items.append((origin.line, item))
            }
        }
        for (index, edit) in ir.edits.enumerated() {
            line(edit.origin, isWorkedOut(edit) ? nil : Item(id: "edit-\(index)", text: edit.path.joined(separator: "."),
                                                            detail: writtenValue(edit).map { .verbatim($0) }))
        }
        for (index, host) in ir.hosts.enumerated() {
            line(host.origin, Item(id: "hostmap-\(index)", text: host.pattern, detail: .verbatim(hostValue(host.value))))
        }
        for (index, kept) in ir.inEffect.enumerated() {
            line(kept.origin, Item(id: "kept-\(index)", text: kept.key))
        }
         
        guard ir.manifest.format != .stash, written != nil else { return items.map { $0.item } }
        return items.enumerated().sorted { ($0.element.line, $0.offset) < ($1.element.line, $1.offset) }.map { $0.element.item }
    }

     
     
     
     
     
     
    static func writtenValue(_ edit: AdBlockConfigurationEdit) -> String? {
        guard !isWorkedOut(edit), let data = edit.valueJSON.data(using: .utf8),
              let read = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        func word(_ value: Any) -> String? {
            switch value {
            case let text as String: return text
            case let number as NSNumber:
                return CFGetTypeID(number) == CFBooleanGetTypeID() ? (number.boolValue ? "true" : "false") : number.stringValue
             
            case let item as [String: Any]: return item["item"] as? String
            default: return nil
            }
        }
        if let list = read as? [Any] {
            let words = list.compactMap(word)
            return words.isEmpty ? nil : words.joined(separator: ", ")
        }
        return read is [String: Any] ? nil : word(read)
    }

     
    static func hostValue(_ value: AdBlockHostValue) -> String {
        switch value {
        case .addresses(let addresses): return addresses.joined(separator: ", ")
        case .name(let name): return name
         
        case .dnsServers(let servers): return "server:" + servers.joined(separator: ", ")
        case .systemDNS: return "server:system"
        case .ipMode(let mode): return "ip-mode:\(mode)"
        }
    }
}
#endif
