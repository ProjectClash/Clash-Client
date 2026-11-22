#if os(iOS)
import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
 
 
 

 

 
@MainActor
enum ConfigurationSubRuleDetail {
     

     
     
    static func leadingIn(_ id: UUID, in draft: ConfigurationRuleDraft) -> [String] {
        guard let name = draft.subRules.first(where: { $0.id == id })?.name else { return [] }
        let elsewhere = draft.rows + draft.subRules.filter { $0.id != id }.flatMap(\.rows)
        return elsewhere.map(\.raw).filter { ConfigurationRuleDraft.subRuleTarget(of: $0) == name }
    }

     
    @discardableResult
    static func rename(_ id: UUID, to name: String, in session: ConfigurationSchemeDraftSession) async -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let old = session.draft?.subRules.first(where: { $0.id == id })?.name, name != old else { return false }
        return await session.change { try $0.renameSubRule(id, to: name) }
    }

     
     
     
     
    @discardableResult
    static func setRule(_ raw: String, rowID: UUID?, in id: UUID, session: ConfigurationSchemeDraftSession) async -> Bool {
        await session.change { try $0.setSubRuleRow(raw, rowID: rowID, in: id) }
    }

    @discardableResult
    static func deleteRules(_ ids: Set<UUID>, in id: UUID, session: ConfigurationSchemeDraftSession) async -> Bool {
        await session.change { $0.removeSubRuleRows(ids, in: id) }
    }

    @discardableResult
    static func moveRules(_ offsets: IndexSet, to destination: Int, in id: UUID,
                          session: ConfigurationSchemeDraftSession) async -> Bool {
        await session.change { $0.moveSubRuleRows(fromOffsets: offsets, toOffset: destination, in: id) }
    }

     
     
     
     
     
    static func delete(_ id: UUID, in session: ConfigurationSchemeDraftSession) async -> (() async -> Bool)? {
        guard let draft = session.draft, let index = draft.subRules.firstIndex(where: { $0.id == id }) else { return nil }
        let saved = draft.subRules[index]
        guard await session.change({ try $0.removeSubRule(id) }) else { return nil }
        guard await landed(session, { !$0.subRules.contains { $0.id == id } }) else { return nil }
        return {
            guard await session.change({ try $0.insertSubRule(saved, at: index) }) else { return false }
            return await landed(session) { $0.subRules.contains { $0.name == saved.name } }
        }
    }

     
    static func landed(_ session: ConfigurationSchemeDraftSession, _ holds: (ConfigurationRuleDraft) -> Bool) async -> Bool {
        await session.waitForSaves()
        guard session.failure == nil, !session.hasUnsavedChanges, let draft = session.draft else { return false }
        return holds(draft)
    }

     

    static func path(_ name: String) -> [ConfigurationTextPathStep] { [.key("sub-rules"), .key(name)] }

     
    static func rules(of name: String, in session: ConfigurationEditorSession) -> [String]? {
        guard case .array(let items)? = session.value(at: ["sub-rules", name]) else { return nil }
        return items.map { item in
            if case .string(let text) = item { return text }
            return item.serialized()
        }
    }

     
     
    static func leadingIn(_ name: String, in session: ConfigurationEditorSession) -> [String] {
        guard let document = session.page?.document else { return [] }
        return Array(OriginalListEdits.uses(ofSubRule: name, in: document).prefix(5))
    }

     
     
    @discardableResult
    static func setRule(_ raw: String, at index: Int?, of name: String, session: ConfigurationEditorSession) async -> Bool {
        let rule = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rule.isEmpty else { return false }
        if let index {
             
             
             
            if let rules = rules(of: name, in: session), rules.indices.contains(index),
               rules[index].trimmingCharacters(in: .whitespacesAndNewlines) == rule { return true }
            return await session.editOriginal(steps: [OriginalListEdits.settingRule(rule, at: index, under: path(name))])
        }
        return await session.editOriginal(steps: [OriginalListEdits.addingRule(rule, to: rules(of: name, in: session),
                                                                               under: path(name))])
    }

    @discardableResult
    static func deleteRules(_ indices: [Int], of name: String, session: ConfigurationEditorSession) async -> Bool {
        await session.editOriginal(steps: OriginalListEdits.deleting(indices, under: path(name)))
    }

    @discardableResult
    static func moveRules(_ offsets: IndexSet, to destination: Int, of name: String,
                          session: ConfigurationEditorSession) async -> Bool {
        let steps = OriginalListEdits.moveSteps(offsets, to: destination, under: path(name))
        guard !steps.isEmpty else { return false }
        return await session.editOriginal(steps: steps)
    }

     
     
     
     
     
     
     
     
    static func delete(_ name: String, in session: ConfigurationEditorSession) async -> (() async -> Bool)? {
        guard let document = session.page?.document, let saved = session.value(at: ["sub-rules", name]) else { return nil }
        let places = OriginalListEdits.uses(ofSubRule: name, in: document)
        guard places.isEmpty else {
            session.refuseDeleting(name, usedBy: places)
            return nil
        }
        guard await !session.keptRulesRefuseDeleting([name]) else { return nil }
        let store = session.model.configurationLibraryStore
        let id = session.profileID
        let followedLink = await Task.detached(priority: .userInitiated) {
            (try? store.map { try ConfigurationOriginalGroupDeletion.followsLink(id, in: $0.snapshot()) }) == true
        }.value
        guard await session.editOriginal(steps: OriginalListEdits.deleting([name], fromMappingAt: "sub-rules")) else { return nil }
        if followedLink {
             
            let textAfter = await Task.detached(priority: .userInitiated) {
                store.flatMap { try? ConfigurationOriginalGroupDeletion.text(of: id, in: $0) }
            }.value
            return {
                do {
                    try await ConfigurationOriginalGroupDeletion.rejoinLink(profileID: id, model: session.model, expecting: textAfter)
                } catch {
                    return false
                }
                await session.reload()
                return true
            }
        }
        return {
            let step = OriginalListEdits.adding(name, saved, toMappingAt: "sub-rules",
                                                exists: session.value(at: ["sub-rules"]) != nil)
            return await session.editOriginal(steps: [step])
        }
    }

     
     
     
    static func matches(_ raw: String, query: String, locale: Locale, ruleSetNames: [String: String] = [:]) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        let words = ConfigurationRuleWords.of(raw, locale: locale, ruleSetNames: ruleSetNames)
        return [raw, words.match, words.kind, words.target ?? ""].contains { $0.localizedCaseInsensitiveContains(query) }
    }

     
     
     
    static func ruleSetNames(_ library: ConfigurationLibrarySnapshot?) -> [String: String] {
        var names: [String: String] = [:]
        for set in library?.localRuleSets ?? [] { names["local-" + set.id] = set.name }
        for entry in ConfigurationRuleCatalog.builtIn.entries { names["catalog-" + entry.id] = entry.displayName }
        return names
    }

     
    static let deleteKey = "Delete Sub-rule"
    static let leadingInKey = "Rules still lead into this sub-rule. Change them first."

     
    static let searchFrom = 10
}

 

struct ConfigurationSubRuleDetailPage: View {
    enum Owner {
        case composed(ConfigurationSchemeDraftSession, id: UUID)
        case original(ConfigurationEditorSession, name: String)
    }

    let owner: Owner
    let configurationName: String

    init(owner: Owner, configurationName: String) {
        self.owner = owner
        self.configurationName = configurationName
    }

    var body: some View {
        switch owner {
        case .composed(let session, let id):
            ComposedSubRuleDetail(session: session, id: id)
        case .original(let session, let name):
            OriginalSubRuleDetail(session: session, name: name, configurationName: configurationName)
        }
    }
}

 
private struct SubRuleRuleRoute: Identifiable {
    let id = UUID()
    let index: Int?
    let rowID: UUID?
    let raw: String
    let asText: Bool
}

 
 
private struct ComposedSubRuleDetail: View {
    @ObservedObject var session: ConfigurationSchemeDraftSession
    let id: UUID
    @Environment(\.locale) private var locale
    @Environment(\.clashFeedback) private var feedback
    @StateObject private var dismiss = ClashDismissHandle()
    @State private var name = ""
    @FocusState private var naming: Bool
    @State private var editMode: EditMode = .inactive
    @State private var search = ""
    @State private var open: SubRuleRuleRoute?
     
     
     
    @State private var deleting: ConfigurationRuleDraft.SubRule?

    private var subRule: ConfigurationRuleDraft.SubRule? { session.draft?.subRules.first { $0.id == id } ?? deleting }
    private var rows: [ConfigurationRuleDraft.Row] { subRule?.rows ?? [] }
    private var shown: [ConfigurationRuleDraft.Row] {
        rows.filter { ConfigurationSubRuleDetail.matches($0.raw, query: search, locale: locale, ruleSetNames: ruleSetNames) }
    }
    private var leading: [String] { session.draft.map { ConfigurationSubRuleDetail.leadingIn(id, in: $0) } ?? [] }
    private var ruleSetNames: [String: String] { ConfigurationSubRuleDetail.ruleSetNames(session.library) }
    private var editable: Bool { session.draft?.subRulesEditable == true }

    var body: some View {
        Form {
            Section {
                TextField(text: $name) { Text(clash: .copy("Name")) }
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .focused($naming)
                    .onSubmit(rename)
                    .disabled(!editable)
                    .accessibilityIdentifier("configuration.sub-rule-detail.name")
            } header: { Text(clash: .copy("Name")) }
            Section {
                if rows.isEmpty {
                    Text(clash: ConfigurationEmptyList.sentence(for: "rules")).foregroundStyle(.secondary)
                }
                ForEach(shown) { row in
                    Button {
                        guard !editMode.isEditing else { return }
                        open = SubRuleRuleRoute(index: nil, rowID: row.id, raw: row.raw, asText: false)
                    } label: { ConfigurationRuleRow(row.raw, ruleSetNames: ruleSetNames) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("configuration.sub-rule-detail.rule")
                }
                .onDelete { offsets in
                    let ids = Set(offsets.map { shown[$0].id })
                    Task { await ConfigurationSubRuleDetail.deleteRules(ids, in: id, session: session) }
                }
                .onMove(perform: search.isEmpty ? { offsets, destination in
                    Task { await ConfigurationSubRuleDetail.moveRules(offsets, to: destination, in: id, session: session) }
                } : nil)
                if editable && !editMode.isEditing {
                    Button { open = SubRuleRuleRoute(index: nil, rowID: nil, raw: "", asText: false) } label: {
                        Label { Text(clash: .copy("Add Rule")) } icon: { Image(systemName: ClashSymbol.plus.name) }
                    }
                    .accessibilityIdentifier("configuration.sub-rule-detail.add-rule")
                }
            } header: {
                Text(clash: .copy("Rules"))
            } footer: {
                VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                     
                    if let failure = session.failure {
                        Text(verbatim: failure).foregroundStyle(.red)
                            .accessibilityIdentifier("configuration.sub-rule-detail.failure")
                    }
                    if let note = session.note(locale: locale) {
                        Text(verbatim: note).accessibilityIdentifier("configuration.sub-rule-detail.note")
                    }
                }
            }
            if editable {
                Section {
                    Button(role: .destructive, action: delete) { Text(clash: .copy(ConfigurationSubRuleDetail.deleteKey)) }
                        .disabled(!leading.isEmpty || session.isSaving)
                        .accessibilityIdentifier("configuration.sub-rule-detail.delete")
                } footer: {
                    if !leading.isEmpty {
                        VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                            Text(clash: .copy(ConfigurationSubRuleDetail.leadingInKey))
                            ForEach(Array(leading.enumerated()), id: \.offset) { _, rule in ConfigurationRuleRow(rule, ruleSetNames: ruleSetNames) }
                        }
                        .accessibilityIdentifier("configuration.sub-rule-detail.leading-in")
                    }
                }
            }
        }
        .clashPageTitle(.verbatim(subRule?.name ?? name), watchAs: "sub-rule-detail")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if editable && !rows.isEmpty {
                    Button {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    } label: { Text(clash: .copy(editMode.isEditing ? "Done" : "Edit")) }
                    .accessibilityIdentifier("configuration.sub-rule-detail.edit")
                }
            }
        }
        .environment(\.editMode, $editMode)
        .modifier(SubRuleSearch(search: $search, shows: rows.count >= ConfigurationSubRuleDetail.searchFrom))
        .onAppear { name = subRule?.name ?? name }
        .onChange(of: naming) { focused in if !focused { rename() } }
         
         
        .onDisappear(perform: commitName)
        .onChange(of: subRule?.name) { renamed in if !naming, let renamed { name = renamed } }
        .clashCapturesDismiss(dismiss)
         
        .clashOnScreen { session.pageOnScreen($0) }
        .clashProductModal(item: $open, role: .form) { route in
            RuleBuilderAdapter(raw: route.raw, options: session.draft.map(ConfigurationGroupEditorBridge.ruleOptions) ?? .empty,
                               showsPersonalMetadata: false, showsTarget: true) { raw in
                Task { await ConfigurationSubRuleDetail.setRule(raw, rowID: route.rowID, in: id, session: session) }
            }
            .clashModalPresentation(.page)
        }
    }

     
     
     
    private func rename() {
        Task {
            if await !ConfigurationSubRuleDetail.rename(id, to: name, in: session) { name = subRule?.name ?? name }
        }
    }

     
    private func commitName() {
        guard name != subRule?.name else { return }
        rename()
    }

     
    private func delete() {
        guard let held = subRule else { return }
        let deleted = held.name
        deleting = held
        Task {
            guard let undo = await ConfigurationSubRuleDetail.delete(id, in: session) else {
                deleting = nil
                return
            }
            dismiss()
            ConfigurationLibraryUndo.offer(feedback, title: ClashFeedbackCopy.deleted(deleted),
                                           restored: ClashFeedbackCopy.restored(deleted),
                                           operation: "configuration.sub-rule.delete", identifier: "feedback.sub-rule.delete",
                                           model: session.model) {
                guard await undo() else { throw ConfigurationLibraryError.staleGeneration }
            }
        }
    }
}

 
 
 
private struct OriginalSubRuleDetail: View {
    @ObservedObject var session: ConfigurationEditorSession
    let name: String
    let configurationName: String
    @Environment(\.locale) private var locale
    @Environment(\.clashFeedback) private var feedback
    @StateObject private var dismiss = ClashDismissHandle()
    @State private var editMode: EditMode = .inactive
    @State private var search = ""
    @State private var open: SubRuleRuleRoute?

    private var rules: [String] { ConfigurationSubRuleDetail.rules(of: name, in: session) ?? [] }
    private var shown: [(index: Int, rule: String)] {
        rules.enumerated().map { (index: $0.offset, rule: $0.element) }
            .filter { ConfigurationSubRuleDetail.matches($0.rule, query: search, locale: locale) }
    }
    private var leading: [String] { ConfigurationSubRuleDetail.leadingIn(name, in: session) }
     
    private var note: String? {
        guard let page = session.page else { return nil }
        return ConfigurationSchemeChangeNote.original(name: configurationName, followsLink: page.followsSubscription, locale: locale)
    }

    var body: some View {
        Form {
            Section {
                Text(verbatim: name).accessibilityIdentifier("configuration.sub-rule-detail.name")
            } header: { Text(clash: .copy("Name")) }
            Section {
                if rules.isEmpty {
                    Text(clash: ConfigurationEmptyList.sentence(for: "rules")).foregroundStyle(.secondary)
                }
                ForEach(shown, id: \.index) { item in
                    Button {
                        guard !editMode.isEditing else { return }
                        open = SubRuleRuleRoute(index: item.index, rowID: nil, raw: item.rule,
                                                asText: OriginalListEdits.isWrittenAsText(item.rule, catalog: session.catalog))
                    } label: { ConfigurationRuleRow(item.rule) }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            open = SubRuleRuleRoute(index: item.index, rowID: nil, raw: item.rule, asText: true)
                        } label: { Text(clash: .copy("Edit as Text")) }
                    }
                    .accessibilityIdentifier("configuration.sub-rule-detail.rule")
                }
                .onDelete { offsets in
                    let indices = offsets.map { shown[$0].index }
                    Task { await ConfigurationSubRuleDetail.deleteRules(indices, of: name, session: session) }
                }
                .onMove(perform: search.isEmpty ? { offsets, destination in
                    Task { await ConfigurationSubRuleDetail.moveRules(offsets, to: destination, of: name, session: session) }
                } : nil)
                if !editMode.isEditing {
                    Button { open = SubRuleRuleRoute(index: nil, rowID: nil, raw: "", asText: false) } label: {
                        Label { Text(clash: .copy("Add Rule")) } icon: { Image(systemName: ClashSymbol.plus.name) }
                    }
                    .accessibilityIdentifier("configuration.sub-rule-detail.add-rule")
                }
            } header: {
                Text(clash: .copy("Rules"))
            } footer: {
                if let note { Text(verbatim: note).accessibilityIdentifier("configuration.sub-rule-detail.note") }
            }
            Section {
                Button(role: .destructive, action: delete) { Text(clash: .copy(ConfigurationSubRuleDetail.deleteKey)) }
                    .disabled(!leading.isEmpty || session.isSaving)
                    .accessibilityIdentifier("configuration.sub-rule-detail.delete")
            } footer: {
                if !leading.isEmpty {
                    VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                        Text(clash: .copy(ConfigurationSubRuleDetail.leadingInKey))
                        ForEach(Array(leading.enumerated()), id: \.offset) { _, rule in ConfigurationRuleRow(rule) }
                    }
                    .accessibilityIdentifier("configuration.sub-rule-detail.leading-in")
                }
            }
        }
        .clashPageTitle(.verbatim(name), watchAs: "sub-rule-detail")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !rules.isEmpty {
                    Button {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    } label: { Text(clash: .copy(editMode.isEditing ? "Done" : "Edit")) }
                    .accessibilityIdentifier("configuration.sub-rule-detail.edit")
                }
            }
        }
        .environment(\.editMode, $editMode)
        .modifier(SubRuleSearch(search: $search, shows: rules.count >= ConfigurationSubRuleDetail.searchFrom))
        .disabled(session.isSaving)
        .configurationPushedAlertHost(session)
        .clashCapturesDismiss(dismiss)
        .clashProductModal(item: $open, role: .form) { route in
            Group {
                if route.asText {
                     
                    ConfigurationRawRuleEditor(raw: route.raw) { raw in
                        Task { await ConfigurationSubRuleDetail.setRule(raw, at: route.index, of: name, session: session) }
                    }
                } else {
                    RuleBuilderAdapter(raw: route.raw, options: RulePolicyOptions.make(document: session.page?.document),
                                       showsPersonalMetadata: false, showsTarget: true) { raw in
                        Task { await ConfigurationSubRuleDetail.setRule(raw, at: route.index, of: name, session: session) }
                    }
                }
            }
            .clashModalPresentation(.page)
        }
    }

     
     
    private func delete() {
        Task {
            guard let undo = await ConfigurationSubRuleDetail.delete(name, in: session) else { return }
            dismiss()
            ConfigurationLibraryUndo.offer(feedback, title: ClashFeedbackCopy.deleted(name),
                                           restored: ClashFeedbackCopy.restored(name),
                                           operation: "configuration.sub-rule.delete", identifier: "feedback.sub-rule.delete",
                                           model: session.model) {
                guard await undo() else { throw ConfigurationLibraryError.staleGeneration }
            }
        }
    }
}

 
private struct SubRuleSearch: ViewModifier {
    @Binding var search: String
    let shows: Bool

    func body(content: Content) -> some View {
        if shows {
            content.clashProductModalSearchable(text: $search, prompt: Text(clash: .copy("Search rules")))
        } else {
            content
        }
    }
}
#endif
