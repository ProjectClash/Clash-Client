import ClashClientKit
import ClashClientUI
import SwiftUI
import UniformTypeIdentifiers

 
 
public struct ClashMacScriptEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
     
    public let canRefresh: Bool
     
     
    public let sourceHost: String?
     
     
     
    public let usage: ClashDisplayText?
    public init(id: String, label: String, canRefresh: Bool = false, sourceHost: String? = nil,
                usage: ClashDisplayText? = nil) {
        self.id = id
        self.label = label
        self.canRefresh = canRefresh
        self.sourceHost = sourceHost
        self.usage = usage
    }
}

 
 
 
public enum ClashMacScriptChoice: Equatable, Sendable {
    case keep
    case choose(String?)
}

 
 
public struct ClashMacAddedScript: Equatable, Sendable {
    public let id: String
    public let fromLink: Bool

    public init(id: String, fromLink: Bool) {
        self.id = id
        self.fromLink = fromLink
    }
}

 
public struct ClashMacScriptsState: Equatable, Sendable {
    public var scripts: [ClashMacScriptEntry]
     
    public var selectedID: String?
     
    public var patchFieldCount: Int
     
    public var exceptions: [String]

    public init(scripts: [ClashMacScriptEntry], selectedID: String?, patchFieldCount: Int, exceptions: [String]) {
        self.scripts = scripts
        self.selectedID = selectedID
        self.patchFieldCount = patchFieldCount
        self.exceptions = exceptions
    }

    public static let empty = ClashMacScriptsState(scripts: [], selectedID: nil, patchFieldCount: 0, exceptions: [])
}

 
 
 
 
public struct ClashMacScriptRefusal: Error {
     
     
    public let message: String
     
    public let state: ClashMacScriptsState
     
     
    public let useAnyway: (@MainActor () async throws -> ClashMacScriptsState)?
     
    public let editScript: (@MainActor () -> Void)?
     
     
     
    public let nothingBehind: Bool
     
    public let overForm: Bool

    public init(message: String, state: ClashMacScriptsState,
                useAnyway: (@MainActor () async throws -> ClashMacScriptsState)?,
                editScript: (@MainActor () -> Void)? = nil, nothingBehind: Bool = false, overForm: Bool = false) {
        self.message = message
        self.state = state
        self.useAnyway = useAnyway
        self.editScript = editScript
        self.nothingBehind = nothingBehind
        self.overForm = overForm
    }
}

extension View {
     
     
    func clashMacScriptRefusalAlert(_ refusal: Binding<ClashMacScriptRefusal?>,
                                    use: @escaping (ClashMacScriptRefusal) -> Void) -> some View {
        alert(
            Text(clash: .copy("Can’t Use This Script")),
            isPresented: Binding(get: { refusal.wrappedValue != nil }, set: { if !$0 { refusal.wrappedValue = nil } }),
            presenting: refusal.wrappedValue
        ) { refused in
            if !refused.nothingBehind {
                 
                if refused.useAnyway != nil {
                    Button { use(refused) } label: { Text(clash: .copy("Save Anyway")) }
                        .accessibilityIdentifier("scripts.refusal.save-anyway")
                }
                Button(role: .cancel) {} label: { Text(clash: .copy("Keep Editing")) }
                    .accessibilityIdentifier("scripts.refusal.keep-editing")
            } else {
                if let editScript = refused.editScript {
                    Button { editScript() } label: { Text(clash: .copy("Edit Script")) }
                        .accessibilityIdentifier("scripts.refusal.edit-script")
                }
                if refused.useAnyway != nil {
                    Button { use(refused) } label: { Text(clash: .copy("Use Anyway")) }
                        .accessibilityIdentifier("scripts.refusal.use-anyway")
                    Button(role: .cancel) {} label: { Text(clash: .copy("Cancel")) }
                        .accessibilityIdentifier("scripts.refusal.cancel")
                } else {
                    Button(role: .cancel) {} label: { Text(clash: .copy("OK")) }
                        .accessibilityIdentifier("scripts.refusal.ok")
                }
            }
        } message: { refused in
            Text(verbatim: refused.message)
        }
    }
}

 
 
 
public struct ClashMacScriptsActions {
    public var load: @MainActor () async -> ClashMacScriptsState
     
    public var select: @MainActor (String?) async throws -> ClashMacScriptsState
     
    public var addLink: @MainActor (String) async throws -> ClashMacScriptsState
     
    public var addManual: @MainActor (String, String) async throws -> ClashMacScriptsState
    public var remove: @MainActor (String) async throws -> ClashMacScriptsState
     
    public var edit: (@MainActor (String) -> Void)? = nil
     
     
     
     
     
     
    public var refresh: (@MainActor (String) async throws -> (state: ClashMacScriptsState, result: ClashFeedbackPresentation))? = nil
     
     
     
     
    public var updateAll: (@MainActor () async throws -> (state: ClashMacScriptsState, result: ClashFeedbackPresentation))? = nil
     
     
    public var didChange: Notification.Name? = nil
     
     
     
     
    public var chooseAdded: (@MainActor (ClashMacAddedScript) async throws -> ClashMacScriptsState)? = nil
     
    public var manageInLibrary: (@MainActor () -> Void)? = nil
    public var clearPatch: @MainActor () async throws -> ClashMacScriptsState
    public var removeException: @MainActor (Int) async throws -> ClashMacScriptsState

    public init(
        load: @escaping @MainActor () async -> ClashMacScriptsState,
        select: @escaping @MainActor (String?) async throws -> ClashMacScriptsState,
        addLink: @escaping @MainActor (String) async throws -> ClashMacScriptsState,
        addManual: @escaping @MainActor (String, String) async throws -> ClashMacScriptsState,
        remove: @escaping @MainActor (String) async throws -> ClashMacScriptsState,
        clearPatch: @escaping @MainActor () async throws -> ClashMacScriptsState,
        removeException: @escaping @MainActor (Int) async throws -> ClashMacScriptsState,
        refresh: (@MainActor (String) async throws -> (state: ClashMacScriptsState, result: ClashFeedbackPresentation))? = nil,
        updateAll: (@MainActor () async throws -> (state: ClashMacScriptsState, result: ClashFeedbackPresentation))? = nil
    ) {
        self.load = load
        self.select = select
        self.addLink = addLink
        self.addManual = addManual
        self.remove = remove
        self.clearPatch = clearPatch
        self.removeException = removeException
        self.refresh = refresh
        self.updateAll = updateAll
    }

    public static var unavailable: ClashMacScriptsActions {
        ClashMacScriptsActions(
            load: { .empty },
            select: { _ in throw ConfigurationLibraryError.unreadable },
            addLink: { _ in throw ConfigurationLibraryError.unreadable },
            addManual: { _, _ in throw ConfigurationLibraryError.unreadable },
            remove: { _ in throw ConfigurationLibraryError.unreadable },
            clearPatch: { throw ConfigurationLibraryError.unreadable },
            removeException: { _ in throw ConfigurationLibraryError.unreadable }
        )
    }
}

 
 
 
 
public struct ClashMacScriptsPage: View {
    private let actions: ClashMacScriptsActions
    @State private var state: ClashMacScriptsState
    @State private var loaded = false
    @State private var busy = false
     
     
    @State private var addedWaiting: [ClashMacAddedScript] = []
    @State private var error: String?
    @State private var adding = false
     
    @State private var refusal: ClashMacScriptRefusal?
     
    @State private var pendingRefusal: ClashMacScriptRefusal?
     
     
     
    @Environment(\.clashFeedback) private var feedback
    @Environment(\.locale) private var locale

     
     
     
     
    private let quickAdd: ((@escaping @MainActor (ClashMacAddedScript) -> Void) -> AnyView)?

    public init(
        actions: ClashMacScriptsActions,
        initial: ClashMacScriptsState = .empty,
        quickAdd: ((@escaping @MainActor (ClashMacAddedScript) -> Void) -> AnyView)? = nil
    ) {
        self.quickAdd = quickAdd
        self.actions = actions
        _state = State(initialValue: initial)
    }

     
     
    public static func choice(tapping id: String?, chosen: String?) -> ClashMacScriptChoice {
        id == chosen ? .keep : .choose(id)
    }

     
     
     
     
    public static func detail(of script: ClashMacScriptEntry) -> [ClashDisplayText] {
        script.usage.map { [$0] } ?? []
    }

     
     
     
    private func tap(_ id: String?) {
        guard case .choose(let choice) = Self.choice(tapping: id, chosen: state.selectedID) else { return }
        perform { try await actions.select(choice) }
    }

     
     
     
     
     
     
     
     
     
    private func radioRow<Label: View>(_ id: String?, identifier: String, _ choice: Binding<String?>,
                                       @ViewBuilder label: () -> Label) -> some View {
        Picker(selection: choice) {
            label()
                 
                 
                .padding(.vertical, Self.rowInset)
                 
                 
                 
                 
                 
                 
                 
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .tag(id)
        } label: {
             
            EmptyView()
        }
        .pickerStyle(.inline)
        .labelsHidden()
         
         
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
         
         
        .listRowInsets(EdgeInsets())
    }

     
     
    private static let rowInset: CGFloat = 4

     
     
     
    private func scriptRow(_ script: ClashMacScriptEntry, _ choice: Binding<String?>) -> some View {
        radioRow(script.id, identifier: "configuration-center.scripts.row.\(script.id)", choice) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: script.label)
                let detail = Self.detail(of: script)
                if !detail.isEmpty {
                    Text(verbatim: detail.map { ClashCopy.string(for: $0, locale: locale) }.joined(separator: " · "))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
         
         
        .contextMenu {
            if let edit = actions.edit {
                 
                Button { edit(script.id) } label: { Text(clash: .copy("Edit…")) }
            }
            if script.canRefresh, let refresh = actions.refresh {
                Button { runUpdate(script.label) { try await refresh(script.id) } } label: { Text(clash: .copy("Update")) }
            }
            if actions.edit != nil || (script.canRefresh && actions.refresh != nil) { Divider() }
             
            Button(role: .destructive) { perform { try await actions.remove(script.id) } } label: { Text(clash: .copy("Delete")) }
        }
         
        .disabled(busy)
    }

    public var body: some View {
         
         
         
         
         
         
         
         
         
         
         
        let chosen = state.scripts.first { $0.id == state.selectedID }
        let others = state.scripts.filter { $0.id != state.selectedID }
        let choice = Binding<String?>(get: { chosen?.id }, set: { tap($0) })
        List {
            if !state.scripts.isEmpty {
                Section {
                     
                    radioRow(nil, identifier: "configuration-center.scripts.none", choice) { Text(clash: .copy("None")) }
                        .disabled(busy)
                    if let chosen { scriptRow(chosen, choice) }
                } header: {
                    Text(clash: .copy("Script"))
                        .accessibilityIdentifier("configuration-center.scripts.selected")
                }
            }
            if !others.isEmpty {
                Section {
                    ForEach(others) { script in
                        scriptRow(script, choice)
                    }
                } header: {
                     
                    Text(clash: chosen == nil ? .copy("Scripts") : .copy("Other Scripts"))
                        .accessibilityIdentifier("configuration-center.scripts.other")
                }
            }
            if state.scripts.isEmpty {
                Section {
                    Text(clash: .copy("None")).foregroundStyle(.secondary)
                } header: {
                    Text(clash: .copy("Scripts"))
                }
            }
            if let quickAdd {
                quickAdd { added in chooseAdded(added) }
            }
             
             
             
            Section {
                 
                 
                 
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        if let updateAll = actions.updateAll, Self.offersUpdateAll(state) {
                            Button {
                                runUpdate(nil) { try await updateAll() }
                            } label: { Text(clash: .copy("Update All")) }
                            .disabled(busy)
                            .accessibilityIdentifier("configuration-center.scripts.update-all")
                        }
                        Spacer()
                         
                         
                         
                         
                         
                        Button { adding = true } label: { Text(clash: .opens("New Script", locale: locale)) }
                            .disabled(busy)
                            .accessibilityIdentifier("configuration-center.scripts.add")
                    }
                    if let feedback {
                        ClashMacFeedbackSlot(center: feedback, operations: [Self.updateOperation])
                    }
                }
                 
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            }
             
             
            if let manage = actions.manageInLibrary {
                Section {
                     
                     
                    Button(action: manage) { Text(clash: .copy("Manage Override Scripts")) }
                        .buttonStyle(.link)
                        .accessibilityIdentifier("configuration-center.scripts.manage")
                }
            }
             
             
             
            if let error {
                Section {
                    Text(verbatim: error).foregroundStyle(.red)
                        .accessibilityIdentifier("configuration-center.scripts.error")
                }
            }
        }
        .listStyle(.inset)
        .task {
            guard !loaded else { return }
            loaded = true
            state = await actions.load()
        }
        .sheet(isPresented: $adding, onDismiss: {
            if let pendingRefusal { refusal = pendingRefusal; self.pendingRefusal = nil }
        }) {
            ClashMacScriptAddSheet(
                addLink: { link in try await apply { try await actions.addLink(link) } },
                addManual: { name, body in try await apply { try await actions.addManual(name, body) } },
                useAnyway: { refused in
                    guard let useAnyway = refused.useAnyway else { return }
                    try await apply { try await useAnyway() }
                },
                close: { adding = false }
            )
            .clashModalPresentation(.fitted)
        }
         
         
         
        .onReceive(NotificationCenter.default.publisher(for: actions.didChange ?? Notification.Name("clash.scripts.unobserved"))
            .receive(on: DispatchQueue.main)) { _ in
            Task { @MainActor in state = await actions.load() }
        }
         
         
        .clashMacScriptRefusalAlert($refusal) { refused in
            guard let useAnyway = refused.useAnyway else { return }
            perform { try await useAnyway() }
        }
        .clashFrameWatch("configuration-scripts")
        .accessibilityIdentifier("configuration-center.scripts")
    }

     
     
     
    private func chooseAdded(_ added: ClashMacAddedScript) {
        guard let chooseAdded = actions.chooseAdded else {
            Task { @MainActor in state = await actions.load() }
            return
        }
         
        if busy { addedWaiting.append(added); return }
        perform { try await chooseAdded(added) }
    }

     
    private func chooseNextAdded() {
        if busy || addedWaiting.isEmpty { return }
        chooseAdded(addedWaiting.removeFirst())
    }

    private func perform(_ operation: @escaping () async throws -> ClashMacScriptsState) {
        guard !busy else { return }
        busy = true
        error = nil
        Task { @MainActor in
            defer {
                busy = false
                chooseNextAdded()
            }
            do {
                state = try await operation()
            } catch let refused as ClashMacScriptRefusal {
                state = refused.state
                refusal = refused
            } catch {
                self.error = ClashErrorCopy.message(error, locale: locale)
                state = await actions.load()
            }
        }
    }

    static let updateOperation = "scripts.update"

     
     
     
     
    static func offersUpdateAll(_ state: ClashMacScriptsState) -> Bool { !state.scripts.isEmpty }

     
     
     
    private func runUpdate(_ name: String?,
                           _ operation: @escaping () async throws -> (state: ClashMacScriptsState, result: ClashFeedbackPresentation)) {
        guard !busy else { return }
        busy = true
        error = nil
        let running = feedback?.say(.loading(title: ClashFeedbackCopy.updating, accessibilityIdentifier: "feedback.scripts.update.running"),
                                     operation: Self.updateOperation)
        Task { @MainActor in
            defer {
                busy = false
                chooseNextAdded()
            }
            do {
                let outcome = try await operation()
                state = outcome.state
                if let running, feedback?.update(running, to: outcome.result) == true {} else {
                    feedback?.say(outcome.result, operation: Self.updateOperation)
                }
            } catch {
                 
                 
                 
                let reason = ClashErrorCopy.message(error, locale: locale)
                guard let feedback else { self.error = reason; return }
                let failed = name.map { ClashMacFeedbackSentences.couldNotUpdate($0, reason: reason, id: Self.updateOperation) }
                    ?? ClashMacFeedbackSentences.couldNotUpdateScripts(reason: reason, id: Self.updateOperation)
                if let running, feedback.update(running, to: failed) {} else {
                    feedback.say(failed, operation: Self.updateOperation)
                }
            }
        }
    }

     
     
     
     
    private func apply(_ operation: @escaping () async throws -> ClashMacScriptsState) async throws {
        do {
            state = try await operation()
        } catch let refused as ClashMacScriptRefusal where !refused.overForm {
             
             
            state = refused.state
            pendingRefusal = refused
        }
        adding = false
    }
}

 
 
 
 
struct ClashMacScriptAddSheet: View {
    enum Tab: Int, CaseIterable, Identifiable {
        case link, file, manual
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .link: "URL"
            case .file: "File"
             
            case .manual: "New Script"
            }
        }
    }

    let addLink: (String) async throws -> Void
    let addManual: (String, String) async throws -> Void
     
    var useAnyway: (ClashMacScriptRefusal) async throws -> Void = { _ in }
    let close: () -> Void
    @Environment(\.locale) private var locale
     
     
    @State private var refusal: ClashMacScriptRefusal?
     
     
    @State private var tab: Tab = .manual
    @State private var link = ""
    @State private var name = ""
    @State private var scriptBody = ""
    @State private var choosingFile = false
    @State private var busy = false
    @State private var error: String?

    private var canAdd: Bool {
        switch tab {
        case .link: !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !busy
        case .file, .manual: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !scriptBody.isEmpty && !busy
        }
    }

    var body: some View {
        ClashMacSheetFrame(title: .copy("Add Script"), subtitle: .copy("Scripts"), width: 560, height: 500) {
            VStack(spacing: 0) {
                Picker(selection: $tab) {
                    ForEach(Tab.allCases) { item in Text(clash: .copy(item.title)).tag(item) }
                } label: {
                    Text(clash: .copy("Add Script"))
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .padding(.top, 16)
                .accessibilityIdentifier("configuration-center.script-add.tabs")
                ClashMacSheetForm {
                    switch tab {
                    case .link:
                        Section {
                            TextField(text: $link, prompt: Text(verbatim: "https://")) { Text(clash: .copy("URL")) }
                                .disabled(busy)
                                .accessibilityIdentifier("configuration-center.script-add.link")
                        }
                    case .file:
                        Section {
                            LabeledContent {
                                Button { choosingFile = true } label: { Text(clash: .copy("Choose File")) }
                                    .disabled(busy)
                                    .accessibilityIdentifier("configuration-center.script-add.choose-file")
                            } label: {
                                Text(clash: name.isEmpty ? .copy("File") : .verbatim(name))
                            }
                            TextField(text: $name, prompt: Text(clash: .copy("Name"))) { Text(clash: .copy("Name")) }
                                .disabled(busy)
                                .accessibilityIdentifier("configuration-center.script-add.file-name")
                        }
                    case .manual:
                        Section {
                            TextField(text: $name, prompt: Text(clash: .copy("New Script"))) { Text(clash: .copy("Name")) }
                                .disabled(busy)
                                .accessibilityIdentifier("configuration-center.script-add.name")
                            TextEditor(text: $scriptBody)
                                .font(.body.monospaced())
                                .frame(minHeight: 180)
                                .disabled(busy)
                                .accessibilityLabel(Text(clash: .copy("Script")))
                                .accessibilityIdentifier("configuration-center.script-add.body")
                        }
                    }
                    if let error {
                        Section {
                            Text(verbatim: error).foregroundStyle(.red)
                                .accessibilityIdentifier("configuration-center.script-add.error")
                        }
                    }
                }
                .accessibilityIdentifier("configuration-center.script-add")
            }
        } trailing: {
            ClashMacSheetButtons(
                closeIdentifier: "configuration-center.script-add.cancel",
                primaryTitle: .copy("Add"),
                primaryIdentifier: "configuration-center.script-add.add",
                primaryDisabled: !canAdd,
                isBusy: busy,
                onClose: close,
                onPrimary: add
            )
        }
        .onChange(of: tab) { _ in error = nil }
        .clashMacScriptRefusalAlert($refusal) { refused in
            busy = true
            Task { @MainActor in
                defer { busy = false }
                do { try await useAnyway(refused) } catch { self.error = ClashErrorCopy.message(error, locale: locale) }
            }
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.plainText, .text, .javaScript].compactMap { $0 }) { result in
            switch result {
            case .success(let picked):
                let scoped = picked.startAccessingSecurityScopedResource()
                defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
                do {
                    scriptBody = try String(contentsOf: picked, encoding: .utf8)
                    if name.isEmpty { name = picked.deletingPathExtension().lastPathComponent }
                    error = nil
                } catch {
                    self.error = ClashErrorCopy.message(error, locale: locale)
                }
            case .failure(let failure):
                error = ClashErrorCopy.message(failure, locale: locale)
            }
        }
    }

    private func add() {
        guard canAdd else { return }
        busy = true
        error = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                switch tab {
                case .link: try await addLink(link.trimmingCharacters(in: .whitespacesAndNewlines))
                case .file, .manual: try await addManual(name.trimmingCharacters(in: .whitespacesAndNewlines), scriptBody)
                }
            } catch let refused as ClashMacScriptRefusal {
                 
                refusal = refused
            } catch {
                self.error = ClashErrorCopy.message(error, locale: locale)
            }
        }
    }
}
