import ClashClientKit
import SwiftUI

 
 
 

extension ClashModuleDetailSnapshot {
     
     
     
    public struct Setting: Equatable, Sendable, Identifiable {
        public enum Control: Equatable, Sendable {
             
            case toggle(isOn: Bool)
             
            case menu(options: [String], selected: String)
             
             
             
            case text(value: String, placeholder: ClashDisplayText)
        }

         
        public var id: String
         
        public var title: String
         
        public var note: String?
        public var control: Control
         
        public var defaultLine: ClashDisplayText?

        public init(id: String, title: String, note: String? = nil, control: Control, defaultLine: ClashDisplayText? = nil) {
            self.id = id
            self.title = title
            self.note = note
            self.control = control
            self.defaultLine = defaultLine
        }
    }

     
    public struct Settings: Equatable, Sendable {
        public var items: [Setting]
         
        public var note: String?
         
         
        public var canReset: Bool
         
        public var refusal: ClashDisplayText?

        public init(items: [Setting], note: String? = nil, canReset: Bool = false, refusal: ClashDisplayText? = nil) {
            self.items = items
            self.note = note
            self.canReset = canReset
            self.refusal = refusal
        }
    }
}

 
 
struct ClashModuleInformationSection: View {
    let snapshot: ClashModuleDetailSnapshot

    var body: some View {
        if snapshot.summary != nil || snapshot.date != nil || snapshot.homepage != nil {
            Section {
                if let summary = snapshot.summary {
                    Text(verbatim: summary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let date = snapshot.date {
                    ClashModuleValueRow(title: "Version Date") { Text(verbatim: date) }
                }
                if let homepage = snapshot.homepage {
                    if let url = Self.webAddress(homepage) {
                         
                        Link(destination: url) {
                            HStack(alignment: .firstTextBaseline, spacing: ClashTheme.Spacing.row) {
                                Text("Homepage")
                                    .foregroundStyle(Color.primary)
                                Spacer(minLength: ClashTheme.Spacing.row)
                                Text(unhyphenated: homepage)
                                    .multilineTextAlignment(.trailing)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityIdentifier("modules.detail.homepage")
                    } else {
                        ClashModuleValueRow(title: "Homepage") {
                            Text(unhyphenated: homepage)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } header: {
                Text("Information")
            }
        }
    }

     
     
    nonisolated static func webAddress(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespaces)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else { return nil }
        return url
    }
}

 
 
 
struct ClashModuleSettingsSection: View {
    let moduleID: String
    let settings: ClashModuleDetailSnapshot.Settings
     
     
    let values: ClashStoredValues<String, String?>
    let perform: (ClashModulesAction) -> Void
    @State private var confirmsReset = false

    var body: some View {
        Section {
             
             
            ForEach(settings.items) { setting in
                ClashModuleSettingRow(setting: setting, values: values,
                                      key: ClashModulesWrites.setting(module: moduleID, name: setting.id)) { value in
                    perform(.setArgument(module: moduleID, name: setting.id, value: value))
                }
            }
            if let refusal = settings.refusal {
                 
                Label {
                    Text(clash: refusal)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: ClashSymbol.exclamationmarkTriangleFill.rawValue)
                        .foregroundStyle(Color.red)
                }
                .font(.subheadline)
                .accessibilityIdentifier("modules.detail.settings.refusal")
            }
        } header: {
            Text("Settings")
        } footer: {
             
            if let note = settings.note {
                Text(verbatim: note)
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        Section {
            Button(role: .destructive) {
                confirmsReset = true
            } label: {
                Text("Reset")
            }
            .disabled(!settings.canReset)
            .accessibilityIdentifier("modules.detail.settings.reset")
             
             
            .confirmationDialog(
                Text("Reset this module's settings?"),
                isPresented: $confirmsReset,
                titleVisibility: .visible
            ) {
                Button(role: .destructive) {
                    perform(.resetArguments(module: moduleID))
                } label: {
                    Text("Reset")
                }
                .accessibilityIdentifier("modules.detail.settings.reset.confirm")
                Button(role: .cancel) {} label: {
                    Text("Cancel")
                }
            }
        }
    }
}

 
 
struct ClashModuleSettingRow: View {
    let setting: ClashModuleDetailSnapshot.Setting
     
     
    let values: ClashStoredValues<String, String?>
    @ObservedObject private var cell: ClashStoredValues<String, String?>.Cell
    let key: String
    let commit: (String?) -> Void

    init(setting: ClashModuleDetailSnapshot.Setting, values: ClashStoredValues<String, String?>, key: String,
         commit: @escaping (String?) -> Void) {
        self.setting = setting
        self.values = values
        cell = values.cell(key)
        self.key = key
        self.commit = commit
    }
    @State private var draft = ""
     
    @State private var sent: String??
    @FocusState private var editing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
            switch setting.control {
            case .toggle(let isOn):
                 
                let shown = values.pressedValue(key).flatMap { $0.map { $0 == "true" } } ?? isOn
                Toggle(isOn: Binding(get: { shown }, set: { commit($0 ? "true" : "false") })) {
                    Text(verbatim: setting.title)
                }
                .modifier(ClashModulesSwitchStyle())
                .accessibilityIdentifier("modules.detail.setting.\(setting.id)")
                notes
            case .menu(let options, let selected):
                let shown = values.pressedValue(key).flatMap { $0 } ?? selected
                Picker(selection: Binding(get: { shown }, set: { commit($0) })) {
                    ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                        Text(verbatim: option).tag(option)
                    }
                } label: {
                    Text(verbatim: setting.title)
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("modules.detail.setting.\(setting.id)")
                notes
            case .text(let value, let placeholder):
                Text(verbatim: setting.title)
                if let note = setting.note {
                    noteText(note)
                }
                HStack {
                    TextField(text: $draft, prompt: Text(clash: placeholder)) {
                        Text(verbatim: setting.title)
                    }
                    .focused($editing)
                    .modifier(ClashModuleFieldStyle())
                    .onSubmit { send(from: value) }
                    .onChange(of: editing) { if !$0 { send(from: value) } }
                    .onChange(of: value) { if !editing { draft = $0 } }
                    .onAppear { draft = value }
                    .onDisappear { send(from: value) }
                    .accessibilityIdentifier("modules.detail.setting.\(setting.id)")
                     
                     
                    if editing {
                        Button("Done") { editing = false }
                    }
                }
                if let line = setting.defaultLine {
                    Text(clash: line)
                        .font(.footnote)
                }
            }
        }
    }

    @ViewBuilder
    private var notes: some View {
        if let note = setting.note {
            noteText(note)
        }
        if let line = setting.defaultLine {
            Text(clash: line)
                .font(.footnote)
        }
    }

    private func noteText(_ note: String) -> some View {
        Text(verbatim: note)
            .font(.footnote)
            .fixedSize(horizontal: false, vertical: true)
    }

     
    private func send(from value: String) {
        let given: String? = draft.isEmpty ? nil : draft
        guard draft != value, sent != .some(given) else { return }
        sent = .some(given)
        commit(given)
    }
}

 
 
private struct ClashModuleFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
#if os(iOS)
        content
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
#else
        content
            .disableAutocorrection(true)
#endif
    }
}

 
private struct ClashModuleValueRow<Value: View>: View {
    let title: ClashDisplayText
    @ViewBuilder let value: () -> Value

    var body: some View {
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, *) {
            LabeledContent { value() } label: { Text(clash: title) }
        } else {
            before16
        }
    }

    private var before16: some View {
        HStack(alignment: .firstTextBaseline, spacing: ClashTheme.Spacing.row) {
            Text(clash: title)
            Spacer(minLength: ClashTheme.Spacing.row)
            value().foregroundStyle(.secondary)
        }
    }
}
