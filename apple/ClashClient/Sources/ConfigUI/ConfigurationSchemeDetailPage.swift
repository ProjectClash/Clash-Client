import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
 
 
struct ConfigurationSchemeDetailSnapshot: Equatable {
     
     
    enum Deletion: Equatable {
         
         
        case allowed(note: String?)
         
        case refused(reason: String)
    }

     
     
     
    enum RemovalPreview: Equatable {
         
         
        case keeps([String])
         
        case refused(String)
    }

     
     
     
     
    enum UpdateResult: Equatable {
        case updated
        case upToDate
         
         
        case refused([ClashDisplayText])
    }

     
     
    static func updateResult(_ outcome: ProfilesViewModel.ConfigurationSourceRefreshResult,
                             refusedSinceThePress refused: (profileID: String, failure: ConfigurationFailure)?,
                             scheme: ConfigurationRuleScheme, library: ConfigurationLibrarySnapshot,
                             name: String) -> UpdateResult? {
        if let refused, library.recipes(runningScheme: scheme.id).contains(where: { $0.id == refused.profileID }) {
             
             
             
            guard let lines = RuleSchemeRefusalNotice.lines(for: refused.failure, schemeName: name,
                                                            fromLink: scheme.kind == .imported) else { return nil }
            return .refused(lines)
        }
        return outcome == .nothingNew ? .upToDate : .updated
    }

    let name: String
    let canRename: Bool
    let ruleCount: Int
    let groupCount: Int
    let canUpdate: Bool
     
     
     
     
    let listsAreReadOnly: Bool
    let builtinNote: String?
    let usedBy: [String]
    let deletion: Deletion

    static let usersHeader = "Configurations Using It"
    static let builtinRefusal = "Built-in rule schemes can’t be deleted."
    static let originalRefusal = "Can’t be deleted: “%@” runs these rules as its link gives them."
     
    static let keptCopyRefusal = "Can’t be deleted: it’s the copy kept for “%@” after its scheme was deleted."
     
     
    static let unclaimedCopyRefusal = "Its link or file was deleted, so this kept copy can't be changed."
    static let keepsRunningNoteOne = "After deletion, %@ keeps using these rules; the rule library no longer lists them."
    static let keepsRunningNote = "After deletion, %@ keep using these rules; the rule library no longer lists them."
     
    static let builtinNotes = [
        ConfigurationBuiltins.basicRuleID: "China and local traffic use Direct; other traffic uses your selected nodes.",
        ConfigurationBuiltins.lazyRuleID: "Ready-made routing for AI, streaming, social and gaming services.",
    ]

     
     
    static func make(scheme: ConfigurationRuleScheme, library: ConfigurationLibrarySnapshot, locale: Locale,
                     removal: RemovalPreview? = nil) -> Self {
        let record = record(of: scheme, in: library)
         
         
        var follows = false
        var fromALink = false
        if case .subscription = record?.origin {
            fromALink = true
            follows = record?.isListedInLibrary == true && scheme.isRetainedSnapshot != true
        }
        return Self(name: ClashTowerRulesLibraryView.displayLabel(scheme, locale: locale),
                    canRename: ClashTowerRulesLibraryView.canRename(scheme),
                    ruleCount: record?.ruleCount ?? 0, groupCount: record?.groupCount ?? 0,
                    canUpdate: follows,
                    listsAreReadOnly: isBuiltin(scheme) || fromALink,
                    builtinNote: builtinNotes[scheme.id].map { ClashCopy.string($0, locale: locale) },
                    usedBy: library.recipes(runningScheme: scheme.id).map(\.label),
                    deletion: deletion(of: scheme, in: library, removal: removal, locale: locale))
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func record(of scheme: ConfigurationRuleScheme, in library: ConfigurationLibrarySnapshot) -> ConfigurationSourceRecord? {
        let scheme = scheme.rulesFromSchemeID.flatMap { base in
            library.rules.first(where: { $0.id == base }) ?? ConfigurationBuiltins.schemes.first(where: { $0.id == base })
        } ?? scheme
        let record: ConfigurationSourceRecord?
        if ConfigurationBuiltins.isNative(scheme.id) {
            record = ConfigurationBuiltins.records.first(where: { $0.id == scheme.sourceID })
        } else {
            record = library.sources.first(where: { $0.id == scheme.sourceID })
                ?? ConfigurationBuiltins.records.first(where: { $0.id == scheme.sourceID })
        }
        guard scheme.collectionKey != nil else { return record }
        return record?.projectedAsCollectionScheme
    }

     
     
     
     
     
    static func deletion(of scheme: ConfigurationRuleScheme, in library: ConfigurationLibrarySnapshot,
                         removal: RemovalPreview?, locale: Locale) -> Deletion {
        if isBuiltin(scheme) {
            return .refused(reason: ClashCopy.string(builtinRefusal, locale: locale))
        }
        if scheme.isRetainedSnapshot == true {
            let owners = runners(of: scheme.id, in: library)
            return .refused(reason: owners.isEmpty ? ClashCopy.string(unclaimedCopyRefusal, locale: locale)
                : ClashCopy.format(keptCopyRefusal, locale: locale, namesInsideQuotes(owners, locale: locale)))
        }
        if scheme.kind == .supplied,
           let original = library.recipes.first(where: { $0.preservesOriginal == true && $0.ruleSchemeID == scheme.id }) {
            return .refused(reason: ClashCopy.format(originalRefusal, locale: locale, original.label))
        }
        switch removal {
        case .keeps(let names)?:
            guard !names.isEmpty else { return .allowed(note: nil) }
            return .allowed(note: ClashCopy.format(names.count == 1 ? keepsRunningNoteOne : keepsRunningNote,
                                                   locale: locale, Self.names(names, locale: locale)))
        case .refused(let reason)?:
            return .refused(reason: reason)
        case nil:
            return .allowed(note: nil)
        }
    }

     
     
    static func isBuiltin(_ scheme: ConfigurationRuleScheme) -> Bool {
        ConfigurationBuiltins.isNative(scheme.id) || scheme.kind == .builtin || scheme.kind == .community
    }

     
     
    static func runners(of id: String, in library: ConfigurationLibrarySnapshot) -> [String] {
        library.recipes.filter { recipe in
            recipe.ruleSchemeID == id || library.rules.contains { $0.id == recipe.ruleSchemeID && $0.rulesFromSchemeID == id }
        }.map(\.label)
    }

     
     
     
     
     
    static func removalPreview(of id: String, in store: ConfigurationLibraryStore, locale: Locale) -> RemovalPreview? {
        do {
            let before = try store.snapshot()
            let prepared = try store.prepareRuleRemoval(id, expectedGeneration: before.generation)
            return .keeps(keptRunners(before: before, after: prepared.candidate))
        } catch ConfigurationLibraryError.staleGeneration, ConfigurationLibraryError.busy {
            return nil
        } catch {
            return .refused(ClashErrorCopy.message(error, locale: locale))
        }
    }

     
     
     
     
     
     
    static func keptRunners(before: ConfigurationLibrarySnapshot, after: ConfigurationLibrarySnapshot) -> [String] {
        let keptBefore = Set(before.rules.filter { $0.isRetainedSnapshot == true }.map(\.id))
        let kept = Set(after.rules.filter { $0.isRetainedSnapshot == true && !keptBefore.contains($0.id) }.map(\.id))
        return after.recipes.filter { recipe in
            kept.contains(recipe.ruleSchemeID)
                || after.rules.contains { view in
                    view.id == recipe.ruleSchemeID && view.rulesFromSchemeID.map { kept.contains($0) } == true
                }
        }.map(\.label)
    }

     
     
     
    static func names(_ names: [String], locale: Locale) -> String {
        let (open, close) = quotes(locale)
        return names.map { "\(open)\($0)\(close)" }.formatted(.list(type: .and).locale(locale))
    }

     
     
     
    static func namesInsideQuotes(_ names: [String], locale: Locale) -> String {
        let joined = Self.names(names, locale: locale)
        let (open, close) = quotes(locale)
        guard joined.first == open, joined.last == close else { return joined }
        return String(joined.dropFirst().dropLast())
    }

    private static func quotes(_ locale: Locale) -> (Character, Character) {
         
        locale.identifier.hasPrefix("zh") ? ("「", "」") : ("“", "”")
    }
}

 
#if os(iOS)

 
 
 
 
 
 
 
struct ConfigurationSchemeDetailPage: View {
    @Environment(\.locale) private var locale
    @Environment(\.clashFeedback) private var feedback
    let model: ProfilesViewModel
    let schemeID: String
    @State private var library: ConfigurationLibrarySnapshot
    let changed: (ConfigurationLibrarySnapshot) -> Void
     
     
     
    let profileID: String?
    @StateObject private var dismiss = ClashDismissHandle()
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var renaming = false
    @State private var renameText = ""
     
    @State private var copying: ConfigurationRuleDraft?
    @State private var copyName = ""
     
     
    @State private var removal: ConfigurationSchemeDetailSnapshot.RemovalPreview?
     
    @State private var updateResult: ConfigurationSchemeDetailSnapshot.UpdateResult?

    init(model: ProfilesViewModel, schemeID: String, library: ConfigurationLibrarySnapshot,
         changed: @escaping (ConfigurationLibrarySnapshot) -> Void, profileID: String?) {
        self.model = model
        self.schemeID = schemeID
        _library = State(initialValue: library)
        self.changed = changed
        self.profileID = profileID
    }

     
    private var scheme: ConfigurationRuleScheme? {
        library.rules.first { $0.id == schemeID } ?? ConfigurationBuiltins.schemes.first { $0.id == schemeID }
    }

    var body: some View {
        Form {
            if let scheme {
                sections(scheme, ConfigurationSchemeDetailSnapshot.make(scheme: scheme, library: library, locale: locale,
                                                                              removal: removal))
            }
            if let errorMessage {
                Section { Text(verbatim: errorMessage).foregroundStyle(.orange) }
            }
        }
        .disabled(busy)
        .clashPageTitle("Rule Scheme")
        .task(id: library.generation) { await askRemoval() }
        .clashCapturesDismiss(dismiss)
         
        .clashTextFieldAlert("Rename", isPresented: $renaming, text: $renameText,
                             field: ClashTextFieldAlertField(placeholder: "Name",
                                                             identifier: "configuration.scheme-detail.rename.name")) { typed in
            guard let scheme, let name = scheme.newName(typed: typed, locale: locale) else { return }
            perform { apply(try await model.renameConfigurationRuleScheme(scheme.id, label: name)) }
        }
        .clashTextFieldAlert("Save as New Scheme", isPresented: Binding(get: { copying != nil }, set: { if !$0 { copying = nil } }),
                             presenting: copying, text: $copyName,
                             field: ClashTextFieldAlertField(placeholder: "Scheme Name",
                                                             identifier: "configuration.scheme-detail.copy.name"),
                             confirm: "Save",
                             isConfirmEnabled: { _, typed in !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { draft, typed in
            let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            perform {
                apply(try await model.copyConfigurationRuleScheme(draft: draft, label: name, generation: library.generation))
                feedback?.show(.success(title: ClashFeedbackCopy.added(name), accessibilityIdentifier: "feedback.rules.copy"),
                               operation: "configuration.scheme-detail.copy")
            }
        }
    }

    @ViewBuilder
    private func sections(_ scheme: ConfigurationRuleScheme, _ snapshot: ConfigurationSchemeDetailSnapshot) -> some View {
        Section {
            if snapshot.canRename {
                Button { renameText = scheme.labelAsRead(locale: locale); renaming = true } label: {
                    valueRow("Name", value: snapshot.name)
                }
                .accessibilityIdentifier("configuration.scheme-detail.rename")
            } else {
                valueRow("Name", value: snapshot.name)
                    .accessibilityIdentifier("configuration.scheme-detail.name")
            }
             
             
            ClashNativeNavigationLink {
                ConfigurationSchemeDetailList(model: model, scheme: scheme, library: library, profileID: profileID,
                                              focus: .rules, readOnly: snapshot.listsAreReadOnly, changed: apply)
            } label: { valueRow("Rules", value: ClashCopy.count(snapshot.ruleCount, locale: locale)) }
                .accessibilityIdentifier("configuration.scheme-detail.rules")
            ClashNativeNavigationLink {
                ConfigurationSchemeDetailList(model: model, scheme: scheme, library: library, profileID: profileID,
                                              focus: .groups, readOnly: snapshot.listsAreReadOnly, changed: apply)
            } label: { valueRow("Policy Groups", value: ClashCopy.count(snapshot.groupCount, locale: locale)) }
                .accessibilityIdentifier("configuration.scheme-detail.groups")
            if snapshot.canUpdate {
                Button("Update") { update(scheme) }
                    .accessibilityIdentifier("configuration.scheme-detail.update")
            }
        } footer: {
            if let note = snapshot.builtinNote {
                Text(verbatim: note).accessibilityIdentifier("configuration.scheme-detail.builtin-note")
            } else if snapshot.canUpdate, let updateResult {
                updateResultLines(updateResult)
            }
        }
        if !snapshot.usedBy.isEmpty {
            Section {
                ForEach(Array(snapshot.usedBy.enumerated()), id: \.offset) { _, name in
                    Text(verbatim: name).accessibilityIdentifier("configuration.scheme-detail.used-by")
                }
            } header: {
                Text(clash: .copy(ConfigurationSchemeDetailSnapshot.usersHeader))
            }
        }
        Section {
            Button("Save as New Scheme") { startCopy(scheme) }
                .accessibilityIdentifier("configuration.scheme-detail.copy")
        }
        Section {
            Button("Delete Rule Scheme", role: .destructive) { delete(scheme) }
                .disabled(!snapshot.deletion.isAllowed)
                .accessibilityIdentifier("configuration.scheme-detail.delete")
        } footer: {
            if let line = snapshot.deletion.line {
                Text(verbatim: line).accessibilityIdentifier("configuration.scheme-detail.delete.note")
            }
        }
    }

     
     
    @ViewBuilder
    private func updateResultLines(_ result: ConfigurationSchemeDetailSnapshot.UpdateResult) -> some View {
        switch result {
        case .refused(let lines):
            VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                if let first = lines.first { ClashStatusMessage(text: first, kind: .error) }
                ForEach(Array(lines.dropFirst().enumerated()), id: \.offset) { _, line in Text(clash: line) }
            }
            .accessibilityIdentifier("configuration.scheme-detail.update-result")
        case .updated:
            Text(clash: .copy("Updated")).accessibilityIdentifier("configuration.scheme-detail.update-result")
        case .upToDate:
            Text(clash: .copy("Up to date")).accessibilityIdentifier("configuration.scheme-detail.update-result")
        }
    }

    private func valueRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ClashTheme.Spacing.row) {
            Text(clash: .copy(title)).foregroundStyle(.primary)
            Spacer(minLength: ClashTheme.Spacing.row)
            Text(verbatim: value).foregroundStyle(.secondary)
        }
    }

    private func apply(_ value: ConfigurationLibrarySnapshot) { library = value; changed(value) }

     
     
    private func askRemoval() async {
        guard let store = model.configurationLibraryStore else { removal = nil; return }
        let id = schemeID
        let locale = locale
        removal = await Task.detached(priority: .userInitiated) {
            ConfigurationSchemeDetailSnapshot.removalPreview(of: id, in: store, locale: locale)
        }.value
    }

    private func reload() async throws {
        guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        apply(try await Task.detached(priority: .userInitiated) { try store.snapshot() }.value)
    }

     
     
     
    private func update(_ scheme: ConfigurationRuleScheme) {
        guard !busy else { return }
        busy = true; errorMessage = nil; updateResult = nil
        let name = ClashTowerRulesLibraryView.displayLabel(scheme, locale: locale)
        Task { @MainActor in
            defer { busy = false }
            await model.pageLibraryWrite {
                do {
                    let serial = model.failureSerial
                    let outcome = try await model.refreshConfigurationSource(scheme.sourceID)
                    try await reload()
                     
                     
                     
                     
                     
                     
                     
                    updateResult = ConfigurationSchemeDetailSnapshot.updateResult(
                        outcome, refusedSinceThePress: model.failureSerial != serial ? model.refusedActivation : nil,
                        scheme: scheme, library: library, name: name)
                    if case .refused(let lines)? = updateResult, lines.count > 1 {
                        feedback?.show(.error(title: lines[0], message: lines[1],
                                              accessibilityIdentifier: "feedback.rules.update.refused"),
                                       operation: "configuration.scheme-detail.update")
                        return
                    }
                    feedback?.show(outcome == .nothingNew
                        ? .information(title: ClashFeedbackCopy.upToDate(name), accessibilityIdentifier: "feedback.rules.update")
                        : .success(title: ClashFeedbackCopy.updated(name), accessibilityIdentifier: "feedback.rules.update"),
                        operation: "configuration.scheme-detail.update")
                } catch { errorMessage = ClashErrorCopy.message(error, locale: locale) }
            }
        }
    }

     
     
    private func startCopy(_ scheme: ConfigurationRuleScheme) {
        perform {
            guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            let draft = try await Task.detached(priority: .userInitiated) {
                try ConfigurationRuleDraft(scheme: scheme, payload: store.ruleSchemePayload(scheme.id))
            }.value
            copyName = ClashTowerRuleCustomizationView.newSchemeName(draft, locale: locale,
                                                                       taken: ClashTowerRuleCustomizationView.takenSchemeNames(in: library, locale: locale))
            copying = draft
        }
    }

     
     
     
    private func delete(_ scheme: ConfigurationRuleScheme) {
         
        let name = ClashTowerRulesLibraryView.displayLabel(scheme, locale: locale)
        perform {
            let deletion = try await model.deleteConfigurationRuleSchemeRestorably(scheme.id, generation: library.generation)
            changed(deletion.snapshot)
            dismiss()
            ConfigurationLibraryUndo.offer(feedback, name: name, deletion: deletion, model: model, changed: changed)
        }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true; errorMessage = nil
        Task { @MainActor in
            defer { busy = false }
            do { try await operation() } catch { errorMessage = ClashErrorCopy.message(error, locale: locale) }
        }
    }
}

private extension ConfigurationSchemeDetailSnapshot.Deletion {
    var isAllowed: Bool { if case .allowed = self { return true } else { return false } }
     
    var line: String? {
        switch self {
        case .allowed(let note): return note
        case .refused(let reason): return reason
        }
    }
}

 
 
 
private struct ConfigurationSchemeDetailList: View {
    let model: ProfilesViewModel
    let scheme: ConfigurationRuleScheme
    let library: ConfigurationLibrarySnapshot
    let profileID: String?
    let focus: ClashTowerRuleFocus
    let readOnly: Bool
    let changed: (ConfigurationLibrarySnapshot) -> Void
    @StateObject private var dismiss = ClashDismissHandle()

    var body: some View {
        ConfigurationTowerRuleCustomizationAdapter(model: model, scheme: scheme, library: library, pushed: true,
                                                   profileID: profileID, changed: changed, close: { dismiss() },
                                                   focus: focus, savesEachChange: true, readOnly: readOnly)
            .clashCapturesDismiss(dismiss)
    }
}
#endif
