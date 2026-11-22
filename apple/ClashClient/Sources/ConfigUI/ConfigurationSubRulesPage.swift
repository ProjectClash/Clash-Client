#if os(iOS)
import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
 

 
struct ConfigurationSubRulesSnapshot: Equatable {
    struct Row: Equatable, Identifiable {
         
        let id: String
        let name: String
         
        let detail: String
    }

    let rows: [Row]
     
     
    let editable: Bool
     
    let notice: String?
     
    let canReorder: Bool

    static let readOnlyKey = "These sub-rules can only be changed in the source."

    static func composed(_ draft: ConfigurationRuleDraft, locale: Locale) -> Self {
        let rows = draft.subRules.map { Row(id: $0.id.uuidString, name: $0.name, detail: count($0.rows.count, locale: locale)) }
        let editable = draft.subRulesEditable
        return Self(rows: rows, editable: editable, notice: editable ? nil : ClashCopy.string(readOnlyKey, locale: locale),
                    canReorder: editable && rows.count > 1)
    }

     
    static func original(_ subRules: OrderedJSON?, locale: Locale) -> Self {
        var rows: [Row] = []
        if case .object(let pairs)? = subRules {
            for pair in pairs {
                var count = 0
                if case .array(let rules) = pair.value { count = rules.count }
                rows.append(Row(id: pair.key, name: pair.key, detail: Self.count(count, locale: locale)))
            }
        }
        return Self(rows: rows, editable: true, notice: nil, canReorder: false)
    }

    private static func count(_ value: Int, locale: Locale) -> String {
        ClashCopy.format(value == 1 ? "%@ rule" : "%@ rules", locale: locale, ClashCopy.count(value, locale: locale))
    }
}

 
struct ConfigurationSubRulesPage: View {
    let model: ProfilesViewModel
    let profileID: String
    @ObservedObject var editor: ConfigurationEditorSession
    let form: ProfilesViewModel.ConfigurationEditorPage.Form
     
     
     
     
    let libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)?

    init(model: ProfilesViewModel, profileID: String, editor: ConfigurationEditorSession,
         form: ProfilesViewModel.ConfigurationEditorPage.Form, libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)? = nil) {
        self.model = model; self.profileID = profileID; self.editor = editor; self.form = form
        self.libraryChanged = libraryChanged
    }

     
     
    static let titleKey = "Sub-rules of “%@”"
    static let newNameKey = "New Sub-rule"
    static let addKey = "Add Sub-rule"

     
     
     
    static func prefilledName(taken: Set<String>, locale: Locale) -> String {
        ClashTowerRuleCustomizationView.nextFreeName(ClashCopy.string(newNameKey, locale: locale), taken: taken)
    }

     
    static func title(_ configurationName: String, locale: Locale) -> String {
        ClashCopy.format(titleKey, locale: locale, configurationName)
    }

     
     
     
     
    static func add(_ name: String, in session: ConfigurationSchemeDraftSession) async -> UUID? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard await session.change({ _ = try $0.addSubRule(named: name) }),
              await ConfigurationSubRuleDetail.landed(session, { $0.subRules.contains { $0.name == name } }) else { return nil }
        return session.draft?.subRules.first { $0.name == name }?.id
    }

     
     
     
     
     
    static func takeFailure(from session: ConfigurationEditorSession) -> String? {
        if let failure = session.failure {
            session.failure = nil
            return failure
        }
        guard let refusal = session.refusal else { return nil }
        if !refusal.editTheSourceInstead { session.refusal = nil }
        return refusal.sentence
    }

     
    static func add(_ name: String, in session: ConfigurationEditorSession) async -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let step = OriginalListEdits.adding(name, .array([]), toMappingAt: "sub-rules",
                                            exists: session.value(at: ["sub-rules"]) != nil)
        return await session.editOriginal(steps: [step])
    }

    private var configurationName: String {
        editor.page?.label ?? model.profiles.first { $0.id == profileID }?.label ?? ""
    }

    var body: some View {
        switch form {
        case .composed:
            ComposedSubRules(model: model, profileID: profileID, configurationName: configurationName,
                             libraryChanged: libraryChanged)
        case .original:
            OriginalSubRules(session: editor, configurationName: configurationName)
        }
    }
}

 
 
private struct ComposedSubRules: View {
    let configurationName: String
    let libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)?
    @StateObject private var session: ConfigurationSchemeDraftSession
    @Environment(\.locale) private var locale
    @Environment(\.clashFeedback) private var feedback
    @State private var editMode: EditMode = .inactive
    @State private var search = ""
    @State private var naming = false
     
    @State private var opened: UUID?

    init(model: ProfilesViewModel, profileID: String, configurationName: String,
         libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)?) {
        self.configurationName = configurationName
        self.libraryChanged = libraryChanged
        _session = StateObject(wrappedValue: ConfigurationSchemeDraftSession(model: model, profileID: profileID))
    }

    private var snapshot: ConfigurationSubRulesSnapshot? {
        session.draft.map { ConfigurationSubRulesSnapshot.composed($0, locale: locale) }
    }

    private func shown(_ rows: [ConfigurationSubRulesSnapshot.Row]) -> [ConfigurationSubRulesSnapshot.Row] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return query.isEmpty ? rows : rows.filter { $0.name.lowercased().contains(query) }
    }

    var body: some View {
        let snapshot = self.snapshot
        Form {
            if let snapshot {
                Section {
                    if snapshot.rows.isEmpty {
                        Text(clash: ConfigurationEmptyList.sentence(for: "sub-rules")).foregroundStyle(.secondary)
                    }
                    ForEach(shown(snapshot.rows)) { row in
                        if snapshot.editable, let id = UUID(uuidString: row.id) {
                            ClashNativeNavigationLink {
                                ConfigurationSubRuleDetailPage(owner: .composed(session, id: id), configurationName: configurationName)
                            } label: { SubRuleRow(row: row) }
                            .accessibilityIdentifier("configuration.sub-rules.row")
                        } else {
                            SubRuleRow(row: row).accessibilityIdentifier("configuration.sub-rules.row")
                        }
                    }
                    .onMove(perform: snapshot.canReorder && search.isEmpty ? { offsets, destination in
                        Task { await session.change { $0.moveSubRules(fromOffsets: offsets, toOffset: destination) } }
                    } : nil)
                    .deleteDisabled(true)
                    if snapshot.editable && !editMode.isEditing {
                        Button { naming = true } label: {
                            Label { Text(clash: .copy(ConfigurationSubRulesPage.addKey)) } icon: { Image(systemName: ClashSymbol.plus.name) }
                        }
                        .accessibilityIdentifier("configuration.sub-rules.add")
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                        if let notice = snapshot.notice {
                            Text(verbatim: notice).accessibilityIdentifier("configuration.sub-rules.read-only")
                        }
                        if let failure = session.failure {
                            Text(verbatim: failure).foregroundStyle(.red).accessibilityIdentifier("configuration.sub-rules.failure")
                        }
                        if let note = session.note(locale: locale) {
                            Text(verbatim: note).accessibilityIdentifier("configuration.sub-rules.note")
                        }
                    }
                }
            } else if let failure = session.failure {
                Section { Text(verbatim: failure).foregroundStyle(.orange) }
            }
        }
        .clashPageTitle(.verbatim(ConfigurationSubRulesPage.title(configurationName, locale: locale)), watchAs: "sub-rules")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if snapshot?.canReorder == true {
                    Button {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    } label: { Text(clash: .copy(editMode.isEditing ? "Done" : "Edit")) }
                    .accessibilityIdentifier("configuration.sub-rules.edit")
                }
            }
        }
        .environment(\.editMode, $editMode)
        .modifier(SubRulesSearch(search: $search, shows: (snapshot?.rows.count ?? 0) >= ConfigurationSubRuleDetail.searchFrom))
        .task {
            session.locale = locale
            session.libraryChanged = libraryChanged
            session.feedback = feedback
            await session.load()
        }
         
         
        .clashOnScreen { session.pageOnScreen($0) }
        .clashProductModal(isPresented: $naming, role: .form) {
            ConfigurationSubRuleNameSheet(
                taken: Set(session.draft?.subRules.map(\.name) ?? []),
                prefilled: ConfigurationSubRulesPage.prefilledName(taken: Set(session.draft?.subRules.map(\.name) ?? []),
                                                                   locale: locale),
                failure: { session.failure }) { name in
                guard let id = await ConfigurationSubRulesPage.add(name, in: session) else { return false }
                opened = id
                return true
            }
        }
         
        .background(ClashRoutedViewDestination(isPresented: Binding(get: { opened != nil }, set: { if !$0 { opened = nil } })) {
            if let opened {
                ConfigurationSubRuleDetailPage(owner: .composed(session, id: opened), configurationName: configurationName)
            }
        })
    }
}

 
 
private struct OriginalSubRules: View {
    @ObservedObject var session: ConfigurationEditorSession
    let configurationName: String
    @Environment(\.locale) private var locale
    @State private var search = ""
    @State private var naming = false
     
    @State private var opened: String?

    private var snapshot: ConfigurationSubRulesSnapshot {
        ConfigurationSubRulesSnapshot.original(session.value(at: ["sub-rules"]), locale: locale)
    }

    private var note: String? {
        guard let page = session.page else { return nil }
        return ConfigurationSchemeChangeNote.original(name: configurationName, followsLink: page.followsSubscription, locale: locale)
    }

    var body: some View {
        let snapshot = self.snapshot
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        let shown = query.isEmpty ? snapshot.rows : snapshot.rows.filter { $0.name.lowercased().contains(query) }
        Form {
            Section {
                if snapshot.rows.isEmpty {
                    Text(clash: ConfigurationEmptyList.sentence(for: "sub-rules")).foregroundStyle(.secondary)
                }
                ForEach(shown) { row in
                    ClashNativeNavigationLink {
                        ConfigurationSubRuleDetailPage(owner: .original(session, name: row.name), configurationName: configurationName)
                    } label: { SubRuleRow(row: row) }
                    .accessibilityIdentifier("configuration.sub-rules.row")
                }
                Button { naming = true } label: {
                    Label { Text(clash: .copy(ConfigurationSubRulesPage.addKey)) } icon: { Image(systemName: ClashSymbol.plus.name) }
                }
                .accessibilityIdentifier("configuration.sub-rules.add")
            } footer: {
                if let note { Text(verbatim: note).accessibilityIdentifier("configuration.sub-rules.note") }
            }
        }
        .clashPageTitle(.verbatim(ConfigurationSubRulesPage.title(configurationName, locale: locale)), watchAs: "sub-rules")
        .modifier(SubRulesSearch(search: $search, shows: snapshot.rows.count >= ConfigurationSubRuleDetail.searchFrom))
        .disabled(session.isSaving)
        .configurationPushedAlertHost(session)
        .clashProductModal(isPresented: $naming, role: .form) {
            ConfigurationSubRuleNameSheet(
                taken: Set(snapshot.rows.map(\.name)),
                prefilled: ConfigurationSubRulesPage.prefilledName(taken: Set(snapshot.rows.map(\.name)), locale: locale),
                failure: { ConfigurationSubRulesPage.takeFailure(from: session) }) { name in
                guard await ConfigurationSubRulesPage.add(name, in: session) else { return false }
                opened = name.trimmingCharacters(in: .whitespacesAndNewlines)
                return true
            }
        }
         
        .background(ClashRoutedViewDestination(isPresented: Binding(get: { opened != nil }, set: { if !$0 { opened = nil } })) {
            if let opened {
                ConfigurationSubRuleDetailPage(owner: .original(session, name: opened), configurationName: configurationName)
            }
        })
    }
}

 
private struct SubRuleRow: View {
    let row: ConfigurationSubRulesSnapshot.Row

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ClashTheme.Spacing.row) {
            Text(verbatim: row.name).foregroundStyle(.primary)
            Spacer(minLength: ClashTheme.Spacing.row)
            Text(verbatim: row.detail).foregroundStyle(.secondary)
        }
    }
}

 
private struct SubRulesSearch: ViewModifier {
    @Binding var search: String
    let shows: Bool

    func body(content: Content) -> some View {
        if shows {
            content.clashProductModalSearchable(text: $search)
        } else {
            content
        }
    }
}

 
 
 
 
struct ConfigurationSubRuleNameSheet: View {
    let taken: Set<String>
     
     
    let failure: () -> String?
     
    let add: (String) async -> Bool
    @State private var name: String
    @State private var busy = false
    @State private var said: String?
    @StateObject private var dismiss = ClashDismissHandle()

    init(taken: Set<String>, prefilled: String, failure: @escaping () -> String? = { nil },
         add: @escaping (String) async -> Bool) {
        self.taken = taken
        self.failure = failure
        self.add = add
        _name = State(initialValue: prefilled)
    }

    static let commaKey = "A sub-rule name can't contain a comma."

     
    static func verdict(_ name: String, taken: Set<String>) -> (canAdd: Bool, problem: String?) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains(",") { return (false, commaKey) }
        return (!trimmed.isEmpty && !taken.contains(trimmed), nil)
    }

    var body: some View {
        let verdict = Self.verdict(name, taken: taken)
        ClashFeatureNavigationContainer {
            Form {
                Section {
                    TextField(text: $name) { Text(clash: .copy("Name")) }
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .accessibilityIdentifier("configuration.sub-rules.new.name")
                } footer: {
                    if let problem = verdict.problem {
                        Text(clash: .copy(problem)).foregroundStyle(.red)
                            .accessibilityIdentifier("configuration.sub-rules.new.problem")
                    } else if let said {
                        Text(verbatim: said).foregroundStyle(.red)
                            .accessibilityIdentifier("configuration.sub-rules.new.failure")
                    }
                }
            }
            .navigationTitle(Text(clash: .copy(ConfigurationSubRulesPage.addKey)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(clash: .copy("Cancel")) }
                        .accessibilityIdentifier("configuration.sub-rules.new.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        busy = true
                        Task {
                            said = nil
                            let added = await add(name)
                            busy = false
                            if added { dismiss() } else { said = failure() }
                        }
                    } label: { Text(clash: .copy("Add")) }
                    .disabled(!verdict.canAdd || busy)
                    .accessibilityIdentifier("configuration.sub-rules.new.add")
                }
            }
        }
        .clashCapturesDismiss(dismiss)
    }
}
#endif
