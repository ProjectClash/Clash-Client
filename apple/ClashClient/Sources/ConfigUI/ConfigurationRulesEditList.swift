import ClashClientKit
import Combine
import ClashClientUI
import SwiftUI

 
 
 
 
 
 
 
 
 

 

 
 
 
 
enum ConfigurationRulesEditOutcome: Equatable {
     
     
     
    case becomesOwn(ConfigurationRuleScheme)
     
     
    case changesInPlace(configurationIDs: [String])

    static func of(profileID: String, in library: ConfigurationLibrarySnapshot) -> Self? {
        guard let recipe = library.recipes.first(where: { $0.id == profileID }), recipe.preservesOriginal != true,
              let scheme = library.rules.first(where: { $0.id == recipe.ruleSchemeID })
                ?? ConfigurationBuiltins.schemes.first(where: { $0.id == recipe.ruleSchemeID }) else { return nil }
        let composed = library.recipes.filter { $0.preservesOriginal != true }
        let kept = scheme.isRetainedSnapshot == true
         
         
        if !kept, scheme.collectionKey == nil, scheme.rulesFromSchemeID == nil,
           scheme.kind == .custom || scheme.kind == .imported {
            let followers = Set(library.rules.filter { $0.rulesFromSchemeID == scheme.id }.map(\.id))
            return .changesInPlace(configurationIDs: composed.filter {
                $0.ruleSchemeID == scheme.id || followers.contains($0.ruleSchemeID)
            }.map(\.id))
        }
         
         
         
        let turnsView = scheme.rulesFromSchemeID != nil
        var after = ConfigurationRuleScheme(id: turnsView ? scheme.id : "", label: scheme.label, kind: .custom, sourceID: "")
        after.ownViewOfCustomScheme = turnsView ? scheme.ownViewOfCustomScheme : nil
        if !turnsView { after.baseSchemeID = scheme.id }
        after.rulesCustomizedFromSchemeID = turnsView ? scheme.rulesFromSchemeID : scheme.id
        if let owner = kept ? profileID : turnsView ? scheme.privateToConfigurationID : nil {
            after.privateToConfigurationID = owner
        }
        guard turnsView else { return .becomesOwn(after) }
         
         
        let users = composed.filter { $0.ruleSchemeID == scheme.id }.map(\.id)
        if scheme.privateToConfigurationID == nil { return .changesInPlace(configurationIDs: users) }
        return .becomesOwn(after)
    }
}

 
 
struct ConfigurationRulesEditSnapshot: Equatable {
     
    enum Action: String, Equatable {
        case saveAsScheme, editAsText, restoreInitialRules, showGroupIcons
    }

     
     
    let note: String?
    let actions: [Action]

     
     
     
    static let finalRowKey = "All Other Traffic → %@"

     
     
     
     
     
     
    static func composed(profileID: String, library: ConfigurationLibrarySnapshot,
                         profiles: [LibraryUsage.Configuration], locale: Locale) -> Self {
        let note = ConfigurationSchemeChangeNote.make(profileID: profileID, library: library, profiles: profiles, locale: locale)
        var actions: [Action] = [.saveAsScheme, .editAsText]
        if let scheme = running(profileID, in: library), isChangedBuiltin(scheme) { actions.append(.restoreInitialRules) }
        actions.append(.showGroupIcons)
        return Self(note: note, actions: actions)
    }

     
     
     
     
    static func original(name: String, followsLink: Bool, opensText: Bool, locale: Locale) -> Self {
        Self(note: ConfigurationSchemeChangeNote.original(name: name, followsLink: followsLink, locale: locale),
             actions: opensText ? [.saveAsScheme, .editAsText] : [.saveAsScheme])
    }

     
    static func finalRow(_ raw: String, locale: Locale) -> String {
        ClashCopy.format(finalRowKey, locale: locale, ClashStructuredRule.parse(raw)?.target ?? "")
    }

     
    static func running(_ profileID: String, in library: ConfigurationLibrarySnapshot) -> ConfigurationRuleScheme? {
        guard let recipe = library.recipes.first(where: { $0.id == profileID }), recipe.preservesOriginal != true else { return nil }
        return library.rules.first { $0.id == recipe.ruleSchemeID }
            ?? ConfigurationBuiltins.schemes.first { $0.id == recipe.ruleSchemeID }
    }

     
     
     
    static func isChangedBuiltin(_ scheme: ConfigurationRuleScheme) -> Bool {
        scheme.baseSchemeID.map(ConfigurationBuiltins.isNative) == true
            || (scheme.ownViewBaseID.map(ConfigurationBuiltins.isNative) == true && scheme.plainViewBaseID == nil)
    }

     
     
    static func name(of scheme: ConfigurationRuleScheme, locale: Locale) -> String {
        scheme.ownViewBaseID == nil ? ClashTowerRulesLibraryView.displayLabel(scheme, locale: locale) : scheme.displayLabel
    }

     
     
     
     
     
     
    static func savesAgain(on now: ConfigurationLibrarySnapshot, known: ConfigurationLibrarySnapshot,
                           profileID: String, schemeID: String) -> Bool {
        now.generation != known.generation
            && running(profileID, in: now)?.id == schemeID
            && sameRules(known, now, schemeID: schemeID)
    }

     
     
     
    static func sameRules(_ a: ConfigurationLibrarySnapshot, _ b: ConfigurationLibrarySnapshot, schemeID: String) -> Bool {
        let schemeA = a.rules.first { $0.id == schemeID }
        guard schemeA == b.rules.first(where: { $0.id == schemeID }) else { return false }
        guard let sourceID = schemeA?.sourceID else { return true }
        return a.sources.first { $0.id == sourceID } == b.sources.first { $0.id == sourceID }
    }
}

 
 
 
#if os(iOS)

 

 
 
 
 
 
 
 
 
 
 
@MainActor
final class ConfigurationRulesEditModel: ObservableObject {
    let model: ProfilesViewModel
    let profileID: String
     
    let schemeSession: ConfigurationSchemeDraftSession
    @Published private(set) var loadFailure: String?
     
    var report: (String) -> Void {
        get { schemeSession.report }
        set { schemeSession.report = newValue }
    }
     
     
    private let knownOriginal: Bool?
    private var relay: AnyCancellable?
     
    let targetNodes = RuleTargetNodeSource()

     
     
     
     
     
    init(model: ProfilesViewModel, profileID: String, running: ConfigurationRulesPageSnapshot.Running? = nil,
         prepared: ConfigurationSchemeRulesPushed.Prepared?,
         changed: @escaping (ConfigurationLibrarySnapshot) -> Void) {
        self.model = model
        self.profileID = profileID
        knownOriginal = running.map { $0 == .original }
        schemeSession = ConfigurationSchemeDraftSession(model: model, profileID: profileID,
                                                        library: prepared?.library, editor: prepared?.editor.editor)
        schemeSession.libraryChanged = changed
         
        relay = schemeSession.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

     
    var library: ConfigurationLibrarySnapshot? { schemeSession.library }
     
     
    var draft: ConfigurationRuleDraft? { schemeSession.draft }
     
    var resetDocument: String? { schemeSession.resetDocument }
    var saving: Bool { schemeSession.isSaving }

     
     
    var isOriginal: Bool? {
        library.map { library in library.recipes.first { $0.id == profileID }?.preservesOriginal == true } ?? knownOriginal
    }

     
     
    func load() async {
        guard draft == nil else { return }
        guard model.configurationLibraryStore != nil else {
            loadFailure = Self.message(ConfigurationLibraryError.unreadable)
            return
        }
        await schemeSession.load()
        guard draft == nil, let failure = schemeSession.failure else { return }
        schemeSession.dismissFailure()
         
         
         
        if library != nil, isOriginal == true { return }
        loadFailure = failure
    }

     
     
    func change(_ transform: @escaping (inout ConfigurationRuleDraft) throws -> Void) {
        schemeSession.apply(transform) { report(Self.message($0)) }
    }

     
     
     
     
    func moveRow(_ id: UUID, before anchor: UUID?) {
        change { draft in
            guard let from = draft.rows.firstIndex(where: { $0.id == id }) else { return }
            let to = anchor.flatMap { anchor in draft.rows.firstIndex { $0.id == anchor } }
                ?? draft.rows.firstIndex(where: \.isFinal) ?? draft.rows.count
            draft.moveRows(fromOffsets: IndexSet(integer: from), toOffset: to)
        }
    }

     
     
     
     
     
     
    func addToScheme(_ raw: String, enabled: Bool, note: String) {
        let rule = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rule.isEmpty else { return }
        change { draft in
            draft.insertRuleFirst(rule)
            if let first = draft.rows.first { draft.setRule(rule, enabled: enabled, note: note, rowID: first.id) }
        }
    }

     
     
     
    var schemeOptions: RulePolicyOptions {
        guard let draft else { return .empty }
        let document = draft.currentDocument()
        let groups = Set(draft.groups.map(\.name))
        var seen = Set<String>()
        var nodes: [(name: String, type: String)] = []
        if case .array(let entries)? = document.topLevelValue("proxies") {
            for entry in entries {
                guard case .string(let name)? = entry.topLevelValue("name"), !name.isEmpty, seen.insert(name).inserted else { continue }
                var type = ""
                if case .string(let value)? = entry.topLevelValue("type") { type = value }
                nodes.append((name, type))
            }
        }
        let builtins = RulePolicyOptions.builtinPolicies
        for name in ConfigurationTowerRuleCustomizationAdapter.referencedNames(in: document)
        where !groups.contains(name) && !builtins.contains(name) && seen.insert(name).inserted {
            nodes.append((name, ""))
        }
        var subRules: [String]?
        if case .object(let fields)? = document.topLevelValue("sub-rules") { subRules = fields.map(\.key).sorted() }
        return RulePolicyOptions(groups: draft.groups.map { ($0.name, $0.type) }, proxies: nodes,
                                 ruleSets: draft.ruleSetNames,
                                 hiddenGroups: Set(draft.groups.filter(\.isHidden).map(\.name)),
                                 subRuleNames: subRules, ruleSetsAreKnown: true)
    }

     
     
    func targetSearchHook(locale: Locale) -> ClashRuleTargetSearchHook {
        let nodes = targetNodes
        let profileID = profileID
        let search = ConfigurationRuleTargetSearch(configurationID: profileID, defaults: DelayTestSettings.appGroupDefaults,
                                                   locale: locale) { await nodes.source(profileID: profileID) }
        return ClashRuleTargetSearchHook(sections: { query, current in await search.sections(query: query, current: current) },
                                         recordUse: { search.recordUse($0) })
    }

     
    func waitForSaves() async {
        await schemeSession.waitForSaves()
    }

     
     
     
    func copy(named name: String) async {
        guard let value = draft, let generation = library?.generation else { return }
        do {
            let library = try await model.copyConfigurationRuleScheme(draft: value, label: name, generation: generation)
            schemeSession.take(library)
        } catch {
            report(Self.message(error))
        }
    }

     
     
    func changeCustomRules(_ change: (inout ProfileRulesDraft) -> Void) {
        do {
            try model.updateCustomRules(profileID: profileID, change)
        } catch {
            report(Self.message(error))
        }
    }

    static func message(_ error: Error) -> String {
        ConfigurationSchemeDraftSession.message(error)
    }
}

 
 
 
 
 
 
 
 
 
 
@MainActor
enum ConfigurationRulesOriginalEdits {
    static let rulesPath: [ConfigurationTextPathStep] = [.key("rules")]

     
     
    struct Row: Equatable {
        let raw: String
        let occurrence: Int
        let total: Int
    }

     
    static func rows(at indices: [Int], in rules: [String]) -> [Row] {
        indices.filter { rules.indices.contains($0) }.map { index in
            let raw = rules[index]
            return Row(raw: raw, occurrence: rules[..<index].filter { $0 == raw }.count,
                       total: rules.filter { $0 == raw }.count)
        }
    }

     
    static func rules(in document: OrderedJSON?) -> [String]? {
        guard case .array(let items)? = document?.node(at: ["rules"]) else { return nil }
        return items.map { item in
            if case .string(let text) = item { return text }
            return item.serialized()
        }
    }

     
    static func index(of row: Row, in rules: [String]) -> Int? {
        var seen = 0
        for (index, rule) in rules.enumerated() where rule == row.raw {
            if seen == row.occurrence { return index }
            seen += 1
        }
        return nil
    }

     
    static func deleting(_ rows: [Row]) -> ConfigurationEditorSession.OriginalChange {
        { document in
            guard let rules = Self.rules(in: document) else { return .cannot }
            var found: [Int] = []
            for row in rows where rules.filter({ $0 == row.raw }).count >= row.total {
                if let at = index(of: row, in: rules) { found.append(at) }
            }
            return .write(found.isEmpty ? [] : OriginalListEdits.deleting(found, under: rulesPath))
        }
    }

     
     
     
    struct Drag: Equatable {
        let row: Row
        let anchor: Row?
        let previous: Row?
        let next: Row?
    }

     
     
     
    static func dragged(_ offsets: IndexSet, to destination: Int, in rules: [String], movable: Int) -> Drag? {
        guard offsets.count == 1, let from = offsets.first, from < movable,
              let row = Self.rows(at: [from], in: rules).first else { return nil }
        return Drag(row: row, anchor: destination < movable ? Self.rows(at: [destination], in: rules).first : nil,
                    previous: Self.rows(at: [from - 1], in: rules).first, next: Self.rows(at: [from + 1], in: rules).first)
    }

     
     
     
     
     
     
    static func moving(_ drag: Drag) -> ConfigurationEditorSession.OriginalChange {
        { document in
            guard let rules = Self.rules(in: document) else { return .cannot }
            let destination: Int
            if let anchor = drag.anchor {
                guard let at = index(of: anchor, in: rules) else { return .cannot }
                destination = at
            } else {
                destination = OriginalListEdits.insertionIndex(forNewRuleIn: rules)
            }
            if destination > 0, rules[destination - 1] == drag.row.raw, joined(drag, in: rules) { return .write([]) }
            guard let from = index(of: drag.row, in: rules) else { return .cannot }
            return .write(OriginalListEdits.moveSteps(IndexSet(integer: from), to: destination, under: rulesPath))
        }
    }

     
     
    private static func joined(_ drag: Drag, in rules: [String]) -> Bool {
        switch (drag.previous, drag.next) {
        case (nil, nil):
            return true
        case (nil, let next?):
            return index(of: next, in: rules) == 0
        case (let previous?, nil):
            return index(of: previous, in: rules).map { $0 + 1 == rules.count } ?? false
        case (let previous?, let next?):
            guard let before = index(of: previous, in: rules) else { return false }
            return index(of: next, in: rules) == before + 1
        }
    }

     
     
     
     
     
    static func setting(_ row: Row, to rule: String, ruleCount: Int) -> ConfigurationEditorSession.OriginalChange {
        { document in
            guard let rules = Self.rules(in: document) else { return .cannot }
            if rules.filter({ $0 == row.raw }).count < row.total, rules.filter({ $0 == rule }).count > ruleCount {
                return .write([])
            }
            guard let at = index(of: row, in: rules) else { return .cannot }
            return .write([OriginalListEdits.settingRule(rule, at: at, under: rulesPath)])
        }
    }

     
     
    static func addingFirst(_ rule: String, existing: Int) -> ConfigurationEditorSession.OriginalChange {
        { document in
            guard let rules = Self.rules(in: document) else {
                return .write([ConfigurationTextStep(path: rulesPath,
                                                     edit: .insert(json: OrderedJSON.array([.string(rule)]).serialized()))])
            }
            guard rules.filter({ $0 == rule }).count <= existing else { return .write([]) }
            return .write([ConfigurationTextStep(path: rulesPath + [.index(0)],
                                                 edit: .insert(json: OrderedJSON.string(rule).serialized()))])
        }
    }

    static func delete(_ rows: [Row], in session: ConfigurationEditorSession) async -> Bool {
        guard !rows.isEmpty else { return true }
        return await session.queueOriginal(deleting(rows))
    }

    static func move(_ drag: Drag, in session: ConfigurationEditorSession) async -> Bool {
        let landed = await session.queueOriginal(moving(drag))
        if !landed { sayIfGone([drag.row] + (drag.anchor.map { [$0] } ?? []), in: session) }
        return landed
    }

     
    static func move(_ row: Row, before anchor: Row?, in session: ConfigurationEditorSession) async -> Bool {
        let shown = rules(in: session.shownDocument) ?? []
        guard let from = index(of: row, in: shown) else { return false }
        return await move(Drag(row: row, anchor: anchor, previous: Self.rows(at: [from - 1], in: shown).first,
                               next: Self.rows(at: [from + 1], in: shown).first), in: session)
    }

    static func set(_ row: Row, to rule: String, in session: ConfigurationEditorSession) async -> Bool {
        let ruleCount = (rules(in: session.shownDocument) ?? []).filter { $0 == rule }.count
        let landed = await session.queueOriginal(setting(row, to: rule, ruleCount: ruleCount))
        if !landed { sayIfGone([row], in: session) }
        return landed
    }

     
     
     
    private static func sayIfGone(_ rows: [Row], in session: ConfigurationEditorSession) {
        guard let now = rules(in: session.page?.document), rows.contains(where: { index(of: $0, in: now) == nil }) else { return }
        session.failure = OriginalEditingError.changedSinceRead.errorDescription
    }

    static func add(_ rule: String, in session: ConfigurationEditorSession) async -> Bool {
        let existing = (rules(in: session.shownDocument) ?? []).filter { $0 == rule }.count
        return await session.queueOriginal(addingFirst(rule, existing: existing))
    }
}

 
 
 
 
 
 
 
struct ConfigurationRulesAddToRulesForm: View {
     
    let model: ProfilesViewModel
    let profileID: String
    @ObservedObject var session: ConfigurationEditorSession
    @StateObject private var editor: ConfigurationRulesEditModel
    @Environment(\.clashFeedback) private var feedback
    @Environment(\.locale) private var locale

     
     
    @State private var options: RulePolicyOptions?

    init(model: ProfilesViewModel, profileID: String, session: ConfigurationEditorSession,
         running: ConfigurationRulesPageSnapshot.Running?, prepared: ConfigurationSchemeRulesPushed.Prepared?,
         libraryChanged: @escaping (ConfigurationLibrarySnapshot) -> Void) {
        self.model = model
        self.profileID = profileID
        self.session = session
        _editor = StateObject(wrappedValue: ConfigurationRulesEditModel(
            model: model, profileID: profileID, running: running, prepared: prepared, changed: libraryChanged))
    }

    var body: some View {
        Group {
            if editor.isOriginal == true {
                ConfigurationRulesPageRead(session: session, form: .original) { _ in
                    if let options {
                        RuleBuilderAdapter(raw: "", options: options, showsPersonalMetadata: false, pageTitle: "Add Rule") { raw in
                            let rule = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !rule.isEmpty else { return }
                             
                            Task { await ConfigurationRulesOriginalEdits.add(rule, in: session) }
                        }
                        .safeAreaInset(edge: .bottom, spacing: 0) { noteLine }
                    }
                }
            } else if editor.draft != nil, let options {
                RuleBuilderAdapter(raw: "", options: options, pageTitle: "Add Rule",
                                   saveDetails: { raw, enabled, note in editor.addToScheme(raw, enabled: enabled, note: note) },
                                   save: { editor.addToScheme($0, enabled: true, note: "") })
                    .environment(\.clashRuleTargetSearch, editor.targetSearchHook(locale: locale))
                    .safeAreaInset(edge: .bottom, spacing: 0) { noteLine }
            } else if let failure = editor.loadFailure {
                List { Text(verbatim: failure).foregroundStyle(.secondary) }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .clashModalPresentation(.page)
        .task { await editor.load() }
        .task(id: "\(String(describing: editor.isOriginal))#\(editor.draft != nil)#\(session.page != nil)") {
            guard options == nil else { return }
            if editor.isOriginal == true {
                if let page = session.page { options = RulePolicyOptions.make(document: page.document) }
            } else if editor.draft != nil {
                options = editor.schemeOptions
            }
        }
        .onAppear { editor.report = report; editor.schemeSession.locale = locale }
    }

     
    @ViewBuilder
    private var noteLine: some View {
        if let note {
            Text(verbatim: note)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                 
                 
                 
                .background(.bar)
                .accessibilityIdentifier("configuration.rules-page.add.note")
        }
    }

    private var note: String? {
        if editor.isOriginal == true {
            guard let page = session.page else { return nil }
            return ConfigurationRulesEditSnapshot.original(name: page.label, followsLink: page.followsSubscription,
                                                          opensText: false, locale: locale).note
        }
        guard let library = editor.library else { return nil }
        return ConfigurationRulesEditSnapshot.composed(profileID: profileID, library: library,
                                                       profiles: model.profiles.map { .init(id: $0.id, name: $0.label) },
                                                       locale: locale).note
    }

     
    private func report(_ message: String) {
        if let feedback {
            feedback.show(.error(title: ClashFeedbackCopy.couldNotSave, message: .copy(message),
                                 accessibilityIdentifier: "feedback.rules.edit"),
                          operation: "rules.edit")
        } else {
            session.failure = message
        }
    }
}

 

 
 
struct ConfigurationRulesEditList: View {
     
     
    let model: ProfilesViewModel
    let profileID: String
    private let handedSession: ConfigurationEditorSession?
    @StateObject private var ownState: ConfigurationPageState
    @StateObject private var editor: ConfigurationRulesEditModel

     
     
     
     
     
     
     
    init(model: ProfilesViewModel, profileID: String, session: ConfigurationEditorSession? = nil,
         running: ConfigurationRulesPageSnapshot.Running? = nil,
         prepared: ConfigurationSchemeRulesPushed.Prepared? = nil,
         libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)? = nil) {
        self.model = model
        self.profileID = profileID
        handedSession = session
        _ownState = StateObject(wrappedValue: ConfigurationPageState(model: model, profileID: profileID, selections: nil))
        _editor = StateObject(wrappedValue: ConfigurationRulesEditModel(
            model: model, profileID: profileID, running: running, prepared: prepared,
            changed: { libraryChanged?($0) }))
    }

    var body: some View {
        ConfigurationRulesEditListContent(model: model, profileID: profileID,
                                          session: handedSession ?? ownState.session, editor: editor)
    }
}

 
private struct ConfigurationRulesEditTarget: Identifiable {
    enum Place {
         
        case custom(Int)
         
        case scheme(UUID)
         
        case original(Int)
    }

    let id = UUID()
    let place: Place
    let raw: String
    let enabled: Bool
    let note: String
     
    var asText = false
     
    var options: RulePolicyOptions? = nil
     
     
    var pressed: ConfigurationRulesOriginalEdits.Row? = nil
}

private struct ConfigurationRulesEditListContent: View {
    let model: ProfilesViewModel
    let profileID: String
    @ObservedObject var session: ConfigurationEditorSession
    @ObservedObject var editor: ConfigurationRulesEditModel
    @State private var custom = ConfigurationRulesEditCustom()
    @State private var editing: ConfigurationRulesEditTarget?
    @State private var customOptions: RulePolicyOptions?
    @State private var namingScheme = false
    @State private var editingText = false
    @State private var confirmsRestore = false
    @AppStorage(ClashTowerRuleCustomizationView.groupIconsPreferenceKey) private var showsGroupIcons = true
    @Environment(\.clashFeedback) private var feedback
    @Environment(\.locale) private var locale
    @Environment(\.configurationFieldCopy) private var fieldCopy
     
    @Environment(\.clashRulesEditQuery) private var query

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }
     
     
     
    @State private var matched: (query: String, raws: Set<String>)?
     
    @State private var published: UInt64?

    var body: some View {
        Group {
            if let original = editor.isOriginal {
                if original {
                     
                     
                    ConfigurationRulesPageRead(session: session, form: .original) { _ in
                        if let page = session.page { list(original: page) }
                    }
                } else if editor.draft != nil {
                    list(original: nil)
                } else {
                    reading
                }
            } else {
                reading
            }
        }
        .task { await editor.load() }
        .task(id: searchKey) { await search() }
         
         
         
        .onReceive(model.$savedConfigurationGeneration) { _ in
            let now = model.publishedGeneration(of: profileID)
            defer { published = now }
            guard let published, published != now, editor.isOriginal == true, !session.isSaving else { return }
            Task { await session.reload() }
        }
        .onAppear { editor.report = report; editor.schemeSession.locale = locale }
        .onReceive(model.$profiles.map { [profileID] in ConfigurationRulesEditCustom($0.first { $0.id == profileID }) }
            .removeDuplicates()) { custom = $0 }
        .clashProductModal(item: $editing, role: .form) { target in
            form(target).clashModalPresentation(.page)
        }
        .clashProductModal(isPresented: $namingScheme, role: .form) {
            ConfigurationSchemeNameSheet(initial: schemeNameOffered) { name in saveAsScheme(named: name) }
                .clashModalPresentation(.form)
        }
        .clashProductModal(isPresented: $editingText, role: .page) { textEditor }
         
         
        .onChange(of: editingText) { open in
            if !open, editor.isOriginal == true { Task { await session.reload() } }
        }
        .alert(Text(clash: .copy("Restore Initial Rules?")), isPresented: $confirmsRestore) {
            Button(role: .destructive) { restore() } label: { Text(clash: .copy("Restore Initial Rules")) }
            Button(role: .cancel) {} label: { Text(clash: .copy("Cancel")) }
        } message: {
            Text(clash: .copy("Removes the rules, renames and reordering added after the scheme was created. My Rule Sets stay."))
        }
    }

    private var reading: some View {
        Group {
            if let failure = editor.loadFailure {
                List { Text(verbatim: failure).foregroundStyle(.secondary) }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

     

    private func list(original page: ProfilesViewModel.ConfigurationEditorPage?) -> some View {
        let snapshot = snapshot(original: page)
        return List {
            customSection
            schemeSection(original: page, note: snapshot.note)
            if trimmedQuery.isEmpty { footSection(snapshot.actions, original: page) }
        }
         
         
        .environment(\.editMode, .constant(.active))
        .accessibilityIdentifier("configuration.rules-page.edit")
    }

    private func snapshot(original page: ProfilesViewModel.ConfigurationEditorPage?) -> ConfigurationRulesEditSnapshot {
        if let page {
            return .original(name: page.label, followsLink: page.followsSubscription, opensText: page.opensEditSource,
                             locale: locale)
        }
        guard let library = editor.library else { return .init(note: nil, actions: []) }
        return .composed(profileID: profileID, library: library,
                         profiles: model.profiles.map { .init(id: $0.id, name: $0.label) }, locale: locale)
    }

     
     
    private func shows(_ raw: String) -> Bool {
        guard !trimmedQuery.isEmpty, let matched else { return true }
        return matched.raws.contains(raw)
    }

     
    private var searchedRules: [String] {
        custom.rules + schemeRows(original: editor.isOriginal == true ? session.page : nil).map(\.raw)
    }

     
     
    private var searchKey: String {
        guard !trimmedQuery.isEmpty else { return "" }
        var hasher = Hasher()
        searchedRules.forEach { hasher.combine($0) }
        return "\(trimmedQuery)#\(hasher.finalize())"
    }

    private func search() async {
        let query = trimmedQuery
        guard !query.isEmpty else { matched = nil; return }
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard !Task.isCancelled else { return }
        let raws = searchedRules, names = ruleSetNames, locale = locale, copy = fieldCopy
        let worker = Task.detached(priority: .userInitiated) { () -> Set<String> in
            var found: Set<String> = []
            for raw in raws {
                if Task.isCancelled { break }
                let words = ConfigurationRuleWords.of(raw, locale: locale, copy: copy, ruleSetNames: names)
                if [raw, words.match, words.kind, words.target ?? ""].contains(where: { $0.localizedCaseInsensitiveContains(query) }) {
                    found.insert(raw)
                }
            }
            return found
        }
        let found = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
        guard !Task.isCancelled else { return }
        matched = (query, found)
    }

    @ViewBuilder
    private var customSection: some View {
        let shown = custom.rules.indices.filter { shows(custom.rules[$0]) }
        if !shown.isEmpty {
            Section {
                ForEach(shown, id: \.self) { index in
                    let raw = custom.rules[index]
                    Button { openCustom(index) } label: {
                         
                         
                        ConfigurationRuleRow(raw)
                            .opacity(custom.disabled.contains(raw) ? 0.5 : 1)
                    }
                    .buttonStyle(.plain)
                    .moveDisabled(!trimmedQuery.isEmpty)
                    .accessibilityIdentifier("configuration.rules-page.edit.custom-rule")
                }
                .onDelete { offsets in deleteCustom(offsets.map { shown[$0] }) }
                .onMove { offsets, destination in
                    guard trimmedQuery.isEmpty else { return }
                    editor.changeCustomRules { $0.rules.move(fromOffsets: offsets, toOffset: destination) }
                }
            } header: {
                Text(clash: .copy(ConfigurationEditorCopy.title(of: .customRules)))
            }
        }
    }

    @ViewBuilder
    private func schemeSection(original page: ProfilesViewModel.ConfigurationEditorPage?, note: String?) -> some View {
        let rows = schemeRows(original: page)
        let final = rows.last?.isFinal == true ? rows.last : nil
        let movable = final == nil ? rows : Array(rows.dropLast())
         
        let names = ruleSetNames
        let shown = movable.filter { shows($0.raw) }
        Section {
            ForEach(shown) { row in
                Button { openScheme(row, original: page) } label: {
                    ConfigurationRuleRow(row.raw, ruleSetNames: names)
                        .opacity(row.enabled ? 1 : 0.5)
                }
                .buttonStyle(.plain)
                .moveDisabled(!trimmedQuery.isEmpty)
                .contextMenu {
                     
                    if case .index(let index) = row.id {
                        Button { editing = originalTarget(index, raw: row.raw, asText: true) } label: {
                            Text(clash: .copy("Edit as Text"))
                        }
                    }
                }
                .accessibilityIdentifier("configuration.rules-page.edit.rule")
            }
            .onDelete { offsets in deleteScheme(offsets.map { shown[$0] }, original: page) }
            .onMove { offsets, destination in
                guard trimmedQuery.isEmpty else { return }
                moveScheme(offsets, destination, original: page)
            }
             
             
            if let final, shows(final.raw) {
                Button { openScheme(final, original: page) } label: {
                    HStack(spacing: ClashTheme.Spacing.compact) {
                        Text(verbatim: ConfigurationRulesEditSnapshot.finalRow(final.raw, locale: locale))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                         
                         
                        ConfigurationRuleDisclosure()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("configuration.rules-page.edit.final")
            }
        } header: {
            Text(clash: schemeTitle(original: page))
        } footer: {
            if let note {
                Text(verbatim: note).accessibilityIdentifier("configuration.rules-page.edit.note")
            }
        }
    }

    @ViewBuilder
    private func footSection(_ actions: [ConfigurationRulesEditSnapshot.Action],
                             original page: ProfilesViewModel.ConfigurationEditorPage?) -> some View {
        Section {
            ForEach(actions, id: \.self) { action in
                switch action {
                case .saveAsScheme:
                    Button { namingScheme = true } label: { Text(clash: .copy("Save as New Scheme")) }
                        .disabled(session.isSaving || editor.saving)
                        .accessibilityIdentifier("configuration.rules-page.edit.save-as-scheme")
                case .editAsText:
                    Button { editingText = true } label: { Text(clash: .copy("Edit as Text")) }
                        .disabled(session.isSaving || editor.saving)
                        .accessibilityIdentifier("configuration.rules-page.edit.text")
                case .restoreInitialRules:
                    Button(role: .destructive) { confirmsRestore = true } label: { Text(clash: .copy("Restore Initial Rules")) }
                        .disabled(editor.saving || editor.resetDocument == nil)
                        .accessibilityIdentifier("configuration.rules-page.edit.restore")
                case .showGroupIcons:
                    Toggle(isOn: $showsGroupIcons) { Text(clash: .copy("Show Group Icons")) }
                        .accessibilityIdentifier("configuration.rules-page.edit.group-icons")
                }
            }
        }
    }

     

     
    struct SchemeRow: Identifiable, Equatable {
        enum Key: Hashable { case row(UUID), index(Int) }
        let id: Key
        let raw: String
        let enabled: Bool
        var isFinal: Bool { ConfigurationRuleDraft.Row(raw: raw).isFinal }
    }

    private func schemeRows(original page: ProfilesViewModel.ConfigurationEditorPage?) -> [SchemeRow] {
        if page != nil {
            return originalRules.enumerated().map { SchemeRow(id: .index($0.offset), raw: $0.element, enabled: true) }
        }
        guard let draft = editor.draft else { return [] }
        return draft.rows.map { SchemeRow(id: .row($0.id), raw: $0.raw, enabled: draft.isEnabled($0.raw)) }
    }

     
    private var originalRules: [String] {
        guard case .array(let items)? = session.value(at: ["rules"]) else { return [] }
        return items.map { item in
            if case .string(let text) = item { return text }
            return item.serialized()
        }
    }

    private func schemeTitle(original page: ProfilesViewModel.ConfigurationEditorPage?) -> ClashDisplayText {
        if page != nil { return .copy(ConfigurationRulesPageSnapshot.originalRulesTitle) }
        guard let library = editor.library, let scheme = ConfigurationRulesEditSnapshot.running(profileID, in: library) else {
            return .copy("Rules")
        }
        return .verbatim(scheme.displayLabel)
    }

     
     
    private var ruleSetNames: [String: String] {
        var names: [String: String] = [:]
        for set in editor.library?.localRuleSets ?? [] { names["local-" + set.id] = set.name }
        for entry in ConfigurationRuleCatalog.builtIn.entries { names["catalog-" + entry.id] = entry.displayName }
        return names
    }

     

    private func deleteCustom(_ indices: [Int]) {
        editor.changeCustomRules { draft in
            for index in indices.sorted(by: >) where draft.rules.indices.contains(index) {
                let raw = draft.rules.remove(at: index)
                if !draft.rules.contains(raw) {
                    draft.disabledRules.remove(raw)
                    draft.comments.removeValue(forKey: raw)
                }
            }
        }
    }

    private func deleteScheme(_ rows: [SchemeRow], original page: ProfilesViewModel.ConfigurationEditorPage?) {
        if page != nil {
             
            let indices = rows.compactMap { if case .index(let index) = $0.id { return index }; return nil }
            let pressed = ConfigurationRulesOriginalEdits.rows(at: indices, in: originalRules)
            Task { await ConfigurationRulesOriginalEdits.delete(pressed, in: session) }
        } else {
            let ids = Set(rows.compactMap { if case .row(let id) = $0.id { return id }; return nil })
            editor.change { $0.remove(ids) }
        }
    }

    private func moveScheme(_ offsets: IndexSet, _ destination: Int, original page: ProfilesViewModel.ConfigurationEditorPage?) {
        if page != nil {
             
             
            let rules = originalRules
            let rows = schemeRows(original: page)
            let movable = rows.last?.isFinal == true ? rows.count - 1 : rows.count
            guard let drag = ConfigurationRulesOriginalEdits.dragged(offsets, to: destination, in: rules, movable: movable)
            else { return }
            Task { await ConfigurationRulesOriginalEdits.move(drag, in: session) }
        } else {
             
            let rows = schemeRows(original: nil)
            let movable = rows.last?.isFinal == true ? rows.count - 1 : rows.count
            guard offsets.count == 1, let from = offsets.first, from < movable, case .row(let id) = rows[from].id else { return }
            var anchor: UUID?
            if destination < movable, case .row(let at) = rows[destination].id { anchor = at }
            editor.moveRow(id, before: anchor)
        }
    }

    private func restore() {
        guard let reset = editor.resetDocument else { return }
        editor.change { try $0.replaceContents(OrderedJSON.parse(reset)) }
    }

     

    private func openCustom(_ index: Int) {
        guard custom.rules.indices.contains(index) else { return }
        let raw = custom.rules[index]
        editing = ConfigurationRulesEditTarget(place: .custom(index), raw: raw, enabled: !custom.disabled.contains(raw),
                                               note: custom.comments[raw] ?? "")
    }

    private func openScheme(_ row: SchemeRow, original page: ProfilesViewModel.ConfigurationEditorPage?) {
        switch row.id {
        case .index(let index):
            editing = originalTarget(index, raw: row.raw,
                                     asText: OriginalListEdits.isWrittenAsText(row.raw, catalog: session.catalog))
        case .row(let id):
            editing = ConfigurationRulesEditTarget(place: .scheme(id), raw: row.raw, enabled: row.enabled,
                                                   note: editor.draft?.note(for: row.raw) ?? "",
                                                   options: editor.schemeOptions)
        }
    }

     
     
    private func originalTarget(_ index: Int, raw: String, asText: Bool) -> ConfigurationRulesEditTarget {
        ConfigurationRulesEditTarget(place: .original(index), raw: raw, enabled: true, note: "", asText: asText,
                                     options: RulePolicyOptions.make(document: session.page?.document),
                                     pressed: ConfigurationRulesOriginalEdits.rows(at: [index], in: originalRules).first)
    }

    @ViewBuilder
    private func form(_ target: ConfigurationRulesEditTarget) -> some View {
        switch target.place {
        case .custom(let index):
            if let options = customOptions {
                RuleBuilderAdapter(raw: target.raw, options: options, enabled: target.enabled, comment: target.note,
                                   saveDetails: { raw, enabled, comment in setCustom(index, from: target.raw, raw, enabled, comment) },
                                   save: { setCustom(index, from: target.raw, $0, true, "") })
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task { await loadCustomOptions() }
            }
        case .scheme(let id):
            RuleBuilderAdapter(raw: target.raw, options: target.options ?? .empty, enabled: target.enabled, comment: target.note,
                               saveDetails: { raw, enabled, note in
                                   editor.change { $0.setRule(raw, enabled: enabled, note: note, rowID: id) }
                               },
                               save: { raw in editor.change { $0.setRule(raw, enabled: true, note: "", rowID: id) } })
                .environment(\.clashRuleTargetSearch, editor.targetSearchHook(locale: locale))
        case .original:
            if target.asText {
                ConfigurationRawRuleEditor(raw: target.raw) { raw in setOriginal(target, raw) }
            } else {
                RuleBuilderAdapter(raw: target.raw, options: target.options ?? .empty,
                                   showsPersonalMetadata: false) { raw in setOriginal(target, raw) }
            }
        }
    }

    private func setCustom(_ index: Int, from old: String, _ raw: String, _ enabled: Bool, _ comment: String) {
        let rule = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rule.isEmpty else { return }
        editor.changeCustomRules { draft in
             
             
            guard draft.rules.indices.contains(index), draft.rules[index] == old else { return }
            draft.replaceRule(at: index, with: rule)
            if enabled { draft.disabledRules.remove(rule) } else { draft.disabledRules.insert(rule) }
            let note = comment.trimmingCharacters(in: .whitespacesAndNewlines)
            if note.isEmpty { draft.comments.removeValue(forKey: rule) } else { draft.comments[rule] = note }
        }
    }

     
     
    private func setOriginal(_ target: ConfigurationRulesEditTarget, _ raw: String) {
        let rule = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rule.isEmpty, rule != target.raw, let pressed = target.pressed else { return }
        Task { await ConfigurationRulesOriginalEdits.set(pressed, to: rule, in: session) }
    }

     
     
    private func loadCustomOptions() async {
        guard customOptions == nil, let profile = model.profiles.first(where: { $0.id == profileID }) else { return }
        let projected = await model.loadUIProjectedYAML(for: profile)
        let shared = await Task.detached(priority: .userInitiated) {
            ProfileRulesAdapter.buildPolicyOptions(sourceYAML: projected, profile: profile)
        }.value
        customOptions = RulePolicyOptions(shared: shared)
    }

     

    private var schemeNameOffered: String {
        if editor.isOriginal == true { return session.page?.label ?? "" }
        guard let draft = editor.draft, let library = editor.library else { return "" }
        return ClashTowerRuleCustomizationView.newSchemeName(
            draft, locale: locale, taken: ClashTowerRuleCustomizationView.takenSchemeNames(in: library, locale: locale))
    }

    private func saveAsScheme(named name: String) {
        guard !name.isEmpty else { return }
        if editor.isOriginal == true {
             
            Task { await session.saveAsScheme(named: name) }
        } else {
            Task { await editor.copy(named: name) }
        }
    }

    @ViewBuilder
    private var textEditor: some View {
        if editor.isOriginal == true {
             
             
            if let profile = model.profiles.first(where: { $0.id == profileID }) {
                ProfileSourceEditorLoader(profile: profile, model: model)
                    .configurationEditorOwnsItsScreen()
                    .clashModalPresentation(.page)
            } else {
                ClashOpeningCancelButton().clashModalPresentation(.page)
            }
        } else if let draft = editor.draft {
             
             
            ClashSingleColumnNavigationContainer {
                ConfigurationTowerManualRuleEditor(draft: draft) { value in
                     
                    let document = value.currentDocument()
                    editor.change { try $0.replaceContents(document) }
                }
            }
            .environment(\.clashProductModalDismiss, { editingText = false })
            .clashModalPresentation(.page)
        }
    }

     
     
    private func report(_ message: String) {
        if let feedback {
            feedback.show(.error(title: ClashFeedbackCopy.couldNotSave, message: .copy(message),
                                 accessibilityIdentifier: "feedback.rules.edit"),
                          operation: "rules.edit")
        } else {
            session.failure = message
        }
    }
}

 
struct ConfigurationRulesEditCustom: Equatable {
    var rules: [String] = []
    var disabled: Set<String> = []
    var comments: [String: String] = [:]

    init() {}

    init(_ profile: Profile?) {
        rules = profile?.override.appendRules ?? []
        disabled = Set(profile?.override.disabledAppendRules ?? [])
        comments = profile?.override.appendRuleComments ?? [:]
    }
}
#endif
