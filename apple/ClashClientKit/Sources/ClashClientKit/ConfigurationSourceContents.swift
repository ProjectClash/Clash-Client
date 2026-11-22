import Foundation

 
 
 
 
 
public enum ConfigurationSourceContents {
    public struct Node: Hashable, Sendable {
        public let name: String
        public let type: String
        public init(name: String, type: String) { self.name = name; self.type = type }
    }

    public struct Group: Identifiable, Equatable, Sendable {
        public let id: String
        public let label: String
        public let nodes: [Node]
        public let providers: [Node]
    }

     
    public static func group(of record: ConfigurationSourceRecord, scope: ConfigurationNodeScope?,
                             in store: ConfigurationLibraryStore) throws -> Group {
        let payload = try store.payload(.init(record))
        let document = try OrderedJSON.parse(payload.documentJSON)
        func text(_ value: OrderedJSON?) -> String { value?.foundationValue as? String ?? "" }
        var nodes: [Node] = []
        if case .array(let entries) = document.topLevelValue("proxies") {
            nodes = entries.compactMap { entry in
                let name = text(entry.topLevelValue("name"))
                return name.isEmpty ? nil : Node(name: name, type: text(entry.topLevelValue("type")))
            }
        }
        var providers: [Node] = []
        if case .object(let entries) = document.topLevelValue("proxy-providers") {
            providers = entries.map { Node(name: $0.key, type: text($0.value.topLevelValue("type"))) }
        }
        if let scope {
            if !scope.includesInlineNodes { nodes = [] }
            else if let names = scope.inlineNodeNames.map(Set.init) { nodes = nodes.filter { names.contains($0.name) } }
            if let excluded = scope.excludedNodeNames.map(Set.init) { nodes = nodes.filter { !excluded.contains($0.name) } }
            let keys = Set(scope.providerKeys)
            providers = providers.filter { keys.contains($0.name) }
        }
        return Group(id: record.id, label: record.label, nodes: nodes, providers: providers)
    }
}
