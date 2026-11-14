#if os(iOS)
import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
 

extension ConfigurationEditorSession {
     
     
     
     
    @discardableResult
    func editOriginal(steps: [ConfigurationTextStep], readDigest: String? = nil) async -> Bool {
        await editOriginalReporting(steps: steps, readDigest: readDigest) == .saved
    }

     
    func editOriginalReporting(steps: [ConfigurationTextStep], readDigest: String? = nil) async -> RunOutcome {
        var ended = RunOutcome.failedOutright
        _ = await handingOn(steps) {
            ended = await self.runReporting { try await self.model.editOriginalConfiguration(self.profileID, steps: steps, readDigest: readDigest) }
            return ended == .saved
        }
        return ended
    }

     
     
    func refuseDeleting(_ name: String, usedBy places: [String]) {
        refuseDeleting([DeletingRefused(name: name, places: places)])
    }

     
    struct DeletingRefused {
        let name: String
        let places: [String]
    }

     
     
    func refuseDeleting(_ refused: [DeletingRefused]) {
        let locale = AppPreferences.language().locale
        var said = Set<String>()
        failure = refused.filter { said.insert($0.name).inserted }.map { item in
            let sentence = ClashCopy.string(for: .format("“%@” is still in use. Change these first.", [item.name]), locale: locale)
            return ([sentence] + item.places.prefix(5)).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}

 
private func matching<Item>(_ items: [Item], _ query: String, _ words: (Item) -> [String]) -> [Item] {
    let query = query.trimmingCharacters(in: .whitespaces).lowercased()
    guard !query.isEmpty else { return items }
    return items.filter { words($0).contains { $0.lowercased().contains(query) } }
}

 

 
struct ConfigurationOriginalRulesView: View {
    @ObservedObject var session: ConfigurationEditorSession
     
    let base: [String]
    let title: ClashDisplayText
    @State private var search = ""
    @State private var editMode: EditMode = .inactive
    @State private var editing: RuleTarget?

     
    struct RuleTarget: Identifiable {
        let id = UUID()
        let index: Int?
        let raw: String
        let asText: Bool
    }

    private var path: [ConfigurationTextPathStep] { base.map { .key($0) } }

     
    private var rules: [String]? {
        guard case .array(let items)? = session.value(at: base) else { return nil }
        return items.map { item in
            if case .string(let text) = item { return text }
            return item.serialized()
        }
    }

    @Environment(\.locale) private var locale
    @Environment(\.configurationFieldCopy) private var fieldCopy

     
    private var shown: [(index: Int, rule: String)] {
        matching((rules ?? []).enumerated().map { (index: $0.offset, rule: $0.element) }, search) { item in
            let words = ConfigurationRuleWords.of(item.rule, locale: locale, copy: fieldCopy)
            return [item.rule, words.match, words.kind, words.target ?? ""]
        }
    }

    var body: some View {
        List {
            Section {
                if (rules ?? []).isEmpty {
                    ConfigurationEmptyListRows(key: "rules") {
                        Button { editing = RuleTarget(index: nil, raw: "", asText: false) } label: {
                            Label { Text(clash: .copy("Add Rule")) } icon: { Image(systemName: ClashSymbol.plus.name) }
                        }
                        .accessibilityIdentifier("configuration-editor.original-rules.add-first")
                    }
                }
                ForEach(shown, id: \.index) { item in
                    Button {
                         
                        guard !editMode.isEditing else { return }
                        editing = RuleTarget(index: item.index, raw: item.rule,
                                             asText: OriginalListEdits.isWrittenAsText(item.rule, catalog: session.catalog))
                    } label: {
                         
                         
                         
                        ConfigurationRuleRow(item.rule)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            editing = RuleTarget(index: item.index, raw: item.rule, asText: true)
                        } label: { Text(clash: .copy("Edit as Text")) }
                    }
                    .accessibilityIdentifier("configuration-editor.original-rules.row")
                }
                 
                .onDelete(perform: editMode.isEditing ? nil : delete)
                .onMove(perform: search.isEmpty ? move : nil)
            }
        }
        .searchable(text: $search)
        .navigationTitle(Text(clash: title))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if (rules ?? []).count > 1 { ConfigurationReorderButton(editMode: $editMode, identifier: "configuration-editor.list.reorder") }
                Button {
                    editing = RuleTarget(index: nil, raw: "", asText: false)
                } label: { Image(systemName: ClashSymbol.plus.name) }
                .accessibilityIdentifier("configuration-editor.original-rules.add")
            }
        }
        .environment(\.editMode, $editMode)
        .disabled(session.isSaving)
        .clashProductModal(item: $editing, role: .form) { target in
            ruleEditor(target).clashModalPresentation(.page)
        }
    }

    @ViewBuilder
    private func ruleEditor(_ target: RuleTarget) -> some View {
        if target.asText {
            ConfigurationRawRuleEditor(raw: target.raw) { raw in Task { await save(raw, target) } }
        } else {
            RuleBuilderAdapter(raw: target.raw, options: RulePolicyOptions.make(document: session.page?.document),
                               showsPersonalMetadata: false) { raw in Task { await save(raw, target) } }
        }
    }

    private func save(_ raw: String, _ target: RuleTarget) async {
        let rule = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rule.isEmpty, rule != target.raw else { return }
        if let index = target.index {
            await session.editOriginal(steps: [OriginalListEdits.settingRule(rule, at: index, under: path)])
        } else {
            await session.editOriginal(steps: [OriginalListEdits.addingRule(rule, to: rules, under: path)])
        }
    }

    private func delete(_ offsets: IndexSet) {
        let indices = offsets.map { shown[$0].index }
        Task { await session.editOriginal(steps: OriginalListEdits.deleting(indices, under: path)) }
    }

    private func move(_ offsets: IndexSet, _ destination: Int) {
        let steps = OriginalListEdits.moveSteps(offsets, to: destination, under: path)
        guard !steps.isEmpty else { return }
        Task { await session.editOriginal(steps: steps) }
    }
}

 

 
 
 
 
 
struct ConfigurationKeptRulesView: View {
    let kept: ProfilesViewModel.ConfigurationEditorPage.KeptRules
    let title: ClashDisplayText
    @StateObject private var pager = KeptRulesPager()
    @State private var search = ""
    @Environment(\.locale) private var locale

    private var header: ClashDisplayText {
        let query = pager.query.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty, let matched = pager.matched {
             
            return .format(matched == 1 ? "%@ match" : "%@ matches", [matched.formatted(.number.locale(locale))])
        }
        let total = pager.total ?? kept.count
        return .format(total == 1 ? "%@ rule" : "%@ rules", [total.formatted(.number.locale(locale))])
    }

    var body: some View {
        List {
            Section {
                ForEach(pager.rules, id: \.index) { entry in
                     
                    ConfigurationRuleRow(entry.rule, showsChevron: false)
                        .accessibilityIdentifier("configuration-editor.kept-rules.row")
                        .onAppear {
                            if entry.index == pager.rules.last?.index { Task { await pager.more() } }
                        }
                }
                if pager.matched == 0 {
                    Text(clash: .copy("No matching rules")).foregroundStyle(.secondary)
                }
                if let failure = pager.failure {
                    Text(verbatim: failure).foregroundStyle(.secondary)
                }
                if pager.loading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("configuration-editor.kept-rules.loading")
                }
            } header: {
                Text(clash: header).accessibilityIdentifier("configuration-editor.kept-rules.count")
            } footer: {
                Text(clash: Self.note)
            }
        }
        .searchable(text: $search)
        .navigationTitle(Text(clash: title))
        .task(id: search) {
             
            if !pager.rules.isEmpty || pager.failure != nil {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
            }
            await pager.load(file: kept.file, query: search)
        }
        .onDisappear { pager.close() }
    }

    static let note: ClashDisplayText = .copy("These rules are too many to edit one by one here. They run as written in the configuration's file.")
}

 
 
struct ConfigurationRawRuleEditor: View {
    let raw: String
    let save: (String) -> Void
    @State private var text = ""
    @StateObject private var dismiss = ClashDismissHandle()

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ClashFeatureNavigationContainer {
            Form {
                Section {
                    TextEditor(text: $text)
                        .font(.body.monospaced())
                        .frame(minHeight: 96)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .accessibilityIdentifier("configuration-editor.original-rules.text")
                } footer: {
                    Text(clash: .copy("Saved as written."))
                }
            }
            .navigationTitle(Text(clash: .copy("Rule")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(clash: .copy("Cancel")) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save(trimmed)
                        dismiss()
                    } label: { Text(clash: .copy("Save")) }
                    .disabled(trimmed.isEmpty || trimmed == raw)
                    .accessibilityIdentifier("configuration-editor.original-rules.text.save")
                }
            }
        }
        .clashCapturesDismiss(dismiss)
        .onAppear { if text.isEmpty { text = raw } }
    }
}

 

 
struct ConfigurationOriginalSubRulesView: View {
    @ObservedObject var session: ConfigurationEditorSession
    @State private var search = ""
    @State private var adding = false

    private var branches: [(name: String, count: Int)] {
        guard case .object(let pairs)? = session.value(at: ["sub-rules"]) else { return [] }
        return pairs.map { pair in
            if case .array(let rules) = pair.value { return (pair.key, rules.count) }
            return (pair.key, 0)
        }
    }

    private var shown: [(name: String, count: Int)] { matching(branches, search) { [$0.name] } }

    var body: some View {
        List {
            Section {
                if branches.isEmpty {
                    ConfigurationEmptyListRows(key: "sub-rules") {
                        Button { adding = true } label: {
                            Label { Text(clash: .copy("Add Sub-rule")) } icon: { Image(systemName: ClashSymbol.plus.name) }
                        }
                        .accessibilityIdentifier("configuration-editor.original-sub-rules.add-first")
                    }
                }
                ForEach(shown, id: \.name) { branch in
                    ClashNativeNavigationLink {
                        ConfigurationOriginalRulesView(session: session, base: ["sub-rules", branch.name],
                                                       title: .verbatim(branch.name))
                            .configurationPushedAlertHost(session)
                    } label: {
                        HStack {
                            Text(verbatim: branch.name)
                            Spacer()
                            Text(verbatim: String(branch.count)).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("configuration-editor.original-sub-rules.branch")
                }
                .onDelete { offsets in delete(offsets.map { shown[$0].name }) }
            }
        }
        .searchable(text: $search)
        .navigationTitle(Text(clash: .copy(ConfigurationEditorCopy.title(of: .subRules))))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ControlGroup {
                    Button { adding = true } label: { Image(systemName: ClashSymbol.plus.name) }
                        .accessibilityLabel(Text(clash: .copy("Add")))
                        .accessibilityIdentifier("configuration-editor.original-sub-rules.add")
                }
                .clashReaderControlGroupStyle()
            }
        }
        .disabled(session.isSaving)
        .clashSheet(isPresented: $adding) {
            ConfigurationNewSubRuleSheet(taken: Set(branches.map(\.name))) { name in
                let step = OriginalListEdits.adding(name, .array([]), toMappingAt: "sub-rules",
                                                    exists: session.value(at: ["sub-rules"]) != nil)
                Task { await session.editOriginal(steps: [step]) }
            }
            .clashModalPresentation(.form)
        }
    }

    private func delete(_ names: [String]) {
        guard let document = session.page?.document else { return }
        for name in names {
            let places = OriginalListEdits.uses(ofSubRule: name, in: document)
            if !places.isEmpty { return session.refuseDeleting(name, usedBy: places) }
        }
        Task {
            guard await !session.keptRulesRefuseDeleting(names) else { return }
            await session.editOriginal(steps: OriginalListEdits.deleting(names, fromMappingAt: "sub-rules"))
        }
    }
}

 
struct ConfigurationNewSubRuleSheet: View {
    let taken: Set<String>
    let save: (String) -> Void
    @State private var name = ""
    @StateObject private var dismiss = ClashDismissHandle()

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        ClashFeatureNavigationContainer {
            Form {
                TextField(text: $name) { Text(clash: .copy("Name")) }
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .accessibilityIdentifier("configuration-editor.original-sub-rules.new.name")
            }
            .navigationTitle(Text(clash: .copy("Add Sub-rule")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(clash: .copy("Cancel")) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save(trimmed)
                        dismiss()
                    } label: { Text(clash: .copy("Save")) }
                    .disabled(trimmed.isEmpty || taken.contains(trimmed))
                    .accessibilityIdentifier("configuration-editor.original-sub-rules.new.save")
                }
            }
        }
        .clashCapturesDismiss(dismiss)
    }
}

 

 
 
 
 
struct ConfigurationOriginalProxiesView: View {
    @ObservedObject var session: ConfigurationEditorSession
    @State private var search = ""
     
    @State private var addingType: String?
     
    @State private var pickingFromLibrary = false
     
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

    struct Node {
        let index: Int
        let name: String
        let type: String
        let value: OrderedJSON
    }

     
    private var nodes: [Node]? {
        guard case .array(let items)? = session.value(at: ["proxies"]) else { return nil }
        return items.enumerated().map { offset, item in
            let entry = OriginalEntry(name: ConfigurationEditorCopy.entryTitle(item, index: offset), value: item)
            return Node(index: offset, name: entry.name, type: entry.type ?? "", value: item)
        }
    }

    private var shown: [Node] { matching(nodes ?? [], search) { [$0.name, $0.type] } }

    var body: some View {
        let types = ConfigurationTypeWords.names(.proxies, copy: fieldCopy, locale: locale)
        List {
            Section {
                if (nodes ?? []).isEmpty {
                    ConfigurationEmptyListRows(key: "proxies") {
                        newNodeMenu
                            .accessibilityIdentifier("configuration-editor.original-proxies.new-row")
                        libraryButton
                            .accessibilityIdentifier("configuration-editor.original-proxies.library-row")
                    }
                }
                ForEach(shown, id: \.index) { node in
                    ClashNativeNavigationLink {
                        nodeEditor(node)
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: node.name).lineLimit(1)
                            Spacer()
                            Text(verbatim: ConfigurationTypeWords.word(node.type, in: types)).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("configuration-editor.original-proxies.node")
                }
                .onDelete(perform: swipeToDelete)
            }
        }
        .searchable(text: $search)
        .navigationTitle(Text(clash: .copy(ConfigurationEditorCopy.title(of: .proxies))))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                 
                 
                Menu {
                    newNodeMenu
                        .accessibilityIdentifier("configuration-editor.original-proxies.new")
                    libraryButton
                        .accessibilityIdentifier("configuration-editor.original-proxies.library")
                } label: {
                    Image(systemName: ClashSymbol.plus.name)
                }
                .accessibilityLabel(Text(clash: .copy("Add")))
                .accessibilityIdentifier("configuration-editor.original-proxies.add")
            }
        }
        .disabled(session.isSaving)
         
         
         
        .clashSheet(isPresented: Binding(get: { addingType != nil }, set: { if !$0 { addingType = nil } })) {
            ClashFeatureNavigationContainer {
                ProxyNodeDetailsView(record: CustomNodesView.newNodeTemplate, retest: {},
                                     saveNode: { _, edited in try await add(edited) },
                                     showsTesting: false, isNew: true, dialerRouting: .payloadField,
                                     dialerCandidates: { candidates(excluding: "") }, onDone: { addingType = nil })
            }
            .clashModalPresentation(.page)
        }
        .clashSheet(isPresented: $pickingFromLibrary) {
            ConfigurationLibraryNodePicker(store: session.model.configurationLibraryStore, profileID: session.profileID,
                                           document: session.page?.document ?? .object([])) { picked, sources in
                Task { await session.addLibraryNodes(picked, from: sources) }
            }
            .clashModalPresentation(.page)
        }
    }

     
     
     
     
    private var newNodeMenu: some View {
        Button { addingType = Self.firstType(newNodeTypes) } label: {
            Label { Text(clash: .copy("New Node…")) } icon: { Image(systemName: ClashSymbol.plus.name) }
        }
        .disabled(newNodeTypes.isEmpty)
    }

     
     
    static func firstType(_ types: [String]) -> String {
        types.contains("ss") ? "ss" : types.first ?? "ss"
    }

     
    private var libraryButton: some View {
        Button { pickingFromLibrary = true } label: {
            Label { Text(clash: .copy("Choose from the Node Library…")) } icon: { Image(systemName: ClashSymbol.rectangleStack.name) }
        }
    }

     
     
    private var newNodeTypes: [String] {
        guard let catalog = session.catalog?.fieldCatalog else { return [] }
        return ProxyNodeCatalog.typeIDs(in: catalog, creating: true, current: nil)
    }

     
     
    private func nodeEditor(_ node: Node) -> some View {
        ConfigurationOriginalNodePage(session: session, name: node.name)
    }

     
    private func candidates(excluding name: String) -> DialerProxyCandidates {
        ConfigurationOriginalNodePage.candidates(excluding: name, in: session)
    }

    private func add(_ edited: String) async throws {
        let node = OriginalListEdits.handWrittenOrder(try OrderedJSON.parse(edited))
        guard case .string(let name)? = node.node(at: ["name"]), !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw OriginalListError.unnamed
        }
        guard nodes?.contains(where: { $0.name == name }) != true else { throw OriginalListError.taken(name) }
        try await saveFromForm([OriginalListEdits.appending(node, toListOf: nodes?.count, at: "proxies")])
    }

    private func saveFromForm(_ steps: [ConfigurationTextStep]) async throws {
        try await ConfigurationOriginalNodePage.saveFromForm(steps, session: session)
    }

     
     
     
     
    private func swipeToDelete(_ offsets: IndexSet) {
        delete(offsets.map { shown[$0].index })
    }

    private func delete(_ indices: [Int]) {
        guard let document = session.page?.document, let nodes else { return }
        for node in nodes where indices.contains(node.index) {
            let places = OriginalListEdits.uses(ofNode: node.name, in: document)
            if !places.isEmpty { return session.refuseDeleting(node.name, usedBy: places) }
        }
        let deleted = nodes.filter { indices.contains($0.index) }.map(\.name)
        Task {
            guard await !session.keptRulesRefuseDeleting(deleted) else { return }
            await session.editOriginal(steps: OriginalListEdits.deleting(indices, under: [.key("proxies")]))
        }
    }
}

 
 
 
 
 
 
struct ConfigurationOriginalNodePage: View {
    @ObservedObject var session: ConfigurationEditorSession
    let name: String

     
    static func node(named name: String, in session: ConfigurationEditorSession) -> (index: Int, value: OrderedJSON)? {
        guard case .array(let items)? = session.value(at: ["proxies"]) else { return nil }
        for (offset, item) in items.enumerated() where ConfigurationEditorCopy.entryTitle(item, index: offset) == name {
            return (offset, item)
        }
        return nil
    }

    var body: some View {
        if let node = Self.node(named: name, in: session) {
            if let record = CustomNodesView.record(fromNodeJSON: node.value.serialized()) {
                ProxyNodeDetailsView(
                    record: record,
                    retest: {},
                    saveNode: { original, edited in try await save(original, edited) },
                    allowsRename: false,
                    showsTesting: false,
                    dialerRouting: .payloadField,
                    dialerCandidates: { Self.candidates(excluding: name, in: session) }
                )
            } else {
                 
                 
                ConfigurationOriginalValueView(session: session, title: name, value: node.value, choices: nil) { _ in }
            }
        } else {
            List { Text(clash: .copy("None")).foregroundStyle(.secondary) }
        }
    }

     
    static func candidates(excluding name: String, in session: ConfigurationEditorSession) -> DialerProxyCandidates {
        let options = RulePolicyOptions.make(document: session.page?.document)
        return DialerProxyCandidates(groups: options.groups.filter { $0.name != name },
                                     proxies: options.proxies.filter { $0.name != name })
    }

    private func save(_ original: String, _ edited: String) async throws {
        guard let node = Self.node(named: name, in: session) else {
            throw OriginalListError.refused(ConfigurationTextEditRefusal(rawCode: "notFound", message: ""))
        }
        let steps = try OriginalListEdits.nodeEdits(written: node.value, formOriginalJSON: original, formEditedJSON: edited,
                                                    at: [.key("proxies"), .index(node.index)])
        try await Self.saveFromForm(steps, session: session)
    }

     
     
     
    static func saveFromForm(_ steps: [ConfigurationTextStep], session: ConfigurationEditorSession) async throws {
        do {
            do {
                try await session.model.editOriginalConfiguration(session.profileID, steps: steps)
            } catch OriginalEditingError.followsSubscription {
                 
                 
                session.model.detachingLinkOriginals.insert(session.profileID)
                defer { session.model.detachingLinkOriginals.remove(session.profileID) }
                try await session.model.editOriginalConfiguration(session.profileID, steps: steps)
            }
        } catch let refused as ConfigurationTextEditRefusal where refused.editTheSourceInstead {
            session.refusal = .init(sentence: refused.errorDescription ?? refused.message, coreWords: refused.failureReason,
                                    editTheSourceInstead: true)
        } catch let refused as ConfigurationTextEditRefusal {
            throw OriginalListError.refused(refused)
        }
        await session.reload()
    }
}

 
 
enum OriginalListError: LocalizedError, Equatable {
    case unnamed
    case taken(String)
    case refused(ConfigurationTextEditRefusal)

    var errorDescription: String? {
        let locale = AppPreferences.language().locale
        switch self {
        case .unnamed:
            return ClashCopy.string("Give the node a name.", locale: locale)
        case .taken(let name):
            return ClashCopy.string(for: .format("A node named “%@” is already in this configuration.", [name]), locale: locale)
        case .refused(let refused):
             
            return ([ClashCopy.string(refused.errorDescription ?? "", locale: locale)] + [refused.failureReason].compactMap { $0 })
                .filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
    }
}

 

 
 
 
 
 
struct ConfigurationOriginalProxyProvidersView: View {
    @ObservedObject var session: ConfigurationEditorSession
    @State private var search = ""
     
    @State private var library: [ConfigurationLibraryPicks.Source]?
    @State private var libraryFailure: String?
    @State private var adding = false
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

    private var entries: [OriginalEntry] { OriginalEntry.all(in: session.value(at: ["proxy-providers"])) }
    private var document: OrderedJSON { session.page?.document ?? .object([]) }
     
    private var links: [ConfigurationLibraryPicks.Source] { (library ?? []).filter(Self.isLink) }
     
     
    private var ownEntries: [OriginalEntry] {
        let own = Set(Self.ownSetNames(in: document, links: links))
        return matching(entries.filter { own.contains($0.name) }, search) { [$0.name, $0.type ?? ""] }
    }

     
     
     
    static func ownSetNames(in document: OrderedJSON, links: [ConfigurationLibraryPicks.Source]) -> [String] {
        let fromLibrary = Set(links.compactMap { ConfigurationLibraryPicks.addedSetName($0, in: document) })
        return OriginalEntry.all(in: document.topLevelValue("proxy-providers")).map(\.name).filter { !fromLibrary.contains($0) }
    }

     
     
     
     
    var body: some View {
        let types = ConfigurationTypeWords.names(.proxyProviders, copy: fieldCopy, locale: locale)
        let words = search.trimmingCharacters(in: .whitespaces).lowercased()
        let shownLinks = links.filter { source in
            words.isEmpty || [source.record.displayLabel(locale: locale), ConfigurationLibraryPicks.linkTitle(source, in: document)]
                .contains { $0.lowercased().contains(words) }
        }
        List {
            if library == nil, let libraryFailure {
                Section { Text(verbatim: libraryFailure).foregroundStyle(.secondary) }
            } else if library == nil {
                Section { ProgressView().frame(maxWidth: .infinity) }
            } else if !shownLinks.isEmpty {
                Section {
                    ForEach(shownLinks) { source in linkSwitch(source) }
                } header: {
                    Text(clash: .copy("Node Library"))
                } footer: {
                    Text(clash: .copy("A link is added whole and updates as the library sets it to. To take single nodes, use Proxies."))
                }
            }
            Section {
                if entries.isEmpty, links.isEmpty {
                    Text(clash: ConfigurationEmptyList.sentence(for: "proxy-providers")).foregroundStyle(.secondary)
                        .accessibilityIdentifier("configuration-editor.list.empty")
                }
                ForEach(ownEntries) { entry in
                    ClashNativeNavigationLink {
                        ConfigurationOriginalProxyProviderView(session: session, name: entry.name)
                            .configurationPushedAlertHost(session)
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: entry.name).lineLimit(1)
                            Spacer()
                            Text(verbatim: ConfigurationTypeWords.word(entry.type, in: types)).foregroundStyle(.secondary)
                        }
                    }
                     
                     
                     
                    .accessibilityIdentifier("configuration-editor.original-providers.entry")
                }
                .onDelete { offsets in let shown = ownEntries; delete(offsets.map { shown[$0].name }) }
                Button { adding = true } label: {
                    Label { Text(clash: .copy("New…")) } icon: { Image(systemName: ClashSymbol.plus.name) }
                }
                .disabled(session.isSaving || session.hasOriginalChangesOwed)
                .accessibilityIdentifier("configuration-editor.original-providers.add")
            }
        }
        .searchable(text: $search)
        .navigationTitle(Text(clash: .copy(ConfigurationEditorCopy.title(of: .proxyProviders))))
        .clashSheet(isPresented: $adding) { ConfigurationNewProxyProviderSheet(session: session).clashModalPresentation(.form) }
         
         
         
         
        .task { await loadLibrary() }
    }

     
     
    private func linkSwitch(_ source: ConfigurationLibraryPicks.Source) -> some View {
        let name = ConfigurationLibraryPicks.addedSetName(source, in: document)
        let key = "library-link." + source.id
        return Toggle(isOn: Binding(get: { session.shownSwitch(key, else: name != nil) }, set: { on in
             
            if !on, session.refusesSwitchingOff(source) { return }
            session.pressSwitch(key, on) { await session.setLibraryLink(source, on: on) }
        })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: ConfigurationLibraryPicks.linkTitle(source, in: document))
                Text(clash: Self.detail(source, in: document)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("configuration-editor.library-sources.source")
    }

     
     
     
     
    static func isLink(_ source: ConfigurationLibraryPicks.Source) -> Bool {
        if case .link? = source.providerKind { return true }
        return false
    }

     
     
     
    static func detail(_ source: ConfigurationLibraryPicks.Source, in document: OrderedJSON) -> ClashDisplayText {
        let count = String(source.nodes.count)
        guard ConfigurationLibraryPicks.linkTitle(source, in: document) != source.label else {
            return .format("Link · %@ nodes", [count])
        }
        return ClashConfigurationSourceCopy.sentence("%@ · Link · %@ nodes", naming: source.record, then: [count])
    }

    private func loadLibrary() async {
        guard library == nil else { return }
        guard let store = session.model.configurationLibraryStore else {
            libraryFailure = ClashCopy.string("The node library can't be read.", locale: locale)
            return
        }
        do {
            library = try await Task.detached(priority: .userInitiated) { [profileID = session.profileID] in
                try ConfigurationLibraryPicks.sources(in: store, excludingThoseOf: profileID)
            }.value
        } catch {
            libraryFailure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

     
     
     
    private func delete(_ names: [String]) {
        Task {
            await session.queueOriginal { document in
                for name in names {
                    let places = OriginalListEdits.uses(ofProvider: name, in: document)
                    if !places.isEmpty { return .refuseDeleting(name, usedBy: places) }
                }
                let written = Set(OriginalEntry.all(in: document.topLevelValue("proxy-providers")).map(\.name))
                let left = names.filter(written.contains)
                return .write(left.isEmpty ? [] : OriginalListEdits.deleting(left, fromMappingAt: "proxy-providers"))
            }
        }
    }
}

 
 
 
 
struct ConfigurationOriginalProxyProviderView: View {
    @ObservedObject var session: ConfigurationEditorSession
    @State var name: String
    @State private var renaming = false
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

     
    static func types(_ catalog: ProfilesViewModel.SyntaxCatalog?) -> [String] {
        ProxyProviderCatalog.types(catalog)
    }

    private var path: [ConfigurationTextPathStep] { [.key("proxy-providers"), .key(name)] }
    private var fields: [(key: String, value: OrderedJSON)] {
        guard case .object(let items)? = session.value(at: ["proxy-providers", name]) else { return [] }
        return items
    }

    var body: some View {
        List {
            Section {
                Button { renaming = true } label: {
                    HStack {
                        Text(clash: .copy("Name"))
                        Spacer()
                        Text(verbatim: name).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(session.isSaving || session.hasOriginalChangesOwed)
                .accessibilityIdentifier("configuration-editor.original-providers.rename")
            }
            if let catalog = session.catalog?.fieldCatalog {
                let layout = ProxyProviderCatalog.layout(of: session.value(at: ["proxy-providers", name]), in: catalog)
                    .splittingOffThePlatformsRows(in: session.value(at: ["proxy-providers", name]))
                 
                 
                let sections = ProxyNodeCatalogSections.sections(of: layout, layoutPath: ProviderFieldCatalog.proxyBase,
                                                                 catalog: catalog, copy: fieldCopy, locale: locale)
                let provider = session.value(at: ["proxy-providers", name])
                ForEach(sections) { section in
                    Section {
                        ForEach(section.rows) { row in
                            ProxyProviderCatalogRow(session: session, providerPath: ["proxy-providers", name], row: row)
                                .disabled(ProxyNodeCatalogSections.inactive(row, in: provider, catalog: catalog))
                        }
                    } header: {
                        if let title = section.title { Text(clash: title) }
                    } footer: {
                        if let footer = section.footer { Text(verbatim: footer) }
                        if let summary = ProxyNodeCatalogSections.offSwitchSummary(over: section.rows, in: provider, catalog: catalog) {
                            Text(clash: fieldCopy.turnOnLine(summary, locale: locale))
                        }
                    }
                }
                if !layout.platformDecided.isEmpty {
                    Section {
                        ClashNativeNavigationLink {
                            ConfigurationSettingsNotApplyingView(items: layout.notApplying)
                        } label: {
                            ConfigurationNotApplyingLabel(count: layout.platformDecided.count)
                        }
                        .accessibilityIdentifier("configuration-editor.not-applying")
                    }
                }
            } else {
                 
                Section {
                    ForEach(fields, id: \.key) { field in
                        ClashNativeNavigationLink {
                            ConfigurationOriginalValueView(session: session, title: field.key, value: field.value,
                                                           choices: field.key == "type" ? Self.types(session.catalog) : nil) { json in
                                await session.editOriginal(path + [.key(field.key)], .set(json: json))
                            }
                            .configurationPushedAlertHost(session)
                        } label: {
                            HStack(alignment: .firstTextBaseline) {
                                Text(verbatim: field.key)
                                Spacer()
                                Text(clash: ConfigurationValueWords.words(field.value, field: nil, locale: AppPreferences.language().locale))
                                    .foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(Text(verbatim: name))
         
         
        .clashSheet(isPresented: $renaming) {
            ConfigurationRenameSheet(current: name,
                                     taken: Set(OriginalEntry.all(in: session.value(at: ["proxy-providers"])).map(\.name))) { newName in
                Task {
                    if await session.renameOriginal(.proxyProvider, from: name, to: newName) { name = newName }
                }
            }
            .clashModalPresentation(.form)
        }
    }
}

 
 
struct ConfigurationNewProxyProviderForm: View {
    let types: [String]
    let taken: Set<String>
     
    var catalog: ProfilesViewModel.SyntaxCatalog?
    let save: (String, OrderedJSON) -> Void
    @State private var name = ""
    @State private var type = ""
    @State private var location = ""
    @StateObject private var dismiss = ClashDismissHandle()
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

    private func field(_ path: String) -> ConfigurationField? { catalog?.fieldCatalog?.field(atCatalogPath: path) }
    private var typeField: ConfigurationField? { field("proxy-providers.*.type") }
    private var locationField: ConfigurationField? { field(type == "http" ? "proxy-providers.*.url" : "proxy-providers.*.path") }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var trimmedLocation: String { location.trimmingCharacters(in: .whitespaces) }
    private var valid: Bool {
        !trimmedName.isEmpty && !taken.contains(trimmedName) && !type.isEmpty
            && (type == "inline" || !trimmedLocation.isEmpty)
    }

    var body: some View {
        ClashFeatureNavigationContainer {
            Form {
                Section {
                    TextField(text: $name) { Text(clash: .copy("Name")) }
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .accessibilityIdentifier("configuration-editor.original-providers.new.name")
                    Picker(selection: $type) {
                        ForEach(types, id: \.self) {
                            Text(verbatim: fieldCopy.valueLabel($0, for: typeField, locale: locale) ?? $0).tag($0)
                        }
                    } label: { Text(verbatim: fieldCopy.title(for: typeField, key: "type", locale: locale)) }
                    .accessibilityIdentifier("configuration-editor.original-providers.new.type")
                    if type == "http" || type == "file" {
                        TextField(text: $location,
                                  prompt: fieldCopy.entry(for: locationField, locale: locale)?.example.map { Text(verbatim: $0) }) {
                            Text(verbatim: fieldCopy.title(for: locationField, key: type == "http" ? "url" : "path", locale: locale))
                        }
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .keyboardType(type == "http" ? .URL : .default)
                            .accessibilityIdentifier("configuration-editor.original-providers.new.location")
                    }
                }
            }
            .navigationTitle(Text(clash: .copy("Add Proxy Provider")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(clash: .copy("Cancel")) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save(trimmedName, OriginalListEdits.newProxyProvider(type: type, location: trimmedLocation))
                        dismiss()
                    } label: { Text(clash: .copy("Save")) }
                    .disabled(!valid)
                    .accessibilityIdentifier("configuration-editor.original-providers.new.save")
                }
            }
        }
        .clashCapturesDismiss(dismiss)
        .onAppear { if type.isEmpty { type = types.first ?? "" } }
    }
}

 
 
 
 
struct ConfigurationOriginalMembersView: View {
     
     
    typealias Change = (inout [String]) -> Void

    @ObservedObject var session: ConfigurationEditorSession
    let group: String
     
    let save: (@escaping Change) async -> Bool
     
    let written: () -> [String]?
    @State private var members: [String]
     
     
     
    @State private var owed = 0
     
    @State private var query = ""
    @State private var editMode: EditMode = .inactive

    init(session: ConfigurationEditorSession, group: String, members: [String],
         written: @escaping () -> [String]?, save: @escaping (@escaping Change) async -> Bool) {
        self.session = session
        self.group = group
        self.save = save
        self.written = written
        _members = State(initialValue: members)
    }

     
    static func names(_ value: OrderedJSON) -> [String]? {
        guard case .array(let items) = value else { return nil }
        var names: [String] = []
        for item in items {
            guard case .string(let name) = item else { return nil }
            names.append(name)
        }
        return names
    }

    private var nodes: [String] { OriginalEntry.all(in: session.value(at: ["proxies"])).map(\.name) }
    private var groups: [String] { OriginalEntry.all(in: session.value(at: ["proxy-groups"])).map(\.name).filter { $0 != group } }

     
     
    private var builtins: [String] {
        let type = OriginalEntry.all(in: session.value(at: ["proxy-groups"])).first { $0.name == group }
            .flatMap { entry -> String? in
                if case .string(let value)? = entry.value.topLevelValue("type") { return value }
                return nil
            }
        return ConfigurationMembersSources.builtins(catalog: session.catalog?.fieldCatalog, groupType: type)
    }

     
     
    private var notFound: [String] {
        let known = Set(builtins + groups + nodes)
        return members.filter { !known.contains($0) }
    }

    var body: some View {
         
         
         
        List {
            if searching.isEmpty {
                Section {
                    ForEach(members, id: \.self) { name in
                        Text(verbatim: name)
                    }
                     
                     
                     
                    .onDelete(perform: editMode.isEditing ? nil : { offsets in
                        let names = Set(offsets.map { members[$0] })
                        change { $0.removeAll(where: names.contains) }
                    })
                    .onMove { from, to in
                        var order = members
                        order.move(fromOffsets: from, toOffset: to)
                        change { list in
                            let present = Set(list), ordered = Set(order)
                            list = order.filter(present.contains) + list.filter { !ordered.contains($0) }
                        }
                    }
                } header: { Text("Selected (in priority order)") }
            }
            options("Built-in", filtered(builtins))
            options("Policy Groups", filtered(groups))
            options("Nodes", filtered(nodes))
            options("Not Found", filtered(notFound))
        }
        .searchable(text: $query)
        .navigationTitle(Text(verbatim: group))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if members.count > 1 {
                    ConfigurationReorderButton(editMode: $editMode, identifier: "configuration-editor.original.members.reorder")
                }
            }
        }
        .environment(\.editMode, $editMode)
         
         
         
         
         
         
        .accessibilityIdentifier("configuration-editor.original.members.list")
    }

    private var searching: String { query.trimmingCharacters(in: .whitespaces).lowercased() }

     
    private func filtered(_ names: [String]) -> [String] {
        let query = searching
        guard !query.isEmpty else { return names }
        return names.filter { $0.lowercased().contains(query) }
    }

    @ViewBuilder
    private func options(_ title: String, _ names: [String]) -> some View {
        if !names.isEmpty {
            Section {
                ForEach(names, id: \.self) { name in
                    Toggle(isOn: Binding(get: { members.contains(name) }, set: { on in
                        change { list in
                            if on, !list.contains(name) { list.append(name) }
                            if !on { list.removeAll { $0 == name } }
                        }
                    })) {
                        Text(verbatim: name)
                    }
                    .accessibilityIdentifier("configuration-editor.original.members.option.\(name)")
                }
            } header: { Text(clash: .copy(title)) }
        }
    }

     
     
    private func change(_ edit: @escaping Change) {
        var after = members
        edit(&after)
        guard after != members, !after.isEmpty else { return }
        members = after
        owed += 1
        Task {
            _ = await save(edit)
            owed -= 1
             
            if owed == 0 { members = written() ?? [] }
        }
    }
}
#endif
