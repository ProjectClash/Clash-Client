import ClashClientKit
import ClashClientUI
import SwiftUI
import UniformTypeIdentifiers

struct ProfileResourcesView: View {
    let profile: Profile
    let canManageProviders: Bool
    @ObservedObject private var vpn: VPNController
     
     
     
     
    private let command: ClashCommandClient

     
     
     
    @StateObject private var dismiss = ClashDismissHandle()
    private let summary: ProfileResourceSummary?
    private let summaryError: ProfileResourceSummaryError?

    init(
        profile: Profile,
        sourceYAML: String?,
        canManageProviders: Bool,
        vpn: VPNController,
        command: ClashCommandClient
    ) {
        self.profile = profile
        self.canManageProviders = canManageProviders
        _vpn = ObservedObject(wrappedValue: vpn)
        self.command = command
        guard let sourceYAML else {
            summary = nil
            summaryError = .sourceUnavailable
            return
        }
        do {
            summary = try ProfileResourceSummary(profile: profile, sourceYAML: sourceYAML)
            summaryError = nil
        } catch let bounded as ProfileResourceSummaryError {
            summary = nil
            summaryError = bounded
        } catch {
            summary = nil
            summaryError = .invalidConfiguration
        }
    }

    var body: some View {
        ClashFeatureNavigationContainer {
            Form {
                Section {
                    ClashProfileContextHeader(
                        profileName: profile.label,
                        message:
                            "These proxy sources and rule sets belong to this profile and update without changing the original file."
                    ) {
                        ClashSymbolImage(symbol: .profileClipboard)
                    }
                }

                if let summaryError {
                    Section {
                        ClashStatusMessage(
                            text: .copy(summaryError.localizedDescription),
                            kind: .error
                        )
                    }
                } else if let summary {
                    if summary.proxyProviderCount > 0 || summary.ruleProviderCount > 0 {
                        Section {
                            if summary.proxyProviderCount > 0 {
                                providerDestination(
                                    title: "Proxy Sources",
                                    subtitle: countText(
                                        summary.proxyProviderCount,
                                        singular: "source",
                                        plural: "sources"
                                    ),
                                    symbol: .serverRack,
                                    tint: .purple,
                                    scope: .proxy,
                                    identifier: "profile-resources.proxy-providers"
                                )
                            }
                            if summary.ruleProviderCount > 0 {
                                providerDestination(
                                    title: "Rule Sets",
                                    subtitle: countText(
                                        summary.ruleProviderCount,
                                        singular: "set",
                                        plural: "sets"
                                    ),
                                    symbol: .listBulletRectangle,
                                    tint: .orange,
                                    scope: .rule,
                                    identifier: "profile-resources.rule-providers"
                                )
                            }
                        } header: {
                            Text("Profile Providers")
                        } footer: {
                            Text(canManageProviders
                                 ? "Sync and health actions use the validated provider copies for this profile."
                                 : "Prepare this profile once to sync providers or view their live status.")
                        }
                    }

                    if summary.supportingFileCount > 0 {
                        Section {
                            HStack(spacing: ClashTheme.Spacing.row) {
                                ClashIconWell(symbol: .docText, tint: .blue)
                                VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                                    Text("Supporting Files")
                                    Text(countText(
                                        summary.supportingFileCount,
                                        singular: "managed file",
                                        plural: "managed files"
                                    ))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, ClashTheme.Spacing.tight)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("profile-resources.supporting-files")
                        } header: {
                            Text("Imported With This Profile")
                        } footer: {
                            Text("Local paths and credentials stay private. Re-import the profile if one of its supporting files is missing.")
                        }
                    }

                    if !summary.hasResources {
                        Section {
                            ClashEmptyState(
                                title: "No External Resources",
                                message: "This profile keeps its proxies and rules directly in the configuration, so there is nothing separate to sync.",
                                symbol: .shippingbox
                            )
                            .listRowSeparator(.hidden)
                        }
                    }
                }
            }
            .clashInsetGroupedListStyle()
            .clashPageTitle("Resources")
            .clashToolbarUnlessInPanel {
                ToolbarItem(placement: .cancellationAction) {
                    ClashSheetCloseButton { dismiss() }
                }
            }
        }
        .clashStackNavigationViewStyle()
        .accessibilityIdentifier("profile-resources.screen")
        .clashCapturesDismiss(dismiss)
    }

    @ViewBuilder
    private func providerDestination(
        title: String,
        subtitle: String,
        symbol: ClashSymbol,
        tint: Color,
        scope: ProviderDisplayScope,
        identifier: String
    ) -> some View {
        if canManageProviders {
            ClashRoutedViewLink {
                ProvidersView(vpn: vpn, command: command, scope: scope)
            } label: {
                destinationLabel(
                    title: title,
                    subtitle: subtitle,
                    symbol: symbol,
                    tint: tint
                )
            }
            .accessibilityIdentifier(identifier)
        } else {
            destinationLabel(
                title: title,
                subtitle: subtitle,
                symbol: symbol,
                tint: tint
            )
            .accessibilityElement(children: .combine)
            .accessibilityHint("Prepare this profile to manage providers")
            .accessibilityIdentifier(identifier)
        }
    }

    private func destinationLabel(
        title: String,
        subtitle: String,
        symbol: ClashSymbol,
        tint: Color
    ) -> some View {
        HStack(spacing: ClashTheme.Spacing.row) {
            ClashIconWell(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                Text(clash: .copy(title))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, ClashTheme.Spacing.tight)
    }

    private func countText(_ count: Int, singular: String, plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }
}

 
 
 
struct ProfileProviderDefinitionsView: View {
    @Environment(\.clashInsideProductModalPresentation)
    private var insideProductModal
     
     
     
     
     
     
     
     
    let profile: Profile
    let kind: ProfileProviderKind
    let ownsNavigationContainer: Bool
    let load: () async throws -> ProfileProviderDefinitionsDraft
    let save: (ProfileProviderDefinitionsDraft) throws -> Void

     
    @StateObject private var dismiss = ClashDismissHandle()
    @State private var draft: ProfileProviderDefinitionsDraft?

    @State private var editor: ProviderEditorSelection?
    @State private var errorMessage = ""
    @State private var isSaving = false

    init(
        profile: Profile,
        kind: ProfileProviderKind,
        ownsNavigationContainer: Bool = true,
        load: @escaping () async throws -> ProfileProviderDefinitionsDraft,
        save: @escaping (ProfileProviderDefinitionsDraft) throws -> Void
    ) {
        self.profile = profile
        self.kind = kind
        self.ownsNavigationContainer = ownsNavigationContainer
        self.load = load
        self.save = save
    }

    var body: some View {
        ClashFeatureNavigationContainer(
            ownsNavigationContainer: ownsNavigationContainer
        ) {
            Group {
                if let draft {
                    providerList(draft)
                } else if errorMessage.isEmpty {
                    ClashAsyncLoadingView()
                } else {
                    Form {
                        Section {
                            ClashStatusMessage(text: .copy(errorMessage), kind: .error)
                        }
                    }
                    .clashInsetGroupedListStyle()
                }
            }
            .navigationTitle(kind == .proxy ? "Proxy Sources" : "Rule Sets")
            .clashFeaturePresentation(
                ownsNavigationContainer: ownsNavigationContainer
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if ownsNavigationContainer {
                        Button("Cancel") { closePage() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                     
                     
                    if !insideProductModal {
                        ClashSaveButton { persist() }
                            .font(.body.weight(.semibold))
                            .disabled(draft == nil || isSaving)
                            .accessibilityIdentifier("provider-definitions.save")
                    }
                }
            }
        }
        .task { await loadDraftIfNeeded() }
        .clashProductModal(
            item: $editor,
            role: .form,
            macOSPanelRole: .page
        ) { selection in
            ClashFeatureNavigationContainer {
                ProfileProviderDefinitionEditorView(
                    record: selection.record,
                    kind: kind,
                    save: applyEditorResult
                )
            }
            .clashPageSizedSheet()
        }
        .alert(
            "Provider settings could not be saved",
            isPresented: Binding(
                get: { !errorMessage.isEmpty && draft != nil },
                set: { if !$0 { errorMessage = "" } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = "" }
        } message: {
            Text(clash: .copy(errorMessage))
        }
        .clashMacProductModalBar {
            if insideProductModal {
                 
                 
                 
                ClashModalActionBar(
                    primaryTitle: "Save",
                    primaryDisabled: draft == nil,
                    isBusy: isSaving,
                    busyTitle: "Saving…",
                    onPrimary: persist
                )
            }
        }
         
         
         
         
         
        .clashRegistersDeparture(
             
             
            isDirty: draft?.hasUnsavedChanges == true,
            isBusy: isSaving,
             
            saveAnswering: { answer in
                answer(commit() ? .saved : .refused(nil))
            },
             
             
            discard: { Task { draft = try? await load() } }
        )
        .clashPageProbe("provider-definitions")
        .accessibilityIdentifier("provider-definitions.\(kind.rawValue).screen")
        .clashCapturesDismiss(dismiss)
    }

    private func providerList(_ value: ProfileProviderDefinitionsDraft) -> some View {
        let records = value.records(kind: kind)
        return Form {
            Section {
                ClashProfileContextHeader(
                    profileName: profile.label,
                    message:
                        kind == .proxy
                            ? "These proxy sources supply nodes to this profile without changing its imported source."
                            : "These rule sets supply matching data to this profile without changing its imported source."
                ) {
                    ClashSymbolImage(symbol: .profileClipboard)
                }
            }

            Section {
#if os(macOS)
                 
                 
                 
                 
                if records.isEmpty {
                    ClashEmptyState(
                        title: kind == .proxy
                            ? "No Proxy Sources"
                            : "No Rule Sets",
                        message: kind == .proxy
                            ? "A proxy source supplies nodes to this profile. It is not itself a selectable route."
                            : "A rule set supplies reusable matching data to this profile’s routing rules.",
                        symbol: kind == .proxy
                            ? .serverRack
                            : .listBulletRectangle
                    )
                    .listRowSeparator(.hidden)
                }
#endif
                ForEach(records) { record in
                    Button {
                        editor = ProviderEditorSelection(record: record)
                    } label: {
                        HStack(spacing: ClashTheme.Spacing.row) {
                            ClashIconWell(
                                symbol: kind == .proxy ? .serverRack : .listBulletRectangle,
                                tint: kind == .proxy ? .purple : .orange
                            )
                            VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                                Text(record.name)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(transportTitle(record.transport))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: ClashTheme.Spacing.compact)
                            Image(systemName: ClashSymbol.chevronForward.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, ClashTheme.Spacing.tight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(
                        "provider-definitions.\(kind.rawValue).\(record.name)"
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            remove(record)
                        } label: {
                            Label("Delete", systemImage: ClashSymbol.trash.name)
                        }
                        .tint(.red)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            remove(record)
                        } label: {
                            Label("Delete", systemImage: ClashSymbol.trash.name)
                        }
                        .accessibilityIdentifier(
                            "provider-definitions.\(kind.rawValue).\(record.name).delete"
                        )
                    }
                }
            } footer: {
#if os(macOS)
                 
                 
                 
                if !records.isEmpty {
                    Text(kind == .proxy
                         ? "A proxy source supplies nodes to this profile. It is not itself a selectable route."
                         : "A rule set supplies reusable matching data to this profile’s routing rules.")
                }
#else
                Text(kind == .proxy
                     ? "A proxy source supplies nodes to this profile. It is not itself a selectable route."
                     : "A rule set supplies reusable matching data to this profile’s routing rules.")
#endif
            }

            Section {
                ClashAddRow(
                    Text(ClashCopy.key(
                        kind == .proxy ? "Add Proxy Source" : "Add Rule Set"
                    ))
                ) {
                    editor = ProviderEditorSelection(record: nil)
                } touchLabel: {
                    Label(
                        kind == .proxy ? "Add Proxy Source" : "Add Rule Set",
                        systemImage: ClashSymbol.plus.name
                    )
                }
                .accessibilityIdentifier("provider-definitions.\(kind.rawValue).add")
            }
        }
        .clashInsetGroupedListStyle()
    }

    @MainActor
    private func loadDraftIfNeeded() async {
        guard draft == nil else { return }
        do {
            draft = try await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyEditorResult(_ result: ProviderEditorResult) throws {
        guard var value = draft else {
            throw ProfileProviderDefinitionError.profileChanged
        }
        if let original = result.originalName {
            if original != result.name {
                try value.renameDefinition(named: original, to: result.name, kind: kind)
            }
            try value.updateDefinition(
                named: result.name,
                kind: kind,
                definitionJSON: result.definitionJSON
            )
        } else {
            try value.addDefinition(
                named: result.name,
                kind: kind,
                definitionJSON: result.definitionJSON
            )
        }
        if result.transport == .file {
            try value.setManagedFile(result.managedFile, for: result.name, kind: kind)
        }
        draft = value
    }

    private func remove(_ record: ProfileProviderDefinitionRecord) {
        guard var value = draft else { return }
        do {
            try value.removeDefinition(named: record.name, kind: kind)
            draft = value
        } catch {
            errorMessage = error.localizedDescription
        }
    }

     
     
     
     
     
    private func persist() { if commit() { closePage() } }

    @discardableResult
    private func commit() -> Bool {
        guard let value = draft else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            try save(value)
            return true
        } catch {
            errorMessage = error.localizedDescription
        }
        return false
    }

    private func transportTitle(_ transport: ProfileProviderTransport) -> String {
        switch transport {
        case .http: return "http · downloaded by the app"
        case .file: return "file · managed local copy"
        case .inline: return "inline · stored in this profile"
        }
    }

     
     
    private func closePage() {
        dismiss.closeModalOrDismiss()
    }
}

private struct ProviderEditorSelection: Identifiable {
    let id = UUID()
    let record: ProfileProviderDefinitionRecord?
}

struct ProviderEditorResult {
    let originalName: String?
    let name: String
    let transport: ProfileProviderTransport
    let definitionJSON: String
    let managedFile: ExternalResourceImportFile?
}

 
 
 
 
 
 
 
struct ProfileProviderDefinitionEditorView: View {
    let save: (ProviderEditorResult) throws -> Void

     
     
     
    @StateObject private var dismiss = ClashDismissHandle()
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale
    @StateObject private var draft: ProfileProviderDefinitionEditorDraft
    @State private var selectedFile: ExternalResourceImportFile?
    @State private var showsFileImporter = false
    @State private var errorMessage = ""
     
    @State private var syntaxCatalog: ProfilesViewModel.SyntaxCatalog?

    init(
        record: ProfileProviderDefinitionRecord?,
        kind: ProfileProviderKind,
        save: @escaping (ProviderEditorResult) throws -> Void
    ) {
        self.save = save
        _draft = StateObject(wrappedValue: ProfileProviderDefinitionEditorDraft(
            record: record,
            kind: kind
        ))
    }

    var body: some View {
        editorForm
            .clashCapturesDismiss(dismiss)
    }

    private var base: String { ProviderFieldCatalog.base(draft.kind) }

     
     
    private var drawnElsewhere: Set<String> { ProviderFieldCatalog.definitionDrawnElsewhere(draft.transport) }

     
    private var unsupported: Set<String> { ProviderFieldCatalog.definitionUnsupported(draft.kind) }

    private var editorForm: some View {
        Form {
            Section {
                HStack {
                    Text(clash: .copy("Name"))
                    Spacer(minLength: 12)
                    TextField(text: $draft.name, prompt: Text(verbatim: "provider1")) { Text(clash: .copy("Name")) }
                        .multilineTextAlignment(.trailing)
                        .font(.body.monospaced())
                        .disableAutocorrection(true)
                        .textInputAutocapitalization(.never)
                }
                .accessibilityIdentifier("provider-definition.name")
                typePicker
            } footer: {
                Text(clash: .copy(transportDetail(draft.transport)))
            }
            if let catalog = syntaxCatalog?.fieldCatalog {
                let layout = ProviderFieldCatalog.layout(
                    of: ProxyNodeCatalog.json(draft.mapping), base: base, in: catalog,
                    drawnElsewhere: drawnElsewhere, unsupported: unsupported)
                    .splittingOffThePlatformsRows(in: ProxyNodeCatalog.json(draft.mapping))
                 
                 
                let sections = ProxyNodeCatalogSections.sections(of: layout, layoutPath: base, catalog: catalog,
                                                                 copy: fieldCopy, locale: locale)
                 
                let firstOwn = sections.first { $0.id.hasPrefix("main#") }?.id
                let document = ProxyNodeCatalog.json(draft.mapping)
                ForEach(sections) { section in
                    Section {
                        ForEach(section.rows) { row in
                            ProviderDefinitionCatalogRow(
                                draft: draft, row: row, base: base, catalog: catalog,
                                chooseFile: { showsFileImporter = true })
                            .disabled(ProxyNodeCatalogSections.inactive(row, in: document, catalog: catalog))
                        }
                    } header: {
                        if let title = section.title { Text(clash: title) }
                    } footer: {
                        if let footer = section.footer { Text(verbatim: footer) }
                        if let summary = ProxyNodeCatalogSections.offSwitchSummary(over: section.rows, in: document, catalog: catalog) {
                            Text(clash: fieldCopy.turnOnLine(summary, locale: locale))
                        }
                        if section.id == firstOwn, !draft.string(path: ["proxy"]).isEmpty {
                            Text(clash: .copy("The fetch proxy is kept as written. Clash downloads this provider itself and uses the cached copy if a refresh fails."))
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
            } else {
                Section {
                    ClashAsyncLoadingView()
                }
            }
        }
#if os(macOS)
         
         
         
        .formStyle(.grouped)
#else
        .clashInsetGroupedListStyle()
#endif
        .navigationTitle(editorTitle)
        .task {
            if syntaxCatalog == nil { syntaxCatalog = try? await ProfilesViewModel.loadSyntaxCatalog() }
        }
         
         
         
        .onChange(of: draft.string(path: ["behavior"])) { _ in correctFormatForBehavior() }
        .onChange(of: draft.string(path: ["format"])) { _ in correctFormatForBehavior() }
#if !os(macOS)
         
         
         
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: persist)
                    .font(.body.weight(.semibold))
                    .accessibilityIdentifier("provider-definition.done")
            }
        }
#endif
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if ClashPlatformLayout.modalEditorUsesGroupedForm {
                 
                 
                 
                ClashModalActionBar(
                    primaryTitle: "Done",
                    primaryDisabled: draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    onPrimary: persist
                )
            }
        }
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: [.data, .text],
            allowsMultipleSelection: false,
            onCompletion: importFile
        )
        .alert(
            "Provider could not be saved",
            isPresented: Binding(
                get: { !errorMessage.isEmpty },
                set: { if !$0 { errorMessage = "" } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = "" }
        } message: {
            Text(clash: .copy(errorMessage))
        }
        .accessibilityIdentifier(
            "provider-definition.\(draft.kind.rawValue).\(draft.transport.rawValue)"
        )
         
        .clashRegistersDeparture(
            isDirty: draft.hasUnsavedChanges,
            save: { completion in
                completion(commit())
            },
            discard: {}
        )
        .clashProductModalRoot(title: .copy(editorTitle))
    }

     
     
     
    private var typePicker: some View {
        let offered = ProviderFieldCatalog.types(syntaxCatalog, base: base)
            .filter { ProfileProviderTransport(rawValue: $0.lowercased()) != nil }
         
         
        let typeField = syntaxCatalog?.fieldCatalog?.field(atCatalogPath: base + ".type")
        return Picker(selection: Binding(
            get: { draft.transport.rawValue },
            set: { if let transport = ProfileProviderTransport(rawValue: $0.lowercased()) { draft.transport = transport } }
        )) {
            ForEach(offered.isEmpty ? [draft.transport.rawValue] : offered, id: \.self) { type in
                Text(verbatim: fieldCopy.valueLabel(type, for: typeField, locale: locale) ?? type).tag(type)
            }
        } label: {
            Text(verbatim: fieldCopy.title(for: typeField, key: "type", locale: locale))
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("provider-definition.transport")
    }

    private func correctFormatForBehavior() {
        guard draft.kind == .rule, draft.string(path: ["behavior"]) == "classical",
              draft.string(path: ["format"]).lowercased() == "mrs" else { return }
        draft.setString("yaml", path: ["format"])
    }

    private var editorTitle: String {
        draft.originalName == nil ? "Add Provider" : "Edit Provider"
    }

    private func transportDetail(_ transport: ProfileProviderTransport) -> String {
        switch transport {
        case .http: return "Downloaded by the app over HTTP or HTTPS"
        case .file: return "A local file copied into the protected store"
        case .inline: return "Content stored inside this profile"
        }
    }

    private func importFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else {
                throw ProfileProviderDefinitionError.missingManagedFile
            }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
             
             
             
            let requiresUTF8Text = draft.string(path: ["format"]).lowercased() != "mrs"
            guard !data.isEmpty,
                  data.count <= ProfileExternalResourceImporter.maximumResourceBytes,
                  !requiresUTF8Text || String(data: data, encoding: .utf8) != nil else {
                throw ProfileProviderDefinitionError.missingManagedFile
            }
            let file = ExternalResourceImportFile(fileName: url.lastPathComponent, data: data)
            selectedFile = file
            draft.setString(file.fileName, path: ["path"], omitWhenEmpty: false)
        } catch {
            errorMessage = ProfileProviderDefinitionError.missingManagedFile.localizedDescription
        }
    }

     
     
     
     
     
    private func persist() { if commit() { dismiss.closeModalOrDismiss() } }

    @discardableResult
    private func commit() -> Bool {
        do {
             
             
             
             
            if let rejection = ProfileProviderDefinitionError.rejecting(draft.name) {
                throw rejection
            }
            let definition = try draft.validatedDefinitionJSON()
            try save(ProviderEditorResult(
                originalName: draft.originalName,
                name: draft.name,
                transport: draft.transport,
                definitionJSON: definition,
                managedFile: selectedFile
            ))
            return true
        } catch {
            errorMessage = error.localizedDescription
        }
        return false
    }
}

 
 
 
private struct ProviderDefinitionCatalogRow: View {
    @ObservedObject var draft: ProfileProviderDefinitionEditorDraft
    let row: ProxyNodeCatalogLayout.Row
    let base: String
    let catalog: ConfigurationFieldCatalog
    let chooseFile: () -> Void

    private var access: CatalogFieldAccess<ProfileProviderDefinitionEditorDraft> { .init(draft: draft, row: row) }
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale
     
    private var title: String { access.title(fieldCopy, locale) }

     
    static func count(_ count: Int) -> ClashDisplayText {
        count == 0 ? .copy("None") : ConfigurationValueWords.itemCount(count, locale: AppPreferences.language().locale)
    }
    private var identifier: String { "provider-definition.\(row.path.joined(separator: "."))" }

    var body: some View {
        control
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if access.isWritten, !["payload", "header", "path"].contains(row.path.first ?? "") || row.path.count > 1 {
                    Button { access.useDefault() } label: { ClashSwipeLabel(.copy("Use Default"), symbol: .arrowUturnBackward) }
                        .tint(.orange)
                }
            }
    }

    @ViewBuilder
    private var control: some View {
        switch row.path {
        case ["payload"]:
            if draft.kind == .proxy {
                ClashRoutedViewLink {
                    ProviderInlineProxyPayloadView(draft: draft)
                } label: {
                    CatalogLabeledRow(title: title, value: Self.count(draft.proxyPayload().count))
                }
                .accessibilityIdentifier("provider-definition.inline.proxy-payload-link")
            } else {
                ClashRoutedViewLink {
                    ProviderInlineRulePayloadView(draft: draft)
                } label: {
                    CatalogLabeledRow(title: title, value: Self.count(draft.rulePayload().count))
                }
                .accessibilityIdentifier("provider-definition.inline.rule-payload-link")
            }
        case ["header"]:
            ClashRoutedViewLink {
                ProviderHeadersEditorView(draft: draft)
            } label: {
                CatalogLabeledRow(title: title, value: draft.headers().isEmpty
                                  ? .copy("Not set") : ConfigurationValueWords.entryCount(draft.headers().count, locale: AppPreferences.language().locale))
            }
            .accessibilityIdentifier("provider-definition.headers-link")
        case ["path"]:
             
             
            HStack {
                Text(verbatim: title)
                Spacer(minLength: 12)
                Text(verbatim: draft.string(path: ["path"])).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Button { chooseFile() } label: { Text(clash: .copy("Choose File")) }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("provider-definition.file.choose")
            }
        default:
            generic
        }
    }

    @ViewBuilder
    private var generic: some View {
        if let field = row.field {
            if CatalogInlineControl<ProfileProviderDefinitionEditorDraft>.isInline(field, access: access) {
                CatalogInlineControl(access: access, field: field, identifier: identifier)
            } else {
                switch field.kind {
                case .select, .suggest:
                    ClashRoutedViewLink {
                        CatalogChoicePage(access: access, options: ProxyNodeCatalog.offeredValues(for: field, written: access.text),
                                          allowsCustom: field.kind != .select, identifier: identifier)
                            .clashCatalogPageSeat()
                    } label: {
                        CatalogLabeledRow(title: title, value: access.words(fieldCopy))
                    }
                    .accessibilityIdentifier(identifier)
                case .number:
                    CatalogTextFieldRow(access: access, field: field, numeric: true, identifier: identifier)
                        .accessibilityIdentifier(identifier)
                case .text, .reference:
                    CatalogTextFieldRow(access: access, field: field, numeric: false, identifier: identifier)
                        .accessibilityIdentifier(identifier)
                case .textList, .multiSelect:
                    ClashRoutedViewLink {
                        CatalogListPage(access: access,
                                        options: field.kind == .textList ? nil : ProxyNodeCatalog.offeredValues(for: field),
                                        identifier: identifier)
                            .clashCatalogPageSeat()
                    } label: {
                        CatalogLabeledRow(title: title, value: access.words(fieldCopy))
                    }
                    .accessibilityIdentifier(identifier)
                case .objectList:
                    ClashRoutedViewLink {
                        CatalogObjectListPage(access: access,
                                              itemKeys: ProviderFieldCatalog.itemKeys(of: row.path, base: base, in: catalog),
                                              identifier: identifier)
                            .clashCatalogPageSeat()
                    } label: {
                        CatalogLabeledRow(title: title, value: access.objects.isEmpty
                                          ? .copy("Not set") : ConfigurationValueWords.itemCount(access.objects.count, locale: AppPreferences.language().locale))
                    }
                    .accessibilityIdentifier(identifier)
                case .toggle, .object, .map, .unrecognised:
                    CatalogLabeledRow(title: title, value: access.words(fieldCopy))
                        .accessibilityIdentifier(identifier)
                }
            }
        } else {
             
            CatalogLabeledRow(title: title, value: access.words(fieldCopy))
                .accessibilityIdentifier(identifier)
        }
    }
}

extension ProfileProviderDefinitionEditorDraft: CatalogEditableDraft {}

private struct ProviderHeaderDraft: Identifiable, Equatable {
    let id: UUID
    var name: String
    var value: String

    init(id: UUID = UUID(), name: String = "", value: String = "") {
        self.id = id
        self.name = name
        self.value = value
    }
}

private struct ProviderHeadersEditorView: View {
    @Environment(\.clashInsideProductModalPresentation)
    private var insideProductModal
    @Environment(\.clashPopRoute) private var popRoute
    @ObservedObject var draft: ProfileProviderDefinitionEditorDraft
    @Environment(\.presentationMode) private var presentationMode
    @State private var rows: [ProviderHeaderDraft]
     
     
    @State private var openedWith: [ProviderHeaderDraft] = []
    @State private var errorMessage = ""
     
    @State private var asksBeforeLeaving = false

    init(draft: ProfileProviderDefinitionEditorDraft) {
        self.draft = draft
        _rows = State(initialValue: draft.headers().map {
            ProviderHeaderDraft(name: $0.name, value: $0.value)
        })
    }

    var body: some View {
        Form {
            Section {
                ForEach($rows) { $row in
                    ClashMacDeletableRow(onDelete: {
                        if let index = rows.firstIndex(
                            where: { $0.id == row.id }
                        ) {
                            rows.remove(at: index)
                        }
                    }) {
                    VStack(alignment: .leading, spacing: 0) {
                        ClashFieldRow(
                            "Header Name",
                            hint: "Required",
                            text: $row.name,
                            identifier:
                                "provider-definition.header.name"
                        )
                            .disableAutocorrection(true)
                            .textInputAutocapitalization(.never)
                        Divider()
                        ClashFieldRow(
                            "Header Value",
                            hint: "Required",
                            text: $row.value,
                            secure: true,
                            identifier:
                                "provider-definition.header.value"
                        )
                    }
                    }
                }
                .onDelete { rows.remove(atOffsets: $0) }
                ClashAddRow(Text("Add Header")) {
                    rows.append(ProviderHeaderDraft())
                } touchLabel: {
                    Label("Add Header", systemImage: ClashSymbol.plus.name)
                }
                .accessibilityIdentifier(
                    "provider-definition.headers.add"
                )
            } footer: {
                Text("Header values are treated as credentials and are never shown in previews or diagnostics.")
            }
        }
        .clashInsetGroupedListStyle()
        .clashPageTitle("Request Headers")
        .clashDetailPageInsets()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                 
                if !insideProductModal {
                    Button("Done", action: persist)
                        .font(.body.weight(.semibold))
                        .accessibilityIdentifier("provider-headers.done")
                }
            }
        }
        .alert(
            "Headers could not be saved",
            isPresented: Binding(
                get: { !errorMessage.isEmpty },
                set: { if !$0 { errorMessage = "" } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = "" }
        } message: {
            Text(clash: .copy(errorMessage))
        }
         
         
         
        .clashProductModalChild(title: "Request Headers", backAction: {
            if rows == openedWith { closeAfterCommit() } else { asksBeforeLeaving = true }
        })
        .asksBeforeDroppingUntaken($asksBeforeLeaving, save: persist, discard: closeAfterCommit)
             
             
             
             
             
             
             
             
        .clashMacProductModalBar {
            if insideProductModal {
                     
                     
                     
                     
                     
                     
                     
                ClashModalActionBar(primaryTitle: "Done",
                                         
                     
                     
                     
                     
                     
                    primaryDisabled: rows == openedWith,
                    onPrimary: persist)
            }
        }
        .onAppear { if openedWith.isEmpty { openedWith = rows } }
    }

    private func persist() {
        let cleaned = rows.map {
            (name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines), value: $0.value)
        }.filter { !$0.name.isEmpty || !$0.value.isEmpty }
        guard cleaned.allSatisfy({ !$0.name.isEmpty && !$0.value.isEmpty }),
              Set(cleaned.map { $0.name.lowercased() }).count == cleaned.count else {
            errorMessage = ProfileProviderDefinitionError.invalidHeader.localizedDescription
            return
        }
        draft.replaceHeaders(cleaned)
        closeAfterCommit()
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private func closeAfterCommit() {
#if os(macOS)
        if let popRoute {
            popRoute(ClashPopToken())
        } else {
            presentationMode.wrappedValue.dismiss()
        }
#else
         
        presentationMode.wrappedValue.dismiss()
#endif
    }
}

private struct ProviderInlineProxyPayloadView: View {
    @ObservedObject var draft: ProfileProviderDefinitionEditorDraft

    var body: some View {
        Form {
            Section {
                ForEach(InlineProxyRow.rows(from: draft.proxyPayload())) { row in
                    if let mapping = row.mapping, let record = record(for: mapping) {
                        ClashRoutedViewLink {
                            ClashLazyView {
                                ProxyNodeDetailsView(
                                    record: record,
                                    retest: {},
                                    saveNode: { _, edited in
                                        try replaceProxy(id: row.id, json: edited)
                                    },
                                     
                                     
                                     
                                    allowsRename: false,
                                    showsTesting: false,
                                     
                                     
                                     
                                     
                                     
                                     
                                     
                                    commitTitle: "Done"
                                )
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                                Text(record.name)
                                    .foregroundStyle(.primary)
                                Text(record.protocolDetails?.displayName ?? record.type)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier(
                            "provider-definition.inline.proxy.\(record.name)"
                        )
                        .contextMenu {
                            Button(role: .destructive) {
                                remove(id: row.id)
                            } label: {
                                Label(
                                    "Delete Node",
                                    systemImage: ClashSymbol.trash.name
                                )
                            }
                            .accessibilityIdentifier(
                                "provider-definition.inline.proxy.\(record.name).delete"
                            )
                        }
                    }
                }
                .onDelete(perform: remove)
            } footer: {
                Text("Each inline node uses the same field-complete editor as the Proxies tab.")
            }
            Section {
                ClashAddRow(Text("Add Node"), action: addProxy) {
                    Label("Add Node", systemImage: ClashSymbol.plus.name)
                }
                .accessibilityIdentifier(
                    "provider-definition.inline.proxy.add"
                )
            }
        }
        .clashInsetGroupedListStyle()
        .clashPageTitle("Proxy Nodes")
        .clashDetailPageInsets()
        .accessibilityIdentifier("provider-definition.inline.proxy-payload")
        .clashProductModalChild(title: "Proxy Nodes")
    }

    private func record(for proxy: [String: Any]) -> ProxyNodeRecord? {
        guard let name = proxy["name"] as? String,
              let type = proxy["type"] as? String,
              let details = ProxyProtocolCatalog.details(for: proxy) else { return nil }
        return ProxyNodeRecord(
            name: name,
            type: type,
            delay: nil,
            groupNames: [],
            protocolDetails: details
        )
    }

     
     
     
    private func replaceProxy(id: String, json: String) throws {
        guard let value = try JSONSerialization.jsonObject(with: Data(json.utf8))
                as? [String: Any] else {
            throw ProfileProviderDefinitionError.invalidPayload
        }
        var payload = draft.proxyPayload()
        guard let index = InlineProxyRow.rows(from: payload)
            .firstIndex(where: { $0.id == id }),
              payload.indices.contains(index) else {
            throw ProfileProviderDefinitionError.invalidPayload
        }
        payload[index] = value
        draft.replaceProxyPayload(payload)
    }

    private func addProxy() {
        var payload = draft.proxyPayload()
        let names = Set(payload.compactMap { $0["name"] as? String })
        var candidate = "New Node"
        var suffix = 2
        while names.contains(candidate) {
            candidate = "New Node \(suffix)"
            suffix += 1
        }
        payload.append(["name": candidate, "type": "direct"])
        draft.replaceProxyPayload(payload)
    }

    private func remove(_ offsets: IndexSet) {
        let payload = draft.proxyPayload()
        let rows = InlineProxyRow.rows(from: payload)
         
         
         
        let doomed = Set(offsets.compactMap { rows.indices.contains($0) ? rows[$0].id : nil })
         
         
        draft.replaceProxyPayload(
            zip(payload, InlineProxyRow.identities(for: payload))
                .filter { _, id in id.map { !doomed.contains($0) } ?? true }
                .map(\.0)
        )
    }

    private func remove(id: String) {
        let payload = draft.proxyPayload()
        draft.replaceProxyPayload(
            zip(payload, InlineProxyRow.identities(for: payload))
                .filter { _, candidate in candidate != id }
                .map(\.0)
        )
    }
}

private struct ProviderInlineRuleRow: Identifiable, Equatable {
    let id = UUID()
    var value: String
}

private struct ProviderInlineRulePayloadView: View {
    @Environment(\.clashInsideProductModalPresentation)
    private var insideProductModal
    @Environment(\.clashPopRoute) private var popRoute
    @ObservedObject var draft: ProfileProviderDefinitionEditorDraft
    @Environment(\.presentationMode) private var presentationMode
    @State private var rows: [ProviderInlineRuleRow]
     
     
    @State private var openedWith: [ProviderInlineRuleRow] = []
     
    @State private var asksBeforeLeaving = false

    init(draft: ProfileProviderDefinitionEditorDraft) {
        self.draft = draft
        _rows = State(initialValue: draft.rulePayload().map(ProviderInlineRuleRow.init))
    }

    var body: some View {
        Form {
            Section {
                ForEach($rows) { $row in
                    HStack(spacing: ClashTheme.Spacing.compact) {
                        TextField("Rule", text: $row.value)
                            .font(.body.monospaced())
                            .disableAutocorrection(true)
                            .textInputAutocapitalization(.never)
                            .accessibilityIdentifier(
                                "provider-definition.inline.rule-value"
                            )
#if os(macOS)
                        Button(role: .destructive) {
                            rows.removeAll { $0.id == row.id }
                        } label: {
                            Image(systemName: ClashSymbol.trash.name)
                                .frame(
                                    width: ClashClientUI.ClashTheme.Control
                                        .minimumHitTarget,
                                    height: ClashClientUI.ClashTheme.Control
                                        .minimumHitTarget
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Delete Rule")
                        .accessibilityIdentifier(
                            "provider-definition.inline.rule.\(row.id).delete"
                        )
#endif
                    }
                }
                .onDelete { rows.remove(atOffsets: $0) }
            } footer: {
                VStack(alignment: .leading, spacing: ClashTheme.Spacing.compact) {
                    Text("Enter the payload syntax required by the selected rule-set behavior.")
                    Text(
                        clashAppleRuntimeProfile
                            .inlineRuleEditorNotice
                    )
                }
            }
            Section {
                ClashAddRow(Text("Add Rule")) {
                    rows.append(ProviderInlineRuleRow(value: ""))
                } touchLabel: {
                    Label("Add Rule", systemImage: ClashSymbol.plus.name)
                }
                .accessibilityIdentifier(
                    "provider-definition.inline.rule.add"
                )
            }
        }
        .clashInsetGroupedListStyle()
        .clashPageTitle("Inline Rules")
        .clashDetailPageInsets()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                 
                if !insideProductModal {
                    Button("Done", action: persist)
                        .font(.body.weight(.semibold))
                }
            }
        }
        .accessibilityIdentifier("provider-definition.inline.rule-payload")
         
        .clashProductModalChild(title: "Inline Rules", backAction: {
            if rows == openedWith { closeAfterCommit() } else { asksBeforeLeaving = true }
        })
        .asksBeforeDroppingUntaken($asksBeforeLeaving, save: persist, discard: closeAfterCommit)
             
             
             
             
             
             
             
             
        .clashMacProductModalBar {
            if insideProductModal {
                     
                     
                     
                     
                     
                     
                     
                ClashModalActionBar(primaryTitle: "Done",
                                         
                     
                     
                     
                     
                     
                    primaryDisabled: rows == openedWith,
                    onPrimary: persist)
            }
        }
        .onAppear { if openedWith.isEmpty { openedWith = rows } }
    }

    private func persist() {
        draft.replaceRulePayload(rows.map { $0.value }.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })
        closeAfterCommit()
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private func closeAfterCommit() {
#if os(macOS)
        if let popRoute {
            popRoute(ClashPopToken())
        } else {
            presentationMode.wrappedValue.dismiss()
        }
#else
         
        presentationMode.wrappedValue.dismiss()
#endif
    }
}
