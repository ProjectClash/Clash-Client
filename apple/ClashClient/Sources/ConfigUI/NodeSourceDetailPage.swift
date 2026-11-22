#if os(iOS)
import ClashClientKit
import ClashClientUI
import Combine
import SwiftUI

 
 
 
 
 
 
 
 
 
 
 

 

 
 
 
 
 
 
 
 
 
@MainActor
final class NodeSourceTickWriter: ObservableObject {
     
     
    enum Item: Hashable {
        case node(String)
        case nodeSet(String)

        func tick(_ checked: Bool) -> ConfigurationSourceTick {
            switch self {
            case .node(let name): .node(name, checked: checked)
            case .nodeSet(let key): .nodeSet(key, checked: checked)
            }
        }
    }

     
     
     
    static let quietNanoseconds: UInt64 = 1_000_000_000

    @Published private(set) var pressed = ClashPressedSwitches<Item>()
     
    @Published private(set) var failure: String?
    @Published private(set) var isWriting = false

    private var waiting: [(item: Item, checked: Bool, press: Int)] = []
     
    private var owesHandOver = false
    private var settler: TrailingEdgeSettler
    private var drained: [CheckedContinuation<Void, Never>] = []
    private let write: @MainActor ([ConfigurationSourceTick]) async throws -> Void
    private let readBack: @MainActor () async -> Void
    private let handOver: @MainActor () async -> Void
    private let message: @MainActor (Error) -> String

    init(quietNanoseconds: UInt64 = NodeSourceTickWriter.quietNanoseconds,
         write: @escaping @MainActor ([ConfigurationSourceTick]) async throws -> Void,
         readBack: @escaping @MainActor () async -> Void,
         handOver: @escaping @MainActor () async -> Void,
         message: @escaping @MainActor (Error) -> String = { ClashErrorCopy.message($0, locale: AppPreferences.language().locale) }) {
        settler = TrailingEdgeSettler(windowNanoseconds: quietNanoseconds)
        self.write = write
        self.readBack = readBack
        self.handOver = handOver
        self.message = message
    }

     
    func shown(_ item: Item, else read: Bool) -> Bool { pressed.shown(item, else: read) }

     
     
    func tap(_ item: Item, to checked: Bool) {
        failure = nil
        let press = pressed.press(item, checked)
        waiting.append((item, checked, press))
         
        settler.cancel()
        guard !isWriting else { return }
        isWriting = true
        Task { await drive() }
    }

     
     
    func leave() async {
        settler.cancel()
        await untilWritten()
        await handOverNow()
    }

     
    func untilWritten() async {
        while isWriting { await withCheckedContinuation { drained.append($0) } }
    }

    private func drive() async {
        while !waiting.isEmpty {
            let batch = waiting
            waiting = []
            do {
                try await write(batch.map { $0.item.tick($0.checked) })
                owesHandOver = true
            } catch {
                failure = message(error)
                clashLogConfigurationWriteFailure(error)
            }
            await readBack()
            for entry in batch { pressed.settle(entry.item, press: entry.press) }
        }
        isWriting = false
        let waiters = drained
        drained = []
        waiters.forEach { $0.resume() }
        if owesHandOver {
            settler.submit { [weak self] in
                guard let self else { return }
                Task { await self.handOverNow() }
            }
        }
    }

    private func handOverNow() async {
        guard owesHandOver, !isWriting else { return }
        owesHandOver = false
        await handOver()
    }
}

extension ProfilesViewModel {
     
     
     
     
     
     
    func saveSourceTicks(_ ticks: [ConfigurationSourceTick], ofSource sourceID: String, for id: String) async throws {
        await settleLibraryHousekeeping()
        var waited = 0
        while changingConfigurationLibrary, waited < 100 {
            try await Task.sleep(nanoseconds: 50_000_000)
            waited += 1
        }
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        var attempt = 0
        while true {
            do {
                let (prepared, generation) = try await Task.detached(priority: .userInitiated) {
                    () throws -> (PreparedConfigurationSourceUpdate, UInt64) in
                    let generation = try library.snapshot().generation
                    let bound = ConfigurationCenterSourceBridge.BoundInputs()
                    return (try library.prepareSourceTicks(ticks, ofSource: sourceID, for: id, expectedGeneration: generation,
                                                           resolveInput: bound.resolve), generation)
                }.value
                guard !prepared.compositions.isEmpty else { return }
                try await saveConfigurationPlan(candidate: prepared.candidate, payloads: prepared.payloads,
                                                compositions: prepared.compositions, generation: generation,
                                                restagesConfigurationInUse: false)
                return
            } catch ConfigurationLibraryError.staleGeneration where attempt < 3 {
                attempt += 1
            }
        }
    }
}

 
 
 
 
@MainActor
final class NodeSourceUse: ObservableObject {
    struct Node: Identifiable, Equatable {
        let name: String
        let type: String
        var id: String { name }
    }

    let profileID: String
    let sourceID: String
     
    let configurationName: String
    @Published private(set) var nodes: [Node] = []
    @Published private(set) var nodeSets: [String] = []
     
    @Published private(set) var scope: ConfigurationNodeScope?
     
    @Published private(set) var takesSource = false
    @Published private(set) var isRead = false
     
    @Published private(set) var keptLastTick: NodeSourceTickWriter.Item?
    private(set) var writer: NodeSourceTickWriter!
    private let model: ProfilesViewModel
    private var forwarding: AnyCancellable?

    init(model: ProfilesViewModel, profileID: String, sourceID: String, configurationName: String,
         quietNanoseconds: UInt64 = NodeSourceTickWriter.quietNanoseconds,
         write: (@MainActor ([ConfigurationSourceTick]) async throws -> Void)? = nil,
         handOver: (@MainActor () async -> Void)? = nil) {
        self.model = model
        self.profileID = profileID
        self.sourceID = sourceID
        self.configurationName = configurationName
        let id = profileID, source = sourceID
        writer = NodeSourceTickWriter(
            quietNanoseconds: quietNanoseconds,
            write: write ?? { [model] ticks in try await model.saveSourceTicks(ticks, ofSource: source, for: id) },
            readBack: { [weak self] in await self?.read() },
            handOver: handOver ?? { [model] in await model.restageConfigurationInUse(id) },
            message: { error in Self.refusal(error) })
         
        forwarding = writer.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

     
    func read() async {
        guard let store = model.configurationLibraryStore else { return }
        let profileID = profileID, sourceID = sourceID
        let read = try? await Task.detached(priority: .userInitiated) {
            () throws -> (takes: Bool, scope: ConfigurationNodeScope?, nodes: [Node], sets: [String]) in
            let snapshot = try store.snapshot()
            guard let recipe = snapshot.recipes.first(where: { $0.id == profileID }), recipe.preservesOriginal != true,
                  let reference = recipe.sources.first(where: { $0.id == sourceID }) else { return (false, nil, [], []) }
            let document = try OrderedJSON.parse(try store.payload(reference).documentJSON)
            var nodes: [Node] = []
            if case .array(let entries)? = document.topLevelValue("proxies") {
                for entry in entries {
                    guard case .string(let name)? = entry.topLevelValue("name") else { continue }
                    let type: String
                    switch entry.topLevelValue("type") {
                    case .string(let written)?: type = written
                    case .scalar(let token)?: type = token
                    default: type = ""
                    }
                    nodes.append(Node(name: name, type: type))
                }
            }
            var sets: [String] = []
            if case .object(let providers)? = document.topLevelValue("proxy-providers") { sets = providers.map(\.key) }
            return (true, recipe.nodeScopes?[sourceID], nodes, sets)
        }.value
        guard let read else { return }
        takesSource = read.takes
        scope = read.scope
        nodes = read.nodes
        nodeSets = read.sets
        isRead = true
    }

     
    func readChecked(_ item: NodeSourceTickWriter.Item) -> Bool {
        switch item {
        case .node(let name): scope?.choosesNode(named: name) ?? true
        case .nodeSet(let key): scope.map { $0.providerKeys.contains(key) } ?? true
        }
    }

    func isChecked(_ item: NodeSourceTickWriter.Item) -> Bool { writer.shown(item, else: readChecked(item)) }

     
    var checkedCount: Int {
        nodes.filter { isChecked(.node($0.name)) }.count + nodeSets.filter { isChecked(.nodeSet($0)) }.count
    }

     
     
    func tap(_ item: NodeSourceTickWriter.Item) {
        let checked = isChecked(item)
        if checked, checkedCount <= 1 {
            keptLastTick = item
            return
        }
        keptLastTick = nil
        writer.tap(item, to: !checked)
    }

     
     
    func detail(of node: Node) -> ClashDisplayText? {
         
         
         
        if !isChecked(.node(node.name)),
           readChecked(.node(node.name)) || scope?.excludedNodeNames?.contains(node.name) == true {
            return .format("Removed from “%@”", [configurationName])
        }
        return node.type.isEmpty ? nil : .verbatim(node.type)
    }

     
    func leave() async { await writer.leave() }

    static func refusal(_ error: Error) -> String {
        let locale = AppPreferences.language().locale
        if case ConfigurationSourceTickError.lastTick = error {
            return ClashCopy.string(NodeSourceDetailCopy.lastTick, locale: locale)
        }
        return ClashErrorCopy.message(error, locale: locale)
    }
}

 

 
enum NodeSourceDetailCopy {
     
    static let lastTick = "Keep at least one node. To stop using this source, turn it off on the node sources page."

     
    static func nodesFor(_ configuration: String) -> ClashDisplayText {
        .format("Nodes for “%@”", [configuration])
    }

     
    static func allNodes(_ count: Int) -> ClashDisplayText { .format("All %@ nodes", [String(count)]) }
    static func selected(_ count: Int) -> ClashDisplayText { .format("%@ selected", [String(count)]) }

     
     
     
     
    static func selected(_ chosen: Int, of total: Int) -> ClashDisplayText {
        .format("Selected %@ / %@", [String(chosen), String(total)])
    }

     
    static let nodeSetsChosen: ClashDisplayText = .copy("The whole proxy provider is used; its nodes change when it updates.")
    static let nodeSetsListed: ClashDisplayText = .copy("When the proxy provider updates, its nodes change with it.")

     
     
    static func deletionTakesNodes(from configurations: [String], locale: Locale) -> ClashDisplayText {
        .format(configurations.count == 1 ? "After deletion, %@ no longer has these nodes."
                                          : "After deletion, %@ no longer have these nodes.",
                [ProxyNodeLibraryCopy.quotedNames(configurations, locale: locale)])
    }

    static func deletionKeepsNodes(in originals: [String], locale: Locale) -> ClashDisplayText {
        .format(originals.count == 1 ? "After deletion, %@ keeps its current nodes and stops updating."
                                     : "After deletion, %@ keep their current nodes and stop updating.",
                [ProxyNodeLibraryCopy.quotedNames(originals, locale: locale)])
    }

    static let builtinCannotBeDeleted: ClashDisplayText = .copy("Built-in node sources can’t be deleted.")
}

 
 
 
struct NodeSourceDetailFacts {
    struct Node: Identifiable {
        let index: Int
        let name: String
        let type: String
        let json: String
        var id: Int { index }
    }

     
    struct Use: Equatable {
        let id: String
        let name: String
        let how: ClashDisplayText
    }

    let record: ConfigurationSourceRecord
    var nodes: [Node] = []
    var nodeSets: [ConfigurationCollection] = []
    var uses: [Use] = []
     
     
    var losing: [String] = []
     
    var keeping: [String] = []
     
    var showsChoice = false
     
     
     
    var isOriginalsOwnText = false

    var isLink: Bool {
        guard record.isRetainedSnapshot != true, record.nodeChain == nil, case .subscription = record.origin else { return false }
        return true
    }

    var link: String? {
        if case .subscription(let link) = record.origin { return link }
        return nil
    }

    var editsNodesInPlace: Bool { ProxyNodeLibraryFacts.editsInPlace(record) }

     
    func deletionNote(locale: Locale) -> [ClashDisplayText] {
        var lines: [ClashDisplayText] = []
        if !losing.isEmpty { lines.append(NodeSourceDetailCopy.deletionTakesNodes(from: losing, locale: locale)) }
        if !keeping.isEmpty { lines.append(NodeSourceDetailCopy.deletionKeepsNodes(in: keeping, locale: locale)) }
        return lines
    }

    var canBeDeleted: Bool {
        if case .bundled = record.origin { return false }
        return record.isRetainedSnapshot != true
    }

    static func read(sourceID: String, configurationID: String?, in store: ConfigurationLibraryStore,
                     configurations: [LibraryUsage.Configuration], locale: Locale) throws -> NodeSourceDetailFacts? {
        let snapshot = try store.snapshot()
        guard let record = snapshot.sources.first(where: { $0.id == sourceID }) else { return nil }
        var facts = NodeSourceDetailFacts(record: record)
        let document = try OrderedJSON.parse(try store.payload(.init(record)).documentJSON)
        if case .array(let entries)? = document.topLevelValue("proxies") {
            facts.nodes = entries.enumerated().compactMap { index, entry in
                guard case .string(let name)? = entry.topLevelValue("name"),
                      !name.hasPrefix(ConfigurationLibraryPicks.privatePrefix) else { return nil }
                let type = entry.topLevelValue("type")?.foundationValue as? String ?? ""
                return Node(index: index, name: name, type: type, json: entry.serialized())
            }
        }
        facts.nodeSets = ConfigurationCollection.read(sourceID: record.id, document: document, kind: .nodes)
        let inline = facts.nodes.map(\.name)
        let names = Dictionary(configurations.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        for recipe in snapshot.recipes {
            let name = names[recipe.id] ?? recipe.label
            if recipe.preservesOriginal == true {
                guard recipe.ruleSource.id == record.id else { continue }
                facts.uses.append(Use(id: recipe.id, name: name, how: .copy("Original Configuration (Rule Scheme)")))
                facts.keeping.append(name)
            } else if recipe.sources.contains(where: { $0.id == record.id }) {
                let how: ClashDisplayText
                if let scope = recipe.nodeScopes?[record.id] {
                    how = NodeSourceDetailCopy.selected(inline.filter { scope.choosesNode(named: $0) }.count, of: inline.count)
                } else {
                    how = .format(record.nodeCount == 1 ? "%@ node" : "%@ nodes", [String(record.nodeCount)])
                }
                facts.uses.append(Use(id: recipe.id, name: name, how: how))
                facts.losing.append(name)
            } else if recipe.ruleSource.id == record.id {
                facts.uses.append(Use(id: recipe.id, name: name, how: .copy("Rule Scheme")))
            }
        }
        if let configurationID, let recipe = snapshot.recipes.first(where: { $0.id == configurationID }) {
            facts.showsChoice = recipe.preservesOriginal != true && recipe.sources.contains { $0.id == record.id }
            facts.isOriginalsOwnText = recipe.preservesOriginal == true && recipe.ruleSource.id == record.id
        }
        return facts
    }
}

 

 
 
 
struct NodeSourceDetailPage: View {
    struct Configuration: Equatable {
        let id: String
        let name: String
    }

    @ObservedObject var model: ProfilesViewModel
    let sourceID: String
    var configuration: Configuration?
    var presentedAlone = false
    let changed: (ConfigurationLibrarySnapshot) -> Void
    let close: () -> Void

    @Environment(\.locale) private var locale
    @Environment(\.clashFeedback) private var feedback
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @State private var facts: NodeSourceDetailFacts?
    @State private var readFailure: String?
    @State private var use: NodeSourceUse?
    @State private var search = ""
    @State private var name = ""
    @State private var link = ""
    @State private var interval = 0
    @State private var busy = false
    @State private var updating = false
    @State private var updateStatus: String?
    @State private var errorMessage: String?
    @State private var confirmsRuleReplacement = false
    @State private var editsSource = false
    @State private var editsChain = false
    @State private var addsNode = false
    @State private var inspected: NodeSourceDetailFacts.Node?

    var body: some View {
        Group {
            if presentedAlone {
                ClashFeatureNavigationContainer { page }
            } else {
                page
            }
        }
    }

    private var page: some View {
        List { content }
            .clashProductModalSearchable(text: $search, prompt: Text(ClashCopy.key("Search Nodes")))
            .clashPageTitle(facts.map { ClashConfigurationSourceCopy.name($0.record) } ?? .copy("Node Source"))
            .clashToolbarUnlessInPanel {
                ToolbarItem(placement: .cancellationAction) {
                    if presentedAlone {
                        ClashSheetCloseButton(dismiss: { leave(); close() }).disabled(busy)
                    }
                }
            }
            .interactiveDismissDisabled(busy)
            .task { await read() }
            .onChange(of: model.libraryContentEpoch) { _ in Task { await read() } }
             
             
            .onReceive(model.$savedConfigurationGeneration.dropFirst()) { _ in
                Task {
                    await read()
                    changed(currentLibrary)
                }
            }
            .onDisappear { leave() }
            .modifier(ConfigurationSourceUpdateConflict(isPresented: $confirmsRuleReplacement) { refresh(replacingRules: true) })
            .clashProductModal(isPresented: $editsSource, role: .page) {
                if let record = facts?.record {
                    ConfigurationNodeSourceEditor(model: model, record: record, changed: took)
                }
            }
            .clashProductModal(isPresented: $editsChain, role: .page) {
                if let record = facts?.record {
                    ConfigurationChainEditor(model: model, existing: record, accept: { payload in
                        took(try await model.saveConfigurationChain(.init(record), replacement: payload))
                    }, close: { editsChain = false })
                }
            }
            .clashProductModal(isPresented: $addsNode, role: .page) {
                ConfigurationNodeSourceAdapter { imported in
                    guard let record = facts?.record,
                          case .array(let nodes) = try OrderedJSON.parse(imported.documentJSON).topLevelValue("proxies"),
                          nodes.count == 1 else { throw ConfigurationLibraryError.unreadable }
                    took(try await model.saveConfigurationCustomNode(.init(record), nodeJSON: nodes[0].serialized(), index: nil))
                }
            }
            .clashProductModal(item: $inspected, role: .page) { node in nodePage(node) }
    }

    @ViewBuilder
    private var content: some View {
        if let facts {
            if let line = errorMessage ?? model.sourceRefusals()[facts.record.id] ?? updateIssueMessage(currentLibrary, sourceID: facts.record.id, locale: locale) {
                Section {
                    Text(verbatim: line).foregroundStyle(.red).textSelection(.enabled)
                        .accessibilityIdentifier("node-source.error")
                }
            }
            linkSections(facts)
            chainSection(facts)
            nodesSection(facts)
            usesSection(facts)
            identitySection(facts)
            deletionSection(facts)
        } else if let readFailure {
            Section { Text(verbatim: readFailure).foregroundStyle(.secondary) }
        } else {
            Section { ProgressView().frame(maxWidth: .infinity) }
        }
    }

     

    @ViewBuilder
    private func linkSections(_ facts: NodeSourceDetailFacts) -> some View {
        if facts.isLink {
            if let usage = facts.record.subscriptionUsage {
                Section { NodeSourceUsageLines(usage: usage) } header: { Text(clash: .copy("Data Usage")) }
            }
            Section {
                Button { refresh() } label: {
                    HStack {
                        if updating { ProgressView().controlSize(.small) }
                        Text(clash: .copy("Update Source"))
                        Spacer(minLength: 8)
                        Text(verbatim: ProxyNodeLibraryCopy.lastUpdated(facts.record, locale: locale, now: Date()))
                            .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .disabled(busy || updating)
                .accessibilityIdentifier("node-source.update")
            } footer: {
                if let updateStatus {
                    Text(verbatim: updateStatus).accessibilityIdentifier("node-source.update-status")
                }
            }
            Section {
                TextField(text: $link) { Text(clash: .copy("Profile URL")) }
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .disableAutocorrection(true)
                    .onSubmit { saveSettings() }
                    .disabled(busy)
                    .accessibilityIdentifier("node-source.link")
                Picker(selection: Binding(get: { interval }, set: { interval = $0; saveSettings() })) {
                    Text(clash: .copy("Manually")).tag(0)
                    ForEach(Self.intervals(including: interval), id: \.self) { hours in
                        Text(clash: .format("Every %@ hours", [String(hours)])).tag(hours)
                    }
                } label: {
                    Text(clash: .copy("Update Interval"))
                }
                .disabled(busy)
                .accessibilityIdentifier("node-source.interval")
            } header: {
                Text(clash: .copy("Profile URL"))
            } footer: {
                Text(clash: .copy("Profile URL updates replace local node edits."))
            }
        }
    }

    static func intervals(including current: Int) -> [Int] {
        let offered = [1, 6, 12, 24, 48, 168]
        return current > 0 && !offered.contains(current) ? (offered + [current]).sorted() : offered
    }

     

    @ViewBuilder
    private func chainSection(_ facts: NodeSourceDetailFacts) -> some View {
        if let chain = facts.record.nodeChain {
            Section {
                Button { editsChain = true } label: {
                    NodeSourceValueRow { Text(verbatim: chain.entry.nodeName) } label: { Text(clash: .copy("Entry Node")) }
                }
                .accessibilityIdentifier("node-source.chain.entry")
                Button { editsChain = true } label: {
                    NodeSourceValueRow { Text(verbatim: chain.exit.nodeName) } label: { Text(clash: .copy("Exit Node")) }
                }
                .accessibilityIdentifier("node-source.chain.exit")
            }
            .foregroundStyle(.primary)
            .disabled(busy)
        }
    }

     

     
     
    private func choosing(_ facts: NodeSourceDetailFacts) -> NodeSourceUse? {
        guard facts.showsChoice, let use, use.takesSource else { return nil }
        return use
    }

    @ViewBuilder
    private func nodesSection(_ facts: NodeSourceDetailFacts) -> some View {
        if let use = choosing(facts) {
            NodeSourceUseSections(use: use, facts: facts, search: search, inspect: { inspected = $0 })
        } else {
            if !facts.nodes.isEmpty || facts.editsNodesInPlace {
                Section {
                    ForEach(facts.nodes.filter { NodeSourceUseSections.matches(search, $0.name, $0.type) }) { node in
                        Button { inspected = node } label: {
                            NodeSourceValueRow { Text(verbatim: typeWord(node.type)) } label: { Text(verbatim: node.name).lineLimit(1) }
                        }
                        .foregroundStyle(.primary)
                        .clashSwipeToDelete(swipe(node, facts))
                        .accessibilityIdentifier("node-source.node")
                    }
                    if facts.editsNodesInPlace {
                        Button { addsNode = true } label: { Text(clash: .copy("Add Custom Node")) }
                            .disabled(busy)
                            .accessibilityIdentifier("node-source.add-node")
                    }
                } header: {
                    Text(clash: .copy("Nodes"))
                }
            }
            if !facts.nodeSets.isEmpty {
                let words = ConfigurationTypeWords.Collections(copy: fieldCopy, locale: locale)
                Section {
                    ForEach(facts.nodeSets) { set in
                        ClashRoutedViewLink { ClashConfigurationCollectionView(collection: set) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: set.name)
                                Text(verbatim: words.line(set)).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("node-source.node-set")
                    }
                } header: {
                    Text(clash: .copy("Proxy Providers (Configuration Chapter)"))
                } footer: {
                    Text(clash: NodeSourceDetailCopy.nodeSetsListed)
                }
            }
        }
    }

     
     
    private func swipe(_ node: NodeSourceDetailFacts.Node, _ facts: NodeSourceDetailFacts) -> (() -> Void)? {
        if facts.editsNodesInPlace { return { deleteNode(node, of: facts.record) } }
        if facts.isOriginalsOwnText { return { removeFromOriginal(node) } }
        return nil
    }

    private func typeWord(_ type: String) -> String {
        ConfigurationTypeWords.word(type, in: ConfigurationTypeWords.names(.proxies, copy: fieldCopy, locale: locale))
    }

     
     
    @ViewBuilder
    private func nodePage(_ node: NodeSourceDetailFacts.Node) -> some View {
        if let facts, facts.isOriginalsOwnText, let configuration {
             
            OriginalNodeEditorPage(model: model, profileID: configuration.id, name: node.name,
                                   saved: { Task { await read() } }, close: { inspected = nil })
        } else if let facts, facts.editsNodesInPlace, let record = CustomNodesView.record(fromNodeJSON: node.json) {
            ClashFeatureNavigationContainer {
                ProxyNodeDetailsView(record: record, retest: {}, saveNode: { _, json in
                    took(try await model.saveConfigurationCustomNode(.init(facts.record), nodeJSON: json, index: node.index))
                }, showsTesting: false, onDone: { inspected = nil }, commitTitle: "Save")
            }
            .clashModalPresentation(.page)
        } else if let record = CustomNodesView.record(fromNodeJSON: node.json) {
            ProxyNodeDetailSheet(nodeName: record.name, yaml: nil, providersDir: nil, suppliedDetails: record.protocolDetails)
        } else {
            ClashOpeningCancelButton()
        }
    }

     

    private func usesSection(_ facts: NodeSourceDetailFacts) -> some View {
        Section {
            if facts.uses.isEmpty {
                Text(clash: .copy("No configuration uses it")).foregroundStyle(.secondary)
            }
            ForEach(facts.uses, id: \.id) { use in
                NodeSourceValueRow { Text(clash: use.how) } label: { Text(verbatim: use.name).lineLimit(1) }
                    .accessibilityIdentifier("node-source.used-by")
            }
        } header: {
            Text(clash: .copy("Configurations Using It"))
        }
    }

     

    private func identitySection(_ facts: NodeSourceDetailFacts) -> some View {
        Section {
            NodeSourceValueRow(combinesForAccessibility: false) {
                TextField(text: $name) { Text(clash: .copy("Name")) }
                    .multilineTextAlignment(.trailing)
                    .onSubmit { rename() }
                    .disabled(busy || facts.record.isRetainedSnapshot == true)
                    .accessibilityIdentifier("node-source.name")
            } label: {
                Text(clash: .copy("Name"))
            }
            switch facts.record.origin {
            case .file(let file), .bundled(let file):
                if file != facts.record.label { Text(verbatim: file).foregroundStyle(.secondary) }
            case .customNodes, .subscription:
                EmptyView()
            }
            if let link = facts.link {
                Button {
                    ClashClipboard.copy(link, feedback: feedback, noun: "Link", operation: "configuration.source.copy-link")
                } label: {
                    Text(clash: .copy("Copy Profile URL"))
                }
                .accessibilityIdentifier("node-source.copy-link")
            }
            if facts.record.isRetainedSnapshot != true, facts.record.nodeChain == nil {
                Button { editsSource = true } label: { Text(clash: .copy("Edit Nodes Source")) }
                    .disabled(busy)
                    .accessibilityIdentifier("node-source.edit-source")
            }
        } footer: {
            if facts.record.isRetainedSnapshot == true {
                Text(clash: .copy("This saved copy no longer receives source updates."))
            }
        }
    }

     

    @ViewBuilder
    private func deletionSection(_ facts: NodeSourceDetailFacts) -> some View {
        if facts.canBeDeleted {
            Section {
                Button(role: .destructive) { delete(facts) } label: {
                    Text(clash: .copy(facts.record.nodeChain == nil ? "Delete Node Source" : "Delete Proxy Chain"))
                }
                .disabled(busy || updating)
                .accessibilityIdentifier("node-source.delete")
            } footer: {
                let lines = facts.deletionNote(locale: locale)
                if !lines.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in Text(clash: line) }
                    }
                    .accessibilityIdentifier("node-source.delete-note")
                }
            }
        } else if case .bundled = facts.record.origin {
            Section {
                Text(clash: NodeSourceDetailCopy.builtinCannotBeDeleted).foregroundStyle(.secondary)
            }
        }
    }

     

    @State private var currentLibrary = ConfigurationLibrarySnapshot()

    private var configurationsNamed: [LibraryUsage.Configuration] {
        model.profiles.map { LibraryUsage.Configuration(id: $0.id, name: ProfileRowPresentation.label(for: $0, locale: locale)) }
    }

    private func read() async {
        guard let store = model.configurationLibraryStore else { return }
        let id = sourceID, configurationID = configuration?.id, configurations = configurationsNamed, locale = locale
        do {
            let read = try await Task.detached(priority: .userInitiated) {
                () throws -> (NodeSourceDetailFacts?, ConfigurationLibrarySnapshot) in
                (try NodeSourceDetailFacts.read(sourceID: id, configurationID: configurationID, in: store,
                                                configurations: configurations, locale: locale), try store.snapshot())
            }.value
            currentLibrary = read.1
            guard let fresh = read.0 else {
                 
                close()
                return
            }
             
             
            if let configuration, fresh.showsChoice {
                let list = use ?? NodeSourceUse(model: model, profileID: configuration.id, sourceID: id,
                                                configurationName: configuration.name)
                await list.read()
                use = list
            }
            let first = facts == nil
             
             
            if first || name == shownName(of: facts?.record) {
                name = fresh.record.displayLabel(locale: locale)
            }
            facts = fresh
            if first {
                let settings = ConfigurationSourceSettingsDraft(source: fresh.record)
                link = settings.url
                interval = settings.intervalHours
            }
        } catch {
            readFailure = ClashErrorCopy.message(error, locale: locale)
        }
    }

    private func shownName(of record: ConfigurationSourceRecord?) -> String {
        record?.displayLabel(locale: locale) ?? ""
    }

    private func took(_ updated: ConfigurationLibrarySnapshot) {
        currentLibrary = updated
        changed(updated)
        Task { await read() }
    }

     
     
     
    private func leave() {
        if let record = facts?.record {
            if name.trimmingCharacters(in: .whitespacesAndNewlines) != record.displayLabel(locale: locale) { rename() }
            if facts?.isLink == true, link.trimmingCharacters(in: .whitespacesAndNewlines) != ConfigurationSourceSettingsDraft(source: record).url {
                saveSettings()
            }
        }
        guard let use else { return }
        Task { await use.leave() }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        errorMessage = nil
        Task {
            defer { busy = false }
            do { try await operation() } catch {
                errorMessage = ClashConfigurationUpdateCopy.message(error, locale: locale)
            }
        }
    }

    private func rename() {
        guard let record = facts?.record else { return }
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty, typed != record.displayLabel(locale: locale) else {
            name = record.displayLabel(locale: locale)
            return
        }
        let stored = ClashConfigurationSourceCopy.nameToStore(typed, origin: record.origin, locale: locale)
        perform { took(try await model.renameConfigurationSource(record.id, label: stored)) }
    }

    private func saveSettings() {
        guard let record = facts?.record, facts?.isLink == true else { return }
        var settings = ConfigurationSourceSettingsDraft(source: record)
        let typed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URLComponents(string: typed)
        guard url?.scheme != nil, !(url?.host?.isEmpty ?? true), url?.url != nil else {
            errorMessage = ClashCopy.string("This isn’t a link that can be opened.", locale: locale)
            return
        }
        settings.url = typed
        settings.intervalHours = interval
        guard settings != ConfigurationSourceSettingsDraft(source: record) else { return }
        perform { took(try await model.saveConfigurationSourceSettings(record.id, draft: settings, label: nil)) }
    }

    private func refresh(replacingRules: Bool = false) {
        guard let source = facts?.record, !busy else { return }
        updating = true
        updateStatus = nil
        busy = true
        errorMessage = nil
        Task {
            defer { busy = false; updating = false }
            do {
                let outcome = try await ConfigurationSourceUpdate.run(source, replacingRules: replacingRules, model: model,
                                                                      locale: locale, changed: took,
                                                                      status: { updateStatus = $0 })
                let label = source.displayLabel(locale: locale)
                updateStatus = (model.wasPutBack(source.id) ? .copy(ProfilesViewModel.putBackKey)
                    : outcome.changed ? ClashFeedbackCopy.updated(label) : ClashFeedbackCopy.upToDate(label))
                    .resolved(locale: locale)
                if !outcome.failures.isEmpty { errorMessage = outcome.failures.joined(separator: "\n") }
            } catch {
                updateStatus = nil
                errorMessage = ClashConfigurationUpdateCopy.message(error, locale: locale)
                if error is ConfigurationRuleReplay.Conflict { confirmsRuleReplacement = true }
            }
        }
    }

     
     
    private func delete(_ facts: NodeSourceDetailFacts) {
        let label = facts.record.displayLabel(locale: locale)
        perform {
            guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            let generation = try await Task.detached { try store.snapshot().generation }.value
            let deletion = try await model.deleteConfigurationSourceRestorably(facts.record.id, generation: generation)
            changed(deletion.snapshot)
            close()
            ConfigurationLibraryUndo.offer(feedback, name: label, deletion: deletion, model: model, changed: changed)
        }
    }

     
     
     
     
     
    private func removeFromOriginal(_ node: NodeSourceDetailFacts.Node) {
        guard let configuration else { return }
        guard !busy else { return }
        busy = true
        errorMessage = nil
        Task {
            defer { busy = false }
            do {
                let removal = try await model.removeNode(node.name, fromConfiguration: configuration.id)
                await read()
                ConfigurationLibraryUndo.offer(feedback, title: ProxyNodeLibraryCopy.removed(node.name, from: configuration.name),
                                               restored: ClashFeedbackCopy.restored(node.name),
                                               operation: "configuration.node.remove", identifier: "feedback.node.remove",
                                               model: model) { [model] in
                    try await model.restoreNodeRemoval(removal)
                }
            } catch {
                errorMessage = ProxyNodeLibraryCopy.refusal(error, locale: locale)
            }
        }
    }

    private func deleteNode(_ node: NodeSourceDetailFacts.Node, of record: ConfigurationSourceRecord) {
        perform {
            let updated = try await model.deleteConfigurationCustomNode(.init(record), index: node.index)
            took(updated)
            guard let after = updated.sources.first(where: { $0.id == record.id }) else { return }
            let changed = changed
            ConfigurationLibraryUndo.offer(feedback, title: ClashFeedbackCopy.deleted(node.name),
                                           restored: ClashFeedbackCopy.restored(node.name),
                                           operation: "library.delete", identifier: "feedback.library.delete",
                                           model: model) { [model] in
                changed(try await model.insertConfigurationCustomNode(.init(after), nodeJSON: node.json, at: node.index))
            }
        }
    }
}

 
 
 
private struct NodeSourceUseSections: View {
    @ObservedObject var use: NodeSourceUse
    let facts: NodeSourceDetailFacts
    let search: String
    let inspect: (NodeSourceDetailFacts.Node) -> Void
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

    static func matches(_ search: String, _ name: String, _ type: String) -> Bool {
        let words = search.trimmingCharacters(in: .whitespaces)
        return words.isEmpty || name.localizedCaseInsensitiveContains(words) || type.localizedCaseInsensitiveContains(words)
    }

    var body: some View {
        Section {
            ForEach(use.nodes.filter { Self.matches(search, $0.name, $0.type) }) { node in
                tickRow(.node(node.name), title: node.name, detail: use.detail(of: node),
                        inspect: facts.nodes.first { $0.name == node.name })
            }
            if !use.nodes.isEmpty {
                NodeSourceValueRow {
                    Text(clash: NodeSourceDetailCopy.selected(use.nodes.filter { use.isChecked(.node($0.name)) }.count))
                } label: {
                    Text(clash: NodeSourceDetailCopy.allNodes(use.nodes.count))
                }
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("node-source.use.count")
            }
        } header: {
            Text(clash: NodeSourceDetailCopy.nodesFor(use.configurationName))
        } footer: {
            if let failure = use.writer.failure {
                Text(verbatim: failure).foregroundStyle(.red).accessibilityIdentifier("node-source.use.failure")
            }
        }
        if !facts.nodeSets.isEmpty {
            let words = ConfigurationTypeWords.Collections(copy: fieldCopy, locale: locale)
            Section {
                ForEach(facts.nodeSets) { set in
                    tickRow(.nodeSet(set.name), title: set.name, detail: .verbatim(words.line(set)), inspect: nil)
                }
            } header: {
                Text(clash: .copy("Proxy Providers (Configuration Chapter)"))
            } footer: {
                Text(clash: NodeSourceDetailCopy.nodeSetsChosen)
            }
        }
    }

    private func tickRow(_ item: NodeSourceTickWriter.Item, title: String, detail: ClashDisplayText?,
                         inspect node: NodeSourceDetailFacts.Node?) -> some View {
        let checked = use.isChecked(item)
        return HStack(spacing: ClashClientUI.ClashTheme.Spacing.row) {
            Button { use.tap(item) } label: {
                HStack(spacing: ClashClientUI.ClashTheme.Spacing.row) {
                    ClashSelectionCircle(isSelected: checked)
                    VStack(alignment: .leading, spacing: ClashClientUI.ClashTheme.Spacing.tight) {
                        Text(verbatim: title).foregroundStyle(.primary).lineLimit(1)
                        if use.keptLastTick == item {
                            Text(clash: .copy(NodeSourceDetailCopy.lastTick)).font(.caption).foregroundStyle(.orange)
                                .accessibilityIdentifier("node-source.use.last-tick")
                        } else if let detail, !detail.isBlank {
                            Text(clash: detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(checked ? .isSelected : [])
            .accessibilityIdentifier("node-source.use.tick")
            if let node {
                Button { inspect(node) } label: {
                    Image(systemName: ClashSymbol.infoCircle.name)
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: ClashClientUI.ClashTheme.Control.minimumHitTarget,
                               height: ClashClientUI.ClashTheme.Control.minimumHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text(clash: .copy("Details")))
                .accessibilityIdentifier("node-source.use.info")
            }
        }
         
        .accessibilityElement(children: .contain)
    }
}

 
 
private struct NodeSourceUsageLines: View {
    let usage: ConfigurationSubscriptionUsage
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: ClashClientUI.ClashTheme.Spacing.tight) {
            if let traffic = ClashSubscriptionUsageFormat.traffic(usage) { Text(clash: traffic) }
            if let fraction = usage.fraction {
                ProgressView(value: fraction, total: 1).progressViewStyle(.linear).tint(.accentColor)
            }
            if let expiry = ClashSubscriptionUsageFormat.expiry(usage, locale: locale) { Text(clash: expiry) }
        }
        .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("node-source.usage")
    }
}
 
 
 
 
 
private struct NodeSourceValueRow<Content: View, Label: View>: View {
    private let combinesForAccessibility: Bool
    private let content: Content
    private let label: Label

    init(combinesForAccessibility: Bool = true, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.combinesForAccessibility = combinesForAccessibility
        self.content = content()
        self.label = label()
    }

    var body: some View {
        let row = HStack {
            label
            Spacer(minLength: 12)
            content.foregroundStyle(.secondary)
        }
        if combinesForAccessibility {
            row.accessibilityElement(children: .combine)
        } else {
            row
        }
    }
}

#endif
