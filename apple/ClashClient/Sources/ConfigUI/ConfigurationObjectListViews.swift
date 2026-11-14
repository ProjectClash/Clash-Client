#if os(iOS)
import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
 
 

 
 
 
struct ConfigurationObjectListView: View {
    @ObservedObject var session: ConfigurationEditorSession
    let location: ConfigurationListLocation
    let title: String
    @State private var adding = false
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

    private var document: OrderedJSON { session.settingsDocument }
    private var items: [OrderedJSON] { location.items(in: document) }

    var body: some View {
        let items = items
        let types = ConfigurationTypeWords.names(.listeners, copy: fieldCopy, locale: locale)
        List {
            Section {
                if items.isEmpty {
                     
                     
                    ConfigurationEmptyListRows(key: Self.topLevelKey(of: location) ?? "") {
                        Button { adding = true } label: {
                            Label { Text(clash: .copy("Add")) } icon: { Image(systemName: ClashSymbol.plus.name) }
                        }
                        .accessibilityIdentifier("configuration-editor.list.add-first")
                    }
                }
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    ClashNativeNavigationLink {
                        ConfigurationObjectItemView(session: session, location: location, index: index)
                            .configurationPushedAlertHost(session)
                    } label: {
                        ConfigurationRowLabel(title: .verbatim(ConfigurationObjectList.title(of: item, index: index)),
                                              value: .verbatim(Self.summary(of: item, typeNames: types)))
                    }
                    .accessibilityIdentifier("configuration-editor.list-item.\(index)")
                }
                .onDelete { offsets in
                    write(items.enumerated().filter { !offsets.contains($0.offset) }.map(\.element))
                }
            }
        }
        .navigationTitle(Text(verbatim: title))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ControlGroup {
                    Button { adding = true } label: { Image(systemName: ClashSymbol.plus.name) }
                        .accessibilityLabel(Text(clash: .copy("Add")))
                        .accessibilityIdentifier("configuration-editor.list.add")
                }
                .clashReaderControlGroupStyle()
            }
        }
        .disabled(session.isSaving)
        .clashSheet(isPresented: $adding) {
            ConfigurationNewListItemForm(session: session, location: location) { item in
                write(location.items(in: session.settingsDocument) + [item])
            }
            .clashModalPresentation(.form)
        }
    }

    private func write(_ next: [OrderedJSON]) {
        session.edit([location.edit(writing: next, in: session.settingsDocument)])
    }

     
     
    static func topLevelKey(of location: ConfigurationListLocation) -> String? {
        guard case .key(let path) = location, path.count == 1 else { return nil }
        return path[0]
    }

     
     
    static func summary(of item: OrderedJSON, typeNames: [String: String] = [:]) -> String {
        guard case .object = item else { return "" }
        let parts = ["type", "port", "listen", "network"].compactMap { key -> String? in
            switch item.topLevelValue(key) {
            case .string(let text)?: return key == "type" ? ConfigurationTypeWords.word(text, in: typeNames) : text
            case .scalar(let token)? where token != "null": return token
            default: return nil
            }
        }
        return parts.dropFirst(item.topLevelValue("name") == nil ? 1 : 0).joined(separator: " · ")
    }
}

 
 
 
 
 
 
struct ConfigurationNewListItemForm: View {
    @ObservedObject var session: ConfigurationEditorSession
    let location: ConfigurationListLocation
    let add: (OrderedJSON) -> Void
    @State private var type = ""
    @State private var values: [String: ConfigurationNewItem.Value] = [:]
    @StateObject private var dismiss = ClashDismissHandle()
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

    private var document: OrderedJSON { session.settingsDocument }
    private var catalog: ConfigurationFieldCatalog? { session.catalog?.fieldCatalog }
    private var types: [String] {
        catalog.map { ConfigurationObjectList.types(location, in: document, catalog: $0) } ?? []
    }
    private var chosenType: String? { types.isEmpty ? nil : (types.contains(type) ? type : types.first) }
    private var form: ConfigurationNewItem? {
        catalog.map { ConfigurationObjectList.newItemForm(location, type: chosenType, in: document, catalog: $0) }
    }

     
     
    private func typeWords(_ type: String) -> String {
        guard let catalog, let list = ConfigurationObjectList.listPath(location, in: document, catalog: catalog),
              let field = catalog.field(atCatalogPath: list + "[" + type + "].type") else { return type }
        return fieldCopy.valueLabel(type, for: field, locale: locale) ?? type
    }

    var body: some View {
        let form = form
        ClashFeatureNavigationContainer {
            Form {
                if !types.isEmpty {
                    Section {
                        Picker(selection: Binding(get: { chosenType ?? "" }, set: { type = $0; values = [:] })) {
                            ForEach(types, id: \.self) { Text(verbatim: typeWords($0)).tag($0) }
                        } label: { Text(clash: .copy("Type")) }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("configuration-editor.new-item.type")
                    }
                }
                if let form {
                    ConfigurationNewItemFields(form: form, values: $values,
                                               identifierPrefix: "configuration-editor.new-item",
                                               addLineIdentifier: "configuration-editor.new-item.add-line")
                }
            }
            .navigationTitle(Text(clash: .copy("Add")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(clash: .copy("Cancel")) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if let form { add(form.item(ConfigurationNewItemFields.filled(form, values))) }
                        dismiss()
                    } label: { Text(clash: .copy("Add")) }
                     
                     
                    .disabled(!(form.map { $0.canAdd(ConfigurationNewItemFields.filled($0, values)) } ?? false))
                    .accessibilityIdentifier("configuration-editor.new-item.add")
                }
            }
        }
        .clashCapturesDismiss(dismiss)
    }
}

 
 
 
 
 
 
struct ConfigurationNewItemFields: View {
    let form: ConfigurationNewItem
    @Binding var values: [String: ConfigurationNewItem.Value]
     
     
    let identifierPrefix: String
    let addLineIdentifier: String
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

     
     
    private func title(of asked: ConfigurationNewItem.Asked) -> String {
        fieldCopy.title(for: asked.field, key: asked.key, locale: locale)
    }

     
    private func words(_ value: String, of asked: ConfigurationNewItem.Asked) -> String {
        fieldCopy.valueLabel(value, for: asked.field, locale: locale) ?? value
    }

    var body: some View {
        let plain = form.asked.filter { !Self.hasOwnSection($0) }
        let required = plain.filter(\.isRequired)
        if !required.isEmpty {
            Section {
                ForEach(required) { asked in control(asked, value: binding(asked), identifier: "\(identifierPrefix).\(asked.key)") }
            } header: { Text(clash: .copy("Required")) }
        }
        ForEach(form.asked.filter(Self.hasOwnSection)) { asked in
            Section {
                sectionControls(asked, value: binding(asked), identifier: "\(identifierPrefix).\(asked.key)")
            } header: {
                Text(verbatim: title(of: asked))
            }
        }
        let optional = plain.filter { !$0.isRequired }
        if !optional.isEmpty {
            Section {
                ForEach(optional) { asked in control(asked, value: binding(asked), identifier: "\(identifierPrefix).\(asked.key)") }
            } header: { Text(clash: .copy("Optional")) }
        }
    }

     
    static func filled(_ form: ConfigurationNewItem, _ values: [String: ConfigurationNewItem.Value])
        -> [String: ConfigurationNewItem.Value] {
        form.initialValues.merging(values) { _, typed in typed }
    }

     
     
    private static func hasOwnSection(_ asked: ConfigurationNewItem.Asked) -> Bool {
        switch asked.control {
        case .choices, .lines, .pair, .group: return true
        default: return false
        }
    }

    private func binding(_ asked: ConfigurationNewItem.Asked) -> Binding<ConfigurationNewItem.Value> {
        Binding(get: { values[asked.key] ?? asked.initialValue }, set: { values[asked.key] = $0 })
    }

     
    private static func problem(_ text: String, of asked: ConfigurationNewItem.Asked) -> ConfigurationFieldProblem? {
        ConfigurationFieldValidation.problem(text, field: asked.field)
    }

     
    @ViewBuilder
    private func control(_ asked: ConfigurationNewItem.Asked, value: Binding<ConfigurationNewItem.Value>,
                         identifier: String) -> some View {
        switch asked.control {
        case .text, .number:
             
             
             
            TextField(text: Self.text(value)) { Text(verbatim: title(of: asked)) }
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .keyboardType(asked.control == .number
                              ? ConfigurationFormatEditors.numberKeyboard(min: asked.field.min, text: Self.text(value).wrappedValue,
                                                                          defaultText: asked.field.defaultText)
                              : .default)
                .accessibilityIdentifier(identifier)
            if let problem = Self.problem(Self.text(value).wrappedValue, of: asked) {
                ConfigurationProblemLine(problem: problem)
            }
        case .choice(let choices):
            Picker(selection: Self.choice(value)) {
                Text(clash: .copy("Choose")).tag("")
                ForEach(choices, id: \.self) { Text(verbatim: words($0, of: asked)).tag($0) }
            } label: { Text(verbatim: title(of: asked)) }
            .pickerStyle(.menu)
            .accessibilityIdentifier(identifier)
        case .flag:
            Toggle(isOn: Self.flag(value)) { Text(verbatim: title(of: asked)) }
                .accessibilityIdentifier(identifier)
        case .choices, .lines, .pair, .group:
            sectionControls(asked, value: value, identifier: identifier)
        }
    }

     
     
     
    private func sectionControls(_ asked: ConfigurationNewItem.Asked, value: Binding<ConfigurationNewItem.Value>,
                                 identifier: String) -> AnyView {
        AnyView(sectionRows(asked, value: value, identifier: identifier))
    }

    @ViewBuilder
    private func sectionRows(_ asked: ConfigurationNewItem.Asked, value: Binding<ConfigurationNewItem.Value>,
                             identifier: String) -> some View {
        switch asked.control {
        case .choices(let choices):
            ForEach(choices, id: \.self) { choice in
                Toggle(isOn: Self.chosen(choice, in: value)) { Text(verbatim: words(choice, of: asked)) }
                    .accessibilityIdentifier("\(identifier).\(choice)")
            }
        case .lines:
            let lines = Self.lines(value)
            ForEach(lines.wrappedValue.indices, id: \.self) { index in
                TextField(text: Binding(get: { lines.wrappedValue.indices.contains(index) ? lines.wrappedValue[index] : "" },
                                        set: { if lines.wrappedValue.indices.contains(index) { lines.wrappedValue[index] = $0 } })) {
                    Text(verbatim: title(of: asked))
                }
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .accessibilityIdentifier("\(identifier).\(index)")
                 
                let entries = lines.wrappedValue.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                if lines.wrappedValue.indices.contains(index), !entries[index].isEmpty,
                   let problem = ConfigurationFieldValidation.problem(
                       entries[index], format: asked.field.format, path: asked.field.path, allowed: asked.field.values ?? [],
                       siblings: entries.enumerated().filter { $0.offset != index && !$0.element.isEmpty }.map(\.element)) {
                    ConfigurationProblemLine(problem: problem)
                }
            }
            Button { lines.wrappedValue.append("") } label: {
                Label { Text(clash: .copy("Add")) } icon: { Image(systemName: ClashSymbol.plus.name) }
            }
            .accessibilityIdentifier(addLineIdentifier)
        case .pair:
            let pair = Self.pair(value)
            TextField(text: Binding(get: { pair.wrappedValue.key }, set: { pair.wrappedValue.key = $0 })) {
                Text(clash: .copy("Key"))
            }
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .accessibilityIdentifier("\(identifier).key")
            TextField(text: Binding(get: { pair.wrappedValue.value }, set: { pair.wrappedValue.value = $0 })) {
                Text(clash: .copy("Value"))
            }
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .accessibilityIdentifier("\(identifier).value")
        case .group:
            ForEach(asked.children) { child in
                control(child, value: Self.child(child, of: value), identifier: "\(identifier).\(child.key)")
            }
        default:
            control(asked, value: value, identifier: identifier)
        }
    }

     

    private static func text(_ value: Binding<ConfigurationNewItem.Value>) -> Binding<String> {
        Binding(get: { if case .text(let text) = value.wrappedValue { return text }; return "" },
                set: { value.wrappedValue = .text($0) })
    }

    private static func choice(_ value: Binding<ConfigurationNewItem.Value>) -> Binding<String> {
        Binding(get: { if case .choice(let choice) = value.wrappedValue { return choice }; return "" },
                set: { value.wrappedValue = .choice($0) })
    }

    private static func flag(_ value: Binding<ConfigurationNewItem.Value>) -> Binding<Bool> {
        Binding(get: { if case .flag(let on) = value.wrappedValue { return on }; return false },
                set: { value.wrappedValue = .flag($0) })
    }

    private static func chosen(_ choice: String, in value: Binding<ConfigurationNewItem.Value>) -> Binding<Bool> {
        Binding(get: {
            if case .choices(let chosen) = value.wrappedValue { return chosen.contains(choice) }
            return false
        }, set: { on in
            var chosen: [String] = []
            if case .choices(let current) = value.wrappedValue { chosen = current }
            chosen.removeAll { $0 == choice }
            if on { chosen.append(choice) }
            value.wrappedValue = .choices(chosen)
        })
    }

    private static func lines(_ value: Binding<ConfigurationNewItem.Value>) -> Binding<[String]> {
        Binding(get: { if case .lines(let lines) = value.wrappedValue, !lines.isEmpty { return lines }; return [""] },
                set: { value.wrappedValue = .lines($0) })
    }

    private static func pair(_ value: Binding<ConfigurationNewItem.Value>) -> Binding<(key: String, value: String)> {
        Binding(get: {
            if case .pair(let key, let text) = value.wrappedValue { return (key: key, value: text) }
            return (key: "", value: "")
        }, set: { value.wrappedValue = .pair(key: $0.key, value: $0.value) })
    }

    private static func child(_ child: ConfigurationNewItem.Asked,
                              of value: Binding<ConfigurationNewItem.Value>) -> Binding<ConfigurationNewItem.Value> {
        Binding(get: {
            if case .group(let values) = value.wrappedValue, let own = values[child.key] { return own }
            return child.initialValue
        }, set: { typed in
            var values: [String: ConfigurationNewItem.Value] = [:]
            if case .group(let current) = value.wrappedValue { values = current }
            values[child.key] = typed
            value.wrappedValue = .group(values)
        })
    }
}

 
 
 
 
 
struct ConfigurationObjectItemView: View {
    @ObservedObject var session: ConfigurationEditorSession
    let location: ConfigurationListLocation
    let index: Int

    private var document: OrderedJSON { session.settingsDocument }
    private var item: OrderedJSON? {
        let items = location.items(in: document)
        return items.indices.contains(index) ? items[index] : nil
    }
    private var catalog: ConfigurationFieldCatalog? { session.catalog?.fieldCatalog }
    private var itemPath: String? {
        catalog.flatMap { ConfigurationObjectList.itemPath(location, index: index, in: document, catalog: $0) }
    }

    struct Row: Identifiable {
        let key: String
         
        let path: [String]
        let field: ConfigurationField?
        let value: OrderedJSON?
        var id: String { path.joined(separator: ".") }
    }

    struct Group: Identifiable {
        let id: String
        let title: String?
        let rows: [Row]
         
        var catalogPath: String? = nil
    }

     
     
     
    struct DrawnSection: Identifiable {
        let id: String
        let title: ClashDisplayText?
        let footer: String?
        let rows: [Row]
    }

    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

    func sections(of item: OrderedJSON) -> [DrawnSection] {
        var drawn: [DrawnSection] = []
        for group in groups(of: item) {
            if group.id.isEmpty {
                let layout = itemPath.flatMap { fieldCopy.layout(forPath: $0, locale: locale) } ?? []
                let byKey = Dictionary(group.rows.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
                for section in ConfigurationFieldCopy.arrange(group.rows.map(\.key), in: layout) {
                    drawn.append(DrawnSection(id: "item#" + section.id, title: section.title, footer: section.footer,
                                              rows: section.keys.compactMap { byKey[$0] }))
                }
            } else {
                let object = group.catalogPath.flatMap { catalog?.field(atCatalogPath: $0) }
                let words = fieldCopy.entry(for: object, locale: locale)
                drawn.append(DrawnSection(id: group.id, title: (words?.title ?? group.title).map(ClashDisplayText.verbatim),
                                          footer: words.flatMap { $0.summary.isEmpty ? nil : $0.summary }, rows: group.rows))
            }
        }
        return drawn
    }

    private func title(of row: Row) -> String {
        fieldCopy.title(for: row.field, key: row.key, locale: locale)
    }

    var body: some View {
        List {
            if let item {
                if case .object = item {
                    ForEach(sections(of: item)) { section in
                        Section {
                            ForEach(section.rows) { row in rowView(row) }
                        } header: {
                            if let title = section.title { Text(clash: title) }
                        } footer: {
                            if let footer = section.footer { Text(verbatim: footer) }
                        }
                    }
                } else {
                     
                    ClashNativeNavigationLink {
                        ConfigurationItemValueView(title: ConfigurationObjectList.title(of: item, index: index), field: nil,
                                                   value: item, document: document, save: { writeItem($0) }, useDefault: nil)
                            .configurationPushedAlertHost(session)
                    } label: {
                        ConfigurationRowLabel(title: .copy("Value"), value: .verbatim(ConfigurationObjectList.title(of: item, index: index)))
                    }
                }
            }
        }
        .navigationTitle(Text(verbatim: item.map { ConfigurationObjectList.title(of: $0, index: index) } ?? ""))
    }

     
     
     
    func groups(of item: OrderedJSON) -> [Group] {
        var groups: [Group] = []
        func collect(at path: [String], catalogPath: String?, title: String?, depth: Int) {
            var rows: [Row] = []
            var nested: [(key: String, path: [String], catalogPath: String)] = []
            let fields = catalogPath.flatMap { base in catalog.map { ConfigurationObjectList.fields(under: base, catalog: $0) } } ?? []
            var known = Set<String>()
            let node = path.isEmpty ? item : item.node(at: path)
            for field in fields {
                let key = ConfigurationSectionLayout.key(of: field)
                known.insert(key)
                let value = node?.topLevelValue(key)
                let objectOrNothing: Bool
                switch value {
                case nil, .object?: objectOrNothing = true
                default: objectOrNothing = false
                }
                if field.kind == .object, depth < 3, objectOrNothing {
                    nested.append((key, path + [key], field.path))
                } else {
                    rows.append(Row(key: key, path: path + [key], field: field, value: value))
                }
            }
            if case .object(let entries)? = node {
                for entry in entries where known.insert(entry.key).inserted {
                    rows.append(Row(key: entry.key, path: path + [entry.key], field: nil, value: entry.value))
                }
            }
            groups.append(Group(id: path.joined(separator: "."), title: title, rows: rows, catalogPath: path.isEmpty ? nil : catalogPath))
            for object in nested {
                collect(at: object.path, catalogPath: object.catalogPath, title: object.path.joined(separator: "."), depth: depth + 1)
            }
        }
        collect(at: [], catalogPath: itemPath, title: nil, depth: 0)
        return groups.filter { !$0.rows.isEmpty }
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        let isDefault = row.value == nil
        if row.path == ["type"] {
             
             
            label(row)
        } else if let field = row.field, field.kind == .objectList {
            ClashNativeNavigationLink {
                ConfigurationObjectListView(session: session, location: .inItem(location, index: index, path: row.path), title: title(of: row))
                    .configurationPushedAlertHost(session)
            } label: { label(row) }
            .accessibilityIdentifier("configuration-editor.item-key.\(row.id)")
        } else if let field = row.field, field.kind == .map {
            ClashNativeNavigationLink {
                ConfigurationItemMapView(session: session, location: location, index: index, path: row.path, title: title(of: row))
                    .configurationPushedAlertHost(session)
            } label: { label(row) }
            .accessibilityIdentifier("configuration-editor.item-key.\(row.id)")
        } else if let field = row.field, ConfigurationSectionLayout.isInline(field, value: row.value, in: document),
                  let draft = ConfigurationFieldDraft(field: field, value: row.value, in: document) {
            ConfigurationInlineFieldRow(title: title(of: row), draft: draft, identifier: "configuration-editor.item-key.inline.\(row.id)",
                                        save: { writeField(row.path, $0) }, isDefault: isDefault, defaultText: field.defaultText,
                                        useDefault: isDefault ? nil : { writeField(row.path, nil) }, field: field)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) { useDefault(row) }
        } else {
            ClashNativeNavigationLink {
                ConfigurationItemValueView(title: title(of: row), field: row.field, value: row.value, document: document,
                                           save: { writeField(row.path, $0) },
                                           useDefault: isDefault ? nil : { writeField(row.path, nil) })
                    .configurationPushedAlertHost(session)
            } label: { label(row) }
            .accessibilityIdentifier("configuration-editor.item-key.\(row.id)")
            .swipeActions(edge: .trailing, allowsFullSwipe: false) { useDefault(row) }
        }
    }

    @ViewBuilder
    private func useDefault(_ row: Row) -> some View {
        if row.value != nil, row.key != "type", row.key != "name" {
            Button { writeField(row.path, nil) } label: { ClashSwipeLabel(.copy("Use Default"), symbol: .arrowUturnBackward) }
                .tint(.orange)
                .accessibilityIdentifier("configuration-editor.item-key.use-default")
        }
    }

    private func label(_ row: Row) -> some View {
         
         
         
        ConfigurationRowLabel(title: .verbatim(title(of: row)),
                              value: ConfigurationValueWords.summary(row.value, field: row.field, locale: locale,
                                                                     copy: fieldCopy),
                              isDefault: row.value == nil)
    }

     
     
     
     
     
    private func writeField(_ path: [String], _ value: OrderedJSON?) {
        session.edit(reading: Self.writing(location, index, pressedOn: session.settingsDocument, read: session.settingsAsRead) {
            $0.setting(path: path, to: value)
        })
    }

    private func writeItem(_ value: OrderedJSON) {
        session.edit(reading: Self.writing(location, index, pressedOn: session.settingsDocument, read: session.settingsAsRead) { _ in value })
    }

     
     
     
     
     
     
     
    static func writing(_ location: ConfigurationListLocation, _ index: Int, pressedOn shown: OrderedJSON,
                        read: OrderedJSON? = nil,
                        _ change: @escaping (OrderedJSON) -> OrderedJSON) -> ConfigurationEditorSession.SettingsChange {
        func name(in document: OrderedJSON?) -> OrderedJSON? {
            guard let document else { return nil }
            let items = location.items(in: document)
            return items.indices.contains(index) ? items[index].topLevelValue("name") : nil
        }
        let names = [name(in: shown), name(in: read)].compactMap { $0 }
        return { document in
            let items = location.items(in: document)
            let position: Int?
            if !names.isEmpty {
                 
                 
                 
                if items.indices.contains(index), let there = items[index].topLevelValue("name"), names.contains(there) {
                    position = index
                } else {
                    position = names.lazy.compactMap { name in items.firstIndex { $0.topLevelValue("name") == name } }.first
                }
            } else {
                position = items.indices.contains(index) ? index : nil
            }
            guard let position else { throw ConfigurationEditorSession.SettingsChangeLost() }
            var next = items
            next[position] = change(items[position])
            return [location.edit(writing: next, in: document)]
        }
    }
}

 
 
 
struct ConfigurationItemMapView: View {
    @ObservedObject var session: ConfigurationEditorSession
    let location: ConfigurationListLocation
    let index: Int
     
    let path: [String]
    let title: String
    @State private var adding = false
    @Environment(\.configurationFieldCopy) private var fieldCopy

    private var document: OrderedJSON { session.settingsDocument }
    private var steps: [ConfigurationDocumentStep] { location.steps + [.index(index)] + path.map(ConfigurationDocumentStep.key) }
    private var entries: [(key: String, value: OrderedJSON)] {
        let items = location.items(in: document)
        guard items.indices.contains(index), case .object(let entries)? = items[index].node(at: path) else { return [] }
        return entries
    }
    private var mapField: ConfigurationField? { session.catalog?.field(at: steps, in: document) }
    private func entryField(_ key: String) -> ConfigurationField? {
        session.catalog?.field(at: steps + [.key(key)], in: document)
    }

    var body: some View {
        let entries = entries
        List {
            Section {
                ForEach(entries.indices, id: \.self) { position in
                    let entry = entries[position]
                    ClashNativeNavigationLink {
                        ConfigurationItemValueView(title: entry.key, field: entryField(entry.key), value: entry.value, document: document,
                                                   save: { write(entry.key, $0) }, useDefault: nil)
                            .configurationPushedAlertHost(session)
                    } label: {
                        ConfigurationRowLabel(title: .verbatim(entry.key),
                                              value: ConfigurationValueWords.summary(entry.value, field: entryField(entry.key),
                                                                                     locale: AppPreferences.language().locale,
                                                                                     copy: fieldCopy))
                    }
                }
                .onDelete { offsets in
                    for key in offsets.map({ entries[$0].key }) { write(key, nil) }
                }
                if entries.isEmpty {
                    Button { adding = true } label: {
                        Label { Text(clash: .copy("Add")) } icon: { Image(systemName: ClashSymbol.plus.name) }
                    }
                    .accessibilityIdentifier("configuration-editor.item-map.add-first")
                }
            }
        }
        .navigationTitle(Text(verbatim: title))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ControlGroup {
                    Button { adding = true } label: { Image(systemName: ClashSymbol.plus.name) }
                        .accessibilityLabel(Text(clash: .copy("Add")))
                        .accessibilityIdentifier("configuration-editor.item-map.add")
                }
                .clashReaderControlGroupStyle()
            }
        }
        .disabled(session.isSaving)
        .clashSheet(isPresented: $adding) {
            ConfigurationNewKeyForm(suggestions: mapField?.key?.values ?? [], taken: Set(entries.map(\.key)), document: document,
                                    entryField: entryField("\u{1F}"), keyFormat: mapField?.key?.format) { key, value in
                write(key, value)
            }
            .clashModalPresentation(.form)
        }
    }

     
    private func write(_ key: String, _ value: OrderedJSON?) {
        let items = location.items(in: session.settingsDocument)
        guard items.indices.contains(index) else { return }
        var next = items
        next[index] = items[index].setting(path: path + [key], to: value)
        session.edit([location.edit(writing: next, in: session.settingsDocument)])
    }
}

 
 
struct ConfigurationItemValueView: View {
    let title: String
    let field: ConfigurationField?
    let value: OrderedJSON?
    let document: OrderedJSON
    let save: (OrderedJSON) -> Void
    let useDefault: (() -> Void)?
    @State private var draft: ConfigurationDraft?
    @State private var opened: ConfigurationDraft?
     
    @State private var handed: OrderedJSON?
    @State private var usedDefault = false
    @StateObject private var dismiss = ClashDismissHandle()
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

    var body: some View {
        let words = fieldCopy.entry(for: field, locale: locale)
        Form {
            if let draft = Binding($draft) {
                if let presets = words?.presets, !presets.isEmpty, field?.format != .ipPort {
                    ConfigurationFieldPresets(draft: draft, presets: presets, defaultValue: field?.defaultText)
                }
                 
                 
                ConfigurationDraftEditor(draft: draft, choices: nil, field: field)
            } else if let value {
                Section {
                    Text(verbatim: value.serialized()).font(.footnote.monospaced()).textSelection(.enabled)
                } footer: {
                    Text(clash: .copy("Change this one in the source."))
                }
            }
            if let useDefault {
                Section {
                    Button {
                        usedDefault = true
                        useDefault()
                        dismiss()
                    } label: { Text(clash: .copy("Use Default")) }
                    .accessibilityIdentifier("configuration-editor.item-value.use-default")
                }
            }
             
             
            ConfigurationFieldAbout(summary: draft?.isList == true ? nil : words?.summary,
                                    key: field.map(ConfigurationSectionLayout.key(of:)))
        }
        .configurationKnownValueSearch(for: field)
        .navigationTitle(Text(verbatim: title))
        .clashCapturesDismiss(dismiss)
        .onAppear {
            guard draft == nil else { return }
            draft = ConfigurationDraft.make(value, field: field, in: document)
                ?? (value == nil && field == nil ? .plain(ConfigurationValueDraft(kind: .text)) : nil)
            opened = draft
        }
         
         
         
        .onDisappear {
            guard !usedDefault, let changed = ConfigurationDraft.handedOn(draft, since: &opened, expected: handed ?? value) else { return }
            handed = changed
            save(changed)
        }
    }
}
#endif
