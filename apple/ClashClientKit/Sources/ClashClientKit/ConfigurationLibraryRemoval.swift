import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
public struct ConfigurationLibraryRemoval: Equatable, Sendable {
    public struct PlacedSource: Equatable, Sendable {
        public let index: Int
        public let record: ConfigurationSourceRecord
    }

    public struct PlacedRuleScheme: Equatable, Sendable {
        public let index: Int
        public let scheme: ConfigurationRuleScheme
    }

     
    public let sources: [PlacedSource]
    public let rules: [PlacedRuleScheme]
    public let updateIssues: [ConfigurationUpdateIssue]
     
    public internal(set) var payloads: [ConfigurationSourcePayload]
     
     
     
    public let leftSources: [String: Trace]
    public let leftRules: [String: Trace]
     
    public internal(set) var recipes: [ConfigurationRecipe] = []
    var leftRecipes: [String: ConfigurationRecipe] = [:]

     
     
     
    public struct Trace: Equatable, Sendable {
        let source: ConfigurationSourceRecord?
        let scheme: ConfigurationRuleScheme?
        var retained: Bool { (source?.isRetainedSnapshot ?? scheme?.isRetainedSnapshot) == true }

        init(_ record: ConfigurationSourceRecord) { source = record; scheme = nil }
        init(_ scheme: ConfigurationRuleScheme) { source = nil; self.scheme = scheme }
    }

    public var isEmpty: Bool { sources.isEmpty && rules.isEmpty && updateIssues.isEmpty && recipes.isEmpty }

     
     
    func untouched(in library: ConfigurationLibrarySnapshot) -> Bool {
        let sourcesOK = sources.allSatisfy { placed in
            let now = library.sources.first { $0.id == placed.record.id }
            guard let left = leftSources[placed.record.id] else { return now == nil }
            guard let now else { return left.retained }
            return Trace(now) == left
        }
        let rulesOK = rules.allSatisfy { placed in
            let now = library.rules.first { $0.id == placed.scheme.id }
            guard let left = leftRules[placed.scheme.id] else { return now == nil }
            guard let now else { return left.retained }
            return Trace(now) == left
        }
         
         
        let recipesOK = recipes.allSatisfy { placed in
            guard let now = library.recipes.first(where: { $0.id == placed.id }) else { return true }
            guard let left = leftRecipes[placed.id] else { return false }
            return Self.sameChoices(now, as: left)
        }
        return sourcesOK && rulesOK && recipesOK
    }

     
     
     
     
     
    static func sameChoices(_ now: ConfigurationRecipe, as left: ConfigurationRecipe) -> Bool {
        now.sources.map(\.id) == left.sources.map(\.id) && now.nodeScopes == left.nodeScopes
            && now.ruleSchemeID == left.ruleSchemeID && now.preservesOriginal == left.preservesOriginal
    }

     
     
     
    static func restoring(_ before: ConfigurationRecipe, onto now: ConfigurationRecipe) -> ConfigurationRecipe {
        let current = Dictionary(now.sources.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var restored = now
        restored.sources = before.sources.map { current[$0.id] ?? $0 }
        restored.nodeScopes = before.nodeScopes
        return restored
    }
}

extension ConfigurationLibraryStore {
     
     
    public func removal(from before: ConfigurationLibrarySnapshot,
                        to prepared: ConfigurationLibrarySnapshot) throws -> ConfigurationLibraryRemoval {
         
         
         
         
        let candidate = Self.pruningUnreferencedRetainedRecords(prepared).snapshot
        let sources = before.sources.enumerated().compactMap { index, record in
            candidate.sources.contains(record) ? nil : ConfigurationLibraryRemoval.PlacedSource(index: index, record: record)
        }
        let rules = before.rules.enumerated().compactMap { index, scheme in
            candidate.rules.contains(scheme) ? nil : ConfigurationLibraryRemoval.PlacedRuleScheme(index: index, scheme: scheme)
        }
        let issues = (before.updateIssues ?? []).filter { !(candidate.updateIssues ?? []).contains($0) }
        var payloads = try sources.map { try payload(ConfigurationSourceVersion($0.record)) }
        var leftSources: [String: ConfigurationLibraryRemoval.Trace] = [:]
        for placed in sources {
            if let kept = candidate.sources.first(where: { $0.id == placed.record.id }) { leftSources[placed.record.id] = .init(kept) }
        }
        var leftRules: [String: ConfigurationLibraryRemoval.Trace] = [:]
        for placed in rules {
            if let kept = candidate.rules.first(where: { $0.id == placed.scheme.id }) { leftRules[placed.scheme.id] = .init(kept) }
        }
        var removal = ConfigurationLibraryRemoval(sources: sources, rules: rules, updateIssues: issues, payloads: payloads,
                                                  leftSources: leftSources, leftRules: leftRules)
        let after = Dictionary(candidate.recipes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for recipe in before.recipes {
            guard let left = after[recipe.id], left != recipe else { continue }
            removal.recipes.append(recipe)
            removal.leftRecipes[recipe.id] = left
        }
         
         
         
         
        let surviving = Self.referencedVersions(of: candidate)
        var held = Set(payloads.map { ConfigurationSourceVersion($0.record) })
        for recipe in removal.recipes {
            for reference in recipe.dependencies where !surviving.contains(reference) && !held.contains(reference) {
                guard let copy = try? payload(reference) else { continue }
                removal.payloads.append(copy)
                held.insert(reference)
            }
        }
        return removal
    }

     
     
     
    func restore(_ removal: ConfigurationLibraryRemoval) throws -> ConfigurationLibrarySnapshot {
        let prepared = try prepareRestore(removal)
         
        guard prepared.compositions.isEmpty else {
            throw ConfigurationLibraryError.invalidIdentifier.noted("a removal that changed configurations is restored with prepareRestore")
        }
        return try commit(prepared.candidate, payloads: prepared.payloads, expectedGeneration: prepared.candidate.generation)
    }

     
     
     
     
     
     
     
     
    public func prepareRestore(_ removal: ConfigurationLibraryRemoval,
                               resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput = {
                                   .init(id: $0.record.id, document: try OrderedJSON.parse($0.documentJSON))
                               }) throws -> PreparedConfigurationSourceUpdate {
        var candidate = try snapshot()
         
        if !removal.recipes.isEmpty, !(candidate.pendingPublications?.isEmpty ?? true) { throw ConfigurationLibraryError.busy }
        guard removal.untouched(in: candidate) else {
            throw ConfigurationLibraryError.staleGeneration
        }
        for placed in removal.sources.sorted(by: { $0.index < $1.index }) {
            if let index = candidate.sources.firstIndex(where: { $0.id == placed.record.id }) {
                candidate.sources[index] = placed.record
            } else {
                candidate.sources.insert(placed.record, at: min(placed.index, candidate.sources.count))
            }
        }
        for placed in removal.rules.sorted(by: { $0.index < $1.index }) {
            if let index = candidate.rules.firstIndex(where: { $0.id == placed.scheme.id }) {
                candidate.rules[index] = placed.scheme
            } else {
                candidate.rules.insert(placed.scheme, at: min(placed.index, candidate.rules.count))
            }
        }
        if !removal.updateIssues.isEmpty {
            var issues = candidate.updateIssues ?? []
            for issue in removal.updateIssues where !issues.contains(issue) { issues.append(issue) }
            candidate.updateIssues = issues
        }
         
         
         
        var compositions: [String: ConfigurationComposition] = [:]
        for recipe in removal.recipes {
            guard let index = candidate.recipes.firstIndex(where: { $0.id == recipe.id }) else { continue }
            var restored = ConfigurationLibraryRemoval.restoring(recipe, onto: candidate.recipes[index])
            guard let composition = try? composition(of: restored, in: candidate, held: removal.payloads,
                                                     resolveInput: resolveInput) else { continue }
            restored.droppedRules = composition.droppedRules.isEmpty ? nil : composition.droppedRules
            compositions[restored.id] = composition
            candidate.recipes[index] = restored
        }
        return .init(candidate: candidate, payloads: removal.payloads, compositions: compositions)
    }
}
