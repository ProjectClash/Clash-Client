#if os(iOS)
import ClashClientKit
import ClashClientUI
import Combine
import SwiftUI

 
 
 
 
 
 
 
 

 
struct ConfigurationRuleSetDetailSnapshot: Equatable {
    enum Subject: Equatable {
        case mine(id: String)
        case collection(ConfigurationCollection.ID, brought: Bool)
    }

    enum Deletion: Equatable {
         
        case allowed(note: String?)
         
        case confirmed(message: String)
         
        case refused(reason: String)
    }

    let subject: Subject
    let name: String
    let canRename: Bool
     
    let link: String?
    let canUpdate: Bool
     
    let ruleCount: Int?
     
    let usedBy: [String]
     
    let canMakeScheme: Bool
    let canEditSource: Bool
     
    let deletesSource: Bool
    let deletion: Deletion

     
    static let deletionNoteKey = "Rules that use it are deleted too."
     
     
     
     
    static let builtinRefusalKey = "Rule sets that come with a built-in rule scheme can’t be deleted on their own."
    static let keptRefusalKey = "This copy was kept when its rule scheme was deleted, so its rule sets can’t be deleted on their own."
    static let linkConfirmationKey = "After deletion, this rule set comes back the next time its link updates. Profiles that reference it must choose another rule set first."
    static let fileConfirmationKey = "Remove this collection from its source. Profiles that reference it must choose another collection first."
    static let usersHeaderKey = "Configurations Using It"
    static let noUsersKey = "No configuration uses it"

     
     
    static func mine(_ set: ConfigurationLocalRuleSet, usedBy: [String], locale: Locale) -> Self {
        let link = set.link?.url ?? (ConfigurationLocalRuleSetLines.looksLikeLink(set.input)
            ? set.input.trimmingCharacters(in: .whitespacesAndNewlines) : nil)
        let count = set.ruleCount
        return Self(subject: .mine(id: set.id), name: set.name, canRename: true, link: link, canUpdate: link != nil,
                    ruleCount: count > 0 ? count : nil, usedBy: usedBy, canMakeScheme: false, canEditSource: false,
                    deletesSource: false, deletion: .allowed(note: ClashCopy.string(deletionNoteKey, locale: locale)))
    }

     
     
     
     
     
     
    @MainActor
    static func collection(_ entry: ConfigurationCollectionEntry, brought: Bool, usedBy: [String], locale: Locale) -> Self {
        let link = entry.collection.type == "http" ? entry.collection.location : nil
        let deletion: Deletion
        if entry.source.isRetainedSnapshot == true {
            deletion = .refused(reason: ClashCopy.string(keptRefusalKey, locale: locale))
        } else if !entry.definitionIsEditable {
            deletion = .refused(reason: ClashCopy.string(builtinRefusalKey, locale: locale))
        } else {
            deletion = .confirmed(message: ClashCopy.string(confirmationKey(entry), locale: locale))
        }
        return Self(subject: .collection(entry.id, brought: brought), name: entry.collection.name, canRename: false,
                    link: link, canUpdate: link != nil, ruleCount: entry.collection.inlineCount, usedBy: usedBy,
                    canMakeScheme: true, canEditSource: entry.definitionIsEditable,
                    deletesSource: deletesSource(entry.source), deletion: deletion)
    }

     
     
    static func confirmationKey(_ entry: ConfigurationCollectionEntry) -> String {
        if case .subscription = entry.source.origin { return linkConfirmationKey }
        return fileConfirmationKey
    }

     
     
    @MainActor
    static func deletesSource(_ source: ConfigurationSourceRecord) -> Bool {
        guard case .subscription = source.origin else { return false }
        return ClashTowerRulesLibraryView.canDeleteSource(source)
    }

     
     
     
    static func users(ofCollection entry: ConfigurationCollectionEntry, in library: ConfigurationLibrarySnapshot,
                      profiles: [LibraryUsage.Configuration]) -> [String] {
        let names = Dictionary(profiles.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return library.recipes(readingRulesOf: entry.source.id).map { names[$0.id] ?? $0.label }
    }

     
     
     
    static func edited(_ set: ConfigurationLocalRuleSet, name: String, input: String) async throws -> ConfigurationLocalRuleSet {
        let read = try await ConfigurationTowerRuleReader.ruleSet(input)
        return ConfigurationLocalRuleSet(id: set.id, name: name, input: input, rules: read.rules, link: read.link,
                                         behavior: read.behavior)
    }

     
     
     
    @MainActor
    static func currentGeneration(_ model: ProfilesViewModel) async throws -> UInt64 {
        guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        return try await Task.detached(priority: .userInitiated) { try store.snapshot().generation }.value
    }

     
     
     
     
    static func users(of setID: String, in library: ConfigurationLibrarySnapshot, store: ConfigurationLibraryStore,
                      profiles: [LibraryUsage.Configuration]) throws -> [String] {
        let schemes = try store.schemeIDs(usingLocalRuleSet: setID, in: library)
        let names = Dictionary(profiles.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return library.recipes(runningAnyOf: schemes).map { names[$0.id] ?? $0.label }
    }
}

 
struct ConfigurationRuleSetDetailPage: View {
     
     
    enum Item {
        case mine(ConfigurationLocalRuleSet)
        case collection(ConfigurationCollectionEntry, brought: Bool)
    }

    let model: ProfilesViewModel
    let item: Item
    let library: ConfigurationLibrarySnapshot
     
    let profileID: String?
    let changed: (ConfigurationLibrarySnapshot) -> Void

    init(model: ProfilesViewModel, item: Item, library: ConfigurationLibrarySnapshot, profileID: String?,
         changed: @escaping (ConfigurationLibrarySnapshot) -> Void) {
        self.model = model; self.item = item; self.library = library; self.profileID = profileID; self.changed = changed
    }

    var body: some View {
        switch item {
        case .mine(let set):
            MyRuleSetDetail(model: model, set: set, library: library, changed: changed)
        case .collection(let entry, let brought):
            CollectionRuleSetDetail(model: model, entry: entry, brought: brought, library: library, changed: changed)
        }
    }
}

 
private struct MyRuleSetDetail: View {
    let model: ProfilesViewModel
    let changed: (ConfigurationLibrarySnapshot) -> Void
    @Environment(\.locale) private var locale
    @Environment(\.clashFeedback) private var feedback
    @StateObject private var dismiss = ClashDismissHandle()
    @State private var set: ConfigurationLocalRuleSet
    @State private var library: ConfigurationLibrarySnapshot
    @State private var usedBy: [String] = []
    @State private var busy = false
    @State private var failure: ClashDisplayText?
    @State private var renaming = false
    @State private var renameText = ""
    @State private var editing = false

    init(model: ProfilesViewModel, set: ConfigurationLocalRuleSet, library: ConfigurationLibrarySnapshot,
         changed: @escaping (ConfigurationLibrarySnapshot) -> Void) {
        self.model = model
        self.changed = changed
        _set = State(initialValue: set)
        _library = State(initialValue: library)
    }

    private var snapshot: ConfigurationRuleSetDetailSnapshot { .mine(set, usedBy: usedBy, locale: locale) }

    var body: some View {
        let snapshot = self.snapshot
        Form {
            Section {
                Button { renameText = set.name; renaming = true } label: { valueRow("Name", value: snapshot.name) }
                    .accessibilityIdentifier("configuration.rule-set-detail.rename")
            }
            Section {
                if let link = snapshot.link {
                    Text(verbatim: link).textSelection(.enabled)
                        .accessibilityIdentifier("configuration.rule-set-detail.link")
                    Button("Copy Link") { ClashClipboard.copy(link, feedback: feedback, operation: "configuration.rule-set-detail.copy-link") }
                        .accessibilityIdentifier("configuration.rule-set-detail.copy-link")
                    Button("Update") { update(link) }
                        .accessibilityIdentifier("configuration.rule-set-detail.update")
                } else {
                    Text(clash: .copy("Local")).accessibilityIdentifier("configuration.rule-set-detail.local")
                }
                Button("Edit Rule Content") { editing = true }
                    .accessibilityIdentifier("configuration.rule-set-detail.edit")
            } header: { Text(clash: .copy("Source")) }
            Section {
                ClashNativeNavigationLink {
                    ConfigurationRuleSetRulesPage(model: model, source: .mine(set), title: set.name,
                                                  sharedNote: ConfigurationRuleSetRulesPage.sharedNote(users: usedBy, locale: locale),
                                                  changed: apply)
                } label: {
                    valueRow("Rules", value: snapshot.ruleCount.map { ClashCopy.count($0, locale: locale) } ?? "")
                }
                .accessibilityIdentifier("configuration.rule-set-detail.rules")
            }
            Section {
                if usedBy.isEmpty {
                    Text(clash: .copy(ConfigurationRuleSetDetailSnapshot.noUsersKey)).foregroundStyle(.secondary)
                        .accessibilityIdentifier("configuration.rule-set-detail.used-by.none")
                }
                ForEach(Array(usedBy.enumerated()), id: \.offset) { _, name in
                    Text(verbatim: name).accessibilityIdentifier("configuration.rule-set-detail.used-by")
                }
            } header: { Text(clash: .copy(ConfigurationRuleSetDetailSnapshot.usersHeaderKey)) }
            Section {
                Button("Delete Rule Set", role: .destructive, action: delete)
                    .accessibilityIdentifier("configuration.rule-set-detail.delete")
            } footer: {
                if case .allowed(let note?) = snapshot.deletion {
                    Text(verbatim: note).accessibilityIdentifier("configuration.rule-set-detail.delete.note")
                }
            }
            if let failure {
                Section {
                    Text(clash: failure).foregroundStyle(.orange)
                        .accessibilityIdentifier("configuration.rule-set-detail.failure")
                }
            }
        }
        .disabled(busy)
        .clashPageTitle(.verbatim(set.name), watchAs: "rule-set-detail")
        .task(id: library.generation) { await readUsers() }
        .clashCapturesDismiss(dismiss)
        .clashTextFieldAlert("Rename", isPresented: $renaming, text: $renameText,
                             field: ClashTextFieldAlertField(placeholder: "Name",
                                                             identifier: "configuration.rule-set-detail.rename.name")) { typed in
            let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name != set.name else { return }
            var renamed = set
            renamed.name = name
            perform { try await save(renamed) }
        }
         
         
         
         
        .clashProductModal(isPresented: $editing, role: .form) {
            ClashSingleColumnNavigationContainer {
                ClashTowerLocalRuleEditor(
                    value: set, policy: "DIRECT", options: .empty, palette: .clashProduct,
                    buildRule: { line, accept in ConfigurationLibraryRuleSetsPage.ruleBuilder(line, accept) },
                    attaches: false,
                    save: { name, input, _ in
                        let edited = try await ConfigurationRuleSetDetailSnapshot.edited(set, name: name, input: input)
                        try await save(edited)
                        editing = false
                    },
                    close: { editing = false })
            }
            .environment(\.clashProductModalDismiss, { editing = false })
        }
    }

    private func valueRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ClashTheme.Spacing.row) {
            Text(clash: .copy(title)).foregroundStyle(.primary)
            Spacer(minLength: ClashTheme.Spacing.row)
            Text(verbatim: value).foregroundStyle(.secondary)
        }
    }

    private func apply(_ value: ConfigurationLibrarySnapshot) {
        library = value
        if let now = value.localRuleSets?.first(where: { $0.id == set.id }) { set = now }
        changed(value)
    }

     
    private func readUsers() async {
        guard let store = model.configurationLibraryStore else { return }
        let id = set.id, library = library
        let profiles = model.profiles.map { LibraryUsage.Configuration(id: $0.id, name: $0.label) }
        let users = await Task.detached(priority: .userInitiated) {
            try? ConfigurationRuleSetDetailSnapshot.users(of: id, in: library, store: store, profiles: profiles)
        }.value
        if let users { usedBy = users }
    }

     
     
     
     
    private func save(_ value: ConfigurationLocalRuleSet) async throws {
        guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        let now = try await Task.detached(priority: .userInitiated) { try store.snapshot() }.value
        guard now.localRuleSets?.first(where: { $0.id == set.id }) == set else { throw ConfigurationLibraryError.staleGeneration }
        apply(try await model.saveConfigurationLocalRuleSet(value, deleting: nil, generation: now.generation))
    }

     
    private func update(_ link: String) {
        let current = set
        perform {
            let read = try await ConfigurationTowerRuleReader.ruleSet(link)
            var value = current
            value.rules = read.rules
            value.link = read.link
            value.behavior = read.behavior
            try await save(value)
        }
    }

     
     
     
    private func delete() {
        let name = set.name, id = set.id
        perform {
            let deletion = try await model.deleteConfigurationLocalRuleSetRestorably(
                id, generation: try await ConfigurationRuleSetDetailSnapshot.currentGeneration(model))
            changed(deletion.snapshot)
            dismiss()
            ConfigurationLibraryUndo.offer(feedback, name: name, deletion: deletion, model: model, changed: changed)
        }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true; failure = nil
        Task { @MainActor in
            defer { busy = false }
            do { try await operation() } catch { failure = ClashErrorCopy.text(error) }
        }
    }
}

 
private struct CollectionRuleSetDetail: View {
    let model: ProfilesViewModel
    let entry: ConfigurationCollectionEntry
    let brought: Bool
    let library: ConfigurationLibrarySnapshot
    let changed: (ConfigurationLibrarySnapshot) -> Void
     
     
    @StateObject private var reader: ConfigurationCollectionReader
    @Environment(\.locale) private var locale
    @Environment(\.clashFeedback) private var feedback
    @StateObject private var dismiss = ClashDismissHandle()
    @State private var busy = false
    @State private var failure: ClashDisplayText?
    @State private var deleting = false
    @State private var deletingSource = false
    @State private var editingSource = false

    init(model: ProfilesViewModel, entry: ConfigurationCollectionEntry, brought: Bool, library: ConfigurationLibrarySnapshot,
         changed: @escaping (ConfigurationLibrarySnapshot) -> Void) {
        self.model = model; self.entry = entry; self.brought = brought; self.library = library; self.changed = changed
        _reader = StateObject(wrappedValue: ConfigurationCollectionReader(model: model, entry: entry))
    }

    private var snapshot: ConfigurationRuleSetDetailSnapshot {
        let users = ConfigurationRuleSetDetailSnapshot.users(ofCollection: entry, in: library, profiles: model.profiles.map {
            LibraryUsage.Configuration(id: $0.id, name: $0.label)
        })
        return .collection(entry, brought: brought, usedBy: users, locale: locale)
    }

    var body: some View {
        let snapshot = self.snapshot
        Form {
            Section {
                valueRow("Name", value: snapshot.name)
                    .accessibilityIdentifier("configuration.rule-set-detail.name")
            }
            sourceSection(snapshot)
            Section {
                ClashNativeNavigationLink {
                    ConfigurationRuleSetRulesPage(model: model, source: .collection(entry), title: snapshot.name, sharedNote: nil,
                                                  changed: changed)
                } label: {
                    valueRow("Rules", value: (snapshot.ruleCount ?? reader.page.count).map { ClashCopy.count($0, locale: locale) } ?? "")
                }
                .accessibilityIdentifier("configuration.rule-set-detail.rules")
            }
            Section {
                if snapshot.usedBy.isEmpty {
                    Text(clash: .copy(ConfigurationRuleSetDetailSnapshot.noUsersKey)).foregroundStyle(.secondary)
                        .accessibilityIdentifier("configuration.rule-set-detail.used-by.none")
                }
                ForEach(Array(snapshot.usedBy.enumerated()), id: \.offset) { _, name in
                    Text(verbatim: name).accessibilityIdentifier("configuration.rule-set-detail.used-by")
                }
            } header: { Text(clash: .copy(ConfigurationRuleSetDetailSnapshot.usersHeaderKey)) }
            Section {
                Button("Add Rule Scheme", action: makeScheme)
                    .accessibilityIdentifier("configuration.rule-set-detail.add-scheme")
                 
                 
                Button("Edit Source") { editingSource = true }
                    .disabled(!snapshot.canEditSource)
                    .accessibilityIdentifier("configuration.rule-set-detail.edit-source")
            }
            deletionSection(snapshot)
            if let failure {
                Section {
                    Text(clash: failure).foregroundStyle(.orange)
                        .accessibilityIdentifier("configuration.rule-set-detail.failure")
                }
            }
        }
        .disabled(busy)
        .clashPageTitle(.verbatim(entry.collection.name), watchAs: "rule-set-detail")
        .clashCapturesDismiss(dismiss)
        .task {
            reader.locale = locale
            await reader.load()
        }
        .onChange(of: locale) { reader.locale = $0 }
        .clashOnScreen { reader.running.follow($0) }
        .onReceive(NotificationCenter.default.publisher(for: .clashActiveConfigurationRepublished)) { _ in
            Task { await reader.running.reload() }
        }
         
         
        .onReceive(model.$ruleCollectionUpdate.map { [id = entry.id] run in
            run.map { !$0.finished && $0.updating.contains(id) } ?? false
        }.removeDuplicates()) { inFlight in
            reader.followRun(inFlight: inFlight)
        }
        .onReceive(NotificationCenter.default.publisher(for: ConfigurationCollectionContentBridge.libraryCopiesDidFollow)) { _ in
            Task { await reader.reloadIfTheCopyChanged() }
        }
        .clashProductModal(isPresented: $editingSource, role: .page) {
            let profile = Profile(id: entry.source.id, label: entry.collection.name, source: .clipboard, autoUpdate: false,
                                  updateIntervalHours: 0, subscriptionInfo: nil, selectedMap: [:], activeRevision: nil, order: 0,
                                  lastUpdatedAt: nil)
            ProfileEditView(profile: profile, rawYAML: entry.collection.definition.serialized(), editorTitle: "Edit Source") { _, text, files, _ in
                guard let text, files.isEmpty else { throw ConfigurationLibraryError.unreadable }
                let json = try ConfigTransforms.yamlToJSON(text)
                changed(try await model.saveConfigurationCollection(entry, definitionJSON: json))
                dismiss()
            }
        }
    }

     
     
     
    private func sourceSection(_ snapshot: ConfigurationRuleSetDetailSnapshot) -> some View {
        Section {
            if let link = snapshot.link {
                Text(verbatim: link).textSelection(.enabled)
                    .accessibilityIdentifier("configuration.rule-set-detail.link")
                Button("Copy Link") { ClashClipboard.copy(link, feedback: feedback, operation: "configuration.rule-set-detail.copy-link") }
                    .accessibilityIdentifier("configuration.rule-set-detail.copy-link")
                 
                 
                Button { Task { await reader.update() } } label: {
                    HStack {
                        Text(clash: .copy("Update Source"))
                        if reader.updating || reader.runHasThis {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(reader.updating || reader.runHasThis)
                .accessibilityIdentifier("configuration.rule-set-detail.update")
            } else {
                Text(clash: .copy("Local")).accessibilityIdentifier("configuration.rule-set-detail.local")
            }
            if snapshot.deletesSource {
                Button("Delete Source", role: .destructive) { deletingSource = true }
                    .accessibilityIdentifier("configuration.rule-set-detail.delete-source")
            }
        } header: {
            Text(clash: .copy("Source"))
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: reader.status(locale: locale))
                    .accessibilityIdentifier("configuration.rule-set-detail.status")
                if let error = reader.shownError {
                    Text(verbatim: error).foregroundStyle(.red)
                }
            }
        }
        .clashDeleteConfirmation(entry.source.displayLabel(locale: locale), isPresented: $deletingSource,
                                 actionTitle: .copy("Delete Source"),
                                 message: .copy("Saved profiles keep their current content and stop following this source."),
                                 identifier: "configuration.rule-set-detail.delete-source.confirm", action: deleteSource)
    }

     
     
    private func deletionSection(_ snapshot: ConfigurationRuleSetDetailSnapshot) -> some View {
        let refusal: String? = { if case .refused(let reason) = snapshot.deletion { return reason }; return nil }()
        return Section {
            Button("Delete Rule Set", role: .destructive) { deleting = true }
                .disabled(refusal != nil)
                .accessibilityIdentifier("configuration.rule-set-detail.delete")
        } footer: {
            if let refusal {
                Text(verbatim: refusal).accessibilityIdentifier("configuration.rule-set-detail.delete.note")
            }
        }
        .clashDeleteConfirmation(entry.collection.name, isPresented: $deleting, actionTitle: .copy("Delete Rule Set"),
                                 message: .copy(ConfigurationRuleSetDetailSnapshot.confirmationKey(entry)),
                                 identifier: "configuration.rule-set-detail.delete.confirm", action: deleteCollection)
    }

    private func valueRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ClashTheme.Spacing.row) {
            Text(clash: .copy(title)).foregroundStyle(.primary)
            Spacer(minLength: ClashTheme.Spacing.row)
            Text(verbatim: value).foregroundStyle(.secondary)
        }
    }

     
    private func makeScheme() {
        perform {
            guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            let entry = entry
            let updated = try await Task.detached(priority: .userInitiated) {
                try store.addRuleScheme(collection: entry, expectedGeneration: store.snapshot().generation)
            }.value
            changed(updated)
            dismiss()
        }
    }

     
    private func deleteCollection() {
        perform {
            changed(try await model.saveConfigurationCollection(entry, definitionJSON: nil))
            dismiss()
        }
    }

     
     
    private func deleteSource() {
        let name = entry.source.displayLabel(locale: locale), id = entry.source.id
        perform {
            let deletion = try await model.deleteConfigurationSourceRestorably(
                id, generation: try await ConfigurationRuleSetDetailSnapshot.currentGeneration(model))
            changed(deletion.snapshot)
            dismiss()
            ConfigurationLibraryUndo.offer(feedback, name: name, deletion: deletion, model: model, changed: changed)
        }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true; failure = nil
        Task { @MainActor in
            defer { busy = false }
            do { try await operation() } catch { failure = ClashErrorCopy.text(error) }
        }
    }
}
#endif
