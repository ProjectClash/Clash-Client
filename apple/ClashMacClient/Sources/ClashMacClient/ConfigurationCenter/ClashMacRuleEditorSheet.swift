import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
public struct ClashMacRuleEditorState: Equatable, Sendable {
    public var draft: ConfigurationRuleDraft
    public var localSets: [ConfigurationLocalRuleSet]
    public var resetDocument: String
     
     
     
     
     
    public var keptRuleCount: Int?

    public init(draft: ConfigurationRuleDraft, localSets: [ConfigurationLocalRuleSet], resetDocument: String,
                keptRuleCount: Int? = nil) {
        self.draft = draft
        self.localSets = localSets
        self.resetDocument = resetDocument
        self.keptRuleCount = keptRuleCount
    }
}

 
 
public struct ClashMacRuleEditorActions {
     
    public var load: @MainActor () async throws -> ClashMacRuleEditorState
     
     
    public var save: @MainActor (ConfigurationRuleDraft) async throws -> ConfigurationRuleDraft
     
    public var saveLocal: @MainActor (ConfigurationLocalRuleSet) async throws -> ClashMacRuleEditorState
     
    public var deleteLocal: @MainActor (String) async throws -> ClashMacRuleEditorState
     
    public var copy: @MainActor (ConfigurationRuleDraft, String) async throws -> Void
     
     
     
     
     
     
    public var download: @MainActor (String) async throws -> ConfigurationRuleSetContent
     
     
     
     
     
     
    public var candidates: (@MainActor () async throws -> ConfigurationRuleTargetCandidates)? = nil
     
     
     
    public var targetSearch: ClashRuleTargetSearchHook? = nil
     
     
     
    public var geoValues: ClashMacGeoValueLoader? = nil
    public var documentText: (@Sendable (String) throws -> String)? = nil
     
     
     
    public var rulesHaveSwitches = true
    public var documentFromText: (@Sendable (String) throws -> String)? = nil
     
     
     
     
    public var keptRulesPane: (@MainActor () -> AnyView)? = nil
     
     
    public var keptRulesNote: ClashDisplayText? = nil

    public init(
        load: @escaping @MainActor () async throws -> ClashMacRuleEditorState,
        save: @escaping @MainActor (ConfigurationRuleDraft) async throws -> ConfigurationRuleDraft,
        saveLocal: @escaping @MainActor (ConfigurationLocalRuleSet) async throws -> ClashMacRuleEditorState,
        deleteLocal: @escaping @MainActor (String) async throws -> ClashMacRuleEditorState,
        copy: @escaping @MainActor (ConfigurationRuleDraft, String) async throws -> Void,
        download: @escaping @MainActor (String) async throws -> ConfigurationRuleSetContent
    ) {
        self.load = load
        self.save = save
        self.saveLocal = saveLocal
        self.deleteLocal = deleteLocal
        self.copy = copy
        self.download = download
    }

    public static var unavailable: ClashMacRuleEditorActions {
        ClashMacRuleEditorActions(
            load: { throw ConfigurationLibraryError.unreadable },
            save: { _ in throw ConfigurationLibraryError.unreadable },
            saveLocal: { _ in throw ConfigurationLibraryError.unreadable },
            deleteLocal: { _ in throw ConfigurationLibraryError.unreadable },
            copy: { _, _ in throw ConfigurationLibraryError.unreadable },
            download: { _ in throw ConfigurationLibraryError.unreadable }
        )
    }
}

 
 
 
public enum ClashMacRuleSetKey {
    public static func catalog(_ entry: ConfigurationRuleCatalogEntry) -> String { "catalog-" + entry.id }
    public static func local(_ set: ConfigurationLocalRuleSet) -> String { "local-" + set.id }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
public struct ClashMacRuleEditorSheet: View {
    private enum Sheet: Identifiable {
        case rule(UUID?)
         
        case subRuleRow(UUID, UUID?)
         
        case subRuleName(UUID?)
        case group(UUID?)
        case ruleSet(String?)
        case duplicate
        var id: String {
            switch self {
            case .rule(let id): "rule-\(id?.uuidString ?? "new")"
            case .subRuleRow(let subRule, let id): "sub-rule-\(subRule.uuidString)-\(id?.uuidString ?? "new")"
            case .subRuleName(let id): "sub-rule-name-\(id?.uuidString ?? "new")"
            case .group(let id): "group-\(id?.uuidString ?? "new")"
            case .ruleSet(let id): "rule-set-\(id ?? "new")"
            case .duplicate: "duplicate"
            }
        }
    }

     
     
     
    public enum Pane: String, CaseIterable, Identifiable {
        case rules, groups, ruleSets, subRules, source
        public var id: String { rawValue }
        var title: ClashDisplayText {
            switch self {
            case .rules: .copy("Rules")
            case .groups: .copy("Policy Groups")
            case .ruleSets: .copy("Rule Sets")
            case .subRules: .copy("Sub-rules")
            case .source: .copy("Source")
            }
        }
    }

     
     
    public enum Presentation: Equatable, Sendable { case sheet, page }

    private let actions: ClashMacRuleEditorActions
    private let presentation: Presentation
    private let saved: () -> Void
     
     
     
     
    @StateObject private var dismiss = ClashDismissHandle()
    @Environment(\.locale) private var locale
    @Environment(\.configurationFieldCopy) private var copy
    @State private var state: ClashMacRuleEditorState?
    @State private var baseline: ConfigurationRuleDraft?
     
     
    @State private var edited = false
     
     
     
    @State private var installedRuleSets: Set<String> = []
     
     
     
     
     
     
     
    @State private var catalogSwitches = ClashStoredSwitch<String>()
    @State private var loadError: String?
    @State private var error: String?
    @State private var busy = false
    @State private var sheet: Sheet?
    @State private var confirmsDiscard = false
    @State private var confirmsReset = false
    @State private var pane: Pane = .rules
     
     
     
    @State private var ruleSelection = Set<ConfigurationRuleDraft.Row.ID>()
    @State private var nodeCandidates = ConfigurationRuleTargetCandidates(sections: [])
    @State private var sourceText = ""
     
    @State private var shownSourceText = ""

     
    @State private var savesAgain = false
    @State private var saving = false
     
    @State private var resetPending = false
     
    @Environment(\.clashFeedback) private var feedback

     
     
    public enum Focus: Equatable, Sendable {
        case group(named: String)
        case ruleSet(named: String)
    }

     
    @State private var focus: Focus?

    public init(
        actions: ClashMacRuleEditorActions, initialPane: Pane = .rules,
        presentation: Presentation = .sheet, focus: Focus? = nil, saved: @escaping () -> Void = {}
    ) {
        self.actions = actions
        self.presentation = presentation
        self.saved = saved
        _pane = State(initialValue: initialPane)
        _focus = State(initialValue: focus)
    }

    private var dirty: Bool { edited && state != nil && baseline != nil }

    public var body: some View {
        frame
        .environment(\.clashRuleTargetSearch, actions.targetSearch)
         
         
         
        .task {
            if state == nil { await load() }
            await loadCandidates()
        }
        .sheet(item: $sheet) { item in
            Group {
            if let state {
                switch item {
                case .rule(let id):
                    ClashMacRuleRowEditor(
                        draft: state.draft, rowID: id, hasSwitches: actions.rulesHaveSwitches,
                        judgesRuleSets: actions.rulesHaveSwitches,
                        nodeCandidates: nodeCandidates,
                        createGroup: { document in try mutateThrowing { draft in try draft.setGroup(document, groupID: nil) } },
                        geoValues: actions.geoValues,
                        commit: { raw, enabled, note in mutate { draft in
                            if let id {
                                draft.setRule(raw, enabled: enabled, note: note, rowID: id)
                            } else {
                                draft.insertRuleFirst(raw)
                                if let first = draft.rows.first { draft.setRule(raw, enabled: enabled, note: note, rowID: first.id) }
                            }
                        } },
                        close: { sheet = nil }
                    )
                case .subRuleRow(let subRuleID, let id):
                     
                     
                     
                    ClashMacRuleRowEditor(
                        draft: state.draft, rowID: id, subRuleID: subRuleID,
                        judgesRuleSets: actions.rulesHaveSwitches,
                        nodeCandidates: nodeCandidates,
                        createGroup: { document in try mutateThrowing { draft in try draft.setGroup(document, groupID: nil) } },
                        geoValues: actions.geoValues,
                        commit: { raw, _, _ in
                            try? mutateThrowing { draft in try draft.setSubRuleRow(raw, rowID: id, in: subRuleID) }
                        },
                        close: { sheet = nil }
                    )
                case .subRuleName(let id):
                    ClashMacNamePrompt(
                        title: id == nil ? .copy("Add Sub-rule") : .copy("Rename Sub-rule"),
                        initial: id.flatMap { subRuleID in state.draft.subRules.first { $0.id == subRuleID }?.name } ?? "",
                        nameIdentifier: "configuration-center.rule-editor.sub-rule.name",
                        cancelIdentifier: "configuration-center.rule-editor.sub-rule.name.cancel",
                        saveIdentifier: "configuration-center.rule-editor.sub-rule.name.save",
                        commit: { name in
                            try mutateThrowing { draft in
                                if let id { try draft.renameSubRule(id, to: name) } else { try draft.addSubRule(named: name) }
                            }
                        },
                        close: { sheet = nil }
                    )
                case .group(let id):
                    ClashMacRuleGroupEditor(
                        group: id.flatMap { gid in state.draft.groups.first { $0.id == gid } },
                        all: state.draft.groups, nodeCandidates: nodeCandidates,
                        commit: { document in try mutateThrowing { draft in try draft.setGroup(document, groupID: id) } },
                        close: { sheet = nil }
                    )
                case .ruleSet(let id):
                    let value = id.flatMap { setID in state.localSets.first { $0.id == setID } }
                    ClashMacLocalRuleSetEditor(
                        value: value,
                        policy: value.flatMap { state.draft.ruleSetPolicy(ClashMacRuleSetKey.local($0)) }
                            ?? state.draft.groups.first?.name ?? "DIRECT",
                        candidates: Self.policyCandidates(groups: state.draft.groups, nodes: nodeCandidates),
                        geoValues: actions.geoValues,
                        download: actions.download,
                        save: { set, policy in
                             
                             
                             
                             
                             
                            try await runThrowing {
                                let next = try await actions.saveLocal(set)
                                adopt(next, keepDraft: true)
                                try mutateThrowing { draft in
                                    try draft.attachRuleSet(
                                        key: ClashMacRuleSetKey.local(set), name: set.name, rules: set.rules, policy: policy,
                                        link: set.link, behavior: set.behavior
                                    )
                                }
                            }
                        },
                        close: { sheet = nil }
                    )
                case .duplicate:
                    ClashMacNamePrompt(
                        title: .copy("Duplicate"),
                        initial: ClashCopy.string("My Rules", locale: locale),
                        nameIdentifier: "configuration-center.rule-editor.duplicate.name",
                        cancelIdentifier: "configuration-center.rule-editor.duplicate.cancel",
                        saveIdentifier: "configuration-center.rule-editor.duplicate.save",
                        commit: { name in try await runThrowing { try await actions.copy(state.draft, name); saved(); dismiss() } },
                        close: { sheet = nil }
                    )
                }
            }
            }
            .clashModalPresentation(.fitted)
             
             
            .environment(\.clashRuleTargetSearch, actions.targetSearch)
        }
        .alert(Text(clash: .copy("Discard Changes")), isPresented: $confirmsDiscard) {
            Button(role: .destructive) { dismiss() } label: { Text(clash: .copy("Discard Changes")) }
            Button(role: .cancel) {} label: { Text(clash: .copy("Cancel")) }
        } message: {
            Text(clash: .copy("This profile has changes that have not been saved."))
        }
        .alert(Text(clash: .copy("Reset")), isPresented: $confirmsReset) {
            Button(role: .destructive) { reset() } label: {
                Text(clash: .copy("Reset"))
            }
            Button(role: .cancel) {} label: { Text(clash: .copy("Cancel")) }
        }
        .clashCapturesDismiss(dismiss)
    }

    @ViewBuilder private var frame: some View {
        switch presentation {
        case .sheet: sheetFrame
        case .page: pageFrame
        }
    }

    private var sheetFrame: some View {
        ClashMacSheetFrame(
            title: .verbatim(state?.draft.label ?? ""),
            subtitle: state.map { ClashDisplayText.count($0.draft.rows.count, one: "%@ rule", other: "%@ rules") },
            width: 680,
            height: 640
        ) {
            if let state {
                content(state)
            } else {
                placeholder
            }
        } leading: {
             
             
            Button { sheet = .duplicate } label: { Text(clash: .copy("Copy Rule Scheme")) }
                .disabled(busy || state == nil)
                .accessibilityIdentifier("configuration-center.rule-editor.save-as")
            if let error {
                Text(verbatim: error).foregroundStyle(.red).font(.subheadline).lineLimit(2)
                    .accessibilityIdentifier("configuration-center.rule-editor.error")
            }
        } trailing: {
            ClashMacSheetButtons(
                closeIdentifier: "configuration-center.rule-editor.cancel",
                 
                primaryTitle: .copy("OK"),
                primaryIdentifier: "configuration-center.rule-editor.save",
                primaryDisabled: !dirty || busy,
                isBusy: busy,
                onClose: { if dirty { confirmsDiscard = true } else { dismiss() } },
                onPrimary: save
            )
        }
    }

    @ViewBuilder private var placeholder: some View {
        if let loadError {
            ClashMacSheetPlaceholder(
                title: .copy("Rule Library"), message: loadError,
                retry: { Task { await load() } },
                retryIdentifier: "configuration-center.rule-editor.retry"
            )
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

     
     
     
    private var pageFrame: some View {
        VStack(spacing: 0) {
            if let error {
                Text(verbatim: error)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("configuration-center.rule-editor.error")
                Divider()
            }
            if let state {
                paneContent(state)
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            if let title = addTitle {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: add) {
                        Label { Text(clash: title) } icon: { Image(systemName: "plus") }
                    }
                    .help(Text(clash: title))
                    .disabled(busy || state == nil || (pane == .subRules && state?.draft.subRulesEditable == false))
                    .accessibilityIdentifier("configuration-center.rule-editor.add")
                }
            }
        }
        .navigationTitle(Text(clash: pane.title))
        .clashFrameWatch("configuration-rule-page")
        .accessibilityIdentifier("configuration-center.rule-page.\(pane.rawValue)")
    }

     
     
    private var addTitle: ClashDisplayText? {
        if state?.keptRuleCount != nil, Self.keptPanes.contains(pane) { return nil }
        return switch pane {
        case .rules: .copy("Add Rule")
        case .groups: .copy("Add Group")
        case .ruleSets: .copy("Add Rule Set")
        case .subRules: .copy("Add Sub-rule")
        case .source: nil
        }
    }

    private func add() {
        switch pane {
        case .rules: sheet = .rule(nil)
        case .groups: sheet = .group(nil)
        case .ruleSets: sheet = .ruleSet(nil)
        case .subRules: sheet = .subRuleName(nil)
        case .source: break
        }
    }

     

     
    @ViewBuilder private func paneContent(_ state: ClashMacRuleEditorState) -> some View {
        if let kept = state.keptRuleCount, Self.keptPanes.contains(pane) {
            keptPane(kept)
        } else {
            editablePane(state)
        }
    }

     
     
     
    static let keptPanes: Set<Pane> = [.rules, .ruleSets, .source]

     
     
    @ViewBuilder private func keptPane(_ count: Int) -> some View {
        let note = actions.keptRulesNote.map { ClashCopy.string(for: $0, locale: locale) }
        if pane == .rules, let list = actions.keptRulesPane {
            list()
        } else {
            ClashMacSheetPlaceholder(title: pane == .rules ? .count(count, one: "%@ rule", other: "%@ rules") : pane.title,
                                     message: note)
                .accessibilityIdentifier("configuration-center.rule-editor.kept")
        }
    }

    @ViewBuilder private func editablePane(_ state: ClashMacRuleEditorState) -> some View {
        switch pane {
        case .rules:
            List(selection: $ruleSelection) { rulesSection(state.draft) }
                .listStyle(.inset)
                .clashMacRuleListRows()
                 
                 
                 
                .contextMenu(forSelectionType: ConfigurationRuleDraft.Row.ID.self) { ids in
                    if ids.count == 1, let id = ids.first, let row = state.draft.rows.first(where: { $0.id == id }) {
                        ruleMenu(row, draft: state.draft)
                    }
                }
        case .groups: List { groupsSection(state.draft) }.listStyle(.inset)
        case .ruleSets: List { ruleSetsSection(state) }.listStyle(.inset)
        case .subRules: List { subRulesSections(state.draft) }.listStyle(.inset)
        case .source: sourcePane(state)
        }
    }

    private func content(_ state: ClashMacRuleEditorState) -> some View {
        HStack(spacing: 0) {
            List(selection: $pane) {
                ForEach(Pane.allCases) { item in
                    Text(clash: item.title).tag(item)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 150)
            .accessibilityIdentifier("configuration-center.rule-editor.pane")
            Divider()
            paneContent(state)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clashFrameWatch("configuration-rule-editor")
        .accessibilityIdentifier("configuration-center.rule-editor")
    }

     
     
     
    private func sourcePane(_ state: ClashMacRuleEditorState) -> some View {
        let currentJSON = Self.sourceText(state)
        return VStack(spacing: 0) {
            TextEditor(text: $sourceText)
                .font(.body.monospaced())
                .padding(12)
                .accessibilityIdentifier("configuration-center.rule-editor.source.text")
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Button(role: .destructive) { confirmsReset = true } label: { Text(clash: .copy("Reset")) }
                        .accessibilityIdentifier("configuration-center.rule-editor.source.reset")
                    Spacer()
                    Button { applySourceText() } label: { Text(clash: .copy("Done")) }
                        .disabled(busy || sourceText == shownSourceText)
                        .accessibilityIdentifier("configuration-center.rule-editor.source.done")
                }
                 
                 
                if presentation == .page, let feedback {
                    ClashMacFeedbackSlot(center: feedback, operations: [Self.resetOperation])
                }
            }
            .padding(10)
        }
        .task(id: currentJSON) {
             
            let convert = actions.documentText
            let text = await Task.detached { (try? convert?(currentJSON)) ?? currentJSON }.value
            shownSourceText = text
            sourceText = text
        }
    }

     
     
     
    private func applySourceText() {
        let text = sourceText
        let convert = actions.documentFromText
        busy = true
        Task {
            defer { busy = false }
            do {
                let root = try await Task.detached { try OrderedJSON.parse(try convert?(text) ?? text) }.value
                if case .object(let entries) = root,
                   entries.contains(where: { !ConfigurationRuleDocument.keys.contains($0.key) }) {
                    throw ClashMacRuleSourceError.foreignKeys
                }
                try mutateThrowing { draft in try draft.replaceContents(root) }
            } catch ClashMacRuleSourceError.foreignKeys {
                error = ClashCopy.string("Only rules and policy groups belong here. Add nodes in Node Library.", locale: locale)
            } catch {
                self.error = ClashErrorCopy.message(error, locale: locale)
            }
        }
    }

    private static func sourceText(_ state: ClashMacRuleEditorState) -> String {
        (try? state.draft.document().serialized()) ?? state.draft.originalDocument.serialized()
    }

    private func rulesSection(_ draft: ConfigurationRuleDraft) -> some View {
        Section {
             
             
            if presentation == .sheet {
                Button { sheet = .rule(nil) } label: { Text(clash: .copy("Add Rule")) }
                    .disabled(busy)
                    .accessibilityIdentifier("configuration-center.rule-editor.add-rule")
            }
             
            if draft.rows.isEmpty {
                Text(clash: .copy("No rules yet. Rules decide, top to bottom, where each connection goes."))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("configuration-center.rule-editor.rules.empty")
            }
            ForEach(draft.rows) { row in
                ruleRow(row, draft: draft)
                     
                     
                    .moveDisabled(row.isFinal)
            }
             
             
            .onMove { offsets, destination in
                mutate { $0.moveRows(fromOffsets: offsets, toOffset: destination) }
            }
        } header: {
            Text(clash: .copy("Rules"))
        }
    }

     
     
    private var ruleSetNames: [String: String] {
        Dictionary((state?.localSets ?? []).map { ("local-" + $0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    private func ruleRow(_ row: ConfigurationRuleDraft.Row, draft: ConfigurationRuleDraft) -> some View {
        let enabled = draft.isEnabled(row.raw)
        let note = draft.note(for: row.raw)
        return HStack(spacing: ClashTheme.Spacing.compact) {
             
             
             
            if actions.rulesHaveSwitches {
                Toggle(isOn: Binding(
                    get: { enabled },
                    set: { on in mutate { $0.setRule(row.raw, enabled: on, note: note, rowID: row.id) } }
                )) {
                    Text(clash: .copy("Enabled"))
                }
                .toggleStyle(.checkbox)
                .labelsHidden()
                 
                 
                 
                 
                .accessibilityIdentifier("configuration-center.rule-editor.rule-enabled.\(row.id.uuidString)")
            }
             
             
             
             
             
            Button { sheet = .rule(row.id) } label: {
                VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                    ConfigurationRuleRow(row.raw, ruleSetNames: ruleSetNames)
                        .opacity(enabled ? 1 : 0.5)
                    if !note.isEmpty {
                        Text(verbatim: note).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("configuration-center.rule-editor.rule.\(row.id.uuidString)")
        }
        .disabled(busy)
    }

     
    @ViewBuilder
    private func ruleMenu(_ row: ConfigurationRuleDraft.Row, draft: ConfigurationRuleDraft) -> some View {
        let enabled = draft.isEnabled(row.raw)
        let note = draft.note(for: row.raw)
        Button { sheet = .rule(row.id) } label: { Text(clash: .copy("Edit")) }
        if actions.rulesHaveSwitches {
            Button {
                mutate { $0.setRule(row.raw, enabled: !enabled, note: note, rowID: row.id) }
            } label: {
                Text(clash: .copy("Enabled"))
            }
        }
        Divider()
         
         
         
         
        Button { mutate { $0.moveRow(row.id, offset: -1) } } label: { Text(clash: .copy("Move Up")) }
            .disabled(busy || row.isFinal || draft.rows.first?.id == row.id)
        Button { mutate { $0.moveRow(row.id, offset: 1) } } label: { Text(clash: .copy("Move Down")) }
            .disabled(busy || row.isFinal || Self.isRowAboveFinal(row, in: draft))
        Divider()
        Button(role: .destructive) { mutate { $0.remove([row.id]) } } label: { Text(clash: .copy("Delete")) }
            .disabled(busy)
    }

     
     
    static let groupIconSize: CGFloat = 22

     
     
    static func routeName(_ route: ConfigurationRuleCatalogDefaultRoute, locale: Locale,
                          copy: ConfigurationFieldCopy = .shared) -> String {
        switch route {
        case .direct: return ConfigurationRuleWords.targetName("DIRECT", locale: locale, copy: copy)
        case .reject: return ConfigurationRuleWords.targetName("REJECT", locale: locale, copy: copy)
        case .proxy: return ClashCopy.string(for: .copy("Proxy"), locale: locale)
        }
    }

    private func groupsSection(_ draft: ConfigurationRuleDraft) -> some View {
         
         
        let typeNames = ClashMacValueWords.valueNames(path: "proxy-groups[*].type", copy: copy, locale: locale)
        return Section {
            if presentation == .sheet {
                Button { sheet = .group(nil) } label: { Text(clash: .copy("Add Group")) }
                    .disabled(busy)
                    .accessibilityIdentifier("configuration-center.rule-editor.add-group")
            }
            if draft.groups.isEmpty {
                Text(clash: .copy("No policy groups yet. A group chooses which node traffic goes through."))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("configuration-center.rule-editor.groups.empty")
            }
            ForEach(draft.groups) { group in
                 
                Button { sheet = .group(group.id) } label: {
                    HStack(spacing: ClashTheme.Spacing.compact) {
                         
                         
                         
                         
                        ClashTowerGroupIconView(icon: ClashTowerGroupIcon.read(group.document), size: Self.groupIconSize) { EmptyView() }
                        VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                            Text(verbatim: group.name)
                            Text(verbatim: typeNames[group.type.lowercased()] ?? group.type).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: ClashTheme.Spacing.row)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .contextMenu {
                    Button { sheet = .group(group.id) } label: { Text(clash: .copy("Edit")) }
                    Divider()
                    Button { moveGroup(group.id, up: true, in: draft) } label: { Text(clash: .copy("Move Up")) }
                        .disabled(draft.groups.first?.id == group.id)
                    Button { moveGroup(group.id, up: false, in: draft) } label: { Text(clash: .copy("Move Down")) }
                        .disabled(draft.groups.last?.id == group.id)
                    Divider()
                    Button(role: .destructive) {
                        try? mutateThrowing { try $0.removeGroups([group.id]) }
                    } label: {
                        Text(clash: .copy("Delete"))
                    }
                }
                .accessibilityIdentifier("configuration-center.rule-editor.group.\(group.id.uuidString)")
            }
             
             
            .onMove { offsets, destination in
                mutate { $0.moveGroups(Self.movedGroups(offsets, in: $0.groups), before: Self.groupAfter(destination, moving: offsets, in: $0.groups)) }
            }
        } header: {
            Text(clash: .copy("Policy Groups"))
        }
    }

     
    static func movedGroups(_ offsets: IndexSet, in groups: [ConfigurationRuleDraft.Group]) -> Set<UUID> {
        Set(offsets.filter { groups.indices.contains($0) }.map { groups[$0].id })
    }

     
     
     
    static func groupAfter(_ destination: Int, moving offsets: IndexSet, in groups: [ConfigurationRuleDraft.Group]) -> UUID? {
        guard destination < groups.count else { return nil }
        return groups[destination...].enumerated().first { !offsets.contains(destination + $0.offset) }?.element.id
    }

    private func ruleSetsSection(_ state: ClashMacRuleEditorState) -> some View {
        Group {
            Section {
                if presentation == .sheet {
                    Button { sheet = .ruleSet(nil) } label: { Text(clash: .copy("Add Rule Set")) }
                        .disabled(busy)
                        .accessibilityIdentifier("configuration-center.rule-editor.add-rule-set")
                }
                 
                 
                 
                 
                 
                 
                ForEach(state.localSets) { set in
                    let key = ClashMacRuleSetKey.local(set)
                    Toggle(isOn: Binding(
                        get: { installedRuleSets.contains(key) },
                        set: { _ in
                            try? mutateThrowing { value in
                                if value.containsRuleSet(key) { value.removeRuleSet(key) }
                                else { try value.addRuleSet(key: key, name: set.name, rules: set.rules, defaultRoute: "proxy",
                                                            link: set.link, behavior: set.behavior) }
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                            Text(verbatim: set.name)
                            Text(clash: .count(set.ruleCount, one: "%@ rule", other: "%@ rules"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("configuration-center.rule-editor.local.\(set.id)")
                    .contextMenu {
                         
                        Button { sheet = .ruleSet(set.id) } label: { Text(clash: .copy("Edit")) }
                        Button(role: .destructive) {
                            Task { await run { let next = try await actions.deleteLocal(set.id); adopt(next, keepDraft: true) } }
                        } label: {
                            Text(clash: .copy("Delete"))
                        }
                    }
                }
            } header: {
                Text(clash: .copy("My Rules"))
            }
            Section {
                ForEach(ConfigurationRuleCatalog.builtIn.entries) { entry in
                    let key = ClashMacRuleSetKey.catalog(entry)
                    VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                        ClashStoredToggle(catalogSwitches, key: key, stored: installedRuleSets.contains(key),
                                          identifier: "configuration-center.rule-editor.catalog.\(entry.id)",
                                          set: { pressCatalog(entry, key: key, $0) }) {
                            HStack(spacing: ClashTheme.Spacing.compact) {
                                VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                                    Text(verbatim: entry.displayName)
                                    Text(verbatim: Self.routeName(entry.defaultRoute, locale: locale, copy: copy))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                ClashMacStoredWriting(catalogSwitches, key: key)
                            }
                        }
                        .toggleStyle(.checkbox)
                        ClashStoredFailure(catalogSwitches, key: key) { failure in
                            Text(verbatim: failure).font(.subheadline).foregroundStyle(.red)
                                .accessibilityIdentifier("configuration-center.rule-editor.catalog.error")
                        }
                    }
                }
            } header: {
                Text(clash: .copy("Rule Sets"))
            }
        }
    }

     
     
     
    @ViewBuilder private func subRulesSections(_ draft: ConfigurationRuleDraft) -> some View {
        if !draft.subRulesEditable {
            Section {
                Text(clash: .copy("These sub-rules can only be changed in the source."))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("configuration-center.rule-editor.sub-rules.source-only")
            }
        } else {
            if presentation == .sheet {
                Section {
                    Button { sheet = .subRuleName(nil) } label: { Text(clash: .copy("Add Sub-rule")) }
                        .disabled(busy)
                        .accessibilityIdentifier("configuration-center.rule-editor.add-sub-rule")
                }
            }
            if draft.subRules.isEmpty {
                Section {
                    Text(clash: .copy("No sub-rules yet. A sub-rule is a named list of rules a rule can hand traffic to."))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("configuration-center.rule-editor.sub-rules.empty")
                }
            }
            ForEach(draft.subRules) { subRule in
                Section {
                     
                     
                    ForEach(Array(subRule.rows.enumerated()), id: \.element.id) { index, row in
                        subRuleRow(row, at: index, in: subRule)
                            .moveDisabled(row.isFinal && index == subRule.rows.count - 1)
                    }
                    .onMove { offsets, destination in
                        mutate { $0.moveSubRuleRows(fromOffsets: offsets, toOffset: destination, in: subRule.id) }
                    }
                     
                     
                    Button { sheet = .subRuleRow(subRule.id, nil) } label: { Text(clash: .copy("Add Rule")) }
                        .disabled(busy)
                        .accessibilityIdentifier("configuration-center.rule-editor.sub-rule.add-rule")
                } header: {
                    subRuleHeader(subRule, used: draft.subRuleUses(of: subRule.name) > 0)
                }
            }
        }
    }

    private func subRuleHeader(_ subRule: ConfigurationRuleDraft.SubRule, used: Bool) -> some View {
        HStack(spacing: ClashTheme.Spacing.compact) {
            Text(verbatim: subRule.name)
             
            if !used { Text(clash: .copy("Unused")).foregroundStyle(.secondary) }
            Spacer(minLength: ClashTheme.Spacing.row)
            Menu {
                Button { sheet = .subRuleName(subRule.id) } label: { Text(clash: .copy("Rename…")) }
                Divider()
                Button(role: .destructive) {
                    try? mutateThrowing { try $0.removeSubRule(subRule.id) }
                } label: {
                    Text(clash: .copy("Delete"))
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(busy)
            .accessibilityIdentifier("configuration-center.rule-editor.sub-rule.menu.\(subRule.id.uuidString)")
        }
    }

    private func subRuleRow(_ row: ConfigurationRuleDraft.Row, at index: Int, in subRule: ConfigurationRuleDraft.SubRule) -> some View {
        let count = subRule.rows.count
         
        let lastMovable = subRule.rows.last?.isFinal == true ? count - 2 : count - 1
        let pinned = row.isFinal && index == count - 1
         
        return Button { sheet = .subRuleRow(subRule.id, row.id) } label: {
            ConfigurationRuleRow(row.raw, ruleSetNames: ruleSetNames)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .contextMenu {
            Button { sheet = .subRuleRow(subRule.id, row.id) } label: { Text(clash: .copy("Edit")) }
            Divider()
            Button { mutate { $0.moveSubRuleRow(row.id, offset: -1, in: subRule.id) } } label: { Text(clash: .copy("Move Up")) }
                .disabled(pinned || index == 0)
            Button { mutate { $0.moveSubRuleRow(row.id, offset: 1, in: subRule.id) } } label: { Text(clash: .copy("Move Down")) }
                .disabled(pinned || index >= lastMovable)
            Divider()
            Button(role: .destructive) { mutate { $0.removeSubRuleRows([row.id], in: subRule.id) } } label: { Text(clash: .copy("Delete")) }
        }
        .accessibilityIdentifier("configuration-center.rule-editor.sub-rule.row.\(row.id.uuidString)")
    }

     

     
     
     
    nonisolated static func installedRuleSets(in draft: ConfigurationRuleDraft) -> Set<String> {
        var keys = Set<String>()
        for row in draft.rows where row.raw.hasPrefix("RULE-SET,") {
            let parts = row.raw.split(separator: ",", maxSplits: 2, omittingEmptySubsequences: false)
            if parts.count == 3 { keys.insert(String(parts[1])) }
        }
        return keys
    }

     
     
     
     
     
    static func groupName(in document: OrderedJSON) -> String? {
        guard case let .string(name)? = document.topLevelValue("name"), !name.isEmpty else { return nil }
        return name
    }

    static func policyCandidates(
        groups: [ConfigurationRuleDraft.Group], nodes: ConfigurationRuleTargetCandidates
    ) -> ConfigurationRuleTargetCandidates {
        let named = ConfigurationRuleTargetCandidates.make(groups: groups.map(\.name), sources: [])
        return ConfigurationRuleTargetCandidates(sections: named.sections + nodes.sections.filter { $0.kind == .source })
    }

    private func mutate(_ change: (inout ConfigurationRuleDraft) -> Void) {
        guard var current = state else { return }
        change(&current.draft)
        state = current
        installedRuleSets = Self.installedRuleSets(in: current.draft)
        edited = true
        error = nil
        saveOnPage()
    }

     
     
    private func mutateThrowing(_ change: (inout ConfigurationRuleDraft) throws -> Void) throws {
        guard var current = state else { return }
        do {
            try change(&current.draft)
            state = current
            installedRuleSets = Self.installedRuleSets(in: current.draft)
            edited = true
            error = nil
            saveOnPage()
        } catch {
            let message = Self.refusal(error, locale: locale)
            self.error = message
            throw ClashMacEditRefusal(message: message)
        }
    }

     
     
    static func refusal(_ error: Error, locale: Locale) -> String {
        if error is ConfigurationSubRuleError { return ClashConfigurationSubRuleCopy.message(error, locale: locale) }
        return ClashConfigurationRuleGroupCopy.message(error, locale: locale)
    }

     
     
     
     
     
     
    private func saveOnPage() {
        guard presentation == .page else { return }
        savesAgain = true
        guard !saving else { return }
        saving = true
        Task { await writeChanges() }
    }

    private func writeChanges() async {
        defer { saving = false }
        while savesAgain, let snapshot = state?.draft {
            savesAgain = false
            do {
                let written = try await actions.save(snapshot)
                baseline = written
                guard var current = state else { return }
                if savesAgain {
                    current.draft = current.draft.continuing(after: written)
                } else {
                    current.draft = written
                    edited = false
                }
                state = current
                installedRuleSets = Self.installedRuleSets(in: current.draft)
                saved()
            } catch {
                savesAgain = false
                let message = Self.refusal(error, locale: locale)
                if let stored = try? await actions.load() { adopt(stored, keepDraft: false) }
                if resetPending {
                     
                    resetPending = false
                    feedback?.say(ClashMacFeedbackSentences.couldNotSave(reason: message, id: Self.resetOperation),
                                  operation: Self.resetOperation)
                } else {
                    self.error = message
                }
                return
            }
        }
        if resetPending {
            resetPending = false
            feedback?.say(ClashMacFeedbackSentences.reset(state?.draft.label ?? "", id: Self.resetOperation),
                          operation: Self.resetOperation)
        }
    }

    static let resetOperation = "rule-editor.reset"

     
     
     
    private func reset() {
        guard let state else { return }
        resetPending = presentation == .page
        do {
            try mutateThrowing { draft in try draft.replaceContents(OrderedJSON.parse(state.resetDocument)) }
        } catch {
             
            resetPending = false
        }
    }

     
     
     
     
    static func isRowAboveFinal(_ row: ConfigurationRuleDraft.Row, in draft: ConfigurationRuleDraft) -> Bool {
        let rows = draft.rows
        guard rows.count >= 2, rows[rows.count - 1].isFinal else { return false }
        return rows[rows.count - 2].id == row.id
    }

    private func moveGroup(_ id: UUID, up: Bool, in draft: ConfigurationRuleDraft) {
        guard let index = draft.groups.firstIndex(where: { $0.id == id }) else { return }
        let target: UUID?
        if up {
            guard index > 0 else { return }
            target = draft.groups[index - 1].id
        } else {
            guard index + 1 < draft.groups.count else { return }
            target = index + 2 < draft.groups.count ? draft.groups[index + 2].id : nil
        }
        mutate { $0.moveGroups([id], before: target) }
    }

     
     
    private func pressCatalog(_ entry: ConfigurationRuleCatalogEntry, key: String, _ on: Bool) {
        catalogSwitches.press(key, on) { on in
            guard on != (state?.draft.containsRuleSet(key) ?? false) else { return }
            guard on else { return mutate { $0.removeRuleSet(key) } }
            let read: ConfigurationRuleSetContent
            do {
                read = try await actions.download(entry.sourceURLString)
            } catch {
                throw ClashMacStoredRefusal(message: ClashErrorCopy.message(error, locale: locale))
            }
            do {
                 
                 
                try mutateThrowing { value in
                    try value.addRuleSet(key: key, name: entry.displayName, rules: read.rules,
                                         defaultRoute: entry.defaultRoute.rawValue, link: read.link, behavior: read.behavior)
                }
            } catch let refusal as ClashMacEditRefusal {
                 
                error = nil
                throw ClashMacStoredRefusal(message: refusal.message)
            }
        }
    }

     

     
     
    private func loadCandidates() async {
        guard let candidates = actions.candidates, let loaded = try? await candidates() else { return }
        nodeCandidates = ConfigurationRuleTargetCandidates(sections: loaded.sections.filter { $0.kind == .source || $0.kind == .providers })
    }

    private func load() async {
        loadError = nil
        do {
            let loaded = try await actions.load()
            adopt(loaded, keepDraft: false)
            openFocus(in: loaded.draft)
        } catch {
            loadError = ClashErrorCopy.message(error, locale: locale)
        }
    }

     
    private func openFocus(in draft: ConfigurationRuleDraft) {
        guard let focus else { return }
        self.focus = nil
        switch focus {
        case .group(let name):
            if let group = draft.groups.first(where: { $0.name == name }) { sheet = .group(group.id) }
        case .ruleSet(let name):
            sheet = .ruleSet(name)
        }
    }

     
     
     
    private func adopt(_ next: ClashMacRuleEditorState, keepDraft: Bool) {
        if keepDraft, var current = state {
             
             
             
             
            let rebased = current.draft.rebased(onto: next.draft)
            current.draft = rebased.draft
            current.localSets = next.localSets
            current.resetDocument = next.resetDocument
            state = current
            baseline = next.draft
            installedRuleSets = Self.installedRuleSets(in: rebased.draft)
            if !rebased.droppedRuleSets.isEmpty {
                let names = rebased.droppedRuleSets.map { key in
                    next.localSets.first { "local-" + $0.id == key }?.name ?? key
                }
                error = ClashCopy.format("Rules on removed rule sets were left out: %@", locale: locale, names.joined(separator: ", "))
            }
        } else {
            state = next
            installedRuleSets = Self.installedRuleSets(in: next.draft)
            baseline = next.draft
            edited = false
        }
    }

    private func save() {
        guard state != nil, dirty, !busy else { return }
        Task {
            await run {
                 
                 
                 
                 
                await catalogSwitches.waitForWrites()
                guard let state else { return }
                let reloaded = try await actions.save(state.draft)
                var current = state
                current.draft = reloaded
                self.state = current
                installedRuleSets = Self.installedRuleSets(in: reloaded)
                baseline = reloaded
                edited = false
                saved()
                 
                 
                 
                 
                dismiss()
            }
        }
    }

    @discardableResult
    private func run(_ operation: () async throws -> Void) async -> Bool {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await operation()
            return true
        } catch {
            self.error = ClashErrorCopy.message(error, locale: locale)
            return false
        }
    }

     
    private func runThrowing(_ operation: () async throws -> Void) async throws {
        busy = true
        error = nil
        defer { busy = false }
        try await operation()
    }
}

 

 
 
 
 
 
 
struct ClashMacRuleRowEditor: View {
    let draft: ConfigurationRuleDraft
     
     
     
    let nodeCandidates: ConfigurationRuleTargetCandidates
    let rowID: UUID?
     
     
     
    let subRuleID: UUID?
     
    var hasSwitches = true
     
     
     
     
    var judgesRuleSets = true
     
     
     
     
     
    let createGroup: ((OrderedJSON) throws -> Void)?
     
     
     
    let geoValues: ClashMacGeoValueLoader?
    let commit: (String, Bool, String) -> Void
    let close: () -> Void
    @Environment(\.locale) private var locale
    @Environment(\.configurationFieldCopy) private var copy
    @Environment(\.clashMacEditorSyntax) private var syntax
    @State private var raw: String
    @State private var enabled: Bool
    @State private var note: String
    @State private var action: ClashStructuredRule.Action
    @State private var content: String
    @State private var target: String
     
     
     
    @State private var src: Bool
    @State private var noResolve: Bool
    @State private var additionalParams: [String]
     
     
     
    @State private var structured: Bool
    @State private var pickingTarget = false
    @State private var addingGroup = false
    @State private var pickingGeo = false
    @State private var pickedFrom: ClashMacGeoResource?
     
    @State private var pickingRuleSet = false
     
     
    @State private var lastAction: ClashStructuredRule.Action
     
     
    private let openedAction: ClashStructuredRule.Action?
     
     
     
     
    private let ruleSets: [String]

    init(draft: ConfigurationRuleDraft, rowID: UUID?, subRuleID: UUID? = nil, hasSwitches: Bool = true,
         judgesRuleSets: Bool = true,
         nodeCandidates: ConfigurationRuleTargetCandidates = .init(sections: []),
         createGroup: ((OrderedJSON) throws -> Void)? = nil,
         geoValues: ClashMacGeoValueLoader? = nil,
         commit: @escaping (String, Bool, String) -> Void, close: @escaping () -> Void) {
        self.draft = draft
        self.nodeCandidates = nodeCandidates
        self.rowID = rowID
        self.subRuleID = subRuleID
        self.hasSwitches = hasSwitches
        self.judgesRuleSets = judgesRuleSets
        self.createGroup = createGroup
        self.geoValues = geoValues
        self.commit = commit
        self.close = close
        let rows = subRuleID.flatMap { id in draft.subRules.first { $0.id == id }?.rows } ?? draft.rows
        let row = rowID.flatMap { id in rows.first { $0.id == id } }
        _raw = State(initialValue: row?.raw ?? "")
        _enabled = State(initialValue: row.map { draft.isEnabled($0.raw) } ?? true)
        _note = State(initialValue: row.map { draft.note(for: $0.raw) } ?? "")
        let parsed = row.flatMap { ClashStructuredRule.parse($0.raw) }
        _action = State(initialValue: parsed?.action ?? .domainSuffix)
        _lastAction = State(initialValue: parsed?.action ?? .domainSuffix)
        openedAction = parsed?.action
        ruleSets = draft.ruleSetNames
        _content = State(initialValue: parsed?.content ?? "")
        _target = State(initialValue: parsed?.target ?? "DIRECT")
        _src = State(initialValue: parsed?.src ?? false)
        _noResolve = State(initialValue: parsed?.noResolve ?? false)
        _additionalParams = State(initialValue: parsed?.additionalParams ?? [])
        _structured = State(initialValue: Self.opensStructured(row?.raw))
    }

     
     
    private func optionName(_ option: String) -> String {
        copy.ruleOptionName(option, language: ConfigurationFieldCopy.Language(locale: locale)) ?? option
    }

     
     
     
     
     
     
     
     
     
     
    static func offeredActions(_ syntax: ClashMacEditorSyntax?, keeping: ClashStructuredRule.Action? = nil,
                               lines: Bool = false, ruleSets: [String]? = nil,
                               alsoKeeping: ClashStructuredRule.Action? = nil) -> [ClashStructuredRule.Action] {
         
         
        let available = ClashStructuredRule.availableActions(for: .macosPacketTunnel)
        var offered: [ClashStructuredRule.Action]
        if let syntax, !syntax.ruleTypes.isEmpty {
            offered = syntax.ruleTypes.filter(\.matchesHere).compactMap { ClashStructuredRule.Action(rawValue: $0.name) }
                .filter(available.contains)
        } else {
            offered = available
        }
        if lines { offered = offered.filter { !ClashStructuredRule.refusedInARuleSet.contains($0) } }
        if let ruleSets {
            let unoffered = ClashRulePolicyOptions(ruleSets: ruleSets, ruleSetsAreKnown: true).unofferedKinds
            offered = offered.filter { !unoffered.contains($0) }
        }
        for kept in [keeping, alsoKeeping].compactMap({ $0 }) where !offered.contains(kept) { offered.append(kept) }
        return offered
    }

     
     
     
     
     
     
    static func opensStructured(_ raw: String?) -> Bool {
        guard let raw else { return true }
        return ClashStructuredRule.parse(raw) != nil && ClashStructuredRule.builderWritesBack(raw)
    }

     
     
    static func options(of action: ClashStructuredRule.Action, in syntax: ClashMacEditorSyntax?) -> [String] {
        syntax?.ruleTypes.first { $0.name == action.rawValue }?.options ?? []
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private var candidates: ConfigurationRuleTargetCandidates {
         
         
        if action == .subRule {
            let names = draft.subRules.filter { $0.id != subRuleID }.map(\.name)
            return ConfigurationRuleTargetCandidates(sections: names.isEmpty ? [] : [
                .init(id: "sub-rules", kind: .source, sourceLabel: ClashCopy.string("Sub-rules", locale: locale), names: names)
            ])
        }
        return ClashMacRuleEditorSheet.policyCandidates(groups: draft.groups, nodes: nodeCandidates)
    }


     
     
    private var knownRuleSets: [String]? { judgesRuleSets ? ruleSets : nil }

    private var assembled: String {
        ClashStructuredRule(
            action: action,
            content: action.needsContent ? content.trimmingCharacters(in: .whitespaces) : "",
            target: target,
            noResolve: noResolve,
            src: src,
            additionalParams: additionalParams
        ).rawValue
    }

     
     
     
    private var canSave: Bool {
        !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!structured || !action.needsContent || !content.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        ClashMacSheetFrame(
            title: rowID == nil ? .copy("Add Rule") : .copy("Rule"),
            width: 560,
            height: pickingGeo ? 520 : (structured ? 480 : 340)
        ) {
            if pickingGeo, let resource = action.clashMacGeoResource, let geoValues {
                ClashMacGeoValuePickerPage(
                    resource: resource, current: content, load: geoValues,
                    identifier: "configuration-center.rule-editor.rule.geo"
                ) { picked in
                    content = picked
                    pickedFrom = resource
                    pickingGeo = false
                }
            } else if pickingRuleSet {
                ClashMacTargetPickerPage(
                    candidates: ConfigurationRuleTargetCandidates(sections: [
                        .init(id: "rule-sets", kind: .source, sourceLabel: ClashCopy.string("Rule Sets", locale: locale), names: ruleSets)
                    ]),
                    current: content,
                    identifier: "configuration-center.rule-editor.rule.rule-set"
                ) { picked in
                    content = picked
                    pickingRuleSet = false
                }
            } else if pickingTarget {
                ClashMacTargetPickerPage(
                    candidates: candidates, current: target,
                    identifier: "configuration-center.rule-editor.rule.target",
                     
                     
                     
                    addGroup: createGroup == nil || action == .subRule ? nil : { addingGroup = true }
                ) { picked in
                    target = picked
                    pickingTarget = false
                }
            } else {
            ClashMacSheetForm {
                if structured {
                    Section {
                        Picker(selection: $action) {
                            ForEach(Self.offeredActions(syntax, keeping: action, ruleSets: knownRuleSets, alsoKeeping: openedAction), id: \.self) { item in
                                Text(verbatim: ConfigurationRuleWords.kindName(item.rawValue, locale: locale, copy: copy)).tag(item)
                            }
                        } label: {
                            Text(clash: .copy("Rule Type"))
                        }
                        .accessibilityIdentifier("configuration-center.rule-editor.rule.action")
                        if action == .ruleSet, let knownRuleSets, !knownRuleSets.isEmpty {
                             
                            ClashMacTargetRow(title: .copy("Rule Set"), value: content,
                                              identifier: "configuration-center.rule-editor.rule.rule-set") {
                                pickingRuleSet = true
                            }
                        } else if let resource = action.clashMacGeoResource, geoValues != nil {
                            ClashMacGeoValueRow(
                                resource: resource, value: content,
                                identifier: "configuration-center.rule-editor.rule.geo"
                            ) { pickingGeo = true }
                        } else if action.needsContent {
                             
                             
                            LabeledContent {
                                TextField(text: $content, prompt: Text(verbatim: action.contentPlaceholder)) { Text(clash: .copy(action.contentLabel)) }
                                    .labelsHidden()
                                    .font(.body.monospaced())
                                    .multilineTextAlignment(.trailing)
                                    .accessibilityIdentifier("configuration-center.rule-editor.rule.content")
                            } label: {
                                 
                                 
                                 
                                 
                                Text(clash: .copy(action.contentLabel))
                            }
                        }
                        ClashMacTargetRow(title: .copy("Target"), value: target, identifier: "configuration-center.rule-editor.rule.target") {
                            pickingTarget = true
                        }
                         
                         
                        let options = Self.options(of: action, in: syntax)
                        if options.contains("no-resolve") {
                            Toggle(isOn: $noResolve) { Text(verbatim: optionName("no-resolve")) }
                                .accessibilityIdentifier("configuration-center.rule-editor.rule.no-resolve")
                        }
                        if options.contains("src") {
                            Toggle(isOn: $src) { Text(verbatim: optionName("src")) }
                                .accessibilityIdentifier("configuration-center.rule-editor.rule.src")
                        }
                    }
                    .onChange(of: action) { changed in
                         
                         
                         
                        if pickedFrom != nil, changed.clashMacGeoResource != pickedFrom { content = ""; pickedFrom = nil }
                         
                         
                        content = ClashRulePolicyOptions.value(content, from: lastAction, to: changed, ruleSets: knownRuleSets)
                        lastAction = changed
                    }
                }
                Section {
                     
                     
                    if !structured {
                        TextField(text: $raw, prompt: Text(verbatim: "DOMAIN-SUFFIX,example.com,DIRECT")) { Text(clash: .copy("Rule")) }
                            .font(.body.monospaced())
                            .accessibilityIdentifier("configuration-center.rule-editor.rule.raw")
                    }
                    if subRuleID == nil && hasSwitches {
                        Toggle(isOn: $enabled) { Text(clash: .copy("Enabled")) }
                            .accessibilityIdentifier("configuration-center.rule-editor.rule.enabled")
                        TextField(text: $note, prompt: Text(clash: .copy("Comment"))) { Text(clash: .copy("Comment")) }
                            .accessibilityIdentifier("configuration-center.rule-editor.rule.comment")
                    }
                } footer: {
                    if structured, !raw.isEmpty {
                        Text(clash: .format("Written as %@ in the configuration file", [raw]))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .accessibilityIdentifier("configuration-center.rule-editor.rule.written-as")
                    }
                }
            }
            .accessibilityIdentifier("configuration-center.rule-editor.rule-sheet")
            }
        } leading: {
            if pickingGeo {
                Button { pickingGeo = false } label: { Text(clash: .copy("Back")) }
                    .accessibilityIdentifier("configuration-center.rule-editor.rule.geo.back")
            } else if pickingTarget {
                Button { pickingTarget = false } label: { Text(clash: .copy("Back")) }
                    .accessibilityIdentifier("configuration-center.rule-editor.rule.target.back")
            } else if pickingRuleSet {
                Button { pickingRuleSet = false } label: { Text(clash: .copy("Back")) }
                    .accessibilityIdentifier("configuration-center.rule-editor.rule.rule-set.back")
            }
        } trailing: {
            if !pickingGeo {
            ClashMacSheetButtons(
                closeIdentifier: "configuration-center.rule-editor.rule.cancel",
                primaryTitle: .copy("Done"),
                primaryIdentifier: "configuration-center.rule-editor.rule.done",
                primaryDisabled: !canSave,
                onClose: close,
                onPrimary: { commit(raw.trimmingCharacters(in: .whitespacesAndNewlines), enabled, note); close() }
            )
            }
        }
         
         
         
        .onAppear { if rowID == nil { raw = assembled } }
         
         
         
         
        .onChange(of: assembled) { value in if structured { raw = value } }
         
         
         
        .sheet(isPresented: $addingGroup) {
            ClashMacRuleGroupEditor(
                group: nil, all: draft.groups, nodeCandidates: nodeCandidates,
                commit: { document in
                    try createGroup?(document)
                    if let name = ClashMacRuleEditorSheet.groupName(in: document) {
                        target = name
                        pickingTarget = false
                    }
                },
                close: { addingGroup = false }
            )
        }
    }
}

 
 
 
 
 
 
 
 
 
 
struct ClashMacRuleGroupEditor: View {
    let group: ConfigurationRuleDraft.Group?
    let all: [ConfigurationRuleDraft.Group]
     
     
    let nodeCandidates: ConfigurationRuleTargetCandidates
    let commit: (OrderedJSON) throws -> Void
    let close: () -> Void
     
    @State private var addingMembers = false
     
    @State private var addingProviders = false
     
     
    @State private var listingAllMembers = false
     
    @State private var visitProviders: [String]?
     
     
    @State private var visitMembers: [String]?
    @State private var name: String
    @State private var icon: String
    @State private var kind: String
    @State private var selected: [String]
    @State private var includeAll: Bool
    @State private var filter: String
     
     
     
    @State private var providers: [String]
     
    @State private var includeAllKey: String
    @State private var error: String?
     
     
    @State private var extra: OrderedJSON
     
    @State private var editingField: ClashMacKeyEdit?
    @Environment(\.clashMacEditorSyntax) private var syntax
    @Environment(\.locale) private var locale
    @Environment(\.configurationFieldCopy) private var copy

    init(group: ConfigurationRuleDraft.Group?, all: [ConfigurationRuleDraft.Group], nodeCandidates: ConfigurationRuleTargetCandidates = .init(sections: []),
         commit: @escaping (OrderedJSON) throws -> Void, close: @escaping () -> Void) {
        self.group = group
        self.nodeCandidates = nodeCandidates
        self.all = all
        self.commit = commit
        self.close = close
        _extra = State(initialValue: group?.document ?? .object([]))
        let seed = Self.fields(of: group)
        _name = State(initialValue: seed.name)
        _icon = State(initialValue: seed.icon)
        _kind = State(initialValue: seed.kind)
        _selected = State(initialValue: seed.selected)
        _includeAll = State(initialValue: seed.includeAll)
        _filter = State(initialValue: seed.filter)
        _providers = State(initialValue: seed.providers)
        _includeAllKey = State(initialValue: seed.includeAllKey)
    }

    struct Fields: Equatable {
        var name = ""
        var kind = "select"
        var selected: [String] = []
        var includeAll = false
        var filter = ""
         
        var icon = ""
         
        var providers: [String] = []
         
         
         
         
         
         
        var includeAllKey = "include-all"
    }

     
    static func fields(of group: ConfigurationRuleDraft.Group?) -> Fields {
        guard let group else { return Fields() }
        var fields = Fields(name: group.name, kind: group.type)
        if case .array(let values) = group.document.topLevelValue("proxies") {
            fields.selected = values.compactMap { if case .string(let value) = $0 { return value }; return nil }
        }
         
        let includeKeys = ["include-all", "include-all-proxies"]
        fields.includeAllKey = includeKeys.first { group.document.topLevelValue($0) == .scalar("true") }
            ?? includeKeys.first { group.document.topLevelValue($0) != nil }
            ?? "include-all"
        fields.includeAll = group.document.topLevelValue(fields.includeAllKey) == .scalar("true")
        if case .string(let value) = group.document.topLevelValue("filter") { fields.filter = value }
        fields.icon = ClashTowerGroupIcon.read(group.document)
        if case .array(let values) = group.document.topLevelValue("use") {
            fields.providers = values.compactMap { if case .string(let value) = $0 { return value }; return nil }
        }
        return fields
    }

     
     
     
     
     
     
     
     
     
     
     
     
    static func document(base: OrderedJSON?, fields: Fields) -> OrderedJSON {
        var document = (base ?? .object([])).settingTopLevel("name", to: .string(fields.name))
         
        document = ClashTowerGroupIcon.apply(fields.icon, to: document)
        document = document.settingTopLevel("type", to: .string(fields.kind))
         
         
        if !fields.selected.isEmpty || base?.topLevelValue("proxies") != nil {
            document = document.settingTopLevel("proxies", to: .array(fields.selected.map(OrderedJSON.string)))
        }
         
         
         
        if fields.includeAll || base?.topLevelValue(fields.includeAllKey) != nil {
            document = document.settingTopLevel(fields.includeAllKey, to: .scalar(fields.includeAll ? "true" : "false"))
        }
         
         
        if !fields.filter.isEmpty || base?.topLevelValue("filter") != nil {
            document = document.settingTopLevel("filter", to: .string(fields.filter))
        }
         
         
         
        if !fields.includeAll {
            for other in ["include-all", "include-all-proxies"] where other != fields.includeAllKey && document.topLevelValue(other) != nil {
                document = document.settingTopLevel(other, to: .scalar("false"))
            }
        }
         
         
        document = fields.providers.isEmpty ? document.removingTopLevel("use")
            : document.settingTopLevel("use", to: .array(fields.providers.map(OrderedJSON.string)))
         
         
         
         
         
         
        if fields.kind == "url-test" || fields.kind == "fallback", !fields.providers.isEmpty,
           document.topLevelValue("url") == nil {
            document = document.settingTopLevel("url", to: .string("https://www.gstatic.com/generate_204"))
            if document.topLevelValue("interval") == nil { document = document.settingTopLevel("interval", to: .scalar("300")) }
        }
        return document
    }

     
    static let formKeys: Set<String> = ["name", "type", "proxies", "include-all", "include-all-proxies", "filter", "icon", "use"]

     
    static func hasMembers(_ fields: Fields) -> Bool { !fields.selected.isEmpty || fields.includeAll || !fields.providers.isEmpty }
     
    static func keepsOne(_ fields: Fields) -> Bool { !fields.includeAll && fields.providers.isEmpty }

    private var fields: Fields { Fields(name: name, kind: kind, selected: selected, includeAll: includeAll, filter: filter, icon: icon, providers: providers, includeAllKey: includeAllKey) }
    private var dirty: Bool { fields != Self.fields(of: group) || extra != (group?.document ?? .object([])) }
    private var canCommit: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && Self.hasMembers(fields) }
     
     
     
    private var kinds: [String] {
        let offered = syntax.flatMap { $0.groupTypes.isEmpty ? nil : $0.groupTypes } ?? ["select", "url-test", "fallback"]
        var seen = Set<String>()
        return (offered + [group?.type ?? "select"]).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

     
     
    private func kindName(_ kind: String) -> String {
        let typeField = syntax?.fields?.fields.first { $0.path.hasPrefix("proxy-groups[") && $0.path.hasSuffix("].type") }
        return copy.valueLabel(kind, for: typeField, locale: locale) ?? kind
    }

     
     
     
     
    private var catalogFields: [ConfigurationField] {
        guard let catalog = syntax?.fields else { return [] }
        return Self.otherFields(of: Self.document(base: extra, fields: fields), in: catalog)
    }

     
     
     
     
    static func arrangedFields(_ fields: [ConfigurationField], kind: String, copy: ConfigurationFieldCopy,
                               locale: Locale) -> [(section: ConfigurationFieldCopy.ArrangedSection, fields: [ConfigurationField])] {
        let layout = copy.layout(forPath: "proxy-groups[\(kind)]", locale: locale) ?? []
        let byKey = Dictionary(fields.map { (key(of: $0), $0) }, uniquingKeysWith: { first, _ in first })
        return ConfigurationFieldCopy.arrange(fields.map { key(of: $0) }, in: layout).map { section in
            (section, section.keys.compactMap { byKey[$0] })
        }
    }

     
     
    private static let formSections: Set<String> = ["basic", "members"]

     
    static func otherFields(of group: OrderedJSON, in catalog: ConfigurationFieldCatalog) -> [ConfigurationField] {
        let probe = OrderedJSON.object([("proxy-groups", .array([group]))])
        return catalog.children(of: [.key("proxy-groups"), .index(0)], in: probe)
            .filter { !formKeys.contains(key(of: $0)) }
    }

    private static func key(of field: ConfigurationField) -> String {
        field.path.split(separator: ".").last.map(String.init) ?? field.path
    }

    private static func token(_ value: OrderedJSON) -> String? {
        switch value {
        case .string(let text): return text
        case .scalar(let token): return token
        default: return nil
        }
    }

     
    private func defaultLine(_ field: ConfigurationField) -> ClashDisplayText {
        ClashMacValueWords.defaultLine(field, locale: locale, copy: copy)
    }

     
     
    @ViewBuilder
    private func catalogRow(_ field: ConfigurationField) -> some View {
        let key = Self.key(of: field)
        let value = extra.topLevelValue(key)
        let control = ClashMacFieldControl.make(field, value: value) { _ in options }
        switch control {
        case .toggle?:
            Toggle(isOn: Binding(
                get: { value.flatMap(Self.token).map { $0 == "true" } ?? field.defaultFlag },
                set: { extra = extra.settingTopLevel(key, to: .scalar($0 ? "true" : "false")) }
            )) { Text(verbatim: copy.title(for: field, key: key, locale: locale)) }
            .toggleStyle(.switch)
            .accessibilityIdentifier("configuration-center.rule-editor.group.field.toggle")
        case .number(_, _, let unit?, _)? where ClashMacTimeMenuRow<EmptyView>.unit(of: control, field: field) != nil:
             
             
            ClashMacTimeMenuRow(field: field, unit: unit, value: value, offersDefault: true, defaultLine: defaultLine(field),
                               identifier: "configuration-center.rule-editor.group.field.time",
                               write: { new in extra = new.map { extra.settingTopLevel(key, to: $0) } ?? extra.removingTopLevel(key) },
                               custom: { editingField = Self.sheetEdit(key: key, value: value, control: control, field: field) }) {
                Text(verbatim: copy.title(for: field, key: key, locale: locale))
            }
        case .choose(let values, let caseInsensitive)?:
            let draft = ClashMacFieldDraft(control: .choose(values, caseInsensitive: caseInsensitive), value: value)
            Picker(selection: Binding<String?>(
                get: { value == nil ? nil : draft.text },
                set: { chosen in extra = chosen.map { extra.settingTopLevel(key, to: .string($0)) } ?? extra.removingTopLevel(key) }
            )) {
                Text(clash: defaultLine(field)).tag(String?.none)
                ForEach(draft.options, id: \.self) {
                    Text(verbatim: copy.valueLabel($0, for: field, locale: locale) ?? $0).tag(String?.some($0))
                }
            } label: { Text(verbatim: copy.title(for: field, key: key, locale: locale)) }
            .pickerStyle(.menu)
            .accessibilityIdentifier("configuration-center.rule-editor.group.field.choice")
        default:
            LabeledContent {
                Button {
                    editingField = Self.sheetEdit(key: key, value: value, control: control, field: field)
                } label: {
                    Text(clash: ConfigurationValueWords.summary(value, field: field, locale: locale, copy: copy))
                }
                .accessibilityIdentifier("configuration-center.rule-editor.group.field.edit")
            } label: {
                Text(verbatim: copy.title(for: field, key: key, locale: locale))
            }
        }
    }
     
    static func sheetEdit(key: String, value: OrderedJSON?, control: ClashMacFieldControl?, field: ConfigurationField) -> ClashMacKeyEdit {
        ClashMacKeyEdit(path: [key], value: value, platformReason: nil,
                       choices: nil, control: control, removable: value != nil, isDefault: value == nil, field: field)
    }

    private var options: [String] {
        var seen = Set<String>()
        return (["DIRECT", "REJECT"] + all.filter { $0.id != group?.id }.map(\.name) + selected).filter { seen.insert($0).inserted }
    }
     
     
    private var shownMembers: [String] {
        guard let seen = visitMembers else { return selected }
        return seen + selected.filter { !seen.contains($0) }
    }

     
     
    private var memberCandidates: ConfigurationRuleTargetCandidates {
        var sections = [ConfigurationRuleTargetCandidates.Section(id: "builtin", kind: .builtin, names: ["DIRECT", "REJECT"])]
        let groups = all.filter { $0.id != group?.id }.map(\.name)
        if !groups.isEmpty { sections.append(.init(id: "groups", kind: .groups, names: groups)) }
        return ConfigurationRuleTargetCandidates(sections: sections + nodeCandidates.sections.filter { $0.kind == .source })
    }

     
     
    private var providerCandidates: ConfigurationRuleTargetCandidates {
        ConfigurationRuleTargetCandidates(sections: nodeCandidates.sections.filter { $0.kind == .providers })
    }

    private var shownProviders: [String] {
        guard let seen = visitProviders else { return providers }
        return seen + providers.filter { !seen.contains($0) }
    }

     
     
     
    private func setMember(_ item: String, on: Bool, shown: [String]) {
        if visitMembers == nil { visitMembers = shown }
        selected = Self.switchMember(item, on: on, shown: shown, selected: selected, keepsOne: Self.keepsOne(fields))
    }

     
    private func setProvider(_ item: String, on: Bool, shown: [String]) {
        if visitProviders == nil { visitProviders = shown }
        providers = Self.switchMember(item, on: on, shown: shown, selected: providers, keepsOne: false)
    }

     
     
    static func switchMember(_ item: String, on: Bool, shown: [String], selected: [String], keepsOne: Bool) -> [String] {
        var next = selected
        if on {
            guard !next.contains(item) else { return next }
            let before = shown.prefix { $0 != item }.filter { next.contains($0) }.count
            next.insert(item, at: min(before, next.count))
        } else {
            guard next.count > 1 || !keepsOne else { return next }
            next.removeAll { $0 == item }
        }
        return next
    }

     
     
     
     
     
    static let membersShownAtMost = 30

     
    private func memberRow(_ item: String, shown: [String]) -> some View {
        HStack(spacing: ClashTheme.Spacing.compact) {
            Toggle(isOn: Binding(get: { selected.contains(item) }, set: { on in setMember(item, on: on, shown: shown) })) {
                Text(verbatim: item).lineLimit(1)
            }
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("configuration-center.rule-editor.group.member")
            Spacer()
            if let index = selected.firstIndex(of: item) {
                Button { move(item, by: -1) } label: { Image(systemName: "chevron.up") }
                    .disabled(index == 0)
                    .accessibilityLabel(Text(clash: .copy("Move Up")))
                    .accessibilityIdentifier("configuration-center.rule-editor.group.up")
                Button { move(item, by: 1) } label: { Image(systemName: "chevron.down") }
                    .disabled(index == selected.count - 1)
                    .accessibilityLabel(Text(clash: .copy("Move Down")))
                    .accessibilityIdentifier("configuration-center.rule-editor.group.down")
            }
        }
        .buttonStyle(.borderless)
    }

    var body: some View {
        ClashMacSheetFrame(
            title: group == nil ? .copy("Add Group") : .copy("Group"),
            subtitle: .copy("Policy Groups"),
            width: 560, height: 640
        ) {
            if listingAllMembers {
                let shown = shownMembers
                List {
                    ForEach(shown, id: \.self) { memberRow($0, shown: shown) }
                }
                .listStyle(.inset)
                .accessibilityIdentifier("configuration-center.rule-editor.group.members.all.list")
            } else if addingMembers {
                ClashMacMemberChecklist(candidates: memberCandidates, selected: $selected, keepsOne: Self.keepsOne(fields),
                                       identifier: "configuration-center.rule-editor.group.members")
            } else if addingProviders {
                ClashMacMemberChecklist(candidates: providerCandidates, selected: $providers, keepsOne: false,
                                       identifier: "configuration-center.rule-editor.group.providers")
            } else {
            ClashMacSheetForm {
                let arranged = Self.arrangedFields(catalogFields, kind: kind, copy: copy, locale: locale)
                 
                Section {
                    TextField(text: $name, prompt: Text(clash: .copy("e.g. 🎬 Netflix"))) { Text(clash: .copy("Group Name")) }
                        .accessibilityIdentifier("configuration-center.rule-editor.group.name")
                    TextField(text: $icon, prompt: Text(verbatim: "https://…")) { Text(clash: .copy("Icon URL")) }
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("configuration-center.rule-editor.group.icon")
                     
                     
                     
                     
                    if let echo = ClashTowerGroupIconEcho.of(icon) {
                        LabeledContent {
                            switch echo {
                            case .emoji(let emoji): Text(verbatim: emoji)
                            case .symbol(let symbol): Image(systemName: symbol.drawableName)
                            case .image(let host): Text(verbatim: host)
                            case .nothingDraws: EmptyView()
                            }
                        } label: {
                            Text(clash: .copy(echo.label))
                                .foregroundStyle(echo == .nothingDraws ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                        }
                        .font(.footnote)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("configuration-center.rule-editor.group.icon.echo")
                    }
                    Picker(selection: $kind) {
                        ForEach(kinds, id: \.self) { Text(verbatim: kindName($0)).tag($0) }
                    } label: {
                        Text(clash: .copy("Group Type"))
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("configuration-center.rule-editor.group.type")
                     
                    ForEach(arranged.first { $0.section.id == "basic" }?.fields ?? [], id: \.path) { field in catalogRow(field) }
                } footer: {
                    Text(clash: .copy("Changing the group type changes how routes are chosen."))
                }
                Section {
                    let shown = shownMembers
                    if shown.isEmpty {
                        Text(clash: .copy("Nothing added yet.")).foregroundStyle(.secondary)
                            .accessibilityIdentifier("configuration-center.rule-editor.group.members.empty")
                    }
                     
                     
                     
                     
                    ForEach(shown.prefix(Self.membersShownAtMost), id: \.self) { memberRow($0, shown: shown) }
                    if shown.count > Self.membersShownAtMost {
                        Button { listingAllMembers = true } label: {
                            Text(clash: .format("All %@", [shown.count.formatted(.number.locale(locale))]))
                        }
                        .accessibilityIdentifier("configuration-center.rule-editor.group.members.all")
                    }
                     
                     
                    Button { addingMembers = true } label: { Text(clash: .copy("Add Members…")) }
                        .accessibilityIdentifier("configuration-center.rule-editor.group.add-members")
                } header: {
                    Text(clash: .copy("Members"))
                }
                 
                 
                 
                 
                if !providerCandidates.sections.isEmpty || !providers.isEmpty {
                    Section {
                        let shown = shownProviders
                        ForEach(shown, id: \.self) { item in
                            Toggle(isOn: Binding(get: { providers.contains(item) }, set: { on in setProvider(item, on: on, shown: shown) })) {
                                Text(verbatim: item).lineLimit(1)
                            }
                            .toggleStyle(.checkbox)
                            .accessibilityIdentifier("configuration-center.rule-editor.group.provider")
                        }
                        Button { addingProviders = true } label: { Text(clash: .copy("Add Proxy Providers…")) }
                            .accessibilityIdentifier("configuration-center.rule-editor.group.add-providers")
                    } header: {
                        Text(clash: .copy("Proxy Providers (Configuration Chapter)"))
                    } footer: {
                        Text(clash: .copy("Their nodes join the group."))
                    }
                }
                Section {
                    Toggle(isOn: $includeAll) { Text(clash: .copy("Include all proxies")) }
                        .accessibilityIdentifier("configuration-center.rule-editor.group.include-all")
                    TextField(text: $filter, prompt: Text(verbatim: "(HK|SG)")) { Text(clash: .copy("Include filter")) }
                        .accessibilityIdentifier("configuration-center.rule-editor.group.filter")
                     
                    ForEach(arranged.first { $0.section.id == "members" }?.fields ?? [], id: \.path) { field in catalogRow(field) }
                } header: {
                    Text(clash: .copy("Node Name Match"))
                }
                 
                 
                ForEach(arranged.filter { !Self.formSections.contains($0.section.id) }, id: \.section.id) { entry in
                    Section {
                        ForEach(entry.fields, id: \.path) { field in catalogRow(field) }
                    } header: {
                        if let title = entry.section.title { Text(clash: title) }
                    } footer: {
                        if let footer = entry.section.footer { Text(verbatim: footer) }
                    }
                }
                if let error {
                    Section {
                        Text(verbatim: error).foregroundStyle(.red)
                            .accessibilityIdentifier("configuration-center.rule-editor.group.error")
                    }
                }
            }
            }
        } leading: {
            if listingAllMembers {
                Button { listingAllMembers = false } label: { Text(clash: .copy("Back")) }
                    .accessibilityIdentifier("configuration-center.rule-editor.group.members.all.back")
            } else if addingMembers {
                Button { addingMembers = false } label: { Text(clash: .copy("Back")) }
                    .accessibilityIdentifier("configuration-center.rule-editor.group.members.back")
            } else if addingProviders {
                Button { addingProviders = false } label: { Text(clash: .copy("Back")) }
                    .accessibilityIdentifier("configuration-center.rule-editor.group.providers.back")
            }
        } trailing: {
            ClashMacSheetButtons(
                closeIdentifier: "configuration-center.rule-editor.group.cancel",
                primaryTitle: .copy("Done"),
                primaryIdentifier: "configuration-center.rule-editor.group.done",
                primaryDisabled: !canCommit || !dirty,
                onClose: close,
                onPrimary: {
                    do {
                        try commit(Self.document(base: extra, fields: fields))
                        close()
                    } catch {
                        self.error = ClashErrorCopy.message(error, locale: locale)
                    }
                }
            )
        }
         
         
        .onChange(of: kind) { newKind in
            extra = extra.settingTopLevel("type", to: .string(newKind))
        }
        .sheet(item: $editingField) { edit in
            ClashMacValueEditSheet(edit: edit, save: { value in
                extra = extra.settingTopLevel(edit.path[0], to: value)
            }, useDefault: edit.removable ? { extra = extra.removingTopLevel(edit.path[0]) } : nil)
        }
    }

    private func move(_ item: String, by offset: Int) {
        guard let index = selected.firstIndex(of: item) else { return }
        let target = index + offset
        guard selected.indices.contains(target) else { return }
        selected.swapAt(index, target)
    }
}

 
struct ClashMacLocalRuleSetEditor: View {
     
     
     
    enum Kind: Hashable { case link, manual }

     
     
     
    struct Line: Identifiable, Equatable {
        let id = UUID()
        var raw: String
         
         
         
         
         
         
         
        var action: ClashStructuredRule.Action? {
            let head = raw.split(separator: ",", maxSplits: 1).first ?? ""
            return ClashStructuredRule.Action(
                rawValue: head.trimmingCharacters(in: .whitespaces).uppercased()
            )
        }
        var value: String {
            let parts = raw.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
            return parts.count > 1 ? String(parts[1]) : ""
        }
    }

    let value: ConfigurationLocalRuleSet?
    let candidates: ConfigurationRuleTargetCandidates
    let geoValues: ClashMacGeoValueLoader?
    let download: @MainActor (String) async throws -> ConfigurationRuleSetContent
     
    let save: (ConfigurationLocalRuleSet, String) async throws -> Void
    let close: () -> Void
    @Environment(\.clashMacEditorSyntax) private var syntax
    @Environment(\.locale) private var locale
    @Environment(\.configurationFieldCopy) private var copy
    @State private var name: String
    @State private var link: String
    @State private var lines: [Line]
    @State private var kind: Kind
    @State private var policy: String
    @State private var pickingPolicy = false
     
     
    @State private var addingLine = false
     
     
     
     
     
     
    static let lineActions: [ClashStructuredRule.Action] =
        ClashStructuredRule.availableActions(for: .macosPacketTunnel).filter { !ClashStructuredRule.refusedInARuleSet.contains($0) }

    @State private var lineAction: ClashStructuredRule.Action = .domainSuffix
    @State private var lineContent = ""
    @State private var pickingGeo = false
    @State private var pickedFrom: ClashMacGeoResource?
    @State private var busy = false
    @State private var error: String?

    init(
        value: ConfigurationLocalRuleSet?, policy: String, candidates: ConfigurationRuleTargetCandidates,
        geoValues: ClashMacGeoValueLoader? = nil,
        download: @escaping @MainActor (String) async throws -> ConfigurationRuleSetContent,
        save: @escaping (ConfigurationLocalRuleSet, String) async throws -> Void,
        close: @escaping () -> Void
    ) {
        self.value = value
        self.candidates = candidates
        self.geoValues = geoValues
        self.download = download
        self.save = save
        self.close = close
        let input = value?.input ?? ""
        let isLink = Self.looksLikeLink(input)
        _name = State(initialValue: value?.name ?? "")
        _link = State(initialValue: isLink ? input : "")
        _lines = State(initialValue: isLink ? [] : Self.lines(from: input))
        _kind = State(initialValue: isLink ? .link : .manual)
        _policy = State(initialValue: policy)
    }

     
     
     
     
     
    static func set(id: String, name: String, input: String, read: ConfigurationRuleSetContent) -> ConfigurationLocalRuleSet {
        ConfigurationLocalRuleSet(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), input: input,
                                  rules: read.rules, link: read.link, behavior: read.behavior)
    }

     
    static func looksLikeLink(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.contains("\n") && (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"))
    }

     
     
    static func lines(from input: String) -> [Line] {
        input.split(separator: "\n", omittingEmptySubsequences: true)
            .map { Line(raw: $0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.raw.isEmpty }
    }

    private var input: String {
        kind == .link ? link.trimmingCharacters(in: .whitespacesAndNewlines) : lines.map(\.raw).joined(separator: "\n")
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !policy.isEmpty && !busy && !pickingPolicy && !addingLine
            && (kind == .link ? Self.looksLikeLink(link) : !lines.isEmpty)
    }

     
    private var assembledLine: String {
        var parts = [lineAction.rawValue]
        if lineAction.needsContent { parts.append(lineContent.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return parts.joined(separator: ",")
    }

    private var canAddLine: Bool {
        !lineAction.needsContent || !lineContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var title: ClashDisplayText {
        if pickingGeo, let resource = lineAction.clashMacGeoResource { return resource.rowTitle }
        if addingLine { return .copy("Add Rule") }
        if pickingPolicy { return .copy("Select Policy") }
        return .copy(value == nil ? "New Rule Set" : "Edit Rule Set")
    }

    var body: some View {
        ClashMacSheetFrame(
            title: title, subtitle: (pickingPolicy || addingLine) ? nil : .copy("My Rules"),
            width: 560, height: 520
        ) {
            if pickingGeo, let resource = lineAction.clashMacGeoResource, let geoValues {
                ClashMacGeoValuePickerPage(
                    resource: resource, current: lineContent, load: geoValues,
                    identifier: "configuration-center.rule-editor.rule-set.geo"
                ) { picked in
                    lineContent = picked
                    pickedFrom = resource
                    pickingGeo = false
                }
            } else if addingLine {
                lineForm
            } else if pickingPolicy {
                ClashMacTargetPickerPage(
                    candidates: candidates, current: policy,
                    identifier: "configuration-center.rule-editor.rule-set.policy"
                ) { picked in
                    policy = picked
                    pickingPolicy = false
                }
            } else {
                form
            }
        } leading: {
            if pickingGeo {
                Button { pickingGeo = false } label: { Text(clash: .copy("Back")) }
                    .accessibilityIdentifier("configuration-center.rule-editor.rule-set.geo.back")
            } else if addingLine {
                Button { addingLine = false } label: { Text(clash: .copy("Back")) }
                    .accessibilityIdentifier("configuration-center.rule-editor.rule-set.line.back")
            } else if pickingPolicy {
                Button { pickingPolicy = false } label: { Text(clash: .copy("Back")) }
                    .accessibilityIdentifier("configuration-center.rule-editor.rule-set.policy.back")
            }
        } trailing: {
            if addingLine, !pickingGeo {
                ClashMacSheetButtons(
                    closeIdentifier: "configuration-center.rule-editor.rule-set.line.cancel",
                    primaryTitle: .copy("Add"),
                    primaryIdentifier: "configuration-center.rule-editor.rule-set.line.add",
                    primaryDisabled: !canAddLine,
                    onClose: { addingLine = false },
                    onPrimary: addLine
                )
            } else if !pickingPolicy, !pickingGeo {
                ClashMacSheetButtons(
                    closeIdentifier: "configuration-center.rule-editor.rule-set.cancel",
                    primaryTitle: .copy("Save"),
                    primaryIdentifier: "configuration-center.rule-editor.rule-set.save",
                    primaryDisabled: !canSave,
                    isBusy: busy,
                    onClose: close,
                    onPrimary: commit
                )
            }
        }
        .onChange(of: lineAction) { changed in
             
             
            if changed.clashMacGeoResource != pickedFrom { lineContent = ""; pickedFrom = nil }
        }
    }

    private var form: some View {
        ClashMacSheetForm {
            Section {
                TextField(text: $name, prompt: Text(clash: .copy("e.g. 🎬 Netflix"))) { Text(clash: .copy("Name")) }
                    .disabled(busy)
                    .accessibilityIdentifier("configuration-center.rule-editor.rule-set.name")
            }
            Section {
                Picker(selection: $kind) {
                    Text(clash: .copy("Link")).tag(Kind.link)
                    Text(clash: .copy("Manual")).tag(Kind.manual)
                } label: {
                    Text(clash: .copy("Rules From"))
                }
                .pickerStyle(.segmented)
                .disabled(busy)
                .accessibilityIdentifier("configuration-center.rule-editor.rule-set.kind")
                if kind == .link {
                    TextField(text: $link, prompt: Text(verbatim: "https://")) { Text(clash: .copy("Link")) }
                        .disabled(busy)
                        .accessibilityIdentifier("configuration-center.rule-editor.rule-set.input")
                } else {
                     
                     
                     
                    ForEach(lines) { line in
                        ClashMacRuleSetLineRow(line: line)
                            .disabled(busy)
                            .contextMenu {
                                Button(role: .destructive) {
                                    lines.removeAll { $0.id == line.id }
                                } label: {
                                    Text(clash: .copy("Delete"))
                                }
                            }
                    }
                    .onDelete { offsets in lines.remove(atOffsets: offsets) }
                    Button {
                        lineAction = .domainSuffix
                        lineContent = ""
                        pickedFrom = nil
                        addingLine = true
                    } label: {
                        Text(clash: .copy("Add Rule"))
                    }
                    .disabled(busy)
                    .accessibilityIdentifier("configuration-center.rule-editor.rule-set.line.open")
                }
            } footer: {
                Text(clash: .copy(kind == .link
                    ? "A text, YAML or MRS rule set the app downloads and keeps updated."
                    : "Add the rules this set matches. The policy is chosen below, not written on each rule."))
            }
            Section {
                ClashMacTargetRow(
                    title: .copy("Policy"), value: policy,
                    identifier: "configuration-center.rule-editor.rule-set.policy.row"
                ) { pickingPolicy = true }
                .disabled(busy)
            } footer: {
                Text(clash: .copy("Traffic matching these rules goes to this policy. Saving adds the rule set to the current rules."))
            }
            if let error {
                Section {
                    Text(verbatim: error).foregroundStyle(.red)
                        .accessibilityIdentifier("configuration-center.rule-editor.rule-set.error")
                }
            }
        }
    }

     
     
     
    private var lineForm: some View {
        ClashMacSheetForm {
            Section {
                Picker(selection: $lineAction) {
                    ForEach(ClashMacRuleRowEditor.offeredActions(syntax, keeping: lineAction, lines: true), id: \.self) { item in
                        Text(verbatim: ConfigurationRuleWords.kindName(item.rawValue, locale: locale, copy: copy)).tag(item)
                    }
                } label: {
                    Text(clash: .copy("Rule Type"))
                }
                .accessibilityIdentifier("configuration-center.rule-editor.rule-set.line.action")
                if let resource = lineAction.clashMacGeoResource, geoValues != nil {
                    ClashMacGeoValueRow(
                        resource: resource, value: lineContent,
                        identifier: "configuration-center.rule-editor.rule-set.line.geo"
                    ) { pickingGeo = true }
                } else if lineAction.needsContent {
                    LabeledContent {
                        TextField(text: $lineContent, prompt: Text(verbatim: lineAction.contentPlaceholder)) {
                            Text(clash: .copy(lineAction.contentLabel))
                        }
                        .labelsHidden()
                        .font(.body.monospaced())
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("configuration-center.rule-editor.rule-set.line.content")
                    } label: {
                        Text(clash: .copy(lineAction.contentLabel))
                    }
                }
                 
                Text(clash: .format("Written as %@ in the configuration file", [assembledLine]))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func addLine() {
        guard canAddLine else { return }
        lines.append(Line(raw: assembledLine))
        addingLine = false
    }

    private func commit() {
        guard canSave else { return }
        busy = true
        error = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                let trimmed = input
                let set = Self.set(id: value?.id ?? UUID().uuidString.lowercased(), name: name,
                                   input: trimmed, read: try await download(trimmed))
                try await save(set, policy)
                close()
            } catch {
                self.error = ClashErrorCopy.message(error, locale: locale)
            }
        }
    }
}

 
 
 
extension View {
     
     
     
     
     
     
     
    func clashMacRuleListRows() -> some View {
        environment(\.defaultMinListRowHeight, ClashMacRuleListMetrics.leastRowHeight)
    }
}

enum ClashMacRuleListMetrics {
     
    static let leastRowHeight: CGFloat = 36
}

struct ClashMacRuleSetLineRow: View {
    let line: ClashMacLocalRuleSetEditor.Line

    var body: some View {
         
         
        ConfigurationRuleRow(line.raw, hasTarget: false, showsChevron: false)
            .accessibilityIdentifier("configuration-center.rule-editor.rule-set.line.\(line.raw)")
    }
}

 
 
struct ClashMacNamePrompt: View {
    let title: ClashDisplayText
    let initial: String
    let nameIdentifier: String
    let cancelIdentifier: String
    let saveIdentifier: String
    let commit: (String) async throws -> Void
    let close: () -> Void
    @Environment(\.locale) private var locale
    @State private var name: String
    @State private var busy = false
    @State private var error: String?

    init(
        title: ClashDisplayText, initial: String,
        nameIdentifier: String, cancelIdentifier: String, saveIdentifier: String,
        commit: @escaping (String) async throws -> Void, close: @escaping () -> Void
    ) {
        self.title = title
        self.initial = initial
        self.nameIdentifier = nameIdentifier
        self.cancelIdentifier = cancelIdentifier
        self.saveIdentifier = saveIdentifier
        self.commit = commit
        self.close = close
        _name = State(initialValue: initial)
    }

    var body: some View {
        ClashMacSheetFrame(title: title, width: 480, height: 230) {
            ClashMacSheetForm {
                Section {
                    TextField(text: $name, prompt: Text(clash: .copy("Name"))) { Text(clash: .copy("Name")) }
                        .disabled(busy)
                        .accessibilityIdentifier(nameIdentifier)
                }
                if let error {
                    Section { Text(verbatim: error).foregroundStyle(.red) }
                }
            }
        } trailing: {
            ClashMacSheetButtons(
                closeIdentifier: cancelIdentifier,
                primaryTitle: .copy("Save"),
                primaryIdentifier: saveIdentifier,
                primaryDisabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy,
                isBusy: busy,
                onClose: close,
                onPrimary: {
                    busy = true
                    error = nil
                    Task { @MainActor in
                        defer { busy = false }
                        do { try await commit(name.trimmingCharacters(in: .whitespacesAndNewlines)); close() }
                        catch { self.error = ClashErrorCopy.message(error, locale: locale) }
                    }
                }
            )
        }
    }
}

private enum ClashMacRuleSourceError: Error { case foreignKeys }

 
private struct ClashMacEditRefusal: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

 
 
 
 
struct ClashMacMemberChecklist: View {
    let candidates: ConfigurationRuleTargetCandidates
    @Binding var selected: [String]
     
    let keepsOne: Bool
    let identifier: String
    @State private var query = ""
    @Environment(\.clashRuleTargetSearch) private var targetSearch
     
     
     
    @State private var searched: [ConfigurationRuleTargetCandidates.Section] = []
    @State private var searching = false

    private func title(_ section: ConfigurationRuleTargetCandidates.Section) -> ClashDisplayText {
        switch section.kind {
        case .builtin: return .copy("Built-in")
        case .groups: return .copy("Policy Groups")
        case .source: return .verbatim(section.sourceLabel ?? section.id)
        case .providers: return .verbatim(section.sourceLabel ?? section.id)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(text: $query, prompt: Text(clash: .copy("Search"))) { Text(clash: .copy("Search")) }
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .accessibilityIdentifier("\(identifier).search")
            Divider()
            List {
                ForEach(ClashMacTargetSearch.merge(candidates.filtered(by: query), searched).sections) { section in
                    Section {
                        ForEach(section.names, id: \.self) { name in
                            Toggle(isOn: Binding(get: { selected.contains(name) }, set: { on in
                                if on {
                                    if !selected.contains(name) { selected.append(name); targetSearch?.recordUse(name) }
                                } else if !keepsOne || selected.count > 1 {
                                    selected.removeAll { $0 == name }
                                }
                            })) {
                                Text(verbatim: name).lineLimit(1)
                            }
                            .toggleStyle(.checkbox)
                            .accessibilityIdentifier("\(identifier).item")
                        }
                    } header: {
                        Text(clash: title(section))
                    }
                }
            }
            .listStyle(.inset)
        }
         
         
        .task(id: query) {
            await ClashMacTargetSearch.run(targetSearch, query: query, current: selected,
                                           searching: $searching, into: $searched)
        }
    }
}
