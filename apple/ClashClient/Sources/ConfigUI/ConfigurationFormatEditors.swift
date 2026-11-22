import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
 
 
 
 

enum ConfigurationFormatEditors {
     
     
    static func shapes(_ format: ConfigurationFieldFormat?) -> Bool {
        switch format {
        case nil, .text?, .unrecognised?: return false
        default: return true
        }
    }

#if os(iOS)
     
    static func keyboard(for format: ConfigurationFieldFormat?) -> UIKeyboardType {
        switch format {
        case .url?, .dnsServer?: return .URL
        case .ip?, .cidr?, .ipPort?, .portRange?: return .numbersAndPunctuation
        default: return .asciiCapable
        }
    }

     
    static func numberKeyboard(min: Double?, text: String, defaultText: String?) -> UIKeyboardType {
        if (min ?? 0) < 0 { return .numbersAndPunctuation }
        if text.contains(".") || defaultText?.contains(".") == true { return .decimalPad }
        return .numberPad
    }
#endif
}

 
struct ConfigurationProblemLine: View {
    let problem: ConfigurationFieldProblem

    var body: some View {
        Text(clash: problem.words)
            .foregroundStyle(.red)
            .accessibilityIdentifier("configuration-editor.value.problem")
    }
}

 
 
 
 
struct ConfigurationTypedEntry: Equatable {
    private(set) var typed: String
     
     
    private(set) var baseline: String
    private(set) var problem: ConfigurationFieldProblem?

    init(text: String) {
        typed = text
        baseline = text
    }

     
    mutating func type(_ text: String, check: (String) -> ConfigurationFieldProblem?) -> String {
        typed = text
        problem = check(text)
        return problem == nil ? text : baseline
    }

     
    mutating func picked(_ text: String) {
        typed = text
        baseline = text
        problem = nil
    }
}

 

 
 
 
 
struct ConfigurationFormatEditor: View {
    @Binding var draft: ConfigurationFieldDraft

    var body: some View {
        switch draft.format {
        case .ipPort?: ConfigurationHostPortEditor(draft: $draft)
        case .password?: ConfigurationShapedTextEditor(draft: $draft, generator: generates ? .password : nil)
        case .uuid?: ConfigurationShapedTextEditor(draft: $draft, generator: generates ? .uuid : nil)
        default: ConfigurationShapedTextEditor(draft: $draft)
        }
    }

     
     
    private var generates: Bool { !draft.path.hasPrefix("proxies") }
}

 
 
 
 
struct ConfigurationShapedTextEditor: View {
    enum Generator { case password, uuid }

    @Binding var draft: ConfigurationFieldDraft
    var generator: Generator? = nil
    @State private var entry: ConfigurationTypedEntry?
     
     
     
    @State private var handed: String?

    var body: some View {
        Section {
            HStack {
                field
                if let generator {
                    Button { generate(generator) } label: { Text(clash: .copy("Generate")) }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("configuration-editor.value.generate")
                }
            }
        } footer: {
            if let problem = entry?.problem {
                ConfigurationProblemLine(problem: problem)
            }
        }
        .onAppear {
            guard entry == nil else { return }
            entry = ConfigurationTypedEntry(text: draft.text)
            handed = draft.text
        }
         
         
        .onChange(of: draft.text) { text in
            guard text != handed else { return }
            entry = ConfigurationTypedEntry(text: text)
            handed = text
        }
    }

    private var typed: Binding<String> {
        Binding(get: { entry?.typed ?? draft.text }, set: { text in
            var next = entry ?? ConfigurationTypedEntry(text: draft.text)
            let written = next.type(text) { draft.problem(typing: $0) }
            entry = next
            if draft.text != written {
                handed = written
                draft.text = written
            }
        })
    }

    private var prompt: Text? {
        ConfigurationFieldExamples.example(for: draft.format).map { Text(clash: .format("For example %@", [$0])) }
    }

    @ViewBuilder
    private var field: some View {
        TextField(text: typed, prompt: prompt) { Text(clash: .copy("Value")) }
            .autocorrectionDisabled()
#if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(ConfigurationFormatEditors.keyboard(for: draft.format))
#endif
            .accessibilityIdentifier("configuration-editor.value.text")
    }

    private func generate(_ generator: Generator) {
        let made: String
        switch generator {
        case .password: made = ConfigurationFieldValidation.generatedPassword()
        case .uuid: made = ConfigurationFieldValidation.generatedUUID()
        }
        var next = entry ?? ConfigurationTypedEntry(text: draft.text)
        next.picked(made)
        entry = next
        handed = made
        draft.text = made
    }
}

 

 
 
 
 
 
 
struct ConfigurationHostPortEditor: View {
    @Binding var draft: ConfigurationFieldDraft
     
    var startsOnCustom = false
    @State private var entry: ConfigurationHostPortEntry?
     
     
    @State private var choosesCustom = false
     
     
     
    @State private var typedInParts = false
     
     
    @State private var baseline = ""
    @State private var edited = false
     
     
    @State private var handed: String?

    static let customTag = "\u{1F}custom"

    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

     
     
    private var choices: [ConfigurationFormatPreset]? {
        ConfigurationFormatPresets.addressChoices(path: draft.path, copy: fieldCopy, language: .init(locale: locale))
    }
    private var listens: Bool { ConfigurationFormatPresets.isListenAddress(path: draft.path) }

     
     
    static func choice(for text: String, in choices: [ConfigurationFormatPreset]) -> String {
        let value = text.trimmingCharacters(in: .whitespaces)
        if value.isEmpty { return choices.first { $0.value == nil }?.id ?? customTag }
        let written = choices.compactMap(\.value)
        guard let match = ConfigurationChoiceMatch.addressChoice(for: value, in: written) else { return customTag }
        return choices.first { $0.value == match }?.id ?? customTag
    }

     
     
     
    static func choosesCustomOnOpen(text: String, in choices: [ConfigurationFormatPreset], startsOnCustom: Bool) -> Bool {
        startsOnCustom || choice(for: text, in: choices) == customTag
    }

     
     
    static func selection(for text: String, in choices: [ConfigurationFormatPreset],
                          choosesCustom: Bool, typedInParts: Bool) -> String {
        if choosesCustom && !typedInParts { return customTag }
        return choice(for: text, in: choices)
    }

     
    private func partsEntry(for text: String) -> ConfigurationHostPortEntry {
        ConfigurationHostPortEntry(text, listens: listens)
    }

    var body: some View {
        Group {
            if let choices {
                let selected = Self.selection(for: draft.text, in: choices, choosesCustom: choosesCustom, typedInParts: typedInParts)
                Section {
                    Picker(selection: Binding(get: { selected }, set: { pick($0, in: choices) })) {
                        ForEach(choices) { choice in Text(clash: choice.label).tag(choice.id) }
                        Text(clash: .copy("Custom")).tag(Self.customTag)
                    } label: { EmptyView() }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .accessibilityIdentifier("configuration-editor.value.address.choice")
                }
                if choosesCustom || selected == Self.customTag { parts }
            } else {
                parts
            }
        }
        .onAppear {
            guard entry == nil else { return }
            take(draft.text)
            if let choices {
                choosesCustom = Self.choosesCustomOnOpen(text: draft.text, in: choices, startsOnCustom: startsOnCustom)
            }
        }
        .onChange(of: draft.text) { text in
            guard text != handed else { return }
            take(text)
        }
    }

     
    private func take(_ text: String) {
        entry = partsEntry(for: text)
        baseline = text
        handed = text
        edited = false
        typedInParts = false
        if let choices { choosesCustom = Self.choice(for: text, in: choices) == Self.customTag }
    }

    private var parts: some View {
        Section {
            if listens {
                Picker(selection: part(\.hostChoice)) {
                    Text(clash: .copy("This Device (127.0.0.1)")).tag(ConfigurationHostPortEntry.HostChoice.thisDevice)
                    Text(clash: .copy("All Networks (0.0.0.0)")).tag(ConfigurationHostPortEntry.HostChoice.allNetworks)
                    Text(clash: .copy("Other Address")).tag(ConfigurationHostPortEntry.HostChoice.custom)
                } label: { Text(clash: .copy("Address")) }
                .pickerStyle(.menu)
                .accessibilityIdentifier("configuration-editor.value.address.host-choice")
                if entry?.hostChoice == .custom { hostField(example: "192.168.1.2") }
            } else {
                hostField(example: "example.com")
            }
            HStack {
                Text(clash: .copy("Port"))
                Spacer(minLength: 12)
                TextField(text: part(\.port), prompt: Text(verbatim: "9090")) { Text(clash: .copy("Port")) }
                    .multilineTextAlignment(.trailing)
#if os(iOS)
                    .keyboardType(.numberPad)
#endif
                    .accessibilityIdentifier("configuration-editor.value.address.port")
            }
        } footer: {
            if edited, let problem = entry?.problem(path: draft.path) {
                ConfigurationProblemLine(problem: problem)
            }
        }
    }

    private func hostField(example: String) -> some View {
        HStack {
            Text(clash: .copy("Address"))
            Spacer(minLength: 12)
            TextField(text: part(\.customHost), prompt: Text(clash: .format("For example %@", [example]))) {
                Text(clash: .copy("Address"))
            }
            .multilineTextAlignment(.trailing)
            .autocorrectionDisabled()
#if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(listens ? .numbersAndPunctuation : .URL)
#endif
            .accessibilityIdentifier("configuration-editor.value.address.host")
        }
    }

     
     
    private func part<Value>(_ keyPath: WritableKeyPath<ConfigurationHostPortEntry, Value>) -> Binding<Value> {
        Binding(get: { (entry ?? partsEntry(for: draft.text))[keyPath: keyPath] }, set: { value in
            var next = entry ?? partsEntry(for: draft.text)
            next[keyPath: keyPath] = value
            entry = next
            edited = true
            typedInParts = true
            let written = Self.written(next, baseline: baseline)
            if draft.text != written {
                handed = written
                draft.text = written
            }
        })
    }

     
     
    static func written(_ entry: ConfigurationHostPortEntry, baseline: String) -> String {
        entry.composed ?? baseline
    }

    private func pick(_ tag: String, in choices: [ConfigurationFormatPreset]) {
        guard tag != Self.customTag else {
            choosesCustom = true
            typedInParts = false
            return
        }
        guard let choice = choices.first(where: { $0.id == tag }) else { return }
        choosesCustom = false
        typedInParts = false
        edited = false
        let value = choice.value ?? ""
        handed = value
        draft.text = value
        baseline = value
        entry = partsEntry(for: value)
    }
}

 

 
 
struct ConfigurationNumberEditor: View {
    @Binding var draft: ConfigurationFieldDraft
    let min: Double?
    let max: Double?
    let unit: String?
    var defaultText: String? = nil
    @State private var entry: ConfigurationTypedEntry?
     
     
    @State private var handed: String?

    var body: some View {
        Section {
            HStack {
                TextField(text: typed) { Text(clash: .copy("Value")) }
#if os(iOS)
                    .keyboardType(ConfigurationFormatEditors.numberKeyboard(min: min, text: draft.text, defaultText: defaultText))
#endif
                    .accessibilityIdentifier("configuration-editor.value.number")
                if let unit, !["count", "port"].contains(unit) {
                    Text(verbatim: unit).foregroundStyle(.secondary)
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let range = Self.range(min: min, max: max) { Text(verbatim: range) }
                if let problem = entry?.problem {
                    ConfigurationProblemLine(problem: problem)
                }
            }
        }
        .onAppear {
            guard entry == nil else { return }
            entry = ConfigurationTypedEntry(text: draft.text)
            handed = draft.text
        }
        .onChange(of: draft.text) { text in
            guard text != handed else { return }
            entry = ConfigurationTypedEntry(text: text)
            handed = text
        }
    }

    private var typed: Binding<String> {
        Binding(get: { entry?.typed ?? draft.text }, set: { text in
            var next = entry ?? ConfigurationTypedEntry(text: draft.text)
            let written = next.type(text) { typed in
                typed.trimmingCharacters(in: .whitespaces).isEmpty ? .notANumber : draft.problem(typing: typed)
            }
            entry = next
            if draft.text != written {
                handed = written
                draft.text = written
            }
        })
    }

     
     
    static func range(min: Double?, max: Double?) -> String? {
        switch (min, max) {
        case let (min?, max?): return ConfigurationFieldValidation.plain(min) + "–" + ConfigurationFieldValidation.plain(max)
        case let (min?, nil) where min != 0: return "≥ " + ConfigurationFieldValidation.plain(min)
        case let (nil, max?): return "≤ " + ConfigurationFieldValidation.plain(max)
        default: return nil
        }
    }
}

 

 
 
 
struct ConfigurationDurationEditor: View {
#if os(iOS)
     
     
    static let amountKeyboard: UIKeyboardType = .numberPad
#endif
    @Binding var draft: ConfigurationFieldDraft
    let min: Double?
    let max: Double?
    let fieldUnit: String
    @State private var entry: ConfigurationDurationEntry?
    @State private var problem: ConfigurationFieldProblem?
     
    @State private var baseline = ""
     
     
    @State private var handed: String?

    var body: some View {
        Section {
            HStack {
                TextField(text: amount) { Text(clash: .copy("Value")) }
#if os(iOS)
                    .keyboardType(Self.amountKeyboard)
#endif
                    .accessibilityIdentifier("configuration-editor.value.duration.amount")
                Picker(selection: unit) {
                    ForEach(entry?.units ?? [], id: \.self) { unit in
                        Text(clash: ConfigurationFormatWords.unitName(unit)).tag(unit)
                    }
                } label: { EmptyView() }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityIdentifier("configuration-editor.value.duration.unit")
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let range = Self.range(min: min, max: max, unit: fieldUnit) { Text(clash: range) }
                if let problem {
                    ConfigurationProblemLine(problem: problem)
                }
            }
        }
        .onAppear {
            guard entry == nil else { return }
            take(draft.text)
        }
        .onChange(of: draft.text) { text in
            guard text != handed else { return }
            take(text)
        }
    }

    private func take(_ text: String) {
        entry = ConfigurationDurationEntry(stored: text, fieldUnit: fieldUnit)
        baseline = text
        handed = text
        problem = nil
    }

    private var amount: Binding<String> {
        Binding(get: { entry?.amount ?? draft.text }, set: { text in update { $0.amount = text } })
    }

    private var unit: Binding<ConfigurationDurationEntry.Unit> {
        Binding(get: { entry?.unit ?? .seconds }, set: { unit in update { $0.unit = unit } })
    }

    private func update(_ change: (inout ConfigurationDurationEntry) -> Void) {
        guard var next = entry else { return }
        change(&next)
        entry = next
        let (written, refused) = Self.written(next, draft: draft, baseline: baseline)
        problem = refused
        if draft.text != written {
            handed = written
            draft.text = written
        }
    }

     
     
     
    static func written(_ entry: ConfigurationDurationEntry, draft: ConfigurationFieldDraft,
                        baseline: String) -> (String, ConfigurationFieldProblem?) {
        guard let stored = entry.stored else { return (baseline, .notANumber) }
        if let problem = draft.problem(typing: stored) { return (baseline, problem) }
        return (stored, nil)
    }

     
    static func range(min: Double?, max: Double?, unit: String) -> ClashDisplayText? {
        func words(_ bound: Double) -> String {
            ConfigurationFormatWords.number(ConfigurationFieldValidation.plain(bound), unit: unit)
                .resolved(locale: AppPreferences.language().locale)
        }
        switch (min, max) {
        case let (min?, max?): return .verbatim(words(min) + "–" + words(max))
        case let (min?, nil) where min != 0: return .verbatim("≥ " + words(min))
        case let (nil, max?): return .verbatim("≤ " + words(max))
        default: return nil
        }
    }
}

 
 
struct ConfigurationNumberEditors: View {
    @Binding var draft: ConfigurationFieldDraft
    let min: Double?
    let max: Double?
    let unit: String?
    var defaultText: String? = nil

    var body: some View {
        if let unit, ConfigurationDurationEntry(stored: draft.text, fieldUnit: unit) != nil {
            ConfigurationDurationEditor(draft: $draft, min: min, max: max, fieldUnit: unit)
        } else {
            ConfigurationNumberEditor(draft: $draft, min: min, max: max, unit: unit, defaultText: defaultText)
        }
    }
}

 

 
 
 
 
 
struct ConfigurationPresetMenuRow: View {
    let title: String
    let draft: ConfigurationFieldDraft
    let identifier: String
    let save: (OrderedJSON) -> Void
    var isDefault = false
    var defaultText: String? = nil
    var useDefault: (() -> Void)? = nil
    var caption: ClashDisplayText? = nil
    @State private var showsCustom = false

    static let defaultTag = "\u{1F}default"
    static let customTag = "\u{1F}custom"

     
     
     
    static func applies(to draft: ConfigurationFieldDraft) -> Bool {
        switch draft.control {
        case .number(_, _, let unit): return !ConfigurationFormatPresets.common(path: draft.path, unit: unit).isEmpty
        case .text(.ipPort): return ConfigurationFormatPresets.addressChoices(path: draft.path) != nil
        default: return false
        }
    }

     
    static func isAddress(_ draft: ConfigurationFieldDraft) -> Bool {
        if case .text(.ipPort) = draft.control { return true }
        return false
    }

    private var unit: String? {
        if case .number(_, _, let unit) = draft.control { return unit }
        return nil
    }

    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

     
     
     
    static func presets(for draft: ConfigurationFieldDraft, copy: ConfigurationFieldCopy,
                        language: ConfigurationFieldCopy.Language) -> [ConfigurationFormatPreset] {
        switch draft.control {
        case .number(_, _, let unit):
            return ConfigurationFormatPresets.common(path: draft.path, unit: unit, copy: copy, language: language)
        case .text(.ipPort):
            return (ConfigurationFormatPresets.addressChoices(path: draft.path, copy: copy, language: language) ?? [])
                .filter { $0.value != nil }
        default:
            return []
        }
    }

    private var presets: [ConfigurationFormatPreset] {
        Self.presets(for: draft, copy: fieldCopy, language: .init(locale: locale))
    }

     
     
    static func defaultLabel(for draft: ConfigurationFieldDraft, defaultText: String?) -> ClashDisplayText {
        if isAddress(draft) {
            guard let defaultText, !defaultText.isEmpty else { return .copy("Off") }
            return .verbatim(defaultText)
        }
        var unit: String?
        if case .number(_, _, let own) = draft.control { unit = own }
        return defaultEntry(defaultText, unit: unit)
    }

     
     
    static func entries(for draft: ConfigurationFieldDraft, isDefault: Bool,
                        presets: [ConfigurationFormatPreset], unit: String?) -> [ConfigurationFormatPreset] {
        let written = draft.text.trimmingCharacters(in: .whitespaces)
        guard !isDefault, !written.isEmpty, !presets.contains(where: { $0.value == written }) else { return presets }
         
        let label: ClashDisplayText = isAddress(draft) ? .verbatim(written) : ConfigurationFormatWords.number(written, unit: unit)
        return presets + [ConfigurationFormatPreset(value: written, label: label)]
    }

     
     
     
    static func selection(for draft: ConfigurationFieldDraft, isDefault: Bool) -> String {
        let text = draft.text.trimmingCharacters(in: .whitespaces)
        return isDefault || (isAddress(draft) && text.isEmpty) ? defaultTag : text
    }

     
     
     
    static func defaultText(for draft: ConfigurationFieldDraft, copy: ConfigurationFieldCopy,
                            language: ConfigurationFieldCopy.Language, defaultText: String?) -> String? {
        copy.entry(forPath: draft.path, language: language)?.unset ?? defaultText
    }

     
    enum Pick: Equatable { case write(OrderedJSON), useDefault, custom, nothing }

    static func pick(_ tag: String, draft: ConfigurationFieldDraft, isDefault: Bool) -> Pick {
        switch tag {
        case defaultTag: return selection(for: draft, isDefault: isDefault) == defaultTag ? .nothing : .useDefault
        case customTag: return .custom
        default:
             
             
            var next = draft
            next.text = tag
            return isDefault || next.isChanged ? .write(next.value) : .nothing
        }
    }

     
     
     
     
    static func defaultEntry(_ defaultText: String?, unit: String?) -> ClashDisplayText {
        guard let defaultText, !defaultText.isEmpty else { return .copy("Not set") }
        guard ConfigurationFieldDraft.isNumber(defaultText) else { return .format("Default · %@", [defaultText]) }
        let words = ConfigurationFormatWords.number(defaultText, unit: unit).resolved(locale: AppPreferences.language().locale)
        return .format("Default · %@", [words])
    }

    var body: some View {
        Picker(selection: Binding(get: { Self.selection(for: draft, isDefault: isDefault) },
                                  set: { tag in
            switch Self.pick(tag, draft: draft, isDefault: isDefault) {
            case .write(let value): save(value)
            case .useDefault: useDefault?()
            case .custom: showsCustom = true
            case .nothing: break
            }
        })) {
            if isDefault || useDefault != nil {
                 
                 
                 
                let words = Self.defaultText(for: draft, copy: fieldCopy, language: .init(locale: locale),
                                             defaultText: defaultText)
                Text(clash: Self.defaultLabel(for: draft, defaultText: words)).tag(Self.defaultTag)
            }
            ForEach(Self.entries(for: draft, isDefault: isDefault, presets: presets, unit: unit)) { preset in
                Text(clash: preset.label).tag(preset.value ?? "")
            }
            Text(clash: .copy("Custom…")).tag(Self.customTag)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                if let caption { Text(clash: caption).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier(identifier)
         
         
        .background(ClashRoutedViewDestination(isPresented: $showsCustom) {
            ConfigurationPresetCustomPage(title: title, draft: draft, save: save, turnOff: useDefault)
        }.opacity(0))
    }
}

 
 
struct ConfigurationPresetCustomPage: View {
    let title: String
    let draft: ConfigurationFieldDraft
    let save: (OrderedJSON) -> Void
     
     
     
    var turnOff: (() -> Void)? = nil
    @State private var local: ConfigurationFieldDraft?

    var body: some View {
        Form {
            if let local = Binding($local), case .number(let min, let max, let unit) = local.wrappedValue.control {
                ConfigurationNumberEditors(draft: local, min: min, max: max, unit: unit)
            } else if let local = Binding($local), case .text(.ipPort) = local.wrappedValue.control {
                 
                 
                ConfigurationHostPortEditor(draft: local, startsOnCustom: true)
            }
        }
        .navigationTitle(Text(verbatim: title))
        .onAppear { if local == nil { local = draft } }
        .onDisappear {
            if Self.turnsOff(local, from: draft) {
                turnOff?()
            } else if let value = Self.saving(local, from: draft) {
                save(value)
            }
        }
    }

     
     
     
    static func turnsOff(_ local: ConfigurationFieldDraft?, from draft: ConfigurationFieldDraft) -> Bool {
        guard let local, ConfigurationPresetMenuRow.isAddress(draft) else { return false }
        return local.text.trimmingCharacters(in: .whitespaces).isEmpty
            && !draft.text.trimmingCharacters(in: .whitespaces).isEmpty
    }

     
     
    static func saving(_ local: ConfigurationFieldDraft?, from draft: ConfigurationFieldDraft) -> OrderedJSON? {
        guard let local, local.isValid, local.text != draft.text, !local.text.isEmpty else { return nil }
        return local.value
    }
}
