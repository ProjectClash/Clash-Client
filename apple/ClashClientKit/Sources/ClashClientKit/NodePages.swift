import Foundation

 
 
 
 
 
 
 
 
 
 
 
public enum NodePaging {
     
    public static let firstMembers = 50
     
    public static let page = 200
}

 
 
 
 
 
 
 
 
 
 
 
 
public enum GroupMembership: Equatable, Sendable {
    case member
    case notMember
     
     
    case unknown

     
     
     
     
     
     
     
     
    public static func judged(held: Bool, holdsEveryMember: Bool, listsEveryGroup: Bool,
                              isOtherGroup: @autoclosure () -> Bool) -> GroupMembership {
        if held { return .member }
        if holdsEveryMember { return .notMember }
        if listsEveryGroup, isOtherGroup() { return .member }
        return .unknown
    }
}

 
public struct NodeDelayReading: Decodable, Equatable, Sendable {
    public let delay: Int?
    public let time: String?

    public init(delay: Int?, time: String?) {
        self.delay = delay
        self.time = time
    }
}

 
public struct NodeMember: Decodable, Equatable, Hashable, Sendable {
    public let name: String
    public let type: String
     
     
    public let inline: Bool
     
    public let placeholderType: String?

    public init(name: String, type: String, inline: Bool, placeholderType: String? = nil) {
        self.name = name
        self.type = type
        self.inline = inline
        self.placeholderType = placeholderType
    }

    private enum Field: String, CodingKey { case name, type, inline, placeholderType }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Field.self)
        name = try c.decode(String.self, forKey: .name)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        inline = try c.decodeIfPresent(Bool.self, forKey: .inline) ?? false
        placeholderType = try c.decodeIfPresent(String.self, forKey: .placeholderType)
    }
}

 
public struct NodeSummary: Decodable, Equatable, Sendable {
     
    public let revision: String?
     
    public let total: Int
     
     
    public let nodes: Int
    public let groups: [String: Group]
    public let providers: [String: Provider]
     
    public let providerErrors: [String: String]
     
     
    public let groupOrder: [String]?

    public struct Group: Decodable, Equatable, Sendable {
        public internal(set) var name: String
        public let type: String
        public let now: String?
        public let fixed: String?
         
        public let total: Int
         
        public let nowMember: NodeMember?
        public let hidden: Bool
        public let icon: String?
        public let testURL: String?
        public let latest: NodeDelayReading?
         
         
         
        public let emptyFallback: String?

        private enum Field: String, CodingKey {
            case name, type, now, fixed, total, nowMember, hidden, icon, testUrl, history, emptyFallback
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Field.self)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
            now = try c.decodeIfPresent(String.self, forKey: .now).flatMap { $0.isEmpty ? nil : $0 }
            fixed = try c.decodeIfPresent(String.self, forKey: .fixed).flatMap { $0.isEmpty ? nil : $0 }
            total = try c.decodeIfPresent(Int.self, forKey: .total) ?? 0
            nowMember = try c.decodeIfPresent(NodeMember.self, forKey: .nowMember)
            hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
            icon = try c.decodeIfPresent(String.self, forKey: .icon)
            testURL = try c.decodeIfPresent(String.self, forKey: .testUrl)
            latest = try c.decodeIfPresent([NodeDelayReading].self, forKey: .history)?.last
            emptyFallback = try c.decodeIfPresent(String.self, forKey: .emptyFallback).flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    public struct Provider: Decodable, Equatable, Sendable {
        public internal(set) var name: String
        public let type: String?
        public let vehicleType: String?
         
        public let total: Int
         
        public let updatedAt: String?
         
         
        public let alive: Int?
        public let dead: Int?
         
        public let testURL: String?
         
         
         
        public let subscriptionUsage: ConfigurationSubscriptionUsage?

        private enum Field: String, CodingKey {
            case name, type, vehicleType, total, updatedAt, alive, dead, testUrl, subscriptionInfo
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Field.self)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            type = try c.decodeIfPresent(String.self, forKey: .type)
            vehicleType = try c.decodeIfPresent(String.self, forKey: .vehicleType)
            total = try c.decodeIfPresent(Int.self, forKey: .total) ?? 0
            updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
            alive = try c.decodeIfPresent(Int.self, forKey: .alive)
            dead = try c.decodeIfPresent(Int.self, forKey: .dead)
            testURL = try c.decodeIfPresent(String.self, forKey: .testUrl)
            subscriptionUsage = (try? c.decodeIfPresent(CoreSubscriptionInfo.self, forKey: .subscriptionInfo))?.usage
        }
    }

    private enum Field: String, CodingKey { case revision, total, nodes, groups, providers, providerErrors, groupOrder }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Field.self)
        revision = try c.decodeIfPresent(String.self, forKey: .revision).flatMap { $0.isEmpty ? nil : $0 }
        total = try c.decodeIfPresent(Int.self, forKey: .total) ?? 0
        nodes = try c.decodeIfPresent(Int.self, forKey: .nodes) ?? 0
        providerErrors = try c.decodeIfPresent([String: String].self, forKey: .providerErrors) ?? [:]
        groupOrder = try c.decodeIfPresent([String].self, forKey: .groupOrder)
         
         
        var decodedGroups = try c.decodeIfPresent([String: Group].self, forKey: .groups) ?? [:]
        for (key, group) in decodedGroups where group.name.isEmpty { decodedGroups[key]?.name = key }
        groups = decodedGroups
        var decodedProviders = try c.decodeIfPresent([String: Provider].self, forKey: .providers) ?? [:]
        for (key, provider) in decodedProviders where provider.name.isEmpty { decodedProviders[key]?.name = key }
        providers = decodedProviders
    }

    public static func decode(_ data: Data) throws -> NodeSummary {
        try JSONDecoder().decode(NodeSummary.self, from: data)
    }

     
     
     
    public static let kernelGlobalName = "GLOBAL"

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    public var globalCountIsTheKernelsOwn: Bool {
        guard let global = groups[Self.kernelGlobalName] else { return false }
        return global.total == 2 + nodes + groups.count - 1
    }

     
     
     
     
    public func globalTailToRead(after firstMembers: Int) -> (offset: Int, limit: Int)? {
        guard globalCountIsTheKernelsOwn, let global = groups[Self.kernelGlobalName] else { return nil }
        let others = groups.count - 1
        guard others > 0, global.total > firstMembers else { return nil }
        return (global.total - others, others)
    }

     
     
     
     
     
     
     
     
     
    public func globalListsEveryGroup(tail: GroupMembersPage?) -> Bool {
        guard globalCountIsTheKernelsOwn, let global = groups[Self.kernelGlobalName],
              let tail, tail.group == Self.kernelGlobalName, tail.total == global.total else { return false }
        let others = Set(groups.keys).subtracting([Self.kernelGlobalName])
        let listed = tail.members.map(\.name)
        return !others.isEmpty && listed.count == others.count && Set(listed) == others
    }
}

 
 
 
 
 
 
 
 
 
public struct CoreSubscriptionInfo: Decodable, Equatable, Sendable {
    public let usage: ConfigurationSubscriptionUsage?

    private enum Field: String, CodingKey {
        case upload = "Upload", download = "Download", total = "Total", expire = "Expire"
    }

    public init(from decoder: Decoder) {
        guard let c = try? decoder.container(keyedBy: Field.self) else {
            usage = nil
            return
        }
        func value(_ field: Field) -> Int64? {
            if let whole = try? c.decodeIfPresent(Int64.self, forKey: field) { return whole }
            guard let float = try? c.decodeIfPresent(Double.self, forKey: field), float.isFinite else { return nil }
            if float >= Double(Int64.max) { return .max }
            if float <= Double(Int64.min) { return .min }
            return Int64(float)
        }
        let upload = value(.upload), download = value(.download), total = value(.total), expire = value(.expire)
        guard upload != nil || download != nil || total != nil || expire != nil else {
            usage = nil
            return
        }
        usage = ConfigurationSubscriptionUsage(upload: upload ?? 0, download: download ?? 0,
                                               total: total ?? 0, expire: expire ?? 0)
    }
}

 
public struct GroupMembersPage: Decodable, Equatable, Sendable {
    public let group: String
    public let total: Int
    public let revision: String?
    public let members: [NodeMember]

    public init(group: String, total: Int, revision: String?, members: [NodeMember]) {
        self.group = group
        self.total = total
        self.revision = revision
        self.members = members
    }

    private enum Field: String, CodingKey { case group, total, revision, members }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Field.self)
        group = try c.decodeIfPresent(String.self, forKey: .group) ?? ""
        total = try c.decodeIfPresent(Int.self, forKey: .total) ?? 0
        revision = try c.decodeIfPresent(String.self, forKey: .revision).flatMap { $0.isEmpty ? nil : $0 }
        members = try c.decodeIfPresent([NodeMember].self, forKey: .members) ?? []
    }
}

 
public struct NodeRow: Decodable, Equatable, Sendable {
    public let name: String
    public let type: String
    public let udp: Bool?
    public let alive: Bool?
    public let latest: NodeDelayReading?
     
    public let total: Int?
     
    public let now: String?

    private enum Field: String, CodingKey { case name, type, udp, alive, history, total, now }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Field.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        udp = try c.decodeIfPresent(Bool.self, forKey: .udp)
        alive = try c.decodeIfPresent(Bool.self, forKey: .alive)
        latest = try c.decodeIfPresent([NodeDelayReading].self, forKey: .history)?.last
        total = try c.decodeIfPresent(Int.self, forKey: .total)
        now = try c.decodeIfPresent(String.self, forKey: .now).flatMap { $0.isEmpty ? nil : $0 }
    }
}

 
public struct ProviderNodesPage: Decodable, Equatable, Sendable {
    public let provider: String
    public let total: Int
    public let revision: String?
    public let proxies: [NodeRow]

    private enum Field: String, CodingKey { case provider, total, revision, proxies }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Field.self)
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? ""
        total = try c.decodeIfPresent(Int.self, forKey: .total) ?? 0
        revision = try c.decodeIfPresent(String.self, forKey: .revision).flatMap { $0.isEmpty ? nil : $0 }
        proxies = try c.decodeIfPresent([NodeRow].self, forKey: .proxies) ?? []
    }
}

 
public struct ProxiesPage: Decodable, Equatable, Sendable {
    public let proxies: [String: NodeRow]
     
    public let next: String?

    private enum Field: String, CodingKey { case proxies, next }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Field.self)
        proxies = try c.decodeIfPresent([String: NodeRow].self, forKey: .proxies) ?? [:]
        next = try c.decodeIfPresent(String.self, forKey: .next).flatMap { $0.isEmpty ? nil : $0 }
    }
}

 
 
public struct ProxySearchPage: Decodable, Equatable, Sendable {
    public let query: String
    public let total: Int
    public let items: [Item]

    public struct Item: Decodable, Equatable, Hashable, Sendable {
        public let name: String
        public let type: String
         
        public let source: String

        public static let groupSource = "group"
        public static let inlineSource = "inline"
    }

    private enum Field: String, CodingKey { case query, total, items }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Field.self)
        query = try c.decodeIfPresent(String.self, forKey: .query) ?? ""
        total = try c.decodeIfPresent(Int.self, forKey: .total) ?? 0
        items = try c.decodeIfPresent([Item].self, forKey: .items) ?? []
    }
}

 
 
 
 
public struct ProxyLookup: Decodable, Equatable, Sendable {
    public let name: String
    public let found: Bool
    public let type: String?
     
    public let source: String?
}

 
public struct NodePageRefusal: Error, Equatable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }

     
    public static func of(_ data: Data) -> NodePageRefusal? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = object["error"] as? String
        else { return nil }
        return NodePageRefusal(message: message)
    }
}
