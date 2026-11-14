import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
 
 
public struct ClashMacSettingsKeyRows: View {
    let keys: [String]
     
     
    let saysScope: Bool
    let actions: ClashMacSettingsSectionActions
    @State private var document: ClashMacSettingsSectionDocument?
     
    @State private var loadFailure: String?
     
     
     
    @State private var writeFailures: [String: String] = [:]
     
     
     
     
    @State private var writes = ClashMacSectionWrites()
    @State private var editing: ClashMacKeyEdit?
     
     
    @State private var runsOver: ClashMacRunsOver?
    @State private var reads = 0
    @Environment(\.configurationFieldCopy) private var copy
    @Environment(\.locale) private var locale

    public init(keys: [String], saysScope: Bool = false, actions: ClashMacSettingsSectionActions) {
        self.keys = keys
        self.saysScope = saysScope
        self.actions = actions
    }

     
    static let customTag = "\u{1F}custom"

    public var body: some View {
        Group {
            if let document {
                ForEach(keys, id: \.self) { key in
                    row(key, in: document)
                    if let reason = writeFailures[key] { ClashMacRowFailure(message: reason) }
                }
                 
                 
                 
                if saysScope, let scope = document.scope {
                    Text(clash: scope).font(.footnote).foregroundStyle(.secondary)
                }
            } else if loadFailure == nil {
                ProgressView().controlSize(.small)
            }
            if let loadFailure {
                Text(verbatim: loadFailure).foregroundStyle(.red)
            }
        }
        .task { await reload() }
        .task(id: reads) { if reads > 0, let read = actions.runsOver { runsOver = await read() } }
        .sheet(item: $editing) { edit in
            ClashMacValueEditSheet(edit: edit, save: { value in
                request([.set(path: edit.path, to: value)])
            }, useDefault: edit.removable ? { request([.remove(path: edit.path)]) } : nil, geoValues: actions.geoValues)
        }
    }

    @ViewBuilder
    private func row(_ key: String, in document: ClashMacSettingsSectionDocument) -> some View {
        let field = document.field(at: [key])
        let value = document.running.topLevelValue(key)
        let title = copy.title(for: field, key: key, locale: locale)
         
        let note = runsOver?([key], field, false, document.running)
        let presets = copy.entry(for: field, locale: locale)?.presets ?? []
        let edit = ClashMacKeyEdit(path: [key], value: value, platformReason: nil, choices: document.choices[key],
                                  control: field.flatMap { document.control(for: $0) },
                                  removable: value != nil && document.removes([key]), isDefault: value == nil, field: field)
        if key == "bind-address", !presets.isEmpty {
             
             
            let written = Self.token(value)
            let shown = Self.choice(for: written ?? field?.defaultText, in: presets.map(\.value))
            Picker(selection: Binding(get: { shown == Self.customTag ? (written ?? Self.customTag) : shown }, set: { picked in
                if picked == Self.customTag { editing = edit; return }
                guard picked != written, presets.contains(where: { $0.value == picked }) else { return }
                request([.set(path: [key], to: .string(picked))])
            })) {
                ForEach(presets, id: \.value) { Text(verbatim: $0.label).tag($0.value) }
                 
                if shown == Self.customTag, let written { Text(verbatim: written).tag(written) }
                Divider()
                Text(clash: .copy("Custom…")).tag(Self.customTag)
            } label: {
                Text(verbatim: title)
                if let note { Text(clash: note).accessibilityIdentifier("configuration-center.lan-share.runs-over") }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("configuration-center.lan-share.bind-address")
        } else {
            LabeledContent {
                Button { editing = edit } label: {
                    Text(clash: ConfigurationValueWords.summary(value, field: field, locale: locale, copy: copy))
                }
                .accessibilityIdentifier("configuration-center.lan-share.key")
            } label: {
                Text(verbatim: title)
                if let note { Text(clash: note).accessibilityIdentifier("configuration-center.lan-share.runs-over") }
            }
        }
    }

     
     
    static func choice(for value: String?, in choices: [String]) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return choices.first ?? customTag }
        return choices.first { $0.lowercased() == value.lowercased() } ?? customTag
    }

    private static func token(_ value: OrderedJSON?) -> String? {
        switch value {
        case .string(let text)?: return text
        case .scalar(let token)?: return token == "null" ? nil : token
        default: return nil
        }
    }

     
    private func request(_ edits: [ConfigurationPageEdit]) {
        guard !edits.isEmpty else { return }
        perform(edits)
    }

     
     
    private func perform(_ edits: [ConfigurationPageEdit]) {
        let now = writes.take(.edits(edits))
        document?.shownEdits = writes.shownEdits
        guard let now else { return }
        Task { await write(from: now) }
    }

    private func write(from first: ClashMacSectionWrites.Step) async {
        var step: ClashMacSectionWrites.Step? = first
        while case .edits(let edits)? = step {
            await save(edits)
            await reload()
            step = writes.finish()
            document?.shownEdits = writes.shownEdits
        }
    }

    private func save(_ edits: [ConfigurationPageEdit]) async {
         
        let keys = edits.compactMap(\.writtenPath.first)
        do {
            try await actions.save(edits, document?.scheme)
            for key in keys { writeFailures[key] = nil }
        } catch is CancellationError {
        } catch {
            for key in keys { writeFailures[key] = ClashErrorCopy.message(error, locale: locale) }
        }
    }

    private func reload() async {
        do {
            var read = try await actions.load(.general)
            read.shownEdits = writes.shownEdits
            document = read
            loadFailure = nil
            reads += 1
        } catch is CancellationError {
        } catch {
            loadFailure = ClashErrorCopy.message(error, locale: locale)
        }
    }
}
