import ClashClientKit
import ClashClientUI
import SwiftUI
import UniformTypeIdentifiers

 
 
 
 
 
 
 
 
 
 
 
 
enum AddProfilePurpose { case profile, source, rules }

struct AddProfileView: View {
     
     
    let purpose: AddProfilePurpose
    let dismissAfterSave: Bool
    let tabHeader: ((Bool) -> AnyView)?
    let sourceKind: ClashConfigurationSourceKind?
    let blankFileEntry: Bool
    let isFirstConfigurationStep: Bool
    let availableTabs: [AddProfileDraft.Tab]
    private var isSourceImport: Bool { purpose != .profile }
     
     
     
    let saveAsync: ((String, Profile.Source, String?, [ExternalResourceImportFile], Bool) async throws -> Void)?
    @State private var isSaving = false
    @Environment(\.locale) private var locale
     
     
     
    @State private var importingFile = false
    @State private var importGeneration = 0
    let registerSuppliedRules: Binding<Bool>?
    let importRuleCollection: (() -> Void)?
     
     
     
     
    let importRuleSet: ((ConfigurationRuleSetPrefill) -> Void)?
    let createEmpty: () -> Void
    let save: (String, Profile.Source, String?, [ExternalResourceImportFile]) -> Void

    init(initialTab: AddProfileDraft.Tab = .link, purpose: AddProfilePurpose = .profile, dismissAfterSave: Bool = true,
         availableTabs: [AddProfileDraft.Tab] = [.link, .file, .blank], tabHeader: ((Bool) -> AnyView)? = nil,
         sourceKind: ClashConfigurationSourceKind? = nil, blankFileEntry: Bool = false, isFirstConfigurationStep: Bool = false,
         registerSuppliedRules: Binding<Bool>? = nil, importRuleCollection: (() -> Void)? = nil,
         importRuleSet: ((ConfigurationRuleSetPrefill) -> Void)? = nil, createEmpty: @escaping () -> Void,
         saveAsync: ((String, Profile.Source, String?, [ExternalResourceImportFile], Bool) async throws -> Void)? = nil,
         save: @escaping (String, Profile.Source, String?, [ExternalResourceImportFile]) -> Void) {
        self.dismissAfterSave = dismissAfterSave
        self.saveAsync = saveAsync
        self.registerSuppliedRules = registerSuppliedRules
        self.importRuleCollection = importRuleCollection
        self.importRuleSet = importRuleSet
        self.purpose = purpose
        self.availableTabs = availableTabs
        self.tabHeader = tabHeader
        self.sourceKind = sourceKind
        self.blankFileEntry = blankFileEntry
        self.isFirstConfigurationStep = isFirstConfigurationStep
        self.createEmpty = createEmpty
        self.save = save
        var initialDraft = AddProfileDraft()
        initialDraft.tab = initialTab
        _draft = State(initialValue:initialDraft)
    }

     
     
     
     
     
     
    @StateObject private var dismiss = ClashDismissHandle()
    @Environment(\.clashInsideProductModalPresentation)
    private var insideProductModal

    @State private var draft = AddProfileDraft()
    @State private var importedResourceFiles: [ExternalResourceImportFile] = []
    @State private var showsImporter = false
    @State private var showsQRCapture = false
    @State private var showsQRPhotoPicker = false
    @State private var showsPastedEditor = false

    private var additionTitle: String {
        if isFirstConfigurationStep { return "Create Nodes 1/2" }
        switch purpose {
        case .profile: return ClashConfigurationAddition.configuration.title
        case .source: return ClashConfigurationAddition.nodes.title
        case .rules: return ClashConfigurationAddition.rules.title
        }
    }

     
     
     
    private var primaryActionTitle: String {
        isFirstConfigurationStep ? "Next" : (draft.tab == .blank ? "Create" : (purpose == .source ? "Import" : (dismissAfterSave ? "Add" : "Read")))
    }

    var body: some View {
        ClashFeatureNavigationContainer {
            Form {
                if tabHeader != nil && purpose == .rules && sourceKind == nil {
                    Section {
                        Picker("Import Method", selection: $draft.tab) {
                            Text("URL").tag(AddProfileDraft.Tab.link)
                            Text("File").tag(AddProfileDraft.Tab.file)
                        }.pickerStyle(.menu)
                            .accessibilityIdentifier("configuration.rules.add.method")
                    }
                }
                switch draft.tab {
                case .link:
                    linkSection
                case .file:
                    fileSection
                case .blank:
                    if blankFileEntry { fileSection }
                    blankPane
                }
                if let importRuleCollection {
                    Section {
                        Button("Import Rule Set", action: importRuleCollection)
                            .accessibilityIdentifier("configuration.rules.import-collection")
                    } footer: { Text("For MRS, Text or YAML rule sets.") }
                }
                 
                 
                 
                nameSection
                if let registerSuppliedRules {
                    Section { Toggle("Register Its Rules", isOn: registerSuppliedRules).accessibilityIdentifier("configuration.import.register-rules") }
                }
                if let requirement = draft.blockingRequirement,
                    !ClashPlatformLayout.pageUsesSystemSettingsIdiom
                {
                     
                     
                     
                     
                     
                     
                     
                    Section {
                        Text(clash: .copy(requirement))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                             
                             
                             
                             
                            .listRowBackground(
                                ClashPlatformLayout.pageUsesSystemSettingsIdiom
                                    ? Color.clear : nil
                            )
                            .accessibilityIdentifier("profile.add.blocked-reason")
                    }
                }
            }
             
             
             
             
             
             
             
             
             
             
             
            .clashPinnedTopBar {
                if let tabHeader { tabHeader(hasInput) }
                else if availableTabs.count > 1 { tabPickerBar }
            }
            .clashPageTitle(.copy(additionTitle))
             
             
             
             
             
             
             
             
             
             
             
            .clashRegistersDeparture(
                 
                 
                 
                 
                 
                isDirty: hasInput,
                isBusy: isSaving,
                save: { completion in submit(completion: completion) },
                discard: { draft = AddProfileDraft(); importedResourceFiles = []; registerSuppliedRules?.wrappedValue = true }
            )
            .disabled(isSaving)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !insideProductModal {
                        Button("Cancel") { dismissPresentation() }.disabled(isSaving)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !insideProductModal {
                         
                         
                         
                        if draft.tab == .blank {
                            Button { submit() } label: { ClashActionProgressLabel(.copy("Create"), isBusy: isSaving) }.disabled(isSaving)
                        } else {
                            Button { submit() } label: { ClashActionProgressLabel(.copy(isFirstConfigurationStep ? "Next" : (purpose == .source ? "Import" : (dismissAfterSave ? "Add" : "Read"))), isBusy: isSaving) }
                                .disabled(!draft.canSubmit || isSaving)
                        }
                    }
                }
            }
            .clashProductModalRoot(title: .copy(additionTitle))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if insideProductModal {
                    ClashModalActionBar(
                        primaryTitle: primaryActionTitle,
                        primaryDisabled: !draft.canSubmit || isSaving,
                         
                         
                         
                         
                         
                         
                         
                        primaryHint: draft.blockingRequirement,
                        isBusy: isSaving,
                        onPrimary: { submit() }
                    )
                }
            }
             
             
             
             
             
            .fileImporter(isPresented: $showsImporter,
                          allowedContentTypes: [.yaml, .plainText, .data],
                          allowsMultipleSelection: false) { result in
                importFile(result)
            }
            .clashProductModal(
                isPresented: $showsQRCapture,
                role: .page
            ) {
                 
                 
                 
                ClashFeatureNavigationContainer {
                    qrCapturePage
                        .clashPageTitle("Scan QR Code")
                        .clashToolbarUnlessInPanel {
                            ToolbarItem(placement: .cancellationAction) {
                                ClashSheetCloseButton { showsQRCapture = false }
                            }
                        }
                         
                         
                         
                         
                        .clashProductModalRoot(title: "Scan QR Code")
                }
                .clashModalPresentation(.page)
            }
            .clashProductModal(
                isPresented: $showsPastedEditor,
                role: .page
            ) {
                ClashFeatureNavigationContainer {
                    ZStack {
                        ClashTheme.canvas.ignoresSafeArea()
                        CodeEditorPanel(
                            text: $draft.pastedConfigText,
                            language: .yaml,
                            minHeight: 360,
                            expandsVertically: true
                        )
                        .padding(ClashTheme.Spacing.standard)
                    }
                    .clashPageTitle("Configuration")
                    .clashToolbarUnlessInPanel {
                        ToolbarItem(placement: .cancellationAction) {
                            ClashSheetCloseButton { showsPastedEditor = false }
                        }
                    }
                    .clashProductModalRoot(title: "Configuration")
                }
                .clashModalPresentation(.page)
            }
            .clashProductModal(
                isPresented: $showsQRPhotoPicker,
                role: .page
            ) {
                QRPhotoPicker { result in
                    showsQRPhotoPicker = false
                    acceptQRResult(result)
                }
                .clashModalPresentation(.page)
                .clashProductModalRoot(title: "Choose QR from Photos")
            }
        }
        .clashCapturesDismiss(dismiss)
         
         
         
        .onChange(of: draft.pastedConfigText) { _ in
            importGeneration &+= 1
            importingFile = false
        }
        .onChange(of: sourceKind) { kind in
            if let kind { draft.tab = kind == .file ? .file : .link }
        }
    }

    private var hasInput: Bool {
        var baseline = AddProfileDraft()
        baseline.tab = draft.tab
        return draft != baseline || !importedResourceFiles.isEmpty || registerSuppliedRules?.wrappedValue == false
    }

     

     
     
     
     
     
     
    private var tabPickerBar: some View {
         
         
         
         
         
         
         
         
         
         
         
         
         
         
#if os(macOS)
        HStack(spacing: 2) {
            if availableTabs.contains(.link) { addTabSegment(.link, "URL", identifier: "profile.add.tab.link") }
            if availableTabs.contains(.file) { addTabSegment(.file, "File", identifier: "profile.add.tab.file") }
            if availableTabs.contains(.blank) { addTabSegment(.blank, "Blank", identifier: "profile.add.blank") }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.07))
        )
         
         
         
         
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 2)
#else
         
         
         
         
         
        Picker(ClashCopy.key("Type"), selection: $draft.tab) {
            if availableTabs.contains(.link) { Text(ClashCopy.key("URL")).tag(AddProfileDraft.Tab.link) }
            if availableTabs.contains(.file) { Text(ClashCopy.key(availableTabs.contains(.link) ? "File" : "Import File")).tag(AddProfileDraft.Tab.file) }
            if availableTabs.contains(.blank) { Text(ClashCopy.key(availableTabs.contains(.link) ? "Blank" : "New Blank File")).tag(AddProfileDraft.Tab.blank) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityIdentifier("profile.add.tab")
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 2)
#endif
    }

    private func addTabSegment(
        _ tab: AddProfileDraft.Tab,
        _ key: String,
         
         
         
        identifier: String
    ) -> some View {
        Button {
            draft.tab = tab
        } label: {
            Text(ClashCopy.key(key))
                .font(.callout.weight(draft.tab == tab ? .semibold : .regular))
                .frame(maxWidth: .infinity, minHeight: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            if draft.tab == tab {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selectedSegmentFill)
                    .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
            }
        }
        .accessibilityIdentifier(identifier)
         
         
         
         
        .accessibilityAddTraits(draft.tab == tab ? .isSelected : [])
    }

    private var selectedSegmentFill: Color {
#if os(macOS)
        Color(nsColor: .controlColor)
#else
        Color(uiColor: .secondarySystemGroupedBackground)
#endif
    }

     
     
    private var nameSection: some View {
        Section {
            ClashFieldRow(
                "Name",
                hint: "Optional",
                text: $draft.label,
                identifier: "profile.add.name"
            )
        } footer: {
            Text(ClashCopy.key(
                isSourceImport ? "Leave blank to use the source's suggested name."
                    : "Leave this empty and the profile takes its name from the source."
            ))
                .addPanelMacLeadingFooter()
        }
    }

     
     
     
     
     
     
     
     
    private var linkSection: some View {
        Section {
             
             
            HStack(spacing: ClashTheme.Spacing.standard) {
                linkField
                ClashPasteControl { draft.acceptPaste($0) }
            }

             
             
             
             
             
            switch draft.crossReference {
            case .configTextBelongsInFile:
                 
                 
                 
                 
                 
                HStack(alignment: .firstTextBaseline) {
                    ClashStatusMessage(
                        text: .copy("That is YAML text, not a Profile URL."),
                        kind: .warning
                    )
                    Spacer(minLength: ClashTheme.Spacing.compact)
                    Button(ClashCopy.key("Move to File")) {
                        draft.movePendingConfigTextToFileTab()
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("profile.add.cross-reference")
                }
            case .nodeBelongsInCustomNodes:
                 
                 
                 
                ClashStatusMessage(
                    text: .copy(isSourceImport ? "That is a node share link. Use Add Custom Node in the source library."
                        : "That is a node, not a profile URL. Add it under a profile's Custom Nodes."),
                    kind: .warning
                )
                .accessibilityIdentifier("profile.add.cross-reference")
            case nil:
                EmptyView()
            }

            Button {
                showsQRCapture = true
            } label: {
                Label("Scan QR Code", systemImage: ClashSymbol.qrcodeViewfinder.name)
                     
                     
                     
                    .frame(
                        maxWidth: ClashPlatformLayout.pageUsesSystemSettingsIdiom
                            ? nil : .infinity,
                        alignment: .leading
                    )
            }
            .clashMacListAddChrome()
            .foregroundStyle(.primary)
            .accessibilityIdentifier("profile.add.qr")

            if !draft.importError.isEmpty {
                ClashStatusMessage(text: importErrorText, kind: .error)
                nodesOnlyButton
            }
            if !draft.importNotice.isEmpty {
                ClashStatusMessage(text: .copy(draft.importNotice), kind: .warning)
                    .accessibilityIdentifier("profile.add.skipped")
            }
        } header: {
            Text(ClashCopy.key("Paste Profile URL"))
        } footer: {
            if let linkFooterText {
                Text(clash: linkFooterText)
                    .addPanelMacLeadingFooter()
            }
        }
    }

     
     
     
     
    @ViewBuilder
    private var linkField: some View {
        Group {
             
             
             
            if #available(iOS 16.0, macOS 13.0, *) {
                TextField(
                    "",
                    text: $draft.linkText,
                     
                     
                     
                     
                     
                    prompt: Text(verbatim: "https://example.com/config.yaml"),
                    axis: .vertical
                )
                    .accessibilityIdentifier("profile.add.link")
                .lineLimit(1...6)
            } else {
                TextField(
                    "",
                    text: $draft.linkText,
                    prompt: Text(verbatim: "https://example.com/config.yaml")
                )
                    .accessibilityIdentifier("profile.add.paste")
            }
        }
#if !os(macOS)
        .keyboardType(.URL)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
#endif
        .frame(maxWidth: .infinity)
         
         
         
         
         
        .labelsHidden()
        .multilineTextAlignment(.leading)
        .accessibilityIdentifier("profile.add.link")
        .onChange(of: draft.linkText) { _ in draft.normalizeLinkText() }
    }

     
     
     
    @ViewBuilder
    private var fileSection: some View {
        if blankFileEntry {
            Section {
                Button {
                    draft.tab = draft.tab == .blank ? .file : .blank
                } label: {
                    HStack {
                        Label(ClashCopy.key("New Blank File"), systemImage: ClashSymbol.docBadgePlus.name).foregroundStyle(.primary)
                        Spacer()
                        if draft.tab == .blank { Image(systemName: ClashSymbol.checkmark.name) }
                    }
                }
            }
        }
        if draft.tab != .blank {
        Section {
            Button {
                showsImporter = true
            } label: {
                 
                 
                 
                 
                Label {
                    if draft.importedFileName.isEmpty {
                        Text(ClashCopy.key("Choose Clash YAML File"))
                    } else {
                        Text(verbatim: draft.importedFileName)
                    }
                } icon: {
                    Image(systemName: ClashSymbol.docBadgePlus.name)
                }
            }
            .clashMacListAddChrome()
            .foregroundStyle(.primary)
            .accessibilityIdentifier("profile.add.file")

             
             
            ForEach(draft.importedResourceNames, id: \.self) { name in
                Label(name, systemImage: ClashSymbol.docText.name)
                    .foregroundStyle(.secondary)
            }

            if !draft.importError.isEmpty {
                ClashStatusMessage(text: importErrorText, kind: .error)
                nodesOnlyButton
            }
            if !draft.importNotice.isEmpty {
                ClashStatusMessage(text: .copy(draft.importNotice), kind: .warning)
                    .accessibilityIdentifier("profile.add.skipped")
            }
        } footer: {
            Text(ClashCopy.key(
                "Select one YAML file plus any certificates or keys it references. Clash copies only the files you explicitly select."
            ))
                .addPanelMacLeadingFooter()
        }

        Section {
            HStack {
                Text(ClashCopy.key("Paste YAML text"))
                Spacer()
                ClashPasteControl { pasted in
                     
                     
                     
                    importGeneration &+= 1
                    importingFile = false
                    draft.acceptConfigTextPaste(pasted)
                     
                     
                     
                    guard !draft.pastedConfigText.isEmpty else { return }
                    let text = draft.pastedConfigText
                    Task {
                        let derived = await Task.detached(priority: .userInitiated) {
                            try? ProxyImportBridge.derivedSubscription(
                                from: Data(text.utf8)
                            )
                        }.value
                         
                        guard let derived, draft.pastedConfigText == text else { return }
                        draft.importNotice = Self.skippedNotice(derived.kept, derived.skipped)
                    }
                }
            }

             
             
            if !draft.configPreviewLines.isEmpty {
                VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                    ForEach(Array(draft.configPreviewLines.enumerated()), id: \.offset) {
                        Text($0.element)
                    }
                }
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("profile.add.config-preview")
            }

             
             
             
             
            if !draft.pastedConfigText.isEmpty {
                Button {
                    showsPastedEditor = true
                } label: {
                    HStack {
                        Text(clash: draft.pastedConfigSummary.map {
                            .format("Review all %@ lines", [$0])
                        } ?? .copy("Review the profile"))
                        Spacer()
                        Image(systemName: ClashSymbol.chevronForward.name)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("profile.add.review-config")
            }
        } footer: {
            Text(ClashCopy.key("Read a profile from the clipboard."))
                .addPanelMacLeadingFooter()
        }
    }
    }

     
     
     
     
    private var blankPane: some View {
        Section {
        } footer: {
            Text(ClashCopy.key(
                isSourceImport ? "Create an empty source, then add nodes and rules."
                    : "You can start without a profile URL: everything goes direct, and you add nodes and rules yourself."
            ))
                .addPanelMacLeadingFooter()
        }
    }

     
     
     
    @ViewBuilder
    private var qrCapturePage: some View {
#if os(macOS)
         
         
        Form {
            Section {
                Button {
                    showsQRCapture = false
                    showsQRPhotoPicker = true
                } label: {
                    Label("Choose QR Image", systemImage: ClashSymbol.photo.name).foregroundStyle(.primary)
                }
                .accessibilityIdentifier("profile.add.qr.file")
            }
        }
#else
        Form {
            Section {
                QRScannerView { code in
                    showsQRCapture = false
                    acceptQRCode(code)
                }
                 
                .aspectRatio(1, contentMode: .fit)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: ClashTheme.Radius.card,
                        style: .continuous
                    )
                )
            }
            Section {
                Button {
                    showsQRCapture = false
                    showsQRPhotoPicker = true
                } label: {
                    Label("Choose QR from Photos", systemImage: ClashSymbol.photo.name).foregroundStyle(.primary)
                }
                .accessibilityIdentifier("profile.add.qr.photos")
            }
        }
#endif
    }

     

     
     
     
    private var linkFooterText: ClashDisplayText? {
        switch draft.linkFooter {
        case .accepts:
            return nil
        case .downloadsOverHTTPS:
            return .copy(
                isSourceImport ? "The source is downloaded before it is saved."
                    : "Clash downloads the profile URL when the profile is activated."
            )
        case .cleartextWarning:
            return .copy(
                "HTTP is not encrypted. Credentials in the address travel in the clear."
            )
        case .unwrappedInstallLink(let host):
            return .format("Install link. The profile URL inside is %@.", [host])
        }
    }

     

    private func submit(nodesOnly: Bool = false, completion: @escaping (Bool) -> Void = { _ in }) {
        guard !isSaving, !importingFile else { completion(false); return }
        switch draft.tab {
        case .blank:
            if purpose == .profile {
                createEmpty(); completion(true); dismissPresentation(); return
            }
            deliver((draft.label.isEmpty ? "Direct" : draft.label, .file("Direct.yaml"), ConfigurationBuiltins.directYAML, []),
                    completion: completion)
        case .link:
            deliver((draft.label, .url(draft.resolvedLink), nil, []), nodesOnly: nodesOnly, completion: completion)
        case .file:
            submitDocument(label: draft.label, imported: draft.importedYAML, fileName: draft.importedFileName,
                           pasted: draft.pastedConfigText, files: importedResourceFiles, nodesOnly: nodesOnly,
                           completion: completion)
        }
    }

     
     
     
     
     
    private func submitDocument(label: String, imported: String, fileName: String, pasted: String,
                                files: [ExternalResourceImportFile], nodesOnly: Bool,
                                completion: @escaping (Bool) -> Void) {
        isSaving = true
        Task { @MainActor in
            if imported.isEmpty, let importRuleSet,
               let prefill = await ConfigurationRuleSetPrefill.local(label: label, fileName: "", data: Data(pasted.utf8)) {
                isSaving = false
                importRuleSet(prefill)
                completion(false)
                return
            }
            do {
                let value: SubmittedSource = try await Task.detached(priority: .userInitiated) {
                    if !imported.isEmpty {
                        try ConfigTransforms.validateSource(imported)
                        return (label, .file(fileName), imported, files)
                    }
                    let yaml = try ProxyImportBridge.derivedSubscriptionYAML(from: Data(pasted.utf8), nodesOnly: nodesOnly)
                    return (label, .clipboard, yaml, [])
                }.value
                isSaving = false
                deliver(value, nodesOnly: nodesOnly, completion: completion)
            } catch {
                isSaving = false
                 
                 
                draft.fail(safeImportMessage(error), error: error, answering: Self.nodesOnlyInput(imported.isEmpty ? .text(pasted) : nil, purpose: purpose))
                completion(false)
            }
        }
    }

     
     
     
     
     
    private func importNodesOnly() {
        guard let offer = draft.nodesOnlyOffer else { return }
        switch Self.nodesOnlyReplay(offer, label: draft.label) {
        case .fetchLink(let label, let url):
            deliver((label, .url(url), nil, []), nodesOnly: true) { _ in }
        case .readText(let label, let text):
            submitDocument(label: label, imported: "", fileName: "", pasted: text, files: [], nodesOnly: true) { _ in }
        case .readFile(let file):
            derive(file, nodesOnly: true) { submit() }
        }
    }

    @ViewBuilder
    private var nodesOnlyButton: some View {
        if let offer = draft.nodesOnlyOffer {
            Button(Self.nodesOnlyOfferTitle(nodes: offer.nodes, locale: locale)) { importNodesOnly() }
                .disabled(isSaving || importingFile)
                .accessibilityIdentifier("profile.add.import.nodesOnly")
        }
    }

    private var importErrorText: ClashDisplayText {
        draft.importErrorIsVerbatim ? .verbatim(draft.importError) : .copy(draft.importError)
    }

    typealias NodesOnlyOffer = AddProfileDraft.NodesOnlyOffer
    typealias PickedFile = AddProfileDraft.PickedFile

     
     
    enum NodesOnlyReplay: Equatable {
        case fetchLink(label: String, url: String)
        case readText(label: String, text: String)
        case readFile(PickedFile)
    }

    static func nodesOnlyReplay(_ offer: NodesOnlyOffer, label: String) -> NodesOnlyReplay {
        switch offer.input {
        case .link(let url): return .fetchLink(label: label, url: url)
        case .text(let text): return .readText(label: label, text: text)
        case .file(let file): return .readFile(file)
        }
    }

     
     
     
    static func nodesOnlyInput(_ input: NodesOnlyOffer.Input?, purpose: AddProfilePurpose) -> NodesOnlyOffer.Input? {
        purpose == .rules ? nil : input
    }

    static func nodesOnlyOfferTitle(nodes: Int, locale: Locale = .current) -> String {
        String(format: ClashCopy.string("Import only its %d nodes", locale: locale), nodes)
    }

    private typealias SubmittedSource = (String, Profile.Source, String?, [ExternalResourceImportFile])

    private func deliver(_ value: SubmittedSource, nodesOnly: Bool = false, completion: @escaping (Bool) -> Void) {
        if let saveAsync {
            isSaving = true
            Task { @MainActor in
                do {
                    try await saveAsync(value.0, value.1, value.2, value.3, nodesOnly)
                    isSaving = false
                    completion(true)
                    if dismissAfterSave { dismissPresentation() }
                } catch {
                     
                     
                    if let set = error as? ConfigurationLinkIsARuleSet, let importRuleSet {
                        isSaving = false
                        importRuleSet(.link(set.link, found: set.found, label: value.0))
                        completion(false)
                        return
                    }
                    isSaving = false
                     
                     
                    var answering: NodesOnlyOffer.Input?
                    if case .url(let url) = value.1 { answering = .link(url) }
                    draft.fail(safeImportMessage(error), error: error, answering: Self.nodesOnlyInput(answering, purpose: purpose))
                    completion(false)
                }
            }
        } else {
            save(value.0, value.1, value.2, value.3)
            completion(true)
            dismissPresentation()
        }
    }

    private func dismissPresentation() {
        dismiss.closeModalOrDismiss()
    }

    private func acceptQRResult(_ result: Result<String, Error>?) {
        guard let result else { return }
        switch result {
        case .success(let code): acceptQRCode(code)
        case .failure(let error): draft.fail(error.localizedDescription)
        }
    }

     
     
     
    private func acceptQRCode(_ code: String) {
        draft.clearImportFeedback()
        draft.tab = .link
        draft.acceptPaste(code)
    }

    private func importFile(_ result: Result<[URL], Error>) {
        draft.clearImportFeedback()
         
        importGeneration &+= 1
        importingFile = false
        switch result {
        case .failure(let error):
            draft.fail(safeImportMessage(error))
        case .success(let urls):
            let yamlURL: URL
            let selected: [ExternalResourceImportFile]
            let yamlFile: ExternalResourceImportFile
            do {
                guard let found = AddProfileDraft.configurationFile(among: urls) else {
                    throw ProfileInstallLinkError.unsupportedFile
                }
                yamlURL = found
                 
                 
                selected = try urls.map { url -> ExternalResourceImportFile in
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                     
                    let data = try ImportedFileBytes.readForImport(url)
                    guard !data.isEmpty else { throw ProfileInstallLinkError.unreadableFile }
                    return ExternalResourceImportFile(
                        fileName: url.lastPathComponent,
                        data: data
                    )
                }
                guard let file = selected.first(where: {
                    $0.fileName == yamlURL.lastPathComponent
                }) else {
                    throw ProfileInstallLinkError.unreadableFile
                }
                yamlFile = file
            } catch {
                draft.fail(safeImportMessage(error))
                return
            }
             
             
             
             
             
             
             
            derive(PickedFile(name: yamlURL.lastPathComponent, bytes: yamlFile.data, selected: selected))
        }
    }

    private func derive(_ file: PickedFile, nodesOnly: Bool = false, then continuation: @escaping () -> Void = {}) {
        let bytes = file.bytes
        let generation = importGeneration
        importingFile = true
        Task { @MainActor in
            defer { if generation == importGeneration { importingFile = false } }
            if let importRuleSet,
               let prefill = await ConfigurationRuleSetPrefill.local(label: draft.label, fileName: file.name, data: bytes) {
                guard generation == importGeneration else { return }
                importRuleSet(prefill)
                return
            }
            do {
                let derived = try await Task.detached(priority: .userInitiated) {
                    try ProxyImportBridge.derivedSubscription(from: bytes, nodesOnly: nodesOnly)
                }.value
                guard generation == importGeneration else { return }
                importedResourceFiles = file.selected.filter { $0.fileName != file.name }
                draft.acceptImportedFile(
                    name: file.name,
                    yaml: derived.yaml,
                    resourceNames: importedResourceFiles.map(\.fileName)
                )
                draft.importNotice = Self.skippedNotice(derived.kept, derived.skipped)
                importingFile = false
                continuation()
            } catch {
                guard generation == importGeneration else { return }
                draft.fail(safeImportMessage(error), error: error, answering: Self.nodesOnlyInput(.file(file), purpose: purpose))
            }
        }
    }

     
     
     
     
     
    static func skippedNotice(
        _ kept: Int,
        _ skipped: [ProxyImportIssue],
        locale: Locale = .current
    ) -> String {
        guard !skipped.isEmpty else { return "" }
         
         
         
         
        let head = String(
            format: ClashCopy.string("Added %d, skipped %d.", locale: locale),
            kept, skipped.count
        )
         
         
         
        return ([head] + skipped.map { issue in
            issue.line.map { "\($0): \(issue.message)" } ?? issue.message
        }).joined(separator: "\n")
    }

     
     
     
     
    private func safeImportMessage(_ error: Error) -> String {
        guard let failure = ConfigurationFailureClassifier.classify(
            error,
            context: .localImport,
            preservesLastKnownGood: false
        ) else { return ClashCopy.string("The profile could not be imported.", locale: locale) }
        return ProfileSwitchFailureText.cardText(for: failure, locale: locale)
    }
}

 
 
 
private extension View {
     
     
     
    @ViewBuilder
    func addPanelMacLeadingFooter() -> some View {
        if ClashPlatformLayout.pageUsesSystemSettingsIdiom {
             
             
             
             
            multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            self
        }
    }
}
