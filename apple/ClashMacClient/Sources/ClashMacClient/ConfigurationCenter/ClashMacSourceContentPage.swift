import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
public struct ClashMacSourceNode: Identifiable, Sendable, Equatable {
    public let index: Int
    public let name: String
    public let type: String
    public let server: String?
    public let json: String
    public var id: Int { index }

    public init(index: Int, name: String, type: String, server: String?, json: String) {
        self.index = index; self.name = name; self.type = type; self.server = server; self.json = json
    }
}

 
 
public struct ClashMacSourceContentActions {
    public var loadNodes: @MainActor () async throws -> [ClashMacSourceNode]
    public var openNode: @MainActor (ClashMacSourceNode) -> Void
     
    public var deleteNode: (@MainActor (ClashMacSourceNode) -> Void)?
    public var addNode: (@MainActor () -> Void)?
    public var update: @MainActor () -> Void
    public var delete: @MainActor () -> Void
    public var editSource: (@MainActor () -> Void)?
    public var editChain: (@MainActor () -> Void)?
     
    public var details: ClashMacSourcePaneActions

    public init(
        loadNodes: @escaping @MainActor () async throws -> [ClashMacSourceNode],
        openNode: @escaping @MainActor (ClashMacSourceNode) -> Void,
        deleteNode: (@MainActor (ClashMacSourceNode) -> Void)? = nil,
        addNode: (@MainActor () -> Void)? = nil,
        update: @escaping @MainActor () -> Void,
        delete: @escaping @MainActor () -> Void,
        editSource: (@MainActor () -> Void)? = nil,
        editChain: (@MainActor () -> Void)? = nil,
        details: ClashMacSourcePaneActions
    ) {
        self.loadNodes = loadNodes; self.openNode = openNode; self.deleteNode = deleteNode; self.addNode = addNode
        self.update = update; self.delete = delete; self.editSource = editSource; self.editChain = editChain
        self.details = details
    }

    public static var unavailable: Self {
        Self(loadNodes: { [] }, openNode: { _ in }, update: {}, delete: {}, details: .unavailable)
    }
}

 
 
 
 
 
 
public struct ClashMacSourceContentPage: View {
    private let source: ConfigurationSourceRecord
    private let usedBy: [ClashProfileSnapshot]
    private let isUpdating: Bool
    private let collections: [ConfigurationCollectionEntry]
    private let collectionPage: (ConfigurationCollectionEntry) -> AnyView
    private let actions: ClashMacSourceContentActions
     
     
    public var updateError: String?
     
     
     
    public var updateIssue: String?
    @State private var nodes: [ClashMacSourceNode]?
    @State private var loadError: String?
    @State private var filter = ""
    @State private var showsDetails = false
     
    @State private var nodeSelection = Set<ClashMacSourceNode.ID>()
     
     
     
     
    @State private var showsAll = false
    static let firstPage = 50
    @Environment(\.locale) private var locale
    @Environment(\.configurationFieldCopy) private var copy

    public init(
        source: ConfigurationSourceRecord, usedBy: [ClashProfileSnapshot], isUpdating: Bool,
        collections: [ConfigurationCollectionEntry] = [],
        collectionPage: @escaping (ConfigurationCollectionEntry) -> AnyView = { _ in AnyView(EmptyView()) },
        actions: ClashMacSourceContentActions
    ) {
        self.source = source; self.usedBy = usedBy; self.isUpdating = isUpdating
        self.collections = collections; self.collectionPage = collectionPage; self.actions = actions
    }

    private var isRetained: Bool { source.isRetainedSnapshot == true }
    private var isSubscription: Bool {
        if isRetained { return false }
        if case .subscription = source.origin { return true }
        return false
    }
    private var isChain: Bool { source.nodeChain != nil }
     
    private var isBundled: Bool {
        if case .bundled = source.origin { return true }
        return false
    }

     
     
    static func detail(of node: ClashMacSourceNode, typeNames: [String: String]) -> String {
        [typeNames[node.type.lowercased()] ?? node.type, node.server].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var shownNodes: [ClashMacSourceNode] {
        guard let nodes else { return [] }
        let needle = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nodes }
        return nodes.filter {
            $0.name.lowercased().contains(needle) || $0.type.lowercased().contains(needle) || ($0.server?.lowercased().contains(needle) ?? false)
        }
    }

    public var body: some View {
         
         
         
         
        List(selection: $nodeSelection) {
            header
            if let chain = source.nodeChain {
                 
                 
                Section {
                    Text(clash: .copy("This Device"))
                    chainHop(.copy("Entry Node"), node: chain.entry.nodeName)
                    chainHop(.copy("Exit Node"), node: chain.exit.nodeName)
                    Text(clash: .copy("Destination Website"))
                } header: {
                    Text(clash: .copy("Connection Order"))
                }
            } else {
                nodesSection
                if !collections.isEmpty { collectionsSection }
            }
            readers
        }
        .listStyle(.inset)
         
        .contextMenu(forSelectionType: ClashMacSourceNode.ID.self) { ids in
            if actions.deleteNode != nil, ids.count == 1, let id = ids.first, let node = nodes?.first(where: { $0.id == id }) {
                 
                Button(role: .destructive) { actions.deleteNode?(node) } label: { Text(clash: .copy("Delete Node")) }
            }
        }
         
         
        .clashListRetainsRowSelection()
        .accessibilityIdentifier("configuration-center.source")
         
         
         
        .clashProductModalSearchable(text: $filter, prompt: Text(clash: .copy("Search Nodes")))
        .task(id: source.version) { await load() }
        .sheet(isPresented: $showsDetails) {
            ClashMacSourceDetailsSheet(source: source, usedBy: usedBy, actions: actions.details, close: { showsDetails = false })
                .clashModalPresentation(.fitted)
        }
    }

    private func chainHop(_ title: ClashDisplayText, node: String) -> some View {
        LabeledContent {
            Text(verbatim: node).lineLimit(1).truncationMode(.middle)
        } label: {
            Label { Text(clash: title) } icon: { ClashSymbolImage(symbol: .arrowDown) }
        }
    }

     
     
     
    private var header: some View {
        Section {
            LabeledContent {
                HStack(spacing: ClashTheme.Spacing.compact) {
                    if isUpdating { ProgressView().controlSize(.small) }
                    if isSubscription {
                        Button { actions.update() } label: { Text(clash: .copy("Update Source")) }
                            .disabled(isUpdating)
                            .accessibilityIdentifier("configuration-center.source.update")
                    }
                    if let editChain = actions.editChain {
                        Button { editChain() } label: { Text(clash: .copy("Edit")) }
                            .accessibilityIdentifier("configuration-center.source.edit-chain")
                    }
                    Menu {
                        Button { showsDetails = true } label: { Text(clash: .copy("Source Details")) }
                        if let editSource = actions.editSource, !isRetained, !isChain {
                            Button { editSource() } label: { Text(clash: .copy("Edit Nodes Source")) }
                        }
                        if !isRetained && !isBundled {
                            Divider()
                             
                             
                             
                             
                             
                            Button(role: .destructive) { actions.delete() } label: {
                                Text(clash: isChain ? .copy("Delete Proxy Chain") : .copy("Delete"))
                            }
                            .accessibilityIdentifier("configuration-center.source.delete")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .fixedSize()
                    .accessibilityIdentifier("configuration-center.source.more")
                }
            } label: {
                 
                Text(clash: isChain ? .copy("Proxy Chain") : isRetained ? .copy("Saved Copy") : .count(source.nodeCount, one: "%@ node", other: "%@ nodes"))
                Text(verbatim: Self.dateFormatters.formatter(for: locale).string(from: source.updatedAt))
            }
            if isRetained {
                 
                Text(clash: .copy("This saved copy no longer receives source updates."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("configuration-center.source.retained")
            }
            if let updateError {
                Text(verbatim: updateError)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("configuration-center.source.update-error")
            }
            if let updateIssue {
                Text(verbatim: updateIssue)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("configuration-center.source.update-issue")
            }
        }
    }

    @ViewBuilder
    private var nodesSection: some View {
        let shown = shownNodes
        let typeNames = ClashMacValueWords.valueNames(path: "proxies[*].type", copy: copy, locale: locale)
        Section {
            if let loadError {
                Text(verbatim: loadError).foregroundStyle(.red)
                    .accessibilityIdentifier("configuration-center.source.error")
            } else if nodes == nil {
                ProgressView().controlSize(.small)
            } else if shown.isEmpty {
                Text(clash: .copy("None")).foregroundStyle(.secondary)
            } else {
                 
                 
                 
                 
                 
                 
                ForEach(showsAll ? shown : Array(shown.prefix(Self.firstPage))) { node in
                    Button { actions.openNode(node) } label: {
                        VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                            Text(verbatim: node.name).lineLimit(1)
                            Text(verbatim: Self.detail(of: node, typeNames: typeNames))
                                .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("configuration-center.source.node.\(node.index)")
                }
                if !showsAll, shown.count > Self.firstPage {
                    Button { showsAll = true } label: { Text(clash: .format("Show all %@ nodes", [String(shown.count)])) }
                        .accessibilityIdentifier("configuration-center.source.show-all")
                }
            }
            if let addNode = actions.addNode {
                Button { addNode() } label: {
                    Label { Text(clash: .opens("Add Custom Node", locale: locale)) } icon: { Image(systemName: "plus") }
                }
                .accessibilityIdentifier("configuration-center.source.add-node")
            }
        } header: {
            Text(clash: .copy("Nodes"))
        }
    }

     
    private var collectionsSection: some View {
        Section {
            ForEach(collections) { entry in
                ClashRoutedViewLink {
                    collectionPage(entry)
                } label: {
                    LabeledContent {
                         
                        Text(clash: entry.memberCount.map { .format("%@ nodes", [String($0)]) }
                             ?? .verbatim(ClashMacValueWords.valueName(entry.collection.type, path: "proxy-providers.*.type", copy: copy, locale: locale)))
                    } label: {
                        Text(verbatim: entry.collection.name)
                    }
                }
                .accessibilityIdentifier("configuration-center.source.collection.\(entry.collection.name)")
            }
        } header: {
            Text(clash: .format("Node Sets (%@)", [String(collections.count)]))
        }
    }

    private var readers: some View {
        Section {
            if usedBy.isEmpty {
                Text(clash: .copy("None")).foregroundStyle(.secondary)
            } else {
                 
                ForEach(usedBy) { profile in
                    Text(verbatim: profile.label)
                        .accessibilityIdentifier("configuration-center.source.used-by.\(profile.id.rawValue)")
                }
            }
        } header: {
            Text(clash: .copy("Used by Profiles"))
        }
    }

    private func load() async {
        loadError = nil
        do { nodes = try await actions.loadNodes() } catch { loadError = ClashErrorCopy.message(error, locale: locale) }
    }

    private static let dateFormatters = ClashMacDateFormatterCache(dateStyle: .medium, timeStyle: .short)
}

 
 
 
 
public struct ClashMacSourceDetailsSheet: View {
    private static let intervals = [1, 3, 6, 12, 24, 48, 72, 168]

    private let source: ConfigurationSourceRecord
    private let usedBy: [ClashProfileSnapshot]
    private let actions: ClashMacSourcePaneActions
    private let close: () -> Void
     
     
     
     
    @State private var name: String?
    @State private var url: String
    @State private var interval: Int
    @State private var error: String?
    @Environment(\.locale) private var locale

    public init(source: ConfigurationSourceRecord, usedBy: [ClashProfileSnapshot], actions: ClashMacSourcePaneActions, close: @escaping () -> Void) {
        self.source = source; self.usedBy = usedBy; self.actions = actions; self.close = close
        let draft = ConfigurationSourceSettingsDraft(source: source)
        _url = State(initialValue: draft.url)
        _interval = State(initialValue: draft.intervalHours)
    }

    private var shownName: String { source.displayLabel(locale: locale) }
    private var nameField: Binding<String> { Binding(get: { name ?? shownName }, set: { name = $0 }) }
    private var typedName: String { (name ?? shownName).trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isRetained: Bool { source.isRetainedSnapshot == true }
    private var isSubscription: Bool {
        if isRetained { return false }
        if case .subscription = source.origin { return true }
        return false
    }
    private var dirty: Bool {
        let draft = ConfigurationSourceSettingsDraft(source: source)
        return typedName != shownName
            || (isSubscription && (url.trimmingCharacters(in: .whitespacesAndNewlines) != draft.url || interval != draft.intervalHours))
    }
    private var urlIsValid: Bool {
        guard isSubscription else { return true }
        let components = URLComponents(string: url.trimmingCharacters(in: .whitespacesAndNewlines))
        return components?.scheme != nil && !(components?.host?.isEmpty ?? true) && components?.url != nil
    }

    public var body: some View {
        ClashMacSheetFrame(title: .copy("Source Details"), subtitle: ClashConfigurationSourceCopy.name(source), width: 560, height: 520) {
            ClashMacSheetForm {
                Section {
                    TextField(text: nameField) { Text(clash: .copy("Name")) }
                        .disabled(isRetained)
                        .accessibilityIdentifier("configuration-center.source.name")
                    switch source.origin {
                    case .file(let fileName), .bundled(let fileName):
                        if fileName != source.label {
                            LabeledContent { Text(verbatim: fileName) } label: { Text(clash: .copy("Source")) }
                        }
                    case .customNodes:
                        LabeledContent { Text(clash: .copy("Custom Nodes")) } label: { Text(clash: .copy("Source")) }
                    default:
                        EmptyView()
                    }
                }
                if let usage = source.subscriptionUsage {
                    Section {
                        LabeledContent { Text(clash: ClashMacSubscriptionUsageCopy.traffic(usage)) } label: { Text(clash: .copy("Traffic")) }
                        if let expiry = ClashMacSubscriptionUsageCopy.expiry(usage, locale: locale) {
                            Text(clash: expiry).foregroundStyle(.secondary)
                        }
                    } header: {
                        Text(clash: .copy("Data Usage"))
                    }
                }
                if isSubscription {
                    Section {
                        TextField(text: $url) { Text(clash: .copy("Profile URL")) }
                            .accessibilityIdentifier("configuration-center.source.url")
                        Picker(selection: $interval) {
                            Text(clash: .copy("Manually")).tag(0)
                            ForEach(Self.intervals, id: \.self) { hours in
                                Text(clash: .format("Every %@ hours", [String(hours)])).tag(hours)
                            }
                            if interval != 0, !Self.intervals.contains(interval) {
                                Text(clash: .format("Every %@ hours", [String(interval)])).tag(interval)
                            }
                        } label: {
                            Text(clash: .copy("Update Interval"))
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("configuration-center.source.interval")
                    } header: {
                        Text(clash: .copy("Profile URL"))
                    }
                }
                if isRetained {
                    Section { Text(clash: .copy("This saved copy no longer receives source updates.")).foregroundStyle(.secondary) }
                }
                Section {
                    if usedBy.isEmpty {
                        Text(clash: .copy("None")).foregroundStyle(.secondary)
                    } else {
                        ForEach(usedBy) { profile in Text(verbatim: profile.label) }
                    }
                } header: {
                    Text(clash: .copy("Used by Profiles"))
                }
            }
        } leading: {
            if let error {
                Text(verbatim: error).foregroundStyle(.red).font(.subheadline).lineLimit(2)
                    .accessibilityIdentifier("configuration-center.source.error")
            }
        } trailing: {
            ClashMacSheetButtons(
                closeIdentifier: "configuration-center.source.close",
                primaryTitle: .copy("OK"),
                primaryIdentifier: "configuration-center.source.save",
                primaryDisabled: !dirty || !urlIsValid || typedName.isEmpty,
                onClose: close,
                onPrimary: commit
            )
        }
    }

    private func commit() {
        let typed = typedName
        var settings: ConfigurationSourceSettingsDraft?
        if isSubscription {
            var draft = ConfigurationSourceSettingsDraft(source: source)
            let nextURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
            if nextURL != draft.url || interval != draft.intervalHours {
                draft.url = nextURL; draft.intervalHours = interval
                settings = draft
            }
        }
         
         
         
        guard typed != shownName || settings != nil else { return close() }
         
         
        let trimmed = ClashConfigurationSourceCopy.nameToStore(typed, origin: source.origin, locale: locale)
        Task { @MainActor in
            if let refusal = await actions.save(trimmed, settings) { error = refusal } else { close() }
        }
    }
}
