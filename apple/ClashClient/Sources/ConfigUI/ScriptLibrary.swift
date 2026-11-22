import Foundation
import ClashClientKit
import ClashClientUI
import SwiftUI
import UniformTypeIdentifiers

struct ConfigScript: Codable, Equatable, Identifiable {
    var id: String
    var label: String
    var body: String
     
     
     
     
     
    var sourceURL: String? = nil
}

enum ScriptImportError: LocalizedError, Equatable {
    case emptyAddress
    case notAnAddress
    case unsupportedScheme(String)
    case notText
    case empty

    var errorDescription: String? {
        switch self {
        case .emptyAddress:
            return "Enter the address of the script you want to import."
        case .notAnAddress:
             
             
            return "That is not a web address. Paste the script file's URL, not the script."
        case let .unsupportedScheme(scheme):
            return ClashCopy.format(
                "Scripts are imported over http or https. This address uses %@.",
                locale: .current,
                scheme
            )
        case .notText:
            return "The address answered with something that is not text."
        case .empty:
            return "The address answered with an empty document."
        }
    }
}

 
 
 
 
 
 
 
enum ScriptEditorSource: Hashable { case write, url, file }

 
 
 
 
 
 
 
 
 
enum ScriptEditorSaveIntent: Equatable {
    case save
    case importThenSave

    static func decide(source: ScriptEditorSource, address: String) -> ScriptEditorSaveIntent {
        guard source == .url,
              !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return .save }
        return .importThenSave
    }
}

 
 
 
 
 
 
 
 
enum ScriptImport {
     
     
    static let maxBytes = 1 << 20

     
    static func address(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ScriptImportError.emptyAddress }
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host, !host.isEmpty,
              let url = components.url
        else { throw ScriptImportError.notAnAddress }
        guard scheme == "http" || scheme == "https" else {
            throw ScriptImportError.unsupportedScheme(scheme)
        }
        return url
    }

     
     
     
     
     
    static func suggestedName(for url: URL) -> String? {
        let stem = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stem.isEmpty, stem != "/", !stem.contains("..") else { return nil }
        return String(stem.prefix(64))
    }

     
     
     
     
     
     
     
    static func body(
        at raw: String,
        using downloader: HTTPFetching = ResourceDownloader()
    ) async throws -> String {
        var request = URLRequest(url: try address(raw))
        request.setValue(ClientUserAgent.resolved(), forHTTPHeaderField: "User-Agent")
        let result = try await downloader.fetch(
            request,
            maxBytes: maxBytes,
            redirectPolicy: .followAcrossOrigins(maxHops: 5)
        )
        guard let text = String(data: result.data, encoding: .utf8) else {
            throw ScriptImportError.notText
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ScriptImportError.empty
        }
        return text
    }

     
     
     
    static func refreshed(
        _ script: ConfigScript,
        using downloader: HTTPFetching = ResourceDownloader()
    ) async throws -> ConfigScript {
        guard let address = script.sourceURL, !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ScriptImportError.emptyAddress
        }
        var updated = script
        updated.body = try await body(at: address, using: downloader)
        return updated
    }
}

enum ScriptLibraryError: LocalizedError, Equatable {
    case missing(String)
     
     
     
     
     
    case tooLarge

    var errorDescription: String? {
        switch self {
        case let .missing(id): return "Selected override script '\(id)' no longer exists."
        case .tooLarge:
            return ClashCopy.string(for: .copy("This configuration is too large to run an override script."),
                                    locale: AppPreferences.language().locale)
        }
    }

     
     
    static func refusingLarge(_ yaml: String) throws {
        if ConfigTransforms.isTooLargeToReadWhole(yaml) { throw ScriptLibraryError.tooLarge }
    }
}

 
 
 
 
 
 
 
 
enum UnsavedEditPolicy: Equatable {
    case leave
    case offerToSave

    static func decision(original: String, current: String) -> UnsavedEditPolicy {
         
         
         
        current == original ? .leave : .offerToSave
    }
}

enum ScriptLibrary {
    private static let key = "script.library"

    static var appGroupDefaults: UserDefaults {


        return UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite) ?? .standard
    }



     
    static let defaultLabel = "New Script"

     
    static func fresh() -> ConfigScript {
        ConfigScript(id: UUID().uuidString.lowercased(), label: defaultLabel, body: ScriptSettings.template)
    }

    static func load(from defaults: UserDefaults = appGroupDefaults) -> [ConfigScript] {
        guard let data = defaults.data(forKey: key),
              let scripts = try? JSONDecoder().decode([ConfigScript].self, from: data) else {
            return []
        }
        return scripts
    }

     
     
     
     
     
     
     
    static let didChange = Notification.Name("ClashScriptLibraryDidChange")

     
     
     
    static let changesRuntimeKey = "changesRuntime"

    static func changesRuntime(_ note: Notification) -> Bool {
        note.userInfo?[changesRuntimeKey] as? Bool ?? true
    }

    enum RenameError: LocalizedError, Equatable {
        case emptyName, nameTaken
        var errorDescription: String? {
            switch self {
            case .emptyName: return ClashCopy.string("Enter a name.", locale: .current)
            case .nameTaken: return ClashCopy.string("Another script already uses that name.", locale: .current)
            }
        }
    }

    static func save(_ scripts: [ConfigScript], in defaults: UserDefaults = appGroupDefaults) {
        writeLock.lock()
        store(scripts, in: defaults)
        writeLock.unlock()
        NotificationCenter.default.post(name: didChange, object: defaults)
    }

     
     
     
     
    private static let writeLock = NSRecursiveLock()

    private static func store(_ scripts: [ConfigScript], in defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(scripts) else { return }
        defaults.set(data, forKey: key)
    }

    private static func mutate(in defaults: UserDefaults, changesRuntime: Bool = true,
                               _ change: (inout [ConfigScript]) throws -> Void) rethrows {
        writeLock.lock()
        var held = true
        defer { if held { writeLock.unlock() } }
        var scripts = load(from: defaults)
        try change(&scripts)
        store(scripts, in: defaults)
        writeLock.unlock()
        held = false
        NotificationCenter.default.post(name: didChange, object: defaults,
                                        userInfo: [changesRuntimeKey: changesRuntime])
    }

    struct ChangedMeanwhile: Error {}

     
    static func removeUnchanged(_ scripts: [ConfigScript], in defaults: UserDefaults) throws {
        guard !scripts.isEmpty else { return }
        mutate(in: defaults) { current in current.removeAll { scripts.contains($0) } }
    }

     
    static func confirm(_ expected: [ConfigScript], in defaults: UserDefaults) throws {
        writeLock.lock()
        defer { writeLock.unlock() }
        guard load(from: defaults) == expected else { throw ChangedMeanwhile() }
    }

     
    static func replace(expected: [ConfigScript], with scripts: [ConfigScript], in defaults: UserDefaults) throws {
        try mutate(in: defaults) { current in
            guard current == expected else { throw ChangedMeanwhile() }
            current = scripts
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static let testConfigYAML = """
    mode: rule
    log-level: info
    proxies:
      - name: "HK-01"
        type: trojan
        server: hk01.example.com
        port: 443
        password: "test-only"
      - name: "JP-01 2x"
        type: ss
        server: jp01.example.com
        port: 8388
        cipher: aes-128-gcm
        password: "test-only"
    proxy-providers: {}
    proxy-groups:
      - name: PROXY
        type: select
        proxies:
          - HK-01
          - JP-01 2x
          - DIRECT
    rules:
      - MATCH,PROXY
    """

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func editedScript(
        id: String,
        label: String,
        body: String,
        sourceURL: String? = nil,
        existing: [ConfigScript] = []
    ) -> ConfigScript? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let taken = existing.contains {
            $0.id != id
                && $0.label.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        guard !taken else { return nil }
        return ConfigScript(id: id, label: trimmed, body: body, sourceURL: sourceURL)
    }

     
     
     
     
    static func upsert(_ script: ConfigScript, in defaults: UserDefaults = appGroupDefaults) {
        let stored = load(from: defaults).first { $0.id == script.id }
        let onlyRenames = stored.map { $0.body == script.body && $0.sourceURL == script.sourceURL } ?? false
        mutate(in: defaults, changesRuntime: !onlyRenames) { scripts in
            if let index = scripts.firstIndex(where: { $0.id == script.id }) {
                scripts[index] = script
            } else {
                scripts.append(script)
            }
        }
    }

     
     
    static func rename(id: String, to label: String, in defaults: UserDefaults = appGroupDefaults) throws {
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw RenameError.emptyName }
        try mutate(in: defaults, changesRuntime: false) { scripts in
            guard let index = scripts.firstIndex(where: { $0.id == id }) else { return }
            guard !scripts.contains(where: { $0.id != id && $0.label.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw RenameError.nameTaken
            }
            scripts[index].label = name
        }
    }

    static func remove(
        id: String,
        in defaults: UserDefaults = appGroupDefaults,
        unlinkProfiles: Bool = true
    ) {
        mutate(in: defaults) { $0.removeAll { $0.id == id } }
         
        SourceEditDrafts.shared.clearAll(owner: id)
        guard unlinkProfiles else { return }
        guard let container = ClashAppIdentifiers.appGroupContainer else { return }
        let store = ProfileStore(
            fileURL: container.appendingPathComponent("working/store/profiles.json")
        )
         
         
        _ = try? store.updateAll { $0 = unlinkReferences(to: id, from: $0) }
    }

     
     
    struct Removal: Equatable {
        let script: ConfigScript
        let index: Int
        let selectedBy: [String]
        let postMergeBy: [String]
         
        var drafts = SourceEditDrafts.Held.none
    }

     
    static func removeRestorably(
        id: String,
        in defaults: UserDefaults = appGroupDefaults,
        profiles: ProfileStore? = defaultProfileStore
    ) -> Removal? {
        let scripts = load(from: defaults)
        guard let index = scripts.firstIndex(where: { $0.id == id }) else { return nil }
        let linked = profiles?.load() ?? []
        let removal = Removal(
            script: scripts[index], index: index,
            selectedBy: linked.filter { $0.selectedScriptID == id }.map(\.id),
            postMergeBy: linked.filter { $0.postMergeScriptID == id }.map(\.id),
            drafts: SourceEditDrafts.shared.holding(owner: id)
        )
        mutate(in: defaults) { $0.removeAll { $0.id == id } }
        SourceEditDrafts.shared.clearAll(owner: id)
        _ = try? profiles?.updateAll { $0 = unlinkReferences(to: id, from: $0) }
        return removal
    }

     
     
     
    static func restore(
        _ removal: Removal,
        in defaults: UserDefaults = appGroupDefaults,
        profiles: ProfileStore? = defaultProfileStore
    ) throws {
         
         
        if !removal.selectedBy.isEmpty || !removal.postMergeBy.isEmpty {
            _ = try profiles?.updateAll { list in
                for index in list.indices {
                    if removal.selectedBy.contains(list[index].id), list[index].selectedScriptID == nil {
                        list[index].selectedScriptID = removal.script.id
                    }
                    if removal.postMergeBy.contains(list[index].id), list[index].postMergeScriptID == nil {
                        list[index].postMergeScriptID = removal.script.id
                    }
                }
            }
        }
        mutate(in: defaults) { scripts in
            guard !scripts.contains(where: { $0.id == removal.script.id }) else { return }
            scripts.insert(removal.script, at: min(removal.index, scripts.count))
        }
        SourceEditDrafts.shared.putBack(removal.drafts)
    }

     
    static var defaultProfileStore: ProfileStore? {
        ClashAppIdentifiers.appGroupContainer.map {
            ProfileStore(fileURL: $0.appendingPathComponent("working/store/profiles.json"))
        }
    }

     
     
     
     
    static func activeProfileName() -> String {
        guard let container = ClashAppIdentifiers.appGroupContainer,
              let configStore = try? ConfigResourceStore(containerURL: container),
              let activeID = (try? configStore.activeIdentity())?.profileID
        else { return "" }
        let profiles = ProfileStore(
            fileURL: container.appendingPathComponent("working/store/profiles.json")
        )
        return profiles.load().first { $0.id == activeID }?.label ?? ""
    }

    static func unlinkReferences(to id: String, from profiles: [Profile]) -> [Profile] {
        profiles.map { profile in
            guard profile.selectedScriptID == id || profile.postMergeScriptID == id else {
                return profile
            }
            var updated = profile
            if updated.selectedScriptID == id {
                updated.selectedScriptID = nil
            }
            if updated.postMergeScriptID == id {
                updated.postMergeScriptID = nil
            }
            return updated
        }
    }

     
     
    static func apply(id: String?, to yaml: String,
                      profileName: String = "",
                      from defaults: UserDefaults = appGroupDefaults,
                      caller: ScriptEngine.Caller) throws -> String {
        try apply(
            id: id, to: yaml, scripts: load(from: defaults), profileName: profileName, caller: caller
        )
    }

    static func apply(
        id: String?,
        to yaml: String,
        scripts: [ConfigScript],
        profileName: String = "",
        caller: ScriptEngine.Caller
    ) throws -> String {
        guard let id else { return yaml }
        guard let script = scripts.first(where: { $0.id == id }) else {
            throw ScriptLibraryError.missing(id)
        }
        try ScriptLibraryError.refusingLarge(yaml)
        let configJSON = try ConfigTransforms.yamlToJSON(yaml)
        let rewritten = try ScriptEngine.run(
            script: script.body, configJSON: configJSON, profileName: profileName, caller: caller, name: script.label
        )
        return try ConfigTransforms.jsonToYAML(rewritten)
    }
}

extension ScriptLibrary {
     
     
     
    static func usage(ofScript id: String, profiles: [Profile]) -> LibraryUsage {
        LibraryUsage(names: profiles.filter { $0.selectedScriptID == id }.map(\.label))
    }

     
     
     
    static func configurationsRunning(_ id: String, in profiles: [Profile]) -> [Profile] {
        profiles.filter { ScriptSaveCheck.runs(id, in: $0) }
    }
}

 
 
 
 
 
 
enum ScriptLibraryCopy {
    static func deletionNote(usedBy names: [String]) -> ClashDisplayText? {
        switch names.count {
        case 0: nil
        case 1: .format("Once deleted, “%@” stops using it.", [names[0]])
        default: .format("Once deleted, %@ configurations stop using it.", ["\(names.count)"])
        }
    }
}

 
 
 
 
 
 
 
#if os(iOS)
struct ScriptLibraryView: View {
     
     
    private let library: UserDefaults
    private let profileStore: ProfileStore?
     
    private let model: ProfilesViewModel
    @State private var scripts: [ConfigScript]
     
     
     
    @State private var configurations: [Profile] = []
    @State private var deletingScripts: [ConfigScript] = []
     
     
    @State private var doorSelection: String?
     
     
    @State private var addingManually = false
    @State private var updating = false
    @StateObject private var quickAdd: ProfileQuickAddController
    @Environment(\.clashFeedback) private var feedback
     
    private var updatable: [ConfigScript] { scripts.filter { !($0.sourceURL ?? "").isEmpty } }

    init(model: ProfilesViewModel, library: UserDefaults = ScriptLibrary.appGroupDefaults,
         profiles: ProfileStore? = ScriptLibrary.defaultProfileStore) {
        self.model = model
        self.library = library
        profileStore = profiles
        _scripts = State(initialValue: ScriptLibrary.load(from: library))
        _quickAdd = StateObject(wrappedValue: ProfileQuickAddController(model: model, target: .scripts))
    }

    var body: some View {
        Group {
        List {
            if scripts.isEmpty {
                ClashEmptyState(
                    title: "No Scripts",
                    message: "",
                    symbol: .curlybraces
                )
                .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(scripts) { script in
                         
                         
                         
                         
                         
                         
                        ClashDoorLink(script.id, selection: $doorSelection) {
                            ScriptLibraryDetailPage(script: script, library: library,
                                usedBy: configurations.filter { $0.selectedScriptID == script.id }.map(\.label),
                                update: (script.sourceURL ?? "").isEmpty ? nil : { Task { await update(saved(script)) } },
                                delete: { removeWithUndo(saved(script)) },
                                saveCheck: { saveCheck(for: $0) })
                        } label: {
                            scriptRow(script)
                        }
                        .accessibilityIdentifier("scripts.row.\(script.id)")
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            if !(script.sourceURL ?? "").isEmpty {
                                 
                                 
                                Button { Task { await update([script]) } } label: {
                                    Label("Update", systemImage: ClashSymbol.arrowClockwise.name)
                                }
                                .tint(.blue)
                                .accessibilityIdentifier("scripts.row.update")
                            }
                        }
                    }
                    .onDelete { offsets in
                        removeWithUndo(offsets.compactMap { scripts.indices.contains($0) ? scripts[$0] : nil })
                    }
                } header: {
                    ClashConfigurationLibraryHeader(title: .copy("Override Scripts"), count: scripts.count)
                }
                 
                 
                 
                 
                Section {
                    Button { Task { await update(updatable) } } label: {
                        Text(ClashCopy.key("Update All"))
                    }
                    .disabled(updating)
                    .accessibilityIdentifier("scripts.update.all")
                }
            }
             
             
             
             
            ProfileQuickAddCard(controller: quickAdd,
                identifiers: .init(linkIdentifier: "scripts.library.quick-add.link",
                                   scanIdentifier: "scripts.library.quick-add.scan",
                                   fileIdentifier: "scripts.library.quick-add.file",
                                   manualIdentifier: "scripts.library.quick-add.manual",
                                   statusIdentifier: "scripts.library.quick-add.status"),
                manual: { addingManually = true }, showsScan: false, header: "Add Override Script")
        }
        .clashInsetGroupedListStyle()
         
        .profileQuickAddPresenters(quickAdd)
        .onAppear { quickAdd.onScriptAdded = { _ in reload() } }
        .clashProductModal(isPresented: $addingManually, role: .page) {
            ScriptManualPage(library: library, close: { addingManually = false }) { _ in
                addingManually = false
                reload()
            }
            .clashModalPresentation(.page)
        }
        }
        .clashPageTitle(pageTitle)
        .clashDetailPageInsets()
        .accessibilityIdentifier("scripts.screen")
        .task { reload() }
         
         
         
        .onReceive(NotificationCenter.default.publisher(for: ScriptLibrary.didChange)) { _ in reload() }
        .clashToolbarUnlessInPanel {
            ToolbarItemGroup(placement: .clashNavigationTrailing) {
                ClashEditButton()
                Button {
                    addingManually = true
                } label: {
                    Label("Add Script", systemImage: ClashSymbol.plus.name)
                }
            }
        }
    }

     
    private var pageTitle: ClashDisplayText { "Override Library" }

     
    private func scriptRow(_ script: ConfigScript) -> some View {
        HStack(spacing: ClashTheme.Spacing.row) {
            ClashSymbolImage(symbol: .curlybraces)
                .foregroundStyle(.purple)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                 
                Text(verbatim: script.label)
                    .font(.body).foregroundStyle(.primary)
                    .lineLimit(1).truncationMode(.tail)
                Text(clash: ClashLibraryUsageCopy.text(ScriptLibrary.usage(ofScript: script.id, profiles: configurations)))
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func reload() {
        scripts = ScriptLibrary.load(from: library)
        configurations = profileStore?.load() ?? []
    }

     
     
     
     
    private func saveCheck(for script: ConfigScript) -> ((ConfigScript) async -> ScriptSaveCheck.Verdict)? {
        Self.saveCheck(running: ScriptLibrary.configurationsRunning(script.id, in: configurations),
                       library: library, model: model)
    }

     
     
     
    static func saveCheck(running: [Profile], library: UserDefaults,
                          model: ProfilesViewModel) -> ((ConfigScript) async -> ScriptSaveCheck.Verdict)? {
        guard !running.isEmpty else { return nil }
        return { edited in
            var scripts = ScriptLibrary.load(from: library)
            if let index = scripts.firstIndex(where: { $0.id == edited.id }) {
                scripts[index] = edited
            } else {
                scripts.append(edited)
            }
            for profile in running {
                guard let raw = await model.loadUIProjectedYAML(for: profile) else { continue }
                let verdict = await Task.detached(priority: .userInitiated) { [scripts] in
                    ScriptSaveCheck.verdict(raw: raw, profile: profile, scripts: scripts)
                }.value
                if verdict != .accepted { return verdict }
            }
            return .accepted
        }
    }

     
     
     
     
    private func saved(_ script: ConfigScript) -> [ConfigScript] {
        ScriptLibrary.load(from: library).filter { $0.id == script.id }
    }

     
     
     
     
     
     
    private func removeWithUndo(_ targets: [ConfigScript]) {
        guard !targets.isEmpty else { return }
        let library = library, profileStore = profileStore
        let removals = targets.compactMap { ScriptLibrary.removeRestorably(id: $0.id, in: library, profiles: profileStore) }
        reload()
        let name = targets.map(\.label).joined(separator: ", ")
        let feedback = feedback
        feedback?.show(.success(title: ClashFeedbackCopy.deleted(name), action: .undo, accessibilityIdentifier: "feedback.scripts.delete"),
                       operation: "scripts.delete",
                       perform: {
             
             
            var failed: [(String, String)] = []
            for removal in removals.reversed() {
                do { try ScriptLibrary.restore(removal, in: library, profiles: profileStore) }
                catch { failed.append((removal.script.label, error.localizedDescription)) }
            }
            reload()
            if failed.isEmpty {
                feedback?.show(.success(title: ClashFeedbackCopy.restored(name), accessibilityIdentifier: "feedback.scripts.delete"),
                               operation: "scripts.delete")
            } else {
                let reasons = failed.map { "\($0.0): \($0.1)" }.joined(separator: "\n")
                feedback?.show(.error(title: ClashFeedbackCopy.couldNotUndo, message: .verbatim(reasons),
                                      accessibilityIdentifier: "feedback.scripts.delete"), operation: "scripts.delete")
            }
        })
    }

    @MainActor
    private func update(_ targets: [ConfigScript]) async {
        guard !updating else { return }
        updating = true
        defer { updating = false }
        let operation = "scripts.update-all"
        if targets.isEmpty {
            feedback?.show(ScriptUpdateSummary.nothingToFetch, operation: operation)
            return
        }
        let running = feedback?.show(.loading(title: ClashFeedbackCopy.updating, progress: .init(completed: 0, total: targets.count),
                                              accessibilityIdentifier: "feedback.scripts.update"), operation: operation)
        var outcome = ScriptUpdateSummary()
        var failedIDs: Set<String> = []
        for (index, script) in targets.enumerated() {
            defer {
                if let running {
                    feedback?.update(running, to: .loading(title: ClashFeedbackCopy.updating,
                                                           progress: .init(completed: index + 1, total: targets.count),
                                                           accessibilityIdentifier: "feedback.scripts.update"))
                }
            }
            do {
                let refreshed = try await ScriptImport.refreshed(script)
                if refreshed.body != script.body {
                    ScriptLibrary.upsert(refreshed, in: library)
                    outcome.changed.append(script.label)
                } else {
                    outcome.unchanged.append(script.label)
                }
            } catch {
                outcome.failed.append((script.label, error.localizedDescription))
                failedIDs.insert(script.id)
            }
        }
        scripts = ScriptLibrary.load(from: library)
         
         
         
        let library = library
        let retry: @MainActor () -> Void = {
            Task { await update(ScriptLibrary.load(from: library).filter { failedIDs.contains($0.id) && !($0.sourceURL ?? "").isEmpty }) }
        }
        feedback?.answer(running, with: outcome.presentation(), operation: operation, perform: retry)
    }
}

 
 
 
 
 
 
struct ScriptLibraryDetailPage: View {
    let script: ConfigScript
    let library: UserDefaults
    let usedBy: [String]
    let update: (() -> Void)?
    let delete: () -> Void
     
    let saveCheck: (ConfigScript) -> ((ConfigScript) async -> ScriptSaveCheck.Verdict)?

    @State private var current: ConfigScript
     
    @State private var reading: ConfigScript?
    @State private var editing: ConfigScript?
    @State private var renaming: ConfigScript?
    @State private var renameText = ""
    @State private var renameFailure: String?
    @Environment(\.clashPopRoute) private var popRoute
    @StateObject private var dismiss = ClashDismissHandle()

    init(script: ConfigScript, library: UserDefaults, usedBy: [String], update: (() -> Void)?, delete: @escaping () -> Void,
         saveCheck: @escaping (ConfigScript) -> ((ConfigScript) async -> ScriptSaveCheck.Verdict)?) {
        self.script = script
        self.library = library
        self.usedBy = usedBy
        self.update = update
        self.delete = delete
        self.saveCheck = saveCheck
        _current = State(initialValue: script)
    }

    private var followsALink: Bool { !(current.sourceURL ?? "").isEmpty }

    var body: some View {
        List {
            Section {
                Button {
                    renameText = current.label
                    renaming = current
                } label: {
                    ScriptDetailValueRow(title: "Name", value: current.label)
                }
                .accessibilityIdentifier("scripts.detail.rename")
                if let link = current.sourceURL, !link.isEmpty {
                     
                    ScriptDetailValueRow(title: "Link", value: link)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("scripts.detail.link")
                }
            }
            Section {
                 
                 
                 
                Button {
                    if followsALink { reading = current } else { editing = current }
                } label: {
                    Text(ClashCopy.key(followsALink ? "View Content" : "Edit"))
                }
                .accessibilityIdentifier("scripts.detail.content")
                if let update {
                    Button(action: update) { Text(ClashCopy.key("Update")) }
                        .accessibilityIdentifier("scripts.detail.update")
                }
            }
            Section {
                if usedBy.isEmpty {
                    Text(clash: ClashLibraryUsageCopy.text(.none)).foregroundStyle(.secondary)
                } else {
                    ForEach(usedBy, id: \.self) { name in
                         
                        Text(verbatim: name)
                    }
                }
            } header: {
                ClashConfigurationLibraryHeader(title: .copy("Configurations Using It"))
            }
            Section {
                Button(role: .destructive) {
                     
                     
                     
                    ClashPushedPageExit.leave(popRoute: popRoute, dismiss: dismiss)
                    delete()
                } label: {
                    Text(ClashCopy.key("Delete Override Script"))
                }
                .accessibilityIdentifier("scripts.detail.delete")
            } footer: {
                if let note = ScriptLibraryCopy.deletionNote(usedBy: usedBy) {
                    Text(clash: note)
                }
            }
        }
        .clashInsetGroupedListStyle()
        .clashPageTitle(.verbatim(current.label), watchAs: "Script")
        .accessibilityIdentifier("scripts.detail.screen")
        .onReceive(NotificationCenter.default.publisher(for: ScriptLibrary.didChange)) { _ in
            if let saved = ScriptLibrary.load(from: library).first(where: { $0.id == script.id }) { current = saved }
        }
        .clashProductModal(item: $reading, role: .page) { opened in
            ScriptLibraryContentPage(id: opened.id, library: library, close: { reading = nil })
                .clashModalPresentation(.page)
        }
         
         
        .clashProductModal(item: $editing, role: .page, immersive: { _ in true }) { opened in
            ScriptEditorView(script: opened, check: saveCheck(opened), rename: { name in
                try ScriptLibrary.rename(id: opened.id, to: name, in: library)
                if let renamed = ScriptLibrary.load(from: library).first(where: { $0.id == opened.id }) {
                    editing?.label = renamed.label
                }
            }) { saved in
                ScriptLibrary.upsert(saved, in: library)
                editing = nil
            }
            .clashModalPresentation(.page)
        }
         
         
        .clashTextFieldAlert("Rename…", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
                             presenting: renaming, text: $renameText,
                             field: ClashTextFieldAlertField(placeholder: "Script name",
                                                             identifier: "scripts.detail.rename.name"),
                             isConfirmEnabled: { script, name in
                                 ScriptLibrary.editedScript(id: script.id, label: name, body: script.body,
                                                            existing: ScriptLibrary.load(from: library)) != nil
                             }) { script, name in
            do { try ScriptLibrary.rename(id: script.id, to: name, in: library) }
            catch { renameFailure = error.localizedDescription }
        }
        .alert(Text(ClashCopy.key("Rename…")), isPresented: Binding(get: { renameFailure != nil }, set: { if !$0 { renameFailure = nil } })) {
            Button("OK") {}
        } message: {
            Text(verbatim: renameFailure ?? "")
        }
        .clashCapturesDismiss(dismiss)
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
struct ScriptLibraryContentPage: View {
    let id: String
    let library: UserDefaults
    let close: () -> Void
     
    @State private var script: ConfigScript?
     
    @State private var text: ClashModuleScriptSourceView.ScriptText?
    @Environment(\.clashFeedback) private var feedback

    init(id: String, library: UserDefaults, close: @escaping () -> Void) {
        self.id = id
        self.library = library
        self.close = close
    }

    var body: some View {
        ClashFeatureNavigationContainer {
            ScrollView {
                Group {
                    if let text {
                        numbered(text)
                    } else {
                        ProgressView()
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("scripts.content.screen")
            .clashPageTitle(script.map { ClashDisplayText.verbatim($0.label) } ?? "Script", watchAs: "Script")
            .clashToolbarUnlessInPanel {
                ToolbarItem(placement: .cancellationAction) {
                    ClashSheetCloseButton(dismiss: close)
                }
                ToolbarItem(placement: .primaryAction) {
                    if let text {
                        Button {
                            ClashClipboard.copy(text.original, feedback: feedback, operation: "scripts.content.copy")
                        } label: {
                            Text("Copy")
                        }
                        .accessibilityIdentifier("scripts.content.copy")
                    }
                }
            }
            .onAppear { reread() }
            .onReceive(NotificationCenter.default.publisher(for: ScriptLibrary.didChange)) { _ in reread() }
            .task(id: script?.body) {
                guard let source = script?.body else { return }
                 
                if text?.original != source { text = nil }
                let rows = await Self.rows(source)
                if !Task.isCancelled { text = rows }
            }
        }
    }

     
     
    private func reread() {
        if let saved = ScriptLibrary.load(from: library).first(where: { $0.id == id }) { script = saved }
    }

    private func numbered(_ text: ClashModuleScriptSourceView.ScriptText) -> some View {
        let width = String(text.lineCount).count
        return LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(text.rows.indices, id: \.self) { index in
                let row = text.rows[index]
                HStack(alignment: .firstTextBaseline, spacing: ClashTheme.Spacing.compact) {
                    Text(verbatim: row.line.map { ClashModuleScriptSourceView.number($0, width: width) }
                                 ?? String(repeating: "\u{2007}", count: width))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(verbatim: row.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .font(.system(.footnote, design: .monospaced))
            }
        }
    }

     
     
     
    static func rows(_ source: String) async -> ClashModuleScriptSourceView.ScriptText {
        await Task.detached(priority: .userInitiated) { ClashModuleScriptSourceView.text(source) }.value
    }
}

 
 
private struct ScriptDetailValueRow: View {
    let title: String
     
    let value: String

    var body: some View {
        if #available(iOS 16.0, *) {
            LabeledContent {
                Text(verbatim: value).foregroundStyle(.secondary).lineLimit(2)
            } label: {
                Text(ClashCopy.key(title)).foregroundStyle(.primary)
            }
        } else {
            HStack {
                Text(ClashCopy.key(title)).foregroundStyle(.primary)
                Spacer()
                Text(verbatim: value).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }
}

 
 
 
 
 
 
 
 
struct ScriptDetailsFromAConfiguration: View {
    let script: ConfigScript
    let library: UserDefaults
    let profiles: ProfileStore?
    let model: ProfilesViewModel?
    let update: (ConfigScript) -> Void
    let delete: (ConfigScript) -> Void
    let pageCheck: (ConfigScript) -> ((ConfigScript) async -> ScriptSaveCheck.Verdict)?
    @State private var configurations: [Profile] = []

    var body: some View {
        ScriptLibraryDetailPage(
            script: script, library: library,
            usedBy: configurations.filter { $0.selectedScriptID == script.id }.map(\.label),
            update: (script.sourceURL ?? "").isEmpty ? nil : { if let saved = saved { update(saved) } },
            delete: { if let saved = saved { delete(saved) } },
            saveCheck: { edited in
                guard let model else { return pageCheck(edited) }
                return ScriptLibraryView.saveCheck(
                    running: ScriptLibrary.configurationsRunning(edited.id, in: configurations), library: library, model: model)
            })
            .onAppear { reload() }
            .onReceive(NotificationCenter.default.publisher(for: ScriptLibrary.didChange)) { _ in reload() }
    }

     
    private var saved: ConfigScript? { ScriptLibrary.load(from: library).first { $0.id == script.id } }

    private func reload() { configurations = profiles?.load() ?? [] }
}
#endif

 
 
 
 
 
struct ScriptUpdateSummary {
     
     
     
     
     
     
    static let nothingToFetch = ClashFeedbackPresentation.information(
        title: ClashFeedbackCopy.nothingToUpdate,
        message: .copy("None of these scripts has a link to update from. For one that came from a link, add it again from the link."),
        isBatchSummary: true,
        accessibilityIdentifier: "feedback.scripts.update"
    )

    var changed: [String] = []
    var unchanged: [String] = []
    var failed: [(name: String, reason: String)] = []

     
     
     
    func presentation(accessibilityIdentifier: String = "feedback.scripts.update") -> ClashFeedbackPresentation {
        if changed.count + unchanged.count + failed.count == 1 {
            if let name = changed.first {
                return .success(title: ClashFeedbackCopy.updated(name), accessibilityIdentifier: accessibilityIdentifier)
            }
            if let name = unchanged.first {
                return .information(title: ClashFeedbackCopy.upToDate(name), accessibilityIdentifier: accessibilityIdentifier)
            }
            if let failure = failed.first {
                return .error(title: ClashFeedbackCopy.couldNotUpdate(failure.name), message: .verbatim(failure.reason),
                              action: .retry, accessibilityIdentifier: accessibilityIdentifier)
            }
        }
        let title = ClashFeedbackCopy.batch(updated: changed.count, failed: failed.count, unchanged: unchanged.count)
        if failed.isEmpty {
            return changed.isEmpty
                ? .information(title: title, isBatchSummary: true, accessibilityIdentifier: accessibilityIdentifier)
                : .success(title: title, isBatchSummary: true, accessibilityIdentifier: accessibilityIdentifier)
        }
        let reasons = ClashDisplayText.verbatim(failed.map { "\($0.name): \($0.reason)" }.joined(separator: "\n"))
        if changed.isEmpty && unchanged.isEmpty {
            return .error(title: title, message: reasons, action: .retry, isBatchSummary: true,
                          accessibilityIdentifier: accessibilityIdentifier)
        }
        return .warning(title: title, message: reasons, action: .retry, isBatchSummary: true,
                        accessibilityIdentifier: accessibilityIdentifier)
    }

    func sentence(locale: Locale) -> String {
        if changed.count + unchanged.count + failed.count == 1 {
            if let name = changed.first { return ClashCopy.format("%@ updated", locale: locale, name) }
            if let name = unchanged.first { return ClashCopy.format("%@ is up to date", locale: locale, name) }
            if let failure = failed.first {
                return ClashCopy.format("%@ could not be updated: %@", locale: locale, failure.name, failure.reason)
            }
        }
        if changed.isEmpty && failed.isEmpty { return ClashCopy.string("All scripts are up to date.", locale: locale) }
        var parts: [String] = []
        if !changed.isEmpty { parts.append(ClashCopy.format("%lld scripts updated.", locale: locale, changed.count)) }
        if !unchanged.isEmpty { parts.append(ClashCopy.format("%lld already up to date.", locale: locale, unchanged.count)) }
        if !failed.isEmpty {
             
            let lines = failed.map { ClashCopy.format("%@ (%@)", locale: locale, $0.name, $0.reason) }
            parts.append(ClashCopy.format("Failed: %@", locale: locale, "\n" + lines.joined(separator: "\n")))
        }
         
        return parts.joined(separator: "\n")
    }
}

 
 
 
 
 
 
 
 
 
 
private struct ScriptEditorTitle: ViewModifier {
    let label: String
    func body(content: Content) -> some View {
#if os(iOS)
        content
            .clashPageTitle(.verbatim(label), watchAs: "Script")
            .navigationBarTitleDisplayMode(.inline)
#else
        content.clashPageTitle(.verbatim(label), watchAs: "Script")
#endif
    }
}

 
 
struct ScriptEditorDraft: Codable, Equatable {
    var label: String
    var body: String
    var sourceURL: String?
     
     
     
     
     
    var baseLabel: String? = nil

     
    init(label: String, body: String, sourceURL: String?, baseLabel: String? = nil) {
        self.label = label
        self.body = body
        self.sourceURL = sourceURL
        self.baseLabel = baseLabel
    }

    init(script: ConfigScript) {
        self.init(label: script.label, body: script.body, sourceURL: script.sourceURL, baseLabel: script.label)
    }

     
     
    func reconciled(with script: ConfigScript) -> ScriptEditorDraft {
        var draft = self
        if let baseLabel, label == baseLabel { draft.label = script.label }
        draft.baseLabel = script.label
        return draft
    }

     
     
     
     
     
     
    static func slot(for script: ConfigScript, store: (any ClashUnsavedDraftStore)?) -> ClashDraftSlot<ScriptEditorDraft> {
        ClashDraftSlot(key: "Script|\(script.id)", original: ScriptEditorDraft(script: script), store: store,
                       basis: ScriptEditorDraft(label: "", body: script.body, sourceURL: script.sourceURL))
    }

    static func restoring(_ opened: (value: ScriptEditorDraft, needsNotice: Bool), over script: ConfigScript)
        -> (value: ScriptEditorDraft, needsNotice: Bool) {
        let value = opened.value.reconciled(with: script)
        return (value, opened.needsNotice && value != ScriptEditorDraft(script: script))
    }
}

struct ScriptEditorView: View {
    let script: ConfigScript
    let save: (ConfigScript) -> Void
     
     
     
    let check: ((ConfigScript) async -> ScriptSaveCheck.Verdict)?
     
     
     
    let rename: ((String) throws -> Void)?

     
     
     
     
     
     
    @StateObject private var dismiss = ClashDismissHandle()
     
     
    @State private var presence = ScriptEditorPresence()
    @Environment(\.clashInsideProductModalPresentation)
    private var insideProductModal
    @State private var label: String
    @State private var bodyText: String
    @State private var result = ""
     
     
     
     
     
     
     
     
     
     
    @State private var activeProfileName: String?
     
     
    @State private var activeProfileNameLoad: Task<String, Never>?
    @State private var diagnostic: CodeEditorDiagnostic?
    @State private var asksAboutUnsaved = false

    @State private var importAddress = ""
    @State private var showsFileImporter = false
    @State private var importing = false
     
     
     
     
    @State private var importResult = ""
     
     
     
    @State private var saveResult = ""
    @State private var typing = false
    @State private var findPresented = false
    @State private var showsLineNumbers = CodeEditorLineNumbers.isOn
    @State private var softWrap = CodeEditorSoftWrap.isOn
    @State private var renaming = false
    @State private var renameDraft = ""
     
    @State private var savedLabel: String
    @State private var importingFromLink = false
     
     
    @State private var sourceURL: String?
    @State private var showsTestResult = false
    @State private var showsSaveResult = false
    @State private var showsImportError = false
     
     
     
    @State private var refusal: ScriptSaveRefusal?
    @State private var checking = false
    @Environment(\.clashFeedback) private var feedback
    private let originalBody: String
     
     
    @State private var draftSlot: ClashDraftSlot<ScriptEditorDraft>
     
    @State private var showsRestoredDraft: Bool

     
     
    let showsImportInMenu: Bool

    init(script: ConfigScript, showsImportInMenu: Bool = false,
         check: ((ConfigScript) async -> ScriptSaveCheck.Verdict)? = nil,
         rename: ((String) throws -> Void)? = nil, save: @escaping (ConfigScript) -> Void) {
        self.script = script
        self.showsImportInMenu = showsImportInMenu
        self.check = check
        self.save = save
        self.rename = rename
        _savedLabel = State(initialValue: script.label)
        originalBody = script.body
        let slot = ScriptEditorDraft.slot(for: script, store: SourceEditDrafts.shared)
        _draftSlot = State(initialValue: slot)
        let opening = ScriptEditorDraft.restoring(slot.opening(), over: script)
        _label = State(initialValue: opening.value.label)
        _bodyText = State(initialValue: opening.value.body)
        _sourceURL = State(initialValue: opening.value.sourceURL)
        _showsRestoredDraft = State(initialValue: opening.needsNotice)
    }

     
     
     
     
     
    var body: some View {
        ClashFeatureNavigationContainer {
            editor
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ClashTheme.canvas.ignoresSafeArea())
                .modifier(ClashBarFadesWhileTyping(typing: $typing))
                .modifier(ScriptEditorTitle(label: label))
                .fileImporter(
                    isPresented: $showsFileImporter,
                    allowedContentTypes: [.javaScript, .plainText, .text],
                    allowsMultipleSelection: false
                ) { outcome in
                    importFromFile(outcome)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if !insideProductModal {
                            Button("Cancel") {
                                if holdsUnsavedEdit { asksAboutUnsaved = true } else { draftSlot.clear(); dismissPresentation() }
                            }
                            .accessibilityIdentifier("scripts.editor.cancel")
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
                            .accessibilityIdentifier("scripts.editor.more")
                            Button("Save") {
                                persist()
                            }
                            .disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || checking)
                            .accessibilityIdentifier("scripts.editor.save")
                        }
                    }
                }
                .clashProductModalRoot(title: "Script")
                .task { await loadActiveProfileName() }
                .safeAreaInset(edge: .top, spacing: 0) {
                    if showsRestoredDraft { restoredNotice }
                }
                .onChange(of: currentDraft) { draftSlot.record($0) }
                .clashMacProductModalBar {
                    if insideProductModal {
                        ClashModalActionBar(
                            primaryTitle: "Save",
                            primaryDisabled: label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || checking,
                            onPrimary: { persist() }
                        )
                    }
                }
                 
                 
                .clashTextFieldAlert("Rename…", isPresented: $renaming, text: $renameDraft,
                                     field: ClashTextFieldAlertField(placeholder: "Script name",
                                                                     identifier: "scripts.editor.name")) { _ in commitRename() }
                .alert("Test Run", isPresented: $showsTestResult) {
                    Button("OK") {}
                } message: {
                    Text(verbatim: result)
                }
                .alert("Cannot Save", isPresented: $showsSaveResult) {
                    Button("OK") {}
                } message: {
                    Text(verbatim: saveResult)
                }
                .scriptSaveRefusalAlert($refusal)
                 
                 
                .onAppear { presence.isOpen = true }
                .onDisappear {
                    presence.isOpen = false
                    feedback?.dismiss(operation: "script.editor.update")
                }
                .alert("Import Failed", isPresented: $showsImportError) {
                    Button("OK") {}
                } message: {
                    Text(verbatim: importResult)
                }
                 
                 
                 
                 
                 
                 
                 
                .clashTextFieldAlert("Import from URL…", isPresented: $importingFromLink, text: $importAddress,
                                     field: ClashTextFieldAlertField(placeholder: "Script URL",
                                                                     identifier: "scripts.editor.import.address", kind: .url),
                                     confirm: "Import", confirmIdentifier: "scripts.editor.import.url") { _ in
                    Task { @MainActor in
                        await importFromAddress()
                        if !importResult.isEmpty { showsImportError = true }
                    }
                }
        }
        .clashStackNavigationViewStyle()
        .clashRegistersDeparture(
            isDirty: holdsUnsavedEdit,
             
             
             
            saveAnswering: { answer in
                persist(fromTheClosingQuestion: true, then: { answer($0 ? .saved : .refused(nil)) })
            },
            discard: { discardDraft() }
        )
        .alert("Save your changes?", isPresented: $asksAboutUnsaved) {
            Button("Save") {
                persist()
            }
            Button("Discard", role: .destructive) {
                draftSlot.clear()
                dismissPresentation()
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("This script has changes that have not been saved.")
        }
        .accessibilityIdentifier("scripts.editor.screen")
        .clashCapturesDismiss(dismiss)
    }

    private var currentDraft: ScriptEditorDraft {
        ScriptEditorDraft(label: label, body: bodyText, sourceURL: sourceURL, baseLabel: savedLabel)
    }

    private var restoredNotice: some View {
        HStack(spacing: ClashTheme.Spacing.compact) {
            ClashStatusMessage(text: .copy("Unsaved edits from last time were restored."), kind: .information)
                .accessibilityIdentifier("scripts.editor.restored")
            Spacer(minLength: 0)
            Button("Discard", role: .destructive) { discardDraft() }
                .font(.subheadline)
                .accessibilityIdentifier("scripts.editor.restored.discard")
        }
        .padding(.horizontal, ClashTheme.Spacing.standard)
        .padding(.vertical, ClashTheme.Spacing.compact)
    }

     
    private func discardDraft() {
        label = savedLabel
        bodyText = originalBody
        sourceURL = script.sourceURL
        draftSlot.clear()
        showsRestoredDraft = false
    }

    private var editor: some View {
        CodeEditorPanel(
            text: $bodyText,
            language: .javascript,
            minHeight: 200,
            diagnostic: diagnostic,
            expandsVertically: true,
            chrome: .minimal,
            showsLineNumbers: showsLineNumbers,
            softWrap: softWrap,
            findPresented: $findPresented,
            typing: $typing
        )
        .padding(.horizontal, ClashTheme.Spacing.standard)
        .padding(.vertical, ClashTheme.Spacing.compact)
    }

    @ViewBuilder
    private var moreMenu: some View {
        Button {
            renameDraft = label
            renaming = true
        } label: {
            Label("Rename…", systemImage: ClashSymbol.pencil.name)
        }
        .accessibilityIdentifier("scripts.editor.rename")
        Button {
            findPresented = true
        } label: {
            Label("Find", systemImage: ClashSymbol.magnifyingglass.name)
        }
        .keyboardShortcut("f", modifiers: .command)
        .accessibilityIdentifier("scripts.editor.find")
        Button {
            showsLineNumbers.toggle()
            CodeEditorLineNumbers.isOn = showsLineNumbers
        } label: {
            Label(
                "Line Numbers",
                systemImage: showsLineNumbers ? ClashSymbol.checkmark.name : ClashSymbol.listBullet.name
            )
        }
        .accessibilityIdentifier("scripts.editor.lineNumbers")
        Button {
            softWrap.toggle()
            CodeEditorSoftWrap.isOn = softWrap
        } label: {
            Label(
                "Wrap Long Lines",
                systemImage: softWrap ? ClashSymbol.checkmark.name : ClashSymbol.arrowRightToLine.name
            )
        }
        .accessibilityIdentifier("scripts.editor.softWrap")
        if showsImportInMenu {
            Divider()
            if let sourceURL, !sourceURL.isEmpty {
                 
                 
                Button {
                    Task { @MainActor in await updateFromSource(sourceURL) }
                } label: {
                    Label("Update", systemImage: ClashSymbol.arrowClockwise.name)
                }
                .disabled(importing)
                .accessibilityIdentifier("scripts.editor.update")
            }
            Button {
                importResult = ""
                importingFromLink = true
            } label: {
                Label("Import from URL…", systemImage: ClashSymbol.link.name)
            }
            .accessibilityIdentifier("scripts.editor.import.link")
            Button {
                showsFileImporter = true
            } label: {
                Label("Import File…", systemImage: ClashSymbol.squareAndArrowDown.name)
            }
            .accessibilityIdentifier("scripts.editor.import.file")
        }
        Divider()
        Button {
            Task { await test() }
        } label: {
            Label("Test Run", systemImage: ClashSymbol.play.name)
        }
        .accessibilityIdentifier("scripts.editor.test")
    }

     
     
     
     
     
     
     
     
     
     
     
    @discardableResult
    private func loadActiveProfileName() async -> String {
        if let activeProfileName { return activeProfileName }
        if let inFlight = activeProfileNameLoad { return await inFlight.value }
        let load = Task.detached(priority: .utility) {
            ScriptLibrary.activeProfileName()
        }
        activeProfileNameLoad = load
        let name = await load.value
        activeProfileName = name
        activeProfileNameLoad = nil
        return name
    }

    @discardableResult
    private func validate(name: String) -> Bool {
        do {
            let json = try ConfigTransforms.yamlToJSON(ScriptLibrary.testConfigYAML)
             
             
             
             
             
             
             
            let output = try ScriptEngine.run(
                script: bodyText,
                configJSON: json,
                profileName: name,
                caller: .surfaced, name: "Test Run"
            )
            _ = try ConfigTransforms.jsonToYAML(output)
            result = "OK — script returned a valid config object."
            diagnostic = nil
            return true
        } catch {
            diagnostic = CodeEditorDiagnostic.parsed(from: error.localizedDescription, in: bodyText)
            result = "Error: \(error.localizedDescription)"
            return false
        }
    }

     
     
     
     
     
     
     
     
    @MainActor
    private func updateFromSource(_ address: String) async {
        let before = bodyText
        importResult = ""
        importAddress = address
        await importFromAddress()
        guard presence.isOpen else { return }
        let name = label
        let operation = "script.editor.update"
        if !importResult.isEmpty {
            feedback?.show(.error(title: ClashFeedbackCopy.couldNotUpdate(name), message: .verbatim(importResult),
                                  action: .retry, accessibilityIdentifier: "feedback.script.editor.update"),
                           operation: operation,
                           perform: { Task { @MainActor in await updateFromSource(address) } })
        } else if bodyText == before {
            feedback?.show(.information(title: ClashFeedbackCopy.upToDate(name),
                                        accessibilityIdentifier: "feedback.script.editor.update"), operation: operation)
        } else {
            feedback?.show(.success(title: ClashFeedbackCopy.updated(name), message: .copy("Save to keep it."),
                                    accessibilityIdentifier: "feedback.script.editor.update"), operation: operation)
        }
    }

    @MainActor
    private func importFromAddress() async {
        importing = true
        importResult = ""
        defer { importing = false }
        do {
            let text = try await ScriptImport.body(at: importAddress)
            bodyText = text
            sourceURL = importAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            result = ""
            diagnostic = nil
            if label == ScriptLibrary.defaultLabel || label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let url = try? ScriptImport.address(importAddress),
               let suggested = ScriptImport.suggestedName(for: url) {
                label = suggested
            }
        } catch {
            importResult = (error as NSError).localizedDescription
        }
    }

    private func importFromFile(_ outcome: Result<[URL], Error>) {
        switch outcome {
        case let .success(urls):
            guard let url = urls.first else { return }
             
             
             
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            importResult = ""
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    importResult = ScriptImportError.empty.localizedDescription
                    return
                }
                bodyText = text
                result = ""
                diagnostic = nil
            } catch {
                importResult = ScriptImportError.notText.localizedDescription
            }
        case let .failure(error):
            importResult = (error as NSError).localizedDescription
        }
        showsImportError = !importResult.isEmpty
    }

    private func test() async {
        _ = validate(name: await loadActiveProfileName())
        showsTestResult = !result.isEmpty
    }

     
     
    private var holdsUnsavedEdit: Bool {
        UnsavedEditPolicy.decision(original: originalBody, current: bodyText) == .offerToSave
            || label != savedLabel
    }

     
     
     
    private func commitRename() {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let rename else { label = trimmed; return }
        do {
            try rename(trimmed)
        } catch {
            saveResult = error.localizedDescription
            showsSaveResult = true
            return
        }
        label = trimmed
        savedLabel = trimmed
         
         
        draftSlot.clear()
        var renamed = script
        renamed.label = trimmed
        renamed.body = originalBody
        draftSlot = ScriptEditorDraft.slot(for: renamed, store: SourceEditDrafts.shared)
        draftSlot.record(currentDraft)
    }

    private func persist(fromTheClosingQuestion: Bool = false, then: ((Bool) -> Void)? = nil) {
         
        let source: ScriptEditorSource = importAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .write : .url
        switch ScriptEditorSaveIntent.decide(source: source, address: importAddress) {
        case .importThenSave:
             
             
             
             
             
             
             
            Task { @MainActor in
                await importFromAddress()
                 
                 
                 
                 
                 
                guard importResult.isEmpty else {
                    if fromTheClosingQuestion { showsImportError = true }
                    then?(false)
                    return
                }
                checkThenCommit(then)
            }
        case .save:
            checkThenCommit(then)
        }
    }

     
     
     
     
    private func checkThenCommit(_ then: ((Bool) -> Void)?) {
        guard let check,
              let edited = ScriptLibrary.editedScript(
                  id: script.id, label: label, body: bodyText, sourceURL: sourceURL,
                  existing: ScriptLibrary.load()
              )
        else {
             
             
            return finish(commit(), then)
        }
        checking = true
        let asked = (label: label, body: bodyText, sourceURL: sourceURL)
        Task { @MainActor in
            let verdict = await check(edited)
            checking = false
             
             
            guard presence.isOpen else { return }
             
             
             
            guard asked.label == label, asked.body == bodyText, asked.sourceURL == sourceURL else {
                return checkThenCommit(then)
            }
            switch verdict {
            case .accepted:
                finish(commit(), then)
            case .refused(let reason), .scriptFailed(let reason):
                refusal = ScriptSaveRefusal(
                    reason: reason,
                    saveAnyway: { finish(commit(), then) },
                    keepEditing: { then?(false) }
                )
            }
        }
    }

     
    @discardableResult
    private func commit() -> Bool {
        guard let edited = ScriptLibrary.editedScript(
            id: script.id,
            label: label,
            body: bodyText,
            sourceURL: sourceURL,
            existing: ScriptLibrary.load()
        ) else {
            saveResult = "Another script already uses that name."
            showsSaveResult = true
            return false
        }
        saveResult = ""
        save(edited)
         
         
        draftSlot.commit()
        return true
    }

     
     
     
     
    private func finish(_ saved: Bool, _ then: ((Bool) -> Void)?) {
        if let then { then(saved) } else if saved { dismissPresentation() }
    }

    private func dismissPresentation() {
        dismiss.closeModalOrDismiss()
    }
}

 
 
 
enum ScriptAddOutcome {
     
     
    @discardableResult
    static func save(label: String, body: String, sourceURL: String? = nil,
                     in library: UserDefaults) throws -> ConfigScript {
        let script = try candidate(label: label, body: body, sourceURL: sourceURL, in: library)
        ScriptLibrary.upsert(script, in: library)
        return script
    }

     
     
    static func candidate(label: String, body: String, sourceURL: String? = nil,
                          in library: UserDefaults) throws -> ConfigScript {
        let existing = ScriptLibrary.load(from: library)
        let id = UUID().uuidString
        var candidate = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.isEmpty { candidate = ScriptLibrary.defaultLabel }
        var attempt = 2
        var script = ScriptLibrary.editedScript(id: id, label: candidate, body: body, sourceURL: sourceURL, existing: existing)
        while script == nil, attempt < 100 {
            script = ScriptLibrary.editedScript(id: id, label: "\(candidate) \(attempt)", body: body, sourceURL: sourceURL, existing: existing)
            attempt += 1
        }
        guard let script else { throw ScriptImportError.empty }
        return script
    }

     
     
     
     
    static func fromFile(_ outcome: Result<[URL], Error>, in library: UserDefaults) throws -> ScriptManualDraft {
        switch outcome {
        case let .success(urls):
            guard let url = urls.first else { throw ScriptImportError.empty }
             
             
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { throw ScriptImportError.notText }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ScriptImportError.empty }
            let named = try candidate(label: url.deletingPathExtension().lastPathComponent, body: text, in: library)
            return ScriptManualDraft(name: named.label, body: text)
        case let .failure(error):
            throw error
        }
    }

    static func fromLink(_ address: String, in library: UserDefaults) async throws -> ConfigScript {
        let text = try await ScriptImport.body(at: address)
        let label = (try? ScriptImport.address(address)).flatMap(ScriptImport.suggestedName(for:))
            ?? ScriptLibrary.defaultLabel
        return try save(label: label, body: text,
                        sourceURL: address.trimmingCharacters(in: .whitespacesAndNewlines), in: library)
    }
}

 
 
 
 
 
struct ScriptManualDraft: Codable, Equatable {
    var name: String
    var body: String
}

struct ScriptManualPage: View {
    let library: UserDefaults
     
     
     
     
     
    let check: ((ConfigScript) async -> ScriptSaveCheck.Verdict?)?
    let close: () -> Void
    let added: (ConfigScript) -> Void

    @Environment(\.clashInsideProductModalPresentation) private var insideProductModal
    @State private var name: String
    @State private var bodyText: String
    @State private var failure = ""
    @State private var showsFailure = false
     
    @State private var draftSlot: ClashDraftSlot<ScriptManualDraft>
    @State private var showsRestoredDraft: Bool
     
    @State private var refusal: ScriptSaveRefusal?
    @State private var checking = false
     
     
    @State private var presence = ScriptEditorPresence()
     
     
    private let usesDraftSlot: Bool
#if os(iOS)
     
    @State private var asksBeforeLeaving = false
#endif

     
     
    init(library: UserDefaults, opening: ScriptManualDraft? = nil,
         check: ((ConfigScript) async -> ScriptSaveCheck.Verdict?)? = nil,
         close: @escaping () -> Void, added: @escaping (ConfigScript) -> Void) {
        self.library = library
        self.check = check
        self.close = close
        self.added = added
        self.usesDraftSlot = opening == nil
        let slot = Self.draftSlot(template: ScriptLibrary.fresh().body, store: SourceEditDrafts.shared)
        _draftSlot = State(initialValue: slot)
        if let opening {
             
             
            _name = State(initialValue: opening.name)
            _bodyText = State(initialValue: opening.body)
            _showsRestoredDraft = State(initialValue: false)
        } else {
            let restored = slot.opening()
            _name = State(initialValue: restored.value.name)
            _bodyText = State(initialValue: restored.value.body)
            _showsRestoredDraft = State(initialValue: restored.needsNotice)
        }
    }

    private var currentDraft: ScriptManualDraft { ScriptManualDraft(name: name, body: bodyText) }

     
     
     
     
    static func draftSlot(template: String, store: (any ClashUnsavedDraftStore)?) -> ClashDraftSlot<ScriptManualDraft> {
        ClashDraftSlot(key: "Script|manual", original: ScriptManualDraft(name: "", body: template), store: store,
                       sameBasis: { _, _ in true })
    }

    private func discardDraft() {
        name = draftSlot.original.name
        bodyText = draftSlot.original.body
        if usesDraftSlot { draftSlot.clear() }
        showsRestoredDraft = false
    }

     
    private func leave() {
        presence.isOpen = false
        if usesDraftSlot { draftSlot.clear() }
        close()
    }
#if os(iOS)

     
     
     
    private var holdsAnEntry: Bool {
        UnsavedEditPolicy.decision(original: draftSlot.original.name, current: name) == .offerToSave
            || UnsavedEditPolicy.decision(original: draftSlot.original.body, current: bodyText) == .offerToSave
    }

     
     
    private func leaveOrAsk() {
        if holdsAnEntry {
            asksBeforeLeaving = true
        } else {
            leave()
        }
    }
#endif

    var body: some View {
        ClashFeatureNavigationContainer {
            Form {
                if showsRestoredDraft {
                    Section {
                        HStack(spacing: ClashTheme.Spacing.compact) {
                            ClashStatusMessage(text: .copy("Unsaved edits from last time were restored."), kind: .information)
                                .accessibilityIdentifier("scripts.add.restored")
                            Spacer(minLength: 0)
                            Button("Discard", role: .destructive) { discardDraft() }
                                .buttonStyle(.borderless)
                                .font(.subheadline)
                                .accessibilityIdentifier("scripts.add.restored.discard")
                        }
                    }
                }
                Section {
                    TextField("Script name", text: $name)
                        .accessibilityIdentifier("scripts.add.name")
                }
                Section {
                    CodeEditorPanel(text: $bodyText, language: .javascript, minHeight: 240, diagnostic: nil)
                }
            }
            .clashPageTitle("Add Script")
            .clashToolbarUnlessInPanel {
                ToolbarItem(placement: .cancellationAction) {
#if os(iOS)
                    Button("Cancel") { leaveOrAsk() }
                        .accessibilityIdentifier("scripts.add.cancel")
#else
                    Button("Cancel") { leave() }
                        .accessibilityIdentifier("scripts.add.cancel")
#endif
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || checking)
                    .accessibilityIdentifier("scripts.add.save")
                }
            }
        }
         
         
        .clashMacProductModalBar {
            if insideProductModal {
                ClashModalActionBar(
                    primaryTitle: "Save",
                    primaryDisabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || checking,
                    onPrimary: { save() }
                )
            }
        }
        .alert("Import Failed", isPresented: $showsFailure) {
            Button("OK") {}
        } message: {
            Text(verbatim: failure)
        }
         
        .scriptSaveRefusalAlert($refusal)
        .onChange(of: currentDraft) { if usesDraftSlot { draftSlot.record($0) } }
        .onAppear { presence.isOpen = true }
        .onDisappear { presence.isOpen = false }
#if os(iOS)
         
         
         
         
        .clashUnsavedChangesAlert(isPresented: $asksBeforeLeaving,
                                  message: .copy("This script has changes that have not been saved."),
                                  isBusy: false, saveDisabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                  save: { save() }, discard: { leave() })
        .interactiveDismissDisabled(holdsAnEntry)
         
         
        .background(ProxyNodeEditorPullDownAttempts { if holdsAnEntry { asksBeforeLeaving = true } })
#endif
    }

     
     
    private func save() {
        guard !checking else { return }
        let script: ConfigScript
        do { script = try ScriptAddOutcome.candidate(label: name, body: bodyText, in: library) }
        catch { failure = (error as NSError).localizedDescription; showsFailure = true; return }
        guard let check else { return keep(script) }
        checking = true
        Task { @MainActor in
            let verdict = await check(script)
            checking = false
            guard presence.isOpen else { return }
            switch verdict {
            case nil, .accepted?:
                keep(script)
            case .refused(let reason)?:
                refusal = ScriptSaveRefusal(reason: reason, saveAnyway: { keep(script) }, keepEditing: {})
            case .scriptFailed(let reason)?:
                refusal = ScriptSaveRefusal(reason: reason, saveAnyway: nil, keepEditing: {})
            }
        }
    }

    private func keep(_ script: ConfigScript) {
        ScriptLibrary.upsert(script, in: library)
        if usesDraftSlot { draftSlot.commit() }
        added(script)
    }
}

 
@MainActor
final class ScriptEditorPresence {
    var isOpen = true
}
