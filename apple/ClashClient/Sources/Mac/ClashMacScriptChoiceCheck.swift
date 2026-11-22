import Foundation

 
 
 
 
 
 
 
 
 
 
enum ClashMacScriptChoiceCheck {
     
     
    enum Door: Equatable {
         
        case newScript
         
        case choose(fromLink: Bool)
         
        case linkAdd
    }

     
     
     
     
     
    static func door(addedFromLink: Bool) -> Door {
        addedFromLink ? .linkAdd : .choose(fromLink: false)
    }

    struct Refusal: Equatable {
         
         
         
        let message: String
         
        let canUseAnyway: Bool
         
        var offersEdit = false
         
         
         
         
        var aftermath: ScriptRefusalAftermath? = nil
         
        var overForm = false
    }

     
     
    static func choosing(_ id: String?, in profile: Profile) -> Profile {
        var updated = profile
        updated.selectedScriptID = id
        updated.overwriteMode = ProfileOverrideModePolicy.mode(stored: updated.overwriteMode ?? .standard, selectedScriptID: id)
        return updated
    }

     
     
     
     
    static func editCheck(running: [Profile], model: ProfilesViewModel)
        -> ((ConfigScript) async -> ScriptSaveCheck.Verdict)? {
        guard !running.isEmpty else { return nil }
        return { edited in
            var scripts = ScriptLibrary.load()
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

     
     
     
    static func refusal(
        door: Door = .choose(fromLink: false),
        choosing id: String?, in profile: Profile, raw: String?, scripts: [ConfigScript], locale: Locale,
        verdict: @escaping @Sendable (String, Profile, [ConfigScript]) -> ScriptSaveCheck.Verdict
            = { ScriptSaveCheck.verdict(raw: $0, profile: $1, scripts: $2) }
    ) async -> Refusal? {
        let updated = choosing(id, in: profile)
        guard ScriptSaveCheck.runsAScript(updated), let raw else { return nil }
        let answer = await Task.detached(priority: .userInitiated) { verdict(raw, updated, scripts) }.value
        switch answer {
        case .accepted:
            return nil
        case .refused(let reason):
            return refusal(reason, canUseAnyway: true, door: door, locale: locale)
        case .scriptFailed(let reason):
            return refusal(reason, canUseAnyway: false, door: door, locale: locale)
        }
    }

     
     
     
     
    private static func refusal(_ reason: ConfigurationRefusalReason, canUseAnyway: Bool, door: Door,
                                locale: Locale) -> Refusal {
        let aftermath: ScriptRefusalAftermath?
        switch door {
        case .newScript: aftermath = nil
        case .choose(let fromLink): aftermath = fromLink ? .fromLink : .handWritten
        case .linkAdd: aftermath = .addedFromLink
        }
        let message = [reason.alertMessage(locale: locale), aftermath?.line(locale: locale)]
            .compactMap { $0 }.joined(separator: "\n\n")
        return Refusal(message: message, canUseAnyway: canUseAnyway,
                       offersEdit: door == .choose(fromLink: false), aftermath: aftermath,
                       overForm: door == .newScript)
    }
}
