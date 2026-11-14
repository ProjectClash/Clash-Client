import CryptoKit
import ClashClientUI
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

 
 
 
 
 
 
 
 
 
 
 
final class SourceEditDrafts: @unchecked Sendable {
    static let shared = SourceEditDrafts()

    struct Restored: Equatable {
        let text: String
         
         
        let needsNotice: Bool
         
         
        var originalChanged = false
    }

    fileprivate struct Draft: Codable, Equatable {
        var base: String
        var text: String
         
        var position: CodeEditorViewport?
         
         
         
        var key: String?
    }

    private let lock = NSLock()
    private var memory: [String: Draft] = [:]
     
     
     
     
     
    private var positions: [String: CodeEditorViewport] = [:]
    private var dirty: Set<String> = []
    private var scheduled: DispatchWorkItem?
    private let directory: URL?
    private let queue = DispatchQueue(label: "clash.source-edit-drafts", qos: .utility)
    private var observers: [NSObjectProtocol] = []

    init(directory: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("SourceEditDrafts", isDirectory: true)) {
        self.directory = directory
#if os(macOS)
        let names = [NSApplication.willResignActiveNotification, NSApplication.willTerminateNotification]
#else
        let names = [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification]
#endif
         
         
        observers = names.map {
            NotificationCenter.default.addObserver(forName: $0, object: nil, queue: nil) { [weak self] _ in
                self?.flush()
            }
        }
    }

     
     
     
     
    static func fingerprint(_ text: String) -> String {
        let utf8 = text.utf8
        let digest = SHA256.hash(data: Data(utf8)).map { String(format: "%02x", $0) }.joined()
        return "\(utf8.count)-\(digest)"
    }

    func restore(key: String, original: String, fingerprint: String) -> Restored? {
        lock.lock()
        let held = memory[key]
        lock.unlock()
        if let held {
            return held.text == original ? nil
                : Restored(text: held.text, needsNotice: held.base != fingerprint, originalChanged: held.base != fingerprint)
        }
        guard let url = file(for: key), let data = try? Data(contentsOf: url),
              var draft = try? JSONDecoder().decode(Draft.self, from: data),
              draft.text != original else { return nil }
        draft.key = key
        lock.lock(); memory[key] = draft; lock.unlock()
        return Restored(text: draft.text, needsNotice: true, originalChanged: draft.base != fingerprint)
    }

    func position(key: String) -> CodeEditorViewport? {
        lock.lock(); defer { lock.unlock() }
        return positions[key] ?? memory[key]?.position
    }

     
     
    func recordPosition(key: String, _ position: CodeEditorViewport) {
        lock.lock(); defer { lock.unlock() }
        positions[key] = position
        if memory[key] != nil {
            memory[key]?.position = position
            dirty.insert(key)
        }
    }

    func record(key: String, fingerprint: String, original: String, text: String) {
        guard text != original else { return clear(key: key) }
        lock.lock()
        memory[key] = Draft(base: memory[key]?.base ?? fingerprint, text: text, position: positions[key], key: key)
        dirty.insert(key)
        scheduled?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        scheduled = work
        lock.unlock()
        queue.asyncAfter(deadline: .now() + 1, execute: work)
    }

    func clear(key: String) {
        lock.lock()
        let had = memory.removeValue(forKey: key) != nil
        dirty.remove(key)
        lock.unlock()
        guard let url = file(for: key) else { return }
        if had || FileManager.default.fileExists(atPath: url.path) {
            queue.async { try? FileManager.default.removeItem(at: url) }
        }
    }

     
     
     
    struct Held: Equatable {
        fileprivate let drafts: [String: Draft]
        var isEmpty: Bool { drafts.isEmpty }
        static let none = Held(drafts: [:])
    }

    func holding(owner: String) -> Held {
        guard !owner.isEmpty else { return Held(drafts: [:]) }
        lock.lock()
        var found = memory.filter { Self.key($0.key, names: owner) }
        lock.unlock()
        if let directory {
            let stored = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for url in stored where url.pathExtension == "json" {
                guard let data = try? Data(contentsOf: url),
                      let draft = try? JSONDecoder().decode(Draft.self, from: data),
                      let key = draft.key, Self.key(key, names: owner), found[key] == nil else { continue }
                found[key] = draft
            }
        }
        return Held(drafts: found)
    }

     
    func putBack(_ held: Held) {
        guard !held.isEmpty else { return }
        lock.lock()
        for (key, draft) in held.drafts {
            memory[key] = draft
            dirty.insert(key)
        }
        scheduled?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        scheduled = work
        lock.unlock()
        queue.asyncAfter(deadline: .now() + 1, execute: work)
    }

     
     
     
     
     
     
    func clearAll(owner: String) {
        guard !owner.isEmpty else { return }
        lock.lock()
        let known = memory.keys.filter { Self.key($0, names: owner) }
        for key in known {
            memory[key] = nil
            positions[key] = nil
            dirty.remove(key)
        }
        lock.unlock()
        guard let directory else { return }
        let files = known.compactMap { file(for: $0) }
        queue.async {
            for url in files { try? FileManager.default.removeItem(at: url) }
            let stored = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for url in stored where url.pathExtension == "json" {
                guard let data = try? Data(contentsOf: url),
                      let draft = try? JSONDecoder().decode(Draft.self, from: data),
                      let key = draft.key, Self.key(key, names: owner) else { continue }
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    static func key(_ key: String, names owner: String) -> Bool {
        key.split(separator: "|", omittingEmptySubsequences: false).contains { $0 == owner }
    }

     
    func flush() {
        lock.lock()
        let pending = dirty.compactMap { key in memory[key].map { (key, $0) } }
        dirty.removeAll()
        scheduled?.cancel(); scheduled = nil
        lock.unlock()
        guard let directory, !pending.isEmpty else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (key, draft) in pending {
            guard let url = file(for: key), let data = try? JSONEncoder().encode(draft) else { continue }
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    private func file(for key: String) -> URL? {
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory?.appendingPathComponent(name + ".json")
    }
}

 
 
extension SourceEditDrafts: ClashUnsavedDraftStore {
    func restoreDraft(key: String, original: String) -> ClashRestoredDraft? {
        restore(key: key, original: original, fingerprint: Self.fingerprint(original))
            .map { ClashRestoredDraft(text: $0.text, needsNotice: $0.needsNotice, originalChanged: $0.originalChanged) }
    }

    func recordDraft(key: String, original: String, text: String) {
        record(key: key, fingerprint: Self.fingerprint(original), original: original, text: text)
    }

    func clearDraft(key: String) {
        clear(key: key)
    }
}

 
 
 
struct ProfileEditView: View {
    let save: (Profile, String?, [ExternalResourceImportFile], Bool) async throws -> Void

     
     
     
     
     
     
    @StateObject private var dismiss = ClashDismissHandle()
    @Environment(\.clashInsideProductModalPresentation)
    private var insideProductModal

    private let savesIndependentSource: Bool
    private let editorTitle: String
    private let original: Profile
     
     
     
     
     
     
     
     
    @State private var departureCompletion: ((Bool) -> Void)?
    private let originalRawText: String
    private let hadRawSource: Bool
     
     
    private let draftKey: String
    private let originalFingerprint: String
     
     
    private let openingPosition: CodeEditorViewport?
    @State private var rawText: String
     
    @State private var showsRestoredDraft: Bool
    @State private var importedResourceFiles: [ExternalResourceImportFile] = []
    @State private var showsFileImporter = false
    @State private var errorMessage = ""
    @State private var diagnostic: CodeEditorDiagnostic?
     
    @State private var errorWords: String?
    @State private var asksAboutAutoUpdate = false
    @State private var asksAboutUnsaved = false
     
    @State private var isSaving = false
     
     
     
    @State private var importingFile = false
    @State private var importGeneration = 0
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    @State private var editorReady = false
    @State private var findPresented = false
    @State private var typing = false
    @State private var showsLineNumbers = CodeEditorLineNumbers.isOn
    @State private var softWrap = CodeEditorSoftWrap.isOn

     
     
     
     
     
    private var editWillBeOverwrittenByAutoUpdate: Bool {
        guard case .url = original.source else { return false }
        return original.autoUpdate && rawChanged
    }

    init(
        profile: Profile,
        rawYAML: String?,
        editorTitle: String = "Edit Source",
        savesIndependentSource: Bool = false,
        save: @escaping (
            Profile, String?, [ExternalResourceImportFile], Bool
        ) async throws -> Void
    ) {
        self.save = save
        self.editorTitle = editorTitle
        self.savesIndependentSource = savesIndependentSource
        original = profile
        originalRawText = rawYAML ?? ""
        hadRawSource = rawYAML != nil
        draftKey = "\(editorTitle)|\(profile.id)"
        originalFingerprint = SourceEditDrafts.fingerprint(rawYAML ?? "")
        let restored = SourceEditDrafts.shared.restore(
            key: draftKey, original: rawYAML ?? "", fingerprint: originalFingerprint)
         
         
         
        var position = SourceEditDrafts.shared.position(key: draftKey)
        if restored?.needsNotice == true { position?.editing = false }
        openingPosition = position
        _rawText = State(initialValue: restored?.text ?? rawYAML ?? "")
        _showsRestoredDraft = State(initialValue: restored?.needsNotice == true)
    }

    private var rawChanged: Bool { rawText != originalRawText }

     
     
     
    private var canSave: Bool {
        rawChanged && !importingFile && !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

     
     
     
     
     
     
     
    private var blockingRequirement: String? {
        guard !canSave else { return nil }
        if rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "The profile cannot be empty."
        }
        return "Edit the profile to save it."
    }

     
     
     
     
    @ViewBuilder
    private var editor: some View {
         
         
        CodeEditorPanel(
            text: $rawText,
            language: .yaml,
            minHeight: 200,
            diagnostic: diagnostic,
            expandsVertically: true,
             
             
            chrome: .minimal,
            showsLineNumbers: showsLineNumbers,
            softWrap: softWrap,
            findPresented: $findPresented,
            typing: $typing,
            position: openingPosition,
            onPositionChange: { [draftKey] in SourceEditDrafts.shared.recordPosition(key: draftKey, $0) }
        )
        .disabled(importingFile)
        .padding(.horizontal, ClashTheme.Spacing.standard)
        .padding(.vertical, ClashTheme.Spacing.compact)
    }

     
     
     
    @ViewBuilder
    private var moreMenu: some View {
        Button {
            findPresented = true
        } label: {
            Label("Find", systemImage: ClashSymbol.magnifyingglass.name)
        }
        .keyboardShortcut("f", modifiers: .command)
        .accessibilityIdentifier("profile.edit.find")
        Button {
            showsLineNumbers.toggle()
            CodeEditorLineNumbers.isOn = showsLineNumbers
        } label: {
            Label(
                "Line Numbers",
                systemImage: showsLineNumbers ? ClashSymbol.checkmark.name : ClashSymbol.listBullet.name
            )
        }
        .accessibilityIdentifier("profile.edit.lineNumbers")
        Button {
            softWrap.toggle()
            CodeEditorSoftWrap.isOn = softWrap
        } label: {
            Label(
                "Wrap Long Lines",
                systemImage: softWrap ? ClashSymbol.checkmark.name : ClashSymbol.arrowRightToLine.name
            )
        }
        .accessibilityIdentifier("profile.edit.softWrap")
        Button {
            showsFileImporter = true
        } label: {
            Label("Replace from File…", systemImage: ClashSymbol.squareAndArrowDown.name)
        }
        .accessibilityIdentifier("profile.edit.replace-file")
    }

    var body: some View {
        ClashFeatureNavigationContainer {
            Group {
                if !editorReady {
                    VStack(spacing: ClashTheme.Spacing.compact) {
                        Spacer()
                        ProgressView()
                        Text(clash: .copy("Opening Editor"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .accessibilityIdentifier("profile.sourceEditor.loading")
                } else if hadRawSource || !rawText.isEmpty {
                    VStack(spacing: 0) {
                        if savesIndependentSource {
                            Text("Changing nodes, groups or rules here makes this profile independent of source updates.")
                                .font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, ClashTheme.Spacing.standard)
                        }
                        editor
                    }
                } else {
                    VStack {
                        Spacer()
                        Text("The source is downloaded on first Sync or activation.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ClashTheme.canvas.ignoresSafeArea())
             
             
             
            .task { editorReady = true }
             
             
             
            .clashPageTitle(editorTitle == "Edit Source" ? .verbatim(original.label) : .copy(editorTitle), watchAs: "Edit Source")
             
             
            .modifier(ClashBarFadesWhileTyping(typing: $typing))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !insideProductModal {
                        Button("Cancel") {
                            switch UnsavedEditPolicy.decision(
                                original: originalRawText,
                                current: rawText
                            ) {
                            case .leave: dismissPresentation()
                            case .offerToSave: asksAboutUnsaved = true
                            }
                        }
                    }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    if !insideProductModal {
                        Menu {
                            moreMenu
                        } label: {
                            Image(systemName: ClashSymbol.ellipsisCircle.name)
                        }
                        .accessibilityLabel("More")
                        .accessibilityIdentifier("profile.edit.more")

                        ClashSaveButton(
                            isEnabled: canSave,
                            identifier: "profile.edit.save"
                        ) {
                            await requestSave()
                        }
                    }
                }
            }
            .clashProductModalRoot(
                title: .copy(editorTitle),
                 
                 
                 
                actionTitle: "Replace from File…",
                action: { showsFileImporter = true }
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if insideProductModal {
                    ClashModalActionBar(
                        primaryTitle: "Save",
                        primaryDisabled: !canSave,
                        primaryHint: blockingRequirement,
                        isBusy: isSaving,
                        busyTitle: "Saving…",
                        onPrimary: {
                             
                             
                             
                            isSaving = true
                            Task { await requestSave() }
                        }
                    )
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if showsRestoredDraft {
                    HStack(spacing: ClashTheme.Spacing.compact) {
                        ClashStatusMessage(text: .copy("Unsaved edits from last time were restored."), kind: .information)
                            .accessibilityIdentifier("profile.edit.restored")
                        Spacer(minLength: 0)
                        Button("Discard", role: .destructive) {
                            rawText = originalRawText
                            SourceEditDrafts.shared.clear(key: draftKey)
                            showsRestoredDraft = false
                        }
                        .font(.subheadline)
                        .accessibilityIdentifier("profile.edit.restored.discard")
                    }
                    .padding(.horizontal, ClashTheme.Spacing.standard)
                    .padding(.vertical, ClashTheme.Spacing.compact)
                }
            }
            .onChange(of: rawText) { text in
                SourceEditDrafts.shared.record(
                    key: draftKey, fingerprint: originalFingerprint, original: originalRawText, text: text)
            }
            .safeAreaInset(edge: .bottom) {
                if !errorMessage.isEmpty {
                    ClashStatusMessage(text: errorWords.map { .format(errorMessage, [$0]) } ?? .copy(errorMessage),
                                       kind: .error)
                        .padding(.horizontal, ClashTheme.Spacing.standard)
                        .padding(.bottom, ClashTheme.Spacing.compact)
                }
            }
             
            .fileImporter(
                isPresented: $showsFileImporter,
                allowedContentTypes: [.yaml, .plainText, .data],
                allowsMultipleSelection: false
            ) { result in
                importFile(result)
            }
        }
                 
         
         
         
         
         
         
         
         
        .interactiveDismissDisabled(UnsavedEditPolicy.decision(original: originalRawText, current: rawText) == .offerToSave)
        .clashRegistersDeparture(
            isDirty: UnsavedEditPolicy.decision(
                original: originalRawText,
                current: rawText
            ) == .offerToSave,
             
             
             
            saveAnswering: { answer in
                let completion: (Bool) -> Void = { answer($0 ? .saved : .refused(nil)) }
                 
                 
                 
                 
                 
                 
                 
                departureCompletion = completion
                Task { await requestSave() }
            },
            discard: {
                rawText = originalRawText
                SourceEditDrafts.shared.clear(key: draftKey)
            }
        )
        .clashStackNavigationViewStyle()
        .alert("Save your changes?", isPresented: $asksAboutUnsaved) {
            Button("Save") {
                if editWillBeOverwrittenByAutoUpdate {
                    asksAboutAutoUpdate = true
                } else {
                    Task { await persist() }
                }
            }
            Button("Discard", role: .destructive) {
                SourceEditDrafts.shared.clear(key: draftKey)
                dismissPresentation()
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("This source has changes that have not been saved.")
        }
        .alert("Auto update will replace this edit", isPresented: $asksAboutAutoUpdate) {
            Button("Turn Off Auto Update") {
                Task {
                    settleDeparture(await persist(disablingAutoUpdate: true))
                }
            }
            Button("Keep Auto Update") {
                Task {
                    settleDeparture(await persist())
                }
            }
             
             
            Button("Cancel", role: .cancel) { settleDeparture(false) }
        } message: {
            Text(
                "This profile updates from its profile URL. The next update overwrites what you edited here."
            )
        }
        .clashCapturesDismiss(dismiss)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    @discardableResult
    private func persist(disablingAutoUpdate: Bool = false) async -> Bool {
        await Task.yield()
        defer { isSaving = false }
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        let text = rawText
        let runtimeProfile = clashAppleRuntimeProfileValue
        if rawChanged,
            let sites = await Task.detached(priority: .userInitiated, operation: {
                ConfigTransforms.invalidDomainSites(in: text, runtimeProfile: runtimeProfile)
            }).value, !sites.isEmpty
        {
            errorMessage = Self.invalidDomainMessage(sites)
            errorWords = nil
            diagnostic = nil
            return false
        }
        let saved = rawText
        do {
            try await save(
                original,
                rawChanged ? saved : nil,
                rawChanged ? importedResourceFiles : [],
                disablingAutoUpdate
            )
            SourceEditDrafts.shared.clear(key: draftKey)
            dismissPresentation()
            return true
        } catch {
             
             
            show(Self.editFailure(error, in: rawText == saved ? rawText : nil))
            return false
        }
    }

     
     
     
     
     
     
     
    private var clashAppleRuntimeProfileValue: String {
        switch clashAppleRuntimeProfile {
        case .macosPacketTunnel: return ClashAppleRuntimeProfile.macosPacketTunnel.rawValue
        case .iosPacketTunnel, .tvosPacketTunnel: return ""
        }
    }

     
     
     
     
     
     
     
    private static func invalidDomainMessage(_ sites: [InvalidDomainSite]) -> String {
        let lines = sites.prefix(8).map { site -> String in
            let place: String
            switch site.locator {
            case .index(let index): place = "\(site.field)[\(index)]"
            case .key(let key): place = "\(site.field)[\"\(key)\"]"
            }
            let why: String
            switch site.reason {
            case .barePlus: why = "a lone + matches nothing"
            case .plusOutsideLeadingLabel: why = "+ is only allowed as the whole first label"
            case .starInsideLabel: why = "* cannot sit inside a label"
            case .trailingDot: why = "a trailing dot"
            case .whitespace: why = "surrounding whitespace"
            case .empty: why = "an empty value"
            case .emptySegment: why = "an empty label"
            case .other: why = "the core refuses this pattern"
            }
            return "\(place) “\(site.entry)” — \(why)"
        }
        let more = sites.count > 8 ? "\n… and \(sites.count - 8) more" : ""
         
         
         
         
        let heading = "The core will refuse this configuration:"
        return ([heading] + lines).joined(separator: "\n") + more
    }

    private func settleDeparture(_ saved: Bool) {
        let completion = departureCompletion
        departureCompletion = nil
        completion?(saved)
    }

    private func requestSave() async {
        if editWillBeOverwrittenByAutoUpdate {
             
             
             
            isSaving = false
            asksAboutAutoUpdate = true
        } else {
             
             
            settleDeparture(await persist())
        }
    }

    private func dismissPresentation() {
        dismiss.closeModalOrDismiss()
    }

    private func importFile(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
             
             
             
            guard let yamlURL = AddProfileDraft.configurationFile(among: urls) else {
                throw ProfileInstallLinkError.unsupportedFile
            }
            let selected = try urls.map { url -> ExternalResourceImportFile in
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                let data = try ImportedFileBytes.read(url)
                guard !data.isEmpty,
                      data.count <= ProfileExternalResourceImporter.maximumResourceBytes else {
                    throw data.isEmpty
                        ? ProfileInstallLinkError.unreadableFile
                        : ProfileInstallLinkError.fileTooLarge
                }
                return ExternalResourceImportFile(fileName: url.lastPathComponent, data: data)
            }
            guard let yamlFile = selected.first(where: {
                $0.fileName == yamlURL.lastPathComponent
            }), let text = String(data: yamlFile.data, encoding: .utf8) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
             
             
            importGeneration &+= 1
            let generation = importGeneration
            importingFile = true
            Task { @MainActor in
                defer { if generation == importGeneration { importingFile = false } }
                do {
                    try await Task.detached(priority: .userInitiated) {
                        try ConfigTransforms.validateSource(text)
                    }.value
                    guard generation == importGeneration else { return }
                    rawText = text
                    importedResourceFiles = selected.filter {
                        $0.fileName != yamlURL.lastPathComponent
                    }
                    diagnostic = nil
                    errorMessage = ""
                    errorWords = nil
                } catch {
                    guard generation == importGeneration else { return }
                     
                    show(Self.editFailure(error, in: nil))
                }
            }
        } catch {
            show(Self.editFailure(error, in: nil))
        }
    }

    private func show(_ failure: EditFailure) {
        diagnostic = failure.diagnostic
        errorMessage = failure.message
        errorWords = failure.words
    }

     
    struct EditFailure {
        let message: String
         
        let words: String?
        let diagnostic: CodeEditorDiagnostic?

        var text: ClashDisplayText { words.map { .format(message, [$0]) } ?? .copy(message) }
    }

     
     
     
    static let markedYAMLMessage =
        "This is not valid YAML. Check the line the editor marked and the lines below it, then save again."
     
     
    static let unmarkedYAMLMessage = "This is not valid YAML: %@"

     
     
     
    static func editFailure(_ error: Error, in text: String?) -> EditFailure {
        let classified = ConfigurationFailureClassifier.classify(
            error,
            context: .activation,
            preservesLastKnownGood: true
        )
        let diagnostic = text.flatMap { CodeEditorDiagnostic.parsed(from: error.localizedDescription, in: $0) }
         
         
         
         
         
         
        guard case .yamlSyntax = classified?.kind else {
            return EditFailure(message: classified?.localizedDescription ?? "The profile could not be saved.",
                               words: nil, diagnostic: diagnostic)
        }
        if diagnostic != nil {
            return EditFailure(message: markedYAMLMessage, words: nil, diagnostic: diagnostic)
        }
         
         
        guard case let .invalidConfiguration(reason)? = error as? ConfigTransformsError else {
            return EditFailure(message: classified?.localizedDescription ?? "The profile could not be saved.",
                               words: nil, diagnostic: nil)
        }
        return EditFailure(message: unmarkedYAMLMessage, words: reason, diagnostic: nil)
    }
}

 
 
 
struct ClashBarFadesWhileTyping: ViewModifier {
    @Binding var typing: Bool

    func body(content: Content) -> some View {
#if os(iOS)
        barHidden(content)
            .overlay(alignment: .top) {
                if typing {
                    Color.clear
                        .frame(height: 24)
                        .contentShape(Rectangle())
                        .onTapGesture { typing = false }
                        .accessibilityHidden(true)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: typing)
#else
        content
#endif
    }

#if os(iOS)
    @ViewBuilder
    private func barHidden(_ content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.toolbar(typing ? .hidden : .visible, for: .navigationBar)
        } else {
            content.navigationBarHidden(typing)
        }
    }
#endif
}
