import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
 

 
 
 
 
 
public struct ClashMacRulesPageLeading: View {
     
     
    let scheme: ClashDisplayText?
    let schemePage: @MainActor () -> AnyView
    let customRules: ClashMacCustomRulesActions
     
     
    let customState: ClashMacCustomRulesState
    let configurationName: String
     
    let addCustomRule: @MainActor () -> Void
    let palette: ClashProductPalette
    @StateObject private var model: ClashMacCustomRulesModel
    @Environment(\.locale) private var locale

    public init(scheme: ClashDisplayText?, schemePage: @escaping @MainActor () -> AnyView,
                customRules: ClashMacCustomRulesActions, customState: ClashMacCustomRulesState,
                configurationName: String, addCustomRule: @escaping @MainActor () -> Void, palette: ClashProductPalette) {
        self.scheme = scheme
        self.schemePage = schemePage
        self.customRules = customRules
        self.customState = customState
        self.configurationName = configurationName
        self.addCustomRule = addCustomRule
        self.palette = palette
        _model = StateObject(wrappedValue: ClashMacCustomRulesModel(initial: customState))
    }

     
    public static let customRulesNoteKey = "Only for “%@”; kept when you change the rule scheme."

    public var body: some View {
        let state = model.state
        VStack(alignment: .leading, spacing: ClashTheme.Spacing.section) {
            ClashProductGroup(palette: palette) {
                ClashRoutedViewLink(showsDisclosureIndicator: false) { schemePage() } label: {
                    ClashMacRulesPageRowLabel(title: .copy("Rule Scheme"), value: scheme)
                }
                .buttonStyle(.plain)
                .disabled(scheme == nil)
                .accessibilityIdentifier("rules.overview.scheme")
            }
             
             
             
             
            VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                ClashProductGroup(.copy("Custom Rules"), footer: .format(Self.customRulesNoteKey, [configurationName]),
                                  palette: palette) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(state.rules) { rule in
                             
                             
                            ClashRoutedViewLink(showsDisclosureIndicator: false) {
                                ClashMacCustomRuleEditPage(rule: rule, actions: customRules, model: model)
                            } label: {
                                VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                                    ConfigurationRuleRow(rule.text)
                                        .opacity(rule.isEnabled ? 1 : 0.5)
                                    if let comment = rule.comment, !comment.isEmpty {
                                        Text(verbatim: comment).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    if rule.isEnabled, let why = model.names?.notInEffect(rule.text) {
                                        Text(clash: why).font(.subheadline).foregroundStyle(.orange)
                                    }
                                }
                                .padding(.vertical, ClashTheme.Spacing.row)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("rules.overview.custom-rule")
                            Divider()
                        }
                        Button(action: addCustomRule) {
                            Label { Text(clash: .copy("Add Rule")) } icon: { Image(systemName: "plus") }
                                .padding(.vertical, ClashTheme.Spacing.row)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityIdentifier("rules.overview.custom-rules.add")
                        Divider()
                        ClashStoredToggle(model.switches, key: ClashMacCustomRulesModel.prepends, stored: state.prepends,
                                          identifier: "rules.overview.custom-rules.prepend",
                                          set: { model.setPrepends($0, customRules) }) {
                            Text(clash: .copy("Insert before profile URL rules"))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .toggleStyle(.switch)
                        .padding(.vertical, ClashTheme.Spacing.row)
                        ClashStoredFailure(model.switches, key: ClashMacCustomRulesModel.prepends) { failure in
                            Text(verbatim: failure).font(.subheadline).foregroundStyle(.red)
                        }
                        if let error = model.error {
                            Text(verbatim: error).font(.subheadline).foregroundStyle(.red)
                                .accessibilityIdentifier("rules.overview.custom-rules.error")
                        }
                    }
                }
                ClashSectionFooter(.copy(ClashProfileRulesCopy.everyProfileHint))
            }
        }
        .task(id: customState) {
            model.locale = locale
            await model.load(customRules)
        }
    }
}

 
 
public struct ClashMacRulesPageChapterRows: View {
    let ruleSets: @MainActor () -> AnyView
    let subRules: @MainActor () -> AnyView
    let palette: ClashProductPalette

    public init(ruleSets: @escaping @MainActor () -> AnyView, subRules: @escaping @MainActor () -> AnyView,
                palette: ClashProductPalette) {
        self.ruleSets = ruleSets
        self.subRules = subRules
        self.palette = palette
    }

    public var body: some View {
        ClashProductGroup(palette: palette) {
            VStack(alignment: .leading, spacing: 0) {
                ClashRoutedViewLink(showsDisclosureIndicator: false) { ruleSets() } label: {
                    ClashMacRulesPageRowLabel(title: .copy("Rule Sets"), value: nil)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("rules.overview.rule-sets")
                Divider()
                ClashRoutedViewLink(showsDisclosureIndicator: false) { subRules() } label: {
                    ClashMacRulesPageRowLabel(title: .copy("Sub-rules"), value: nil)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("rules.overview.sub-rules")
            }
        }
    }
}

 
struct ClashMacRulesPageRowLabel: View {
    let title: ClashDisplayText
    let value: ClashDisplayText?

    var body: some View {
        HStack(spacing: ClashTheme.Spacing.row) {
            Text(clash: title)
            Spacer(minLength: ClashTheme.Spacing.compact)
            if let value {
                Text(clash: value).foregroundStyle(.secondary).lineLimit(1)
            }
            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, ClashTheme.Spacing.row)
        .contentShape(Rectangle())
    }
}

 
 
struct ClashMacCustomRuleEditPage: View {
    let rule: ClashMacCustomRule
    let actions: ClashMacCustomRulesActions
    @ObservedObject var model: ClashMacCustomRulesModel

    var body: some View {
        ClashMacAddRuleSheet(
            targets: actions.targets,
            ruleSets: model.names?.ruleSets.map { $0.sorted() },
            geoValues: actions.geoValues,
            add: { _ in },
            close: {},
            editing: rule,
            replace: { [model, actions] old, new in try await model.replace(old, with: new, actions) }
        )
        .environment(\.clashRuleTargetSearch, actions.targetSearch)
        .navigationTitle(Text(clash: .copy("Rule")))
    }
}

 
 
 
public struct ClashMacCustomRuleAddSheet: View {
    let actions: ClashMacCustomRulesActions
    let close: () -> Void
    @State private var names: ClashRuleNames?

    public init(actions: ClashMacCustomRulesActions, close: @escaping () -> Void) {
        self.actions = actions
        self.close = close
    }

    public var body: some View {
        ClashMacAddRuleSheet(
            targets: actions.targets,
            ruleSets: names?.ruleSets.map { $0.sorted() },
            geoValues: actions.geoValues,
            add: { [actions] rule in try await ClashMacCustomRuleAddSheet.add(rule, actions) },
            close: close
        )
        .environment(\.clashRuleTargetSearch, actions.targetSearch)
        .task { names = await actions.ruleNames() }
    }

     
     
    @MainActor
    static func add(_ rule: ClashMacCustomRule, _ actions: ClashMacCustomRulesActions) async throws {
        let now = await actions.load()
        _ = try await actions.save(now.rules + [rule])
    }
}

 
 
 
 
 
 
 
 
 
 
public struct ClashMacRulesPageCustomRulesSection: View {
    let actions: ClashMacCustomRulesActions
    let customState: ClashMacCustomRulesState

    public init(actions: ClashMacCustomRulesActions, customState: ClashMacCustomRulesState) {
        self.actions = actions
        self.customState = customState
    }

    public var body: some View {
        ClashMacRulesPageCustomRulesList(actions: actions, customState: customState)
            .id(Self.identity(customState))
    }

     
     
    static func identity(_ state: ClashMacCustomRulesState) -> [String] {
        state.rules.map { [$0.text, $0.isEnabled ? "1" : "0", $0.comment ?? ""].joined(separator: "\u{0}") }
            + [state.prepends ? "prepends" : "appends"]
    }
}

struct ClashMacRulesPageCustomRulesList: View {
    let actions: ClashMacCustomRulesActions
    let customState: ClashMacCustomRulesState
    @StateObject private var model: ClashMacCustomRulesModel
    @Environment(\.locale) private var locale
    @Environment(\.configurationFieldCopy) private var copy
    @Environment(\.clashRulesEditQuery) private var query
    @State private var matched: (query: String, raws: Set<String>)?

    init(actions: ClashMacCustomRulesActions, customState: ClashMacCustomRulesState) {
        self.actions = actions
        self.customState = customState
        _model = StateObject(wrappedValue: ClashMacCustomRulesModel(initial: customState))
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        let rules = model.state.rules
        let filtering = !trimmedQuery.isEmpty
        let shown = ClashMacRulesPageSearch.shown(rules.map(\.text), query: trimmedQuery, matched: matched)
        let listed = rules.filter { shown.contains($0.text) }
        Group {
            if !listed.isEmpty {
                Section {
                    ForEach(listed) { rule in
                        row(rule)
                            .moveDisabled(filtering)
                    }
                    .onMove { offsets, destination in
                         
                        guard !filtering else { return }
                        model.move(fromOffsets: offsets, toOffset: destination, actions)
                    }
                    if let error = model.error {
                        Text(verbatim: error).foregroundStyle(.red)
                            .accessibilityIdentifier("rules.overview.edit.custom-rules.error")
                    }
                } header: {
                    Text(clash: .copy("Custom Rules"))
                }
            }
        }
        .task(id: customState) {
            model.locale = locale
            await model.load(actions)
        }
        .task(id: ClashMacRulesPageSearch.key(trimmedQuery, rules.map(\.text))) {
            matched = await ClashMacRulesPageSearch.search(trimmedQuery, in: rules.map(\.text), locale: locale, copy: copy)
        }
    }

    private func row(_ rule: ClashMacCustomRule) -> some View {
        let key = ClashMacCustomRulesModel.rule(rule.text)
        return VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
            HStack(alignment: .firstTextBaseline, spacing: ClashTheme.Spacing.compact) {
                 
                 
                Button { model.remove(rule.text, actions) } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help(Text(clash: .copy("Delete")))
                .accessibilityLabel(Text(clash: .copy("Delete")))
                .accessibilityIdentifier("rules.overview.edit.custom-rule.delete")
                ClashStoredToggle(model.switches, key: key, stored: rule.isEnabled,
                                  identifier: "rules.overview.edit.custom-rule.enabled",
                                  set: { model.setEnabled(rule.text, $0, actions) }) {
                    Text(clash: .copy("Enabled"))
                }
                .labelsHidden()
                .toggleStyle(.checkbox)
                ClashRoutedViewLink(showsDisclosureIndicator: false) {
                    ClashMacCustomRuleEditPage(rule: rule, actions: actions, model: model)
                } label: {
                    VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                        ConfigurationRuleRow(rule.text)
                        if let comment = rule.comment, !comment.isEmpty {
                            Text(verbatim: comment).font(.subheadline).foregroundStyle(.secondary)
                        }
                        if rule.isEnabled, let why = model.names?.notInEffect(rule.text) {
                            Text(clash: why).font(.subheadline).foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("rules.overview.edit.custom-rule")
            }
            ClashStoredFailure(model.switches, key: key) { failure in
                Text(verbatim: failure).font(.subheadline).foregroundStyle(.red)
            }
        }
        .contextMenu {
            Button(role: .destructive) { model.remove(rule.text, actions) } label: { Text(clash: .copy("Delete")) }
        }
    }
}

 
 
 
 
enum ClashMacRulesPageSearch {
     
     
    static func key(_ query: String, _ raws: [String]) -> String {
        guard !query.isEmpty else { return "" }
        var hasher = Hasher()
        raws.forEach { hasher.combine($0) }
        return "\(query)#\(hasher.finalize())"
    }

     
    static func search(_ query: String, in raws: [String], locale: Locale, copy: ConfigurationFieldCopy,
                       names: [String: String] = [:]) async -> (query: String, raws: Set<String>)? {
        guard !query.isEmpty else { return nil }
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard !Task.isCancelled else { return nil }
        let found = await Task.detached(priority: .userInitiated) {
            matches(raws, query: query, locale: locale, copy: copy, names: names)
        }.value
        return Task.isCancelled ? nil : (query, found)
    }

    static func matches(_ raws: [String], query: String, locale: Locale, copy: ConfigurationFieldCopy,
                        names: [String: String]) -> Set<String> {
        var found: Set<String> = []
        for raw in raws {
            if raw.localizedCaseInsensitiveContains(query) { found.insert(raw); continue }
            let words = ConfigurationRuleWords.of(raw, locale: locale, copy: copy, ruleSetNames: names)
            if [words.match, words.kind, words.target ?? ""].contains(where: { $0.localizedCaseInsensitiveContains(query) }) {
                found.insert(raw)
            }
        }
        return found
    }

     
     
    static func shown(_ raws: [String], query: String, matched: (query: String, raws: Set<String>)?) -> Set<String> {
        guard !query.isEmpty, let matched else { return Set(raws) }
        return matched.raws
    }
}
