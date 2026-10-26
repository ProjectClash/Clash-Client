import ClashClientUI
import SwiftUI

/// Editor for the settings every configuration receives on top of its own.
struct GlobalOverridesView: View {
    var restageRuntime: () -> Void = {}

    @State private var isEnabled = GlobalOverridesConfig.load().isEnabled
    @State private var rules = GlobalOverridesConfig.load().rules
    @State private var patchText = GlobalOverridesConfig.load().patchJSON
    @State private var editing: RuleDraft?

    private struct RuleDraft: Identifiable {
        let id = UUID()
        let index: Int?
        let raw: String
    }

    private var patchIsValid: Bool {
        GlobalOverridesConfig.patchIsValid(patchText)
    }

    var body: some View {
        ClashMacSettingsFormContainer {
            Section {
                Toggle("Enable Global Overrides", isOn: $isEnabled)
                    .accessibilityIdentifier("global-overrides.enabled")
                    .onChange(of: isEnabled) { _ in persist() }
            } header: {
                Text("Global Overrides")
            } footer: {
                Text("These settings are applied to every configuration, including subscriptions that keep their own. They live outside the profile, so a source update cannot drop them.")
            }

            Section {
                if rules.isEmpty {
                    Text(clash: .copy("No Global Rules"))
                        .foregroundStyle(.secondary)
                }
                ForEach(rules.indices, id: \.self) { index in
                    Button {
                        editing = RuleDraft(index: index, raw: rules[index])
                    } label: {
                        ConfigurationRuleRow(rules[index], showsChevron: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("global-overrides.rule.\(index)")
                }
                .onDelete { offsets in
                    rules.remove(atOffsets: offsets)
                    persist()
                }
                ClashAddRow(Text(clash: .copy("Add Rule"))) {
                    editing = RuleDraft(index: nil, raw: "")
                }
                .accessibilityIdentifier("global-overrides.rule.add")
            } header: {
                Text("Rules")
            } footer: {
                Text("Prepended to every configuration, before its own rules. A rule that names a policy a configuration does not define is left out for that configuration.")
            }

            Section {
                CodeEditorPanel(
                    text: $patchText,
                    language: .json,
                    minHeight: 220
                )
                if !patchIsValid {
                    ClashStatusMessage(text: .copy("Global patch must be a JSON object."), kind: .error)
                }
            } header: {
                Text("Global Patch")
            } footer: {
                Text("Any other app-level field, as a JSON object: dns (including nameserver-policy and fake-ip-filter), tun (including route-exclude-address), sniffer, hosts. It is applied under every configuration, so a field a profile sets keeps its own value; rules above are separate because their order matters.")
            }
        }
        .clashPageTitle("Global Overrides")
        .sheet(item: $editing) { draft in
            RuleEditorSheet(rule: draft.raw) { text in
                commit(text, at: draft.index)
            }
        }
        .task(id: patchText) {
            guard patchIsValid else { return }
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            persist()
        }
        .onDisappear {
            if patchIsValid { persist() }
        }
    }

    private func commit(_ text: String, at index: Int?) {
        let rule = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rule.isEmpty else { return }
        if let index, rules.indices.contains(index) {
            rules[index] = rule
        } else {
            rules.insert(rule, at: 0)
        }
        persist()
    }

    private func persist() {
        var config = GlobalOverridesConfig.load()
        config.isEnabled = isEnabled
        config.rules = rules
        config.patchJSON = patchText
        GlobalOverridesConfig.save(config)
        rules = GlobalOverridesConfig.normalized(rules)
        patchText = GlobalOverridesConfig.normalizedPatch(patchText)
        restageRuntime()
    }
}

private struct RuleEditorSheet: View {
    let rule: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(rule: String, onSave: @escaping (String) -> Void) {
        self.rule = rule
        self.onSave = onSave
        _text = State(initialValue: rule)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(clash: .copy(rule.isEmpty ? "Add Rule" : "Edit Rule"))
                .font(.headline)
            TextField("DOMAIN-SUFFIX,example.com,DIRECT", text: $text)
                .font(.body.monospaced())
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("global-overrides.field")
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text(clash: .copy("Cancel"))
                }
                .keyboardShortcut(.cancelAction)
                Button {
                    onSave(text)
                    dismiss()
                } label: {
                    Text(clash: .copy("Save"))
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }
}
