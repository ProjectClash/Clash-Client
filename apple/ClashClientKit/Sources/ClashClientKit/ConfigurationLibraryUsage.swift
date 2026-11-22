import Foundation

 
 
 
 
 
 
 
public enum LibraryUsage: Equatable, Sendable {
    case none
    case one(name: String)
    case many(count: Int)

     
     
    public struct Configuration: Equatable, Sendable {
        public let id: String
        public let name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

     
    public init(names: [String]) {
        switch names.count {
        case 0: self = .none
        case 1: self = .one(name: names[0])
        default: self = .many(count: names.count)
        }
    }
}

public extension ConfigurationLibrarySnapshot {
     
     
     
     
     
    func usage(ofSource id: String, profiles: [LibraryUsage.Configuration]) -> LibraryUsage {
        let using = Set(recipes.filter { $0.sources.contains { $0.id == id } }.map(\.id))
        return LibraryUsage(names: profiles.filter { using.contains($0.id) }.map(\.name))
    }

     
     
     
     
     
     
    func usage(ofScheme id: String, profiles: [LibraryUsage.Configuration]) -> LibraryUsage {
        let using = Set(recipes(runningScheme: id).map(\.id))
        return LibraryUsage(names: profiles.filter { using.contains($0.id) }.map(\.name))
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    func recipes(runningScheme id: String) -> [ConfigurationRecipe] {
        let views = Set(rules.filter { $0.rulesFromSchemeID == id || $0.ownViewBaseID == id }.map(\.id))
        let byID = Dictionary(rules.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        return recipes.filter { recipe in
            (recipe.ruleSchemeID == id || views.contains(recipe.ruleSchemeID)
                || Self.unlistedCopy(recipe.ruleSchemeID, comesFrom: id, in: byID))
                && seen.insert(recipe.id).inserted
        }
    }

     
     
     
     
    private static func unlistedCopy(_ schemeID: String, comesFrom id: String,
                                     in byID: [String: ConfigurationRuleScheme]) -> Bool {
        var next: String? = schemeID
        var walked = Set<String>()
        while let current = next, current != id {
            guard walked.insert(current).inserted, let scheme = byID[current], !scheme.isListedInLibrary else { return false }
            next = scheme.baseSchemeID ?? scheme.rulesFromSchemeID ?? scheme.rulesCustomizedFromSchemeID
        }
        return next == id && !walked.isEmpty
    }
}
