import Foundation
import ClashClientKit

public struct ClashProxiesDisplayPreferences:
    Codable,
    Equatable,
    Sendable
{
    public enum Style: String, CaseIterable, Codable, Sendable {
        case list
        case tabs
    }

    public enum Sort: String, CaseIterable, Codable, Sendable {
        case standard
        case delay
        case name
    }

    public enum Layout: String, CaseIterable, Codable, Sendable {
        case loose
        case compact
    }

    public enum Size: String, CaseIterable, Codable, Sendable {
        case standard
        case compact
        case minimal
    }

    public var style: Style
    public var sort: Sort
    public var layout: Layout
    public var size: Size
     
     
     
     
     
     
     
     
     
     
     
     
    public var groupIconImages: Bool

    public init(
        style: Style = .list,
        sort: Sort = .standard,
        layout: Layout = .loose,
        size: Size = .standard,
        groupIconImages: Bool = false
    ) {
        self.style = style
        self.sort = sort
        self.layout = layout
        self.size = size
        self.groupIconImages = groupIconImages
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        style = try container.decodeIfPresent(Style.self, forKey: .style) ?? .list
        sort = try container.decodeIfPresent(Sort.self, forKey: .sort) ?? .standard
        layout = try container.decodeIfPresent(Layout.self, forKey: .layout) ?? .loose
        size = try container.decodeIfPresent(Size.self, forKey: .size) ?? .standard
        groupIconImages = try container.decodeIfPresent(
            Bool.self, forKey: .groupIconImages
        ) ?? false
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
public enum ClashLatencyKey {
    private static let separator: Character = "\u{1F}"

    public static func recordKey(_ name: String, url: String) -> String {
        "@" + tag(url) + tag(name) + String(separator) + name
    }

     
    public static func nodeName(ofRecordKey key: String) -> String? {
        guard key.first == "@", let index = key.firstIndex(of: separator),
              key.distance(from: key.startIndex, to: index) == 33 else { return nil }
        return String(key[key.index(after: index)...])
    }

     
     
    public static func reading<Value>(_ key: String, in table: [String: Value]) -> Value? {
        if let value = table[key] { return value }
        return nodeName(ofRecordKey: key).flatMap { table[$0] }
    }

     
    public static func isTesting(_ key: String, in testing: Set<String>) -> Bool {
        isNamed(key, in: testing)
    }

     
     
    public static func isNamed(_ key: String, in names: Set<String>) -> Bool {
        names.contains(key) || nodeName(ofRecordKey: key).map(names.contains) == true
    }

    private static func tag(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }
}

public enum ClashProxyLatencyState: Codable, Equatable, Sendable {
    case untested
    case testing
    case measured(milliseconds: Int)
    case failed
    case timedOut

    var normalized: ClashProxyLatencyState {
        switch self {
        case .measured(let milliseconds):
            guard (1...3_600_000).contains(milliseconds) else {
                return milliseconds <= 0 ? .timedOut : .failed
            }
            return self
        case .untested, .testing, .failed, .timedOut:
            return self
        }
    }

     
     
     
     
    public var tier: ClashProxyLatencyTier? {
        guard case .measured(let milliseconds) = self else { return nil }
        if milliseconds < 800 { return .fast }
        if milliseconds < 1_600 { return .slow }
        return .slower
    }
}

 
 
public enum ClashProxyLatencyTier: Equatable, Sendable {
    case fast
    case slow
    case slower
}

 
 
 
 
 
 
 
public enum ClashProxyLatencyAffordance: Equatable, Sendable {
    case offersTest
    case inProgress
    case showsResultAndRetests

    public static func of(
        _ state: ClashProxyLatencyState
    ) -> ClashProxyLatencyAffordance {
        switch state {
        case .untested: .offersTest
        case .testing: .inProgress
         
         
        case .measured, .failed, .timedOut: .showsResultAndRetests
        }
    }
}

public struct ClashProxySnapshot:
    Codable,
    Equatable,
    Hashable,
    Identifiable,
    Sendable
{
    public var id: String { name }
    public let name: String
    public let type: String

    public init(name: String, type: String) {
         
         
         
         
         
         
        self.name = name
        self.type = Self.presentationText(type)
    }

    private static func presentationText(_ value: String) -> String {
        String(value.prefix(256))
    }
}

public struct ClashProxyMemberSnapshot:
    Codable,
    Equatable,
    Hashable,
    Identifiable,
    Sendable
{
    public var id: String { name }
    public let name: String
    public let type: String
    public let isGroup: Bool
     
     
     
     
     
     
     
    public let chainedThrough: String?
     
     
     
     
    public let placeholderType: String?
     
     
     
     
     
    public let latencyKey: String

    public init(
        name: String,
        type: String,
        isGroup: Bool = false,
        chainedThrough: String? = nil,
        placeholderType: String? = nil,
        latencyKey: String? = nil
    ) {
         
         
         
         
         
         
        self.name = name
        self.type = String(type.prefix(256))
        self.isGroup = isGroup
        self.chainedThrough = chainedThrough.map { String($0.prefix(256)) }
        self.placeholderType = placeholderType.map { String($0.prefix(64)) }
        self.latencyKey = latencyKey ?? name
    }

    private enum CodingKeys: String, CodingKey {
        case name, type, isGroup, chainedThrough, placeholderType, latencyKey
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(String.self, forKey: .type)
        isGroup = try container.decodeIfPresent(Bool.self, forKey: .isGroup) ?? false
        chainedThrough = try container.decodeIfPresent(String.self, forKey: .chainedThrough)
        placeholderType = try container.decodeIfPresent(String.self, forKey: .placeholderType)
         
        latencyKey = try container.decodeIfPresent(String.self, forKey: .latencyKey) ?? name
    }
}

public struct ClashProxyGroupSnapshot:
    Codable,
    Equatable,
    Hashable,
    Identifiable,
    Sendable
{
    public var id: String { name }
    public let name: String
    public let type: String
    public let members: [ClashProxyMemberSnapshot]
    public let configuredSelection: String?
    public let runtimeSelection: String?
    public let resolvedRuntimeRoute: String?
     
     
    public let icon: String?
     
     
     
     
    public let emptyFallback: String?
     
     
     
    public var emptyNote: String? = nil
     
     
     
    public let memberTotal: Int?
     
     
     
    public var carriedSelection: String? = nil
     
     
    public var carriesSelection: Bool { carriedSelection != nil && !hasEveryMember }

    public init(
        name: String,
        type: String,
        members: [ClashProxyMemberSnapshot],
        configuredSelection: String? = nil,
        runtimeSelection: String? = nil,
        resolvedRuntimeRoute: String? = nil,
        icon: String? = nil,
        emptyFallback: String? = nil,
        memberTotal: Int? = nil
    ) {
        let partial = memberTotal.map { $0 > members.count } ?? false
        self.memberTotal = partial ? memberTotal : nil
        self.emptyFallback = emptyFallback.flatMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
         
         
         
         
         
         
        self.name = name
        self.type = String(type.prefix(256))
        self.members = members
         
         
        self.configuredSelection = Self.normalizedSelection(
            configuredSelection,
            members: members,
            partial: partial
        )
        self.runtimeSelection = Self.normalizedSelection(
            runtimeSelection,
            members: members,
            partial: partial
        )
        self.resolvedRuntimeRoute = Self.nonemptyPresentationText(
            resolvedRuntimeRoute
        )
         
         
         
         
         
        let trimmedIcon = icon?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.icon = (trimmedIcon?.isEmpty ?? true) ? nil : trimmedIcon
    }

    public var currentSelection: String? {
        runtimeSelection ?? configuredSelection
    }

     
     
     
     
     
     
     
    public var isEmpty: Bool {
        guard let emptyFallback, hasEveryMember else { return false }
        return members.map(\.name) == [emptyFallback]
    }

     
    public var memberCount: Int { memberTotal ?? members.count }

     
    public var hasEveryMember: Bool { memberTotal == nil }

     
     
     
    public func membership(of name: String) -> GroupMembership {
        GroupMembership.judged(
            held: members.contains { $0.name == name },
            holdsEveryMember: hasEveryMember,
            listsEveryGroup: false,
            isOtherGroup: false
        )
    }

    private var normalizedType: String {
        type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var isManual: Bool {
        normalizedType == "select" || normalizedType == "selector"
    }

     
     
     
     
     
     
     
    public var allowsMemberChoice: Bool {
        isManual || canBeUnpinned
    }

     
     
     
     
     
     
     
     
     
    public var memberChoiceRefusal: String? {
        guard !allowsMemberChoice else { return nil }
        if normalizedType == "relay" {
            return "A relay sends traffic through its members in order, so there is no one member to choose."
        }
        if normalizedType == "load-balance" || normalizedType == "loadbalance" {
            return "A load-balance group spreads connections across its members, so it has no single route to pin."
        }
        return "This group picks its own member."
    }

     
     
     
    public var canBeUnpinned: Bool {
         
         
         
         
         
        ["url-test", "urltest", "fallback"].contains(normalizedType)
    }

     
     
     
     
     
     
    public var allowsOfflineConfiguredRoute: Bool {
        isManual || configuredSelection != nil
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private static func normalizedSelection(
        _ value: String?,
        members: [ClashProxyMemberSnapshot],
        partial: Bool = false
    ) -> String? {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              partial || members.contains(where: { $0.name == value }) else {
            return nil
        }
        return value
    }

    private static func nonemptyPresentationText(
        _ value: String?
    ) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(256))
    }
}

public struct ClashProxyProviderSnapshot:
    Codable,
    Equatable,
    Hashable,
    Identifiable,
    Sendable
{
    public var id: String { name }
     
    public let name: String
     
     
    public let displayName: String?
    public var title: String { displayName ?? name }
    public let type: String
    public let nodeCount: Int?
     
     
     
     
     
     
     
     
    public let nodes: [ClashProxyMemberSnapshot]?

     
     
     
     
     
     
     
     
     
     
     
     
     
    public let loadFailure: String?
     
     
     
     
    public let note: String?

     
     
     
    public var isUpdatable: Bool { type.lowercased() == "http" }

    public init(
        name: String,
        displayName: String? = nil,
        type: String,
        nodeCount: Int? = nil,
        nodes: [ClashProxyMemberSnapshot]? = nil,
        loadFailure: String? = nil,
        note: String? = nil
    ) {
         
         
         
         
         
         
        self.name = name
        self.displayName = displayName
        self.type = String(type.prefix(256))
        self.nodeCount = nodeCount.map { max(0, $0) }
        self.nodes = nodes
        self.loadFailure = loadFailure.flatMap {
            $0.isEmpty ? nil : String($0.prefix(2048))
        }
        self.note = note.flatMap { $0.isEmpty ? nil : String($0.prefix(2048)) }
    }
}

public enum ClashProxiesCatalogState:
    Codable,
    Equatable,
    Sendable
{
    case disconnected
    case loading
    case ready
    case failed(message: String)
}

 
 
 
 
 
public struct ClashProxiesSnapshot: Codable, Equatable, Sendable {
    public let groups: [ClashProxyGroupSnapshot]
     
     
     
     
     
    public let hiddenGroups: [ClashProxyGroupSnapshot]
    public let searchableProxies: [ClashProxySnapshot]
    public let providers: [ClashProxyProviderSnapshot]
    public let ungrouped: [ClashProxySnapshot]
     
     
     
     
     
     
     
    public let browsingSuppressedByDirectMode: Bool
    public let latencyByName: [String: ClashProxyLatencyState]
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    public let failureCategories: [String: String]
    public let isConnected: Bool
    public let isTestingLatency: Bool
    public let latencyCompletedCount: Int
    public let latencyTotalCount: Int
    public let initiallyExpandedGroup: String?
     
     
     
    public let rememberedExpandedGroups: Set<String>
     
     
     
    public var rememberedOpenGroup: String? = nil
     
     
     
     
    public var readerFoldedAll: Bool? = nil
     
     
     
     
     
     
    public var liveCatalog: Bool? = nil
    public let displayPreferences: ClashProxiesDisplayPreferences
     
     
    public let catalogState: ClashProxiesCatalogState?
     
     
    public let canRefreshCatalog: Bool?
     
     
     
     
     
     
     
     
    public let canUnpinGroups: Bool?

     
     
     
     
     
     
     
     
     
    public let actionRefusals: [String: ClashGroupActionRefusal]

     
     
     
     
     
     
     
     
     
    public let editableMembers: Set<String>

     
     
     
    public var nodeScripts: [ClashProxyNodeScript]? = nil

     
    public var scriptsForNodes: [ClashProxyNodeScript] { nodeScripts ?? [] }

     
    public func canEdit(_ member: ClashProxyMemberSnapshot) -> Bool {
        !member.isGroup && editableMembers.contains(member.name)
    }

     
    public func offersUnpin(for group: ClashProxyGroupSnapshot) -> Bool {
        guard canUnpinGroups == true else { return false }
         
         
         
         
        return group.canBeUnpinned && group.configuredSelection != nil
    }

    public init(
        groups: [ClashProxyGroupSnapshot] = [],
        hiddenGroups: [ClashProxyGroupSnapshot] = [],
        searchableProxies: [ClashProxySnapshot] = [],
        providers: [ClashProxyProviderSnapshot] = [],
        ungrouped: [ClashProxySnapshot] = [],
        browsingSuppressedByDirectMode: Bool = false,
        latencyByName: [String: ClashProxyLatencyState] = [:],
        failureCategories: [String: String] = [:],
        isConnected: Bool = false,
        isTestingLatency: Bool = false,
        latencyCompletedCount: Int = 0,
        latencyTotalCount: Int = 0,
        initiallyExpandedGroup: String? = nil,
        rememberedExpandedGroups: Set<String> = [],
        displayPreferences: ClashProxiesDisplayPreferences = .init(),
        catalogState: ClashProxiesCatalogState? = nil,
        canRefreshCatalog: Bool? = nil,
        canUnpinGroups: Bool? = nil,
        actionRefusals: [String: ClashGroupActionRefusal] = [:],
        editableMembers: Set<String> = [],
        rememberedOpenGroup: String? = nil,
        readerFoldedAll: Bool? = nil,
        liveCatalog: Bool? = nil,
        nodeScripts: [ClashProxyNodeScript] = []
    ) {
        self.liveCatalog = liveCatalog
        self.nodeScripts = nodeScripts.isEmpty ? nil : nodeScripts
        self.groups = groups
        self.hiddenGroups = hiddenGroups
        self.searchableProxies = searchableProxies
        self.providers = providers
        self.ungrouped = ungrouped
        self.browsingSuppressedByDirectMode = browsingSuppressedByDirectMode
         
         
         
        self.latencyByName = latencyByName.mapValues(\.normalized)
        self.failureCategories = failureCategories
        self.isConnected = isConnected
        self.isTestingLatency = isTestingLatency
        let total = max(0, latencyTotalCount)
        self.latencyTotalCount = total
        self.latencyCompletedCount = min(
            max(0, latencyCompletedCount),
            total
        )
        self.initiallyExpandedGroup = initiallyExpandedGroup.flatMap { name in
             
            groups.contains(where: { $0.name == name }) ? name : nil
        }
         
         
        let declared = Set(groups.map(\.name))
        self.rememberedExpandedGroups =
            rememberedExpandedGroups.intersection(declared)
        self.rememberedOpenGroup = rememberedOpenGroup.flatMap { declared.contains($0) ? $0 : nil }
        self.readerFoldedAll = readerFoldedAll
        self.displayPreferences = displayPreferences
        self.catalogState = catalogState.map {
            switch $0 {
            case .failed(let message):
                return .failed(
                    message: String(message.prefix(512))
                )
            case .disconnected:
                return .disconnected
            case .loading:
                return .loading
            case .ready:
                return .ready
            }
        }
        self.canRefreshCatalog = canRefreshCatalog
        self.canUnpinGroups = canUnpinGroups
        self.actionRefusals = actionRefusals
        self.editableMembers = editableMembers
    }

    public static let empty = ClashProxiesSnapshot()

    public var effectiveCatalogState: ClashProxiesCatalogState {
        catalogState ?? .ready
    }

    public func group(named name: String) -> ClashProxyGroupSnapshot? {
        groups.first { $0.name == name } ?? hiddenGroups.first { $0.name == name }
    }

    public func latency(for name: String) -> ClashProxyLatencyState {
         
        ClashLatencyKey.reading(name, in: latencyByName) ?? .untested
    }

    public func members(
        in group: ClashProxyGroupSnapshot,
        sortedBy sort: ClashProxiesDisplayPreferences.Sort
    ) -> [ClashProxyMemberSnapshot] {
        sort.ordered(group.members, name: \.name, latency: displayedLatency(for:))
    }

     
     
     
     
     
     
     
     
     
    public func groups(matching query: String) -> [ClashProxyGroupSnapshot] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return groups }
        return groups.compactMap { group in
            let members = group.members.filter {
                $0.name.localizedCaseInsensitiveContains(needle)
            }
            guard !members.isEmpty else { return nil }
            return ClashProxyGroupSnapshot(
                name: group.name,
                type: group.type,
                members: members,
                configuredSelection: group.configuredSelection,
                runtimeSelection: group.runtimeSelection,
                resolvedRuntimeRoute: group.resolvedRuntimeRoute,
                 
                 
                 
                icon: group.icon
            )
        }
    }

     
     
     
    public func ungroupedNodes(matching query: String) -> [ClashProxySnapshot] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return ungrouped }
        return ungrouped.filter {
            $0.name.localizedCaseInsensitiveContains(needle)
        }
    }

     
     
     
    public func shownMembers(matching query: String) -> [ClashProxiesShownMembers] {
        var shown = groups(matching: query).map {
            ClashProxiesShownMembers(group: $0.name, members: $0.members.map(\.name))
        }
        let loose = ungroupedNodes(matching: query).map(\.name)
        if !loose.isEmpty { shown.append(ClashProxiesShownMembers(group: "", members: loose)) }
        return shown
    }

     
     
    public func showsOnlyUngroupedNodes(matching query: String) -> Bool {
        !browsingSuppressedByDirectMode
            && groups(matching: query).isEmpty
            && !ungroupedNodes(matching: query).isEmpty
    }

     
     
     
    public func resolvedDisplayRoute(
        for member: ClashProxyMemberSnapshot
    ) -> String? {
        guard member.isGroup, let group = group(named: member.name) else {
            return member.name
        }
         
         
        guard !group.isEmpty else { return nil }
        if isConnected {
            return group.resolvedRuntimeRoute ?? group.runtimeSelection
        }
        guard group.allowsOfflineConfiguredRoute else { return nil }
        return resolvedConfiguredRoute(forGroupNamed: group.name)
    }

     
     
     
     
    public func displayedLatency(
        for member: ClashProxyMemberSnapshot
    ) -> ClashProxyLatencyState {
         
         
        if isEmptyGroup(member) { return .untested }
        let direct = latency(for: member.latencyKey)
        guard let route = resolvedDisplayRoute(for: member) else { return direct }
         
         
        let routeKey = member.isGroup ? terminalLatencyKey(from: member.name, route: route) : route
        let routed = latency(for: routeKey)
         
         
         
         
         
         
         
         
         
         
         
        if member.isGroup { return routed }
        return direct == .untested ? routed : direct
    }

     
     
     
     
    public func terminalLatencyKey(from groupName: String, route: String) -> String {
         
         
         
         
        guard var current = group(named: groupName) else { return route }
        var visited: Set<String> = [current.name]
        while let next = current.runtimeSelection ?? current.configuredSelection,
              let inner = group(named: next), visited.insert(inner.name).inserted {
            current = inner
        }
        return current.members.first { $0.name == route && !$0.isGroup }?.latencyKey ?? route
    }

     
     
     
    public func isEmptyGroup(_ member: ClashProxyMemberSnapshot) -> Bool {
        member.isGroup && group(named: member.name)?.isEmpty == true
    }

     
     
     
     
    public func displayedLatency(
        forGroup group: ClashProxyGroupSnapshot
    ) -> ClashProxyLatencyState {
        displayedLatency(for: ClashProxyMemberSnapshot(name: group.name, type: group.type, isGroup: true))
    }

    public func resolvedConfiguredRoute(
        forGroupNamed name: String
    ) -> String? {
        let selections = Dictionary(
            (groups + hiddenGroups).compactMap { group in
                group.configuredSelection.map { (group.name, $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        return resolvedRoute(
            from: selections[name],
            selectionsByGroup: selections
        )
    }

    private func resolvedRoute(
        from initial: String?,
        selectionsByGroup: [String: String]
    ) -> String? {
        guard var current = initial, !current.isEmpty else { return nil }
        var visited = Set<String>()
        while group(named: current) != nil {
            guard visited.insert(current).inserted,
                  let next = selectionsByGroup[current],
                  !next.isEmpty else {
                return nil
            }
            current = next
        }
        return current
    }
}

extension ClashProxiesDisplayPreferences.Sort {
     
     
     
     
     
     
     
     
     
    public func ordered<Member>(
        _ members: [Member],
        name: (Member) -> String,
        latency: (Member) -> ClashProxyLatencyState
    ) -> [Member] {
        switch self {
        case .standard:
            return members
        case .name:
            return members.enumerated().sorted {
                let comparison = name($0.element).localizedStandardCompare(name($1.element))
                return comparison == .orderedSame
                    ? $0.offset < $1.offset
                    : comparison == .orderedAscending
            }.map(\.element)
        case .delay:
            return members.enumerated()
                .map { (key: Self.delayKey(latency($0.element), offset: $0.offset), member: $0.element) }
                .sorted { $0.key < $1.key }
                .map(\.member)
        }
    }

    private static func delayKey(
        _ latency: ClashProxyLatencyState,
        offset: Int
    ) -> (Int, Int, Int) {
        switch latency {
        case .measured(let milliseconds):
            return (0, milliseconds, offset)
        case .testing:
            return (1, 0, offset)
        case .untested:
            return (2, 0, offset)
        case .failed:
            return (3, 0, offset)
        case .timedOut:
            return (4, 0, offset)
        }
    }
}

 
 
public enum ClashProxyBrowsing {
     
     
     
    public static let kernelGlobalGroupName = "GLOBAL"

     
     
     
     
     
     
    public static func notOpenedUnasked(_ groups: [ClashProxyGroupSnapshot], liveCatalog: Bool) -> Set<String> {
        guard !liveCatalog, groups.contains(where: { $0.name == kernelGlobalGroupName }) else { return [] }
        return [kernelGlobalGroupName]
    }

     
     
    public static func defaultTab(_ tabs: [String], skipping: Set<String>) -> String? {
        tabs.first { !skipping.contains($0) } ?? tabs.first
    }
     
     
     
     
    public static let ungroupedKey = "\u{0}ungrouped"

     
     
     
     
     
    public static func inspects(_ member: ClashProxyMemberSnapshot) -> Bool {
        if member.isGroup { return false }
        if LatencyProbeNamePolicy.builtinNames.contains(
            member.name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        ) { return false }
         
         
         
        return !routeTypesWithoutABody.contains(
            member.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        )
    }

     
     
    private static let routeTypesWithoutABody: Set<String> = [
        "direct", "reject", "reject-drop", "pass", "compatible",
    ]

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    public static func groupAnchor(_ name: String) -> AnyHashable {
        "proxies.group.\(name)"
    }

     
     
    public static func memberAnchor(group: String, member: String) -> AnyHashable {
        "proxies.member.\(group)\u{1F}\(member)"
    }

     
     
    public static func locatableSelection(of group: ClashProxyGroupSnapshot) -> String? {
        guard !group.isEmpty, let now = group.currentSelection,
              group.members.contains(where: { $0.name == now }) else { return nil }
        return now
    }

     
     
     
     
     
     
     
     
    public static func groupToKeepOpen(
        visible: [String],
        expanded: Set<String>,
        lastOpened: String?,
        isSearching: Bool,
        readerFoldedAll: Bool = false,
        notAsFallback: Set<String> = []
    ) -> String? {
        guard !isSearching, !visible.isEmpty else { return nil }
        guard !visible.contains(where: expanded.contains) else { return nil }
         
         
         
        guard !readerFoldedAll else { return nil }
        if let lastOpened, visible.contains(lastOpened) { return lastOpened }
         
        return visible.first { !notAsFallback.contains($0) }
    }

    public static func columnCount(
        availableWidth: Double,
        layout: ClashProxiesDisplayPreferences.Layout
    ) -> Int {
        let readableCardWidth = 250.0
        let base = max(Int((availableWidth / readableCardWidth).rounded(.up)), 2)
        switch layout {
        case .loose: return max(base - 1, 1)
        case .compact: return base
        }
    }

     
     
     
     
     
    public static func groupsToOpenOnEntry(
        remembered: Set<String>,
        destination: String?
    ) -> Set<String> {
        if let destination { return [destination] }
        return remembered.count == 1 ? remembered : []
    }

    public static func showsMembers(
        of group: String,
        expanded: Set<String>,
        isSearching: Bool
    ) -> Bool {
        isSearching || expanded.contains(group)
    }
}

 
 
 
public struct ClashProxiesShownMembers: Codable, Equatable, Sendable {
    public let group: String
    public let members: [String]

    public init(group: String, members: [String]) {
        self.group = group
        self.members = members
    }
}

 
 
 
 
 
 
 
 
public struct ClashGroupActionRefusal: Codable, Hashable, Sendable {
    public enum RefusedVerb: String, Codable, Hashable, Sendable {
         
        case select
         
        case unfix
    }

    public let verb: RefusedVerb
     
    public let coreSentence: String?
     
    public let appSentence: ClashDisplayText?

    public init(verb: RefusedVerb, coreSentence: String?, appSentence: ClashDisplayText?) {
        self.verb = verb
        self.coreSentence = coreSentence
        self.appSentence = appSentence
    }

     
    public var result: ClashDisplayText {
        if let appSentence { return appSentence }
        switch verb {
        case .select: return "Couldn't switch to this node"
        case .unfix: return "Couldn't resume automatic selection"
        }
    }
}
