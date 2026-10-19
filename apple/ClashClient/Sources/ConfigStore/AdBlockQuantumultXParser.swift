import Foundation

/// Reads a Quantumult X configuration into a module.
///
/// The sections that carry rewriting, and the two that carry matching:
///
/// ```ini
/// [rewrite_local]
/// ^https?://example\.com/a url script-request-header https://…/x.js
/// ^https?://example\.com/b url script-response-body https://…/y.js
/// ^https?://example\.com/c url reject-dict
///
/// [task_local]
/// 0 10 * * * https://…/task.js, tag=Daily, timeout=10
///
/// [filter_local]
/// host, example.com, REJECT
///
/// [mitm]
/// hostname = example.com
/// ```
///
/// Quantumult X is the one platform whose whole rewrite surface is URL-regex
/// patterns with a fixed action, so there is no expression language to read.
/// That is also why a script written for it is the most likely to have been
/// written against `$task`/`$prefs`, and why the module's dialect is what its
/// identity follows.
enum AdBlockQuantumultXParser {
    /// The actions that attach a script, and the phase each one runs in.
    private static let scriptActions: [String: AdBlockRewritePhase] = [
        "script-request-header": .request,
        "script-request-body": .request,
        "script-response-header": .response,
        "script-response-body": .response,
        "script-echo-response": .request,
        "script-analyze-echo-response": .request,
    ]

    /// The actions that answer without going upstream, as the action the tunnel
    /// should use.
    private static let inlineActions: [String: AdBlockRewriteAction] = [
        "reject": .reject,
        "reject-200": .reject200,
        "reject-img": .rejectImg,
        "reject-dict": .rejectDict,
        "reject-array": .rejectArray,
        "reject-drop": .rejectDrop,
    ]

    /// The actions that send the request somewhere else.
    private static let redirectActions: Set<String> = ["302", "307"]

    static func parse(_ text: String, manifest: AdBlockModuleManifest, sourceURL: String?,
                      platform: AdBlockPlatform, environment: [String: String],
                      check: AdBlockRuleMapping.Check? = nil) throws -> AdBlockModuleIR {
        var ir = AdBlockModuleIR.empty(manifest)
        var section: String?
        var hostLines: [AdBlockHostListLine] = []
        var filterRules: [(text: String, origin: AdBlockLineOrigin)] = []
        var rewriteLines: [(origin: AdBlockLineOrigin, line: String)] = []
        var taskLines: [(origin: AdBlockLineOrigin, line: String)] = []

        for (index, raw) in text.split(separator: "\n").enumerated() {
            let line = stripComment(raw)
            if line.isEmpty { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast()).lowercased()
                continue
            }
            let origin = AdBlockLineOrigin(section: section ?? "", line: index + 1)
            switch section {
            case "rewrite_local": rewriteLines.append((origin, line))
            case "task_local": taskLines.append((origin, line))
            case "filter_local": filterRules.append((line, origin))
            case "mitm": hostLines.append(mitmLine(line, origin))
            default: break
            }
        }

        ir.mitmHostLines = hostLines
        // `[filter_local]` lines are rules like `[Rule]`'s. They are read with
        // the kernel check when one is given, which is what a module being
        // installed for the running kernel wants.
        // `[filter_local]` lines are rules like `[Rule]`'s, so they go through
        // the same reader. A check is only given when the module is being
        // installed for a kernel that can be asked; without one the reader
        // accepts the line and the engine decides at run time.
        AdBlockRuleSetSyntax.takeSection("filter_local", lines: filterRules, family: .quantumultX,
                                         platform: platform, check: check ?? AdBlockRuleMapping.kernelCheck,
                                         into: &ir)

        for (origin, line) in rewriteLines {
            switch rewrite(line, origin: origin, manifest: manifest) {
            case .script(let script): ir.scripts.append(script)
            case .rule(let rule): ir.rewriteRules.append(rule)
            case .ignored(let reason): ir.ignored.append(AdBlockIgnoredEntry(text: line, reason: reason, origin: origin))
            }
        }
        for (origin, line) in taskLines {
            switch task(line, origin: origin, manifest: manifest) {
            case .success(let script): ir.scripts.append(script)
            case .failure(let reason): ir.ignored.append(AdBlockIgnoredEntry(text: line, reason: reason, origin: origin))
            }
        }
        return ir
    }

    // MARK: - Rewrite lines

    /// One `[rewrite_local]` line: `<pattern> url <action> [arguments]`.
    ///
    /// A script action attaches a script; an inline action becomes a rewrite
    /// rule; a redirect becomes a redirect. Anything else is reported, because a
    /// silently dropped line is the worst outcome — the user sees an ad and no
    /// reason why.
    private enum RewriteOutcome {
        case script(AdBlockScript)
        case rule(AdBlockRewriteRule)
        case ignored(AdBlockIgnoredReason)
    }

    private static func rewrite(_ line: String, origin: AdBlockLineOrigin,
                                manifest: AdBlockModuleManifest) -> RewriteOutcome {
        let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        guard parts.count >= 3 else { return .ignored(.unreadableLine) }
        guard parts[1].lowercased() == "url" else { return .ignored(.unreadableLine) }
        let pattern = String(parts[0])
        guard AdBlockLineSyntax.isValidPattern(pattern) else { return .ignored(.invalidPattern) }
        let action = String(parts[2]).lowercased()
        let rest = parts.count > 3 ? String(parts[3]) : ""
        let options = parameters(rest)

        if let phase = scriptActions[action] {
            return .script(script(line: line, pattern: pattern, action: action, phase: phase,
                                  options: options, origin: origin))
        }
        if let ending = inlineActions[action] {
            return .rule(AdBlockRewriteRule(pattern: pattern, actions: [ending], origin: origin, policy: nil))
        }
        if redirectActions.contains(action) {
            // `302 https://example.com` — the target is the first non-option word.
            guard let target = options.first(where: { !$0.contains("=") }) else { return .ignored(.unreadableLine) }
            let redirect = action == "302" ? AdBlockRewriteAction.redirect302(target) : .redirect307(target)
            return .rule(AdBlockRewriteRule(pattern: pattern, actions: [redirect], origin: origin, policy: nil))
        }
        return .ignored(.unsupportedRewriteType(action))
    }

    /// One `[task_local]` line: `<schedule> url <script> [options]`.
    private static func task(_ line: String, origin: AdBlockLineOrigin,
                             manifest: AdBlockModuleManifest) -> Result<AdBlockScript, AdBlockIgnoredReason> {
        let fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        // The address is followed by `url`; the schedule is everything before it.
        guard let addressIndex = fields.firstIndex(where: { $0.lowercased().hasPrefix("http://") || $0.lowercased().hasPrefix("https://") }),
              addressIndex >= 2, fields[addressIndex - 1].lowercased() == "url" else {
            return .failure(.unreadableLine)
        }
        let schedule = Array(fields[0..<addressIndex - 1])
        let scriptLine = fields[addressIndex...].joined(separator: " ")
        let parts = scriptLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return .failure(.unreadableLine) }
        guard parts[0].lowercased() == "url" else { return .failure(.unreadableLine) }
        let action = String(parts[1]).lowercased()
        let options = parameters(parts.count > 2 ? String(parts[2]) : "")
        guard scriptActions[action] != nil else { return .failure(.unsupportedRewriteType(action)) }
        return .success(cronScript(action: action, options: options, schedule: schedule, origin: origin))
    }

    // MARK: - Script construction

    private static func script(line: String, pattern: String, action: String, phase: AdBlockRewritePhase,
                               options: [String], origin: AdBlockLineOrigin) -> AdBlockScript {
        AdBlockScript(
            name: name(options: options, pattern: pattern),
            phase: phase,
            pattern: pattern,
            scriptURL: address(options: options),
            requiresBody: action.contains("body"),
            binaryBodyMode: action.contains("body"),
            maxSize: nil,
            timeout: timeout(options: options),
            argument: argument(options: options),
            updateInterval: AdBlockLineSyntax.defaultScriptUpdateInterval,
            bodySHA256: nil,
            origin: origin)
    }

    private static func cronScript(action: String, options: [String], schedule: [String],
                                   origin: AdBlockLineOrigin) -> AdBlockScript {
        AdBlockScript(
            name: name(options: options, pattern: schedule.joined(separator: " ")),
            phase: .cron,
            pattern: schedule.joined(separator: " "),
            scriptURL: address(options: options),
            requiresBody: action.contains("body"),
            binaryBodyMode: action.contains("body"),
            maxSize: nil,
            timeout: timeout(options: options),
            argument: argument(options: options),
            updateInterval: AdBlockLineSyntax.defaultScriptUpdateInterval,
            bodySHA256: nil,
            origin: origin,
            cronFields: schedule)
    }

    private static func address(options: [String]) -> String {
        options.first(where: { $0.lowercased().hasPrefix("http://") || $0.lowercased().hasPrefix("https://") }) ?? ""
    }

    private static func name(options: [String], pattern: String) -> String {
        if let tag = options.first(where: { $0.lowercased().hasPrefix("tag=") }) {
            let value = unquote(String(tag.dropFirst(4)))
            if !value.isEmpty { return value }
        }
        return pattern
    }

    private static func timeout(options: [String]) -> Int? {
        options.first(where: { $0.lowercased().hasPrefix("timeout=") })
            .flatMap { Int(String($0.dropFirst("timeout=".count)).trimmingCharacters(in: .whitespacess)) }
    }

    private static func argument(options: [String]) -> String? {
        options.first(where: { $0.lowercased().hasPrefix("argument=") }).map { unquote(String($0.dropFirst(9))) }
    }

    // MARK: - Line helpers

    /// The `key=value` options after the address, in order, quotes intact.
    private static func parameters(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        var quoted = false
        for character in text {
            switch character {
            case "\"": quoted.toggle(); current.append(character)
            case " " where !quoted:
                if !current.isEmpty { out.append(current); current = "" }
            default: current.append(character)
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    private static func unquote(_ text: String) -> String {
        guard text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") else { return text }
        return String(text.dropFirst().dropLast())
    }

    /// `[mitm]`'s `hostname = a.com, b.com` becomes a host list line.
    private static func mitmLine(_ line: String, origin: AdBlockLineOrigin) -> AdBlockHostListLine {
        let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else {
            return AdBlockHostListLine(directive: .none, entries: [], origin: origin)
        }
        let names = parts[1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespacess) }
        let disabled = parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "hostname-disabled"
        let entries = names.compactMap { name -> AdBlockHostEntry? in
            guard let entry = AdBlockHostList.entry(name) else { return nil }
            return AdBlockHostEntry(pattern: entry.pattern, port: entry.port, excluded: entry.excluded || disabled)
        }
        return AdBlockHostListLine(directive: .none, entries: entries, origin: origin)
    }

    private static func stripComment(_ raw: String) -> String {
        let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : String(raw)
        if let range = line.range(of: " #") { line = String(line[..<range.lowerBound]) }
        return line.trimmingCharacters(in: .whitespacess)
    }
}
