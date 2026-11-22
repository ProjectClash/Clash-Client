import ClashClientKit
import ClashClientUI
import ClashMacClient
import Foundation

 
 
 
 
 
 
 
 
 
 
struct ClashMacOverrideLibrary {
    var library: UserDefaults = ScriptLibrary.appGroupDefaults
    var profiles: ProfileStore? = ScriptLibrary.defaultProfileStore
     
     
    var activeProfileName: @Sendable () -> String = { ScriptLibrary.activeProfileName() }

     
     
     
     
    static func chosenScript(of configuration: Profile) -> String? {
        configuration.overwriteMode == .script ? configuration.selectedScriptID : nil
    }

     
    static func rows(scripts: [ConfigScript], configurations: [Profile]) -> [ClashMacOverrideLibraryRow] {
         
         
        let running = configurations.filter { chosenScript(of: $0) != nil }
        return scripts.map { script in
            ClashMacOverrideLibraryRow(
                id: script.id,
                name: script.label,
                usage: ClashLibraryUsageCopy.text(ScriptLibrary.usage(ofScript: script.id, profiles: running)),
                isLinked: isLinked(script)
            )
        }
    }

     
     
     
    static func entries(scripts: [ConfigScript], configurations: [Profile]) -> [ClashMacScriptEntry] {
         
         
        let running = configurations.filter { chosenScript(of: $0) != nil }
        return scripts.map {
            ClashMacScriptEntry(id: $0.id, label: $0.label, canRefresh: isLinked($0),
                                sourceHost: $0.sourceURL.flatMap { URL(string: $0)?.host },
                                usage: ClashLibraryUsageCopy.text(ScriptLibrary.usage(ofScript: $0.id, profiles: running)))
        }
    }

    func rows() -> [ClashMacOverrideLibraryRow] {
        Self.rows(scripts: ScriptLibrary.load(from: library), configurations: profiles?.load() ?? [])
    }

     
     
    static func isLinked(_ script: ConfigScript) -> Bool {
        ClashMacOverrideScriptDetail.isLinked(script.sourceURL)
    }

     
     
     
     
     
    static func offersUpdateAll(_ scripts: [ConfigScript]) -> Bool {
        !scripts.isEmpty
    }

     

     
     
    func detail(_ id: String) -> ClashMacOverrideScriptDetail? {
        guard let script = ScriptLibrary.load(from: library).first(where: { $0.id == id }) else { return nil }
        let users = (profiles?.load() ?? []).filter { Self.chosenScript(of: $0) == id }
        return ClashMacOverrideScriptDetail(
            id: script.id,
            name: script.label,
            link: script.sourceURL,
            usedBy: users.map { LibraryUsage.Configuration(id: $0.id, name: $0.label) },
            deletionNote: ScriptLibraryCopy.deletionNote(usedBy: users.map(\.label))
        )
    }

     
     
    func rename(_ id: String, to name: String) throws {
        try ScriptLibrary.rename(id: id, to: name, in: library)
    }

     
     
     
     
     
     
     
    func testRun(_ id: String) async -> ClashMacScriptTestRun {
        let library = library, activeProfileName = activeProfileName
        return await Task.detached(priority: .userInitiated) {
            do {
                _ = try ScriptLibrary.apply(id: id, to: ScriptLibrary.testConfigYAML, scripts: ScriptLibrary.load(from: library),
                                            profileName: activeProfileName(), caller: .surfaced)
                return .passed
            } catch {
                return .failed(ClashErrorCopy.message(error, locale: Locale.current))
            }
        }.value
    }

     

     
    @discardableResult
    func addManual(name: String, body: String) throws -> ConfigScript {
        let script = try Self.named(label: name, body: body, link: nil, existing: ScriptLibrary.load(from: library))
        ScriptLibrary.upsert(script, in: library)
        return script
    }

     
    @discardableResult
    func addLink(_ link: String, using downloader: HTTPFetching = ResourceDownloader()) async throws -> ConfigScript {
        let body = try await ScriptImport.body(at: link, using: downloader)
        let label = (try? ScriptImport.address(link)).flatMap(ScriptImport.suggestedName(for:)) ?? ScriptLibrary.defaultLabel
        let script = try Self.named(label: label, body: body, link: link, existing: ScriptLibrary.load(from: library))
        ScriptLibrary.upsert(script, in: library)
        return script
    }

     
     
     
    static func named(label: String, body: String, link: String?, existing: [ConfigScript]) throws -> ConfigScript {
        let id = UUID().uuidString
        var candidate = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.isEmpty { candidate = ScriptLibrary.defaultLabel }
        var attempt = 2
        var script = ScriptLibrary.editedScript(id: id, label: candidate, body: body, sourceURL: link, existing: existing)
        while script == nil, attempt < 100 {
            script = ScriptLibrary.editedScript(id: id, label: "\(candidate) \(attempt)", body: body, sourceURL: link, existing: existing)
            attempt += 1
        }
        guard let script else { throw ScriptImportError.empty }
        return script
    }

     

     
     
    struct Deletion {
        let label: String
        let operation: String
        let undo: @MainActor () -> ClashMacUndoAnswer
    }

     
     
    func delete(_ id: String) -> Deletion? {
        guard let removal = ScriptLibrary.removeRestorably(id: id, in: library, profiles: profiles) else { return nil }
        let library = library, profiles = profiles
        return Deletion(label: removal.script.label, operation: "scripts.delete.\(id)") {
            do {
                try ScriptLibrary.restore(removal, in: library, profiles: profiles)
                return .restored
            } catch {
                return .failed(ClashErrorCopy.message(error, locale: Locale.current))
            }
        }
    }
}
