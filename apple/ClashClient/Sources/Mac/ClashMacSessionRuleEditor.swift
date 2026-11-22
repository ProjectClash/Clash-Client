import ClashClientKit
import ClashClientUI
import ClashMacClient
import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
enum ClashMacSessionRuleEditor {
     
    struct Refusal: LocalizedError, Equatable {
        let message: String
        var errorDescription: String? { message }
    }

    static func actions(_ base: ClashMacRuleEditorActions, session: ConfigurationSchemeDraftSession) -> ClashMacRuleEditorActions {
        var editor = base
        editor.load = { try await state(session) }
        editor.save = { draft in try await save(draft, session: session) }
        editor.saveLocal = { set in try await writeLocal(set, deleting: nil, session: session) }
        editor.deleteLocal = { id in try await writeLocal(nil, deleting: id, session: session) }
        editor.deleteLocalRestorably = { id in try await deleteLocal(id, session: session) }
        editor.changeNote = { session.note(locale: session.locale) }
        return editor
    }

     
     
     
     
     
     
     
     
    static func deleteLocal(_ id: String, session: ConfigurationSchemeDraftSession) async throws -> ClashMacLocalRuleSetDeletion {
        await session.waitForSaves()
        guard let known = session.library, let store = session.model.configurationLibraryStore else { throw refusal(session) }
        let deletion: (snapshot: ConfigurationLibrarySnapshot, removal: ConfigurationLibraryRemoval)
        do {
            deletion = try await session.model.deleteConfigurationLocalRuleSetRestorably(id, generation: known.generation)
        } catch ConfigurationLibraryError.staleGeneration {
            let now = try await Task.detached(priority: .userInitiated) { try store.snapshot() }.value
            guard now.generation != known.generation, now.localRuleSets == known.localRuleSets else {
                throw ConfigurationLibraryError.staleGeneration
            }
            deletion = try await session.model.deleteConfigurationLocalRuleSetRestorably(id, generation: now.generation)
        }
        await told(session, deletion.snapshot)
        let committed = deletion.snapshot.generation, removal = deletion.removal
        return try await ClashMacLocalRuleSetDeletion.done(reading: { try await state(session) }) {
            do {
                await told(session, try await session.model.restoreConfigurationLibraryRemoval(removal, expectedGeneration: committed))
                return true
            } catch {
                return false
            }
        }
    }

     
     
    private static func told(_ session: ConfigurationSchemeDraftSession, _ written: ConfigurationLibrarySnapshot) async {
        await session.adopt(written)
        session.libraryChanged?(written)
    }

     
     
     
     
     
    static func state(_ session: ConfigurationSchemeDraftSession) async throws -> ClashMacRuleEditorState {
        if session.draft == nil {
            await session.load()
        } else if let store = session.model.configurationLibraryStore,
                  let now = try? await Task.detached(priority: .userInitiated, operation: { try store.snapshot() }).value {
            guard ConfigurationRulesEditSnapshot.running(session.profileID, in: now) != nil else {
                throw ConfigurationLibraryError.unreadable
            }
            await session.adopt(now)
        }
        guard let draft = session.draft else { throw refusal(session) }
        return ClashMacRuleEditorState(draft: draft, localSets: session.library?.localRuleSets ?? [],
                                       resetDocument: session.resetDocument ?? draft.originalDocument.serialized())
    }

     
     
     
     
     
     
    static func save(_ draft: ConfigurationRuleDraft, session: ConfigurationSchemeDraftSession) async throws -> ConfigurationRuleDraft {
        if let held = session.draft, held.schemeID != draft.schemeID || held.version != draft.version {
            throw ConfigurationLibraryError.staleGeneration
        }
        await session.change { current in current = draft.continuing(after: current) }
        await session.waitForSaves()
        if session.failure != nil { throw refusal(session) }
        guard let saved = session.draft else { throw refusal(session) }
        return saved
    }

     
     
    static func writeLocal(_ value: ConfigurationLocalRuleSet?, deleting id: String?,
                           session: ConfigurationSchemeDraftSession) async throws -> ClashMacRuleEditorState {
        guard await session.saveLocalRuleSet(value, deleting: id) else { throw refusal(session) }
        return try await state(session)
    }

    private static func refusal(_ session: ConfigurationSchemeDraftSession) -> Refusal {
        Refusal(message: session.failure ?? ClashErrorCopy.message(ConfigurationLibraryError.unreadable, locale: session.locale))
    }
}
