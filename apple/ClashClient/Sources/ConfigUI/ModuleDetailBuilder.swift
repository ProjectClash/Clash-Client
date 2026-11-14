#if os(iOS) || os(macOS)
import ClashClientKit
import ClashClientUI
import Foundation

 
 
 
 
 
 
 
 
 
 
enum ModuleDetailBuilder {
    typealias Item = ClashModuleDetailSnapshot.Item
    typealias Section = ClashModuleDetailSnapshot.Section

     
     
     
    enum Decryption: Equatable {
        case off
         
        case notReady(Why)
        case working

        enum Why: Equatable {
             
            case certificate
             
            case preparing
             
            case unavailable
             
             
             
             
            case onHold
        }

         
         
         
         
         
        var waiting: ClashDisplayText? {
            switch self {
            case .off: return "Needs HTTPS Decryption"
            case .notReady(.certificate): return "Certificate Needed"
            case .notReady(.preparing): return "Getting Ready"
            case .notReady(.unavailable): return "Not Available Yet"
            case .notReady(.onHold): return "On Hold for Now"
            case .working: return nil
            }
        }

         
         
        var wait: ClashModuleDecryptionWait? {
            switch self {
            case .off: return .off
            case .notReady(.onHold): return .onHold
            case .notReady: return .notReady
            case .working: return nil
            }
        }
    }

     
     
     
    static func detail(record: ModuleRecord, facts: ModulePageFacts, source text: Data?, isUpdating: Bool,
                       locale: Locale) -> ClashModuleDetailSnapshot {
         
        let counted = facts.modules[record.id].map { ModulePageSnapshotBuilder.counted(facts, record: record, ir: $0) }
        var out = detail(record: record, ir: facts.modules[record.id], source: text, decryption: ModulePageSnapshotBuilder.decryption(facts),
                         isUpdating: isUpdating, locale: locale, publication: facts.summary, storedValues: facts.storedValues,
                         settingsRefusal: facts.settingsModuleID == record.id ? facts.settingsFailure?.displayText : nil,
                         counted: counted,
                         scriptFile: facts.locations.map { locations in { locations.script(record.id, sha256: $0) } })
        out.panels = panels(record: record, ir: facts.modules[record.id], facts: facts)
         
         
         
         
        if facts.isConnected, record.enabled,
           let omitted = facts.report?.omittedModules.first(where: { $0.id == record.id }) {
            out.failure = ModuleEngineInsight.Copy.leftOut(omitted).displayText
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

     
     
     
     
     
     
     
    static func detail(record: ModuleRecord, ir: ModuleIR?, source text: Data?, decryption: Decryption,
                       isUpdating: Bool, locale: Locale, publication: ModulePublicationSummary? = nil,
                       storedValues: [String: String] = [:], settingsRefusal: ClashDisplayText? = nil,
                       counted: ModulePageSnapshotBuilder.Counted? = nil,
                       scriptFile: ((String) -> URL)? = nil) -> ClashModuleDetailSnapshot {
        let source: ClashModuleSource
        let failure: ClashDisplayText?
        var failureIsSentence = false
        let lines: [Substring]?
        let taken: ModuleIR?
        if let counted {
            lines = counted.written
            taken = counted.published
        } else {
            lines = ir.flatMap { writtenLines(text, of: $0) }
            taken = ir.map { published($0, record: record, publication: publication, written: lines) }
        }
        let ir = taken
        let row = ModulePageSnapshotBuilder.row(record, ir: ir, locale: locale, decryption: decryption, written: lines)
         
        let unreadFailure: ClashDisplayText? = record.failureFromALaterBuild ? "Update failed" : nil
        switch record.origin {
        case .url(let link):
            source = .link(link)
             
             
            failure = record.lastFailure.map { ModuleStoredSentence.failure($0, linked: true).displayText } ?? unreadFailure
             
            failureIsSentence = record.lastFailure != nil
        case .local:
            source = .local
             
             
             
             
            failure = record.lastFailure.map { ModuleStoredSentence.failure($0, linked: false).displayText } ?? unreadFailure
            failureIsSentence = record.lastFailure != nil
        case .unknown:
             
            source = .unknown
            failure = row.failure.map { _ in "Update failed" }
        }
        var sections = ir.map { self.sections($0, written: lines, waiting: decryption.waiting, scriptFile: scriptFile) } ?? []
         
         
         
        if record.enabled, let ir, let index = sections.firstIndex(where: { $0.id == "appScripts" }) {
            sections[index].items = zip(sections[index].items, ir.appScripts).map { item, script in
                var item = item
                if script.kind == .cron, appScriptRuns(script) {
                    item.runNow = ModuleAppScriptEntry.id(module: record.id, origin: script.origin)
                }
                return item
            }
        }
         
        let counts = ir.map { self.counts($0, decryption: decryption, written: lines) } ?? Counts(kept: 0, waiting: 0, unavailable: 0)
        var out = ClashModuleDetailSnapshot(
            id: record.id, name: row.name, summary: prose(ir?.manifest.desc), author: written(ir?.manifest.author),
            source: source, updatedAt: record.lastUpdatedAt, enabled: record.enabled, effectiveCount: counts.kept,
            ignoredCount: row.ignoredCount, failure: failure, isUpdating: isUpdating, sections: sections,
            needsDecryptionCount: counts.waiting, failureIsSentence: failureIsSentence,
            waitsFor: counts.waiting > 0 ? decryption.wait : nil, unavailableCount: counts.unavailable)
         
         
        if case .unknown = record.origin {} else { out.ownName = ModulePageSnapshotBuilder.ownName(record, locale: locale) }
        out.date = written(ir?.manifest.date)
        out.homepage = written(ir?.manifest.homepage)
        out.settings = ir.flatMap { settings($0.manifest, values: record.argumentValues, stored: storedValues, refusal: settingsRefusal) }
        return out
    }

     

     
     
     
     
     
    static func panels(record: ModuleRecord, ir: ModuleIR?, facts: ModulePageFacts) -> [ClashModuleDetailSnapshot.Panel] {
        guard record.enabled, let ir else { return [] }
        let downloaded = Set(ir.appScripts.filter { $0.kind == .generic && $0.bodySHA256 != nil }.map(\.name))
        return ir.panels.map { panel in
            let key = ModulePanelResults.key(module: record.id, panel: panel.name)
            let result = facts.panelResults[key]
            let refreshes = panel.scriptName != nil
             
            let runnable = panel.scriptName.map(downloaded.contains) ?? false
            var status: AuthoredText?
            if refreshes, !runnable {
                status = ModulePageSnapshotBuilder.Copy.panelScriptMissing
            } else if refreshes, !facts.isConnected {
                status = ModulePageSnapshotBuilder.Copy.panelNeedsConnection
            } else if facts.panelsFailed.contains(key) {
                status = ModulePageSnapshotBuilder.Copy.panelFailed
            }
            return ClashModuleDetailSnapshot.Panel(
                id: key, title: result?.title ?? panel.title ?? panel.name,
                content: (result?.content ?? panel.content).map { $0.replacingOccurrences(of: #"\n"#, with: "\n") },
                 
                icon: (result?.icon ?? panel.icon).flatMap { ModuleNodeScriptPresentation.systemDrawsSymbol($0) ? $0 : nil },
                iconColor: result?.iconColor ?? panel.iconColor,
                updatedAt: result?.at, refreshes: refreshes, canRefresh: runnable && facts.isConnected,
                isRefreshing: facts.panelsRefreshing.contains(key),
                status: status?.displayText, statusIsFailure: status == ModulePageSnapshotBuilder.Copy.panelFailed)
        }
    }

     

    typealias Setting = ClashModuleDetailSnapshot.Setting

     
     
     
     
     
     
     
     
    static func settings(_ manifest: ModuleManifest, values: [String: String], stored: [String: String],
                         refusal: ClashDisplayText?) -> ClashModuleDetailSnapshot.Settings? {
        var seen = Set<String>()
        var changed = !values.isEmpty
        let items = manifest.arguments.compactMap { argument -> Setting? in
            guard seen.insert(argument.name).inserted else { return nil }
            let title = written(argument.tag) ?? argument.name
            let note = prose(argument.desc)
            let control: Setting.Control
            let isDefault: Bool
            let defaultLine: ClashDisplayText
            switch argument.kind {
            case .toggle:
                let byDefault = isOn(argument.defaultValue)
                let on = values[argument.name].map(isOn) ?? byDefault
                control = .toggle(isOn: on)
                isDefault = on == byDefault
                defaultLine = .formatCopy("Default: %@", [byDefault ? "On" : "Off"])
            case .choice(let options), .storedChoice(let options):
                let byDefault: String
                let current: String
                if case .storedChoice = argument.kind {
                    byDefault = options.first ?? ""
                    current = stored[argument.name] ?? byDefault
                } else {
                    byDefault = argument.defaultValue ?? options.first ?? ""
                    current = values[argument.name] ?? byDefault
                }
                 
                control = .menu(options: options.contains(current) ? options : options + [current], selected: current)
                isDefault = current == byDefault
                defaultLine = byDefault.isEmpty ? .formatCopy("Default: %@", ["Not set"]) : .format("Default: %@", [byDefault])
            case .text, .input, .storedInput:
                let byDefault: String
                let given: String?
                if case .storedInput = argument.kind {
                    byDefault = ""
                    given = stored[argument.name]
                } else {
                    byDefault = argument.defaultValue ?? ""
                    given = values[argument.name]
                }
                control = .text(value: given ?? "", placeholder: byDefault.isEmpty ? "Not set" : .verbatim(byDefault))
                isDefault = (given ?? byDefault) == byDefault
                defaultLine = byDefault.isEmpty ? .formatCopy("Default: %@", ["Not set"]) : .format("Default: %@", [byDefault])
            }
            if !isDefault { changed = true }
            return Setting(id: argument.name, title: title, note: note, control: control, defaultLine: isDefault ? nil : defaultLine)
        }
        guard !items.isEmpty else { return nil }
        return ClashModuleDetailSnapshot.Settings(items: items, note: prose(manifest.argumentsDescription), canReset: changed,
                                                  refusal: refusal)
    }

     
    static func isOn(_ value: String?) -> Bool {
        ["true", "1", "yes", "on"].contains(value?.trimmingCharacters(in: .whitespaces).lowercased() ?? "")
    }

     

     
     
     
     
     
    struct Counts: Equatable {
        var kept: Int
        var waiting: Int
         
         
         
        var unavailable: Int

         
         
         
         
         
        func shown(enabled: Bool) -> Int { enabled ? max(0, kept - waiting - unavailable) : kept }
    }

     
     
     
     
    static func counts(_ ir: ModuleIR, decryption: Decryption, written: [Substring]? = nil) -> Counts {
        let settingEntries = ir.hosts.count + ir.edits.count + ir.deviceSettings.count + ir.inEffect.count
        let kept = ir.effectiveCount - settingEntries + settingItems(ir, written: written).count
        let waiting = decryption.waiting == nil ? 0
            : (ir.mitmHostLines + ir.forceHTTPEngineHostLines).reduce(0) { $0 + $1.entries.count }
                + ir.rewriteRules.count + ir.engineRules.count + ir.scripts.count
         
         
        return Counts(kept: kept + ir.appScripts.count, waiting: waiting,
                      unavailable: ir.appScripts.filter { !appScriptRuns($0, panels: panelScripts(ir)) }.count)
    }

     
     
     
     
     

     

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func published(_ ir: ModuleIR, record: ModuleRecord, publication: ModulePublicationSummary?,
                          written: [Substring]? = nil) -> ModuleIR {
        guard record.enabled, let publication else { return ir }
        let skipped = publication.skipped ?? []
        let withheld = (publication.changes ?? []).filter { !$0.applied }
        guard !skipped.isEmpty || !withheld.isEmpty else { return ir }
        var ir = ir
        let ruleOrigin = ModuleActivationStep.moduleRuleOrigin
        let rules = Set(ir.routingRules.map(rendered))
        let sets = Set(ir.ruleSets.flatMap(ruleSetNames))
        let settings = Set(ir.edits.map(\.origin) + ir.hosts.map(\.origin) + ir.deviceSettings.map(\.origin)
                           + ir.inEffect.map(\.origin) + ir.changes.map(\.origin))
        var mine: [ModuleIgnoredEntry] = []
        var leftOutRules = Set<String>()
        var leftOutLines = Set<ModuleLineOrigin>()
        var refusal: ModuleIgnoredReason?
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
                mine.append(ModuleIgnoredEntry(text: text, reason: refusal, origin: origin, moduleID: record.id))
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

     
    private static func ruleSetNames(_ set: ModuleRuleSet) -> [String] {
         
        [set.url, ruleSetLine(set), set.reference].compactMap { $0 }
    }

     
     
     
     
    static func settingsLines(of ir: ModuleIR) -> [ModuleLineOrigin] {
        var seen = Set<ModuleLineOrigin>()
        let all = (ir.edits.map(\.origin) + ir.hosts.map(\.origin) + ir.deviceSettings.map(\.origin) + ir.changes.map(\.origin))
            .filter { seen.insert($0).inserted }
        guard ir.manifest.format != .stash else { return all }
        return all.enumerated().sorted { ($0.element.line, $0.offset) < ($1.element.line, $1.offset) }.map(\.element)
    }

     
     
     
     
     
     
    static func writtenKey(_ origin: ModuleLineOrigin, in ir: ModuleIR) -> String? {
        if ir.manifest.format == .stash { return origin.section }
        if let kept = ir.inEffect.first(where: { $0.origin == origin }) { return kept.key }
        if let host = ir.hosts.first(where: { $0.origin == origin }) { return host.pattern }
        if let setting = ir.deviceSettings.first(where: { $0.origin == origin }) { return writtenKey(setting.key) }
        return ir.edits.first { $0.origin == origin && !isWorkedOut($0) }.map { $0.path.joined(separator: ".") }
    }

     
     
    static func writtenKey(_ key: ModuleDeviceSettingKey) -> String {
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

     
     
     
    static func isWorkedOut(_ edit: ModuleConfigurationEdit) -> Bool {
        switch edit.operation {
        case .copyIfAbsent, .serverParameter, .nameserversWithParameter, .engineRoute: return true
        case .replace, .append, .prepend, .merge, .replaceIfAbsent: return false
        }
    }

     
    private static func written(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

     
     
     
     
    private static func prose(_ value: String?) -> String? {
        written(value).map { $0.replacingOccurrences(of: #"\n"#, with: "\n") }
    }

     
     
     
     
     
     
     
    static func sections(_ ir: ModuleIR, written: [Substring]?, waiting waits: ClashDisplayText?,
                         scriptFile: ((String) -> URL)? = nil) -> [Section] {
        func source(_ name: String, _ link: String, _ body: String?) -> ClashModuleScriptSource {
            ClashModuleScriptSource(name: name, link: link, file: body.flatMap { body in scriptFile.map { $0(body) } })
        }
        let numbered = ir.manifest.format != .stash
        let files = fileAddresses(ir)
        let all: [(id: String, title: ClashDisplayText, items: [Item], waits: ClashDisplayText?)] = [
            ("hosts", "Sites", siteItems(ir), waits),
            ("rules", "Rules", ruleItems(ir, written: written, waiting: waits), nil),
            ("rewrites", "Rewrites", ir.rewriteRules.enumerated().map {
                 
                 
                rewriteItem($0.element, index: $0.offset, files: files[$0.offset] ?? [],
                            written: ir.manifest.format == .quantumultX ? writtenLine($0.element.origin, in: written) : nil)
            }, waits),
             
             
            ("settings", "General", settingItems(ir, written: written), nil),
             
            ("scripts", "Scripts", ir.scripts.enumerated().map {
                Item(id: "script-\($0.offset)", text: $0.element.name, secondary: $0.element.pattern,
                     script: source($0.element.name, $0.element.scriptURL, $0.element.bodySHA256))
            }, waits),
             
             
            ("appScripts", ir.scripts.isEmpty ? "Scripts" : "Other Scripts", appScriptItems(ir).enumerated().map { index, item in
                var item = item
                let script = ir.appScripts[index]
                item.script = source(script.name, script.scriptURL, script.bodySHA256)
                return item
            }, nil),
            ("skipped", "Skipped", ir.ignored.enumerated().map {
                Item(id: "skipped-\($0.offset)", text: $0.element.text, detail: $0.element.reason.authoredText.displayText,
                     place: numbered ? place($0.element.origin) : nil)
            }, nil),
        ]
        return all.filter { !$0.items.isEmpty }.map {
            Section(id: $0.id, title: $0.title, items: $0.items, waiting: $0.waits)
        }
    }

     
     
     
     
    static func appScriptItems(_ ir: ModuleIR) -> [Item] {
        let panels = panelScripts(ir)
        return ir.appScripts.enumerated().map { index, script in
            Item(id: "app-script-\(index)", text: script.name, detail: appScriptWhen(script, panels: panels),
                 secondary: script.kind == .cron ? script.cronExpression : script.kind == .event ? script.eventName : nil)
        }
    }

     
     
    static func appScriptWhen(_ script: ModuleAppScript, panels: Set<String> = []) -> ClashDisplayText {
        guard appScriptRuns(script, panels: panels) else { return "Not Available Yet" }
        switch script.kind {
        case .cron: return "Runs on schedule while Clash is open and connected"
        case .networkChanged: return "Runs when the network changes while Clash is open and connected"
        case .generic where panels.contains(script.name): return "Runs when its panel refreshes"
        case .generic: return "Long-press a node on the Proxies page to run"
        case .event: return "Not Available Yet"
        }
    }

     
     
     
     
     
    static func panelScripts(_ ir: ModuleIR) -> Set<String> {
        Set(ir.panels.compactMap(\.scriptName))
    }

    static func appScriptRuns(_ script: ModuleAppScript, panels: Set<String> = []) -> Bool {
        guard script.bodySHA256 != nil else { return false }
        switch script.kind {
        case .cron, .networkChanged: return true
        case .event: return false
        case .generic where panels.contains(script.name): return true
        case .generic:
#if os(macOS)
            return false
#else
            return true
#endif
        }
    }

     
     
     
     
    static func place(_ origin: ModuleLineOrigin) -> ClashDisplayText? {
        origin.line > 0 ? .format("Line %@", [String(origin.line)]) : nil
    }

     
     
     
    static func writtenLines(_ text: Data?, of ir: ModuleIR) -> [Substring]? {
        guard let text, ir.manifest.format != .stash, ModuleJSON.sha256(text) == ir.manifest.contentSHA256,
              var read = String(data: text, encoding: .utf8) else { return nil }
         
        if read.hasPrefix("\u{FEFF}") { read.removeFirst() }
        read = read.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return read.split(separator: "\n", omittingEmptySubsequences: false)
    }

     

     
     
    static func siteItems(_ ir: ModuleIR) -> [Item] {
        let decrypted = ir.mitmHostLines.flatMap(\.entries).map(\.spelling)
        let plain = ir.forceHTTPEngineHostLines.flatMap(\.entries).map(\.spelling)
        return decrypted.enumerated().map { Item(id: "site-\($0.offset)", text: $0.element) }
            + plain.enumerated().map { Item(id: "plain-\($0.offset)", text: $0.element, detail: .verbatim("HTTP")) }
    }

     

     
     
     
     
     
    static func ruleItems(_ ir: ModuleIR, written: [Substring]?, waiting: ClashDisplayText?) -> [Item] {
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

     
     
    static func writtenLine(_ origin: ModuleLineOrigin, in lines: [Substring]?) -> String? {
        guard let lines, origin.line > 0, origin.line <= lines.count else { return nil }
        let line = ModuleParser.strippingComment(lines[origin.line - 1].trimmingCharacters(in: .whitespaces))
        return line.isEmpty ? nil : line
    }

     
     
     
     
     
    static func rendered(_ rule: ModuleRoutingRule) -> String {
        let name = rule.policy.kernelName ?? policy(rule.policy)
        return ([rule.head] + (name.isEmpty ? [] : [name]) + rule.params).joined(separator: ",")
    }

     
     
    static func policy(_ policy: ModuleRulePolicy) -> String {
        switch policy {
        case .builtIn(let name), .named(let name): return name
        case .moduleChoice: return "PROXY"
        }
    }

    static func ruleSetLine(_ set: ModuleRuleSet) -> String {
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

     
     
    static func spelling(_ condition: ModuleRuleCondition) -> String {
        func parts(_ conditions: [ModuleRuleCondition]) -> String {
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

     
     
    static func decision(_ decision: ModuleEngineDecision) -> String {
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

     

     
     
     
     
     
     
    static func rewriteItem(_ rule: ModuleRewriteRule, index: Int, files: [String] = [], written: String? = nil) -> Item {
        var files = files[...]
        var actions = rule.actions.map { action in
            spelling(action, file: waitsForAFile(action) ? files.popFirst() : nil)
        }.joined(separator: " | ")
        if let written, !rule.pattern.isEmpty, written.hasPrefix(rule.pattern) {
            let rest = written.dropFirst(rule.pattern.count).trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty { actions = rest }
        }
        let condition = rule.condition.map(spelling)
        if !rule.pattern.isEmpty {
            return Item(id: "rewrite-\(index)", text: rule.pattern, detail: .verbatim(actions), secondary: condition)
        }
        if let condition {
            return Item(id: "rewrite-\(index)", text: condition, detail: .verbatim(actions))
        }
        return Item(id: "rewrite-\(index)", text: actions)
    }

     
     
     
    static func fileAddresses(_ ir: ModuleIR) -> [Int: [String]] {
        var left: [ModuleLineOrigin: [String]] = [:]
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

     
    static func waitsForAFile(_ action: ModuleRewriteAction) -> Bool {
        switch action {
        case .localAnswer(let answer):
            if case .file = answer.body { return true }
            return false
        case .requestBody(.file, _): return true
        case .bodyJQ(_, let expression, let sha256): return sha256 != nil || expression.isEmpty
        default: return false
        }
    }

     
     
     
    static func spelling(_ action: ModuleRewriteAction, file: String? = nil) -> String {
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

    static func headerVerb(_ operation: ModuleHeaderOperation) -> String {
        switch operation {
        case .add: return "header-add"
        case .delete: return "header-del"
        case .replace: return "header-replace"
        case .replaceRegex: return "header-replace-regex"
        case .set: return "header-set"
        case .replaceHead: return "request-header"
        }
    }

    private static func bodyKeyword(_ phase: ModuleRewritePhase) -> String {
        switch phase {
        case .request: return "http-request"
        case .response: return "http-response"
        }
    }

     
    static func body(_ body: ModuleAnswerBody) -> [String] {
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

     
    static func json(_ operation: ModuleJSONOperation, phase: ModuleRewritePhase) -> String {
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

    static func keyPath(_ path: [ModuleJSONPathComponent]) -> String {
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

     
     
    static func spelling(_ condition: ModuleCondition) -> String {
        func nested(_ condition: ModuleCondition) -> String {
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

    private static func variable(_ variable: ModuleConditionVariable) -> String {
        switch variable {
        case .url: return "${url}"
        case .requestMethod: return "${request.method}"
        case .requestHeader(let name): return "${request.header.\(name)}"
        case .responseStatus: return "${response.status}"
        case .responseHeader(let name): return "${response.header.\(name)}"
        case .requestHead: return "${request.head}"
        }
    }

    private static func value(_ value: ModuleConditionValue) -> String {
        switch value {
        case .regex(let pattern): return "/\(pattern)/"
        case .string(let text): return "\"\(text)\""
        case .number(let number):
            return number.rounded() == number && abs(number) < 1e15 ? String(Int64(number)) : String(number)
         
        case .null: return "null"
        }
    }

     

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func settingItems(_ ir: ModuleIR, written: [Substring]? = nil) -> [Item] {
        var items: [(line: Int, item: Item)] = []
        for (index, change) in ir.changes.enumerated() where change.applied {
            items.append((change.origin.line, Item(id: "change-\(index)", text: writtenLine(change.origin, in: written) ?? change.value,
                                                   detail: change.key.label.displayText)))
        }
         
         
        let changed = Set(ir.changes.map(\.origin))
        var listed = Set<ModuleLineOrigin>()
        func line(_ origin: ModuleLineOrigin, _ fallback: @autoclosure () -> Item?) {
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

     
     
     
     
     
     
    static func writtenValue(_ edit: ModuleConfigurationEdit) -> String? {
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

     
    static func hostValue(_ value: ModuleHostValue) -> String {
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
