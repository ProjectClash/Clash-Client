import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
 
 
 

 
struct ClashMacProblemLine: View {
    let problem: ConfigurationFieldProblem

    var body: some View {
        Text(clash: problem.words)
            .foregroundStyle(.red)
            .accessibilityIdentifier("configuration-center.section.field.problem")
    }
}

 

 
 
 
 
 
 
 
 
 
struct ClashMacHostPortEditor: View {
    @Binding var draft: ClashMacFieldDraft
    let title: Text
    @State private var entry: ConfigurationHostPortEntry?
     
    @State private var showsParts = false

    static let customTag = "\u{1F}custom"

    private var choices: [ConfigurationFormatPreset]? { ConfigurationFormatPresets.addressChoices(path: draft.path) }
    private var listens: Bool { ConfigurationFormatPresets.isListenAddress(path: draft.path) }

     
     
     
     
    private var current: ConfigurationHostPortEntry { entry ?? ConfigurationHostPortEntry(draft.text, listens: listens) }

     
     
    static func choice(for text: String, in choices: [ConfigurationFormatPreset]) -> String {
        let value = text.trimmingCharacters(in: .whitespaces)
        if value.isEmpty { return choices.first { $0.value == nil }?.id ?? customTag }
        let written = choices.compactMap(\.value)
        guard let match = ConfigurationChoiceMatch.addressChoice(for: value, in: written)
                ?? ConfigurationChoiceMatch.choice(for: value, in: written) else { return customTag }
        return choices.first { $0.value == match }?.id ?? customTag
    }

    var body: some View {
        Group {
            if let choices {
                Picker(selection: Binding(get: { selectedTag(in: choices) }, set: { pick($0, in: choices) })) {
                    ForEach(choices) { choice in Text(clash: choice.label).tag(choice.id) }
                    Text(clash: .copy("Custom")).tag(Self.customTag)
                } label: { title }
                 
                .labelsHidden()
                .pickerStyle(.radioGroup)
                .accessibilityIdentifier("configuration-center.section.field.address.choice")
                if showsParts || selectedTag(in: choices) == Self.customTag { parts }
            } else {
                parts
            }
        }
        .onAppear {
            guard entry == nil else { return }
            let parts = ConfigurationHostPortEntry(draft.text, listens: listens)
            entry = parts
             
             
             
            if draft.problem != nil, parts.composed != nil { Self.apply(parts, to: &draft) }
            if let choices { showsParts = Self.choice(for: draft.text, in: choices) == Self.customTag }
        }
    }

     
     
    private func selectedTag(in choices: [ConfigurationFormatPreset]) -> String {
        draft.partsProblem == nil ? Self.choice(for: draft.text, in: choices) : Self.customTag
    }

    @ViewBuilder
    private var parts: some View {
        if listens {
            Picker(selection: part(\.hostChoice)) {
                Text(clash: .copy("This Device (127.0.0.1)")).tag(ConfigurationHostPortEntry.HostChoice.thisDevice)
                Text(clash: .copy("All Networks (0.0.0.0)")).tag(ConfigurationHostPortEntry.HostChoice.allNetworks)
                Text(clash: .copy("Other Address")).tag(ConfigurationHostPortEntry.HostChoice.custom)
            } label: { Text(clash: .copy("Address")) }
            .pickerStyle(.menu)
            .accessibilityIdentifier("configuration-center.section.field.address.host-choice")
             
            if current.hostChoice == .custom { hostField(title: .copy("Other Address"), example: "192.168.1.2") }
        } else {
            hostField(title: .copy("Address"), example: "example.com")
        }
        TextField(text: part(\.port), prompt: Text(verbatim: ConfigurationFormatPresets.listenPort(path: draft.path) ?? "443")) {
            Text(clash: .copy("Port"))
        }
        .accessibilityIdentifier("configuration-center.section.field.address.port")
    }

    private func hostField(title: ClashDisplayText, example: String) -> some View {
        TextField(text: part(\.customHost), prompt: Text(verbatim: example)) { Text(clash: title) }
            .disableAutocorrection(true)
            .accessibilityIdentifier("configuration-center.section.field.address.host")
    }

     
     
    private func part<Value>(_ keyPath: WritableKeyPath<ConfigurationHostPortEntry, Value>) -> Binding<Value> {
        Binding(get: { current[keyPath: keyPath] }, set: { value in
            var next = current
            next[keyPath: keyPath] = value
            entry = next
            Self.apply(next, to: &draft)
        })
    }

     
     
    static func apply(_ entry: ConfigurationHostPortEntry, to draft: inout ClashMacFieldDraft) {
        if let composed = entry.composed {
            draft.text = composed
            draft.partsProblem = nil
        } else {
            draft.partsProblem = entry.problem(path: draft.path) ?? .address
        }
    }

     
     
    private func pick(_ tag: String, in choices: [ConfigurationFormatPreset]) {
        guard tag != Self.customTag else {
            showsParts = true
            return
        }
        guard let choice = choices.first(where: { $0.id == tag }) else { return }
        showsParts = false
        draft.text = choice.value ?? ""
        draft.partsProblem = nil
        entry = ConfigurationHostPortEntry(choice.value, listens: listens)
    }
}

extension ConfigurationFormatPresets {
     
     
    static func listenPort(path: String) -> String? {
        addressChoices(path: path)?.compactMap(\.value).first.flatMap { ConfigurationFieldValidation.splitHostPort($0)?.port }
    }
}

 

 
 
 
 
struct ClashMacSecretField: View {
    @Binding var draft: ClashMacFieldDraft
    let title: Text
    let prompt: String?
    let secure: Bool
    @State private var revealed = false

    private var generates: Bool { !draft.path.hasPrefix("proxies") }

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                field
                if secure {
                    Button { revealed.toggle() } label: { Text(clash: .copy(revealed ? "Hide" : "Show")) }
                        .accessibilityIdentifier("configuration-center.section.field.reveal")
                }
                if generates {
                    Button(action: generate) { Text(clash: .copy("Generate")) }
                        .accessibilityIdentifier("configuration-center.section.field.generate")
                }
            }
        } label: { title }
    }

    @ViewBuilder
    private var field: some View {
        if secure && !revealed {
            SecureField(text: $draft.text, prompt: prompt.map { Text(verbatim: $0) }) { title }
                .labelsHidden()
                .accessibilityIdentifier("configuration-center.section.field.secret")
        } else {
            TextField(text: $draft.text, prompt: prompt.map { Text(verbatim: $0) }) { title }
                .labelsHidden()
                .disableAutocorrection(true)
                .accessibilityIdentifier("configuration-center.section.field.text")
        }
    }

    private func generate() {
        draft.text = secure ? ConfigurationFieldValidation.generatedPassword() : ConfigurationFieldValidation.generatedUUID()
        draft.partsProblem = nil
    }
}

 

 
 
 
 
struct ClashMacDurationEditor: View {
    @Binding var draft: ClashMacFieldDraft
    let min: Double?
    let max: Double?
    let fieldUnit: String
    let title: Text
    @State private var entry: ConfigurationDurationEntry?
    @Environment(\.locale) private var locale

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                TextField(text: amount) { title }
                    .labelsHidden()
                    .frame(minWidth: 60)
                    .accessibilityIdentifier("configuration-center.section.field.duration.amount")
                Picker(selection: unit) {
                    ForEach(current?.units ?? [], id: \.self) { unit in
                        Text(clash: ConfigurationFormatWords.unitName(unit)).tag(unit)
                    }
                } label: { EmptyView() }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .accessibilityIdentifier("configuration-center.section.field.duration.unit")
            }
        } label: {
            title
            if let range = Self.range(min: min, max: max, unit: fieldUnit, locale: locale) { Text(verbatim: range) }
        }
        .onAppear { if entry == nil { entry = ConfigurationDurationEntry(stored: draft.text, fieldUnit: fieldUnit) } }
    }

    private var current: ConfigurationDurationEntry? { entry ?? ConfigurationDurationEntry(stored: draft.text, fieldUnit: fieldUnit) }

    private var amount: Binding<String> {
        Binding(get: { current?.amount ?? draft.text }, set: { text in update { $0.amount = text } })
    }

    private var unit: Binding<ConfigurationDurationEntry.Unit> {
        Binding(get: { current?.unit ?? .seconds }, set: { unit in update { $0.unit = unit } })
    }

    private func update(_ change: (inout ConfigurationDurationEntry) -> Void) {
        guard var next = current else { return }
        change(&next)
        entry = next
        Self.apply(next, to: &draft)
    }

     
     
     
    static func apply(_ entry: ConfigurationDurationEntry, to draft: inout ClashMacFieldDraft) {
        if let stored = entry.stored {
            draft.text = stored
            draft.partsProblem = nil
        } else {
            draft.partsProblem = .notANumber
        }
    }

     
    static func range(min: Double?, max: Double?, unit: String, locale: Locale) -> String? {
        func words(_ bound: Double) -> String {
            ConfigurationFormatWords.number(ConfigurationFieldValidation.plain(bound), unit: unit).resolved(locale: locale)
        }
        switch (min, max) {
        case let (min?, max?): return words(min) + "–" + words(max)
        case let (min?, nil) where min != 0: return "≥ " + words(min)
        case let (nil, max?): return "≤ " + words(max)
        default: return nil
        }
    }
}

 

 
 
 
 
 
 
 
struct ClashMacTimeMenuRow<Label: View>: View {
    let field: ConfigurationField
    let unit: String
    let value: OrderedJSON?
     
    let offersDefault: Bool
    let defaultLine: ClashDisplayText
    let identifier: String
     
    let write: (OrderedJSON?) -> Void
     
    let custom: () -> Void
    @ViewBuilder let label: () -> Label
    @Environment(\.locale) private var locale

    private static var defaultTag: String { "\u{1F}default" }
    private static var customTag: String { "\u{1F}custom" }

     
     
    static func unit(of control: ClashMacFieldControl?, field: ConfigurationField?) -> String? {
        guard case .number(_, _, let unit?, _)? = control, let field,
              !ConfigurationFormatPresets.common(path: field.path, unit: unit).isEmpty else { return nil }
        return unit
    }

    private var written: String? {
        switch value {
        case .string(let text)?: return text.trimmingCharacters(in: .whitespaces)
        case .scalar(let token)?: return token == "null" ? nil : token.trimmingCharacters(in: .whitespaces)
        default: return nil
        }
    }

     
    private var entries: [ConfigurationFormatPreset] {
        let presets = ConfigurationFormatPresets.common(path: field.path, unit: unit)
        guard let written, !presets.contains(where: { $0.value == written }) else { return presets }
        return presets + [ConfigurationFormatPreset(value: written, label: ConfigurationValueWords.number(written, unit: unit, locale: locale))]
    }

    var body: some View {
        Picker(selection: Binding(get: { value == nil ? Self.defaultTag : written ?? Self.defaultTag }, set: { tag in
            switch tag {
            case Self.defaultTag: if value != nil, offersDefault { write(nil) }
            case Self.customTag: custom()
            default: if tag != written { write(.scalar(tag)) }
            }
        })) {
            if value == nil || offersDefault {
                Text(clash: defaultLine).tag(Self.defaultTag)
            }
            ForEach(entries) { preset in Text(clash: preset.label).tag(preset.value ?? "") }
            Divider()
            Text(clash: .copy("Custom…")).tag(Self.customTag)
        } label: {
            label()
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier(identifier)
    }
}

 

 
 
 
 
 
 
struct ClashMacAddressMenuRow<Label: View>: View {
    let path: String
    let value: OrderedJSON?
     
    let offersOff: Bool
    let identifier: String
     
    let write: (OrderedJSON?) -> Void
     
    let custom: () -> Void
    @ViewBuilder let label: () -> Label

    private static var customTag: String { ClashMacHostPortEditor.customTag }

     
    static func applies(to field: ConfigurationField?, control: ClashMacFieldControl?) -> Bool {
        guard case .text(.ipPort?, _)? = control, let field else { return false }
        return ConfigurationFormatPresets.addressChoices(path: field.path) != nil
    }

     
     
    static func listsOff(written: String, offersOff: Bool) -> Bool { written.isEmpty || offersOff }

     
     
    static func offWrites(written: String, offersOff: Bool) -> Bool { !written.isEmpty && offersOff }

    private var written: String {
        switch value {
        case .string(let text)?: return text.trimmingCharacters(in: .whitespaces)
        case .scalar(let token)?: return token == "null" ? "" : token.trimmingCharacters(in: .whitespaces)
        default: return ""
        }
    }

    var body: some View {
        let choices = ConfigurationFormatPresets.addressChoices(path: path) ?? []
        let off = choices.first { $0.value == nil }
         
        let shown = ClashMacHostPortEditor.choice(for: written, in: choices)
        Picker(selection: Binding(get: { shown == Self.customTag ? written : shown }, set: { tag in
            if tag == Self.customTag { return custom() }
            if tag == off?.id {
                if Self.offWrites(written: written, offersOff: offersOff) { write(nil) }
                return
            }
            guard let picked = choices.first(where: { $0.id == tag })?.value, picked != written else { return }
            write(.string(picked))
        })) {
            ForEach(choices) { choice in
                if choice.value != nil || Self.listsOff(written: written, offersOff: offersOff) {
                    Text(clash: choice.label).tag(choice.id)
                }
            }
             
            if shown == Self.customTag, !written.isEmpty {
                Text(verbatim: written).tag(written)
            }
            Divider()
            Text(clash: .copy("Custom…")).tag(Self.customTag)
        } label: {
            label()
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier(identifier)
    }
}
