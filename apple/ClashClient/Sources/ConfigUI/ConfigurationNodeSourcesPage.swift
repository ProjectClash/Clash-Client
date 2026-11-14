#if os(iOS)
import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
 
 
 
 
@MainActor
final class ConfigurationNodeSourcesModel: ObservableObject {
     
    enum Kind: CaseIterable {
        case profileURL, file, customNodes, chain, existingProfile

        var title: String {
            switch self {
            case .profileURL: "From Profile URLs"
            case .file: "From Files"
            case .customNodes: "Custom Nodes"
            case .chain: "Proxy Chains"
            case .existingProfile: "Existing Profiles"
            }
        }

        static func of(_ record: ConfigurationSourceRecord) -> Kind {
            if record.nodeChain != nil { return .chain }
            switch record.origin {
            case .subscription: return .profileURL
            case .file, .bundled: return .file
            case .customNodes: return .customNodes
            }
        }
    }

    struct SourceRow: Identifiable, Equatable {
        let id: String
        let label: String
        var detail: String?
        var isOn: Bool
        var kind: Kind
    }

     
    struct Node: Hashable {
        let name: String
        let type: String
    }

     
    struct NodeGroup: Identifiable, Equatable {
        let id: String
        let label: String
        let nodes: [Node]
        let providers: [Node]
    }

    @Published private(set) var rows: [SourceRow] = []
    @Published private(set) var groups: [NodeGroup] = []
    @Published private(set) var busy = false
    @Published var failure: String?
     
    @Published private(set) var pressed = ClashPressedSwitches<String>()
     
     
    private(set) var library = ConfigurationLibrarySnapshot()
     
     
    private var legacy: [String: ConfigurationSourcePayload] = [:]
    private var scopes: [String: ConfigurationNodeScope] = [:]
    let model: ProfilesViewModel
    let profileID: String
    var libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)?

    init(model: ProfilesViewModel, profileID: String, libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)? = nil) {
        self.model = model
        self.profileID = profileID
        self.libraryChanged = libraryChanged
    }

    func load() async {
        do {
            guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            let snapshot = try await Task.detached(priority: .userInitiated) { try store.snapshot() }.value
            library = snapshot
            guard let recipe = snapshot.recipes.first(where: { $0.id == profileID }) else {
                rows = []; groups = []; return
            }
            let selected = recipe.sources.map(\.id)
            scopes = recipe.nodeScopes ?? [:]
            let records = snapshot.sources.filter {
                $0.suppliesNodes && ($0.isListedInLibrary || selected.contains($0.id))
            }
            let locale = AppPreferences.language().locale
            var rows = records.map { record in
                SourceRow(id: record.id, label: record.displayLabel(locale: locale),
                          detail: Self.summary(nodes: record.nodeCount, providers: record.providerCount),
                          isOn: selected.contains(record.id), kind: Kind.of(record))
            }
             
             
            let known = Set(snapshot.sources.map(\.id))
            let older = (try? await model.configurationLegacyNodeSources(in: snapshot)) ?? [:]
            legacy = [:]
            for (owner, payload) in older where owner != profileID {
                let id = "legacy-" + owner
                guard !known.contains(id), payload.record.nodeCount > 0 || payload.record.providerCount > 0 else { continue }
                legacy[id] = payload
                let label = model.profiles.first { $0.id == owner }?.label ?? payload.record.label
                rows.append(SourceRow(id: id, label: label,
                                      detail: Self.summary(nodes: payload.record.nodeCount, providers: payload.record.providerCount),
                                      isOn: false, kind: .existingProfile))
            }
            self.rows = rows.sorted { lhs, rhs in
                lhs.kind == rhs.kind ? false : Kind.allCases.firstIndex(of: lhs.kind)! < Kind.allCases.firstIndex(of: rhs.kind)!
            }
            let scopes = self.scopes
            let ordered = selected.compactMap { id in snapshot.sources.first { $0.id == id } }
            groups = try await Task.detached(priority: .userInitiated) {
                try ordered.map { record in try Self.group(of: record, scope: scopes[record.id], in: store) }
            }.value
        } catch {
            failure = error.localizedDescription
        }
    }

     
     
     
    func isOn(_ id: String) -> Bool { pressed.shown(id, else: rows.first { $0.id == id }?.isOn ?? false) }

     
    func scope(of id: String) -> ConfigurationNodeScope? { scopes[id] }

    func record(of id: String) -> ConfigurationSourceRecord? { library.sources.first { $0.id == id } }

     
     
     
    func set(_ id: String, on: Bool) async {
        await set(id, on: on, press: pressed.press(id, on))
    }

     
     
     
     
    func pressSource(_ id: String, on: Bool) {
        let press = pressed.press(id, on)
        Task { await set(id, on: on, press: press) }
    }

    private func set(_ id: String, on: Bool, press: Int) async {
         
        defer { pressed.settle(id, press: press) }
        if on, let payload = legacy[id] {
            await edit { draft in Self.accept(payload, into: &draft) }
            return
        }
        await edit { draft in
            if on { if !draft.selectedSourceIDs.contains(id) { draft.selectedSourceIDs.append(id) } }
            else { draft.selectedSourceIDs.removeAll { $0 == id } }
        }
    }

     
     
    func setScope(_ id: String, _ scope: ConfigurationNodeScope?) async {
        await edit { draft in
            var scopes = draft.nodeScopes ?? [:]
            scopes[id] = scope?.isEmpty == true ? nil : scope
            draft.nodeScopes = scopes.isEmpty ? nil : scopes
            if scope?.isEmpty == true { draft.selectedSourceIDs.removeAll { $0 == id } }
            else if !draft.selectedSourceIDs.contains(id) { draft.selectedSourceIDs.append(id) }
        }
    }

     
     
     
     
    func add(_ payload: ConfigurationSourcePayload) async throws {
        while writing { await withCheckedContinuation { idle.append($0) } }
        writing = true
        failure = nil
        var thrown: Error?
        do { try await perform { draft in draft.add(payload, rule: nil) } } catch { thrown = error }
        await load()
        await drive()
        if let thrown { throw thrown }
    }

     

    typealias Change = (inout ConfigurationCreationDraft) -> Void

     
     
     
     
     
    private func edit(_ change: @escaping Change) async {
        await withCheckedContinuation { answer in
            waiting.append((change, answer))
            guard !writing else { return }
            writing = true
            failure = nil
            Task { await self.drive() }
        }
    }

     
    private func drive() async {
        while !waiting.isEmpty {
            let batch = waiting
            waiting = []
            await apply(batch.map(\.change))
            await load()
            batch.forEach { $0.answer.resume() }
        }
        writing = false
        let waiters = idle
        idle = []
        waiters.forEach { $0.resume() }
    }

     
     
     
    private func apply(_ changes: [Change]) async {
        do {
            try await perform { draft in for change in changes { change(&draft) } }
        } catch {
            guard changes.count > 1 else { return refused(error) }
            for change in changes {
                do { try await perform(change) } catch { refused(error) }
            }
        }
    }

    private func refused(_ error: Error) {
        failure = error.localizedDescription
        clashLogConfigurationWriteFailure(error)
    }

     
     
     
    private var writing = false { didSet { busy = writing } }
    private var waiting: [(change: Change, answer: CheckedContinuation<Void, Never>)] = []
    private var idle: [CheckedContinuation<Void, Never>] = []

     
     
    private func perform(_ change: @escaping Change) async throws {
        guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        let snapshot = try await Task.detached(priority: .userInitiated) { try store.snapshot() }.value
        guard let recipe = snapshot.recipes.first(where: { $0.id == profileID }) else { return }
        let label = model.profiles.first { $0.id == profileID }?.label ?? recipe.label
        let before = ConfigurationCreationAdapter.editingDraft(recipe: recipe, label: label)
        var draft = before
        change(&draft)
        guard draft != before else { return }
        try await model.editConfiguration(draft, id: profileID, generation: snapshot.generation)
        if let libraryChanged,
           let saved = try? await Task.detached(priority: .userInitiated, operation: { try store.snapshot() }).value {
            libraryChanged(saved)
        }
    }

     

    nonisolated static func summary(nodes: Int, providers: Int) -> String {
        let locale = AppPreferences.language().locale
        return providers > 0
            ? String(format: ClashCopy.string("%@ nodes · %@ providers", locale: locale), "\(nodes)", "\(providers)")
            : String(format: ClashCopy.string("%@ nodes", locale: locale), "\(nodes)")
    }

     
     
    private static func accept(_ payload: ConfigurationSourcePayload, into draft: inout ConfigurationCreationDraft) {
        let hasRules = payload.record.hasRules && payload.record.registersSuppliedRules != false
        let rule: ConfigurationRuleScheme? = hasRules
            ? .init(id: "rules-" + payload.record.id, label: payload.record.label, kind: .supplied, sourceID: payload.record.id) : nil
        draft.add(payload, rule: rule)
    }

     
     
     
    nonisolated static func group(of record: ConfigurationSourceRecord, scope: ConfigurationNodeScope?,
                                  in store: ConfigurationLibraryStore) throws -> NodeGroup {
        let group = try ConfigurationSourceContents.group(of: record, scope: scope, in: store)
        return NodeGroup(id: group.id, label: record.displayLabel(locale: AppPreferences.language().locale),
                         nodes: group.nodes.map { Node(name: $0.name, type: $0.type) },
                         providers: group.providers.map { Node(name: $0.name, type: $0.type) })
    }
}

 
 
 
 
 
 
struct ConfigurationNodeSourcesPage: View {
    @ObservedObject var model: ProfilesViewModel
    let section: ConfigurationOutlineSection
    @StateObject private var sources: ConfigurationNodeSourcesModel
    @State private var adding = false
    @State private var managing = false
    @State private var scoping: ScopeTarget?
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

     
    private struct ScopeTarget: Identifiable {
        let record: ConfigurationSourceRecord
        let scope: ConfigurationNodeScope?
        var id: String { record.id }
    }

    init(model: ProfilesViewModel, profileID: String, section: ConfigurationOutlineSection = .proxies,
         libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)? = nil) {
        self.model = model
        self.section = section
        _sources = StateObject(wrappedValue: ConfigurationNodeSourcesModel(model: model, profileID: profileID,
                                                                           libraryChanged: libraryChanged))
    }

    var body: some View {
         
        let nodeTypes = ConfigurationTypeWords.names(.proxies, copy: fieldCopy, locale: locale)
        let providerTypes = ConfigurationTypeWords.names(.proxyProviders, copy: fieldCopy, locale: locale)
        List {
            if let failure = sources.failure {
                Section { Text(verbatim: failure).foregroundStyle(.red) }
            }
            ForEach(ConfigurationNodeSourcesModel.Kind.allCases, id: \.self) { kind in
                let items = sources.rows.filter { $0.kind == kind }
                if !items.isEmpty {
                    Section {
                        ForEach(items) { row in sourceToggle(row) }
                    } header: {
                        Text(clash: .copy(kind.title))
                    }
                }
            }
            Section {
                Button { managing = true } label: { Text(clash: .copy("Manage Node Sources")) }
                     
                     
                    .disabled(sources.busy)
                    .accessibilityIdentifier("configuration-editor.sources.manage")
            }
            ForEach(sources.groups) { group in
                Section {
                    if section != .proxyProviders {
                        ForEach(group.nodes, id: \.self) { node in
                            ConfigurationRowLabel(title: .verbatim(node.name),
                                                  value: .verbatim(ConfigurationTypeWords.word(node.type, in: nodeTypes)))
                                .accessibilityIdentifier("configuration-editor.sources.node.\(node.name)")
                        }
                    }
                    ForEach(group.providers, id: \.self) { provider in
                        ConfigurationRowLabel(title: .verbatim(provider.name),
                                              value: .verbatim(ConfigurationTypeWords.word(provider.type, in: providerTypes)))
                            .accessibilityIdentifier("configuration-editor.sources.provider.\(provider.name)")
                    }
                    if let record = sources.record(of: group.id) {
                        Button { scoping = ScopeTarget(record: record, scope: sources.scope(of: group.id)) } label: {
                            Text(clash: .copy("Select Nodes"))
                        }
                         
                        .disabled(sources.busy)
                        .accessibilityIdentifier("configuration-editor.sources.scope.\(group.id)")
                    }
                } header: {
                    Text(verbatim: group.label)
                }
            }
        }
         
         
        .navigationTitle(Text(clash: .copy(ConfigurationEditorCopy.title(of: section))))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ControlGroup {
                    Button { adding = true } label: { Image(systemName: ClashSymbol.plus.name) }
                        .disabled(sources.busy)
                        .accessibilityLabel(Text(clash: .copy("Add Source")))
                        .accessibilityIdentifier("configuration-editor.sources.add")
                }
                .clashReaderControlGroupStyle()
            }
        }
        .task { await sources.load() }
        .clashSheet(isPresented: $adding, onDismiss: { Task { await sources.load() } }) {
            ConfigurationSourceImportAdapter(model: model, kind: .subscription, choosesKind: true,
                                             finishImport: { adding = false }) { payload in
                try await sources.add(payload)
            }
            .clashModalPresentation(.page)
        }
        .clashSheet(isPresented: $managing, onDismiss: { Task { await sources.load() } }) {
            ConfigurationSourceLibraryAdapter(model: model, library: sources.library,
                                              changed: { _ in }, close: { managing = false })
                .clashModalPresentation(.page)
        }
        .clashSheet(item: $scoping) { target in
            ConfigurationNodeScopeAdapter(model: model, source: target.record, staged: nil, initial: target.scope,
                                          save: { scope in
                                              scoping = nil
                                              Task { await sources.setScope(target.record.id, scope) }
                                          }, close: { scoping = nil })
                .clashModalPresentation(.page)
        }
    }

    private func sourceToggle(_ row: ConfigurationNodeSourcesModel.SourceRow) -> some View {
         
         
         
        Toggle(isOn: Binding(get: { sources.isOn(row.id) }, set: { sources.pressSource(row.id, on: $0) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.label)
                if let detail = row.detail {
                    Text(verbatim: detail).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("configuration-editor.sources.source.\(row.id)")
    }
}

 
 
 
struct ConfigurationNodeSourcesSheet: View {
    @ObservedObject var model: ProfilesViewModel
    let profileID: String
    var libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)?
    @StateObject private var dismiss = ClashDismissHandle()

    var body: some View {
        ClashFeatureNavigationContainer {
            ConfigurationNodeSourcesPage(model: model, profileID: profileID, section: .proxies, libraryChanged: libraryChanged)
                .navigationTitle(Text(clash: .copy("Node Sources")))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { dismiss.closeModalOrDismiss() } label: { Text(clash: .copy("Done")) }
                            .accessibilityIdentifier("configuration-editor.sources.done")
                    }
                }
        }
        .clashCapturesDismiss(dismiss)
    }
}
#endif
