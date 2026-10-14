import ClashClientKit
import ClashClientUI
import SwiftUI

 
public enum ClashMacOutlineDestination {
     
    case page(@MainActor () -> AnyView)
     
    case open(@MainActor () -> Void)
}

 
 
 
public struct ClashMacOutlineScheme: Equatable {
    public enum Kind: Equatable {
         
         
        case builtIn
         
        case own(configurations: Int)
         
         
        case shared
    }
    public let id: String
    public let label: String
    public let kind: Kind
    public init(id: String, label: String, kind: Kind) { self.id = id; self.label = label; self.kind = kind }
}

 
public struct ClashMacCompileProblem: Equatable, Sendable {
     
    public let message: String
     
    public let place: String?
    public init(message: String, place: String?) { self.message = message; self.place = place }
}

 
 
struct ClashMacOriginalChoice {
     
    let isChosen: Bool
     
    let sourceName: String?
    let choose: @MainActor () -> Void
}

 
public enum ClashMacCompileResult: Equatable, Sendable {
    case accepted
     
    case refused([ClashMacCompileProblem])
     
    case unavailable(String?)
}

 
 
 
 
struct ClashMacConfigurationOutlineCard: View {
     
    let rows: [ConfigurationOutlineRow]?
    let form: ConfigurationOutlineForm
     
    let scheme: ClashMacOutlineScheme?
     
     
     
    var original: ClashMacOriginalChoice? = nil
    let schemes: [ConfigurationRuleScheme]
     
    let usage: [String: Int]
     
     
     
    var followedLinks: [String: String] = [:]
    let scriptValue: ClashDisplayText
     
     
    let customRules: Int
    let busy: Bool
     
    var configurationLabel: String? = nil
    let destination: @MainActor (ConfigurationOutlineSection) -> ClashMacOutlineDestination?
     
    let onReturn: @MainActor () -> Void
    let chooseScheme: @MainActor (String) -> Void
    @Environment(\.locale) private var locale

     
     
     
     
     
     
     
    var body: some View {
        let shown = Self.shownSections(rows, form: form)
        let own = shown.filter(\.isConfigurationsOwn)
        let hasScheme = scheme != nil || original?.isChosen == true
        if hasScheme || !own.isEmpty {
            Section {
                if hasScheme { schemeRow }
                ForEach(own, id: \.self) { section in
                    outlineRow(section, rows?.first { $0.section == section })
                }
            } header: {
                Text(clash: .copy("Configuration Override")).accessibilityIdentifier("configuration-center.configuration.override-header")
            } footer: {
                let lines = footerLines(hasOwn: !own.isEmpty)
                if !lines.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(lines.indices, id: \.self) { Text(clash: lines[$0]) }
                    }
                }
            }
        }
        Section {
             
             
            ForEach(shown.filter { !$0.isConfigurationsOwn }, id: \.self) { section in
                outlineRow(section, rows?.first { $0.section == section })
            }
        } header: {
            Text(clash: Self.detailsTitle(label: configurationLabel))
                .accessibilityIdentifier("configuration-center.configuration.details-header")
        }
    }

     
     
    static func detailsTitle(label: String?) -> ClashDisplayText {
        guard let label, !label.trimmingCharacters(in: .whitespaces).isEmpty else { return .copy("Configuration Details") }
        return .format("%@ Configuration Details", [label])
    }

     
     
     
    private func footerLines(hasOwn: Bool) -> [ClashDisplayText] {
        Self.footerLines(reach: schemeReach, hasOwn: hasOwn, runsOriginal: original?.isChosen == true)
    }

     
     
    static func footerLines(reach: ClashDisplayText?, hasOwn: Bool, runsOriginal: Bool) -> [ClashDisplayText] {
        var lines: [ClashDisplayText] = []
        if let reach { lines.append(reach) }
        if hasOwn { lines.append(.copy("Custom rules and the override script are this configuration’s own and stay when you switch schemes.")) }
        if runsOriginal {
            lines.append(.copy("An original configuration runs its own rules, so rule library changes do not reach it; pick a rule scheme above to use them."))
        }
        return lines
    }

     
     
     
    private var schemeReach: ClashDisplayText? {
        switch scheme?.kind {
        case .own(let count)? where count > 1:
            return .format("Changes here apply to all %@ configurations on rule scheme “%@”.", [String(count), scheme?.label ?? ""])
        case .builtIn?, .shared?:
            return .format("Saving here copies rule scheme “%@” for this configuration only.", [scheme?.label ?? ""])
        default:
            return nil
        }
    }

     

     
    private static let originalTag = "\u{0}original"

     
     
     
     
     
     
     
     
    private var schemeRow: some View {
        let runsOriginal = original?.isChosen == true
        let line: ClashDisplayText = runsOriginal ? original?.sourceName.map(ClashDisplayText.verbatim) ?? .copy("Original")
            : scheme.map { chosen in followedLinks[chosen.id].map { .format("Follows the “%@” link", [$0]) } ?? Self.kindLine(chosen.kind) } ?? .verbatim("")
        let selection = Binding<String>(
            get: { runsOriginal ? Self.originalTag : scheme?.id ?? "" },
            set: { id in
                if id == Self.originalTag {
                    if let original, !original.isChosen { original.choose() }
                } else {
                    chooseScheme(id)
                }
            }
        )
         
         
         
        let split = Self.builtInFirst(schemes)
        return Picker(selection: selection) {
            ForEach(split.builtIn, id: \.id) { choice in
                Text(verbatim: menuLine(choice)).tag(choice.id)
            }
            if original != nil {
                Text(clash: .copy("Original")).tag(Self.originalTag)
                    .accessibilityIdentifier("configuration-center.configuration.original")
            }
            ForEach(split.others, id: \.id) { choice in
                Text(verbatim: menuLine(choice)).tag(choice.id)
            }
        } label: {
            Text(clash: .copy("Rule Scheme"))
            Text(clash: line)
        }
        .pickerStyle(.menu)
        .disabled(busy)
        .accessibilityIdentifier("configuration-center.configuration.schemes.all")
    }

     
     
    static func builtInFirst(_ schemes: [ConfigurationRuleScheme]) -> (builtIn: [ConfigurationRuleScheme], others: [ConfigurationRuleScheme]) {
        let ids = Set(ConfigurationBuiltins.schemes.map(\.id))
        return (schemes.filter { ids.contains($0.id) }, schemes.filter { !ids.contains($0.id) })
    }

     
    private func menuLine(_ scheme: ConfigurationRuleScheme) -> String {
        Self.menuLine(scheme, usage: usage, followedLink: followedLinks[scheme.id], locale: locale)
    }

     
    static func menuLine(_ scheme: ConfigurationRuleScheme, usage: [String: Int], followedLink: String?, locale: Locale) -> String {
        let kind: ClashDisplayText
        if ConfigurationBuiltins.isNative(scheme.id) {
            kind = .copy("Built-in")
        } else if let followedLink {
            kind = .format("Follows the “%@” link", [followedLink])
        } else {
            kind = .count(usage[scheme.id] ?? 0, one: "Used by %@ configuration", other: "Used by %@ configurations")
        }
        return scheme.displayLabel + " · " + ClashCopy.string(for: kind, locale: locale)
    }

    static func kindLine(_ kind: ClashMacOutlineScheme.Kind) -> ClashDisplayText {
        switch kind {
        case .builtIn: return .copy("Built-in Scheme")
        case .shared: return .copy("Profile URL Scheme")
        case .own(let count): return .count(count, one: "Your scheme · used by %@ configuration", other: "Your scheme · used by %@ configurations")
        }
    }

     

     
     
     
    @ViewBuilder
    private func outlineRow(_ section: ConfigurationOutlineSection, _ row: ConfigurationOutlineRow?) -> some View {
        let shown = row.map { Self.value($0, script: scriptValue) } ?? Self.valueWithoutOutline(section, script: scriptValue, customRules: customRules)
        let label = LabeledContent { Text(clash: shown.value) } label: { Text(clash: Self.title(section)) }
        let identifier = Self.identifier(section)
        switch destination(section) {
        case .page(let page)?:
            ClashRoutedViewLink(onReturn: onReturn) { page() } label: { label }
                .accessibilityValue(Text(clash: shown.value))
                .accessibilityIdentifier(identifier)
        case .open(let open)?:
            Button(action: open) { label }
                .buttonStyle(.plain)
                .accessibilityValue(Text(clash: shown.value))
                .accessibilityIdentifier(identifier)
        case nil:
            label
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(identifier)
        }
    }

     
     
    static func identifier(_ section: ConfigurationOutlineSection) -> String {
        switch section {
        case .customRules: return named(identifier: "configuration-center.configuration.custom-rules")
        case .overrideScript: return named(identifier: "configuration-center.configuration.scripts")
        case .sniffer: return named(identifier: "configuration-center.configuration.network")
        default: return sectionIdentifier(section, identifierPrefix: "configuration-center.configuration.outline")
        }
    }

     
    private static func named(identifier: String) -> String { identifier }

    private static func sectionIdentifier(_ section: ConfigurationOutlineSection, identifierPrefix: String) -> String {
        identifierPrefix + "." + section.rawValue
    }

     
     
    static func title(_ section: ConfigurationOutlineSection) -> ClashDisplayText {
        switch section {
        case .general: return .copy("General Configuration (Configuration Chapter)")
        case .dns: return .copy("DNS")
        case .sniffer: return .copy("Domain Sniffing (Configuration Chapter)")
        case .mitm: return .copy("MITM Interception (Configuration Chapter)")
        case .inbound: return .copy("Inbounds (Configuration Chapter)")
        case .proxies: return .copy("Proxies (Configuration Chapter)")
        case .proxyProviders: return .copy("Proxy Providers (Configuration Chapter)")
        case .proxyGroups: return .copy("Proxy Groups (Configuration Chapter)")
        case .rules: return .copy("Route Rules (Configuration Chapter)")
        case .ruleProviders: return .copy("Rule Providers (Configuration Chapter)")
        case .subRules: return .copy("Sub-rules")
        case .tunnels: return .copy("Tunnels (Configuration Chapter)")
        case .ntp: return .copy("NTP")
        case .experimental: return .copy("Experimental (Configuration Chapter)")
        case .unknown: return .copy("Unknown Keys")
        case .customRules: return .copy("Custom Rules")
        case .overrideScript: return .copy("Override Script")
        }
    }

    static func valueWithoutOutline(_ section: ConfigurationOutlineSection, script: ClashDisplayText,
                                    customRules: Int) -> (value: ClashDisplayText, note: ClashDisplayText?) {
        switch section {
        case .overrideScript: return (script, nil)
        case .customRules: return (customRules == 0 ? .verbatim("") : .count(customRules, one: "%@ rule", other: "%@ rules"), nil)
        default: return (.verbatim(""), nil)
        }
    }

     
     
     
     
    static func shownSections(_ rows: [ConfigurationOutlineRow]?, form: ConfigurationOutlineForm) -> [ConfigurationOutlineSection] {
        guard let rows else { return ConfigurationOutline.sections(for: form).filter { $0 != .unknown } }
        return rows.filter { $0.section != .unknown || $0.count > 0 }.map(\.section)
    }

     
     
     
     
    static func value(_ row: ConfigurationOutlineRow, script: ClashDisplayText) -> (value: ClashDisplayText, note: ClashDisplayText?) {
        if row.section == .overrideScript { return (script, nil) }
        if ConfigurationOutline.showsDefaults(row.section) {
            switch (row.section, row.enabled) {
            case (.sniffer, false?): return (.copy("Off"), nil)
            case (.sniffer, true?): return (.copy("On"), nil)
            case (.mitm, false?): return (.copy("Off"), nil)
            case (.mitm, true?): return (.copy("On"), nil)
            default: return (.verbatim(""), nil)
            }
        }
        guard row.count > 0 else { return (.verbatim(""), nil) }
        let count = String(row.count)
        switch row.section {
        case .customRules:
            return (.count(row.count, one: "%@ rule", other: "%@ rules"), nil)
        case .proxyGroups where (row.hidden ?? 0) > 0:
            return (.format("%@ · %@ hidden", [count, String(row.hidden ?? 0)]), nil)
        case .unknown:
            return (.format("%@ · Read Only", [count]), nil)
        default:
            return (.verbatim(count), nil)
        }
    }
}

 
 
struct ClashMacConfigurationPageActions: View {
    let editSource: (@MainActor () -> Void)?
    let compile: (@MainActor () -> Void)?
    let compiling: Bool
    let export: @MainActor () -> Void
    let saveAsScheme: (@MainActor () -> Void)?
     
    var duplicate: (@MainActor () -> Void)? = nil
    var duplicating = false

     
     
     
    var body: some View {
        Section {
            HStack(spacing: 8) {
                if let editSource {
                    Button(action: editSource) {
                        Label { Text(clash: .copy("Edit Source…")) } icon: { Image(systemName: "pencil") }
                    }
                    .accessibilityIdentifier("configuration-center.configuration.page.edit-source")
                }
                if let compile {
                    Button(action: compile) {
                        Label { Text(clash: .copy("Compile Configuration")) } icon: {
                            if compiling { ProgressView().controlSize(.small) } else { Image(systemName: "checkmark.seal") }
                        }
                    }
                    .disabled(compiling)
                    .accessibilityIdentifier("configuration-center.configuration.page.compile")
                }
                if let saveAsScheme {
                    Button(action: saveAsScheme) {
                        Label { Text(clash: .copy("Save as Rule Scheme…")) } icon: { Image(systemName: "square.stack") }
                    }
                    .accessibilityIdentifier("configuration-center.configuration.page.save-as-scheme")
                }
                if let duplicate {
                    Button(action: duplicate) {
                        Label { Text(clash: .copy("Duplicate")) } icon: {
                            if duplicating { ProgressView().controlSize(.small) } else { Image(systemName: "plus.square.on.square") }
                        }
                    }
                    .disabled(duplicating)
                    .accessibilityIdentifier("configuration-center.configuration.page.duplicate")
                }
                Button(action: export) {
                    Label { Text(clash: .copy("Export…")) } icon: { Image(systemName: "square.and.arrow.up") }
                }
                .accessibilityIdentifier("configuration-center.configuration.page.export")
                Spacer()
            }
        } footer: {
            Text(clash: .copy("Changes take effect as you make them. Compiling only checks."))
        }
    }
}

 
 
struct ClashMacCompileResultSheet: View {
    let result: ClashMacCompileResult
    let done: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(clash: headline).font(.headline)
            } icon: {
                Image(systemName: result == .accepted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(result == .accepted ? Color.green : Color.orange)
            }
            if case .refused(let problems) = result, !problems.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(problems.enumerated()), id: \.offset) { _, problem in
                            VStack(alignment: .leading, spacing: 2) {
                                if let place = problem.place {
                                    Text(verbatim: place).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                }
                                Text(verbatim: problem.message).font(.body.monospaced())
                            }
                        }
                    }
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 260)
                .accessibilityIdentifier("configuration-center.configuration.compile.detail")
            } else if case .unavailable(let why?) = result {
                Text(verbatim: why).font(.body.monospaced()).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("configuration-center.configuration.compile.detail")
            }
            Text(clash: .copy("Only checked: nothing was published or reconnected."))
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(action: done) { Text(clash: .copy("OK")) }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("configuration-center.configuration.compile.done")
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var headline: ClashDisplayText {
        switch result {
        case .accepted: return .copy("The core accepts this configuration.")
        case .refused: return .copy("The core refuses this configuration.")
        case .unavailable: return .copy("This configuration could not be checked.")
        }
    }

}

 
struct ClashMacCompilePresentation: Identifiable {
    let id = UUID()
    let result: ClashMacCompileResult
}
