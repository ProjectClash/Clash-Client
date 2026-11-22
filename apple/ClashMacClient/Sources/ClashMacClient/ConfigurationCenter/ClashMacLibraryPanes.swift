import ClashClientKit
import ClashClientUI
import Combine
import SwiftUI

 
 
public struct ClashMacSourcePaneActions {
     
     
     
     
     
     
     
    public var save: @MainActor (_ label: String, _ settings: ConfigurationSourceSettingsDraft?) async -> String?
    public var update: @MainActor () -> Void
    public var delete: @MainActor () -> Void
     
    public var editSource: (@MainActor () -> Void)?

    public init(
        save: @escaping @MainActor (String, ConfigurationSourceSettingsDraft?) async -> String?,
        update: @escaping @MainActor () -> Void,
        delete: @escaping @MainActor () -> Void,
        editSource: (@MainActor () -> Void)? = nil
    ) {
        self.save = save; self.update = update; self.delete = delete
        self.editSource = editSource
    }

    public static var unavailable: Self { Self(save: { _, _ in nil }, update: {}, delete: {}) }
}

 
 
public struct ClashMacSchemePaneActions {
    public var edit: @MainActor () -> Void
     
     
     
     
    public var duplicate: @MainActor () async throws -> String
     
     
     
    public var update: @MainActor () async throws -> Bool
    public var delete: @MainActor () -> Void
     
    public var load: @MainActor () async throws -> ClashMacRuleEditorState
     
    public var page: (@MainActor (String) -> AnyView)?
     
     
     
    public var editAt: (@MainActor (ClashMacRuleEditorSheet.Pane) -> Void)? = nil
     
     
     
    public var rename: (@MainActor (String) async throws -> Void)? = nil
     
     
     
     
    public var waitForUpdateAll: (@MainActor (_ waiting: @escaping @MainActor () -> Void) async -> Void)? = nil

    public init(
        edit: @escaping @MainActor () -> Void,
        duplicate: @escaping @MainActor () async throws -> String,
        update: @escaping @MainActor () async throws -> Bool = { false },
        delete: @escaping @MainActor () -> Void,
        load: @escaping @MainActor () async throws -> ClashMacRuleEditorState = { throw ConfigurationLibraryError.unreadable },
        page: (@MainActor (String) -> AnyView)? = nil,
        editAt: (@MainActor (ClashMacRuleEditorSheet.Pane) -> Void)? = nil
    ) {
        self.edit = edit; self.duplicate = duplicate; self.update = update; self.delete = delete; self.load = load; self.page = page
        self.editAt = editAt
    }

    public static var unavailable: Self { Self(edit: {}, duplicate: { throw ConfigurationLibraryError.unreadable }, delete: {}) }

     
    public func renaming(_ rename: @escaping @MainActor (String) async throws -> Void) -> Self {
        var actions = self
        actions.rename = rename
        return actions
    }

     
    public func waitingOutUpdateAll(_ wait: @escaping @MainActor (_ waiting: @escaping @MainActor () -> Void) async -> Void) -> Self {
        var actions = self
        actions.waitForUpdateAll = wait
        return actions
    }
}

 
 
 
 
public struct ClashMacSchemePane: View {
    private let scheme: ConfigurationRuleScheme
    private let source: ConfigurationSourceRecord?
    private let usedBy: [ClashProfileSnapshot]
    private let actions: ClashMacSchemePaneActions
     
    public var updateError: String?
    @Environment(\.clashPushRoute) private var pushRoute
    @Environment(\.locale) private var locale
    @State private var busy = false
     
    @State private var status: ClashDisplayText?
    @State private var failure: String?
    @State private var renaming = false
     
    @State private var waitingForUpdateAll = false

    public init(scheme: ConfigurationRuleScheme, source: ConfigurationSourceRecord?, usedBy: [ClashProfileSnapshot], actions: ClashMacSchemePaneActions) {
        self.scheme = scheme
        self.source = source
        self.usedBy = usedBy
        self.actions = actions
    }

    private var kind: ClashDisplayText {
        switch scheme.kind {
        case .builtin: .copy("Built-in")
        case .community: .copy("Community")
        case .custom: .copy("Custom")
        case .imported, .supplied: .copy("Imported")
        }
    }

     
     
     
     
     
     
     
     
    private var isEditable: Bool { scheme.isRetainedSnapshot != true }
    private var comesFromLink: Bool {
        if case .subscription = source?.origin { return true }
        return false
    }

    public var body: some View {
         
         
         
        Form {
            header
             
             
             
             
            Section {
                LabeledContent { Text(clash: kind) } label: { Text(clash: .copy("Kind")) }
                if let source {
                     
                     
                     
                     
                     
                    if isEditable, let editAt = actions.editAt {
                        Button { editAt(.groups) } label: { countRow(.copy("Policy Groups"), source.groupCount) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("configuration-center.scheme.groups")
                        Button { editAt(.rules) } label: { countRow(.copy("Rules"), source.ruleCount) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("configuration-center.scheme.rules")
                    } else {
                        ClashRoutedViewLink {
                            ClashMacRuleBrowsePage(kind: .groups, load: actions.load, edit: isEditable ? actions.edit : nil)
                                .navigationTitle(Text(clash: .copy("Policy Groups")))
                        } label: {
                            countRow(.copy("Policy Groups"), source.groupCount)
                        }
                        .accessibilityIdentifier("configuration-center.scheme.groups")
                        ClashRoutedViewLink {
                            ClashMacRuleBrowsePage(kind: .rules, load: actions.load, edit: isEditable ? actions.edit : nil)
                                .navigationTitle(Text(clash: .copy("Rules")))
                        } label: {
                            countRow(.copy("Rules"), source.ruleCount)
                        }
                        .accessibilityIdentifier("configuration-center.scheme.rules")
                    }
                }
            }
            Section {
                if usedBy.isEmpty {
                    Text(clash: .copy("None")).foregroundStyle(.secondary)
                } else {
                     
                    ForEach(usedBy) { profile in
                        Text(verbatim: profile.label)
                            .accessibilityIdentifier("configuration-center.scheme.used-by.\(profile.id.rawValue)")
                    }
                }
            } header: {
                Text(clash: .copy("Used by Profiles"))
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("configuration-center.scheme")
        .sheet(isPresented: $renaming) {
            ClashMacNamePrompt(
                title: .copy("Rename…"),
                 
                 
                 
                 
                 
                initial: scheme.labelAsRead(locale: locale),
                nameIdentifier: "configuration-center.scheme.rename.name",
                cancelIdentifier: "configuration-center.scheme.rename.cancel",
                saveIdentifier: "configuration-center.scheme.rename.save",
                commit: { typed in
                    if let name = scheme.newName(typed: typed, locale: locale) { try await actions.rename?(name) }
                    renaming = false
                },
                close: { renaming = false }
            )
        }
    }

     
     
    private func countRow(_ title: ClashDisplayText, _ count: Int) -> some View {
        LabeledContent { Text(verbatim: String(count)) } label: { Text(clash: title) }
            .contentShape(Rectangle())
    }

     
     
     
    private var header: some View {
        Section {
            LabeledContent {
                HStack(spacing: ClashTheme.Spacing.compact) {
                    if busy || waitingForUpdateAll { ProgressView().controlSize(.small) }
                     
                     
                     
                     
                    if isEditable {
                        Button { actions.edit() } label: { Text(clash: .copy("Edit")) }
                            .disabled(busy)
                            .accessibilityIdentifier("configuration-center.scheme.edit")
                    }
                    Menu {
                        Button { perform { let id = try await actions.duplicate(); open(id) } } label: { Text(clash: .copy("Copy Rule Scheme")) }
                            .accessibilityIdentifier("configuration-center.scheme.duplicate")
                        if actions.rename != nil, ClashTowerRulesLibraryView.canRename(scheme) {
                            Button { renaming = true } label: { Text(clash: .copy("Rename…")) }
                                .accessibilityIdentifier("configuration-center.scheme.rename")
                        }
                        if comesFromLink {
                            Button { updateScheme() } label: { Text(clash: .copy("Update")) }
                                .disabled(waitingForUpdateAll)
                                .accessibilityIdentifier("configuration-center.scheme.update")
                        }
                        if scheme.canBeDeleted {
                            Divider()
                             
                             
                            Button(role: .destructive) { actions.delete() } label: {
                                Text(clash: .copy("Delete"))
                            }
                            .accessibilityIdentifier("configuration-center.scheme.delete")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .fixedSize()
                    .disabled(busy)
                    .accessibilityIdentifier("configuration-center.scheme.more")
                }
            } label: {
                Text(clash: kind)
            }
            if let text = failure ?? updateError {
                Text(verbatim: text)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("configuration-center.scheme.update-error")
            } else if let status {
                Text(clash: status)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("configuration-center.scheme.update-status")
            }
        }
    }

     
     
     
    private func updateScheme() {
        guard !busy, !waitingForUpdateAll else { return }
        Task { @MainActor in
            if let wait = actions.waitForUpdateAll {
                await wait {
                    waitingForUpdateAll = true
                    failure = nil
                    status = .copy("Waiting for the current update to finish…")
                }
                waitingForUpdateAll = false
            }
            perform { status = try await actions.update() ? .copy("Updated") : .copy("Up to date") }
        }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        failure = nil
        status = nil
        Task { @MainActor in
            defer { busy = false }
            do { try await operation() } catch { failure = ClashErrorCopy.message(error, locale: locale) }
        }
    }

     
     
    private func open(_ id: String) {
        guard let page = actions.page, let pushRoute else { return }
        let token = UUID()
        ClashViewRouteRegistry.set(token, ownership: .oneShot, onReturn: {}) { page(id) }
        pushRoute(ClashViewRoute(id: token))
    }
}

 
 
 
struct ClashMacRuleBrowsePage: View {
    enum Kind { case groups, rules }

    let kind: Kind
    let load: @MainActor () async throws -> ClashMacRuleEditorState
     
     
     
    var edit: (@MainActor () -> Void)? = nil
    @State private var state: ClashMacRuleEditorState?
    @State private var error: String?
    @State private var filter = ""
     
    @State private var expanded: Set<UUID> = []
    @Environment(\.configurationFieldCopy) private var copy
    @Environment(\.locale) private var locale
    @Environment(\.defaultMinListRowHeight) private var inheritedRowHeight

    private var needle: String { filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

     
     
    private static func members(of group: ConfigurationRuleDraft.Group) -> [String] {
        var names: [String] = []
        if case .array(let values) = group.document.topLevelValue("proxies") {
            names += values.compactMap { if case .string(let value) = $0 { return value }; return nil }
        }
        if case .array(let values) = group.document.topLevelValue("use") {
            names += values.compactMap { if case .string(let value) = $0 { return value }; return nil }
        }
        return names
    }

    var body: some View {
         
         
        List {
            if let edit {
                Section {
                    Button { edit() } label: { Text(clash: .copy("Edit")) }
                        .accessibilityIdentifier("configuration-center.scheme.browse.edit")
                }
            }
            if let error {
                Section {
                    Text(verbatim: error).foregroundStyle(.red)
                        .accessibilityIdentifier("configuration-center.scheme.browse.error")
                }
            }
            if let state {
                switch kind {
                case .groups:
                    Section {
                         
                         
                        let typeNames = ClashMacValueWords.valueNames(path: "proxy-groups[*].type", copy: copy, locale: locale)
                        ForEach(groups(in: state)) { group in
                             
                             
                            DisclosureGroup(isExpanded: isOpen(group.id)) {
                                ForEach(Array(Self.members(of: group).enumerated()), id: \.offset) { _, member in
                                    Text(verbatim: member).foregroundStyle(.secondary)
                                }
                            } label: {
                                 
                                 
                                Button { isOpen(group.id).wrappedValue.toggle() } label: {
                                    LabeledContent {
                                        Text(verbatim: typeNames[group.type.lowercased()] ?? group.type)
                                    } label: { Text(verbatim: group.name) }
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("configuration-center.scheme.browse.group")
                            }
                        }
                    }
                case .rules:
                    Section {
                        ForEach(rules(in: state)) { row in
                             
                             
                            ConfigurationRuleRow(row.raw, showsChevron: false)
                                .opacity(state.draft.disabledRules.contains(row.raw) ? 0.5 : 1)
                        }
                    }
                }
            } else if error == nil {
                Section { ProgressView().controlSize(.small) }
            }
        }
        .listStyle(.inset)
         
        .environment(\.defaultMinListRowHeight, kind == .rules ? ClashMacRuleListMetrics.leastRowHeight : inheritedRowHeight)
        .clashProductModalSearchable(text: $filter, prompt: Text(clash: .copy("Filter")))
        .task {
            do { state = try await load() } catch { self.error = ClashErrorCopy.message(error, locale: locale) }
        }
    }

     
    private func isOpen(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { open in if open { expanded.insert(id) } else { expanded.remove(id) } }
        )
    }

     
     
    private func groups(in state: ClashMacRuleEditorState) -> [ConfigurationRuleDraft.Group] {
        let needle = needle
        guard !needle.isEmpty else { return state.draft.groups }
        let typeNames = ClashMacValueWords.valueNames(path: "proxy-groups[*].type", copy: copy, locale: locale)
        return state.draft.groups.filter {
            $0.name.lowercased().contains(needle) || $0.type.lowercased().contains(needle)
                || (typeNames[$0.type.lowercased()]?.lowercased().contains(needle) ?? false)
        }
    }

     
     
    private func rules(in state: ClashMacRuleEditorState) -> [ConfigurationRuleDraft.Row] {
        let needle = needle
        guard !needle.isEmpty else { return state.draft.rows }
        return state.draft.rows.filter { Self.rule($0.raw, matches: needle, locale: locale, copy: copy) }
    }

     
    static func rule(_ raw: String, matches needle: String, locale: Locale, copy: ConfigurationFieldCopy = .shared) -> Bool {
        if raw.lowercased().contains(needle) { return true }
        let words = ConfigurationRuleWords.of(raw, locale: locale, copy: copy)
        return [words.match, words.kind, words.target ?? ""].contains { $0.lowercased().contains(needle) }
    }
}

 
 
public struct ClashMacCollectionPage: Equatable, Sendable {
    public struct Row: Identifiable, Equatable, Sendable {
        public let id: Int
        public let title: String
        public let subtitle: String?
        public init(id: Int, title: String, subtitle: String?) { self.id = id; self.title = title; self.subtitle = subtitle }
    }
    public var rows: [Row]
    public var count: Int?
    public var updatedAt: Date?
    public var nextOffset: Int?
    public var message: String?

    public init(rows: [Row] = [], count: Int? = nil, updatedAt: Date? = nil, nextOffset: Int? = nil, message: String? = nil) {
        self.rows = rows; self.count = count; self.updatedAt = updatedAt; self.nextOffset = nextOffset; self.message = message
    }
}

 
 
 
 
public enum ClashMacCollectionUpdateStep: Equatable, Sendable {
     
    case waiting
     
    case downloading
     
     
    case applying(libraryCopyIn: Bool)
     
     
     
    case takingEffect
     
     
    case tunnelDownloading(onlyRuleSets: Bool)
}

 
 
public struct ClashMacCollectionInUse: Equatable, Sendable {
    public var count: Int
     
     
    public var ofThisCopy: Bool
    public init(count: Int, ofThisCopy: Bool = false) { self.count = count; self.ofThisCopy = ofThisCopy }
}

 
 
 
 
public struct ClashMacCollectionPageActions {
    public var load: @MainActor (String, Int) async throws -> ClashMacCollectionPage
     
     
     
     
    public var update: (@MainActor (_ step: @escaping @MainActor (ClashMacCollectionUpdateStep) -> Void) async throws -> String?)?
     
     
     
     
     
    public var runningCount: (@MainActor () async -> ClashMacCollectionInUse?)?
     
     
    public var runningCountChanges: AnyPublisher<Void, Never>?
     
     
     
    public var inSharedRun: AnyPublisher<Bool, Never>?
     
     
     
     
    public var copyChanges: AnyPublisher<Void, Never>?
    public var createScheme: (@MainActor () async throws -> Void)?
    public var editSource: (@MainActor () -> Void)?
    public var delete: (@MainActor () async throws -> Void)?
     
     
     
     
    public var definitionIsEditable = true

    public init(
        load: @escaping @MainActor (String, Int) async throws -> ClashMacCollectionPage,
        update: (@MainActor (_ step: @escaping @MainActor (ClashMacCollectionUpdateStep) -> Void) async throws -> String?)? = nil,
        createScheme: (@MainActor () async throws -> Void)? = nil,
        editSource: (@MainActor () -> Void)? = nil,
        delete: (@MainActor () async throws -> Void)? = nil
    ) {
        self.load = load; self.update = update; self.createScheme = createScheme; self.editSource = editSource; self.delete = delete
    }

    public static var unavailable: ClashMacCollectionPageActions {
        ClashMacCollectionPageActions(load: { _, _ in ClashMacCollectionPage() })
    }
}

 
 
 
 
 
public struct ClashMacCollectionPane: View {
    private let collection: ConfigurationCollection
    private let sourceLabel: String?
    private let actions: ClashMacCollectionPageActions
    @State private var page: ClashMacCollectionPage?
    @State private var filter = ""
     
    @State private var readsInFlight = 0
     
     
     
    @State private var readTicket = 0
     
     
    @State private var shownTicket = 0
     
    @State private var sharedRunHasThis = false
    @State private var busy = false
    @State private var error: String?
    @State private var confirmsDeletion = false
     
     
     
     
    @State private var updating = false
     
    @State private var updatePhase: String?
     
     
     
    @State private var updateFailure: String?
     
     
    @State private var updateWord: String?
     
     
    @State private var updateWordSaidAt: Date?
     
    @State private var runningCount: ClashMacCollectionInUse?
     
     
    @State private var countTicket = 0
    private var loading: Bool { readsInFlight > 0 }
    @Environment(\.locale) private var locale
    @Environment(\.configurationFieldCopy) private var copy
     
     
    @Environment(\.clashFeedback) private var feedback

    public init(collection: ConfigurationCollection, sourceLabel: String? = nil, actions: ClashMacCollectionPageActions = .unavailable) {
        self.collection = collection
        self.sourceLabel = sourceLabel
        self.actions = actions
        _countChanges = State(initialValue: actions.runningCountChanges ?? Empty().eraseToAnyPublisher())
        _sharedRun = State(initialValue: actions.inSharedRun ?? Empty().eraseToAnyPublisher())
        _copyChanges = State(initialValue: actions.copyChanges ?? Empty().eraseToAnyPublisher())
    }

     
     
     
     
    @State private var countChanges: AnyPublisher<Void, Never>
    @State private var sharedRun: AnyPublisher<Bool, Never>
    @State private var copyChanges: AnyPublisher<Void, Never>

    private static let dateFormatters = ClashMacDateFormatterCache(dateStyle: .medium, timeStyle: .short)

    private var status: String {
        var parts: [String] = []
        if let sourceLabel { parts.append(sourceLabel) }
         
         
         
         
         
        parts += ClashConfigurationCollectionCopy.members(
            of: collection, count: page?.count, inUse: runningCount?.count,
            inUseIsThisCopy: runningCount?.ofThisCopy ?? false
        ).map { ClashCopy.string(for: $0, locale: locale) }
        if let date = page?.updatedAt { parts.append(Self.dateFormatters.formatter(for: locale).string(from: date)) }
        if let message = page?.message { parts.append(message) }
        return parts.joined(separator: " · ")
    }

    public var body: some View {
         
         
         
        List {
            header
            details
            members
        }
        .listStyle(.inset)
        .clashProductModalSearchable(text: $filter, prompt: Text(clash: .copy("Filter")))
        .accessibilityIdentifier("configuration-center.collection")
        .task(id: filter) {
            if !filter.isEmpty { try? await Task.sleep(nanoseconds: 180_000_000) }
            guard !Task.isCancelled else { return }
            await load()
        }
        .task { await loadRunningCount() }
        .onReceive(countChanges) { _ in
            Task { await loadRunningCount() }
        }
        .onReceive(sharedRun) { inFlight in
            let was = sharedRunHasThis
            sharedRunHasThis = inFlight
            if was && !inFlight { Task { await refreshIfChanged(); await loadRunningCount() } }
        }
         
         
         
        .onReceive(copyChanges) { _ in
            Task { await refreshIfChanged(); await loadRunningCount() }
        }
        .alert(Text(clash: .copy("Delete Collection")), isPresented: $confirmsDeletion) {
            Button(role: .destructive) {
                perform {
                    try await actions.delete?()
                    feedback?.say(ClashMacFeedbackSentences.deleted(collection.name, undoable: false, id: "collection.delete"),
                                   operation: "collection.delete")
                }
            } label: { Text(clash: .copy("Delete Collection")) }
                .accessibilityIdentifier("configuration-center.collection.delete.confirm")
            Button(role: .cancel) {} label: { Text(clash: .copy("Cancel")) }
        } message: {
            Text(clash: .copy("Remove this collection from its source. Profiles that reference it must choose another collection first."))
        }
    }

     
     
    private var header: some View {
        Section {
            LabeledContent {
                HStack(spacing: ClashTheme.Spacing.compact) {
                    if loading || busy || updating || sharedRunHasThis { ProgressView().controlSize(.small) }
                    if actions.update != nil {
                        Button { Task { await update() } } label: { Text(clash: .copy("Update Source")) }
                            .disabled(busy || updating)
                            .accessibilityIdentifier("configuration-center.collection.update")
                    }
                    if actions.createScheme != nil || actions.editSource != nil || actions.delete != nil {
                        Menu {
                            if actions.createScheme != nil {
                                 
                                Button { perform { try await actions.createScheme?() } } label: { Text(clash: .copy("Add Rule Scheme")) }
                            }
                            if let editSource = actions.editSource {
                                Button { editSource() } label: { Text(clash: .copy("Edit Source")) }
                                    .disabled(!actions.definitionIsEditable)
                            }
                            if actions.delete != nil {
                                Divider()
                                Button(role: .destructive) { confirmsDeletion = true } label: { Text(clash: .copy("Delete Collection")) }
                                    .disabled(!actions.definitionIsEditable)
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .fixedSize()
                        .disabled(busy || updating)
                        .accessibilityIdentifier("configuration-center.collection.manage")
                    }
                }
            } label: {
                Text(verbatim: status.isEmpty ? collection.name : status).lineLimit(1).truncationMode(.middle)
            }
            if let updatePhase {
                Text(verbatim: updatePhase).foregroundStyle(.secondary)
                    .accessibilityIdentifier("configuration-center.collection.update-phase")
            } else if let updateWord {
                Text(clash: .copy(updateWord)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("configuration-center.collection.update-result")
            }
            if error != nil || updateFailure != nil {
                Text(verbatim: [error, updateFailure].compactMap { $0 }.joined(separator: "\n")).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("configuration-center.collection.error")
            }
        }
    }

    private var details: some View {
        let hasFormat = collection.id.kind == .rules
        let behavior = hasFormat ? collection.behavior : nil
         
         
        let base = hasFormat ? "rule-providers.*." : "proxy-providers.*."
        return Section {
            LabeledContent {
                Text(verbatim: ClashMacValueWords.valueName(collection.type, path: base + "type", copy: copy, locale: locale))
            } label: { Text(clash: .copy("Type")) }
            if hasFormat {
                LabeledContent {
                    Text(verbatim: ClashMacValueWords.valueName(collection.format, path: base + "format", copy: copy, locale: locale))
                } label: { Text(clash: .copy("Format")) }
            }
            if let behavior {
                LabeledContent {
                    Text(verbatim: ClashMacValueWords.valueName(behavior, path: base + "behavior", copy: copy, locale: locale))
                } label: { Text(clash: .copy("Behavior")) }
            }
            if let location = collection.location {
                Text(verbatim: location).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var members: some View {
        let rows = page?.rows ?? []
        let typeNames = collection.id.kind == .nodes ? ClashMacValueWords.valueNames(path: "proxies[*].type", copy: copy, locale: locale) : [:]
        Section {
            if rows.isEmpty {
                Text(clash: .copy("None")).foregroundStyle(.secondary)
            }
             
             
             
             
             
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                    Text(verbatim: row.title)
                        .font(row.subtitle == nil ? .body.monospaced() : .body)
                        .lineLimit(1).truncationMode(.middle)
                    if let subtitle = row.subtitle, !subtitle.isEmpty {
                         
                        Text(verbatim: typeNames[subtitle.lowercased()] ?? subtitle)
                            .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("configuration-center.collection.row")
            }
            if let more = page?.nextOffset {
                Button { Task { await load(offset: more) } } label: { Text(clash: .copy("Load More")) }
                    .accessibilityIdentifier("configuration-center.collection.more")
            }
        } header: {
            Text(clash: .copy("Members"))
        }
    }

    private func load(offset: Int = 0) async {
        if offset == 0 {
            readTicket &+= 1
        } else if shownTicket != readTicket {
             
             
            return
        }
        let ticket = readTicket
        readsInFlight += 1
        defer { readsInFlight -= 1 }
        do {
            let loaded = try await actions.load(filter, offset)
             
             
            guard ticket == readTicket, offset == 0 || (shownTicket == ticket && page?.nextOffset == offset) else { return }
            if offset == 0 {
                page = loaded
                shownTicket = ticket
                retireUpdateWordIfPassed()
            } else {
                var merged = loaded
                merged.rows = (page?.rows ?? []) + loaded.rows
                page = merged
            }
            if offset == 0 { error = nil }
        } catch {
            guard ticket == readTicket, !(error is CancellationError) else { return }
             
             
             
             
            if offset == 0 { page?.nextOffset = nil }
            self.error = ClashErrorCopy.message(error, locale: locale)
        }
    }

     
     
     
     
     
    private func update() async {
        guard !updating, let update = actions.update else { return }
        updating = true
        updateFailure = nil
        updateWord = nil
        updateWordSaidAt = nil
        defer { updating = false; updatePhase = nil }
        var shownCopy = false
        do {
            updateWord = try await update { step in
                switch step {
                case .waiting:
                    updatePhase = ClashCopy.string("Waiting for the current update to finish…", locale: locale)
                case .downloading:
                    updatePhase = nil
                case .applying(let libraryCopyIn):
                    updatePhase = ClashCopy.string("Applying to the configuration in use…", locale: locale)
                    if libraryCopyIn {
                        shownCopy = true
                        Task { await load() }
                    }
                case .takingEffect:
                     
                    updatePhase = ClashCopy.string("Waiting for the tunnel to load the update…", locale: locale)
                case .tunnelDownloading(let onlyRuleSets):
                    updatePhase = ClashCopy.string(onlyRuleSets ? "Waiting for the tunnel to download rule sets…"
                                                                : "Downloading…", locale: locale)
                }
            }
        } catch {
            updateFailure = ClashErrorCopy.message(error, locale: locale)
        }
        if updateWord != nil { updateWordSaidAt = Date() }
        if !shownCopy { await load() }
        await loadRunningCount()
    }

     
     
     
     
    private func retireUpdateWordIfPassed() {
        guard updateWord != nil, let saidAt = updateWordSaidAt,
              !ClashConfigurationCollectionCopy.updateWordStands(saidAt: saidAt, lineUpdatedAt: page?.updatedAt) else { return }
        updateWord = nil
        updateWordSaidAt = nil
    }

     
     
     
     
    private func refreshIfChanged() async {
        guard let current = page else { await load(); return }
        let ticket = readTicket
        guard let fresh = try? await actions.load(filter, 0), ticket == readTicket else { return }
        guard fresh.updatedAt != current.updatedAt || fresh.count != current.count else { return }
        readTicket &+= 1
        shownTicket = readTicket
        page = fresh
        error = nil
        retireUpdateWordIfPassed()
    }

    private func loadRunningCount() async {
        guard let count = actions.runningCount else { return }
        countTicket &+= 1
        let ticket = countTicket
        let next = await count()
        guard ticket == countTicket else { return }
        if next != runningCount { runningCount = next }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        error = nil
        Task { @MainActor in
            defer { busy = false }
            do { try await operation() } catch { self.error = ClashErrorCopy.message(error, locale: locale) }
        }
    }
}
