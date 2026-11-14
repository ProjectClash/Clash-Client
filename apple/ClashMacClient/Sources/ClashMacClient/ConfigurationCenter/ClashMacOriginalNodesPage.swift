import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
public struct ClashMacOriginalNode: Identifiable, Hashable, Sendable {
     
    public let index: Int
    public let name: String
     
    public let type: String
    public var id: Int { index }

    public init(index: Int, name: String, type: String) {
        self.index = index; self.name = name; self.type = type
    }
}

 
public struct ClashMacLibraryNode: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
     
    public let type: String
     
     
     
    public let isAdded: Bool

    public init(id: String, name: String, type: String, isAdded: Bool = false) {
        self.id = id; self.name = name; self.type = type; self.isAdded = isAdded
    }
}

 
 
 
public struct ClashMacLibrarySource: Identifiable, Hashable, Sendable {
     
    public enum SetKind: Hashable, Sendable { case link, nodes }
    public let id: String
    public let label: String
    public let nodes: [ClashMacLibraryNode]
     
    public let setKind: SetKind?
     
    public let isChain: Bool
     
     
    public let addedSetName: String?
     
    public var isAdded: Bool { addedSetName != nil }

    public init(id: String, label: String, nodes: [ClashMacLibraryNode], setKind: SetKind?, isChain: Bool = false,
                addedSetName: String? = nil) {
        self.id = id; self.label = label; self.nodes = nodes; self.setKind = setKind; self.isChain = isChain
        self.addedSetName = addedSetName
    }
}

 
 
 
public enum ClashMacOriginalNodes {
     
     
    public static func nodes(in document: OrderedJSON) -> [ClashMacOriginalNode]? {
        guard case .array(let items)? = document.topLevelValue("proxies") else { return nil }
        return items.enumerated().map { offset, item in
            ClashMacOriginalNode(index: offset, name: title(item, index: offset), type: type(of: item))
        }
    }

     
     
    static func title(_ value: OrderedJSON, index: Int) -> String {
        if case .string(let name)? = value.topLevelValue("name") { return name }
        return "#\(index + 1)"
    }

    static func type(of item: OrderedJSON) -> String {
        switch item.topLevelValue("type") {
        case .string(let written)?: return written
        case .scalar(let token)?: return token == "null" ? "" : token
        default: return ""
        }
    }

     
     
     
    public static func value(of node: ClashMacOriginalNode, in document: OrderedJSON) -> (index: Int, value: OrderedJSON)? {
        guard case .array(let items)? = document.topLevelValue("proxies") else { return nil }
        if items.indices.contains(node.index), title(items[node.index], index: node.index) == node.name {
            return (node.index, items[node.index])
        }
        for (offset, item) in items.enumerated() where title(item, index: offset) == node.name {
            return (offset, item)
        }
        return nil
    }
}

 
 
public struct ClashMacOriginalNodesActions {
     
    public var load: @MainActor () async throws -> [ClashMacOriginalNode]?
     
    public var nodeForm: @MainActor (ClashMacOriginalNode?, @escaping @MainActor () -> Void) -> AnyView
     
    public var librarySources: @MainActor () async throws -> [ClashMacLibrarySource]
     
     
    public var addFromLibrary: @MainActor ([ClashMacLibraryNode]) async throws -> ClashDisplayText?
     
    public var delete: @MainActor (ClashMacOriginalNode) async throws -> Void
     
     
    public var updateNote: ClashDisplayText?

    public init(
        load: @escaping @MainActor () async throws -> [ClashMacOriginalNode]?,
        nodeForm: @escaping @MainActor (ClashMacOriginalNode?, @escaping @MainActor () -> Void) -> AnyView,
        librarySources: @escaping @MainActor () async throws -> [ClashMacLibrarySource],
        addFromLibrary: @escaping @MainActor ([ClashMacLibraryNode]) async throws -> ClashDisplayText?,
        delete: @escaping @MainActor (ClashMacOriginalNode) async throws -> Void,
        updateNote: ClashDisplayText? = nil
    ) {
        self.load = load; self.nodeForm = nodeForm; self.librarySources = librarySources
        self.addFromLibrary = addFromLibrary; self.delete = delete; self.updateNote = updateNote
    }

    public static var unavailable: Self {
        Self(load: { nil }, nodeForm: { _, _ in AnyView(EmptyView()) }, librarySources: { [] },
             addFromLibrary: { _ in nil }, delete: { _ in })
    }
}

 
 
 
 
 
 
 
public struct ClashMacOriginalNodesPage: View {
    private let actions: ClashMacOriginalNodesActions
    @State private var nodes: [ClashMacOriginalNode]?
    @State private var failure: String?
     
     
    @Environment(\.clashFeedback) private var feedback
    @State private var filter = ""
    @State private var showsAll = false
    @State private var busy = false
     
    @State private var selection = Set<ClashMacOriginalNode.ID>()
    @State private var form: FormRequest?
    @State private var picking = false
    @State private var deleting: ClashMacOriginalNode?
    @Environment(\.configurationFieldCopy) private var copy
    @Environment(\.locale) private var locale

     
    struct FormRequest: Identifiable {
        let node: ClashMacOriginalNode?
        var id: String { node.map { "node-\($0.index)-\($0.name)" } ?? "new" }
    }

    public init(actions: ClashMacOriginalNodesActions) {
        self.actions = actions
    }

     
     
    static func shown(_ nodes: [ClashMacOriginalNode], filter: String, typeNames: [String: String]) -> [ClashMacOriginalNode] {
        let needle = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nodes }
        return nodes.filter {
            $0.name.lowercased().contains(needle) || $0.type.lowercased().contains(needle)
                || (typeNames[$0.type.lowercased()]?.lowercased().contains(needle) ?? false)
        }
    }

    public var body: some View {
        let typeNames = ClashMacValueWords.valueNames(path: "proxies[*].type", copy: copy, locale: locale)
        List(selection: $selection) {
            if let failure {
                Section {
                    Text(verbatim: failure).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("configuration-center.original-nodes.error")
                }
            }
            Section {
                if let nodes {
                    if nodes.isEmpty {
                         
                         
                        Text(clash: .copy("No nodes yet. Add one, or copy nodes from the node library."))
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("configuration-center.original-nodes.empty")
                        newNodeButton.accessibilityIdentifier("configuration-center.original-nodes.new-row")
                        libraryButton.accessibilityIdentifier("configuration-center.original-nodes.library-row")
                    } else {
                        let shown = Self.shown(nodes, filter: filter, typeNames: typeNames)
                        ForEach(showsAll ? shown : Array(shown.prefix(ClashMacSourceContentPage.firstPage))) { node in
                             
                            Button { form = FormRequest(node: node) } label: {
                                HStack(spacing: ClashTheme.Spacing.compact) {
                                    Text(verbatim: node.name).lineLimit(1)
                                    Spacer(minLength: ClashTheme.Spacing.compact)
                                    Text(verbatim: typeNames[node.type.lowercased()] ?? node.type)
                                        .foregroundStyle(.secondary).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(busy)
                            .accessibilityIdentifier("configuration-center.original-nodes.node.\(node.index)")
                        }
                        if !showsAll, shown.count > ClashMacSourceContentPage.firstPage {
                            Button { showsAll = true } label: { Text(clash: .format("Show all %@ nodes", [String(shown.count)])) }
                                .accessibilityIdentifier("configuration-center.original-nodes.show-all")
                        }
                         
                         
                         
                         
                         
                        newNodeButton.disabled(busy).accessibilityIdentifier("configuration-center.original-nodes.new-row")
                        libraryButton.disabled(busy).accessibilityIdentifier("configuration-center.original-nodes.library-row")
                    }
                } else if failure == nil {
                    ProgressView().controlSize(.small)
                }
            } footer: {
                if let note = actions.updateNote {
                    Text(clash: note).accessibilityIdentifier("configuration-center.original-nodes.update-note")
                }
            }
        }
        .listStyle(.inset)
         
        .contextMenu(forSelectionType: ClashMacOriginalNode.ID.self) { ids in
            if ids.count == 1, let id = ids.first, let node = nodes?.first(where: { $0.id == id }) {
                Button { form = FormRequest(node: node) } label: { Text(clash: .copy("Edit")) }
                Divider()
                Button(role: .destructive) { deleting = node } label: { Text(clash: .copy("Delete Node")) }
                    .accessibilityIdentifier("configuration-center.original-nodes.delete")
            }
        }
        .clashProductModalSearchable(text: $filter, prompt: Text(clash: .copy("Search Nodes")))
        .navigationTitle(Text(clash: ClashMacConfigurationOutlineCard.title(.proxies)))
        .accessibilityIdentifier("configuration-center.original-nodes")
        .task { await load() }
        .clashProductModal(item: $form, role: .form) { request in
            actions.nodeForm(request.node) {
                form = nil
                Task { await load() }
            }
        }
        .sheet(isPresented: $picking) {
            ClashMacLibraryNodePicker(load: actions.librarySources, add: { picked in
                picking = false
                Task { await add(picked) }
            }, close: { picking = false })
        }
         
         
        .alert(Text(clash: .copy("Delete Node")), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
               presenting: deleting) { node in
            Button(role: .destructive) {
                deleting = nil
                Task { await delete(node) }
            } label: {
                Text(clash: .copy("Delete Node"))
            }
            .accessibilityIdentifier("configuration-center.original-nodes.delete.confirm")
            Button(role: .cancel) {} label: { Text(clash: .copy("Cancel")) }
        } message: { node in
            Text(verbatim: node.name)
        }
    }

    private func say(_ sentence: ClashDisplayText?) {
        guard let sentence else { return }
        feedback?.say(.success(title: sentence, accessibilityIdentifier: "feedback.original-nodes.added"), operation: "original-nodes.add")
    }

     
    private var newNodeButton: some View {
        Button { form = FormRequest(node: nil) } label: {
            Label { Text(clash: .copy("New Node…")) } icon: { Image(systemName: "plus") }
        }
    }

     
    private var libraryButton: some View {
        Button { picking = true } label: {
            Label { Text(clash: .copy("Choose from the Node Library…")) } icon: { Image(systemName: "rectangle.stack") }
        }
    }

    private func load() async {
        do {
            nodes = try await actions.load() ?? []
            failure = nil
        } catch is CancellationError {
        } catch {
            failure = ClashErrorCopy.message(error, locale: locale)
        }
    }

     
     
     
    private func perform(_ work: @escaping @MainActor () async throws -> Void) async {
        busy = true
        defer { busy = false }
        var refusal: String?
        do {
            try await work()
        } catch is CancellationError {
        } catch {
            refusal = ClashErrorCopy.message(error, locale: locale)
        }
        await load()
        if let refusal { failure = refusal }
    }

    private func add(_ picked: [ClashMacLibraryNode]) async {
        guard !picked.isEmpty else { return }
        await perform { say(try await actions.addFromLibrary(picked)) }
    }

     
     
     
     
    private func delete(_ node: ClashMacOriginalNode) async {
        await perform {
            do {
                try await actions.delete(node)
                feedback?.say(ClashMacFeedbackSentences.deleted(node.name, undoable: false, id: Self.deleteOperation),
                              operation: Self.deleteOperation)
            } catch is CancellationError {
            } catch {
                feedback?.say(ClashMacFeedbackSentences.couldNotDelete(node.name, reason: ClashErrorCopy.message(error, locale: locale),
                                                                      id: Self.deleteOperation),
                              operation: Self.deleteOperation)
            }
        }
    }

    static let deleteOperation = "original-nodes.delete"
}

 
 
 
 
public struct ClashMacLibraryNodePicker: View {
    let load: @MainActor () async throws -> [ClashMacLibrarySource]
    let add: @MainActor ([ClashMacLibraryNode]) -> Void
    let close: @MainActor () -> Void
    @State private var sources: [ClashMacLibrarySource]?
    @State private var failure: String?
    @State private var chosen = Set<String>()
    @State private var query = ""
    @Environment(\.configurationFieldCopy) private var copy
    @Environment(\.locale) private var locale

    public init(load: @escaping @MainActor () async throws -> [ClashMacLibrarySource],
                add: @escaping @MainActor ([ClashMacLibraryNode]) -> Void,
                close: @escaping @MainActor () -> Void) {
        self.load = load; self.add = add; self.close = close
    }

     
     
    static func shown(_ source: ClashMacLibrarySource, query: String, typeNames: [String: String]) -> [ClashMacLibraryNode] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return source.nodes }
        return source.nodes.filter {
            $0.name.lowercased().contains(needle) || $0.type.lowercased().contains(needle)
                || (typeNames[$0.type.lowercased()]?.lowercased().contains(needle) ?? false)
        }
    }

     
     
    static func isInNodeSets(_ source: ClashMacLibrarySource) -> Bool {
        source.setKind == .link && source.isAdded
    }

     
     
     
    static func picked(_ sources: [ClashMacLibrarySource], chosen: Set<String>) -> [ClashMacLibraryNode] {
        sources.filter { !isInNodeSets($0) }.flatMap(\.nodes).filter { chosen.contains($0.id) && !$0.isAdded }
    }

    public var body: some View {
        let typeNames = ClashMacValueWords.valueNames(path: "proxies[*].type", copy: copy, locale: locale)
        ClashMacSheetFrame(title: .copy("Choose from the Node Library"), width: 560, height: 560) {
            VStack(spacing: 0) {
                TextField(text: $query, prompt: Text(clash: .copy("Search Nodes"))) { Text(clash: .copy("Search Nodes")) }
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .accessibilityIdentifier("configuration-center.library-nodes.search")
                Divider()
                List {
                    if let sources {
                        let withNodes = sources.filter { !$0.nodes.isEmpty }
                        if withNodes.isEmpty {
                            Text(clash: .copy("The node library has no nodes yet.")).foregroundStyle(.secondary)
                                .accessibilityIdentifier("configuration-center.library-nodes.empty")
                        }
                        ForEach(withNodes) { source in
                            let nodes = Self.shown(source, query: query, typeNames: typeNames)
                            let inNodeSets = Self.isInNodeSets(source)
                            if !nodes.isEmpty {
                                Section {
                                    ForEach(nodes) { node in
                                        let taken = inNodeSets || node.isAdded
                                        Toggle(isOn: Binding(get: { taken || chosen.contains(node.id) }, set: { on in
                                            if on { chosen.insert(node.id) } else { chosen.remove(node.id) }
                                        })) {
                                            HStack(spacing: ClashTheme.Spacing.compact) {
                                                Text(verbatim: node.name).lineLimit(1)
                                                Spacer(minLength: ClashTheme.Spacing.compact)
                                                 
                                                 
                                                Text(clash: inNodeSets ? .copy("Already in Proxy Providers")
                                                     : node.isAdded ? .copy("Added") : source.isChain ? .copy("Proxy Chain")
                                                     : .verbatim(typeNames[node.type.lowercased()] ?? node.type))
                                                    .foregroundStyle(.secondary).lineLimit(1)
                                            }
                                        }
                                        .toggleStyle(.checkbox)
                                        .disabled(taken)
                                        .accessibilityIdentifier("configuration-center.library-nodes.node")
                                    }
                                } header: {
                                    Text(verbatim: source.label)
                                } footer: {
                                     
                                    if source.setKind == .link, !inNodeSets {
                                        Text(clash: .copy("Nodes copied from a link don’t update with it. To keep them updated, add the whole link in Proxy Providers."))
                                    }
                                }
                            }
                        }
                    } else if let failure {
                        Text(verbatim: failure).foregroundStyle(.secondary)
                            .accessibilityIdentifier("configuration-center.library-nodes.error")
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .listStyle(.inset)
            }
        } trailing: {
            ClashMacSheetButtons(
                closeIdentifier: "configuration-center.library-nodes.cancel",
                primaryTitle: chosen.isEmpty ? .copy("Add") : .format("Add %@", [String(chosen.count)]),
                primaryIdentifier: "configuration-center.library-nodes.add",
                primaryDisabled: chosen.isEmpty,
                onClose: close,
                onPrimary: { add(Self.picked(sources ?? [], chosen: chosen)) }
            )
        }
        .task {
            guard sources == nil else { return }
            do { sources = try await load() } catch is CancellationError {
            } catch { failure = ClashErrorCopy.message(error, locale: locale) }
        }
    }
}
