import AppKit
import ClashClientKit
import ClashClientUI
import SwiftUI
import UniformTypeIdentifiers

 
 
 
 
 
 
 
public struct ClashMacSourceImportActions {
     
    public var fetch: @MainActor (String, String) async throws -> ConfigurationSourcePayload
     
     
     
     
     
    public var readFile: @MainActor (String, Data, [ClashMacImportResourceFile]) async throws -> ConfigurationSourcePayload
     
     
    public var fetchNodesOnly: (@MainActor (String, String) async throws -> ConfigurationSourcePayload)?
    public var readFileNodesOnly: (@MainActor (String, Data, [ClashMacImportResourceFile]) async throws -> ConfigurationSourcePayload)?
     
     
     
     
    public var fileBytes: (URL) throws -> Data = { try Data(contentsOf: $0) }
     
     
     
     
    public var readPasted: (@MainActor (String, String, [ClashMacImportResourceFile], Bool) async throws -> ConfigurationSourcePayload)?
     
     
     
    public var refusedNodeCount: ((Error) -> Int?)?
     
     
     
    public var importOriginal: (@MainActor (ConfigurationSourcePayload) async throws -> Void)?
     
     
    public var readNodes: (@MainActor (String) async throws -> ConfigurationSourcePayload)?
     
     
     
    public var createQuickRule: (@MainActor (String, Bool, String) async throws -> Void)?
     
     
     
    public var quickRuleTargets: (@MainActor () async throws -> [String])?
     
     
    public var geoValues: ClashMacGeoValueLoader?
     
     
    public var addRuleSet: (@MainActor (ClashMacRuleSetImportDraft) async throws -> Void)?
     
     
     
     
     
    public var ruleSetAtLink: (@MainActor (String, Error) async -> (found: ClashRuleSetSniff.Found, link: String)?)?
     
     
     
    public var fetchRules: (@MainActor (String, String) async throws -> ConfigurationSourcePayload)?
     
     
     
    public var ruleSetIn: (@MainActor (Data) async -> ClashRuleSetSniff.Found?)?
     
     
     
     
    public var customNodesEditor: ((_ accept: @escaping (ConfigurationSourcePayload) async throws -> Void, _ close: @escaping () -> Void) -> AnyView)? = nil

    public init(
        fetch: @escaping @MainActor (String, String) async throws -> ConfigurationSourcePayload,
        readFile: @escaping @MainActor (String, Data, [ClashMacImportResourceFile]) async throws -> ConfigurationSourcePayload,
        importOriginal: (@MainActor (ConfigurationSourcePayload) async throws -> Void)? = nil,
        readNodes: (@MainActor (String) async throws -> ConfigurationSourcePayload)? = nil,
        createQuickRule: (@MainActor (String, Bool, String) async throws -> Void)? = nil
    ) {
        self.fetch = fetch
        self.readFile = readFile
        self.importOriginal = importOriginal
        self.readNodes = readNodes
        self.createQuickRule = createQuickRule
    }

    public static var unavailable: ClashMacSourceImportActions {
        ClashMacSourceImportActions(
            fetch: { _, _ in throw ConfigurationLibraryError.unreadable },
            readFile: { _, _, _ in throw ConfigurationLibraryError.unreadable }
        )
    }
}

 
 
public struct ClashMacImportResourceFile: Equatable, Sendable {
    public let fileName: String
    public let data: Data
    public init(fileName: String, data: Data) { self.fileName = fileName; self.data = data }
}

 
 
public enum ClashMacSourceImportPurpose: Sendable {
    case nodes, rules
}

 
 
 
 
 
 
 
 
 
 
public struct ClashMacSourceImportSheet: View {
    @Environment(\.clashMacEditorSyntax) private var syntax
    public enum Tab: Int, CaseIterable, Identifiable {
        case link, file, nodes, manual
        public var id: Int { rawValue }
        var title: String {
            switch self {
            case .link: "URL"
            case .file: "File"
            case .nodes: "Node"
             
             
             
             
            case .manual: "quick-add.new.rules"
            }
        }
    }

    private let purpose: ClashMacSourceImportPurpose
    private let actions: ClashMacSourceImportActions
    private let accept: (ConfigurationSourcePayload) async throws -> Void
    private let close: () -> Void
     
    private let closeTitle: ClashDisplayText
    @Environment(\.locale) private var locale
    @Environment(\.configurationFieldCopy) private var copy
    @State private var tab: Tab = .link
    @State private var url = ""
    @State private var label = ""
    @State private var fileName = ""
     
    @State private var suggestedLabel: String?
     
     
    @State private var text = ""
     
    @State private var largeFile: LargeFile?
    @State private var nodesText = ""
    @State private var choosingFile = false
    @State private var preview: ConfigurationSourcePayload?
    @State private var busy = false
    @State private var error: String?
     
     
     
     
    struct NodesOnlyOffer {
         
         
         
         
        enum Input {
            case link(url: String)
            case file(name: String, data: Data, resources: [ClashMacImportResourceFile])
            case pasted(text: String, resources: [ClashMacImportResourceFile])
        }
        let nodes: Int
        let input: Input
        let operation: (ConfigurationSourcePayload) async throws -> Void
    }
    @State private var nodesOnlyOffer: NodesOnlyOffer?

     
     
     
    static func offersNodesOnly(purpose: ClashMacSourceImportPurpose, tab: Tab) -> Bool {
        purpose == .nodes && (tab == .link || tab == .file)
    }

     
     
     
     
    static func readsAsPasted(purpose: ClashMacSourceImportPurpose, tab: Tab, fileName: String) -> Bool {
        purpose == .nodes && tab == .file && fileName.isEmpty
    }

     
     
     
    static func labelAfterPaste(_ label: String, suggested: String?) -> String {
        label == suggested ? "" : label
    }

     
     
     
    @MainActor
    static func readFileTab(purpose: ClashMacSourceImportPurpose, fileName: String, label: String, text: String,
                            bytes: Data? = nil, resources: [ClashMacImportResourceFile],
                            actions: ClashMacSourceImportActions) async throws -> ConfigurationSourcePayload {
        if readsAsPasted(purpose: purpose, tab: .file, fileName: fileName), let readPasted = actions.readPasted {
            return try await readPasted(label, text, resources, false)
        }
        let name = fileName.isEmpty ? "Configuration.yaml" : fileName
        return try await actions.readFile(label.isEmpty ? name : label, bytes ?? Data(text.utf8), resources)
    }

     
    static func fileTabInput(purpose: ClashMacSourceImportPurpose, fileName: String, text: String,
                             bytes: Data? = nil, resources: [ClashMacImportResourceFile],
                             actions: ClashMacSourceImportActions) -> NodesOnlyOffer.Input {
        if readsAsPasted(purpose: purpose, tab: .file, fileName: fileName), actions.readPasted != nil {
            return .pasted(text: text, resources: resources)
        }
        return .file(name: fileName.isEmpty ? "Configuration.yaml" : fileName, data: bytes ?? Data(text.utf8),
                     resources: resources)
    }

     
     
     
     
     
     
     
    nonisolated public static let textBytesAtMost = 4 * 1_048_576

     
     
     
    struct LargeFile: Equatable {
        let id = UUID()
        let bytes: Data
         
        let size: String

        init(bytes: Data) {
            self.bytes = bytes
            size = ByteCountFormatter.string(fromByteCount: Int64(bytes.count), countStyle: .file)
        }

        static func == (lhs: LargeFile, rhs: LargeFile) -> Bool { lhs.id == rhs.id }
    }

     
    enum PickedConfiguration {
        case text(String)
        case large(LargeFile)
    }

     
     
    nonisolated static func pickedConfiguration(_ bytes: Data, keepsBinaryRuleSet: Bool = false) throws -> PickedConfiguration {
        guard bytes.count <= textBytesAtMost else { return .large(LargeFile(bytes: bytes)) }
        guard let text = String(data: bytes, encoding: .utf8) else {
             
             
            if keepsBinaryRuleSet, ClashRuleSetSniff.ruleSet(in: bytes)?.format == "mrs" { return .large(LargeFile(bytes: bytes)) }
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return .text(text)
    }

     
    @MainActor
    static func readNodesOnly(_ input: NodesOnlyOffer.Input, label: String,
                              actions: ClashMacSourceImportActions) async throws -> ConfigurationSourcePayload {
        let payload: ConfigurationSourcePayload
        switch input {
        case let .link(url):
            guard let fetch = actions.fetchNodesOnly else { throw ConfigurationLibraryError.unreadable }
            payload = try await fetch(url, label)
        case let .file(name, data, resources):
            guard let read = actions.readFileNodesOnly else { throw ConfigurationLibraryError.unreadable }
            payload = try await read(label.isEmpty ? name : label, data, resources)
        case let .pasted(text, resources):
            guard let read = actions.readPasted else { throw ConfigurationLibraryError.unreadable }
            payload = try await read(label, text, resources, true)
        }
        return payload
    }
    @State private var ruleAction: ClashStructuredRule.Action = .domainSuffix
    @State private var ruleContent = ""
    @State private var ruleTarget = "DIRECT"
    @State private var ruleEnabled = true
    @State private var ruleComment = ""
    @State private var ruleTargets: [String] = ["DIRECT", "REJECT"]
     
    @State private var pickingGeo = false
    @State private var pickedFrom: ClashMacGeoResource?
    @State private var resources: [ClashMacImportResourceFile] = []
    @State private var pendingTab: Tab?
    @State private var confirmsTabDiscard = false
    @State private var importingRuleSet = false
     
     
    @State private var ruleSetDraft = ClashMacRuleSetImportDraft()
    @State private var reviewsText = false

    public init(
        purpose: ClashMacSourceImportPurpose,
        actions: ClashMacSourceImportActions,
        initialTab: Tab = .link,
        closeTitle: ClashDisplayText = .copy("Cancel"),
        accept: @escaping (ConfigurationSourcePayload) async throws -> Void,
        close: @escaping () -> Void
    ) {
        self.purpose = purpose
        self.actions = actions
        _tab = State(initialValue: initialTab)
        self.closeTitle = closeTitle
        self.accept = accept
        self.close = close
    }

     
     
    private var tabs: [Tab] {
        var result: [Tab] = [.link, .file]
        if purpose == .nodes, actions.readNodes != nil { result.append(.nodes) }
        if purpose == .rules, actions.createQuickRule != nil { result.append(.manual) }
        return result
    }

    private var title: ClashDisplayText {
        purpose == .nodes ? .copy("Create Nodes") : .copy("Create Rules")
    }

    private var subtitle: ClashDisplayText {
        switch tab {
        case .link: purpose == .rules ? .copy("Profile URL or Rule Set Link") : .copy("Profile URL or Share Link")
        case .file: .copy("File")
        case .nodes: .copy("Custom Nodes")
        case .manual: .copy("Add Rule")
        }
    }

    private var assembledRule: String {
        var parts = [ruleAction.rawValue]
        if ruleAction.needsContent { parts.append(ruleContent.trimmingCharacters(in: .whitespacesAndNewlines)) }
        parts.append(ruleTarget)
        return parts.joined(separator: ",")
    }

     
     
     
    private var canAdd: Bool {
        if tab == .manual {
            return (!ruleAction.needsContent || !ruleContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) && !busy && !pickingGeo
        }
        return canRead
    }

    private var canRead: Bool {
        switch tab {
        case .link: !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !busy
        case .file: (!text.isEmpty || largeFile != nil) && !busy
        case .nodes: !nodesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !busy
        case .manual: false
        }
    }

     
     
    private var offersOriginalImport: Bool {
        purpose == .nodes && actions.importOriginal != nil && (tab == .link || tab == .file)
    }

    public var body: some View {
        if importingRuleSet, let addRuleSet = actions.addRuleSet {
             
            ClashMacRuleSetImportForm(add: addRuleSet, back: { importingRuleSet = false }, done: close, initial: ruleSetDraft,
                                      readRuleSet: actions.ruleSetIn)
        } else {
            importBody
        }
    }

     
    private var tabIsDirty: Bool {
        switch tab {
        case .link: !url.isEmpty || !label.isEmpty
        case .file: !text.isEmpty || !fileName.isEmpty || !label.isEmpty
        case .nodes: !nodesText.isEmpty
        case .manual: !ruleContent.isEmpty
        }
    }

     
     
    private func requestTab(_ next: Tab) {
        guard next != tab, !busy else { return }
        if tabIsDirty {
            pendingTab = next
            confirmsTabDiscard = true
        } else {
            tab = next
        }
    }

    private func discardTabAndSwitch() {
        switch tab {
        case .link: url = ""; label = ""
        case .file: text = ""; largeFile = nil; fileName = ""; label = ""; suggestedLabel = nil; resources = []
        case .nodes: nodesText = ""
        case .manual: ruleContent = ""
        }
        if let pendingTab { tab = pendingTab }
        pendingTab = nil
    }

    private var importBody: some View {
        ClashMacSheetFrame(
            title: pickingGeo ? (ruleAction.clashMacGeoResource?.rowTitle ?? title) : title,
            subtitle: pickingGeo ? nil : subtitle,
            width: 560, height: 540
        ) {
            if pickingGeo, let resource = ruleAction.clashMacGeoResource, let load = actions.geoValues {
                ClashMacGeoValuePickerPage(
                    resource: resource, current: ruleContent, load: load,
                    identifier: "configuration-center.import.manual.geo"
                ) { picked in
                    ruleContent = picked
                    pickedFrom = resource
                    pickingGeo = false
                }
            } else {
            VStack(spacing: 0) {
                Picker(selection: Binding(get: { tab }, set: { requestTab($0) })) {
                    ForEach(tabs) { item in
                        Text(clash: .copy(item.title)).tag(item)
                    }
                } label: {
                    Text(clash: title)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .padding(.top, 16)
                .accessibilityIdentifier("configuration-center.import.tabs")
                if tab == .nodes, let editor = actions.customNodesEditor {
                     
                     
                     
                    editor(accept, close)
                        .accessibilityIdentifier("configuration-center.import.nodes")
                } else {
                ClashMacSheetForm {
                    switch tab {
                    case .link: linkSection
                    case .file: fileSection
                    case .nodes: nodesSection
                    case .manual: manualSection
                    }
                    if purpose == .rules, actions.addRuleSet != nil, tab == .link || tab == .file {
                         
                        Section {
                             
                             
                            Button { ruleSetDraft = ClashMacRuleSetImportDraft(); importingRuleSet = true } label: { Text(clash: .opens("Import Rule Set", locale: locale)) }
                                .buttonStyle(.bordered).tint(.primary)
                                .disabled(busy)
                                .accessibilityIdentifier("configuration-center.import.rule-set")
                        } footer: {
                            Text(clash: .copy("For MRS, Text or YAML rule sets."))
                        }
                    }
                    if let error {
                        Section {
                            Text(verbatim: error).foregroundStyle(.red)
                                .accessibilityIdentifier("configuration-center.import.error")
                             
                             
                            if let offer = nodesOnlyOffer {
                                Button { runNodesOnly(offer) } label: {
                                    Text(verbatim: String(format: ClashCopy.string("Import only its %d nodes", locale: locale), offer.nodes))
                                }
                                .disabled(busy)
                                .accessibilityIdentifier("configuration-center.import.nodes-only")
                            }
                        }
                    }
                }
                .accessibilityIdentifier("configuration-center.import")
                }
            }
            }
        } leading: {
            if pickingGeo {
                Button { pickingGeo = false } label: { Text(clash: .copy("Back")) }
                    .accessibilityIdentifier("configuration-center.import.manual.geo.back")
            } else if offersOriginalImport {
                Button {
                    run { payload in try await actions.importOriginal?(payload) }
                } label: {
                    Text(clash: .copy("Import Original Configuration"))
                }
                .disabled(busy)
                .accessibilityIdentifier("configuration-center.import.original")
            }
        } trailing: {
            if tab != .nodes || actions.customNodesEditor == nil {
                ClashMacSheetButtons(
                    closeTitle: closeTitle,
                    closeIdentifier: "configuration-center.import.cancel",
                    primaryTitle: .copy("Add"),
                    primaryIdentifier: "configuration-center.import.add",
                    primaryDisabled: !canAdd,
                    isBusy: busy,
                    onClose: close,
                    onPrimary: { if tab == .manual { createRule() } else { run(accept) } }
                )
            }
        }
        .onChange(of: tab) { _ in preview = nil; error = nil; nodesOnlyOffer = nil }
         
         
         
         
        .onChange(of: url) { _ in preview = nil; nodesOnlyOffer = nil }
        .onChange(of: text) { _ in preview = nil; nodesOnlyOffer = nil }
         
        .onChange(of: largeFile) { _ in preview = nil; nodesOnlyOffer = nil }
        .onChange(of: fileName) { _ in preview = nil; nodesOnlyOffer = nil }
        .onChange(of: label) { _ in preview = nil }
        .onChange(of: ruleAction) { changed in
             
             
            if changed.clashMacGeoResource != pickedFrom { ruleContent = ""; pickedFrom = nil }
        }
        .alert(Text(clash: .copy("Discard Changes?")), isPresented: $confirmsTabDiscard) {
            Button(role: .destructive) { discardTabAndSwitch() } label: { Text(clash: .copy("Discard Changes")) }
                .accessibilityIdentifier("configuration-center.import.discard.confirm")
            Button(role: .cancel) { pendingTab = nil } label: { Text(clash: .copy("Keep Editing")) }
        } message: {
            Text(clash: .copy("Switching tabs discards what you have not saved."))
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: Self.fileTypes, allowsMultipleSelection: true) { result in
            switch result {
            case .success(let picked): readPickedFiles(picked)
            case .failure(let failure): error = ClashErrorCopy.message(failure, locale: locale)
            }
        }
    }

    private static var fileTypes: [UTType] {
        [.plainText, .text, UTType(filenameExtension: "yaml"), UTType(filenameExtension: "yml"),
         UTType(filenameExtension: "mrs"), UTType(filenameExtension: "txt")].compactMap { $0 }
    }

     

    private var linkSection: some View {
        Section {
            TextField(text: $url, prompt: Text(verbatim: "https://")) { Text(clash: .copy("URL")) }
                .disabled(busy)
                .accessibilityIdentifier("configuration-center.import.url")
            TextField(text: $label, prompt: Text(clash: .copy("Name"))) { Text(clash: .copy("Name")) }
                .disabled(busy)
                .accessibilityIdentifier("configuration-center.import.name")
        }
    }

    private var fileSection: some View {
        Section {
            LabeledContent {
                Button { choosingFile = true } label: { Text(clash: .copy("Choose File")) }
                    .buttonStyle(.bordered).tint(.primary)
                    .disabled(busy)
                    .accessibilityIdentifier("configuration-center.import.choose-file")
            } label: {
                Text(clash: fileName.isEmpty ? .copy("File") : .verbatim(fileName))
                 
                 
                if let largeFile { Text(verbatim: largeFile.size) }
            }
            if !resources.isEmpty {
                LabeledContent {
                    Text(verbatim: resources.map(\.fileName).joined(separator: ", ")).lineLimit(2).truncationMode(.middle)
                } label: {
                    Text(clash: .copy("Files"))
                }
                .accessibilityIdentifier("configuration-center.import.resources")
            }
             
             
             
            LabeledContent {
                Button { pasteConfigurationText() } label: { Text(clash: .copy("Paste")) }
                    .buttonStyle(.bordered).tint(.primary)
                    .disabled(busy)
                    .accessibilityIdentifier("configuration-center.import.paste")
            } label: {
                Text(clash: .copy("Paste YAML text"))
            }
            if !text.isEmpty {
                 
                 
                Button { reviewsText.toggle() } label: {
                    HStack {
                        Text(clash: .format("Review all %@ lines", [String(lineCount)]))
                        Spacer()
                        ClashSymbolImage(symbol: reviewsText ? .chevronDown : .chevronForward).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("configuration-center.import.review")
                if reviewsText {
                    TextEditor(text: $text)
                        .font(.body.monospaced())
                        .frame(minHeight: 120)
                        .disabled(busy)
                        .accessibilityLabel(Text(clash: .copy("Paste YAML text")))
                        .accessibilityIdentifier("configuration-center.import.text")
                }
            }
            TextField(text: $label, prompt: Text(clash: .copy("Name"))) { Text(clash: .copy("Name")) }
                .disabled(busy)
                .accessibilityIdentifier("configuration-center.import.file-name")
        } header: {
            Text(clash: .copy("File"))
        }
    }

    private var lineCount: Int {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
    }

    private func pasteConfigurationText() {
        guard let pasted = NSPasteboard.general.string(forType: .string), !pasted.isEmpty else { return }
        text = pasted
        largeFile = nil
         
         
        fileName = ""
        resources = []
        label = Self.labelAfterPaste(label, suggested: suggestedLabel)
        suggestedLabel = nil
        reviewsText = false
        error = nil
    }

     
     
    private var nodesSection: some View {
        Section {
            Text(clash: .copy("Custom Nodes")).foregroundStyle(.secondary)
        } header: {
            Text(clash: .copy("Custom Nodes"))
        }
    }

    private var manualSection: some View {
        Section {
            Picker(selection: $ruleAction) {
                 
                ForEach(ClashMacRuleRowEditor.offeredActions(syntax, keeping: ruleAction, lines: true), id: \.self) { item in
                    Text(verbatim: ConfigurationRuleWords.kindName(item.rawValue, locale: locale, copy: copy)).tag(item)
                }
            } label: {
                Text(clash: .copy("Rule Type"))
            }
            .disabled(busy)
            .accessibilityIdentifier("configuration-center.import.manual.action")
            if let resource = ruleAction.clashMacGeoResource, actions.geoValues != nil {
                 
                ClashMacGeoValueRow(resource: resource, value: ruleContent, identifier: "configuration-center.import.manual.geo") {
                    pickingGeo = true
                }
                .disabled(busy)
            } else if ruleAction.needsContent {
                 
                 
                 
                LabeledContent {
                    TextField(text: $ruleContent, prompt: Text(verbatim: ruleAction.contentPlaceholder)) { Text(clash: .copy(ruleAction.contentLabel)) }
                        .labelsHidden()
                        .font(.body.monospaced())
                        .multilineTextAlignment(.trailing)
                        .disabled(busy)
                        .accessibilityIdentifier("configuration-center.import.manual.content")
                } label: {
                    Text(clash: .copy(ruleAction.contentLabel))
                }
            }
             
             
            Picker(selection: $ruleTarget) {
                ForEach(ruleTargets, id: \.self) { name in Text(verbatim: name).tag(name) }
            } label: {
                Text(clash: .copy("Policy Groups"))
            }
            .disabled(busy)
            .accessibilityIdentifier("configuration-center.import.manual.target")
            .task {
                guard let targets = actions.quickRuleTargets else { return }
                if let loaded = try? await targets(), !loaded.isEmpty {
                    ruleTargets = loaded
                    if !loaded.contains(ruleTarget) { ruleTarget = loaded[0] }
                }
            }
            Toggle(isOn: $ruleEnabled) { Text(clash: .copy("Enabled")) }
                .disabled(busy)
                .accessibilityIdentifier("configuration-center.import.manual.enabled")
            TextField(text: $ruleComment) { Text(clash: .copy("Comment")) }
                .disabled(busy)
                .accessibilityIdentifier("configuration-center.import.manual.comment")
             
            Text(clash: .format("Written as %@ in the configuration file", [assembledRule]))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        } header: {
            Text(clash: .copy("Add Rule"))
        }
    }

     

     
     
     
    private var currentInput: NodesOnlyOffer.Input? {
        switch tab {
        case .link:
            return .link(url: url.trimmingCharacters(in: .whitespacesAndNewlines))
        case .file:
            return Self.fileTabInput(purpose: purpose, fileName: fileName, text: text, bytes: largeFile?.bytes,
                                     resources: resources, actions: actions)
        case .nodes, .manual:
            return nil
        }
    }

    private func readPayload() async throws -> ConfigurationSourcePayload {
        switch tab {
        case .link:
            let fetch = purpose == .rules ? actions.fetchRules ?? actions.fetch : actions.fetch
            return try await fetch(url.trimmingCharacters(in: .whitespacesAndNewlines), label)
        case .file:
            return try await Self.readFileTab(purpose: purpose, fileName: fileName, label: label, text: text,
                                              bytes: largeFile?.bytes, resources: resources, actions: actions)
        case .nodes:
            guard let readNodes = actions.readNodes else { throw ConfigurationLibraryError.unreadable }
            return try await readNodes(nodesText)
        case .manual:
            throw ConfigurationLibraryError.unreadable
        }
    }

    private func run(_ operation: @escaping (ConfigurationSourcePayload) async throws -> Void) {
        guard canRead else { return }
        busy = true
        error = nil
        nodesOnlyOffer = nil
        let input = currentInput
        Task { @MainActor in
            defer { busy = false }
             
             
             
            if preview == nil, purpose == .rules, tab == .file, actions.addRuleSet != nil {
                let bytes = largeFile?.bytes ?? Data(text.utf8)
                let found: ClashRuleSetSniff.Found?
                if let read = actions.ruleSetIn { found = await read(bytes) }
                else { found = await Task.detached(priority: .userInitiated) { ClashRuleSetSniff.ruleSet(in: bytes) }.value }
                if let found, let draft = Self.ruleSetDraft(purpose: purpose, tab: tab, label: label, fileName: fileName,
                                                            bytes: bytes, found: found, actions: actions) {
                    openRuleSetImport(draft)
                    return
                }
            }
            do {
                let payload: ConfigurationSourcePayload
                if let preview { payload = preview } else {
                    do {
                        payload = try await readPayload()
                    } catch {
                         
                        let link = url.trimmingCharacters(in: .whitespacesAndNewlines)
                        if purpose == .rules, tab == .link, actions.addRuleSet != nil,
                           let read = await actions.ruleSetAtLink?(link, error) {
                            openRuleSetImport(Self.linkRuleSetDraft(read.found, link: read.link, label: label))
                            return
                        }
                        throw error
                    }
                }
                preview = payload
                try await operation(payload)
            } catch {
                self.error = ClashErrorCopy.message(error, locale: locale)
                if Self.offersNodesOnly(purpose: purpose, tab: tab), let input, let nodes = actions.refusedNodeCount?(error) {
                    nodesOnlyOffer = NodesOnlyOffer(nodes: nodes, input: input, operation: operation)
                }
            }
        }
    }

    private func openRuleSetImport(_ draft: ClashMacRuleSetImportDraft) {
        ruleSetDraft = draft
        importingRuleSet = true
    }

     
     
     
     
    static func ruleSetDraft(purpose: ClashMacSourceImportPurpose, tab: Tab, label: String, fileName: String,
                             bytes: Data, found: ClashRuleSetSniff.Found?,
                             actions: ClashMacSourceImportActions) -> ClashMacRuleSetImportDraft? {
        guard purpose == .rules, tab == .file, actions.addRuleSet != nil, let found else { return nil }
        var draft = ClashMacRuleSetImportDraft()
        draft.name = ClashRuleSetSniff.name(typed: label, fileName: fileName)
        draft.fileName = ClashRuleSetSniff.fileName(fileName, found: found)
        draft.fileData = bytes
        draft.format = found.format
         
        if let behavior = found.behavior { draft.behavior = behavior }
        return draft
    }

     
    static func linkRuleSetDraft(_ found: ClashRuleSetSniff.Found, link: String, label: String) -> ClashMacRuleSetImportDraft {
        var draft = ClashMacRuleSetImportDraft()
        draft.link = link
        let typed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.name = typed.isEmpty ? ClashRuleSetSniff.linkStem(link) : typed
        draft.format = found.format
        if let behavior = found.behavior { draft.behavior = behavior }
        return draft
    }

     
     
    private func runNodesOnly(_ offer: NodesOnlyOffer) {
        busy = true
        error = nil
        nodesOnlyOffer = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                let payload = try await Self.readNodesOnly(offer.input, label: label, actions: actions)
                preview = payload
                try await offer.operation(payload)
            } catch {
                self.error = ClashErrorCopy.message(error, locale: locale)
            }
        }
    }

    private func createRule() {
        guard canAdd, let create = actions.createQuickRule else { return }
        busy = true
        error = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                try await create(assembledRule, ruleEnabled, ruleComment.trimmingCharacters(in: .whitespacesAndNewlines))
                close()
            } catch {
                self.error = ClashErrorCopy.message(error, locale: locale)
            }
        }
    }

     
     
     
     
     
     
     
     
    private func readPickedFiles(_ picked: [URL]) {
        do {
            guard let read = try Self.readPicked(picked, fileBytes: actions.fileBytes,
                                                 keepsBinaryRuleSet: purpose == .rules && actions.addRuleSet != nil) else { return }
             
             
             
            text = read.text
            largeFile = read.largeFile
            resources = read.resources
            fileName = read.fileName
            if label.isEmpty {
                label = read.suggestedLabel
                suggestedLabel = label
            }
            error = nil
        } catch {
            self.error = ClashErrorCopy.message(error, locale: locale)
        }
    }

     
     
     
    struct PickedFiles: Equatable {
        var text = ""
        var largeFile: LargeFile?
        var resources: [ClashMacImportResourceFile] = []
        var fileName: String
        var suggestedLabel: String
    }

     
     
     
     
     
     
    nonisolated static func readPicked(_ picked: [URL], fileBytes: (URL) throws -> Data,
                                       keepsBinaryRuleSet: Bool = false) throws -> PickedFiles? {
        let configuration = picked.first { ["yaml", "yml"].contains($0.pathExtension.lowercased()) } ?? picked.first
        guard let configuration else { return nil }
        var read = PickedFiles(fileName: configuration.lastPathComponent,
                               suggestedLabel: configuration.deletingPathExtension().lastPathComponent)
        for url in picked {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if url == configuration {
                switch try pickedConfiguration(fileBytes(url), keepsBinaryRuleSet: keepsBinaryRuleSet) {
                case .text(let text): read.text = text
                case .large(let file): read.largeFile = file
                }
            } else {
                read.resources.append(ClashMacImportResourceFile(fileName: url.lastPathComponent, data: try fileBytes(url)))
            }
        }
        return read
    }
}
