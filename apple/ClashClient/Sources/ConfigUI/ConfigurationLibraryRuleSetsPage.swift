#if os(iOS)
import ClashClientKit
import ClashClientUI
import SwiftUI
import UniformTypeIdentifiers

 
 
 
 
 
 
 
 

 
struct ConfigurationLibraryRuleSetsSnapshot: Equatable {
    struct Row: Equatable, Identifiable {
        enum Kind: Equatable {
            case mine(String)
            case collection(ConfigurationCollection.ID)
        }
        let id: String
        let kind: Kind
        let name: String
         
        let usage: LibraryUsage
         
        let detail: String
    }

     
    let mine: [Row]
     
    let fromLinks: [Row]
    let fromFiles: [Row]

     
    static func count(localSets: [ConfigurationLocalRuleSet], collections: [ConfigurationCollectionEntry]) -> Int {
        localSets.count + collections.filter(isListed).count
    }

     
    static func countText(_ count: Int) -> ClashDisplayText {
        .format(count == 1 ? "%@ rule set" : "%@ rule sets", [String(count)])
    }

     
     
     
    static func isListed(_ entry: ConfigurationCollectionEntry) -> Bool {
        entry.id.kind == .rules
            && (ClashConfigurationRuleLibrarySection.subscription.contains(entry.source)
                || ClashConfigurationRuleLibrarySection.file.contains(entry.source))
    }

     
     
     
    static func listed(_ collections: [ConfigurationCollectionEntry], library: ConfigurationLibrarySnapshot)
        -> [ConfigurationCollectionEntry] {
        let read = library.sourcesWhoseRulesAreRead
        return collections.filter { isListed($0) && (!$0.source.suppliesNodes || read.contains($0.source.id)) }
    }

     
     
    static func updatable(_ collections: [ConfigurationCollectionEntry], library: ConfigurationLibrarySnapshot)
        -> [ConfigurationCollectionEntry] {
        listed(collections, library: library).filter { $0.collection.type == "http" && $0.source.isRetainedSnapshot != true }
    }

     
     
     
     
     
     
    static func make(localSets: [ConfigurationLocalRuleSet], collections: [ConfigurationCollectionEntry],
                     library: ConfigurationLibrarySnapshot, mineUsers: [String: [String]],
                     profiles: [LibraryUsage.Configuration],
                     copies: [ConfigurationCollection.ID: ConfigurationCollectionContentBridge.Cache],
                     locale: Locale, now: Date = Date()) -> Self {
        let mine = localSets.map { set -> Row in
            let count = set.ruleCount
            return Row(id: "mine:" + set.id, kind: .mine(set.id), name: set.name,
                       usage: LibraryUsage(names: mineUsers[set.id] ?? []),
                       detail: ConfigurationRuleSetLine.detail(set.link == nil ? .local : .link, count: count > 0 ? count : nil,
                                                               updatedAt: nil, locale: locale, now: now))
        }
        func row(_ entry: ConfigurationCollectionEntry) -> Row {
            let users = ConfigurationRuleSetDetailSnapshot.users(ofCollection: entry, in: library, profiles: profiles)
            let detail: String
            switch ConfigurationRuleSetLine.origin(of: entry.collection.definition) {
            case .inProfile:
                 
                detail = ConfigurationRuleSetLine.detail(nil, count: entry.collection.inlineCount, updatedAt: nil,
                                                         locale: locale, now: now)
            case let origin:
                let held = copies[entry.id]
                detail = ConfigurationRuleSetLine.detail(origin, count: held?.count, updatedAt: held?.updatedAt,
                                                         locale: locale, now: now)
            }
            return Row(id: "\(entry.source.id)/\(entry.collection.name)", kind: .collection(entry.id), name: entry.collection.name,
                       usage: LibraryUsage(names: users), detail: detail)
        }
        let listed = listed(collections, library: library)
        return Self(mine: mine,
                    fromLinks: listed.filter { ClashConfigurationRuleLibrarySection.subscription.contains($0.source) }.map(row),
                    fromFiles: listed.filter { ClashConfigurationRuleLibrarySection.file.contains($0.source) }.map(row))
    }
}

 
struct ConfigurationLibraryRuleSetsPage: View {
    let model: ProfilesViewModel
    let changed: (ConfigurationLibrarySnapshot) -> Void
    @State private var library: ConfigurationLibrarySnapshot
    @Environment(\.locale) private var locale
    @State private var collections: [ConfigurationCollectionEntry] = []
    @State private var copies: [ConfigurationCollection.ID: ConfigurationCollectionContentBridge.Cache] = [:]
    @State private var mineUsers: [String: [String]] = [:]
    @State private var link = ""
    @State private var importing: ImportRequest?
    @State private var pickingFile = false
    @State private var creating = false
     
    @State private var opened: ConfigurationRuleSetDetailPage.Item?

     
    private struct ImportRequest: Identifiable {
        let id = UUID()
        let initial: ConfigurationRuleSetPrefill?
    }

    init(model: ProfilesViewModel, library: ConfigurationLibrarySnapshot,
         changed: @escaping (ConfigurationLibrarySnapshot) -> Void) {
        self.model = model
        self.changed = changed
        _library = State(initialValue: library)
    }

    private var snapshot: ConfigurationLibraryRuleSetsSnapshot {
        .make(localSets: library.localRuleSets ?? [], collections: collections, library: library, mineUsers: mineUsers,
              profiles: model.profiles.map { .init(id: $0.id, name: $0.label) }, copies: copies, locale: locale)
    }

     
    private var updatable: [ConfigurationCollectionEntry] {
        ConfigurationLibraryRuleSetsSnapshot.updatable(collections, library: library)
    }

    var body: some View {
        let snapshot = self.snapshot
        List {
            group("My Rule Sets", rows: snapshot.mine, identifier: "configuration.library.rule-sets.mine")
            group("From Profile URLs", rows: snapshot.fromLinks, identifier: "configuration.library.rule-sets.link")
            group("From Files", rows: snapshot.fromFiles, identifier: "configuration.library.rule-sets.file")
            if !updatable.isEmpty {
                Section {
                    Button {
                        _ = model.updateRuleCollections(updatable, scripts: .silent, locale: locale)
                    } label: {
                        ClashActionProgressLabel(.copy("Update All"), isBusy: updating)
                    }
                    .disabled(updating)
                    .accessibilityIdentifier("configuration.library.rule-sets.update-all")
                }
            }
            addSection
        }
        .refreshable {
            await model.updateRuleCollections(updatable, scripts: .silent, locale: locale).value
            await reload()
        }
        .clashPageTitle(.copy("Rule Sets"), watchAs: "library-rule-sets")
        .task { await reload() }
        .onChange(of: model.libraryContentEpoch) { _ in Task { await reload() } }
        .clashProductModal(item: $importing, role: .page) { request in
            ConfigurationCollectionImportAdapter(model: model, library: library, changed: apply,
                                                 close: { importing = nil }, initial: request.initial)
        }
         
         
        .clashProductModal(isPresented: $creating, role: .form) {
            ClashSingleColumnNavigationContainer {
                ClashTowerLocalRuleEditor(
                    value: nil, policy: "DIRECT", options: .empty, palette: .clashProduct,
                    buildRule: { line, accept in Self.ruleBuilder(line, accept) },
                    confirmTitle: "Add", attaches: false,
                    save: { name, input, _ in
                        try await Self.add(name: name, input: input, model: model, apply: apply)
                        creating = false
                    },
                    close: { creating = false })
            }
            .environment(\.clashProductModalDismiss, { creating = false })
        }
        .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.data]) { result in
            guard case .success(let url) = result else { return }
            Task { await importFile(url) }
        }
         
        .background(ClashRoutedViewDestination(isPresented: Binding(get: { opened != nil }, set: { if !$0 { opened = nil } })) {
            if let opened {
                ConfigurationRuleSetDetailPage(model: model, item: opened, library: library, profileID: nil, changed: apply)
            }
        })
    }

    private var updating: Bool {
        model.ruleCollectionUpdate.map { !$0.finished } ?? false
    }

    @ViewBuilder
    private func group(_ title: String, rows: [ConfigurationLibraryRuleSetsSnapshot.Row], identifier: String) -> some View {
        if !rows.isEmpty {
            Section {
                ForEach(rows) { row in
                     
                     
                    Button { open(row) } label: {
                        ClashConfigurationLibraryRow(title: row.name, count: .verbatim(row.detail),
                                                     inUse: ClashLibraryUsageCopy.text(row.usage))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(identifier)
                }
            } header: {
                Text(clash: .copy(title))
            }
        }
    }

     
     
     
    private var addSection: some View {
        Section {
            HStack {
                TextField(text: $link, prompt: Text(verbatim: "https://")) { Text(clash: .copy("Link")) }
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
                    .onSubmit(openLink)
                    .accessibilityIdentifier("configuration.library.rule-sets.add.link")
                ClashPasteControl(style: .square) { pasted in
                    link = pasted
                    openLink()
                }
            }
            Button { pickingFile = true } label: {
                Label { Text(clash: .copy("Import File")) } icon: { Image(systemName: ClashSymbol.arrowUpDocument.name) }
            }
            .accessibilityIdentifier("configuration.library.rule-sets.add.file")
            Button { creating = true } label: {
                Label { Text(clash: .copy("New Rule Set")) } icon: { Image(systemName: ClashSymbol.plus.name) }
            }
            .accessibilityIdentifier("configuration.library.rule-sets.add.new")
        } header: {
            Text(clash: .copy("Add Rule Set"))
        }
    }

    private func open(_ row: ConfigurationLibraryRuleSetsSnapshot.Row) {
        switch row.kind {
        case .mine(let id):
            if let set = library.localRuleSets?.first(where: { $0.id == id }) { opened = .mine(set) }
        case .collection(let id):
            if let entry = collections.first(where: { $0.id == id }) { opened = .collection(entry, brought: false) }
        }
    }

    private func openLink() {
        let typed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ConfigurationLocalRuleSetLines.looksLikeLink(typed) else { return }
        var initial = ConfigurationRuleSetPrefill()
        initial.link = typed
        initial.name = ClashRuleSetSniff.linkStem(typed)
        importing = ImportRequest(initial: initial)
        link = ""
    }

     
     
    private func importFile(_ url: URL) async {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            importing = ImportRequest(initial: nil)
            return
        }
        let initial = await ConfigurationRuleSetPrefill.local(label: "", fileName: url.lastPathComponent, data: data)
        importing = ImportRequest(initial: initial)
    }

    private func apply(_ value: ConfigurationLibrarySnapshot) {
        if value.generation >= library.generation { library = value }
        changed(value)
        Task { await reload() }
    }

     
     
    private func reload() async {
        guard let store = model.configurationLibraryStore else { return }
        let profiles = model.profiles.map { LibraryUsage.Configuration(id: $0.id, name: $0.label) }
        let held = library
        let read = await Task.detached(priority: .userInitiated) { () -> Read? in
            guard let now = try? store.snapshot() else { return nil }
            let library = now.generation >= held.generation ? now : held
            let catalog = (try? ConfigurationCollectionContentBridge.catalog(store, snapshot: library)) ?? []
            var copies: [ConfigurationCollection.ID: ConfigurationCollectionContentBridge.Cache] = [:]
            for entry in catalog where ConfigurationLibraryRuleSetsSnapshot.isListed(entry) {
                if let copy = ConfigurationCollectionContentBridge.libraryCopyRecord(of: entry) { copies[entry.id] = copy }
            }
            var users: [String: [String]] = [:]
            for set in library.localRuleSets ?? [] {
                users[set.id] = (try? ConfigurationRuleSetDetailSnapshot.users(of: set.id, in: library, store: store, profiles: profiles)) ?? []
            }
            return Read(library: library, catalog: catalog, copies: copies, users: users)
        }.value
        guard let read else { return }
        library = read.library
        collections = read.catalog
        copies = read.copies
        mineUsers = read.users
    }

    private struct Read: Sendable {
        let library: ConfigurationLibrarySnapshot
        let catalog: [ConfigurationCollectionEntry]
        let copies: [ConfigurationCollection.ID: ConfigurationCollectionContentBridge.Cache]
        let users: [String: [String]]
    }
}

extension ConfigurationLibraryRuleSetsPage {
     
     
    static func ruleBuilder(_ line: String?, _ accept: @escaping (String) -> Void) -> AnyView {
        AnyView(RuleBuilderAdapter(raw: line ?? "", options: RulePolicyOptions(shared: .empty), showsPersonalMetadata: false,
                                   showsTarget: false, createGroup: nil, enabled: true, comment: "",
                                   pageTitle: line == nil ? "Add Rule" : "Rule",
                                   saveDetails: { raw, _, _ in accept(raw) }, save: { raw in accept(raw) }))
    }

     
     
     
    static func add(name: String, input: String, model: ProfilesViewModel,
                    apply: (ConfigurationLibrarySnapshot) -> Void) async throws {
        guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        let read = try await ConfigurationTowerRuleReader.ruleSet(input)
        let value = ConfigurationLocalRuleSet(id: UUID().uuidString.lowercased(), name: name, input: input, rules: read.rules,
                                              link: read.link, behavior: read.behavior)
        let now = try await Task.detached(priority: .userInitiated) { try store.snapshot() }.value
        apply(try await model.saveConfigurationLocalRuleSet(value, deleting: nil, generation: now.generation))
    }
}

#endif
