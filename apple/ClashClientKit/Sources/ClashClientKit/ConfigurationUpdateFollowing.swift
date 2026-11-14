import Foundation

 
 
 
 
 
 
public enum ConfigurationUpdateFollowing: String, Codable, Equatable, Sendable {
     
    case following
     
    case paused
     
     
    case ownCopy
     
     
    case customizedRules
     
     
     
     
    case copyWithoutOrigin
}

public extension ConfigurationLibrarySnapshot {
     
     
    func updateFollowing(ofRecipe id: String) -> ConfigurationUpdateFollowing? {
        guard let recipe = recipes.first(where: { $0.id == id }) else { return nil }
        if let origin = recipe.ownCopyOf {
            let previous = origin.previous
             
             
            guard previous.dependencies.allSatisfy({ isFollowable($0.id) }), canRun(schemeOf: previous) else {
                return .copyWithoutOrigin
            }
             
             
             
            let ranALink = previous.dependencies.contains { isLink($0.id) } || linkSchemeCustomized(by: previous) != nil
            return ranALink ? .ownCopy : nil
        }
         
         
         
        if sources.first(where: { $0.id == recipe.ruleSource.id })?.privateToConfigurationID == id,
           rules.first(where: { $0.id == recipe.ruleSchemeID })?.ownViewBaseID == nil {
            return .copyWithoutOrigin
        }
        if linkSchemeCustomized(by: recipe) != nil { return .customizedRules }
        guard recipe.dependencies.contains(where: { isLink($0.id) }) else { return nil }
        return recipe.followsUpdates ? .following : .paused
    }

     
     
    func sourcesToRejoin(ofRecipe id: String) -> [ConfigurationSourceRecord]? {
        guard updateFollowing(ofRecipe: id) == .ownCopy,
              let previous = recipes.first(where: { $0.id == id })?.ownCopyOf?.previous else { return nil }
        var seen = Set<String>()
        return previous.dependencies.compactMap { reference in
            guard seen.insert(reference.id).inserted else { return nil }
            return sources.first { $0.id == reference.id }
        }
    }

     
     
     
     
     
     
     
    func linksToRejoin(ofRecipe id: String) -> [ConfigurationSourceRecord] {
        guard updateFollowing(ofRecipe: id) == .copyWithoutOrigin,
              let recipe = recipes.first(where: { $0.id == id }) else { return [] }
        let links = availableSources.filter {
            guard $0.suppliesNodes, case .subscription = $0.origin else { return false }
            return true
        }
        return links.filter { $0.label == recipe.label } + links.filter { $0.label != recipe.label }
    }

     
     
     
    internal func linkSchemeCustomized(by recipe: ConfigurationRecipe) -> ConfigurationRuleScheme? {
        guard recipe.preservesOriginal != true,
              let scheme = rules.first(where: { $0.id == recipe.ruleSchemeID }), scheme.kind == .custom,
              scheme.rulesFromSchemeID == nil,
              let baseID = scheme.rulesCustomizedFromSchemeID ?? scheme.baseSchemeID,
              let base = rules.first(where: { $0.id == baseID }), base.kind == .supplied,
              base.isRetainedSnapshot != true, isLink(base.sourceID) else { return nil }
        return base
    }

    private func isLink(_ sourceID: String) -> Bool {
        guard let record = sources.first(where: { $0.id == sourceID }), record.isRetainedSnapshot != true,
              case .subscription = record.origin else { return false }
        return true
    }

     
    private func isFollowable(_ sourceID: String) -> Bool {
        sources.contains { $0.id == sourceID && $0.isRetainedSnapshot != true }
    }

     
     
     
     
    private func canRun(schemeOf recipe: ConfigurationRecipe) -> Bool {
        if recipe.preservesOriginal == true { return true }
        return rules.contains { $0.id == recipe.ruleSchemeID && $0.isRetainedSnapshot != true }
            || ConfigurationBuiltins.schemes.contains { $0.id == recipe.ruleSchemeID }
    }
}

public extension ConfigurationLibraryStore {
     
     
     
     
     
     
     
     
     
     
     
    func prepareRejoiningSources(_ profileID: String, link linkID: String? = nil, expectedGeneration: UInt64,
        resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput = {
            .init(id: $0.record.id, document: try OrderedJSON.parse($0.documentJSON))
        }) throws -> PreparedConfigurationCreation {
        var candidate = try snapshot()
        guard candidate.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        guard candidate.pendingPublications?.isEmpty ?? true else { throw ConfigurationLibraryError.busy }
        guard let index = candidate.recipes.firstIndex(where: { $0.id == profileID }) else {
            throw ConfigurationLibraryError.missingDependency(profileID)
        }
        let current = candidate.recipes[index]
        func latest(_ reference: ConfigurationSourceVersion) throws -> ConfigurationSourceVersion {
            guard let record = candidate.sources.first(where: { $0.id == reference.id }),
                  record.isRetainedSnapshot != true else { throw ConfigurationLibraryError.missingDependency(reference.id) }
            return .init(record)
        }

         
        var recipe: ConfigurationRecipe
        switch candidate.updateFollowing(ofRecipe: profileID) {
        case .ownCopy?:
            guard let origin = current.ownCopyOf else { throw ConfigurationLibraryError.invalidIdentifier.noted() }
            recipe = origin.previous
            recipe.ruleSource = try latest(recipe.ruleSource)
            recipe.settingsSource = try recipe.settingsSource.map(latest)
            recipe.settingsRuleDependencies = try recipe.settingsRuleDependencies?.mapValues(latest)
        case .copyWithoutOrigin?:
            guard let linkID, let link = candidate.linksToRejoin(ofRecipe: profileID).first(where: { $0.id == linkID }) else {
                throw ConfigurationLibraryError.missingDependency(linkID ?? "link")
            }
            recipe = current
            recipe.sources = [.init(link)]
            recipe.ruleSource = .init(link)
            recipe.ruleSchemeID = "rules-" + link.id
            recipe.preservesOriginal = true
            recipe.settingsSource = nil
            recipe.settingsRuleDependencies = nil
             
            recipe.nodeScopes = nil
        case .customizedRules?:
            recipe = current
        default:
            throw ConfigurationLibraryError.invalidIdentifier.noted()
        }
         
         
        recipe.sources = try recipe.sources.map(latest)
        recipe.label = current.label
        recipe.followsUpdates = true
        recipe.ownCopyOf = nil

        var composition: ConfigurationComposition
        var payloads: [ConfigurationSourcePayload] = []
        if recipe.preservesOriginal == true {
             
            recipe.originalSettingsJSON = current.originalSettingsJSON
            recipe.droppedRules = nil
            let input = try resolveInput(payload(recipe.ruleSource))
            guard input.id == recipe.ruleSource.id, case .object = input.document else {
                throw ConfigurationCompositionError.invalidDocument(recipe.ruleSource.id)
            }
             
             
             
            if input.document.topLevelValue("rules") != nil || input.document.topLevelValue("rule-providers") != nil,
               let index = candidate.sources.firstIndex(where: { $0.id == recipe.ruleSource.id }) {
                candidate.sources[index].registersSuppliedRules = true
                let record = candidate.sources[index]
                if !candidate.rules.contains(where: { $0.id == recipe.ruleSchemeID }) {
                    candidate.rules.append(ConfigurationRuleScheme(id: recipe.ruleSchemeID, label: record.label,
                                                                   kind: .supplied, sourceID: record.id))
                }
            }
            candidate.recipes[index] = recipe
            composition = .init(document: try overlayingAdvancedSettings(of: recipe, onto: input.document),
                                sourceIDs: [input.id])
        } else if let base = candidate.linkSchemeCustomized(by: recipe) {
             
             
             
             
             
             
            let derivativeID = recipe.ruleSchemeID
            recipe.settingsRuleDependencies = nil
            candidate.recipes[index] = recipe
            let switched = try switchingScheme(in: candidate, profileID: profileID, to: base.id, resolveInput: resolveInput)
            candidate = switched.candidate
            payloads += switched.payloads
            composition = switched.composition
            Self.removeCustomizedCopyIfUnused(derivativeID, from: &candidate)
        } else {
            candidate.recipes[index] = recipe
            composition = try self.composition(ofRecipe: profileID, in: candidate, resolveInput: resolveInput)
            candidate.recipes[index].droppedRules = composition.droppedRules.isEmpty ? nil : composition.droppedRules
        }
        return .init(recipe: candidate.recipes[index], composition: composition, candidate: candidate, payloads: payloads)
    }

     
     
     
     
    private static func removeCustomizedCopyIfUnused(_ id: String, from candidate: inout ConfigurationLibrarySnapshot) {
        let previous = candidate.recipes.compactMap { $0.ownCopyOf?.previous }
        let inUse = candidate.schemeIDsInUse
            .union(candidate.rules.compactMap(\.rulesFromSchemeID))
            .union([candidate.selectedRuleSchemeID].compactMap { $0 })
         
         
         
        guard !inUse.contains(id), let scheme = candidate.rules.first(where: { $0.id == id }), scheme.ownViewBaseID == nil else { return }
        candidate.rules.removeAll { $0.id == id }
        let sourceInUse = candidate.rules.contains { $0.sourceID == scheme.sourceID }
            || (candidate.recipes.flatMap(\.dependencies) + previous.flatMap(\.dependencies)).contains { $0.id == scheme.sourceID }
        if !sourceInUse { candidate.sources.removeAll { $0.id == scheme.sourceID } }
    }
}
