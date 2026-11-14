import ClashClientKit
import ClashClientUI
import SwiftUI
import UniformTypeIdentifiers

 
 
struct ProfileQuickAddState: Equatable {
    enum Notice: Equatable {
        case nodeBelongsInCustomNodes
    }
    enum Phase: Equatable {
        case idle
        case busy(host: String)
         
         
         
        case busyNodes
        case failed(String)
        case notice(Notice)
    }

    var text = "" {
         
         
         
        didSet { if text != unwrappedRules?.address { unwrappedRules = nil } }
    }
    var phase: Phase = .idle
     
     
    private(set) var pending: ProfileQuickAddInput?
     
     
     
     
     
    struct UnwrappedRules: Equatable {
        let address: String
        let rules: InstallLinkRuleScheme
    }
    private(set) var unwrappedRules: UnwrappedRules?
     
     
     
     
    struct NodesOnly: Equatable {
        let input: ProfileQuickAddInput
        let nodes: Int
    }
    private(set) var nodesOnly: NodesOnly?
     
     
     
     
    private(set) var failure: ConfigurationFailure?

    var isBusy: Bool {
        switch phase {
        case .busy, .busyNodes: return true
        case .idle, .failed, .notice: return false
        }
    }

    var canSubmit: Bool {
        !isBusy && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

     
     
    mutating func accept(_ input: ProfileQuickAddInput) {
        switch input {
        case .nothing:
            phase = .idle
        case .nodeShareLink:
            phase = .notice(.nodeBelongsInCustomNodes)
        case .link(let url, let rules):
             
             
            let kept = unwrappedRules.flatMap { $0.address == url && text == url ? $0.rules : nil }
            text = url
            if let named = rules ?? kept {
                unwrappedRules = UnwrappedRules(address: url, rules: named)
                pending = .link(url, rules: named)
            } else {
                pending = input
            }
        case .document, .nodes:
            unwrappedRules = nil
            pending = input
        }
    }

    mutating func begin(_ input: ProfileQuickAddInput) {
        pending = nil
        nodesOnly = nil
        failure = nil
        switch input {
        case .link(let url, _):
            text = url
            phase = .busy(host: URL(string: url)?.host ?? url)
        case let .document(fileName, _, _):
            phase = .busy(host: fileName)
        case .nodes:
            phase = .busyNodes
        case .nodeShareLink, .nothing:
            phase = .idle
        }
    }

     
     
    mutating func succeed(notice: Notice? = nil) {
        phase = notice.map { .notice($0) } ?? .idle
        text = ""
        nodesOnly = nil
        failure = nil
    }

     
    mutating func fail(_ message: String, failure classified: ConfigurationFailure? = nil, nodesOnly offer: NodesOnly? = nil) {
        phase = .failed(message)
        failure = classified
        nodesOnly = offer
    }
}

 
 
 
 
 
 
 
@MainActor
final class ProfileQuickAddController: ObservableObject {
     
     
     
     
     
    enum Target { case profile, source, rules, scripts }

    let target: Target
    @Published var state = ProfileQuickAddState()
    @Published var showsImporter = false
    @Published var showsQRCapture = false {
        didSet {
             
             
            if showsQRCapture, !oldValue { hasDeliveredScan = false }
        }
    }
    @Published var showsQRPhotoPicker = false
     
     
    var onFirstProfileCreated: (() -> Void)?
     
    var onSourceAdded: ((ConfigurationLibrarySnapshot) -> Void)?
     
    var onScriptAdded: ((ConfigScript) -> Void)?
     
     
     
    private var pendingScan: Result<String, Error>?
     
     
    private var hasDeliveredScan = false
    private let model: ProfilesViewModel

    init(model: ProfilesViewModel, target: Target) {
        self.model = model
        self.target = target
    }

     
     
     
     
     
    var importContentTypes: [UTType] {
        switch target {
         
         
         
         
         
         
        case .profile, .source, .rules: [.yaml, .plainText, .text]
        case .scripts: [.javaScript, .plainText, .text]
        }
    }

    var headerKey: String {
        switch target {
        case .profile: "Add Profile"
        case .source: "Add Nodes"
        case .rules: "Add Rules"
         
         
        case .scripts: "Add Script"
        }
    }

    func submitTyped() {
        guard state.canSubmit else { return }
        state.accept(classify(state.text))
        runPending()
    }

    func acceptPasted(_ raw: String) {
        state.accept(classify(raw))
        runPending()
    }

    func acceptScanned(_ code: String) {
        state.accept(classify(code))
        runPending()
    }

     
     
    func classify(_ raw: String) -> ProfileQuickAddInput {
        Self.classify(raw, for: target)
    }

    nonisolated static func classify(_ raw: String, for target: Target) -> ProfileQuickAddInput {
         
         
         
        if target == .source, case .nodeShareLinks(let links) = PastedContentClassifier.classify(raw) {
            return .nodes(links.joined(separator: "\n"))
        }
        return ProfileQuickAddInput.classify(raw)
    }

     
    func holdScan(_ result: Result<String, Error>) {
         
         
         
         
         
        guard !hasDeliveredScan else { return }
        hasDeliveredScan = true
        pendingScan = result
        showsQRCapture = false
        showsQRPhotoPicker = false
#if os(macOS)
         
         
         
         
         
         
         
        deliverPendingScan()
#endif
    }

     
    func deliverPendingScan() {
        guard let result = pendingScan else { return }
        pendingScan = nil
        switch result {
        case .success(let code): acceptScanned(code)
        case .failure(let error): state.fail(error.localizedDescription)
        }
    }

    func importFile(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = AddProfileDraft.configurationFile(among: urls) else {
                throw ProfileInstallLinkError.unsupportedFile
            }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
             
             
            let data = try ImportedFileBytes.readForImport(url)
            guard !data.isEmpty else { throw ProfileInstallLinkError.unreadableFile }
            state.accept(.document(fileName: url.lastPathComponent, data: data))
            runPending()
        } catch {
            state.fail(error.localizedDescription)
        }
    }

     
     
     
    nonisolated static func nodesOnly(for error: Error, input: ProfileQuickAddInput, target: Target) -> ProfileQuickAddState.NodesOnly? {
        switch target {
        case .profile, .source: break
        case .rules, .scripts: return nil
        }
        return AddProfileDraft.refusedNodeCount(for: error).map { .init(input: input, nodes: $0) }
    }

     
    func importNodesOnly() {
        guard let offer = state.nodesOnly else { return }
        state.accept(offer.input)
        runPending(nodesOnly: true)
    }

     
    private func runPending(nodesOnly: Bool = false) {
        guard let input = state.pending else { return }
        state.begin(input)
        Task { @MainActor in
            do {
                switch target {
                case .profile:
                     
                     
                     
                    let outcome = try await model.quickCreate(input, nodesOnly: nodesOnly)
                    state.succeed()
                     
                    if outcome.isFirstUserProfile { onFirstProfileCreated?() }
                case .source:
                    let snapshot = try await model.quickAddSource(input, nodesOnly: nodesOnly)
                    state.succeed()
                    onSourceAdded?(snapshot)
                case .rules:
                    let snapshot = try await model.quickAddRules(input)
                    state.succeed()
                    onSourceAdded?(snapshot)
                case .scripts:
                     
                     
                     
                     
                     
                    let script = try await ScriptQuickAdd.add(input)
                    state.succeed()
                    onScriptAdded?(script)
                }
            } catch let kept as ConfigurationRulesKeptByConfiguration {
                 
                 
                 
                state.fail(kept.localizedDescription)
            } catch {
                let classified = ConfigurationFailureClassifier.classify(
                    error, context: .localImport, preservesLastKnownGood: false
                )
                state.fail(
                    classified?.localizedDescription ?? error.localizedDescription,
                    failure: classified,
                    nodesOnly: Self.nodesOnly(for: error, input: input, target: target)
                )
            }
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
struct ProfileQuickAddIdentifiers {
    let linkIdentifier: String
    let scanIdentifier: String
    let fileIdentifier: String
    let manualIdentifier: String
    let statusIdentifier: String
}

struct ProfileQuickAddCard: View {
    @ObservedObject var controller: ProfileQuickAddController
    let identifiers: ProfileQuickAddIdentifiers
    @Environment(\.locale) private var locale
     
    var onFirstProfileCreated: (() -> Void)? = nil
     
    var manual: (() -> Void)? = nil

    var body: some View {
        Section {
             
             
            HStack(spacing: ClashTheme.Spacing.standard) {
                linkField
                ClashPasteControl(style: .square) { pasted in
                    controller.acceptPasted(pasted)
                }
                .disabled(controller.state.isBusy)
            }
            statusRow
            actionRows
        } header: {
             
             
            ClashConfigurationLibraryHeader(title: .copy(controller.headerKey))
        }
        .onAppear {
            controller.onFirstProfileCreated = onFirstProfileCreated
        }
    }

     
     
     
     
     
     
     
     
    @ViewBuilder
    private var actionRows: some View {
        Button {
            controller.showsQRCapture = true
        } label: {
            Label(ClashCopy.key("Scan QR Code"), systemImage: ClashSymbol.qrcodeViewfinder.name)
        }
        .disabled(controller.state.isBusy)
        .accessibilityIdentifier(identifiers.scanIdentifier)
        Button {
            controller.showsImporter = true
        } label: {
            Label(ClashCopy.key("Import File"), systemImage: ClashSymbol.arrowUpDocument.name)
        }
        .disabled(controller.state.isBusy)
        .accessibilityIdentifier(identifiers.fileIdentifier)
        if let manual {
            Button(action: manual) {
                 
                Label(ClashCopy.key(controller.target == .rules ? "quick-add.new.rules" : "quick-add.new.node"),
                      systemImage: ClashSymbol.docBadgePlus.name)
            }
            .disabled(controller.state.isBusy)
            .accessibilityIdentifier(identifiers.manualIdentifier)
        }
    }

     
     
     
    private var linkField: some View {
        TextField("", text: $controller.state.text, prompt: Text(verbatim: "https://example.com/config.yaml"))
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .onSubmit { controller.submitTyped() }
            .disabled(controller.state.isBusy)
            .accessibilityIdentifier(identifiers.linkIdentifier)
    }

    private func busyRow(_ host: String) -> some View {
        HStack(spacing: ClashTheme.Spacing.compact) {
            ProgressView().controlSize(.small)
            Text(clash: .format("Downloading %@…", [host]))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier(identifiers.statusIdentifier)
    }

    @ViewBuilder
    private var statusRow: some View {
        switch controller.state.phase {
        case .idle:
            EmptyView()
        case .busy(let host):
            busyRow(host)
        case .busyNodes:
            busyRow(ConfigurationSourceRecord.displayLabel(ConfigurationBuiltins.customNodesName, origin: .customNodes, locale: locale))
        case .failed(let message):
            ClashStatusMessage(
                text: .verbatim(controller.state.failure.map { ProfileSwitchFailureText.cardText(for: $0, locale: locale) } ?? message),
                kind: .error
            )
                .accessibilityIdentifier(identifiers.statusIdentifier)
            if let offer = controller.state.nodesOnly {
                Button(AddProfileView.nodesOnlyOfferTitle(nodes: offer.nodes, locale: locale)) {
                    controller.importNodesOnly()
                }
                .accessibilityIdentifier("quick-add.import.nodesOnly")
            }
        case .notice(.nodeBelongsInCustomNodes):
            ClashStatusMessage(
                text: .copy("That is a node, not a profile URL. Add it under a profile's Custom Nodes."),
                kind: .warning
            )
            .accessibilityIdentifier(identifiers.statusIdentifier)
        }
    }
}

extension View {
     
     
    func profileQuickAddPresenters(_ controller: ProfileQuickAddController) -> some View {
        modifier(ProfileQuickAddPresenters(controller: controller))
    }
}

private struct ProfileQuickAddPresenters: ViewModifier {
    @ObservedObject var controller: ProfileQuickAddController

    func body(content: Content) -> some View {
        content
             
             
             
            .fileImporter(isPresented: $controller.showsImporter,
                          allowedContentTypes: controller.importContentTypes,
                          allowsMultipleSelection: false) { result in
                controller.importFile(result)
            }
            .clashProductModal(isPresented: $controller.showsQRCapture, role: .page,
                              onDismiss: { controller.deliverPendingScan() }) {
                ClashFeatureNavigationContainer {
                    Form {
                         
                         
                         
                         
                        Section {
                            QRScannerView { code in
                                controller.holdScan(.success(code))
                            }
                             
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: ClashTheme.Radius.card, style: .continuous))
                        }
                        Section {
                            Button {
#if os(macOS)
                                 
                                 
                                QRImagePanel.choose { result in
                                    guard let result else { return }
                                    controller.holdScan(result)
                                    controller.showsQRCapture = false
                                }
#else
                                controller.showsQRCapture = false
                                controller.showsQRPhotoPicker = true
#endif
                            } label: {
                                Label("Choose QR from Photos", systemImage: ClashSymbol.photo.name)
                                    .foregroundStyle(.primary)
                            }
                             
                             
                             
                             
                             
                             
                            .clashMacFormActionChrome()
                        }
                    }
                    .clashPageTitle("Scan QR Code")
                    .clashToolbarUnlessInPanel {
                        ToolbarItem(placement: .cancellationAction) {
                            ClashSheetCloseButton { controller.showsQRCapture = false }
                        }
                    }
                    .clashProductModalRoot(title: "Scan QR Code")
                }
                .clashModalPresentation(.page)
            }
            .clashProductModal(isPresented: $controller.showsQRPhotoPicker, role: .page,
                              onDismiss: { controller.deliverPendingScan() }) {
                QRPhotoPicker { result in
                     
                    if let result { controller.holdScan(result) } else { controller.showsQRPhotoPicker = false }
                }
                .clashModalPresentation(.page)
                .clashProductModalRoot(title: "Choose QR from Photos")
            }
    }
}
