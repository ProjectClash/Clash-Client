import Foundation
import ClashClientKit
import ClashClientUI

 
 
 
 
 
 
enum ConfigurationLibraryPicks {
     
    struct Node: Identifiable, Equatable {
        let sourceID: String
        let index: Int
        let name: String
        let type: String
        let value: OrderedJSON
         
         
         
        var isCompanion = false
        var id: String { sourceID + "\u{1F}" + String(index) }

         
        var dialer: String? {
            guard case .string(let name)? = value.topLevelValue("dialer-proxy"), !name.isEmpty else { return nil }
            return name
        }
    }

     
    struct Source: Identifiable, Equatable {
        let record: ConfigurationSourceRecord
        let nodes: [Node]
        var id: String { record.id }
        var label: String { record.label }

         
         
        var offered: [Node] { nodes.filter { !$0.isCompanion } }

         
         
         
         
         
         
        var providerKind: ProviderKind? {
            switch record.origin {
            case .subscription(let link) where !link.trimmingCharacters(in: .whitespaces).isEmpty: return .link(link)
            case .file, .customNodes:
                guard record.nodeChain == nil, !nodes.isEmpty,
                      !nodes.contains(where: { $0.dialer.map { !ConfigurationLibraryPicks.builtinNames.contains($0) } ?? false })
                else { return nil }
                return .nodes
            default: return nil
            }
        }
    }

    enum ProviderKind: Equatable {
        case link(String)
        case nodes
    }

     
     
     
     
     
    static func sources(in store: ConfigurationLibraryStore, excludingThoseOf profileID: String? = nil) throws -> [Source] {
        let snapshot = try store.snapshot()
        let recipe = profileID.flatMap { id in snapshot.recipes.first { $0.id == id } }
        let own = Set((recipe?.sources.map(\.id) ?? []) + [recipe?.ruleSource.id].compactMap { $0 })
        return try snapshot.sources.compactMap { record -> Source? in
            guard record.suppliesNodes, record.isListedInLibrary, !own.contains(record.id) else { return nil }
            if case .bundled = record.origin { return nil }
            let document = try OrderedJSON.parse(store.payload(.init(record)).documentJSON)
            var nodes: [Node] = []
            if case .array(let entries)? = document.topLevelValue("proxies") {
                for (index, entry) in entries.enumerated() {
                    guard case .string(let name)? = entry.topLevelValue("name"),
                          !name.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                    let type: String
                    switch entry.topLevelValue("type") {
                    case .string(let written)?: type = written
                    case .scalar(let token)?: type = token
                    default: type = ""
                    }
                    nodes.append(Node(sourceID: record.id, index: index, name: name, type: type, value: entry))
                }
            }
            if let chain = record.nodeChain { nodes = readable(chain, of: record.id, nodes) }
             
            nodes.removeAll { $0.name.hasPrefix(Self.privatePrefix) }
            let source = Source(record: record, nodes: nodes)
            return nodes.isEmpty && source.providerKind == nil ? nil : source
        }
    }

     
     
    static let privatePrefix = "__clash_"

     
     
     
    static func readable(_ chain: ConfigurationNodeChain, of recordID: String, _ nodes: [Node]) -> [Node] {
        let privateName = ConfigurationNodeChain.entryName(for: recordID)
        var taken = Set(nodes.map(\.name).filter { $0 != privateName })
        let entryName = uniqueName(chain.entry.nodeName, taken: &taken)
        return nodes.map { node in
            if node.name == privateName {
                return Node(sourceID: node.sourceID, index: node.index, name: entryName, type: node.type,
                            value: node.value.settingTopLevel("name", to: .string(entryName)), isCompanion: true)
            }
            guard node.dialer == privateName else { return node }
            return Node(sourceID: node.sourceID, index: node.index, name: node.name, type: node.type,
                        value: node.value.settingTopLevel("dialer-proxy", to: .string(entryName)))
        }
    }

     
     
     
    static let builtinNames: Set<String> = ["DIRECT", "REJECT", "REJECT-DROP", "COMPATIBLE", "PASS", "PASS-RULE", "GLOBAL"]

     
     
     
    static func takenNodeNames(in document: OrderedJSON) -> Set<String> {
        builtinNames.union(names(in: document.topLevelValue("proxies"))).union(names(in: document.topLevelValue("proxy-groups")))
    }

     
     
     
     
    static func takenNodeSetNames(in document: OrderedJSON) -> Set<String> {
        Set(keys(of: document.topLevelValue("proxy-providers")))
            .union(names(in: document.topLevelValue("proxy-groups"))).union(["default"])
    }

     
     
     
    private static func keys(of mapping: OrderedJSON?) -> [String] {
        guard case .object(let entries)? = mapping else { return names(in: mapping) }
        return entries.map(\.key)
    }

    private static func names(in list: OrderedJSON?) -> [String] {
        guard case .array(let items)? = list else { return [] }
        return items.compactMap { item in
            if case .string(let name)? = item.topLevelValue("name") { return name }
            return nil
        }
    }

     
     
    static func uniqueName(_ name: String, taken: inout Set<String>) -> String {
        var candidate = name
        var number = 2
        while taken.contains(candidate) {
            candidate = "\(name) \(number)"
            number += 1
        }
        taken.insert(candidate)
        return candidate
    }

     
    struct NodePlan {
        var steps: [ConfigurationTextStep]
         
        var renamed: [(from: String, to: String)]
         
        var added: Int
         
        var broughtAlong: [String]
    }

     
     
     
    struct UnreachableDialer: Error {
        let node: String
        let dialer: String
        var sentence: ClashDisplayText {
            .format("“%@” connects through “%@”, which neither the node library nor this configuration has.", [node, dialer])
        }
    }

     
     
     
     
     
     
     
     
    static func nodeSteps(_ picked: [Node], available: [Node] = [], in document: OrderedJSON) throws -> NodePlan {
        var existing: [OrderedJSON] = []
        if case .array(let items)? = document.topLevelValue("proxies") { existing = items }
        let there = takenNodeNames(in: document)
        func key(_ sourceID: String, _ name: String) -> String { sourceID + "\u{1F}" + name }
        var byName: [String: Node] = [:]
        for node in available + picked where byName[key(node.sourceID, node.name)] == nil {
            byName[key(node.sourceID, node.name)] = node
        }
         
        var ordered: [Node] = []
        var placed: Set<String> = []
        func place(_ node: Node, through path: Set<String>) throws {
            guard !placed.contains(node.id) else { return }
            if let dialer = node.dialer {
                if let target = byName[key(node.sourceID, dialer)], target.id != node.id {
                    if !path.contains(target.id) { try place(target, through: path.union([node.id])) }
                } else if !there.contains(dialer) {
                    throw UnreachableDialer(node: node.name, dialer: dialer)
                }
            }
            placed.insert(node.id)
            ordered.append(node)
        }
        for node in picked { try place(node, through: []) }

        var taken = there
        var names: [String: String] = [:]
        var renamed: [(from: String, to: String)] = []
        for node in ordered {
            let name = uniqueName(node.name, taken: &taken)
            names[key(node.sourceID, node.name)] = name
            if name != node.name { renamed.append((node.name, name)) }
        }
        let pickedIDs = Set(picked.map(\.id))
        var count: Int? = document.topLevelValue("proxies") == nil ? nil : existing.count
        var steps: [ConfigurationTextStep] = []
        for node in ordered {
            var value = node.value.settingTopLevel("name", to: .string(names[key(node.sourceID, node.name)] ?? node.name))
            if let dialer = node.dialer, let followed = names[key(node.sourceID, dialer)], followed != dialer {
                value = value.settingTopLevel("dialer-proxy", to: .string(followed))
            }
            steps.append(OriginalListEdits.appending(value, toListOf: count, at: "proxies"))
            count = (count ?? 0) + 1
        }
        let broughtAlong = ordered.filter { !pickedIDs.contains($0.id) }.map { names[key($0.sourceID, $0.name)] ?? $0.name }
        return NodePlan(steps: steps, renamed: renamed, added: ordered.count, broughtAlong: broughtAlong)
    }

     

     
     
    static func identity(of node: OrderedJSON) -> OrderedJSON {
        guard case .object(let fields) = node else { return node }
        return .object(fields.filter { $0.key != "name" && $0.key != "dialer-proxy" })
    }

     
     
     
     
    static func addedNodeIDs(_ sources: [Source], in document: OrderedJSON) -> Set<String> {
        guard case .array(let written)? = document.topLevelValue("proxies"), !written.isEmpty else { return [] }
        let have = written.map(identity(of:))
        return Set(sources.flatMap(\.nodes).filter { node in have.contains(identity(of: node.value)) }.map(\.id))
    }

     
     
    static func isAdded(_ source: Source, in document: OrderedJSON) -> Bool {
        addedSetName(source, in: document) != nil
    }

     
     
     
     
    static func linkTitle(_ source: Source, in document: OrderedJSON) -> String {
        addedSetName(source, in: document) ?? source.label
    }

     
    static func addedSetName(_ source: Source, in document: OrderedJSON) -> String? {
        guard let kind = source.providerKind,
              case .object(let sets)? = document.topLevelValue("proxy-providers") else { return nil }
        return sets.first { set in
            switch kind {
            case .link(let link):
                guard case .string(let url)? = set.value.topLevelValue("url") else { return false }
                return url.trimmingCharacters(in: .whitespaces) == link.trimmingCharacters(in: .whitespaces)
            case .nodes:
                guard case .array(let payload)? = set.value.topLevelValue("payload") else { return false }
                return payload.map(identity(of:)) == source.nodes.map { identity(of: $0.value) }
            }
        }?.key
    }

     
    static func renameNotice(added: Int, renamed: [(from: String, to: String)]) -> ClashDisplayText {
        .format("Added %@ nodes. Renamed to keep names unique: %@",
                [String(added), renamed.map { "“\($0.to)”" }.joined(separator: " ")])
    }

     
     
    static func notice(for plan: NodePlan) -> ClashDisplayText? {
        if !plan.renamed.isEmpty { return renameNotice(added: plan.added, renamed: plan.renamed) }
        guard !plan.broughtAlong.isEmpty else { return nil }
        return .format("Added %@ nodes, with the ones they connect through: %@",
                       [String(plan.added), plan.broughtAlong.map { "“\($0)”" }.joined(separator: " ")])
    }

     
     
     
     
     
     
     
     
     
    static func provider(for source: Source, taken: Set<String>) -> (name: String, value: OrderedJSON)? {
        guard let kind = source.providerKind else { return nil }
        var names = taken
        let label = source.label.trimmingCharacters(in: .whitespaces)
        let name = uniqueName(label.isEmpty ? "provider" : label, taken: &names)
        switch kind {
        case .link(let link):
            var fields: [(key: String, value: OrderedJSON)] = [("type", .string("http")), ("url", .string(link))]
             
             
             
            if let hours = source.record.updateIntervalHours, hours > 0 {
                fields.append(("interval", .scalar(String(hours * 3600))))
            }
            if let agent = source.record.userAgent?.trimmingCharacters(in: .whitespaces), !agent.isEmpty {
                fields.append(("header", .object([("User-Agent", .array([.string(agent)]))])))
            }
            return (name, .object(fields))
        case .nodes:
            return (name, .object([("type", .string("inline")), ("payload", .array(source.nodes.map(\.value)))]))
        }
    }
}

 
 
 
enum ConfigurationEmptyList {
    static func sentence(for key: String) -> ClashDisplayText {
        switch key {
        case "proxies": .copy("No nodes yet. Add one, or copy nodes from the node library.")
        case "proxy-providers": .copy("No node sets yet. A node set brings nodes from a link or a file.")
        case "proxy-groups": .copy("No policy groups yet. A group chooses which node traffic goes through.")
        case "rule-providers": .copy("No rule sets yet. A rule set is a list of rules kept at a link or in a file.")
        case "listeners": .copy("No listeners yet. A listener opens a port that other apps or devices connect through.")
        case "tunnels": .copy("No tunnels yet. A tunnel forwards a port on this device to an address, through a proxy.")
        case "rules": .copy("No rules yet. Rules decide, top to bottom, where each connection goes.")
        case "sub-rules": .copy("No sub-rules yet. A sub-rule is a named list of rules a rule can hand traffic to.")
        default: .copy("Nothing added yet.")
        }
    }
}

#if os(iOS)
import SwiftUI

extension ConfigurationEditorSession {

     
     
     
     
     
    func addLibraryNodes(_ picked: [ConfigurationLibraryPicks.Node], from sources: [ConfigurationLibraryPicks.Source]) async {
        guard !picked.isEmpty, let document = page?.document else { return }
        let plan: ConfigurationLibraryPicks.NodePlan
        do {
            plan = try ConfigurationLibraryPicks.nodeSteps(picked, available: sources.flatMap(\.nodes), in: document)
        } catch let unreachable as ConfigurationLibraryPicks.UnreachableDialer {
            refusal = Refusal(sentence: ClashCopy.string(for: unreachable.sentence, locale: AppPreferences.language().locale),
                              coreWords: nil, editTheSourceInstead: false)
            return
        } catch {
            return
        }
        guard await editOriginal(steps: plan.steps) else { return }
        notice = ConfigurationLibraryPicks.notice(for: plan)
    }

     
     
     
     
    func refusesSwitchingOff(_ source: ConfigurationLibraryPicks.Source) -> Bool {
        let shown = shownDocument ?? .object([])
        guard let there = ConfigurationLibraryPicks.addedSetName(source, in: shown) else { return false }
        let places = OriginalListEdits.uses(ofProvider: there, in: shown)
        guard !places.isEmpty else { return false }
        refuseDeleting(there, usedBy: places)
        return true
    }

     
     
     
     
     
     
     
     
    @discardableResult
    func setLibraryLink(_ source: ConfigurationLibraryPicks.Source, on: Bool) async -> Bool {
         
         
         
         
        if !on, refusesSwitchingOff(source) { return false }
        let there = ConfigurationLibraryPicks.addedSetName(source, in: shownDocument ?? .object([]))
        let saved = await queueOriginal { document in
            let written = ConfigurationLibraryPicks.addedSetName(source, in: document)
            if on {
                guard written == nil else { return .write([]) }
                let taken = ConfigurationLibraryPicks.takenNodeSetNames(in: document)
                guard let made = ConfigurationLibraryPicks.provider(for: source, taken: taken) else { return .cannot }
                return .write([OriginalListEdits.adding(made.name, made.value, toMappingAt: "proxy-providers",
                                                        exists: document.topLevelValue("proxy-providers") != nil)])
            }
            guard let written else { return .write([]) }
            let places = OriginalListEdits.uses(ofProvider: written, in: document)
            if !places.isEmpty { return .refuseDeleting(written, usedBy: places) }
            return .write(OriginalListEdits.deleting([written], fromMappingAt: "proxy-providers"))
        }
        if saved, on, there == nil,
           let added = ConfigurationLibraryPicks.addedSetName(source, in: page?.document ?? .object([])), added != source.label {
            notice = .format("Added as “%@”: this configuration already uses the name “%@”.", [added, source.label])
        }
        return saved
    }
}

 
struct ConfigurationEmptyListRows<Actions: View>: View {
    let key: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        Text(clash: ConfigurationEmptyList.sentence(for: key))
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("configuration-editor.list.empty")
        actions()
    }
}

 
 
 
struct ConfigurationReorderButton: View {
    @Binding var editMode: EditMode
    let identifier: String

    var body: some View {
        Button {
            withAnimation { editMode = editMode.isEditing ? .inactive : .active }
        } label: {
            Text(clash: .copy(editMode.isEditing ? "Done" : "Reorder List"))
        }
        .accessibilityIdentifier(identifier)
    }
}

 
 
struct ConfigurationAmbientReorderButton: View {
    @Environment(\.editMode) private var editMode
    let identifier: String

    var body: some View {
        Button {
            guard let editMode else { return }
            withAnimation { editMode.wrappedValue = editMode.wrappedValue.isEditing ? .inactive : .active }
        } label: {
            Text(clash: .copy(editMode?.wrappedValue.isEditing == true ? "Done" : "Reorder List"))
        }
        .accessibilityIdentifier(identifier)
    }
}

 
 
struct ConfigurationLibraryNodePicker: View {
    let store: ConfigurationLibraryStore?
     
    let profileID: String
     
     
    let document: OrderedJSON
     
     
    let add: ([ConfigurationLibraryPicks.Node], [ConfigurationLibraryPicks.Source]) -> Void
    @State private var sources: [ConfigurationLibraryPicks.Source]?
    @State private var added: Set<String> = []
     
     
    @State private var inNodeSets: Set<String> = []
    @State private var chosen: Set<String> = []
    @State private var query = ""
    @State private var failure: String?
    @StateObject private var dismiss = ClashDismissHandle()
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

    private func shown(_ source: ConfigurationLibraryPicks.Source, types: [String: String]) -> [ConfigurationLibraryPicks.Node] {
        let words = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !words.isEmpty else { return source.offered }
        return source.offered.filter {
            $0.name.lowercased().contains(words) || ConfigurationTypeWords.word($0.type, in: types).lowercased().contains(words)
        }
    }

    var body: some View {
        let types = ConfigurationTypeWords.names(.proxies, copy: fieldCopy, locale: locale)
        ClashFeatureNavigationContainer {
            List {
                if let sources {
                    let withNodes = sources.filter { !$0.offered.isEmpty }
                    if withNodes.isEmpty {
                        Text(clash: .copy("The node library has no nodes yet.")).foregroundStyle(.secondary)
                    }
                    ForEach(withNodes) { source in
                        let nodes = shown(source, types: types)
                        if !nodes.isEmpty {
                            let isLink: Bool = { if case .link? = source.providerKind { return true }; return false }()
                            Section {
                                ForEach(nodes) { node in
                                    row(node, isChain: source.record.nodeChain != nil,
                                        state: inNodeSets.contains(source.id) ? .inNodeSet : added.contains(node.id) ? .added : .offered,
                                        types: types)
                                }
                            } header: {
                                Text(clash: ClashConfigurationSourceCopy.name(source.record))
                            } footer: {
                                 
                                if isLink, !inNodeSets.contains(source.id) {
                                    Text(clash: .copy("Nodes copied from a link don’t update with it. To keep them updated, add the whole link in Proxy Providers."))
                                }
                            }
                        }
                    }
                } else if let failure {
                    Text(verbatim: failure).foregroundStyle(.secondary)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .searchable(text: $query)
            .navigationTitle(Text(clash: .copy("Choose from the Node Library")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(clash: .copy("Cancel")) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        add((sources ?? []).flatMap(\.offered).filter { chosen.contains($0.id) }, sources ?? [])
                        dismiss()
                    } label: {
                        Text(clash: chosen.isEmpty ? .copy("Add") : .format("Add %@", [String(chosen.count)]))
                    }
                    .disabled(chosen.isEmpty)
                    .accessibilityIdentifier("configuration-editor.library-nodes.add")
                }
            }
            .task { await load() }
        }
        .clashCapturesDismiss(dismiss)
    }

     
     
    enum RowState { case offered, added, inNodeSet }

    private func row(_ node: ConfigurationLibraryPicks.Node, isChain: Bool, state: RowState, types: [String: String]) -> some View {
        let isAdded = state != .offered
        return Toggle(isOn: Binding(get: { isAdded || chosen.contains(node.id) },
                             set: { on in if on { chosen.insert(node.id) } else { chosen.remove(node.id) } })) {
             
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: node.name).lineLimit(1)
                Text(clash: state == .inNodeSet ? .copy("Already in Proxy Providers") : state == .added ? .copy("Added")
                     : isChain ? .copy("Proxy Chain") : .verbatim(ConfigurationTypeWords.word(node.type, in: types)))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .disabled(isAdded)
        .accessibilityIdentifier("configuration-editor.library-nodes.node")
    }

    private func load() async {
        guard sources == nil else { return }
        guard let store else {
            failure = ClashCopy.string("The node library can't be read.", locale: locale)
            return
        }
        do {
            let read = try await Task.detached(priority: .userInitiated) { [profileID] in try ConfigurationLibraryPicks.sources(in: store, excludingThoseOf: profileID) }.value
            added = ConfigurationLibraryPicks.addedNodeIDs(read, in: document)
            inNodeSets = Set(read.filter { source in
                if case .link? = source.providerKind { return ConfigurationLibraryPicks.isAdded(source, in: document) }
                return false
            }.map(\.id))
            sources = read
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

 

 
struct ConfigurationNewProxyProviderSheet: View {
    @ObservedObject var session: ConfigurationEditorSession

    var body: some View {
        ConfigurationNewProxyProviderForm(types: ConfigurationOriginalProxyProviderView.types(session.catalog),
                                          taken: ConfigurationLibraryPicks.takenNodeSetNames(in: session.page?.document ?? .object([])),
                                          catalog: session.catalog) { name, provider in
            let step = OriginalListEdits.adding(name, provider, toMappingAt: "proxy-providers",
                                                exists: session.value(at: ["proxy-providers"]) != nil)
            Task { await session.editOriginal(steps: [step]) }
        }
    }
}

 
 
struct ConfigurationNewListItemButton: View {
    @ObservedObject var session: ConfigurationEditorSession
    let location: ConfigurationListLocation
    let title: ClashDisplayText
    let identifier: String
    @State private var adding = false

    var body: some View {
        Button { adding = true } label: {
            Label { Text(clash: title) } icon: { Image(systemName: ClashSymbol.plus.name) }
        }
        .accessibilityIdentifier(identifier)
        .clashSheet(isPresented: $adding) {
            ConfigurationNewListItemForm(session: session, location: location) { item in
                session.edit([location.edit(writing: location.items(in: session.settingsDocument) + [item],
                                            in: session.settingsDocument)])
            }
            .clashModalPresentation(.form)
        }
    }
}
#endif
