import Foundation

 
 
 
 
 
 
 
 
 
 
 
public struct ProviderRefreshState: Decodable, Equatable, Sendable {
     
     
    public static let directoryName = "provider-refresh"
    public static let stateFileName = "state.json"

    public enum Result: String, Decodable, Sendable {
        case scheduled, updated, unchanged, failed, pendingApp
    }

     
     
     
     
    public enum Variant: String, Decodable, Sendable {
        case compiled, indexed, text, mrs, proxy, mapped, library
    }

    public struct Running: Decodable, Equatable, Sendable {
         
        public let configSHA256: String?
         
        public let providers: [String: String]
         
         
         
        public let variants: [String: String]?
    }

    public struct Entry: Decodable, Equatable, Sendable {
        public let kind: String
        public let url: String
        public let interval: Int?
         
         
        public let lastCheckedAt: Int64?
        public let lastChangedAt: Int64?
        public let nextDueAt: Int64?
         
         
        public let lastAttemptAt: Int64?
         
        public let result: Result?
         
        public let error: String?
         
         
         
        public let pendingReason: String?
         
         
        public let pendingSHA256: String?
         
        public let pendingWait: String?
        public let pendingCheckedAt: Int64?
        public let countBefore: Int?
        public let countAfter: Int?
        public let subscriptionInfo: String?

        private enum CodingKeys: String, CodingKey {
            case kind, url, interval, lastCheckedAt, lastChangedAt, nextDueAt, lastAttemptAt, result, error,
                 pendingReason, pendingSHA256, pendingWait, pendingCheckedAt, countBefore, countAfter, subscriptionInfo
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            kind = try c.decode(String.self, forKey: .kind)
            url = try c.decode(String.self, forKey: .url)
            interval = try c.decodeIfPresent(Int.self, forKey: .interval)
            lastCheckedAt = try c.decodeIfPresent(Int64.self, forKey: .lastCheckedAt)
            lastChangedAt = try c.decodeIfPresent(Int64.self, forKey: .lastChangedAt)
            nextDueAt = try c.decodeIfPresent(Int64.self, forKey: .nextDueAt)
            lastAttemptAt = try c.decodeIfPresent(Int64.self, forKey: .lastAttemptAt)
            result = (try? c.decodeIfPresent(String.self, forKey: .result)).flatMap { $0.flatMap(Result.init(rawValue:)) }
            error = Self.nonEmpty(try c.decodeIfPresent(String.self, forKey: .error))
            pendingReason = Self.nonEmpty(try c.decodeIfPresent(String.self, forKey: .pendingReason))
            pendingSHA256 = Self.nonEmpty(try c.decodeIfPresent(String.self, forKey: .pendingSHA256))
            pendingWait = Self.nonEmpty(try c.decodeIfPresent(String.self, forKey: .pendingWait))
            pendingCheckedAt = try c.decodeIfPresent(Int64.self, forKey: .pendingCheckedAt)
            countBefore = try c.decodeIfPresent(Int.self, forKey: .countBefore)
            countAfter = try c.decodeIfPresent(Int.self, forKey: .countAfter)
            subscriptionInfo = Self.nonEmpty(try c.decodeIfPresent(String.self, forKey: .subscriptionInfo))
        }

        private static func nonEmpty(_ value: String?) -> String? {
            value.flatMap { $0.isEmpty ? nil : $0 }
        }

         
        public var checkedAt: Date? {
            lastCheckedAt.flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil }
        }

         
         
         
        public var waitReason: String? { pendingWait ?? pendingReason }
    }

    public let version: Int
    public let writtenAt: Int64?
    public let running: Running?
    public let entries: [String: Entry]

    public static func key(kind: String, name: String) -> String { kind + ":" + name }

     
     
    public func variant(kind: String, name: String) -> Variant? {
        running?.variants?[Self.key(kind: kind, name: name)].flatMap(Variant.init(rawValue:))
    }

     
     
    public static func read(workingDirectory: URL) -> ProviderRefreshState? {
        let url = workingDirectory.appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(stateFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    public static func decode(_ data: Data) -> ProviderRefreshState? {
        guard let state = try? JSONDecoder().decode(ProviderRefreshState.self, from: data),
              state.version == 2 else { return nil }
        return state
    }

     
    public func requestKey(kind: String, name: String) -> String? {
        running?.providers[Self.key(kind: kind, name: name)]
    }

     
     
     
    public func entry(kind: String, name: String, url: String) -> Entry? {
        guard let key = requestKey(kind: kind, name: name),
              let entry = entries[key], entry.kind == kind, entry.url == url else { return nil }
        return entry
    }

     
     
     
     
     
     
     
    public enum PendingTaker: Equatable, Sendable {
         
         
         
         
         
        case appWhenOpen
         
        case appWhenAsked
         
         
         
        case tunnelRetries
         
         
        case tunnelKeepsOld
    }

     
    public func pendingTaker(kind: String, name: String, reason: String?, appCanFetch: Bool = true) -> PendingTaker {
        Self.pendingTaker(kind: kind, reason: reason, variant: variant(kind: kind, name: name), appCanFetch: appCanFetch)
    }

    public static func pendingTaker(kind: String, reason: String?, variant: Variant?,
                                    appCanFetch: Bool = true) -> PendingTaker {
        if !appCanFetch { return reason == "killed" ? .tunnelKeepsOld : .tunnelRetries }
        switch (kind, reason) {
         
         
         
        case (_, "recompile"?): return .appWhenOpen
        case ("proxy", "memory"?): return .tunnelRetries
        case ("proxy", "killed"?): return .tunnelKeepsOld
        case ("rule", "routes"?): return .appWhenOpen
        case ("rule", "memory"?), ("rule", "killed"?):
            return variant == .compiled || variant == .mrs ? .appWhenOpen : .appWhenAsked
        default: return .appWhenAsked
        }
    }

     
     
    public func displayLine(kind: String, name: String, _ entry: Entry,
                            appCanFetch: Bool = true) -> (key: String, arguments: [String])? {
        Self.displayLine(result: entry.result, error: entry.error, countBefore: entry.countBefore,
                         countAfter: entry.countAfter,
                         taker: pendingTaker(kind: kind, name: name, reason: entry.waitReason, appCanFetch: appCanFetch),
                         reason: entry.waitReason)
    }

     
     
     
     
    public static func displayLine(result: Result?, error: String?, countBefore: Int?, countAfter: Int?,
                                   taker: PendingTaker, reason: String? = nil) -> (key: String, arguments: [String])? {
        switch result {
        case .pendingApp?: return pendingLine(taker, reason: reason, countBefore: countBefore).map { ($0, []) }
         
        case .failed?: return error.map { ("Update failed: %@", [$0]) } ?? ("Update failed", [])
        case .updated?:
            if countAfter == 0, let before = countBefore, before > 0 {
                return ("Updated: now empty (was %@)", [String(before)])
            }
            return ("Updated", [])
        case .unchanged?: return ("Up to date", [])
        case .scheduled?, nil: return nil
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    public static func pendingLine(_ taker: PendingTaker, reason: String? = nil, countBefore: Int? = nil) -> String? {
        switch taker {
        case .appWhenOpen where reason == "routes": return "Applies after you reconnect"
        case .appWhenOpen: return nil
        case .appWhenAsked: return "Downloaded — tap Update to use it"
        case .tunnelRetries, .tunnelKeepsOld: return keptLine(taker, countBefore: countBefore)
        }
    }

     
     
     
    public static func keptLine(_ taker: PendingTaker, countBefore: Int? = nil) -> String {
        switch taker {
        case .tunnelRetries where countBefore == 0: return "Not loaded yet — try reconnecting"
        case .tunnelKeepsOld: return "Using the saved copy until there's new content"
        case .tunnelRetries, .appWhenOpen, .appWhenAsked: return "Using the saved copy — updates after you reconnect"
        }
    }
}

 
 
public struct ProviderUpdateAnswer: Decodable, Equatable, Sendable {
     
    public let result: ProviderRefreshState.Result?
    public let countBefore: Int?
    public let countAfter: Int?
     
    public let error: String?
     
    public let pendingReason: String?
     
    public let checkedAt: Int64?

    private enum CodingKeys: String, CodingKey {
        case result, countBefore, countAfter, error, pendingReason, checkedAt
    }

    public init(result: ProviderRefreshState.Result?, countBefore: Int? = nil, countAfter: Int? = nil,
                error: String? = nil, pendingReason: String? = nil, checkedAt: Int64? = nil) {
        self.result = result
        self.countBefore = countBefore
        self.countAfter = countAfter
        self.error = error
        self.pendingReason = pendingReason
        self.checkedAt = checkedAt
    }

     
     
    public init(_ entry: ProviderRefreshState.Entry) {
        self.init(result: entry.result, countBefore: entry.countBefore, countAfter: entry.countAfter,
                  error: entry.error, pendingReason: entry.waitReason, checkedAt: entry.lastCheckedAt)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        result = (try? c.decodeIfPresent(String.self, forKey: .result)).flatMap { $0.flatMap(ProviderRefreshState.Result.init(rawValue:)) }
        countBefore = try c.decodeIfPresent(Int.self, forKey: .countBefore)
        countAfter = try c.decodeIfPresent(Int.self, forKey: .countAfter)
        error = (try c.decodeIfPresent(String.self, forKey: .error)).flatMap { $0.isEmpty ? nil : $0 }
        pendingReason = (try c.decodeIfPresent(String.self, forKey: .pendingReason)).flatMap { $0.isEmpty ? nil : $0 }
        checkedAt = try c.decodeIfPresent(Int64.self, forKey: .checkedAt)
    }

     
    public static func decode(_ json: String) -> ProviderUpdateAnswer? {
        try? JSONDecoder().decode(ProviderUpdateAnswer.self, from: Data(json.utf8))
    }

     
     
    public func displayLine(taker: ProviderRefreshState.PendingTaker) -> (key: String, arguments: [String])? {
        ProviderRefreshState.displayLine(result: result, error: error, countBefore: countBefore,
                                         countAfter: countAfter, taker: taker, reason: pendingReason)
    }
}

 
 
 
 
public enum ProviderUpdateRefusal: Equatable, Sendable {
     
     
    case unavailable
     
    case busy
     
     
    case stillRunning

    public static let unavailablePrefix = "clash: provider update unavailable: "
    public static let busyPrefix = "clash: provider update: the tunnel is busy"
    public static let stillRunningPrefix = "clash: provider update: still running in the tunnel"

     
     
     
    public init?(_ text: String) {
        if text.contains(Self.unavailablePrefix) { self = .unavailable }
        else if text.contains(Self.busyPrefix) { self = .busy }
        else if text.contains(Self.stillRunningPrefix) { self = .stillRunning }
        else { return nil }
    }
}

 
 
public struct ProviderUpdateTarget: Equatable, Sendable {
    public let kind: String             
    public let name: String
     
    public let vehicle: String
    public let url: String?
     
     
    public let fetchedByCore: Bool
     
    public let unusableAddress: Bool

    public init(kind: String, name: String, vehicle: String, url: String?, fetchedByCore: Bool,
                unusableAddress: Bool = false) {
        self.kind = kind
        self.name = name
        self.vehicle = vehicle
        self.url = url
        self.fetchedByCore = fetchedByCore
        self.unusableAddress = unusableAddress
    }

     
    public init(kind: String, name: String, vehicle: String, url: String?, outbound: String?,
                unusableAddress: Bool = false) {
        self.init(kind: kind, name: name, vehicle: vehicle, url: url,
                  fetchedByCore: ConfigurationCollection.namesOutbound(outbound ?? ""), unusableAddress: unusableAddress)
    }
}

 
 
 
public enum ProviderUpdateRoute: Equatable, Sendable {
     
     
    case tunnel
     
     
    case appSeed
     
     
    case awaitingConnection
    case notUpdatable(Reason)

    public enum Reason: Equatable, Sendable {
         
        case local
         
        case unusableAddress
    }

    public static func decide(_ target: ProviderUpdateTarget, tunnelRunning: Bool) -> ProviderUpdateRoute {
        guard target.vehicle.lowercased() == "http" else { return .notUpdatable(.local) }
        if target.unusableAddress { return .notUpdatable(.unusableAddress) }
        if tunnelRunning { return .tunnel }
        return target.fetchedByCore ? .awaitingConnection : .appSeed
    }
}
