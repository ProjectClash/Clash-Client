import Foundation

 
 
 
 
 
 
 
public extension ConfigurationLibraryStore {
     
     
     
     
     
     
     
    func schemeIDs(usingLocalRuleSet id: String, in snapshot: ConfigurationLibrarySnapshot) throws -> [String] {
        let key = "local-" + id
        return try snapshot.availableRules.filter { scheme in
            guard scheme.kind == .custom || scheme.kind == .imported, scheme.collectionKey == nil,
                  scheme.rulesFromSchemeID == nil else { return false }
            return try ConfigurationRuleDraft(scheme: scheme, payload: ruleSchemePayload(scheme.id)).containsRuleSet(key)
        }.map(\.id)
    }
}

public extension ConfigurationLibrarySnapshot {
     
     
     
     
    func recipes(runningAnyOf schemeIDs: [String]) -> [ConfigurationRecipe] {
        let running = Set(schemeIDs.flatMap { recipes(runningScheme: $0).map(\.id) })
        var seen = Set<String>()
        return recipes.filter { running.contains($0.id) && seen.insert($0.id).inserted }
    }

     
     
     
     
     
    func recipes(readingRulesOf sourceID: String) -> [ConfigurationRecipe] {
        var seen = Set<String>()
        return recipes.filter { recipe in
            (recipe.ruleSource.id == sourceID
                || (recipe.settingsRuleDependencies ?? [:]).values.contains { $0.id == sourceID })
                && seen.insert(recipe.id).inserted
        }
    }
}
