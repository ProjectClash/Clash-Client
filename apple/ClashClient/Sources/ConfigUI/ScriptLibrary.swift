import Foundation
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

struct ScriptLibraryView: View {
    @State private var scripts = ScriptLibrary.load()
    @State private var deletingScripts: [ConfigScript] = []
    @State private var editing: ConfigScript?
    @State private var adding: ConfigScript?
    @State private var updating = false
    @Environment(\.clashFeedback) private var feedback
     
    private var updatable: [ConfigScript] { scripts.filter { !($0.sourceURL ?? "").isEmpty } }

    var body: some View {
        Group {
#if os(macOS)
         
         
         
         
         
         
        Form {
            if scripts.isEmpty {
                Section {
                ClashEmptyState(
                    title: "No Scripts",
                    message: "",
                    symbol: .curlybraces
                )
                .listRowSeparator(.hidden)
                }
            } else {
                Section {
            ForEach(scripts) { script in
                Button { editing = script } label: {
                    ClashDestinationRow(
                         
                        title: .verbatim(script.label),
                        subtitle: "JavaScript main(config)",
                        symbol: .curlybraces,
                        tint: .purple
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("scripts.row.\(script.id)")
            }
            .onDelete { offsets in
                removeWithUndo(offsets.compactMap { scripts.indices.contains($0) ? scripts[$0] : nil })
            }
                }
            }
            Section {
                ClashAddRow(Text(ClashCopy.key("Add Script"))) {
                    adding = ScriptLibrary.fresh()
                }
                .accessibilityIdentifier("scripts.row.add")
            }
        }
#else
        List {
            if scripts.isEmpty {
                ClashEmptyState(
                    title: "No Scripts",
                    message: "",
                    symbol: .curlybraces
                )
                .listRowSeparator(.hidden)
            }
            ForEach(scripts) { script in
                Button { editing = script } label: {
                    ClashDestinationRow(
                         
                        title: .verbatim(script.label),
                        subtitle: "JavaScript main(config)",
                        symbol: .curlybraces,
                        tint: .purple
                    )
                }
                .buttonStyle(.plain)
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
        }
        .clashInsetGroupedListStyle()
#endif
        }
        .clashPageTitle("Scripts")
        .clashDetailPageInsets()
        .accessibilityIdentifier("scripts.screen")
        .clashToolbarUnlessInPanel {
            ToolbarItemGroup(placement: .clashNavigationTrailing) {
                 
                 
                 
                 
                Button { Task { await update(updatable) } } label: {
                    Label("Update All", systemImage: ClashSymbol.arrowClockwise.name)
                }
                .disabled(updating)
                .accessibilityIdentifier("scripts.update.all")
                ClashEditButton()
                Button { adding = ScriptLibrary.fresh() } label: {
                    Label("Add Script", systemImage: ClashSymbol.plus.name)
                }
            }
        }
         
        .clashProductModal(item: $editing, role: .page, immersive: { _ in true }) { script in
            ScriptEditorView(script: script, showsImportInMenu: true, rename: { name in
                try ScriptLibrary.rename(id: script.id, to: name)
                scripts = ScriptLibrary.load()
                 
                 
                 
                if let renamed = scripts.first(where: { $0.id == script.id }) { editing?.label = renamed.label }
            }) { save($0) }
                .clashModalPresentation(.page)
        }
        .clashProductModal(item: $adding, role: .page, immersive: { _ in true }) { script in
            ScriptEditorView(script: script, showsImportInMenu: true) { save($0) }
                .clashModalPresentation(.page)
        }
    }

    private func save(_ script: ConfigScript) {
        ScriptLibrary.upsert(script)
        scripts = ScriptLibrary.load()
        editing = nil
        adding = nil
    }

     
     
     
     
     
     
    private func removeWithUndo(_ targets: [ConfigScript]) {
        guard !targets.isEmpty else { return }
        let removals = targets.compactMap { ScriptLibrary.removeRestorably(id: $0.id) }
        scripts = ScriptLibrary.load()
        let name = targets.map(\.label).joined(separator: ", ")
        let feedback = feedback
        feedback?.show(.success(title: ClashFeedbackCopy.deleted(name), action: .undo, accessibilityIdentifier: "feedback.scripts.delete"),
                       operation: "scripts.delete",
                       perform: {
             
             
            var failed: [(String, String)] = []
            for removal in removals.reversed() {
                do { try ScriptLibrary.restore(removal) }
                catch { failed.append((removal.script.label, error.localizedDescription)) }
            }
            scripts = ScriptLibrary.load()
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
                    ScriptLibrary.upsert(refreshed)
                    outcome.changed.append(script.label)
                } else {
                    outcome.unchanged.append(script.label)
                }
            } catch {
                outcome.failed.append((script.label, error.localizedDescription))
                failedIDs.insert(script.id)
            }
        }
        scripts = ScriptLibrary.load()
         
         
         
        let retry: @MainActor () -> Void = {
            Task { await update(ScriptLibrary.load().filter { failedIDs.contains($0.id) && !($0.sourceURL ?? "").isEmpty }) }
        }
        feedback?.answer(running, with: outcome.presentation(), operation: operation, perform: retry)
    }
}

 
 
 
 
 
struct ScriptUpdateSummary {
     
    static let nothingToFetch = ClashFeedbackPresentation.information(
        title: ClashFeedbackCopy.nothingToUpdate,
        message: .copy("These scripts were imported before the app kept their link, so there is nothing to fetch yet. Import each from its link once more; Update works from then on."),
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
        ScriptLibrary.upsert(script, in: library)
        return script
    }

    static func fromFile(_ outcome: Result<[URL], Error>, in library: UserDefaults) throws -> ConfigScript {
        switch outcome {
        case let .success(urls):
            guard let url = urls.first else { throw ScriptImportError.empty }
             
             
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { throw ScriptImportError.notText }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ScriptImportError.empty }
            return try save(label: url.deletingPathExtension().lastPathComponent, body: text, in: library)
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
    let close: () -> Void
    let added: (ConfigScript) -> Void

    @Environment(\.clashInsideProductModalPresentation) private var insideProductModal
    @State private var name: String
    @State private var bodyText: String
    @State private var failure = ""
    @State private var showsFailure = false
     
    @State private var draftSlot: ClashDraftSlot<ScriptManualDraft>
    @State private var showsRestoredDraft: Bool

    init(library: UserDefaults, close: @escaping () -> Void, added: @escaping (ConfigScript) -> Void) {
        self.library = library
        self.close = close
        self.added = added
        let slot = Self.draftSlot(template: ScriptLibrary.fresh().body, store: SourceEditDrafts.shared)
        _draftSlot = State(initialValue: slot)
        let opening = slot.opening()
        _name = State(initialValue: opening.value.name)
        _bodyText = State(initialValue: opening.value.body)
        _showsRestoredDraft = State(initialValue: opening.needsNotice)
    }

    private var currentDraft: ScriptManualDraft { ScriptManualDraft(name: name, body: bodyText) }

     
     
     
     
    static func draftSlot(template: String, store: (any ClashUnsavedDraftStore)?) -> ClashDraftSlot<ScriptManualDraft> {
        ClashDraftSlot(key: "Script|manual", original: ScriptManualDraft(name: "", body: template), store: store,
                       sameBasis: { _, _ in true })
    }

    private func discardDraft() {
        name = draftSlot.original.name
        bodyText = draftSlot.original.body
        draftSlot.clear()
        showsRestoredDraft = false
    }

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
                    Button("Cancel") { draftSlot.clear(); close() }
                        .accessibilityIdentifier("scripts.add.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("scripts.add.save")
                }
            }
        }
         
         
        .clashMacProductModalBar {
            if insideProductModal {
                ClashModalActionBar(
                    primaryTitle: "Save",
                    primaryDisabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    onPrimary: { save() }
                )
            }
        }
        .alert("Import Failed", isPresented: $showsFailure) {
            Button("OK") {}
        } message: {
            Text(verbatim: failure)
        }
        .onChange(of: currentDraft) { draftSlot.record($0) }
    }

    private func save() {
        do {
            let script = try ScriptAddOutcome.save(label: name, body: bodyText, in: library)
            draftSlot.commit()
            added(script)
        } catch { failure = (error as NSError).localizedDescription; showsFailure = true }
    }
}

 
@MainActor
final class ScriptEditorPresence {
    var isOpen = true
}
