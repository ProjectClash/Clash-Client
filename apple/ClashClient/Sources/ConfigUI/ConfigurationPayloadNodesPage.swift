#if os(iOS)
import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
 
 
struct ConfigurationPayloadNodesPage: View {
    @ObservedObject var session: ConfigurationEditorSession
     
    let providerPath: [String]
    let title: String
     
    @State private var addingType: String?
    @Environment(\.locale) private var locale
    @Environment(\.configurationFieldCopy) private var fieldCopy

     
     
    private static func protocolName(_ type: String, in names: [String: String]) -> String {
        names[type.lowercased()] ?? ProxyProtocolCatalog.specification(for: type)?.displayName ?? type
    }

    struct Row: Equatable {
        let index: Int
        let name: String
        let type: String
    }

    private var payloadPath: [String] { providerPath + ["payload"] }
    private var base: [ConfigurationTextPathStep] { payloadPath.map(ConfigurationTextPathStep.key) }
    private var value: OrderedJSON? { session.value(at: payloadPath) }

     
     
    static func rows(of value: OrderedJSON?) -> [Row] {
        guard case .array(let items)? = value else { return [] }
        return items.enumerated().map { offset, item in
            var type = ""
            if case .string(let text)? = item.topLevelValue("type") { type = text }
            return Row(index: offset, name: ConfigurationEditorCopy.entryTitle(item, index: offset), type: type)
        }
    }

     
     
    static func appending(_ node: OrderedJSON, to value: OrderedJSON?, under base: [ConfigurationTextPathStep]) -> ConfigurationTextStep {
        guard case .array(let items)? = value else {
            return ConfigurationTextStep(path: base, edit: .insert(json: OrderedJSON.array([node]).serialized()))
        }
        return ConfigurationTextStep(path: base + [.index(items.count)], edit: .insert(json: node.serialized()))
    }

    var body: some View {
        let rows = Self.rows(of: value)
        let types = ConfigurationTypeWords.names(.proxies, copy: fieldCopy, locale: locale)
        List {
            Section {
                if rows.isEmpty {
                     
                    Text(clash: .copy("No nodes in this set yet.")).foregroundStyle(.secondary)
                    Button { addingType = "ss" } label: {
                        Label { Text(clash: .copy("Add Node")) } icon: { Image(systemName: ClashSymbol.plus.name) }
                    }
                    .disabled(newNodeTypes.isEmpty)
                    .accessibilityIdentifier("configuration-editor.original-providers.payload.add-row")
                }
                ForEach(rows, id: \.index) { row in
                    ClashNativeNavigationLink {
                        nodePage(row)
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: row.name).lineLimit(1)
                            Spacer()
                            Text(verbatim: Self.protocolName(row.type, in: types))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("configuration-editor.original-providers.payload.node")
                }
                .onDelete { offsets in
                    Task { await session.editOriginal(steps: OriginalListEdits.deleting(offsets.map { rows[$0].index }, under: base)) }
                }
            }
        }
        .navigationTitle(Text(verbatim: title))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                 
                 
                Button { addingType = "ss" } label: {
                    Image(systemName: ClashSymbol.plus.name)
                }
                .disabled(newNodeTypes.isEmpty)
                .accessibilityIdentifier("configuration-editor.original-providers.payload.add")
            }
        }
        .disabled(session.isSaving)
         
        .clashSheet(isPresented: Binding(get: { addingType != nil }, set: { if !$0 { addingType = nil } })) {
            ClashFeatureNavigationContainer {
                ProxyNodeDetailsView(record: CustomNodesView.newNodeTemplate, retest: {},
                                     saveNode: { _, edited in try await add(edited) },
                                     showsTesting: false, isNew: true, dialerRouting: .payloadField,
                                     dialerCandidates: { ConfigurationOriginalNodePage.candidates(excluding: "", in: session) },
                                     onDone: { addingType = nil })
            }
            .clashModalPresentation(.page)
        }
    }

     
     
    private var newNodeTypes: [String] {
        guard let catalog = session.catalog?.fieldCatalog else { return [] }
        return ProxyNodeCatalog.typeIDs(in: catalog, creating: true, current: nil)
    }

     
     
    @ViewBuilder
    private func nodePage(_ row: Row) -> some View {
        if case .array(let items)? = value, items.indices.contains(row.index),
           let record = CustomNodesView.record(fromNodeJSON: items[row.index].serialized()) {
            ProxyNodeDetailsView(
                record: record,
                retest: {},
                saveNode: { original, edited in try await save(row.index, original, edited) },
                allowsRename: false,
                showsTesting: false,
                dialerRouting: .payloadField,
                dialerCandidates: { ConfigurationOriginalNodePage.candidates(excluding: row.name, in: session) }
            )
        } else {
            List { Text(clash: .copy("This node no longer exists.")).foregroundStyle(.secondary) }
        }
    }

    private func save(_ index: Int, _ original: String, _ edited: String) async throws {
        guard case .array(let items)? = value, items.indices.contains(index) else {
            throw OriginalListError.refused(ConfigurationTextEditRefusal(rawCode: "notFound", message: ""))
        }
        let steps = try OriginalListEdits.nodeEdits(written: items[index], formOriginalJSON: original, formEditedJSON: edited,
                                                    at: base + [.index(index)])
        try await ConfigurationOriginalNodePage.saveFromForm(steps, session: session)
    }

    private func add(_ edited: String) async throws {
        let node = OriginalListEdits.handWrittenOrder(try OrderedJSON.parse(edited))
        guard case .string(let name)? = node.node(at: ["name"]), !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw OriginalListError.unnamed
        }
        guard !Self.rows(of: value).contains(where: { $0.name == name }) else { throw OriginalListError.taken(name) }
        try await ConfigurationOriginalNodePage.saveFromForm([Self.appending(node, to: value, under: base)], session: session)
    }
}
#endif
