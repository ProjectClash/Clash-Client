import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
public struct ClashMacNodeScopeChoices: Sendable {
    public var collections: [ConfigurationCollection]
    public var nodes: [ClashConfigurationSelectableNode]

    public init(collections: [ConfigurationCollection], nodes: [ClashConfigurationSelectableNode]) {
        self.collections = collections
        self.nodes = nodes
    }
}

 
 
 
 
struct ClashMacNodeScopePage: View {
    let source: ConfigurationSourceRecord
    let load: @MainActor () async throws -> ClashMacNodeScopeChoices
    let initial: ConfigurationNodeScope?
    let save: (ConfigurationNodeScope?) -> Void
    let back: () -> Void
     
     
     
    var closeTitle: ClashDisplayText = .copy("Back")
     
     
     
     
    var savesUnchanged = false
    @State private var choices: ClashMacNodeScopeChoices?
    @State private var selectedNodes: Set<String> = []
    @State private var selectedCollections: Set<String> = []
    @State private var initialNodes: Set<String> = []
    @State private var initialCollections: Set<String> = []
    @State private var filter = ""
    @State private var error: String?
     
    @State private var showsAll = false
    @Environment(\.locale) private var locale

     
    static func initialSelection(
        _ scope: ConfigurationNodeScope?, collections: [ConfigurationCollection], nodes: [ClashConfigurationSelectableNode]
    ) -> (nodes: Set<String>, collections: Set<String>) {
        let nodeNames = scope?.includesInlineNodes == false ? Set<String>() : Set(scope?.inlineNodeNames ?? nodes.map(\.name))
        let collectionNames = Set(scope?.providerKeys ?? collections.map(\.name))
        return (nodeNames, collectionNames)
    }

     
     
    static func selection(
        nodes selectedNodes: Set<String>, collections selectedCollections: Set<String>,
        allNodes: [ClashConfigurationSelectableNode], allCollections: [ConfigurationCollection]
    ) -> ConfigurationNodeScope? {
        let everyNode = selectedNodes == Set(allNodes.map(\.name))
        if everyNode && selectedCollections == Set(allCollections.map(\.name)) { return nil }
        return ConfigurationNodeScope(
            includesInlineNodes: !selectedNodes.isEmpty,
            providerKeys: selectedCollections.sorted(),
            inlineNodeNames: everyNode ? nil : selectedNodes.sorted()
        )
    }

    private var dirty: Bool { selectedNodes != initialNodes || selectedCollections != initialCollections }

    private var needle: String { filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    private var shownCollections: [ConfigurationCollection] {
        let all = choices?.collections ?? []
        return needle.isEmpty ? all : all.filter { $0.name.lowercased().contains(needle) }
    }
    private var matchingNodes: [ClashConfigurationSelectableNode] {
        let all = choices?.nodes ?? []
        return needle.isEmpty ? all : all.filter { $0.name.lowercased().contains(needle) || $0.type.lowercased().contains(needle) }
    }

     
     
     
     
     
    static let firstPage = 100

    var body: some View {
         
        ClashMacSheetFrame(title: ClashConfigurationSourceCopy.name(source), width: 600, height: 560) {
            VStack(spacing: 0) {
                 
                 
                TextField(text: $filter) { Text(clash: .copy("Search Nodes")) }
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("configuration-center.scope.filter")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                 
                 
                 
                 
                 
                List {
                    if let error {
                        Section {
                            Text(verbatim: error).foregroundStyle(.red)
                                .accessibilityIdentifier("configuration-center.scope.error")
                        }
                    }
                    if choices == nil, error == nil {
                        Section { ProgressView().controlSize(.small) }
                    }
                    if !shownCollections.isEmpty {
                        Section {
                            ForEach(shownCollections) { collection in
                                Toggle(isOn: membership(collection.name, in: $selectedCollections)) {
                                    choiceLabel(collection.name, detail: collection.type)
                                }
                                .toggleStyle(.checkbox)
                                .accessibilityIdentifier("configuration-center.scope.collection.\(collection.name)")
                            }
                        } header: {
                            Text(clash: .copy("Node Collections"))
                        }
                    }
                    if let choices, !choices.nodes.isEmpty {
                        let matching = matchingNodes
                        Section {
                            ForEach(showsAll ? matching : Array(matching.prefix(Self.firstPage))) { node in
                                Toggle(isOn: membership(node.name, in: $selectedNodes)) {
                                    choiceLabel(node.name, detail: node.type)
                                }
                                .toggleStyle(.checkbox)
                                .accessibilityIdentifier("configuration-center.scope.node.\(node.name)")
                            }
                            if !showsAll, matching.count > Self.firstPage {
                                Button { showsAll = true } label: {
                                    Text(clash: .format("Show all %@ nodes", [String(matching.count)]))
                                }
                                .accessibilityIdentifier("configuration-center.scope.show-all")
                            }
                        } header: {
                            Text(clash: .copy("Nodes"))
                        }
                    }
                }
                .listStyle(.inset)
            }
            .accessibilityIdentifier("configuration-center.scope")
        } trailing: {
            ClashMacSheetButtons(
                closeTitle: closeTitle,
                closeIdentifier: "configuration-center.scope.cancel",
                primaryTitle: .copy("Done"),
                primaryIdentifier: "configuration-center.scope.done",
                 
                primaryDisabled: choices == nil || (!dirty && !savesUnchanged),
                onClose: back,
                onPrimary: {
                    guard let choices else { return }
                    save(Self.selection(nodes: selectedNodes, collections: selectedCollections, allNodes: choices.nodes, allCollections: choices.collections))
                }
            )
        }
        .task {
            do {
                let loaded = try await load()
                let seed = Self.initialSelection(initial, collections: loaded.collections, nodes: loaded.nodes)
                selectedNodes = seed.nodes; initialNodes = seed.nodes
                selectedCollections = seed.collections; initialCollections = seed.collections
                choices = loaded
            } catch {
                self.error = ClashErrorCopy.message(error, locale: locale)
            }
        }
    }

     
    private func choiceLabel(_ name: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
            Text(verbatim: name).lineLimit(1)
            Text(verbatim: detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
        }
    }

     
    private func membership(_ name: String, in chosen: Binding<Set<String>>) -> Binding<Bool> {
        Binding(
            get: { chosen.wrappedValue.contains(name) },
            set: { on in if on { chosen.wrappedValue.insert(name) } else { chosen.wrappedValue.remove(name) } }
        )
    }
}
