import Foundation
import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
 
 
 
 

enum ProxyNodeCatalog {
     
     
    static let pageOwnedKeys: Set<String> = ["name", "type", "dialer-proxy"]

     
     
     
    static func offeredValues(for field: ConfigurationField, written: String? = nil) -> [String] {
        field.offeredValues(written: written).map(\.value)
    }

    static func typePath(_ typeID: String) -> String { "proxies[" + typeID.lowercased() + "]" }

     
    static func knows(_ typeID: String, in catalog: ConfigurationFieldCatalog) -> Bool {
        !children(of: typePath(typeID), in: catalog).isEmpty
    }

     
    private static func typeField(in catalog: ConfigurationFieldCatalog) -> ConfigurationField? {
        catalog.fields.first { field in
            field.kind == .select && field.path.hasPrefix("proxies[") && field.path.hasSuffix("].type")
        }
    }

     
     
     
     
     
    static func typeIDs(in catalog: ConfigurationFieldCatalog, creating: Bool, current: String?) -> [String] {
        var types = typeField(in: catalog)?.offeredValues().map(\.value) ?? []
        if creating { types.removeAll { ProxyTypeGrouping.nonServerTypeIDs.contains($0) } }
        if let current, !current.isEmpty, !types.contains(current) { types.append(current) }
        return types
    }

     
     
    static func typeUnavailability(_ typeID: String, in catalog: ConfigurationFieldCatalog) -> ConfigurationUnavailableValue? {
        typeField(in: catalog)?.unavailability(of: typeID)
    }

     
     
    static func newNodeRecord(type typeID: String) -> ProxyNodeRecord {
        ProxyNodeRecord(name: "", type: typeID, delay: nil, groupNames: [],
                        protocolDetails: ProxyProtocolCatalog.details(for: newNodeMapping(type: typeID)))
    }

     
     
    static func newNodeMapping(type typeID: String) -> [String: Any] {
        var template: [String: Any] = ["name": "", "type": typeID]
        ProxyEditorNewNodeDefaults.applying(to: &template, typeID: typeID)
        return template
    }

     
     
     
     
     
     
    static func children(of path: String, in catalog: ConfigurationFieldCatalog) -> [ConfigurationField] {
        let memoKey = "\(catalog.fields.count)|\(catalog.fields.first?.path ?? "")|\(catalog.platformKeys.count)|\(path)"
        memoLock.lock()
        if let remembered = childrenMemo[memoKey] {
            memoLock.unlock()
            return remembered
        }
        memoLock.unlock()
        let base = path + "."
        let found = catalog.fields.filter { field in
            guard field.path.hasPrefix(base) else { return false }
            let rest = field.path.dropFirst(base.count)
            return !rest.isEmpty && !rest.contains(".") && !rest.contains("[") && rest != "*"
        }
        memoLock.lock()
        childrenMemo[memoKey] = found
        memoLock.unlock()
        return found
    }

    private static let memoLock = NSLock()
    nonisolated(unsafe) private static var childrenMemo: [String: [ConfigurationField]] = [:]

    static func key(of field: ConfigurationField) -> String {
        field.path.split(separator: ".").last.map(String.init) ?? field.path
    }

     
     
     
     
     
     
    static func platformDecidedKeys(of mapping: [String: Any], typeID: String,
                                    in catalog: ConfigurationFieldCatalog?) -> Set<String> {
        guard let catalog else { return [] }
        let decided = children(of: typePath(typeID), in: catalog).filter { $0.platformDecision?.overridesTheFile == true }
        guard !decided.isEmpty else { return [] }
        let node = json(mapping) ?? .object([])
        return Set(decided.filter { $0.platformDecision?.applies(to: node) == true }.map(key(of:)))
    }

     
    static func keys(of typeID: String, in catalog: ConfigurationFieldCatalog) -> Set<String> {
        Set(children(of: typePath(typeID), in: catalog).map(key(of:)))
    }

     
     
    static func droppedKeys(from mapping: [String: Any], changingTo typeID: String,
                            in catalog: ConfigurationFieldCatalog) -> [String] {
        let taken = keys(of: typeID, in: catalog)
        return mapping.keys.filter { !pageOwnedKeys.contains($0) && !taken.contains($0) }.sorted()
    }

     
     
     
     
     
    static func droppedFieldTitles(from mapping: [String: Any], currentType: String, changingTo typeID: String,
                                   in catalog: ConfigurationFieldCatalog, copy: ConfigurationFieldCopy,
                                   locale: Locale) -> [String] {
        let language = ConfigurationFieldCopy.Language(locale: locale)
        return droppedKeys(from: mapping, changingTo: typeID, in: catalog).map { key in
            copy.entry(forPath: typePath(currentType) + "." + key, language: language)?.title ?? key
        }
    }

     
     
     
     
     
     
    static func layout(of mapping: [String: Any], typeID: String,
                       in catalog: ConfigurationFieldCatalog) -> ProxyNodeCatalogLayout {
        typealias Row = ProxyNodeCatalogLayout.Row
        typealias Group = ProxyNodeCatalogLayout.Group
        let base = typePath(typeID)
        var rows: [Row] = []
        var objects: [Group] = []
        var known = pageOwnedKeys
        for field in children(of: base, in: catalog) {
            let key = key(of: field)
            guard !ProxyEditorHiddenFields.isHidden(key) else { continue }
            known.insert(key)
            guard !pageOwnedKeys.contains(key) else { continue }
            let value = mapping[key]
            if field.kind == .object, value == nil || value is [String: Any] {
                objects += objectGroups(path: [key], catalogPath: base + "." + key, mapping: mapping,
                                        catalog: catalog, depth: 1)
            } else {
                rows.append(Row(key: key, path: [key], field: field, value: value.flatMap(json)))
            }
        }
        var groups: [Group] = rows.isEmpty ? [] : [Group(id: "main", title: nil, rows: rows)]
        groups += objects
        let extra = mapping.keys.filter { !known.contains($0) }.sorted()
        if !extra.isEmpty {
            let hidden = Dictionary(children(of: base, in: catalog).map { (key(of: $0), $0) }, uniquingKeysWith: { first, _ in first })
            groups.append(Group(id: "other", title: nil,
                                rows: extra.map { Row(key: $0, path: [$0], field: nil, value: mapping[$0].flatMap(json),
                                                      titleField: hidden[$0]) }))
        }
        return ProxyNodeCatalogLayout(groups: groups)
    }

     
     
     
     
    static func field(at path: [String], typeID: String, mapping: [String: Any],
                      in catalog: ConfigurationFieldCatalog) -> ConfigurationField? {
        var parent = typePath(typeID)
        var plainParent: String?
        for (index, key) in path.enumerated() {
            let here = parent + "." + key
            guard index < path.count - 1 else {
                return catalog.field(atCatalogPath: here) ?? plainParent.flatMap { catalog.field(atCatalogPath: $0 + "." + key) }
            }
            if let chosen = variant(of: here, path: Array(path[...index]), mapping: mapping, in: catalog) {
                plainParent = here
                parent = here + "[" + chosen + "]"
            } else {
                plainParent = nil
                parent = here
            }
        }
        return nil
    }

     
     
     
     
     
    static func variant(of catalogPath: String, path: [String], mapping: [String: Any],
                        in catalog: ConfigurationFieldCatalog) -> String? {
        let prefix = catalogPath + "["
        guard catalog.fields.contains(where: { $0.path.hasPrefix(prefix) }) else { return nil }
        var parent: Any? = mapping
        for step in path.dropLast() { parent = (parent as? [String: Any])?[step] }
        var object: Any? = mapping
        for step in path { object = (object as? [String: Any])?[step] }
        let chooser: String?
        if path.last == "plugin-opts" {
            chooser = (parent as? [String: Any])?["plugin"] as? String
        } else {
            chooser = (object as? [String: Any])?["mode"] as? String
        }
        guard let chosen = chooser?.lowercased(), !chosen.isEmpty,
              catalog.fields.contains(where: { $0.path.hasPrefix(prefix + chosen + "].") }) else { return nil }
        return chosen
    }

    private static func objectGroups(path: [String], catalogPath: String, mapping: [String: Any],
                                     catalog: ConfigurationFieldCatalog, depth: Int) -> [ProxyNodeCatalogLayout.Group] {
        var object: Any? = mapping
        for step in path { object = (object as? [String: Any])?[step] }
        let written = object as? [String: Any] ?? [:]
        var rows: [ProxyNodeCatalogLayout.Row] = []
        var nested: [ProxyNodeCatalogLayout.Group] = []
        var known: Set<String> = []
         
         
         
         
        var fields = children(of: catalogPath, in: catalog)
        var variantPath: String?
        if let chosen = variant(of: catalogPath, path: path, mapping: mapping, in: catalog) {
            let base = catalogPath + "[" + chosen + "]"
            variantPath = base
            let plain = Set(fields.map(key(of:)))
            fields += children(of: base, in: catalog).filter { !plain.contains(key(of: $0)) }
        }
        for field in fields {
            let key = key(of: field)
            known.insert(key)
            let value = written[key]
            if field.kind == .object, depth < 3, value == nil || value is [String: Any] {
                let parentPath = variantPath.flatMap { base in field.path.hasPrefix(base + ".") ? base : nil } ?? catalogPath
                nested += objectGroups(path: path + [key], catalogPath: parentPath + "." + key, mapping: mapping,
                                       catalog: catalog, depth: depth + 1)
            } else {
                rows.append(.init(key: key, path: path + [key], field: field, value: value.flatMap(json)))
            }
        }
        for key in written.keys.sorted() where !known.contains(key) {
            rows.append(.init(key: key, path: path + [key], field: nil, value: written[key].flatMap(json)))
        }
        return [.init(id: "object:" + path.joined(separator: "."), title: path.joined(separator: "."), rows: rows,
                      catalogPath: catalogPath)] + nested
    }

     
     
    static func summary(of value: OrderedJSON) -> String {
        switch value {
        case .string(let text): return text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        case .array(let items): return items.map(summary(of:)).joined(separator: ", ")
        case .object(let entries): return entries.map(\.key).joined(separator: ", ")
        default: return value.serialized()
        }
    }

     
    static func json(_ value: Any) -> OrderedJSON? {
        guard JSONSerialization.isValidJSONObject([value]),
              let data = try? JSONSerialization.data(withJSONObject: [value]),
              case .array(let items)? = try? OrderedJSON.parse(String(decoding: data, as: UTF8.self))
        else { return nil }
        return items.first
    }
}

struct ProxyNodeCatalogLayout: Equatable {
    struct Row: Identifiable, Equatable {
        let key: String
        let path: [String]
        let field: ConfigurationField?
        let value: OrderedJSON?
         
         
         
        var titleField: ConfigurationField? = nil
        var id: String { path.joined(separator: ".") }
    }
    struct Group: Identifiable, Equatable {
        let id: String
         
         
        let title: String?
        let rows: [Row]
         
         
        var catalogPath: String? = nil
    }
    let groups: [Group]
     
     
    var platformDecided: [Row] = []
}

 

 
 
@MainActor
protocol CatalogEditableDraft: AnyObject {
    func value(path: [String]) -> Any?
    func hasValue(path: [String]) -> Bool
    func string(path: [String]) -> String
    func bool(path: [String]) -> Bool
    func setString(_ value: String, path: [String], number: Bool, omitWhenEmpty: Bool)
    func setBool(_ value: Bool, path: [String])
    func replaceJSONValue(_ value: Any?, path: [String])
    func removeValue(path: [String])
}

extension CatalogEditableDraft {
    func hasValue(path: [String]) -> Bool { value(path: path) != nil }
}

extension ProxyNodeEditorDraft: CatalogEditableDraft {}

extension CatalogFieldAccess {
     
     
    var words: ClashDisplayText { words(nil) }

     
     
    func words(_ copy: ConfigurationFieldCopy?) -> ClashDisplayText {
        ConfigurationValueWords.summary(draft.value(path: row.path).flatMap(ProxyNodeCatalog.json), field: row.field,
                                        locale: AppPreferences.language().locale, copy: copy)
    }

     
    func title(_ copy: ConfigurationFieldCopy, _ locale: Locale) -> String {
        copy.title(for: row.field ?? row.titleField, key: row.key, locale: locale)
    }
}

 
 
@MainActor
struct CatalogFieldAccess<Draft: CatalogEditableDraft> {
    let draft: Draft
    let row: ProxyNodeCatalogLayout.Row

    var isWritten: Bool { draft.hasValue(path: row.path) }

     
     
    var text: String {
        get { draft.string(path: row.path) }
        nonmutating set {
            let numeric = row.field?.kind == .number
                || (row.field?.values.map { !$0.isEmpty && $0.allSatisfy { Int($0) != nil } } ?? false)
            draft.setString(newValue, path: row.path, number: numeric, omitWhenEmpty: true)
        }
    }

    var flag: Bool {
         
         
        get { isWritten ? draft.bool(path: row.path) : row.field?.defaultFlag == true }
        nonmutating set { draft.setBool(newValue, path: row.path) }
    }

     
     
    var items: [String] {
        get {
            switch draft.value(path: row.path) {
            case let list as [Any]: return list.map { "\($0)" }
            case let text as String:
                guard let separator = row.field?.separator else { return text.isEmpty ? [] : [text] }
                return text.components(separatedBy: separator).filter { !$0.isEmpty }
            default: return []
            }
        }
        nonmutating set {
            let entries = newValue.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if entries.isEmpty {
                draft.removeValue(path: row.path)
            } else if let separator = row.field?.separator {
                draft.replaceJSONValue(entries.joined(separator: separator), path: row.path)
            } else {
                draft.replaceJSONValue(entries, path: row.path)
            }
        }
    }

     
     
    var objects: [[String: String]] {
        get {
            ((draft.value(path: row.path) as? [Any]) ?? []).map { item in
                ((item as? [String: Any]) ?? [:]).mapValues { "\($0)" }
            }
        }
        nonmutating set {
            let kept = newValue.filter { item in item.values.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
            if kept.isEmpty { draft.removeValue(path: row.path) } else { draft.replaceJSONValue(kept, path: row.path) }
        }
    }

    func useDefault() { draft.removeValue(path: row.path) }

     
    func write(_ value: OrderedJSON) {
        guard let data = value.serialized().data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return }
        draft.replaceJSONValue(object, path: row.path)
    }

     
     
     
    var defaultText: String? { ConfigurationValueWords.defaultPrompt(for: row.field, locale: AppPreferences.language().locale) }

     
     
    func defaultPrompt(_ copy: ConfigurationFieldCopy, _ locale: Locale) -> String? {
        ConfigurationValueWords.defaultPrompt(for: row.field, locale: locale, copy: copy)
    }

     
     
    var defaultEntry: ClashDisplayText {
        guard let value = defaultText else { return .copy("Not set") }
        return .format("Default (%@)", [value])
    }
}

typealias ProxyNodeFieldAccess = CatalogFieldAccess<ProxyNodeEditorDraft>

extension ProxyNodeEditorDraft {
     
     
     
     
     
     
     
    func changeType(to typeID: String, catalog: ConfigurationFieldCatalog) {
        let base = ProxyNodeCatalog.typePath(typeID)
        let fields = Dictionary(ProxyNodeCatalog.children(of: base, in: catalog).map { (ProxyNodeCatalog.key(of: $0), $0) },
                                uniquingKeysWith: { first, _ in first })
        for key in mapping.keys where !ProxyNodeCatalog.pageOwnedKeys.contains(key) {
            guard let field = fields[key] else {
                removeValue(path: [key])
                continue
            }
            if field.kind == .select, !(field.values ?? []).isEmpty,
               let current = mapping[key] as? String, !current.isEmpty,
               !ProxyNodeCatalog.offeredValues(for: field).contains(where: { $0.caseInsensitiveCompare(current) == .orderedSame }) {
                removeValue(path: [key])
            }
        }
        setString(typeID, key: "type", omitWhenEmpty: false)
        applyNewTypeDefaults(typeID)
    }

     
     
     
     
    func shownFlag(path: [String], catalog: ConfigurationFieldCatalog?) -> Bool {
        if hasValue(path: path) { return bool(path: path) }
        guard let catalog else { return false }
        return ProxyNodeCatalog.field(at: path, typeID: typeID, mapping: mapping, in: catalog)?.defaultFlag ?? false
    }
}

 

 
struct ProxyNodeCatalogSections: View {
    @ObservedObject var draft: ProxyNodeEditorDraft
    let catalog: ConfigurationFieldCatalog
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

     
     
    struct DrawnSection: Identifiable {
        let id: String
        let title: ClashDisplayText?
        let footer: String?
        let rows: [ProxyNodeCatalogLayout.Row]
    }

     
     
     
     
    static func sections(of layout: ProxyNodeCatalogLayout, typeID: String, catalog: ConfigurationFieldCatalog,
                         copy: ConfigurationFieldCopy, locale: Locale) -> [DrawnSection] {
        sections(of: layout, layoutPath: ProxyNodeCatalog.typePath(typeID), catalog: catalog, copy: copy, locale: locale)
    }

     
     
    static func sections(of layout: ProxyNodeCatalogLayout, layoutPath: String, catalog: ConfigurationFieldCatalog,
                         copy: ConfigurationFieldCopy, locale: Locale) -> [DrawnSection] {
        var drawn: [DrawnSection] = []
        for group in layout.groups {
            switch group.id {
            case "main":
                let sections = copy.layout(forPath: layoutPath, locale: locale) ?? []
                let byKey = Dictionary(group.rows.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
                for section in ConfigurationFieldCopy.arrange(group.rows.map(\.key), in: sections) {
                    drawn.append(DrawnSection(id: "main#" + section.id, title: section.title, footer: section.footer,
                                              rows: section.keys.compactMap { byKey[$0] }))
                }
            case "other":
                drawn.append(DrawnSection(id: group.id, title: .copy("Other Fields"), footer: nil, rows: group.rows))
            default:
                let words = copy.entry(for: group.catalogPath.flatMap { catalog.field(atCatalogPath: $0) }, locale: locale)
                drawn.append(DrawnSection(id: group.id, title: (words?.title ?? group.title).map(ClashDisplayText.verbatim),
                                          footer: words.flatMap { $0.summary.isEmpty ? nil : $0.summary }, rows: group.rows))
            }
        }
        return drawn
    }

     
     
     
     
     
    static func inactive(_ row: ProxyNodeCatalogLayout.Row, in document: OrderedJSON?,
                         catalog: ConfigurationFieldCatalog) -> Bool {
        guard let field = row.field, let document else { return false }
        return catalog.isInactive(field, at: row.path.map(ConfigurationDocumentStep.key), in: document)
    }

     
     
     
    static func offSwitchSummary(over rows: [ProxyNodeCatalogLayout.Row], in document: OrderedJSON?,
                                 catalog: ConfigurationFieldCatalog) -> ConfigurationOffSwitchSummary? {
        guard let document else { return nil }
        return catalog.offSwitchSummary(over: rows.compactMap { row in
            row.field.map { (field: $0, steps: row.path.map(ConfigurationDocumentStep.key)) }
        }, in: document)
    }

    var body: some View {
        let document = ProxyNodeCatalog.json(draft.mapping)
         
         
        let layout = ProxyNodeCatalog.layout(of: draft.mapping, typeID: draft.typeID, in: catalog)
            .splittingOffThePlatformsRows(in: document)
        ForEach(Self.sections(of: layout, typeID: draft.typeID, catalog: catalog, copy: fieldCopy, locale: locale)) { section in
            Section {
                ForEach(section.rows) { row in
                    ProxyNodeCatalogRow(access: ProxyNodeFieldAccess(draft: draft, row: row))
                        .disabled(Self.inactive(row, in: document, catalog: catalog))
                }
            } header: {
                if let title = section.title { Text(clash: title) }
            } footer: {
                if let footer = section.footer { Text(verbatim: footer) }
                if let summary = Self.offSwitchSummary(over: section.rows, in: document, catalog: catalog) {
                    Text(clash: fieldCopy.turnOnLine(summary, locale: locale))
                }
            }
        }
        if !layout.platformDecided.isEmpty {
            Section {
                ClashRoutedViewLink {
                    ConfigurationSettingsNotApplyingView(items: layout.notApplying)
                } label: {
                    ConfigurationNotApplyingLabel(count: layout.platformDecided.count)
                }
                .accessibilityIdentifier("configuration-editor.not-applying")
            }
        }
    }
}

 
 
 
 
struct ProxyNodeTypePicker: View {
    @ObservedObject var draft: ProxyNodeEditorDraft
    let catalog: ConfigurationFieldCatalog?
    let isNew: Bool
    @Binding var pendingType: String?

    var body: some View {
        if let catalog {
            Picker(selection: Binding(get: { draft.typeID }, set: { choose($0, in: catalog) })) {
                ForEach(ProxyNodeCatalog.typeIDs(in: catalog, creating: isNew, current: draft.typeID), id: \.self) { typeID in
                    Text(verbatim: ProxyProtocolCatalog.specification(for: typeID)?.displayName ?? typeID).tag(typeID)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(clash: .copy("Proxy Type"))
                    ConfigurationUnavailableReasons(
                        reasons: ProxyNodeCatalog.typeUnavailability(draft.typeID, in: catalog).map { [$0] } ?? [])
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("proxies.nodeEditor.type")
        } else {
            HStack {
                Text(clash: .copy("Proxy Type"))
                Spacer()
                ProgressView()
            }
            .accessibilityIdentifier("proxies.nodeEditor.type")
        }
    }

    private func choose(_ typeID: String, in catalog: ConfigurationFieldCatalog) {
        guard typeID != draft.typeID else { return }
        if ProxyNodeCatalog.droppedKeys(from: draft.mapping, changingTo: typeID, in: catalog).isEmpty {
            draft.changeType(to: typeID, catalog: catalog)
        } else {
            pendingType = typeID
        }
    }
}

 
 
 
struct ProxyNodeCatalogRow: View {
    let access: ProxyNodeFieldAccess

     
     
     
    enum FreeControl: Equatable { case text, number, toggle, json }

    static func freeControl(for value: OrderedJSON?) -> FreeControl {
        switch value {
        case .none, .string?: return .text
        case .scalar(let token)?:
            if token == "true" || token == "false" { return .toggle }
            if token == "null" { return .text }
            return Double(token) != nil ? .number : .text
        case .array?, .object?: return .json
        }
    }

    private var key: String { access.row.key }
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale
     
    private var title: String { access.title(fieldCopy, locale) }
    private var identifier: String { "proxies.nodeEditor.field.\(access.row.path.joined(separator: "."))" }

    var body: some View {
        control
            .accessibilityIdentifier(identifier)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if access.isWritten {
                    Button { access.useDefault() } label: { ClashSwipeLabel(.copy("Use Default"), symbol: .arrowUturnBackward) }
                        .tint(.orange)
                }
            }
    }

    @ViewBuilder
    private var control: some View {
        if let note = ProxyEditorPlatformNotes.clientManagedNote(forKey: key) {
             
            VStack(alignment: .leading, spacing: 2) {
                CatalogLabeledRow(title: title, value: access.text)
                Text(clash: .copy(note)).font(.caption).foregroundStyle(.secondary)
            }
        } else if let field = access.row.field {
            if CatalogInlineControl<ProxyNodeEditorDraft>.isInline(field, access: access) {
                CatalogInlineControl(access: access, field: field, identifier: identifier)
            } else {
                switch field.kind {
                case .select, .suggest:
                    ProxyNodeDraftNavigationLink(source: access.draft) { local in
                        CatalogChoicePage(access: ProxyNodeFieldAccess(draft: local, row: access.row),
                                          options: ProxyNodeCatalog.offeredValues(for: field, written: access.text),
                                          allowsCustom: field.kind != .select, identifier: identifier)
                            .clashCatalogPageSeat()
                    } label: {
                        CatalogLabeledRow(title: title, value: access.words(fieldCopy))
                    }
                case .reference where !(field.values ?? []).isEmpty:
                    ProxyNodeDraftNavigationLink(source: access.draft) { local in
                        CatalogChoicePage(access: ProxyNodeFieldAccess(draft: local, row: access.row),
                                          options: ProxyNodeCatalog.offeredValues(for: field, written: access.text),
                                          allowsCustom: true, identifier: identifier)
                            .clashCatalogPageSeat()
                    } label: {
                        CatalogLabeledRow(title: title, value: access.words(fieldCopy))
                    }
                case .number:
                    CatalogTextFieldRow(access: access, field: field, numeric: true, identifier: identifier)
                case .text, .reference:
                    if isDocument { documentLink } else {
                        CatalogTextFieldRow(access: access, field: field, numeric: false, identifier: identifier)
                    }
                case .textList, .multiSelect:
                    ProxyNodeDraftNavigationLink(source: access.draft) { local in
                        CatalogListPage(access: ProxyNodeFieldAccess(draft: local, row: access.row),
                                        options: field.kind == .textList ? nil : ProxyNodeCatalog.offeredValues(for: field),
                                        identifier: identifier)
                            .clashCatalogPageSeat()
                    } label: {
                        CatalogLabeledRow(title: title, value: access.words(fieldCopy))
                    }
                case .map, .objectList:
#if os(iOS)
                     
                     
                     
                    ProxyNodeDraftNavigationLink(source: access.draft) { local in
                        ProxyNodeEntryPage(draft: local, path: access.row.path, field: field, title: title)
                    } label: {
                        CatalogLabeledRow(title: title, value: access.words(fieldCopy))
                    }
#else
                     
                     
                    if let entryPage = ProxyNodeEditorMacOverrides.entryPage {
                        ProxyNodeDraftNavigationLink(source: access.draft) { local in
                            entryPage(local, access.row.path, field, title)
                        } label: {
                            CatalogLabeledRow(title: title, value: access.words(fieldCopy))
                        }
                    } else {
                        jsonLink
                    }
#endif
                case .toggle, .object, .unrecognised:
                    jsonLink
                }
            }
        } else if isDocument {
            documentLink
        } else {
             
            switch Self.freeControl(for: access.row.value) {
            case .text: freeTextRow(numeric: false)
            case .number: freeTextRow(numeric: true)
            case .toggle:
                Toggle(isOn: Binding(get: { access.flag }, set: { access.flag = $0 })) { Text(verbatim: title) }
            case .json: jsonLink
            }
        }
    }

     
    private func freeTextRow(numeric: Bool) -> some View {
        HStack {
            Text(verbatim: title)
            Spacer(minLength: 12)
            TextField(text: Binding(get: { access.text }, set: { newValue in
                access.draft.setString(newValue, path: access.row.path, number: numeric, omitWhenEmpty: true)
            }), prompt: nil) { Text(verbatim: title) }
            .multilineTextAlignment(.trailing)
            .autocorrectionDisabled()
#if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(numeric ? .numbersAndPunctuation : .default)
#endif
        }
    }

     
     
     
    private var isDocument: Bool {
        access.text.contains(where: \.isNewline)
            || ProxyNodeDetailsView.isDocumentField(key, typeID: access.draft.typeID)
    }

    private var documentLink: some View {
        ProxyNodeDraftNavigationLink(source: access.draft) { local in
            CatalogDocumentPage(access: ProxyNodeFieldAccess(draft: local, row: access.row), identifier: identifier)
                .clashCatalogPageSeat()
        } label: {
            CatalogLabeledRow(title: title, value: access.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? "")
        }
    }

    private var jsonLink: some View {
        ProxyNodeDraftNavigationLink(source: access.draft) { local in
            ProxyJSONPathEditorView(draft: local, path: access.row.path, title: title, goType: "")
        } label: {
            CatalogLabeledRow(title: title, value: access.words(fieldCopy))
        }
    }
}

#if os(iOS)
 
 
 
 
 
 
struct ProxyNodeEntryPage: View {
    @ObservedObject var draft: ProxyNodeEditorDraft
    let path: [String]
    let field: ConfigurationField
    let title: String

    private var document: OrderedJSON {
        .object([(key: "proxies", value: .array([ProxyNodeCatalog.json(draft.mapping) ?? .object([])]))])
    }
    private var steps: [ConfigurationDocumentStep] { [.key("proxies"), .index(0)] + path.map(ConfigurationDocumentStep.key) }
    private var value: OrderedJSON? { draft.value(path: path).flatMap(ProxyNodeCatalog.json) }

    var body: some View {
        if field.kind == .map {
            ConfigurationEntryMapPage(title: title, value: value, steps: steps, document: document,
                                      catalog: ProfilesViewModel.rememberedSyntaxCatalog, save: save)
        } else {
            ConfigurationEntryObjectListPage(title: title, value: value, steps: steps, document: document,
                                             catalog: ProfilesViewModel.rememberedSyntaxCatalog, save: save)
        }
    }

     
    private func save(_ next: OrderedJSON?) { Self.apply(next, to: draft, path: path) }

     
     
     
     
    static func apply(_ next: OrderedJSON?, to draft: ProxyNodeEditorDraft, path: [String]) {
        guard let next else {
            draft.removeValue(path: path)
            return
        }
        guard let data = next.serialized().data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return }
        draft.replaceJSONValue(object, path: path)
    }
}
#endif

 

 
 
 
 
 
 
struct CatalogInlineControl<Draft: CatalogEditableDraft>: View {
    let access: CatalogFieldAccess<Draft>
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale
    let field: ConfigurationField
    let identifier: String

     
    static func isInline(_ field: ConfigurationField, access: CatalogFieldAccess<Draft>) -> Bool {
        ConfigurationSectionLayout.isInline(field, value: access.row.value, in: .object([]))
    }

    private var draft: ConfigurationFieldDraft? {
        ConfigurationFieldDraft(field: field, value: access.row.value, in: .object([]))
    }

    var body: some View {
        if let draft {
#if os(iOS)
            ConfigurationInlineFieldRow(
                title: access.title(fieldCopy, locale), draft: draft, identifier: identifier,
                save: { access.write($0) },
                isDefault: !access.isWritten, defaultText: access.defaultText,
                useDefault: access.isWritten ? { access.useDefault() } : nil, field: field)
#else
            CatalogNativeInlineRow(access: access, draft: draft, choices: draft.choices, identifier: identifier)
#endif
        }
    }
}

 
 
 
struct ConfigurationUnavailableReasons: View {
    let reasons: [ConfigurationUnavailableValue]
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

    var body: some View {
        if !reasons.isEmpty {
             
             
             
            VStack(alignment: .leading, spacing: 2) {
                ForEach(reasons, id: \.value) { reason in
                    if let words = fieldCopy.unavailableWords(reason.value, locale: locale) {
                        Text(verbatim: words)
                    } else {
                        Text(clash: .format("%@ can’t run on this device.", [reason.value]))
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

 
 
struct CatalogNativeInlineRow<Draft: CatalogEditableDraft>: View {
    let access: CatalogFieldAccess<Draft>
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale
    let draft: ConfigurationFieldDraft
     
    let choices: [String]
    let identifier: String

    private static var defaultTag: String { "\u{1F}default" }

    private var offered: [String] {
        let current = draft.text
        guard access.isWritten, !current.isEmpty, !choices.contains(current) else { return choices }
        return [current] + choices
    }

    var body: some View {
        switch draft.control {
        case .toggle:
            Toggle(isOn: Binding(get: { access.flag }, set: { access.flag = $0 })) { label }
                .accessibilityIdentifier(identifier + ".toggle")
        default:
            Picker(selection: Binding(get: { access.isWritten ? draft.text : Self.defaultTag }, set: { choice in
                if choice == Self.defaultTag {
                    access.useDefault()
                } else {
                    var next = draft
                    next.text = choice
                    access.write(next.value)
                }
            })) {
                Text(clash: access.defaultEntry).tag(Self.defaultTag)
                ForEach(offered, id: \.self) { Text(verbatim: fieldCopy.valueLabel($0, for: access.row.field, locale: locale) ?? $0).tag($0) }
            } label: {
                label
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier(identifier + ".menu")
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: access.title(fieldCopy, locale))
             
             
            if access.isWritten {
                ConfigurationUnavailableReasons(reasons: draft.unavailableInUse)
            }
        }
    }
}

 
 
struct CatalogTextFieldRow<Draft: CatalogEditableDraft>: View {
    let access: CatalogFieldAccess<Draft>
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale
    let field: ConfigurationField
    let numeric: Bool
    let identifier: String
     
     
     
    @State private var refused: ConfigurationTypedEntry?

     
    private var typed: Binding<String> {
        Binding(get: { refused?.typed ?? access.text }, set: { text in
            if let problem = ConfigurationFieldValidation.problem(text, field: field) {
                var entry = refused ?? ConfigurationTypedEntry(text: access.text)
                _ = entry.type(text) { _ in problem }
                refused = entry
            } else {
                refused = nil
                access.text = text
            }
        })
    }

    var body: some View {
#if os(macOS)
         
         
         
         
        ClashFieldRow(access.title(fieldCopy, locale), hint: access.defaultPrompt(fieldCopy, locale) ?? "", text: typed,
                     identifier: identifier, subtitle: refused?.problem?.words)
            .id(identifier)
#else
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: access.title(fieldCopy, locale))
                if field.isRequired {
                    Text(clash: .copy("Required")).font(.caption).foregroundStyle(.secondary)
                }
                if let problem = refused?.problem {
                    Text(clash: problem.words).font(.caption).foregroundStyle(.red)
                }
            }
            Spacer(minLength: 12)
            TextField(text: typed, prompt: access.defaultPrompt(fieldCopy, locale).map { Text(verbatim: $0) }) {
                Text(verbatim: access.title(fieldCopy, locale))
            }
            .multilineTextAlignment(.trailing)
            .autocorrectionDisabled()
#if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(numeric
                ? ConfigurationFormatEditors.numberKeyboard(min: field.min, text: access.text, defaultText: field.defaultText)
                : ConfigurationFormatEditors.keyboard(for: field.format))
#endif
        }
#endif
    }
}

 
struct CatalogLabeledRow: View {
    let title: String
    let value: ClashDisplayText

    init(title: String, value: ClashDisplayText) {
        self.title = title
        self.value = value
    }

    init(title: String, value: String) {
        self.init(title: title, value: .verbatim(value))
    }

    var body: some View {
        HStack {
            Text(verbatim: title)
            Spacer(minLength: 12)
            Text(clash: value).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

extension View {
     
     
     
    func clashCatalogPageSeat() -> some View { ProxyEditorSeat { self } }
}

 
struct CatalogDocumentPage<Draft: CatalogEditableDraft>: View {
    let access: CatalogFieldAccess<Draft>
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale
    let identifier: String
    @State private var text = ""

    var body: some View {
        Group {
            Section {
                TextEditor(text: $text)
                    .font(.body.monospaced())
                    .frame(minHeight: 220)
                    .autocorrectionDisabled()
#if os(iOS)
                    .textInputAutocapitalization(.never)
#endif
                    .accessibilityIdentifier(identifier + ".document")
            }
#if os(iOS)
             
             
            ConfigurationFieldAbout(summary: fieldCopy.entry(for: access.row.field, locale: locale)?.summary,
                                    key: access.row.path.last)
#endif
        }
        .navigationTitle(Text(verbatim: access.title(fieldCopy, locale)))
        .onAppear { text = access.text }
        .onDisappear { if text != access.text { access.text = text } }
    }
}

 
 
 
 
 
 
 
 
struct CatalogCustomEntry: Equatable {
    private(set) var text: String
     
    private(set) var isPending = false

    init(text: String = "") { self.text = text }

     
    mutating func type(_ typed: String) {
        guard typed != text else { return }
        text = typed
        isPending = true
    }

     
    mutating func picked() { isPending = false }

     
     
    mutating func take() -> String? {
        defer { isPending = false }
        guard isPending else { return nil }
        let typed = text.trimmingCharacters(in: .whitespaces)
        return typed.isEmpty ? nil : typed
    }
}

 
struct CatalogChoicePage<Draft: CatalogEditableDraft>: View {
    let access: CatalogFieldAccess<Draft>
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale
    let options: [String]
    let allowsCustom: Bool
    let identifier: String
    @State private var custom = CatalogCustomEntry()
     
    @State private var beforeTyping: String?
     
     
    @State private var revision = 0

     
     
     
    private func option(for value: String) -> String? {
        ConfigurationChoiceMatch.choice(for: value, in: options, caseInsensitive: access.row.field?.caseInsensitive == true)
    }

    var body: some View {
        let _ = revision
        Group {
            Picker(selection: Binding(get: { option(for: access.text) ?? (access.text.isEmpty ? "" : "\u{1F}own") },
                                      set: pick)) {
                Text(clash: access.defaultEntry).tag("")
                ForEach(options, id: \.self) { Text(verbatim: fieldCopy.valueLabel($0, for: access.row.field, locale: locale) ?? $0).tag($0) }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
            .accessibilityIdentifier(identifier + ".choices")
             
             
            if let unavailable = access.row.field?.unavailability(of: access.text) {
                Section {} footer: { ConfigurationUnavailableReasons(reasons: [unavailable]) }
            }
            if allowsCustom {
                Section {
                    TextField(text: Binding(get: { custom.text }, set: type),
                              prompt: Text(clash: .copy("Custom"))) { Text(clash: .copy("Custom")) }
                        .autocorrectionDisabled()
                        .onSubmit { if let typed = custom.take(), typed != access.text { write(typed) } }
                        .accessibilityIdentifier(identifier + ".custom")
                }
            }
        }
        .navigationTitle(Text(verbatim: access.title(fieldCopy, locale)))
        .onAppear {
             
            if !custom.isPending { custom = CatalogCustomEntry(text: option(for: access.text) != nil ? "" : access.text) }
        }
         
        .onDisappear {
            if let typed = custom.take(), typed != access.text { access.text = typed }
        }
    }

     
     
     
    private func pick(_ value: String) {
        guard value != "\u{1F}own" else { return }
        custom = CatalogCustomEntry()
        beforeTyping = nil
        write(value)
    }

     
     
     
    private func type(_ typed: String) {
        guard typed != custom.text else { return }
        custom.type(typed)
        if beforeTyping == nil { beforeTyping = access.text }
        let value = typed.trimmingCharacters(in: .whitespaces)
        write(value.isEmpty ? (beforeTyping ?? access.text) : value)
    }

    private func write(_ value: String) {
        if access.text != value { access.text = value }
        revision += 1
    }
}

 
struct CatalogListPage<Draft: CatalogEditableDraft>: View {
    let access: CatalogFieldAccess<Draft>
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale
     
    let options: [String]?
    let identifier: String
    @State private var entries: [String] = []
    @State private var adding = ""

    var body: some View {
        Group {
            if let options {
                 
                 
                 
                Section {
                    ForEach(options + entries.filter { !options.contains($0) }, id: \.self) { option in
                        Toggle(isOn: Binding(get: { entries.contains(option) }, set: { on in
                            var chosen = access.items
                            if on, !chosen.contains(option) { chosen.append(option) }
                            if !on { chosen.removeAll { $0 == option } }
                            access.items = chosen
                            entries = chosen
                        })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: fieldCopy.valueLabel(option, for: access.row.field, locale: locale) ?? option)
                                 
                                 
                                ConfigurationUnavailableReasons(
                                    reasons: access.row.field?.unavailability(of: option).map { [$0] } ?? [])
                            }
                        }
                        .accessibilityIdentifier(identifier + ".option")
                    }
                }
            } else {
#if os(iOS)
                 
                 
                 
                ConfigurationListRows(items: Binding(get: { entries }, set: { entries = $0; access.items = $0 }),
                                      newItem: $adding, field: access.row.field,
                                      ordered: access.row.field?.ordered == true,
                                      suggestions: access.row.field.map { ProxyNodeCatalog.offeredValues(for: $0) } ?? [])
#else
                Section {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, _ in
                        TextField(text: Binding(get: { entries[index] }, set: { entries[index] = $0; access.items = entries }),
                                  prompt: nil) { EmptyView() }
                            .autocorrectionDisabled()
                            .accessibilityIdentifier(identifier + ".entry")
                    }
                    .onDelete { offsets in
                        entries.remove(atOffsets: offsets)
                        access.items = entries
                    }
                    .onMove { from, to in
                        entries.move(fromOffsets: from, toOffset: to)
                        access.items = entries
                    }
                    TextField(text: $adding, prompt: Text(clash: .copy("Add"))) { Text(clash: .copy("Add")) }
                        .autocorrectionDisabled()
                        .onSubmit {
                            let value = adding.trimmingCharacters(in: .whitespaces)
                            guard !value.isEmpty else { return }
                            entries.append(value)
                            access.items = entries
                            adding = ""
                        }
                        .accessibilityIdentifier(identifier + ".add")
                }
#endif
            }
        }
        .navigationTitle(Text(verbatim: access.title(fieldCopy, locale)))
        .onAppear { entries = access.items }
         
        .onDisappear {
            if let next = Self.entriesOnLeaving(entries: entries, adding: adding) {
                entries = next
                access.items = next
                adding = ""
            }
        }
    }

     
     
    static func entriesOnLeaving(entries: [String], adding: String) -> [String]? {
        let value = adding.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        return entries + [value]
    }
}

 
 
 
struct CatalogObjectListPage<Draft: CatalogEditableDraft>: View {
    let access: CatalogFieldAccess<Draft>
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale
     
    let itemKeys: [String]
    let identifier: String
    @State private var items: [[String: String]] = []
    @State private var adding: [String: String] = [:]

     
     
     
    private func words(_ key: String) -> ConfigurationFieldCopy.Entry? {
        guard let path = access.row.field?.path else { return nil }
        return fieldCopy.entry(forPath: path + "[]." + key, language: .init(locale: locale))
    }

    private func label(_ key: String) -> Text { Text(verbatim: words(key)?.title ?? key) }

    private func prompt(_ key: String) -> Text? { words(key)?.example.map { Text(verbatim: $0) } }

    var body: some View {
        Group {
            ForEach(Array(items.enumerated()), id: \.offset) { index, _ in
                Section {
                    ForEach(itemKeys, id: \.self) { key in
                        TextField(text: Binding(get: { items[index][key] ?? "" }, set: { items[index][key] = $0; access.objects = items }),
                                  prompt: prompt(key)) { label(key) }
                            .autocorrectionDisabled()
                            .accessibilityIdentifier(identifier + ".item")
                    }
                    Button(role: .destructive) {
                        items.remove(at: index)
                        access.objects = items
                    } label: {
                        Text(clash: .copy("Delete"))
                    }
                    .accessibilityIdentifier(identifier + ".delete")
                }
            }
            Section {
                ForEach(itemKeys, id: \.self) { key in
                    TextField(text: Binding(get: { adding[key] ?? "" }, set: { adding[key] = $0 }),
                              prompt: prompt(key) ?? label(key)) { label(key) }
                        .autocorrectionDisabled()
                        .accessibilityIdentifier(identifier + ".new")
                }
                Button {
                    items.append(adding)
                    access.objects = items
                    adding = [:]
                } label: {
                    Text(clash: .copy("Add"))
                }
                .disabled(!adding.values.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
                .accessibilityIdentifier(identifier + ".add")
            }
        }
        .navigationTitle(Text(verbatim: access.title(fieldCopy, locale)))
        .onAppear { items = access.objects }
    }
}
