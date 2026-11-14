import Foundation
import ClashClientKit
import ClashClientUI

enum ProviderRuntimeCatalogError: LocalizedError, Equatable {
    case unavailable
    case invalidName
    case invalidResponse
     
     
     
    case notNow

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Live provider status is unavailable. Connect Clash and try again."
        case .invalidName:
            return "The provider name is invalid."
        case .invalidResponse:
            return "Clash Core returned an invalid provider status response."
        case .notNow:
            return nil
        }
    }
}

struct ProxyProviderRuntime: Equatable {
    struct Proxy: Equatable, Identifiable {
        let name: String
        let type: String?
        let alive: Bool?
        let latestDelayMilliseconds: Int?
         
         
        var measuredAt: Date?
         
         
         
        var delaysByURL: [String: Int] = [:]

        var id: String { name }
    }

    let name: String
    let vehicleType: String?
    let updatedAt: Date?
    let hasHealthCheck: Bool
    let proxies: [Proxy]
     
     
     
    var total: Int? = nil
     
    var deadCount: Int? = nil
     
     
     
    var subscriptionInfo: SubscriptionInfo? = nil

     
    var nodeCount: Int { max(total ?? 0, proxies.count) }
     
     
     
    var healthyCount: Int {
        if let deadCount, proxies.isEmpty { return max(nodeCount - deadCount, 0) }
        return proxies.filter { $0.alive == true }.count
    }
    var unhealthyCount: Int {
        if let deadCount, proxies.isEmpty { return deadCount }
        return proxies.filter { $0.alive == false }.count
    }
}

extension SubscriptionInfo {
     
    init(usage: ConfigurationSubscriptionUsage) {
        self.init(upload: usage.upload, download: usage.download, total: usage.total, expire: usage.expire)
    }
}

extension ProviderRefreshState.Entry {
     
     
     
     
     
     
     
     
     
     
    var usage: SubscriptionInfo? { subscriptionInfo.flatMap(SubscriptionInfo.parse(header:)) }

     
     
     
     
     
     
     
     
     
     
     
     
    var countOfCheckedContent: Int? {
        guard result == .updated || result == .unchanged, let count = countAfter, count > 0 else { return nil }
        return count
    }

     
     
     
    func isNewer(than date: Date?) -> Bool {
        guard let checked = checkedAt else { return false }
        return date.map { checked > $0 } ?? true
    }
}

extension ProviderRefreshState {
     
     
     
     
     
     
     
    func newerEntry(of provider: ProviderCatalog.Entry, than date: Date?) -> Entry? {
        newerEntry(kind: provider.kind, name: provider.name, url: provider.url, than: date)
    }

    func newerEntry(kind: String, name: String, url: String, than date: Date?) -> Entry? {
        guard let found = entry(kind: kind, name: name, url: url), found.isNewer(than: date) else { return nil }
        return found
    }
}

struct RuleProviderRuntime: Equatable {
    let name: String
    let vehicleType: String?
    let updatedAt: Date?
    let behavior: String?
    let format: String?
    let ruleCount: Int
}

struct ProviderRuntimeSummary: Equatable {
    let vehicleType: String?
    let updatedAt: Date?
    let entryCount: Int
    let healthyCount: Int?
    let unhealthyCount: Int?
    let healthCheckAvailable: Bool
     
    var subscriptionInfo: SubscriptionInfo? = nil
}

struct ProviderRuntimeCatalog: Equatable {
    var proxyProviders: [String: ProxyProviderRuntime]
    var ruleProviders: [String: RuleProviderRuntime]

    static let empty = ProviderRuntimeCatalog(proxyProviders: [:], ruleProviders: [:])

    func summary(name: String, kind: String?) -> ProviderRuntimeSummary? {
        switch kind?.lowercased() {
        case "proxy":
            guard let provider = proxyProviders[name] else { return nil }
            return ProviderRuntimeSummary(
                vehicleType: provider.vehicleType,
                updatedAt: provider.updatedAt,
                entryCount: provider.nodeCount,
                healthyCount: provider.healthyCount,
                unhealthyCount: provider.unhealthyCount,
                healthCheckAvailable: provider.hasHealthCheck,
                subscriptionInfo: provider.subscriptionInfo
            )
        case "rule":
            guard let provider = ruleProviders[name] else { return nil }
            return ProviderRuntimeSummary(
                vehicleType: provider.vehicleType,
                updatedAt: provider.updatedAt,
                entryCount: provider.ruleCount,
                healthyCount: nil,
                unhealthyCount: nil,
                healthCheckAvailable: false
            )
        default:
            return nil
        }
    }
}

enum ProviderRuntimeCatalogParser {
    private struct ProxyEnvelope: Decodable {
        let providers: [String: ProxyPayload]
    }

    private struct RuleEnvelope: Decodable {
        let providers: [String: RulePayload]
    }

    private struct ProxyPayload: Decodable {
        let name: String?
        let vehicleType: String?
        let updatedAt: String?
        let testUrl: String?
        let proxies: [ProxyPayloadEntry]?
         
        let total: Int?
        let dead: Int?
        let subscriptionInfo: CoreSubscriptionInfo?
    }

    private struct ProxyPayloadEntry: Decodable {
        let name: String?
        let type: String?
        let alive: Bool?
        let history: [DelayPayload]?
        let extra: [String: ProxyStatePayload]?
    }

     
    private struct ProxyStatePayload: Decodable {
        let alive: Bool?
        let history: [DelayPayload]?
    }

    private struct DelayPayload: Decodable {
        let delay: Int?
         
         
         
         
        let time: String?
    }

    private struct RulePayload: Decodable {
        let name: String?
        let vehicleType: String?
        let updatedAt: String?
        let behavior: String?
        let format: String?
        let ruleCount: Int?
    }

    static func catalog(proxyJSON: String, ruleJSON: String) throws -> ProviderRuntimeCatalog {
        do {
            let decoder = JSONDecoder()
            let proxyEnvelope = try decoder.decode(
                ProxyEnvelope.self,
                from: Data(proxyJSON.utf8)
            )
            let ruleEnvelope = try decoder.decode(
                RuleEnvelope.self,
                from: Data(ruleJSON.utf8)
            )
            var proxyProviders: [String: ProxyProviderRuntime] = [:]
            for (fallbackName, payload) in proxyEnvelope.providers {
                let provider = try proxyProvider(payload: payload, fallbackName: fallbackName)
                proxyProviders[provider.name] = provider
            }
            var ruleProviders: [String: RuleProviderRuntime] = [:]
            for (fallbackName, payload) in ruleEnvelope.providers {
                let provider = try ruleProvider(payload: payload, fallbackName: fallbackName)
                ruleProviders[provider.name] = provider
            }
            return ProviderRuntimeCatalog(
                proxyProviders: proxyProviders,
                ruleProviders: ruleProviders
            )
        } catch let error as ProviderRuntimeCatalogError {
            throw error
        } catch {
             
             
            throw ProviderRuntimeCatalogError.invalidResponse
        }
    }

     
     
    static func proxyProviders(summary: NodeSummary) -> [String: ProxyProviderRuntime] {
        var providers: [String: ProxyProviderRuntime] = [:]
        for (key, provider) in summary.providers {
            let name = normalizedName(provider.name, fallback: key)
            guard !name.isEmpty else { continue }
            providers[name] = ProxyProviderRuntime(
                name: name,
                vehicleType: provider.vehicleType,
                updatedAt: parseDate(provider.updatedAt),
                hasHealthCheck: !(provider.testURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                proxies: [],
                total: provider.total,
                deadCount: provider.dead,
                subscriptionInfo: provider.subscriptionUsage.map(SubscriptionInfo.init(usage:))
            )
        }
        return providers
    }

    static func proxyDetail(json: String, fallbackName: String) throws -> ProxyProviderRuntime {
        guard !fallbackName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderRuntimeCatalogError.invalidName
        }
        do {
            let payload = try JSONDecoder().decode(ProxyPayload.self, from: Data(json.utf8))
            return try proxyProvider(payload: payload, fallbackName: fallbackName)
        } catch let error as ProviderRuntimeCatalogError {
            throw error
        } catch {
            throw ProviderRuntimeCatalogError.invalidResponse
        }
    }

    private static func proxyProvider(
        payload: ProxyPayload,
        fallbackName: String
    ) throws -> ProxyProviderRuntime {
        let name = normalizedName(payload.name, fallback: fallbackName)
        guard !name.isEmpty else { throw ProviderRuntimeCatalogError.invalidResponse }
        let proxies = (payload.proxies ?? []).compactMap { proxy -> ProxyProviderRuntime.Proxy? in
             
            guard let name = proxy.name, !name.isEmpty else { return nil }
            let delay = proxy.history?
                .compactMap(\.delay)
                .last(where: { $0 > 0 })
            return ProxyProviderRuntime.Proxy(
                name: name,
                type: proxy.type,
                alive: proxy.alive,
                latestDelayMilliseconds: delay,
                measuredAt: proxy.history?.last.flatMap { parseDate($0.time) },
                delaysByURL: (proxy.extra ?? [:]).reduce(into: [:]) { table, entry in
                    if let reading = NodeInventory.reading(
                        delays: entry.value.history?.compactMap(\.delay) ?? [], alive: entry.value.alive) {
                        table[entry.key] = reading
                    }
                }
            )
        }
        return ProxyProviderRuntime(
            name: name,
            vehicleType: payload.vehicleType,
            updatedAt: parseDate(payload.updatedAt),
            hasHealthCheck: !(payload.testUrl ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            proxies: proxies,
            total: payload.total,
            deadCount: payload.dead,
            subscriptionInfo: payload.subscriptionInfo?.usage.map(SubscriptionInfo.init(usage:))
        )
    }

    private static func ruleProvider(
        payload: RulePayload,
        fallbackName: String
    ) throws -> RuleProviderRuntime {
        let name = normalizedName(payload.name, fallback: fallbackName)
        guard !name.isEmpty else { throw ProviderRuntimeCatalogError.invalidResponse }
        return RuleProviderRuntime(
            name: name,
            vehicleType: payload.vehicleType,
            updatedAt: parseDate(payload.updatedAt),
            behavior: payload.behavior,
            format: payload.format,
            ruleCount: max(payload.ruleCount ?? 0, 0)
        )
    }

     
     
     
    private static func normalizedName(_ name: String?, fallback: String) -> String {
        let primary = name ?? ""
        return primary.isEmpty ? fallback : primary
    }

     
     
     
     
     
     
     
     
     
     
     
     
    static func parseDate(_ value: String?) -> Date? {
        guard let date = ClashInstant.parse(value), date.timeIntervalSince1970 > 0 else { return nil }
        return date
    }
}

 
 
 
enum NativeProviderRuntimeDispatcher {
    static func catalog(
        proxy: () throws -> String,
        rule: () throws -> String
    ) throws -> ProviderRuntimeCatalog {
        try ProviderRuntimeCatalogParser.catalog(
            proxyJSON: proxy(),
            ruleJSON: rule()
        )
    }

    static func healthCheck(
        name: String,
        health: (String) throws -> Void,
        detail: (String) throws -> String
    ) throws -> ProxyProviderRuntime {
         
         
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderRuntimeCatalogError.invalidName
        }
        try health(name)
        return try ProviderRuntimeCatalogParser.proxyDetail(
            json: detail(name),
            fallbackName: name
        )
    }
}

 
 
 
 
 
 
struct ProviderCatalog: Codable, Equatable {
    struct Entry: Codable, Equatable {
        let name: String
        let kind: String    
        let url: String
        let path: String    
        let count: Int?
        let subscriptionInfo: SubscriptionInfo?
         
        let updateIntervalSeconds: Int64?
         
        let lastUpdatedAt: Date?
         
         
         
         
         
        let note: ProviderNote?
         
        var loadFailure: String? { note?.englishText }
         
         
         
        var request: String? {
            requestFingerprint?.split(separator: "\n", maxSplits: 1).first.map(String.init)
        }
         
         
         
         
         
         
         
         
        let payloadURL: String?
         
         
         
         
         
         
         
         
         
         
         
        let payloadRequest: String?
         
         
         
         
         
        let acquiredAt: Date?
         
         
         
         
        let requestFingerprint: String?
         
         
         
         
         
        let notedAt: Date?

        init(
            name: String,
            kind: String,
            url: String,
            path: String,
            count: Int? = nil,
            subscriptionInfo: SubscriptionInfo? = nil,
            updateIntervalSeconds: Int64? = nil,
            lastUpdatedAt: Date? = nil,
            loadFailure: String? = nil,
            note: ProviderNote? = nil,
            payloadURL: String? = nil,
            payloadRequest: String? = nil,
            acquiredAt: Date? = nil,
            requestFingerprint: String? = nil,
            notedAt: Date? = nil
        ) {
            self.name = name
            self.kind = kind
            self.url = url
            self.path = path
            self.count = count
            self.subscriptionInfo = subscriptionInfo
            self.updateIntervalSeconds = updateIntervalSeconds
            self.lastUpdatedAt = lastUpdatedAt
            self.note = note ?? loadFailure.map(ProviderNote.init(recorded:))
            self.payloadURL = payloadURL
            self.payloadRequest = payloadRequest
            self.acquiredAt = acquiredAt
            self.requestFingerprint = requestFingerprint
            self.notedAt = note == nil && loadFailure == nil ? nil : notedAt
        }
    }
    var entries: [Entry]
     
     
    var routeSetProviders: Set<String>? = nil
     
    var coreFetchedProviders: Set<String>? = nil
     
     
     
    var coreRouteSeeds: Set<String>? = nil
     
     
     
     
     
    var unusableProxyProviders: [String: String]? = nil
     
     
     
    var seedPaths: [String: String]? = nil
     
     
     
     
     
     
    var userAgent: String? = nil

     
     
     
    var proxyProviderNotes: [String: ProviderNote] {
        var notes: [String: ProviderNote] = [:]
        for entry in entries where entry.kind == "proxy" {
            if let note = entry.note { notes[entry.name] = note }
        }
         
        for (name, notice) in unusableProxyProviders ?? [:] { notes[name] = .failed(.verbatim(notice)) }
        return notes
    }

     
     
    static func unusableProxyProviders(in plan: RemoteResourcePlan) -> [String: String] {
        let prefix = "proxy-providers.", suffix = ".url"
        var found: [String: String] = [:]
        for notice in plan.structuredNotices ?? [] where notice.kind == "provider-url-unusable" {
            guard let field = notice.field, field.hasPrefix(prefix), field.hasSuffix(suffix),
                  field.count > prefix.count + suffix.count else { continue }
            found[String(field.dropFirst(prefix.count).dropLast(suffix.count))] = notice.text
        }
        return found
    }

     
     
    static let fileName = "providers.json"

    func write(providersDir: URL) throws {
        try FileManager.default.createDirectory(at: providersDir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: providersDir.appendingPathComponent(Self.fileName),
                       options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func load(providersDir: URL) -> ProviderCatalog? {
        guard let data = try? Data(contentsOf: providersDir.appendingPathComponent(fileName)) else {
            return nil
        }
        return try? JSONDecoder().decode(ProviderCatalog.self, from: data)
    }

     
    static func requestFingerprint(of provider: RemoteResourcePlan.Provider) -> String {
        ProviderRequestIdentity.of(provider) + "\n" + String(provider.maximumBytes)
    }

    static func from(
        plan: RemoteResourcePlan,
        entryCounts: [String: Int] = [:],
        subscriptionInfo: [String: SubscriptionInfo] = [:],
        lastUpdatedAt: [String: Date] = [:],
        notes: [String: ProviderNote] = [:],
         
        notedAt: [String: Date] = [:],
        payloadSourceURLs: [String: String] = [:],
        payloadRequests: [String: String] = [:],
         
        acquiredAt: [String: Date] = [:],
        routeSetProviders: Set<String> = [],
        coreRouteSeeds: Set<String> = [],
        seedPaths: [String: String] = [:],
         
        userAgent: String? = nil
    ) -> ProviderCatalog {
        let entries = plan.providers.map {
            Entry(
                name: $0.name,
                kind: $0.kind,
                url: $0.url,
                path: $0.path,
                count: entryCounts[$0.name],
                subscriptionInfo: subscriptionInfo[$0.name],
                updateIntervalSeconds: $0.updateIntervalSeconds,
                lastUpdatedAt: lastUpdatedAt[$0.name],
                note: notes[$0.name],
                 
                 
                 
                 
                payloadURL: payloadSourceURLs[$0.path],
                payloadRequest: payloadRequests[$0.path],
                acquiredAt: acquiredAt[$0.path],
                requestFingerprint: requestFingerprint(of: $0),
                notedAt: notedAt[$0.name]
            )
        }
        return ProviderCatalog(
            entries: entries,
            routeSetProviders: Set(plan.providers.filter {
                $0.kind == "rule" && $0.behavior.lowercased() == "ipcidr"
                    && routeSetProviders.contains($0.name)
            }.map(\.name)),
            coreFetchedProviders: Set(plan.providers.filter {
                ProviderFetchedByCore.applies(toProxy: $0.proxy)
            }.map(\.name)),
            coreRouteSeeds: coreRouteSeeds.isEmpty ? nil : coreRouteSeeds,
            unusableProxyProviders: {
                let found = unusableProxyProviders(in: plan)
                return found.isEmpty ? nil : found
            }(),
            seedPaths: seedPaths.isEmpty ? nil : seedPaths,
            userAgent: userAgent)
    }
}


extension ProviderCatalog.Entry {
    private enum CodingKeys: String, CodingKey {
        case name, kind, url, path, count, subscriptionInfo, updateIntervalSeconds, lastUpdatedAt
        case note, payloadURL, payloadRequest, acquiredAt, requestFingerprint, notedAt
         
         
        case loadFailure
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try container.decode(String.self, forKey: .name),
            kind: try container.decode(String.self, forKey: .kind),
            url: try container.decode(String.self, forKey: .url),
            path: try container.decode(String.self, forKey: .path),
            count: try container.decodeIfPresent(Int.self, forKey: .count),
            subscriptionInfo: try container.decodeIfPresent(SubscriptionInfo.self, forKey: .subscriptionInfo),
            updateIntervalSeconds: try container.decodeIfPresent(Int64.self, forKey: .updateIntervalSeconds),
            lastUpdatedAt: try container.decodeIfPresent(Date.self, forKey: .lastUpdatedAt),
            loadFailure: try container.decodeIfPresent(String.self, forKey: .loadFailure),
            note: try container.decodeIfPresent(ProviderNote.self, forKey: .note),
            payloadURL: try container.decodeIfPresent(String.self, forKey: .payloadURL),
            payloadRequest: try container.decodeIfPresent(String.self, forKey: .payloadRequest),
            acquiredAt: try container.decodeIfPresent(Date.self, forKey: .acquiredAt),
            requestFingerprint: try container.decodeIfPresent(String.self, forKey: .requestFingerprint),
            notedAt: try container.decodeIfPresent(Date.self, forKey: .notedAt)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
        try container.encode(url, forKey: .url)
        try container.encode(path, forKey: .path)
        try container.encodeIfPresent(count, forKey: .count)
        try container.encodeIfPresent(subscriptionInfo, forKey: .subscriptionInfo)
        try container.encodeIfPresent(updateIntervalSeconds, forKey: .updateIntervalSeconds)
        try container.encodeIfPresent(lastUpdatedAt, forKey: .lastUpdatedAt)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeIfPresent(payloadURL, forKey: .payloadURL)
        try container.encodeIfPresent(payloadRequest, forKey: .payloadRequest)
        try container.encodeIfPresent(acquiredAt, forKey: .acquiredAt)
        try container.encodeIfPresent(requestFingerprint, forKey: .requestFingerprint)
        try container.encodeIfPresent(notedAt, forKey: .notedAt)
    }
}
