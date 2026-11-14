import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
public struct ClashMacConfigurationWizardActions {
    public var create: @MainActor (ConfigurationCreationDraft, UInt64, String) async throws -> Void
    public var sourceImport: ClashMacSourceImportActions
     
     
     
    public var loadScopeChoices: @MainActor (ConfigurationSourceRecord, ConfigurationSourcePayload?) async throws -> ClashMacNodeScopeChoices = { _, _ in
        throw ConfigurationLibraryError.unreadable
    }
     
     
     
    public var preview: (@MainActor (ConfigurationCreationDraft) async throws -> ClashMacWizardPreview)?

    public init(
        create: @escaping @MainActor (ConfigurationCreationDraft, UInt64, String) async throws -> Void,
        sourceImport: ClashMacSourceImportActions
    ) {
        self.create = create
        self.sourceImport = sourceImport
    }

    public static var unavailable: ClashMacConfigurationWizardActions {
        ClashMacConfigurationWizardActions(
            create: { _, _, _ in throw ConfigurationLibraryError.unreadable },
            sourceImport: .unavailable
        )
    }
}

 
 
public enum ClashMacConfigurationWizardRules {
     
     
    public static func canAdvance(_ draft: ConfigurationCreationDraft) -> Bool {
        switch draft.step {
        case .sources: !draft.selectedSourceIDs.isEmpty || !draft.newSources.isEmpty
        case .rules: draft.selectedRuleID != nil
        case .finish: !draft.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

     
     
     
     
     
     
     
     
     
    public static func suggestedLabel(
        _ draft: ConfigurationCreationDraft,
        in snapshot: ConfigurationLibrarySnapshot,
        fallback: String = "Profile",
        locale: Locale = .current
    ) -> String {
        let typed = draft.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        let fromSource = ((draft.newSources.first?.record ?? chosenSources(draft, in: snapshot).first)
            .map { $0.displayLabel(locale: locale) } ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return fromSource.isEmpty ? fallback : fromSource
    }

     
     
     
    public static func chosenSources(
        _ draft: ConfigurationCreationDraft,
        in snapshot: ConfigurationLibrarySnapshot
    ) -> [ConfigurationSourceRecord] {
        draft.selectedSourceIDs.compactMap { id in snapshot.availableSources.first { $0.id == id } }
    }

     
     
     
     
     
     
     
     
    public static func addSource(_ payload: ConfigurationSourcePayload, to draft: inout ConfigurationCreationDraft) {
        if draft.selectedSourceIDs.isEmpty, draft.newSources.isEmpty,
           payload.record.suppliesNodes,
           payload.record.nodeCount > 0 || payload.record.providerCount > 0,
           ConfigurationCreationDraft.runsAsWritten(payload) {
            draft.useOriginal(payload)
        } else {
            draft.add(payload, rule: nil)
        }
    }

     
     
    public static func defaultRuleID(_ draft: ConfigurationCreationDraft) -> String {
        draft.selectedRuleID ?? ConfigurationBuiltins.basicRuleID
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
public struct ClashMacConfigurationWizardSheet: View {
    @ObservedObject private var model: ClashMacConfigurationLibraryModel
    private let actions: ClashMacConfigurationWizardActions
     
     
    private let created: (String) -> Void
     
     
     
     
    @StateObject private var dismiss = ClashDismissHandle()
    @Environment(\.locale) private var locale
    @State private var draft = ConfigurationCreationDraft()
    @State private var creationID = UUID().uuidString.lowercased()
    @State private var addingSource = false
     
    @State private var scopeSourceID: String?
    @State private var confirmsDiscard = false
    @State private var preview: ClashMacWizardPreview?
    @State private var expandedShelves: Set<String> = []
    @State private var busy = false
    @State private var error: String?
     
     
    @State private var refusedForItsRules: String?

    public init(
        model: ClashMacConfigurationLibraryModel,
        actions: ClashMacConfigurationWizardActions,
        initialDraft: ConfigurationCreationDraft? = nil,
        created: @escaping (String) -> Void
    ) {
        self.model = model
        self.actions = actions
        if let initialDraft { _draft = State(initialValue: initialDraft) }
        self.created = created
    }

    private var canAdvance: Bool { ClashMacConfigurationWizardRules.canAdvance(draft) && !busy }

    private var stepTitle: ClashDisplayText {
        switch draft.step {
        case .sources: .copy("Select Nodes")
        case .rules: .copy("Select Rules")
        case .finish: .copy("Add Profile")
        }
    }

    private var stepSubtitle: ClashDisplayText {
        switch draft.step {
        case .sources: .copy("Node Library")
        case .rules: .copy("Rule Library")
        case .finish: .copy("Configuration")
        }
    }

    public var body: some View {
         
         
         
         
        if addingSource {
            ClashMacSourceImportSheet(
                purpose: .nodes,
                actions: actions.sourceImport,
                closeTitle: .copy("Back"),
                accept: { payload in
                    ClashMacConfigurationWizardRules.addSource(payload, to: &draft)
                    addingSource = false
                     
                     
                     
                    if draft.originalSourceID != nil {
                        draft.label = suggestedLabel
                        save()
                    }
                },
                close: { addingSource = false }
            )
        } else if let scopeSourceID, let source = scopeSource(scopeSourceID) {
             
            ClashMacNodeScopePage(
                source: source,
                load: { [actions] in
                    try await actions.loadScopeChoices(source, draft.newSources.first { $0.record.id == scopeSourceID })
                },
                initial: draft.nodeScopes?[scopeSourceID],
                save: { scope in
                     
                     
                    var scopes = draft.nodeScopes ?? [:]
                    scopes[scopeSourceID] = scope?.isEmpty == true ? nil : scope
                    draft.nodeScopes = scopes.isEmpty ? nil : scopes
                    if scope?.isEmpty == true {
                        draft.selectedSourceIDs.removeAll { $0 == scopeSourceID }
                    } else if !draft.selectedSourceIDs.contains(scopeSourceID) {
                        draft.selectedSourceIDs.append(scopeSourceID)
                    }
                    self.scopeSourceID = nil
                },
                back: { self.scopeSourceID = nil }
            )
        } else {
            wizard
        }
    }

    private func scopeSource(_ id: String) -> ConfigurationSourceRecord? {
        draft.newSources.first { $0.record.id == id }?.record ?? model.snapshot.sources.first { $0.id == id }
    }

     
    private func scopeButton(_ id: String) -> some View {
        Button { scopeSourceID = id } label: { Image(systemName: "info.circle") }
            .buttonStyle(.borderless)
            .help(Text(clash: .copy("Node Collections")))
            .accessibilityLabel(Text(clash: .copy("Node Collections")))
            .accessibilityIdentifier("configuration-center.wizard.scope.\(id)")
    }

    private var wizard: some View {
        wizardFrame
             
            .alert(Text(clash: .copy("Discard Changes?")), isPresented: $confirmsDiscard) {
                Button(role: .destructive) { dismiss() } label: { Text(clash: .copy("Discard Changes")) }
                    .accessibilityIdentifier("configuration-center.wizard.discard.confirm")
                Button(role: .cancel) {} label: { Text(clash: .copy("Keep Editing")) }
            } message: {
                Text(clash: .copy("This profile has changes that have not been saved."))
            }
    }

    private var wizardFrame: some View {
        ClashMacSheetFrame(title: stepTitle, subtitle: draft.step == .finish ? nil : stepSubtitle, width: 600, height: 560) {
            VStack(spacing: 0) {
                Group {
                    switch draft.step {
                    case .sources: sourcesStep
                    case .rules: rulesStep
                    case .finish: finishStep
                    }
                }
                .accessibilityIdentifier("configuration-center.wizard")
                if let refusal = originalRefusal {
                     
                     
                    Divider()
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(verbatim: refusal.message).foregroundStyle(.red).font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("configuration-center.wizard.error")
                        Button { useOriginal(refusal.candidate) } label: { Text(clash: .copy("Use Original Configuration")) }
                            .disabled(busy)
                            .accessibilityIdentifier("configuration-center.wizard.error.original")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
            }
        } leading: {
            if draft.step == .sources {
                 
                 
                Button { addingSource = true } label: { Text(clash: .opens("Add Source", locale: locale)) }
                    .disabled(busy)
                    .accessibilityIdentifier("configuration-center.wizard.add-source")
            } else {
                Button(action: back) { Text(clash: .copy("Back")) }
                    .disabled(busy)
                    .accessibilityIdentifier("configuration-center.wizard.back")
            }
            if let error, originalRefusal == nil {
                Text(verbatim: error).foregroundStyle(.red).font(.subheadline).lineLimit(2)
                    .accessibilityIdentifier("configuration-center.wizard.error")
            }
        } trailing: {
            ClashMacSheetButtons(
                closeIdentifier: "configuration-center.wizard.cancel",
                 
                 
                 
                 
                primaryTitle: draft.step == .sources ? .copy("Next") : .copy("Save"),
                primaryIdentifier: "configuration-center.wizard.next",
                primaryDisabled: !canAdvance,
                isBusy: busy,
                onClose: { if draft != ConfigurationCreationDraft() && !busy { confirmsDiscard = true } else { dismiss() } },
                onPrimary: advance
            )
        }
        .task { if model.phase == .idle { await model.reload() } }
        .clashCapturesDismiss(dismiss)
    }

     

     
    private var rowsShownAtOnce: Int { 30 }

     
     
     
     
     
     
    private var sourcesStep: some View {
        List {
            if !draft.newSources.isEmpty {
                 
                 
                Section {
                    ForEach(draft.newSources, id: \.record.id) { payload in
                         
                        sourceRow(payload.record, identifier: "configuration-center.wizard.new-source.\(payload.record.id)")
                    }
                } header: {
                    Text(clash: .copy("Add Source"))
                }
            }
            ForEach(model.nodeShelves) { shelf in
                let expanded = expandedShelves.contains(shelf.id) || shelf.sources.count <= rowsShownAtOnce
                Section {
                    ForEach(expanded ? shelf.sources : Array(shelf.sources.prefix(rowsShownAtOnce))) { source in
                        sourceRow(source, identifier: "configuration-center.wizard.source.\(source.id)")
                    }
                    if !expanded {
                        Button { expandedShelves.insert(shelf.id) } label: { Text(clash: .copy("All Sources")) }
                            .accessibilityIdentifier("configuration-center.wizard.show-all")
                    }
                } header: {
                    Text(clash: .copy(shelf.group.title))
                }
            }
            if model.nodeShelves.isEmpty && draft.newSources.isEmpty {
                Section { Text(clash: .copy("None")).foregroundStyle(.secondary) }
            }
             
             
             
             
            if let candidate = originalCandidate {
                Section {
                    LabeledContent {
                        Button { useOriginal(candidate) } label: { Text(clash: .copy("Use Original Configuration")) }
                            .accessibilityIdentifier("configuration-center.wizard.original")
                    } label: {
                         
                        Text(verbatim: candidate.label)
                        Text(clash: .copy("Runs the configuration as received, with its own proxy groups, rules and DNS."))
                    }
                } header: {
                    Text(clash: .copy("Original Configuration"))
                }
            }
        }
        .listStyle(.inset)
    }

     
     
    private func sourceRow(_ source: ConfigurationSourceRecord, identifier: String) -> some View {
        let chosen = draft.selectedSourceIDs.contains(source.id)
        return HStack(spacing: ClashTheme.Spacing.compact) {
            Toggle(isOn: Binding(
                get: { chosen },
                set: { isOn in if isOn != draft.selectedSourceIDs.contains(source.id) { draft.toggleSource(source.id) } }
            )) {
                Text(clash: ClashConfigurationSourceCopy.name(source))
                Text(verbatim: ClashConfigurationSourceCopy.summary(source, locale: locale))
            }
            .toggleStyle(.checkbox)
            .accessibilityIdentifier(identifier)
            Spacer()
            if chosen { scopeButton(source.id) }
        }
    }

     
     
    private var originalCandidate: (id: String, label: String)? {
        guard draft.selectedSourceIDs.count == 1, let id = draft.selectedSourceIDs.first else { return nil }
        if let staged = draft.newSources.first(where: { $0.record.id == id }) {
            return staged.record.nodeChain == nil ? (id, staged.record.displayLabel(locale: locale)) : nil
        }
        guard let record = model.snapshot.sources.first(where: { $0.id == id }), record.nodeChain == nil else { return nil }
        return (id, record.displayLabel(locale: locale))
    }

     
     
     
    private func useOriginal(_ candidate: (id: String, label: String)) {
        error = nil
        if let staged = draft.newSources.first(where: { $0.record.id == candidate.id }) {
            draft.useOriginal(staged)
        } else {
            var original = ConfigurationCreationDraft()
            original.originalSourceID = candidate.id
            original.selectedSourceIDs = [candidate.id]
            original.label = candidate.label
            original.dnsMode = .source
            original.step = .finish
            draft = original
        }
         
        draft.label = suggestedLabel
        if !busy { save() }
    }

     
     
    private func schemeSubtitle(_ scheme: ConfigurationRuleScheme) -> ClashDisplayText {
        let base = scheme.baseSchemeID ?? scheme.id
        if base == ConfigurationBuiltins.basicRuleID {
            return .copy("China and local traffic use Direct; other traffic uses your selected nodes.")
        }
        if base == ConfigurationBuiltins.lazyRuleID {
            return .copy("Ready-made routing for AI, streaming, social and gaming services.")
        }
        return .count(model.usageCount(ofScheme: scheme.id), one: "Used by %@ profile", other: "Used by %@ profiles")
    }

     
     
    private var rulesStep: some View {
        let selected = ClashMacConfigurationWizardRules.defaultRuleID(draft)
        return ClashMacSheetForm {
            ForEach(model.ruleShelves) { shelf in
                Section {
                    Picker(selection: Binding<String?>(
                         
                        get: { shelf.schemes.contains { $0.id == selected } ? selected : nil },
                        set: { id in if let id { draft.selectedRuleID = id } }
                    )) {
                        ForEach(shelf.schemes, id: \.id) { scheme in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: scheme.displayLabel)
                                Text(clash: schemeSubtitle(scheme)).font(.subheadline).foregroundStyle(.secondary)
                            }
                            .tag(String?.some(scheme.id))
                            .accessibilityIdentifier("configuration-center.wizard.rule.\(scheme.id)")
                        }
                    } label: {
                        Text(clash: .copy(shelf.section.title))
                    }
                    .pickerStyle(.radioGroup)
                     
                    .labelsHidden()
                } header: {
                    Text(clash: .copy(shelf.section.title))
                }
            }
        }
    }

    private var finishStep: some View {
        ClashMacSheetForm {
            Section {
                TextField(text: $draft.label, prompt: Text(clash: .copy("Name"))) { Text(clash: .copy("Name")) }
                    .disabled(busy)
                    .accessibilityIdentifier("configuration-center.wizard.name")
                if let originalID = draft.originalSourceID {
                     
                     
                    LabeledContent {
                        Text(verbatim: (draft.newSources.first { $0.record.id == originalID }?.record
                            ?? model.snapshot.sources.first { $0.id == originalID })
                            .map { $0.displayLabel(locale: locale) } ?? "")
                    } label: {
                        Text(clash: .copy("Original Configuration"))
                    }
                    .accessibilityIdentifier("configuration-center.wizard.original-source")
                } else {
                    LabeledContent {
                        Text(verbatim: (draft.newSources.map(\.record)
                            + ClashMacConfigurationWizardRules.chosenSources(draft, in: model.snapshot)
                                .filter { record in !draft.newSources.contains { $0.record.id == record.id } })
                            .map { $0.displayLabel(locale: locale) }
                            .joined(separator: ", "))
                    } label: {
                        Text(clash: .copy("Node Sources"))
                    }
                    LabeledContent {
                        Text(verbatim: model.snapshot.effectiveRuleScheme(ClashMacConfigurationWizardRules.defaultRuleID(draft))?.displayLabel ?? "")
                    } label: {
                        Text(clash: .copy("Rule Scheme"))
                    }
                }
            } footer: {
                 
                if draft.originalSourceID != nil {
                    Text(clash: .copy("Keep the document's nodes, rules and settings."))
                }
            }
             
            if actions.preview != nil {
                Section {
                    LabeledContent {
                        if let preview { Text(verbatim: String(preview.nodes)) } else { ProgressView().controlSize(.small) }
                    } label: {
                        Text(clash: .copy("Nodes"))
                    }
                    .accessibilityIdentifier("configuration-center.wizard.preview.nodes")
                    LabeledContent {
                        if let preview { Text(verbatim: String(preview.rules)) } else { ProgressView().controlSize(.small) }
                    } label: {
                        Text(clash: .copy("Rules"))
                    }
                    .accessibilityIdentifier("configuration-center.wizard.preview.rules")
                }
            }
        }
        .task(id: draft.step) {
            guard draft.step == .finish, let load = actions.preview else { return }
            preview = nil
            preview = try? await load(draft)
        }
    }

     

    private func back() {
        error = nil
        switch draft.step {
        case .sources: break
        case .rules: draft.step = .sources
        case .finish:
            if draft.originalSourceID != nil {
                 
                draft.originalSourceID = nil
                draft.dnsMode = ConfigurationCreationDraft().dnsMode
                draft.step = .sources
            } else {
                draft.step = .rules
            }
        }
    }

     
     
    private var suggestedLabel: String {
        ClashMacConfigurationWizardRules.suggestedLabel(
            draft, in: model.snapshot, fallback: ClashCopy.string("Profile", locale: locale), locale: locale
        )
    }

    private func advance() {
        guard canAdvance else { return }
        error = nil
        switch draft.step {
        case .sources:
            if draft.selectedRuleID == nil { draft.selectedRuleID = ConfigurationBuiltins.basicRuleID }
            draft.step = .rules
        case .rules:
            draft.label = suggestedLabel
             
             
            save()
        case .finish:
            save()
        }
    }

     
     
     
     
    private var originalRefusal: (message: String, candidate: (id: String, label: String))? {
        guard let error, let candidate = originalCandidate, refusedForItsRules == candidate.id else { return nil }
        return (error, candidate)
    }

     
     
    nonisolated static func sourceRefusedForItsRules(_ error: Error) -> String? {
        guard case .rulesRunOnlyAsTheOriginal(let source)? = error as? ConfigurationCompositionError else { return nil }
        return source
    }

    private func save() {
        busy = true
        refusedForItsRules = nil
        var candidate = draft
        candidate.label = candidate.label.trimmingCharacters(in: .whitespacesAndNewlines)
        candidate.connectAfterCreation = false
        Task { @MainActor in
            defer { busy = false }
            do {
                try await actions.create(candidate, model.snapshot.generation, creationID)
                await model.reload()
                created(candidate.label)
                dismiss()
            } catch {
                self.error = ClashErrorCopy.message(error, locale: locale)
                refusedForItsRules = Self.sourceRefusedForItsRules(error)
            }
        }
    }
}

 
 
public struct ClashMacWizardPreview: Equatable, Sendable {
    public var nodes: Int
    public var rules: Int
    public init(nodes: Int, rules: Int) { self.nodes = nodes; self.rules = rules }
}
