import ClashClientUI
import Foundation
import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
struct ConfigurationRefusalReason: Equatable, Sendable {
     
    let summary: ClashDisplayText
     
    let original: String

     
    static let copyKeys: [String] = [
        Copy.unknownRuleType, Copy.missingPolicy, Copy.missingRuleSet, Copy.missingSubRule,
        Copy.ruleFormat, Copy.ruleError, Copy.groupMissingMember, Copy.groupError, Copy.unknownGroupType,
        Copy.duplicateGroup, Copy.duplicateProxy, Copy.yaml, Copy.unknown,
        Copy.scriptFailed, Copy.scriptNoMain, Copy.scriptNoResult, Copy.scriptTimedOut, Copy.scriptUnavailable,
    ]

    private enum Copy {
        static let unknownRuleType = "Rule type “%@” isn’t valid."
        static let missingPolicy = "A rule uses %@, which doesn’t exist."
        static let missingRuleSet = "A rule uses the rule set %@, which doesn’t exist."
        static let missingSubRule = "A rule uses the sub-rule %@, which doesn’t exist."
        static let ruleFormat = "This rule isn’t written correctly: %@"
        static let ruleError = "This rule has an error: %@"
        static let groupMissingMember = "The group %1$@ uses %2$@, which doesn’t exist."
        static let groupError = "The group %@ isn’t set up correctly."
        static let unknownGroupType = "Group type not recognized: %@"
        static let duplicateGroup = "More than one group is named %@."
        static let duplicateProxy = "More than one proxy is named %@."
        static let yaml = "The configuration’s format isn’t valid."
        static let unknown = "The configuration has an error."
        static let scriptFailed = "The script failed: %@"
        static let scriptNoMain = "The script has no main function."
        static let scriptNoResult = "The script didn’t return the configuration."
        static let scriptTimedOut = "The script ran too long and was stopped."
        static let scriptUnavailable = "The script couldn’t run."
    }

     
     
     
    private static let rule = try! NSRegularExpression(
        pattern: #"(?:^|: )rules\[\d+\] \[(.*?)\] error: (.*)$"#, options: [.dotMatchesLineSeparators])
    private static let group = try! NSRegularExpression(
        pattern: #"(?:^|: )proxy group\[\d+\]: (.*)$"#, options: [.dotMatchesLineSeparators])
    private static let duplicateGroup = try! NSRegularExpression(
        pattern: #"(?:^|: )proxy group (.+): the duplicate name$"#)
    private static let duplicateProxy = try! NSRegularExpression(
        pattern: #"(?:^|: )proxy (.+) is the duplicate name$"#)
    private static let yaml = try! NSRegularExpression(pattern: #"(?:^|: )yaml: "#)

    static func reading(_ sentence: String) -> ConfigurationRefusalReason {
        let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        return ConfigurationRefusalReason(summary: summary(of: text), original: sentence)
    }

     
    static func reading(_ problem: ConfigurationCompileAnswer.Problem) -> ConfigurationRefusalReason {
        reading(problem.message)
    }

     
    static func reading(scriptFailure error: Error) -> ConfigurationRefusalReason {
        let original = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        guard let failure = error as? ScriptEngine.ScriptError else {
             
             
            return ConfigurationRefusalReason(summary: .format(Copy.scriptFailed, [original]), original: original)
        }
        let summary: ClashDisplayText
        switch failure {
        case .evaluationFailed(let message), .threw(let message):
             
             
            summary = .format(Copy.scriptFailed, [message])
        case .missingMain: summary = .copy(Copy.scriptNoMain)
        case .invalidResult: summary = .copy(Copy.scriptNoResult)
        case .timedOut: summary = .copy(Copy.scriptTimedOut)
        case .contextUnavailable: summary = .copy(Copy.scriptUnavailable)
        }
        return ConfigurationRefusalReason(summary: summary, original: original)
    }

    private static func summary(of text: String) -> ClashDisplayText {
        if let match = captures(rule, in: text), match.count == 2 {
            return ruleSummary(rule: match[0], error: match[1])
        }
        if let match = captures(group, in: text), match.count == 1 {
            return groupSummary(match[0])
        }
        if let name = captures(duplicateGroup, in: text)?.first { return .format(Copy.duplicateGroup, [name]) }
        if let name = captures(duplicateProxy, in: text)?.first { return .format(Copy.duplicateProxy, [name]) }
        if yaml.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil { return .copy(Copy.yaml) }
        return .copy(Copy.unknown)
    }

     
     
    private static func ruleSummary(rule: String, error: String) -> ClashDisplayText {
         
         
        let unsupported = "unsupported rule type: "
        if error.hasPrefix(unsupported) { return .format(Copy.unknownRuleType, [String(error.dropFirst(unsupported.count))]) }
        if error.hasPrefix("unsupported rule type") { return .format(Copy.ruleError, [rule]) }
        if let name = bracketed(after: "proxy [", in: error) { return .format(Copy.missingPolicy, [name]) }
        if let name = bracketed(after: "rule set [", in: error) { return .format(Copy.missingRuleSet, [name]) }
        if let name = bracketed(after: "sub-rule [", in: error) { return .format(Copy.missingSubRule, [name]) }
        if error.hasPrefix("format invalid") || error.hasPrefix("missing subsequent parameters") {
            return .format(Copy.ruleFormat, [rule])
        }
        return .format(Copy.ruleError, [rule])
    }

     
     
     
    private static func groupSummary(_ rest: String) -> ClashDisplayText {
        let unsupported = "unsupported type: "
        if rest.hasPrefix(unsupported) {
            let type = rest.dropFirst(unsupported.count).split(separator: ":").first.map(String.init) ?? ""
            return .format(Copy.unknownGroupType, [type.trimmingCharacters(in: .whitespaces)])
        }
        guard let separator = rest.range(of: ": ") else { return .copy(Copy.unknown) }
        let name = String(rest[..<separator.lowerBound])
        let why = String(rest[separator.upperBound...])
         
         
         
         
        let notFound = "' not found"
        if why.count > notFound.count, why.hasPrefix("'"), why.hasSuffix(notFound) {
            let member = String(why.dropFirst().dropLast(notFound.count))
            return .format(Copy.groupMissingMember, [name, member])
        }
        return .format(Copy.groupError, [name])
    }

    private static func bracketed(after prefix: String, in text: String) -> String? {
        guard text.hasPrefix(prefix), let end = text.range(of: "] not found") else { return nil }
        return String(text[text.index(text.startIndex, offsetBy: prefix.count)..<end.lowerBound])
    }

    private static func captures(_ expression: NSRegularExpression, in text: String) -> [String]? {
        guard let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
    }
}

 
 
 
 
 
 
 
enum ScriptSaveCheck {
    enum Verdict: Equatable, Sendable {
        case accepted
         
        case scriptFailed(ConfigurationRefusalReason)
         
        case refused(ConfigurationRefusalReason)
    }

     
     
    static func runs(_ id: String, in profile: Profile) -> Bool {
        (profile.overwriteMode == .script && profile.selectedScriptID == id) || profile.postMergeScriptID == id
    }

     
    static func runsAScript(_ profile: Profile) -> Bool {
        (profile.overwriteMode == .script && profile.selectedScriptID != nil) || profile.postMergeScriptID != nil
    }

     
    typealias ScriptStep = (String?, String, String) throws -> String
    private struct ScriptStepFailure: Error { let underlying: Error }

     
     
     
     
     
    static func verdict(
        raw: String,
        profile: Profile,
        scripts: [ConfigScript],
        build: (String, Profile, @escaping ScriptStep) throws -> String = productionBuild,
        parse: (String) -> ConfigurationCompileAnswer = coreParse
    ) -> Verdict {
         
        let script: ScriptStep = { id, yaml, name in
            do { return try ScriptLibrary.apply(id: id, to: yaml, scripts: scripts, profileName: name, caller: .surfaced) }
            catch { throw ScriptStepFailure(underlying: error) }
        }
        let yaml: String
        do {
            yaml = try build(raw, profile, script)
        } catch let failure as ScriptStepFailure {
            return .scriptFailed(.reading(scriptFailure: failure.underlying))
        } catch {
            return .accepted
        }
        guard case .refused(let problems) = parse(yaml) else {
             
             
            return .accepted
        }
        return .refused(problems.first.map(ConfigurationRefusalReason.reading)
            ?? .reading(""))
    }

     
    static func productionBuild(raw: String, profile: Profile, script: @escaping ScriptStep) throws -> String {
        try ProfileRuntimeConfigBuilder.buildStages(
            raw: raw,
            profile: profile,
            globalOverride: GlobalConfig.load(),
            runtimeOverride: FlClashRuntimeConfig.load(),
            profileScript: script,
            configScript: { try ScriptSettings.apply(toConfigYAML: $0, profileName: $1, caller: .silent) },
            postMergeScript: script
        ).finished()
    }

     
     
     
    static func coreParse(_ yaml: String) -> ConfigurationCompileAnswer {
        guard let container = ClashAppIdentifiers.appGroupContainer else { return .unavailable(nil) }
        do { try AppCoreSetup.ensure(container: container) } catch { return .unavailable(error.localizedDescription) }
        var error: NSError?
        guard let answer = AppCore.compileCheck(yaml, "", &error) else {
            return .unavailable(error?.localizedDescription)
        }
        return .decode(answer.value)
    }
}

 
struct ScriptSaveRefusal: Identifiable {
    let id = UUID()
    let reason: ConfigurationRefusalReason
     
     
    let saveAnyway: (() -> Void)?
    let keepEditing: () -> Void
}

 
 
 
private struct ScriptSaveRefusalAlert: ViewModifier {
    @Binding var refusal: ScriptSaveRefusal?
    @Environment(\.locale) private var locale

    func body(content: Content) -> some View {
        content.alert(
            "Can’t Use This Script",
            isPresented: Binding(get: { refusal != nil }, set: { if !$0 { refusal = nil } }),
            presenting: refusal
        ) { refusal in
            if let saveAnyway = refusal.saveAnyway {
                Button("Save Anyway") { saveAnyway() }
                    .accessibilityIdentifier("scripts.refusal.save-anyway")
            }
            Button("Keep Editing", role: .cancel) { refusal.keepEditing() }
                .accessibilityIdentifier("scripts.refusal.keep-editing")
        } message: { refusal in
             
            Text(verbatim: ClashCopy.string(for: refusal.reason.summary, locale: locale)
                + "\n\n" + refusal.reason.original)
        }
    }
}

extension View {
    func scriptSaveRefusalAlert(_ refusal: Binding<ScriptSaveRefusal?>) -> some View {
        modifier(ScriptSaveRefusalAlert(refusal: refusal))
    }
}

 
 
extension ScriptEngine.ScriptError: ClashAuthoredError {
    var displayText: ClashDisplayText {
        switch self {
        case .evaluationFailed(let message): .format("script error: %@", [message])
        case .threw(let message): .format("script threw: %@", [message])
        case .timedOut, .contextUnavailable, .missingMain, .invalidResult: .copy(errorDescription ?? "")
        }
    }
}

 
 
extension ScriptLibraryError: ClashAuthoredError {
    var displayText: ClashDisplayText {
        switch self {
        case .missing(let id): .format("Selected override script '%@' no longer exists.", [id])
        case .tooLarge: .copy("This configuration is too large to run an override script.")
        }
    }
}

 
 
extension ConfigTransformsError: ClashAuthoredError {
    var displayText: ClashDisplayText {
        switch self {
        case .bridgeReturnedNil(let operation):
            .format("The configuration operation %@ did not return a result.", [operation])
        case .invalidConfiguration(let reason):
            .format("The downloaded configuration is invalid: %@", [Self.readable(reason)])
        }
    }
}
