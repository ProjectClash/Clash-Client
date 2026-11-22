import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
public extension ConfigurationLibraryStore {
     
     
     
     
     
    func prepareDuplicate(ofRecipe originalID: String, as profileID: String, label: String,
                          expectedGeneration: UInt64,
                          resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput = {
                              .init(id: $0.record.id, document: try OrderedJSON.parse($0.documentJSON))
                          }) throws -> PreparedConfigurationCreation {
        let current = try snapshot()
        guard current.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        guard let original = current.recipes.first(where: { $0.id == originalID }) else {
            throw ConfigurationLibraryError.missingDependency(originalID)
        }
        guard !current.recipes.contains(where: { $0.id == profileID }) else {
            throw ConfigurationLibraryError.invalidIdentifier.noted("a duplicate needs an id of its own")
        }
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ConfigurationLibraryError.emptyName }

        let own = try ConfigurationDuplication.ownRecords(of: original, in: current)
         
         
         
         
         
        var renamed: [String: String] = [:]
        var inOrder = false
        for _ in 0..<8 where !inOrder {
            renamed = ConfigurationDuplication.newIdentifiers(originalID: originalID, profileID: profileID,
                                                              sources: own.sources, schemes: own.schemes,
                                                              among: current.sources.map(\.id))
            inOrder = ConfigurationDuplication.keepsOrder(renamed, sources: own.sources, among: current.sources.map(\.id))
        }
        guard inOrder else {
            throw ConfigurationLibraryError.invalidIdentifier.noted("a duplicate's ids would not sort as the original's")
        }
        let taken = Set(current.sources.map(\.id) + current.rules.map(\.id) + current.recipes.map(\.id))
        guard taken.isDisjoint(with: Set(renamed.values)) else {
            throw ConfigurationLibraryError.invalidIdentifier.noted("a duplicate's new id is taken")
        }

        var candidate = current
         
        for record in current.sources where own.sources.contains(record.id) {
            candidate.sources.append(try ConfigurationDuplication.renaming(record, renamed))
        }
        for scheme in current.rules where own.schemes.contains(scheme.id) {
            candidate.rules.append(try ConfigurationDuplication.renaming(scheme, renamed))
        }
        var recipe = try ConfigurationDuplication.renaming(original, renamed)
        recipe.label = name
        candidate.recipes.append(recipe)

         
         
         
        var versions = Set(current.sources.filter { own.sources.contains($0.id) }.map(ConfigurationSourceVersion.init))
        versions.formUnion(original.dependencies.filter { own.sources.contains($0.id) })
        for record in current.sources where own.sources.contains(record.id) {
            versions.formUnion((record.nodeChain?.hops ?? []).map(\.source).filter { own.sources.contains($0.id) })
        }
         
         
         
         
         
        let named = renamed.filter { own.sources.contains($0.key) }
        let payloads = try versions.sorted { ($0.id, $0.version) < ($1.id, $1.version) }.map { reference in
            let stored = try payload(reference)
             
             
             
            return ConfigurationSourcePayload(
                record: try ConfigurationDuplication.renaming(stored.record, renamed),
                original: ConfigurationDuplication.composedNames(in: stored.original, named),
                documentJSON: ConfigurationDuplication.composedNames(in: stored.documentJSON, named),
                resourceFiles: stored.resourceFiles,
                ruleBaselineJSON: stored.ruleBaselineJSON.map { ConfigurationDuplication.composedNames(in: $0, named) })
        }

         
         
        let composition: ConfigurationComposition
        if recipe.preservesOriginal == true {
            let source = try payloads.first { ConfigurationSourceVersion($0.record) == recipe.ruleSource }
                ?? payload(recipe.ruleSource)
            let input = try resolveInput(source)
            guard input.id == recipe.ruleSource.id, case .object = input.document else {
                throw ConfigurationCompositionError.invalidDocument(recipe.ruleSource.id)
            }
            composition = .init(document: try overlayingAdvancedSettings(of: recipe, onto: input.document),
                                sourceIDs: [input.id])
        } else {
            composition = try self.composition(of: recipe, in: candidate, held: payloads, resolveInput: resolveInput)
        }
        return .init(recipe: recipe, composition: composition, candidate: candidate, payloads: payloads,
                     renamedIdentifiers: renamed)
    }
}

public extension PreparedConfigurationCreation {
     
     
     
     
     
     
     
     
     
     
     
     
     
    func carryingComposedNames<Value: Codable>(_ value: Value) throws -> Value {
        let text = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        let moved = ConfigurationDuplication.composedNames(in: text, renamedIdentifiers)
        return moved == text ? value : try JSONDecoder().decode(Value.self, from: Data(moved.utf8))
    }
}

enum ConfigurationDuplication {
     
     
     
     
     
     
     
     
     
    static func ownRecords(of recipe: ConfigurationRecipe, in snapshot: ConfigurationLibrarySnapshot) throws
        -> (sources: Set<String>, schemes: Set<String>) {
        let sources = Dictionary(snapshot.sources.filter { $0.privateToConfigurationID == recipe.id }.map { ($0.id, $0) },
                                 uniquingKeysWith: { first, _ in first })
        let schemes = Dictionary(snapshot.rules.filter { $0.privateToConfigurationID == recipe.id }.map { ($0.id, $0) },
                                 uniquingKeysWith: { first, _ in first })
        var found: (sources: Set<String>, schemes: Set<String>) = ([], [])
        var pending = Array(try strings(in: recipe))
        while let id = pending.popLast() {
            if let record = sources[id], found.sources.insert(id).inserted { pending += try strings(in: record) }
            if let scheme = schemes[id], found.schemes.insert(id).inserted { pending += try strings(in: scheme) }
        }
        return found
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func newIdentifiers(originalID: String, profileID: String,
                               sources: Set<String>, schemes: Set<String>,
                               among others: [String] = []) -> [String: String] {
        var renamed = [originalID: profileID]
        let staying = others.filter { !sources.contains($0) }
         
         
        let groups = Dictionary(grouping: sources) { id in
            "\(id.hasPrefix("edited-"))\u{0}\(staying.filter { $0 < id }.count)"
        }
        for originals in groups.values {
            let copies = originals.map { id in
                mint(like: id) { candidate in staying.allSatisfy { (candidate < $0) == (id < $0) } }
            }.sorted()
            for (id, copy) in zip(originals.sorted(), copies) {
                renamed[id] = copy
                renamed["rules-" + id] = "rules-" + copy
            }
        }
        for id in schemes.sorted() where renamed[id] == nil { renamed[id] = UUID().uuidString }
        return renamed
    }

     
     
     
     
     
    static func keepsOrder(_ renamed: [String: String], sources: Set<String>, among others: [String]) -> Bool {
        guard Set(renamed.values).count == renamed.count else { return false }
        let placed = Set(others).union(sources).sorted().map { sources.contains($0) ? renamed[$0] ?? $0 : $0 }
        return zip(placed, placed.dropFirst()).allSatisfy { $0 < $1 }
    }

     
     
     
     
     
    static func mint(like id: String, fits: (String) -> Bool) -> String {
        let shape = id.hasPrefix("edited-") ? "edited-" : ""
        for kept in shape.count..<max(id.count, shape.count + 1) {
            for _ in 0..<16 {
                let fresh = shape + UUID().uuidString
                let candidate = String(id.prefix(kept)) + fresh.dropFirst(kept)
                if candidate != id, fits(candidate) { return candidate }
            }
        }
        return shape + UUID().uuidString
    }

     
     
     
     
     
     
     
     
     
     
    static func composedNames(in text: String, _ renamed: [String: String]) -> String {
        guard text.contains("[") else { return text }
        var moved = text
        for (original, copy) in renamed where moved.contains("[\(original)] ") {
            moved = moved.replacingOccurrences(of: "[\(original)] ", with: "[\(copy)] ")
        }
        return moved
    }

     
     
     
    static func composedNames(in original: Data, _ renamed: [String: String]) -> Data {
        guard renamed.keys.contains(where: { original.range(of: Data("[\($0)] ".utf8)) != nil }),
              let text = String(data: original, encoding: .utf8) else { return original }
        return Data(composedNames(in: text, renamed).utf8)
    }

     
     
     
     
     
     
    static func renaming<Value: Codable>(_ value: Value, _ renamed: [String: String]) throws -> Value {
        let encoded = try OrderedJSON.parse(String(decoding: JSONEncoder().encode(value), as: UTF8.self))
        func moved(_ text: String) -> String { renamed[text] ?? composedNames(in: text, renamed) }
        func rename(_ node: OrderedJSON) -> OrderedJSON {
            switch node {
            case .object(let entries): return .object(entries.map { (key: moved($0.key), value: rename($0.value)) })
            case .array(let items): return .array(items.map(rename))
            case .string(let text): return .string(moved(text))
            case .scalar: return node
            }
        }
        return try JSONDecoder().decode(Value.self, from: Data(rename(encoded).serialized().utf8))
    }

     
    static func strings<Value: Encodable>(in value: Value) throws -> Set<String> {
        var found = Set<String>()
        func collect(_ node: OrderedJSON) {
            switch node {
            case .object(let entries): for entry in entries { found.insert(entry.key); collect(entry.value) }
            case .array(let items): items.forEach(collect)
            case .string(let text): found.insert(text)
            case .scalar: break
            }
        }
        collect(try OrderedJSON.parse(String(decoding: JSONEncoder().encode(value), as: UTF8.self)))
        return found
    }
}
