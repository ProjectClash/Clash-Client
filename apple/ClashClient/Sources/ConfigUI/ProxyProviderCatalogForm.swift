#if os(iOS)
import Foundation
import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 

 
 
struct ProxyProviderCatalogRow: View {
    @ObservedObject var session: ConfigurationEditorSession
    let providerPath: [String]
    let row: ProxyNodeCatalogLayout.Row
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

     
    private var title: String { fieldCopy.title(for: row.field, key: row.key, locale: locale) }

     
     
     
    static func opensNodeList(_ path: [String]) -> Bool { path == ["payload"] }

    private var identifier: String {
        "configuration-editor.original-providers.field.\(row.path.joined(separator: "."))"
    }

    var body: some View {
        control
            .accessibilityIdentifier("configuration-editor.original-providers.field.\(row.path.joined(separator: "."))")
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if row.value != nil {
                    Button { Task { await useDefault() } } label: { ClashSwipeLabel(.copy("Use Default"), symbol: .arrowUturnBackward) }
                        .tint(.orange)
                }
            }
    }

    @ViewBuilder
    private var control: some View {
        if let field = row.field,
           ConfigurationSectionLayout.isInline(field, value: row.value, in: session.page?.document ?? .object([])),
           let draft = ConfigurationFieldDraft(field: field, value: row.value, in: session.page?.document ?? .object([])) {
            ConfigurationInlineFieldRow(
                title: title, draft: draft, identifier: identifier,
                save: { value in Task { await write(value.serialized()) } },
                isDefault: row.value == nil, defaultText: field.defaultText,
                useDefault: row.value == nil ? nil : { Task { await useDefault() } }, field: field)
        } else if Self.opensNodeList(row.path) {
            ClashNativeNavigationLink {
                ConfigurationPayloadNodesPage(session: session, providerPath: providerPath, title: title)
                    .configurationPushedAlertHost(session)
            } label: {
                valueLabel
            }
        } else if let field = row.field, field.kind == .map || field.kind == .objectList {
             
             
             
             
            ClashNativeNavigationLink {
                entryPage(field)
                    .configurationPushedAlertHost(session)
            } label: {
                valueLabel
            }
        } else {
            ClashNativeNavigationLink {
                ConfigurationOriginalValueView(session: session, title: title,
                                               value: row.value ?? startingValue, choices: nil, field: row.field) { json in
                    await write(json)
                }
                .configurationPushedAlertHost(session)
            } label: {
                valueLabel
            }
        }
    }

    private var valueLabel: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: title)
            Spacer()
            Text(clash: ConfigurationValueWords.summary(row.value, field: row.field, locale: AppPreferences.language().locale,
                                                       copy: fieldCopy))
                .foregroundStyle(.secondary).lineLimit(1)
        }
    }

    @ViewBuilder
    private func entryPage(_ field: ConfigurationField) -> some View {
        let steps = (providerPath + row.path).map(ConfigurationDocumentStep.key)
        let document = session.page?.document ?? .object([])
        if field.kind == .map {
            ConfigurationEntryMapPage(title: title, value: row.value, steps: steps, document: document,
                                      catalog: session.catalog) { value in Task { await saveEntry(value) } }
        } else {
            ConfigurationEntryObjectListPage(title: title, value: row.value, steps: steps, document: document,
                                             catalog: session.catalog) { value in Task { await saveEntry(value) } }
        }
    }

     
    private func saveEntry(_ value: OrderedJSON?) async {
        if let value { await write(value.serialized()) } else { await useDefault() }
    }

     
    private var startingValue: OrderedJSON { Self.startingValue(for: row.field) }

     
     
     
    static func startingValue(for field: ConfigurationField?) -> OrderedJSON {
        switch field?.defaultShape {
        case .value(let text)?: return field?.kind == .number ? .scalar(text) : .string(text)
        case .list(let items)? where !items.isEmpty: return .array(items.map { .string($0) })
        default: return .string("")
        }
    }

     
     
     
     
     
     
    private func write(_ json: String) async {
        let base = providerPath, path = row.path, key = row.key
        _ = await session.queueOriginal { document in
            let steps = { (path: [String]) in (base + path).map(ConfigurationTextPathStep.key) }
            guard document.node(at: base) != nil else { return .cannot }
            let parent = Array(path.dropLast())
            if !parent.isEmpty, document.node(at: base + parent) == nil, let value = try? OrderedJSON.parse(json) {
                return .write([ConfigurationTextStep(path: steps(parent),
                                                     edit: .insert(json: OrderedJSON.object([(key: key, value: value)]).serialized()))])
            }
            let written = document.node(at: base + path)
            if let written, let value = try? OrderedJSON.parse(json), value == written { return .write([]) }
            return .write([ConfigurationTextStep(path: steps(path), edit: written != nil ? .set(json: json) : .insert(json: json))])
        }
    }

    private func useDefault() async {
        let base = providerPath, path = row.path
        _ = await session.queueOriginal { document in
            .write(document.node(at: base + path) == nil ? [] : [ConfigurationTextStep(path: (base + path).map(ConfigurationTextPathStep.key), edit: .delete)])
        }
    }
}
#endif
