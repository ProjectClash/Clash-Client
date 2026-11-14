import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
public struct ClashMacCustomRule: Identifiable, Equatable, Sendable {
    public var text: String
    public var isEnabled: Bool
    public var comment: String?
    public var id: String { text }

    public init(text: String, isEnabled: Bool = true, comment: String? = nil) {
        self.text = text; self.isEnabled = isEnabled; self.comment = comment
    }
}

public struct ClashMacCustomRulesState: Equatable, Sendable {
    public var rules: [ClashMacCustomRule]
     
     
    public var prepends: Bool

    public init(rules: [ClashMacCustomRule], prepends: Bool) { self.rules = rules; self.prepends = prepends }
    public static let empty = ClashMacCustomRulesState(rules: [], prepends: true)
}

 
 
 
public struct ClashMacCustomRulesActions {
    public var load: @MainActor () async -> ClashMacCustomRulesState
     
    public var save: @MainActor ([ClashMacCustomRule]) async throws -> ClashMacCustomRulesState
    public var setPrepends: @MainActor (Bool) async throws -> ClashMacCustomRulesState
     
     
     
     
    public var targets: @MainActor () async throws -> ConfigurationRuleTargetCandidates
     
     
    public var geoValues: ClashMacGeoValueLoader
     
     
     
    public var targetSearch: ClashRuleTargetSearchHook?
     
     
     
     
    public var ruleNames: @MainActor () async -> ClashRuleNames? = { nil }

    public init(
        load: @escaping @MainActor () async -> ClashMacCustomRulesState,
        save: @escaping @MainActor ([ClashMacCustomRule]) async throws -> ClashMacCustomRulesState,
        setPrepends: @escaping @MainActor (Bool) async throws -> ClashMacCustomRulesState,
        targets: @escaping @MainActor () async throws -> ConfigurationRuleTargetCandidates,
        geoValues: @escaping ClashMacGeoValueLoader = { _ in [] },
        targetSearch: ClashRuleTargetSearchHook? = nil
    ) {
        self.load = load; self.save = save; self.setPrepends = setPrepends; self.targets = targets; self.geoValues = geoValues
        self.targetSearch = targetSearch
    }
}

 
 
 
 
 
 
 
 
 
 
@MainActor
final class ClashMacCustomRulesModel: ObservableObject {
    @Published private(set) var state: ClashMacCustomRulesState
     
     
    @Published private(set) var error: String?
     
    @Published private(set) var names: ClashRuleNames?
    let writes = ClashMacPageWrites<String>()
    var switches: ClashStoredSwitch<String> { writes.switches }
     
    var locale = Locale.current
    private var acting: [UUID: Task<Void, Never>] = [:]

    init(initial: ClashMacCustomRulesState) {
        state = initial
    }

     
    static let prepends = "\u{0}prepends"

     
    static func rule(_ text: String) -> String { "rule\u{0}" + text }

    func load(_ actions: ClashMacCustomRulesActions) async {
        await writes.turns.run { state = await actions.load() }
        names = await actions.ruleNames()
    }

    func setEnabled(_ text: String, _ on: Bool, _ actions: ClashMacCustomRulesActions) {
        switches.press(Self.rule(text), on) { [weak self] on in
            guard let self else { return }
             
             
            var rules = self.state.rules
            guard let index = rules.firstIndex(where: { $0.text == text }), rules[index].isEnabled != on else { return }
            rules[index].isEnabled = on
            try await self.saving { try await actions.save(rules) }
        }
    }

    func setPrepends(_ on: Bool, _ actions: ClashMacCustomRulesActions) {
        switches.press(Self.prepends, on) { [weak self] on in
            guard let self, self.state.prepends != on else { return }
            try await self.saving { try await actions.setPrepends(on) }
        }
    }

    func remove(_ text: String, _ actions: ClashMacCustomRulesActions) {
        act(actions) { $0.filter { $0.text != text } }
    }

     
     
    func move(fromOffsets offsets: IndexSet, toOffset destination: Int, _ actions: ClashMacCustomRulesActions) {
        var shown = state.rules
        shown.move(fromOffsets: offsets, toOffset: destination)
        let order = shown.map(\.text)
        act(actions) { rules in
            let byText = Dictionary(rules.map { ($0.text, $0) }, uniquingKeysWith: { first, _ in first })
            let placed = order.compactMap { byText[$0] }
            return placed + rules.filter { !order.contains($0.text) }
        }
    }

     
    func add(_ rule: ClashMacCustomRule, _ actions: ClashMacCustomRulesActions) async throws {
        try await writes.turns.run {
            state = try await actions.save(state.rules + [rule])
        }
    }

     
    func waitForWrites() async {
        repeat {
            while let (id, task) = acting.first {
                await task.value
                acting[id] = nil
            }
            await switches.waitForWrites()
        } while !acting.isEmpty || switches.isDraining
    }

     
     
    private func saving(_ save: () async throws -> ClashMacCustomRulesState) async throws {
        do {
            state = try await save()
        } catch {
            throw ClashMacStoredRefusal(message: ClashErrorCopy.message(error, locale: locale))
        }
    }

    private func act(_ actions: ClashMacCustomRulesActions, _ change: @escaping ([ClashMacCustomRule]) -> [ClashMacCustomRule]) {
        error = nil
        let id = UUID()
        acting[id] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.acting[id] = nil }
            do {
                try await self.writes.turns.run {
                    self.state = try await actions.save(change(self.state.rules))
                }
            } catch {
                self.error = ClashErrorCopy.message(error, locale: self.locale)
            }
        }
    }
}

 
 
 
 
 
public struct ClashMacCustomRulesPage: View {
    @Environment(\.configurationFieldCopy) private var copy
    @Environment(\.locale) private var locale
    let actions: ClashMacCustomRulesActions
    @StateObject private var model: ClashMacCustomRulesModel
    @State private var adding = false

    public init(actions: ClashMacCustomRulesActions, initial: ClashMacCustomRulesState = .empty) {
        self.actions = actions
        _model = StateObject(wrappedValue: ClashMacCustomRulesModel(initial: initial))
    }

    public var body: some View {
        let state = model.state
        List {
            Section {
                ForEach(state.rules) { rule in
                    let key = ClashMacCustomRulesModel.rule(rule.text)
                    VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                        ClashStoredToggle(model.switches, key: key, stored: rule.isEnabled,
                                          identifier: "configuration-center.custom-rules.rule.\(rule.text)",
                                          set: { model.setEnabled(rule.text, $0, actions) }) {
                            VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                                 
                                 
                                ConfigurationRuleRow(rule.text, showsChevron: false)
                                if let comment = rule.comment, !comment.isEmpty {
                                    Text(verbatim: comment).font(.subheadline).foregroundStyle(.secondary)
                                }
                                 
                                 
                                 
                                if rule.isEnabled, let why = model.names?.notInEffect(rule.text) {
                                    Text(clash: why).font(.subheadline).foregroundStyle(.orange)
                                        .accessibilityIdentifier("configuration-center.custom-rules.not-in-effect")
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                         
                        ClashStoredFailure(model.switches, key: key) { failure in
                            Text(verbatim: failure).font(.subheadline).foregroundStyle(.red)
                                .accessibilityIdentifier("configuration-center.custom-rules.rule.error")
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) { model.remove(rule.text, actions) } label: { Text(clash: .copy("Delete")) }
                            .accessibilityIdentifier("configuration-center.custom-rules.delete")
                    }
                }
                .onMove { offsets, destination in
                    model.move(fromOffsets: offsets, toOffset: destination, actions)
                }
                Button { adding = true } label: { Label { Text(clash: .copy("Add Rule")) } icon: { Image(systemName: "plus") } }
                    .accessibilityIdentifier("configuration-center.custom-rules.add")
            } footer: {
                VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                    Text(clash: state.prepends
                        ? .copy("These rules are added in front of the configuration's own rules when it is used.")
                        : .copy("These rules are added after the configuration's own rules when it is used."))
                    Text(clash: .copy(ClashProfileRulesCopy.everyProfileHint))
                }
            }
            Section {
                ClashStoredToggle(model.switches, key: ClashMacCustomRulesModel.prepends, stored: state.prepends,
                                  identifier: "configuration-center.custom-rules.prepend",
                                  set: { model.setPrepends($0, actions) }) {
                    Text(clash: .copy("Insert before profile URL rules"))
                }
                .toggleStyle(.switch)
                ClashStoredFailure(model.switches, key: ClashMacCustomRulesModel.prepends) { failure in
                    Text(verbatim: failure).foregroundStyle(.red)
                        .accessibilityIdentifier("configuration-center.custom-rules.prepend.error")
                }
            }
            if let error = model.error {
                Section {
                    Text(verbatim: error).foregroundStyle(.red)
                        .accessibilityIdentifier("configuration-center.custom-rules.error")
                }
            }
        }
         
         
        .listStyle(.inset)
        .accessibilityIdentifier("configuration-center.custom-rules")
        .task {
            model.locale = locale
            await model.load(actions)
        }
        .onChange(of: locale) { model.locale = $0 }
        .sheet(isPresented: $adding) {
            ClashMacAddRuleSheet(
                targets: actions.targets,
                ruleSets: model.names?.ruleSets.map { $0.sorted() },
                geoValues: actions.geoValues,
                add: { rule in try await model.add(rule, actions) },
                close: { adding = false }
            )
            .environment(\.clashRuleTargetSearch, actions.targetSearch)
            .clashModalPresentation(.fitted)
        }
    }
}

 
 
 
struct ClashMacAddRuleSheet: View {
    @Environment(\.configurationFieldCopy) private var copy
    @Environment(\.locale) private var locale
    let targets: @MainActor () async throws -> ConfigurationRuleTargetCandidates
     
     
     
     
     
    var ruleSets: [String]? = nil
    let geoValues: ClashMacGeoValueLoader
    let add: @MainActor (ClashMacCustomRule) async throws -> Void
    let close: () -> Void
    @State private var action: ClashStructuredRule.Action = .domainSuffix
     
    @State private var pickingRuleSet = false
     
     
    @State private var lastAction: ClashStructuredRule.Action = .domainSuffix
    @Environment(\.clashMacEditorSyntax) private var syntax
    @State private var content = ""
     
    @State private var pickingGeo = false
     
     
    @State private var pickedFrom: ClashMacGeoResource?
    @State private var target = "DIRECT"
    @State private var candidates = ConfigurationRuleTargetCandidates.make(groups: [], sources: [])
    @State private var pickingTarget = false
    @State private var enabled = true
    @State private var comment = ""
    @State private var busy = false
    @State private var error: String?

    private var assembled: String {
        var parts = [action.rawValue]
        if action.needsContent { parts.append(content.trimmingCharacters(in: .whitespacesAndNewlines)) }
        parts.append(target)
        return parts.joined(separator: ",")
    }

    private var canAdd: Bool {
        (!action.needsContent || !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) && !busy && !pickingGeo && !pickingTarget
            && !pickingRuleSet
    }

    private var title: ClashDisplayText {
        if pickingGeo, let resource = action.clashMacGeoResource { return resource.rowTitle }
        if pickingTarget { return .copy("Target") }
        if pickingRuleSet { return .copy("Rule Set") }
        return .copy("Add Rule")
    }

    var body: some View {
        ClashMacSheetFrame(title: title, width: 520, height: 440) {
            if pickingGeo, let resource = action.clashMacGeoResource {
                ClashMacGeoValuePickerPage(
                    resource: resource, current: content, load: geoValues,
                    identifier: "configuration-center.custom-rules.form.geo"
                ) { picked in
                    content = picked
                    pickedFrom = resource
                    pickingGeo = false
                }
            } else if pickingTarget {
                ClashMacTargetPickerPage(
                    candidates: candidates, current: target,
                    identifier: "configuration-center.custom-rules.form.target"
                ) { picked in
                    target = picked
                    pickingTarget = false
                }
            } else if pickingRuleSet {
                ClashMacTargetPickerPage(
                    candidates: ConfigurationRuleTargetCandidates(sections: [
                        .init(id: "rule-sets", kind: .source, sourceLabel: ClashCopy.string("Rule Sets", locale: locale), names: ruleSets ?? [])
                    ]),
                    current: content,
                    identifier: "configuration-center.custom-rules.form.rule-set"
                ) { picked in
                    content = picked
                    pickingRuleSet = false
                }
            } else {
                form
            }
        } leading: {
            if pickingGeo {
                Button { pickingGeo = false } label: { Text(clash: .copy("Back")) }
                    .accessibilityIdentifier("configuration-center.custom-rules.form.geo.back")
            } else if pickingTarget {
                Button { pickingTarget = false } label: { Text(clash: .copy("Back")) }
                    .accessibilityIdentifier("configuration-center.custom-rules.form.target.back")
            } else if pickingRuleSet {
                Button { pickingRuleSet = false } label: { Text(clash: .copy("Back")) }
                    .accessibilityIdentifier("configuration-center.custom-rules.form.rule-set.back")
            }
        } trailing: {
            ClashMacSheetButtons(
                closeTitle: .copy("Cancel"),
                closeIdentifier: "configuration-center.custom-rules.form.cancel",
                primaryTitle: .copy("Add"),
                primaryIdentifier: "configuration-center.custom-rules.form.add",
                primaryDisabled: !canAdd,
                isBusy: busy,
                onClose: close,
                onPrimary: submit
            )
        }
        .onChange(of: action) { changed in
             
             
             
            if changed.clashMacGeoResource != pickedFrom { content = ""; pickedFrom = nil }
             
            content = ClashRulePolicyOptions.value(content, from: lastAction, to: changed, ruleSets: ruleSets)
            lastAction = changed
        }
    }

    private var form: some View {
            ClashMacSheetForm {
                Section {
                    Picker(selection: $action) {
                        ForEach(ClashMacRuleRowEditor.offeredActions(syntax, keeping: action, ruleSets: ruleSets), id: \.self) { item in
                            Text(verbatim: ConfigurationRuleWords.kindName(item.rawValue, locale: locale, copy: copy)).tag(item)
                        }
                    } label: {
                        Text(clash: .copy("Rule Type"))
                    }
                    .disabled(busy)
                    .accessibilityIdentifier("configuration-center.custom-rules.form.action")
                    if action == .ruleSet, let ruleSets {
                         
                        ClashMacTargetRow(title: .copy("Rule Set"), value: content,
                                          identifier: "configuration-center.custom-rules.form.rule-set") {
                            pickingRuleSet = true
                        }
                        .disabled(busy || ruleSets.isEmpty)
                    } else if let resource = action.clashMacGeoResource {
                         
                        ClashMacGeoValueRow(resource: resource, value: content, identifier: "configuration-center.custom-rules.form.geo") {
                            pickingGeo = true
                        }
                        .disabled(busy)
                    } else if action.needsContent {
                        LabeledContent {
                            TextField(text: $content, prompt: Text(verbatim: action.contentPlaceholder)) { Text(clash: .copy(action.contentLabel)) }
                                .labelsHidden()
                                .font(.body.monospaced())
                                .multilineTextAlignment(.trailing)
                                .disabled(busy)
                                .accessibilityIdentifier("configuration-center.custom-rules.form.content")
                        } label: {
                            Text(clash: .copy(action.contentLabel))
                        }
                    }
                     
                     
                    ClashMacTargetRow(title: .copy("Target"), value: target, identifier: "configuration-center.custom-rules.form.target") {
                        pickingTarget = true
                    }
                    .disabled(busy)
                    Toggle(isOn: $enabled) { Text(clash: .copy("Enabled")) }
                        .disabled(busy)
                        .accessibilityIdentifier("configuration-center.custom-rules.form.enabled")
                    TextField(text: $comment) { Text(clash: .copy("Comment")) }
                        .disabled(busy)
                        .accessibilityIdentifier("configuration-center.custom-rules.form.comment")
                     
                    Text(clash: .format("Written as %@ in the configuration file", [assembled]))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let error {
                    Section {
                        Text(verbatim: error).foregroundStyle(.red)
                            .accessibilityIdentifier("configuration-center.custom-rules.form.error")
                    }
                }
            }
            .task {
                if let loaded = try? await targets(), !loaded.names.isEmpty {
                    candidates = loaded
                    if !loaded.contains(target) { target = loaded.names[0] }
                }
            }
    }

    private func submit() {
        guard canAdd else { return }
        busy = true
        error = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
                try await add(ClashMacCustomRule(text: assembled, isEnabled: enabled, comment: trimmed.isEmpty ? nil : trimmed))
                close()
            } catch {
                self.error = ClashErrorCopy.message(error, locale: locale)
            }
        }
    }
}
