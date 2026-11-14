import Foundation

 
 
 
 
 
 
 
public struct ConfigurationRuleTargetCandidates: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable { case builtin, groups, source, providers }

    public struct Section: Equatable, Sendable, Identifiable {
         
        public let id: String
        public let kind: Kind
         
         
        public let sourceLabel: String?
         
        public let names: [String]

        public init(id: String, kind: Kind, sourceLabel: String? = nil, names: [String]) {
            self.id = id; self.kind = kind; self.sourceLabel = sourceLabel; self.names = names
        }
    }

     
     
    public struct NodeSource: Equatable, Sendable {
        public let id: String
        public let label: String
        public let documentJSON: String
        public init(id: String, label: String, documentJSON: String) {
            self.id = id; self.label = label; self.documentJSON = documentJSON
        }
    }

     
    public static let builtinPolicies = ["DIRECT", "REJECT", "REJECT-DROP", "PASS"]

     
     
     
    public let sections: [Section]

    public init(sections: [Section]) { self.sections = sections }

     
     
     
    public static func make(groups: [String], sources: [NodeSource], providers: Bool = false) -> ConfigurationRuleTargetCandidates {
        var sections = [Section(id: "builtin", kind: .builtin, names: builtinPolicies)]
        let groupNames = unique(groups.filter { !$0.isEmpty && !builtinPolicies.contains($0) })
        if !groupNames.isEmpty { sections.append(Section(id: "groups", kind: .groups, names: groupNames)) }
        for source in sources {
            let names = unique(nodeNames(inDocumentJSON: source.documentJSON))
            guard !names.isEmpty else { continue }
            sections.append(Section(id: "source:" + source.id, kind: .source, sourceLabel: source.label, names: names))
        }
        for source in sources where providers {
            let keys = providerKeys(inDocumentJSON: source.documentJSON)
            guard !keys.isEmpty else { continue }
            sections.append(Section(id: "providers:" + source.id, kind: .providers, sourceLabel: source.label, names: keys))
        }
        return ConfigurationRuleTargetCandidates(sections: sections)
    }

     
     
     
     
     
     
     
     
     
     
    public static func make(
        groups: [String],
        snapshot: ConfigurationLibrarySnapshot,
        sourceIDs: [String]? = nil,
        providers: Bool = false,
        naming: (ConfigurationSourceRecord) -> String,
        payload: (ConfigurationSourceVersion) throws -> ConfigurationSourcePayload
    ) throws -> ConfigurationRuleTargetCandidates {
        var sources: [NodeSource] = []
         
         
        for record in snapshot.sources where record.suppliesNodes && record.isRetainedSnapshot != true {
            if let sourceIDs, !sourceIDs.contains(record.id) { continue }
            if sourceIDs == nil, record.privateToConfigurationID != nil { continue }
            let document = try payload(ConfigurationSourceVersion(record)).documentJSON
            sources.append(NodeSource(id: record.id, label: naming(record), documentJSON: document))
        }
        return make(groups: groups, sources: sources, providers: providers)
    }

     
    public var names: [String] { Self.unique(sections.flatMap(\.names)) }

    public func contains(_ name: String) -> Bool { sections.contains { $0.names.contains(name) } }

     
     
    public func filtered(by query: String) -> ConfigurationRuleTargetCandidates {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return self }
        let kept = sections.compactMap { section -> Section? in
            let names = section.names.filter { $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            return names.isEmpty ? nil : Section(id: section.id, kind: section.kind, sourceLabel: section.sourceLabel, names: names)
        }
        return ConfigurationRuleTargetCandidates(sections: kept)
    }

     
     
    public static func nodeNames(inDocumentJSON json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let proxies = root["proxies"] as? [[String: Any]] else { return [] }
        return proxies.compactMap { node in
            guard let name = node["name"] as? String else { return nil }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

     
     
    public static func providerKeys(inDocumentJSON json: String) -> [String] {
        guard let document = try? OrderedJSON.parse(json),
              case .object(let pairs)? = document.topLevelValue("proxy-providers") else { return [] }
        return unique(pairs.map(\.key).filter { !$0.isEmpty })
    }

    private static func unique(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }
}
