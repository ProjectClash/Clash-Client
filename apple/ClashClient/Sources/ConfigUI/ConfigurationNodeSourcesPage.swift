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
         
         
        var detail: ClashDisplayText?
        var isOn: Bool
        var kind: Kind
         
         
        var switchable = true
         
         
        var hasPage = true
    }

    @Published private(set) var rows: [SourceRow] = []
    @Published private(set) var busy = false
    @Published var failure: String?
     
    @Published private(set) var isOriginal = false
     
     
     
     
     
     
    @Published private(set) var picks: [ConfigurationLibraryPicks.Source]?
     
    @Published private(set) var pressed = ClashPressedSwitches<String>()
     
    private(set) var library = ConfigurationLibrarySnapshot()
     
     
    private var legacy: [String: ConfigurationSourcePayload] = [:]
    let model: ProfilesViewModel
    let profileID: String
    var libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)?

    init(model: ProfilesViewModel, profileID: String, libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)? = nil) {
        self.model = model
        self.profileID = profileID
        self.libraryChanged = libraryChanged
    }

     
     
     
     
    func load() async {
        let before = loading
        let read = Task { @MainActor in
            await before?.value
            await self.read()
        }
        loading = read
        await read.value
    }
    private var loading: Task<Void, Never>?

    private func read() async {
        do {
            guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            let locale = AppPreferences.language().locale
            let profileID = profileID
            let found = try await Task.detached(priority: .userInitiated) {
                () throws -> (ConfigurationLibrarySnapshot, [SourceRow], Bool, [ConfigurationLibraryPicks.Source]?)? in
                let snapshot = try store.snapshot()
                guard let recipe = snapshot.recipes.first(where: { $0.id == profileID }) else { return nil }
                let original = recipe.preservesOriginal == true
                let rows = try Self.rows(of: recipe, in: snapshot, store: store, locale: locale, now: Date())
                let picks = original ? (try? ConfigurationLibraryPicks.sources(in: store, excludingThoseOf: profileID)) : nil
                return (snapshot, rows, original, picks)
            }.value
            guard let found else {
                rows = []
                picks = nil
                return
            }
            let (snapshot, listed, original, picked) = found
            library = snapshot
            isOriginal = original
            picks = picked
            var rows = listed
             
             
             
            legacy = [:]
            if !original {
                let known = Set(snapshot.sources.map(\.id))
                let older = (try? await model.configurationLegacyNodeSources(in: snapshot)) ?? [:]
                for (owner, payload) in older where owner != profileID {
                    let id = "legacy-" + owner
                    guard !known.contains(id), payload.record.nodeCount > 0 || payload.record.providerCount > 0 else { continue }
                    legacy[id] = payload
                    let label = model.profiles.first { $0.id == owner }?.label ?? payload.record.label
                    rows.append(SourceRow(id: id, label: label,
                                          detail: .verbatim(Self.summary(nodes: payload.record.nodeCount,
                                                                         providers: payload.record.providerCount)),
                                          isOn: false, kind: .existingProfile, hasPage: false))
                }
            }
            self.rows = rows.sorted { lhs, rhs in
                lhs.kind == rhs.kind ? false : Kind.allCases.firstIndex(of: lhs.kind)! < Kind.allCases.firstIndex(of: rhs.kind)!
            }
        } catch {
            failure = error.localizedDescription
        }
    }

     
     
     
    nonisolated static func rows(of recipe: ConfigurationRecipe, in snapshot: ConfigurationLibrarySnapshot,
                                 store: ConfigurationLibraryStore, locale: Locale, now: Date) throws -> [SourceRow] {
        let selected = recipe.sources.map(\.id)
        let original = recipe.preservesOriginal == true
        let records = snapshot.sources.filter {
            $0.suppliesNodes && ($0.isListedInLibrary || selected.contains($0.id) || (original && $0.id == recipe.ruleSource.id))
        }
        return try records.map { record in
            let kind = Kind.of(record)
            if original {
                let own = record.id == recipe.ruleSource.id
                let detail: ClashDisplayText = own
                    ? .format(record.nodeCount == 1 ? "Original Configuration · %@ node" : "Original Configuration · %@ nodes",
                              [String(record.nodeCount)])
                    : .verbatim(ClashConfigurationSourceCopy.summary(record, locale: locale))
                let isLink: Bool = {
                    guard record.nodeChain == nil, record.isRetainedSnapshot != true, case .subscription = record.origin else { return false }
                    return true
                }()
                return SourceRow(id: record.id, label: record.displayLabel(locale: locale), detail: detail,
                                 isOn: own, kind: kind, switchable: !own && isLink)
            }
            var detail: ClashDisplayText = .verbatim(ClashConfigurationSourceCopy.summary(record, locale: locale))
            if let reference = recipe.sources.first(where: { $0.id == record.id }), let scope = recipe.nodeScopes?[record.id] {
                 
                let names = nodeNames(in: try OrderedJSON.parse(try store.payload(reference).documentJSON))
                let picked = ClashCopy.string(for: NodeSourceDetailCopy.selected(names.filter { scope.choosesNode(named: $0) }.count,
                                                                                 of: names.count), locale: locale)
                detail = .verbatim(picked + " · " + ProxyNodeLibraryCopy.lastUpdated(record, locale: locale, now: now))
            }
            return SourceRow(id: record.id, label: record.displayLabel(locale: locale), detail: detail,
                             isOn: selected.contains(record.id), kind: kind)
        }
    }

     
    nonisolated static func nodeNames(in document: OrderedJSON) -> [String] {
        guard case .array(let nodes)? = document.topLevelValue("proxies") else { return [] }
        return nodes.compactMap { node in
            if case .string(let name)? = node.topLevelValue("name") { return name }
            return nil
        }
    }

     
     
     
    func isOn(_ id: String) -> Bool { pressed.shown(id, else: rows.first { $0.id == id }?.isOn ?? false) }

    func record(of id: String) -> ConfigurationSourceRecord? { library.sources.first { $0.id == id } }

     
    var configurationName: String {
        model.profiles.first { $0.id == profileID }.map { ProfileRowPresentation.label(for: $0, locale: AppPreferences.language().locale) }
            ?? library.recipes.first { $0.id == profileID }?.label ?? ""
    }

     
     
     
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
}

 
enum ConfigurationNodeSourcesCopy {
     
    static func title(_ configuration: String) -> ClashDisplayText { .format("Node Sources of “%@”", [configuration]) }
     
    static func onlyHere(_ configuration: String) -> ClashDisplayText { .format("Changes here apply only to “%@”.", [configuration]) }
     
    static func turningOnStopsFollowing(_ configuration: String) -> ClashDisplayText {
        .format("Once turned on, “%@” no longer follows its link.", [configuration])
    }
}

 
 
 
 
 
 
 
struct ConfigurationNodeSourcesPage: View {
    @ObservedObject var model: ProfilesViewModel
     
    let section: ConfigurationOutlineSection
    @StateObject private var sources: ConfigurationNodeSourcesModel
    @StateObject private var quickAdd: ProfileQuickAddController
     
     
    @StateObject private var original: ConfigurationEditorSession
    @State private var inspected: String?
     
    @State private var originalDoor: OriginalAddNodesDoor?
    @State private var showsNewNode = false
    @State private var showsNewChain = false
    @Environment(\.locale) private var locale

    init(model: ProfilesViewModel, profileID: String, section: ConfigurationOutlineSection = .proxies,
         libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)? = nil) {
        self.model = model
        self.section = section
        _sources = StateObject(wrappedValue: ConfigurationNodeSourcesModel(model: model, profileID: profileID,
                                                                           libraryChanged: libraryChanged))
        _quickAdd = StateObject(wrappedValue: ProfileQuickAddController(model: model, target: .source))
        _original = StateObject(wrappedValue: ConfigurationEditorSession(profileID: profileID, model: model))
    }

    var body: some View {
        List {
            if let failure = sources.failure {
                Section { Text(verbatim: failure).foregroundStyle(.red) }
            }
            if sources.isOriginal {
                OriginalNodeSourcesSections(session: original, configurationName: sources.configurationName,
                                            rows: sources.rows, picks: sources.picks, door: $originalDoor,
                                            inspect: { inspected = $0 })
            } else {
                composedRows
                addCard
            }
            Section {
                ClashNativeNavigationLink {
                    ConfigurationSourceLibraryAdapter(model: model, library: sources.library, changed: { _ in }, close: {},
                                                      embedded: true, showsClose: false)
                        .clashPageTitle(.copy("Node Library"))
                        .environment(\.clashProductModalDismiss, nil)
                         
                         
                         
                         
                        .clashOnScreen { onScreen in if !onScreen { Task { await sources.load() } } }
                } label: {
                    Text(clash: .copy("Manage Node Sources"))
                }
                 
                 
                .disabled(sources.busy)
                .accessibilityIdentifier("configuration-editor.sources.manage")
            }
        }
         
         
        .clashPageTitle(ConfigurationNodeSourcesCopy.title(sources.configurationName))
        .task { await sources.load() }
         
         
        .task(id: originalRevision) { if sources.isOriginal { await original.reload() } }
        .configurationPushedAlertHost(original)
         
        .originalAddNodesPages($originalDoor, session: original)
         
         
         
         
         
        .onChange(of: model.libraryContentEpoch) { _ in Task { await sources.load() } }
        .onReceive(model.$savedConfigurationGeneration.dropFirst()) { _ in Task { await sources.load() } }
        .profileQuickAddPresenters(quickAdd)
        .onAppear { quickAdd.onNodeSourceAdded = { switchOn($0.id) } }
        .clashProductModal(isPresented: $showsNewNode, role: .page) {
            ConfigurationNewNodeAdapter(model: model, library: nil, changed: { _ in }, close: { showsNewNode = false },
                                        added: { switchOn($0.id) })
        }
        .clashProductModal(isPresented: $showsNewChain, role: .page) {
            ConfigurationChainEditor(model: model, existing: nil, accept: { payload in
                guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
                let generation = try await Task.detached { try store.snapshot().generation }.value
                _ = try await model.addConfigurationSource(payload, generation: generation)
                switchOn(payload.record.id)
            }, close: { showsNewChain = false })
        }
        .background(ClashRoutedViewDestination(isPresented: Binding(get: { inspected != nil },
                                                                    set: { if !$0 { inspected = nil } })) {
            if let id = inspected {
                NodeSourceDetailPage(model: model, sourceID: id,
                                     configuration: .init(id: sources.profileID, name: sources.configurationName),
                                     changed: { _ in Task { await sources.load() } },
                                     close: { inspected = nil })
            }
        })
    }

    private var originalRevision: String {
        guard sources.isOriginal else { return "" }
        return "original|" + (model.profiles.first { $0.id == sources.profileID }?.activeRevision ?? "")
    }

     
     
    @ViewBuilder
    private var composedRows: some View {
        let kinds = ConfigurationNodeSourcesModel.Kind.allCases.filter { kind in sources.rows.contains { $0.kind == kind } }
        ForEach(kinds, id: \.self) { kind in
            Section {
                ForEach(sources.rows.filter { $0.kind == kind }) { row in sourceRow(row) }
            } header: {
                Text(clash: .copy(kind.title))
            } footer: {
                if kind == kinds.last {
                    Text(clash: ConfigurationNodeSourcesCopy.onlyHere(sources.configurationName))
                        .accessibilityIdentifier("configuration-editor.sources.only-here")
                }
            }
        }
    }

     
     
    private var addCard: some View {
        ProfileQuickAddCard(
            controller: quickAdd,
            identifiers: .init(linkIdentifier: "configuration-editor.sources.add.link",
                               scanIdentifier: "configuration-editor.sources.add.scan",
                               fileIdentifier: "configuration-editor.sources.add.file",
                               manualIdentifier: "configuration-editor.sources.add.manual",
                               statusIdentifier: "configuration-editor.sources.add.status"),
            manual: { showsNewNode = true },
            footer: .format("Node sources you add are used for “%@”.", [sources.configurationName]),
            moreRows: AnyView(
                Button { showsNewChain = true } label: {
                    Label(ClashCopy.key("New Proxy Chain"), systemImage: ClashSymbol.link.name)
                }
                .disabled(sources.busy)
                .accessibilityIdentifier("configuration-editor.sources.add.chain")
            )
        )
         
        .disabled(sources.busy)
    }

    private func sourceRow(_ row: ConfigurationNodeSourcesModel.SourceRow) -> some View {
        HStack(spacing: ClashClientUI.ClashTheme.Spacing.row) {
            sourceToggle(row)
            if row.hasPage { NodeSourceInfoButton(id: row.id) { inspected = row.id } }
        }
         
        .accessibilityElement(children: .contain)
    }

    private func sourceToggle(_ row: ConfigurationNodeSourcesModel.SourceRow) -> some View {
         
         
         
        Toggle(isOn: Binding(get: { sources.isOn(row.id) }, set: { sources.pressSource(row.id, on: $0) })) {
            NodeSourceRowLabel(row: row)
        }
        .accessibilityIdentifier("configuration-editor.sources.source.\(row.id)")
    }

     
     
    private func switchOn(_ id: String) {
        Task { @MainActor in
            await sources.load()
            sources.pressSource(id, on: true)
        }
    }
}

 
struct NodeSourceRowLabel: View {
    let row: ConfigurationNodeSourcesModel.SourceRow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: row.label)
            if let detail = row.detail {
                Text(clash: detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

 
struct NodeSourceInfoButton: View {
    let id: String
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            Image(systemName: ClashSymbol.infoCircle.name)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: ClashClientUI.ClashTheme.Control.minimumHitTarget,
                       height: ClashClientUI.ClashTheme.Control.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text(clash: .copy("Details")))
        .accessibilityIdentifier("configuration-editor.sources.info.\(id)")
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
