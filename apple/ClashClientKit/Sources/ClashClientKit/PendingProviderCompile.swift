import Foundation

 
 
 
 
 
public struct PendingProviderCompile: Decodable, Equatable, Sendable {
    public let kind: String
    public let name: String
    public let result: ProviderRefreshState.Result?
     
    public let error: String?
    public let countAfter: Int?

    private enum Field: String, CodingKey { case kind, name, result, error, countAfter }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Field.self)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        result = (try? c.decodeIfPresent(String.self, forKey: .result)).flatMap { $0.flatMap(ProviderRefreshState.Result.init(rawValue:)) }
        error = try c.decodeIfPresent(String.self, forKey: .error).flatMap { $0.isEmpty ? nil : $0 }
        countAfter = try c.decodeIfPresent(Int.self, forKey: .countAfter)
    }

     
    public static func decode(_ json: String) throws -> [PendingProviderCompile] {
        try JSONDecoder().decode([PendingProviderCompile].self, from: Data(json.utf8))
    }

     
     
     
     
     
     
     
    public static func waits(in state: ProviderRefreshState?, excluding: Set<String> = []) -> Bool {
        held(in: state).contains {
            compilesInFront(kind: $0.kind, variant: $0.variant) && !excluding.contains(Held.key($0.key, $0.pendingSHA256))
        }
    }

     
     
     
     
     
    public static func couldNotTake(_ compiled: [PendingProviderCompile], in state: ProviderRefreshState?) -> [Held] {
        let failed = Set(compiled.filter { $0.result == .failed }.map { $0.kind + ":" + $0.name })
        guard !failed.isEmpty else { return [] }
        return held(in: state).filter { compilesInFront(kind: $0.kind, variant: $0.variant) && failed.contains($0.kind + ":" + $0.name) }
            .map { Held(kind: $0.kind, name: $0.name, requestKey: $0.key, pendingSHA256: $0.pendingSHA256) }
            .sorted { ($0.kind, $0.name) < ($1.kind, $1.name) }
    }

     
     
     
     
     
     
     
    public static func compileTakes(in state: ProviderRefreshState?, excluding: Set<String> = []) -> [Held] {
        held(in: state).filter { compilesInFront(kind: $0.kind, variant: $0.variant) }
            .map { Held(kind: $0.kind, name: $0.name, requestKey: $0.key, pendingSHA256: $0.pendingSHA256) }
            .filter { !excluding.contains($0.key) }
            .sorted { ($0.kind, $0.name) < ($1.kind, $1.name) }
    }

     
     
     
    public static func compilesInFront(kind: String, variant: ProviderRefreshState.Variant?) -> Bool {
        switch (kind, variant) {
        case ("rule", .mapped?), ("rule", .indexed?), ("proxy", .library?): return true
        default: return false
        }
    }

     
     
    public struct Held: Equatable, Sendable {
        public let kind: String
        public let name: String
         
         
        public let requestKey: String
        public let pendingSHA256: String

         
        public var key: String { Self.key(requestKey, pendingSHA256) }

        static func key(_ requestKey: String, _ pendingSHA256: String) -> String {
            requestKey + "\u{0}" + pendingSHA256
        }
    }

     
     
     
     
     
    public static func waitingForAPublication(in state: ProviderRefreshState?) -> [Held] {
        held(in: state).filter { !compilesInFront(kind: $0.kind, variant: $0.variant) }
            .map { Held(kind: $0.kind, name: $0.name, requestKey: $0.key, pendingSHA256: $0.pendingSHA256) }
            .sorted { ($0.kind, $0.name) < ($1.kind, $1.name) }
    }

     
    public static func heldKeys(in state: ProviderRefreshState?) -> Set<String> {
        Set(held(in: state).map { Held.key($0.key, $0.pendingSHA256) })
    }

     
    private static func held(in state: ProviderRefreshState?)
        -> [(kind: String, name: String, key: String, variant: ProviderRefreshState.Variant?, pendingSHA256: String)] {
        guard let state, let running = state.running else { return [] }
        var out: [(kind: String, name: String, key: String, variant: ProviderRefreshState.Variant?, pendingSHA256: String)] = []
        for (identity, key) in running.providers {
            guard let entry = state.entries[key], entry.result == .pendingApp else { continue }
            let parts = identity.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let kind = String(parts[0]), name = String(parts[1])
            guard state.pendingTaker(kind: kind, name: name, reason: entry.waitReason) == .appWhenOpen else { continue }
            out.append((kind, name, key, state.variant(kind: kind, name: name), entry.pendingSHA256 ?? ""))
        }
        return out
    }
}
