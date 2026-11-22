import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
 
struct ClashMacGroupExcludesPage: View {
    @StateObject private var model: ConfigurationGroupExcludesModel
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

    init(group: String, document: OrderedJSON, write: @escaping @MainActor (String, OrderedJSON?) async -> String?) {
        _model = StateObject(wrappedValue: ConfigurationGroupExcludesModel(
            group: group,
            pattern: ConfigurationGroupExcludes.text(document.topLevelValue("exclude-filter")),
            types: ConfigurationGroupExcludes.text(document.topLevelValue("exclude-type")),
            check: ConfigurationTowerRuleCustomizationAdapter.groupPatternCheck,
            write: write))
    }

    private var language: ConfigurationFieldCopy.Language { .init(locale: locale) }
    private var patternCopy: ConfigurationFieldCopy.Entry? { fieldCopy.entry(forPath: ClashGroupLeaveOutNodes.copyPath, language: language) }
    private var typesCopy: ConfigurationFieldCopy.Entry? { fieldCopy.entry(forPath: "proxy-groups[*].exclude-type", language: language) }

    var body: some View {
        Form {
            Section {
                TextField(text: $model.pattern, prompt: patternCopy?.example.map { Text(verbatim: $0) }) {
                    Text(verbatim: ConfigurationGroupExcludes.title(fieldCopy, locale: locale))
                }
                .autocorrectionDisabled()
                .onSubmit { Task { await model.submitPattern() } }
                .accessibilityIdentifier("configuration.group.excludes.pattern")
                if let refusal = model.refusal {
                    Text(clash: refusal).font(.footnote).foregroundStyle(.red)
                        .accessibilityIdentifier("configuration.group.excludes.pattern.refusal")
                }
                Button { Task { await model.addInfoNodes() } } label: { Text(clash: .copy("Leave Out Info Nodes")) }
                    .disabled(model.holdsInfoNodes)
                    .accessibilityIdentifier("configuration.group.excludes.info-nodes")
            } header: {
                Text(clash: .copy("By Name"))
            } footer: {
                if let summary = patternCopy?.summary { Text(verbatim: summary) }
            }
            Section {
                ForEach(ConfigurationGroupExcludes.typeRows(fieldCopy, locale: locale, written: model.types), id: \.value) { row in
                    Toggle(isOn: Binding(get: { model.excludes(row.value) }, set: { on in model.press(row.value, on: on) })) {
                        Text(verbatim: row.label)
                    }
                    .accessibilityLabel(Text(clash: ConfigurationGroupExcludes.typeLabel(row.label)))
                    .accessibilityIdentifier("configuration.group.excludes.type.\(row.value)")
                }
            } header: {
                Text(clash: .copy("By Protocol"))
            } footer: {
                if let summary = typesCopy?.summary { Text(verbatim: summary) }
            }
            if let failure = model.failure {
                Section { Text(verbatim: failure).foregroundStyle(.orange) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text(verbatim: ConfigurationGroupExcludes.title(fieldCopy, locale: locale)))
         
         
        .task(id: model.pattern) {
            guard !model.pattern.isEmpty else { return }
            if model.pattern != model.written {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
            }
            await model.checkPattern()
        }
         
         
         
        .clashOnScreen { [model] onScreen in
            if !onScreen { Task { await model.submitPattern() } }
        }
    }
}
