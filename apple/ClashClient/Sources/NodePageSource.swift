import Clash
import ClashClientKit
import Foundation

 
 
 
 
protocol NodePageSource: AnyObject {
    func summary() async throws -> NodeSummary
    func groupMembers(_ group: String, offset: Int, limit: Int) async throws -> GroupMembersPage
    func providerNodes(_ provider: String, offset: Int, limit: Int) async throws -> ProviderNodesPage
    func proxiesPage(after: String, limit: Int) async throws -> ProxiesPage
    func search(_ query: String, offset: Int, limit: Int) async throws -> ProxySearchPage
     
    func searchGroupMembers(_ group: String, query: String, offset: Int, limit: Int) async throws -> GroupMembersPage
     
    func lookup(_ name: String) async throws -> ProxyLookup
}

 
 
enum NodePageSourceError: Error, Equatable {
    case unavailable
    case closed
}

 
 
 
 
 
 
 
final class OfflineNodeCatalog: NodePageSource, @unchecked Sendable {
     
     
     
    let serial: UInt64 = OfflineNodeCatalog.nextSerial()
    private static let serialLock = NSLock()
    nonisolated(unsafe) private static var lastSerial: UInt64 = 0
    private static func nextSerial() -> UInt64 {
        serialLock.lock(); defer { serialLock.unlock() }
        lastSerial &+= 1
        return lastSerial
    }

     
     
    private var catalog: ClashNodeCatalog?
     
     
     
    private let markLock = NSLock()
    private var marked = false
    private var isMarkedClosed: Bool { markLock.withLock { marked } }

    init(_ catalog: ClashNodeCatalog) {
        self.catalog = catalog
    }

     
     
    func withCatalog<T>(_ body: (ClashNodeCatalog) throws -> T) throws -> T {
        try AppCore.exclusive {
            guard !isMarkedClosed, let catalog else { throw NodePageSourceError.closed }
            return try body(catalog)
        }
    }

     
     
    static func open(configuration: String, resourceMapJSON: String, selectionsJSON: String) async throws -> OfflineNodeCatalog {
        try await Task.detached(priority: .userInitiated) {
            var error: NSError?
            guard let catalog = AppCore.openNodeCatalog(configuration, resourceMapJSON, selectionsJSON, &error) else {
                throw error ?? NodePageSourceError.unavailable
            }
            return OfflineNodeCatalog(catalog)
        }.value
    }

    func close() {
        AppCore.exclusive {
            catalog?.close()
            catalog = nil
        }
    }

     
     
     
     
    func closeLater() {
        markLock.withLock { marked = true }
        Self.closeQueue.async { self.close() }
    }

    private static let closeQueue = DispatchQueue(label: "network.clash.node-catalog.close", qos: .utility)

    deinit {
        catalog?.close()
    }

    func summary() async throws -> NodeSummary {
        try await read { $0.summaryJSON() }.decoded(NodeSummary.self)
    }

    func groupMembers(_ group: String, offset: Int, limit: Int) async throws -> GroupMembersPage {
        try await read { $0.groupMembersJSON(group, offset: Int32(clamping: offset), limit: Int32(clamping: limit)) }
            .decoded(GroupMembersPage.self)
    }

    func providerNodes(_ provider: String, offset: Int, limit: Int) async throws -> ProviderNodesPage {
        try await read { $0.providerNodesJSON(provider, offset: Int32(clamping: offset), limit: Int32(clamping: limit)) }
            .decoded(ProviderNodesPage.self)
    }

    func proxiesPage(after: String, limit: Int) async throws -> ProxiesPage {
        try await read { $0.proxiesPageJSON(after, limit: Int32(clamping: limit)) }.decoded(ProxiesPage.self)
    }

    func search(_ query: String, offset: Int, limit: Int) async throws -> ProxySearchPage {
        try await read { $0.searchJSON(query, offset: Int32(clamping: offset), limit: Int32(clamping: limit)) }
            .decoded(ProxySearchPage.self)
    }

    func searchGroupMembers(_ group: String, query: String, offset: Int, limit: Int) async throws -> GroupMembersPage {
        try await read {
            $0.searchGroupMembersJSON(group, query: query, offset: Int32(clamping: offset), limit: Int32(clamping: limit))
        }.decoded(GroupMembersPage.self)
    }

    func lookup(_ name: String) async throws -> ProxyLookup {
        try await read { $0.lookupJSON(name) }.decoded(ProxyLookup.self)
    }

    private func read(_ body: @escaping @Sendable (ClashNodeCatalog) -> String) async throws -> Data {
        try await Task.detached(priority: .userInitiated) { [self] in
            try AppCore.exclusive {
                guard !self.isMarkedClosed, let catalog else { throw NodePageSourceError.closed }
                return Data(body(catalog).utf8)
            }
        }.value
    }
}

extension Data {
     
    func decoded<Page: Decodable>(_: Page.Type) throws -> Page {
        if let refusal = NodePageRefusal.of(self) { throw refusal }
        return try JSONDecoder().decode(Page.self, from: self)
    }
}

 
 
 
 
 
 
 
 
 
enum CompactProxiesDocument {
    struct Built {
        let data: Data
        let summary: NodeSummary
    }

     
     
     
     
    static let changedWhileRead = "node-list-changed-while-read"

    static func build(from source: NodePageSource, firstMembers: Int = NodePaging.firstMembers) async throws -> Built {
        var attempt = 0
        while true {
            attempt += 1
            let summary = try await source.summary()
             
             
             
             
             
            async let tail = readGlobalTail(of: summary, from: source, firstMembers: firstMembers)
            let pages = try await firstPages(of: summary, from: source, limit: firstMembers)
            let globalTail = await tail
            let consistent = (Array(pages.values) + [globalTail].compactMap { $0 }).allSatisfy { page in
                page.revision == nil || summary.revision == nil || page.revision == summary.revision
            }
            if consistent {
                return Built(data: try document(summary: summary, pages: pages, globalTail: globalTail), summary: summary)
            }
             
             
            if attempt >= 2 {
                throw NodePageRefusal(message: Self.changedWhileRead)
            }
        }
    }

     
     
     
     
     
     
    private static func readGlobalTail(
        of summary: NodeSummary,
        from source: NodePageSource,
        firstMembers: Int
    ) async -> GroupMembersPage? {
        guard let span = summary.globalTailToRead(after: firstMembers) else { return nil }
        for attempt in 0..<2 {
            do {
                return try await source.groupMembers(NodeSummary.kernelGlobalName, offset: span.offset, limit: span.limit)
            } catch is NodePageRefusal {
                if attempt == 0 { try? await Task.sleep(nanoseconds: 300_000_000) }
            } catch {
                return nil
            }
        }
        return nil
    }

    private static func firstPages(
        of summary: NodeSummary,
        from source: NodePageSource,
        limit: Int
    ) async throws -> [String: GroupMembersPage] {
        let names = Array(summary.groups.keys)
        var pages: [String: GroupMembersPage] = [:]
         
         
        let width = 8
        var index = 0
        while index < names.count {
            let batch = names[index..<min(index + width, names.count)]
            try await withThrowingTaskGroup(of: (String, GroupMembersPage?).self) { group in
                for name in batch {
                    group.addTask {
                         
                         
                         
                        for attempt in 0..<2 {
                            do {
                                return (name, try await source.groupMembers(name, offset: 0, limit: limit))
                            } catch is NodePageRefusal {
                                if attempt == 0 { try? await Task.sleep(nanoseconds: 300_000_000) }
                            }
                        }
                        return (name, nil)
                    }
                }
                for try await (name, page) in group {
                    if let page { pages[name] = page }
                }
            }
            index += width
        }
        return pages
    }

     
     
     
     
     
    static func document(summary: NodeSummary, pages: [String: GroupMembersPage],
                         globalTail: GroupMembersPage? = nil) throws -> Data {
        var proxies: [String: Any] = [:]
        func addMember(_ member: NodeMember) {
            guard summary.groups[member.name] == nil, proxies[member.name] == nil else { return }
            var entry: [String: Any] = ["name": member.name, "type": member.type]
            if let placeholder = member.placeholderType { entry["placeholderType"] = placeholder }
            proxies[member.name] = entry
        }
        for (name, group) in summary.groups {
            var members = pages[name]?.members ?? []
             
             
             
             
             
             
             
            var carried: String?
            if let now = group.now, !members.contains(where: { $0.name == now }) {
                let selected = group.nowMember
                    ?? NodeMember(name: now, type: summary.groups[now]?.type ?? "", inline: true)
                members.append(selected)
                carried = selected.name
            }
            members.forEach(addMember)
            var entry: [String: Any] = [
                "name": name,
                "type": group.type,
                "all": members.map(\.name),
                "total": max(pages[name]?.total ?? group.total, group.total),
                "hidden": group.hidden,
            ]
            if let now = group.now { entry["now"] = now }
            if let carried { entry["outOfPlace"] = [carried] }
             
             
             
             
            if name == NodeSummary.kernelGlobalName, summary.globalListsEveryGroup(tail: globalTail) {
                entry["listsEveryGroup"] = true
            }
            if let fixed = group.fixed { entry["fixed"] = fixed }
            if let icon = group.icon { entry["icon"] = icon }
            if let url = group.testURL { entry["testUrl"] = url }
            if let fallback = group.emptyFallback { entry["emptyFallback"] = fallback }
            if let latest = group.latest {
                entry["history"] = [["delay": latest.delay ?? 0, "time": latest.time ?? ""]]
            }
            proxies[name] = entry
        }
        return try JSONSerialization.data(withJSONObject: ["proxies": proxies])
    }
}

extension CompactProxiesDocument {
     
     
     
     
    static func offlineCatalogAnswer(_ catalog: OfflineNodeCatalog, firstMembers: Int = NodePaging.firstMembers) throws -> Data {
        let summary = try catalog.withCatalog { Data($0.summaryJSON().utf8) }.decoded(NodeSummary.self)
        var pages: [String: GroupMembersPage] = [:]
        for name in summary.groups.keys {
            let data = try catalog.withCatalog {
                Data($0.groupMembersJSON(name, offset: 0, limit: Int32(clamping: firstMembers)).utf8)
            }
            if let page = try? data.decoded(GroupMembersPage.self) { pages[name] = page }
        }
        var globalTail: GroupMembersPage?
        if let span = summary.globalTailToRead(after: firstMembers) {
            globalTail = try? catalog.withCatalog {
                Data($0.groupMembersJSON(NodeSummary.kernelGlobalName, offset: Int32(clamping: span.offset),
                                         limit: Int32(clamping: span.limit)).utf8)
            }.decoded(GroupMembersPage.self)
        }
        let proxies = try document(summary: summary, pages: pages, globalTail: globalTail)
        guard var root = try JSONSerialization.jsonObject(with: proxies) as? [String: Any] else {
            throw NodePageSourceError.unavailable
        }
        var providers: [String: Any] = [:]
        for (name, provider) in summary.providers {
            var entry: [String: Any] = ["name": provider.name, "total": provider.total, "proxies": [Any]()]
            if let type = provider.type { entry["type"] = type }
            if let vehicle = provider.vehicleType { entry["vehicleType"] = vehicle }
            if let updated = provider.updatedAt { entry["updatedAt"] = updated }
            if let dead = provider.dead { entry["dead"] = dead }
            if let alive = provider.alive { entry["alive"] = alive }
            if let url = provider.testURL { entry["testUrl"] = url }
            providers[name] = entry
        }
        root["providers"] = providers
        root["providerErrors"] = summary.providerErrors
        return try JSONSerialization.data(withJSONObject: root)
    }
}

 
 
 
 
 
 
 
 
 
enum OfflineNodeCatalogRegistry {
    struct Holder: Hashable, Sendable {
        let id: String
         
        static let nodesPage = Holder(id: "nodes-page")
    }

    private struct Entry {
        let catalog: OfflineNodeCatalog
        var holders: Set<Holder>
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var entries: [String: Entry] = [:]
    nonisolated(unsafe) private static var holdings: [Holder: String] = [:]

     
     
     
     
    static func take(
        _ fingerprint: String,
        for holder: Holder,
        open: () throws -> OfflineNodeCatalog
    ) throws -> OfflineNodeCatalog {
        var closing: [OfflineNodeCatalog] = []
        if let shared = lock.withLock({ attach(fingerprint, to: holder, closing: &closing) }) {
            closing.forEach { $0.close() }
            return shared
        }
        let opened = try open()
        let catalog = lock.withLock { () -> OfflineNodeCatalog in
            if let shared = attach(fingerprint, to: holder, closing: &closing) {
                closing.append(opened)
                return shared
            }
            entries[fingerprint] = Entry(catalog: opened, holders: [holder])
            holdings[holder] = fingerprint
            return opened
        }
        closing.forEach { $0.close() }
        return catalog
    }

     
    static func held(by holder: Holder) -> OfflineNodeCatalog? {
        lock.withLock { holdings[holder].flatMap { entries[$0]?.catalog } }
    }

     
    static func isHeld(_ fingerprint: String, by holder: Holder) -> Bool {
        lock.withLock { holdings[holder] == fingerprint }
    }

     
    static var current: OfflineNodeCatalog? { held(by: .nodesPage) }

     
    static func release(_ holder: Holder) {
        var closing: [OfflineNodeCatalog] = []
        lock.withLock { detach(holder, closing: &closing) }
        closing.forEach { $0.closeLater() }
    }

     
    static func closeAll() {
        let all = lock.withLock { () -> [OfflineNodeCatalog] in
            let open = entries.values.map(\.catalog)
            entries = [:]
            holdings = [:]
            return open
        }
        all.forEach { $0.close() }
    }

     
    static var openCount: Int { lock.withLock { entries.count } }

     
     
    static func isOpen(_ fingerprint: String) -> Bool { lock.withLock { entries[fingerprint] != nil } }

     
    private static func attach(_ fingerprint: String, to holder: Holder, closing: inout [OfflineNodeCatalog]) -> OfflineNodeCatalog? {
        if holdings[holder] != fingerprint { detach(holder, closing: &closing) }
        guard var entry = entries[fingerprint] else { return nil }
        entry.holders.insert(holder)
        entries[fingerprint] = entry
        holdings[holder] = fingerprint
        return entry.catalog
    }

     
    private static func detach(_ holder: Holder, closing: inout [OfflineNodeCatalog]) {
        guard let fingerprint = holdings.removeValue(forKey: holder), var entry = entries[fingerprint] else { return }
        entry.holders.remove(holder)
        if entry.holders.isEmpty {
            entries.removeValue(forKey: fingerprint)
            closing.append(entry.catalog)
        } else {
            entries[fingerprint] = entry
        }
    }
}
